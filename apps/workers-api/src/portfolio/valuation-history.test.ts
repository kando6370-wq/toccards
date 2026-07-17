import { describe, expect, it } from "vitest";
import { loadValuationHistory } from "./valuation-history";

class FakeDb {
  constructor(
    readonly events: Record<string, unknown>[],
    readonly skus: Record<string, unknown>[],
    readonly cards: Record<string, unknown>[],
  ) {}
  prepare(sql: string) {
    const rows = sql.includes("collection_item_event")
      ? this.events
      : sql.includes("FROM cards_all")
        ? this.cards
        : this.skus;
    return {
      bind: (..._args: unknown[]) => ({
        all: async <T>() => ({ results: rows as T[] }),
      }),
    };
  }
}

describe("portfolio valuation history", () => {
  it("keeps value before deletion and follows folder moves because history must not be rewritten from current holdings", async () => {
    const db = new FakeDb(
      [
        event("a1", "item-a", "main", "100", "upsert", "2026-06-01T00:00:00.000Z", 2),
        event("a2", "item-a", "trade", "100", "upsert", "2026-07-05T00:00:00.000Z", 2),
        event("a3", "item-a", "trade", "100", "delete", "2026-07-08T00:00:00.000Z", 2),
        event("b1", "item-b", "main", "200", "upsert", "2026-07-03T00:00:00.000Z", 1),
      ],
      [
        sku(100, 1, [{ date: "2026-06-01", price: 10 }, { date: "2026-07-06", price: 20 }]),
        sku(200, 2, [{ date: "2026-06-01", price: 5 }]),
      ],
      [card("100", "High Card"), card("200", "Low Card")],
    );

    const result = await loadValuationHistory(
      db as unknown as D1Database,
      { owner_type: "anonymous", owner_id: "anon-1" },
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

  it("sorts by unit price rather than quantity because Most Valuable is not total position value", async () => {
    const db = new FakeDb(
      [
        event("a", "expensive", "main", "100", "upsert", "2026-06-01T00:00:00.000Z", 1),
        event("b", "bulk", "main", "200", "upsert", "2026-06-01T00:00:00.000Z", 100),
      ],
      [
        sku(100, 1, [{ date: "2026-06-01", price: 20 }]),
        sku(200, 2, [{ date: "2026-06-01", price: 5 }]),
      ],
      [card("100", "Expensive"), card("200", "Bulk")],
    );
    const [main] = await loadValuationHistory(
      db as unknown as D1Database,
      { owner_type: "anonymous", owner_id: "anon-1" },
      ["main"],
      1,
      new Date("2026-07-10T12:00:00.000Z"),
    );
    expect(main!.current_value_usd).toBe(520);
    expect(main!.most_valuable.map((item) => item.item_id)).toEqual(["expensive", "bulk"]);
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
    quantity,
    event_type: eventType,
    effective_at: effectiveAt,
  };
}

function sku(productId: number, skuId: number, history: unknown[]) {
  return {
    sku_id: skuId,
    product_id: productId,
    condition_code: "NM",
    condition_name: "Near Mint",
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: "Normal",
    price_history: JSON.stringify(history),
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
