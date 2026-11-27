import { Hono } from "hono";
import { verifyWithJwks } from "hono/jwt";
import type { Env } from "../env";
import { getBearerToken } from "../auth/http-auth";
import { isRecord } from "../subscription-config/model";
import { googlePlayScope } from "./access";
import { openToken, playDigest, PlayError, sealToken, tokenValid } from "./publisher";
import { syncPurchase } from "./purchases";
import { scanVoidedPage, reconcileOrderId } from "./reconcile";
import { syncOrder } from "./orders";

// Only these public RTDN fields are kept for support. Tokens and account identifiers stay out of the snapshot.
const variants = {
  subscriptionNotification: ["subscription", "notificationType", "subscriptionId"],
  oneTimeProductNotification: ["one_time", "notificationType", "sku"],
  voidedPurchaseNotification: ["voided", "refundType", "productType", "orderId"],
  pendingRefundReviewNotification: ["refund_review", "refundReason", "orderId"],
  testNotification: ["test"],
} as const;

function describeNotification(data: Record<string, unknown>) {
  const present = Object.entries(variants).filter(([key]) => data[key] !== undefined);
  if (present.length > 1) return null;
  const payload: Record<string, unknown> = { packageName: data.packageName, eventTimeMillis: data.eventTimeMillis };
  const version = (value: unknown) => typeof value === "string" && /^\d{1,3}(?:\.\d{1,3}){0,2}$/.test(value) ? value : undefined;
  payload.version = version(data.version);
  if (!present.length) return { kind: "unknown", payload };
  const [key, [family, ...fields]] = present[0];
  const event = data[key];
  if (!isRecord(event)) return { kind: "unknown", payload };
  const safe: Record<string, unknown> = { version: version(event.version) };
  for (const field of fields) {
    const value = event[field];
    if (field === "orderId" || field === "subscriptionId" || field === "sku") {
      if (typeof value === "string" && value.length < 256) safe[field] = value;
    } else if (Number.isSafeInteger(value)) safe[field] = value;
  }
  payload[key] = safe;
  const type = safe.notificationType ?? safe.refundType;
  return { kind: type === undefined ? family : family + ":" + type, payload };
}

export const notificationRoutes = new Hono<{ Bindings: Env }>();
notificationRoutes.post("/google-play/notifications", async c => {
  const env = c.env, scope = googlePlayScope(env), topic = env.GOOGLE_PLAY_TOPIC;
  if (!scope || !topic || !env.GOOGLE_PLAY_PUSH_AUDIENCE || !env.GOOGLE_PLAY_PUSH_EMAIL || !env.GOOGLE_PLAY_PUSH_SUBSCRIPTION) return c.body(null, 503);
  const token = getBearerToken(c.req.header("Authorization"));
  if (!token || token.length > 8192) return c.body(null, 401);
  try {
    const claims = await verifyWithJwks(token, { jwks_uri: "https://www.googleapis.com/oauth2/v3/certs", allowedAlgorithms: ["RS256"],
      verification: { iss: /^(?:https:\/\/)?accounts\.google\.com$/, aud: env.GOOGLE_PLAY_PUSH_AUDIENCE } }, { signal: AbortSignal.timeout(8000) });
    if (claims.email !== env.GOOGLE_PLAY_PUSH_EMAIL || claims.email_verified !== true || typeof claims.exp !== "number" || typeof claims.iat !== "number") return c.body(null, 401);
  } catch { return c.body(null, 401); }
  const envelope: unknown = await c.req.json().catch(() => null);
  if (!isRecord(envelope) || envelope.subscription !== env.GOOGLE_PLAY_PUSH_SUBSCRIPTION || !isRecord(envelope.message)) return c.body(null, 422);
  const msg = envelope.message;
  if (typeof msg.messageId !== "string" || !/^[\w-]{1,128}$/.test(msg.messageId) || typeof msg.data !== "string" || msg.data.length > 65536) return c.body(null, 422);
  let data: unknown;
  try { data = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(msg.data), ch => ch.charCodeAt(0)))); } catch { return c.body(null, 422); }
  if (!isRecord(data) || data.packageName !== env.GOOGLE_PLAY_PACKAGE_NAME || typeof data.eventTimeMillis !== "string" || !/^\d{1,13}$/.test(data.eventTimeMillis)) return c.body(null, 422);
  const sub = data.subscriptionNotification, voided = data.voidedPurchaseNotification, review = data.pendingRefundReviewNotification;
  const description = describeNotification(data);
  if (!description) return c.body(null,422);
  const {kind, payload} = description;
  const types = [1,2,3,4,5,6,7,8,9,10,11,12,13,17,18,19,20,21,22];
  const processable = (isRecord(voided) && voided.productType === 1) || (isRecord(sub) && typeof sub.notificationType === "number" && types.includes(sub.notificationType));
  const purchase = isRecord(sub) ? sub.purchaseToken : isRecord(voided) ? voided.purchaseToken : null;
  if (processable && !tokenValid(purchase)) return c.body(null, 422);
  const source = isRecord(voided) ? voided : isRecord(review) ? review : null;
  const order = typeof source?.orderId === "string" && source.orderId.length < 256 ? source.orderId : null;
  const now = new Date().toISOString();
  await env.DB.prepare(`INSERT INTO google_play_inbox(scope,topic,message_id,kind,event_at,received_at,token_hash,token_encrypted,order_id,state,next_check_at,redacted_payload)
    VALUES(?,?,?,?,?,?,?,?,?,?,?,?::jsonb) ON CONFLICT(scope,topic,message_id) DO NOTHING`)
    .bind(scope, topic, msg.messageId, kind, new Date(Number(data.eventTimeMillis)).toISOString(), now,
      tokenValid(purchase) ? await playDigest(env, scope, "token", purchase) : null,
      tokenValid(purchase) ? await sealToken(env, scope, purchase) : null, order,
      kind === "test" ? "received_test" : processable ? "pending" : "quarantined", processable ? now : null, JSON.stringify(payload)).run();
  return c.body(null, 204);
});

