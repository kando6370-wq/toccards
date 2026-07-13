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

type PreferenceRow = {
  owner_type: OwnerType;
  owner_id: string;
  last_selected_folder_id: string | null;
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

    return null;
  }

  async all<T>(): Promise<{ results: T[] }> {
    if (this.sql.includes("FROM portfolio_folder")) {
      const [ownerType, ownerId] = this.args;
      const results = this.db.folders
        .filter((row) => row.owner_type === ownerType && row.owner_id === ownerId)
        .sort((left, right) => left.sort_order - right.sort_order);

      return { results: results as T[] };
    }

    return { results: [] };
  }

  async run(): Promise<{ success: true; meta: { changes: number } }> {
    if (this.sql.includes("INSERT INTO portfolio_folder")) {
      const [id, ownerType, ownerId, name, sortOrder, createdAt, updatedAt] =
        this.args as [string, OwnerType, string, string, number, string, string];

      if (
        this.db.folders.some(
          (row) =>
            row.owner_type === ownerType &&
            row.owner_id === ownerId &&
            row.name === name,
        )
      ) {
        throw new Error("UNIQUE constraint failed: portfolio_folder.name");
      }

      this.db.folders.push({
        id,
        owner_type: ownerType,
        owner_id: ownerId,
        name,
        is_default: 0,
        sort_order: sortOrder,
        created_at: createdAt,
        updated_at: updatedAt,
      });

      return changed(1);
    }

    if (this.sql.includes("UPDATE portfolio_folder") && this.sql.includes("name =")) {
      const [name, updatedAt, ownerType, ownerId, folderId] = this.args as [
        string,
        string,
        OwnerType,
        string,
        string,
      ];
      const duplicate = this.db.folders.some(
        (row) =>
          row.owner_type === ownerType &&
          row.owner_id === ownerId &&
          row.name === name &&
          row.id !== folderId,
      );

      if (duplicate) {
        throw new Error("UNIQUE constraint failed: portfolio_folder.name");
      }

      const folder = this.db.folders.find(
        (row) =>
          row.owner_type === ownerType &&
          row.owner_id === ownerId &&
          row.id === folderId,
      );

      if (!folder) return changed(0);

      folder.name = name;
      folder.updated_at = updatedAt;
      return changed(1);
    }

    if (this.sql.includes("DELETE FROM portfolio_folder")) {
      const [ownerType, ownerId, folderId] = this.args;
      const before = this.db.folders.length;
      this.db.folders = this.db.folders.filter(
        (row) =>
          !(
            row.owner_type === ownerType &&
            row.owner_id === ownerId &&
            row.id === folderId
          ),
      );
      return changed(before - this.db.folders.length);
    }

    if (this.sql.includes("UPDATE user_preference")) {
      const [ownerType, ownerId, folderId] = this.args;
      let changes = 0;

      for (const preference of this.db.preferences) {
        if (
          preference.owner_type === ownerType &&
          preference.owner_id === ownerId &&
          preference.last_selected_folder_id === folderId
        ) {
          preference.last_selected_folder_id = null;
          changes += 1;
        }
      }

      return changed(changes);
    }

    if (this.sql.includes("SET is_default = 0")) {
      const [updatedAt, ownerType, ownerId] = this.args as [
        string,
        OwnerType,
        string,
      ];
      let changes = 0;

      for (const folder of this.db.folders) {
        if (folder.owner_type === ownerType && folder.owner_id === ownerId) {
          folder.is_default = 0;
          folder.updated_at = updatedAt;
          changes += 1;
        }
      }

      return changed(changes);
    }

    if (this.sql.includes("SET is_default = 1")) {
      const [updatedAt, ownerType, ownerId, folderId] = this.args as [
        string,
        OwnerType,
        string,
        string,
      ];
      const folder = this.db.folders.find(
        (row) =>
          row.owner_type === ownerType &&
          row.owner_id === ownerId &&
          row.id === folderId,
      );

      if (!folder) return changed(0);

      folder.is_default = 1;
      folder.updated_at = updatedAt;
      return changed(1);
    }

    if (this.sql.includes("sort_order =")) {
      const [sortOrder, updatedAt, ownerType, ownerId, folderId] = this.args as [
        number,
        string,
        OwnerType,
        string,
        string,
      ];
      const folder = this.db.folders.find(
        (row) =>
          row.owner_type === ownerType &&
          row.owner_id === ownerId &&
          row.id === folderId,
      );

      if (!folder) return changed(0);

      folder.sort_order = sortOrder;
      folder.updated_at = updatedAt;
      return changed(1);
    }

    return changed(0);
  }
}

describe("portfolio folder routes", () => {
  it("rejects missing bearer tokens because asset data must never be inferred without owner proof", async () => {
    const response = await app.request(
      "/api/v1/portfolio/folders",
      {},
      createTestEnv(),
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({
      success: false,
      error: { code: "UNAUTHORIZED", message: "Unauthorized." },
    });
  });

  it("lists only the authenticated owner's folders in sort order because portfolio data is owner isolated", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.folders.push(
      folder({ id: "other-folder", owner_type: "user", owner_id: "other" }),
      folder({ id: "binder", name: "Binder", sort_order: 100 }),
      folder({ id: "main", name: "Main", is_default: 1, sort_order: 0 }),
    );

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

  it("creates a non-default folder after the current owner's last sort order because new folders should not disturb Main", async () => {
    const db = createDbForOwner("user", "user-1");
    db.folders.push(
      folder({
        id: "main",
        owner_type: "user",
        owner_id: "user-1",
        is_default: 1,
        sort_order: 0,
      }),
    );

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

  it("returns CONFLICT when creating a duplicate folder name because owner folder names are unique", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.folders.push(folder({ id: "main", name: "Main" }));

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
    const db = createDbForOwner("anonymous", "anon-1");

    const create = await app.request(
      "/api/v1/portfolio/folders",
      {
        method: "POST",
        headers: { ...(await authHeaders("anonymous", "anon-1")) },
        body: JSON.stringify({ name: "A".repeat(51) }),
      },
      createTestEnv(db),
    );
    db.folders.push(folder({ id: "trade", name: "Trade" }));
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
    const db = createDbForOwner("user", "user-1");
    db.folders.push(
      folder({ id: "main", owner_type: "user", owner_id: "user-1", is_default: 1 }),
      folder({ id: "trade", owner_type: "user", owner_id: "user-1", name: "Trade" }),
    );

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
    const db = createDbForOwner("anonymous", "anon-1");
    db.folders.push(folder({ id: "main", is_default: 1 }), folder({ id: "trade", name: "Trade" }));
    db.preferences.push({
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
    expect(db.folders.map((row) => row.id)).toEqual(["main"]);
    expect(db.preferences[0]?.last_selected_folder_id).toBeNull();
  });

  it("sets one default folder and reorders owned folders because folder state must remain consistent per owner", async () => {
    const db = createDbForOwner("anonymous", "anon-1");
    db.folders.push(
      folder({ id: "main", is_default: 1, sort_order: 0 }),
      folder({ id: "trade", name: "Trade", sort_order: 100 }),
    );

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
    db.anonymousAccounts.push({
      id: ownerId,
      upgraded_user_id: null,
    });
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
