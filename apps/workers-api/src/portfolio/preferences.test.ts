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
const LATER = "2099-01-01T00:00:00.000Z";

class FakeD1Database {
  sessions: SessionRow[] = [];
  users: OwnerRow[] = [];
  anonymousAccounts: OwnerRow[] = [];
  folders: FolderRow[] = [];
  preferences: PreferenceRow[] = [];

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

    if (this.sql.includes("FROM portfolio_folder")) {
      const [ownerType, ownerId, folderId] = this.args;
      return (this.db.folders.find(
        (row) =>
          row.owner_type === ownerType &&
          row.owner_id === ownerId &&
          row.id === folderId,
      ) ?? null) as T | null;
    }

    if (this.sql.includes("FROM user_preference")) {
      const [ownerType, ownerId] = this.args;
      return (this.db.preferences.find(
        (row) => row.owner_type === ownerType && row.owner_id === ownerId,
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
    if (this.sql.includes("UPDATE user_preference")) {
      const [
        currency,
        amountHidden,
        lastSelectedFolderId,
        updatedAt,
        ownerType,
        ownerId,
      ] = this.args as [
        string,
        number,
        string | null,
        string,
        OwnerType,
        string,
      ];
      const preference = this.db.preferences.find(
        (row) => row.owner_type === ownerType && row.owner_id === ownerId,
      );

      if (!preference) return changed(0);

      preference.currency = currency;
      preference.amount_hidden = amountHidden;
      preference.last_selected_folder_id = lastSelectedFolderId;
      preference.updated_at = updatedAt;
      return changed(1);
    }

    return changed(0);
  }
}

describe("preference routes", () => {
  it("gets only the authenticated owner's preferences because display settings are owner scoped", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.preferences.push(
      preference({ currency: "USD", amount_hidden: 0 }),
      preference({
        id: "other-pref",
        owner_type: "user",
        owner_id: "other",
        currency: "JPY",
        amount_hidden: 1,
      }),
    );

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
    const db = createDbForOwner("user", "user-1");
    db.preferences.push(
      preference({ owner_type: "user", owner_id: "user-1", currency: "USD" }),
    );
    db.folders.push({ id: "folder-1", owner_type: "user", owner_id: "user-1" });

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
    expect(db.preferences[0]).toMatchObject({
      currency: "JPY",
      amount_hidden: 1,
      last_selected_folder_id: "folder-1",
      updated_at: expect.any(String),
    });
  });

  it("rejects invalid preference values because downstream display code relies on normalized settings", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.preferences.push(preference({}));

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
    const db = createDbForOwner("anonymous", "anon-1");
    db.preferences.push(preference({}));
    db.folders.push({ id: "folder-1", owner_type: "user", owner_id: "other" });

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
