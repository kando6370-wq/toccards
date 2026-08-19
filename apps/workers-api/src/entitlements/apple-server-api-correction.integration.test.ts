import { Environment, Status, type JWSRenewalInfoDecodedPayload, type JWSTransactionDecodedPayload } from "@apple/app-store-server-library";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { retryAppleServerApiCorrections } from "./apple-server-api-correction";

const NOW = new Date("2026-08-12T11:00:00.000Z");

describe("Apple Server API purchase-chain correction", () => {
  let mf: Miniflare;
  let db: D1Database;
  let env: Env;

  beforeEach(async () => {
    mf = new Miniflare({ modules: true, script: "export default { fetch() { return new Response('ok') } }", compatibilityDate: "2024-11-01", d1Databases: ["DB"] });
    db = await mf.getD1Database("DB");
    for (const statement of SCHEMA) await db.prepare(statement).run();
    await db.batch([
      db.prepare("INSERT INTO billing_purchase_chain (id, store, environment, original_transaction_id, product_id, entitlement_id, original_owner_type, original_owner_id, status, auto_renew, revoked_at, created_at, updated_at) VALUES ('chain-1', 'app_store', 'Sandbox', 'original-1', 'yearly', 'performance_pro', 'anonymous', '100', 'REVOKED', 0, ?, ?, ?)").bind(NOW.toISOString(), NOW.toISOString(), NOW.toISOString()),
      db.prepare("INSERT INTO billing_session_entitlement_grant (id, session_id, purchase_chain_id, entitlement_id, source, status, granted_at, last_verified_at, revoked_at, updated_at) VALUES ('grant-1', 'session-1', 'chain-1', 'performance_pro', 'restore', 'revoked', ?, ?, ?, ?)").bind(NOW.toISOString(), NOW.toISOString(), NOW.toISOString(), NOW.toISOString()),
      db.prepare("INSERT INTO billing_transaction (id, purchase_chain_id, store, environment, transaction_id, product_id, transaction_reason, status, purchase_at, revoked_at, refund_completed_at, created_at, updated_at) VALUES ('order-1', 'chain-1', 'app_store', 'Sandbox', 'transaction-1', 'yearly', 'PURCHASE', 'refunded', ?, ?, ?, ?, ?)").bind(NOW.toISOString(), NOW.toISOString(), NOW.toISOString(), NOW.toISOString(), NOW.toISOString()),
      db.prepare("INSERT INTO apple_notification_inbox (id, environment, payload_sha256, request_json, signed_payload, processing_status, attempts, received_at) VALUES ('inbox-1', 'Sandbox', 'hash-1', '{}', 'jws', 'correction_required', 1, ?)").bind(NOW.toISOString()),
      db.prepare("INSERT INTO apple_server_notification (id, inbox_id, notification_uuid, notification_type, environment, original_transaction_id, transaction_id, signed_payload, processing_status, attempts, received_at) VALUES ('notification-1', 'inbox-1', 'uuid-1', 'REFUND_REVERSED', 'Sandbox', 'original-1', 'transaction-1', 'jws', 'correction_required', 1, ?)").bind(NOW.toISOString()),
    ]);
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "test", APP_ENVIRONMENT: "development" };
  });

  afterEach(async () => { await mf.dispose(); });

  it("uses inbox id as the correction batch tie-breaker because equal receive times need deterministic selection", async () => {
    const preparedSql: string[] = [];
    const statement = {
      bind: (..._values: unknown[]) => statement,
      all: async () => ({ results: [] }),
    };
    const captureDb = {
      prepare: (sql: string) => {
        preparedSql.push(sql.replace(/\s+/g, " ").trim());
        return statement;
      },
    } as unknown as D1Database;

    await retryAppleServerApiCorrections({ ...env, DB: captureDb });

    expect(preparedSql[0]).toContain(
      "ORDER BY i.received_at ASC, i.id ASC LIMIT ?",
    );
  });

  it("restores only the affected transaction and existing grants from current Apple-signed status", async () => {
    await retryAppleServerApiCorrections(env, dependencies());

    expect(await db.prepare("SELECT status, revoked_at, correction_status FROM billing_purchase_chain").first()).toMatchObject({ status: "ACTIVE", revoked_at: null, correction_status: "server_api_verified" });
    expect(await db.prepare("SELECT status, revoked_at FROM billing_session_entitlement_grant").first()).toMatchObject({ status: "active", revoked_at: null });
    expect(await db.prepare("SELECT status, revoked_at, refund_completed_at FROM billing_transaction WHERE transaction_id = 'transaction-1'").first()).toMatchObject({ status: "purchased", revoked_at: null, refund_completed_at: null });
    expect((await db.prepare("SELECT processing_status FROM apple_notification_inbox").first())?.processing_status).toBe("processed");
  });

  it("rejects Apple evidence for another chain and keeps the correction retryable", async () => {
    await retryAppleServerApiCorrections(env, dependencies({ originalTransactionId: "other-chain" }));

    expect((await db.prepare("SELECT status FROM billing_purchase_chain").first())?.status).toBe("REVOKED");
    expect(await db.prepare("SELECT processing_status, last_error FROM apple_notification_inbox").first()).toMatchObject({ processing_status: "correction_required", last_error: "SERVER_API_EVIDENCE_MISMATCH" });
  });

  it("keeps transient Apple API failure retryable without changing lifecycle or grants", async () => {
    await retryAppleServerApiCorrections(env, {
      now: () => NOW,
      createClient: () => ({
        async getAllSubscriptionStatuses() { throw new Error("temporary"); },
        async getTransactionInfo() { throw new Error("temporary"); },
      }),
      createVerifier: dependencies().createVerifier,
    });

    expect((await db.prepare("SELECT status FROM billing_purchase_chain").first())?.status).toBe("REVOKED");
    expect((await db.prepare("SELECT status FROM billing_session_entitlement_grant").first())?.status).toBe("revoked");
    expect(await db.prepare("SELECT processing_status, last_error FROM apple_notification_inbox").first()).toMatchObject({ processing_status: "correction_required", last_error: "SERVER_API_REQUEST_FAILED" });
  });

  it("does not reserve Production corrections from the dev cron because shared leases are environment-scoped", async () => {
    await db.batch([
      db.prepare("INSERT INTO apple_notification_inbox (id, environment, payload_sha256, request_json, signed_payload, processing_status, attempts, received_at) VALUES ('inbox-production', 'Production', 'hash-production', '{}', 'prod-jws', 'correction_required', 1, ?)").bind(NOW.toISOString()),
      db.prepare("INSERT INTO apple_server_notification (id, inbox_id, notification_uuid, notification_type, environment, original_transaction_id, transaction_id, signed_payload, processing_status, attempts, received_at) VALUES ('notification-production', 'inbox-production', 'uuid-production', 'REFUND_REVERSED', 'Production', 'original-production', 'transaction-production', 'prod-jws', 'correction_required', 1, ?)").bind(NOW.toISOString()),
    ]);

    await retryAppleServerApiCorrections(env, dependencies());

    expect(await db.prepare(
      "SELECT processing_status, attempts FROM apple_notification_inbox WHERE id = 'inbox-production'",
    ).first()).toMatchObject({ processing_status: "correction_required", attempts: 1 });
  });
});

