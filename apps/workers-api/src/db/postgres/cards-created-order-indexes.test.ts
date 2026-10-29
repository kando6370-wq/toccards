import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createLocalDbDataSourceAdapter } from "../../data-source/local-db-adapter";
import { PGliteDatabase } from "../../test-support/pglite-database";

const migrations = new URL("./migrations/", import.meta.url);
const oldIndexes = [
  "idx_cards_all_updated_product",
  "idx_cards_all_game_updated_product",
  "idx_cards_all_game_set_updated_product",
];
const newIndexes = [
  "idx_cards_all_created_product",
  "idx_cards_all_game_created_product",
  "idx_cards_all_game_set_created_product",
];

describe("PostgreSQL Cards creation-order indexes", () => {
  let db: PGliteDatabase;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
  });

  afterEach(async () => { await db.close(); });

  it("replaces only obsolete ordering indexes while preserving card data and updated_at", async () => {
    await db.prepare(`INSERT INTO cards_all
      (product_id, game_id, game, product_type_name, created_at, updated_at)
      VALUES (?, 1, 'Pokemon', 'Cards', ?, ?)`).bind(
      "card-1", "2026-10-01 00:00:00", "2026-10-28 00:00:00",
    ).run();
    const before = await cardIndexes();
    const migration = readFileSync(new URL("0016_cards_all_created_order_indexes.sql", migrations), "utf8");

    await db.exec(`BEGIN;\n${migration}\nCOMMIT;`);
    await db.exec(`BEGIN;\n${migration}\nCOMMIT;`);

    const after = await cardIndexes();
    expect(before.filter((name) => !oldIndexes.includes(name)).sort()).toEqual(
      after.filter((name) => !newIndexes.includes(name)).sort(),
    );
    expect(after).toEqual(expect.arrayContaining(newIndexes));
    for (const index of oldIndexes) expect(after).not.toContain(index);
    expect((await db.prepare(`SELECT product_id, created_at, updated_at
      FROM cards_all WHERE product_id = ?`).bind("card-1").first())).toEqual({
      product_id: "card-1",
      created_at: "2026-10-01 00:00:00",
      updated_at: "2026-10-28 00:00:00",
    });
    const definitions = await db.query<{ indexname: string; indexdef: string }>(
      `SELECT indexname, indexdef FROM pg_indexes
       WHERE tablename = 'cards_all' AND indexname = ANY($1::text[])`,
      [newIndexes],
    );
    expect(definitions.rows).toHaveLength(3);
    for (const [name, keys] of [
      [newIndexes[0], "(created_at DESC NULLS LAST, product_id DESC)"],
      [newIndexes[1], "(lower(game), created_at DESC NULLS LAST, product_id DESC)"],
      [newIndexes[2], "(lower(game), lower(set_code), created_at DESC NULLS LAST, product_id DESC)"],
    ]) {
      expect(definitions.rows.find((row) => row.indexname === name)?.indexdef).toContain(keys);
    }
  });

  it("keeps Cards pages ordered by creation time with null dates last", async () => {
    for (const [id, game, createdAt, updatedAt] of [
      ["card-a", "Pokemon", "2026-10-28 00:00:00", "2026-10-28 00:00:00"],
      ["card-b", "Pokemon", "2026-10-28 00:00:00", "2026-10-01 00:00:00"],
      ["card-c", "Pokemon", null, "2026-10-29 00:00:00"],
      ["card-d", "Pokemon", "2026-10-27 00:00:00", "2026-10-29 00:00:00"],
      ["card-z", "Other", "2026-10-30 00:00:00", "2026-10-30 00:00:00"],
    ] as const) {
      await db.prepare(`INSERT INTO cards_all
        (product_id, game_id, game, product_type_name, created_at, updated_at)
        VALUES (?, 1, ?, 'Cards', ?, ?)`).bind(id, game, createdAt, updatedAt).run();
    }
    await db.exec(readFileSync(new URL("0001_price_domain.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0016_cards_all_created_order_indexes.sql", migrations), "utf8"));

    const adapter = createLocalDbDataSourceAdapter(db);
    const first = (await adapter.searchCards("", {
      game: "Pokemon", object_type: "tcg", page: 1, page_size: 2,
    })).map((card) => card.card_ref);
    const second = (await adapter.searchCards("", {
      game: "Pokemon", object_type: "tcg", page: 2, page_size: 2,
    })).map((card) => card.card_ref);
    expect(first).toHaveLength(2);
    expect(first).toEqual(expect.arrayContaining(["card-a", "card-b"]));
    expect(second).toEqual(["card-d", "card-c"]);
  });

  it("streams empty-query browse pages through the matching index without sorting the catalog", async () => {
    await db.exec(`INSERT INTO cards_all
      (product_id, game_id, game, set_code, product_type_name, name, created_at)
      SELECT 'card-' || lpad(n::text, 6, '0'), 1,
        CASE WHEN n % 2 = 0 THEN 'Pokemon' ELSE 'Other' END,
        CASE WHEN n % 4 = 0 THEN 'SET1' ELSE 'SET2' END,
        'Cards', 'Card ' || n,
        to_char(timestamp '2026-01-01' + n * interval '1 second', 'YYYY-MM-DD HH24:MI:SS')
      FROM generate_series(1, 6000) AS series(n)`);
    await db.exec(readFileSync(new URL("0001_price_domain.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0016_cards_all_created_order_indexes.sql", migrations), "utf8"));
    await db.exec("ANALYZE cards_all");

    const adapter = createLocalDbDataSourceAdapter(db);
    for (const [options, indexName] of [
      [{ object_type: "tcg", page_size: 40 }, newIndexes[0]],
      [{ object_type: "tcg", game: "Pokemon", page_size: 40 }, newIndexes[1]],
      [{ object_type: "tcg", game: "Pokemon", set_code: "SET1", page_size: 40 }, newIndexes[2]],
    ] as const) {
      const querySpy = vi.spyOn(db, "query");
      await adapter.searchCards("", options);
      const catalogCall = querySpy.mock.calls.find(([sql]) =>
        sql.includes("FROM cards_all") && sql.includes("ORDER BY created_at DESC NULLS LAST")
      );
      querySpy.mockRestore();
      expect(catalogCall).toBeDefined();

      const plan = await db.query<{ "QUERY PLAN": unknown }>(
        `EXPLAIN (FORMAT JSON) ${catalogCall![0]}`,
        catalogCall![1] ?? [],
      );
      const nodes = JSON.stringify(plan.rows[0]?.["QUERY PLAN"]);
      expect(nodes).toContain(`"Index Name":"${indexName}"`);
      expect(nodes).not.toMatch(/"Node Type":"(?:Incremental )?Sort"/);
    }
  });

  async function cardIndexes(): Promise<string[]> {
    const result = await db.query<{ indexname: string }>(
      `SELECT indexname FROM pg_indexes WHERE tablename = 'cards_all' ORDER BY indexname`,
    );
    return result.rows.map((row) => row.indexname);
  }
});
