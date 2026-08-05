import type {
  CardObjectType,
  CardSearchResult,
  DataSourceAdapter,
  MarketPrice,
  PricePoint,
  SetSearchResult,
  SoldListing,
} from "./adapter";

type CardCatalogRow = {
  product_id: string;
  game_id: number;
  game: string | null;
  set_name: string | null;
  set_code: string | null;
  name: string | null;
  rarity: string | null;
  product_type_name: string | null;
};

type TcgPriceRow = {
  sku_id: number;
  product_id: string;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  price_history: string;
};

type CardNumberRow = {
  product_id: string;
  number: string | null;
};

type TrendingRow = CardCatalogRow &
  Omit<TcgPriceRow, "product_id"> & {
    increase_rate: number;
  };

type SkuPricingRow = Pick<
  TcgPriceRow,
  "variant_name" | "variant_code" | "language_name" | "language_code" | "price_history"
>;

type PriceHistoryEntry = {
  date: string;
  price: number;
};

type TcgPriceHistoryRow = {
  pricecharting_id: string;
  product_sub_type: string | null;
  price_Ungraded: string;
  increase_Ungraded: number;
  price_Grade_7: string;
  price_Grade_8: string;
  price_Grade_9: string;
  price_Grade_9_5: string;
  price_PSA_10: string;
  price_BGS_10: string;
  price_CGC_10: string;
  price_SGC_10: string;
  increase_Grade_7: number;
  increase_Grade_8: number;
  increase_Grade_9: number;
  increase_Grade_9_5: number;
  increase_PSA_10: number;
  increase_BGS_10: number;
  increase_CGC_10: number;
  increase_SGC_10: number;
};

const GRADED_PRICE_FIELDS = [
  ["Grade", 7, "7/7.5", "price_Grade_7", "increase_Grade_7"],
  ["Grade", 8, "8/8.5", "price_Grade_8", "increase_Grade_8"],
  ["Grade", 9, "9", "price_Grade_9", "increase_Grade_9"],
  ["Grade", 9.5, "9.5", "price_Grade_9_5", "increase_Grade_9_5"],
  ["PSA", 10, "10", "price_PSA_10", "increase_PSA_10"],
  ["BGS", 10, "10", "price_BGS_10", "increase_BGS_10"],
  ["CGC", 10, "10", "price_CGC_10", "increase_CGC_10"],
  ["SGC", 10, "10", "price_SGC_10", "increase_SGC_10"],
] as const satisfies ReadonlyArray<
  readonly [
    string,
    number,
    string,
    keyof TcgPriceHistoryRow,
    keyof TcgPriceHistoryRow,
  ]
>;

const CARD_SELECT = `
SELECT product_id, game_id, game, set_name, set_code, name, rarity, product_type_name
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
      const setClause = options.set_code ? "AND lower(set_code) = lower(?)" : "";
      const bindings = [
        ...effectiveSearchTerms.map((term) => `%${term}%`),
        ...(options.game ? [options.game] : []),
        ...(options.set_code ? [options.set_code] : []),
        pageSize,
        offset,
      ];
      const searchCatalog = (includeCardNumber: boolean) =>
        db
          .prepare(
            `${CARD_SELECT}
WHERE ${effectiveSearchTerms
  .map(
    () => `lower(
  coalesce(name, '') || ' ' ||
  ${includeCardNumber ? "coalesce(number, '') || ' ' ||" : ""}
  coalesce(set_name, '') || ' ' ||
  coalesce(set_code, '') || ' ' ||
  coalesce(rarity, '') || ' ' ||
  coalesce(game, '')
) LIKE ?`,
  )
  .join("\nAND ")}
