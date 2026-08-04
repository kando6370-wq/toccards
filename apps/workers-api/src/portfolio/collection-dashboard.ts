import {
  groupSkus,
  loadCards,
  loadSkus,
  matchingSku,
  priceOnDate,
  type CardRow,
  type SkuRow,
} from "./valuation-history";
import { cardImageUrl } from "../card-image-url";
import type { MarketPrice } from "../data-source/adapter";
import { createLocalDbDataSourceAdapter } from "../data-source/local-db-adapter";

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
  const [cards, skus] = await Promise.all([loadCards(db, refs), loadSkus(db, refs)]);
  const cardsByRef = new Map(cards.map((card) => [card.product_id, card]));
  const skusByRef = groupSkus(skus);
  const gradedPricesByCard = await loadGradedPrices(db, portfolio);
  const currentDate = now.toISOString().slice(0, 10);
  const baseline = new Date(`${currentDate}T00:00:00.000Z`);
  baseline.setUTCDate(baseline.getUTCDate() - 30);
  const baselineDate = baseline.toISOString().slice(0, 10);

  return {
    portfolio_items: portfolio.map((item) => {
      if (normalized(item.grader) !== "raw") {
        const price = matchingGradedPrice(
          item,
          gradedPricesByCard.get(gradedPriceKey(item.card_ref, item.finish)) ?? [],
        );
        return presentation(
          item,
          cardsByRef.get(item.card_ref),
          null,
          currentDate,
          baselineDate,
          price,
        );
      }
      const sku = matchingSku(item, skusByRef.get(item.card_ref) ?? []);
      return presentation(item, cardsByRef.get(item.card_ref), sku, currentDate, baselineDate);
    }),
    wishlist_items: wishlist.map((item) => {
      const rows = skusByRef.get(item.card_ref) ?? [];
      const sku = wishlistSku(rows);
      return presentation(item, cardsByRef.get(item.card_ref), sku, currentDate, baselineDate);
    }),
  };
}

function presentation(
  item: DashboardPortfolioRow | DashboardWishlistRow,
  card: CardRow | undefined,
  sku: SkuRow | null,
  currentDate: string,
  baselineDate: string,
  gradedPrice: MarketPrice | null = null,
) {
  return {
    ...item,
    name: card?.name ?? item.card_ref,
    set_name: card?.set_name ?? "Card data unavailable",
    card_number: card?.number ?? "",
    rarity: card?.rarity ?? "",
    game: card?.game ?? "Unknown",
    image_url: cardImageUrl(item.card_ref, "thumbnail"),
    market_price_usd: gradedPrice?.price ?? (sku ? priceOnDate(sku.price_history, currentDate) : null),
    previous_30d_price_usd: gradedPrice
      ? priceFromPoints(gradedPrice.history, baselineDate)
      : sku
        ? priceOnDate(sku.price_history, baselineDate)
        : null,
    market_language: sku?.language_name ?? null,
    market_finish: gradedPrice?.product_sub_type ?? sku?.variant_name ?? null,
    market_condition: gradedPrice?.condition ?? sku?.condition_name ?? null,
  };
}

async function loadGradedPrices(
  db: D1Database,
  portfolio: DashboardPortfolioRow[],
): Promise<Map<string, MarketPrice[]>> {
  const adapter = createLocalDbDataSourceAdapter(db);
  const targets = new Map<string, { cardRef: string; finish: string | null }>();
  for (const item of portfolio) {
    if (normalized(item.grader) === "raw") continue;
    targets.set(gradedPriceKey(item.card_ref, item.finish), {
      cardRef: item.card_ref,
      finish: item.finish,
    });
  }
  const entries = await Promise.all(
    [...targets].map(async ([key, target]) => [
      key,
      await adapter.getMarketPrices(target.cardRef, target.finish),
    ] as const),
  );
  return new Map(entries);
}

function gradedPriceKey(cardRef: string, finish: string | null): string {
  return `${cardRef}\u0000${normalized(finish)}`;
}

function matchingGradedPrice(
  item: Pick<DashboardPortfolioRow, "grader" | "grade">,
  prices: MarketPrice[],
): MarketPrice | null {
  return prices.find((price) =>
    normalized(price.grader) === normalized(item.grader)
      && price.grade === item.grade
      && price.price !== null
  ) ?? null;
}

function priceFromPoints(
  points: MarketPrice["history"],
  date: string,
): number | null {
  return points?.filter((point) => point.date <= date).at(-1)?.price ?? null;
}

function wishlistSku(rows: SkuRow[]): SkuRow | null {
  const priced = rows.filter((row) => priceOnDate(row.price_history, "9999-12-31") !== null);
  return priced.find((row) => [row.condition_code, row.condition_name]
    .some((value) => normalized(value) === "near mint" || normalized(value) === "nm"))
    ?? priced[0]
    ?? null;
}

function normalized(value: string | null): string {
  return (value ?? "").trim().toLowerCase();
}
