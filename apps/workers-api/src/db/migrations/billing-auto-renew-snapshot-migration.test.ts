import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

describe("0034 billing auto-renew snapshot migration", () => {
  let mf: Miniflare;
  let db: D1Database;

  beforeEach(async () => {
    mf = new Miniflare({ modules: true, script: "export default { fetch() { return new Response('ok') } }", compatibilityDate: "2024-11-01", d1Databases: ["DB"] });
    db = await mf.getD1Database("DB");
    await db.prepare("CREATE TABLE billing_transaction (id TEXT PRIMARY KEY)").run();
    await db.prepare("INSERT INTO billing_transaction VALUES ('historical-order')").run();
  });

  afterEach(async () => { await mf.dispose(); });

  it("keeps historical auto-renew unknown because the current chain state is not an order snapshot", async () => {
    const sql = await readFile(join(dirname(fileURLToPath(import.meta.url)), "0034_billing_auto_renew_snapshot.sql"), "utf8");
    await db.prepare(sql).run();

    expect(await db.prepare(`SELECT auto_renew_snapshot
      FROM billing_transaction WHERE id = 'historical-order'`).first()).toEqual({
      auto_renew_snapshot: null,
    });
    await expect(db.prepare("UPDATE billing_transaction SET auto_renew_snapshot = 2").run()).rejects.toThrow();
  });
});
