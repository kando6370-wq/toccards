import { hashPassword, signAccessToken } from "@kando/auth-core";
import { describe, expect, it } from "vitest";
import app, { type Env as AppEnv } from "../index";

type TestEnv = AppEnv & { JWT_SECRET: string };

type AdminRole = "super_admin" | "operator";
type AdminStatus = "active" | "disabled";
type FeedbackStatus = "open" | "in_progress" | "closed";

type AdminUserRow = {
  id: string;
  email: string;
  password_hash: string;
  role: AdminRole;
  status: AdminStatus;
  created_at: string;
};

type SessionRow = {
  id: string;
  owner_type: "admin" | "user" | "anonymous";
  owner_id: string;
  refresh_token: string;
  expires_at: string;
  created_at: string;
  revoked_at: string | null;
};

type UserRow = {
  id: string;
  email: string;
  password_hash: string | null;
  display_name: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

type AnonymousAccountRow = {
  id: string;
  device_id: string;
  created_at: string;
  upgraded_user_id: string | null;
};

type FeedbackTicketRow = {
  id: string;
  email: string;
  types: string;
  functions: string;
  message: string;
  status: FeedbackStatus;
  created_at: string;
  updated_at: string;
};

type AppConfigRow = {
  key: string;
  value: string;
  updated_by: string | null;
  updated_at: string;
};

type TrendingPinRow = {
  id: string;
  card_ref: string;
  rank: number;
  active: number;
  updated_by: string | null;
  updated_at: string;
};

type CardOverrideRow = {
  id: string;
  card_ref: string;
  override_fields: string | null;
  image_url: string | null;
  is_missing_card: number;
  updated_by: string | null;
  updated_at: string;
};

type AdminLoginResponse = {
  success: true;
  data: {
    admin_id: string;
    email: string;
    role: AdminRole;
    access_token: string;
    refresh_token: string;
    expires_in: number;
  };
};

class FakeD1 {
  adminUsers: AdminUserRow[] = [];
  sessions: SessionRow[] = [];
  users: UserRow[] = [];
  anonymousAccounts: AnonymousAccountRow[] = [];
  feedbackTickets: FeedbackTicketRow[] = [];
  appConfigs: AppConfigRow[] = [];
  trendingPins: TrendingPinRow[] = [];
  cardOverrides: CardOverrideRow[] = [];

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
  }
}

class FakeD1Statement {
  private values: unknown[] = [];

  constructor(
    private readonly db: FakeD1,
    private readonly sql: string,
  ) {}

  bind(...values: unknown[]): FakeD1Statement {
    this.values = values;
    return this;
  }

  async first<T = unknown>(): Promise<T | null> {
    const sql = normalizeSql(this.sql);

    if (sql.includes("FROM admin_user") && sql.includes("WHERE email = ?")) {
      const [email] = this.values as [string];
      return (this.db.adminUsers.find((row) => row.email === email) ?? null) as T | null;
    }

    if (sql.includes("FROM admin_user") && sql.includes("WHERE id = ?")) {
      const [id] = this.values as [string];
      return (this.db.adminUsers.find((row) => row.id === id) ?? null) as T | null;
    }

    if (sql.includes("FROM session") && sql.includes("WHERE refresh_token = ?")) {
      const [refreshToken] = this.values as [string];
      return (this.db.sessions.find((row) => row.refresh_token === refreshToken) ?? null) as T | null;
    }

    if (sql.includes("FROM session") && sql.includes("WHERE id = ?")) {
      const [id] = this.values as [string];
      return (this.db.sessions.find((row) => row.id === id) ?? null) as T | null;
    }

    if (sql.includes("FROM user") && sql.includes("WHERE id = ?")) {
      const [id] = this.values as [string];
      return (this.db.users.find((row) => row.id === id) ?? null) as T | null;
    }

    if (sql.includes("FROM anonymous_account") && sql.includes("WHERE id = ?")) {
      const [id] = this.values as [string];
      return (this.db.anonymousAccounts.find((row) => row.id === id) ?? null) as T | null;
    }

    if (sql.includes("FROM feedback_ticket") && sql.includes("WHERE id = ?")) {
      const [id] = this.values as [string];
      return (this.db.feedbackTickets.find((row) => row.id === id) ?? null) as T | null;
    }

    if (sql.includes("FROM trending_pin") && sql.includes("WHERE id = ?")) {
      const [id] = this.values as [string];
      return (this.db.trendingPins.find((row) => row.id === id) ?? null) as T | null;
    }

    if (sql.includes("FROM card_override") && sql.includes("WHERE id = ?")) {
      const [id] = this.values as [string];
      return (this.db.cardOverrides.find((row) => row.id === id) ?? null) as T | null;
    }

    if (sql.includes("FROM card_override") && sql.includes("WHERE card_ref = ?")) {
      const [cardRef] = this.values as [string];
      return (this.db.cardOverrides.find((row) => row.card_ref === cardRef) ?? null) as T | null;
    }

    throw new Error(`Unsupported first SQL: ${sql}`);
  }

