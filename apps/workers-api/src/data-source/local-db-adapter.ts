import type {
  CardObjectType,
  CardSearchResult,
  DataSourceAdapter,
  MarketPrice,
  PricePoint,
  PriceSeriesRequest,
  SetSearchResult,
  SoldListing,
} from "./adapter";
import {
  amountMicrosToUsd,
  loadPriceHistoryBySeries,
  loadPublishedPriceRows,
  pointsWithPublishedSnapshot,
  shiftDate,
  type PublishedPriceRow,
} from "./postgres-price-store";

type CardCatalogRow = {
  product_id: string;
  game_id: number;
  game: string | null;
  set_id: string | null;
  set_name: string | null;
  set_code: string | null;
  name: string | null;
  rarity: string | null;
  product_type_name: string | null;
};

type CardNumberRow = {
  product_id: string;
  number: string | null;
};

type TrendingRow = CardCatalogRow & {
  rank: number;
  source_code: string;
  source_record_id: string;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  observed_on: string;
  amount_micros: number;
  baseline_1d_on: string;
  baseline_1d_amount_micros: number;
  change_1d_percent: number;
};

const CARD_SELECT = `
SELECT product_id, game_id, game, set_id, set_name, set_code, name, rarity, product_type_name
FROM cards_all
`;

