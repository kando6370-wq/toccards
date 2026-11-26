import type { Env } from "../env";
import { divideAndRoundMicros, loadBillingUsdSnapshot, type BillingUsdSnapshot } from "../entitlements/billing-currency";
import { isRecord } from "../subscription-config/model";
import { playDigest, PlayError, publisher } from "./publisher";
import { utc } from "./purchases";

export function money(value: unknown) {
  if (!isRecord(value) || typeof value.currencyCode !== "string" || !/^[A-Z]{3}$/.test(value.currencyCode)) return null;
  const units = value.units ?? "0", nanos = value.nanos ?? 0;
  if (typeof units !== "string" || !/^\d{1,19}$/.test(units) || typeof nanos !== "number" || !Number.isInteger(nanos) || nanos < 0 || nanos >= 1e9) return null;
  const amount = Number(BigInt(units) * 1_000_000n + (BigInt(nanos) + 500n) / 1000n);
  return Number.isSafeInteger(amount) ? { currency: value.currencyCode, micros: amount } : null;
}

type Event = { key: string; kind: "charge" | "refund"; at: string; amount: number | null };
export function orderFacts(raw: unknown, orderId: string) {
  if (!isRecord(raw) || raw.orderId !== orderId || !isRecord(raw.orderHistory)) throw new PlayError("GOOGLE_PLAY_ORDER_UNVERIFIED");
  const h = raw.orderHistory, total = money(raw.total), tax = money(raw.tax), events: Event[] = [];
  function refundAmount(details: unknown) {
    const paid = isRecord(details) ? money(details.total) : null;
    return paid && total && paid.currency === total.currency ? paid.micros : null;
  }
  const charge = isRecord(h.processedEvent) && utc(h.processedEvent.eventTime);
  if (charge) events.push({ key: "charge", kind: "charge", at: charge, amount: total?.micros ?? null });
  let partialSum: number | null = 0;
  if (Array.isArray(h.partialRefundEvents)) {
    for (const partial of h.partialRefundEvents) {
      if (!isRecord(partial) || partial.state !== "PROCESSED_SUCCESSFULLY") continue;
      const at = utc(partial.processTime);
      if (!at) throw new PlayError("GOOGLE_PLAY_ORDER_UNVERIFIED");
      const amount = refundAmount(partial.refundDetails);
      partialSum = amount === null || partialSum === null ? null : partialSum + amount;
      events.push({ key: `partial-${events.length}`, kind: "refund", at, amount });
    }
  }
  if (total && partialSum !== null && partialSum > total.micros) throw new PlayError("GOOGLE_PLAY_REFUND_MISMATCH");
  if (isRecord(h.refundEvent)) {
    const at = utc(h.refundEvent.eventTime), amount = refundAmount(h.refundEvent.refundDetails);
    if (!at) throw new PlayError("GOOGLE_PLAY_ORDER_UNVERIFIED");
    events.push({ key: "full-refund", kind: "refund", at,
      amount: partialSum === null || amount === null || !total ? null : Math.min(amount, total.micros - partialSum) });
  }
  return { total, tax, events };
}

