import type { PricePoint } from "./adapter";

export type PublishedPriceRow = {
  series_id: number;
  source_code: string;
  source_record_id: string;
  metric_code: string;
  product_id: string;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  grader_code: string;
  grade_min_x10: number | null;
  grade_max_x10: number | null;
  observed_on: string;
  amount_micros: number;
  baseline_1d_on: string | null;
  baseline_1d_amount_micros: number | null;
  baseline_7d_on: string | null;
  baseline_7d_amount_micros: number | null;
  baseline_30d_on: string | null;
  baseline_30d_amount_micros: number | null;
  change_1d_percent: number | null;
  change_7d_percent: number | null;
  change_30d_percent: number | null;
};

type PriceHistoryMonthRow = {
  series_id: number;
  points_json: string;
};

const CURRENT_CARD_CHUNK_SIZE = 40;
const CURRENT_QUERY_ROW_LIMIT = 1000;
const HISTORY_SERIES_CHUNK_SIZE = 100;
const HISTORY_QUERY_ROW_LIMIT = 1600;
const MAX_HISTORY_RANGE_DAYS = 400;
const DAY_MS = 24 * 60 * 60 * 1000;

export class PriceQueryLimitError extends Error {}

export async function loadPublishedPriceRows(
  db: D1Database,
  cardRefs: string[],
): Promise<PublishedPriceRow[]> {
  const uniqueCardRefs = [...new Set(cardRefs.filter(Boolean))];
  const rows: PublishedPriceRow[] = [];

  for (let offset = 0; offset < uniqueCardRefs.length; offset += CURRENT_CARD_CHUNK_SIZE) {
    const chunk = uniqueCardRefs.slice(offset, offset + CURRENT_CARD_CHUNK_SIZE);
    rows.push(...(await loadPublishedPriceChunk(db, chunk)));
  }

  return rows;
}

async function loadPublishedPriceChunk(
  db: D1Database,
  cardRefs: string[],
): Promise<PublishedPriceRow[]> {
  const placeholders = cardRefs.map(() => "?").join(", ");
  const result = await db.prepare(
    `WITH ranked_current AS (
         SELECT batch.source_id, pointer.batch_id,
           ROW_NUMBER() OVER (
             PARTITION BY batch.source_id
             ORDER BY batch.business_date DESC, batch.batch_id DESC
           ) AS publication_rank
         FROM current_price_pointer AS pointer
         JOIN price_ingest_batch AS batch
           ON batch.batch_id = pointer.batch_id
          AND batch.scope_code = pointer.scope_code
         WHERE pointer.scope_code LIKE 'current:%'
           AND batch.status = 'published'
       ),
       published_current AS (
         SELECT source_id, batch_id
         FROM ranked_current
         WHERE publication_rank = 1
       )
       SELECT series.series_id, source.source_code, series.source_record_id,
         series.metric_code, series.card_ref AS product_id,
         series.condition_code, series.condition_name,
         series.language_code, series.language_name,
         series.finish_code AS variant_code, series.finish_name AS variant_name,
         series.grader_code, series.grade_min_x10, series.grade_max_x10,
         snapshot.observed_on, snapshot.amount_micros,
         snapshot.baseline_1d_on, snapshot.baseline_1d_amount_micros,
         snapshot.baseline_7d_on, snapshot.baseline_7d_amount_micros,
         snapshot.baseline_30d_on, snapshot.baseline_30d_amount_micros,
         snapshot.change_1d_percent, snapshot.change_7d_percent,
         snapshot.change_30d_percent
       FROM price_series AS series
       JOIN price_source AS source
         ON source.source_id = series.source_id
       JOIN published_current AS published
         ON published.source_id = series.source_id
       JOIN price_current_snapshot AS snapshot
         ON snapshot.batch_id = published.batch_id
        AND snapshot.series_id = series.series_id
       WHERE series.is_active
         AND source.is_active IS TRUE
         AND series.currency_code = 'USD'
         AND series.card_ref IN (${placeholders})
       ORDER BY series.card_ref, series.series_id
       LIMIT ${CURRENT_QUERY_ROW_LIMIT + 1}`,
  ).bind(...cardRefs).all<PublishedPriceRow>();
  const rows = result.results ?? [];
  if (rows.length <= CURRENT_QUERY_ROW_LIMIT) return rows;

  if (cardRefs.length === 1) {
    throw new PriceQueryLimitError(
      `Published price query exceeded ${CURRENT_QUERY_ROW_LIMIT} rows for 1 cards`,
    );
  }

  const midpoint = Math.ceil(cardRefs.length / 2);
  return [
    ...(await loadPublishedPriceChunk(db, cardRefs.slice(0, midpoint))),
    ...(await loadPublishedPriceChunk(db, cardRefs.slice(midpoint))),
  ];
}