export function createLocalDbDataSourceAdapter(db: D1Database): DataSourceAdapter {
  return {
    async searchCards(query, options = {}) {
      const normalizedQuery = query.trim().toLowerCase();
      const searchTerms = normalizedQuery.split(/\s+/).filter(Boolean);
      const effectiveSearchTerms = searchTerms.length > 0 ? searchTerms : [""];
      const page = positiveIntegerOrDefault(options.page, 1);
      const pageSize = positiveIntegerOrDefault(options.page_size, 40);
      const offset = (page - 1) * pageSize;
      const objectTypeClause = objectTypeWhereClause(options.object_type);
      const gameClause = options.game ? "AND lower(game) = lower(?)" : "";
      const setIdClause = options.set_id ? "AND set_id = ?" : "";
      const setClause = options.set_code ? "AND lower(set_code) = lower(?)" : "";
      const bindings = [
        ...effectiveSearchTerms.map((term) => `%${term}%`),
        ...(options.game ? [options.game] : []),
        ...(options.set_id ? [options.set_id] : []),
        ...(options.set_code ? [options.set_code] : []),
        pageSize,
        offset,
      ];
      const results = await db.prepare(
        `${CARD_SELECT}
WHERE ${effectiveSearchTerms.map(
  () => `lower(
  coalesce(name, '') || ' ' ||
  coalesce(number, '') || ' ' ||
  coalesce(set_name, '') || ' ' ||
  coalesce(set_code, '') || ' ' ||
  coalesce(rarity, '') || ' ' ||
  coalesce(game, '')
) LIKE ?`,
).join("\nAND ")}
${objectTypeClause}
${gameClause}
${setIdClause}
${setClause}
ORDER BY updated_at DESC NULLS LAST, product_id ASC
LIMIT ? OFFSET ?`,
      ).bind(...bindings).all<CardCatalogRow>();

      return cardsWithSearchPricing(db, results.results ?? []);
    },

    async searchSets(query, options = {}) {
      const normalizedQuery = query.trim().toLowerCase();
      const page = positiveIntegerOrDefault(options.page, 1);
      const pageSize = positiveIntegerOrDefault(options.page_size, 20);
      const offset = (page - 1) * pageSize;
      const gameClause = options.game ? "AND lower(s.game) = lower(?)" : "";
      const bindings = [
        `%${normalizedQuery}%`,
        ...(options.game ? [options.game] : []),
        pageSize,
        offset,
      ];
      const results = await db.prepare(
        `SELECT s.set_id,
                s.set_code,
                s.name AS set_name,
                s.game,
                NULL AS image_url,
                nullif(trim(s.set_image_id), '') AS image_card_ref,
                coalesce(s.total_cards, 0) AS card_count
         FROM sets s
         WHERE lower(s.name || ' ' || coalesce(s.set_code, '')) LIKE ?
           AND trim(coalesce(s.set_code, '')) <> ''
           ${gameClause}
         ORDER BY s.name ASC, s.set_id ASC
         LIMIT ? OFFSET ?`,
      ).bind(...bindings).all<SetSearchResult>();

      return results.results ?? [];
    },

    async getCard(cardRef) {
      const row = await db.prepare(`${CARD_SELECT}WHERE product_id = ? LIMIT 1`)
        .bind(cardRef).first<CardCatalogRow>();
      if (!row) return null;

      const [numbers, priceRows] = await Promise.all([
        findCardNumbersByProductId(db, [row.product_id]),
        loadPublishedPriceRows(db, [row.product_id]),
      ]);
      const card = cardWithSearchPricing(
        row,
        priceRows,
        numbers.get(row.product_id) ?? "",
      );
      return {
        ...card,
        available_languages: uniquePriceValues(
          priceRows,
          (price) => price.language_name ?? price.language_code,
        ),
        available_finishes: uniquePriceValues(
          priceRows,
          (price) => price.variant_name,
        ),
      };
    },

    async getPriceSeries(cardRef, grader, grade, condition, days, finish) {
      const [series] = await loadPriceSeriesBatch(db, cardRef, [{
        grader,
        grade,
        condition,
        days,
        finish: finish ?? null,
      }]);
      return series ?? [];
    },

    async getPriceSeriesBatch(cardRef, requests) {
      return loadPriceSeriesBatch(db, cardRef, requests);
    },

    async getMarketPrices(cardRef, finish, language) {
      const rows = filterPricesByLanguage(
        filterPricesByFinish(await loadPublishedPriceRows(db, [cardRef]), finish),
        language,
      );
      const rawRows = preferredRawMarketPrices(rows);
      const gradedRows = preferredGradedMarketPrices(rows);
      const historyRows = gradedRows.length === 0
        ? new Map<number, PricePoint[]>()
        : await loadHistoryForRows(db, gradedRows, 90);

      return [
        ...rawRows.map(rawMarketPrice),
        ...gradedRows.map((row) => gradedMarketPrice(
          row,
          filterPointsByDays(
            pointsWithPublishedSnapshot(row, historyRows.get(row.series_id)),
            90,
          ),
        )),
      ];
    },

    async getTrending(options) {
      const page = options?.page ?? 1;
      const pageSize = options?.page_size ?? 10;
      const results = await db.prepare(
        `SELECT trend.rank, cards.product_id, cards.game_id, cards.game,
           cards.set_id, cards.set_name, cards.set_code, cards.name,
           cards.rarity, cards.product_type_name,
           source.source_code, series.source_record_id,
           series.condition_code, series.condition_name,
           series.language_code, series.language_name,
           series.finish_code AS variant_code, series.finish_name AS variant_name,
           trend.observed_on, trend.amount_micros,
           trend.baseline_1d_on, trend.baseline_1d_amount_micros,
           trend.change_1d_percent
         FROM current_price_pointer AS pointer
         JOIN card_trending_snapshot AS trend
           ON trend.batch_id = pointer.batch_id
         JOIN price_series AS series
           ON series.series_id = trend.winning_series_id
         JOIN price_source AS source
           ON source.source_id = series.source_id
         JOIN cards_all AS cards
           ON cards.product_id = trend.card_ref
         WHERE pointer.scope_code = 'trending:global'
         ORDER BY trend.rank
         LIMIT ? OFFSET ?`,
      ).bind(pageSize, (page - 1) * pageSize).all<TrendingRow>();

      return (results.results ?? []).map(trendingCard);
    },

    async getSoldListings(cardRef): Promise<SoldListing[]> {
      const card = await db.prepare(`${CARD_SELECT}WHERE product_id = ? LIMIT 1`)
        .bind(cardRef).first<CardCatalogRow>();
      if (!card) return [];

      const prices = (await loadPublishedPriceRows(db, [cardRef]))
        .filter((row) => row.source_code === "tcgplayer");
      return preferredRawMarketPrices(prices)
        .map((row) => shopListingFromTcgplayerPrice(card, row))
        .sort((left, right) => right.date.localeCompare(left.date))
        .slice(0, 4);
    },
  };
}