  async all<T = unknown>(): Promise<D1Result<T>> {
    const sql = normalizeSql(this.sql);

    if (sql.includes("FROM user") && sql.includes("UNION ALL")) {
      const [type, q] = this.values as [string | null, string | null];
      const query = q?.toLowerCase() ?? "";
      const formalUsers = this.db.users
        .filter(() => !type || type === "user")
        .filter((row) => !query || row.email.toLowerCase().includes(query))
        .map((row) => ({
          account_type: "user",
          id: row.id,
          email: row.email,
          device_id: null,
          created_at: row.created_at,
          status: row.deleted_at ? "disabled" : "active",
        }));
      const anonymousUsers = this.db.anonymousAccounts
        .filter(() => !type || type === "anonymous")
        .filter((row) => !query || row.device_id.toLowerCase().includes(query))
        .map((row) => ({
          account_type: "anonymous",
          id: row.id,
          email: null,
          device_id: row.device_id,
          created_at: row.created_at,
          status: row.upgraded_user_id ? "upgraded" : "guest",
        }));
      return okResult<T>([...formalUsers, ...anonymousUsers] as T[]);
    }

    if (sql.includes("FROM feedback_ticket")) {
      const [status] = this.values as [FeedbackStatus | null];
      return okResult<T>(
        this.db.feedbackTickets.filter((row) => !status || row.status === status) as T[],
      );
    }

    if (sql.includes("FROM app_config")) {
      return okResult<T>(this.db.appConfigs as T[]);
    }

    if (sql.includes("FROM trending_pin")) {
      return okResult<T>([...this.db.trendingPins].sort((left, right) => left.rank - right.rank) as T[]);
    }

    if (sql.includes("FROM card_override")) {
      return okResult<T>(this.db.cardOverrides as T[]);
    }

    throw new Error(`Unsupported all SQL: ${sql}`);
  }

