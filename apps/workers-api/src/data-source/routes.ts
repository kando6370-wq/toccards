import { Hono } from "hono";
import type { Env } from "../env";
import type {
  CardObjectType,
  CardSearchResult,
  DataSourceAdapter,
  PriceSeriesRequest,
  SetSearchResult,
} from "./adapter";
import {
  createCacheApiDataSourceAdapter,
  type DataSourceCache,
} from "./cache-api";
import { createKvCachedDataSourceAdapter } from "./kv-cache";
import { createLocalDbDataSourceAdapter } from "./local-db-adapter";
import { PriceQueryLimitError } from "./postgres-price-store";
import {
  ExchangeRateUnavailableError,
  loadUsdExchangeRates,
} from "./exchange-rates";
import { cardImageUrl, type CardImageVariant } from "../card-image-url";
import { authenticateOwner } from "../owner-auth";
import {
  LOCAL_PREMIUM_STATE_HEADER,
  resolvePremiumAccess,
} from "../entitlements/premium-access";

type DataSourceRoutesOptions = {
  createAdapter?: (env: Env) => DataSourceAdapter;
};

type CardOverrideRow = {
  card_ref: string;
  override_fields: string | null;
  image_url: string | null;
  is_missing_card: number;
};

export type CardResponse = CardSearchResult & {
  override_applied: boolean;
};

type PriceSeriesBatchRequest = PriceSeriesRequest;

const SELECT_CARD_OVERRIDE_SQL = `
SELECT card_ref, override_fields, image_url, is_missing_card
FROM card_override
WHERE card_ref = ?
LIMIT 1
`;

const VALIDATION_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Invalid request.",
  },
} as const;

const NOT_FOUND_RESPONSE = {
  success: false,
  error: {
    code: "NOT_FOUND",
    message: "Not found.",
  },
} as const;

const UNAUTHORIZED_RESPONSE = {
  success: false,
  error: { code: "UNAUTHORIZED", message: "Unauthorized." },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: { code: "INTERNAL_ERROR", message: "Internal server error." },
} as const;

const PREMIUM_REQUIRED_RESPONSE = {
  success: false,
  error: { code: "PREMIUM_REQUIRED", message: "Premium is required." },
} as const;

const ENTITLEMENT_SYNC_REQUIRED_RESPONSE = {
  success: false,
  error: {
    code: "ENTITLEMENT_SYNC_REQUIRED",
    message: "Premium access is still syncing.",
  },
} as const;

const SUPPORTED_CURRENCIES = new Set([
  "USD",
  "EUR",
  "JPY",
  "GBP",
  "CAD",
  "AUD",
  "NZD",
  "SGD",
]);

const SUPPORTED_OBJECT_TYPES = new Set<CardObjectType>([
  "tcg",
  "sports",
  "sealed",
  "other",
]);

const CARD_OVERRIDE_FIELDS = [
  "name",
  "set_name",
  "set_code",
  "card_number",
  "finish",
  "language",
  "object_type",
  "image_url",
  "rarity",
] as const;

