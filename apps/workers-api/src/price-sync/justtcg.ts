import type { Env } from "../env";

const SOURCE = "justtcg-v1";
const API_URL = "https://api.justtcg.com/v1/cards";
const DEFAULT_BATCH_SIZE = 100;
const MAX_BATCH_SIZE = 100;
const WRITE_BATCH_SIZE = 50;
const RETRY_DELAY_MS = 60 * 60 * 1000;
const CYCLE_INTERVAL_MS = 24 * 60 * 60 * 1000;

type PriceSyncStatusValue =
  | "not_started"
  | "running"
  | "completed"
  | "blocked"
  | "failed";

type PriceSyncStateRow = {
  source: string;
  status: PriceSyncStatusValue;
  cursor_product_id: number | null;
  cycle_started_at: string | null;
  last_attempt_at: string | null;
  last_success_at: string | null;
  last_completed_at: string | null;
  next_run_at: string | null;
  products_processed: number;
  variants_written: number;
  covered_products: number;
  total_products: number;
  last_error: string | null;
};

type CatalogProductRow = { product_id: string };
type CoverageRow = { covered_products: number; total_products: number };

export type PriceSyncStatus = PriceSyncStateRow & {
  configured: boolean;
};

export type PriceSyncOptions = {
  fetch?: typeof fetch;
  force?: boolean;
  now?: Date;
};

export type NormalizedPriceVariant = {
  productId: number;
  sourceVariantId: string;
  conditionCode: string;
  conditionName: string;
  languageCode: string;
  languageName: string;
  variantCode: string;
  variantName: string;
  priceHistory: Array<{ date: string; price: number }>;
};

const SELECT_STATE_SQL = `
  SELECT source, status, cursor_product_id, cycle_started_at, last_attempt_at,
         last_success_at, last_completed_at, next_run_at, products_processed,
         variants_written, covered_products, total_products, last_error
  FROM price_sync_state
  WHERE source = ?
  LIMIT 1
`;

const SELECT_PRODUCTS_SQL = `
  SELECT product_id
  FROM cards_all
  WHERE product_type_name = 'Cards'
    AND CAST(product_id AS INTEGER) > ?
  ORDER BY CAST(product_id AS INTEGER) ASC
  LIMIT ?
`;

const SELECT_COVERAGE_SQL = `
  SELECT
    (SELECT COUNT(DISTINCT product_id)
     FROM tcgplayer_skus
     WHERE price_history <> '[]') AS covered_products,
    (SELECT COUNT(*)
     FROM cards_all
     WHERE product_type_name = 'Cards') AS total_products
`;

const UPSERT_VARIANT_SQL = `
  INSERT INTO tcgplayer_skus (
    product_id, sku_key, condition_code, condition_name, language_code,
    language_name, variant_code, variant_name, created_at, updated_at,
    price_history, source, source_variant_id
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(source, source_variant_id) DO UPDATE SET
    product_id = excluded.product_id,
    sku_key = excluded.sku_key,
    condition_code = excluded.condition_code,
    condition_name = excluded.condition_name,
    language_code = excluded.language_code,
    language_name = excluded.language_name,
    variant_code = excluded.variant_code,
    variant_name = excluded.variant_name,
    updated_at = excluded.updated_at,
    price_history = excluded.price_history
`;

const UPSERT_STATE_SQL = `
  INSERT INTO price_sync_state (
    source, status, cursor_product_id, cycle_started_at, last_attempt_at,
    last_success_at, last_completed_at, next_run_at, products_processed,
    variants_written, covered_products, total_products, last_error
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(source) DO UPDATE SET
    status = excluded.status,
    cursor_product_id = excluded.cursor_product_id,
    cycle_started_at = excluded.cycle_started_at,
    last_attempt_at = excluded.last_attempt_at,
    last_success_at = excluded.last_success_at,
    last_completed_at = excluded.last_completed_at,
    next_run_at = excluded.next_run_at,
    products_processed = excluded.products_processed,
    variants_written = excluded.variants_written,
    covered_products = excluded.covered_products,
    total_products = excluded.total_products,
    last_error = excluded.last_error
`;