  async run<T = unknown>(): Promise<D1Result<T>> {
    const sql = normalizeSql(this.sql);

    if (sql.startsWith("INSERT INTO session")) {
      const [id, ownerType, ownerId, refreshToken, expiresAt, createdAt] = this.values as [
        string,
        "admin",
        string,
        string,
        string,
        string,
      ];
      this.db.sessions.push({
        id,
        owner_type: ownerType,
        owner_id: ownerId,
        refresh_token: refreshToken,
        expires_at: expiresAt,
        created_at: createdAt,
        revoked_at: null,
      });
      return okResult<T>();
    }

    if (sql.startsWith("UPDATE session SET revoked_at")) {
      const [revokedAt, id] = this.values as [string, string];
      const session = this.db.sessions.find((row) => row.id === id && row.revoked_at === null);
      if (session) session.revoked_at = revokedAt;
      return okResult<T>(undefined, session ? 1 : 0);
    }

    if (sql.startsWith("UPDATE user SET deleted_at")) {
      const [deletedAt, id] = this.values as [string, string];
      const user = this.db.users.find((row) => row.id === id && row.deleted_at === null);
      if (user) user.deleted_at = deletedAt;
      return okResult<T>(undefined, user ? 1 : 0);
    }

    if (sql.startsWith("UPDATE feedback_ticket SET status")) {
      const [status, updatedAt, id] = this.values as [FeedbackStatus, string, string];
      const ticket = this.db.feedbackTickets.find((row) => row.id === id);
      if (ticket) {
        ticket.status = status;
        ticket.updated_at = updatedAt;
      }
      return okResult<T>(undefined, ticket ? 1 : 0);
    }

    if (sql.startsWith("INSERT INTO app_config")) {
      const [key, value, updatedBy, updatedAt] = this.values as [string, string, string, string];
      const row = this.db.appConfigs.find((config) => config.key === key);
      if (row) {
        row.value = value;
        row.updated_by = updatedBy;
        row.updated_at = updatedAt;
      } else {
        this.db.appConfigs.push({ key, value, updated_by: updatedBy, updated_at: updatedAt });
      }
      return okResult<T>();
    }

    if (sql.startsWith("INSERT INTO trending_pin")) {
      const [id, cardRef, rank, active, updatedBy, updatedAt] = this.values as [
        string,
        string,
        number,
        number,
        string,
        string,
      ];
      this.db.trendingPins.push({
        id,
        card_ref: cardRef,
        rank,
        active,
        updated_by: updatedBy,
        updated_at: updatedAt,
      });
      return okResult<T>();
    }

    if (sql.startsWith("UPDATE trending_pin SET")) {
      const [rank, active, updatedBy, updatedAt, id] = this.values as [number, number, string, string, string];
      const row = this.db.trendingPins.find((pin) => pin.id === id);
      if (row) {
        row.rank = rank;
        row.active = active;
        row.updated_by = updatedBy;
        row.updated_at = updatedAt;
      }
      return okResult<T>(undefined, row ? 1 : 0);
    }

    if (sql.startsWith("DELETE FROM trending_pin")) {
      const [id] = this.values as [string];
      const before = this.db.trendingPins.length;
      this.db.trendingPins = this.db.trendingPins.filter((row) => row.id !== id);
      return okResult<T>(undefined, before - this.db.trendingPins.length);
    }

    if (sql.startsWith("INSERT INTO card_override")) {
      const [id, cardRef, fields, imageUrl, isMissingCard, updatedBy, updatedAt] = this.values as [
        string,
        string,
        string | null,
        string | null,
        number,
        string,
        string,
      ];
      this.db.cardOverrides.push({
        id,
        card_ref: cardRef,
        override_fields: fields,
        image_url: imageUrl,
        is_missing_card: isMissingCard,
        updated_by: updatedBy,
        updated_at: updatedAt,
      });
      return okResult<T>();
    }

    if (sql.startsWith("UPDATE card_override SET")) {
      const [fields, imageUrl, isMissingCard, updatedBy, updatedAt, id] = this.values as [
        string | null,
        string | null,
        number,
        string,
        string,
        string,
      ];
      const row = this.db.cardOverrides.find((override) => override.id === id);
      if (row) {
        row.override_fields = fields;
        row.image_url = imageUrl;
        row.is_missing_card = isMissingCard;
        row.updated_by = updatedBy;
        row.updated_at = updatedAt;
      }
      return okResult<T>(undefined, row ? 1 : 0);
    }

    if (sql.startsWith("UPDATE card_override_IMAGE")) {
      return okResult<T>();
    }

    if (sql.startsWith("DELETE FROM card_override")) {
      const [id] = this.values as [string];
      const before = this.db.cardOverrides.length;
      this.db.cardOverrides = this.db.cardOverrides.filter((row) => row.id !== id);
      return okResult<T>(undefined, before - this.db.cardOverrides.length);
    }

    throw new Error(`Unsupported run SQL: ${sql}`);
  }
}