export function createDataSourceRoutes(
  options: DataSourceRoutesOptions = {},
): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();
  const createAdapter = options.createAdapter ?? createDefaultAdapter;

  routes.get("/cards/search", async (c) => {
    const query = c.req.query("q")?.trim() ?? "";
    const game = nullableString(c.req.query("game")) ?? undefined;
    const setId = nullableString(c.req.query("set_id")) ?? undefined;
    const setCode = nullableString(c.req.query("set_code")) ?? undefined;

    if (!query && !game && !setId && !setCode) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const objectType = parseObjectType(c.req.query("object_type"));

    if (objectType === "invalid") {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const page = positiveIntegerOrDefault(c.req.query("page"), 1);
    const pageSize = positiveIntegerOrDefault(c.req.query("page_size"), 40, 100);
    const adapter = createAdapter(c.env);
    const items = await listOrEmpty(() =>
      adapter.searchCards(query, {
        object_type: "tcg",
        game,
        set_id: setId,
        set_code: setCode,
        page,
        page_size: pageSize,
      }),
    );

    const responseItems = items.map((item) =>
      withCardImageUrl(item, "list"),
    );

    return c.json({
      success: true,
      data: {
        items: responseItems,
        total: responseItems.length,
        page,
        page_size: pageSize,
      },
    });
  });

  routes.get("/games", async (c) => {
    const result = await c.env.DB.prepare(
      `SELECT CAST(game_id AS TEXT) AS id, name
       FROM games
       WHERE load = 1 AND trim(coalesce(name, '')) <> ''
       ORDER BY search_sort ASC, game_id ASC`,
    ).all<{ id: string; name: string }>();

    return c.json({ success: true, data: { items: result.results ?? [] } });
  });

  routes.get("/sets/search", async (c) => {
    const query = c.req.query("q")?.trim() ?? "";
    const game = nullableString(c.req.query("game")) ?? undefined;

    if (!query && !game) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const page = positiveIntegerOrDefault(c.req.query("page"), 1);
    const pageSize = positiveIntegerOrDefault(c.req.query("page_size"), 20, 1000);
    const adapter = createAdapter(c.env);
    const sets = await listOrEmpty(() =>
      adapter.searchSets(query, { game, page, page_size: pageSize }),
    );
    const items = sets.map(withCardSetImageUrl);

    return c.json({
      success: true,
      data: { items, total: items.length, page, page_size: pageSize },
    });
  });

  routes.get("/cards/trending", async (c) => {
    const page = positiveIntegerOrDefault(c.req.query("page"), 1);
    const pageSize = positiveIntegerOrDefault(c.req.query("page_size"), 10, 100);
    const adapter = createAdapter(c.env);
    const items = await adapter.getTrending({ page, page_size: pageSize });
    const overrides = await findCardOverrides(
      c.env.DB,
      items.map((item) => item.card_ref),
    );
    const overriddenItems = items.map((item) => {
      const card = applyCardOverride(
        item,
        overrides.get(item.card_ref) ?? null,
        item.card_ref,
      );

      return { ...(card ?? { ...item, override_applied: false }), pinned: false };
    });

    return c.json({
      success: true,
      data: {
        items: overriddenItems.map((item) =>
          withCardImageUrl(item, "list"),
        ),
      },
    });
  });

  routes.get("/cards/:card_ref/image", async (c) => {
    const cardRef = cardRefParam(c.req.param("card_ref"));
    const adapter = createAdapter(c.env);
    const card = await resolveCard(c.env.DB, adapter, cardRef);
    if (!card) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }
    return c.redirect(cardImageUrl(cardRef, "master"), 302);
  });

  routes.get("/cards/:card_ref/market-prices", async (c) => {
    c.header("Cache-Control", "no-store");
    const cardRef = cardRefParam(c.req.param("card_ref"));
    const adapter = createAdapter(c.env);
    const finish = nullableString(c.req.query("finish"));
    const language = nullableString(c.req.query("language"));
    const prices = await listOrEmpty(() =>
      adapter.getMarketPrices(cardRef, finish, language),
    );

    return c.json({
      success: true,
      data: {
        card_ref: cardRef,
        prices: prices.map((price) => ({
          ...price,
          ...(price.history
            ? { history: priceHistoryWithinDays(price.history, 90) }
            : {}),
          currency: "USD",
        })),
        updated_at: new Date().toISOString(),
      },
    });
  });

  routes.get("/cards/:card_ref/price-series", async (c) => {
    c.header("Cache-Control", "no-store");
    const cardRef = cardRefParam(c.req.param("card_ref"));
    const grader = c.req.query("grader")?.trim() || "Raw";
    const grade = nullableNumber(c.req.query("grade"));
    const condition = nullableString(c.req.query("condition"));
    const days = positiveIntegerOrDefault(c.req.query("days"), 30, 365);
    if (days > 90) {
      const denied = await extendedPriceHistoryDenial(
        c.env,
        c.req.header("Authorization"),
        c.req.header(LOCAL_PREMIUM_STATE_HEADER),
      );
      if (denied === "internal_error") return c.json(INTERNAL_ERROR_RESPONSE, 500);
      if (denied === "unauthorized") return c.json(UNAUTHORIZED_RESPONSE, 401);
      if (denied === "sync_required") {
        return c.json(ENTITLEMENT_SYNC_REQUIRED_RESPONSE, 409);
      }
      if (denied === "premium_required") {
        return c.json(PREMIUM_REQUIRED_RESPONSE, 403);
      }
    }
    const finish = nullableString(c.req.query("finish"));
    const adapter = createAdapter(c.env);
    const series = await listOrEmpty(() =>
      adapter.getPriceSeries(cardRef, grader, grade, condition, days, finish),
    );

    return c.json({
      success: true,
      data: {
        card_ref: cardRef,
        grader,
        grade,
        condition,
        ...(finish ? { finish } : {}),
        days,
        series,
      },
    });
  });

  routes.post("/cards/:card_ref/price-series/batch", async (c) => {
    c.header("Cache-Control", "no-store");
    const cardRef = cardRefParam(c.req.param("card_ref"));
    const body = await c.req.json<unknown>().catch(() => null);
    const requests = parsePriceSeriesBatch(body);
    if (!requests) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }
    if (requests.some((request) => request.days > 90)) {
      const denied = await extendedPriceHistoryDenial(
        c.env,
        c.req.header("Authorization"),
        c.req.header(LOCAL_PREMIUM_STATE_HEADER),
      );
      if (denied === "internal_error") return c.json(INTERNAL_ERROR_RESPONSE, 500);
      if (denied === "unauthorized") return c.json(UNAUTHORIZED_RESPONSE, 401);
      if (denied === "sync_required") {
        return c.json(ENTITLEMENT_SYNC_REQUIRED_RESPONSE, 409);
      }
      if (denied === "premium_required") {
        return c.json(PREMIUM_REQUIRED_RESPONSE, 403);
      }
    }
    const adapter = createAdapter(c.env);
    const series = adapter.getPriceSeriesBatch
      ? await adapter.getPriceSeriesBatch(cardRef, requests)
      : await loadPriceSeriesSequentially(adapter, cardRef, requests);
    const results = requests.map((request, index) => ({
      ...request,
      series: series[index] ?? [],
    }));

    return c.json({ success: true, data: { card_ref: cardRef, results } });
  });

  routes.get("/cards/:card_ref/sold-listings", async (c) => {
    c.header("Cache-Control", "no-store");
    const cardRef = cardRefParam(c.req.param("card_ref"));
    const adapter = createAdapter(c.env);
    const items = await listOrEmpty(() => adapter.getSoldListings(cardRef));

    return c.json({
      success: true,
      data: {
        items: items.map((item) => ({ ...item, currency: "USD" })),
      },
    });
  });

  routes.get("/cards/:card_ref", async (c) => {
    const cardRef = cardRefParam(c.req.param("card_ref"));
    const adapter = createAdapter(c.env);
    const card = await resolveCard(c.env.DB, adapter, cardRef);

    return card
      ? c.json({ success: true, data: withCardImageUrl(card, "detail") })
      : c.json(NOT_FOUND_RESPONSE, 404);
  });

  routes.get("/rates", async (c) => {
    const base = (c.req.query("base") ?? "USD").trim().toUpperCase();
    const targets = targetCurrencies(c.req.query("targets"));
    if (
      base !== "USD" ||
      targets.some((target) => !SUPPORTED_CURRENCIES.has(target))
    ) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }
    try {
      const snapshot = await loadUsdExchangeRates(c.env.CACHE_KV);
      const rates = Object.fromEntries(
        targets.map((target) => [target, snapshot.rates[target]]),
      );
      return c.json({
        success: true,
        data: {
          base,
          rates,
          updated_at: snapshot.updatedAt,
          stale: snapshot.stale,
        },
      });
    } catch (error) {
      if (error instanceof ExchangeRateUnavailableError) {
        return c.json(
          {
            success: false,
            error: {
              code: "UPSTREAM_ERROR",
              message: "Exchange rates are unavailable.",
            },
          },
          502,
        );
      }
      throw error;
    }
  });

  return routes;
}

