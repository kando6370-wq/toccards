import { PGliteDatabase } from "../test-support/pglite-database";
import { createPortfolioPostgresFixture, closePortfolioPostgresFixtures, seedPortfolioRows, readPortfolioRows } from "../test-support/portfolio-postgres-fixture";
import { signAccessToken } from "@kando/auth-core";
import { afterEach, describe, expect, it } from "vitest";
import app, { type Env } from "../index";

type OwnerType = "anonymous" | "user";

type WishlistRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
  card_ref: string;
  created_at: string;
};

type CollectionItemRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
  card_ref: string;
};

const JWT_SECRET = "test-secret";
const NOW = "2026-07-07T00:00:00.000Z";
const fixtureColumns = {
  wishlist_item: ["id", "owner_type", "owner_id", "card_ref", "created_at"],
};

afterEach(async () => { await closePortfolioPostgresFixtures(); });

describe("wishlist routes", () => {
  it("lists paged owner-isolated wishlist rows because wanting a card is private asset intent", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'wishlist_item', wishlist({ id: "older", card_ref: "card-a", created_at: "2026-01-01T00:00:00.000Z" }), wishlist({ id: "newer", card_ref: "card-b", created_at: "2026-02-01T00:00:00.000Z" }), wishlist({ id: "other", owner_type: "user", owner_id: "other", card_ref: "card-c" }));

    const response = await app.request(
      "/api/v1/wishlist?page=1&page_size=1&sort_by=created_at&sort_order=desc",
      { headers: await authHeaders("anonymous", "anon-1") },
      createTestEnv(db),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        items: [
          wishlistResponse({
            id: "newer",
            card_ref: "card-b",
            created_at: "2026-02-01T00:00:00.000Z",
          }),
        ],
        total: 2,
        page: 1,
        page_size: 1,
      },
    });
  });

  it("uses wishlist id as a stable tie-breaker because equal timestamps must not duplicate or skip wishes across pages", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    const createdAt = "2026-02-01T00:00:00.000Z";
    await seedPortfolioRows(db, 'wishlist_item', wishlist({ id: "wish-b", card_ref: "card-b", created_at: createdAt }), wishlist({ id: "wish-a", card_ref: "card-a", created_at: createdAt }));

    const [firstPage, secondPage] = await Promise.all([
      app.request(
        "/api/v1/wishlist?page=1&page_size=1&sort_by=created_at&sort_order=desc",
        { headers: await authHeaders("anonymous", "anon-1") },
        createTestEnv(db),
      ),
      app.request(
        "/api/v1/wishlist?page=2&page_size=1&sort_by=created_at&sort_order=desc",
        { headers: await authHeaders("anonymous", "anon-1") },
        createTestEnv(db),
      ),
    ]);
    const firstBody = await firstPage.json() as { data: { items: Array<{ id: string }> } };
    const secondBody = await secondPage.json() as { data: { items: Array<{ id: string }> } };

    expect(firstBody.data.items.map((entry) => entry.id)).toEqual(["wish-a"]);
    expect(secondBody.data.items.map((entry) => entry.id)).toEqual(["wish-b"]);
  });

  it("creates a wishlist row because search and card detail need to persist owner intent without a folder", async () => {
    const db = await createDbForOwner("user", "user-1");

    const response = await app.request(
      "/api/v1/wishlist",
      {
        method: "POST",
        headers: await authHeaders("user", "user-1"),
        body: JSON.stringify({ card_ref: "card-a" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({
      success: true,
      data: wishlistResponse({
        id: expect.any(String),
        card_ref: "card-a",
        created_at: expect.any(String),
      }),
    });
    expect((await readPortfolioRows<WishlistRow>(db, 'wishlist_item', fixtureColumns.wishlist_item))).toEqual([
      {
        id: expect.any(String),
        owner_type: "user",
        owner_id: "user-1",
        card_ref: "card-a",
        created_at: expect.any(String),
      },
    ]);
  });

  it("replays Wishlist Add after a lost response because retry must confirm the original intent", async () => {
    const db = await createDbForOwner("user", "user-1");
    const idempotencyKey = "66666666-6666-4666-8666-666666666666";
    const headers = {
      ...(await authHeaders("user", "user-1")),
      "Idempotency-Key": idempotencyKey,
    };
    const body = JSON.stringify({ card_ref: "card-a" });

    const created = await app.request(
      "/api/v1/wishlist",
      { method: "POST", headers, body },
      createTestEnv(db),
    );
    const replayed = await app.request(
      "/api/v1/wishlist",
      { method: "POST", headers, body },
      createTestEnv(db),
    );

    expect(created.status).toBe(201);
    expect(replayed.status).toBe(200);
    expect(await replayed.json()).toMatchObject({
      success: true,
      data: { id: idempotencyKey, card_ref: "card-a" },
    });
    expect((await readPortfolioRows<WishlistRow>(db, 'wishlist_item', fixtureColumns.wishlist_item))).toHaveLength(1);
  });

  it("rejects reusing a Wishlist Add key for another card because one key has one intent", async () => {
    const db = await createDbForOwner("user", "user-1");
    const headers = {
      ...(await authHeaders("user", "user-1")),
      "Idempotency-Key": "77777777-7777-4777-8777-777777777777",
    };
    await app.request(
      "/api/v1/wishlist",
      { method: "POST", headers, body: JSON.stringify({ card_ref: "card-a" }) },
      createTestEnv(db),
    );

    const response = await app.request(
      "/api/v1/wishlist",
      { method: "POST", headers, body: JSON.stringify({ card_ref: "card-b" }) },
      createTestEnv(db),
    );

    expect(response.status).toBe(409);
    expect((await readPortfolioRows<WishlistRow>(db, 'wishlist_item', fixtureColumns.wishlist_item))).toHaveLength(1);
  });

  it("returns CONFLICT for duplicate card_ref because one owner should have only one wishlist intent per card", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'wishlist_item', wishlist({ card_ref: "card-a" }));

    const response = await app.request(
      "/api/v1/wishlist",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ card_ref: "card-a" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      success: false,
      error: { code: "CONFLICT", message: "Conflict." },
    });
  });

  it("returns CONFLICT when the card is already in Portfolio because owned cards must not also stay wanted", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'collection_item', item({ card_ref: "card-a" }));

    const response = await app.request(
      "/api/v1/wishlist",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ card_ref: "card-a" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      success: false,
      error: { code: "CONFLICT", message: "Conflict." },
    });
    expect((await readPortfolioRows<WishlistRow>(db, 'wishlist_item', fixtureColumns.wishlist_item))).toEqual([]);
  });

  it("rejects blank card_ref because wishlist rows must identify a third-party card", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");

    const response = await app.request(
      "/api/v1/wishlist",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ card_ref: "   " }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({
      success: false,
      error: { code: "VALIDATION_ERROR", message: "Invalid request." },
    });
  });

  it("deletes only owned wishlist rows because removing intent must stay inside the owner boundary", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'wishlist_item', wishlist({ id: "owned", card_ref: "card-a" }), wishlist({ id: "other", owner_type: "user", owner_id: "other", card_ref: "card-b" }));

    const missing = await app.request(
      "/api/v1/wishlist/other",
      {
        method: "DELETE",
        headers: await authHeaders("anonymous", "anon-1"),
      },
      createTestEnv(db),
    );
    const remove = await app.request(
      "/api/v1/wishlist/owned",
      {
        method: "DELETE",
        headers: await authHeaders("anonymous", "anon-1"),
      },
      createTestEnv(db),
    );

    expect(missing.status).toBe(404);
    expect(await missing.json()).toEqual({
      success: false,
      error: { code: "NOT_FOUND", message: "Not found." },
    });
    expect(remove.status).toBe(200);
    expect(await remove.json()).toEqual({ success: true, data: {} });
    expect((await readPortfolioRows<WishlistRow>(db, 'wishlist_item', fixtureColumns.wishlist_item))).toEqual([
      wishlist({
        id: "other",
        owner_type: "user",
        owner_id: "other",
        card_ref: "card-b",
      }),
    ]);
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

function wishlist(overrides: Partial<WishlistRow>): WishlistRow {
  return {
    id: "wish",
    owner_type: "anonymous",
    owner_id: "anon-1",
    card_ref: "card-a",
    created_at: NOW,
    ...overrides,
  };
}

function item(overrides: Partial<CollectionItemRow>): CollectionItemRow {
  return {
    id: "item",
    owner_type: "anonymous",
    owner_id: "anon-1",
    card_ref: "card-a",
    ...overrides,
  };
}

function wishlistResponse(
  overrides: Partial<{
    id: unknown;
    card_ref: string;
    created_at: unknown;
  }>,
): {
  id: unknown;
  card_ref: string;
  created_at: unknown;
} {
  return {
    id: "wish",
    card_ref: "card-a",
    created_at: NOW,
    ...overrides,
  };
}
