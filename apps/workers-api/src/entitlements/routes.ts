import { Hono, type Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { Env } from "../env";
import { createId } from "../id";
import { authenticateOwner } from "../owner-auth";
import {
  createAppleVerifier,
  Environment,
  type AppleTransactionVerifier,
  type JWSTransactionDecodedPayload,
} from "./apple-signed-data";
import { PREMIUM_ENTITLEMENT_ID } from "./premium-access";
import { billingOrderFactStatements, businessStatusForAppleTransaction } from "./billing-order-facts";
import { loadBillingUsdSnapshot } from "./billing-currency";

const CHALLENGE_TTL_MS = 10 * 60 * 1000;
const VERIFICATION_LEASE_MS = 60 * 1000;
const MAX_EVIDENCE_LENGTH = 100_000;
export const APPLE_VERIFICATION_PROCESSING_HTTP_STATUS = 503;
export const APPLE_VERIFICATION_PROCESSING_RESPONSE = {
  success: false,
  error: {
    code: "VERIFICATION_UNAVAILABLE",
    message: "Apple transaction verification is already in progress.",
  },
} as const;

const UNAUTHORIZED = {
  success: false,
  error: { code: "UNAUTHORIZED", message: "Unauthorized." },
} as const;

const VERIFICATION_UNAVAILABLE = {
  success: false,
  error: {
    code: "VERIFICATION_UNAVAILABLE",
    message: "Apple purchase verification is not configured.",
  },
} as const;

type EntitlementRouteDependencies = {
  now?: () => Date;
  createVerifier?: (env: Env) => Promise<{
    environment: Environment;
    verifier: AppleTransactionVerifier;
  } | null> | {
    environment: Environment;
    verifier: AppleTransactionVerifier;
  } | null;
};

type AttemptRow = {
  evidence_sha256: string;
  response_json: string;
  http_status: number;
  result_code: string;
  processing_expires_at: string | null;
};
type ChallengeRow = {
  token: string;
  session_id: string;
  product_id: string;
  expires_at: string;
  consumed_at: string | null;
};
type ProductRow = { entitlement_id: string };
type ChainRow = { id: string; status: string; state_effective_at: string | null };
type SessionLifecycleRow = {
  original_transaction_id: string;
  product_id: string;
  lifecycle_status: string;
  state_effective_at: string | null;
};

export function createEntitlementRoutes(
  dependencies: EntitlementRouteDependencies = {},
): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();
  const now = dependencies.now ?? (() => new Date());
  const verifierFactory = dependencies.createVerifier ?? createAppleVerifier;

  routes.get("/entitlements/apple/lifecycle", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "internal_error") return internalError(c);
    if (auth.status === "unauthorized") return c.json(UNAUTHORIZED, 401);

    const environment = c.env.APP_ENVIRONMENT === "production" ? "Production" : "Sandbox";
    try {
      const result = await c.env.DB.prepare(`
        SELECT purchase_chain.original_transaction_id,
               purchase_chain.product_id,
               purchase_chain.status AS lifecycle_status,
               purchase_chain.state_effective_at
        FROM billing_session_entitlement_grant AS session_grant
        INNER JOIN billing_purchase_chain AS purchase_chain
          ON purchase_chain.id = session_grant.purchase_chain_id
        WHERE session_grant.session_id = ?
          AND session_grant.entitlement_id = ?
          AND purchase_chain.store = 'app_store'
          AND purchase_chain.environment = ?
        ORDER BY purchase_chain.state_effective_at DESC NULLS LAST,
                 purchase_chain.original_transaction_id ASC
      `).bind(
        auth.owner.session_id,
        PREMIUM_ENTITLEMENT_ID,
        environment,
      ).all<SessionLifecycleRow>();

      return c.json({
        success: true,
        data: {
          schema_version: 1,
          purchase_chains: result.results,
        },
      });
    } catch {
      return internalError(c);
    }
  });

  routes.post("/entitlements/apple/purchase-challenge", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "internal_error") {
      return c.json({ success: false, error: { code: "INTERNAL_ERROR", message: "Something went wrong." } }, 500);
    }
    if (auth.status === "unauthorized") return c.json(UNAUTHORIZED, 401);

    const body = await readJson(c.req);
    const productId = productIdFromBody(body);
    if (!productId) {
      return c.json({ success: false, error: { code: "VALIDATION_ERROR", message: "Invalid request." } }, 422);
    }

    const allowedProducts = configuredProductIds(c.env.APPLE_IAP_PRODUCT_IDS);
    if (!allowedProducts || !allowedProducts.has(productId)) {
      return c.json(VERIFICATION_UNAVAILABLE, 503);
    }
    const product = await c.env.DB.prepare(`
      SELECT entitlement_id
      FROM billing_product
      WHERE store = 'app_store' AND product_id = ? AND active = 1
      LIMIT 1
    `).bind(productId).first<ProductRow>();
    if (!product || product.entitlement_id !== PREMIUM_ENTITLEMENT_ID) {
      return c.json(VERIFICATION_UNAVAILABLE, 503);
    }

    if (!await verifierFactory(c.env)) return c.json(VERIFICATION_UNAVAILABLE, 503);

    const createdAt = now();
    const token = crypto.randomUUID();
    const expiresAt = new Date(createdAt.getTime() + CHALLENGE_TTL_MS).toISOString();
    try {
      await c.env.DB.prepare(`
        INSERT INTO billing_apple_purchase_challenge
          (token, session_id, product_id, expires_at, consumed_at, consumed_transaction_id, created_at)
        VALUES (?, ?, ?, ?, NULL, NULL, ?)
      `).bind(token, auth.owner.session_id, productId, expiresAt, createdAt.toISOString()).run();
    } catch {
      return c.json({ success: false, error: { code: "INTERNAL_ERROR", message: "Something went wrong." } }, 500);
    }

    return c.json({
      success: true,
      data: {
        schema_version: 1,
        application_account_token: token,
        product_id: productId,
        expires_at: expiresAt,
      },
    }, 201);
  });

  routes.post("/entitlements/apple/verify", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "internal_error") return internalError(c);
    if (auth.status === "unauthorized") return c.json(UNAUTHORIZED, 401);

    const body = verificationBody(await readJson(c.req));
    const idempotencyKey = c.req.header("Idempotency-Key");
    if (!body || idempotencyKey !== body.requestId) {
      return c.json({ success: false, error: { code: "VALIDATION_ERROR", message: "Invalid request." } }, 422);
    }

    const evidenceSha256 = await sha256Hex(body.signedTransactionInfo);
    const attemptedAt = now();
    const existing = await loadAttempt(c.env.DB, auth.owner.session_id, body.requestId);
    if (existing) {
      if (existing.evidence_sha256 !== evidenceSha256) {
        return c.json({ success: false, error: { code: "STATE_CONFLICT", message: "Idempotency key was used with different evidence." } }, 409);
      }
      if (!shouldResumeAppleVerificationAttempt(existing, attemptedAt)) {
        return storedAttemptResponse(c, existing);
      }
    }

    const reserved = await reserveAttempt(
      c.env.DB,
      auth.owner.session_id,
      body.requestId,
      evidenceSha256,
      attemptedAt,
    );
    if (!reserved) {
      const raced = await loadAttempt(c.env.DB, auth.owner.session_id, body.requestId);
      return raced ? storedAttemptResponse(c, raced) : internalError(c);
    }

    const configuredVerifier = await verifierFactory(c.env);
    const allowedProducts = configuredProductIds(c.env.APPLE_IAP_PRODUCT_IDS);
    if (!configuredVerifier || !allowedProducts) {
      return await finishAttempt(c, auth.owner.session_id, body.requestId, "VERIFICATION_UNAVAILABLE", 503, VERIFICATION_UNAVAILABLE);
    }

    let transaction: JWSTransactionDecodedPayload;
    try {
      transaction = await configuredVerifier.verifier.verifyAndDecodeTransaction(body.signedTransactionInfo);
    } catch {
      return await finishAttempt(c, auth.owner.session_id, body.requestId, "EVIDENCE_INVALID", 422, {
        success: false,
        error: { code: "EVIDENCE_INVALID", message: "Apple transaction evidence is invalid." },
      });
    }

    const normalized = normalizeAppleTransaction(
      transaction,
      configuredVerifier.environment,
      allowedProducts,
      attemptedAt,
    );
    if (!normalized) {
      return await finishAttempt(c, auth.owner.session_id, body.requestId, "EVIDENCE_INVALID", 422, {
        success: false,
        error: { code: "EVIDENCE_INVALID", message: "Apple transaction evidence is invalid." },
      }, transaction.transactionId);
    }

    const product = await c.env.DB.prepare(`
      SELECT entitlement_id
      FROM billing_product
      WHERE store = 'app_store' AND product_id = ? AND active = 1
      LIMIT 1
    `).bind(normalized.productId).first<ProductRow>();
    if (!product || product.entitlement_id !== PREMIUM_ENTITLEMENT_ID) {
      return await finishAttempt(c, auth.owner.session_id, body.requestId, "VERIFICATION_UNAVAILABLE", 503, VERIFICATION_UNAVAILABLE, normalized.transactionId);
    }

    const challenge = await c.env.DB.prepare(`
      SELECT token, session_id, product_id, expires_at, consumed_at
      FROM billing_apple_purchase_challenge
      WHERE token = ?
      LIMIT 1
    `).bind(normalized.appAccountToken).first<ChallengeRow>();
    if (!validChallenge(challenge, auth.owner.session_id, normalized.productId, attemptedAt)) {
      return await finishAttempt(c, auth.owner.session_id, body.requestId, "REPLAY_REJECTED", 409, {
        success: false,
        error: { code: "REPLAY_REJECTED", message: "Apple purchase proof is not valid for this session." },
      }, normalized.transactionId);
    }

    const existingTransaction = await c.env.DB.prepare(`
      SELECT id FROM billing_transaction
      WHERE store = 'app_store' AND environment = ? AND transaction_id = ?
      LIMIT 1
    `).bind(normalized.environment, normalized.transactionId).first<{ id: string }>();
    if (existingTransaction) {
      return await finishAttempt(c, auth.owner.session_id, body.requestId, "REPLAY_REJECTED", 409, {
        success: false,
        error: { code: "REPLAY_REJECTED", message: "Apple transaction was already processed." },
      }, normalized.transactionId);
    }

    const existingChain = await c.env.DB.prepare(`
      SELECT id, status, state_effective_at
      FROM billing_purchase_chain
      WHERE store = 'app_store' AND environment = ? AND original_transaction_id = ?
      LIMIT 1
    `).bind(normalized.environment, normalized.originalTransactionId).first<ChainRow>();
    if (hasLaterChainState(existingChain, normalized.stateEffectiveAt)) {
      return await finishAttempt(c, auth.owner.session_id, body.requestId, "STATE_CONFLICT", 409, {
        success: false,
        error: { code: "STATE_CONFLICT", message: "A newer Apple lifecycle state already exists." },
      }, normalized.transactionId);
    }

    const chainId = existingChain?.id ?? createId(attemptedAt);
    const usd = await loadBillingUsdSnapshot(
      c.env.CACHE_KV, normalized.amountMicros, normalized.currency, attemptedAt,
    );
    const successResponse = {
      success: true,
      data: {
        schema_version: 1,
        state: "VERIFIED_ACTIVE",
        entitlement_id: product.entitlement_id,
        product_id: normalized.productId,
        expires_at: normalized.expiresAt,
      },
    } as const;
    const orderFactStatements = billingOrderFactStatements(c.env.DB, chainId, normalized.environment);
    const grantResultIndex = 3 + orderFactStatements.length;
    const attemptResultIndex = grantResultIndex + 1;
    let mutationResults: D1Result[];
    try {
      mutationResults = await c.env.DB.batch([
      c.env.DB.prepare(`
        UPDATE billing_apple_purchase_challenge
        SET consumed_at = ?, consumed_transaction_id = ?
        WHERE token = ? AND session_id = ? AND product_id = ?
          AND consumed_at IS NULL AND expires_at > ?
          AND NOT EXISTS (
            SELECT 1 FROM billing_purchase_chain
            WHERE store = 'app_store' AND environment = ? AND original_transaction_id = ?
              AND state_effective_at IS NOT NULL AND state_effective_at > ?
          )
      `).bind(
        attemptedAt.toISOString(), normalized.transactionId, normalized.appAccountToken,
        auth.owner.session_id, normalized.productId, attemptedAt.toISOString(),
        normalized.environment, normalized.originalTransactionId, normalized.stateEffectiveAt,
      ),
      c.env.DB.prepare(`
        INSERT INTO billing_purchase_chain
          (id, store, environment, original_transaction_id, product_id, entitlement_id,
           original_owner_type, original_owner_id, app_account_token, status, auto_renew,
           expires_at, grace_period_expires_at, revoked_at, state_effective_at, created_at, updated_at)
        SELECT ?, 'app_store', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?
        WHERE EXISTS (
          SELECT 1 FROM billing_apple_purchase_challenge
          WHERE token = ? AND consumed_transaction_id = ?
        )
        ON CONFLICT(store, environment, original_transaction_id) DO UPDATE SET
          product_id = excluded.product_id,
          entitlement_id = excluded.entitlement_id,
          original_owner_type = CASE WHEN billing_purchase_chain.original_owner_type = 'unlinked'
            THEN excluded.original_owner_type ELSE billing_purchase_chain.original_owner_type END,
          original_owner_id = CASE WHEN billing_purchase_chain.original_owner_type = 'unlinked'
            THEN excluded.original_owner_id ELSE billing_purchase_chain.original_owner_id END,
          app_account_token = excluded.app_account_token,
          status = excluded.status,
          auto_renew = excluded.auto_renew,
          expires_at = excluded.expires_at,
          revoked_at = NULL,
          state_effective_at = excluded.state_effective_at,
          updated_at = excluded.updated_at
        WHERE billing_purchase_chain.state_effective_at IS NULL
           OR billing_purchase_chain.state_effective_at <= excluded.state_effective_at
      `).bind(
        chainId, normalized.environment, normalized.originalTransactionId, normalized.productId,
        product.entitlement_id, auth.owner.owner_type, auth.owner.owner_id,
        normalized.appAccountToken, normalized.chainStatus, normalized.autoRenew,
        normalized.expiresAt, normalized.stateEffectiveAt, attemptedAt.toISOString(), attemptedAt.toISOString(),
        normalized.appAccountToken, normalized.transactionId,
      ),
      c.env.DB.prepare(`
        INSERT INTO billing_transaction
          (id, purchase_chain_id, store, environment, transaction_id, product_id,
           transaction_reason, status, business_status, charge_count, source_notification_uuid,
           auto_renew_snapshot,
           storefront_country_code, amount_micros, currency,
           amount_usd_micros, usd_exchange_rate, usd_exchange_rate_base, usd_exchange_rate_quote,
           usd_exchange_rate_source, usd_exchange_rate_effective_at, usd_exchange_rate_fetched_at,
           usd_exchange_rate_stale, usd_conversion_version, usd_rounding_mode,
           purchase_at, expires_at, revoked_at, signed_transaction, created_at, updated_at)
        SELECT ?, ?, 'app_store', ?, ?, ?, ?, 'purchased', ?, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?
        WHERE EXISTS (
          SELECT 1 FROM billing_apple_purchase_challenge
          WHERE token = ? AND consumed_transaction_id = ?
        )
          AND EXISTS (
            SELECT 1 FROM billing_purchase_chain
            WHERE id = ? AND status = ? AND state_effective_at = ?
          )
      `).bind(
        createId(attemptedAt), chainId, normalized.environment, normalized.transactionId,
        normalized.productId, normalized.transactionReason, normalized.businessStatus,
        normalized.autoRenewSnapshot, normalized.storefront,
        normalized.amountMicros, normalized.currency,
        usd?.amountUsdMicros ?? null, usd?.rate ?? null, usd?.base ?? null, usd?.quote ?? null,
        usd?.source ?? null, usd?.effectiveAt ?? null, usd?.fetchedAt ?? null, usd?.stale ?? null,
        usd?.conversionVersion ?? null, usd?.roundingMode ?? null,
        normalized.purchaseAt, normalized.expiresAt,
        body.signedTransactionInfo, attemptedAt.toISOString(), attemptedAt.toISOString(),
        normalized.appAccountToken, normalized.transactionId,
        chainId, normalized.chainStatus, normalized.stateEffectiveAt,
      ),
      ...orderFactStatements,
      c.env.DB.prepare(`
        INSERT INTO billing_session_entitlement_grant
          (id, session_id, purchase_chain_id, entitlement_id, source, status, granted_at,
           expires_at, last_verified_at, revoked_at, updated_at)
        SELECT ?, ?, ?, ?, 'fresh_purchase', 'active', ?, ?, ?, NULL, ?
        WHERE EXISTS (
          SELECT 1 FROM billing_apple_purchase_challenge
          WHERE token = ? AND consumed_transaction_id = ?
        )
          AND EXISTS (
            SELECT 1 FROM billing_purchase_chain
            WHERE id = ? AND status = ? AND state_effective_at = ?
          )
        ON CONFLICT(session_id, purchase_chain_id, entitlement_id) DO UPDATE SET
          source = excluded.source,
          status = 'active',
          expires_at = excluded.expires_at,
          last_verified_at = excluded.last_verified_at,
          revoked_at = NULL,
          updated_at = excluded.updated_at
      `).bind(
        createId(attemptedAt), auth.owner.session_id, chainId, product.entitlement_id,
        attemptedAt.toISOString(), normalized.expiresAt, attemptedAt.toISOString(),
        attemptedAt.toISOString(), normalized.appAccountToken, normalized.transactionId,
        chainId, normalized.chainStatus, normalized.stateEffectiveAt,
      ),
      c.env.DB.prepare(`
        UPDATE billing_apple_verification_attempt
        SET result_code = 'VERIFIED_ACTIVE', transaction_id = ?, response_json = ?, http_status = 200,
            processing_expires_at = NULL
        WHERE session_id = ? AND request_id = ? AND result_code = 'PROCESSING'
          AND EXISTS (
            SELECT 1 FROM billing_session_entitlement_grant
            WHERE session_id = ? AND purchase_chain_id = ? AND entitlement_id = ?
              AND status = 'active' AND last_verified_at = ?
          )
      `).bind(
        normalized.transactionId, JSON.stringify(successResponse),
        auth.owner.session_id, body.requestId, auth.owner.session_id, chainId,
        product.entitlement_id, attemptedAt.toISOString(),
      ),
      ]);
    } catch {
      return await finishAttempt(c, auth.owner.session_id, body.requestId, "REPLAY_REJECTED", 409, {
        success: false,
        error: { code: "REPLAY_REJECTED", message: "Apple transaction was already processed." },
      }, normalized.transactionId);
    }

    if (
      mutationResults[0]?.meta.changes !== 1 ||
      mutationResults[2]?.meta.changes !== 1 ||
      mutationResults[grantResultIndex]?.meta.changes !== 1 ||
      mutationResults[attemptResultIndex]?.meta.changes !== 1
    ) {
      return await finishAttempt(c, auth.owner.session_id, body.requestId, "REPLAY_REJECTED", 409, {
        success: false,
        error: { code: "REPLAY_REJECTED", message: "Apple purchase proof was already consumed." },
      }, normalized.transactionId);
    }

    return c.json(successResponse, 200);
  });

  return routes;
}

