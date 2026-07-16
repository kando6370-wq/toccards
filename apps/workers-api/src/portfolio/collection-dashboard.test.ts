import { describe, expect, it } from "vitest";
import { enrichCollectionDashboard } from "./collection-dashboard";

class FakeDb {
  constructor(
    readonly cards: Record<string, unknown>[],
    readonly skus: Record<string, unknown>[],
  ) {}

  prepare(sql: string) {
    const rows = sql.includes("FROM cards_all") ? this.cards : this.skus;
    return {
      bind: (..._args: unknown[]) => ({
        all: async <T>() => ({ results: rows as T[] }),
      }),
    };
  }
}

describe("collection dashboard enrichment", () => {
  it("returns every owned row and prices only its saved state because Collection must not truncate or substitute variants", async () => {
    const portfolio = Array.from({ length: 101 }, (_, index) => ({
      id: `item-${index}`,
      folder_id: "main",
      card_ref: "100",
      object_type: "tcg",
      grader: index === 100 ? "PSA" : "Raw",
      condition: index === 100 ? null : "Near Mint (NM)",
      grade: index === 100 ? 10 : null,
      language: "English",
      finish: "Normal",
      quantity: 1,
      created_at: "2026-07-01T00:00:00.000Z",
    }));
    const result = await enrichCollectionDashboard(
      new FakeDb([card("100")], [sku(100)]) as unknown as D1Database,
      portfolio,
      [{ id: "wish-1", card_ref: "100", created_at: "2026-07-02T00:00:00.000Z" }],
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(result.portfolio_items).toHaveLength(101);
    expect(result.portfolio_items[0]).toMatchObject({
      name: "Server Card",
      market_price_usd: 20,
      previous_30d_price_usd: 10,
    });
    expect(result.portfolio_items[100]).toMatchObject({
      grader: "PSA",
      market_price_usd: null,
      previous_30d_price_usd: null,
    });
    expect(result.wishlist_items[0]).toMatchObject({
      market_price_usd: 20,
      market_condition: "Near Mint",
    });
  });
});

function card(productId: string) {
  return {
    product_id: productId,
    game: "Pokemon",
    name: "Server Card",
    set_name: "Server Set",
    image_url: "https://img.example/card.jpg",
  };
}

function sku(productId: number) {
  return {
    sku_id: 1,
    product_id: productId,
    condition_code: "NM",
    condition_name: "Near Mint",
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: "Normal",
    price_history: JSON.stringify([
      { date: "2026-06-01", price: 10 },
      { date: "2026-07-06", price: 20 },
    ]),
  };
}
