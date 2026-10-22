import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { PGliteDatabase } from "../../test-support/pglite-database";

const NOW = "2026-10-21T00:00:00.000Z";

describe("trial conversion status PostgreSQL migration", () => {
  let db: PGliteDatabase;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    const migrations = new URL("./migrations/", import.meta.url);
    for (const name of ["0000_business_schema.sql", "0007_billing_refund_status.sql"]) {
      await db.exec(readFileSync(new URL(name, migrations), "utf8"));
    }
    await db.prepare(`INSERT INTO app_config(key, value, updated_at) VALUES (?, ?, ?)`)
      .bind("billing.apple.admission:development:example.app", JSON.stringify({
        "trial.week": {
          product_id: "trial.week", plan_id: "apple:trial.week", product_type: "subscription",
          is_trial_product: true, singular_event_name: "trial_week", approved_by: "admin", approved_at: NOW,
        },
        "normal.week": {
          product_id: "normal.week", plan_id: "apple:normal.week", product_type: "subscription",
          is_trial_product: false, singular_event_name: "normal_week", approved_by: "admin", approved_at: NOW,
        },
      }), NOW).run();
    for (const id of ["trial", "normal", "zero", "refunded", "unconfirmed"]) {
      await db.prepare(`INSERT INTO billing_purchase_chain
        (id, store, environment, original_transaction_id, product_id, entitlement_id,
         original_owner_type, original_owner_id, status, created_at, updated_at)
        VALUES (?, 'app_store', 'Sandbox', ?, 'trial.week', 'performance_pro',
                'anonymous', '100000', 'ACTIVE', ?, ?)`)
        .bind(`chain-${id}`, `original-${id}`, NOW, NOW).run();
    }
    await insert("trial-first", "trial", "trial-1", "trial.week", "renewal", 1_000_000,
      "2026-10-01T00:00:00.000Z", "notification-trial-1");
    await insert("trial-second", "trial", "trial-2", "trial.week", "renewal", 1_000_000,
      "2026-10-08T00:00:00.000Z", "notification-trial-2");
    await insert("normal-first", "normal", "normal-1", "normal.week", "renewal", 1_000_000,
      "2026-10-01T00:00:00.000Z", "notification-normal-1");
    await insert("trial-zero", "zero", "zero-1", "trial.week", "renewal", 0,
      "2026-10-01T00:00:00.000Z", "notification-zero-1");
    await insert("trial-refunded", "refunded", "refund-1", "trial.week", "refunded", 1_000_000,
      "2026-10-01T00:00:00.000Z", "notification-refund-1", "renewal");
    await insert("trial-unconfirmed", "unconfirmed", "unconfirmed-1", "trial.week", "renewal", 1_000_000,
      "2026-10-01T00:00:00.000Z", null);
  });

  afterEach(async () => { await db.close(); });

  it("backfills only the first confirmed positive renewal of a registered trial SKU", async () => {
    const migration = readFileSync(new URL("./migrations/0015_trial_conversion_status.sql", import.meta.url), "utf8");
    await db.exec(migration);
    await db.exec(migration);

    expect((await db.prepare(`SELECT transaction_id, business_status, business_status_before_refund
      FROM billing_transaction ORDER BY transaction_id`).all()).results).toEqual([
      { transaction_id: "normal-1", business_status: "renewal", business_status_before_refund: null },
      { transaction_id: "refund-1", business_status: "refunded", business_status_before_refund: "trial_conversion" },
      { transaction_id: "trial-1", business_status: "trial_conversion", business_status_before_refund: null },
      { transaction_id: "trial-2", business_status: "renewal", business_status_before_refund: null },
      { transaction_id: "unconfirmed-1", business_status: "renewal", business_status_before_refund: null },
      { transaction_id: "zero-1", business_status: "renewal", business_status_before_refund: null },
    ]);
  });

  async function insert(
    id: string,
    chain: string,
    transactionId: string,
    productId: string,
    businessStatus: string,
    amountMicros: number,
    purchaseAt: string,
    sourceNotificationUuid: string | null,
    businessStatusBeforeRefund: string | null = null,
  ) {
    await db.prepare(`INSERT INTO billing_transaction
      (id, purchase_chain_id, store, environment, transaction_id, product_id,
       transaction_reason, status, business_status, business_status_before_refund,
       source_notification_uuid, amount_micros, purchase_at, created_at, updated_at)
      VALUES (?, ?, 'app_store', 'Sandbox', ?, ?, 'RENEWAL', 'purchased', ?, ?, ?, ?, ?, ?, ?)`)
      .bind(id, `chain-${chain}`, transactionId, productId, businessStatus, businessStatusBeforeRefund,
        sourceNotificationUuid, amountMicros, purchaseAt, NOW, NOW).run();
  }
});