export async function getJustTcgPriceSyncStatus(
  env: Pick<Env, "DB" | "JUSTTCG_API_KEY">,
): Promise<PriceSyncStatus> {
  const row = await env.DB.prepare(SELECT_STATE_SQL)
    .bind(SOURCE)
    .first<PriceSyncStateRow>();

  return {
    ...(row ?? emptyState()),
    configured: hasApiKey(env.JUSTTCG_API_KEY),
  };
}

export async function runJustTcgPriceSync(
  env: Pick<Env, "DB" | "JUSTTCG_API_KEY" | "JUSTTCG_BATCH_SIZE">,
  options: PriceSyncOptions = {},
): Promise<PriceSyncStatus> {
  const now = options.now ?? new Date();
  const nowIso = now.toISOString();
  const current = await getJustTcgPriceSyncStatus(env);

  if (!options.force && isFuture(current.next_run_at, now)) {
    return current;
  }

  if (!hasApiKey(env.JUSTTCG_API_KEY)) {
    const blocked = stateFrom(current, {
      status: "blocked",
      last_attempt_at: nowIso,
      next_run_at: addMilliseconds(now, RETRY_DELAY_MS),
      last_error: "JUSTTCG_API_KEY is not configured.",
    });
    await writeState(env.DB, blocked);
    return { ...blocked, configured: false };
  }

  const startingNewCycle =
    current.status === "not_started" || current.status === "completed";
  const cycleStartedAt = startingNewCycle
    ? nowIso
    : current.cycle_started_at ?? nowIso;
  const cursor = startingNewCycle ? 0 : current.cursor_product_id ?? 0;
  const productsProcessed = startingNewCycle
    ? 0
    : current.products_processed;
  const variantsWritten = startingNewCycle ? 0 : current.variants_written;
  const batchSize = readBatchSize(env.JUSTTCG_BATCH_SIZE);
  const productRows = await env.DB.prepare(SELECT_PRODUCTS_SQL)
    .bind(cursor, batchSize)
    .all<CatalogProductRow>();
  const productIds = (productRows.results ?? [])
    .map((row) => Number(row.product_id))
    .filter(Number.isSafeInteger);

  if (productIds.length === 0) {
    const coverage = await readCoverage(env.DB);
    const nextCycleAt = Math.max(
      Date.parse(cycleStartedAt) + CYCLE_INTERVAL_MS,
      now.getTime() + 5 * 60 * 1000,
    );
    const completed = stateFrom(current, {
      status: "completed",
      cursor_product_id: null,
      cycle_started_at: cycleStartedAt,
      last_attempt_at: nowIso,
      last_completed_at: nowIso,
      next_run_at: new Date(nextCycleAt).toISOString(),
      products_processed: productsProcessed,
      variants_written: variantsWritten,
      covered_products: coverage.covered_products,
      total_products: coverage.total_products,
      last_error: null,
    });
    await writeState(env.DB, completed);
    return { ...completed, configured: true };
  }

  try {
    const response = await (options.fetch ?? fetch)(API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": "KandoCardAI/1.0",
        "x-api-key": env.JUSTTCG_API_KEY!.trim(),
      },
      body: JSON.stringify(
        productIds.map((productId) => ({ tcgplayerId: String(productId) })),
      ),
    });

    if (!response.ok) {
      const body = (await response.text()).slice(0, 300);
      throw new Error(
        `JustTCG returned HTTP ${response.status}${body ? `: ${body}` : "."}`,
      );
    }

    const variants = normalizeJustTcgResponse(
      await response.json(),
      new Set(productIds),
    );
    await writeVariants(env.DB, variants, nowIso);
    const coverage = await readCoverage(env.DB);
    const running = stateFrom(current, {
      status: "running",
      cursor_product_id: productIds.at(-1)!,
      cycle_started_at: cycleStartedAt,
      last_attempt_at: nowIso,
      last_success_at: nowIso,
      next_run_at: null,
      products_processed: productsProcessed + productIds.length,
      variants_written: variantsWritten + variants.length,
      covered_products: coverage.covered_products,
      total_products: coverage.total_products,
      last_error: null,
    });
    await writeState(env.DB, running);
    return { ...running, configured: true };
  } catch (error) {
    const failed = stateFrom(current, {
      status: "failed",
      cursor_product_id: cursor || null,
      cycle_started_at: cycleStartedAt,
      last_attempt_at: nowIso,
      next_run_at: addMilliseconds(now, RETRY_DELAY_MS),
      products_processed: productsProcessed,
      variants_written: variantsWritten,
      last_error: errorMessage(error),
    });
    await writeState(env.DB, failed);
    return { ...failed, configured: true };
  }
}