type VerificationBody = { requestId: string; signedTransactionInfo: string };

function verificationBody(body: unknown): VerificationBody | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return null;
  const value = body as Record<string, unknown>;
  if (
    value.schema_version !== 1 ||
    value.evidence_type !== "storekit2_signed_transaction" ||
    typeof value.request_id !== "string" || !isUuid(value.request_id) ||
    typeof value.signed_transaction_info !== "string" ||
    value.signed_transaction_info.length < 1 || value.signed_transaction_info.length > MAX_EVIDENCE_LENGTH
  ) return null;
  return { requestId: value.request_id, signedTransactionInfo: value.signed_transaction_info };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

type NormalizedTransaction = {
  originalTransactionId: string;
  transactionId: string;
  productId: string;
  productType: "subscription" | "non_consumable";
  appAccountToken: string;
  environment: "Production" | "Sandbox";
  transactionReason: string;
  purchaseAt: string;
  expiresAt: string | null;
  stateEffectiveAt: string;
  chainStatus: "ACTIVE" | "TRIAL" | "LIFETIME";
  autoRenew: 0 | 1;
  autoRenewSnapshot: 0 | null;
  storefront: string | null;
  amountMicros: number | null;
  currency: string | null;
  businessStatus: ReturnType<typeof businessStatusForAppleTransaction>;
};

