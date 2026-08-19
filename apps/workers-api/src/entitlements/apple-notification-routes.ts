import { Hono } from "hono";
import type { Env } from "../env";
import { createId } from "../id";
import {
  classifyAppleVerificationFailure,
  createAppleNotificationVerifier,
  Environment,
  type AppleNotificationVerifier,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from "./apple-signed-data";
import { billingOrderFactStatements, businessStatusForAppleTransaction } from "./billing-order-facts";
import { loadBillingUsdSnapshot, type BillingUsdSnapshot } from "./billing-currency";

const MAX_REQUEST_BYTES = 200_000;
const PROCESSING_LEASE_MS = 60_000;
const RETRY_BATCH_SIZE = 20;

type Dependencies = {
  now?: () => Date;
  createVerifier?: (env: Env) => Promise<{
    environment: Environment;
    verifier: AppleNotificationVerifier;
  } | null> | {
    environment: Environment;
    verifier: AppleNotificationVerifier;
  } | null;
};

type InboxRow = {
  id: string;
  environment: "Production" | "Sandbox";
  signed_payload: string;
  processing_status: string;
  processing_expires_at: string | null;
};

type StructuredRow = { inbox_id: string | null; signed_payload: string };
type ChainRow = {
  id: string;
  status: string;
  auto_renew: number;
  next_product_id: string | null;
  state_effective_at: string | null;
  lifecycle_signed_at: string | null;
  lifecycle_notification_uuid: string | null;
  auto_renew_signed_at: string | null;
  plan_signed_at: string | null;
};

export function createAppleNotificationRoutes(
  dependencies: Dependencies = {},
): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();
  const now = dependencies.now ?? (() => new Date());

  routes.post("/apple/notifications/v2", async (c) => {
    const contentLength = Number(c.req.header("content-length"));
    if (Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BYTES) {
      return c.json({ error: "PAYLOAD_TOO_LARGE" }, 413);
    }

    const requestJson = await c.req.raw.text();
    if (new TextEncoder().encode(requestJson).byteLength > MAX_REQUEST_BYTES) {
      return c.json({ error: "PAYLOAD_TOO_LARGE" }, 413);
    }
    const signedPayload = readSignedPayload(requestJson);
    if (!signedPayload) return c.json({ error: "INVALID_REQUEST" }, 400);

    const receivedAt = now();
    const environment = runtimeAppleEnvironment(c.env);
    const payloadSha256 = await sha256Hex(signedPayload);
    const inboxId = createId(receivedAt);
    try {
      await c.env.DB.prepare(`
        INSERT INTO apple_notification_inbox
          (id, payload_sha256, request_json, signed_payload, processing_status, attempts,
           environment, processing_expires_at, notification_uuid, last_error, received_at,
           processed_at)
        VALUES (?, ?, ?, ?, 'pending', 0, ?, NULL, NULL, NULL, ?, NULL)
        ON CONFLICT DO NOTHING
      `).bind(
        inboxId,
        payloadSha256,
        requestJson,
        signedPayload,
        environment,
        receivedAt.toISOString(),
      ).run();
    } catch {
      return c.json({ error: "PERSISTENCE_FAILED" }, 500);
    }

    const inbox = await c.env.DB.prepare(`
      SELECT id, environment, signed_payload, processing_status, processing_expires_at
      FROM apple_notification_inbox
      WHERE environment = ? AND payload_sha256 = ? LIMIT 1
    `).bind(environment, payloadSha256).first<InboxRow>();
    if (!inbox) return c.json({ error: "PERSISTENCE_FAILED" }, 500);

    const processing = processAppleNotificationInbox(c.env, inbox.id, dependencies);
    try {
      c.executionCtx.waitUntil(processing);
    } catch {
      await processing;
    }
    return c.body(null, 200);
  });

  return routes;
}

