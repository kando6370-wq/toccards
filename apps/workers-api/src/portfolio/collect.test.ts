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

    if (this.sql.includes("FROM portfolio_folder") && this.sql.includes("is_default = 1")) {
      const [ownerType, ownerId] = this.args;
      return (this.db.folders.find(
        (row) =>
          row.owner_type === ownerType &&
          row.owner_id === ownerId &&
          row.is_default === 1,
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

    if (this.sql.includes("FROM user")) {
      const [ownerId] = this.args;
      return (this.db.users.find(
        (row) => row.id === ownerId && row.deleted_at === null,
      ) ?? null) as T | null;
    }

    return null;
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

describe("collect shortcut route", () => {
  it("creates a collection item from the path card_ref and removes wishlist intent because Collect moves a wanted card into ownership", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.folders.push(folder({ id: "main", is_default: 1 }), folder({ id: "trade" }));
    db.wishlist.push({ owner_type: "anonymous", owner_id: "anon-1", card_ref: "card-a" });

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
    expect(db.wishlist).toEqual([]);
  });

  it("uses the default folder when folder_id is null because the shortcut supports one-tap Collect without folder picking", async () => {
    const db = createDbForOwner("user", "user-1");
    db.folders.push(
      folder({ id: "main", owner_type: "user", owner_id: "user-1", is_default: 1 }),
      folder({ id: "trade", owner_type: "user", owner_id: "user-1" }),
    );

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

  it("rejects invalid grading and another owner's folder because Collect must preserve collection item invariants", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.folders.push(
      folder({ id: "main", is_default: 1 }),
      folder({ id: "other-folder", owner_type: "user", owner_id: "other" }),
    );

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