async function loadPriceSeriesSequentially(
  adapter: DataSourceAdapter,
  cardRef: string,
  requests: PriceSeriesBatchRequest[],
): Promise<Array<Array<{ date: string; price: number }>>> {
  const results: Array<Array<{ date: string; price: number }>> = [];
  for (const request of requests) {
    results.push(await listOrEmpty(() => adapter.getPriceSeries(
      cardRef,
      request.grader,
      request.grade,
      request.condition,
      request.days,
      request.finish,
    )));
  }
  return results;
}

async function extendedPriceHistoryDenial(
  env: Env,
  authorization: string | undefined,
  localPremiumState: string | undefined,
): Promise<
  "allowed" | "unauthorized" | "internal_error" | "sync_required" | "premium_required"
> {
  const auth = await authenticateOwner(env, authorization);
  if (auth.status !== "ok") return auth.status;
  const access = await resolvePremiumAccess(
    env,
    auth.owner.session_id,
    localPremiumState,
  );
  if (access === "premium") return "allowed";
  return access === "sync_required" ? "sync_required" : "premium_required";
}

function priceHistoryWithinDays(
  points: { date: string; price: number }[],
  days: number,
): { date: string; price: number }[] {
  const sorted = [...points].sort((left, right) => left.date.localeCompare(right.date));
  const latest = sorted.at(-1);
  if (!latest) return [];
  const latestAt = Date.parse(latest.date);
  if (!Number.isFinite(latestAt)) return sorted;
  const cutoff = latestAt - days * 24 * 60 * 60 * 1000;
  return sorted.filter((point) => {
    const pointAt = Date.parse(point.date);
    return Number.isFinite(pointAt) && pointAt >= cutoff;
  });
}