export async function syncOrder(env: Env, scope: string, store: string, id: string) {
  const db = env.DB;
  const order = await db.prepare("SELECT token_hash,fx_snapshot,sync_revision FROM google_play_order WHERE scope=? AND store_kind=? AND order_id=?")
    .bind(scope, store, id).first<{token_hash: string; fx_snapshot: BillingUsdSnapshot | null; sync_revision: string | null}>();
  if (!order) throw new PlayError("GOOGLE_PLAY_ORDER_UNKNOWN", 409);
  const raw = await publisher(env, `orders/${encodeURIComponent(id)}`);
  if (!isRecord(raw) || typeof raw.purchaseToken !== "string" || await playDigest(env, scope, "token", raw.purchaseToken) !== order.token_hash) throw new PlayError("GOOGLE_PLAY_ORDER_UNVERIFIED");
  const { total, tax, events } = orderFacts(raw, id);
  const item = Array.isArray(raw.lineItems) && raw.lineItems.length === 1 ? raw.lineItems[0] : null;
  const details = isRecord(item) && isRecord(item.subscriptionDetails) ? item.subscriptionDetails : null;
  const phase = details && isRecord(details.offerPhaseDetails) ? details.offerPhaseDetails : null;
  const freePhase = phase ? isRecord(phase.freeTrialDetails) : details?.offerPhase === "FREE_TRIAL";
  const paidPhase = phase ? isRecord(phase.baseDetails) || isRecord(phase.introductoryPriceDetails)
    : details?.offerPhase === "BASE" || details?.offerPhase === "INTRODUCTORY";
  const trial = freePhase ? true : paidPhase ? false : null;
  const sdkFrom = utc(env.GOOGLE_PLAY_SINGULAR_SDK_FROM);
  const now = new Date(), revision = crypto.randomUUID();
  const fx = order.fx_snapshot ?? await loadBillingUsdSnapshot(env.CACHE_KV, total?.micros ?? null, total?.currency ?? null, now);
  const where = "scope=? AND store_kind=? AND order_id=?";
  // Compare-and-swap the entire history so a slower lookup cannot replace a newer refund or FX snapshot.
  const params = [scope, store, id];
  const saved = await db.batch([
    db.prepare(`UPDATE google_play_order SET total_micros=?,tax_micros=?,currency=?,fx_snapshot=?::jsonb,checked_at=?,sync_revision=?,
      period_start=CASE WHEN product_id=? AND base_plan_id=? THEN ? ELSE NULL END,
      period_end=CASE WHEN product_id=? AND base_plan_id=? THEN ? ELSE NULL END,free_trial=?,period_offer_id=?
      WHERE ${where} AND sync_revision IS NOT DISTINCT FROM ?`).bind(total?.micros ?? null, tax?.micros ?? null, total?.currency ?? null,
        fx ? JSON.stringify(fx) : null, now.toISOString(), revision,
        item?.productId ?? null, details?.basePlanId ?? null, utc(details?.servicePeriodStartTime),
        item?.productId ?? null, details?.basePlanId ?? null, utc(details?.servicePeriodEndTime), trial, details?.offerId ?? "", ...params, order.sync_revision),
    db.prepare(`DELETE FROM google_play_order_event WHERE ${where} AND EXISTS(SELECT 1 FROM google_play_order WHERE ${where} AND sync_revision=?)`)
      .bind(...params, ...params, revision),
    ...events.map(event => db.prepare(`INSERT INTO google_play_order_event(scope,store_kind,order_id,event_key,kind,event_at,amount_micros,usd_micros)
      SELECT scope,store_kind,order_id,?,?,?,?,? FROM google_play_order WHERE ${where} AND sync_revision=?`)
      .bind(event.key, event.kind, event.at, event.amount, event.amount !== null && fx ? divideAndRoundMicros(event.amount, fx.rate) : null, ...params, revision)),
    ...(store === "live" && sdkFrom ? [db.prepare(`INSERT INTO google_play_first_charge
      (scope, chain_id, order_id, owner_id, product_id, event_name, currency, amount_micros, charged_at)
      SELECT o.scope, p.chain_id, o.order_id, p.owner_id, o.product_id, product.revenue_event, o.currency, e.amount_micros, e.event_at
      FROM google_play_order o JOIN google_play_order_event e USING(scope,store_kind,order_id)
      JOIN google_play_purchase p ON p.scope=o.scope AND p.token_hash=o.token_hash AND p.store_kind=o.store_kind
      JOIN google_play_product product ON product.scope=p.scope AND product.product_id=o.product_id
        AND product.base_plan_id=o.base_plan_id AND product.offer_id=o.period_offer_id
      WHERE o.scope=? AND o.store_kind='live' AND o.token_hash=? AND p.previous_hash IS NULL AND NOT p.superseded
        AND p.owner_id IS NOT NULL AND e.kind='charge' AND e.amount_micros>0 AND e.event_at>=? AND o.currency IS NOT NULL
        AND NOT o.free_trial AND (o.period_start=p.started_at OR EXISTS (
          SELECT 1 FROM google_play_order trial JOIN google_play_order_event t USING(scope,store_kind,order_id)
          WHERE trial.scope=o.scope AND trial.store_kind=o.store_kind AND trial.token_hash=o.token_hash
            AND trial.free_trial AND t.kind='charge' AND t.amount_micros=0
            AND trial.period_start=p.started_at AND trial.period_end=o.period_start))
        AND EXISTS (SELECT 1 FROM google_play_order WHERE ${where} AND sync_revision=?)
      ORDER BY e.event_at,o.order_id LIMIT 1 ON CONFLICT DO NOTHING`)
      .bind(scope, order.token_hash, sdkFrom, ...params, revision)] : []),
  ]);
  if (saved[0]?.meta.changes !== 1) throw new PlayError("GOOGLE_PLAY_ORDER_CHANGED", 409);
}