export async function retryAppleNotificationInbox(
  env: Env,
  dependencies: Dependencies = {},
): Promise<void> {
  const now = dependencies.now?.() ?? new Date();
  const environment = runtimeAppleEnvironment(env);
  const { results = [] } = await env.DB.prepare(`
    SELECT id FROM apple_notification_inbox
    WHERE environment = ? AND (
      processing_status IN ('pending', 'processing_failed')
      OR (processing_status = 'processing' AND processing_expires_at <= ?)
    )
    ORDER BY received_at ASC, id ASC LIMIT ?
  `).bind(environment, now.toISOString(), RETRY_BATCH_SIZE).all<{ id: string }>();
  for (const row of results) await processAppleNotificationInbox(env, row.id, dependencies);
}

export async function processAppleNotificationInbox(
  env: Env,
  inboxId: string,
  dependencies: Dependencies = {},
): Promise<void> {
  const now = dependencies.now?.() ?? new Date();
  const environment = runtimeAppleEnvironment(env);
  const leaseExpiresAt = new Date(now.getTime() + PROCESSING_LEASE_MS).toISOString();
  const reserved = await env.DB.prepare(`
    UPDATE apple_notification_inbox
    SET processing_status = 'processing', attempts = attempts + 1,
        processing_expires_at = ?, last_error = NULL
    WHERE id = ? AND environment = ? AND (
      processing_status IN ('pending', 'processing_failed')
      OR (processing_status = 'processing' AND processing_expires_at <= ?)
    )
  `).bind(leaseExpiresAt, inboxId, environment, now.toISOString()).run();
  if (reserved.meta.changes !== 1) return;

  const inbox = await env.DB.prepare(`
    SELECT id, environment, signed_payload, processing_status, processing_expires_at
    FROM apple_notification_inbox WHERE id = ? AND environment = ? LIMIT 1
  `).bind(inboxId, environment).first<InboxRow>();
  if (!inbox) return;

  const configured = await (dependencies.createVerifier ?? createAppleNotificationVerifier)(env);
  if (!configured) {
    await failInbox(env.DB, inboxId, environment, "processing_failed", "VERIFIER_NOT_CONFIGURED");
    return;
  }
  if (configured.environment !== environment) {
    await failInbox(
      env.DB,
      inboxId,
      environment,
      "processing_failed",
      "VERIFIER_ENVIRONMENT_MISMATCH",
    );
    return;
  }

  let notification: ResponseBodyV2DecodedPayload;
  try {
    notification = await configured.verifier.verifyAndDecodeNotification(inbox.signed_payload);
  } catch (error) {
    const failure = await classifyAppleVerificationFailure(error);
    await failInbox(
      env.DB,
      inboxId,
      environment,
      failure?.retryable ? "processing_failed" : "verification_failed",
      failure ? `NOTIFICATION_JWS_${failure.status}` : "NOTIFICATION_JWS_INVALID",
      failure?.retryable ? undefined : now,
    );
    return;
  }

  const envelope = normalizeEnvelope(notification, configured.environment);
  if (!envelope) {
    await failInbox(env.DB, inboxId, environment, "parse_failed", "NOTIFICATION_PAYLOAD_INVALID", now);
    return;
  }

  let transaction: JWSTransactionDecodedPayload | null = null;
  let renewal: JWSRenewalInfoDecodedPayload | null = null;
  try {
    if (notification.data?.signedTransactionInfo) {
      transaction = await configured.verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo);
    }
    if (notification.data?.signedRenewalInfo) {
      renewal = await configured.verifier.verifyAndDecodeRenewalInfo(notification.data.signedRenewalInfo);
    }
  } catch (error) {
    const failure = await classifyAppleVerificationFailure(error);
    await failInbox(
      env.DB,
      inboxId,
      environment,
      failure?.retryable ? "processing_failed" : "parse_failed",
      failure ? `NESTED_JWS_${failure.status}` : "NESTED_JWS_INVALID",
      failure?.retryable ? undefined : now,
    );
    return;
  }

  if (!nestedEvidenceMatches(transaction, renewal, envelope.environment)) {
    await failInbox(env.DB, inboxId, environment, "parse_failed", "NESTED_EVIDENCE_MISMATCH", now);
    return;
  }

  const existingNotification = await env.DB.prepare(`
    SELECT inbox_id, signed_payload FROM apple_server_notification
    WHERE notification_uuid = ? LIMIT 1
  `).bind(envelope.notificationUuid).first<StructuredRow>();
  if (existingNotification && existingNotification.signed_payload !== inbox.signed_payload) {
    await failInbox(env.DB, inboxId, environment, "correction_required", "NOTIFICATION_UUID_CONFLICT", now);
    return;
  }

  const originalTransactionId = transaction?.originalTransactionId ?? renewal?.originalTransactionId ?? null;
  const transactionId = transaction?.transactionId ?? null;
  const productId = transaction?.productId ?? renewal?.productId ?? null;
  const decodedPayload = JSON.stringify({ notification, transaction, renewal_info: renewal });
  try {
    await env.DB.prepare(`
      INSERT INTO apple_server_notification
        (id, inbox_id, notification_uuid, notification_type, subtype, environment,
         original_transaction_id, transaction_id, product_id, signed_payload,
         decoded_payload, processing_status, attempts, last_error, signed_at,
         received_at, processed_at)
      SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, NULL, ?, received_at, NULL
      FROM apple_notification_inbox WHERE id = ? AND environment = ?
      ON CONFLICT DO NOTHING
    `).bind(
      createId(now), inboxId, envelope.notificationUuid, envelope.notificationType,
      envelope.subtype, envelope.environment, originalTransactionId, transactionId,
      productId, inbox.signed_payload, decodedPayload, envelope.signedAt, inboxId, environment,
    ).run();

    const amountMicros = applePriceMicros(transaction?.price);
    const usd = createsOrder(envelope.notificationType)
      ? await loadBillingUsdSnapshot(
          env.CACHE_KV, amountMicros, transaction?.currency ?? null, now,
        )
      : null;
    const outcome = await consumeNotification(
      env.DB,
      envelope,
      transaction,
      renewal,
      notification.data?.signedTransactionInfo ?? null,
      now,
      usd,
    );
    await completeInbox(env.DB, inboxId, environment, envelope.notificationUuid, outcome, now);
  } catch {
    await failInbox(
      env.DB,
      inboxId,
      environment,
      "processing_failed",
      "BUSINESS_CONSUMPTION_FAILED",
    );
  }
}