export function createDefaultAdapter(env: Env): DataSourceAdapter {
  const kvCached = createKvCachedDataSourceAdapter(
    createLocalDbDataSourceAdapter(env.DB),
    env.CACHE_KV,
  );
  const defaultCache = runtimeDefaultCache();

  return defaultCache
    ? createCacheApiDataSourceAdapter(kvCached, defaultCache)
    : kvCached;
}

function runtimeDefaultCache(): DataSourceCache | null {
  const runtime = globalThis as unknown as {
    caches?: { default?: DataSourceCache };
  };

  return runtime.caches?.default ?? null;
}

async function listOrEmpty<T>(load: () => Promise<T[]>): Promise<T[]> {
  try {
    return await load();
  } catch (error) {
    if (error instanceof PriceQueryLimitError) throw error;
    console.error("Data source list request failed.", error);
    return [];
  }
}

async function findCardOverride(
  db: D1Database,
  cardRef: string,
): Promise<CardOverrideRow | null> {
  try {
    return await db
      .prepare(SELECT_CARD_OVERRIDE_SQL)
      .bind(cardRef)
      .first<CardOverrideRow>();
  } catch {
    return null;
  }
}

async function findCardOverrides(
  db: D1Database,
  cardRefs: string[],
): Promise<Map<string, CardOverrideRow>> {
  const overrides = new Map<string, CardOverrideRow>();
  if (cardRefs.length === 0) return overrides;

  try {
    const placeholders = cardRefs.map(() => "?").join(", ");
    const results = await db
      .prepare(
        `SELECT card_ref, override_fields, image_url, is_missing_card
FROM card_override
WHERE card_ref IN (${placeholders})`,
      )
      .bind(...cardRefs)
      .all<CardOverrideRow>();

    for (const override of results.results ?? []) {
      overrides.set(override.card_ref, override);
    }
  } catch {
    // Overrides are optional corrections; catalog data remains usable without them.
  }

  return overrides;
}

async function getCardOrNull(
  adapter: DataSourceAdapter,
  cardRef: string,
): Promise<CardSearchResult | null> {
  try {
    return await adapter.getCard(cardRef);
  } catch {
    return null;
  }
}

export async function resolveCard(
  db: D1Database,
  adapter: DataSourceAdapter,
  cardRef: string,
): Promise<CardResponse | null> {
  const override = await findCardOverride(db, cardRef);

  if (override?.is_missing_card === 1) {
    const overriddenCard = applyCardOverride(null, override, cardRef);

    if (overriddenCard) {
      return overriddenCard;
    }
  }

  const card = await getCardOrNull(adapter, cardRef);
  return applyCardOverride(card, override, cardRef);
}

export function withCardImageUrl<T extends CardSearchResult>(
  card: T,
  variant: CardImageVariant,
): T {
  return { ...card, image_url: cardImageUrl(card.card_ref, variant) };
}

function applyCardOverride(
  card: CardSearchResult | null,
  override: CardOverrideRow | null,
  cardRef: string,
): CardResponse | null {
  if (!override) {
    return card ? { ...card, override_applied: false } : null;
  }

  const fields = parseOverrideFields(override.override_fields);
  const baseCard =
    card ?? (override.is_missing_card === 1 ? cardFromOverride(cardRef, fields) : null);

  if (!baseCard) {
    return null;
  }

  return {
    ...baseCard,
    ...fields,
    card_ref: cardRef,
    image_url: override.image_url ?? fields.image_url ?? baseCard.image_url,
    override_applied: true,
  };
}