function dependencies(overrides: Partial<JWSTransactionDecodedPayload> = {}) {
  const transaction: JWSTransactionDecodedPayload = {
    originalTransactionId: "original-1", transactionId: "transaction-current", productId: "yearly",
    purchaseDate: NOW.getTime(), expiresDate: NOW.getTime() + 86_400_000,
    signedDate: NOW.getTime(), environment: Environment.SANDBOX,
    type: "Auto-Renewable Subscription", transactionReason: "RENEWAL", ...overrides,
  };
  const renewal: JWSRenewalInfoDecodedPayload = {
    originalTransactionId: "original-1", productId: "yearly", autoRenewStatus: 1,
    signedDate: NOW.getTime(), environment: Environment.SANDBOX,
  };
  return {
    now: () => NOW,
    createClient: () => ({
      async getAllSubscriptionStatuses() {
        return { environment: Environment.SANDBOX, data: [{ lastTransactions: [{ status: Status.ACTIVE, originalTransactionId: "original-1", signedTransactionInfo: "transaction.jws", signedRenewalInfo: "renewal.jws" }] }] };
      },
      async getTransactionInfo() { return { signedTransactionInfo: "transaction.jws" }; },
    }),
    createVerifier: () => ({
      environment: Environment.SANDBOX,
      verifier: {
        async verifyAndDecodeNotification() { throw new Error("unused"); },
        async verifyAndDecodeTransaction() { return transaction; },
        async verifyAndDecodeRenewalInfo() { return renewal; },
      },
    }),
  };
}

const SCHEMA = [
  "CREATE TABLE billing_purchase_chain (id TEXT PRIMARY KEY, store TEXT NOT NULL, environment TEXT NOT NULL, original_transaction_id TEXT NOT NULL, product_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, original_owner_type TEXT NOT NULL, original_owner_id TEXT NOT NULL, status TEXT NOT NULL, auto_renew INTEGER NOT NULL, expires_at TEXT, grace_period_expires_at TEXT, revoked_at TEXT, state_effective_at TEXT, next_product_id TEXT, correction_status TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(store, environment, original_transaction_id))",
  "CREATE TABLE billing_session_entitlement_grant (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, purchase_chain_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, source TEXT NOT NULL, status TEXT NOT NULL, granted_at TEXT NOT NULL, expires_at TEXT, last_verified_at TEXT NOT NULL, revoked_at TEXT, updated_at TEXT NOT NULL)",
  "CREATE TABLE billing_transaction (id TEXT PRIMARY KEY, purchase_chain_id TEXT NOT NULL, store TEXT NOT NULL, environment TEXT NOT NULL, transaction_id TEXT NOT NULL, product_id TEXT NOT NULL, transaction_reason TEXT NOT NULL, status TEXT NOT NULL, purchase_at TEXT NOT NULL, expires_at TEXT, revoked_at TEXT, refund_completed_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
  "CREATE TABLE apple_notification_inbox (id TEXT PRIMARY KEY, environment TEXT NOT NULL, payload_sha256 TEXT NOT NULL, request_json TEXT NOT NULL, signed_payload TEXT NOT NULL, processing_status TEXT NOT NULL, attempts INTEGER NOT NULL, processing_expires_at TEXT, notification_uuid TEXT, last_error TEXT, received_at TEXT NOT NULL, processed_at TEXT, UNIQUE(environment, payload_sha256))",
  "CREATE TABLE apple_server_notification (id TEXT PRIMARY KEY, inbox_id TEXT UNIQUE, notification_uuid TEXT NOT NULL UNIQUE, notification_type TEXT NOT NULL, environment TEXT NOT NULL, original_transaction_id TEXT, transaction_id TEXT, signed_payload TEXT NOT NULL, processing_status TEXT NOT NULL, attempts INTEGER NOT NULL, last_error TEXT, received_at TEXT NOT NULL, processed_at TEXT)",
];
