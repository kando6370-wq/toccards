import { signAccessToken } from "@kando/auth-core";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { createPortfolioRoutes } from "./routes";

const JWT_SECRET = "performance-premium-test";

describe("Premium Performance routes", () => {
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
    await db.batch([
      db.prepare("INSERT INTO user (id, status) VALUES ('user-1', 'active')"),
      db.prepare("INSERT INTO session (id, owner_type, owner_id, expires_at, revoked_at) VALUES ('session-a', 'user', 'user-1', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO session (id, owner_type, owner_id, expires_at, revoked_at) VALUES ('session-b', 'user', 'user-1', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO portfolio_folder (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at) VALUES ('main', 'user', 'user-1', 'Main', 1, 0, '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z')"),
      db.prepare("INSERT INTO collection_item (id, owner_type, owner_id, folder_id, card_ref, object_type, grader, condition, grade, language, finish, quantity, purchase_price, purchase_currency, performance_start_at, purchase_price_effective_at, performance_history_available_from, notes, created_at, updated_at) VALUES ('item-1', 'user', 'user-1', 'main', '100', 'tcg', 'Raw', 'Near Mint (NM)', NULL, 'English', 'Normal', 1, 10, 'USD', '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z', NULL, '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z')"),
      db.prepare("INSERT INTO collection_item_event (id, item_id, owner_type, owner_id, folder_id, card_ref, object_type, grader, condition, grade, language, finish, quantity, purchase_price, purchase_currency, performance_history_available_from, event_type, effective_at) VALUES ('event-1', 'item-1', 'user', 'user-1', 'main', '100', 'tcg', 'Raw', 'Near Mint (NM)', NULL, 'English', 'Normal', 1, 10, 'USD', '2026-08-01T00:00:00.000Z', 'upsert', '2026-08-01T00:00:00.000Z')"),
      db.prepare("INSERT INTO tcg_price (product_id, condition_code, condition_name, language_code, language_name, variant_code, variant_name, price_Ungraded) VALUES ('100', 'NM', 'Near Mint', 'EN', 'English', 'N', 'Normal', '[{\"date\":\"2026-08-01\",\"price\":20}]')"),
    ]);
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET, APP_ENVIRONMENT: "development" };
  });

  afterEach(async () => mf.dispose());

  it("keeps the existing valuation history available to Free users", async () => {
    const response = await request("session-a", "/portfolio/valuation-history?days=1");
    expect(response.status).toBe(200);
  });

  it("protects extended valuation history with the current session grant", async () => {
    const free = await request("session-a", "/portfolio/valuation-history?days=365");
    expect(free.status).toBe(403);
    expect(await errorCode(free)).toBe("PREMIUM_REQUIRED");

    await db.batch([
      db.prepare("INSERT INTO billing_purchase_chain (id, environment, status, expires_at, revoked_at) VALUES ('chain-history', 'Sandbox', 'ACTIVE', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO billing_session_entitlement_grant (id, session_id, purchase_chain_id, entitlement_id, status, expires_at, revoked_at) VALUES ('grant-history', 'session-a', 'chain-history', 'performance_pro', 'active', '2099-01-01T00:00:00.000Z', NULL)"),
    ]);

    expect((await request("session-a", "/portfolio/valuation-history?days=365")).status).toBe(200);
    expect((await request("session-b", "/portfolio/valuation-history?days=365")).status).toBe(403);
  });

  it("rejects Free before returning Premium business data", async () => {
    const response = await request("session-a", "/portfolio/performance?range=1M");
    expect(response.status).toBe(403);
    expect(await errorCode(response)).toBe("PREMIUM_REQUIRED");
  });

  it("keeps a local verified client in sync_required without trusting its header", async () => {
    const response = await request("session-a", "/portfolio/performance?range=1M", {
      "X-Local-Premium-State": "verified",
    });
    expect(response.status).toBe(409);
    expect(await errorCode(response)).toBe("ENTITLEMENT_SYNC_REQUIRED");
  });

  it("allows only the session with a verified grant", async () => {
    await db.batch([
      db.prepare("INSERT INTO billing_purchase_chain (id, environment, status, expires_at, revoked_at) VALUES ('chain-1', 'Sandbox', 'ACTIVE', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO billing_session_entitlement_grant (id, session_id, purchase_chain_id, entitlement_id, status, expires_at, revoked_at) VALUES ('grant-1', 'session-a', 'chain-1', 'performance_pro', 'active', '2099-01-01T00:00:00.000Z', NULL)"),
    ]);
    const allowed = await request("session-a", "/portfolio/items/item-1/performance?range=15D");
    expect(allowed.status).toBe(200);
    const body = await allowed.json() as { data: { item_id: string; current: { market_value_usd: number } } };
    expect(body.data.item_id).toBe("item-1");
    expect(body.data.current.market_value_usd).toBe(20);

    const otherSession = await request("session-b", "/portfolio/items/item-1/performance?range=15D");
    expect(otherSession.status).toBe(403);
  });

  async function request(sessionId: string, path: string, headers: Record<string, string> = {}) {
    const app = createPortfolioRoutes();
    return app.request(path, {
      headers: { Authorization: `Bearer ${await token(sessionId)}`, ...headers },
    }, env);
  }
});

