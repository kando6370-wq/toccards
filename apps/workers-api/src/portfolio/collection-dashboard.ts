import {
  groupSkus,
  loadCards,
  loadSkus,
  matchingPrice,
  priceOnDate,
  type CardRow,
  type SkuRow,
} from "./valuation-history";
import { cardImageUrl } from "../card-image-url";

export type DashboardPortfolioRow = {
  id: string;
  folder_id: string;
  card_ref: string;
  object_type: string;
  grader: string;
  condition: string | null;
  grade: number | null;
  language: string | null;
  finish: string | null;
  quantity: number;
  folder_joined_at: string;
  created_at: string;
};

export type DashboardWishlistRow = {
  id: string;
  card_ref: string;
  created_at: string;
};

export async function enrichCollectionDashboard(
  db: D1Database,
  portfolio: DashboardPortfolioRow[],
  wishlist: DashboardWishlistRow[],
  now = new Date(),
) {
  const refs = [...new Set([
    ...portfolio.map((item) => item.card_ref),
    ...wishlist.map((item) => item.card_ref),
  ])];
  const currentDate = now.toISOString().slice(0, 10);
  const baseline = new Date(`${currentDate}T00:00:00.000Z`);
  baseline.setUTCDate(baseline.getUTCDate() - 30);
  const baselineDate = baseline.toISOString().slice(0, 10);
  const [cards, skus] = await Promise.all([
    loadCards(db, refs),
    loadSkus(db, refs, baselineDate, currentDate),
  ]);
  const cardsByRef = new Map(cards.map((card) => [card.product_id, card]));
  const skusByRef = groupSkus(skus);

  return {
    portfolio_items: portfolio.map((item) => {
      const matched = matchingPrice(item, skusByRef.get(item.card_ref) ?? []);
      return presentation(
        item,
        cardsByRef.get(item.card_ref),
        matched?.row ?? null,
        currentDate,
        baselineDate,
        matched?.history ?? null,
        matched?.increaseRate ?? null,
      );
    }),
    wishlist_items: wishlist.map((item) => {
      const rows = skusByRef.get(item.card_ref) ?? [];
      const sku = wishlistSku(rows);
      return presentation(
        item,
        cardsByRef.get(item.card_ref),
        sku,
        currentDate,
        baselineDate,
        null,
        sku?.increase_rate ?? null,
      );
    }),
  };
}

function presentation(
  item: DashboardPortfolioRow | DashboardWishlistRow,
  card: CardRow | undefined,
  sku: SkuRow | null,
  currentDate: string,
  baselineDate: string,
  priceHistory: string | null = null,
  increasePercent: number | null = null,
) {
  return {
    ...item,
    name: card?.name ?? item.card_ref,
    set_name: card?.set_name ?? "Card data unavailable",
    card_number: card?.number ?? "",
    rarity: card?.rarity ?? "",
    game: card?.game ?? "Unknown",
    image_url: cardImageUrl(item.card_ref, "thumbnail"),
    market_price_usd: priceHistory
      ? priceOnDate(priceHistory, currentDate)
      : sku ? priceOnDate(sku.price_history, currentDate) : null,
    previous_30d_price_usd: priceHistory
      ? priceOnDate(priceHistory, baselineDate)
      : sku ? priceOnDate(sku.price_history, baselineDate) : null,
    increase_percent:
      increasePercent !== null && Number.isFinite(increasePercent)
        ? increasePercent
        : null,
    market_language: sku?.language_name ?? null,
    market_finish: sku?.variant_name ?? null,
    market_condition: sku?.condition_name ?? null,
  };
}

function wishlistSku(rows: SkuRow[]): SkuRow | null {
  const priced = rows.filter((row) =>
    row.grader_code.trim().toUpperCase() === "RAW"
    && priceOnDate(row.price_history, "9999-12-31") !== null
  );
  return priced.find((row) => [row.condition_code, row.condition_name]
    .some((value) => normalized(value) === "near mint" || normalized(value) === "nm"))
    ?? priced[0]
    ?? null;
}

function normalized(value: string | null): string {
  return (value ?? "").trim().toLowerCase();
}