export function normalizeAppleTransaction(
  transaction: JWSTransactionDecodedPayload,
  expectedEnvironment: Environment,
  allowedProducts: ReadonlySet<string>,
  now: Date,
): NormalizedTransaction | null {
  const {
    originalTransactionId, transactionId, productId, appAccountToken,
    purchaseDate, expiresDate, signedDate,
  } = transaction;
  if (
    !originalTransactionId || !transactionId || !productId || !appAccountToken ||
    !isUuid(appAccountToken) || !allowedProducts.has(productId) ||
    transaction.environment !== expectedEnvironment || transaction.transactionReason !== "PURCHASE" ||
    transaction.revocationDate !== undefined || !Number.isFinite(purchaseDate)
  ) return null;

  const isSubscription = transaction.type === "Auto-Renewable Subscription";
  const isLifetime = transaction.type === "Non-Consumable";
  if (!isSubscription && !isLifetime) return null;
  if (isSubscription && (!Number.isFinite(expiresDate) || expiresDate! <= now.getTime())) return null;

  const effectiveMs = Number.isFinite(signedDate) ? signedDate! : purchaseDate!;
  const amountMicros = Number.isSafeInteger(transaction.price)
    ? transaction.price! * 1000
    : null;
  if (amountMicros !== null && !Number.isSafeInteger(amountMicros)) return null;

  return {
    originalTransactionId,
    transactionId,
    productId,
    productType: isSubscription ? "subscription" : "non_consumable",
    appAccountToken: appAccountToken.toLowerCase(),
    environment: expectedEnvironment === Environment.PRODUCTION ? "Production" : "Sandbox",
    transactionReason: transaction.transactionReason,
    purchaseAt: new Date(purchaseDate!).toISOString(),
    expiresAt: isSubscription ? new Date(expiresDate!).toISOString() : null,
    stateEffectiveAt: new Date(effectiveMs).toISOString(),
    chainStatus: isLifetime
      ? "LIFETIME"
      : transaction.offerDiscountType === "FREE_TRIAL" ? "TRIAL" : "ACTIVE",
    autoRenew: isSubscription ? 1 : 0,
    autoRenewSnapshot: isLifetime ? 0 : null,
    storefront: transaction.storefront ?? null,
    amountMicros,
    currency: transaction.currency ?? null,
    businessStatus: businessStatusForAppleTransaction("PURCHASE", "", transaction),
  };
}

