import { signAccessToken } from "@kando/auth-core";
import { describe, expect, it } from "vitest";
import app, { type Env } from "../index";

type OwnerType = "anonymous" | "user";

type SessionRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

type OwnerRow = {
  id: string;
  deleted_at?: string | null;
  upgraded_user_id?: string | null;
};

type FolderRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
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
  quantity: number;
  purchase_price: number | null;
  purchase_currency: string | null;
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
const LATER = "2099-01-01T00:00:00.000Z";

class FakeD1Database {
  sessions: SessionRow[] = [];
  users: OwnerRow[] = [];
  anonymousAccounts: OwnerRow[] = [];
  folders: FolderRow[] = [];
  items: CollectionItemRow[] = [];
  wishlist: WishlistRow[] = [];

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
  }

  async batch(statements: FakeD1Statement[]): Promise<unknown[]> {
    return Promise.all(statements.map((statement) => statement.run()));
  }
}

class FakeD1Statement {
  private args: unknown[] = [];

  constructor(
    private readonly db: FakeD1Database,
    private readonly sql: string,
  ) {}

  bind(...args: unknown[]): FakeD1Statement {
    this.args = args;
    return this;
  }

  async first<T>(): Promise<T | null> {
    if (this.sql.includes("FROM session")) {
      const [sessionId] = this.args;
      return (this.db.sessions.find((row) => row.id === sessionId) ??
        null) as T | null;
    }

    if (this.sql.includes("FROM anonymous_account")) {
      const [ownerId] = this.args;
      return (this.db.anonymousAccounts.find(
        (row) => row.id === ownerId && row.upgraded_user_id === null,
      ) ?? null) as T | null;
    }

    if (this.sql.includes("FROM user")) {
      const [ownerId] = this.args;
      return (this.db.users.find(
        (row) => row.id === ownerId && row.deleted_at === null,
      ) ?? null) as T | null;
    }

    if (this.sql.includes("FROM portfolio_folder")) {
      const [ownerType, ownerId, folderId] = this.args;
      return (this.db.folders.find(
        (row) =>
          row.owner_type === ownerType &&
          row.owner_id === ownerId &&
          row.id === folderId,
      ) ?? null) as T | null;
    }

    if (this.sql.includes("FROM collection_item")) {
      const [ownerType, ownerId, itemId] = this.args;
      return (this.db.items.find(
        (row) =>
          row.owner_type === ownerType &&
          row.owner_id === ownerId &&
          row.id === itemId,
      ) ?? null) as T | null;
    }

    return null;
  }

  async all<T>(): Promise<{ results: T[] }> {
    if (this.sql.includes("FROM collection_item")) {
      const [ownerType, ownerId] = this.args;
      return {
        results: this.db.items.filter(
          (row) => row.owner_type === ownerType && row.owner_id === ownerId,
        ) as T[],
      };
    }

    return { results: [] };
  }