type Envelope = {
  notificationUuid: string;
  notificationType: string;
  subtype: string | null;
  environment: "Production" | "Sandbox";
  signedAt: string;
};

function normalizeEnvelope(
  value: ResponseBodyV2DecodedPayload,
  expectedEnvironment: Environment,
): Envelope | null {
  const environment = expectedEnvironment === Environment.PRODUCTION ? "Production" : "Sandbox";
  if (
    !value.notificationUUID || !value.notificationType || !Number.isFinite(value.signedDate) ||
    value.data?.environment !== undefined && value.data.environment !== expectedEnvironment
  ) return null;
  return {
    notificationUuid: value.notificationUUID,
    notificationType: value.notificationType,
    subtype: value.subtype ?? null,
    environment,
    signedAt: new Date(value.signedDate!).toISOString(),
  };
}

function nestedEvidenceMatches(
  transaction: JWSTransactionDecodedPayload | null,
  renewal: JWSRenewalInfoDecodedPayload | null,
  environment: "Production" | "Sandbox",
): boolean {
  if (transaction?.environment !== undefined && transaction.environment !== environment) return false;
  if (renewal?.environment !== undefined && renewal.environment !== environment) return false;
  if (
    transaction?.originalTransactionId && renewal?.originalTransactionId &&
    transaction.originalTransactionId !== renewal.originalTransactionId
  ) return false;
  return true;
}

type ConsumptionOutcome = "processed" | "correction_required";

