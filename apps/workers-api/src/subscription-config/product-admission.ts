import type { Env } from "../env";
import { createId } from "../id";
import { mutationLockKey } from "../db/mutation-lock";
import { appleAdmissionKey } from "../entitlements/apple-product-policy";
import type { CatalogProduct } from "./catalog";
import { errorOutcome, type Outcome } from "./model";
import { replayOutcome } from "./store";

export async function writeProductAdmission(env: Env, scope: string, adminId: string, requestId: string,
  hash: string, product: CatalogProduct | null, eventName: string, failure: Outcome | null): Promise<Outcome> {
  const db = env.DB;
  const run = crypto.randomUUID();
  const at = new Date().toISOString();
  const owner = [scope, requestId, run];
  const pending = "EXISTS(SELECT 1 FROM subscription_display_mutation WHERE scope = ? AND request_id = ? AND run_id = ? AND http_status IS NULL)";
  const statements = [
    db.prepare("INSERT INTO mutation_lock(lock_key) VALUES (?) ON CONFLICT(lock_key) DO UPDATE SET lock_key = excluded.lock_key")
      .bind(await mutationLockKey("subscription-display", scope)),
    db.prepare(`INSERT INTO subscription_display_mutation
      (scope, request_id, admin_id, payload_hash, operation, run_id, http_status, response, created_at)
      VALUES (?, ?, ?, ?, 'admit', ?, ?, ?::text::jsonb, ?) ON CONFLICT(scope, request_id) DO NOTHING`)
      .bind(scope, requestId, adminId, hash, run, failure?.status ?? null, failure ? JSON.stringify(failure.body) : null, at),
  ];
  if (product && !failure) {
    const id = product.product_id;
    const plan = "apple:" + id;
    statements.push(db.prepare("INSERT INTO mutation_lock(lock_key) VALUES (?) ON CONFLICT(lock_key) DO UPDATE SET lock_key = excluded.lock_key")
      .bind(await mutationLockKey("billing-product", id)));
    const scopeConflict = errorOutcome("PRODUCT_SCOPE_CONFLICT", "This Product ID is already admitted to another environment or App in this billing database.", 409);
    statements.push(db.prepare(`UPDATE subscription_display_mutation SET http_status = 409, response = ?::text::jsonb
      WHERE scope = ? AND request_id = ? AND run_id = ? AND http_status IS NULL AND EXISTS (
        SELECT 1 FROM app_config a WHERE CASE
          WHEN a.key LIKE 'billing.apple.admission:%' AND a.key <> ?
          THEN jsonb_exists(a.value::jsonb, ?) ELSE false END
      )`).bind(JSON.stringify(scopeConflict.body), ...owner, appleAdmissionKey(scope), id));
    statements.push(db.prepare("SELECT id FROM billing_product WHERE store = 'app_store' AND product_id = ? FOR UPDATE").bind(id));
    const conflict = errorOutcome("PRODUCT_MAPPING_CONFLICT", "An existing product or plan mapping conflicts with this admission. No mapping was overwritten.", 409);
    statements.push(db.prepare(`UPDATE subscription_display_mutation SET http_status = 409, response = ?::text::jsonb
      WHERE scope = ? AND request_id = ? AND run_id = ? AND http_status IS NULL AND EXISTS(
        SELECT 1 FROM billing_product WHERE store = 'app_store' AND
        ((product_id = ? AND (active <> 1 OR entitlement_id <> 'performance_pro' OR product_type <> ?))
         OR (plan_id = ? AND product_id <> ?)))`)
      .bind(JSON.stringify(conflict.body), ...owner, id, product.product_type, plan, id));
    statements.push(db.prepare(`INSERT INTO billing_product
      (id, store, product_id, plan_id, entitlement_id, product_type, active, created_at, updated_at)
      SELECT ?, 'app_store', ?, ?, 'performance_pro', ?, 1, ?, ? WHERE ${pending}
      ON CONFLICT(store, product_id) DO NOTHING`).bind(createId(), id, plan, product.product_type, at, at, ...owner));
    statements.push(db.prepare(`INSERT INTO app_config(key, value, updated_by, updated_at)
      SELECT ?, jsonb_build_object(product_id, jsonb_build_object(
        'product_id', product_id, 'plan_id', plan_id, 'product_type', product_type,
        'is_trial_product', ?::boolean, 'singular_event_name', ?::text,
        'approved_by', ?::text, 'approved_at', ?::text))::text, ?, ?
      FROM billing_product WHERE store = 'app_store' AND product_id = ? AND ${pending}
      ON CONFLICT(key) DO UPDATE SET value = (app_config.value::jsonb || excluded.value::jsonb)::text,
        updated_by = excluded.updated_by, updated_at = excluded.updated_at`)
      .bind(appleAdmissionKey(scope), product.has_free_trial, eventName, adminId, at, adminId, at, id, ...owner));
    statements.push(db.prepare(`UPDATE subscription_display_mutation SET http_status = 200,
      response = jsonb_build_object('success', true, 'data', jsonb_build_object('product_id', ?::text, 'scope', ?::text))
      WHERE scope = ? AND request_id = ? AND run_id = ? AND http_status IS NULL`).bind(id, scope, ...owner));
  }
  statements.push(db.prepare("SELECT admin_id, payload_hash, http_status, response FROM subscription_display_mutation WHERE scope = ? AND request_id = ?").bind(scope, requestId));
  const results = await db.batch<{ admin_id: string; payload_hash: string; http_status: number | null; response: Outcome["body"] | null }>(statements);
  const row = results.at(-1)?.results?.[0];
  if (!row || results.some((result) => !result.success)) throw new Error("Product admission transaction failed.");
  return replayOutcome(row, adminId, hash);
}
