import type { Env } from "../env";
import { configuredProductIds } from "./apple-signed-data";

export type AppleProductPolicyEnv = Pick<Env, "DB" | "APP_ENVIRONMENT" | "APPLE_IAP_BUNDLE_ID" | "APPLE_IAP_PRODUCT_IDS" | "APP_STORE_CONNECT_APP_ID">;
export type ApprovedAppleProduct = {
  product_id: string; plan_id: string; product_type: "subscription" | "non_consumable";
  is_trial_product: boolean; singular_event_name: string; approved_by: string; approved_at: string;
};
export function appleAdmissionKey(scope: string): string { return "billing.apple.admission:" + scope; }
export function appleAdmissionScope(env: AppleProductPolicyEnv): string | null {
  // Existing deployments without the optional catalog module retain their original policy.
  if (!env.APP_STORE_CONNECT_APP_ID?.trim()) return null;
  if (!env.APPLE_IAP_BUNDLE_ID?.trim() || !["production", "development"].includes(env.APP_ENVIRONMENT ?? "")) {
    throw new Error("Apple admission scope is not configured.");
  }
  return env.APP_ENVIRONMENT + ":" + env.APPLE_IAP_BUNDLE_ID.trim();
}
export async function approvedAppleProducts(env: AppleProductPolicyEnv): Promise<ApprovedAppleProduct[]> {
  const scope = appleAdmissionScope(env);
  if (!scope) return [];
  const row = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?")
    .bind(appleAdmissionKey(scope)).first<{ value: string }>();
  if (!row) return [];
  const value: unknown = JSON.parse(row.value);
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid Apple admission registry.");
  const products = Object.entries(value).map(([id, item]) => {
    const p = item as ApprovedAppleProduct;
    if (!p || p.product_id !== id || !id.trim() || id !== id.trim() || typeof p.plan_id !== "string" || !p.plan_id.trim() ||
        !["subscription", "non_consumable"].includes(p.product_type) || typeof p.is_trial_product !== "boolean" ||
        typeof p.singular_event_name !== "string" || !/^[A-Za-z][A-Za-z0-9_]{0,99}$/.test(p.singular_event_name) ||
        typeof p.approved_by !== "string" || typeof p.approved_at !== "string") throw new Error("Invalid Apple admission product.");
    return p;
  });
  if (new Set(products.map((p) => p.plan_id)).size !== products.length) throw new Error("Duplicate Apple admission plan.");
  return products;
}
export async function allowedAppleProductIds(env: AppleProductPolicyEnv): Promise<ReadonlySet<string> | null> {
  const products = new Set(configuredProductIds(env.APPLE_IAP_PRODUCT_IDS) ?? []);
  for (const p of await approvedAppleProducts(env)) products.add(p.product_id);
  return products.size ? products : null;
}
