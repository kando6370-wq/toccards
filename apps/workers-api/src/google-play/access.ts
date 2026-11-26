import type { Env } from "../env";
import type { AuthenticatedOwner } from "../owner-auth";

export function googlePlayScope(env: Env): string | null {
  const name = env.GOOGLE_PLAY_PACKAGE_NAME?.trim();
  if (!name || !/^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+$/.test(name) ||
      (env.APP_ENVIRONMENT !== "production" && env.APP_ENVIRONMENT !== "development")) return null;
  return `${env.APP_ENVIRONMENT}:google_play:${name}`;
}

export type PlayAccess = {
  access_policy: "free_launch" | "legacy_free" | "metered";
  premium: boolean;
  verified_build: number | null;
  sales_available: boolean;
  can_purchase: boolean;
  expires_at: string | null;
  auto_renew: boolean | null;
  product_id: string | null;
  cohort: string | null;
};
const freeLaunch: PlayAccess = {
  verified_build: null, sales_available: false, access_policy: "free_launch", premium: false, can_purchase: false, expires_at: null,
  auto_renew: null, product_id: null, cohort: null,
};

export async function googlePlayAccess(env: Env, owner: AuthenticatedOwner, now = new Date()): Promise<PlayAccess> {
  if (owner.platform !== "android") throw new Error("Android session required");
  const scope = googlePlayScope(env);
  if (!scope) return freeLaunch;
  const row = await env.DB.prepare(`SELECT r.minimum_build, r.sales_enabled, r.metering_enabled,
      b.version_code, EXISTS (SELECT 1 FROM google_play_legacy_space l WHERE l.scope = r.scope AND
        ((l.owner_type = ? AND l.owner_id = ?) OR (l.owner_type = 'anonymous' AND ? = 'user' AND EXISTS
          (SELECT 1 FROM anonymous_account a WHERE a.id = l.owner_id AND a.platform = 'android' AND a.upgraded_user_id = ?)))) AS legacy,
      g.expires_at, g.auto_renew, g.product_id
    FROM (SELECT ?::text AS scope) config LEFT JOIN google_play_rollout r ON r.scope = config.scope
    LEFT JOIN google_play_session_build b ON b.session_id = ? AND b.package_name = ?
    LEFT JOIN LATERAL (SELECT p.expires_at, p.auto_renew, p.product_id FROM google_play_purchase p
      WHERE p.scope = config.scope AND ? = 'user' AND p.owner_id = ? AND p.granted AND NOT p.superseded AND p.expires_at > ?
        AND (p.store_kind = 'live' OR (p.store_kind = 'test' AND EXISTS
          (SELECT 1 FROM google_play_test_space t WHERE t.scope = p.scope AND t.owner_id = p.owner_id)))
      ORDER BY p.expires_at DESC, p.token_hash LIMIT 1) g ON true`)
    .bind(owner.owner_type, owner.data_space_id, owner.owner_type, owner.data_space_id, scope, owner.session_id,
      env.GOOGLE_PLAY_PACKAGE_NAME!.trim(), owner.owner_type, owner.data_space_id, now.toISOString())
    .first<{minimum_build: number | null; version_code: number | null; sales_enabled: boolean; metering_enabled: boolean;
      legacy: boolean; expires_at: string | null; auto_renew: boolean | null; product_id: string | null}>();
  if (!row) throw new Error("Unable to read Android access policy");
  const metered = row.metering_enabled && !row.legacy && row.minimum_build !== null &&
    row.version_code !== null && row.version_code >= row.minimum_build;
  return {
    access_policy: row.legacy ? "legacy_free" : metered ? "metered" : "free_launch",
    verified_build: row.version_code, sales_available: Boolean(metered && row.sales_enabled && !row.expires_at),
    can_purchase: Boolean(metered && !row.expires_at && row.sales_enabled && owner.owner_type === "user"),
    premium: row.expires_at !== null, expires_at: row.expires_at, auto_renew: row.auto_renew,
    product_id: row.product_id, cohort: metered ? scope : null,
  };
}
