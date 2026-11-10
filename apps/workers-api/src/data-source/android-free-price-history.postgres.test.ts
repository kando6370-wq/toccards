import { signAccessToken } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import type { DataSourceAdapter } from "./adapter";
import { createDataSourceRoutes } from "./routes";

const JWT_SECRET = "android-free-price-history";

describe("Android free-launch extended price history", () => {
  let db: PGliteDatabase;
  let env: Env;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(`
      CREATE TABLE "user" (id text PRIMARY KEY, status text NOT NULL);
      CREATE TABLE platform_account (
        id text PRIMARY KEY, user_id text NOT NULL, platform text NOT NULL,
        status text NOT NULL
      );
      CREATE TABLE session (
        id text PRIMARY KEY, owner_type text NOT NULL, owner_id text NOT NULL,
        platform text, user_id text, expires_at text NOT NULL, revoked_at text
      );
      INSERT INTO "user" VALUES ('base-user', 'active');
      INSERT INTO platform_account VALUES ('android-space', 'base-user', 'android', 'active');
      INSERT INTO session VALUES (
        'android-session', 'user', 'android-space', 'android', 'base-user',
        '2099-01-01T00:00:00.000Z', NULL
      );
    `);
    env = {
      DB: db,
      CACHE_KV: {} as KVNamespace,
      JWT_SECRET,
      APP_ENVIRONMENT: "development",
    };
  });

  afterEach(async () => db.close());

  it("serves single and batch 1Y history without Apple entitlement or local Premium state", async () => {
    const token = await signAccessToken({
      owner_type: "user",
      owner_id: "android-space",
      session_id: "android-session",
    }, JWT_SECRET);
    const app = createDataSourceRoutes({ createAdapter: () => adapter });

    const response = await app.request("/cards/card-1/price-series?days=365", {
      headers: { Authorization: `Bearer ${token}` },
    }, env);

    expect(response.status).toBe(200);

    const batch = await app.request("/cards/card-1/price-series/batch", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        requests: [{ grader: "Raw", grade: null, condition: null, finish: null, days: 365 }],
      }),
    }, env);
    expect(batch.status).toBe(200);
  });
});

const adapter: DataSourceAdapter = {
  searchCards: async () => [],
  searchSets: async () => [],
  getCard: async () => null,
  getPriceSeries: async () => [{ date: "2026-11-05", price: 20 }],
  getMarketPrices: async () => [],
  getTrending: async () => [],
  getSoldListings: async () => [],
};
