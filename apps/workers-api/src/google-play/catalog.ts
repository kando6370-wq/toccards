import type { Env } from "../env";
import { isRecord } from "../subscription-config/model";
import type { PlayPlan } from "./purchases";
import { PlayError, publisher } from "./publisher";

export function planKey(p: PlayPlan) { return JSON.stringify([p.product_id, p.base_plan_id, p.offer_id]); }
export function parsePlan(input: unknown): PlayPlan | null {
  if (!isRecord(input) || typeof input.product_id !== "string" || !/^[a-z0-9][a-z0-9._]{0,149}$/.test(input.product_id) ||
      typeof input.base_plan_id !== "string" || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(input.base_plan_id) ||
      typeof input.offer_id !== "string" || (input.offer_id && !/^[a-z0-9][a-z0-9-]{0,62}$/.test(input.offer_id))) return null;
  return { product_id:input.product_id,base_plan_id:input.base_plan_id,offer_id:input.offer_id };
}
async function list(env: Env, resource: string, field: string) {
  let token = "";
  const all: Record<string,unknown>[] = [], seen = new Set<string>();
  do {
    const data = await publisher(env, `${resource}?pageSize=100${token ? `&pageToken=${encodeURIComponent(token)}` : ""}`);
    if (data === undefined) break; // Play returns HTTP 204 for an empty subscription or offer list.
    if (!isRecord(data) || (data[field] !== undefined && !Array.isArray(data[field]))) throw new PlayError("GOOGLE_PLAY_CATALOG_UNAVAILABLE");
    all.push(...((data[field] ?? []) as unknown[]).filter(isRecord));
    token = typeof data.nextPageToken === "string" ? data.nextPageToken : "";
    if (token && seen.has(token)) throw new PlayError("GOOGLE_PLAY_CATALOG_UNAVAILABLE");
    seen.add(token);
  } while (token);
  return all;
}
export async function storeCatalog(env: Env) {
  if (!env.GOOGLE_PLAY_PUBLISHER_EMAIL?.trim() || !env.GOOGLE_PLAY_PUBLISHER_PRIVATE_KEY?.trim()) {
    throw new PlayError("GOOGLE_PLAY_PUBLISHER_NOT_CONFIGURED");
  }
  const catalog: Array<PlayPlan & { countries: string[] }> = [];
  for (const product of await list(env, "subscriptions", "subscriptions")) {
    if (product.packageName !== env.GOOGLE_PLAY_PACKAGE_NAME || typeof product.productId !== "string" || !Array.isArray(product.basePlans) || product.archived) continue;
    for (const base of product.basePlans.filter(isRecord)) {
      if (base.state !== "ACTIVE" || !isRecord(base.autoRenewingBasePlanType) || typeof base.basePlanId !== "string") continue;
      const countries = Array.isArray(base.regionalConfigs) ? base.regionalConfigs.filter(isRecord)
        .filter(region => region.newSubscriberAvailability === true && typeof region.regionCode === "string").map(r => String(r.regionCode)) : [];
      if (!countries.length) continue;
      const plan = {product_id:product.productId,base_plan_id:base.basePlanId,offer_id:"",countries};
      catalog.push(plan);
      for (const offer of await list(env, `subscriptions/${encodeURIComponent(product.productId)}/basePlans/${encodeURIComponent(base.basePlanId)}/offers`, "subscriptionOffers")) {
        if (offer.state !== "ACTIVE" || offer.packageName !== product.packageName || offer.productId !== product.productId || offer.basePlanId !== base.basePlanId || typeof offer.offerId !== "string") continue;
        const regions = Array.isArray(offer.regionalConfigs) ? offer.regionalConfigs.filter(isRecord).filter(r => r.newSubscriberAvailability === true && countries.includes(String(r.regionCode))).map(r => String(r.regionCode)) : [];
        if (regions.length) catalog.push({...plan,offer_id:offer.offerId,countries:regions});
      }
    }
  }
  return catalog;
}

export function displayConfig(input: unknown) {
  if (!isRecord(input) || typeof input.title !== "string" || !input.title.trim() || input.title.length > 120 || !Array.isArray(input.plans) || input.plans.length < 1 || input.plans.length > 12) return null;
  const plans: Array<PlayPlan & {label: string; is_default: boolean}> = [];
  for (const item of input.plans) {
    const plan = parsePlan(item);
    if (!plan || !isRecord(item) || typeof item.label !== "string" || !item.label.trim() || item.label.length > 100 || typeof item.is_default !== "boolean" || plans.some(p => planKey(p) === planKey(plan))) return null;
    plans.push({...plan,label:item.label.trim(),is_default:item.is_default});
  }
  return plans.filter(p => p.is_default).length === 1 ? {title:input.title.trim(),plans} : null;
}
