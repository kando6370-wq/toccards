import type {
  CardObjectType,
  CardSearchResult,
  DataSourceAdapter,
  MarketPrice,
  PricePoint,
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
  image_url: string | null;
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
SELECT product_id, game_id, game, set_name, set_code, name, rarity, product_type_name, image_url
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
ORDER BY updated_at DESC, product_id ASC
LIMIT ? OFFSET ?`,
        )
        .bind(`%${normalizedQuery}%`, pageSize, offset)
        .all<CardCatalogRow>();

      return (results.results ?? []).map(cardFromRow);
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
      const points = matchingRows
        .flatMap((row) => parsePriceHistory(row.price_history))
        .sort((left, right) => left.date.localeCompare(right.date));

      return filterPointsByDays(points, days);
    },

    async getMarketPrices(card_ref) {
      const skuRows = await findSkuRows(db, card_ref);
      const prices: MarketPrice[] = [];

      for (const row of skuRows) {
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
      return [];
    },

    async getSoldListings(): Promise<SoldListing[]> {
      return [];
    },
  };
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
    set_name: row.set_name ?? "",
    set_code: row.set_code ?? "",
    card_number: "",
    finish: null,
    language: null,
    object_type: objectTypeFromProductType(row.product_type_name),
    image_url: row.image_url,
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
  const latest = latestPricePoint([...points]);

  if (!latest) {
    return [];
  }

  const cutoff = new Date(`${latest.date}T00:00:00.000Z`);
  cutoff.setUTCDate(cutoff.getUTCDate() - Math.max(days, 1));

  return points
    .filter((point) => new Date(`${point.date}T00:00:00.000Z`) >= cutoff)
    .map((point) => ({ date: point.date, price: point.price }));
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