async function consumeNotification(
  db: D1Database,
  envelope: Envelope,
  transaction: JWSTransactionDecodedPayload | null,
  renewal: JWSRenewalInfoDecodedPayload | null,
  signedTransaction: string | null,
  now: Date,
  usd: BillingUsdSnapshot | null,
): Promise<ConsumptionOutcome> {
  const originalTransactionId = transaction?.originalTransactionId ?? renewal?.originalTransactionId;
  const lifecycle = lifecycleFor(envelope, transaction, renewal);
  const updatesRenewal = envelope.notificationType === "DID_CHANGE_RENEWAL_STATUS";
  const updatesPlan = envelope.notificationType === "DID_CHANGE_RENEWAL_PREF";
  const needsChain = lifecycle !== null || updatesRenewal || updatesPlan ||
    createsOrder(envelope.notificationType) || envelope.notificationType === "REFUND";
  if (!originalTransactionId) return needsChain ? "correction_required" : "processed";

  let chain = await db.prepare(`
    SELECT id, status, auto_renew, next_product_id, state_effective_at, lifecycle_signed_at,
           lifecycle_notification_uuid, auto_renew_signed_at, plan_signed_at
    FROM billing_purchase_chain
    WHERE store = 'app_store' AND environment = ? AND original_transaction_id = ? LIMIT 1
  `).bind(envelope.environment, originalTransactionId).first<ChainRow>();
  if (!chain && createsOrder(envelope.notificationType) &&
      validTransaction(transaction, envelope.environment) && lifecycle) {
    const product = await db.prepare(`SELECT entitlement_id FROM billing_product
      WHERE store = 'app_store' AND product_id = ? AND active = 1 LIMIT 1`)
      .bind(transaction.productId).first<{ entitlement_id: string }>();
    if (!product) return "correction_required";
    const chainId = createId(now);
    await db.prepare(`
      INSERT INTO billing_purchase_chain
        (id, store, environment, original_transaction_id, product_id, entitlement_id,
         original_owner_type, original_owner_id, status, auto_renew, expires_at,
         grace_period_expires_at, revoked_at, state_effective_at, created_at, updated_at)
      VALUES (?, 'app_store', ?, ?, ?, ?, 'unlinked', '', ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT DO NOTHING
    `).bind(
      chainId, envelope.environment, originalTransactionId, transaction.productId,
      product.entitlement_id, lifecycle.status, lifecycle.autoRenew, lifecycle.expiresAt,
      lifecycle.gracePeriodExpiresAt, lifecycle.revokedAt, lifecycle.stateEffectiveAt,
      now.toISOString(), now.toISOString(),
    ).run();
    chain = await db.prepare(`
      SELECT id, status, auto_renew, next_product_id, state_effective_at, lifecycle_signed_at,
             lifecycle_notification_uuid, auto_renew_signed_at, plan_signed_at
      FROM billing_purchase_chain
      WHERE store = 'app_store' AND environment = ? AND original_transaction_id = ? LIMIT 1
    `).bind(envelope.environment, originalTransactionId).first<ChainRow>();
  }
  if (!chain) return needsChain ? "correction_required" : "processed";

  if (
    chain.lifecycle_signed_at === envelope.signedAt &&
    chain.lifecycle_notification_uuid &&
    chain.lifecycle_notification_uuid !== envelope.notificationUuid
  ) return "correction_required";

  const statements: D1PreparedStatement[] = [];
  if (createsOrder(envelope.notificationType) && !validTransaction(transaction, envelope.environment)) {
    return "correction_required";
  }
  if (updatesRenewal && renewal?.autoRenewStatus !== 0 && renewal?.autoRenewStatus !== 1) {
    return "correction_required";
  }
  if (updatesPlan && !renewal?.autoRenewProductId) return "correction_required";
  if (
    updatesRenewal && chain.auto_renew_signed_at === envelope.signedAt &&
    chain.auto_renew !== renewal!.autoRenewStatus
  ) return "correction_required";
  if (
    updatesPlan && chain.plan_signed_at === envelope.signedAt &&
    chain.next_product_id !== renewal!.autoRenewProductId
  ) return "correction_required";
  if (updatesRenewal) {
    statements.push(db.prepare(`
      UPDATE billing_purchase_chain
      SET auto_renew = ?, auto_renew_signed_at = ?, updated_at = ?
      WHERE id = ? AND (auto_renew_signed_at IS NULL OR auto_renew_signed_at < ?)
    `).bind(
      renewal?.autoRenewStatus === 1 ? 1 : 0, envelope.signedAt,
      now.toISOString(), chain.id, envelope.signedAt,
    ));
  }
  if (updatesPlan) {
    statements.push(db.prepare(`
      UPDATE billing_purchase_chain
      SET next_product_id = ?, plan_signed_at = ?, updated_at = ?
      WHERE id = ? AND (plan_signed_at IS NULL OR plan_signed_at < ?)
    `).bind(renewal?.autoRenewProductId ?? null, envelope.signedAt, now.toISOString(), chain.id, envelope.signedAt));
  }
  if (createsOrder(envelope.notificationType) && validTransaction(transaction, envelope.environment)) {
    const businessStatus = businessStatusForAppleTransaction(
      envelope.notificationType,
      chain.status,
      transaction,
    );
    const autoRenewSnapshot = transaction.type === "Non-Consumable"
      ? 0
      : renewal?.autoRenewStatus === 0 || renewal?.autoRenewStatus === 1
        ? renewal.autoRenewStatus
        : null;
    statements.push(db.prepare(`
      INSERT INTO billing_transaction
        (id, purchase_chain_id, store, environment, transaction_id, product_id,
         transaction_reason, status, business_status, charge_count, source_notification_uuid,
         auto_renew_snapshot,
         storefront_country_code, amount_micros, currency,
         amount_usd_micros, usd_exchange_rate, usd_exchange_rate_base, usd_exchange_rate_quote,
         usd_exchange_rate_source, usd_exchange_rate_effective_at, usd_exchange_rate_fetched_at,
         usd_exchange_rate_stale, usd_conversion_version, usd_rounding_mode,
         purchase_at, expires_at, revoked_at, refund_completed_at,
         signed_transaction, created_at, updated_at)
      VALUES (?, ?, 'app_store', ?, ?, ?, ?, 'purchased', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?)
      ON CONFLICT DO NOTHING
    `).bind(
      createId(now), chain.id, envelope.environment, transaction.transactionId,
      transaction.productId, transaction.transactionReason ?? "PURCHASE",
      businessStatus,
      null,
      envelope.notificationUuid,
      autoRenewSnapshot,
      transaction.storefront ?? null, applePriceMicros(transaction.price), transaction.currency ?? null,
      usd?.amountUsdMicros ?? null, usd?.rate ?? null, usd?.base ?? null, usd?.quote ?? null,
      usd?.source ?? null, usd?.effectiveAt ?? null, usd?.fetchedAt ?? null, usd?.stale ?? null,
      usd?.conversionVersion ?? null, usd?.roundingMode ?? null,
      toIso(transaction.purchaseDate), toNullableIso(transaction.expiresDate), signedTransaction,
      now.toISOString(), now.toISOString(),
    ));
    statements.push(...billingOrderFactStatements(db, chain.id, envelope.environment));
  }

  if (envelope.notificationType === "REFUND" && transaction?.transactionId) {
    const refundedOrder = await db.prepare(`
      SELECT id FROM billing_transaction
      WHERE purchase_chain_id = ? AND environment = ? AND transaction_id = ? LIMIT 1
    `).bind(chain.id, envelope.environment, transaction.transactionId).first<{ id: string }>();
    if (!refundedOrder) return "correction_required";
    statements.push(db.prepare(`
      UPDATE billing_transaction
      SET status = 'refunded', business_status = 'refunded', revoked_at = ?, refund_completed_at = ?, updated_at = ?
      WHERE purchase_chain_id = ? AND environment = ? AND transaction_id = ?
    `).bind(
      toNullableIso(transaction.revocationDate) ?? envelope.signedAt,
      toNullableIso(transaction.revocationDate) ?? envelope.signedAt,
      now.toISOString(), chain.id, envelope.environment, transaction.transactionId,
    ));
  }

  const applyLifecycle = lifecycle && (
    chain.state_effective_at === null || chain.state_effective_at <= lifecycle.stateEffectiveAt
  );
  if (applyLifecycle) {
    statements.push(db.prepare(`
      UPDATE billing_purchase_chain SET
        product_id = COALESCE(?, product_id), next_product_id = ?, status = ?, auto_renew = ?,
        expires_at = COALESCE(?, expires_at), grace_period_expires_at = ?, revoked_at = ?,
        state_effective_at = ?, lifecycle_signed_at = ?, lifecycle_notification_uuid = ?,
        correction_status = NULL, updated_at = ?
      WHERE id = ?
        AND (state_effective_at IS NULL OR state_effective_at <= ?)
        AND (lifecycle_signed_at IS NULL OR lifecycle_signed_at < ?)
    `).bind(
      lifecycle.productId, lifecycle.nextProductId, lifecycle.status, lifecycle.autoRenew,
      lifecycle.expiresAt, lifecycle.gracePeriodExpiresAt, lifecycle.revokedAt,
      lifecycle.stateEffectiveAt, envelope.signedAt, envelope.notificationUuid,
      now.toISOString(), chain.id, lifecycle.stateEffectiveAt, envelope.signedAt,
    ));
    statements.push(db.prepare(`
      UPDATE billing_session_entitlement_grant SET
        status = ?, expires_at = ?, last_verified_at = ?, revoked_at = ?, updated_at = ?
      WHERE purchase_chain_id = ? AND EXISTS (
        SELECT 1 FROM billing_purchase_chain
        WHERE id = ? AND lifecycle_notification_uuid = ?
      )
    `).bind(
      lifecycle.grantStatus, lifecycle.expiresAt, envelope.signedAt,
      lifecycle.grantStatus === "active" ? null : lifecycle.stateEffectiveAt,
      now.toISOString(), chain.id, chain.id, envelope.notificationUuid,
    ));
  }

  if (statements.length > 0) await db.batch(statements);
  if (envelope.notificationType === "REFUND_REVERSED") return "correction_required";
  return "processed";
}

