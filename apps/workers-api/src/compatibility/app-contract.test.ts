import { signAccessToken } from "@kando/auth-core";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

import { app } from "../app";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";

const directory = path.dirname(fileURLToPath(import.meta.url));
const secret = "local-compatibility-fixture-only";
const folderId = "11111111-1111-4111-8111-111111111111";
const reservationId = "22222222-2222-4222-8222-222222222222";
const cases: Record<string, unknown> = {};
let db: PGliteDatabase;
let ownerToken: string;
let otherToken: string;

function env(environment: Env["APP_ENVIRONMENT"] = "production"): Env {
  return {
    DB: db, JWT_SECRET: secret, APP_ENVIRONMENT: environment,
    CACHE_KV: new Proxy({} as KVNamespace, { get() { throw new Error("Compatibility fixtures must not use a remote cache"); } }),
  };
}

async function call(name: string, route: string, status: number, options: {
  method?: string; body?: unknown; token?: string; headers?: Record<string, string>;
  environment?: Env["APP_ENVIRONMENT"];
} = {}) {
  const method = options.method ?? "GET";
  const response = await app.request("/api/v1" + route, {
    method,
    headers: {
      ...(options.token ? { Authorization: "Bearer " + options.token } : {}),
      ...(options.body === undefined ? {} : { "Content-Type": "application/json" }),
      ...options.headers,
    },
    ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
  }, env(options.environment));
  const body = await response.json() as Record<string, any>;
  expect(response.status, name).toBe(status);
  expect(response.headers.get("X-Request-ID"), name).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
  cases[name] = { method, route, requestBody: options.body ?? null, status, body };
  return { response, body };
}

async function versionRule(environment: string, platform: string, latest: string, enabled = true) {
  await db.prepare("INSERT INTO app_config (key,value,updated_at) VALUES (?,?,?) ON CONFLICT (key) DO UPDATE SET value = excluded.value")
    .bind("admin.app_version." + environment + "." + platform, JSON.stringify({
      min_supported_version: "1.0.4", recommended_version: latest, force_update: true,
      status: enabled ? "enabled" : "disabled",
      store_url: platform === "ios" ? "https://apps.apple.com/app/id6793017224" : "https://play.google.com/store/apps/details?id=com.cardai.tcg",
    }), "2026-10-09").run();
}

