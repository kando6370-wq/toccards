import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { PGliteDatabase } from "../test-support/pglite-database";
import { createLocalDbDataSourceAdapter } from "./local-db-adapter";

describe("PostgreSQL Set search ordering", () => {
  let db: PGliteDatabase;

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(
      new URL("../db/postgres/migrations/0000_business_schema.sql", import.meta.url),
      "utf8",
    ));
    for (const [id, name, code, game] of [
      ["700", "Alpha", "S700", "Pokemon"],
      ["80", "Dragon Collection", "S80", "Pokemon"],
      ["9", "Zulu", "S9", "Pokemon"],
      ["10", "Beta", "S10", "Pokemon"],
      ["0010", "Gamma", "S0010", "Pokemon"],
      ["0", "Epsilon", "S0", "Pokemon"],
      ["000", "Delta", "S000", "Pokemon"],
      ["9223372036854775808", "Omega", "SBIG", "Pokemon"],
      ["A12", "Promo Alpha", "PROMO", "Pokemon"],
      ["sports:12", "Promo Sports", "PROMO2", "Pokemon"],
      ["hidden-empty", "Dragon Hidden", " ", "Pokemon"],
      ["99999", "Other Game", "PROMO", "Other"],
    ] as const) {
      await db.prepare("INSERT INTO sets (set_id, name, set_code, game) VALUES (?, ?, ?, ?)")
        .bind(id, name, code, game).run();
    }
  });

  afterAll(async () => { await db.close(); });

  it("sorts by numeric set_id with text fallback across pages rather than by name", async () => {
    const adapter = createLocalDbDataSourceAdapter(db);
    const pages = [];
    for (const page of [1, 2, 3]) {
      pages.push((await adapter.searchSets("", {
        game: "Pokemon", page, page_size: 4,
      })).map((set) => set.set_id));
    }
    expect(pages).toEqual([
      ["9223372036854775808", "700", "80", "10"],
      ["0010", "9", "000", "0"],
      ["sports:12", "A12"],
    ]);
    expect(new Set(pages.flat()).size).toBe(10);
  });

  it("keeps Game, keyword, and nonempty set_code filters without rewriting IDs", async () => {
    const adapter = createLocalDbDataSourceAdapter(db);
    expect((await adapter.searchSets("dragon", { game: "Pokemon" })).map((set) => set.set_id))
      .toEqual(["80"]);
    expect((await adapter.searchSets("promo", { game: "Pokemon" })).map((set) => set.set_id))
      .toEqual(["sports:12", "A12"]);
    expect((await adapter.searchSets("S0010", { game: "Pokemon" })).map((set) => set.set_id))
      .toEqual(["0010"]);
    expect((await adapter.searchSets("PROMO", { game: "Other" })).map((set) => set.set_id))
      .toEqual(["99999"]);
  });
});