function parseOverrideFields(
  value: string | null,
): Partial<CardSearchResult> {
  if (!value) {
    return {};
  }

  try {
    const parsed = JSON.parse(value);

    if (!isRecord(parsed)) {
      return {};
    }

    const fields: Record<string, string | null> = {};

    for (const field of CARD_OVERRIDE_FIELDS) {
      const fieldValue = parsed[field];

      if (fieldValue === undefined) {
        continue;
      }

      if (field === "object_type") {
        if (
          typeof fieldValue === "string" &&
          SUPPORTED_OBJECT_TYPES.has(fieldValue as CardObjectType)
        ) {
          fields[field] = fieldValue;
        }

        continue;
      }

      if (typeof fieldValue === "string" || fieldValue === null) {
        fields[field] = fieldValue;
      }
    }

    return fields as Partial<CardSearchResult>;
  } catch {
    return {};
  }
}

function cardFromOverride(
  cardRef: string,
  fields: Partial<CardSearchResult>,
): CardSearchResult | null {
  const name = requiredStringField(fields.name);
  const setName = requiredStringField(fields.set_name);
  const setCode = requiredStringField(fields.set_code);
  const cardNumber = requiredStringField(fields.card_number);
  const objectType = fields.object_type;

  if (
    !name ||
    !setName ||
    !setCode ||
    !cardNumber ||
    !objectType ||
    !SUPPORTED_OBJECT_TYPES.has(objectType)
  ) {
    return null;
  }

  return {
    card_ref: cardRef,
    name,
    set_name: setName,
    set_code: setCode,
    card_number: cardNumber,
    finish: fields.finish ?? null,
    language: fields.language ?? null,
    object_type: objectType,
    image_url: fields.image_url ?? null,
    rarity: fields.rarity ?? null,
  };
}

function requiredStringField(value: string | null | undefined): string | null {
  const normalized = value?.trim() ?? "";

  return normalized.length > 0 ? normalized : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function withCardSetImageUrl(
  set: SetSearchResult,
): Omit<SetSearchResult, "image_card_ref"> {
  const { image_card_ref: imageCardRef, ...item } = set;
  if (!imageCardRef) return { ...item, image_url: null };
  return {
    ...item,
    image_url: cardImageUrl(imageCardRef, "list"),
  };
}

function parseObjectType(value: string | undefined): CardObjectType | undefined | "invalid" {
  if (!value) {
    return undefined;
  }

  const normalized = value.trim().toLowerCase();

  return SUPPORTED_OBJECT_TYPES.has(normalized as CardObjectType)
    ? (normalized as CardObjectType)
    : "invalid";
}

function cardRefParam(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function positiveIntegerOrDefault(
  value: string | undefined,
  fallback: number,
  max?: number,
): number {
  if (!value || !/^\d+$/.test(value)) {
    return fallback;
  }

  const parsed = Number(value);

  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    return fallback;
  }

  return max ? Math.min(parsed, max) : parsed;
}

function parsePriceSeriesBatch(value: unknown): PriceSeriesBatchRequest[] | null {
  if (!isRecord(value) || !Array.isArray(value.requests)) {
    return null;
  }
  if (value.requests.length === 0 || value.requests.length > 100) {
    return null;
  }

  const requests: PriceSeriesBatchRequest[] = [];
  for (const item of value.requests) {
    if (!isRecord(item)) return null;
    const grader = typeof item.grader === "string" ? item.grader.trim() : "";
    const grade = item.grade === null ? null : item.grade;
    const condition = item.condition === null ? null : item.condition;
    const finish = item.finish == null ? null : item.finish;
    const days = item.days;
    if (
      !grader ||
      (grade !== null && (typeof grade !== "number" || !Number.isFinite(grade))) ||
      (condition !== null && typeof condition !== "string") ||
      (finish !== null && typeof finish !== "string") ||
      typeof days !== "number" ||
      !Number.isInteger(days) ||
      days < 1 ||
      days > 365
    ) {
      return null;
    }
    requests.push({
      grader,
      grade,
      condition: typeof condition === "string" ? condition.trim() || null : null,
      finish: typeof finish === "string" ? finish.trim() || null : null,
      days,
    });
  }
  return requests;
}

function nullableNumber(value: string | undefined): number | null {
  if (!value) {
    return null;
  }

  const parsed = Number(value);

  return Number.isFinite(parsed) ? parsed : null;
}

function nullableString(value: string | undefined): string | null {
  const normalized = value?.trim() ?? "";

  return normalized.length > 0 ? normalized : null;
}

function targetCurrencies(value: string | undefined): string[] {
  const targets = (value ?? "USD")
    .split(",")
    .map((target) => target.trim().toUpperCase())
    .filter((target) => target.length > 0);

  return targets.length > 0 ? targets : ["USD"];
}
