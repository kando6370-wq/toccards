import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

describe("0032 billing order facts migration", () => {
  let mf: Miniflare;
  let db: D1Database;

  beforeEach(async () => {
    mf = new Miniflare({ modules: true, script: "export default { fetch() { return new Response('ok') } }", compatibilityDate: "2024-11-01", d1Databases: ["DB"] });
    db = await mf.getD1Database("DB");
    await db.prepare(`CREATE TABLE billing_transaction (
      id TEXT PRIMARY KEY, purchase_chain_id TEXT NOT NULL, environment TEXT NOT NULL,
      transaction_id TEXT NOT NULL, transaction_reason TEXT NOT NULL, status TEXT NOT NULL,
      amount_micros INTEGER, purchase_at TEXT NOT NULL
    )`).run();
    await db.batch([
      row("trial", "trial-0", "PURCHASE", "purchased", 0, "2026-01-01T00:00:00.000Z"),
      row("paid-2", "transaction-2", "RENEWAL", "purchased", 5000000, "2026-02-01T00:00:00.000Z"),
      row("paid-1", "transaction-1", "RENEWAL", "refunded", 5000000, "2026-02-01T00:00:00.000Z"),
      row("unknown", "transaction-unknown", "PURCHASE", "purchased", null, "2026-03-01T00:00:00.000Z"),
    ]);
  });

  afterEach(async () => { await mf.dispose(); });

  it("backfills only provable facts and uses the runtime transaction ordering", async () => {
    const sql = await readFile(join(dirname(fileURLToPath(import.meta.url)), "0032_billing_order_facts.sql"), "utf8");
    for (const statement of sql.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean)) {
      await db.prepare(statement).run();
    }
    const result = await db.prepare(`SELECT transaction_id, business_status, charge_count
      FROM billing_transaction ORDER BY purchase_at, transaction_id`).all();
    expect(result.results).toEqual([
      { transaction_id: "trial-0", business_status: "trial", charge_count: 0 },
      { transaction_id: "transaction-1", business_status: "refunded", charge_count: 1 },
      { transaction_id: "transaction-2", business_status: "renewal", charge_count: 2 },
      { transaction_id: "transaction-unknown", business_status: "initial_purchase", charge_count: null },
    ]);
  });

  function row(id: string, transactionId: string, reason: string, status: string, amount: number | null, purchaseAt: string) {
    return db.prepare(`INSERT INTO billing_transaction
      (id, purchase_chain_id, environment, transaction_id, transaction_reason, status, amount_micros, purchase_at)
      VALUES (?, 'chain-1', 'Sandbox', ?, ?, ?, ?, ?)`)
      .bind(id, transactionId, reason, status, amount, purchaseAt);
  }
});
