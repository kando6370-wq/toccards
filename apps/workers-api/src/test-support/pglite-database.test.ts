import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { PGliteDatabase } from "./pglite-database";

describe("PGlite PostgreSQL test database", () => {
  let db: PGliteDatabase;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
  });

  afterEach(async () => db.close());

  it("executes PostgreSQL statements and normalizes production scalar types", async () => {
    const executed = await db.exec(`
      CREATE TABLE example (id text PRIMARY KEY, amount numeric, happened_on date);
      INSERT INTO example VALUES ('one', 12.5, '2026-08-26');
      INSERT INTO example VALUES ('two', 20, '2026-08-27');
    `);
    const row = await db.prepare(`
      SELECT count(*)::bigint AS count,
             sum(amount)::numeric AS total,
             min(happened_on) AS first_date
      FROM example
      WHERE amount >= ?
    `).bind(10).first<{
      count: number;
      total: number;
      first_date: string;
    }>();

    expect(executed.count).toBe(3);
    expect(row).toEqual({
      count: 2,
      total: 32.5,
      first_date: "2026-08-26",
    });
  });

  it("runs D1-style batches in one PostgreSQL transaction", async () => {
    await db.prepare("CREATE TABLE batched (id text PRIMARY KEY)").run();

    const results = await db.batch([
      db.prepare("INSERT INTO batched VALUES (?)").bind("a"),
      db.prepare("INSERT INTO batched VALUES (?)").bind("b"),
    ]);
    const rows = await db.prepare("SELECT id FROM batched ORDER BY id").all<{
      id: string;
    }>();

    expect(results.map((result) => result.meta.changes)).toEqual([1, 1]);
    expect(rows.results).toEqual([{ id: "a" }, { id: "b" }]);
  });
});
