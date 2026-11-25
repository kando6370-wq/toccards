import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword } from "@kando/auth-core";
import { Hono } from "hono";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { adminRoutes } from "./routes";

describe("Admin platform account targeting on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;
  let token: string;
  let operatorToken: string;
  const app = new Hono<{ Bindings: Env }>().route("/admin", adminRoutes);

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    for (const name of ["0000_business_schema.sql", "0018_platform_account_isolation.sql"]) {
      await db.exec(readFileSync(new URL(`../db/postgres/migrations/${name}`, import.meta.url), "utf8"));
    }
    const now = "2026-11-05T00:00:00.000Z";
    const passwordHash = await hashPassword("admin-platform-password");
    await db.prepare(`
      INSERT INTO admin_user (id, email, password_hash, role, status, created_at)
      VALUES ('admin-platform', 'admin@example.com', ?, 'super_admin', 'active', ?),
        ('operator-platform', 'operator@example.com', ?, 'operator', 'active', ?)
    `).bind(passwordHash, now, passwordHash, now).run();
    await db.exec(`
      INSERT INTO "user" (id, email, password_hash, display_name, created_at, updated_at, status)
      VALUES ('base-user', 'user@example.com', NULL, NULL, '${now}', '${now}', 'active');
      INSERT INTO platform_account (id, user_id, platform, status, created_at, updated_at)
      VALUES
        ('ios-space', 'base-user', 'ios', 'active', '${now}', '${now}'),
        ('android-space', 'base-user', 'android', 'active', '${now}', '${now}');
      INSERT INTO session (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES
        ('ios-session', 'user', 'ios-space', 'ios-refresh', '2099-01-01T00:00:00.000Z', '${now}', 'ios', 'base-user'),
        ('android-session', 'user', 'android-space', 'android-refresh', '2099-01-01T00:00:00.000Z', '${now}', 'android', 'base-user');
    `);
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "admin-platform-test", APP_ENVIRONMENT: "development" };
    const login = await app.request("/admin/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "admin@example.com", password: "admin-platform-password" }),
    }, env);
    token = ((await login.json()) as { data: { access_token: string } }).data.access_token;
    const operatorLogin = await app.request("/admin/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "operator@example.com", password: "admin-platform-password" }),
    }, env);
    operatorToken = ((await operatorLogin.json()) as { data: { access_token: string } }).data.access_token;
  }, 30_000);

  afterAll(async () => db.close());

  it("lets operators reach installations after the first 100 groups and filter by every country in scope", async () => {
    await db.exec(`
      INSERT INTO app_installation (installation_id, uid, country_code, platform, first_seen_at, last_seen_at)
      SELECT 'install-' || n, lpad(LEAST(n, 105)::text, 3, '0'), CASE WHEN n <= 100 THEN 'US' ELSE 'JP' END,
        'iOS', '2026-11-05', '2026-11-05' FROM generate_series(1, 106) n;
      INSERT INTO app_installation (installation_id, uid, country_code, platform, first_seen_at, last_seen_at)
      VALUES ('other-platform', NULL, 'FR', 'Android', '2026-11-05', '2026-11-05'),
        ('other-date', NULL, 'CA', 'iOS', '2026-11-06', '2026-11-06');
    `);
    const headers = { Authorization: `Bearer ${operatorToken}` };
    const scope = "environment=development&platform=ios&date_from=2026-11-05&date_to=2026-11-05";
    async function get(suffix: string) {
      const response = await app.request(`/admin/analytics/installations${suffix}`, { headers }, env);
      expect(response.status).toBe(200);
      return (await response.json() as { data: { total: number; rows: { uid: string }[]; countries?: string[] } }).data;
    }
    const first = await get(`?${scope}&page_size=100`);
    expect(first).toMatchObject({ total: 105, summary: { total_installations: 106, countries: 2 } });
    expect(first.rows).toHaveLength(100);
    expect((await get(`?${scope}&page_size=100&page=2`)).rows.map((row) => row.uid))
      .toEqual(["101", "102", "103", "104", "105"]);
    expect((await get(`?${scope}&page_size=8&page=14`)).rows).toMatchObject([{ uid: "105", country: "JP", installs: 2 }]);
    expect(await get(`?${scope}&page_size=8&page=15`)).toMatchObject({ total: 105, rows: [] });
    expect(await get(`?${scope}&country=JP`)).toMatchObject({ total: 5, summary: { total_installations: 6 } });
    expect(await get(`/options?${scope}&country=US`)).toEqual({ countries: ["JP", "US"] });
    expect(await get("/options?environment=production")).toEqual({ countries: [] });
    expect(await get("?environment=production")).toMatchObject({ total: 0, rows: [] });
    expect((await app.request("/admin/analytics/installations/options", {}, env)).status).toBe(401);
  });

  it("returns the platform data space and disables only that platform", async () => {
    const headers = { Authorization: `Bearer ${token}` };
    const detail = await app.request("/admin/users/user/ios-space", { headers }, env);
    expect(detail.status).toBe(200);
    expect((await detail.json()) as object).toMatchObject({
      data: {
        id: "ios-space",
        user_id: "base-user",
        platform: "ios",
        status: "active",
        base_user_status: "active",
      },
    });

    const forbidden = await app.request("/admin/users/user/ios-space/disable", {
      method: "PATCH",
      headers: { Authorization: `Bearer ${operatorToken}` },
    }, env);
    expect(forbidden.status).toBe(403);

    const disabled = await app.request("/admin/users/user/ios-space/disable", {
      method: "PATCH",
      headers,
    }, env);
    expect(disabled.status).toBe(200);
    expect(await db.prepare("SELECT status FROM platform_account WHERE id = 'ios-space'").first("status")).toBe("disabled");
    expect(await db.prepare("SELECT status FROM platform_account WHERE id = 'android-space'").first("status")).toBe("active");
    expect(await db.prepare("SELECT status FROM \"user\" WHERE id = 'base-user'").first("status")).toBe("active");
    expect(await db.prepare("SELECT revoked_at FROM session WHERE id = 'ios-session'").first("revoked_at")).not.toBeNull();
    expect(await db.prepare("SELECT revoked_at FROM session WHERE id = 'android-session'").first("revoked_at")).toBeNull();
  });
});
