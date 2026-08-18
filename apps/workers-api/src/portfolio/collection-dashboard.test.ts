import { describe, expect, it } from "vitest";
import { enrichCollectionDashboard } from "./collection-dashboard";

class FakeDb {
  constructor(
    readonly cards: Record<string, unknown>[],
    readonly skus: Record<string, unknown>[],
    readonly gradedPrices: Record<string, unknown>[] = [],
  ) {}

  prepare(sql: string) {
    const prices = [...this.skus, ...this.gradedPrices];
    const rows = sql.includes("FROM price_history_month AS history")
      ? prices.map((row) => ({
        series_id: row.series_id,
        points_json: row.price_history,
      }))
      : sql.includes("FROM cards_all")
      ? this.cards
      : prices;
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
      price_series_id: null,
      quantity: 1,
      folder_joined_at: "2026-07-01T00:00:00.000Z",
      created_at: "2026-07-01T00:00:00.000Z",
    }));
    const result = await enrichCollectionDashboard(
      new FakeDb(
        [card("100")],
        [sku("100")],
        [gradedPrice("100", "Normal", 4357.94)],
      ) as unknown as D1Database,
      portfolio,
      [{ id: "wish-1", card_ref: "100", created_at: "2026-07-02T00:00:00.000Z" }],
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(result.portfolio_items).toHaveLength(101);
    expect(result.portfolio_items[0]).toMatchObject({
      name: "Server Card",
      card_number: "025",
      rarity: "Rare Holo",
      image_url: "https://image.tcgcard.fun/cards/100.jpg",
      market_price_usd: 20,
      previous_30d_price_usd: 10,
      increase_percent: 12.34,
    });
    expect(result.portfolio_items[100]).toMatchObject({
      grader: "PSA",
      market_price_usd: 4357.94,
      previous_30d_price_usd: null,
    });
    expect(result.wishlist_items[0]).toMatchObject({
      market_price_usd: 20,
      market_condition: "Near Mint",
    });
  });

  it("values legacy Unknown qualifiers as unspecified because the client displayed English Normal while persisting Unknown", async () => {
    const baseItem = {
      id: "legacy-item",
      folder_id: "main",
      card_ref: "100",
      object_type: "tcg",
      grader: "Raw",
      condition: "Moderately Played (MP)",
      grade: null,
      language: "Unknown",
      finish: "Unknown",
      price_series_id: null,
      quantity: 1,
      folder_joined_at: "2026-07-01T00:00:00.000Z",
      created_at: "2026-07-01T00:00:00.000Z",
    };
    const result = await enrichCollectionDashboard(
      new FakeDb(
        [card("100")],
        [sku("100", "MP", "Moderately Played", 11.23)],
      ) as unknown as D1Database,
      [baseItem, { ...baseItem, id: "explicit-item", language: "Japanese" }],
      [],
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(result.portfolio_items[0]).toMatchObject({
      market_price_usd: 11.23,
      market_condition: "Moderately Played",
      market_language: "English",
      market_finish: "Normal",
    });
    expect(result.portfolio_items[1]).toMatchObject({
      market_price_usd: null,
      market_language: null,
      market_finish: null,
    });
  });

  it("maps PSA 7.5 to Grade 7 because saved grader labels must select the shared database price bucket", async () => {
    const item = {
      id: "graded-item",
      folder_id: "main",
      card_ref: "100",
      object_type: "tcg",
      grader: "PSA",
      condition: null,
      grade: 7.5,
      language: "English",
      finish: "Normal",
      price_series_id: null,
      quantity: 2,
      folder_joined_at: "2026-07-01T00:00:00.000Z",
      created_at: "2026-07-01T00:00:00.000Z",
    };
    const result = await enrichCollectionDashboard(
      new FakeDb(
        [card("100")],
        [],
        [gradedPrice("100", "Normal", 75, {
          grade_min_x10: 70,
          grade_max_x10: 75,
          price_history: JSON.stringify([
            { date: "2026-07-09", price: 70 },
            { date: "2026-07-10", price: 75 },
          ]),
          observed_on: "2026-07-10",
          amount_micros: 75_000_000,
        })],
      ) as unknown as D1Database,
      [item],
      [],
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(result.portfolio_items[0]).toMatchObject({
      market_price_usd: 75,
      market_language: "English",
      market_finish: "Normal",
    });
  });

  it("uses the saved series without exposing its internal id because Dashboard must keep the public API stable", async () => {
    const result = await enrichCollectionDashboard(
      new FakeDb(
        [card("100")],
        [sku("100")],
        [gradedPrice("100", "Normal", 99)],
      ) as unknown as D1Database,
      [{
        id: "stable-item",
        folder_id: "main",
        card_ref: "100",
        object_type: "tcg",
        grader: "Raw",
        condition: "Near Mint (NM)",
        grade: null,
        language: "English",
        finish: "Normal",
        price_series_id: 2,
        quantity: 1,
        folder_joined_at: "2026-07-01T00:00:00.000Z",
        created_at: "2026-07-01T00:00:00.000Z",
      }],
      [],
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(result.portfolio_items[0]).toMatchObject({ market_price_usd: 99 });
    expect(result.portfolio_items[0]).not.toHaveProperty("price_series_id");
  });
});

function card(productId: string) {
  return {
    product_id: productId,
    game: "Pokemon",
    name: "Server Card",
    set_name: "Server Set",
    number: "025",
    rarity: "Rare Holo",
  };
}

function gradedPrice(
  productId: string,
  finish: string,
  price: number,
  overrides: Record<string, unknown> = {},
) {
  return {
    series_id: 2,
    source_code: "pricecharting",
    source_record_id: "graded-1",
    metric_code: "psa_100",
    product_id: productId,
    condition_code: null,
    condition_name: null,
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: finish,
    grader_code: "PSA",
    grade_min_x10: 100,
    grade_max_x10: 100,
    observed_on: "2026-07-06",
    amount_micros: price * 1_000_000,
    baseline_1d_on: null,
    baseline_1d_amount_micros: null,
    baseline_7d_on: null,
    baseline_7d_amount_micros: null,
    baseline_30d_on: null,
    baseline_30d_amount_micros: null,
    price_history: JSON.stringify([{ date: "2026-07-06", price }]),
    change_1d_percent: null,
    change_7d_percent: null,
    change_30d_percent: null,
    ...overrides,
  };
}

function sku(
  productId: string,
  conditionCode = "NM",
  conditionName = "Near Mint",
  currentPrice = 20,
) {
  return {
    sku_id: 1,
    series_id: 1,
    source_code: "tcgplayer",
    source_record_id: "sku-1",
    metric_code: "ungraded",
    product_id: productId,
    condition_code: conditionCode,
    condition_name: conditionName,
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: "Normal",
    grader_code: "RAW",
    grade_min_x10: null,
    grade_max_x10: null,
    observed_on: "2026-07-06",
    amount_micros: currentPrice * 1_000_000,
    baseline_1d_on: null,
    baseline_1d_amount_micros: null,
    baseline_7d_on: null,
    baseline_7d_amount_micros: null,
    baseline_30d_on: "2026-06-01",
    baseline_30d_amount_micros: 10_000_000,
    price_history: JSON.stringify([
      { date: "2026-06-01", price: 10 },
      { date: "2026-07-06", price: currentPrice },
    ]),
    change_1d_percent: null,
    change_7d_percent: null,
    change_30d_percent: 12.34,
  };
}