async function token(sessionId: string): Promise<string> {
  return signAccessToken({ owner_type: "user", owner_id: "user-1", session_id: sessionId }, JWT_SECRET);
}

async function errorCode(response: Response): Promise<string> {
  const body = await response.json() as { error: { code: string } };
  return body.error.code;
}

const SCHEMA = [
  "CREATE TABLE user (id TEXT PRIMARY KEY, status TEXT NOT NULL)",
  "CREATE TABLE session (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, expires_at TEXT NOT NULL, revoked_at TEXT)",
  "CREATE TABLE portfolio_folder (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, name TEXT NOT NULL, is_default INTEGER NOT NULL, sort_order INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
  "CREATE TABLE collection_item (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, folder_id TEXT NOT NULL, card_ref TEXT NOT NULL, object_type TEXT NOT NULL, grader TEXT NOT NULL, condition TEXT, grade REAL, language TEXT, finish TEXT, quantity INTEGER NOT NULL, purchase_price REAL, purchase_currency TEXT, performance_start_at TEXT, purchase_price_effective_at TEXT, performance_history_available_from TEXT, notes TEXT, folder_joined_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
  "CREATE TABLE collection_item_event (id TEXT PRIMARY KEY, item_id TEXT NOT NULL, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, folder_id TEXT NOT NULL, card_ref TEXT NOT NULL, object_type TEXT NOT NULL, grader TEXT NOT NULL, condition TEXT, grade REAL, language TEXT, finish TEXT, quantity INTEGER NOT NULL, purchase_price REAL, purchase_currency TEXT, performance_history_available_from TEXT, event_type TEXT NOT NULL, effective_at TEXT NOT NULL)",
  "CREATE TABLE tcg_price (product_id TEXT, condition_code TEXT, condition_name TEXT, language_code TEXT, language_name TEXT, variant_code TEXT, variant_name TEXT, price_Ungraded TEXT, increase_Ungraded REAL, price_Grade_7 TEXT, price_Grade_8 TEXT, price_Grade_9 TEXT, price_Grade_9_5 TEXT, price_PSA_10 TEXT, price_BGS_10 TEXT, price_CGC_10 TEXT, price_SGC_10 TEXT, increase_Grade_7 REAL, increase_Grade_8 REAL, increase_Grade_9 REAL, increase_Grade_9_5 REAL, increase_PSA_10 REAL, increase_BGS_10 REAL, increase_CGC_10 REAL, increase_SGC_10 REAL)",
  "CREATE TABLE cards_all (product_id TEXT, game TEXT, name TEXT, set_name TEXT, number TEXT, rarity TEXT)",
  "CREATE TABLE billing_purchase_chain (id TEXT PRIMARY KEY, environment TEXT NOT NULL, status TEXT NOT NULL, expires_at TEXT, revoked_at TEXT)",
  "CREATE TABLE billing_session_entitlement_grant (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, purchase_chain_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, status TEXT NOT NULL, expires_at TEXT, revoked_at TEXT)",
];
