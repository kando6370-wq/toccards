import type { Env } from "../env";
import { isRecord } from "../subscription-config/model";
import { playDigest, PlayError, publisher, sealToken, tokenValid } from "./publisher";

export type PlayPlan = { product_id: string; base_plan_id: string; offer_id: string };
const grantingStates = new Set(["ACTIVE", "IN_GRACE_PERIOD", "CANCELED"]);
const states = new Set([...grantingStates, "ON_HOLD", "PAUSED", "EXPIRED", "PENDING", "PENDING_PURCHASE_CANCELED"]);
export function utc(value: unknown) {
  if (typeof value !== "string" || !/^\d{4}-\d\d-\d\dT.*(?:Z|[+-]\d\d:\d\d)$/.test(value) || !Number.isFinite(Date.parse(value))) return null;
  return new Date(value).toISOString();
}
function record(value: unknown) { return isRecord(value) ? value : {}; }

export function verifiedPurchase(raw: unknown, plans: PlayPlan[], now: Date) {
  const value = record(raw);
  const state = typeof value.subscriptionState === "string" ? value.subscriptionState.replace(/^SUBSCRIPTION_STATE_/, "") : "";
  if (!states.has(state) || !Array.isArray(value.lineItems) || value.kind !== "androidpublisher#subscriptionPurchaseV2" ||
      (value.testPurchase !== undefined && !isRecord(value.testPurchase))) throw new PlayError("GOOGLE_PLAY_UNKNOWN_STATE");
  const items = value.lineItems.flatMap((input: unknown) => {
    const item = record(input), offer = record(item.offerDetails), renewal = record(item.autoRenewingPlan);
    if (!isRecord(item.autoRenewingPlan) || renewal.installmentDetails) return [];
    const plan = plans.find(p => p.product_id === item.productId && p.base_plan_id === offer.basePlanId && p.offer_id === (offer.offerId ?? ""));
    if (!plan) return [];
    const expires = utc(item.expiryTime);
    return [{ ...plan, expires, renew: renewal.autoRenewEnabled === true,
      orderId: typeof item.latestSuccessfulOrderId === "string" ? item.latestSuccessfulOrderId : null }];
  }).sort((a, b) => (b.expires ?? "").localeCompare(a.expires ?? ""));
  const item = items[0];
  if (!item) throw new PlayError("GOOGLE_PLAY_PLAN_NOT_APPROVED", 422);
  if (!item.expires && grantingStates.has(state)) throw new PlayError("GOOGLE_PLAY_UNKNOWN_STATE");
  const previous = record(value.outOfAppPurchaseContext);
  const accountRefs = [record(value.externalAccountIdentifiers).obfuscatedExternalAccountId,
    record(previous.expiredExternalAccountIdentifiers).obfuscatedExternalAccountId].filter((v): v is string => typeof v === "string" && v.length > 0);
  const predecessor = value.linkedPurchaseToken ?? previous.expiredPurchaseToken;
  const ack = value.acknowledgementState;
  if (ack !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" && ack !== "ACKNOWLEDGEMENT_STATE_PENDING") throw new PlayError("GOOGLE_PLAY_UNKNOWN_STATE");
  return { ...item, state, accountRefs, predecessor: tokenValid(predecessor) ? predecessor : null,
    granted: grantingStates.has(state) && item.expires !== null && item.expires > now.toISOString(),
    ack, store: value.testPurchase === undefined ? "live" : "test", country: typeof value.regionCode === "string" ? value.regionCode : null,
    orderIds: [...new Set(items.flatMap(i => i.orderId ? [i.orderId] : []))] };
}

export async function accountRef(env: Env, scope: string, ownerId: string) {
  const candidate = await playDigest(env, scope, "account", ownerId);
  const row = await env.DB.prepare(`INSERT INTO google_play_account(scope,owner_id,account_ref)
    VALUES(?,?,?) ON CONFLICT(scope,owner_id) DO UPDATE SET owner_id = excluded.owner_id RETURNING account_ref`)
    .bind(scope, ownerId, candidate).first<{account_ref: string}>();
  if (!row) throw new PlayError("GOOGLE_PLAY_UNAVAILABLE");
  return row.account_ref;
}

export async function syncPurchase(env: Env, scope: string, token: string, expectedOwner?: string, now = new Date()) {
  const hash = await playDigest(env, scope, "token", token);
  const lease = crypto.randomUUID();
  const stamp = now.toISOString();
  const leaseUntil = new Date(now.getTime() + 90_000).toISOString();
  const db = env.DB;
  const held = await db.prepare(`INSERT INTO google_play_purchase(scope,token_hash,token_encrypted,chain_id,lease_id,lease_until,next_check_at)
    VALUES(?,?,?,?,?,?,?) ON CONFLICT(scope,token_hash) DO UPDATE SET lease_id=excluded.lease_id,lease_until=excluded.lease_until
    WHERE google_play_purchase.lease_until IS NULL OR google_play_purchase.lease_until <= ?
    RETURNING owner_id,chain_id,store_kind,attempts,superseded`)
    .bind(scope, hash, await sealToken(env, scope, token), hash, lease, leaseUntil, leaseUntil, stamp)
    .first<{owner_id: string | null; chain_id: string; store_kind: string | null; attempts: number; superseded: boolean}>();
  if (!held) throw new PlayError("GOOGLE_PLAY_SYNC_PENDING", 409);
  try {
    if (expectedOwner && held.owner_id && held.owner_id !== expectedOwner) throw new PlayError("GOOGLE_PLAY_OWNER_CONFLICT", 403);
    const plans = await db.prepare("SELECT product_id,base_plan_id,offer_id FROM google_play_product WHERE scope = ?")
      .bind(scope).all<PlayPlan>();
    const purchase = verifiedPurchase(await publisher(env, `purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`), plans.results, now);
    const previousHash = purchase.predecessor ? await playDigest(env, scope, "token", purchase.predecessor) : null;
    const predecessor = previousHash && previousHash !== hash ? await db.prepare(`SELECT owner_id,chain_id,store_kind FROM google_play_purchase
      WHERE scope=? AND token_hash=?`).bind(scope, previousHash).first<typeof held>() : null;
    const owners = new Set([held.owner_id, predecessor?.owner_id].filter((v): v is string => Boolean(v)));
    for (const ref of new Set(purchase.accountRefs)) {
      const binding = await db.prepare("SELECT owner_id FROM google_play_account WHERE scope=? AND account_ref=?")
        .bind(scope, ref).first<{owner_id: string}>();
      if (!binding) throw new PlayError("GOOGLE_PLAY_UNCLAIMED", 409);
      owners.add(binding.owner_id);
    }
    const [ownerId] = owners;
    if (!ownerId) throw new PlayError("GOOGLE_PLAY_UNCLAIMED", 409);
    if (owners.size !== 1 || (expectedOwner && expectedOwner !== ownerId) ||
        [held.store_kind, predecessor?.store_kind].some(k => k && k !== purchase.store)) throw new PlayError("GOOGLE_PLAY_OWNER_CONFLICT", 403);
    const eligibleTest = purchase.store === "live" || Boolean(await db.prepare("SELECT 1 FROM google_play_test_space WHERE scope=? AND owner_id=?")
      .bind(scope, ownerId).first());
    const liveOwner = await db.prepare("SELECT 1 FROM platform_account WHERE id=? AND platform='android' AND status='active'").bind(ownerId).first();
    const deliver = purchase.granted && !held.superseded && Boolean(liveOwner) && eligibleTest;
    const expiryMs = purchase.expires ? Date.parse(purchase.expires) : 0;
    const checkAt = new Date(Math.min(now.getTime() + (purchase.state === "PENDING" ? 60_000 : 6 * 3600_000),
      expiryMs > now.getTime() ? expiryMs : Infinity)).toISOString();
    const needsAck = deliver && purchase.ack === "ACKNOWLEDGEMENT_STATE_PENDING";
    const updates = [db.prepare(`UPDATE google_play_purchase SET owner_id=?, chain_id=?, previous_hash=?, store_kind=?,state=?,
      product_id=?,base_plan_id=?,offer_id=?,expires_at=?,auto_renew=?,granted=(? AND NOT superseded),acknowledgement=?,latest_order_id=?,country=?,
      checked_at=?,next_check_at=?,last_error=?,attempts=0 WHERE scope=? AND token_hash=? AND lease_id=? AND (owner_id IS NULL OR owner_id=?) RETURNING granted`)
      .bind(ownerId, predecessor?.chain_id ?? previousHash ?? held.chain_id, previousHash, purchase.store, purchase.state, purchase.product_id, purchase.base_plan_id,
        purchase.offer_id, purchase.expires, purchase.renew, deliver, purchase.ack, purchase.orderId, purchase.country, stamp,
        purchase.state === "EXPIRED" || purchase.state === "PENDING_PURCHASE_CANCELED" ? null : needsAck ? stamp : checkAt,
        eligibleTest ? (liveOwner ? null : "OWNER_DELETED") : "TEST_SPACE_NOT_APPROVED", scope, hash, lease, ownerId)];
    // Save all known order IDs before a later renewal changes the latest successful order.
    for (const id of purchase.orderIds) updates.push(db.prepare(`INSERT INTO google_play_order(scope,store_kind,order_id,token_hash,owner_id,product_id,base_plan_id,country)
      SELECT scope,store_kind,?,token_hash,owner_id,product_id,base_plan_id,country FROM google_play_purchase WHERE scope=? AND token_hash=? AND lease_id=?
      ON CONFLICT(scope,store_kind,order_id) DO NOTHING`).bind(id, scope, hash, lease));
    if (previousHash && previousHash !== hash && purchase.predecessor && deliver) {
      // Replacement can arrive before its predecessor. Persist the link before the old token can be claimed.
      updates.push(db.prepare(`SELECT google_play_supersede_purchase(scope,?,?,owner_id,chain_id,store_kind,?)
        FROM google_play_purchase WHERE scope=? AND token_hash=? AND granted AND lease_id=?`)
        .bind(previousHash, await sealToken(env, scope, purchase.predecessor), stamp, scope, hash, lease));
    }
    const results = await db.batch<{granted: boolean}>(updates);
    if (results[0]?.meta.changes !== 1) throw new PlayError("GOOGLE_PLAY_SYNC_PENDING", 409);
    // Delivery is durable before acknowledgement. On a timeout re-read Play's acknowledgement state first.
    const delivered = results[0].results[0]?.granted === true;
    if (needsAck && delivered) {
      await publisher(env, `purchases/subscriptions/${encodeURIComponent(purchase.product_id)}/tokens/${encodeURIComponent(token)}:acknowledge`, "POST");
      await db.prepare(`UPDATE google_play_purchase SET acknowledgement='ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',next_check_at=? WHERE scope=? AND token_hash=? AND lease_id=?`)
        .bind(checkAt, scope, hash, lease).run();
    }
    if (!eligibleTest && expectedOwner) throw new PlayError("GOOGLE_PLAY_TEST_SPACE_REQUIRED", 403);
    return { state: purchase.state, premium: delivered, expires_at: purchase.expires, auto_renew: purchase.renew };
  } catch (error) {
    const cause = error instanceof PlayError ? error : error instanceof Error && error.message === "GOOGLE_PLAY_OWNER_CONFLICT"
      ? new PlayError("GOOGLE_PLAY_OWNER_CONFLICT",403) : new PlayError("GOOGLE_PLAY_SYNC_UNAVAILABLE");
    if (cause.code !== "GOOGLE_PLAY_OWNER_CONFLICT") {
      const attempts = held.attempts + 1;
      const next = attempts >= 12 || cause.status === 404 ? null : new Date(now.getTime() + Math.min(3_600_000, 15_000 * 2 ** attempts)).toISOString();
      await db.prepare(`UPDATE google_play_purchase SET last_error=?,attempts=?,next_check_at=? WHERE scope=? AND token_hash=? AND lease_id=?`)
        .bind(cause.code, attempts, next, scope, hash, lease).run();
    }
    throw cause;
  } finally {
    await db.prepare("UPDATE google_play_purchase SET lease_until=NULL,lease_id=NULL WHERE scope=? AND token_hash=? AND lease_id=?")
      .bind(scope, hash, lease).run();
  }
}
