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

  it("keeps numeric IDs in numeric order across Cards pages without moving older or unrelated cards", async () => {
    for (const [id, game, setId, createdAt, updatedAt] of [
      ["9223372036854775808", "Pokemon", "set-1", "2026-10-28 00:00:00", "2026-10-01 00:00:00"],
      ["700", "Pokemon", "set-1", "2026-10-28 00:00:00", "2026-10-01 00:00:00"],
      ["80", "Pokemon", "set-1", "2026-10-28 00:00:00", "2026-10-01 00:00:00"],
      ["9", "Pokemon", "set-1", "2026-10-28 00:00:00", "2026-10-01 00:00:00"],
      ["0010", "Pokemon", "set-1", "2026-10-28 00:00:00", "2026-10-01 00:00:00"],
      ["10", "Pokemon", "set-1", "2026-10-28 00:00:00", "2026-10-01 00:00:00"],
      ["A12", "Pokemon", "set-1", "2026-10-28 00:00:00", "2026-10-01 00:00:00"],
      ["sports:12", "Pokemon", "set-1", "2026-10-28 00:00:00", "2026-10-01 00:00:00"],
      ["999999999999999999999", "Pokemon", "set-1", "2026-10-27 00:00:00", "2026-10-29 00:00:00"],
      ["null-created", "Pokemon", "set-1", null, "2026-10-29 00:00:00"],
      ["other-set", "Pokemon", "set-2", "2026-10-30 00:00:00", "2026-10-30 00:00:00"],
      ["other-game", "Other", "set-1", "2026-10-31 00:00:00", "2026-10-31 00:00:00"],
    ] as const) {
      await db.prepare(`INSERT INTO cards_all
        (product_id, game_id, game, set_id, product_type_name, created_at, updated_at)
        VALUES (?, 1, ?, ?, 'Cards', ?, ?)`).bind(id, game, setId, createdAt, updatedAt).run();
    }
    await db.exec(readFileSync(new URL("0001_price_domain.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0016_cards_all_created_order_indexes.sql", migrations), "utf8"));

    const adapter = createLocalDbDataSourceAdapter(db);
    const pages = [];
    for (const page of [1, 2, 3]) {
      const cards = await adapter.searchCards("", {
        game: "Pokemon", set_id: "set-1", object_type: "tcg", page, page_size: 4,
      });
      pages.push(cards.map((card) => card.card_ref));
    }
    expect(pages).toEqual([
      ["9223372036854775808", "700", "80", "10"],
      ["0010", "9", "sports:12", "A12"],
      ["999999999999999999999", "null-created"],
    ]);
    expect(new Set(pages.flat()).size).toBe(10);
    expect((await adapter.searchCards("", {
      game: "Pokemon", object_type: "tcg", page: 1, page_size: 1,
    })).map((card) => card.card_ref)).toEqual(["other-set"]);
  });

  it("can use the created-time index prefix for empty-query browse ranges", async () => {
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
    }
  });

  async function cardIndexes(): Promise<string[]> {
    const result = await db.query<{ indexname: string }>(
      `SELECT indexname FROM pg_indexes WHERE tablename = 'cards_all' ORDER BY indexname`,
    );
    return result.rows.map((row) => row.indexname);
  }
});
