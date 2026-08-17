import { describe, expect, it } from "vitest";
import {
  loadPriceHistoryBySeries,
  loadPublishedPriceRows,
} from "./postgres-price-store";

type QueryCall = {
  sql: string;
  bindings: unknown[];
};

class RecordingDatabase {
  readonly calls: QueryCall[] = [];

  constructor(
    private readonly reply: (sql: string, bindings: unknown[]) => unknown[] = () => [],
  ) {}

  prepare(sql: string): D1PreparedStatement {
    let bindings: unknown[] = [];
    const statement = {
      bind: (...values: unknown[]) => {
        bindings = values;
        return statement;
      },
      all: async <T>() => {
        this.calls.push({ sql, bindings });
        return { results: this.reply(sql, bindings) as T[] };
      },
    };
    return statement as unknown as D1PreparedStatement;
  }

  asD1(): D1Database {
    return this as unknown as D1Database;
  }
}

describe("PostgreSQL price store query boundaries", () => {
  it("chunks current prices at 40 cards and accepts 1000 rows because Hyperdrive responses must stay bounded", async () => {
    const db = new RecordingDatabase((_sql, bindings) =>
      bindings.length === 40 ? Array.from({ length: 1000 }, () => ({})) : []
    );

    const rows = await loadPublishedPriceRows(
      db.asD1(),
      Array.from({ length: 41 }, (_, index) => `card-${index}`),
    );

    expect(rows).toHaveLength(1000);
    expect(db.calls.map((call) => call.bindings.length)).toEqual([40, 1]);
    expect(db.calls[0]?.sql).toContain("ROW_NUMBER() OVER");
    expect(db.calls[0]?.sql).toContain("LIMIT 1001");
  });

  it("fails when a current-price chunk exceeds 1000 rows so oversized responses cannot pass silently", async () => {
    const db = new RecordingDatabase(() => Array.from({ length: 1001 }, () => ({})));

    await expect(loadPublishedPriceRows(db.asD1(), ["card-1"]))
      .rejects.toThrow("Published price query exceeded 1000 rows for 1 cards");
  });

  it("chunks history at 100 series and accepts 1600 month rows because price batches need a fixed response ceiling", async () => {
    const db = new RecordingDatabase((_sql, bindings) =>
      bindings.length === 103
        ? Array.from({ length: 1600 }, () => ({ series_id: 1, points_json: "[]" }))
        : []
    );

    await loadPriceHistoryBySeries(
      db.asD1(),
      Array.from({ length: 101 }, (_, index) => index + 1),
      "2026-01-01",
      "2026-12-31",
    );

    expect(db.calls.map((call) => call.bindings.length)).toEqual([103, 4]);
    expect(db.calls[0]?.sql).toContain("CAST(history.points AS TEXT)");
    expect(db.calls[0]?.sql).toContain("LIMIT 1601");
  });

  it("fails when a history chunk exceeds 1600 month rows so Hyperdrive cannot return an unbounded payload", async () => {
    const db = new RecordingDatabase(() =>
      Array.from({ length: 1601 }, () => ({ series_id: 1, points_json: "[]" }))
    );

    await expect(loadPriceHistoryBySeries(db.asD1(), [1], "2026-01-01", "2026-12-31"))
      .rejects.toThrow("Price history query exceeded 1600 monthly rows for 1 series");
  });

  it("preserves micros precision from monthly JSON because portfolio valuation uses exact source prices", async () => {
    const db = new RecordingDatabase(() => [{
      series_id: 7,
      points_json: JSON.stringify([
        { d: "2026-08-01", a: 1_234_567 },
        { date: "2026-08-02", price: 2.5 },
      ]),
    }]);

    const points = await loadPriceHistoryBySeries(
      db.asD1(),
      [7],
      "2026-08-01",
      "2026-08-02",
    );

    expect(points.get(7)).toEqual([
      { date: "2026-08-01", price: 1.234567 },
      { date: "2026-08-02", price: 2.5 },
    ]);
  });

  it("reads only the published current scope because another scope from the same source must not expose history", async () => {
    const db = new RecordingDatabase();

    await loadPriceHistoryBySeries(db.asD1(), [7], "2026-08-01", "2026-08-02");

    const sql = db.calls[0]?.sql ?? "";
    expect(sql).toContain("history_batch.status IN ('published', 'superseded')");
    expect(sql).toContain("history_batch.source_id = series.source_id");
    expect(sql).toContain("baseline_batch.status IN ('published', 'superseded')");
    expect(sql).toContain("current_batch.status = 'published'");
    expect(sql).toContain("current_batch.source_id = series.source_id");
    expect(sql).toContain("current_pointer.scope_code = history_batch.scope_code");
    expect(sql).toContain("baseline_batch.scope_code = history_batch.scope_code");
  });

  it("accepts 400 days and rejects 401 because public history requests have a fixed maximum range", async () => {
    const db = new RecordingDatabase();

    await expect(loadPriceHistoryBySeries(db.asD1(), [], "2025-01-01", "2026-02-05"))
      .resolves.toEqual(new Map());
    await expect(loadPriceHistoryBySeries(db.asD1(), [], "2025-01-01", "2026-02-06"))
      .rejects.toThrow("Price history range exceeds 400 days");
  });
});
