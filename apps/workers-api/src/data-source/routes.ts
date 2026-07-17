import { Hono } from "hono";
import type { Env } from "../env";
import type {
  CardObjectType,
  CardSearchResult,
  DataSourceAdapter,
  SetSearchResult,
} from "./adapter";
import {
  createCacheApiDataSourceAdapter,
  type DataSourceCache,
} from "./cache-api";
import { createKvCachedDataSourceAdapter } from "./kv-cache";
import { createLocalDbDataSourceAdapter } from "./local-db-adapter";
import {
  ExchangeRateUnavailableError,
  loadUsdExchangeRates,
} from "./exchange-rates";

type DataSourceRoutesOptions = {
  createAdapter?: (env: Env) => DataSourceAdapter;
};

type CardOverrideRow = {
  card_ref: string;
  override_fields: string | null;
  image_url: string | null;
  is_missing_card: number;
};

type CardResponse = CardSearchResult & {
  override_applied: boolean;
};

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

const IMAGE_UPSTREAM_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "UPSTREAM_ERROR",
    message: "Card image is unavailable.",
  },
} as const;

const TRUSTED_IMAGE_HOSTS = new Set(["product-images.tcgplayer.com"]);

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
    const query = requiredQuery(c.req.query("q"));

    if (!query) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const objectType = parseObjectType(c.req.query("object_type"));

    if (objectType === "invalid") {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const page = positiveIntegerOrDefault(c.req.query("page"), 1);
    const pageSize = positiveIntegerOrDefault(c.req.query("page_size"), 20, 100);
    const game = nullableString(c.req.query("game")) ?? undefined;
    const adapter = createAdapter(c.env);
    const items = await listOrEmpty(() =>
      adapter.searchCards(query, {
        object_type: objectType,
        game,
        page,
        page_size: pageSize,
      }),
    );

    const responseItems = items.map((item) =>
      withProxiedImageUrl(item, c.req.url),
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

  routes.get("/sets/search", async (c) => {
    const query = requiredQuery(c.req.query("q"));

    if (!query) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const page = positiveIntegerOrDefault(c.req.query("page"), 1);
    const pageSize = positiveIntegerOrDefault(c.req.query("page_size"), 20, 100);
    const game = nullableString(c.req.query("game")) ?? undefined;
    const adapter = createAdapter(c.env);
    const sets = await listOrEmpty(() =>
      adapter.searchSets(query, { game, page, page_size: pageSize }),
    );
    const items = sets.map((set) => withProxiedSetImageUrl(set, c.req.url));

    return c.json({
      success: true,
      data: { items, total: items.length, page, page_size: pageSize },
    });
  });

  routes.get("/cards/trending", async (c) => {
    const adapter = createAdapter(c.env);
    const items = await listOrEmpty(() => adapter.getTrending());
    const overriddenItems = await Promise.all(
      items.map(async (item) => {
        const override = await findCardOverride(c.env.DB, item.card_ref);
        const card = applyCardOverride(item, override, item.card_ref);

        return { ...(card ?? { ...item, override_applied: false }), pinned: false };
      }),
    );

    return c.json({
      success: true,
      data: {
        items: overriddenItems.map((item) =>
          withProxiedImageUrl(item, c.req.url),
        ),
      },
    });
  });

  routes.get("/cards/:card_ref/image", async (c) => {
    const cardRef = cardRefParam(c.req.param("card_ref"));
    const adapter = createAdapter(c.env);
    const card = await resolveCard(c.env.DB, adapter, cardRef);
    const imageUrl = trustedImageUrl(card?.image_url ?? null);

    if (!imageUrl) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    try {
      const upstream = await fetch(imageUrl.href);
      const contentType = upstream.headers.get("content-type") ?? "";

      if (!upstream.ok || !contentType.toLowerCase().startsWith("image/")) {
        return c.json(IMAGE_UPSTREAM_ERROR_RESPONSE, 502);
      }

      const headers = new Headers({
        "Cache-Control":
          upstream.headers.get("cache-control") ?? "public, max-age=86400",
        "Content-Type": contentType,
        "X-Content-Type-Options": "nosniff",
      });

      return new Response(upstream.body, { status: 200, headers });
    } catch {
      return c.json(IMAGE_UPSTREAM_ERROR_RESPONSE, 502);
    }
  });

  routes.get("/cards/:card_ref/market-prices", async (c) => {
    c.header("Cache-Control", "no-store");
    const cardRef = cardRefParam(c.req.param("card_ref"));
    const adapter = createAdapter(c.env);
    const prices = await listOrEmpty(() => adapter.getMarketPrices(cardRef));

    return c.json({
      success: true,
      data: {
        card_ref: cardRef,
        prices: prices.map((price) => ({ ...price, currency: "USD" })),
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
    const days = positiveIntegerOrDefault(c.req.query("days"), 30);
    const adapter = createAdapter(c.env);
    const series = await listOrEmpty(() =>
      adapter.getPriceSeries(cardRef, grader, grade, condition, days),
    );

    return c.json({
      success: true,
      data: { card_ref: cardRef, grader, grade, condition, days, series },
    });
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
      ? c.json({ success: true, data: withProxiedImageUrl(card, c.req.url) })
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

function createDefaultAdapter(env: Env): DataSourceAdapter {
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

async function resolveCard(
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

function withProxiedImageUrl<T extends CardSearchResult>(
  card: T,
  requestUrl: string,
): T {
  if (!trustedImageUrl(card.image_url)) {
    return card;
  }

  const url = new URL(requestUrl);
  const dataSourcePathIndex = ["/cards/", "/sets/"]
    .map((segment) => url.pathname.indexOf(segment))
    .find((index) => index >= 0);
  const basePath =
    dataSourcePathIndex === undefined
      ? ""
      : url.pathname.slice(0, dataSourcePathIndex);
  url.pathname = `${basePath}/cards/${encodeURIComponent(card.card_ref)}/image`;
  url.search = "";
  url.hash = "";

  return { ...card, image_url: url.href };
}

function trustedImageUrl(value: string | null): URL | null {
  if (!value) {
    return null;
  }

  try {
    const url = new URL(value);

    return url.protocol === "https:" && TRUSTED_IMAGE_HOSTS.has(url.hostname)
      ? url
      : null;
  } catch {
    return null;
  }
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

function withProxiedSetImageUrl(
  set: SetSearchResult,
  requestUrl: string,
): Omit<SetSearchResult, "image_card_ref"> {
  const { image_card_ref: imageCardRef, ...item } = set;
  if (!item.image_url || !imageCardRef) return item;

  const origin = new URL(requestUrl).origin;
  return {
    ...item,
    image_url: `${origin}/api/v1/cards/${encodeURIComponent(imageCardRef)}/image`,
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

function requiredQuery(value: string | undefined): string | null {
  const normalized = value?.trim() ?? "";

  return normalized.length > 0 ? normalized : null;
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