async function loadPriceSeriesBatch(
  db: D1Database,
  cardRef: string,
  requests: PriceSeriesRequest[],
): Promise<PricePoint[][]> {
  const rows = await loadPublishedPriceRows(db, [cardRef]);
  const selectedRows = requests.map((request) => {
    const isRawRequest = normalizedGraderQualifier(request.grader) === "raw";
    const graderRows = isRawRequest
      ? rows.filter(isRawPrice)
      : rows.filter((row) =>
        normalizedGraderQualifier(row.grader_code)
          === normalizedGraderQualifier(request.grader)
        && priceMatchesGrade(row, request.grade)
      );
    const finishRows = filterPricesByFinish(graderRows, request.finish);
    const conditionRows = request.condition
      ? finishRows.filter((row) => priceMatchesCondition(row, request.condition!))
      : finishRows;
    return isRawRequest
      ? preferredSearchPrice(conditionRows)
      : preferredGradedSeriesPrice(conditionRows);
  });
  const rowsToLoad = selectedRows.filter(
    (row): row is PublishedPriceRow => row !== null,
  );
  const histories = rowsToLoad.length === 0
    ? new Map<number, PricePoint[]>()
    : await loadHistoryForSelections(db, requests, selectedRows);

  return selectedRows.map((row, index) => row
    ? filterPointsByDays(
      pointsWithPublishedSnapshot(row, histories.get(row.series_id)),
      requests[index]!.days,
    )
    : []);
}

async function loadHistoryForSelections(
  db: D1Database,
  requests: PriceSeriesRequest[],
  selectedRows: Array<PublishedPriceRow | null>,
): Promise<Map<number, PricePoint[]>> {
  return loadHistoryForWindows(db, selectedRows.flatMap((row, index) => row
    ? [{
      seriesId: row.series_id,
      start: shiftDate(row.observed_on, -Math.max(requests[index]!.days, 1)),
      end: row.observed_on,
    }]
    : []));
}

async function loadHistoryForRows(
  db: D1Database,
  rows: PublishedPriceRow[],
  days: number,
): Promise<Map<number, PricePoint[]>> {
  return loadHistoryForWindows(db, rows.map((row) => ({
    seriesId: row.series_id,
    start: shiftDate(row.observed_on, -days),
    end: row.observed_on,
  })));
}

async function loadHistoryForWindows(
  db: D1Database,
  windows: Array<{ seriesId: number; start: string; end: string }>,
): Promise<Map<number, PricePoint[]>> {
  const bySeries = new Map<number, { seriesId: number; start: string; end: string }>();
  for (const window of windows) {
    const existing = bySeries.get(window.seriesId);
    bySeries.set(window.seriesId, existing
      ? {
        seriesId: window.seriesId,
        start: existing.start < window.start ? existing.start : window.start,
        end: existing.end > window.end ? existing.end : window.end,
      }
      : window);
  }

  const groups: Array<{
    seriesIds: number[];
    start: string;
    end: string;
  }> = [];
  for (const window of [...bySeries.values()].sort((left, right) =>
    left.start.localeCompare(right.start) || left.end.localeCompare(right.end)
  )) {
    const group = groups.at(-1);
    const candidateEnd = group && group.end > window.end ? group.end : window.end;
    if (group && daysBetween(group.start, candidateEnd) <= 400) {
      group.seriesIds.push(window.seriesId);
      group.end = candidateEnd;
    } else {
      groups.push({ seriesIds: [window.seriesId], start: window.start, end: window.end });
    }
  }

  const histories = new Map<number, PricePoint[]>();
  for (const group of groups) {
    const loaded = await loadPriceHistoryBySeries(db, group.seriesIds, group.start, group.end);
    for (const [seriesId, points] of loaded) histories.set(seriesId, points);
  }
  return histories;
}