  async run(): Promise<{ success: true; meta: { changes: number } }> {
    if (this.sql.includes("INSERT INTO collection_item")) {
      const [
        id,
        ownerType,
        ownerId,
        folderId,
        cardRef,
        objectType,
        grader,
        condition,
        grade,
        language,
        finish,
        quantity,
        purchasePrice,
        purchaseCurrency,
        notes,
        createdAt,
        updatedAt,
      ] = this.args as [
        string,
        OwnerType,
        string,
        string,
        string,
        string,
        string,
        string | null,
        number | null,
        string | null,
        string | null,
        number,
        number | null,
        string | null,
        string | null,
        string,
        string,
      ];

      this.db.items.push({
        id,
        owner_type: ownerType,
        owner_id: ownerId,
        folder_id: folderId,
        card_ref: cardRef,
        object_type: objectType,
        grader,
        condition,
        grade,
        language,
        finish,
        quantity,
        purchase_price: purchasePrice,
        purchase_currency: purchaseCurrency,
        notes,
        created_at: createdAt,
        updated_at: updatedAt,
      });

      return changed(1);
    }

    if (this.sql.includes("UPDATE collection_item") && this.sql.includes("SET grader")) {
      const [
        grader,
        condition,
        grade,
        language,
        finish,
        quantity,
        purchasePrice,
        purchaseCurrency,
        notes,
        updatedAt,
        ownerType,
        ownerId,
        itemId,
      ] = this.args as [
        string,
        string | null,
        number | null,
        string | null,
        string | null,
        number,
        number | null,
        string | null,
        string | null,
        string,
        OwnerType,
        string,
        string,
      ];
      const item = findItem(this.db, ownerType, ownerId, itemId);

      if (!item) return changed(0);

      Object.assign(item, {
        grader,
        condition,
        grade,
        language,
        finish,
        quantity,
        purchase_price: purchasePrice,
        purchase_currency: purchaseCurrency,
        notes,
        updated_at: updatedAt,
      });

      return changed(1);
    }

    if (this.sql.includes("UPDATE collection_item") && this.sql.includes("SET folder_id")) {
      const [folderId, updatedAt, ownerType, ownerId, itemId] = this.args as [
        string,
        string,
        OwnerType,
        string,
        string,
      ];
      const item = findItem(this.db, ownerType, ownerId, itemId);

      if (!item) return changed(0);

      item.folder_id = folderId;
      item.updated_at = updatedAt;
      return changed(1);
    }

    if (this.sql.includes("DELETE FROM collection_item")) {
      const [ownerType, ownerId, itemId] = this.args;
      const before = this.db.items.length;
      this.db.items = this.db.items.filter(
        (row) =>
          !(
            row.owner_type === ownerType &&
            row.owner_id === ownerId &&
            row.id === itemId
          ),
      );

      return changed(before - this.db.items.length);
    }

    if (this.sql.includes("DELETE FROM wishlist_item")) {
      const [ownerType, ownerId, cardRef] = this.args;
      const before = this.db.wishlist.length;
      this.db.wishlist = this.db.wishlist.filter(
        (row) =>
          !(
            row.owner_type === ownerType &&
            row.owner_id === ownerId &&
            row.card_ref === cardRef
          ),
      );

      return changed(before - this.db.wishlist.length);
    }

    return changed(0);
  }
}

