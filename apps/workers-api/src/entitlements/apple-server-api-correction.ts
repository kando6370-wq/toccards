import type {
  AppStoreServerAPIClient,
  StatusResponse,
  TransactionInfoResponse,
} from "@apple/app-store-server-library";
import type { Env } from "../env";
import {
  createAppleNotificationVerifier,
  Environment,
  type AppleNotificationVerifier,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
} from "./apple-signed-data";

const CORRECTION_BATCH_SIZE = 20;
const CORRECTION_LEASE_MS = 60_000;
const RETRY_DELAY_MS = 5 * 60_000;
const APPLE_SUBSCRIPTION_STATUS = {
  ACTIVE: 1,
  EXPIRED: 2,
  BILLING_RETRY: 3,
  BILLING_GRACE_PERIOD: 4,
  REVOKED: 5,
} as const;

export type AppleServerApi = Pick<
  AppStoreServerAPIClient,
  "getAllSubscriptionStatuses" | "getTransactionInfo"
>;

type Dependencies = {
  now?: () => Date;
  createClient?: (env: Env) => Promise<AppleServerApi | null> | AppleServerApi | null;
  createVerifier?: (env: Env) => Promise<{
    environment: Environment;
    verifier: AppleNotificationVerifier;
  } | null> | {
    environment: Environment;
    verifier: AppleNotificationVerifier;
  } | null;
};

type CorrectionRow = {
  inbox_id: string;
  notification_uuid: string;
  notification_type: string;
  environment: "Production" | "Sandbox";
  original_transaction_id: string;
  transaction_id: string | null;
};

export async function createAppleServerApiClient(env: Env): Promise<AppleServerApi | null> {
  const signingKey = env.APPLE_IAP_PRIVATE_KEY;
  const keyId = env.APPLE_IAP_KEY_ID?.trim();
  const issuerId = env.APPLE_IAP_ISSUER_ID?.trim();
  const bundleId = env.APPLE_IAP_BUNDLE_ID?.trim();
  if (!signingKey || !keyId || !issuerId || !bundleId) return null;
  const environment = env.APP_ENVIRONMENT === "production"
    ? Environment.PRODUCTION
    : Environment.SANDBOX;
  try {
    const { AppStoreServerAPIClient } = await import("@apple/app-store-server-library");
    return new AppStoreServerAPIClient(signingKey, keyId, issuerId, bundleId, environment);
  } catch {
    return null;
  }
}

export async function retryAppleServerApiCorrections(
  env: Env,
  dependencies: Dependencies = {},
): Promise<void> {
  const now = dependencies.now?.() ?? new Date();
  const { results = [] } = await env.DB.prepare(`
    SELECT n.inbox_id, n.notification_uuid, n.notification_type, n.environment,
           n.original_transaction_id, n.transaction_id
    FROM apple_server_notification n
    JOIN apple_notification_inbox i ON i.id = n.inbox_id
    WHERE i.processing_status = 'correction_required'
      AND n.original_transaction_id IS NOT NULL
      AND (i.processing_expires_at IS NULL OR i.processing_expires_at <= ?)
    ORDER BY i.received_at ASC LIMIT ?
  `).bind(now.toISOString(), CORRECTION_BATCH_SIZE).all<CorrectionRow>();

  for (const row of results) {
    await correctApplePurchaseChain(env, row, dependencies);
  }
}

async function correctApplePurchaseChain(
  env: Env,
  row: CorrectionRow,
  dependencies: Dependencies,
): Promise<void> {
  const now = dependencies.now?.() ?? new Date();
  const leaseExpiresAt = new Date(now.getTime() + CORRECTION_LEASE_MS).toISOString();
  const reserved = await env.DB.prepare(`
    UPDATE apple_notification_inbox
    SET processing_status = 'processing', attempts = attempts + 1,
        processing_expires_at = ?, last_error = NULL
    WHERE id = ? AND processing_status = 'correction_required'
      AND (processing_expires_at IS NULL OR processing_expires_at <= ?)
  `).bind(leaseExpiresAt, row.inbox_id, now.toISOString()).run();
  if (reserved.meta.changes !== 1) return;

  const client = await (dependencies.createClient ?? createAppleServerApiClient)(env);
  const configuredVerifier = await (dependencies.createVerifier ?? createAppleNotificationVerifier)(env);
  if (!client || !configuredVerifier) {
    await deferCorrection(env.DB, row.inbox_id, "SERVER_API_NOT_CONFIGURED", now);
    return;
  }
  const expectedEnvironment = configuredVerifier.environment === Environment.PRODUCTION
    ? "Production"
    : "Sandbox";
  if (row.environment !== expectedEnvironment) {
    await deferCorrection(env.DB, row.inbox_id, "SERVER_API_ENVIRONMENT_MISMATCH", now);
    return;
  }

  try {
    const evidence = await loadCurrentEvidence(client, configuredVerifier.verifier, row);
    if (!evidence || evidence.environment !== expectedEnvironment) {
      await deferCorrection(env.DB, row.inbox_id, "SERVER_API_EVIDENCE_MISMATCH", now);
      return;
    }
    await applyCorrection(env.DB, row, evidence, now);
  } catch {
    await deferCorrection(env.DB, row.inbox_id, "SERVER_API_REQUEST_FAILED", now);
  }
}

