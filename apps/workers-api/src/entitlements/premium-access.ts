import type { Env } from "../env";
import {
  appleDatabaseEnvironments,
  configuredProductIds,
} from "./apple-signed-data";

export const PREMIUM_ENTITLEMENT_ID = "performance_pro";
export const LOCAL_PREMIUM_STATE_HEADER = "X-Local-Premium-State";

export type PremiumAccess = "premium" | "free" | "sync_required";

type ActiveGrantRow = {
  id: string;
  purchase_chain_id: string;
  expires_at: string | null;
  environment: "Production" | "Sandbox";
  product_id: string;
};

const SELECT_ACTIVE_SESSION_GRANT_SQL = `
SELECT grant_record.id, grant_record.purchase_chain_id, grant_record.expires_at,
       purchase_chain.environment, purchase_chain.product_id
FROM billing_session_entitlement_grant AS grant_record
INNER JOIN billing_purchase_chain AS purchase_chain
  ON purchase_chain.id = grant_record.purchase_chain_id
WHERE grant_record.session_id = ?
  AND grant_record.entitlement_id = ?
  AND grant_record.status = 'active'
  AND grant_record.revoked_at IS NULL
  AND (grant_record.expires_at IS NULL OR grant_record.expires_at > ?)
  AND purchase_chain.status IN ('ACTIVE', 'TRIAL', 'GRACE_PERIOD', 'LIFETIME')
  AND purchase_chain.revoked_at IS NULL
  AND (purchase_chain.expires_at IS NULL OR purchase_chain.expires_at > ?)
`;

export async function hasActivePremiumGrant(
  env: Pick<Env, "DB" | "APP_ENVIRONMENT" | "APPLE_IAP_PRODUCT_IDS">,
  sessionId: string,
  now = new Date(),
): Promise<boolean> {
  const timestamp = now.toISOString();
  const products = configuredProductIds(env.APPLE_IAP_PRODUCT_IDS);
  if (!products) return false;
  const environments = new Set(appleDatabaseEnvironments(env));
  const result = await env.DB.prepare(SELECT_ACTIVE_SESSION_GRANT_SQL)
    .bind(
      sessionId,
      PREMIUM_ENTITLEMENT_ID,
      timestamp,
      timestamp,
    )
    .all<ActiveGrantRow>();

  return (result.results ?? []).some((grant) =>
    products.has(grant.product_id) && environments.has(grant.environment)
  );
}

export async function resolvePremiumAccess(
  env: Pick<Env, "DB" | "APP_ENVIRONMENT" | "APPLE_IAP_PRODUCT_IDS">,
  sessionId: string,
  localPremiumState: string | undefined,
  now = new Date(),
): Promise<PremiumAccess> {
  if (await hasActivePremiumGrant(env, sessionId, now)) return "premium";
  return localPremiumState?.toLowerCase() === "verified" ? "sync_required" : "free";
}
