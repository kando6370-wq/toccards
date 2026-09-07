import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

describe("0033 billing exchange-rate snapshot migration", () => {
  let mf: Miniflare;
  let db: D1Database;

  beforeEach(async () => {
    mf = new Miniflare({ modules: true, script: "export default { fetch() { return new Response('ok') } }", compatibilityDate: "2024-11-01", d1Databases: ["DB"] });
    db = await mf.getD1Database("DB");
    await db.prepare("CREATE TABLE billing_transaction (id TEXT PRIMARY KEY, amount_usd_micros INTEGER)").run();
    await db.prepare("INSERT INTO billing_transaction VALUES ('historical-order', NULL)").run();
  });

  afterEach(async () => { await mf.dispose(); });

  it("adds nullable audit fields without inventing a historical exchange-rate snapshot", async () => {
    const sql = await readFile(join(dirname(fileURLToPath(import.meta.url)), "0033_billing_exchange_rate_snapshot.sql"), "utf8");
    for (const statement of sql.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean)) {
      await db.prepare(statement).run();
    }
    const row = await db.prepare(`SELECT amount_usd_micros, usd_exchange_rate,
      usd_exchange_rate_source, usd_conversion_version, usd_rounding_mode
      FROM billing_transaction WHERE id = 'historical-order'`).first();
    expect(row).toEqual({
      amount_usd_micros: null, usd_exchange_rate: null, usd_exchange_rate_source: null,
      usd_conversion_version: null, usd_rounding_mode: null,
    });
  });
});
