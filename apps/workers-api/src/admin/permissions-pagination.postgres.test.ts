import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword } from "@kando/auth-core";
import { Hono } from "hono";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { adminRoutes } from "./routes";

type PermissionList = {
  success: boolean;
  data: { items: Array<{ id: string; role: string; permission_status: string }>; total: number; page: number; page_size: number };
};

describe("Admin permissions pagination on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;
  let token: string;
  const app = new Hono<{ Bindings: Env }>().route("/admin", adminRoutes);

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("../db/postgres/migrations/0000_business_schema.sql", import.meta.url), "utf8"));
    const passwordHash = await hashPassword("permission-test-password");
    for (let index = 0; index < 11; index += 1) {
      await db.prepare("INSERT INTO admin_user (id, email, password_hash, role, status, created_at) VALUES (?, ?, ?, ?, ?, ?)")
        .bind(`permission-${index}`, `user-${index}@example.com`, passwordHash, index === 0 ? "super_admin" : "operator", index % 2 === 0 ? "active" : "disabled", `2026-10-28T${String(index === 1 ? 0 : index).padStart(2, "0")}:00:00.000Z`).run();
    }
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "permissions-test", APP_ENVIRONMENT: "development" };
    const login = await app.request("/admin/auth/login", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "user-0@example.com", password: "permission-test-password" }),
    }, env);
    expect(login.status).toBe(200);
    token = ((await login.json()) as { data: { access_token: string } }).data.access_token;
  }, 30000);

  afterAll(async () => { await db?.close(); });

  async function list(query: string): Promise<PermissionList["data"]> {
    const response = await app.request(`/admin/permissions${query}`, { headers: { Authorization: `Bearer ${token}` } }, env);
    expect(response.status).toBe(200);
    return ((await response.json()) as PermissionList).data;
  }

  it("keeps every matching account reachable after the first page", async () => {
    const unfiltered = await list("");
    const first = await list("?page_size=8");
    const second = await list("?page_size=8&page=2");
    expect(unfiltered).toMatchObject({ total: 11, page: 1, page_size: 20 });
    expect(unfiltered.items).toHaveLength(11);
    expect(first).toMatchObject({ total: 11, page: 1, page_size: 8 });
    expect(first.items).toHaveLength(8);
    expect(second).toMatchObject({ total: 11, page: 2, page_size: 8 });
    expect(second.items.map((item) => item.id)).toEqual(["permission-2", "permission-0", "permission-1"]);
    const empty = await list("?page_size=8&page=99");
    expect(empty.total).toBe(11);
    expect(empty.items).toEqual([]);
  });

  it("counts with the same email and status filters as the returned page", async () => {
    const filtered = await list("?q=user-&status=disabled&page_size=2");
    expect(filtered.total).toBe(5);
    expect(filtered.items).toHaveLength(2);
    const exact = await list("?q=USER-1%40EXAMPLE.COM&status=disabled");
    expect(exact.total).toBe(1);
    expect(exact.items[0]?.id).toBe("permission-1");
  });

  it("keeps role and status edits restricted to super admins", async () => {
    const statusOnly = await app.request("/admin/permissions/permission-3", {
      method: "PATCH", headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ status: "active" }),
    }, env);
    expect(statusOnly.status).toBe(200);
    expect((await statusOnly.json()) as { data: { id: string; role: string; permission_status: string } }).toMatchObject({
      data: { id: "permission-3", role: "operator", permission_status: "active" },
    });
    const changed = await app.request("/admin/permissions/permission-1", {
      method: "PATCH", headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ role: "super_admin", status: "active" }),
    }, env);
    expect(changed.status).toBe(200);
    expect((await changed.json()) as { data: { role: string; permission_status: string } }).toMatchObject({
      data: { role: "super_admin", permission_status: "active" },
    });
    const operatorLogin = await app.request("/admin/auth/login", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "user-2@example.com", password: "permission-test-password" }),
    }, env);
    const operatorToken = ((await operatorLogin.json()) as { data: { access_token: string } }).data.access_token;
    const forbidden = await app.request("/admin/permissions/permission-3", {
      method: "PATCH", headers: { Authorization: `Bearer ${operatorToken}`, "content-type": "application/json" },
      body: JSON.stringify({ role: "super_admin" }),
    }, env);
    expect(forbidden.status).toBe(403);
  });

  it("requires Admin login before showing permission records", async () => {
    expect((await app.request("/admin/permissions", {}, env)).status).toBe(401);
  });
});
