import { PGliteDatabase } from "../test-support/pglite-database";
import { createPortfolioPostgresFixture, closePortfolioPostgresFixtures, seedPortfolioRows, readPortfolioRows } from "../test-support/portfolio-postgres-fixture";
import { signAccessToken } from "@kando/auth-core";
import { afterEach, describe, expect, it } from "vitest";
import app, { type Env } from "../index";

type OwnerType = "anonymous" | "user";

type PreferenceRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
  currency: string;
  amount_hidden: number;
  last_selected_folder_id: string | null;
  created_at: string;
  updated_at: string;
};

const JWT_SECRET = "test-secret";
const NOW = "2026-07-07T00:00:00.000Z";
const fixtureColumns = {
  user_preference: ["id", "owner_type", "owner_id", "currency", "amount_hidden", "last_selected_folder_id", "created_at", "updated_at"],
};

afterEach(async () => { await closePortfolioPostgresFixtures(); });

describe("preference routes", () => {
  it("gets only the authenticated owner's preferences because display settings are owner scoped", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'user_preference', preference({ currency: "USD", amount_hidden: 0 }), preference({
        id: "other-pref",
        owner_type: "user",
        owner_id: "other",
        currency: "JPY",
        amount_hidden: 1,
      }));

    const response = await app.request(
      "/api/v1/preferences",
      { headers: await authHeaders("anonymous", "anon-1") },
      createTestEnv(db),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        currency: "USD",
        amount_hidden: false,
        last_selected_folder_id: null,
      },
    });
  });

  it("updates preference fields and returns the full preference because clients need one canonical settings snapshot", async () => {
    const db = await createDbForOwner("user", "user-1");
    await seedPortfolioRows(db, 'user_preference', preference({ owner_type: "user", owner_id: "user-1", currency: "USD" }));
    await seedPortfolioRows(db, 'portfolio_folder', { id: "folder-1", owner_type: "user", owner_id: "user-1" });

    const response = await app.request(
      "/api/v1/preferences",
      {
        method: "PATCH",
        headers: await authHeaders("user", "user-1"),
        body: JSON.stringify({
          currency: "JPY",
          amount_hidden: true,
          last_selected_folder_id: "folder-1",
        }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        currency: "JPY",
        amount_hidden: true,
        last_selected_folder_id: "folder-1",
      },
    });
    expect((await readPortfolioRows<PreferenceRow>(db, 'user_preference', fixtureColumns.user_preference))[0]).toMatchObject({
      currency: "JPY",
      amount_hidden: 1,
      last_selected_folder_id: "folder-1",
      updated_at: expect.any(String),
    });
  });

  it("rejects invalid preference values because downstream display code relies on normalized settings", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'user_preference', preference({}));

    const invalidCurrency = await app.request(
      "/api/v1/preferences",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ currency: "usd" }),
      },
      createTestEnv(db),
    );
    const invalidHidden = await app.request(
      "/api/v1/preferences",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ amount_hidden: 1 }),
      },
      createTestEnv(db),
    );

    expect(invalidCurrency.status).toBe(422);
    expect(await invalidCurrency.json()).toEqual({
      success: false,
      error: { code: "VALIDATION_ERROR", message: "Invalid request." },
    });
    expect(invalidHidden.status).toBe(422);
    expect(await invalidHidden.json()).toEqual({
      success: false,
      error: { code: "VALIDATION_ERROR", message: "Invalid request." },
    });
  });

  it("rejects another owner's folder as last_selected_folder_id because preferences must not bridge owner boundaries", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'user_preference', preference({}));
    await seedPortfolioRows(db, 'portfolio_folder', { id: "folder-1", owner_type: "user", owner_id: "other" });

    const response = await app.request(
      "/api/v1/preferences",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ last_selected_folder_id: "folder-1" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({
      success: false,
      error: { code: "NOT_FOUND", message: "Not found." },
    });
  });
});

async function createDbForOwner(ownerType: OwnerType, ownerId: string): Promise<PGliteDatabase> {
  return createPortfolioPostgresFixture(ownerType, ownerId);
}

function createTestEnv(db: PGliteDatabase): Env {
  return { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET };
}

async function authHeaders(
  ownerType: OwnerType,
  ownerId: string,
): Promise<{ Authorization: string; "Content-Type": string }> {
  const token = await signAccessToken(
    {
      owner_type: ownerType,
      owner_id: ownerId,
      session_id: sessionId(ownerType, ownerId),
    },
    JWT_SECRET,
  );

  return { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
}

function sessionId(ownerType: OwnerType, ownerId: string): string {
  return `${ownerType}-${ownerId}-session`;
}

function preference(overrides: Partial<PreferenceRow>): PreferenceRow {
  return {
    id: "preference",
    owner_type: "anonymous",
    owner_id: "anon-1",
    currency: "USD",
    amount_hidden: 0,
    last_selected_folder_id: null,
    created_at: NOW,
    updated_at: NOW,
    ...overrides,
  };
}
