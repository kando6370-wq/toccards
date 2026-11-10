import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { signAccessToken } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import type { AuthenticatedOwner } from "../owner-auth";
import { PGliteDatabase } from "../test-support/pglite-database";
import { createFeedbackRoutes, insertFeedbackForActiveOwner } from "./routes";

const JWT_SECRET = "feedback-route-test";
const NOW = "2026-11-05T00:00:00.000Z";

describe("feedback routes on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;
  let anonymousToken: string;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    const migrations = new URL("../db/postgres/migrations/", import.meta.url);
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
    await db.exec(`
      INSERT INTO "user" (id, email, created_at, updated_at)
      VALUES ('base-user', 'user@example.com', '${NOW}', '${NOW}');
      INSERT INTO anonymous_account (id, device_id, created_at)
      VALUES ('anonymous-ios', 'device-ios', '${NOW}');
      INSERT INTO session (id, owner_type, owner_id, refresh_token, expires_at, created_at)
      VALUES ('anonymous-session', 'anonymous', 'anonymous-ios', 'anonymous-refresh',
        '2099-01-01T00:00:00.000Z', '${NOW}');
    `);
    await db.exec(readFileSync(new URL("0018_platform_account_isolation.sql", migrations), "utf8"));
    await db.exec(`
      INSERT INTO platform_account (id, user_id, platform, status, created_at, updated_at)
      VALUES ('android-space', 'base-user', 'android', 'active', '${NOW}', '${NOW}');
      INSERT INTO session (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES ('android-session', 'user', 'android-space', 'android-refresh',
        '2099-01-01T00:00:00.000Z', '${NOW}', 'android', 'base-user');
    `);
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET, APP_ENVIRONMENT: "development" };
    anonymousToken = await signAccessToken({
      owner_type: "anonymous", owner_id: "anonymous-ios", session_id: "anonymous-session",
    }, JWT_SECRET);
  });

  afterEach(async () => db.close());

  it("persists authenticated feedback because support submissions must reach the operations queue", async () => {
    const response = await submit(anonymousToken, {
      email: " Person@Example.com ", types: ["Bug Report"],
      functions: ["Price Data"], message: " Prices are stale. ",
    });
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({
      success: true,
      data: { id: expect.any(String), status: "open", created_at: expect.any(String) },
    });
    expect(await db.prepare(`SELECT uid, email, types::text, functions::text, message, status
      FROM feedback_ticket`).first()).toEqual({
      uid: "anonymous-ios", email: "person@example.com", types: '["Bug Report"]',
      functions: '["Price Data"]', message: "Prices are stale.", status: "open",
    });
  });

  it("defaults empty classifications to Other because PRD makes both selectors optional", async () => {
    expect((await submit(anonymousToken, {
      email: "guest@example.com", types: [], message: "General feedback",
    })).status).toBe(201);
    expect(await db.prepare("SELECT types::text, functions::text FROM feedback_ticket").first())
      .toEqual({ types: '["Other"]', functions: '["Other"]' });
  });

  it("rejects invalid content because the database must not rely on client-side validation", async () => {
    for (const body of [
      { email: "invalid", message: "Feedback" },
      { email: "guest@example.com", types: ["Subscription"], message: "Feedback" },
      { email: "guest@example.com", message: "x".repeat(1001) },
    ]) expect((await submit(anonymousToken, body)).status).toBe(422);
    expect(await db.prepare("SELECT COUNT(*) AS total FROM feedback_ticket").first("total")).toBe(0);
  });

  it("rejects missing authentication because feedback is submitted from an active app session", async () => {
    const response = await createFeedbackRoutes().request("/feedback", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "guest@example.com", message: "Feedback" }),
    }, env);
    expect(response.status).toBe(401);
  });

  it("rejects a deleted platform after authentication while the other platform remains writable", async () => {
    const iosOwner: AuthenticatedOwner = {
      owner_type: "user", owner_id: "base-user", session_id: "legacy-ios-session",
      platform: "ios", user_id: "base-user", data_space_id: "base-user",
    };
    const androidOwner: AuthenticatedOwner = {
      owner_type: "user", owner_id: "android-space", session_id: "android-session",
      platform: "android", user_id: "base-user", data_space_id: "android-space",
    };
    await db.prepare(`UPDATE platform_account SET status = 'deleted', deleted_at = ?, updated_at = ?
      WHERE id = 'base-user'`).bind(NOW, NOW).run();
    const draft = {
      email: "user@example.com", types: ["Other"], functions: ["Account"],
      message: "Deletion race feedback",
    };
    await expect(insertFeedbackForActiveOwner(db, iosOwner, "ios-feedback", draft, NOW))
      .resolves.toBe(false);
    await expect(insertFeedbackForActiveOwner(db, androidOwner, "android-feedback", draft, NOW))
      .resolves.toBe(true);
    expect(await db.prepare("SELECT uid FROM feedback_ticket").first("uid")).toBe("android-space");
  });

  async function submit(token: string, body: object): Promise<Response> {
    return await createFeedbackRoutes().request("/feedback", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }, env);
  }
});
