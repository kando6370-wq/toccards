import { Hono } from "hono";
import type { Env } from "../env";
import { createId } from "../id";
import { authenticateOwner } from "../owner-auth";
import { appleAppAttestVerifier, sha256Bytes, type AppleAppAttestVerifier } from "./apple-app-attest";
import {
  asVerifierConfigurations,
  configuredProductIds,
  createAppleVerifiers,
  Environment,
  type AppleVerifierFactoryResult,
  type JWSTransactionDecodedPayload,
  verifyAppleTransaction,
} from "./apple-signed-data";
import { PREMIUM_ENTITLEMENT_ID } from "./premium-access";
import { billingOrderFactStatements, businessStatusForAppleTransaction } from "./billing-order-facts";

const CHALLENGE_TTL_MS = 10 * 60 * 1000;
const MAX_EVIDENCE_LENGTH = 100_000;
const MAX_ATTESTATION_LENGTH = 200_000;

type Dependencies = {
  now?: () => Date;
  appAttestVerifier?: AppleAppAttestVerifier;
  createAppleVerifier?: (env: Env) =>
    Promise<AppleVerifierFactoryResult> | AppleVerifierFactoryResult;
};

type ChallengeRow = {
  token: string;
  session_id: string;
  purpose: "register" | "restore";
  request_id: string;
  key_id: string | null;
  evidence_sha256: string | null;
  client_data: string;
  expires_at: string;
  consumed_at: string | null;
  result_code: string | null;
  response_json: string | null;
  http_status: number | null;
};

type KeyRow = { public_key_pem: string; sign_count: number; status: string };
type ProductRow = { entitlement_id: string };
type ChainRow = { id: string; state_effective_at: string | null };

const unavailable = { success: false, error: { code: "VERIFICATION_UNAVAILABLE", message: "Apple restore verification is not configured." } } as const;
const invalid = { success: false, error: { code: "EVIDENCE_INVALID", message: "Apple restore evidence is invalid." } } as const;
const replay = { success: false, error: { code: "REPLAY_REJECTED", message: "Apple restore proof was already consumed." } } as const;

