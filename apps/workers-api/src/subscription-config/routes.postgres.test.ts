import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword } from "@kando/auth-core";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { app } from "../app";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { SubscriptionConfigError } from "./model";
import type { DisplayConfig } from "./model";
import { catalogFixture, displayFixture } from "./test-fixtures";

const { catalogLoader } = vi.hoisted(() => ({ catalogLoader: vi.fn() }));
vi.mock("./catalog", async (original) => ({
  ...await original<typeof import("./catalog")>(), createAppleCatalogLoader: () => catalogLoader,
}));
let db: PGliteDatabase;
let env: Env;
let operator: string;
let supervisor: string;
let info: ReturnType<typeof vi.spyOn>;
type JsonResponse = { success: boolean; data: any; error?: { code: string; fields?: unknown[] } };

async function call(path: string, method = "GET", body?: unknown, options: { env?: Env; token?: string | null } = {}) {
  const token = options.token === undefined ? operator : options.token;
  const response = await app.request("/api/v1" + path, { method, headers: {
    ...(token ? { Authorization: "Bearer " + token } : {}), ...(body === undefined ? {} : { "Content-Type": "application/json" }),
  }, body: body === undefined ? undefined : JSON.stringify(body) }, options.env ?? env);
  return { status: response.status, body: await response.json() as JsonResponse, headers: response.headers };
}
async function create(config = displayFixture(), requestId = crypto.randomUUID(), options: { env?: Env; token?: string | null } = {}) {
  return call("/admin/subscription-configs", "POST", { request_id: requestId, config }, options);
}
async function enable(id: string | null, activeRevision = 0, configRevision: number | null = 1, options: { env?: Env; token?: string | null; page?: "page" | "modal"; requestId?: string } = {}) {
  return call("/admin/subscription-configs/active/" + (options.page ?? "page"), "PUT", {
    request_id: options.requestId ?? crypto.randomUUID(), config_id: id, expected_active_revision: activeRevision,
    ...(id ? { expected_config_revision: configRevision } : {}),
  }, options);
}
async function update(id: string, config: DisplayConfig, revision = 1, requestId = crypto.randomUUID()) {
  return call("/admin/subscription-configs/" + id, "PUT", { request_id: requestId, expected_revision: revision, config });
}
const publicConfig = (options: { env?: Env; type?: string; platform?: string } = {}) => call(
  "/subscription-display-config?type=" + (options.type ?? "page") + (options.platform ? "&platform=" + options.platform : ""),
  "GET", undefined, { env: options.env, token: null },
);

beforeAll(async () => {
  info = vi.spyOn(console, "info").mockImplementation(() => {});
  db = await PGliteDatabase.create();
  for (const name of ["0000_business_schema", "0006_mutation_lock", "0014_subscription_display_config"]) {
    await db.exec(readFileSync(new URL("../db/postgres/migrations/" + name + ".sql", import.meta.url), "utf8"));
  }
  env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "subscription-config-test-secret", APP_ENVIRONMENT: "development",
    APPLE_IAP_BUNDLE_ID: "example.app", APPLE_IAP_PRODUCT_IDS: "paid.week,trial.week,lifetime",
    SUBSCRIPTION_DISPLAY_PRODUCT_IDS: "paid.week,trial.week,lifetime", SUBSCRIPTION_LIFETIME_PRODUCT_IDS: "lifetime" };
  const password = "test-admin-password";
  const passwordHash = await hashPassword(password);
  for (const role of ["operator", "super_admin"]) {
    const email = role + "@example.test";
    await db.prepare("INSERT INTO admin_user (id, email, password_hash, role, status, created_at) VALUES (?, ?, ?, ?, 'active', ?)")
      .bind(role, email, passwordHash, role, new Date().toISOString()).run();
    const login = await call("/admin/auth/login", "POST", { email, password }, { token: null });
    expect(login.status).toBe(200);
    if (role === "operator") operator = login.body.data.access_token;
    else supervisor = login.body.data.access_token;
  }
}, 30_000);
afterAll(async () => { info?.mockRestore(); await db?.close(); });
beforeEach(async () => {
  await db.exec("DELETE FROM subscription_display_active; DELETE FROM subscription_display_config; DELETE FROM subscription_display_mutation; DELETE FROM billing_product;");
  for (const [productId, type] of [["paid.week", "subscription"], ["trial.week", "subscription"], ["lifetime", "non_consumable"]]) {
    await db.prepare("INSERT INTO billing_product (id, store, product_id, plan_id, entitlement_id, product_type, active, created_at, updated_at) VALUES (?, 'app_store', ?, ?, 'performance_pro', ?, 1, ?, ?)")
      .bind(productId, productId, productId, type, "2026-10-14", "2026-10-14").run();
  }
  catalogLoader.mockReset();
  catalogLoader.mockResolvedValue(catalogFixture());
});