${objectTypeClause}
${gameClause}
${setClause}
ORDER BY updated_at DESC, product_id ASC
LIMIT ? OFFSET ?`,
          )
          .bind(...bindings)
          .all<CardCatalogRow>();

      let results: D1Result<CardCatalogRow>;
      try {
        results = await searchCatalog(true);
      } catch (error) {
        if (!isMissingCardNumberColumn(error)) throw error;
        results = await searchCatalog(false);
      }

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
      const results = await db
        .prepare(
          `SELECT s.set_code,
                  s.name AS set_name,
                  s.game,
                  NULL AS image_url,
                  nullif(trim(s.set_image_id), '') AS image_card_ref,
                  coalesce(s.total_cards, 0) AS card_count
           FROM sets s
           WHERE lower(s.name || ' ' || coalesce(s.set_code, '')) LIKE ?
             AND trim(coalesce(s.set_code, '')) <> ''
             ${gameClause}
           ORDER BY s.name ASC
           LIMIT ? OFFSET ?`,
        )
        .bind(...bindings)
        .all<SetSearchResult>();

      return results.results ?? [];
    },

    async getCard(card_ref) {
      const row = await db
        .prepare(`${CARD_SELECT}WHERE product_id = ? LIMIT 1`)
        .bind(card_ref)
        .first<CardCatalogRow>();

      if (!row) return null;
      const numbers = await findCardNumbersByProductId(db, [row.product_id]);
      const skuRows = await findSkuRows(db, card_ref);
      const card = cardWithSearchPricing(
        row,
        skuRows,
        numbers.get(row.product_id) ?? "",
      );
      return {
        ...card,
        available_languages: uniqueSkuValues(
          skuRows,
          (sku) => sku.language_name ?? sku.language_code,
        ),
        available_finishes: uniqueSkuValues(
          skuRows,
          (sku) => sku.variant_name,
        ),
      };
    },

    async getPriceSeries(card_ref, grader, _grade, condition, days, finish) {
      if (grader !== "Raw") {
        return [];
      }

      const skuRows = filterSkusByFinish(await findSkuRows(db, card_ref), finish);
      const matchingRows = condition
        ? skuRows.filter((row) => skuMatchesCondition(row, condition))
        : skuRows;
      const selectedRow = preferredSearchSku(matchingRows);
      const points = selectedRow
        ? parsePriceHistory(selectedRow.price_history)
        : [];

      if (points.length > 0) return filterPointsByDays(points, days);
      if (skuRows.some((row) => parsePriceHistory(row.price_history).length > 0)) {
        return [];
      }
      return findUngradedFallbackSeries(db, card_ref, finish, days);
    },

    async getMarketPrices(card_ref, finish) {
      const skuRows = filterSkusByFinish(await findSkuRows(db, card_ref), finish);
      const prices: MarketPrice[] = [];

      for (const row of preferredMarketSkus(skuRows)) {
        const latest = latestPricePoint(parsePriceHistory(row.price_history));

        if (!latest) {
          continue;
        }

        prices.push({
          grader: "Raw",
          grade: null,
          condition: row.condition_name ?? row.condition_code,
          price: latest.price,
        });
      }

      if (prices.length === 0) {
        const fallback = await findUngradedFallbackMarketPrice(db, card_ref, finish);
        if (fallback) prices.push(fallback);
      }
      return [...prices, ...(await findGradedMarketPrices(db, card_ref, finish))];
    },

    async getTrending(options) {
      const page = options?.page ?? 1;
      const pageSize = options?.page_size ?? 10;
      const results = await db
        .prepare(
          `SELECT cards_all.product_id, cards_all.game_id, cards_all.game,
       cards_all.set_name, cards_all.set_code, cards_all.name,
       cards_all.rarity, cards_all.product_type_name,
       sku.sku_id, sku.condition_code, sku.condition_name,
       sku.language_code, sku.language_name, sku.variant_code,
       sku.variant_name, sku.price_Ungraded AS price_history,
       sku.increase_Ungraded AS increase_rate
FROM tcg_price AS sku INDEXED BY idx_tcg_price_increase_ungraded
JOIN cards_all
  ON cards_all.product_id = sku.product_id
WHERE sku.sku_id IS NOT NULL AND sku.increase_Ungraded IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM tcg_price AS better
    WHERE better.product_id = sku.product_id
      AND better.sku_id IS NOT NULL
      AND better.increase_Ungraded IS NOT NULL
      AND (
        better.increase_Ungraded > sku.increase_Ungraded
        OR (better.increase_Ungraded = sku.increase_Ungraded AND better.sku_id < sku.sku_id)
      )
  )
