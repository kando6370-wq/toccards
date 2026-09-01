import { signAccessToken } from "@kando/auth-core";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { createPortfolioRoutes } from "./routes";

const JWT_SECRET = "folder-premium-test";

describe("Portfolio Folder Premium limit", () => {
  let mf: Miniflare;
  let db: D1Database;
  let env: Env;

  beforeEach(async () => {
    mf = new Miniflare({ modules: true, script: "export default { fetch() { return new Response('ok') } }", compatibilityDate: "2024-11-01", d1Databases: ["DB"] });
    db = await mf.getD1Database("DB");
    for (const statement of SCHEMA) await db.prepare(statement).run();
    await db.batch([
      db.prepare("INSERT INTO user (id, status) VALUES ('user-1', 'active')"),
      db.prepare("INSERT INTO session (id, owner_type, owner_id, expires_at, revoked_at) VALUES ('session-a', 'user', 'user-1', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO session (id, owner_type, owner_id, expires_at, revoked_at) VALUES ('session-b', 'user', 'user-1', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO portfolio_folder (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at) VALUES ('main', 'user', 'user-1', 'Main', 1, 0, '2026-08-12T00:00:00.000Z', '2026-08-12T00:00:00.000Z')"),
    ]);
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET, APP_ENVIRONMENT: "development", APPLE_IAP_PRODUCT_IDS: "yearly" };
  });

  afterEach(async () => { await mf.dispose(); });

  it("allows only one of two concurrent Free creates because the count and insert are one D1 statement", async () => {
    const app = createPortfolioRoutes();
    const [a, b] = await Promise.all([
      create(app, "session-a", "Binder A"),
      create(app, "session-b", "Binder B"),
    ]);

    expect([a.status, b.status].sort()).toEqual([201, 403]);
    expect(await folderCount()).toBe(2);
  });

  it("replays overlapping creates with one idempotency key because a committed first request is not a premium-limit failure", async () => {
    const app = createPortfolioRoutes();
    const idempotencyKey = "11111111-1111-4111-8111-111111111111";
    const headers = { "Idempotency-Key": idempotencyKey };
    const [a, b] = await Promise.all([
      create(app, "session-a", "Binder", headers),
      create(app, "session-b", "Binder", headers),
    ]);

    expect([a.status, b.status].sort()).toEqual([200, 201]);
    expect(await folderCount()).toBe(2);
    await expect(db.prepare(
      "SELECT COUNT(*) AS total FROM portfolio_folder WHERE id = ?",
    ).bind(idempotencyKey).first<number>("total")).resolves.toBe(1);
  });

  it("does not trust a local verified header and fails closed without a session grant", async () => {
    const app = createPortfolioRoutes();
    const response = await create(app, "session-a", "Binder", { "X-Local-Premium-State": "verified" });

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ success: false, error: { code: "ENTITLEMENT_SYNC_REQUIRED", message: "Premium access is still syncing." } });
    expect(await folderCount()).toBe(1);
  });

  it("allows the proving session past the Free limit but not another session of the same UID", async () => {
    await db.batch([
      db.prepare("INSERT INTO portfolio_folder (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at) VALUES ('binder', 'user', 'user-1', 'Binder', 0, 100, '2026-08-12T00:00:00.000Z', '2026-08-12T00:00:00.000Z')"),
      db.prepare("INSERT INTO billing_purchase_chain (id, environment, product_id, status, expires_at, revoked_at) VALUES ('chain-1', 'Sandbox', 'yearly', 'ACTIVE', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO billing_session_entitlement_grant (id, session_id, purchase_chain_id, entitlement_id, status, expires_at, revoked_at) VALUES ('grant-1', 'session-a', 'chain-1', 'performance_pro', 'active', '2099-01-01T00:00:00.000Z', NULL)"),
    ]);
    const app = createPortfolioRoutes();
    expect((await create(app, "session-a", "Premium Binder")).status).toBe(201);
    expect((await create(app, "session-b", "Other Device Binder")).status).toBe(403);
    expect(await folderCount()).toBe(3);
  });

  it("assigns distinct sort orders to concurrent Premium creates because folder order is owner scoped", async () => {
    await db.batch([
      db.prepare("INSERT INTO billing_purchase_chain (id, environment, product_id, status, expires_at, revoked_at) VALUES ('chain-1', 'Sandbox', 'yearly', 'ACTIVE', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO billing_session_entitlement_grant (id, session_id, purchase_chain_id, entitlement_id, status, expires_at, revoked_at) VALUES ('grant-a', 'session-a', 'chain-1', 'performance_pro', 'active', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO billing_session_entitlement_grant (id, session_id, purchase_chain_id, entitlement_id, status, expires_at, revoked_at) VALUES ('grant-b', 'session-b', 'chain-1', 'performance_pro', 'active', '2099-01-01T00:00:00.000Z', NULL)"),
    ]);
    const app = createPortfolioRoutes();
    const responses = await Promise.all([
      create(app, "session-a", "Binder A"),
      create(app, "session-b", "Binder B"),
    ]);

    expect(responses.map((response) => response.status)).toEqual([201, 201]);
    const rows = await db.prepare(
      "SELECT sort_order FROM portfolio_folder WHERE owner_type = 'user' AND owner_id = 'user-1' ORDER BY sort_order",
    ).all<{ sort_order: number }>();
    expect(rows.results.map((row) => row.sort_order)).toEqual([0, 100, 200]);
  });

  async function create(
    app: ReturnType<typeof createPortfolioRoutes>,
    sessionId: string,
    name: string,
    extraHeaders: Record<string, string> = {},
  ) {
    return await app.request("/portfolio/folders", {
      method: "POST",
      headers: { Authorization: `Bearer ${await token(sessionId)}`, "Content-Type": "application/json", ...extraHeaders },
      body: JSON.stringify({ name }),
    }, env);
  }

  async function folderCount(): Promise<number> {
    return (await db.prepare("SELECT COUNT(*) AS total FROM portfolio_folder").first<{ total: number }>())?.total ?? 0;
  }
});

async function token(sessionId: string): Promise<string> {
  return await signAccessToken({ owner_type: "user", owner_id: "user-1", session_id: sessionId }, JWT_SECRET);
}

const SCHEMA = [
  "CREATE TABLE mutation_lock (lock_key TEXT PRIMARY KEY)",
  "CREATE TABLE user (id TEXT PRIMARY KEY, status TEXT NOT NULL)",
  "CREATE TABLE session (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, expires_at TEXT NOT NULL, revoked_at TEXT)",
  "CREATE TABLE portfolio_folder (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, name TEXT NOT NULL, is_default INTEGER NOT NULL, sort_order INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(owner_type, owner_id, name))",
  "CREATE TABLE billing_purchase_chain (id TEXT PRIMARY KEY, environment TEXT NOT NULL, product_id TEXT NOT NULL, status TEXT NOT NULL, expires_at TEXT, revoked_at TEXT)",
  "CREATE TABLE billing_session_entitlement_grant (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, purchase_chain_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, status TEXT NOT NULL, expires_at TEXT, revoked_at TEXT)",
];