export function createAppleRestoreRoutes(dependencies: Dependencies = {}): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();
  const now = dependencies.now ?? (() => new Date());
  const attestVerifier = dependencies.appAttestVerifier ?? appleAppAttestVerifier;
  const appleVerifierFactory = dependencies.createAppleVerifier ?? createAppleVerifiers;

  routes.post("/entitlements/apple/app-attest/challenge", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "internal_error") return internalError(c);
    if (auth.status === "unauthorized") return c.json({ success: false, error: { code: "UNAUTHORIZED", message: "Unauthorized." } }, 401);
    const body = challengeBody(await readJson(c.req));
    if (!body) return validationError(c);
    const config = appAttestConfig(c.env);
    if (!config) return c.json(unavailable, 503);

    const createdAt = now();
    const token = crypto.randomUUID();
    const evidenceSha256 = body.signedTransactionInfo
      ? await sha256Hex(body.signedTransactionInfo)
      : null;
    const clientData = canonicalClientData({
      challenge: token,
      purpose: body.purpose,
      requestId: body.requestId,
      sessionId: auth.owner.session_id,
      keyId: body.keyId,
      evidenceSha256,
    });
    const existing = await loadChallengeByRequest(
      c.env.DB,
      auth.owner.session_id,
      body.requestId,
    );
    if (existing) {
      if (!sameChallengeBinding(existing, body.purpose, body.keyId, evidenceSha256)) {
        return c.json({ success: false, error: { code: "STATE_CONFLICT", message: "Request ID is already in use." } }, 409);
      }
      return c.json({ success: true, data: { schema_version: 1, challenge: existing.token, client_data: existing.client_data } });
    }
    try {
      await c.env.DB.prepare(`
        INSERT INTO billing_apple_app_attest_challenge
          (token, session_id, purpose, request_id, key_id, evidence_sha256, client_data,
           expires_at, consumed_at, consumption_id, result_code, response_json,
           http_status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, ?)
      `).bind(
        token, auth.owner.session_id, body.purpose, body.requestId, body.keyId,
        evidenceSha256, clientData,
        new Date(createdAt.getTime() + CHALLENGE_TTL_MS).toISOString(), createdAt.toISOString(),
      ).run();
    } catch {
      return c.json({ success: false, error: { code: "STATE_CONFLICT", message: "Request ID is already in use." } }, 409);
    }
    return c.json({ success: true, data: { schema_version: 1, challenge: token, client_data: clientData } }, 201);
  });

  routes.post("/entitlements/apple/app-attest/register", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "internal_error") return internalError(c);
    if (auth.status === "unauthorized") return c.json({ success: false, error: { code: "UNAUTHORIZED", message: "Unauthorized." } }, 401);
    const body = registrationBody(await readJson(c.req));
    if (!body) return validationError(c);
    const config = appAttestConfig(c.env);
    if (!config) return c.json(unavailable, 503);
    const challenge = await loadChallenge(c.env.DB, body.challenge, auth.owner.session_id);
    const stored = storedChallengeResponse(c, challenge, "register", body.requestId, body.keyId, null);
    if (stored) return stored;
    if (!validChallenge(challenge, "register", body.requestId, body.keyId, null, now())) return c.json(replay, 409);
    try {
      const verified = await attestVerifier.verifyAttestation({
        appId: config.appId,
        developmentEnvironment: config.developmentEnvironment,
        keyId: body.keyId,
        clientDataHash: await sha256Bytes(challenge.client_data),
        attestation: body.attestation,
      });
      const timestamp = now().toISOString();
      const consumptionId = crypto.randomUUID();
      const response = { success: true, data: { schema_version: 1, key_id: body.keyId } } as const;
      const results = await c.env.DB.batch([
        c.env.DB.prepare(`UPDATE billing_apple_app_attest_challenge SET consumed_at = ?, consumption_id = ? WHERE token = ? AND session_id = ? AND consumed_at IS NULL AND expires_at > ?`).bind(timestamp, consumptionId, body.challenge, auth.owner.session_id, timestamp),
        c.env.DB.prepare(`
          INSERT INTO billing_apple_app_attest_key
            (key_id, public_key_pem, receipt_base64, sign_count, environment,
             registered_session_id, status, created_at, updated_at)
          SELECT ?, ?, ?, ?, ?, ?, 'active', ?, ?
          WHERE EXISTS (SELECT 1 FROM billing_apple_app_attest_challenge WHERE token = ? AND consumption_id = ?)
          ON CONFLICT(key_id) DO NOTHING
        `).bind(body.keyId, verified.publicKeyPem, verified.receiptBase64, verified.signCount,
          config.developmentEnvironment ? "development" : "production", auth.owner.session_id,
          timestamp, timestamp, body.challenge, consumptionId),
        c.env.DB.prepare(`UPDATE billing_apple_app_attest_challenge SET result_code = 'REGISTERED', response_json = ?, http_status = 201 WHERE token = ? AND consumption_id = ? AND EXISTS (SELECT 1 FROM billing_apple_app_attest_key WHERE key_id = ?)`).bind(JSON.stringify(response), body.challenge, consumptionId, body.keyId),
      ]);
      if (results[0]?.meta.changes !== 1 || results[1]?.meta.changes !== 1 || results[2]?.meta.changes !== 1) return c.json(replay, 409);
      return c.json(response, 201);
    } catch {
      return c.json(invalid, 422);
    }
  });

  routes.post("/entitlements/apple/restore", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "internal_error") return internalError(c);
    if (auth.status === "unauthorized") return c.json({ success: false, error: { code: "UNAUTHORIZED", message: "Unauthorized." } }, 401);
    const body = restoreBody(await readJson(c.req));
    if (!body || c.req.header("Idempotency-Key") !== body.requestId) return validationError(c);
    const config = appAttestConfig(c.env);
    const appleVerifiers = asVerifierConfigurations(
      await appleVerifierFactory(c.env),
    );
    const products = configuredProductIds(c.env.APPLE_IAP_PRODUCT_IDS);
    if (!config || appleVerifiers.length === 0 || !products) {
      return c.json(unavailable, 503);
    }
    const evidenceSha256 = await sha256Hex(body.signedTransactionInfo);
    const challenge = await loadChallenge(c.env.DB, body.challenge, auth.owner.session_id);
    const stored = storedChallengeResponse(c, challenge, "restore", body.requestId, body.keyId, evidenceSha256);
    if (stored) return stored;
    const key = await c.env.DB.prepare(`SELECT public_key_pem, sign_count, status FROM billing_apple_app_attest_key WHERE key_id = ? LIMIT 1`).bind(body.keyId).first<KeyRow>();
    if (!key || key.status !== "active" || !validChallenge(challenge, "restore", body.requestId, body.keyId, evidenceSha256, now())) return c.json(replay, 409);

    let signCount: number;
    let verifiedTransaction: Awaited<ReturnType<typeof verifyAppleTransaction>>;
    try {
      signCount = (await attestVerifier.verifyAssertion({ appId: config.appId, assertion: body.assertion,
        clientData: challenge.client_data, publicKeyPem: key.public_key_pem, previousSignCount: key.sign_count })).signCount;
      verifiedTransaction = await verifyAppleTransaction(
        appleVerifiers,
        body.signedTransactionInfo,
      );
    } catch {
      return c.json(invalid, 422);
    }
    if (!verifiedTransaction) return c.json(invalid, 422);
    const transaction: JWSTransactionDecodedPayload = verifiedTransaction.transaction;
    const attemptedAt = now();
    const normalized = normalizeRestoreTransaction(
      transaction,
      verifiedTransaction.configuration.environment,
      products,
      attemptedAt,
    );
    if (!normalized) return c.json(invalid, 422);
    const product = await c.env.DB.prepare(`SELECT entitlement_id FROM billing_product WHERE store = 'app_store' AND product_id = ? AND active = 1 LIMIT 1`).bind(normalized.productId).first<ProductRow>();
    if (!product || product.entitlement_id !== PREMIUM_ENTITLEMENT_ID) return c.json(unavailable, 503);
    const existingChain = await c.env.DB.prepare(`SELECT id, state_effective_at FROM billing_purchase_chain WHERE store = 'app_store' AND environment = ? AND original_transaction_id = ? LIMIT 1`).bind(normalized.environment, normalized.originalTransactionId).first<ChainRow>();
    if (existingChain?.state_effective_at && Date.parse(existingChain.state_effective_at) > Date.parse(normalized.stateEffectiveAt)) {
      return c.json({ success: false, error: { code: "STATE_CONFLICT", message: "A newer Apple lifecycle state already exists." } }, 409);
    }
    const timestamp = attemptedAt.toISOString();
    const consumptionId = crypto.randomUUID();
    const chainId = existingChain?.id ?? createId(attemptedAt);
    const response = { success: true, data: { schema_version: 1, state: "VERIFIED_ACTIVE", entitlement_id: product.entitlement_id, product_id: normalized.productId, expires_at: normalized.expiresAt } } as const;
    const orderFactStatements = billingOrderFactStatements(c.env.DB, chainId, normalized.environment);
    const grantResultIndex = 4 + orderFactStatements.length;
    const completionResultIndex = grantResultIndex + 1;
    try {
      const results = await c.env.DB.batch([
        c.env.DB.prepare(`UPDATE billing_apple_app_attest_challenge SET consumed_at = ?, consumption_id = ? WHERE token = ? AND session_id = ? AND consumed_at IS NULL AND expires_at > ? AND EXISTS (SELECT 1 FROM billing_apple_app_attest_key WHERE key_id = ? AND status = 'active' AND sign_count = ?)`).bind(timestamp, consumptionId, body.challenge, auth.owner.session_id, timestamp, body.keyId, key.sign_count),
        c.env.DB.prepare(`UPDATE billing_apple_app_attest_key SET sign_count = ?, updated_at = ? WHERE key_id = ? AND status = 'active' AND sign_count = ? AND EXISTS (SELECT 1 FROM billing_apple_app_attest_challenge WHERE token = ? AND consumption_id = ?)`).bind(signCount, timestamp, body.keyId, key.sign_count, body.challenge, consumptionId),
        c.env.DB.prepare(`
          INSERT INTO billing_purchase_chain
            (id, store, environment, original_transaction_id, product_id, entitlement_id,
             original_owner_type, original_owner_id, app_account_token, status, auto_renew,
             expires_at, grace_period_expires_at, revoked_at, state_effective_at, created_at, updated_at)
          SELECT ?, 'app_store', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?
          WHERE EXISTS (SELECT 1 FROM billing_apple_app_attest_challenge WHERE token = ? AND consumption_id = ?)
          ON CONFLICT(store, environment, original_transaction_id) DO UPDATE SET
            product_id=excluded.product_id, entitlement_id=excluded.entitlement_id,
            original_owner_type=CASE WHEN billing_purchase_chain.original_owner_type='unlinked'
              THEN excluded.original_owner_type ELSE billing_purchase_chain.original_owner_type END,
            original_owner_id=CASE WHEN billing_purchase_chain.original_owner_type='unlinked'
              THEN excluded.original_owner_id ELSE billing_purchase_chain.original_owner_id END,
            status=excluded.status, expires_at=excluded.expires_at,
            state_effective_at=excluded.state_effective_at, updated_at=excluded.updated_at
          WHERE billing_purchase_chain.state_effective_at IS NULL OR billing_purchase_chain.state_effective_at <= excluded.state_effective_at
        `).bind(chainId, normalized.environment, normalized.originalTransactionId, normalized.productId,
          product.entitlement_id, auth.owner.owner_type, auth.owner.owner_id, normalized.appAccountToken,
          normalized.chainStatus, normalized.autoRenew, normalized.expiresAt, normalized.stateEffectiveAt,
          timestamp, timestamp, body.challenge, consumptionId),
        c.env.DB.prepare(`
          INSERT INTO billing_transaction
            (id, purchase_chain_id, store, environment, transaction_id, product_id, transaction_reason,
             status, business_status, charge_count, source_notification_uuid, auto_renew_snapshot,
             storefront_country_code, amount_micros, currency, amount_usd_micros,
             purchase_at, expires_at, revoked_at, signed_transaction, created_at, updated_at)
          SELECT ?, ?, 'app_store', ?, ?, ?, ?, 'purchased', ?, NULL, NULL, ?, ?, ?, ?, NULL, ?, ?, NULL, ?, ?, ?
          WHERE EXISTS (SELECT 1 FROM billing_purchase_chain WHERE id = ? AND state_effective_at = ?)
          ON CONFLICT(store, environment, transaction_id) DO NOTHING
        `).bind(createId(attemptedAt), chainId, normalized.environment, normalized.transactionId,
          normalized.productId, normalized.transactionReason, normalized.businessStatus,
          normalized.autoRenewSnapshot,
          normalized.storefront,
          normalized.amountMicros, normalized.currency, normalized.purchaseAt, normalized.expiresAt,
          body.signedTransactionInfo, timestamp, timestamp, chainId, normalized.stateEffectiveAt),
        ...orderFactStatements,
        c.env.DB.prepare(`
          INSERT INTO billing_session_entitlement_grant
            (id, session_id, purchase_chain_id, entitlement_id, source, status, granted_at,
             expires_at, last_verified_at, revoked_at, updated_at)
          SELECT ?, ?, ?, ?, 'restore', 'active', ?, ?, ?, NULL, ?
          WHERE EXISTS (SELECT 1 FROM billing_apple_app_attest_challenge WHERE token = ? AND consumption_id = ?)
            AND EXISTS (SELECT 1 FROM billing_purchase_chain WHERE id = ? AND state_effective_at = ?)
          ON CONFLICT(session_id, purchase_chain_id, entitlement_id) DO UPDATE SET
            source='restore', status='active', expires_at=excluded.expires_at,
            last_verified_at=excluded.last_verified_at, revoked_at=NULL, updated_at=excluded.updated_at
        `).bind(createId(attemptedAt), auth.owner.session_id, chainId, product.entitlement_id,
          timestamp, normalized.expiresAt, timestamp, timestamp, body.challenge, consumptionId,
          chainId, normalized.stateEffectiveAt),
        c.env.DB.prepare(`UPDATE billing_apple_app_attest_challenge SET result_code = 'VERIFIED_ACTIVE', response_json = ?, http_status = 200 WHERE token = ? AND consumption_id = ? AND EXISTS (SELECT 1 FROM billing_session_entitlement_grant WHERE session_id = ? AND purchase_chain_id = ? AND entitlement_id = ? AND status = 'active')`).bind(JSON.stringify(response), body.challenge, consumptionId, auth.owner.session_id, chainId, product.entitlement_id),
      ]);
      if (results[0]?.meta.changes !== 1 || results[1]?.meta.changes !== 1 || results[2]?.meta.changes !== 1 || results[grantResultIndex]?.meta.changes !== 1 || results[completionResultIndex]?.meta.changes !== 1) return c.json(replay, 409);
    } catch {
      return internalError(c);
    }
    return c.json(response);
  });
  return routes;
}