ORDER BY sku.increase_Ungraded DESC, sku.sku_id ASC
LIMIT ? OFFSET ?`,
        )
        .bind(pageSize, (page - 1) * pageSize)
        .all<TrendingRow>();

      return (results.results ?? []).map((row) => ({
        ...cardWithSkuPricing(row, row),
        price_change_1d_percent: row.increase_rate,
      }));
    },

    async getSoldListings(card_ref): Promise<SoldListing[]> {
      const card = await db
        .prepare(`${CARD_SELECT}WHERE product_id = ? LIMIT 1`)
        .bind(card_ref)
        .first<CardCatalogRow>();

      if (!card) {
        return [];
      }

      const skuRows = preferredMarketSkus(await findSkuRows(db, card_ref));

      return skuRows
        .map((row) => soldListingFromSku(card, row))
        .filter((listing): listing is SoldListing => listing !== null)
        .sort((left, right) => right.date.localeCompare(left.date))
        .slice(0, 4);
    },
  };
}

function soldListingFromSku(
  card: CardCatalogRow,
  sku: TcgPriceRow,
): SoldListing | null {
  const latest = latestPricePoint(parsePriceHistory(sku.price_history));

  if (!latest) {
    return null;
  }

  const title = [
    card.name ?? card.product_id,
    sku.condition_name ?? sku.condition_code,
    sku.language_name ?? sku.language_code,
    sku.variant_name ?? sku.variant_code,
  ]
    .filter((value): value is string => Boolean(value?.trim()))
    .join(" / ");

  return {
    date: latest.date,
    title,
    price: latest.price,
    platform: "TCGplayer",
    url: `https://www.tcgplayer.com/product/${encodeURIComponent(card.product_id)}`,
  };
}

async function cardsWithSearchPricing(
  db: D1Database,
  rows: CardCatalogRow[],
): Promise<CardSearchResult[]> {
  const skusByProductId = await findSkuRowsByProductId(
    db,
    rows.map((row) => row.product_id),
  );
  const numbersByProductId = await findCardNumbersByProductId(
    db,
    rows.map((row) => row.product_id),
  );

  return rows.map((row) =>
    cardWithSearchPricing(
      row,
      skusByProductId.get(row.product_id) ?? [],
      numbersByProductId.get(row.product_id) ?? "",
    ),
  );
}

function isMissingCardNumberColumn(error: unknown): boolean {
  const message = error instanceof Error ? error.message.toLowerCase() : "";
  return message.includes("no such column") && message.includes("number");
}

function cardWithSearchPricing(
  row: CardCatalogRow,
  skus: TcgPriceRow[],
  cardNumber: string,
): CardSearchResult {
  const card = cardFromRow(row, cardNumber);
  const sku = preferredSearchSku(skus);

  if (!sku) {
    return card;
  }

  return cardWithSkuPricing(row, sku, cardNumber);
}

function cardWithSkuPricing(
  row: CardCatalogRow,
  sku: SkuPricingRow,
  cardNumber = "",
): CardSearchResult {
  const card = cardFromRow(row, cardNumber);

  const series = filterPointsByDays(parsePriceHistory(sku.price_history), 30);
  const current = series.at(-1)?.price;
  const previous = series.length > 1 ? series[0]?.price : undefined;

  return {
    ...card,
    finish: sku.variant_name ?? sku.variant_code,
    language: sku.language_name ?? sku.language_code,
    ...(current === undefined ? {} : { price_usd: current }),
    ...(previous === undefined ? {} : { previous_30d_price_usd: previous }),
  };
}

async function findCardNumbersByProductId(
  db: D1Database,
  cardRefs: string[],
): Promise<Map<string, string>> {
  const numbersByProductId = new Map<string, string>();
  if (cardRefs.length === 0) return numbersByProductId;

  const placeholders = cardRefs.map(() => "?").join(", ");
  try {
    const results = await db
      .prepare(
        `SELECT product_id, number
         FROM cards_all
         WHERE product_id IN (${placeholders})`,
      )
      .bind(...cardRefs)
      .all<CardNumberRow>();
    for (const row of results.results ?? []) {
      const number = row.number?.trim();
      if (number) numbersByProductId.set(row.product_id, number);
    }
  } catch {
    // Older local catalogs predate the optional number column.
  }
  return numbersByProductId;
}

