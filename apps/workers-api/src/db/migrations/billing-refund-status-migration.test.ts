import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

describe("0037 billing refund status migration", () => {
  let mf: Miniflare;
  let db: D1Database;

  beforeEach(async () => {
    mf = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      compatibilityDate: "2024-11-01",
      d1Databases: ["DB"],
    });
    db = await mf.getD1Database("DB");
    await db.prepare(`CREATE TABLE billing_transaction (
      id TEXT PRIMARY KEY, business_status TEXT
    )`).run();
    await db.prepare(`INSERT INTO billing_transaction (id, business_status)
      VALUES ('historical-refund', 'refunded')`).run();
  });

  afterEach(async () => { await mf.dispose(); });

  it("keeps historical refund provenance unknown instead of inventing a prior order status", async () => {
    const sql = await readFile(
      join(dirname(fileURLToPath(import.meta.url)), "0037_billing_refund_status.sql"),
      "utf8",
    );
    await db.prepare(sql).run();

    expect(await db.prepare(`SELECT business_status, business_status_before_refund
      FROM billing_transaction`).first()).toEqual({
      business_status: "refunded",
      business_status_before_refund: null,
    });
  });
});