describe("frozen App contracts against current PostgreSQL-backed API", () => {
  beforeAll(async () => {
    vi.spyOn(console, "info").mockImplementation(() => {});
    db = await PGliteDatabase.create();
    for (const name of ["0000_business_schema.sql", "0006_mutation_lock.sql"]) {
      await db.exec(readFileSync(path.join(directory, "../db/postgres/migrations", name), "utf8"));
    }
    for (const id of ["compat-owner", "compat-other"]) {
      await db.prepare("INSERT INTO anonymous_account (id,device_id,created_at) VALUES (?,?,?)").bind(id, id + "-device", "2026-10-09").run();
      await db.prepare("INSERT INTO session (id,owner_type,owner_id,refresh_token,expires_at,created_at) VALUES (?,'anonymous',?,?,?,?)")
        .bind(id + "-session", id, id + "-refresh", "2099-01-01T00:00:00.000Z", "2026-10-09").run();
    }
    ownerToken = await signAccessToken({ owner_type: "anonymous", owner_id: "compat-owner", session_id: "compat-owner-session" }, secret);
    otherToken = await signAccessToken({ owner_type: "anonymous", owner_id: "compat-other", session_id: "compat-other-session" }, secret);
  }, 30_000);
  afterAll(async () => {
    await db?.close();
    vi.restoreAllMocks();
    if (process.env.APP_COMPATIBILITY_OUTPUT) {
      writeFileSync(process.env.APP_COMPATIBILITY_OUTPUT, JSON.stringify({ schemaVersion: 1, producer: "current-hono-api", cases }, null, 2), { flag: "wx" });
    }
  });

  it("C01 preserves old upgrade fields and isolates platform/environment rather than forcing old builds out", async () => {
    await versionRule("production", "ios", "1.0.4");
    await versionRule("production", "google", "1.0.4", false);
    await versionRule("development", "ios", "2.0.0");
    const ios = await call("config-ios", "/app-config?platform=ios", 200);
    expect(ios.body.data.upgrade_prompt).toMatchObject({ latest_version: "1.0.4", min_version: "1.0.4", force_update: true, title: expect.any(String), message: expect.any(String), forced_message: expect.any(String) });
    expect(ios.body.data.upgrade_prompt.title.trim()).not.toBe("");
    expect(ios.response.headers.get("Cache-Control")).toBe("no-store");
    const google = await call("config-google", "/app-config?platform=google", 200);
    expect(google.body.data.upgrade_prompt).toBeNull();
    expect(google.body.data.app_store_url).toContain("play.google.com");
    const development = await call("config-development", "/app-config?platform=ios", 200, { environment: "development" });
    expect(development.body.data.upgrade_prompt.latest_version).toBe("2.0.0");
    await versionRule("production", "ios", "1.0.5");
    const newer = await call("config-recommended", "/app-config?platform=ios", 200);
    expect(newer.body.data.upgrade_prompt.min_version).toBe("1.0.4");
  });

  it("C02/C09 keeps unauthenticated errors independent of optional request IDs", async () => {
    const legacy = await call("folders-unauthorized", "/portfolio/folders", 401);
    const invalid = await call("folders-invalid-request-id", "/portfolio/folders", 401, { headers: { "X-Request-ID": "old-client-non-uuid" } });
    const valid = await call("folders-valid-request-id", "/portfolio/folders", 401, { headers: { "X-Request-ID": reservationId } });
    expect(invalid.body).toEqual(legacy.body);
    expect(valid.body).toEqual(legacy.body);
    expect(valid.response.headers.get("X-Request-ID")).toBe(reservationId);
    expect(legacy.body.error.code).toBe("UNAUTHORIZED");
  });

  it("C04/C13 preserves a new writer's folder for old list/rename/delete operations without crossing owners", async () => {
    const create = { method: "POST", token: ownerToken, body: { name: "Shared collection" }, headers: { "Idempotency-Key": folderId } };
    const created = await call("folder-created", "/portfolio/folders", 201, create);
    expect(created.body.data).toMatchObject({ id: folderId, name: "Shared collection", is_default: false });
    const replay = await call("folder-replay", "/portfolio/folders", 200, create);
    expect(replay.body).toEqual(created.body);
    await call("folder-conflict", "/portfolio/folders", 409, { ...create, body: { name: "Different operation" } });
    const oldRead = await call("folders-new-write", "/portfolio/folders", 200, { token: ownerToken });
    expect(oldRead.body.data.items).toHaveLength(1);
    await call("folder-foreign-rename", "/portfolio/folders/" + folderId, 404, { method: "PATCH", token: otherToken, body: { name: "Old client edit" } });
    const renamed = await call("folder-old-rename", "/portfolio/folders/" + folderId, 200, { method: "PATCH", token: ownerToken, body: { name: "Old client edit" } });
    expect(renamed.body.data.name).toBe("Old client edit");
    const newRead = await call("folders-after-old-edit", "/portfolio/folders", 200, { token: ownerToken });
    expect(newRead.body.data.items[0].name).toBe("Old client edit");
    await call("folder-old-delete", "/portfolio/folders/" + folderId, 200, { method: "DELETE", token: ownerToken });
    expect((await call("folders-after-old-delete", "/portfolio/folders", 200, { token: ownerToken })).body.data.items).toEqual([]);
    expect(await db.prepare("SELECT count(*) AS count FROM portfolio_folder").first<number>("count")).toBe(0);
  });

  it("C06 keeps lifetime Free quota and request replay semantics without trusting client Premium claims", async () => {
    const fresh = await call("quota-fresh", "/scan/quota", 200, { token: ownerToken });
    expect(fresh.body.data).toEqual({ access: "free", limit: 10, reserved: 0, consumed: 0, remaining: 10, unlimited: false });
    const options = { method: "POST", token: ownerToken, body: { request_id: reservationId }, headers: { "Idempotency-Key": reservationId } };
    const reserved = await call("quota-reserved", "/scan/quota/reserve", 200, options);
    expect(reserved.body.data.quota).toMatchObject({ reserved: 1, consumed: 0, remaining: 9 });
    expect((await call("quota-replayed", "/scan/quota/reserve", 200, options)).body).toEqual(reserved.body);
    const denied = await call("quota-premium-unverified", "/scan/quota", 409, { token: ownerToken, headers: { "X-Local-Premium-State": "verified" } });
    expect(denied.body.error.code).toBe("ENTITLEMENT_SYNC_REQUIRED");
    expect(await db.prepare("SELECT count(*) AS count FROM scan_quota_request").first<number>("count")).toBe(1);
  });
});