async function findSkuRowsByProductId(
  db: D1Database,
  cardRefs: string[],
): Promise<Map<string, TcgPriceRow[]>> {
  const productIds = cardRefs.filter((cardRef) => /^\d+$/.test(cardRef));
  const skusByProductId = new Map<string, TcgPriceRow[]>();
  if (productIds.length === 0) return skusByProductId;

  const placeholders = productIds.map(() => "?").join(", ");
  const results = await db
    .prepare(
      `SELECT sku_id, product_id, condition_code, condition_name, language_code,
              language_name, variant_code, variant_name,
              price_Ungraded AS price_history
       FROM tcg_price
       WHERE sku_id IS NOT NULL AND product_id IN (${placeholders})
       ORDER BY product_id, language_code, variant_code, condition_code`,
    )
    .bind(...productIds)
    .all<TcgPriceRow>();
  for (const sku of results.results ?? []) {
    const productId = sku.product_id;
    const productSkus = skusByProductId.get(productId);
    if (productSkus) {
      productSkus.push(sku);
    } else {
      skusByProductId.set(productId, [sku]);
    }
  }
  return skusByProductId;
}

function preferredSearchSku(rows: TcgPriceRow[]): TcgPriceRow | null {
  return (
    [...rows]
      .filter((row) => parsePriceHistory(row.price_history).length > 0)
      .sort(compareSkuPreference)[0] ?? null
  );
}

function uniqueSkuValues(
  rows: TcgPriceRow[],
  valueOf: (row: TcgPriceRow) => string | null,
): string[] {
  return [...new Set(rows.map(valueOf).map((value) => value?.trim()).filter(
    (value): value is string => Boolean(value),
  ))].sort((left, right) => left.localeCompare(right));
}

function preferredMarketSkus(rows: TcgPriceRow[]): TcgPriceRow[] {
  const rowsByCondition = new Map<string, TcgPriceRow>();

  for (const row of rows) {
    if (parsePriceHistory(row.price_history).length === 0) {
      continue;
    }
    const condition = (row.condition_code ?? row.condition_name ?? "unknown")
      .trim()
      .toLowerCase();
    const current = rowsByCondition.get(condition);

    if (
      !current ||
      searchSkuRank(row) < searchSkuRank(current) ||
      (searchSkuRank(row) === searchSkuRank(current) &&
        isFresherSku(row, current))
    ) {
      rowsByCondition.set(condition, row);
    }
  }

  return [...rowsByCondition.values()].sort(
    (left, right) =>
      marketConditionRank(left) - marketConditionRank(right) ||
      left.sku_id - right.sku_id,
  );
}

function marketConditionRank(row: TcgPriceRow): number {
  switch ((row.condition_code ?? "").trim().toUpperCase()) {
    case "NM":
      return 0;
    case "LP":
      return 1;
    case "MP":
      return 2;
    case "HP":
      return 3;
    case "DMG":
      return 4;
    default:
      return 5;
  }
}

function searchSkuRank(row: TcgPriceRow): number {
  return (
    (row.condition_code === "NM" ? 0 : 100) +
    (row.language_code === "EN" ? 0 : 10) +
    (row.variant_code === "N" ? 0 : 1)
  );
}

function compareSkuPreference(
  left: TcgPriceRow,
  right: TcgPriceRow,
): number {
  return (
    searchSkuRank(left) - searchSkuRank(right) ||
    latestPriceDate(right).localeCompare(latestPriceDate(left)) ||
    left.sku_id - right.sku_id
  );
}

function isFresherSku(
  candidate: TcgPriceRow,
  current: TcgPriceRow,
): boolean {
  const candidateDate = latestPriceDate(candidate);
  const currentDate = latestPriceDate(current);
  return candidateDate > currentDate ||
    (candidateDate === currentDate && candidate.sku_id < current.sku_id);
}

