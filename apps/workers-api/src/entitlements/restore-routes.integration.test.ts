import { signAccessToken } from "@kando/auth-core";
import { Environment, type JWSTransactionDecodedPayload } from "@apple/app-store-server-library";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { createAppleRestoreRoutes } from "./restore-routes";

const NOW = new Date("2026-08-12T08:00:00.000Z");
const KEY_ID = "a2V5LWlk";
const PRODUCT_ID = "com.cardai.tcg.pro.yearly";
const JWS = "apple.restore.jws";

describe("Apple Restore proof routes", () => {
  let miniflare: Miniflare;
  let db: D1Database;
  let env: Env;

  beforeEach(async () => {
    miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      compatibilityDate: "2024-11-01",
      d1Databases: ["DB"],
    });
    db = await miniflare.getD1Database("DB");
    await db.exec(SCHEMA);
    await db.batch([
      db.prepare("INSERT INTO anonymous_account (id, upgraded_user_id) VALUES ('100000', NULL)"),
      db.prepare("INSERT INTO session (id, owner_type, owner_id, expires_at, revoked_at) VALUES ('session-a', 'anonymous', '100000', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO session (id, owner_type, owner_id, expires_at, revoked_at) VALUES ('session-b', 'anonymous', '100000', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO billing_product (store, product_id, entitlement_id, active) VALUES ('app_store', ?, 'performance_pro', 1)").bind(PRODUCT_ID),
    ]);
    env = {
      DB: db,
      CACHE_KV: {} as KVNamespace,
      JWT_SECRET: "restore-test-secret",
      APP_ENVIRONMENT: "development",
      APPLE_APP_ATTEST_APP_ID: "B95U3272HR.com.cardai.tcg",
      APPLE_APP_ATTEST_DEVELOPMENT: "true",
      APPLE_IAP_PRODUCT_IDS: PRODUCT_ID,
    };
    currentEnv = env;
  });

  afterEach(async () => {
    currentEnv = null;
    await miniflare.dispose();
  });

  it("grants only the live proving session and rejects replay without advancing the counter", async () => {
    const app = createAppleRestoreRoutes({
      now: () => NOW,
      appAttestVerifier: {
        async verifyAttestation() {
          return { publicKeyPem: "public-key", receiptBase64: "receipt", signCount: 0 };
        },
        async verifyAssertion(input) {
          expect(input.previousSignCount).toBe(0);
          return { signCount: 1 };
        },
      },
      createAppleVerifier: () => ({
        environment: Environment.SANDBOX,
        verifier: { async verifyAndDecodeTransaction() { return transaction(); } },
      }),
    });
    const tokenA = await token("session-a");
    const tokenB = await token("session-b");

    const registerChallenge = await challenge(app, tokenA, {
      purpose: "register",
      request_id: "123e4567-e89b-42d3-a456-426614174001",
      key_id: KEY_ID,
    });
    const registration = await request(app, "/entitlements/apple/app-attest/register", tokenA, {
      schema_version: 1,
      request_id: "123e4567-e89b-42d3-a456-426614174001",
      challenge: registerChallenge.challenge,
      key_id: KEY_ID,
      attestation: "attestation-base64",
    });
    expect(registration.status).toBe(201);

    const restoreChallenge = await challenge(app, tokenA, {
      purpose: "restore",
      request_id: "123e4567-e89b-42d3-a456-426614174002",
      key_id: KEY_ID,
      signed_transaction_info: JWS,
    });
    const stolen = await request(app, "/entitlements/apple/restore", tokenB, restoreBody(restoreChallenge.challenge), {
      "Idempotency-Key": "123e4567-e89b-42d3-a456-426614174002",
    });
    expect(stolen.status).toBe(409);
    expect(await grantCount()).toBe(0);

    await db.prepare(`INSERT INTO billing_purchase_chain
      (id, store, environment, original_transaction_id, product_id, entitlement_id,
       original_owner_type, original_owner_id, status, auto_renew, state_effective_at, created_at, updated_at)
      VALUES ('unlinked-chain', 'app_store', 'Sandbox', 'original-restore', ?, 'performance_pro',
              'unlinked', '', 'ACTIVE', 1, '2026-08-12T07:59:00.000Z', ?, ?)`)
      .bind(PRODUCT_ID, NOW.toISOString(), NOW.toISOString()).run();

    const restored = await request(app, "/entitlements/apple/restore", tokenA, restoreBody(restoreChallenge.challenge), {
      "Idempotency-Key": "123e4567-e89b-42d3-a456-426614174002",
    });
    expect(restored.status).toBe(200);
    expect(await db.prepare(`SELECT original_owner_type, original_owner_id
      FROM billing_purchase_chain WHERE id = 'unlinked-chain'`).first()).toEqual({
      original_owner_type: "anonymous",
      original_owner_id: "100000",
    });
    expect(await db.prepare("SELECT session_id, source, status FROM billing_session_entitlement_grant").first()).toEqual({
      session_id: "session-a",
      source: "restore",
      status: "active",
    });
    // Restore proves this session's entitlement but remains outside Admin until notification confirmation.
    expect(await db.prepare(`SELECT business_status, charge_count, source_notification_uuid,
      auto_renew_snapshot, storefront_country_code
      FROM billing_transaction`).first()).toEqual({
      business_status: "renewal",
      charge_count: null,
      source_notification_uuid: null,
      auto_renew_snapshot: null,
      storefront_country_code: null,
    });
    expect(await signCount()).toBe(1);

    const replayed = await request(app, "/entitlements/apple/restore", tokenA, restoreBody(restoreChallenge.challenge), {
      "Idempotency-Key": "123e4567-e89b-42d3-a456-426614174002",
    });
    expect(replayed.status).toBe(200);
    expect(await grantCount()).toBe(1);
    expect(await signCount()).toBe(1);
  });

  async function token(sessionId: string) {
    return signAccessToken(
      { owner_type: "anonymous", owner_id: "100000", session_id: sessionId },
      env.JWT_SECRET,
    );
  }

  async function grantCount() {
    return (await db.prepare("SELECT COUNT(*) AS count FROM billing_session_entitlement_grant").first<{ count: number }>())!.count;
  }

  async function signCount() {
    return (await db.prepare("SELECT sign_count FROM billing_apple_app_attest_key WHERE key_id = ?").bind(KEY_ID).first<{ sign_count: number }>())!.sign_count;
  }
});