export async function processPlayInbox(env: Env, scope: string, now: Date) {
  const db = env.DB, stamp = now.toISOString(), lease = new Date(now.getTime() + 120_000).toISOString();
  const msg = await db.prepare(`UPDATE google_play_inbox SET state='processing', attempts=attempts+1,next_check_at=?
    WHERE (scope,topic,message_id) IN (SELECT scope,topic,message_id FROM google_play_inbox WHERE scope=? AND next_check_at<=?
      ORDER BY next_check_at LIMIT 1 FOR UPDATE SKIP LOCKED) RETURNING topic,message_id,token_hash,token_encrypted,order_id,attempts`)
    .bind(lease, scope, stamp).first<{topic: string; message_id: string; token_hash: string; token_encrypted: string; order_id: string|null; attempts: number}>();
  if (!msg) return;
  let error: string | null = null;
  try {
    // An old/refunded period can still be reconciled after its subscription token expires.
    if (msg.order_id) await reconcileOrderId(env, scope, msg.order_id);
    try { await syncPurchase(env, scope, await openToken(env, scope, msg.token_encrypted)); }
    catch (e) { if (!msg.order_id || !(e instanceof PlayError) || e.status !== 404) throw e; }
  } catch (cause) { error = cause instanceof PlayError ? cause.code : "GOOGLE_PLAY_SYNC_UNAVAILABLE"; }
  await db.prepare(`UPDATE google_play_inbox SET state=?,last_error=?,next_check_at=? WHERE scope=? AND topic=? AND message_id=? AND next_check_at=?`)
    .bind(error ? "failed" : "processed", error, error && msg.attempts < 12 ? new Date(now.getTime()+Math.min(3600000,15000 * 2**msg.attempts)).toISOString() : null,
      scope, msg.topic, msg.message_id, lease).run();
}

export async function runGooglePlayTasks(env: Env, now = new Date()) {
  const scope = googlePlayScope(env);
  if (!scope || !env.GOOGLE_PLAY_PUBLISHER_EMAIL) return;
  const limit = Date.now() + 24_000;
  const db = env.DB;
  try { await scanVoidedPage(env,scope,now); }
  catch (error) { console.warn("Google Play voided purchases", error instanceof PlayError ? error.code : "GOOGLE_PLAY_VOIDED_UNAVAILABLE"); }
  for (let i = 0; i < 3 && Date.now() < limit; i++) await processPlayInbox(env, scope, now);
  const due = await db.prepare(`SELECT token_encrypted FROM google_play_purchase WHERE scope=? AND next_check_at<=? AND
    (lease_until IS NULL OR lease_until<=?) ORDER BY next_check_at LIMIT 5`).bind(scope, now.toISOString(), now.toISOString()).all<{token_encrypted: string}>();
  for (const p of due.results) {
    if (Date.now() >= limit) break;
    try { await syncPurchase(env, scope, await openToken(env, scope, p.token_encrypted)); }
    catch (error) { console.warn("Google Play reconciliation", error instanceof PlayError ? error.code : "GOOGLE_PLAY_SYNC_UNAVAILABLE"); }
  }
  const orders = await db.prepare(`SELECT order_id,store_kind FROM google_play_order WHERE scope=? AND (next_check_at IS NULL OR next_check_at<=?)
    ORDER BY next_check_at NULLS FIRST,order_id LIMIT 5`).bind(scope, now.toISOString()).all<{order_id: string; store_kind: string}>();
  for (const row of orders.results) {
    if (Date.now() >= limit) break;
    let delay = 86400_000;
    try { await syncOrder(env, scope, row.store_kind, row.order_id); }
    catch (error) { delay = 15 * 60_000; console.warn("Google Play order reconciliation", error instanceof PlayError ? error.code : "GOOGLE_PLAY_ORDER_UNAVAILABLE"); }
    await db.prepare("UPDATE google_play_order SET next_check_at=? WHERE scope=? AND store_kind=? AND order_id=?")
      .bind(new Date(now.getTime()+delay).toISOString(), scope, row.store_kind, row.order_id).run();
  }
}
