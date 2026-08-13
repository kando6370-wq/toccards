import { signAccessToken } from "@kando/auth-core";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import type { DataSourceAdapter } from "./adapter";
import { createDataSourceRoutes } from "./routes";

const JWT_SECRET = "price-history-premium-test";

describe("Extended card price history", () => {
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
      db.prepare("INSERT INTO user VALUES ('user-1', 'active')"),
      db.prepare("INSERT INTO session VALUES ('session-a', 'user', 'user-1', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO session VALUES ('session-b', 'user', 'user-1', '2099-01-01T00:00:00.000Z', NULL)"),
    ]);
    env = {
      DB: db,
      CACHE_KV: {} as KVNamespace,
      JWT_SECRET,
      APP_ENVIRONMENT: "development",
    };
  });

  afterEach(async () => mf.dispose());

  it("keeps 1D through 3M public because only extended history is Premium", async () => {
    expect((await request("/cards/100/price-series?days=90")).status).toBe(200);
  });

  it("caps public market-price history at 3M because it must not bypass the 1Y gate", async () => {
    const response = await request("/cards/100/market-prices");
    const body = await response.json() as {
      data: { prices: { history: { date: string }[] }[] };
    };
    expect(body.data.prices[0].history.map((point) => point.date)).toEqual([
      "2026-06-01",
      "2026-08-12",
    ]);
  });

  it("rejects Free and local-only Premium before returning 1Y data", async () => {
    const free = await request("/cards/100/price-series?days=365", "session-a");
    expect(free.status).toBe(403);
    expect(await errorCode(free)).toBe("PREMIUM_REQUIRED");

    const syncing = await request(
      "/cards/100/price-series?days=365",
      "session-a",
      { "X-Local-Premium-State": "verified" },
    );
    expect(syncing.status).toBe(409);
    expect(await errorCode(syncing)).toBe("ENTITLEMENT_SYNC_REQUIRED");
  });

  it("allows only the live session with a server grant for single and batch 1Y", async () => {
    await db.batch([
      db.prepare("INSERT INTO billing_purchase_chain VALUES ('chain-1', 'Sandbox', 'ACTIVE', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO billing_session_entitlement_grant VALUES ('grant-1', 'session-a', 'chain-1', 'performance_pro', 'active', '2099-01-01T00:00:00.000Z', NULL)"),
    ]);

    expect((await request("/cards/100/price-series?days=365", "session-a")).status).toBe(200);
    expect((await request("/cards/100/price-series?days=365", "session-b")).status).toBe(403);

    const body = JSON.stringify({
      requests: [{ grader: "Raw", grade: null, condition: null, finish: null, days: 365 }],
    });
    expect((await request("/cards/100/price-series/batch", "session-a", { "Content-Type": "application/json" }, body, "POST")).status).toBe(200);
    expect((await request("/cards/100/price-series/batch", "session-b", { "Content-Type": "application/json" }, body, "POST")).status).toBe(403);
  });

  async function request(
    path: string,
    sessionId?: string,
    headers: Record<string, string> = {},
    body?: string,
    method = "GET",
  ) {
    const app = createDataSourceRoutes({ createAdapter: () => adapter });
    return app.request(path, {
      method,
      body,
      headers: {
        ...(sessionId ? { Authorization: `Bearer ${await token(sessionId)}` } : {}),
        ...headers,
      },
    }, env);
  }
});

const adapter: DataSourceAdapter = {
  searchCards: async () => [],
  searchSets: async () => [],
  getCard: async () => null,
  getPriceSeries: async () => [{ date: "2026-08-12", price: 20 }],
  getMarketPrices: async () => [{
    grader: "PSA",
    grade: 10,
    condition: null,
    price: 20,
    history: [
      { date: "2025-08-12", price: 10 },
      { date: "2026-06-01", price: 15 },
      { date: "2026-08-12", price: 20 },
    ],
  }],
  getTrending: async () => [],
  getSoldListings: async () => [],
};

async function token(sessionId: string): Promise<string> {
  return signAccessToken(
    { owner_type: "user", owner_id: "user-1", session_id: sessionId },
    JWT_SECRET,
  );
}

async function errorCode(response: Response): Promise<string> {
  const body = await response.json() as { error: { code: string } };
  return body.error.code;
}

const SCHEMA = [
  "CREATE TABLE user (id TEXT PRIMARY KEY, status TEXT NOT NULL)",
  "CREATE TABLE session (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, expires_at TEXT NOT NULL, revoked_at TEXT)",
  "CREATE TABLE billing_purchase_chain (id TEXT PRIMARY KEY, environment TEXT NOT NULL, status TEXT NOT NULL, expires_at TEXT, revoked_at TEXT)",
  "CREATE TABLE billing_session_entitlement_grant (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, purchase_chain_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, status TEXT NOT NULL, expires_at TEXT, revoked_at TEXT)",
];
