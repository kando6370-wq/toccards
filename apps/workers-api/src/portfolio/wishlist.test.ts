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

type WishlistRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
  card_ref: string;
  created_at: string;
};

const JWT_SECRET = "test-secret";
const NOW = "2026-07-07T00:00:00.000Z";
const LATER = "2099-01-01T00:00:00.000Z";

class FakeD1Database {
  sessions: SessionRow[] = [];
  users: OwnerRow[] = [];
  anonymousAccounts: OwnerRow[] = [];
  wishlist: WishlistRow[] = [];

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
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

    if (this.sql.includes("FROM wishlist_item")) {
      const [ownerType, ownerId, itemId] = this.args;
      return (this.db.wishlist.find(
        (row) =>
          row.owner_type === ownerType &&
          row.owner_id === ownerId &&
          row.id === itemId,
      ) ?? null) as T | null;
    }

    return null;
  }

  async all<T>(): Promise<{ results: T[] }> {
    if (this.sql.includes("FROM wishlist_item")) {
      const [ownerType, ownerId] = this.args;
      return {
        results: this.db.wishlist.filter(
          (row) => row.owner_type === ownerType && row.owner_id === ownerId,
        ) as T[],
      };
    }

    return { results: [] };
  }

  async run(): Promise<{ success: true; meta: { changes: number } }> {
    if (this.sql.includes("INSERT INTO wishlist_item")) {
      const [id, ownerType, ownerId, cardRef, createdAt] = this.args as [
        string,
        OwnerType,
        string,
        string,
        string,
      ];

      if (
        this.db.wishlist.some(
          (row) =>
            row.owner_type === ownerType &&
            row.owner_id === ownerId &&
            row.card_ref === cardRef,
        )
      ) {
        throw new Error("UNIQUE constraint failed: wishlist_item.card_ref");
      }

      this.db.wishlist.push({
        id,
        owner_type: ownerType,
        owner_id: ownerId,
        card_ref: cardRef,
        created_at: createdAt,
      });

      return changed(1);
    }

    if (this.sql.includes("DELETE FROM wishlist_item")) {
      const [ownerType, ownerId, itemId] = this.args;
      const before = this.db.wishlist.length;
      this.db.wishlist = this.db.wishlist.filter(
        (row) =>
          !(
            row.owner_type === ownerType &&
            row.owner_id === ownerId &&
            row.id === itemId
          ),
      );

      return changed(before - this.db.wishlist.length);
    }

    return changed(0);
  }
}

describe("wishlist routes", () => {
  it("lists paged owner-isolated wishlist rows because wanting a card is private asset intent", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.wishlist.push(
      wishlist({ id: "older", card_ref: "card-a", created_at: "2026-01-01T00:00:00.000Z" }),
      wishlist({ id: "newer", card_ref: "card-b", created_at: "2026-02-01T00:00:00.000Z" }),
      wishlist({ id: "other", owner_type: "user", owner_id: "other", card_ref: "card-c" }),
    );

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

  it("creates a wishlist row because search and card detail need to persist owner intent without a folder", async () => {
    const db = createDbForOwner("user", "user-1");

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
    expect(db.wishlist).toEqual([
      {
        id: expect.any(String),
        owner_type: "user",
        owner_id: "user-1",
        card_ref: "card-a",
        created_at: expect.any(String),
      },
    ]);
  });

  it("returns CONFLICT for duplicate card_ref because one owner should have only one wishlist intent per card", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.wishlist.push(wishlist({ card_ref: "card-a" }));

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

  it("rejects blank card_ref because wishlist rows must identify a third-party card", async () => {
    const db = createDbForOwner("anonymous", "anon-1");

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
    const db = createDbForOwner("anonymous", "anon-1");
    db.wishlist.push(
      wishlist({ id: "owned", card_ref: "card-a" }),
      wishlist({ id: "other", owner_type: "user", owner_id: "other", card_ref: "card-b" }),
    );

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
    expect(db.wishlist).toEqual([
      wishlist({
        id: "other",
        owner_type: "user",
        owner_id: "other",
        card_ref: "card-b",
      }),
    ]);
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
