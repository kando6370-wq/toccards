import { PGliteDatabase } from "../test-support/pglite-database";
import { createPortfolioPostgresFixture, closePortfolioPostgresFixtures, seedPortfolioRows, readPortfolioRows } from "../test-support/portfolio-postgres-fixture";
import { signAccessToken } from "@kando/auth-core";
import { afterEach, describe, expect, it } from "vitest";
import app, { type Env } from "../index";

type OwnerType = "anonymous" | "user";

type FolderRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
  name: string;
  is_default: number;
  sort_order: number;
  created_at: string;
  updated_at: string;
};

type PreferenceRow = {
  owner_type: OwnerType;
  owner_id: string;
  last_selected_folder_id: string | null;
};

const JWT_SECRET = "test-secret";
const NOW = "2026-07-07T00:00:00.000Z";
const fixtureColumns = {
  portfolio_folder: ["id", "owner_type", "owner_id", "name", "is_default", "sort_order", "created_at", "updated_at"],
  user_preference: ["owner_type", "owner_id", "last_selected_folder_id"],
};

afterEach(async () => { await closePortfolioPostgresFixtures(); });

describe("portfolio folder routes", () => {
  it("rejects missing bearer tokens because asset data must never be inferred without owner proof", async () => {
    const response = await app.request(
      "/api/v1/portfolio/folders",
      {},
      createTestEnv(await createDbForOwner("anonymous", "unauthenticated-fixture")),
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({
      success: false,
      error: { code: "UNAUTHORIZED", message: "Unauthorized." },
    });
  });

  it("lists only the authenticated owner's folders in sort order because portfolio data is owner isolated", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "other-folder", owner_type: "user", owner_id: "other" }), folder({ id: "binder", name: "Binder", sort_order: 100 }), folder({ id: "main", name: "Main", is_default: 1, sort_order: 0 }));

    const response = await app.request(
      "/api/v1/portfolio/folders",
      { headers: await authHeaders("anonymous", "anon-1") },
      createTestEnv(db),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        items: [
          folderResponse({ id: "main", name: "Main", is_default: true, sort_order: 0 }),
          folderResponse({ id: "binder", name: "Binder", sort_order: 100 }),
        ],
      },
    });
  });

  it("uses folder id as a stable tie-breaker because equal custom positions must not reorder between reads", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "folder-z", name: "Binder Z", sort_order: 100 }), folder({ id: "folder-a", name: "Binder A", sort_order: 100 }));

    const response = await app.request(
      "/api/v1/portfolio/folders",
      { headers: await authHeaders("anonymous", "anon-1") },
      createTestEnv(db),
    );
    const body = await response.json() as {
      data: { items: Array<{ id: string }> };
    };

    expect(response.status).toBe(200);
    expect(body.data.items.map((item) => item.id)).toEqual([
      "folder-a",
      "folder-z",
    ]);
  });

  it("creates a non-default folder after the current owner's last sort order because new folders should not disturb Main", async () => {
    const db = await createDbForOwner("user", "user-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({
        id: "main",
        owner_type: "user",
        owner_id: "user-1",
        is_default: 1,
        sort_order: 0,
      }));

    const response = await app.request(
      "/api/v1/portfolio/folders",
      {
        method: "POST",
        headers: { ...(await authHeaders("user", "user-1")) },
        body: JSON.stringify({ name: "Trade Binder" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        id: expect.any(String),
        name: "Trade Binder",
        is_default: false,
        sort_order: 100,
        created_at: expect.any(String),
        updated_at: expect.any(String),
      },
    });
  });

  it("replays the same folder create after a lost response because retries must not create duplicate folders", async () => {
    const db = await createDbForOwner("user", "user-1");
    const idempotencyKey = "11111111-1111-4111-8111-111111111111";
    const request = {
      method: "POST",
      headers: {
        ...(await authHeaders("user", "user-1")),
        "Idempotency-Key": idempotencyKey,
      },
      body: JSON.stringify({ name: "Trade Binder" }),
    };

    const created = await app.request(
      "/api/v1/portfolio/folders",
      request,
      createTestEnv(db),
    );
    const replayed = await app.request(
      "/api/v1/portfolio/folders",
      request,
      createTestEnv(db),
    );

    expect(created.status).toBe(201);
    expect(replayed.status).toBe(200);
    expect(await replayed.json()).toEqual({
      success: true,
      data: expect.objectContaining({
        id: idempotencyKey,
        name: "Trade Binder",
      }),
    });
    expect((await readPortfolioRows<FolderRow>(db, 'portfolio_folder', fixtureColumns.portfolio_folder))).toHaveLength(1);
  });

  it("rejects reusing a folder idempotency key for a different name because one operation key has one meaning", async () => {
    const db = await createDbForOwner("user", "user-1");
    const idempotencyKey = "22222222-2222-4222-8222-222222222222";
    const headers = {
      ...(await authHeaders("user", "user-1")),
      "Idempotency-Key": idempotencyKey,
    };
    await app.request(
      "/api/v1/portfolio/folders",
      {
        method: "POST",
        headers,
        body: JSON.stringify({ name: "Trade Binder" }),
      },
      createTestEnv(db),
    );

    const response = await app.request(
      "/api/v1/portfolio/folders",
      {
        method: "POST",
        headers,
        body: JSON.stringify({ name: "Sealed" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(409);
    expect((await readPortfolioRows<FolderRow>(db, 'portfolio_folder', fixtureColumns.portfolio_folder))).toHaveLength(1);
  });

  it("rejects a malformed folder idempotency key because only server-compatible operation ids may become folder ids", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");

    const response = await app.request(
      "/api/v1/portfolio/folders",
      {
        method: "POST",
        headers: {
          ...(await authHeaders("anonymous", "anon-1")),
          "Idempotency-Key": "not-a-uuid",
        },
        body: JSON.stringify({ name: "Trade Binder" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(422);
    expect((await readPortfolioRows<FolderRow>(db, 'portfolio_folder', fixtureColumns.portfolio_folder))).toHaveLength(0);
  });

  it("returns CONFLICT when creating a duplicate folder name because owner folder names are unique", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", name: "Main" }));

    const response = await app.request(
      "/api/v1/portfolio/folders",
      {
        method: "POST",
        headers: { ...(await authHeaders("anonymous", "anon-1")) },
        body: JSON.stringify({ name: "Main" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      success: false,
      error: { code: "CONFLICT", message: "Conflict." },
    });
  });

  it("rejects folder names over 50 characters because Portfolio folders must stay readable in the mobile UI", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");

    const create = await app.request(
      "/api/v1/portfolio/folders",
      {
        method: "POST",
        headers: { ...(await authHeaders("anonymous", "anon-1")) },
        body: JSON.stringify({ name: "A".repeat(51) }),
      },
      createTestEnv(db),
    );
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "trade", name: "Trade" }));
    const rename = await app.request(
      "/api/v1/portfolio/folders/trade",
      {
        method: "PATCH",
        headers: { ...(await authHeaders("anonymous", "anon-1")) },
        body: JSON.stringify({ name: "B".repeat(51) }),
      },
      createTestEnv(db),
    );

    expect(create.status).toBe(422);
    expect(await create.json()).toEqual({
      success: false,
      error: { code: "VALIDATION_ERROR", message: "Invalid request." },
    });
    expect(rename.status).toBe(422);
    expect(await rename.json()).toEqual({
      success: false,
      error: { code: "VALIDATION_ERROR", message: "Invalid request." },
    });
  });

  it("renames an owned folder and rejects deleting the default folder because Main must stay protected", async () => {
    const db = await createDbForOwner("user", "user-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", owner_type: "user", owner_id: "user-1", is_default: 1 }), folder({ id: "trade", owner_type: "user", owner_id: "user-1", name: "Trade" }));

    const rename = await app.request(
      "/api/v1/portfolio/folders/trade",
      {
        method: "PATCH",
        headers: { ...(await authHeaders("user", "user-1")) },
        body: JSON.stringify({ name: "Personal Collection" }),
      },
      createTestEnv(db),
    );
    const deleteDefault = await app.request(
      "/api/v1/portfolio/folders/main",
      {
        method: "DELETE",
        headers: await authHeaders("user", "user-1"),
      },
      createTestEnv(db),
    );

    expect(rename.status).toBe(200);
    expect(await rename.json()).toEqual({
      success: true,
      data: folderResponse({
        id: "trade",
        name: "Personal Collection",
        sort_order: 100,
        updated_at: expect.any(String),
      }),
    });
    expect(deleteDefault.status).toBe(403);
    expect(await deleteDefault.json()).toEqual({
      success: false,
      error: { code: "FORBIDDEN", message: "Forbidden." },
    });
  });

  it("deletes a non-default folder and clears last_selected_folder_id because clients must fall back to Main", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", is_default: 1 }), folder({ id: "trade", name: "Trade" }));
    await seedPortfolioRows(db, 'user_preference', {
      owner_type: "anonymous",
      owner_id: "anon-1",
      last_selected_folder_id: "trade",
    });

    const response = await app.request(
      "/api/v1/portfolio/folders/trade",
      {
        method: "DELETE",
        headers: await authHeaders("anonymous", "anon-1"),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ success: true, data: {} });
    expect((await readPortfolioRows<FolderRow>(db, 'portfolio_folder', fixtureColumns.portfolio_folder)).map((row) => row.id)).toEqual(["main"]);
    expect((await readPortfolioRows<PreferenceRow>(db, 'user_preference', fixtureColumns.user_preference))[0]?.last_selected_folder_id).toBeNull();
  });

  it("sets one default folder and reorders owned folders because folder state must remain consistent per owner", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", is_default: 1, sort_order: 0 }), folder({ id: "trade", name: "Trade", sort_order: 100 }));

    const setDefault = await app.request(
      "/api/v1/portfolio/folders/trade/set-default",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
      },
      createTestEnv(db),
    );
    const reorder = await app.request(
      "/api/v1/portfolio/folders/reorder",
      {
        method: "PATCH",
        headers: { ...(await authHeaders("anonymous", "anon-1")) },
        body: JSON.stringify({
          orders: [
            { folder_id: "trade", sort_order: 0 },
            { folder_id: "main", sort_order: 100 },
          ],
        }),
      },
      createTestEnv(db),
    );
    const list = await app.request(
      "/api/v1/portfolio/folders",
      { headers: await authHeaders("anonymous", "anon-1") },
      createTestEnv(db),
    );

    expect(setDefault.status).toBe(200);
    expect(await setDefault.json()).toEqual({
      success: true,
      data: folderResponse({
        id: "trade",
        name: "Trade",
        is_default: true,
        sort_order: 100,
        updated_at: expect.any(String),
      }),
    });
    expect(reorder.status).toBe(200);
    expect(await reorder.json()).toEqual({ success: true, data: {} });
    expect(await list.json()).toEqual({
      success: true,
      data: {
        items: [
          folderResponse({
            id: "trade",
            name: "Trade",
            is_default: true,
            sort_order: 0,
            updated_at: expect.any(String),
          }),
          folderResponse({
            id: "main",
            name: "Main",
            is_default: false,
            sort_order: 100,
            updated_at: expect.any(String),
          }),
        ],
      },
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

function folder(overrides: Partial<FolderRow>): FolderRow {
  return {
    id: "folder",
    owner_type: "anonymous",
    owner_id: "anon-1",
    name: "Main",
    is_default: 0,
    sort_order: 100,
    created_at: NOW,
    updated_at: NOW,
    ...overrides,
  };
}

function folderResponse(
  overrides: Partial<{
    id: string;
    name: string;
    is_default: boolean;
    sort_order: number;
    created_at: unknown;
    updated_at: unknown;
  }>,
): {
  id: string;
  name: string;
  is_default: boolean;
  sort_order: number;
  created_at: unknown;
  updated_at: unknown;
} {
  return {
    id: "folder",
    name: "Main",
    is_default: false,
    sort_order: 100,
    created_at: NOW,
    updated_at: NOW,
    ...overrides,
  };
}
