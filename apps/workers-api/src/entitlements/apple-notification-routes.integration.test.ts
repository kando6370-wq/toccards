import { Environment, type JWSRenewalInfoDecodedPayload, type JWSTransactionDecodedPayload, type ResponseBodyV2DecodedPayload } from "@apple/app-store-server-library";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { createAppleNotificationRoutes, retryAppleNotificationInbox } from "./apple-notification-routes";

const NOW = new Date("2026-08-12T10:10:00.000Z");

describe("Apple Notifications V2 durable consumption", () => {
  let mf: Miniflare;
  let db: D1Database;
  let env: Env;

  beforeEach(async () => {
    mf = new Miniflare({ modules: true, script: "export default { fetch() { return new Response('ok') } }", compatibilityDate: "2024-11-01", d1Databases: ["DB"] });
    db = await mf.getD1Database("DB");
    for (const statement of SCHEMA) await db.prepare(statement).run();
    await db.prepare("INSERT INTO billing_product (store, product_id, entitlement_id, active) VALUES ('app_store', 'yearly', 'performance_pro', 1)").run();
    await db.prepare(`INSERT INTO billing_purchase_chain
      (id, store, environment, original_transaction_id, product_id, entitlement_id,
       original_owner_type, original_owner_id, status, auto_renew, created_at, updated_at)
      VALUES ('chain-1', 'app_store', 'Sandbox', 'original-1', 'yearly', 'performance_pro',
              'anonymous', '100', 'ACTIVE', 1, ?, ?)`)
      .bind(NOW.toISOString(), NOW.toISOString()).run();
    await db.prepare(`INSERT INTO billing_session_entitlement_grant
      (id, session_id, purchase_chain_id, entitlement_id, source, status, granted_at, last_verified_at, updated_at)
      VALUES ('grant-1', 'session-1', 'chain-1', 'performance_pro', 'fresh_purchase', 'active', ?, ?, ?)`)
      .bind(NOW.toISOString(), NOW.toISOString(), NOW.toISOString()).run();
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "test", APP_ENVIRONMENT: "development" };
  });

  afterEach(async () => { await mf.dispose(); });

  it("preserves invalid evidence without any structured or entitlement side effect", async () => {
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({ verifyNotification: async () => { throw new Error("bad signature"); } }),
    }) });
    expect((await post(app, env, "invalid.jws")).status).toBe(200);
    expect(await scalar("SELECT COUNT(*) AS value FROM apple_notification_inbox")).toBe(1);
    expect(await scalar("SELECT COUNT(*) AS value FROM apple_server_notification")).toBe(0);
    expect((await db.prepare("SELECT processing_status FROM apple_notification_inbox").first())?.processing_status).toBe("verification_failed");
    expect((await db.prepare("SELECT status FROM billing_session_entitlement_grant").first())?.status).toBe("active");
  });

  it("creates an unlinked Apple order without granting Premium when no UID chain exists", async () => {
    await db.prepare("DELETE FROM billing_session_entitlement_grant").run();
    await db.prepare("DELETE FROM billing_purchase_chain").run();
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({
        verifyNotification: async () => notification("unlinked-uuid", "SUBSCRIBED", 10 * 60 + 5),
        verifyTransaction: async () => transaction({ transactionReason: "PURCHASE" }),
      }),
    }) });

    await post(app, env, "unlinked");

    expect(await db.prepare(`SELECT original_owner_type, original_owner_id, status
      FROM billing_purchase_chain`).first()).toMatchObject({
      original_owner_type: "unlinked",
      original_owner_id: "",
      status: "ACTIVE",
    });
    expect(await scalar("SELECT COUNT(*) AS value FROM billing_transaction")).toBe(1);
    expect(await scalar("SELECT COUNT(*) AS value FROM billing_session_entitlement_grant")).toBe(0);
    expect((await db.prepare("SELECT processing_status FROM apple_notification_inbox").first())?.processing_status).toBe("processed");
  });

  it("quarantines an order for an unconfigured SKU because verified Apple evidence must still belong to this app catalog", async () => {
    await db.prepare("DELETE FROM billing_session_entitlement_grant").run();
    await db.prepare("DELETE FROM billing_purchase_chain").run();
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({
        verifyNotification: async () => notification("unknown-sku-uuid", "SUBSCRIBED", 10 * 60 + 5),
        verifyTransaction: async () => transaction({ productId: "unknown.product", transactionReason: "PURCHASE" }),
      }),
    }) });

    await post(app, env, "unknown-sku");

    expect(await scalar("SELECT COUNT(*) AS value FROM billing_purchase_chain")).toBe(0);
    expect(await scalar("SELECT COUNT(*) AS value FROM billing_transaction")).toBe(0);
    expect((await db.prepare("SELECT processing_status FROM apple_notification_inbox").first())?.processing_status).toBe("correction_required");
  });

  it("deduplicates a renewal and ignores a later-delivered older lifecycle event", async () => {
    const events: Record<string, ResponseBodyV2DecodedPayload> = {
      renewal: notification("renewal-uuid", "DID_RENEW", 10 * 60 + 5),
      older: notification("older-uuid", "DID_FAIL_TO_RENEW", 10 * 60, "GRACE_PERIOD"),
    };
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({ verifyNotification: async (payload) => events[payload]! }),
    }) });
    await post(app, env, "renewal");
    await db.prepare("UPDATE billing_purchase_chain SET state_effective_at = '2026-08-12T10:06:00.000Z'").run();
    await post(app, env, "renewal");
    await post(app, env, "older");

    expect(await scalar("SELECT COUNT(*) AS value FROM billing_transaction")).toBe(1);
    expect(await db.prepare("SELECT business_status, charge_count FROM billing_transaction").first())
      .toMatchObject({ business_status: "renewal", charge_count: 1 });
    expect(await scalar("SELECT COUNT(*) AS value FROM apple_notification_inbox")).toBe(2);
    const chain = await db.prepare("SELECT status, lifecycle_notification_uuid FROM billing_purchase_chain").first();
    expect(chain).toMatchObject({ status: "ACTIVE", lifecycle_notification_uuid: "renewal-uuid" });
    expect((await db.prepare("SELECT status FROM billing_session_entitlement_grant").first())?.status).toBe("active");
  });

  it("recovers a business failure from the durable inbox", async () => {
    await db.exec("DROP TABLE billing_transaction");
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({ verifyNotification: async () => notification("retry-uuid", "DID_RENEW", 10 * 60 + 5) }),
    }) });
    await post(app, env, "retry");
    expect((await db.prepare("SELECT processing_status FROM apple_notification_inbox").first())?.processing_status).toBe("processing_failed");

    await db.prepare(TRANSACTION_SCHEMA).run();
    await retryAppleNotificationInbox(env, { now: () => new Date(NOW.getTime() + 1_000), createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({ verifyNotification: async () => notification("retry-uuid", "DID_RENEW", 10 * 60 + 5) }),
    }) });
    expect((await db.prepare("SELECT processing_status, attempts FROM apple_notification_inbox").first())).toMatchObject({ processing_status: "processed", attempts: 2 });
    expect(await scalar("SELECT COUNT(*) AS value FROM billing_transaction")).toBe(1);
  });

  it("quarantines a cross-environment payload without touching the Sandbox chain", async () => {
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({ verifyNotification: async () => ({
        ...notification("production-uuid", "DID_RENEW", 10 * 60 + 5),
        data: { environment: Environment.PRODUCTION, signedTransactionInfo: "transaction.jws" },
      }) }),
    }) });
    await post(app, env, "production");
    expect((await db.prepare("SELECT processing_status FROM apple_notification_inbox").first())?.processing_status).toBe("parse_failed");
    expect(await scalar("SELECT COUNT(*) AS value FROM billing_transaction")).toBe(0);
    expect((await db.prepare("SELECT status FROM billing_purchase_chain").first())?.status).toBe("ACTIVE");
  });

  it("updates auto-renew metadata without resurrecting an expired entitlement", async () => {
    await db.prepare("UPDATE billing_purchase_chain SET status = 'EXPIRED', auto_renew = 1").run();
    await db.prepare("UPDATE billing_session_entitlement_grant SET status = 'expired'").run();
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({
        verifyNotification: async () => notification("renewal-status-uuid", "DID_CHANGE_RENEWAL_STATUS", 10 * 60 + 5, "AUTO_RENEW_DISABLED"),
        verifyRenewal: async () => ({ originalTransactionId: "original-1", productId: "yearly", autoRenewStatus: 0, signedDate: Date.UTC(2026, 7, 12, 10, 5), environment: Environment.SANDBOX }),
      }),
    }) });
    await post(app, env, "renewal-status");
    expect(await db.prepare("SELECT status, auto_renew FROM billing_purchase_chain").first()).toMatchObject({ status: "EXPIRED", auto_renew: 0 });
    expect((await db.prepare("SELECT status FROM billing_session_entitlement_grant").first())?.status).toBe("expired");
  });

  it.each(["UPGRADE", "DOWNGRADE"])("records %s as a next-plan change without creating an order", async (subtype) => {
    await db.prepare("INSERT INTO billing_product (store, product_id, entitlement_id, active) VALUES ('app_store', 'weekly', 'performance_pro', 1)").run();
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({
        verifyNotification: async () => notification(`plan-${subtype}`, "DID_CHANGE_RENEWAL_PREF", 10 * 60 + 5, subtype),
        verifyRenewal: async () => ({ originalTransactionId: "original-1", productId: "yearly", autoRenewProductId: "weekly", autoRenewStatus: 1, signedDate: Date.UTC(2026, 7, 12, 10, 5), environment: Environment.SANDBOX }),
      }),
    }) });

    await post(app, env, `plan-${subtype}`);

    expect(await db.prepare("SELECT product_id, next_product_id, status FROM billing_purchase_chain").first()).toMatchObject({ product_id: "yearly", next_product_id: "weekly", status: "ACTIVE" });
    expect(await scalar("SELECT COUNT(*) AS value FROM billing_transaction")).toBe(0);
  });

  it("classifies RESUBSCRIBE by purchase chain instead of trusting PURCHASE reason alone", async () => {
    await db.prepare(`INSERT INTO billing_transaction
      (id, purchase_chain_id, store, environment, transaction_id, product_id,
       transaction_reason, status, business_status, charge_count, purchase_at, created_at, updated_at)
      VALUES ('order-first', 'chain-1', 'app_store', 'Sandbox', 'transaction-first', 'yearly',
              'PURCHASE', 'purchased', 'initial_purchase', 1, '2026-07-01T00:00:00.000Z', ?, ?)`)
      .bind(NOW.toISOString(), NOW.toISOString()).run();
    const sameChain = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({
        verifyNotification: async () => notification("resubscribe-same", "SUBSCRIBED", 10 * 60 + 5, "RESUBSCRIBE"),
        verifyTransaction: async () => transaction({ transactionId: "transaction-resubscribed", transactionReason: "PURCHASE" }),
      }),
    }) });

    await post(sameChain, env, "resubscribe-same");
    expect(await db.prepare("SELECT business_status, charge_count FROM billing_transaction WHERE transaction_id = 'transaction-resubscribed'").first()).toMatchObject({ business_status: "renewal", charge_count: 2 });

    await db.prepare("INSERT INTO billing_product (store, product_id, entitlement_id, active) VALUES ('app_store', 'weekly', 'performance_pro', 1)").run();
    const newChain = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({
        verifyNotification: async () => notification("resubscribe-new", "SUBSCRIBED", 10 * 60 + 6, "RESUBSCRIBE"),
        verifyTransaction: async () => transaction({ originalTransactionId: "original-new", transactionId: "transaction-new", productId: "weekly", transactionReason: "PURCHASE" }),
        verifyRenewal: async () => ({ originalTransactionId: "original-new", productId: "weekly", autoRenewStatus: 1, signedDate: Date.UTC(2026, 7, 12, 10, 6), environment: Environment.SANDBOX }),
      }),
    }) });

    await post(newChain, env, "resubscribe-new");
    expect(await db.prepare("SELECT business_status, charge_count FROM billing_transaction WHERE transaction_id = 'transaction-new'").first()).toMatchObject({ business_status: "initial_purchase", charge_count: 1 });
  });

  it("keeps Premium through Apple's grace-period expiry rather than the failed renewal date", async () => {
    const graceExpiry = NOW.getTime() + 3 * 86_400_000;
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({
        verifyNotification: async () => notification("grace-uuid", "DID_FAIL_TO_RENEW", 10 * 60 + 5, "GRACE_PERIOD"),
        verifyRenewal: async () => ({ originalTransactionId: "original-1", productId: "yearly", autoRenewStatus: 1, isInBillingRetryPeriod: true, gracePeriodExpiresDate: graceExpiry, signedDate: NOW.getTime(), environment: Environment.SANDBOX }),
      }),
    }) });
    await post(app, env, "grace");

    expect(await db.prepare("SELECT status, expires_at, grace_period_expires_at FROM billing_purchase_chain").first()).toMatchObject({ status: "GRACE_PERIOD", expires_at: new Date(graceExpiry).toISOString(), grace_period_expires_at: new Date(graceExpiry).toISOString() });
    expect(await db.prepare("SELECT status, expires_at FROM billing_session_entitlement_grant").first()).toMatchObject({ status: "active", expires_at: new Date(graceExpiry).toISOString() });
  });

  it("expires Premium during billing retry and restores it after Apple confirms recovery", async () => {
    const events: Record<string, ResponseBodyV2DecodedPayload> = {
      retry: notification("billing-retry-uuid", "DID_FAIL_TO_RENEW", 10 * 60 + 5),
      recovery: notification("billing-recovery-uuid", "DID_RENEW", 10 * 60 + 6),
    };
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({ verifyNotification: async (payload) => events[payload]! }),
    }) });

    await post(app, env, "retry");
    expect((await db.prepare("SELECT status FROM billing_purchase_chain").first())?.status).toBe("BILLING_RETRY");
    expect((await db.prepare("SELECT status FROM billing_session_entitlement_grant").first())?.status).toBe("expired");

    await post(app, env, "recovery");
    expect((await db.prepare("SELECT status FROM billing_purchase_chain").first())?.status).toBe("ACTIVE");
    expect((await db.prepare("SELECT status FROM billing_session_entitlement_grant").first())?.status).toBe("active");
    expect((await db.prepare("SELECT business_status FROM billing_transaction").first())?.business_status).toBe("billing_recovery");
  });

  it("expires Premium when Apple reports the subscription expired", async () => {
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({ verifyNotification: async () => notification("expired-uuid", "EXPIRED", 10 * 60 + 5) }),
    }) });

    await post(app, env, "expired");

    expect((await db.prepare("SELECT status FROM billing_purchase_chain").first())?.status).toBe("EXPIRED");
    expect((await db.prepare("SELECT status FROM billing_session_entitlement_grant").first())?.status).toBe("expired");
  });

  it("revokes Premium and marks the original order refunded after Apple confirms a refund", async () => {
    await db.prepare(`INSERT INTO billing_transaction
      (id, purchase_chain_id, store, environment, transaction_id, product_id,
       transaction_reason, status, business_status, purchase_at, created_at, updated_at)
      VALUES ('order-1', 'chain-1', 'app_store', 'Sandbox', 'transaction-1', 'yearly',
              'PURCHASE', 'purchased', 'first_paid', ?, ?, ?)`)
      .bind(NOW.toISOString(), NOW.toISOString(), NOW.toISOString()).run();
    const revokedAt = Date.UTC(2026, 7, 12, 10, 5);
    const app = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: verifier({
        verifyNotification: async () => notification("refund-uuid", "REFUND", 10 * 60 + 6),
        verifyTransaction: async () => transaction({ revocationDate: revokedAt }),
      }),
    }) });

    await post(app, env, "refund");

    expect(await db.prepare("SELECT status, revoked_at FROM billing_purchase_chain").first()).toMatchObject({ status: "REVOKED", revoked_at: new Date(revokedAt).toISOString() });
    expect((await db.prepare("SELECT status FROM billing_session_entitlement_grant").first())?.status).toBe("revoked");
    expect(await db.prepare("SELECT status, business_status, refund_completed_at FROM billing_transaction").first()).toMatchObject({ status: "refunded", business_status: "refunded", refund_completed_at: new Date(revokedAt).toISOString() });
  });

  async function scalar(sql: string): Promise<number> {
    return (await db.prepare(sql).first<{ value: number }>())?.value ?? 0;
  }
});

