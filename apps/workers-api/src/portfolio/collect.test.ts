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

type CollectionItemRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
  folder_id: string;
  card_ref: string;
  object_type: string;
  grader: string;
  condition: string | null;
  grade: number | null;
  language: string | null;
  finish: string | null;
  price_series_id: number | null;
  quantity: number;
  purchase_price: number | null;
  purchase_currency: string | null;
  performance_start_at: string;
  purchase_price_effective_at: string;
  performance_history_available_from: string;
  notes: string | null;
  created_at: string;
  updated_at: string;
};

type WishlistRow = {
  owner_type: OwnerType;
  owner_id: string;
  card_ref: string;
};

const JWT_SECRET = "test-secret";
const NOW = "2026-07-07T00:00:00.000Z";
const fixtureColumns = {
  wishlist_item: ["owner_type", "owner_id", "card_ref"],
  collection_item: ["id", "owner_type", "owner_id", "folder_id", "card_ref", "object_type", "grader", "condition", "grade", "language", "finish", "price_series_id", "quantity", "purchase_price", "purchase_currency", "performance_start_at", "purchase_price_effective_at", "performance_history_available_from", "notes", "created_at", "updated_at"],
};

afterEach(async () => { await closePortfolioPostgresFixtures(); });

describe("collect shortcut route", () => {
  it("creates a collection item from the path card_ref and removes wishlist intent because Collect moves a wanted card into ownership", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", is_default: 1 }), folder({ id: "trade", name: "Trade" }));
    await seedPortfolioRows(db, 'wishlist_item', { owner_type: "anonymous", owner_id: "anon-1", card_ref: "card-a" });

    const response = await app.request(
      "/api/v1/cards/card-a/collect",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          folder_id: "trade",
          object_type: "tcg",
          grader: "Raw",
          condition: "Near Mint (NM)",
          grade: null,
          language: "English",
          finish: "Holofoil",
          quantity: 2,
          purchase_price: 50,
          purchase_currency: "USD",
          notes: "quick add",
        }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({
      success: true,
      data: itemResponse({
        id: expect.any(String),
        folder_id: "trade",
        card_ref: "card-a",
        quantity: 2,
        purchase_price: 50,
        purchase_currency: "USD",
        notes: "quick add",
        created_at: expect.any(String),
        updated_at: expect.any(String),
      }),
    });
    expect((await readPortfolioRows<WishlistRow>(db, 'wishlist_item', fixtureColumns.wishlist_item))).toEqual([]);
  });

  it("replays Quick Collect after a lost response because one-tap retries must not become duplicate errors", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", is_default: 1 }));
    const idempotencyKey = "55555555-5555-4555-8555-555555555555";
    const headers = {
      ...(await authHeaders("anonymous", "anon-1")),
      "Idempotency-Key": idempotencyKey,
    };
    const body = JSON.stringify({
      folder_id: "main",
      object_type: "tcg",
      grader: "Raw",
      condition: "Near Mint (NM)",
      grade: null,
      language: "English",
      finish: "Holofoil",
      quantity: 1,
    });

    const created = await app.request(
      "/api/v1/cards/card-a/collect",
      { method: "POST", headers, body },
      createTestEnv(db),
    );
    const replayed = await app.request(
      "/api/v1/cards/card-a/collect",
      { method: "POST", headers, body },
      createTestEnv(db),
    );

    expect(created.status).toBe(201);
    expect(replayed.status).toBe(200);
    expect(await replayed.json()).toMatchObject({
      success: true,
      data: { id: idempotencyKey, card_ref: "card-a" },
    });
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toHaveLength(1);
  });

  it("uses the default folder when folder_id is null because the shortcut supports one-tap Collect without folder picking", async () => {
    const db = await createDbForOwner("user", "user-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", owner_type: "user", owner_id: "user-1", is_default: 1 }), folder({ id: "trade", owner_type: "user", owner_id: "user-1", name: "Trade" }));

    const response = await app.request(
      "/api/v1/cards/card-b/collect",
      {
        method: "POST",
        headers: await authHeaders("user", "user-1"),
        body: JSON.stringify({
          folder_id: null,
          object_type: "sealed",
          grader: "Raw",
          condition: null,
          grade: null,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({
      success: true,
      data: itemResponse({
        id: expect.any(String),
        folder_id: "main",
        card_ref: "card-b",
        object_type: "sealed",
        condition: null,
        finish: null,
        language: null,
        created_at: expect.any(String),
        updated_at: expect.any(String),
      }),
    });
  });

  it("allows different grading while rejecting an exact collection item duplicate", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", is_default: 1 }));
    await seedPortfolioRows(db, 'collection_item', {
      id: "owned", owner_type: "anonymous", owner_id: "anon-1", folder_id: "main",
      card_ref: "card-a", object_type: "tcg", grader: "Raw", condition: "Near Mint (NM)",
      grade: null, language: "English", finish: "Holofoil", quantity: 1,
      price_series_id: null,
      purchase_price: null, purchase_currency: null,
      performance_start_at: NOW, purchase_price_effective_at: NOW,
      performance_history_available_from: NOW,
      notes: null, created_at: NOW, updated_at: NOW,
    });
    const headers = await authHeaders("anonymous", "anon-1");
    const request = (finish: string) => app.request("/api/v1/cards/card-a/collect", {
      method: "POST",
      headers,
      body: JSON.stringify({ folder_id: "main", object_type: "tcg", grader: "Raw", condition: "Near Mint (NM)", grade: null, language: "English", finish, quantity: 1 }),
    }, createTestEnv(db));

    const differentGrading = await app.request("/api/v1/cards/card-a/collect", {
      method: "POST", headers,
      body: JSON.stringify({ folder_id: "main", object_type: "tcg", grader: "PSA", condition: null, grade: 10, language: "English", finish: "Holofoil", quantity: 1 }),
    }, createTestEnv(db));
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toHaveLength(2);
    const duplicate = await request("Holofoil");
    const distinct = await request("Reverse Holofoil");

    expect(differentGrading.status).toBe(201);
    expect(duplicate.status).toBe(409);
    expect(await duplicate.json()).toMatchObject({ error: { code: "DUPLICATE_COLLECTION_ITEM" } });
    expect(distinct.status).toBe(201);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toHaveLength(3);
  });

  it("rejects invalid grading and another owner's folder because Collect must preserve collection item invariants", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", is_default: 1 }), folder({ id: "other-folder", owner_type: "user", owner_id: "other" }));

    const invalidGrading = await app.request(
      "/api/v1/cards/card-c/collect",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          folder_id: "main",
          object_type: "tcg",
          grader: "Raw",
          condition: null,
          grade: null,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );
    const otherFolder = await app.request(
      "/api/v1/cards/card-c/collect",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          folder_id: "other-folder",
          object_type: "tcg",
          grader: "PSA",
          condition: null,
          grade: 9,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );

    expect(invalidGrading.status).toBe(422);
    expect(await invalidGrading.json()).toEqual({
      success: false,
      error: { code: "VALIDATION_ERROR", message: "Invalid request." },
    });
    expect(otherFolder.status).toBe(404);
    expect(await otherFolder.json()).toEqual({
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

function itemResponse(
  overrides: Partial<{
    id: unknown;
    folder_id: string;
    card_ref: string;
    object_type: string;
    grader: string;
    condition: string | null;
    grade: number | null;
    language: string | null;
    finish: string | null;
    quantity: number;
    purchase_price: number | null;
    purchase_currency: string | null;
    notes: string | null;
    created_at: unknown;
    updated_at: unknown;
  }>,
): {
  id: unknown;
  folder_id: string;
  card_ref: string;
  object_type: string;
  grader: string;
  condition: string | null;
  grade: number | null;
  language: string | null;
  finish: string | null;
  quantity: number;
  purchase_price: number | null;
  purchase_currency: string | null;
  notes: string | null;
  created_at: unknown;
  updated_at: unknown;
} {
  return {
    id: "item",
    folder_id: "main",
    card_ref: "card-a",
    object_type: "tcg",
    grader: "Raw",
    condition: "Near Mint (NM)",
    grade: null,
    language: "English",
    finish: "Holofoil",
    quantity: 1,
    purchase_price: null,
    purchase_currency: null,
    notes: null,
    created_at: NOW,
    updated_at: NOW,
    ...overrides,
  };
}
