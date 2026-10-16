import { appleAdmissionKey, appleAdmissionScope, approvedAppleProducts } from "../entitlements/apple-product-policy";
import type { Env } from "../env";
import type { Database } from "../db/database";
import { mutationLockKey } from "../db/mutation-lock";
import { createId } from "../id";
import {
  configuredIds, errorOutcome, referencedProducts,
  type DisplayConfig, type Outcome, type PageType, type ProductType,
} from "./model";

export type ConfigRow = {
  id: string; scope: string; page_type: PageType; revision: number;
  body: DisplayConfig; updated_by: string; updated_at: string; enabled: boolean;
};
type MutationRow = {
  admin_id: string; payload_hash: string; http_status: number | null;
  response: Outcome["body"] | null;
};
export type MutationCommand =
  | { kind: "create"; config: DisplayConfig | null }
  | { kind: "save"; id: string; expected_revision: number; config: DisplayConfig | null }
  | { kind: "activate"; page_type: PageType; config_id: string | null; expected_active_revision: number; expected_config_revision: number | null; config: DisplayConfig | null };

export async function readConfig(db: Database, scope: string, id: string): Promise<ConfigRow | null> {
  return db.prepare(`
    SELECT c.*, EXISTS(SELECT 1 FROM subscription_display_active a
      WHERE a.scope = c.scope AND a.config_id = c.id) AS enabled
    FROM subscription_display_config c WHERE c.scope = ? AND c.id = ?
  `).bind(scope, id).first<ConfigRow>();
}

export async function readConfigList(db: Database, scope: string) {
  // One statement keeps the list's enabled flags and active revisions consistent.
  return db.prepare(`
    SELECT jsonb_build_object(
      'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'page_type', c.page_type, 'revision', c.revision, 'body', c.body,
        'updated_by', c.updated_by, 'updated_at', c.updated_at,
        'enabled', EXISTS(SELECT 1 FROM subscription_display_active a WHERE a.scope = c.scope AND a.config_id = c.id)
      ) ORDER BY c.updated_at DESC, c.id) FROM subscription_display_config c WHERE c.scope = ?), '[]'::jsonb),
      'active', (SELECT jsonb_agg(jsonb_build_object(
        'page_type', t.page_type, 'config_id', a.config_id, 'active_revision', COALESCE(a.revision, 0)
      ) ORDER BY t.position) FROM (VALUES ('page', 1), ('modal', 2)) t(page_type, position)
        LEFT JOIN subscription_display_active a ON a.scope = ? AND a.page_type = t.page_type)
    ) AS data
  `).bind(scope, scope).first("data");
}

export async function readActiveConfig(db: Database, scope: string, type: PageType): Promise<ConfigRow | null> {
  return db.prepare(`
    SELECT c.*, true AS enabled FROM subscription_display_active a
    JOIN subscription_display_config c ON c.id = a.config_id AND c.scope = a.scope AND c.page_type = a.page_type
    WHERE a.scope = ? AND a.page_type = ?
  `).bind(scope, type).first<ConfigRow>();
}

export async function readMutation(db: Database, scope: string, requestId: string): Promise<MutationRow | null> {
  return db.prepare(`SELECT admin_id, payload_hash, http_status, response
    FROM subscription_display_mutation WHERE scope = ? AND request_id = ?`)
    .bind(scope, requestId).first<MutationRow>();
}

export function replayOutcome(row: MutationRow, adminId: string, hash?: string): Outcome {
  if (row.admin_id !== adminId || (hash !== undefined && row.payload_hash !== hash)) {
    return errorOutcome("IDEMPOTENCY_CONFLICT", "Request ID belongs to a different operation or administrator.", 409);
  }
  if (row.http_status === null || row.response === null) {
    return errorOutcome("MUTATION_RESULT_UNKNOWN", "The operation result is not yet known. Recheck the original request.", 503);
  }
  return { status: row.http_status, body: row.response };
}

export async function productAdmission(env: Env, products: Array<{ product_id: string; product_type: ProductType }>) {
  if (!products.length) return [];
  const ids = [...new Set(products.map((p) => p.product_id))];
  const { results: rows = [] } = await env.DB.prepare(`
    SELECT product_id, product_type, active, entitlement_id FROM billing_product
    WHERE store = 'app_store' AND product_id IN (${ids.map(() => "?").join(",")})
  `).bind(...ids).all<{ product_id: string; product_type: string; active: number; entitlement_id: string }>();
  const allowed = configuredIds(env.APPLE_IAP_PRODUCT_IDS);
  const approved = configuredIds(env.SUBSCRIPTION_DISPLAY_PRODUCT_IDS);
  for (const p of await approvedAppleProducts(env)) { allowed.add(p.product_id); approved.add(p.product_id); }
  return products.map((p) => {
    const row = rows.find((r) => r.product_id === p.product_id);
    const reasons: string[] = [];
    if (!allowed.has(p.product_id)) reasons.push("NOT_IN_ENTITLEMENT_ALLOWLIST");
    if (!approved.has(p.product_id)) reasons.push("DISPLAY_APPROVAL_REQUIRED");
    if (!row || row.active !== 1 || row.entitlement_id !== "performance_pro" || row.product_type !== p.product_type) reasons.push("ENTITLEMENT_MAPPING_UNAVAILABLE");
    return { product_id: p.product_id, admitted: !reasons.length, reasons };
  });
}

