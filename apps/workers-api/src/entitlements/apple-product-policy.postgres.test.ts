import { URL } from "node:url";
import { readFileSync } from "node:fs";
import { signAccessToken } from "@kando/auth-core";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { PGliteDatabase } from "../test-support/pglite-database";
import type { Env } from "../env";
import { allowedAppleProductIds } from "./apple-product-policy";
import { createEntitlementRoutes } from "./routes";
import { createAppleRestoreRoutes } from "./restore-routes";
import { createAppleNotificationRoutes } from "./apple-notification-routes";
import { Environment } from "./apple-signed-data";
import { hasActivePremiumGrant } from "./premium-access";
import { writeProductAdmission } from "../subscription-config/product-admission";
import { catalogFixture } from "../subscription-config/test-fixtures";

const NOW = new Date("2026-10-16T01:00:00Z");
let db: PGliteDatabase; let env: Env; let authorization: Record<string, string>;
beforeAll(async () => {
  db = await PGliteDatabase.create();
  const directory = new URL("../db/postgres/migrations/", import.meta.url);
  for (const name of ["0000_business_schema.sql", "0002_apple_inbox_environment.sql", "0006_mutation_lock.sql", "0007_billing_refund_status.sql", "0009_apple_notification_app_bundle.sql", "0014_subscription_display_config.sql"]) await db.exec(readFileSync(new URL(name, directory), "utf8"));
  env = { DB: db, CACHE_KV: { get: async () => null } as unknown as KVNamespace, JWT_SECRET: "dynamic-policy-test",
    APP_ENVIRONMENT: "development", APPLE_IAP_BUNDLE_ID: "example.app", APP_STORE_CONNECT_APP_ID: "456", APPLE_IAP_PRODUCT_IDS: "legacy.week" };
  await db.exec("INSERT INTO anonymous_account(id,device_id,created_at) VALUES('100000','test-device','2026-10-16'); INSERT INTO session(id,owner_type,owner_id,refresh_token,expires_at,created_at) VALUES('session-a','anonymous','100000','test-refresh','2099-01-01','2026-10-16');");
  authorization = { authorization: "Bearer " + await signAccessToken({ owner_type: "anonymous", owner_id: "100000", session_id: "session-a" }, env.JWT_SECRET), "content-type": "application/json" };
  for (const [id, fixture] of [
    ["cardx.month", catalogFixture().products[0]],
    ["new.year", catalogFixture().products[0]],
    ["trial.week", catalogFixture().products[1]],
  ] as const) {
    const result = await writeProductAdmission(env, "development:example.app", "super-admin", crypto.randomUUID(), id,
      { ...fixture, product_id: id }, "card_monthlytest", null);
    expect(result.status).toBe(200);
  }
}, 30_000);
afterAll(async () => { await db?.close(); });

