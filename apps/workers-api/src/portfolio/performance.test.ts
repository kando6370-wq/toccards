import { describe, expect, it } from "vitest";
import {
  calculatePerformance,
  loadPortfolioPerformance,
  performanceRangeStart,
} from "./performance";

describe("portfolio performance", () => {
  it("uses calendar boundaries because 1M and 1Y are not fixed day counts", () => {
    expect(performanceRangeStart("1M", new Date("2026-03-31T12:00:00Z"))).toBe("2026-02-28");
    expect(performanceRangeStart("1Y", new Date("2024-02-29T12:00:00Z"))).toBe("2023-02-28");
  });

  it("uses historical quantity but the latest purchase price because cost edits are retroactive", () => {
    const result = calculatePerformance(
      [
        event("one", "2026-08-01T00:00:00.000Z", 1, 10),
        event("two", "2026-08-10T00:00:00.000Z", 2, 20),
      ],
      [sku([{ date: "2026-08-01", price: 30 }])],
      "15D",
      { folderId: "main", now: new Date("2026-08-12T12:00:00Z") },
    );
    expect(result.series.find((point) => point.date === "2026-08-01")).toMatchObject({
      market_value_usd: 30,
      total_paid_usd: 20,
      profit_loss_usd: 10,
    });
    expect(result.current).toMatchObject({
      market_value_usd: 60,
      total_paid_usd: 40,
      profit_loss_usd: 20,
      return_percent: 50,
    });
    expect(result).toMatchObject({ item_count: 1, market_price_status: "available" });
  });

  it("ranks current Folder items by profit, return, then market value because Top Performers is an Item-level current snapshot", () => {
    const definitions = [
      ["a", 10, 50],
      ["b", 20, 60],
      ["c", 0, 40],
      ["d", 20, 40],
      ["e", 10, 20],
      ["f", 100, 90],
      ["g", 100, 80],
    ] as const;
    const result = calculatePerformance(
      [
        ...definitions.map(([id, purchasePrice]) => ({
          ...event(id, "2026-08-01T00:00:00.000Z", 1, purchasePrice),
          item_id: `item-${id}`,
          card_ref: `card-${id}`,
        })),
        {
          ...event("missing", "2026-08-01T00:00:00.000Z", 1, 0),
          item_id: "item-missing",
          card_ref: "card-missing",
          purchase_price: null,
          purchase_currency: null,
        },
      ],
      definitions.map(([id, , marketPrice], index) => ({
        ...sku([{ date: "2026-08-01", price: marketPrice }]),
        series_id: index + 1,
        product_id: `card-${id}`,
      })),
      "1D",
      {
        folderId: "main",
        now: new Date("2026-08-12T12:00:00Z"),
        includeTopPerformers: true,
        cards: definitions.map(([id]) => ({
          product_id: `card-${id}`,
          game: "Pokemon",
          name: `Card ${id.toUpperCase()}`,
          set_name: "Ranking Set",
          number: id,
          rarity: "Rare",
        })),
      },
    );

    expect(result.top_performer_count).toBe(7);
    expect(result.top_performers.map((item) => item.item_id)).toEqual([
      "item-a",
      "item-b",
      "item-c",
      "item-d",
      "item-e",
    ]);
    expect(result.top_performers[0]).toMatchObject({
      name: "Card A",
      profit_loss_usd: 40,
      return_percent: 400,
      market_value_usd: 50,
    });
    expect(result.top_performers[2]).toMatchObject({
      item_id: "item-c",
      profit_loss_usd: 40,
      return_percent: null,
    });
  });

  it("ranks Top Performers before response rounding because display precision must not change business order", () => {
    const result = calculatePerformance(
      [
        {
          ...event("a", "2026-08-01T00:00:00.000Z", 1, 100),
          item_id: "item-a",
          card_ref: "card-a",
        },
        {
          ...event("b", "2026-08-01T00:00:00.000Z", 1, 0.001),
          item_id: "item-b",
          card_ref: "card-b",
        },
      ],
      [
        {
          ...sku([{ date: "2026-08-01", price: 100.004 }]),
          series_id: 1,
          product_id: "card-a",
        },
        {
          ...sku([{ date: "2026-08-01", price: 0.004 }]),
          series_id: 2,
          product_id: "card-b",
        },
      ],
      "1D",
      {
        folderId: "main",
        now: new Date("2026-08-12T12:00:00Z"),
        includeTopPerformers: true,
      },
    );

    expect(result.top_performers.map((item) => item.item_id)).toEqual([
      "item-a",
      "item-b",
    ]);
  });

  it("does not treat non-USD purchase prices as USD without a reliable historical rate", () => {
    const result = calculatePerformance(
      [{ ...event("one", "2026-08-01T00:00:00.000Z", 1, 100), purchase_currency: "JPY" }],
      [sku([{ date: "2026-08-01", price: 30 }])],
      "15D",
      { folderId: "main", now: new Date("2026-08-12T12:00:00Z") },
    );
    expect(result.purchase_price_status).toBe("missing");
    expect(result.current).toMatchObject({
      market_value_usd: 30,
      total_paid_usd: null,
      profit_loss_usd: null,
    });
  });

  it("distinguishes an empty portfolio from owned items without market data", () => {
    const empty = calculatePerformance([], [], "1M", {
      folderId: "main",
      now: new Date("2026-08-12T12:00:00Z"),
    });
    const noMarket = calculatePerformance(
      [event("one", "2026-08-01T00:00:00.000Z", 1, 10)],
      [],
      "1M",
      { folderId: "main", now: new Date("2026-08-12T12:00:00Z") },
    );

    expect(empty).toMatchObject({ item_count: 0, market_price_status: "missing" });
    expect(noMarket).toMatchObject({ item_count: 1, market_price_status: "missing" });
    expect(noMarket.current.quantity).toBe(1);
  });

  it("splits daily value movement into market and portfolio change for the tooltip", () => {
    const result = calculatePerformance(
      [
        event("one", "2026-08-01T00:00:00.000Z", 10, 10),
        event("two", "2026-08-02T00:00:00.000Z", 12, 10),
      ],
      [sku([
        { date: "2026-08-01", price: 10 },
        { date: "2026-08-02", price: 12 },
      ])],
      "7D",
      { folderId: "main", now: new Date("2026-08-02T12:00:00Z") },
    );

    expect(result.series.find((point) => point.date === "2026-08-01")).toMatchObject({
      market_value_usd: 100,
      market_change_usd: null,
      portfolio_change_usd: null,
      quantity: 10,
      quantity_change: null,
    });
    expect(result.series.find((point) => point.date === "2026-08-02")).toMatchObject({
      market_value_usd: 144,
      market_value_change_usd: 44,
      market_change_usd: 20,
      portfolio_change_usd: 24,
      quantity: 12,
      quantity_change: 2,
      profit_loss_change_usd: 24,
    });
  });

  it("uses the adjacent reliable day before the range for the first tooltip point", () => {
    const result = calculatePerformance(
      [
        { ...event("one", "2026-07-25T00:00:00.000Z", 10, 10), performance_history_available_from: "2026-07-25T00:00:00.000Z" },
        { ...event("two", "2026-07-27T00:00:00.000Z", 12, 10), performance_history_available_from: "2026-07-25T00:00:00.000Z" },
      ],
      [sku([
        { date: "2026-07-26", price: 10 },
        { date: "2026-07-27", price: 12 },
      ])],
      "7D",
      { folderId: "main", now: new Date("2026-08-02T12:00:00Z") },
    );

    expect(result.series[0]).toMatchObject({
      date: "2026-07-27",
      market_change_usd: 20,
      portfolio_change_usd: 24,
      quantity: 12,
      quantity_change: 2,
    });
  });

  it("keeps 1Y available while exposing only the reliable partial history", () => {
    const result = calculatePerformance(
      [
        {
          ...event("legacy", "2025-01-02T00:00:00.000Z", 2, 25),
          performance_history_available_from: "2026-08-01T00:00:00.000Z",
        },
      ],
      [sku([{ date: "2026-08-01", price: 30 }])],
      "1Y",
      { folderId: "main", now: new Date("2026-08-12T12:00:00Z") },
    );

    expect(result).toMatchObject({
      range: "1Y",
      range_start: "2025-08-12",
      history_available_from: "2026-08-01",
      partial_history: true,
    });
    expect(result.series[0]?.date).toBe("2026-08-01");
  });

  it("moves all reliable history to the latest Folder because Folder Move is whole-history attribution", () => {
    const events = [
      event("created", "2026-08-01T00:00:00.000Z", 1, 10),
      {
        ...event("moved", "2026-08-10T00:00:00.000Z", 2, 10),
        folder_id: "trade",
      },
    ];
    const prices = [sku([
      { date: "2026-08-01", price: 20 },
      { date: "2026-08-10", price: 30 },
    ])];
    const options = { now: new Date("2026-08-12T12:00:00Z") };

    const source = calculatePerformance(events, prices, "15D", {
      ...options,
      folderId: "main",
    });
    const target = calculatePerformance(events, prices, "15D", {
      ...options,
      folderId: "trade",
    });

    expect(source).toMatchObject({
      history_available_from: null,
      item_count: 0,
      market_price_status: "missing",
    });
    expect(source.series.every((point) => point.quantity === 0)).toBe(true);
    expect(target.series.find((point) => point.date === "2026-08-01")).toMatchObject({
      market_value_usd: 20,
      quantity: 1,
    });
    expect(target.current).toMatchObject({ market_value_usd: 60, quantity: 2 });
  });

  it("filters Card Detail by item in SQL because one item must not load the owner's complete event history", async () => {
    const calls: Array<{ sql: string; bindings: unknown[] }> = [];
    const db = recordingDatabase([], calls);

    await loadPortfolioPerformance(
      db,
      { owner_type: "user", owner_id: "owner-1", session_id: "session-1" },
      "1M",
      { itemId: "item-1", now: new Date("2026-08-12T12:00:00Z") },
    );

    expect(calls[0]?.sql).toContain("AND item_id = ?");
    expect(calls[0]?.sql).toContain("LIMIT 10001");
    expect(calls[0]?.bindings).toEqual(["user", "owner-1", "item-1"]);
  });

  it("fails above 10000 events because Hyperdrive responses must stay bounded", async () => {
    const db = recordingDatabase(
      Array.from({ length: 10_001 }, (_, index) => ({ id: `event-${index}` })),
      [],
    );

    await expect(loadPortfolioPerformance(
      db,
      { owner_type: "user", owner_id: "owner-1", session_id: "session-1" },
      "1M",
      { now: new Date("2026-08-12T12:00:00Z") },
    )).rejects.toThrow("Portfolio performance query exceeded 10000 events");
  });

  it("uses event-level saved series and fails closed when it is unavailable because Performance replays historical bindings", () => {
    const qualifierSeries = sku([{ date: "2026-08-01", price: 10 }]);
    const savedSeries = {
      ...sku([{ date: "2026-08-01", price: 30 }]),
      series_id: 2,
      condition_code: "LP",
      condition_name: "Lightly Played",
    };
    const options = { folderId: "main", now: new Date("2026-08-01T12:00:00Z") };

    const saved = calculatePerformance(
      [{ ...event("saved", "2026-08-01T00:00:00.000Z", 2, 10), price_series_id: 2 }],
      [qualifierSeries, savedSeries],
      "1D",
      options,
    );
    const unavailable = calculatePerformance(
      [{ ...event("missing", "2026-08-01T00:00:00.000Z", 2, 10), price_series_id: 99 }],
      [qualifierSeries, savedSeries],
      "1D",
      options,
    );

    expect(saved.current.market_value_usd).toBe(60);
    expect(unavailable).toMatchObject({ market_price_status: "missing" });
    expect(unavailable.current.market_value_usd).toBe(0);
  });
});