export async function loadPriceHistoryBySeries(
  db: D1Database,
  seriesIds: number[],
  startDate: string,
  endDate: string,
): Promise<Map<number, PricePoint[]>> {
  assertHistoryRange(startDate, endDate);
  const uniqueSeriesIds = [...new Set(seriesIds)];
  const startMonth = `${startDate.slice(0, 7)}-01`;
  const endMonth = `${endDate.slice(0, 7)}-01`;
  const pointsBySeries = new Map<number, Map<string, PricePoint>>();

  for (let offset = 0; offset < uniqueSeriesIds.length; offset += HISTORY_SERIES_CHUNK_SIZE) {
    const chunk = uniqueSeriesIds.slice(offset, offset + HISTORY_SERIES_CHUNK_SIZE);
    const placeholders = chunk.map(() => "?").join(", ");
    const result = await db.prepare(
      `SELECT history.series_id, CAST(history.points AS TEXT) AS points_json
       FROM price_history_month AS history
       JOIN price_series AS series
         ON series.series_id = history.series_id
       JOIN price_ingest_batch AS history_batch
         ON history_batch.batch_id = history.last_batch_id
        AND history_batch.source_id = series.source_id
        AND history_batch.status IN ('published', 'superseded')
       WHERE history.series_id IN (${placeholders})
         AND EXISTS (
           SELECT 1
           FROM current_price_pointer AS current_pointer
           JOIN price_ingest_batch AS current_batch
             ON current_batch.batch_id = current_pointer.batch_id
            AND current_batch.scope_code = current_pointer.scope_code
           WHERE current_batch.source_id = series.source_id
             AND current_pointer.scope_code LIKE 'current:%'
             AND current_pointer.scope_code = history_batch.scope_code
             AND current_batch.status = 'published'
         )
         AND history.month_start <= ?
         AND (
           history.month_start >= ?
           OR history.month_start = (
             SELECT max(baseline.month_start)
             FROM price_history_month AS baseline
             JOIN price_ingest_batch AS baseline_batch
               ON baseline_batch.batch_id = baseline.last_batch_id
             AND baseline_batch.source_id = series.source_id
              AND baseline_batch.scope_code = history_batch.scope_code
              AND baseline_batch.status IN ('published', 'superseded')
             WHERE baseline.series_id = history.series_id
               AND baseline.month_start < ?
           )
         )
       ORDER BY history.series_id, history.month_start
       LIMIT ${HISTORY_QUERY_ROW_LIMIT + 1}`,
    ).bind(...chunk, endMonth, startMonth, startMonth).all<PriceHistoryMonthRow>();
    const chunkRows = result.results ?? [];
    if (chunkRows.length > HISTORY_QUERY_ROW_LIMIT) {
      throw new PriceQueryLimitError(
        `Price history query exceeded ${HISTORY_QUERY_ROW_LIMIT} monthly rows for ${chunk.length} series`,
      );
    }
    for (const row of chunkRows) {
      const seriesPoints = pointsBySeries.get(row.series_id) ?? new Map<string, PricePoint>();
      for (const point of parseStoredPricePoints(row.points_json)) {
        seriesPoints.set(point.date, point);
      }
      pointsBySeries.set(row.series_id, seriesPoints);
    }
  }

  return new Map(
    [...pointsBySeries].map(([seriesId, points]) => [
      seriesId,
      [...points.values()].sort((left, right) => left.date.localeCompare(right.date)),
    ]),
  );
}

export function pointsWithPublishedSnapshot(
  row: PublishedPriceRow,
  history: PricePoint[] = [],
): PricePoint[] {
  const points = new Map(history.map((point) => [point.date, point]));
  addSnapshotPoint(points, row.baseline_30d_on, row.baseline_30d_amount_micros);
  addSnapshotPoint(points, row.baseline_7d_on, row.baseline_7d_amount_micros);
  addSnapshotPoint(points, row.baseline_1d_on, row.baseline_1d_amount_micros);
  addSnapshotPoint(points, row.observed_on, row.amount_micros);
  return [...points.values()].sort((left, right) => left.date.localeCompare(right.date));
}

export function amountMicrosToUsd(amountMicros: number): number {
  return amountMicros / 1_000_000;
}

export function shiftDate(date: string, days: number): string {
  const shifted = new Date(`${date}T00:00:00.000Z`);
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
}

function parseStoredPricePoints(value: string): PricePoint[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value) as unknown;
  } catch {
    throw new Error("Invalid PostgreSQL price history payload");
  }
  if (!Array.isArray(parsed)) {
    throw new Error("Invalid PostgreSQL price history payload");
  }
  return parsed.map((entry, index): PricePoint => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error(`Invalid PostgreSQL price history point at index ${index}`);
    }
    const record = entry as Record<string, unknown>;
    if (
      isIsoDate(record.d)
      && typeof record.a === "number"
      && Number.isSafeInteger(record.a)
      && record.a >= 0
    ) {
      return { date: record.d, price: amountMicrosToUsd(record.a) };
    }
    const legacyPrice = parseLegacyUsdPrice(record.price);
    if (isIsoDate(record.date) && legacyPrice !== null) {
      return { date: record.date, price: legacyPrice };
    }
    throw new Error(`Invalid PostgreSQL price history point at index ${index}`);
  });
}

function isIsoDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function parseLegacyUsdPrice(value: unknown): number | null {
  if (typeof value === "number") {
    return Number.isFinite(value) && value >= 0 ? value : null;
  }
  if (typeof value !== "string" || !/^\d+(?:\.\d+)?$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function addSnapshotPoint(
  points: Map<string, PricePoint>,
  date: string | null,
  amountMicros: number | null,
): void {
  if (!date || amountMicros === null) return;
  points.set(date, { date, price: amountMicrosToUsd(amountMicros) });
}

function assertHistoryRange(startDate: string, endDate: string): void {
  const start = Date.parse(`${startDate}T00:00:00.000Z`);
  const end = Date.parse(`${endDate}T00:00:00.000Z`);
  if (!Number.isFinite(start) || !Number.isFinite(end) || start > end) {
    throw new Error(`Invalid price history range: ${startDate}..${endDate}`);
  }
  if ((end - start) / DAY_MS > MAX_HISTORY_RANGE_DAYS) {
    throw new Error(`Price history range exceeds ${MAX_HISTORY_RANGE_DAYS} days`);
  }
}