function validChallenge(
  challenge: ChallengeRow | null,
  sessionId: string,
  productId: string,
  now: Date,
): challenge is ChallengeRow {
  return !!challenge && challenge.session_id === sessionId && challenge.product_id === productId &&
    challenge.consumed_at === null && Date.parse(challenge.expires_at) > now.getTime();
}

function hasLaterChainState(chain: ChainRow | null, incomingEffectiveAt: string): boolean {
  if (!chain?.state_effective_at) return false;
  const existing = Date.parse(chain.state_effective_at);
  const incoming = Date.parse(incomingEffectiveAt);
  return Number.isFinite(existing) && Number.isFinite(incoming) && existing > incoming;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function loadAttempt(db: D1Database, sessionId: string, requestId: string): Promise<AttemptRow | null> {
  return await db.prepare(`
    SELECT evidence_sha256, response_json, http_status, result_code, processing_expires_at
    FROM billing_apple_verification_attempt
    WHERE session_id = ? AND request_id = ?
    LIMIT 1
  `).bind(sessionId, requestId).first<AttemptRow>();
}

async function reserveAttempt(
  db: D1Database,
  sessionId: string,
  requestId: string,
  evidenceSha256: string,
  now: Date,
): Promise<boolean> {
  const response = JSON.stringify(APPLE_VERIFICATION_PROCESSING_RESPONSE);
  const leaseExpiresAt = new Date(now.getTime() + VERIFICATION_LEASE_MS).toISOString();
  const result = await db.prepare(`
    INSERT INTO billing_apple_verification_attempt
      (id, session_id, request_id, evidence_type, evidence_sha256, result_code,
       transaction_id, response_json, http_status, processing_expires_at, created_at)
    VALUES (?, ?, ?, 'storekit2_signed_transaction', ?, 'PROCESSING', NULL, ?, ?, ?, ?)
    ON CONFLICT(session_id, request_id) DO UPDATE SET
      result_code = 'PROCESSING',
      response_json = excluded.response_json,
      http_status = excluded.http_status,
      processing_expires_at = excluded.processing_expires_at
    WHERE billing_apple_verification_attempt.result_code IN ('PROCESSING', 'VERIFICATION_UNAVAILABLE')
      AND billing_apple_verification_attempt.evidence_sha256 = excluded.evidence_sha256
      AND (
        billing_apple_verification_attempt.result_code = 'VERIFICATION_UNAVAILABLE'
        OR billing_apple_verification_attempt.processing_expires_at IS NULL
        OR billing_apple_verification_attempt.processing_expires_at <= ?
      )
  `).bind(
    createId(now), sessionId, requestId, evidenceSha256, response,
    APPLE_VERIFICATION_PROCESSING_HTTP_STATUS,
    leaseExpiresAt, now.toISOString(), now.toISOString(),
  ).run();
  return result.meta.changes === 1;
}

async function finishAttempt(
  c: Context<{ Bindings: Env }>,
  sessionId: string,
  requestId: string,
  resultCode: string,
  httpStatus: ContentfulStatusCode,
  response: object,
  transactionId: string | undefined = undefined,
) {
  await c.env.DB.prepare(`
    UPDATE billing_apple_verification_attempt
    SET result_code = ?, transaction_id = ?, response_json = ?, http_status = ?, processing_expires_at = NULL
    WHERE session_id = ? AND request_id = ? AND result_code = 'PROCESSING'
  `).bind(resultCode, transactionId ?? null, JSON.stringify(response), httpStatus, sessionId, requestId).run();
  return c.json(response, httpStatus);
}

export function shouldResumeAppleVerificationAttempt(
  attempt: Pick<AttemptRow, "result_code" | "processing_expires_at">,
  now: Date,
): boolean {
  if (attempt.result_code === "VERIFICATION_UNAVAILABLE") return true;
  if (attempt.result_code !== "PROCESSING") return false;
  const expiresAt = attempt.processing_expires_at
    ? Date.parse(attempt.processing_expires_at)
    : NaN;
  return !Number.isFinite(expiresAt) || expiresAt <= now.getTime();
}

function storedAttemptResponse(
  c: Context<{ Bindings: Env }>,
  attempt: AttemptRow,
) {
  try {
    return c.json(JSON.parse(attempt.response_json) as object, attempt.http_status as ContentfulStatusCode);
  } catch {
    return internalError(c);
  }
}

function internalError(c: Context<{ Bindings: Env }>) {
  return c.json({ success: false, error: { code: "INTERNAL_ERROR", message: "Something went wrong." } }, 500);
}

export function configuredProductIds(value: string | undefined): ReadonlySet<string> | null {
  if (!value) return null;
  const ids = value.split(",").map((item) => item.trim()).filter(Boolean);
  return ids.length > 0 ? new Set(ids) : null;
}

async function readJson(request: { json(): Promise<unknown> }): Promise<unknown> {
  try { return await request.json(); } catch { return null; }
}

function productIdFromBody(body: unknown): string | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return null;
  const productId = (body as Record<string, unknown>).product_id;
  return typeof productId === "string" && productId.trim() === productId && productId.length > 0 && productId.length <= 200
    ? productId
    : null;
}