function daysBetween(start: string, end: string): number {
  return (Date.parse(`${end}T00:00:00.000Z`) - Date.parse(`${start}T00:00:00.000Z`))
    / (24 * 60 * 60 * 1000);
}

function rawMarketPrice(row: PublishedPriceRow): MarketPrice {
  return {
    grader: "Raw",
    grade: null,
    condition: row.condition_name ?? row.condition_code,
    price: amountMicrosToUsd(row.amount_micros),
    ...(row.baseline_7d_amount_micros === null
      ? {}
      : { previous_7d_price_usd: amountMicrosToUsd(row.baseline_7d_amount_micros) }),
    ...(row.source_code === "pricecharting"
      ? { product_sub_type: row.variant_name ?? row.variant_code }
      : {}),
    ...(Number.isFinite(row.change_7d_percent)
      ? { increase_percent: row.change_7d_percent! }
      : {}),
  };
}

function gradedMarketPrice(
  row: PublishedPriceRow,
  history: PricePoint[],
): MarketPrice {
  const minGrade = row.grade_min_x10 === null ? null : row.grade_min_x10 / 10;
  const maxGrade = row.grade_max_x10 === null ? null : row.grade_max_x10 / 10;
  const gradeLabel = minGrade === null
    ? undefined
    : maxGrade !== null && maxGrade !== minGrade
      ? `${formatGrade(minGrade)}/${formatGrade(maxGrade)}`
      : formatGrade(minGrade);
  return {
    grader: graderDisplayName(row.grader_code),
    grade: minGrade,
    ...(gradeLabel ? { grade_label: gradeLabel } : {}),
    condition: null,
    price: amountMicrosToUsd(row.amount_micros),
    ...(row.baseline_7d_amount_micros === null
      ? {}
      : { previous_7d_price_usd: amountMicrosToUsd(row.baseline_7d_amount_micros) }),
    product_sub_type: row.variant_name ?? row.variant_code,
    ...(Number.isFinite(row.change_7d_percent)
      ? { increase_percent: row.change_7d_percent! }
      : {}),
    history,
  };
}

function shopListingFromTcgplayerPrice(
  card: CardCatalogRow,
  row: PublishedPriceRow,
): SoldListing {
  const title = [
    card.name ?? card.product_id,
    row.condition_name ?? row.condition_code,
    row.language_name ?? row.language_code,
    row.variant_name ?? row.variant_code,
  ].filter((value): value is string => Boolean(value?.trim())).join(" / ");
  return {
    date: row.observed_on,
    title,
    price: amountMicrosToUsd(row.amount_micros),
    platform: "TCGplayer",
    url: `https://www.tcgplayer.com/product/${encodeURIComponent(card.product_id)}`,
  };
}

function trendingCard(row: TrendingRow): CardSearchResult {
  return {
    ...cardFromRow(row),
    finish: row.variant_name ?? row.variant_code,
    language: row.language_name ?? row.language_code,
    price_usd: amountMicrosToUsd(row.amount_micros),
    previous_1d_price_usd: amountMicrosToUsd(row.baseline_1d_amount_micros),
    price_change_1d_percent: row.change_1d_percent,
    price_as_of: row.observed_on,
    previous_price_as_of: row.baseline_1d_on,
  };
}