describe("collection item routes", () => {
  it("lists paged owner-isolated collection items because portfolios must not leak between owners", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.folders.push(folder({ id: "main" }), folder({ id: "trade" }));
    db.items.push(
      item({ id: "older", folder_id: "main", card_ref: "card-a", created_at: "2026-01-01T00:00:00.000Z" }),
      item({ id: "newer", folder_id: "trade", card_ref: "card-b", created_at: "2026-02-01T00:00:00.000Z" }),
      item({ id: "other", owner_type: "user", owner_id: "other", folder_id: "other-folder" }),
    );

    const response = await app.request(
      "/api/v1/portfolio/items?page=1&page_size=1&sort_by=created_at&sort_order=desc",
      { headers: await authHeaders("anonymous", "anon-1") },
      createTestEnv(db),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        items: [itemResponse({ id: "newer", folder_id: "trade", card_ref: "card-b", created_at: "2026-02-01T00:00:00.000Z" })],
        total: 2,
        page: 1,
        page_size: 1,
      },
    });
  });

  it("creates a Raw collection item and removes the matching wishlist row because Collect transfers intent into ownership", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.folders.push(folder({ id: "main" }));
    db.wishlist.push({ owner_type: "anonymous", owner_id: "anon-1", card_ref: "card-a" });

    const response = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          folder_id: "main",
          card_ref: "card-a",
          object_type: "tcg",
          grader: "Raw",
          condition: "Near Mint",
          grade: null,
          language: "English",
          finish: "Holofoil",
          quantity: 2,
          purchase_price: 50,
          purchase_currency: "USD",
          notes: "first copy",
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
        card_ref: "card-a",
        condition: "Near Mint",
        quantity: 2,
        purchase_price: 50,
        purchase_currency: "USD",
        notes: "first copy",
        created_at: expect.any(String),
        updated_at: expect.any(String),
      }),
    });
    expect(db.wishlist).toEqual([]);
  });

  it("rejects grader and folder validation failures because collection valuation depends on consistent grading state", async () => {
    const db = createDbForOwner("user", "user-1");
    db.folders.push(folder({ id: "main", owner_type: "user", owner_id: "user-1" }));

    const badRaw = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers: await authHeaders("user", "user-1"),
        body: JSON.stringify({
          folder_id: "main",
          card_ref: "card-a",
          object_type: "tcg",
          grader: "Raw",
          condition: null,
          grade: null,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );
    const missingFolder = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers: await authHeaders("user", "user-1"),
        body: JSON.stringify({
          folder_id: "missing",
          card_ref: "card-a",
          object_type: "tcg",
          grader: "PSA",
          condition: null,
          grade: 9,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );

    expect(badRaw.status).toBe(422);
    expect(await badRaw.json()).toEqual({
      success: false,
      error: { code: "VALIDATION_ERROR", message: "Invalid request." },
    });
    expect(missingFolder.status).toBe(404);
    expect(await missingFolder.json()).toEqual({
      success: false,
      error: { code: "NOT_FOUND", message: "Not found." },
    });
  });

  it("gets, updates, moves, and deletes only owned collection items because item operations must stay inside the owner boundary", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.folders.push(folder({ id: "main" }), folder({ id: "trade" }));
    db.items.push(item({ id: "owned", folder_id: "main" }));

    const detail = await app.request(
      "/api/v1/portfolio/items/owned",
      { headers: await authHeaders("anonymous", "anon-1") },
      createTestEnv(db),
    );
    const update = await app.request(
      "/api/v1/portfolio/items/owned",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          grader: "PSA",
          grade: 10,
          condition: null,
          language: "Japanese",
          finish: "Foil",
          quantity: 3,
          purchase_price: null,
          purchase_currency: null,
          notes: "graded",
        }),
      },
      createTestEnv(db),
    );
    const move = await app.request(
      "/api/v1/portfolio/items/owned/move",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ folder_id: "trade" }),
      },
      createTestEnv(db),
    );
    const remove = await app.request(
      "/api/v1/portfolio/items/owned",
      {
        method: "DELETE",
        headers: await authHeaders("anonymous", "anon-1"),
      },
      createTestEnv(db),
    );

    expect(detail.status).toBe(200);
    expect(await detail.json()).toEqual({
      success: true,
      data: itemResponse({ id: "owned", folder_id: "main" }),
    });
    expect(update.status).toBe(200);
    expect(await update.json()).toEqual({
      success: true,
      data: itemResponse({
        id: "owned",
        folder_id: "main",
        grader: "PSA",
        condition: null,
        grade: 10,
        language: "Japanese",
        finish: "Foil",
        quantity: 3,
        notes: "graded",
        updated_at: expect.any(String),
      }),
    });
    expect(move.status).toBe(200);
    expect(await move.json()).toEqual({
      success: true,
      data: itemResponse({
        id: "owned",
        folder_id: "trade",
        grader: "PSA",
        condition: null,
        grade: 10,
        language: "Japanese",
        finish: "Foil",
        quantity: 3,
        notes: "graded",
        updated_at: expect.any(String),
      }),
    });
    expect(remove.status).toBe(200);
    expect(await remove.json()).toEqual({ success: true, data: {} });
    expect(db.items).toEqual([]);
  });
});

function findItem(
  db: FakeD1Database,
  ownerType: OwnerType,
  ownerId: string,
  itemId: string,
): CollectionItemRow | undefined {
  return db.items.find(
    (row) =>
      row.owner_type === ownerType &&
      row.owner_id === ownerId &&
      row.id === itemId,
  );
}

function changed(changes: number): { success: true; meta: { changes: number } } {
  return { success: true, meta: { changes } };
}

function createDbForOwner(ownerType: OwnerType, ownerId: string): FakeD1Database {
  const db = new FakeD1Database();

  db.sessions.push({
    id: sessionId(ownerType, ownerId),
    owner_type: ownerType,
    owner_id: ownerId,
    expires_at: LATER,
    revoked_at: null,
  });

  if (ownerType === "anonymous") {
    db.anonymousAccounts.push({ id: ownerId, upgraded_user_id: null });
  } else {
    db.users.push({ id: ownerId, deleted_at: null });
  }

  return db;
}

function createTestEnv(db = new FakeD1Database()): Env {
  return {
    DB: db as unknown as D1Database,
    CACHE_KV: {} as KVNamespace,
    JWT_SECRET: JWT_SECRET,
  };
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
    id: "main",
    owner_type: "anonymous",
    owner_id: "anon-1",
    ...overrides,
  };
}

function item(overrides: Partial<CollectionItemRow>): CollectionItemRow {
  return {
    id: "item",
    owner_type: "anonymous",
    owner_id: "anon-1",
    folder_id: "main",
    card_ref: "card-a",
    object_type: "tcg",
    grader: "Raw",
    condition: "Near Mint",
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
    condition: "Near Mint",
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
