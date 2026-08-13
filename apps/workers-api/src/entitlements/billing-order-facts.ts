import type { JWSTransactionDecodedPayload } from "./apple-signed-data";

export type BillingBusinessStatus =
  | "trial"
  | "initial_purchase"
  | "trial_conversion"
  | "renewal"
  | "grace_recovery"
  | "billing_recovery";

export function businessStatusForAppleTransaction(
  notificationType: string,
  previousChainStatus: string,
  transaction: Pick<JWSTransactionDecodedPayload, "transactionReason" | "offerDiscountType">,
): BillingBusinessStatus {
  if (transaction.offerDiscountType === "FREE_TRIAL") return "trial";
  if (notificationType === "DID_RENEW" && previousChainStatus === "GRACE_PERIOD") {
    return "grace_recovery";
  }
  if (notificationType === "DID_RENEW" && previousChainStatus === "BILLING_RETRY") {
    return "billing_recovery";
  }
  if (transaction.transactionReason === "RENEWAL") return "renewal";
  return "initial_purchase";
}

export function billingOrderFactStatements(
  db: D1Database,
  purchaseChainId: string,
  environment: "Production" | "Sandbox",
): D1PreparedStatement[] {
  return [
    db.prepare(`
      UPDATE billing_transaction AS current_transaction
      SET business_status = 'renewal'
      WHERE purchase_chain_id = ? AND environment = ?
        AND business_status = 'initial_purchase'
        AND EXISTS (
          SELECT 1 FROM billing_transaction AS earlier_paid_transaction
          WHERE earlier_paid_transaction.purchase_chain_id = current_transaction.purchase_chain_id
            AND earlier_paid_transaction.environment = current_transaction.environment
            AND earlier_paid_transaction.business_status IS NOT NULL
            AND earlier_paid_transaction.business_status != 'trial'
            AND (
              earlier_paid_transaction.purchase_at < current_transaction.purchase_at
              OR (earlier_paid_transaction.purchase_at = current_transaction.purchase_at
                AND earlier_paid_transaction.transaction_id < current_transaction.transaction_id)
            )
        )
    `).bind(purchaseChainId, environment),
    db.prepare(`
      UPDATE billing_transaction AS current_transaction
      SET business_status = CASE WHEN EXISTS (
        SELECT 1 FROM billing_transaction AS trial_transaction
        WHERE trial_transaction.purchase_chain_id = current_transaction.purchase_chain_id
          AND trial_transaction.environment = current_transaction.environment
          AND trial_transaction.business_status = 'trial'
          AND (
            trial_transaction.purchase_at < current_transaction.purchase_at
            OR (trial_transaction.purchase_at = current_transaction.purchase_at
              AND trial_transaction.transaction_id < current_transaction.transaction_id)
          )
      ) AND NOT EXISTS (
        SELECT 1 FROM billing_transaction AS earlier_paid_transaction
        WHERE earlier_paid_transaction.purchase_chain_id = current_transaction.purchase_chain_id
          AND earlier_paid_transaction.environment = current_transaction.environment
          AND earlier_paid_transaction.business_status IS NOT NULL
          AND earlier_paid_transaction.business_status != 'trial'
          AND (
            earlier_paid_transaction.purchase_at < current_transaction.purchase_at
            OR (earlier_paid_transaction.purchase_at = current_transaction.purchase_at
              AND earlier_paid_transaction.transaction_id < current_transaction.transaction_id)
          )
      ) THEN 'trial_conversion' ELSE 'renewal' END
      WHERE purchase_chain_id = ? AND environment = ?
        AND business_status IN ('trial_conversion', 'renewal')
    `).bind(purchaseChainId, environment),
    db.prepare(`
      UPDATE billing_transaction AS current_transaction
      SET charge_count = CASE
        WHEN current_transaction.business_status = 'trial' THEN 0
        WHEN current_transaction.business_status IS NULL THEN NULL
        ELSE (
          SELECT COUNT(*) FROM billing_transaction AS counted_transaction
          WHERE counted_transaction.purchase_chain_id = current_transaction.purchase_chain_id
            AND counted_transaction.environment = current_transaction.environment
            AND counted_transaction.business_status IS NOT NULL
            AND counted_transaction.business_status != 'trial'
            AND (
              counted_transaction.purchase_at < current_transaction.purchase_at
              OR (counted_transaction.purchase_at = current_transaction.purchase_at
                AND counted_transaction.transaction_id <= current_transaction.transaction_id)
            )
        )
      END
      WHERE purchase_chain_id = ? AND environment = ?
    `).bind(purchaseChainId, environment),
  ];
}