async function cardsWithSearchPricing(
  db: D1Database,
  rows: CardCatalogRow[],
): Promise<CardSearchResult[]> {
  const refs = rows.map((row) => row.product_id);
  const [pricesByProductId, numbersByProductId] = await Promise.all([
    findPriceRowsByProductId(db, refs),
    findCardNumbersByProductId(db, refs),
  ]);
  return rows.map((row) => cardWithSearchPricing(
    row,
    pricesByProductId.get(row.product_id) ?? [],
    numbersByProductId.get(row.product_id) ?? "",
  ));
}

function cardWithSearchPricing(
  row: CardCatalogRow,
  prices: PublishedPriceRow[],
  cardNumber: string,
): CardSearchResult {
  const card = cardFromRow(row, cardNumber);
  const price = preferredSearchPrice(prices.filter(isRawPrice));
  if (!price) return card;

  return {
    ...card,
    finish: price.variant_name ?? price.variant_code,
    language: price.language_name ?? price.language_code,
    price_usd: amountMicrosToUsd(price.amount_micros),
    ...(price.baseline_30d_amount_micros === null
      ? {}
      : { previous_30d_price_usd: amountMicrosToUsd(price.baseline_30d_amount_micros) }),
    ...(price.baseline_7d_amount_micros === null
      ? {}
      : { previous_7d_price_usd: amountMicrosToUsd(price.baseline_7d_amount_micros) }),
    ...(price.baseline_1d_amount_micros === null
      ? {}
      : { previous_1d_price_usd: amountMicrosToUsd(price.baseline_1d_amount_micros) }),
    ...(Number.isFinite(price.change_30d_percent)
      ? { price_change_30d_percent: price.change_30d_percent! }
      : {}),
    ...(Number.isFinite(price.change_7d_percent)
      ? { price_change_7d_percent: price.change_7d_percent! }
      : {}),
    ...(Number.isFinite(price.change_1d_percent)
      ? { price_change_1d_percent: price.change_1d_percent! }
      : {}),
    price_as_of: price.observed_on,
    ...(price.baseline_1d_on ? { previous_price_as_of: price.baseline_1d_on } : {}),
  };
}

async function findCardNumbersByProductId(
  db: D1Database,
  cardRefs: string[],
): Promise<Map<string, string>> {
  const numbersByProductId = new Map<string, string>();
  if (cardRefs.length === 0) return numbersByProductId;
  const placeholders = cardRefs.map(() => "?").join(", ");
  const results = await db.prepare(
    `SELECT product_id, number
     FROM cards_all
     WHERE product_id IN (${placeholders})`,
  ).bind(...cardRefs).all<CardNumberRow>();
  for (const row of results.results ?? []) {
    const number = row.number?.trim();
    if (number) numbersByProductId.set(row.product_id, number);
  }
  return numbersByProductId;
}

async function findPriceRowsByProductId(
  db: D1Database,
  cardRefs: string[],
): Promise<Map<string, PublishedPriceRow[]>> {
  const grouped = new Map<string, PublishedPriceRow[]>();
  for (const row of await loadPublishedPriceRows(db, cardRefs)) {
    grouped.set(row.product_id, [...(grouped.get(row.product_id) ?? []), row]);
  }
  return grouped;
}

function preferredSearchPrice(rows: PublishedPriceRow[]): PublishedPriceRow | null {
  return [...rows].sort((left, right) =>
    compareIncreaseDescending(left, right)
    || searchPriceRank(left) - searchPriceRank(right)
    || comparePriceFreshness(left, right)
    || compareNaturalQualifiers(left, right)
  )[0] ?? null;
}

function preferredRawMarketPrices(rows: PublishedPriceRow[]): PublishedPriceRow[] {
  const rowsByCondition = new Map<string, PublishedPriceRow>();
  for (const row of rows.filter(isRawPrice)) {
    const condition = normalizedQualifier(row.condition_code ?? row.condition_name) || "unknown";
    const current = rowsByCondition.get(condition);
    if (
      !current
      || searchPriceRank(row) < searchPriceRank(current)
      || (searchPriceRank(row) === searchPriceRank(current)
        && comparePriceFreshness(row, current) < 0)
    ) {
      rowsByCondition.set(condition, row);
    }
  }
  return [...rowsByCondition.values()].sort((left, right) =>
    marketConditionRank(left) - marketConditionRank(right)
    || compareNaturalQualifiers(left, right)
  );
}

