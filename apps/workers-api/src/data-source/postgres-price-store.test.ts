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

  it("splits a dense card chunk because valid price dimensions must not make catalog pagination fail", async () => {
    const db = new RecordingDatabase((_sql, bindings) =>
      Array.from({ length: bindings.length > 10 ? 1001 : 600 }, () => ({}))
    );
    const cardRefs = Array.from({ length: 40 }, (_, index) => `card-${index}`);

    const rows = await loadPublishedPriceRows(db.asD1(), cardRefs);

    expect(rows).toHaveLength(2400);
    expect(db.calls.map((call) => call.bindings)).toEqual([
      cardRefs,
      cardRefs.slice(0, 20),
      cardRefs.slice(0, 10),
      cardRefs.slice(10, 20),
      cardRefs.slice(20),
      cardRefs.slice(20, 30),
      cardRefs.slice(30),
    ]);
  });

  it("fails when a current-price chunk exceeds 1000 rows so oversized responses cannot pass silently", async () => {
    const db = new RecordingDatabase(() => Array.from({ length: 1001 }, () => ({})));

    await expect(loadPublishedPriceRows(db.asD1(), ["card-1"]))
      .rejects.toThrow("Published price query exceeded 1000 rows for 1 cards");
  });

  it("matches the active-series partial index predicate because current prices must not scan every provider series", async () => {
    const db = new RecordingDatabase();

    await loadPublishedPriceRows(db.asD1(), ["card-1"]);

    const sql = db.calls[0]?.sql ?? "";
    expect(sql).toContain("WHERE series.is_active\n");
    expect(sql).not.toContain("series.is_active IS TRUE");
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
        { date: "2026-08-03", price: "3.75" },
      ]),
    }]);

    const points = await loadPriceHistoryBySeries(
      db.asD1(),
      [7],
      "2026-08-01",
      "2026-08-03",
    );

    expect(points.get(7)).toEqual([
      { date: "2026-08-01", price: 1.234567 },
      { date: "2026-08-02", price: 2.5 },
      { date: "2026-08-03", price: 3.75 },
    ]);
  });

  it("fails invalid monthly payloads because corrupted PostgreSQL history is not empty business data", async () => {
    const nonArray = new RecordingDatabase(() => [{
      series_id: 7,
      points_json: JSON.stringify({ d: "2026-08-01", a: 1_000_000 }),
    }]);
    const invalidPoint = new RecordingDatabase(() => [{
      series_id: 7,
      points_json: JSON.stringify([{ d: "2026-08-01", a: "not-micros" }]),
    }]);

    await expect(loadPriceHistoryBySeries(
      nonArray.asD1(),
      [7],
      "2026-08-01",
      "2026-08-02",
    )).rejects.toThrow("Invalid PostgreSQL price history payload");
    await expect(loadPriceHistoryBySeries(
      invalidPoint.asD1(),
      [7],
      "2026-08-01",
      "2026-08-02",
    )).rejects.toThrow("Invalid PostgreSQL price history point at index 0");
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