// JSON strings bind as text before casting: postgres.js otherwise serializes them again.
// All writes in one scope are serialized before the following statements obtain
// their READ COMMITTED snapshots. No external Apple request runs inside this batch.
export async function writeMutation(
  env: Env, scope: string, adminId: string, requestId: string, hash: string,
  command: MutationCommand, preflightFailure: Outcome | null,
): Promise<Outcome> {
  const db = env.DB;
  const runId = crypto.randomUUID();
  const timestamp = new Date().toISOString();
  const pending = `EXISTS (SELECT 1 FROM subscription_display_mutation
    WHERE scope = ? AND request_id = ? AND run_id = ? AND http_status IS NULL)`;
  const owner = [scope, requestId, runId];
  const statements = [
    db.prepare(`INSERT INTO mutation_lock (lock_key) VALUES (?)
      ON CONFLICT (lock_key) DO UPDATE SET lock_key = excluded.lock_key`)
      .bind(await mutationLockKey("subscription-display", scope)),
    db.prepare(`INSERT INTO subscription_display_mutation
      (scope, request_id, admin_id, payload_hash, operation, run_id, http_status, response, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?::text::jsonb, ?) ON CONFLICT (scope, request_id) DO NOTHING`)
      .bind(scope, requestId, adminId, hash, command.kind, runId,
        preflightFailure?.status ?? null, preflightFailure ? JSON.stringify(preflightFailure.body) : null, timestamp),
  ];
  const failWhen = (condition: string, bindings: unknown[], outcome: Outcome) => {
    statements.push(db.prepare(`UPDATE subscription_display_mutation SET http_status = ?, response = ?::text::jsonb
      WHERE scope = ? AND request_id = ? AND run_id = ? AND http_status IS NULL AND (${condition})`)
      .bind(outcome.status, JSON.stringify(outcome.body), ...owner, ...bindings));
  };
  const conflict = errorOutcome("CONFIG_CONFLICT", "Configuration or active selection changed. Reload before retrying with a new request ID.", 409);
  const notFound = errorOutcome("CONFIG_NOT_FOUND", "Configuration not found in this App scope.", 404);
  for (const type of ["page", "modal"]) statements.push(db.prepare(`
    INSERT INTO subscription_display_active (scope, page_type)
    SELECT ?, ? WHERE ${pending} ON CONFLICT (scope, page_type) DO NOTHING
  `).bind(scope, type, ...owner));

  if (command.kind === "save") {
    failWhen("NOT EXISTS(SELECT 1 FROM subscription_display_config WHERE scope = ? AND id = ?)", [scope, command.id], notFound);
    failWhen("EXISTS(SELECT 1 FROM subscription_display_config WHERE scope = ? AND id = ? AND revision <> ?)", [scope, command.id, command.expected_revision], conflict);
    failWhen(`EXISTS(SELECT 1 FROM subscription_display_active WHERE scope = ? AND config_id = ? AND page_type <> ?)`,
      [scope, command.id, command.config?.page_type ?? "page"], errorOutcome("ACTIVE_PAGE_TYPE_IMMUTABLE", "Disable the configuration before changing its page type.", 409));
  } else if (command.kind === "activate") {
    failWhen("EXISTS(SELECT 1 FROM subscription_display_active WHERE scope = ? AND page_type = ? AND revision <> ?)",
      [scope, command.page_type, command.expected_active_revision], conflict);
    if (command.config_id !== null) {
      failWhen("NOT EXISTS(SELECT 1 FROM subscription_display_config WHERE scope = ? AND id = ? AND page_type = ?)", [scope, command.config_id, command.page_type], notFound);
      failWhen("EXISTS(SELECT 1 FROM subscription_display_config WHERE scope = ? AND id = ? AND revision <> ?)", [scope, command.config_id, command.expected_config_revision], conflict);
    }
  }

  if (command.config && command.kind !== "create") {
    const allowlist = configuredIds(env.APPLE_IAP_PRODUCT_IDS);
    const approved = configuredIds(env.SUBSCRIPTION_DISPLAY_PRODUCT_IDS);
    const required = referencedProducts(command.config, false).map((p) => ({ ...p,
      allowed: allowlist.has(p.product_id), approved: approved.has(p.product_id) }));
    const needsAdmission = command.kind === "activate" ? "true" :
      "EXISTS(SELECT 1 FROM subscription_display_active WHERE scope = ? AND config_id = ?)";
    // Keep admitted billing mappings stable until this activation/content commit.
    statements.push(db.prepare(`SELECT b.id FROM billing_product b
      JOIN jsonb_to_recordset(?::text::jsonb) AS p(product_id text) ON p.product_id = b.product_id
      WHERE b.store = 'app_store' AND ${pending} AND ${needsAdmission}
      ORDER BY b.id FOR SHARE OF b`).bind(JSON.stringify(required), ...owner,
        ...(command.kind === "save" ? [scope, command.id] : [])));
    failWhen(`${needsAdmission} AND EXISTS (
      SELECT 1 FROM jsonb_to_recordset(?::text::jsonb) AS p(product_id text, product_type text, allowed boolean, approved boolean)
      LEFT JOIN billing_product b ON b.store = 'app_store' AND b.product_id = p.product_id
      WHERE ((NOT p.allowed OR NOT p.approved) AND NOT EXISTS (
        SELECT 1 FROM app_config a WHERE a.key = ? AND ?::boolean
          AND jsonb_extract_path_text(a.value::jsonb, p.product_id, 'product_type') = p.product_type
      )) OR b.id IS NULL OR b.active <> 1
        OR b.entitlement_id <> 'performance_pro' OR b.product_type <> p.product_type
    )`, [...(command.kind === "save" ? [scope, command.id] : []), JSON.stringify(required), appleAdmissionKey(scope), appleAdmissionScope(env) !== null],
    errorOutcome("PRODUCT_NOT_ADMITTED", "Every effective product must have display approval, entitlement allowlisting and an active matching Premium mapping.", 422));
  }

  if (command.kind === "activate") {
    statements.push(db.prepare(`WITH changed AS (
      UPDATE subscription_display_active SET config_id = ?, revision = revision + 1
      WHERE scope = ? AND page_type = ? AND ${pending} RETURNING *
    ) UPDATE subscription_display_mutation SET http_status = 200, response = (
      SELECT jsonb_build_object('success', true, 'data', jsonb_build_object(
        'page_type', page_type, 'config_id', config_id, 'active_revision', revision)) FROM changed
    ) WHERE scope = ? AND request_id = ? AND run_id = ? AND http_status IS NULL
      AND EXISTS(SELECT 1 FROM changed)`)
      .bind(command.config_id, scope, command.page_type, ...owner, ...owner));
  } else if (command.config) {
    const config = command.config;
    const write = command.kind === "create"
      ? `INSERT INTO subscription_display_config (id, scope, page_type, body, updated_by, updated_at)
          SELECT ?, ?, ?, ?::text::jsonb, ?, ? WHERE ${pending} RETURNING *`
      : `UPDATE subscription_display_config SET page_type = ?, body = ?::text::jsonb,
          revision = revision + 1, updated_by = ?, updated_at = ?
          WHERE scope = ? AND id = ? AND ${pending} RETURNING *`;
    const bindings = command.kind === "create"
      ? [createId(), scope, config.page_type, JSON.stringify(config), adminId, timestamp, ...owner]
      : [config.page_type, JSON.stringify(config), adminId, timestamp, scope, command.id, ...owner];
    statements.push(db.prepare(`WITH changed AS (${write})
      UPDATE subscription_display_mutation SET http_status = ?, response = (
        SELECT jsonb_build_object('success', true, 'data', jsonb_build_object(
          'id', c.id, 'page_type', c.page_type, 'revision', c.revision, 'body', c.body,
          'updated_by', c.updated_by, 'updated_at', c.updated_at,
          'enabled', EXISTS(SELECT 1 FROM subscription_display_active a WHERE a.scope = c.scope AND a.config_id = c.id)))
        FROM changed c
      ) WHERE scope = ? AND request_id = ? AND run_id = ? AND http_status IS NULL
        AND EXISTS(SELECT 1 FROM changed)`)
      .bind(...bindings, command.kind === "create" ? 201 : 200, ...owner));
  }
  statements.push(db.prepare(`SELECT admin_id, payload_hash, http_status, response
    FROM subscription_display_mutation WHERE scope = ? AND request_id = ?`).bind(scope, requestId));
  const results = await db.batch<MutationRow>(statements);
  const row = results.at(-1)?.results?.[0];
  if (!row || results.some((result) => !result.success)) throw new Error("Subscription configuration transaction failed.");
  return replayOutcome(row, adminId, hash);
}