function preferredGradedMarketPrices(rows: PublishedPriceRow[]): PublishedPriceRow[] {
  const preferred = new Map<string, PublishedPriceRow>();
  for (const row of rows.filter((candidate) => !isRawPrice(candidate))) {
    const key = [
      row.grader_code.toUpperCase(),
      row.grade_min_x10 ?? "",
      row.grade_max_x10 ?? "",
      normalizedQualifier(row.language_code ?? row.language_name),
      normalizedQualifier(row.variant_code ?? row.variant_name),
    ].join("\u0000");
    const current = preferred.get(key);
    if (!current || comparePriceFreshness(row, current) < 0) preferred.set(key, row);
  }
  return [...preferred.values()].sort((left, right) =>
    left.grader_code.localeCompare(right.grader_code)
    || (left.grade_min_x10 ?? -1) - (right.grade_min_x10 ?? -1)
    || compareNaturalQualifiers(left, right)
  );
}

function uniquePriceValues(
  rows: PublishedPriceRow[],
  valueOf: (row: PublishedPriceRow) => string | null,
): string[] {
  return [...new Set(rows.map(valueOf).map((value) => value?.trim()).filter(
    (value): value is string => Boolean(value),
  ))].sort((left, right) => left.localeCompare(right));
}

function filterPricesByFinish(
  rows: PublishedPriceRow[],
  finish?: string | null,
): PublishedPriceRow[] {
  const expected = normalizedQualifier(finish);
  if (!expected) return rows;
  return rows.filter((row) =>
    qualifierValues(row.variant_code, row.variant_name).includes(expected)
  );
}

function filterPricesByLanguage(
  rows: PublishedPriceRow[],
  language?: string | null,
): PublishedPriceRow[] {
  const expected = normalizedQualifier(language);
  if (!expected) return rows;
  const exact = rows.filter((row) =>
    qualifierValues(row.language_code, row.language_name).includes(expected)
  );
  if (exact.length > 0) return exact;
  return rows.filter(
    (row) => qualifierValues(row.language_code, row.language_name).length === 0,
  );
}

function isRawPrice(row: PublishedPriceRow): boolean {
  return row.grader_code.trim().toUpperCase() === "RAW";
}

function priceMatchesCondition(row: PublishedPriceRow, condition: string): boolean {
  const expected = normalizedQualifier(condition);
  return qualifierValues(row.condition_code, row.condition_name).includes(expected);
}

function priceMatchesGrade(row: PublishedPriceRow, grade: number | null): boolean {
  if (grade === null || row.grade_min_x10 === null || row.grade_max_x10 === null) return false;
  const gradeX10 = Math.round(grade * 10);
  return gradeX10 >= row.grade_min_x10 && gradeX10 <= row.grade_max_x10;
}

function preferredGradedSeriesPrice(rows: PublishedPriceRow[]): PublishedPriceRow | null {
  return [...rows].sort((left, right) =>
    ((left.grade_max_x10 ?? 100) - (left.grade_min_x10 ?? 0))
    - ((right.grade_max_x10 ?? 100) - (right.grade_min_x10 ?? 0))
    || searchPriceRank(left) - searchPriceRank(right)
    || comparePriceFreshness(left, right)
    || compareNaturalQualifiers(left, right)
  )[0] ?? null;
}

function qualifierValues(code: string | null, name: string | null): string[] {
  return [code, name].map(normalizedQualifier).filter(Boolean);
}

function normalizedQualifier(value: string | null | undefined): string {
  return (value ?? "").trim().toLowerCase();
}

function normalizedGraderQualifier(value: string | null | undefined): string {
  const normalized = normalizedQualifier(value);
  return normalized === "grade" || normalized === "generic" ? "generic" : normalized;
}