type Lifecycle = {
  status: string;
  grantStatus: "active" | "expired" | "revoked";
  autoRenew: 0 | 1;
  productId: string | null;
  nextProductId: string | null;
  expiresAt: string | null;
  gracePeriodExpiresAt: string | null;
  revokedAt: string | null;
  stateEffectiveAt: string;
};

function lifecycleFor(
  envelope: Envelope,
  transaction: JWSTransactionDecodedPayload | null,
  renewal: JWSRenewalInfoDecodedPayload | null,
): Lifecycle | null {
  const autoRenew = transaction?.type === "Non-Consumable"
    ? 0
    : renewal?.autoRenewStatus === 1 ? 1 : 0;
  const expiresAt = toNullableIso(transaction?.expiresDate);
  const gracePeriodExpiresAt = toNullableIso(renewal?.gracePeriodExpiresDate);
  const base = {
    autoRenew: autoRenew as 0 | 1,
    productId: transaction?.productId ?? renewal?.productId ?? null,
    nextProductId: envelope.notificationType === "DID_CHANGE_RENEWAL_PREF" ? renewal?.autoRenewProductId ?? null : null,
    expiresAt,
    gracePeriodExpiresAt,
    revokedAt: null,
    stateEffectiveAt: envelope.signedAt,
  };
  switch (envelope.notificationType) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "ONE_TIME_CHARGE":
      return { ...base, status: transaction?.type === "Non-Consumable"
        ? "LIFETIME"
        : transaction?.offerDiscountType === "FREE_TRIAL" ? "TRIAL" : "ACTIVE", grantStatus: "active" };
    case "DID_FAIL_TO_RENEW":
      return envelope.subtype === "GRACE_PERIOD"
        ? { ...base, status: "GRACE_PERIOD", grantStatus: "active", expiresAt: gracePeriodExpiresAt }
        : { ...base, status: "BILLING_RETRY", grantStatus: "expired" };
    case "GRACE_PERIOD_EXPIRED":
      return { ...base, status: "BILLING_RETRY", grantStatus: "expired" };
    case "EXPIRED":
      return { ...base, status: "EXPIRED", grantStatus: "expired" };
    case "REFUND":
    case "REVOKE":
      return { ...base, status: "REVOKED", grantStatus: "revoked", revokedAt: toNullableIso(transaction?.revocationDate) ?? envelope.signedAt };
    default:
      return null;
  }
}