function verifier(options: {
  verifyNotification: (payload: string) => Promise<ResponseBodyV2DecodedPayload>;
  verifyTransaction?: () => Promise<JWSTransactionDecodedPayload>;
  verifyRenewal?: () => Promise<JWSRenewalInfoDecodedPayload>;
}) {
  return {
    verifyAndDecodeNotification: options.verifyNotification,
    async verifyAndDecodeTransaction(): Promise<JWSTransactionDecodedPayload> {
      if (options.verifyTransaction) return await options.verifyTransaction();
      return transaction();
    },
    async verifyAndDecodeRenewalInfo(): Promise<JWSRenewalInfoDecodedPayload> {
      if (options.verifyRenewal) return await options.verifyRenewal();
      return { originalTransactionId: "original-1", productId: "yearly", autoRenewStatus: 1, signedDate: Date.UTC(2026, 7, 12, 10, 5), environment: Environment.SANDBOX };
    },
  };
}

function transaction(overrides: Partial<JWSTransactionDecodedPayload> = {}): JWSTransactionDecodedPayload {
  return { originalTransactionId: "original-1", transactionId: "transaction-1", productId: "yearly", purchaseDate: Date.UTC(2026, 7, 12, 10, 5), expiresDate: Date.UTC(2027, 7, 12), signedDate: Date.UTC(2026, 7, 12, 10, 5), environment: Environment.SANDBOX, type: "Auto-Renewable Subscription", transactionReason: "RENEWAL", price: 49_990, currency: "USD", ...overrides };
}