type CorrectedEvidence = {
  status: "ACTIVE" | "EXPIRED" | "BILLING_RETRY" | "GRACE_PERIOD" | "REVOKED" | "LIFETIME";
  grantStatus: "active" | "expired" | "revoked";
  environment: "Production" | "Sandbox";
  transaction: JWSTransactionDecodedPayload;
  renewal: JWSRenewalInfoDecodedPayload | null;
};

async function loadCurrentEvidence(
  client: AppleServerApi,
  verifier: AppleNotificationVerifier,
  row: CorrectionRow,
): Promise<CorrectedEvidence | null> {
  let statuses: StatusResponse | null = null;
  try {
    statuses = await client.getAllSubscriptionStatuses(row.original_transaction_id);
  } catch {
    statuses = null;
  }
  if (statuses && statuses.environment !== row.environment) return null;
  const item = statuses?.data
    ?.flatMap((group) => group.lastTransactions ?? [])
    .find((candidate) => candidate.originalTransactionId === row.original_transaction_id);
  if (item?.signedTransactionInfo && item.signedRenewalInfo && item.status !== undefined) {
    const [transaction, renewal] = await Promise.all([
      verifier.verifyAndDecodeTransaction(item.signedTransactionInfo),
      verifier.verifyAndDecodeRenewalInfo(item.signedRenewalInfo),
    ]);
    if (!matchesChain(transaction, renewal, row)) return null;
    const mapped = mapSubscriptionStatus(item.status);
    return mapped ? { ...mapped, environment: row.environment, transaction, renewal } : null;
  }

  const response: TransactionInfoResponse = await client.getTransactionInfo(
    row.transaction_id ?? row.original_transaction_id,
  );
  if (!response.signedTransactionInfo) return null;
  const transaction = await verifier.verifyAndDecodeTransaction(response.signedTransactionInfo);
  if (!matchesChain(transaction, null, row) || transaction.type !== "Non-Consumable") return null;
  const revoked = Number.isFinite(transaction.revocationDate);
  return {
    status: revoked ? "REVOKED" : "LIFETIME",
    grantStatus: revoked ? "revoked" : "active",
    environment: row.environment,
    transaction,
    renewal: null,
  };
}

function matchesChain(
  transaction: JWSTransactionDecodedPayload,
  renewal: JWSRenewalInfoDecodedPayload | null,
  row: CorrectionRow,
): boolean {
  return transaction.originalTransactionId === row.original_transaction_id &&
    transaction.environment === row.environment &&
    (!renewal || renewal.originalTransactionId === row.original_transaction_id) &&
    (!renewal?.environment || renewal.environment === row.environment);
}

function mapSubscriptionStatus(status: number): Pick<CorrectedEvidence, "status" | "grantStatus"> | null {
  switch (status) {
    case APPLE_SUBSCRIPTION_STATUS.ACTIVE: return { status: "ACTIVE", grantStatus: "active" };
    case APPLE_SUBSCRIPTION_STATUS.EXPIRED: return { status: "EXPIRED", grantStatus: "expired" };
    case APPLE_SUBSCRIPTION_STATUS.BILLING_RETRY: return { status: "BILLING_RETRY", grantStatus: "expired" };
    case APPLE_SUBSCRIPTION_STATUS.BILLING_GRACE_PERIOD: return { status: "GRACE_PERIOD", grantStatus: "active" };
    case APPLE_SUBSCRIPTION_STATUS.REVOKED: return { status: "REVOKED", grantStatus: "revoked" };
    default: return null;
  }
}