function latestPriceDate(row: TcgPriceRow): string {
  return latestPricePoint(parsePriceHistory(row.price_history))?.date ?? "";
}

async function findSkuRows(
  db: D1Database,
  cardRef: string,
): Promise<TcgPriceRow[]> {
  if (!/^\d+$/.test(cardRef)) {
    return [];
  }

  const results = await db
    .prepare(
      `SELECT sku_id, product_id, condition_code, condition_name, language_code,
              language_name, variant_code, variant_name,
              price_Ungraded AS price_history
       FROM tcg_price
       WHERE sku_id IS NOT NULL AND product_id = ?
       ORDER BY language_code, variant_code, condition_code`,
    )
    .bind(cardRef)
    .all<TcgPriceRow>();

  return results.results ?? [];
}

async function findGradedMarketPrices(
  db: D1Database,
  cardRef: string,
  finish?: string | null,
): Promise<MarketPrice[]> {
  if (!/^\d+$/.test(cardRef)) return [];

  let rows: TcgPriceHistoryRow[];
  try {
    const results = await db
      .prepare(
        `SELECT DISTINCT pricecharting_id, variant_name AS product_sub_type,
                price_Ungraded, increase_Ungraded,
                price_Grade_7, price_Grade_8, price_Grade_9, price_Grade_9_5,
                price_PSA_10, price_BGS_10, price_CGC_10, price_SGC_10,
                increase_Grade_7, increase_Grade_8, increase_Grade_9,
                increase_Grade_9_5, increase_PSA_10, increase_BGS_10,
                increase_CGC_10, increase_SGC_10
         FROM tcg_price
         WHERE product_id = ?
           AND (? IS NULL OR lower(trim(variant_name)) = lower(trim(?)))
         ORDER BY variant_name, pricecharting_id`,
      )
      .bind(cardRef, finish ?? null, finish ?? null)
      .all<TcgPriceHistoryRow>();
    rows = (results.results ?? []).filter((row) => historyMatchesFinish(row, finish));
  } catch (error) {
    console.error("Failed to load graded price history.", error);
    return [];
  }

  return rows.flatMap((row) =>
    GRADED_PRICE_FIELDS.flatMap(
      ([grader, grade, gradeLabel, historyField, increaseField]) => {
        const history = filterPointsByDays(
          parsePriceHistory(String(row[historyField] ?? "[]")),
          90,
        );
        const latest = history.at(-1);
        if (!latest) return [];

        const increase = Number(row[increaseField]);
        return [{
          grader,
          grade,
          grade_label: gradeLabel,
          condition: null,
          price: latest.price,
          pricecharting_id: row.pricecharting_id,
          product_sub_type: row.product_sub_type,
          increase_percent: Number.isFinite(increase) ? increase : 0,
          history,
        }];
      },
    ),
  );
}

function filterSkusByFinish(
  rows: TcgPriceRow[],
  finish?: string | null,
): TcgPriceRow[] {
  const normalized = finish?.trim().toLowerCase();
  if (!normalized) return rows;
  return rows.filter((row) =>
    [row.variant_name, row.variant_code].some(
      (value) => value?.trim().toLowerCase() === normalized,
    ),
  );
}

async function findUngradedFallbackSeries(
  db: D1Database,
  cardRef: string,
  finish: string | null | undefined,
  days: number,
): Promise<PricePoint[]> {
  const rows = await findPriceHistoryRows(db, cardRef, finish);
  for (const row of rows) {
    const history = parsePriceHistory(String(row.price_Ungraded ?? "[]"));
    if (history.length > 0) return filterPointsByDays(history, days);
  }
  return [];
}

async function findUngradedFallbackMarketPrice(
  db: D1Database,
  cardRef: string,
  finish?: string | null,
): Promise<MarketPrice | null> {
  const rows = await findPriceHistoryRows(db, cardRef, finish);
  for (const row of rows) {
    const history = filterPointsByDays(
      parsePriceHistory(String(row.price_Ungraded ?? "[]")),
      90,
    );
    const latest = history.at(-1);
    if (!latest) continue;
    const increase = Number(row.increase_Ungraded);
    return {
      grader: "Raw",
      grade: null,
      condition: "Ungraded",
      price: latest.price,
      product_sub_type: row.product_sub_type,
      increase_percent: Number.isFinite(increase) ? increase : 0,
      history,
    };
  }
  return null;
}

