import { hashPassword } from "@kando/auth-core";
import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type { DatabaseStatement } from "../db/database";
import type { Env } from "../env";
import app from "../index";
import { PGliteDatabase } from "../test-support/pglite-database";

const rule = {
  platform: "iOS",
  min_supported_version: "1.0.1",
  recommended_version: "1.0.2",
  force_update: true,
  store_url: "https://apps.apple.com/app/id6793017224",
  recommended_update_message: "A newer version is available.",
  forced_update_message: "Update to continue.",
  status: "enabled",
};

describe("version control in a shared PostgreSQL database", () => {
  let db: PGliteDatabase;
  let token: string;

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("../db/postgres/migrations/0000_business_schema.sql", import.meta.url), "utf8"));
    await db.prepare("INSERT INTO admin_user VALUES ('version-admin', 'version@example.com', ?, 'operator', 'active', '2026-09-08')")
      .bind(await hashPassword("version-test-password")).run();
    const login = await app.request("/api/v1/admin/auth/login", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "version@example.com", password: "version-test-password" }),
    }, env());
    expect(login.status).toBe(200);
    token = (await login.json() as { data: { access_token: string } }).data.access_token;
  });
  afterAll(async () => { await db?.close(); });
  beforeEach(async () => { await db.exec("DELETE FROM app_config"); });

  function env(environment: Env["APP_ENVIRONMENT"] = "development"): Env {
    return { DB: db, APP_ENVIRONMENT: environment, CACHE_KV: {} as KVNamespace, JWT_SECRET: "version-control-test-secret" };
  }
  function admin(environment: Env["APP_ENVIRONMENT"], path: string, body?: unknown, database: Env["DB"] = db) {
    return app.request(`/api/v1/admin${path}`, {
      method: body === undefined ? "GET" : "PATCH",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }, { ...env(environment), DB: database });
  }
  function publicConfig(environment: Env["APP_ENVIRONMENT"], platform = "ios", database: Env["DB"] = db) {
    return app.request(`/api/v1/app-config?platform=${platform}&environment=production`, {}, { ...env(environment), DB: database });
  }
  async function seed(key: string, value: unknown) {
    await db.prepare("INSERT INTO app_config (key, value, updated_at) VALUES (?, ?, ?)")
      .bind(key, typeof value === "string" ? value : JSON.stringify(value), "2026-09-08").run();
  }

  it("keeps dev edits and disabling separate from production because both Workers share the same database", async () => {
    const saved = await Promise.all([
      admin("production", "/app-versions/iOS", rule),
      admin("development", "/app-versions/iOS", { ...rule, recommended_version: "2.0.0", min_supported_version: "2.0.0", environment: "production" }),
    ]);
    expect(saved.map((response) => response.status)).toEqual([200, 200]);
    expect(await (await publicConfig("production")).json()).toMatchObject({ data: { upgrade_prompt: { latest_version: "1.0.2", min_version: "1.0.1", force_update: true } } });
    expect(await (await publicConfig("development")).json()).toMatchObject({ data: { upgrade_prompt: { latest_version: "2.0.0" } } });
    expect(await (await admin("development", "/app-versions")).json()).toMatchObject({ data: { environment: "development", items: expect.arrayContaining([expect.objectContaining({ recommended_version: "2.0.0" })]) } });

    await admin("development", "/app-versions/iOS", { ...rule, status: "disabled" });
    expect(await (await publicConfig("development")).json()).toMatchObject({ data: { upgrade_prompt: null } });
    expect(await (await publicConfig("production")).json()).toMatchObject({ data: { upgrade_prompt: { force_update: true } } });
  });

  it("maps Android and Google to one isolated rule without crossing iOS or environments", async () => {
    await admin("production", "/app-versions/iOS", rule);
    const storeUrl = "https://play.google.com/store/apps/details?id=com.cardai.tcg";
    await admin("production", "/app-versions/Google", { ...rule, store_url: storeUrl, status: "disabled" });
    await admin("development", "/app-versions/Google", {
      ...rule,
      min_supported_version: "2.0.0",
      recommended_version: "2.1.0",
      store_url: "https://play.google.com/store/apps/details?id=dev.example",
    });
    const google = await (await publicConfig("production", "google")).json();
    const android = await (await publicConfig("production", "android")).json();
    expect(android).toEqual(google);
    expect(google).toMatchObject({ data: { upgrade_prompt: null, app_store_url: storeUrl } });
    expect(await (await publicConfig("production")).json()).toMatchObject({ data: { upgrade_prompt: { force_update: true } } });
    expect(await (await publicConfig("development", "android")).json()).toMatchObject({ data: {
      upgrade_prompt: { latest_version: "2.1.0", min_version: "2.0.0", force_update: true },
      app_store_url: "https://play.google.com/store/apps/details?id=dev.example",
    } });
  });

  it("reads saved iOS and Android rules without reusing stale ordinary selects", async () => {
    await admin("production", "/app-versions/iOS", rule);
    await admin("development", "/app-versions/iOS", { ...rule, recommended_version: "1.0.3" });
    await admin("production", "/app-versions/Google", {
      ...rule,
      platform: "Google",
      store_url: "https://play.google.com/store/apps/details?id=old.example",
    });
    const staleReads = await databaseWithStaleOrdinaryAppConfigReads(db);
    const iosProduction = { ...rule, recommended_version: "1.1.0" };
    const iosDevelopment = { ...rule, min_supported_version: "2.0.0", recommended_version: "2.1.0" };
    const googleProduction = {
      ...rule,
      platform: "Google",
      min_supported_version: "3.0.0",
      recommended_version: "3.1.0",
      store_url: "https://play.google.com/store/apps/details?id=com.cardai.tcg",
    };

    expect((await admin("production", "/app-versions/iOS", iosProduction, staleReads)).status).toBe(200);
    expect((await admin("development", "/app-versions/iOS", iosDevelopment, staleReads)).status).toBe(200);
    expect((await admin("production", "/app-versions/Google", googleProduction, staleReads)).status).toBe(200);

    const productionList = await (await admin("production", "/app-versions", undefined, staleReads)).json();
    const developmentList = await (await admin("development", "/app-versions", undefined, staleReads)).json();
    expect(productionList).toMatchObject({ data: { environment: "production", items: expect.arrayContaining([
      expect.objectContaining({ platform: "iOS", recommended_version: "1.1.0" }),
      expect.objectContaining({ platform: "Google", recommended_version: "3.1.0" }),
    ]) } });
    expect(developmentList).toMatchObject({ data: { environment: "development", items: expect.arrayContaining([
      expect.objectContaining({ platform: "iOS", recommended_version: "2.1.0" }),
      expect.objectContaining({ platform: "Google", status: "disabled" }),
    ]) } });

    expect(await (await publicConfig("production", "ios", staleReads)).json()).toMatchObject({
      data: { upgrade_prompt: { latest_version: "1.1.0" } },
    });
    const google = await (await publicConfig("production", "google", staleReads)).json();
    expect(await (await publicConfig("production", "android", staleReads)).json()).toEqual(google);
    expect(google).toMatchObject({ data: { upgrade_prompt: { latest_version: "3.1.0" } } });
    expect(await (await publicConfig("development", "ios", staleReads)).json()).toMatchObject({
      data: { upgrade_prompt: { latest_version: "2.1.0" } },
    });
  });

  it("never falls back to shared or other-environment rules because an uninitialized environment must be configured explicitly", async () => {
    await seed("admin.app_version.ios", rule);
    await seed("upgrade_prompt", { latest_version: "9.0.0", force_update: true });
    await seed("app_store_url", "https://example.com/shared");
    await seed("admin.app_version.production.ios", rule);
    expect((await publicConfig("development")).status).toBe(503);
    expect((await publicConfig("production")).status).toBe(200);
  });

  it("fails when the trusted Worker environment is missing instead of choosing production or trusting request input", async () => {
    const missingEnv = { ...env(), APP_ENVIRONMENT: undefined };
    const publicResponse = await app.request("/api/v1/app-config?environment=production", {}, missingEnv);
    const adminResponse = await app.request("/api/v1/admin/app-versions", { headers: { Authorization: `Bearer ${token}` } }, missingEnv);
    expect(publicResponse.status).toBe(503);
    expect(adminResponse.status).toBe(503);
  });

  it("prevents generic config writes from bypassing environment isolation and version validation", async () => {
    await admin("production", "/app-versions/iOS", rule);
    for (const key of ["admin.app_version.production.ios", "admin.app_version.development.ios", "admin.app_version.ios", "upgrade_prompt", "app_store_url"]) {
      expect((await admin("development", `/app-config/${key}`, { value: JSON.stringify({ ...rule, status: "disabled" }) })).status).toBe(422);
    }
    const list = JSON.stringify(await (await admin("development", "/app-config")).json());
    expect(list).not.toContain("admin.app_version.production.ios");
    expect(await (await publicConfig("production")).json()).toMatchObject({ data: { upgrade_prompt: { force_update: true } } });
  });

  it.each([
    { min_supported_version: "2.0.0", recommended_version: "1.0.1" },
    { store_url: "" },
    { store_url: "javascript:alert(1)" },
    { force_update: "true" },
    { status: "invalid" },
    { min_supported_version: "1.0.1+125" },
  ])("rejects unusable update rules so a saved mandatory update has a valid target: %j", async (invalid) => {
    expect((await admin("development", "/app-versions/iOS", { ...rule, ...invalid })).status).toBe(422);
    expect((await db.query("SELECT key FROM app_config")).rows).toHaveLength(0);
  });

  it("does not cache version decisions because administrators must be able to change update requirements", async () => {
    await admin("production", "/app-versions/iOS", rule);
    const response = await publicConfig("production");
    expect(response.headers.get("Cache-Control")).toContain("no-store");
  });

  it("surfaces corrupt scoped configuration instead of silently allowing unsupported clients", async () => {
    await seed("admin.app_version.development.ios", "{broken");
    expect((await publicConfig("development")).status).toBe(503);
    expect((await admin("development", "/app-versions")).status).toBe(503);
  });

  it("retires editable release copy while preserving fixed prompts for older clients", async () => {
    await seed("admin.app_version.development.ios", rule);
    const listed = await (await admin("development", "/app-versions")).json();
    expect(JSON.stringify(listed)).not.toContain("recommended_update_message");
    expect(JSON.stringify(listed)).not.toContain("forced_update_message");
    const response = await admin("development", "/app-versions/iOS", rule);
    expect(response.status).toBe(200);
    const saved = await db.prepare("SELECT value FROM app_config WHERE key = 'admin.app_version.development.ios'").first<{ value: string }>();
    expect(JSON.parse(saved!.value)).not.toHaveProperty("recommended_update_message");
    expect(JSON.parse(saved!.value)).not.toHaveProperty("forced_update_message");
    expect(await (await publicConfig("development")).json()).toMatchObject({ data: { upgrade_prompt: {
      force_update: true, title: "Update Now",
      message: "New update available! Tap to upgrade",
      forced_message: "New update available! Tap to upgrade",
    } } });
  });
});

async function databaseWithStaleOrdinaryAppConfigReads(database: Env["DB"]): Promise<Env["DB"]> {
  const stale = await database.prepare(`
    SELECT key, value, updated_by, updated_at
    FROM app_config
    ORDER BY key ASC
  `).all();
  const wrap = (statement: DatabaseStatement): DatabaseStatement => new Proxy(statement, {
    get(target, property, receiver) {
      if (property === "bind") {
        return (...values: unknown[]) => wrap(target.bind(...values));
      }
      if (property === "all") {
        return async () => stale;
      }
      const value = Reflect.get(target, property, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });

  return new Proxy(database, {
    get(target, property, receiver) {
      if (property === "prepare") {
        return (query: string) => query.includes("FROM app_config") && !query.includes("CURRENT_TIMESTAMP")
          ? wrap(target.prepare(query))
          : target.prepare(query);
      }
      const value = Reflect.get(target, property, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}