export function normalizeJustTcgResponse(
  payload: unknown,
  requestedProductIds: ReadonlySet<number>,
): NormalizedPriceVariant[] {
  if (!isRecord(payload) || !Array.isArray(payload.data)) {
    throw new Error("JustTCG response does not contain a data array.");
  }

  const variants: NormalizedPriceVariant[] = [];
  for (const card of payload.data) {
    if (!isRecord(card)) continue;
    const productId = Number(card.tcgplayerId);
    if (!Number.isSafeInteger(productId) || !requestedProductIds.has(productId)) {
      continue;
    }
    if (!Array.isArray(card.variants)) continue;

    for (const variant of card.variants) {
      const normalized = normalizeVariant(productId, variant);
      if (normalized) variants.push(normalized);
    }
  }

  return variants;
}

function normalizeVariant(
  productId: number,
  value: unknown,
): NormalizedPriceVariant | null {
  if (!isRecord(value) || typeof value.uuid !== "string") return null;
  const sourceVariantId = value.uuid.trim();
  const condition = normalizeCondition(value.condition);
  const printing = normalizePrinting(value.printing);
  const priceHistory = normalizePriceHistory(value);
  if (!sourceVariantId || !condition || !printing || priceHistory.length === 0) {
    return null;
  }

  const language = normalizeLanguage(value.language);
  return {
    productId,
    sourceVariantId,
    conditionCode: condition.code,
    conditionName: condition.name,
    languageCode: language.code,
    languageName: language.name,
    variantCode: printing.code,
    variantName: printing.name,
    priceHistory,
  };
}

function normalizeCondition(
  value: unknown,
): { code: string; name: string } | null {
  if (typeof value !== "string") return null;
  switch (value.trim().toLowerCase()) {
    case "nm":
    case "near mint":
      return { code: "NM", name: "Near Mint" };
    case "lp":
    case "lightly played":
      return { code: "LP", name: "Lightly Played" };
    case "mp":
    case "moderately played":
      return { code: "MP", name: "Moderately Played" };
    case "hp":
    case "heavily played":
      return { code: "HP", name: "Heavily Played" };
    case "dm":
    case "dmg":
    case "damaged":
      return { code: "DM", name: "Damaged" };
    default:
      return null;
  }
}

function normalizePrinting(
  value: unknown,
): { code: string; name: string } | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const name = value.trim();
  switch (name.toLowerCase()) {
    case "normal":
      return { code: "N", name };
    case "foil":
    case "holofoil":
      return { code: "F", name };
    case "etched foil":
    case "foil etched":
      return { code: "EF", name };
    default:
      return {
        code: name.toUpperCase().replace(/[^A-Z0-9]+/g, "_").slice(0, 32),
        name,
      };
  }
}

function normalizeLanguage(
  value: unknown,
): { code: string; name: string } {
  if (typeof value !== "string" || !value.trim()) {
    return { code: "EN", name: "English" };
  }
  const name = value.trim();
  if (name.toLowerCase() === "english" || name.toUpperCase() === "EN") {
    return { code: "EN", name: "English" };
  }
  return { code: name.slice(0, 8).toUpperCase(), name };
}

