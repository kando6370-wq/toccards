import { describe, expect, it } from "vitest";
import { calculatePerformance, performanceRangeStart } from "./performance";

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
});

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
    product_id: "100",
    condition_code: "NM",
    condition_name: "Near Mint",
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: "Normal",
    price_history: JSON.stringify(history),
    increase_rate: null,
    price_Grade_7: "[]",
    price_Grade_8: "[]",
    price_Grade_9: "[]",
    price_Grade_9_5: "[]",
    price_PSA_10: "[]",
    price_BGS_10: "[]",
    price_CGC_10: "[]",
    price_SGC_10: "[]",
    increase_Grade_7: null,
    increase_Grade_8: null,
    increase_Grade_9: null,
    increase_Grade_9_5: null,
    increase_PSA_10: null,
    increase_BGS_10: null,
    increase_CGC_10: null,
    increase_SGC_10: null,
  };
}
