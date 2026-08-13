import { signAccessToken } from "@kando/auth-core";
import { Environment, type JWSTransactionDecodedPayload } from "@apple/app-store-server-library";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { createEntitlementRoutes } from "./routes";

const NOW = new Date("2026-08-13T08:00:00.000Z");
const PRODUCT_ID = "com.cardai.tcg.pro.yearly";
const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174010";

describe("Apple Fresh Purchase routes", () => {
  let mf: Miniflare;
  let db: D1Database;
  let env: Env;

  beforeEach(async () => {
    mf = new Miniflare({ modules: true, script: "export default { fetch() { return new Response('ok') } }", compatibilityDate: "2024-11-01", d1Databases: ["DB"] });
    db = await mf.getD1Database("DB");
    await db.exec(SCHEMA);
    await db.batch([
      db.prepare("INSERT INTO anonymous_account VALUES ('100000', NULL)"),
      db.prepare("INSERT INTO session VALUES ('session-a', 'anonymous', '100000', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO billing_product VALUES ('app_store', ?, 'performance_pro', 1)").bind(PRODUCT_ID),
    ]);
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "fresh-purchase-test", APP_ENVIRONMENT: "development", APPLE_IAP_PRODUCT_IDS: PRODUCT_ID };
  });

  afterEach(async () => { await mf.dispose(); });

  it("consumes the session challenge and keeps subscription auto-renew unknown without renewal evidence", async () => {
    let appAccountToken = "";
    const app = createEntitlementRoutes({
      now: () => NOW,
      createVerifier: () => ({
        environment: Environment.SANDBOX,
        verifier: { async verifyAndDecodeTransaction() { return transaction(appAccountToken); } },
      }),
    });
    const token = await signAccessToken(
      { owner_type: "anonymous", owner_id: "100000", session_id: "session-a" },
      env.JWT_SECRET!,
    );
    const authorization = { authorization: `Bearer ${token}`, "content-type": "application/json" };
    const challengeResponse = await app.request("/entitlements/apple/purchase-challenge", {
      method: "POST", headers: authorization, body: JSON.stringify({ product_id: PRODUCT_ID }),
    }, env);
    expect(challengeResponse.status).toBe(201);
    appAccountToken = ((await challengeResponse.json()) as any).data.application_account_token;

    const verified = await app.request("/entitlements/apple/verify", {
      method: "POST",
      headers: { ...authorization, "Idempotency-Key": REQUEST_ID },
      body: JSON.stringify({
        schema_version: 1,
        evidence_type: "storekit2_signed_transaction",
        request_id: REQUEST_ID,
        signed_transaction_info: "fresh.purchase.jws",
      }),
    }, env);

    expect(verified.status).toBe(200);
    expect(await db.prepare(`SELECT auto_renew_snapshot, business_status, charge_count
      FROM billing_transaction`).first()).toEqual({
      auto_renew_snapshot: null,
      business_status: "initial_purchase",
      charge_count: 1,
    });
    expect(await db.prepare("SELECT session_id, status FROM billing_session_entitlement_grant").first())
      .toEqual({ session_id: "session-a", status: "active" });
    expect((await db.prepare("SELECT consumed_transaction_id FROM billing_apple_purchase_challenge").first())?.consumed_transaction_id)
      .toBe("transaction-fresh");
  });
});

function transaction(appAccountToken: string): JWSTransactionDecodedPayload {
  return {
    originalTransactionId: "original-fresh",
    transactionId: "transaction-fresh",
    productId: PRODUCT_ID,
    purchaseDate: NOW.getTime() - 1_000,
    expiresDate: NOW.getTime() + 86_400_000,
    signedDate: NOW.getTime(),
    type: "Auto-Renewable Subscription",
    appAccountToken,
    environment: Environment.SANDBOX,
    transactionReason: "PURCHASE",
    price: 49_990,
    currency: "USD",
  };
}

const SCHEMA = `
CREATE TABLE anonymous_account (id TEXT PRIMARY KEY, upgraded_user_id TEXT);
CREATE TABLE user (id TEXT PRIMARY KEY, status TEXT);
CREATE TABLE session (id TEXT PRIMARY KEY, owner_type TEXT, owner_id TEXT, expires_at TEXT, revoked_at TEXT);
CREATE TABLE billing_product (store TEXT, product_id TEXT, entitlement_id TEXT, active INTEGER, UNIQUE(store, product_id));
CREATE TABLE billing_purchase_chain (id TEXT PRIMARY KEY, store TEXT, environment TEXT, original_transaction_id TEXT, product_id TEXT, entitlement_id TEXT, original_owner_type TEXT, original_owner_id TEXT, app_account_token TEXT, status TEXT, auto_renew INTEGER, expires_at TEXT, grace_period_expires_at TEXT, revoked_at TEXT, state_effective_at TEXT, created_at TEXT, updated_at TEXT, UNIQUE(store, environment, original_transaction_id));
CREATE TABLE billing_apple_purchase_challenge (token TEXT PRIMARY KEY, session_id TEXT, product_id TEXT, expires_at TEXT, consumed_at TEXT, consumed_transaction_id TEXT, created_at TEXT);
CREATE TABLE billing_apple_verification_attempt (id TEXT PRIMARY KEY, session_id TEXT, request_id TEXT, evidence_type TEXT, evidence_sha256 TEXT, result_code TEXT, transaction_id TEXT, response_json TEXT, http_status INTEGER, processing_expires_at TEXT, created_at TEXT, UNIQUE(session_id, request_id));
CREATE TABLE billing_transaction (id TEXT PRIMARY KEY, purchase_chain_id TEXT, store TEXT, environment TEXT, transaction_id TEXT, product_id TEXT, transaction_reason TEXT, status TEXT, business_status TEXT, charge_count INTEGER, source_notification_uuid TEXT, auto_renew_snapshot INTEGER, storefront_country_code TEXT, amount_micros INTEGER, currency TEXT, amount_usd_micros INTEGER, usd_exchange_rate TEXT, usd_exchange_rate_base TEXT, usd_exchange_rate_quote TEXT, usd_exchange_rate_source TEXT, usd_exchange_rate_effective_at TEXT, usd_exchange_rate_fetched_at TEXT, usd_exchange_rate_stale INTEGER, usd_conversion_version TEXT, usd_rounding_mode TEXT, purchase_at TEXT, expires_at TEXT, revoked_at TEXT, signed_transaction TEXT, created_at TEXT, updated_at TEXT, UNIQUE(store, environment, transaction_id));
CREATE TABLE billing_session_entitlement_grant (id TEXT PRIMARY KEY, session_id TEXT, purchase_chain_id TEXT, entitlement_id TEXT, source TEXT, status TEXT, granted_at TEXT, expires_at TEXT, last_verified_at TEXT, revoked_at TEXT, updated_at TEXT, UNIQUE(session_id, purchase_chain_id, entitlement_id));
`;
