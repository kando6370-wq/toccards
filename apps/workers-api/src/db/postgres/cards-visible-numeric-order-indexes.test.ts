import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createLocalDbDataSourceAdapter } from "../../data-source/local-db-adapter";
import type { CardSearchOptions } from "../../data-source/adapter";
import { PGliteDatabase } from "../../test-support/pglite-database";

const migrations = new URL("./migrations/", import.meta.url);
const migration0017 = new URL("0017_cards_visible_numeric_order_indexes.sql", migrations);
const expectedIndexes = [
  "idx_cards_all_visible_created_numeric_product",
  "idx_cards_all_visible_game_created_numeric_product",
  "idx_cards_all_visible_game_set_created_numeric_product",
];

describe("PostgreSQL visible Cards numeric-order indexes", () => {
  let db: PGliteDatabase;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0001_price_domain.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0016_cards_all_created_order_indexes.sql", migrations), "utf8"));
  });

  afterEach(async () => { await db.close(); });

  it("removes the extra sort from all three image-filtered browse ranges", async () => {
    await db.exec(`INSERT INTO cards_all
      (product_id, game_id, game, set_id, product_type_name, name, has_image, created_at)
      SELECT lpad(n::text, 7, '0'), 1,
        CASE WHEN n % 2 = 0 THEN 'Pokemon' ELSE 'Other' END,
        CASE WHEN n % 4 = 0 THEN 'set-1' ELSE 'set-2' END,
        'Cards', 'Card ' || n, CASE WHEN n % 10 = 0 THEN 1 ELSE 2 END,
        '2026-10-28 00:00:00'
      FROM generate_series(1, 6000) AS series(n)`);
    await db.exec("ANALYZE cards_all");

    const ranges: Array<[CardSearchOptions, string]> = [
      [{ object_type: "tcg", has_image: 2, page_size: 40 }, expectedIndexes[0]],
      [{ object_type: "tcg", has_image: 2, game: "Pokemon", page_size: 40 }, expectedIndexes[1]],
      [{ object_type: "tcg", has_image: 2, game: "Pokemon", set_id: "set-1", page_size: 40 }, expectedIndexes[2]],
    ];
    for (const [options] of ranges) {
      const before = await browsePlan(options);
      expect(before).toMatch(/"Node Type":"(?:Incremental )?Sort"/);
    }
    await db.exec(readFileSync(migration0017, "utf8"));
    await db.exec("ANALYZE cards_all");
    for (const [options, indexName] of ranges) {
      const after = await browsePlan(options);
      expect(after).not.toMatch(/"Node Type":"(?:Incremental )?Sort"/);
      expect(after).toContain(`"Index Name":"${indexName}"`);
    }
  });

  it("preserves numeric ordering, stable pages, and the 0016 indexes when applied twice", async () => {
    for (const [id, game, setId, hasImage, createdAt] of [
      ["9223372036854775808", "Pokemon", "set-1", 2, "2026-10-28 00:00:00"],
      ["700", "Pokemon", "set-1", 2, "2026-10-28 00:00:00"],
      ["80", "Pokemon", "set-1", 2, "2026-10-28 00:00:00"],
      ["0010", "Pokemon", "set-1", 2, "2026-10-28 00:00:00"],
      ["10", "Pokemon", "set-1", 2, "2026-10-28 00:00:00"],
      ["9", "Pokemon", "set-1", 2, "2026-10-28 00:00:00"],
      ["A12", "Pokemon", "set-1", 2, "2026-10-28 00:00:00"],
      ["sports:12", "Pokemon", "set-1", 2, "2026-10-28 00:00:00"],
      ["999999999999999999999", "Pokemon", "set-1", 2, "2026-10-27 00:00:00"],
      ["null-created", "Pokemon", "set-1", 2, null],
      ["hidden", "Pokemon", "set-1", 1, "2026-10-29 00:00:00"],
      ["other-set", "Pokemon", "set-2", 2, "2026-10-29 00:00:00"],
      ["other-game", "Other", "set-1", 2, "2026-10-29 00:00:00"],
    ] as const) {
      await db.prepare(`INSERT INTO cards_all
        (product_id, game_id, game, set_id, product_type_name, has_image, created_at)
        VALUES (?, 1, ?, ?, 'Cards', ?, ?)`).bind(id, game, setId, hasImage, createdAt).run();
    }
    const options: CardSearchOptions = {
      object_type: "tcg", has_image: 2, game: "Pokemon", set_id: "set-1", page_size: 4,
    };
    const before = await pages(options);
    const originalIndexes = await indexDefinitions();

    const migration = readFileSync(migration0017, "utf8");
    await db.exec(migration);
    await db.exec(migration);

    const after = await pages(options);
    expect(after).toEqual(before);
    expect(after).toEqual([
      ["9223372036854775808", "700", "80", "10"],
      ["0010", "9", "sports:12", "A12"],
      ["999999999999999999999", "null-created"],
    ]);
    expect(new Set(after.flat()).size).toBe(10);

    const indexes = await indexDefinitions();
    for (const original of originalIndexes) {
      expect(indexes).toContainEqual(original);
    }
    for (const name of expectedIndexes) {
      const definition = indexes.find((row) => row.indexname === name)?.indexdef;
      const normalized = definition?.replace(/\s+/g, " ");
      expect(normalized).toContain("CASE WHEN (product_id ~ '^[0-9]+$'::text) THEN (product_id)::numeric ELSE NULL::numeric END");
      expect(normalized).toContain("WHERE (has_image = 2)");
    }
    expect(indexes.filter((row) => expectedIndexes.includes(row.indexname))).toHaveLength(3);
  });

  async function pages(options: CardSearchOptions): Promise<string[][]> {
    const adapter = createLocalDbDataSourceAdapter(db);
    const result: string[][] = [];
    for (const page of [1, 2, 3]) {
      const cards = await adapter.searchCards("", { ...options, page });
      result.push(cards.map((card) => card.card_ref));
    }
    return result;
  }

  function indexDefinitions(): Promise<Array<{ indexname: string; indexdef: string }>> {
    return db.query<{ indexname: string; indexdef: string }>(
      "SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'cards_all' ORDER BY indexname",
    ).then((result) => result.rows);
  }

  async function browsePlan(options: CardSearchOptions): Promise<string> {
    const spy = vi.spyOn(db, "query");
    await createLocalDbDataSourceAdapter(db).searchCards("", options);
    const call = spy.mock.calls.find(([sql]) =>
      sql.includes("FROM cards_all") && sql.includes("ORDER BY created_at DESC NULLS LAST")
    );
    spy.mockRestore();
    expect(call).toBeDefined();
    const plan = await db.query<{ "QUERY PLAN": unknown }>(
      `EXPLAIN (FORMAT JSON) ${call![0]}`,
      call![1] ?? [],
    );
    return JSON.stringify(plan.rows[0]?.["QUERY PLAN"]);
  }
});