function createsOrder(type: string): boolean {
  return type === "SUBSCRIBED" || type === "DID_RENEW" || type === "ONE_TIME_CHARGE";
}

function validTransaction(
  value: JWSTransactionDecodedPayload | null,
  environment: "Production" | "Sandbox",
): value is JWSTransactionDecodedPayload & { transactionId: string; productId: string; purchaseDate: number } {
  return !!value?.transactionId && !!value.productId && Number.isFinite(value.purchaseDate) &&
    (value.environment === undefined || value.environment === environment);
}

async function completeInbox(
  db: D1Database,
  inboxId: string,
  environment: "Production" | "Sandbox",
  notificationUuid: string,
  outcome: ConsumptionOutcome,
  now: Date,
): Promise<void> {
  const error = outcome === "correction_required" ? "APPLE_SERVER_API_CORRECTION_REQUIRED" : null;
  await db.batch([
    db.prepare(`
      UPDATE apple_server_notification
      SET processing_status = ?, attempts = attempts + 1, last_error = ?, processed_at = ?
      WHERE inbox_id = ? AND environment = ?
    `).bind(outcome, error, now.toISOString(), inboxId, environment),
    db.prepare(`
      UPDATE apple_notification_inbox
      SET processing_status = ?, processing_expires_at = NULL, notification_uuid = ?,
          last_error = ?, processed_at = ? WHERE id = ? AND environment = ?
    `).bind(outcome, notificationUuid, error, now.toISOString(), inboxId, environment),
  ]);
}