describe("approved Apple products through real PostgreSQL purchase boundaries", () => {
  it("combines original products with only the current environment and Bundle approvals", async () => {
    expect(await allowedAppleProductIds(env)).toEqual(new Set(["legacy.week", "cardx.month", "new.year", "trial.week"]));
    for (const other of [{ ...env, APP_ENVIRONMENT: "production" as const }, { ...env, APPLE_IAP_BUNDLE_ID: "other.app" }]) {
      expect(await allowedAppleProductIds(other)).toEqual(new Set(["legacy.week"]));
    }
  });
  it("rejects reusing one dynamic Product ID across scopes in a shared billing database", async () => {
    const other = { ...env, APP_ENVIRONMENT: "production" as const, APPLE_IAP_BUNDLE_ID: "other.app" };
    const result = await writeProductAdmission(other, "production:other.app", "super-admin", crypto.randomUUID(), "cross-scope",
      { ...catalogFixture().products[0], product_id: "cardx.month" }, "card_monthly", null);
    expect(result.status).toBe(409);
    expect(result.body).toMatchObject({ error: { code: "PRODUCT_SCOPE_CONFLICT" } });
    expect(await allowedAppleProductIds(other)).toEqual(new Set(["legacy.week"]));
  });
  it("verifies a new SKU with the original V1 request and grants only its proving session", async () => {
    let token = "";
    const routes = createEntitlementRoutes({ now: () => NOW, createVerifier: () => ({ environment: Environment.SANDBOX,
      verifier: { verifyAndDecodeTransaction: async () => ({ originalTransactionId: "original-month", transactionId: "transaction-month",
        productId: "cardx.month", purchaseDate: NOW.getTime() - 1000, expiresDate: NOW.getTime() + 86_400_000,
        signedDate: NOW.getTime(), type: "Auto-Renewable Subscription", appAccountToken: token,
        environment: Environment.SANDBOX, transactionReason: "PURCHASE", price: 9990, currency: "USD" }) } }) });
    const challenge = await routes.request("/entitlements/apple/purchase-challenge", { method: "POST", headers: authorization, body: JSON.stringify({ product_id: "cardx.month" }) }, env);
    expect(challenge.status).toBe(201);
    token = (await challenge.json() as any).data.application_account_token;
    const id = crypto.randomUUID();
    const verified = await routes.request("/entitlements/apple/verify", { method: "POST", headers: { ...authorization, "Idempotency-Key": id },
      body: JSON.stringify({ schema_version: 1, evidence_type: "storekit2_signed_transaction", request_id: id, signed_transaction_info: "test.signed.payload" }) }, env);
    expect(verified.status).toBe(200);
    expect(await hasActivePremiumGrant(env, "session-a", NOW)).toBe(true);
    expect(await hasActivePremiumGrant(env, "session-b", NOW)).toBe(false);
    expect(await hasActivePremiumGrant({ ...env, APP_ENVIRONMENT: "production" }, "session-a", NOW)).toBe(false);
    const foreign = await routes.request("/entitlements/apple/purchase-challenge", { method: "POST", headers: authorization, body: JSON.stringify({ product_id: "cardx.month" }) }, { ...env, APP_ENVIRONMENT: "production" });
    expect(foreign.status).toBe(503);
    const lifecycle = await routes.request("/entitlements/apple/lifecycle", { headers: authorization }, env);
    expect((await lifecycle.json() as any).data.purchase_chains[0].product_id).toBe("cardx.month");
  });
  it("restores a dynamically approved SKU through App Attest without changing the legacy V1 body", async () => {
    const restoreEnv = { ...env, APPLE_APP_ATTEST_APP_ID: "TEAM123456.example.app", APPLE_APP_ATTEST_DEVELOPMENT: "true" };
    const routes = createAppleRestoreRoutes({ now: () => NOW,
      appAttestVerifier: { verifyAttestation: async () => ({ publicKeyPem: "public", receiptBase64: "receipt", signCount: 0 }),
        verifyAssertion: async () => ({ signCount: 1 }) },
      createAppleVerifier: () => ({ environment: Environment.SANDBOX, verifier: { verifyAndDecodeTransaction: async () => ({
        productId: "cardx.month", originalTransactionId: "original-restore-month", transactionId: "restore-month",
        purchaseDate: NOW.getTime() - 1000, expiresDate: NOW.getTime() + 86_400_000, signedDate: NOW.getTime(),
        environment: Environment.SANDBOX, transactionReason: "PURCHASE", type: "Auto-Renewable Subscription" }) } }),
    });
    const post = async (path: string, body: Record<string, unknown>) => routes.request(path, { method: "POST",
      headers: { ...authorization, "Idempotency-Key": String(body.request_id) }, body: JSON.stringify({ schema_version: 1, ...body }) }, restoreEnv);
    const registrationId = crypto.randomUUID(); const keyId = "a2V5LWlk";
    const registrationChallenge = await post("/entitlements/apple/app-attest/challenge", { purpose: "register", request_id: registrationId, key_id: keyId });
    const registrationBody = await registrationChallenge.json() as any;
    expect(registrationChallenge.status, JSON.stringify(registrationBody)).toBe(201);
    const challenge = registrationBody.data.challenge;
    expect((await post("/entitlements/apple/app-attest/register", { schema_version: 1, request_id: registrationId, key_id: keyId, challenge, attestation: "attestation-base64" })).status).toBe(201);
    const requestId = crypto.randomUUID();
    const restoreChallenge = await post("/entitlements/apple/app-attest/challenge", { purpose: "restore", request_id: requestId, key_id: keyId, signed_transaction_info: "restore.signed.payload" });
    const restored = await post("/entitlements/apple/restore", { schema_version: 1, request_id: requestId, key_id: keyId,
      challenge: (await restoreChallenge.json() as any).data.challenge, assertion: "assertion-base64", signed_transaction_info: "restore.signed.payload" });
    expect(restored.status).toBe(200);
    expect(await db.prepare("SELECT g.session_id FROM billing_session_entitlement_grant g JOIN billing_purchase_chain c ON c.id = g.purchase_chain_id WHERE c.original_transaction_id = 'original-restore-month' AND g.status = 'active'").first("session_id")).toBe("session-a");
  });
  it("keeps only the first paid renewal of an approved trial SKU as trial conversion", async () => {
    await db.prepare(`INSERT INTO billing_purchase_chain
      (id, store, environment, original_transaction_id, product_id, entitlement_id,
       original_owner_type, original_owner_id, status, auto_renew, created_at, updated_at)
      VALUES ('trial-conversion-chain', 'app_store', 'Sandbox', 'original-trial-week',
              'trial.week', 'performance_pro', 'anonymous', '100000', 'ACTIVE', 1, ?, ?)`)
      .bind(NOW.toISOString(), NOW.toISOString()).run();
    const firstAt = NOW.getTime();
    const secondAt = firstAt + 86_400_000;
    const refundAt = secondAt + 86_400_000;
    expect((await postTrialNotification("trial-conversion-notification", "DID_RENEW",
      "trial-conversion-transaction", firstAt, firstAt)).status).toBe(200);
    expect((await postTrialNotification("trial-renewal-notification", "DID_RENEW",
      "trial-renewal-transaction", secondAt, secondAt)).status).toBe(200);
    expect((await postTrialNotification("trial-refund-notification", "REFUND",
      "trial-renewal-transaction", secondAt, refundAt, refundAt)).status).toBe(200);

    expect((await db.prepare(`SELECT transaction_id, business_status,
      business_status_before_refund, charge_count FROM billing_transaction
      WHERE purchase_chain_id = 'trial-conversion-chain' ORDER BY purchase_at`).all()).results).toEqual([
      {
        transaction_id: "trial-conversion-transaction", business_status: "trial_conversion",
        business_status_before_refund: null, charge_count: 1,
      },
      {
        transaction_id: "trial-renewal-transaction", business_status: "refunded",
        business_status_before_refund: "renewal", charge_count: 2,
      },
    ]);

    async function postTrialNotification(
      notificationUuid: string,
      notificationType: string,
      transactionId: string,
      purchaseDate: number,
      signedDate: number,
      revocationDate?: number,
    ) {
      const routes = createAppleNotificationRoutes({ now: () => new Date(signedDate), createVerifier: () => ({
        environment: Environment.SANDBOX,
        verifier: {
          verifyAndDecodeNotification: async () => ({
            notificationUUID: notificationUuid, notificationType, signedDate,
            data: { environment: Environment.SANDBOX,
              signedTransactionInfo: "trial-transaction", signedRenewalInfo: "trial-renewal" },
          }),
          verifyAndDecodeTransaction: async () => ({
            originalTransactionId: "original-trial-week", transactionId, productId: "trial.week",
            purchaseDate, expiresDate: purchaseDate + 86_400_000, signedDate,
            revocationDate, environment: Environment.SANDBOX,
            type: "Auto-Renewable Subscription", transactionReason: "RENEWAL", price: 9990, currency: "USD",
          }),
          verifyAndDecodeRenewalInfo: async () => ({
            originalTransactionId: "original-trial-week", productId: "trial.week",
            autoRenewProductId: "trial.week", autoRenewStatus: 1, environment: Environment.SANDBOX,
          }),
        },
      }) });
      return routes.request("/apple/notifications/v2", {
        method: "POST", body: JSON.stringify({ signedPayload: `${notificationUuid}.jws` }),
      }, env);
    }
  });
  it("records an upgrade to an approved new SKU without adding another hardcoded ID", async () => {
    await db.prepare("INSERT INTO billing_purchase_chain (id, store, environment, original_transaction_id, product_id, entitlement_id, original_owner_type, original_owner_id, status, auto_renew, created_at, updated_at) VALUES ('upgrade-chain', 'app_store', 'Sandbox', 'original-upgrade-month', 'cardx.month', 'performance_pro', 'anonymous', '100000', 'ACTIVE', 1, ?, ?)").bind(NOW.toISOString(), NOW.toISOString()).run();
    const routes = createAppleNotificationRoutes({ now: () => NOW, createVerifier: () => ({ environment: Environment.SANDBOX,
      verifier: {
        verifyAndDecodeNotification: async () => ({ notificationUUID: "new-upgrade", notificationType: "DID_CHANGE_RENEWAL_PREF", subtype: "UPGRADE", signedDate: NOW.getTime(),
          data: { environment: Environment.SANDBOX, signedTransactionInfo: "transaction", signedRenewalInfo: "renewal" } }),
        verifyAndDecodeTransaction: async () => ({ originalTransactionId: "original-upgrade-month", transactionId: "new-upgrade-transaction", productId: "new.year",
          purchaseDate: NOW.getTime(), expiresDate: NOW.getTime() + 86_400_000, signedDate: NOW.getTime(),
          environment: Environment.SANDBOX, type: "Auto-Renewable Subscription", transactionReason: "PURCHASE", price: 9990, currency: "USD" }),
        verifyAndDecodeRenewalInfo: async () => ({ originalTransactionId: "original-upgrade-month", productId: "new.year", autoRenewProductId: "new.year", autoRenewStatus: 1, environment: Environment.SANDBOX }),
      } }) });
    const response = await routes.request("/apple/notifications/v2", { method: "POST", body: JSON.stringify({ signedPayload: "new.upgrade.jws" }) }, env);
    expect(response.status).toBe(200);
    expect(await db.prepare("SELECT product_id, business_status FROM billing_transaction WHERE transaction_id = 'new-upgrade-transaction'").first())
      .toEqual({ product_id: "new.year", business_status: "upgrade" });
  });
});
