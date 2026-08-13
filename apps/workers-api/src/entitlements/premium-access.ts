import type { Env } from "../env";

export const PREMIUM_ENTITLEMENT_ID = "performance_pro";
export const LOCAL_PREMIUM_STATE_HEADER = "X-Local-Premium-State";

export type PremiumAccess = "premium" | "free" | "sync_required";

type ActiveGrantRow = {
  id: string;
  purchase_chain_id: string;
  expires_at: string | null;
};

const SELECT_ACTIVE_SESSION_GRANT_SQL = `
SELECT grant_record.id, grant_record.purchase_chain_id, grant_record.expires_at
FROM billing_session_entitlement_grant AS grant_record
INNER JOIN billing_purchase_chain AS purchase_chain
  ON purchase_chain.id = grant_record.purchase_chain_id
WHERE grant_record.session_id = ?
  AND grant_record.entitlement_id = ?
  AND grant_record.status = 'active'
  AND grant_record.revoked_at IS NULL
  AND (grant_record.expires_at IS NULL OR grant_record.expires_at > ?)
  AND purchase_chain.environment = ?
  AND purchase_chain.status IN ('ACTIVE', 'TRIAL', 'GRACE_PERIOD', 'LIFETIME')
  AND purchase_chain.revoked_at IS NULL
  AND (purchase_chain.expires_at IS NULL OR purchase_chain.expires_at > ?)
LIMIT 1
`;

export async function hasActivePremiumGrant(
  env: Pick<Env, "DB" | "APP_ENVIRONMENT">,
  sessionId: string,
  now = new Date(),
): Promise<boolean> {
  const timestamp = now.toISOString();
  const environment = env.APP_ENVIRONMENT === "production" ? "Production" : "Sandbox";
  const grant = await env.DB.prepare(SELECT_ACTIVE_SESSION_GRANT_SQL)
    .bind(sessionId, PREMIUM_ENTITLEMENT_ID, timestamp, environment, timestamp)
    .first<ActiveGrantRow>();

  return grant !== null;
}

export async function resolvePremiumAccess(
  env: Pick<Env, "DB" | "APP_ENVIRONMENT">,
  sessionId: string,
  localPremiumState: string | undefined,
  now = new Date(),
): Promise<PremiumAccess> {
  if (await hasActivePremiumGrant(env, sessionId, now)) return "premium";
  return localPremiumState?.toLowerCase() === "verified" ? "sync_required" : "free";
}