describe("admin routes", () => {
  it("issues isolated Admin tokens because App tokens must never authorize the back office", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "admin-1", "admin@example.com", "correct-password", "super_admin");

    const login = await loginAdmin(env, "admin@example.com", "correct-password");
    const appToken = await signAccessToken(
      { owner_type: "user", owner_id: "user-1", session_id: "session-1" },
      env.JWT_SECRET,
    );

    const adminResponse = await requestAdmin(env, "/users", "GET", undefined, login.data.access_token);
    const appTokenResponse = await requestAdmin(env, "/users", "GET", undefined, appToken);

    expect(login.data).toEqual(
      expect.objectContaining({
        admin_id: "admin-1",
        email: "admin@example.com",
        role: "super_admin",
        expires_in: 900,
      }),
    );
    expect(env.DB.sessions).toEqual([
      expect.objectContaining({ owner_type: "admin", owner_id: "admin-1", revoked_at: null }),
    ]);
    expect(adminResponse.status).toBe(200);
    expect(appTokenResponse.status).toBe(401);
  });

  it("revokes Admin refresh sessions because logout must close the back-office session", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "admin-2", "ops@example.com", "correct-password", "operator");
    const login = await loginAdmin(env, "ops@example.com", "correct-password");

    const refreshResponse = await requestAdmin(env, "/auth/refresh", "POST", {
      refresh_token: login.data.refresh_token,
    });
    const logoutResponse = await requestAdmin(
      env,
      "/auth/logout",
      "POST",
      { refresh_token: login.data.refresh_token },
      login.data.access_token,
    );
    const refreshAfterLogoutResponse = await requestAdmin(env, "/auth/refresh", "POST", {
      refresh_token: login.data.refresh_token,
    });

    expect(refreshResponse.status).toBe(200);
    expect(logoutResponse.status).toBe(200);
    expect(env.DB.sessions[0]?.revoked_at).not.toBeNull();
    expect(refreshAfterLogoutResponse.status).toBe(401);
  });

  it("lists formal and anonymous users together because support needs one search surface", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "admin-3", "support@example.com", "correct-password", "operator");
    env.DB.users.push(userRow("user-1", "collector@example.com"));
    env.DB.anonymousAccounts.push({
      id: "anon-1",
      device_id: "ios-device-1",
      created_at: "2026-07-07T00:00:00.000Z",
      upgraded_user_id: null,
    });
    const login = await loginAdmin(env, "support@example.com", "correct-password");

    const response = await requestAdmin(env, "/users", "GET", undefined, login.data.access_token);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        items: [
          expect.objectContaining({ account_type: "user", id: "user-1", status: "active" }),
          expect.objectContaining({ account_type: "anonymous", id: "anon-1", status: "guest" }),
        ],
        page: 1,
        page_size: 20,
      },
    });
  });

  it("allows only super_admin to disable users because account shutdown is high risk", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "operator-1", "operator@example.com", "correct-password", "operator");
    await seedAdmin(env, "super-1", "super@example.com", "correct-password", "super_admin");
    env.DB.users.push(userRow("user-disable", "disable@example.com"));
    const operatorLogin = await loginAdmin(env, "operator@example.com", "correct-password");
    const superLogin = await loginAdmin(env, "super@example.com", "correct-password");

    const operatorResponse = await requestAdmin(
      env,
      "/users/user/user-disable/disable",
      "PATCH",
      {},
      operatorLogin.data.access_token,
    );
    const superResponse = await requestAdmin(
      env,
      "/users/user/user-disable/disable",
      "PATCH",
      {},
      superLogin.data.access_token,
    );

    expect(operatorResponse.status).toBe(403);
    expect(superResponse.status).toBe(200);
    expect(env.DB.users[0]?.deleted_at).not.toBeNull();
  });

  it("lets operators advance feedback and app config because daily operations should not need super_admin", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "operator-2", "daily@example.com", "correct-password", "operator");
    env.DB.feedbackTickets.push({
      id: "ticket-1",
      email: "player@example.com",
      types: JSON.stringify(["Bug Report"]),
      functions: JSON.stringify(["Search"]),
      message: "Search failed.",
      status: "open",
      created_at: "2026-07-07T00:00:00.000Z",
      updated_at: "2026-07-07T00:00:00.000Z",
    });
    const login = await loginAdmin(env, "daily@example.com", "correct-password");

    const feedbackResponse = await requestAdmin(
      env,
      "/feedbacks/ticket-1/status",
      "PATCH",
      { status: "in_progress" },
      login.data.access_token,
    );
    const configResponse = await requestAdmin(
      env,
      "/app-config/announcement",
      "PATCH",
      { value: "{\"title\":\"Notice\"}" },
      login.data.access_token,
    );

    expect(feedbackResponse.status).toBe(200);
    expect(configResponse.status).toBe(200);
    expect(env.DB.feedbackTickets[0]?.status).toBe("in_progress");
    expect(env.DB.appConfigs[0]).toEqual(
      expect.objectContaining({ key: "announcement", updated_by: "operator-2" }),
    );
  });

  it("guards destructive ops while still allowing card and trending maintenance", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "operator-3", "card-ops@example.com", "correct-password", "operator");
    await seedAdmin(env, "super-2", "card-super@example.com", "correct-password", "super_admin");
    const operatorLogin = await loginAdmin(env, "card-ops@example.com", "correct-password");
    const superLogin = await loginAdmin(env, "card-super@example.com", "correct-password");

    const createPinResponse = await requestAdmin(
      env,
      "/trending-pins",
      "POST",
      { card_ref: "card-1", rank: 1, active: true },
      operatorLogin.data.access_token,
    );
    const operatorDeletePinResponse = await requestAdmin(
      env,
      `/trending-pins/${env.DB.trendingPins[0]?.id}`,
      "DELETE",
      undefined,
      operatorLogin.data.access_token,
    );
    const imageResponse = await requestAdmin(
      env,
      "/card-overrides/image-upload",
      "POST",
      { card_ref: "card-2", image_url: "https://example.com/card.jpg" },
      operatorLogin.data.access_token,
    );
    const superDeleteOverrideResponse = await requestAdmin(
      env,
      `/card-overrides/${env.DB.cardOverrides[0]?.id}`,
      "DELETE",
      undefined,
      superLogin.data.access_token,
    );

    expect(createPinResponse.status).toBe(200);
    expect(operatorDeletePinResponse.status).toBe(403);
    expect(imageResponse.status).toBe(200);
    expect(superDeleteOverrideResponse.status).toBe(200);
    expect(env.DB.trendingPins).toHaveLength(1);
    expect(env.DB.cardOverrides).toHaveLength(0);
  });
});