type ChallengeBody = { purpose: "register" | "restore"; requestId: string; keyId: string | null; signedTransactionInfo: string | null };
function challengeBody(body: unknown): ChallengeBody | null {
  if (!record(body) || body.schema_version !== 1 || !uuid(body.request_id) || (body.purpose !== "register" && body.purpose !== "restore")) return null;
  const keyId = typeof body.key_id === "string" && validBase64(body.key_id) ? body.key_id : null;
  const evidence = typeof body.signed_transaction_info === "string" && body.signed_transaction_info.length <= MAX_EVIDENCE_LENGTH ? body.signed_transaction_info : null;
  if (!keyId) return null;
  if (body.purpose === "restore" && !evidence) return null;
  if (body.purpose === "register" && body.signed_transaction_info != null) return null;
  return { purpose: body.purpose, requestId: body.request_id as string, keyId, signedTransactionInfo: evidence };
}
function registrationBody(body: unknown) {
  if (!record(body) || body.schema_version !== 1 || !uuid(body.request_id) || !uuid(body.challenge) || typeof body.key_id !== "string" || !validBase64(body.key_id) || typeof body.attestation !== "string" || body.attestation.length < 1 || body.attestation.length > MAX_ATTESTATION_LENGTH) return null;
  return { requestId: body.request_id as string, challenge: body.challenge as string, keyId: body.key_id, attestation: body.attestation };
}
function restoreBody(body: unknown) {
  if (!record(body) || body.schema_version !== 1 || !uuid(body.request_id) || !uuid(body.challenge) || typeof body.key_id !== "string" || !validBase64(body.key_id) || typeof body.assertion !== "string" || body.assertion.length < 1 || body.assertion.length > MAX_ATTESTATION_LENGTH || typeof body.signed_transaction_info !== "string" || body.signed_transaction_info.length < 1 || body.signed_transaction_info.length > MAX_EVIDENCE_LENGTH) return null;
  return { requestId: body.request_id as string, challenge: body.challenge as string, keyId: body.key_id, assertion: body.assertion, signedTransactionInfo: body.signed_transaction_info };
}
function canonicalClientData(input: { challenge: string; purpose: string; requestId: string; sessionId: string; keyId: string | null; evidenceSha256: string | null }): string {
  return JSON.stringify({ challenge: input.challenge, evidence_sha256: input.evidenceSha256, key_id: input.keyId, purpose: input.purpose, request_id: input.requestId, session_id: input.sessionId });
}
function appAttestConfig(env: Env) {
  const appId = env.APPLE_APP_ATTEST_APP_ID?.trim();
  if (!appId || !/^[A-Z0-9]{10}\.[A-Za-z0-9.-]+$/.test(appId)) return null;
  return { appId, developmentEnvironment: env.APPLE_APP_ATTEST_DEVELOPMENT === "true" };
}
async function loadChallenge(db: D1Database, token: string, sessionId: string) {
  return db.prepare(`SELECT token, session_id, purpose, request_id, key_id, evidence_sha256, client_data, expires_at, consumed_at, result_code, response_json, http_status FROM billing_apple_app_attest_challenge WHERE token = ? AND session_id = ? LIMIT 1`).bind(token, sessionId).first<ChallengeRow>();
}
async function loadChallengeByRequest(db: D1Database, sessionId: string, requestId: string) {
  return db.prepare(`SELECT token, session_id, purpose, request_id, key_id, evidence_sha256, client_data, expires_at, consumed_at, result_code, response_json, http_status FROM billing_apple_app_attest_challenge WHERE session_id = ? AND request_id = ? LIMIT 1`).bind(sessionId, requestId).first<ChallengeRow>();
}
function sameChallengeBinding(row: ChallengeRow, purpose: "register" | "restore", keyId: string | null, evidenceSha256: string | null) {
  return row.purpose === purpose && row.key_id === keyId && row.evidence_sha256 === evidenceSha256;
}
function storedChallengeResponse(c: any, row: ChallengeRow | null, purpose: "register" | "restore", requestId: string, keyId: string, evidenceSha256: string | null) {
  if (!row || row.request_id !== requestId || !sameChallengeBinding(row, purpose, keyId, evidenceSha256) || row.response_json === null || row.http_status === null) return null;
  try { return c.json(JSON.parse(row.response_json) as object, row.http_status); } catch { return internalError(c); }
}
function validChallenge(row: ChallengeRow | null, purpose: "register" | "restore", requestId: string, keyId: string | null, evidenceSha256: string | null, at: Date): row is ChallengeRow {
  return !!row && row.purpose === purpose && row.request_id === requestId && row.key_id === keyId && row.evidence_sha256 === evidenceSha256 && row.consumed_at === null && Date.parse(row.expires_at) > at.getTime();
}
export function normalizeRestoreTransaction(transaction: JWSTransactionDecodedPayload, expected: Environment, products: ReadonlySet<string>, at: Date) {
  const { originalTransactionId, transactionId, productId, purchaseDate, expiresDate, signedDate } = transaction;
  if (!originalTransactionId || !transactionId || !productId || !products.has(productId) || transaction.environment !== expected || (transaction.transactionReason !== "PURCHASE" && transaction.transactionReason !== "RENEWAL") || transaction.revocationDate !== undefined || !Number.isFinite(purchaseDate)) return null;
  const subscription = transaction.type === "Auto-Renewable Subscription";
  const lifetime = transaction.type === "Non-Consumable";
  if ((!subscription && !lifetime) || (subscription && (!Number.isFinite(expiresDate) || expiresDate! <= at.getTime()))) return null;
  const amountMicros = Number.isSafeInteger(transaction.price) ? transaction.price! * 1000 : null;
  if (amountMicros !== null && !Number.isSafeInteger(amountMicros)) return null;
  return { originalTransactionId, transactionId, productId, appAccountToken: transaction.appAccountToken ?? null,
    environment: expected === Environment.PRODUCTION ? "Production" as const : "Sandbox" as const,
    transactionReason: transaction.transactionReason, purchaseAt: new Date(purchaseDate!).toISOString(),
    expiresAt: subscription ? new Date(expiresDate!).toISOString() : null,
    stateEffectiveAt: new Date(Number.isFinite(signedDate) ? signedDate! : purchaseDate!).toISOString(),
    chainStatus: lifetime ? "LIFETIME" as const
      : transaction.offerDiscountType === "FREE_TRIAL" ? "TRIAL" as const : "ACTIVE" as const,
    autoRenew: subscription ? 1 as const : 0 as const,
    autoRenewSnapshot: lifetime ? 0 as const : null,
    storefront: transaction.storefront ?? null, amountMicros, currency: transaction.currency ?? null,
    businessStatus: businessStatusForAppleTransaction("RESTORE", "", transaction) };
}
function record(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
function uuid(value: unknown): value is string { return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function validBase64(value: string) { return value.length > 0 && value.length <= 500 && /^[A-Za-z0-9+/]+={0,2}$/.test(value); }
async function sha256Hex(value: string) { return Array.from(await sha256Bytes(value), (byte) => byte.toString(16).padStart(2, "0")).join(""); }
async function readJson(request: { json(): Promise<unknown> }) { try { return await request.json(); } catch { return null; } }
function validationError(c: any) { return c.json({ success: false, error: { code: "VALIDATION_ERROR", message: "Invalid request." } }, 422); }
function internalError(c: any) { return c.json({ success: false, error: { code: "INTERNAL_ERROR", message: "Something went wrong." } }, 500); }