function searchPriceRank(row: PublishedPriceRow): number {
  return (
    (row.condition_code === "NM" ? 0 : 100)
    + (row.language_code === "EN" ? 0 : 10)
    + (row.variant_code === "N" ? 0 : 1)
  );
}

function marketConditionRank(row: PublishedPriceRow): number {
  switch ((row.condition_code ?? "").trim().toUpperCase()) {
    case "NM": return 0;
    case "LP": return 1;
    case "MP": return 2;
    case "HP": return 3;
    case "DMG": return 4;
    default: return 5;
  }
}

function compareIncreaseDescending(
  left: PublishedPriceRow,
  right: PublishedPriceRow,
): number {
  const leftIncrease = Number.isFinite(left.change_30d_percent)
    ? left.change_30d_percent!
    : null;
  const rightIncrease = Number.isFinite(right.change_30d_percent)
    ? right.change_30d_percent!
    : null;
  if (leftIncrease === null) return rightIncrease === null ? 0 : 1;
  if (rightIncrease === null) return -1;
  return rightIncrease - leftIncrease;
}

function comparePriceFreshness(left: PublishedPriceRow, right: PublishedPriceRow): number {
  return right.observed_on.localeCompare(left.observed_on)
    || left.source_code.localeCompare(right.source_code)
    || left.source_record_id.localeCompare(right.source_record_id)
    || left.metric_code.localeCompare(right.metric_code)
    || left.series_id - right.series_id;
}

function compareNaturalQualifiers(
  left: PublishedPriceRow,
  right: PublishedPriceRow,
): number {
  return [left.condition_name, left.language_name, left.variant_name]
    .map(normalizedQualifier).join("\u0000").localeCompare(
      [right.condition_name, right.language_name, right.variant_name]
        .map(normalizedQualifier).join("\u0000"),
    ) || comparePriceFreshness(left, right);
}

function cardFromRow(row: CardCatalogRow, cardNumber = ""): CardSearchResult {
  return {
    card_ref: row.product_id,
    name: row.name ?? row.product_id,
    game: row.game,
    set_name: row.set_name ?? "",
    set_code: row.set_code ?? "",
    card_number: cardNumber,
    finish: null,
    language: null,
    object_type: objectTypeFromProductType(row.product_type_name),
    image_url: null,
    rarity: row.rarity,
  };
}

function objectTypeFromProductType(productType: string | null): CardObjectType {
  if (productType === "Cards") return "tcg";
  if (!productType) return "other";
  return "sealed";
}

function objectTypeWhereClause(objectType: CardObjectType | undefined): string {
  switch (objectType) {
    case "tcg": return "AND product_type_name = 'Cards'";
    case "sealed": return "AND product_type_name IS NOT NULL AND product_type_name <> 'Cards'";
    case "other": return "AND product_type_name IS NULL";
    case "sports": return "AND 0 = 1";
    default: return "";
  }
}

function filterPointsByDays(points: PricePoint[], days: number): PricePoint[] {
  const sorted = [...points].sort((left, right) => left.date.localeCompare(right.date));
  const latest = sorted.at(-1);
  if (!latest) return [];
  const cutoff = shiftDate(latest.date, -Math.max(days, 1));
  const inRange = sorted.filter((point) => point.date >= cutoff);
  const baseline = sorted.filter((point) => point.date < cutoff).at(-1);
  return [...(baseline ? [baseline] : []), ...inRange];
}

function graderDisplayName(graderCode: string): string {
  const normalized = graderCode.trim().toUpperCase();
  return normalized === "GRADE" || normalized === "GENERIC" ? "Grade" : normalized;
}

function formatGrade(grade: number): string {
  return Number.isInteger(grade) ? String(grade) : grade.toFixed(1);
}

function positiveIntegerOrDefault(value: number | undefined, fallback: number): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : fallback;
}