async function failInbox(
  db: D1Database,
  inboxId: string,
  environment: "Production" | "Sandbox",
  status: "verification_failed" | "parse_failed" | "correction_required" | "processing_failed",
  error: string,
  now?: Date,
): Promise<void> {
  await db.prepare(`
    UPDATE apple_notification_inbox
    SET processing_status = ?, processing_expires_at = NULL, last_error = ?, processed_at = ?
    WHERE id = ? AND environment = ?
  `).bind(status, error, now?.toISOString() ?? null, inboxId, environment).run();
}

function runtimeAppleEnvironment(env: Env): "Production" | "Sandbox" {
  return env.APP_ENVIRONMENT === "production" ? "Production" : "Sandbox";
}

function readSignedPayload(requestJson: string): string | null {
  try {
    const value = JSON.parse(requestJson) as unknown;
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const payload = (value as Record<string, unknown>).signedPayload;
    return typeof payload === "string" && payload.length > 0 && payload.length <= MAX_REQUEST_BYTES
      ? payload
      : null;
  } catch {
    return null;
  }
}

function toIso(value: number | undefined): string {
  return new Date(value!).toISOString();
}

function toNullableIso(value: number | undefined): string | null {
  return Number.isFinite(value) ? new Date(value!).toISOString() : null;
}

function applePriceMicros(value: number | undefined): number | null {
  if (!Number.isSafeInteger(value)) return null;
  const micros = value! * 1000;
  return Number.isSafeInteger(micros) ? micros : null;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
