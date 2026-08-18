import { describe, expect, it } from "vitest";
import { loadSkus, loadValuationHistory, matchingPrice } from "./valuation-history";

class FakeDb {
  constructor(
    readonly events: Record<string, unknown>[],
    readonly skus: Record<string, unknown>[],
    readonly cards: Record<string, unknown>[],
  ) {}
  readonly bindings: Array<{ sql: string; values: unknown[] }> = [];

  prepare(sql: string) {
    const rows = sql.includes("collection_item_event")
      ? this.events
      : sql.includes("FROM price_history_month AS history")
        ? this.skus.map((row) => ({
          series_id: row.series_id,
          points_json: row.price_history,
        }))
      : sql.includes("FROM cards_all")
        ? this.cards
        : this.skus;
    return {
      bind: (...values: unknown[]) => {
        this.bindings.push({ sql, values });
        return {
          all: async <T>() => ({ results: rows as T[] }),
        };
      },
    };
  }
}

describe("portfolio valuation history", () => {
  it("binds every text card reference because PostgreSQL price_series.card_ref is not numeric-only", async () => {
    const db = new FakeDb([], [], []);

    await loadSkus(db as unknown as D1Database, ["100", "200", "custom-card"]);

    expect(db.bindings).toEqual([
      expect.objectContaining({ values: ["100", "200", "custom-card"] }),
    ]);
  });

  it("distinguishes an empty folder from holdings without PostgreSQL prices because Home must not infer holdings from Most Valuable", async () => {
    const db = new FakeDb(
      [event("a1", "item-a", "main", "100", "upsert", "2026-07-01T00:00:00.000Z", 1)],
      [],
      [card("100", "Unpriced Card")],
    );

    const [main, empty] = await loadValuationHistory(
      db as unknown as D1Database,
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      ["main", "empty"],
      1,
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(main).toMatchObject({
      item_count: 1,
      market_price_status: "missing",
      current_value_usd: 0,
      most_valuable: [],
    });
    expect(empty).toMatchObject({
      item_count: 0,
      market_price_status: "missing",
    });
  });

  it("treats a published zero price as available because zero and missing are different market states", async () => {
    const db = new FakeDb(
      [event("a1", "item-a", "main", "100", "upsert", "2026-07-01T00:00:00.000Z", 1)],
      [sku("100", 1, [{ date: "2026-07-10", price: 0 }])],
      [card("100", "Zero Price Card")],
    );

    const [main] = await loadValuationHistory(
      db as unknown as D1Database,
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      ["main"],
      1,
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(main).toMatchObject({
      item_count: 1,
      market_price_status: "available",
      current_value_usd: 0,
    });
  });

  it("keeps value before deletion and follows folder moves because history must not be rewritten from current holdings", async () => {
    const db = new FakeDb(
      [
        event("a1", "item-a", "main", "100", "upsert", "2026-06-01T00:00:00.000Z", 2),
        event("a2", "item-a", "trade", "100", "upsert", "2026-07-05T00:00:00.000Z", 2),
        event("a3", "item-a", "trade", "100", "delete", "2026-07-08T00:00:00.000Z", 2),
        event("b1", "item-b", "main", "200", "upsert", "2026-07-03T00:00:00.000Z", 1),
      ],
      [
        sku("100", 1, [{ date: "2026-06-01", price: 10 }, { date: "2026-07-06", price: 20 }]),
        sku("200", 2, [{ date: "2026-06-01", price: 5 }]),
      ],
      [card("100", "High Card"), card("200", "Low Card")],
    );

    const result = await loadValuationHistory(
      db as unknown as D1Database,
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      ["main", "trade"],
      10,
      new Date("2026-07-10T12:00:00.000Z"),
    );

    const main = result[0]!;
    const trade = result[1]!;
    expect(value(main, "2026-06-30")).toBe(20);
    expect(value(main, "2026-07-03")).toBe(25);
    expect(value(main, "2026-07-05")).toBe(5);
    expect(value(trade, "2026-07-05")).toBe(20);
    expect(value(trade, "2026-07-06")).toBe(40);
    expect(value(trade, "2026-07-07")).toBe(40);
    expect(value(trade, "2026-07-08")).toBe(0);
    expect(trade.current_value_usd).toBe(0);
    expect(main.most_valuable).toEqual([
      expect.objectContaining({
        item_id: "item-b",
        name: "Low Card",
        price_usd: 5,
        previous_30d_price_usd: 5,
      }),
    ]);
  });

  it("sorts and displays unit prices because quantity must not change Most Valuable rank", async () => {
    const db = new FakeDb(
      [
        event("a", "expensive", "main", "100", "upsert", "2026-06-01T00:00:00.000Z", 1),
        event("b", "bulk", "main", "200", "upsert", "2026-06-01T00:00:00.000Z", 100),
      ],
      [
        sku("100", 1, [{ date: "2026-06-01", price: 20 }]),
        sku("200", 2, [{ date: "2026-06-01", price: 5 }]),
      ],
      [card("100", "Expensive"), card("200", "Bulk")],
    );
    const [main] = await loadValuationHistory(
      db as unknown as D1Database,
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      ["main"],
      1,
      new Date("2026-07-10T12:00:00.000Z"),
    );
    expect(main!.current_value_usd).toBe(520);
    expect(main!.most_valuable.map((item) => item.item_id)).toEqual(["expensive", "bulk"]);
    expect(main!.most_valuable.map((item) => item.price_usd)).toEqual([20, 5]);
    expect(main!.most_valuable.map((item) => item.previous_30d_price_usd)).toEqual([20, 5]);
  });

  it("breaks equal unit prices by 30D growth, added time, then name because Home ranking must be deterministic", async () => {
    const db = new FakeDb(
      [
        event("e1", "z-high-growth", "main", "100", "upsert", "2026-06-01T00:00:00.000Z", 1),
        event("e2", "a-recent-zulu", "main", "200", "upsert", "2026-07-09T00:00:00.000Z", 1),
        event("e3", "b-recent-alpha", "main", "300", "upsert", "2026-07-09T00:00:00.000Z", 1),
        event("e4", "c-older", "main", "400", "upsert", "2026-07-01T00:00:00.000Z", 1),
      ],
      [
        { ...sku("100", 1, [{ date: "2026-07-10", price: 10 }]), change_30d_percent: 9 },
        { ...sku("200", 2, [{ date: "2026-07-10", price: 10 }]), change_30d_percent: 5 },
        { ...sku("300", 3, [{ date: "2026-07-10", price: 10 }]), change_30d_percent: 5 },
        { ...sku("400", 4, [{ date: "2026-07-10", price: 10 }]), change_30d_percent: 5 },
      ],
      [
        card("100", "Growth"),
        card("200", "Zulu"),
        card("300", "Alpha"),
        card("400", "Older"),
      ],
    );

    const [main] = await loadValuationHistory(
      db as unknown as D1Database,
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      ["main"],
      1,
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(main!.most_valuable.map((item) => item.item_id)).toEqual([
      "z-high-growth",
      "b-recent-alpha",
      "a-recent-zulu",
    ]);
  });

  it("uses graded finish and language history because Home must price the saved Collection item state", async () => {
    const graded = {
      ...event("graded", "graded-item", "main", "100", "upsert", "2026-07-01T00:00:00.000Z", 2),
      grader: "PSA",
      condition: null,
      grade: 7.5,
      language: "Japanese",
      finish: "Foil",
    };
    const db = new FakeDb(
      [graded],
      [
        {
          ...sku("100", 1, [{ date: "2026-07-08", price: 30 }]),
          language_code: "JP",
          language_name: "Japanese",
          variant_code: "F",
          variant_name: "Foil",
          grader_code: "PSA",
          grade_min_x10: 70,
          grade_max_x10: 75,
        },
        {
          ...sku("100", 2, [{ date: "2026-07-10", price: 999 }]),
          language_code: "EN",
          language_name: "English",
          variant_code: "N",
          variant_name: "Normal",
          grader_code: "PSA",
          grade_min_x10: 70,
          grade_max_x10: 75,
        },
      ],
      [{ ...card("100", "Graded Card"), number: "007" }],
    );

    const [main] = await loadValuationHistory(
      db as unknown as D1Database,
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      ["main"],
      1,
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(main!.current_value_usd).toBe(60);
    expect(main!.series.at(-1)?.value_usd).toBe(60);
    expect(main!.most_valuable[0]).toMatchObject({
      card_number: "007",
      price_usd: 30,
    });
  });

  it("prefers the narrowest matching grade range because Portfolio must use the same exact series as Card Detail", () => {
    const gradedEvent = {
      ...event("graded", "graded-item", "main", "100", "upsert", "2026-07-01T00:00:00.000Z", 1),
      grader: "PSA",
      condition: null,
      grade: 10,
    };
    const wide = {
      ...sku("100", 1, [{ date: "2026-07-10", price: 100 }]),
      grader_code: "PSA",
      grade_min_x10: 95,
      grade_max_x10: 100,
    };
    const exact = {
      ...sku("100", 2, [{ date: "2026-07-10", price: 200 }]),
      grader_code: "PSA",
      grade_min_x10: 100,
      grade_max_x10: 100,
    };

    expect(matchingPrice(gradedEvent, [wide, exact])?.row.series_id).toBe(2);
  });

  it("uses a saved series id even when qualifiers would select another row because migrated holdings need stable valuation", () => {
    const saved = {
      ...event("saved", "item", "main", "100", "upsert", "2026-07-01T00:00:00.000Z", 1),
      price_series_id: 2,
    };
    const qualifierMatch = sku("100", 1, [{ date: "2026-07-10", price: 10 }]);
    const stableSeries = {
      ...sku("100", 2, [{ date: "2026-07-10", price: 30 }]),
      condition_code: "LP",
      condition_name: "Lightly Played",
    };

    expect(matchingPrice(saved, [qualifierMatch, stableSeries])?.row.series_id).toBe(2);
  });

  it("does not guess another series when a saved series is unavailable because explicit bindings fail closed", () => {
    const saved = {
      ...event("saved", "item", "main", "100", "upsert", "2026-07-01T00:00:00.000Z", 1),
      price_series_id: 99,
    };

    expect(matchingPrice(saved, [sku("100", 1, [{ date: "2026-07-10", price: 10 }])])).toBeNull();
    expect(matchingPrice(
      { ...saved, price_series_id: 1 },
      [sku("100", 1, [])],
    )).toBeNull();
  });

  it("replays each event's saved series because historical valuation must not use the current item binding", async () => {
    const db = new FakeDb(
      [{
        ...event("saved", "item", "main", "100", "upsert", "2026-07-01T00:00:00.000Z", 2),
        price_series_id: 2,
      }],
      [
        sku("100", 1, [{ date: "2026-07-01", price: 10 }]),
        {
          ...sku("100", 2, [{ date: "2026-07-01", price: 30 }]),
          condition_code: "LP",
          condition_name: "Lightly Played",
        },
      ],
      [card("100", "Saved Series")],
    );

    const [main] = await loadValuationHistory(
      db as unknown as D1Database,
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      ["main"],
      1,
      new Date("2026-07-10T12:00:00.000Z"),
    );

    expect(main?.current_value_usd).toBe(60);
  });
});

function event(
  id: string,
  itemId: string,
  folderId: string,
  cardRef: string,
  eventType: "upsert" | "delete",
  effectiveAt: string,
  quantity: number,
) {
  return {
    id,
    item_id: itemId,
    folder_id: folderId,
    card_ref: cardRef,
    grader: "Raw",
    condition: "Near Mint (NM)",
    grade: null,
    language: null,
    finish: null,
    price_series_id: null,
    quantity,
    event_type: eventType,
    effective_at: effectiveAt,
  };
}

function sku(productId: string, skuId: number, history: unknown[]) {
  const points = history as Array<{ date: string; price: number }>;
  const latest = points.at(-1);
  return {
    sku_id: skuId,
    series_id: skuId,
    source_code: "tcgplayer",
    source_record_id: `sku-${skuId}`,
    metric_code: "ungraded",
    product_id: productId,
    condition_code: "NM",
    condition_name: "Near Mint",
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: "Normal",
    grader_code: "RAW",
    grade_min_x10: null,
    grade_max_x10: null,
    observed_on: latest?.date ?? "2026-07-10",
    amount_micros: (latest?.price ?? 0) * 1_000_000,
    baseline_1d_on: null,
    baseline_1d_amount_micros: null,
    baseline_7d_on: null,
    baseline_7d_amount_micros: null,
    baseline_30d_on: null,
    baseline_30d_amount_micros: null,
    price_history: JSON.stringify(history),
    change_1d_percent: null,
    change_7d_percent: null,
    change_30d_percent: null,
  };
}

function card(productId: string, name: string) {
  return {
    product_id: productId,
    name,
    set_name: "Server Set",
  };
}

function value(
  history: { series: Array<{ date: string; value_usd: number }> },
  date: string,
): number | undefined {
  return history.series.find((point) => point.date === date)?.value_usd;
}