async function seedAdmin(
  env: TestEnvWithFakeDb,
  id: string,
  email: string,
  password: string,
  role: AdminRole,
): Promise<void> {
  env.DB.adminUsers.push({
    id,
    email,
    password_hash: await hashPassword(password),
    role,
    status: "active",
    created_at: "2026-07-07T00:00:00.000Z",
  });
}

async function loginAdmin(
  env: TestEnvWithFakeDb,
  email: string,
  password: string,
): Promise<AdminLoginResponse> {
  const response = await requestAdmin(env, "/auth/login", "POST", { email, password });
  expect(response.status).toBe(200);
  return (await response.json()) as AdminLoginResponse;
}

async function requestAdmin(
  env: TestEnvWithFakeDb,
  path: string,
  method: string,
  body?: unknown,
  token?: string,
): Promise<Response> {
  const headers = new Headers();
  if (body !== undefined) headers.set("Content-Type", "application/json");
  if (token) headers.set("Authorization", `Bearer ${token}`);

  return app.request(
    `/api/v1/admin${path}`,
    {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    },
    env,
  );
}

type TestEnvWithFakeDb = Omit<TestEnv, "DB"> & { DB: FakeD1 };

function createTestEnv(): TestEnvWithFakeDb {
  return {
    DB: new FakeD1(),
    CACHE_KV: {} as KVNamespace,
    JWT_SECRET: "test-secret",
  };
}

function userRow(id: string, email: string): UserRow {
  return {
    id,
    email,
    password_hash: null,
    display_name: null,
    created_at: "2026-07-07T00:00:00.000Z",
    updated_at: "2026-07-07T00:00:00.000Z",
    deleted_at: null,
  };
}

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim();
}

function okResult<T>(results: T[] = [], changes = 1): D1Result<T> {
  return {
    success: true,
    results,
    meta: {
      duration: 0,
      size_after: 0,
      rows_read: 0,
      rows_written: changes,
      last_row_id: 0,
      changed_db: changes > 0,
      changes,
    },
  };
}
