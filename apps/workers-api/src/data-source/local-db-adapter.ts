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

type TcgplayerSkuRow = {
  sku_id: number;
  product_id: number;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  price_history: string;
};

type PriceHistoryEntry = {
  date: string;
  price: number;
};

const CARD_SELECT = `
SELECT product_id, game_id, game, set_name, set_code, name, rarity, product_type_name
FROM cards_all
`;

export function createLocalDbDataSourceAdapter(db: D1Database): DataSourceAdapter {
  return {
    async searchCards(query, options = {}) {
      const normalizedQuery = query.trim().toLowerCase();
      const page = positiveIntegerOrDefault(options.page, 1);
      const pageSize = positiveIntegerOrDefault(options.page_size, 20);
      const offset = (page - 1) * pageSize;
      const objectTypeClause = objectTypeWhereClause(options.object_type);
      const gameClause = options.game ? "AND lower(game) = lower(?)" : "";
      const setClause = options.set_code ? "AND lower(set_code) = lower(?)" : "";
      const bindings = [
        `%${normalizedQuery}%`,
        ...(options.game ? [options.game] : []),
        ...(options.set_code ? [options.set_code] : []),
        pageSize,
        offset,
      ];
      const results = await db
        .prepare(
          `${CARD_SELECT}
WHERE lower(
  coalesce(name, '') || ' ' ||
  coalesce(set_name, '') || ' ' ||
  coalesce(set_code, '') || ' ' ||
  coalesce(rarity, '') || ' ' ||
  coalesce(game, '')
) LIKE ?
${objectTypeClause}
${gameClause}
${setClause}
ORDER BY updated_at DESC, product_id ASC
LIMIT ? OFFSET ?`,
        )
        .bind(...bindings)
        .all<CardCatalogRow>();

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
                  nullif(trim(s.product_id), '') AS image_card_ref,
                  coalesce(s.total_cards, 0) AS card_count
           FROM sets s
           WHERE lower(s.name || ' ' || coalesce(s.set_code, '')) LIKE ?
             AND trim(coalesce(s.set_code, '')) <> ''
             ${gameClause}
           ORDER BY coalesce(s.release_date, '') DESC, s.name ASC
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

      return row ? cardFromRow(row) : null;
    },

    async getPriceSeries(card_ref, grader, _grade, condition, days) {
      if (grader !== "Raw") {
        return [];
      }

      const skuRows = await findSkuRows(db, card_ref);
      const matchingRows = condition
        ? skuRows.filter((row) => skuMatchesCondition(row, condition))
        : skuRows;
      const selectedRow = preferredSearchSku(matchingRows);
      const points = selectedRow
        ? parsePriceHistory(selectedRow.price_history)
        : [];

      return filterPointsByDays(points, days);
    },

    async getMarketPrices(card_ref) {
      const skuRows = await findSkuRows(db, card_ref);
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

      return prices;
    },

    async getTrending() {
      const results = await db
        .prepare(
          `${CARD_SELECT}
WHERE EXISTS (
  SELECT 1 FROM tcgplayer_skus
  WHERE tcgplayer_skus.product_id = CAST(cards_all.product_id AS INTEGER)
)
ORDER BY updated_at DESC, product_id ASC
LIMIT 100`,
        )
        .all<CardCatalogRow>();
      const rows = results.results ?? [];
      const skusByProductId = await findSkuRowsByProductId(
        db,
        rows.map((row) => row.product_id),
      );

      return rows
        .map((row) => {
          const skus = skusByProductId.get(row.product_id) ?? [];
          const sku = preferredSearchSku(skus);
          return { row, skus, trend: sku ? oneDayTrend(sku) : null };
        })
        .sort(
          (left, right) =>
            Number(left.trend === null) - Number(right.trend === null) ||
            (right.trend?.percent ?? 0) - (left.trend?.percent ?? 0) ||
            left.row.product_id.localeCompare(right.row.product_id),
        )
        .slice(0, 10)
        .map(({ row, skus, trend }) => ({
          ...cardWithSearchPricing(row, skus),
          ...(trend === null
            ? {}
            : {
                previous_1d_price_usd: trend.previous,
                price_change_1d_percent: trend.percent,
                price_as_of: trend.currentDate,
                previous_price_as_of: trend.previousDate,
              }),
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
        .slice(0, 4);
    },
  };
}

function soldListingFromSku(
  card: CardCatalogRow,
  sku: TcgplayerSkuRow,
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

  return rows.map((row) =>
    cardWithSearchPricing(row, skusByProductId.get(row.product_id) ?? []),
  );
}

function cardWithSearchPricing(
  row: CardCatalogRow,
  skus: TcgplayerSkuRow[],
): CardSearchResult {
  const card = cardFromRow(row);
  const sku = preferredSearchSku(skus);

  if (!sku) {
    return card;
  }

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

async function findSkuRowsByProductId(
  db: D1Database,
  cardRefs: string[],
): Promise<Map<string, TcgplayerSkuRow[]>> {
  const productIds = cardRefs
    .filter((cardRef) => /^\d+$/.test(cardRef))
    .map(Number);
  const skusByProductId = new Map<string, TcgplayerSkuRow[]>();
  if (productIds.length === 0) return skusByProductId;

  const placeholders = productIds.map(() => "?").join(", ");
  const results = await db
    .prepare(
      `SELECT sku_id, product_id, condition_code, condition_name, language_code,
              language_name, variant_code, variant_name, price_history
       FROM tcgplayer_skus
       WHERE product_id IN (${placeholders})
       ORDER BY product_id, language_code, variant_code, condition_code`,
    )
    .bind(...productIds)
    .all<TcgplayerSkuRow>();
  for (const sku of results.results ?? []) {
    const productId = String(sku.product_id);
    const productSkus = skusByProductId.get(productId);
    if (productSkus) {
      productSkus.push(sku);
    } else {
      skusByProductId.set(productId, [sku]);
    }
  }
  return skusByProductId;
}

function preferredSearchSku(rows: TcgplayerSkuRow[]): TcgplayerSkuRow | null {
  return (
    [...rows]
      .filter((row) => parsePriceHistory(row.price_history).length > 0)
      .sort(compareSkuPreference)[0] ?? null
  );
}

function preferredMarketSkus(rows: TcgplayerSkuRow[]): TcgplayerSkuRow[] {
  const rowsByCondition = new Map<string, TcgplayerSkuRow>();

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

function marketConditionRank(row: TcgplayerSkuRow): number {
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

function searchSkuRank(row: TcgplayerSkuRow): number {
  return (
    (row.condition_code === "NM" ? 0 : 100) +
    (row.language_code === "EN" ? 0 : 10) +
    (row.variant_code === "N" ? 0 : 1)
  );
}

function compareSkuPreference(
  left: TcgplayerSkuRow,
  right: TcgplayerSkuRow,
): number {
  return (
    searchSkuRank(left) - searchSkuRank(right) ||
    latestPriceDate(right).localeCompare(latestPriceDate(left)) ||
    left.sku_id - right.sku_id
  );
}

function isFresherSku(
  candidate: TcgplayerSkuRow,
  current: TcgplayerSkuRow,
): boolean {
  const candidateDate = latestPriceDate(candidate);
  const currentDate = latestPriceDate(current);
  return candidateDate > currentDate ||
    (candidateDate === currentDate && candidate.sku_id < current.sku_id);
}

function latestPriceDate(row: TcgplayerSkuRow): string {
  return latestPricePoint(parsePriceHistory(row.price_history))?.date ?? "";
}

async function findSkuRows(
  db: D1Database,
  cardRef: string,
): Promise<TcgplayerSkuRow[]> {
  if (!/^\d+$/.test(cardRef)) {
    return [];
  }

  const results = await db
    .prepare(
      `SELECT sku_id, product_id, condition_code, condition_name, language_code,
              language_name, variant_code, variant_name, price_history
       FROM tcgplayer_skus
       WHERE product_id = ?
       ORDER BY language_code, variant_code, condition_code`,
    )
    .bind(Number(cardRef))
    .all<TcgplayerSkuRow>();

  return results.results ?? [];
}

function cardFromRow(row: CardCatalogRow): CardSearchResult {
  return {
    card_ref: row.product_id,
    name: row.name ?? row.product_id,
    game: row.game,
    set_name: row.set_name ?? "",
    set_code: row.set_code ?? "",
    card_number: "",
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

function oneDayTrend(row: TcgplayerSkuRow): {
  currentDate: string;
  previousDate: string;
  previous: number;
  percent: number;
} | null {
  const points = parsePriceHistory(row.price_history).sort((left, right) =>
    left.date.localeCompare(right.date),
  );
  const current = points.at(-1);
  if (!current) return null;

  const cutoff = new Date(`${current.date}T00:00:00.000Z`);
  cutoff.setUTCDate(cutoff.getUTCDate() - 1);
  const previous = points
    .filter((point) => new Date(`${point.date}T00:00:00.000Z`) <= cutoff)
    .at(-1);
  if (!previous || previous.price <= 0) return null;

  return {
    currentDate: current.date,
    previousDate: previous.date,
    previous: previous.price,
    percent: ((current.price - previous.price) / previous.price) * 100,
  };
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
  row: TcgplayerSkuRow,
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
