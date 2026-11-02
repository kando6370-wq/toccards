import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword } from "@kando/auth-core";
import { Hono } from "hono";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { adminRoutes } from "./routes";

type FeedbackList = {
  success: boolean;
  data: { items: Array<{ id: string; status: string; platform: string; issue_type: string }>; total: number; page: number; page_size: number };
};

describe("Admin feedback pagination and filters on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;
  let token: string;
  const app = new Hono<{ Bindings: Env }>().route("/admin", adminRoutes);

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("../db/postgres/migrations/0000_business_schema.sql", import.meta.url), "utf8"));
    const now = "2026-10-28T08:00:00.000Z";
    await db.prepare(
      "INSERT INTO admin_user (id, email, password_hash, role, status, created_at) VALUES ('feedback-admin', 'feedback@example.com', ?, 'operator', 'active', ?)",
    ).bind(await hashPassword("feedback-test-password"), now).run();
    for (const [id, uid, types, status, createdAt] of [
      ["a", "user-1", '["Bug Report"]', "open", "2026-10-28T10:00:00.000Z"],
      ["b", "user-1", '["Improvement","Bug Report"]', "in_progress", "2026-10-28T10:00:00.000Z"],
      ["c", "user-1", '["Bug Report"]', "closed", "2026-10-28T08:00:00.000Z"],
      ["d", "user-2", '["Bug Report"]', "processed", "2026-10-27T23:59:59.000Z"],
      ["e", "user-1", '["Feature Request"]', "ignored", "2026-10-29T10:00:00.000Z"],
    ]) {
      await db.prepare("INSERT INTO feedback_ticket (id, uid, email, types, functions, message, status, created_at, updated_at) VALUES (?, ?, 'user@example.com', ?, '[\"Search\"]', 'Feedback', ?, ?, ?)")
        .bind(id, uid, types, status, createdAt, createdAt).run();
    }
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "feedback-filter-test", APP_ENVIRONMENT: "development" };
    const login = await app.request("/admin/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "feedback@example.com", password: "feedback-test-password" }),
    }, env);
    expect(login.status).toBe(200);
    token = ((await login.json()) as { data: { access_token: string } }).data.access_token;
  }, 30000);

  afterAll(async () => { await db?.close(); });

  async function list(query: string): Promise<FeedbackList["data"]> {
    const response = await app.request(`/admin/feedbacks${query}`, { headers: { Authorization: `Bearer ${token}` } }, env);
    expect(response.status).toBe(200);
    return ((await response.json()) as FeedbackList).data;
  }

  it("counts and pages all matching feedback, including beyond the first page", async () => {
    const unfiltered = await list("");
    const first = await list("?page_size=2");
    const second = await list("?page_size=2&page=2");
    expect(unfiltered).toMatchObject({ total: 5, page: 1, page_size: 20 });
    expect(unfiltered.items).toHaveLength(5);
    expect(unfiltered.items.every((item) => item.platform === "未知")).toBe(true);
    expect(first).toMatchObject({ total: 5, page: 1, page_size: 2 });
    expect(first.items.map((item) => item.id)).toEqual(["e", "a"]);
    expect(second).toMatchObject({ total: 5, page: 2, page_size: 2 });
    expect(second.items.map((item) => item.id)).toEqual(["b", "c"]);
  });

  it("applies UID, type, legacy status, and dates before page and total", async () => {
    const query = "?uid=user-1&issue_type=Bug%20Report&status=pending&date_from=2026-10-28&date_to=2026-10-28&page_size=1";
    const first = await list(query);
    const second = await list(`${query}&page=2`);
    expect(first.total).toBe(2);
    expect(first.items.map((item) => item.id)).toEqual(["a"]);
    expect(first.items[0]?.status).toBe("pending");
    expect(second.total).toBe(2);
    expect(second.items.map((item) => item.id)).toEqual(["b"]);
    expect(second.items[0]?.status).toBe("pending");
    const processed = await list("?status=processed&page_size=1");
    expect(processed.total).toBe(2);
    expect(processed.items.map((item) => item.id)).toEqual(["c"]);
  });

  it("keeps authentication and rejects malformed dates", async () => {
    expect((await app.request("/admin/feedbacks", {}, env)).status).toBe(401);
    const response = await app.request("/admin/feedbacks?date_from=invalid", { headers: { Authorization: `Bearer ${token}` } }, env);
    expect(response.status).toBe(422);
  });

  it("keeps historical invalid type data readable while excluding it from type filters", async () => {
    for (const [id, types] of [["bad-json", "{not-json"], ["non-array", '"Bug Report"']]) {
      await db.prepare("INSERT INTO feedback_ticket (id, uid, email, types, functions, message, status, created_at, updated_at) VALUES (?, 'user-1', 'user@example.com', ?, '[\"Search\"]', 'Feedback', 'open', '2026-10-30T10:00:00.000Z', '2026-10-30T10:00:00.000Z')")
        .bind(id, types).run();
    }
    try {
      const unfiltered = await list("?page_size=20");
      expect(unfiltered.total).toBe(7);
      expect(unfiltered.items.filter((item) => item.id === "bad-json" || item.id === "non-array")
        .map((item) => item.issue_type)).toEqual(["其他", "其他"]);
      const filtered = await list("?issue_type=Bug%20Report&page_size=2");
      expect(filtered.total).toBe(4);
      expect(filtered.items.map((item) => item.id)).toEqual(["a", "b"]);
    } finally {
      await db.prepare("DELETE FROM feedback_ticket WHERE id IN ('bad-json', 'non-array')").run();
    }
  });

  it("keeps feedback beyond the first hundred records reachable", async () => {
    for (let index = 0; index < 101; index += 1) {
      const id = `bulk-${String(index).padStart(3, "0")}`;
      await db.prepare("INSERT INTO feedback_ticket (id, uid, email, types, functions, message, status, created_at, updated_at) VALUES (?, 'bulk-user', 'user@example.com', '[\"Other\"]', '[\"Search\"]', 'Feedback', 'open', '2026-10-26T10:00:00.000Z', '2026-10-26T10:00:00.000Z')")
        .bind(id).run();
    }
    const last = await list("?page_size=100&page=2");
    expect(last.total).toBe(106);
    expect(last.items.map((item) => item.id)).toEqual([
      "bulk-095", "bulk-096", "bulk-097", "bulk-098", "bulk-099", "bulk-100",
    ]);
  });
});