async function findPriceHistoryRows(
  db: D1Database,
  cardRef: string,
  finish?: string | null,
): Promise<TcgPriceHistoryRow[]> {
  if (!/^\d+$/.test(cardRef)) return [];
  try {
    const result = await db.prepare(
      `SELECT DISTINCT pricecharting_id, variant_name AS product_sub_type,
              price_Ungraded, increase_Ungraded
       FROM tcg_price
       WHERE product_id = ?
         AND (? IS NULL OR lower(trim(variant_name)) = lower(trim(?)))
       ORDER BY variant_name, pricecharting_id`,
    ).bind(cardRef, finish ?? null, finish ?? null).all<TcgPriceHistoryRow>();
    return (result.results ?? []).filter((row) => historyMatchesFinish(row, finish));
  } catch (error) {
    console.error("Failed to load ungraded price history.", error);
    return [];
  }
}

function historyMatchesFinish(
  row: TcgPriceHistoryRow,
  finish?: string | null,
): boolean {
  const normalized = finish?.trim().toLowerCase();
  return !normalized || row.product_sub_type?.trim().toLowerCase() === normalized;
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

function objectTypeFromProductType(
  productType: string | null,
): CardObjectType {
  if (productType === "Cards") {
    return "tcg";
  }

  if (!productType) {
    return "other";
  }

  return "sealed";
}

function objectTypeWhereClause(objectType: CardObjectType | undefined): string {
  switch (objectType) {
    case "tcg":
      return "AND product_type_name = 'Cards'";
    case "sealed":
      return "AND product_type_name IS NOT NULL AND product_type_name <> 'Cards'";
    case "other":
      return "AND product_type_name IS NULL";
    case "sports":
      return "AND 0 = 1";
    default:
      return "";
  }
}

function parsePriceHistory(value: string): PriceHistoryEntry[] {
  try {
    const parsed = JSON.parse(value);

    if (!Array.isArray(parsed)) {
      return [];
    }

    return parsed
      .map((entry) => {
        if (!isRecord(entry) || typeof entry.date !== "string") {
          return null;
        }

        const price = Number(entry.price);

        return Number.isFinite(price) && entry.date.length > 0
          ? { date: entry.date, price }
          : null;
      })
      .filter((entry): entry is PriceHistoryEntry => entry !== null);
  } catch {
    return [];
  }
}

function latestPricePoint(
  points: PriceHistoryEntry[],
): PriceHistoryEntry | null {
  return points.sort((left, right) => left.date.localeCompare(right.date)).at(-1) ?? null;
}

function filterPointsByDays(
  points: PriceHistoryEntry[],
  days: number,
): PricePoint[] {
  const sorted = [...points].sort((left, right) =>
    left.date.localeCompare(right.date),
  );
  const latest = sorted.at(-1) ?? null;

  if (!latest) {
    return [];
  }

  const cutoff = new Date(`${latest.date}T00:00:00.000Z`);
  cutoff.setUTCDate(cutoff.getUTCDate() - Math.max(days, 1));

  const inRange = sorted.filter(
    (point) => new Date(`${point.date}T00:00:00.000Z`) >= cutoff,
  );
  const baseline = sorted
    .filter((point) => new Date(`${point.date}T00:00:00.000Z`) < cutoff)
    .at(-1);

  return [...(baseline ? [baseline] : []), ...inRange].map((point) => ({
    date: point.date,
    price: point.price,
  }));
}

function skuMatchesCondition(
  row: TcgPriceRow,
  condition: string,
): boolean {
  const normalized = condition.trim().toLowerCase();

  return [row.condition_name, row.condition_code]
    .filter(Boolean)
    .some((value) => value!.trim().toLowerCase() === normalized);
}

function positiveIntegerOrDefault(
  value: number | undefined,
  fallback: number,
): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : fallback;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
