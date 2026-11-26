import { Hono } from "hono";
import { verifyAndroidInstallation } from "../auth/android-integrity";
import type { Env } from "../env";
import { authenticateOwner, type AuthenticatedOwner } from "../owner-auth";
import { isPageType, isRecord } from "../subscription-config/model";
import { googlePlayAccess, googlePlayScope } from "./access";
import { accountRef, syncPurchase, type PlayPlan } from "./purchases";
import { playDigest, PlayError, tokenValid } from "./publisher";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const playRoutes = new Hono<{ Bindings: Env; Variables: { owner: AuthenticatedOwner } }>();
const failure = (code: string) => ({ success: false as const, error: { code } });
const guard: import("hono").MiddlewareHandler<{ Bindings: Env; Variables: { owner: AuthenticatedOwner } }> = async (c, next) => {
  const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
  if (auth.status !== "ok") return c.json(failure(auth.status === "unauthorized" ? "UNAUTHORIZED" : "INTERNAL_ERROR"), auth.status === "unauthorized" ? 401 : 500);
  if (auth.owner.platform !== "android") return c.json(failure("GOOGLE_PLAY_PLATFORM_UNAVAILABLE"), 403);
  c.set("owner", auth.owner);
  await next();
};
playRoutes.use("/entitlements/google/*", guard);
playRoutes.use("/google-play/catalog", guard);
playRoutes.onError((error, c) => {
  if (error instanceof PlayError) return c.json(failure(error.code), error.status);
  console.error("Google Play request failed", c.req.path);
  return c.json(failure("GOOGLE_PLAY_UNAVAILABLE"), 503);
});
playRoutes.get("/entitlements/google/play", async c => {
  const owner = c.get("owner"), scope = googlePlayScope(c.env);
  const { cohort: _cohort, ...policy } = await googlePlayAccess(c.env, owner);
  return c.json({ success: true, data: { ...policy, package_name: c.env.GOOGLE_PLAY_PACKAGE_NAME ?? null,
    installation_binding: scope ? owner.session_id : null,
    account_ref: policy.can_purchase && scope ? await accountRef(c.env, scope, owner.data_space_id) : null } });
});
playRoutes.post("/entitlements/google/installation", async c => {
  const owner = c.get("owner");
  const body: unknown = await c.req.json().catch(() => null);
  if (!isRecord(body) || typeof body.device_id !== "string" || typeof body.request_nonce !== "string") return c.json(failure("VALIDATION_ERROR"), 422);
  const result = await verifyAndroidInstallation(c.env, body.integrity_token, { deviceId: body.device_id, requestNonce: body.request_nonce, sessionId: owner.session_id });
  if (typeof result === "string" || !result.build || result.build.package_name !== c.env.GOOGLE_PLAY_PACKAGE_NAME?.trim()) {
    return c.json(failure("GOOGLE_PLAY_BUILD_UNVERIFIED"), result === "unavailable" ? 503 : 403);
  }
  const build = result.build;
  await c.env.DB.prepare(`INSERT INTO google_play_session_build(session_id,package_name,certificate_digest,version_code,verified_at)
    VALUES(?,?,?,?,?) ON CONFLICT(session_id) DO UPDATE SET certificate_digest=excluded.certificate_digest,
    version_code=excluded.version_code,verified_at=excluded.verified_at WHERE google_play_session_build.package_name=excluded.package_name
    AND google_play_session_build.version_code <= excluded.version_code AND google_play_session_build.verified_at <= excluded.verified_at`)
    .bind(owner.session_id, build.package_name, build.certificate_digest, build.version_code, build.verified_at).run();
  return c.json({ success: true });
});
playRoutes.get("/google-play/catalog", async c => {
  const placement = c.req.query("placement") ?? "page";
  if (!isPageType(placement)) return c.json(failure("VALIDATION_ERROR"), 422);
  const scope = googlePlayScope(c.env), owner = c.get("owner");
  const policy = await googlePlayAccess(c.env, owner);
  if (!scope || policy.access_policy !== "metered") return c.json({ success: true, data: { status: "not_applicable", config: null, products: [] } });
  const [config, products] = await Promise.all([
    c.env.DB.prepare("SELECT published,revision FROM google_play_display WHERE scope=? AND placement=?").bind(scope, placement)
      .first<{published: unknown; revision: number}>(),
    c.env.DB.prepare("SELECT product_id,base_plan_id,offer_id FROM google_play_product WHERE scope=? ORDER BY product_id,base_plan_id,offer_id")
      .bind(scope).all<PlayPlan>(),
  ]);
  return c.json({ success: true, data: { status: config?.published ? "configured" : "unconfigured", revision: config?.revision ?? 0,
    config: config?.published ?? null, products: products.results } });
});
playRoutes.post("/entitlements/google/verify", async c => {
  const owner = c.get("owner"), scope = googlePlayScope(c.env);
  if (owner.owner_type !== "user") return c.json(failure("GOOGLE_PLAY_LOGIN_REQUIRED"), 403);
  if (!scope) throw new PlayError("GOOGLE_PLAY_UNAVAILABLE");
  const body: unknown = await c.req.json().catch(() => null), id = c.req.header("Idempotency-Key");
  if (!id || !uuid.test(id) || !isRecord(body) || !tokenValid(body.purchase_token)) return c.json(failure("VALIDATION_ERROR"), 422);
  const hash = await playDigest(c.env, scope, "token", body.purchase_token);
  const prior = await c.env.DB.prepare(`INSERT INTO google_play_verify_request(scope,owner_id,request_id,token_hash,created_at)
    VALUES(?,?,?,?,?) ON CONFLICT(scope,owner_id,request_id) DO UPDATE SET request_id=excluded.request_id RETURNING token_hash,result`)
    .bind(scope, owner.data_space_id, id, hash, new Date().toISOString()).first<{token_hash: string; result: Record<string, unknown> | null}>();
  if (!prior || hash !== prior.token_hash) return c.json(failure("IDEMPOTENCY_CONFLICT"), 409);
  if (prior.result) return c.json(prior.result);
  const response = { success: true, data: await syncPurchase(c.env, scope, body.purchase_token, owner.data_space_id) };
  const saved = await c.env.DB.prepare(`UPDATE google_play_verify_request SET result=COALESCE(result,?::jsonb),status_code=200
    WHERE scope=? AND owner_id=? AND request_id=? RETURNING result`)
    .bind(JSON.stringify(response), scope, owner.data_space_id, id).first<{ result: Record<string, unknown> }>();
  return c.json(saved!.result);
});
