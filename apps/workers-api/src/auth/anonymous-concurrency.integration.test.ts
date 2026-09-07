import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Env } from "../env";
import { mutationLockKey } from "../db/mutation-lock";
import { authRoutes } from "./anonymous";

const JWT_SECRET = "anonymous-concurrency-test-secret";

describe("anonymous account concurrency", () => {
  let mf: Miniflare;
  let db: D1Database;
  let env: Env;

  beforeEach(async () => {
    mf = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      compatibilityDate: "2024-11-01",
      d1Databases: ["DB"],
    });
    db = await mf.getD1Database("DB");
    for (const statement of SCHEMA) await db.prepare(statement).run();
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET };
  });

  afterEach(async () => {
    await mf.dispose();
  });

  it("creates one live owner for overlapping device requests because device identity cannot fork guest assets", async () => {
    const responses = await Promise.all([
      createAnonymous("same-device"),
      createAnonymous("same-device"),
    ]);
    const bodies = await Promise.all(responses.map((response) => response.json())) as Array<{
      data: { anonymous_id: string };
    }>;

    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    expect(new Set(bodies.map((body) => body.data.anonymous_id)).size).toBe(1);
    await expect(count("anonymous_account")).resolves.toBe(1);
    await expect(count("portfolio_folder")).resolves.toBe(1);
    await expect(count("user_preference")).resolves.toBe(1);
    await expect(count("session")).resolves.toBe(2);
    await expect(count("account_uid")).resolves.toBe(2);
    const lockRows = await db.prepare(
      "SELECT lock_key FROM mutation_lock ORDER BY lock_key",
    ).all<{ lock_key: string }>();
    expect(lockRows.results.map((row) => row.lock_key)).toEqual([
      "account-uid",
      await mutationLockKey("anonymous-device", "same-device"),
    ]);
  });

  async function createAnonymous(deviceId: string): Promise<Response> {
    return authRoutes.request("/anonymous", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: deviceId, platform: "ios" }),
    }, env);
  }

  async function count(table: string): Promise<number> {
    return await db.prepare(`SELECT COUNT(*) AS total FROM ${table}`).first<number>("total") ?? 0;
  }
});

const SCHEMA = [
  "CREATE TABLE mutation_lock (lock_key TEXT PRIMARY KEY)",
  "CREATE TABLE account_uid (uid INTEGER PRIMARY KEY, created_at TEXT NOT NULL)",
  "CREATE TABLE anonymous_account (id TEXT PRIMARY KEY, device_id TEXT NOT NULL, created_at TEXT NOT NULL, upgraded_user_id TEXT)",
  "CREATE TABLE app_installation (installation_id TEXT PRIMARY KEY, uid TEXT, platform TEXT NOT NULL, country_code TEXT, first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL)",
  "CREATE TABLE portfolio_folder (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, name TEXT NOT NULL, is_default INTEGER NOT NULL, sort_order INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(owner_type, owner_id, name))",
  "CREATE TABLE user_preference (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, currency TEXT NOT NULL, amount_hidden INTEGER NOT NULL, last_selected_folder_id TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(owner_type, owner_id))",
  "CREATE TABLE session (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, login_method TEXT, refresh_token TEXT NOT NULL UNIQUE, expires_at TEXT NOT NULL, created_at TEXT NOT NULL, revoked_at TEXT)",
];