async function applyCorrection(
  db: D1Database,
  row: CorrectionRow,
  evidence: CorrectedEvidence,
  now: Date,
): Promise<void> {
  const transaction = evidence.transaction;
  const renewal = evidence.renewal;
  const graceExpiresAt = iso(renewal?.gracePeriodExpiresDate);
  const expiresAt = evidence.status === "GRACE_PERIOD"
    ? graceExpiresAt
    : iso(transaction.expiresDate);
  const revokedAt = evidence.grantStatus === "revoked"
    ? iso(transaction.revocationDate) ?? now.toISOString()
    : null;
  const autoRenew = renewal?.autoRenewStatus === 1 ? 1 : 0;
  const correctionVersion = now.toISOString();

  const statements: D1PreparedStatement[] = [
    db.prepare(`
      UPDATE billing_purchase_chain SET
        product_id = COALESCE(?, product_id), next_product_id = ?, status = ?,
        auto_renew = ?, expires_at = CASE WHEN ? = 'LIFETIME' THEN NULL ELSE COALESCE(?, expires_at) END,
        grace_period_expires_at = ?, revoked_at = ?, state_effective_at = ?,
        correction_status = 'server_api_verified', updated_at = ?
      WHERE store = 'app_store' AND environment = ? AND original_transaction_id = ?
    `).bind(
      transaction.productId ?? renewal?.productId ?? null,
      renewal?.autoRenewProductId ?? null, evidence.status, autoRenew, evidence.status, expiresAt,
      graceExpiresAt, revokedAt, correctionVersion, correctionVersion,
      row.environment, row.original_transaction_id,
    ),
    db.prepare(`
      UPDATE billing_session_entitlement_grant SET
        status = ?, expires_at = ?, last_verified_at = ?, revoked_at = ?, updated_at = ?
      WHERE purchase_chain_id = (
        SELECT id FROM billing_purchase_chain
        WHERE store = 'app_store' AND environment = ? AND original_transaction_id = ?
      )
    `).bind(
      evidence.grantStatus, expiresAt, correctionVersion,
      evidence.grantStatus === "active" ? null : correctionVersion, correctionVersion,
      row.environment, row.original_transaction_id,
    ),
  ];
  if (row.notification_type === "REFUND_REVERSED") {
    statements.push(db.prepare(`
      UPDATE billing_transaction SET
        status = CASE WHEN ? = 'active' THEN 'purchased' ELSE status END,
        revoked_at = CASE WHEN ? = 'active' THEN NULL ELSE revoked_at END,
        refund_completed_at = CASE WHEN ? = 'active' THEN NULL ELSE refund_completed_at END,
        updated_at = ?
      WHERE purchase_chain_id = (
        SELECT id FROM billing_purchase_chain
        WHERE store = 'app_store' AND environment = ? AND original_transaction_id = ?
      ) AND transaction_id = ?
    `).bind(
      evidence.grantStatus, evidence.grantStatus, evidence.grantStatus,
      correctionVersion, row.environment, row.original_transaction_id,
      row.transaction_id ?? transaction.transactionId,
    ));
  }
  statements.push(
    db.prepare(`
      UPDATE apple_server_notification
      SET processing_status = 'processed', attempts = attempts + 1,
          last_error = NULL, processed_at = ? WHERE inbox_id = ?
    `).bind(correctionVersion, row.inbox_id),
    db.prepare(`
      UPDATE apple_notification_inbox
      SET processing_status = 'processed', processing_expires_at = NULL,
          last_error = NULL, processed_at = ? WHERE id = ?
    `).bind(correctionVersion, row.inbox_id),
  );
  const results = await db.batch(statements);
  if (results[0]?.meta.changes !== 1) throw new Error("purchase chain not found");
}

async function deferCorrection(
  db: D1Database,
  inboxId: string,
  error: string,
  now: Date,
): Promise<void> {
  await db.prepare(`
    UPDATE apple_notification_inbox
    SET processing_status = 'correction_required', processing_expires_at = ?, last_error = ?
    WHERE id = ?
  `).bind(new Date(now.getTime() + RETRY_DELAY_MS).toISOString(), error, inboxId).run();
}

function iso(value: number | undefined): string | null {
  return Number.isFinite(value) ? new Date(value!).toISOString() : null;
}
