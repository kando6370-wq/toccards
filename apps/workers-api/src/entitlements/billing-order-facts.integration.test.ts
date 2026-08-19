import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { billingOrderFactStatements, businessStatusForAppleTransaction } from "./billing-order-facts";

describe("billing order facts", () => {
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
      id TEXT PRIMARY KEY, purchase_chain_id TEXT NOT NULL, environment TEXT NOT NULL,
      transaction_id TEXT NOT NULL, purchase_at TEXT NOT NULL,
      business_status TEXT, charge_count INTEGER, source_notification_uuid TEXT
    )`).run();
  });

  afterEach(async () => { await mf.dispose(); });

  it("keeps trial free and deterministically renumbers paid transactions after an older transaction arrives", async () => {
    await insert("trial", "t-0", "2026-01-01T00:00:00.000Z", "trial");
    await insert("later", "t-2", "2026-03-01T00:00:00.000Z", "renewal");
    await recalculate();
    expect(await rows()).toEqual([
      { transaction_id: "t-0", business_status: "trial", charge_count: 0 },
      { transaction_id: "t-2", business_status: "trial_conversion", charge_count: 1 },
    ]);

    await insert("earlier", "t-1", "2026-02-01T00:00:00.000Z", "renewal");
    await recalculate();
    expect(await rows()).toEqual([
      { transaction_id: "t-0", business_status: "trial", charge_count: 0 },
      { transaction_id: "t-1", business_status: "trial_conversion", charge_count: 1 },
      { transaction_id: "t-2", business_status: "renewal", charge_count: 2 },
    ]);
  });

  it("preserves a refunded order's paid sequence number", async () => {
    await insert("paid", "t-1", "2026-01-01T00:00:00.000Z", "refunded");
    await recalculate();
    expect(await rows()).toEqual([
      { transaction_id: "t-1", business_status: "refunded", charge_count: 1 },
    ]);
  });

  it("classifies a same-chain resubscribe as renewal because only the first paid transaction is initial", async () => {
    await insert("first", "t-1", "2026-01-01T00:00:00.000Z", "initial_purchase");
    await insert("resubscribe", "t-2", "2026-02-01T00:00:00.000Z", "initial_purchase");
    await recalculate();

    expect(await rows()).toEqual([
      { transaction_id: "t-1", business_status: "initial_purchase", charge_count: 1 },
      { transaction_id: "t-2", business_status: "renewal", charge_count: 2 },
    ]);
  });

  it("does not let client proof affect Admin charge order before an Apple notification promotes it", async () => {
    await insert("client-only", "t-1", "2026-01-01T00:00:00.000Z", "initial_purchase", null);
    await insert("notification-order", "t-2", "2026-02-01T00:00:00.000Z", "renewal");
    await recalculate();

    expect(await rows()).toEqual([
      { transaction_id: "t-1", business_status: "initial_purchase", charge_count: null },
      { transaction_id: "t-2", business_status: "renewal", charge_count: 1 },
    ]);
  });

  it("does not infer trial conversion without a proven trial transaction", () => {
    expect(businessStatusForAppleTransaction("DID_RENEW", "ACTIVE", {
      transactionReason: "RENEWAL",
    })).toBe("renewal");
    expect(businessStatusForAppleTransaction("SUBSCRIBED", "ACTIVE", {
      transactionReason: "PURCHASE",
      offerDiscountType: "FREE_TRIAL",
    })).toBe("trial");
  });

  async function insert(
    id: string,
    transactionId: string,
    purchaseAt: string,
    status: string,
    sourceNotificationUuid: string | null = `notification-${id}`,
  ) {
    await db.prepare(`INSERT INTO billing_transaction
      (id, purchase_chain_id, environment, transaction_id, purchase_at, business_status,
       source_notification_uuid)
      VALUES (?, 'chain-1', 'Sandbox', ?, ?, ?, ?)`)
      .bind(id, transactionId, purchaseAt, status, sourceNotificationUuid).run();
  }

  async function recalculate() {
    await db.batch(billingOrderFactStatements(db, "chain-1", "Sandbox"));
  }

  async function rows() {
    const result = await db.prepare(`SELECT transaction_id, business_status, charge_count
      FROM billing_transaction ORDER BY purchase_at, transaction_id`).all();
    return result.results;
  }
});
