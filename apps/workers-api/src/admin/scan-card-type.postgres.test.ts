import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword } from "@kando/auth-core";
import { Hono } from "hono";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { adminRoutes } from "./routes";

type ScanList = {
  success: boolean;
  data: {
    items: Array<{ scan_id: string }>;
    page: number;
    page_size: number;
    total: number;
  };
};

describe("Admin scan card type filter on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;
  let token: string;
  const app = new Hono<{ Bindings: Env }>().route("/admin", adminRoutes);

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    for (const migration of ["0000_business_schema.sql", "0010_scan_record_environment.sql"]) {
      await db.exec(readFileSync(new URL(`../db/postgres/migrations/${migration}`, import.meta.url), "utf8"));
    }
    const now = "2026-10-28T08:00:00.000Z";
    await db.prepare(
      "INSERT INTO admin_user (id, email, password_hash, role, status, created_at) VALUES ('scan-admin', 'scan@example.com', ?, 'operator', 'active', ?)",
    ).bind(await hashPassword("scan-test-password"), now).run();
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "scan-filter-test", APP_ENVIRONMENT: "development" };
    const login = await app.request("/admin/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "scan@example.com", password: "scan-test-password" }),
    }, env);
    expect(login.status).toBe(200);
    token = ((await login.json()) as { data: { access_token: string } }).data.access_token;

    for (const [id, environment, ownerId, status, cardType, createdAt] of [
      ["tcg-dev", "development", "user-1", "success", 0, "2026-10-28T10:00:00.000Z"],
      ["sports-dev-a", "development", "user-1", "failed", 1, "2026-10-28T09:00:00.000Z"],
      ["sports-dev-b", "development", "user-1", "failed", 1, "2026-10-28T08:00:00.000Z"],
      ["sports-prod", "production", "user-1", "failed", 1, "2026-10-28T07:00:00.000Z"],
      ["legacy-unknown", "development", "user-1", "failed", null, "2026-10-28T06:00:00.000Z"],
    ] as const) {
      await db.prepare(`
        INSERT INTO scan_record
          (id, environment, owner_type, owner_id, filename, platform, app_version,
           recognition_status, user_confirmation_status, system_result, user_result,
           candidates, raw_response, created_at)
        VALUES (?, ?, 'user', ?, 'scan.jpg', 'iOS', '1.0.7', ?, 'pending', ?, '{}', '[]', '{}', ?)
      `).bind(id, environment, ownerId, status,
        JSON.stringify(cardType === null ? {} : { card_type: cardType }), createdAt).run();
    }
  }, 30000);

  afterAll(async () => { await db?.close(); });

  async function list(query: string): Promise<ScanList["data"]> {
    const response = await app.request(`/admin/scans${query}`, {
      headers: { Authorization: `Bearer ${token}` },
    }, env);
    expect(response.status).toBe(200);
    return ((await response.json()) as ScanList).data;
  }

  it("filters the page and total by persisted type while leaving unknown historical records in All", async () => {
    const all = await list("?environment=development&page_size=10");
    expect(all.total).toBe(4);
    expect(all.items.map((item) => item.scan_id)).toContain("legacy-unknown");

    const tcg = await list("?environment=development&card_type=0");
    expect(tcg.total).toBe(1);
    expect(tcg.items.map((item) => item.scan_id)).toEqual(["tcg-dev"]);

    for (const page of [1, 2]) {
      const sports = await list(`?environment=development&card_type=1&page_size=1&page=${page}`);
      expect(sports.total).toBe(2);
      expect(sports.items.map((item) => item.scan_id)).toEqual([page === 1 ? "sports-dev-a" : "sports-dev-b"]);
    }
  });

  it("combines card type with existing owner, status and environment filters", async () => {
    const matching = await list("?uid=user-1&recognition_status=failed&environment=production&card_type=1");
    expect(matching.total).toBe(1);
    expect(matching.items[0]?.scan_id).toBe("sports-prod");
    const excluded = await list("?uid=user-1&recognition_status=success&environment=development&card_type=1");
    expect(excluded.total).toBe(0);
    expect(excluded.items).toEqual([]);
  });

  it("rejects unsupported type values before querying and keeps Admin authentication", async () => {
    for (const value of ["2", "01", "sports", "-1"]) {
      const response = await app.request(`/admin/scans?card_type=${encodeURIComponent(value)}`, {
        headers: { Authorization: `Bearer ${token}` },
      }, env);
      expect(response.status).toBe(422);
      expect(await response.json()).toMatchObject({ success: false, error: { code: "VALIDATION_ERROR" } });
    }
    const withoutAdminToken = await app.request("/admin/scans?card_type=1", {}, env);
    expect(withoutAdminToken.status).toBe(401);
  });
});