function recordingDatabase(
  events: unknown[],
  calls: Array<{ sql: string; bindings: unknown[] }>,
): D1Database {
  return {
    prepare(sql: string) {
      let bindings: unknown[] = [];
      const statement = {
        bind(...values: unknown[]) {
          bindings = values;
          return statement;
        },
        async all<T>() {
          calls.push({ sql, bindings });
          return { results: events as T[] };
        },
      };
      return statement;
    },
  } as unknown as D1Database;
}

function event(id: string, effectiveAt: string, quantity: number, purchasePrice: number) {
  return {
    id,
    item_id: "item-1",
    folder_id: "main",
    card_ref: "100",
    grader: "Raw",
    condition: "Near Mint (NM)",
    grade: null,
    language: "English",
    finish: "Normal",
    price_series_id: null,
    quantity,
    purchase_price: purchasePrice,
    purchase_currency: "USD",
    performance_history_available_from: "2026-08-01T00:00:00.000Z",
    event_type: "upsert" as const,
    effective_at: effectiveAt,
  };
}

function sku(history: Array<{ date: string; price: number }>) {
  return {
    series_id: 1,
    source_code: "tcgplayer",
    source_record_id: "sku-1",
    metric_code: "ungraded",
    product_id: "100",
    condition_code: "NM",
    condition_name: "Near Mint",
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: "Normal",
    grader_code: "RAW",
    grade_min_x10: null,
    grade_max_x10: null,
    price_history: JSON.stringify(history),
    change_30d_percent: null,
  };
}