function normalizePriceHistory(
  variant: Record<string, unknown>,
): Array<{ date: string; price: number }> {
  const pricesByDate = new Map<string, number>();
  if (Array.isArray(variant.priceHistory)) {
    for (const point of variant.priceHistory) {
      if (!isRecord(point)) continue;
      const date = dateFromTimestamp(point.t);
      const price = Number(point.p);
      if (date && Number.isFinite(price) && price > 0) {
        pricesByDate.set(date, price);
      }
    }
  }

  const currentDate = dateFromTimestamp(variant.lastUpdated);
  const currentPrice = Number(variant.price);
  if (currentDate && Number.isFinite(currentPrice) && currentPrice > 0) {
    pricesByDate.set(currentDate, currentPrice);
  }

  return [...pricesByDate.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .slice(-365)
    .map(([date, price]) => ({ date, price }));
}

function dateFromTimestamp(value: unknown): string | null {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return null;
  const milliseconds = numeric > 10_000_000_000 ? numeric : numeric * 1000;
  const date = new Date(milliseconds);
  return Number.isNaN(date.getTime()) ? null : date.toISOString().slice(0, 10);
}

async function writeVariants(
  db: D1Database,
  variants: NormalizedPriceVariant[],
  nowIso: string,
): Promise<void> {
  for (let offset = 0; offset < variants.length; offset += WRITE_BATCH_SIZE) {
    const statements = variants
      .slice(offset, offset + WRITE_BATCH_SIZE)
      .map((variant) =>
        db.prepare(UPSERT_VARIANT_SQL).bind(
          variant.productId,
          `${SOURCE}:${variant.sourceVariantId}`,
          variant.conditionCode,
          variant.conditionName,
          variant.languageCode,
          variant.languageName,
          variant.variantCode,
          variant.variantName,
          nowIso,
          nowIso,
          JSON.stringify(variant.priceHistory),
          SOURCE,
          variant.sourceVariantId,
        ),
      );
    if (statements.length > 0) await db.batch(statements);
  }
}

async function readCoverage(db: D1Database): Promise<CoverageRow> {
  return (
    (await db.prepare(SELECT_COVERAGE_SQL).first<CoverageRow>()) ?? {
      covered_products: 0,
      total_products: 0,
    }
  );
}

async function writeState(
  db: D1Database,
  state: PriceSyncStateRow,
): Promise<void> {
  await db.prepare(UPSERT_STATE_SQL)
    .bind(
      SOURCE,
      state.status,
      state.cursor_product_id,
      state.cycle_started_at,
      state.last_attempt_at,
      state.last_success_at,
      state.last_completed_at,
      state.next_run_at,
      state.products_processed,
      state.variants_written,
      state.covered_products,
      state.total_products,
      state.last_error,
    )
    .run();
}

function stateFrom(
  current: PriceSyncStatus,
  changes: Partial<PriceSyncStateRow>,
): PriceSyncStateRow {
  const { configured: _, ...state } = current;
  return { ...state, ...changes, source: SOURCE };
}

function emptyState(): PriceSyncStateRow {
  return {
    source: SOURCE,
    status: "not_started",
    cursor_product_id: null,
    cycle_started_at: null,
    last_attempt_at: null,
    last_success_at: null,
    last_completed_at: null,
    next_run_at: null,
    products_processed: 0,
    variants_written: 0,
    covered_products: 0,
    total_products: 0,
    last_error: null,
  };
}

function readBatchSize(value: string | undefined): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) && parsed > 0
    ? Math.min(parsed, MAX_BATCH_SIZE)
    : DEFAULT_BATCH_SIZE;
}

function hasApiKey(value: string | undefined): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isFuture(value: string | null, now: Date): boolean {
  return value !== null && Date.parse(value) > now.getTime();
}

function addMilliseconds(date: Date, milliseconds: number): string {
  return new Date(date.getTime() + milliseconds).toISOString();
}

function errorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.slice(0, 500);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