function notification(uuid: string, type: string, minute: number, subtype?: string): ResponseBodyV2DecodedPayload {
  return { notificationUUID: uuid, notificationType: type, subtype, signedDate: Date.UTC(2026, 7, 12, 0, minute), data: { environment: Environment.SANDBOX, signedTransactionInfo: "transaction.jws", signedRenewalInfo: "renewal.jws" } };
}

async function post(app: ReturnType<typeof createAppleNotificationRoutes>, env: Env, signedPayload: string) {
  return await app.request("/apple/notifications/v2", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ signedPayload }) }, env);
}

const TRANSACTION_SCHEMA = `CREATE TABLE billing_transaction (
  id TEXT PRIMARY KEY, purchase_chain_id TEXT NOT NULL, store TEXT NOT NULL, environment TEXT NOT NULL,
  transaction_id TEXT NOT NULL, product_id TEXT NOT NULL, transaction_reason TEXT NOT NULL, status TEXT NOT NULL,
  business_status TEXT, charge_count INTEGER, source_notification_uuid TEXT,
  storefront_country_code TEXT, amount_micros INTEGER, currency TEXT, amount_usd_micros INTEGER,
  usd_exchange_rate TEXT, usd_exchange_rate_base TEXT, usd_exchange_rate_quote TEXT,
  usd_exchange_rate_source TEXT, usd_exchange_rate_effective_at TEXT, usd_exchange_rate_fetched_at TEXT,
  usd_exchange_rate_stale INTEGER, usd_conversion_version TEXT, usd_rounding_mode TEXT,
  purchase_at TEXT NOT NULL, expires_at TEXT, revoked_at TEXT, refund_completed_at TEXT,
  signed_transaction TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  UNIQUE(store, environment, transaction_id));`;