describe("subscription configuration APIs on PostgreSQL", () => {
  it.each(["page", "modal"] as const)("allows three %s cards including an independent trial and rejects over-limit writes atomically", async (pageType) => {
    const config = displayFixture(); config.page_type = pageType; config.trial_enabled = false;
    config.skus[0].trial = null;
    config.skus.push({ ...config.skus[0], product_id: "trial.week", is_default: false });
    const oversized = structuredClone(config);
    oversized.skus.push({ ...config.skus[0], product_id: "paid.year", is_default: false });
    const invalid = { status: 422, body: { error: { code: "VALIDATION_ERROR",
      fields: [{ path: "skus", message: "At most 3 display SKUs are allowed." }] } } };
    expect(await create(oversized)).toMatchObject(invalid);
    expect((await call("/admin/subscription-configs")).body.data.items).toEqual([]);
    expect(catalogLoader).not.toHaveBeenCalled();

    const created = await create(config);
    expect(created.status).toBe(201);
    const id = created.body.data.id;
    expect(created.body.data.body.skus).toEqual(config.skus);
    expect((await enable(id, 0, 1, { page: pageType })).status).toBe(200);
    const before = await publicConfig({ type: pageType });
    expect(before.status).toBe(200);
    expect(before.body.data.skus).toEqual(config.skus);
    const list = (await call("/admin/subscription-configs")).body;
    catalogLoader.mockClear();
    const requestId = crypto.randomUUID();
    expect(await update(id, oversized, 1, requestId)).toMatchObject(invalid);
    expect((await call("/admin/subscription-config-mutations/" + requestId)).body.data).toMatchObject({ status: "failed", http_status: 422 });
    expect(catalogLoader).not.toHaveBeenCalled();
    expect((await call("/admin/subscription-configs")).body).toEqual(list);
    expect((await publicConfig({ type: pageType })).body).toEqual(before.body);
  });

  it.each(["page", "modal"] as const)("keeps a legacy oversized %s configuration editable but blocks activation and public use until repaired", async (pageType) => {
    const config = displayFixture(); config.page_type = pageType;
    const id = (await create(config)).body.data.id;
    expect((await enable(id, 0, 1, { page: pageType })).status).toBe(200);
    const oversized = structuredClone(config);
    oversized.skus.push(...["paid.year", "paid.month"].map((productId) => ({ ...config.skus[0], product_id: productId, is_default: false, trial: null })));
    await db.prepare("UPDATE subscription_display_config SET body = CAST(? AS text)::jsonb WHERE id = ?").bind(JSON.stringify(oversized), id).run();
    expect((await call("/admin/subscription-configs/" + id)).body.data.body).toEqual(oversized);
    const list = (await call("/admin/subscription-configs")).body;
    catalogLoader.mockClear();
    expect(await enable(id, 1, 1, { page: pageType })).toMatchObject({ status: 422,
      body: { error: { code: "VALIDATION_ERROR", fields: [{ path: "skus", message: "At most 3 display SKUs are allowed." }] } } });
    expect(catalogLoader).not.toHaveBeenCalled();
    expect((await call("/admin/subscription-configs")).body).toEqual(list);
    expect(await publicConfig({ type: pageType })).toMatchObject({ status: 503, body: { error: { code: "SUBSCRIPTION_CONFIG_UNAVAILABLE" } } });
    expect((await enable(null, 1, null, { page: pageType })).status).toBe(200);
    expect((await publicConfig({ type: pageType })).body.data).toBeNull();
    expect((await update(id, config)).status).toBe(200);
    expect((await enable(id, 2, 2, { page: pageType })).status).toBe(200);
    expect((await publicConfig({ type: pageType })).body.data.skus).toEqual(config.skus);
  });

  it("uses existing live Admin auth for both roles and never opens writes to an App user", async () => {
    expect((await create(displayFixture(), crypto.randomUUID(), { token: null })).status).toBe(401);
    expect((await create(displayFixture(), crypto.randomUUID(), { token: "invalid" })).status).toBe(401);
    expect((await create()).status).toBe(201);
    expect((await create(displayFixture(), crypto.randomUUID(), { token: supervisor })).status).toBe(201);
    await db.prepare("UPDATE admin_user SET status = 'disabled' WHERE id = 'operator'").run();
    try { expect((await create()).status).toBe(401); }
    finally { await db.prepare("UPDATE admin_user SET status = 'active' WHERE id = 'operator'").run(); }
  });

  it("creates disabled configurations and returns success/null only when a page has none active", async () => {
    expect((await publicConfig()).body).toEqual({ success: true, data: null });
    const created = await create();
    expect(created.status).toBe(201);
    expect(created.body.data.enabled).toBe(false);
    const list = await call("/admin/subscription-configs");
    expect(list.body.data.items).toHaveLength(1);
    expect(list.body.data.active).toEqual([
      { page_type: "page", config_id: null, active_revision: 0 }, { page_type: "modal", config_id: null, active_revision: 0 },
    ]);
    const response = await publicConfig();
    expect(response.body.data).toBeNull();
    expect(response.headers.get("Cache-Control")).toBe("no-store");
  });

  it("replays creation with a stable result even when Apple later fails, and rejects changed payloads", async () => {
    const requestId = crypto.randomUUID();
    const first = await create(displayFixture(), requestId);
    catalogLoader.mockRejectedValue(new SubscriptionConfigError("CATALOG_UNAVAILABLE", "Unavailable."));
    const retry = await create(displayFixture(), requestId);
    expect(retry).toMatchObject({ status: 201, body: first.body });
    expect(catalogLoader).toHaveBeenCalledTimes(1);
    expect((await create({ ...displayFixture(), name: "different" }, requestId)).body.error?.code).toBe("IDEMPOTENCY_CONFLICT");
    expect((await call("/admin/subscription-configs")).body.data.items).toHaveLength(1);
  });

  it("keeps request ID ownership and mutation status scoped to the administrator", async () => {
    const requestId = crypto.randomUUID();
    const first = await create(displayFixture(), requestId);
    const status = await call("/admin/subscription-config-mutations/" + requestId);
    expect(status.body.data).toMatchObject({ status: "succeeded", http_status: 201, response: first.body });
    expect((await call("/admin/subscription-config-mutations/" + requestId, "GET", undefined, { token: supervisor })).status).toBe(403);
    expect((await create(displayFixture(), requestId, { token: supervisor })).status).toBe(409);
    expect((await call("/admin/subscription-config-mutations/" + crypto.randomUUID())).body.data.status).toBe("unknown");
  });

  it("records confirmed validation failures without partial writes and allows safe status reconciliation", async () => {
    const requestId = crypto.randomUUID();
    const config = displayFixture(); config.cta = "Try {price}";
    const response = await create(config, requestId);
    expect(response.status).toBe(422);
    expect(response.body.error?.fields).toBeDefined();
    const status = await call("/admin/subscription-config-mutations/" + requestId);
    expect(status.body.data).toMatchObject({ status: "failed", http_status: 422, response: response.body });
    expect((await call("/admin/subscription-configs")).body.data.items).toEqual([]);
    expect(catalogLoader).not.toHaveBeenCalled();
  });

  it("enables atomically, keeps Page and Modal independent, and hides internal/retained data publicly", async () => {
    const pageConfig = displayFixture(); pageConfig.trial_enabled = false; pageConfig.name = "Internal-only name";
    const page = (await create(pageConfig)).body.data;
    const modal = (await create({ ...displayFixture(), page_type: "modal" })).body.data;
    expect((await enable(page.id)).status).toBe(200);
    expect((await enable(modal.id, 0, 1, { page: "modal" })).status).toBe(200);
    const publicPage = await publicConfig();
    expect(publicPage.body.data.config_id).toBe(page.id);
    expect(publicPage.body.data).not.toHaveProperty("name");
    expect(publicPage.body.data).not.toHaveProperty("updated_by");
    expect(publicPage.body.data).not.toHaveProperty("scope");
    expect(publicPage.body.data.skus[0].trial).toBeNull();
    expect(publicPage.body.data.trial_toggle_text).toBe("");
    expect((await call("/admin/subscription-configs/" + page.id)).body.data.body.skus[0].trial).not.toBeNull();
    expect((await enable(null, 1)).status).toBe(200);
    expect((await publicConfig()).body.data).toBeNull();
    expect((await publicConfig({ type: "modal" })).body.data.config_id).toBe(modal.id);
  });

  it("concurrent replacements using the same confirmed active revision cannot overwrite each other", async () => {
    const a = (await create()).body.data;
    const b = (await create({ ...displayFixture(), name: "second" })).body.data;
    const results = await Promise.all([enable(a.id), enable(b.id)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    const list = await call("/admin/subscription-configs");
    expect(list.body.data.items.filter((i: { enabled: boolean }) => i.enabled)).toHaveLength(1);
    expect(list.body.data.active.find((i: { page_type: string }) => i.page_type === "page").active_revision).toBe(1);
  });

  it("duplicate concurrent requests create only one configuration and return the same result", async () => {
    const requestId = crypto.randomUUID();
    const results = await Promise.all([create(displayFixture(), requestId), create(displayFixture(), requestId)]);
    expect(results.map((r) => r.status)).toEqual([201, 201]);
    expect(results[0].body).toEqual(results[1].body);
    expect((await call("/admin/subscription-configs")).body.data.items).toHaveLength(1);
  });

  it("saving enabled content preserves activation and rejects stale editors or direct page-type moves", async () => {
    const id = (await create()).body.data.id;
    await enable(id);
    const changed = displayFixture(); changed.name = "New content"; changed.skus[0].cta = "BUY";
    const saved = await update(id, changed);
    expect(saved.status).toBe(200);
    expect(saved.body.data).toMatchObject({ enabled: true, revision: 2 });
    expect((await publicConfig()).body.data.skus[0].cta).toBe("BUY");
    expect((await update(id, displayFixture())).status).toBe(409);
    expect((await update(id, { ...changed, page_type: "modal" }, 2)).body.error?.code).toBe("ACTIVE_PAGE_TYPE_IMMUTABLE");
    await enable(null, 1);
    const moved = await update(id, { ...changed, page_type: "modal" }, 2);
    expect(moved.body.data).toMatchObject({ page_type: "modal", revision: 3, enabled: false });
    expect((await enable(id, 0, 3, { page: "modal" })).status).toBe(200);
  });

  it("rechecks target content revision after catalog I/O so activation cannot approve unseen edits", async () => {
    const id = (await create()).body.data.id;
    let entered!: () => void; let release!: () => void;
    const started = new Promise<void>((resolve) => { entered = resolve; });
    const waiting = new Promise<void>((resolve) => { release = resolve; });
    catalogLoader.mockImplementationOnce(async () => { entered(); await waiting; return catalogFixture(); });
    const pending = enable(id);
    await started;
    expect((await update(id, { ...displayFixture(), name: "Edited during approval" })).status).toBe(200);
    release();
    expect((await pending).body.error?.code).toBe("CONFIG_CONFLICT");
    expect((await publicConfig()).body.data).toBeNull();
  });

  it("checks entitlement admission in the transaction after external catalog validation", async () => {
    const id = (await create()).body.data.id;
    catalogLoader.mockImplementationOnce(async () => {
      await db.prepare("UPDATE billing_product SET active = 0 WHERE product_id = 'paid.week'").run();
      return catalogFixture();
    });
    expect((await enable(id)).body.error?.code).toBe("PRODUCT_NOT_ADMITTED");
    expect((await publicConfig()).body.data).toBeNull();
  });

  it.each(["approval", "allowlist", "mapping", "type"])("permits disabled preparation but blocks activation when %s is missing", async (missing) => {
    if (missing === "mapping") await db.prepare("DELETE FROM billing_product WHERE product_id = 'paid.week'").run();
    if (missing === "type") await db.prepare("UPDATE billing_product SET product_type = 'non_consumable' WHERE product_id = 'paid.week'").run();
    const scopedEnv = { ...env,
      ...(missing === "approval" ? { SUBSCRIPTION_DISPLAY_PRODUCT_IDS: "lifetime,trial.week" } : {}),
      ...(missing === "allowlist" ? { APPLE_IAP_PRODUCT_IDS: "lifetime,trial.week" } : {}),
    };
    const created = await create(displayFixture(), crypto.randomUUID(), { env: scopedEnv });
    expect(created.status).toBe(201);
    expect((await enable(created.body.data.id, 0, 1, { env: scopedEnv })).body.error?.code).toBe("PRODUCT_NOT_ADMITTED");
  });

  it("active edits cannot introduce an unapproved SKU or silently lose the last known configuration", async () => {
    const id = (await create()).body.data.id;
    await enable(id);
    const config = displayFixture(); config.skus[0].product_id = "new.week";
    const catalog = catalogFixture(); catalog.products[0].product_id = "new.week";
    catalogLoader.mockResolvedValue(catalog);
    expect((await update(id, config)).body.error?.code).toBe("PRODUCT_NOT_ADMITTED");
    expect((await publicConfig()).body.data.skus[0].product_id).toBe("paid.week");
    expect((await call("/admin/subscription-configs/" + id)).body.data.revision).toBe(1);
  });

  it("catalog outages never become empty/deleted products, and disabling still works offline", async () => {
    const id = (await create()).body.data.id;
    await enable(id);
    catalogLoader.mockRejectedValue(new SubscriptionConfigError("CATALOG_NOT_CONFIGURED", "Catalog is unavailable."));
    expect((await call("/admin/subscription-products?type=subscription")).status).toBe(503);
    expect((await update(id, { ...displayFixture(), name: "Cannot save" })).status).toBe(503);
    expect((await call("/admin/subscription-configs/" + id)).body.data.body.name).toBe("Test configuration");
    expect((await publicConfig()).status).toBe(200);
    expect((await enable(null, 1)).status).toBe(200);
    expect((await publicConfig()).body.data).toBeNull();
  });

  it("does not sell revoked admission from a stale active configuration or serve Apple products to Android", async () => {
    const id = (await create()).body.data.id;
    await enable(id);
    await db.prepare("UPDATE billing_product SET active = 0 WHERE product_id = 'paid.week'").run();
    expect((await publicConfig()).status).toBe(503);
    const google = await publicConfig({ platform: "google", env: { ...env, APPLE_IAP_BUNDLE_ID: undefined } });
    expect(google.body).toEqual({ success: true, data: null });
  });

  it("cannot reference another page, App or deployment scope", async () => {
    const id = (await create()).body.data.id;
    expect((await enable(id, 0, 1, { page: "modal" })).status).toBe(404);
    for (const other of [{ ...env, APP_ENVIRONMENT: "production" as const }, { ...env, APPLE_IAP_BUNDLE_ID: "other.app" }]) {
      expect((await call("/admin/subscription-configs/" + id, "GET", undefined, { env: other })).status).toBe(404);
      expect((await enable(id, 0, 1, { env: other })).status).toBe(404);
      expect((await publicConfig({ env: other })).body.data).toBeNull();
    }
    await expect(db.prepare("INSERT INTO subscription_display_active (scope, page_type, config_id) VALUES ('other:app', 'page', ?)").bind(id).run()).rejects.toThrow();
  });

  it("configuration removal is display-only and never deletes historical billing mappings", async () => {
    const id = (await create()).body.data.id;
    await enable(id);
    const config = displayFixture(); config.skus.pop();
    expect((await update(id, config)).status).toBe(200);
    expect((await publicConfig()).body.data.skus).toHaveLength(1);
    expect(await db.prepare("SELECT product_id FROM billing_product WHERE product_id = 'lifetime'").first()).not.toBeNull();
    expect((await enable(null, 1)).status).toBe(200);
    expect(await db.prepare("SELECT COUNT(*) AS count FROM billing_product").first("count")).toBe(3);
  });

  it("rolls back the configuration and result together when persistence fails, then safely retries the original ID", async () => {
    await db.exec(`CREATE FUNCTION test_subscription_result_failure() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'result storage unavailable'; END $$;
      CREATE TRIGGER test_subscription_result_failure BEFORE UPDATE ON subscription_display_mutation
      FOR EACH ROW EXECUTE FUNCTION test_subscription_result_failure();`);
    const requestId = crypto.randomUUID();
    try {
      expect((await create(displayFixture(), requestId)).status).toBe(503);
      expect((await call("/admin/subscription-configs")).body.data.items).toEqual([]);
      expect((await call("/admin/subscription-config-mutations/" + requestId)).body.data.status).toBe("unknown");
    } finally { await db.exec("DROP TRIGGER test_subscription_result_failure ON subscription_display_mutation; DROP FUNCTION test_subscription_result_failure();"); }
    expect((await create(displayFixture(), requestId)).status).toBe(201);
  });

  it("leaves unrelated API contracts and Admin writes untouched by new feature middleware", async () => {
    const legacy = await call("/admin/app-config/stage1-regression", "PATCH", { value: "x".repeat(270_000) });
    expect(legacy.status).toBe(200);
    expect(legacy.headers.get("Cache-Control")).toBeNull();
    expect((await call("/health", "GET", undefined, { token: null })).body).toEqual({ status: "ok" });
    const response = await create({ ...displayFixture(), name: "x".repeat(270_000) });
    expect(response.status).toBe(413);
    expect((await publicConfig({ type: "invalid" })).status).toBe(422);
    expect((await call("/admin/subscription-products?type=bad")).status).toBe(422);
  });
});