type App = ReturnType<typeof createAppleRestoreRoutes>;

async function challenge(app: App, bearer: string, body: Record<string, unknown>) {
  const response = await request(app, "/entitlements/apple/app-attest/challenge", bearer, {
    schema_version: 1,
    ...body,
  });
  expect(response.status).toBe(201);
  const envelope = await response.json() as { data: { challenge: string; client_data: string } };
  expect(envelope.data.client_data).toContain('"session_id":"session-a"');
  return envelope.data;
}

function restoreBody(challengeId: string) {
  return {
    schema_version: 1,
    request_id: "123e4567-e89b-42d3-a456-426614174002",
    challenge: challengeId,
    key_id: KEY_ID,
    assertion: "assertion-base64",
    signed_transaction_info: JWS,
  };
}

function request(
  app: App,
  path: string,
  bearer: string,
  body: object,
  headers: Record<string, string> = {},
) {
  return app.request(path, {
    method: "POST",
    headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  }, envFor(app));
}

let currentEnv: Env | null = null;
function envFor(_app: App): Env {
  if (!currentEnv) throw new Error("Test environment is not initialized.");
  return currentEnv;
}

function transaction(): JWSTransactionDecodedPayload {
  return {
    originalTransactionId: "original-restore",
    transactionId: "transaction-restore",
    productId: PRODUCT_ID,
    purchaseDate: NOW.getTime() - 1_000,
    expiresDate: NOW.getTime() + 86_400_000,
    signedDate: NOW.getTime(),
    type: "Auto-Renewable Subscription",
    environment: Environment.SANDBOX,
    transactionReason: "RENEWAL",
  };
}

const SCHEMA = `
CREATE TABLE anonymous_account (id TEXT PRIMARY KEY, upgraded_user_id TEXT);
CREATE TABLE session (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, expires_at TEXT NOT NULL, revoked_at TEXT);
CREATE TABLE billing_product (store TEXT NOT NULL, product_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, active INTEGER NOT NULL, UNIQUE(store, product_id));
CREATE TABLE billing_apple_app_attest_challenge (token TEXT PRIMARY KEY, session_id TEXT NOT NULL, purpose TEXT NOT NULL, request_id TEXT NOT NULL, key_id TEXT, evidence_sha256 TEXT, client_data TEXT NOT NULL, expires_at TEXT NOT NULL, consumed_at TEXT, consumption_id TEXT, result_code TEXT, response_json TEXT, http_status INTEGER, created_at TEXT NOT NULL, UNIQUE(session_id, request_id));
CREATE TABLE billing_apple_app_attest_key (key_id TEXT PRIMARY KEY, public_key_pem TEXT NOT NULL, receipt_base64 TEXT NOT NULL, sign_count INTEGER NOT NULL, environment TEXT NOT NULL, registered_session_id TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE billing_purchase_chain (id TEXT PRIMARY KEY, store TEXT NOT NULL, environment TEXT NOT NULL, original_transaction_id TEXT NOT NULL, product_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, original_owner_type TEXT NOT NULL, original_owner_id TEXT NOT NULL, app_account_token TEXT, status TEXT NOT NULL, auto_renew INTEGER NOT NULL, expires_at TEXT, grace_period_expires_at TEXT, revoked_at TEXT, state_effective_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(store, environment, original_transaction_id));
CREATE TABLE billing_transaction (id TEXT PRIMARY KEY, purchase_chain_id TEXT NOT NULL, store TEXT NOT NULL, environment TEXT NOT NULL, transaction_id TEXT NOT NULL, product_id TEXT NOT NULL, transaction_reason TEXT NOT NULL, status TEXT NOT NULL, business_status TEXT, charge_count INTEGER, source_notification_uuid TEXT, auto_renew_snapshot INTEGER, storefront_country_code TEXT, amount_micros INTEGER, currency TEXT, amount_usd_micros INTEGER, purchase_at TEXT NOT NULL, expires_at TEXT, revoked_at TEXT, signed_transaction TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(store, environment, transaction_id));
CREATE TABLE billing_session_entitlement_grant (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, purchase_chain_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, source TEXT NOT NULL, status TEXT NOT NULL, granted_at TEXT NOT NULL, expires_at TEXT, last_verified_at TEXT NOT NULL, revoked_at TEXT, updated_at TEXT NOT NULL, UNIQUE(session_id, purchase_chain_id, entitlement_id));
`;