const SCHEMA = [
  "CREATE TABLE billing_product (store TEXT NOT NULL, product_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, active INTEGER NOT NULL, UNIQUE(store, product_id))",
  "CREATE TABLE billing_purchase_chain (id TEXT PRIMARY KEY, store TEXT NOT NULL, environment TEXT NOT NULL, original_transaction_id TEXT NOT NULL, product_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, original_owner_type TEXT NOT NULL, original_owner_id TEXT NOT NULL, status TEXT NOT NULL, auto_renew INTEGER NOT NULL, expires_at TEXT, grace_period_expires_at TEXT, revoked_at TEXT, state_effective_at TEXT, next_product_id TEXT, lifecycle_signed_at TEXT, lifecycle_notification_uuid TEXT, correction_status TEXT, auto_renew_signed_at TEXT, plan_signed_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(store, environment, original_transaction_id))",
  "CREATE TABLE billing_session_entitlement_grant (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, purchase_chain_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, source TEXT NOT NULL, status TEXT NOT NULL, granted_at TEXT NOT NULL, expires_at TEXT, last_verified_at TEXT NOT NULL, revoked_at TEXT, updated_at TEXT NOT NULL)",
  TRANSACTION_SCHEMA,
  "CREATE TABLE apple_notification_inbox (id TEXT PRIMARY KEY, payload_sha256 TEXT NOT NULL UNIQUE, request_json TEXT NOT NULL, signed_payload TEXT NOT NULL, processing_status TEXT NOT NULL, attempts INTEGER NOT NULL, processing_expires_at TEXT, notification_uuid TEXT, last_error TEXT, received_at TEXT NOT NULL, processed_at TEXT)",
  "CREATE TABLE apple_server_notification (id TEXT PRIMARY KEY, inbox_id TEXT UNIQUE, notification_uuid TEXT NOT NULL UNIQUE, notification_type TEXT NOT NULL, subtype TEXT, environment TEXT NOT NULL, original_transaction_id TEXT, transaction_id TEXT, product_id TEXT, signed_payload TEXT NOT NULL, decoded_payload TEXT, processing_status TEXT NOT NULL, attempts INTEGER NOT NULL, last_error TEXT, signed_at TEXT, received_at TEXT NOT NULL, processed_at TEXT)",
];
