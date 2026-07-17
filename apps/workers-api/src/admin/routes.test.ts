import { hashPassword, signAccessToken } from "@kando/auth-core";
import { describe, expect, it } from "vitest";
import app, { type Env as AppEnv } from "../index";

type TestEnv = AppEnv & { JWT_SECRET: string };

type AdminRole = "super_admin" | "operator";
type AdminStatus = "active" | "disabled";
type FeedbackStatus = "open" | "in_progress" | "closed" | "pending" | "processed" | "ignored";

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

type ScanRecordRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  image_url: string | null;
  filename: string;
  platform: string;
  app_version: string;
  device_model: string | null;
  os_version: string | null;
  recognition_status: string;
  user_confirmation_status: string;
  modified_result: number;
  system_result: string;
  user_result: string;
  candidates: string;
  created_at: string;
};

type AuthIdentityRow = {
  user_id: string;
  provider: "google" | "apple";
};

class FakeR2 {
  readonly objects = new Map<string, { bytes: Uint8Array; contentType: string }>();

  async get(key: string): Promise<R2ObjectBody | null> {
    const object = this.objects.get(key);
    if (!object) return null;
    return {
      body: new Blob([object.bytes], { type: object.contentType }).stream(),
      httpMetadata: { contentType: object.contentType },
    } as R2ObjectBody;
  }
}

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
  authIdentities: AuthIdentityRow[] = [];
  feedbackTickets: FeedbackTicketRow[] = [];
  appConfigs: AppConfigRow[] = [];
  trendingPins: TrendingPinRow[] = [];
  cardOverrides: CardOverrideRow[] = [];
  scanRecords: ScanRecordRow[] = [];

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

    if (sql.startsWith("SELECT COUNT(*) AS total FROM ( WITH accounts AS")) {
      return { total: adminUserResults(this.db, this.values).length } as T;
    }

    if (sql.startsWith("SELECT COUNT(*) AS total FROM scan_record")) {
      return { total: this.db.scanRecords.length } as T;
    }

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

    if (sql.includes("FROM scan_record") && sql.includes("WHERE id = ?")) {
      const [id] = this.values as [string];
      return (this.db.scanRecords.find((row) => row.id === id) ?? null) as T | null;
    }

    throw new Error(`Unsupported first SQL: ${sql}`);
  }

  async all<T = unknown>(): Promise<D1Result<T>> {
    const sql = normalizeSql(this.sql);

    if (sql.includes("AS install_type")) {
      const formalUsers = this.db.users
        .filter((row) => row.deleted_at === null)
        .map((row) => ({
          install_type: "user",
          uid: row.id,
          platform: "iOS",
          country: "Unknown",
          environment: "production",
          created_at: row.created_at,
        }));
      const anonymousUsers = this.db.anonymousAccounts.map((row) => ({
        install_type: "anonymous",
        uid: row.id,
        platform: "iOS",
        country: "Unknown",
        environment: "production",
        created_at: row.created_at,
      }));
      return okResult<T>([...formalUsers, ...anonymousUsers] as T[]);
    }

    if (sql.includes("FROM admin_user")) {
      const [q, , status] = this.values as [string | null, string | null, AdminStatus | null];
      const query = q?.toLowerCase() ?? "";
      return okResult<T>(
        this.db.adminUsers
          .filter((row) => !query || row.email.toLowerCase().includes(query))
          .filter((row) => !status || row.status === status) as T[],
      );
    }

    if (sql.includes("WITH accounts AS")) {
      const rows = adminUserResults(this.db, this.values);
      const pageSize = Number(this.values[13] ?? rows.length);
      const offset = Number(this.values[14] ?? 0);
      return okResult<T>(rows.slice(offset, offset + pageSize) as T[]);
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

    if (sql.includes("FROM scan_record")) {
      return okResult<T>(this.db.scanRecords as T[]);
    }

    throw new Error(`Unsupported all SQL: ${sql}`);
  }

  async run<T = unknown>(): Promise<D1Result<T>> {
    const sql = normalizeSql(this.sql);

    if (sql.startsWith("INSERT INTO admin_user")) {
      const [id, email, passwordHash, role, status, createdAt] = this.values as [
        string,
        string,
        string,
        AdminRole,
        AdminStatus,
        string,
      ];
      this.db.adminUsers.push({
        id,
        email,
        password_hash: passwordHash,
        role,
        status,
        created_at: createdAt,
      });
      return okResult<T>();
    }

    if (sql.startsWith("UPDATE admin_user SET")) {
      const [role, status, id] = this.values as [AdminRole, AdminStatus, string];
      const admin = this.db.adminUsers.find((row) => row.id === id);
      if (admin) {
        admin.role = role;
        admin.status = status;
      }
      return okResult<T>(undefined, admin ? 1 : 0);
    }

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
        total: 2,
        page: 1,
        page_size: 20,
      },
    });
  });

  it("searches App identities by UID and returns the latest real platform because support must see the same account used by the App", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "admin-users", "users@example.com", "correct-password", "operator");
    env.DB.users.push(userRow("UID-GOOGLE-1", "collector@example.com"));
    env.DB.authIdentities.push({ user_id: "UID-GOOGLE-1", provider: "google" });
    env.DB.scanRecords.push({
      id: "scan-user-1", owner_type: "user", owner_id: "UID-GOOGLE-1", image_url: null,
      filename: "card.jpg", platform: "Android", app_version: "2.0.0", device_model: null,
      os_version: null, recognition_status: "success", user_confirmation_status: "confirmed",
      modified_result: 0, system_result: "{}", user_result: "{}", candidates: "[]",
      created_at: "2026-07-08T00:00:00.000Z",
    });
    const login = await loginAdmin(env, "users@example.com", "correct-password");

    const response = await requestAdmin(
      env,
      "/users?q=uid-google&identity=google&platform=android&page_size=8",
      "GET",
      undefined,
      login.data.access_token,
    );
    const body = await response.json() as { data: unknown };

    expect(response.status).toBe(200);
    expect(body.data).toEqual({
      items: [expect.objectContaining({ id: "UID-GOOGLE-1", identity: "google", platform: "Android" })],
      total: 1,
      page: 1,
      page_size: 8,
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

  it("lets operators advance feedback with UI processing states because the new console has only pending, processed, and ignored", async () => {
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
      { status: "processed" },
      login.data.access_token,
    );
    const feedbackBody = await feedbackResponse.json();

    expect(feedbackResponse.status).toBe(200);
    expect(feedbackBody).toEqual({
      success: true,
      data: expect.objectContaining({
        id: "ticket-1",
        status: "processed",
        issue_type: "Bug Report",
        module: "Search",
      }),
    });
    expect(env.DB.feedbackTickets[0]?.status).toBe("processed");
  });

  it("lets operators update app config because daily operations should not need super_admin", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "operator-2b", "daily-config@example.com", "correct-password", "operator");
    const login = await loginAdmin(env, "daily-config@example.com", "correct-password");

    const configResponse = await requestAdmin(
      env,
      "/app-config/announcement",
      "PATCH",
      { value: "{\"title\":\"Notice\"}" },
      login.data.access_token,
    );

    expect(configResponse.status).toBe(200);
    expect(env.DB.appConfigs[0]).toEqual(
      expect.objectContaining({ key: "announcement", updated_by: "operator-2b" }),
    );
  });

  it("returns installation analytics derived from accounts because the admin trend chart needs an install source", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "admin-install", "install@example.com", "correct-password", "operator");
    env.DB.users.push(userRow("user-install-1", "one@example.com", "2026-07-07T08:00:00.000Z"));
    env.DB.anonymousAccounts.push({
      id: "anon-install-1",
      device_id: "ios-device-install",
      created_at: "2026-07-08T08:00:00.000Z",
      upgraded_user_id: null,
    });
    const login = await loginAdmin(env, "install@example.com", "correct-password");

    const response = await requestAdmin(
      env,
      "/analytics/installations?date_from=2026-07-07&date_to=2026-07-08",
      "GET",
      undefined,
      login.data.access_token,
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: expect.objectContaining({
        summary: expect.objectContaining({ total_installations: 2 }),
        trend: [
          expect.objectContaining({ date: "2026-07-07", total: 1 }),
          expect.objectContaining({ date: "2026-07-08", total: 1 }),
        ],
        rows: expect.arrayContaining([
          expect.objectContaining({ date: "2026-07-07", platform: "iOS", installs: 1 }),
          expect.objectContaining({ date: "2026-07-08", platform: "iOS", installs: 1 }),
        ]),
      }),
    });
  });

  it("lists scan records with detail fields because support must audit recognition and user confirmation", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "admin-scan", "scan@example.com", "correct-password", "operator");
    env.DB.scanRecords.push({
      id: "scan-db-1",
      owner_type: "anonymous",
      owner_id: "UID-100284",
      image_url: "scans/anonymous/UID-100284/2026/07/scan-db-1.jpg",
      filename: "scan.jpg",
      platform: "iOS",
      app_version: "1.0.0",
      device_model: "iPhone 15 Pro",
      os_version: "iOS 18.5",
      recognition_status: "success",
      user_confirmation_status: "confirmed",
      modified_result: 0,
      system_result: JSON.stringify({
        status: "success",
        name: "Bushi Tenderfoot",
        ip_game: "Magic: The Gathering",
        set: "CHK",
        number: "1",
        confidence: 86.2,
        candidate_count: 1,
      }),
      user_result: JSON.stringify({
        confirmation_status: "confirmed",
        final_card: "Bushi Tenderfoot - CHK 1",
        modified_result: false,
        added_to_inventory: true,
        added_to_wishlist: false,
      }),
      candidates: JSON.stringify([
        {
          rank: 1,
          card_ref: "11958",
          name: "Bushi Tenderfoot",
          set: "CHK",
          number: "1",
          confidence: 86.2,
        },
      ]),
      created_at: "2026-07-10T09:00:00.000Z",
    });
    const login = await loginAdmin(env, "scan@example.com", "correct-password");
    (env.SCAN_IMAGES as unknown as FakeR2).objects.set(
      "scans/anonymous/UID-100284/2026/07/scan-db-1.jpg",
      { bytes: new Uint8Array([1, 2, 3]), contentType: "image/jpeg" },
    );

    const listResponse = await requestAdmin(env, "/scans", "GET", undefined, login.data.access_token);
    const listBody = await listResponse.json() as {
      success: boolean;
      data?: { items: Array<{ scan_id: string }> };
    };
    const scanId = listBody.success ? listBody.data?.items[0]?.scan_id : "";
    const detailResponse = await requestAdmin(env, `/scans/${scanId}`, "GET", undefined, login.data.access_token);
    const detailBody = await detailResponse.json();

    expect(listResponse.status).toBe(200);
    expect(listBody).toEqual({
      success: true,
      data: expect.objectContaining({
        total: 1,
        items: [
          expect.objectContaining({
            scan_id: "scan-db-1",
            image_url: "/scans/scan-db-1/image",
            recognition_status: "success",
            user_confirmation_status: "confirmed",
            modified_result: false,
          }),
        ],
      }),
    });
    expect(detailResponse.status).toBe(200);
    expect(detailBody).toEqual({
      success: true,
      data: expect.objectContaining({
        scan_id: scanId,
        system_result: expect.objectContaining({ name: "Bushi Tenderfoot", confidence: 86.2 }),
        user_result: expect.objectContaining({ added_to_inventory: expect.any(Boolean) }),
        candidates: [expect.objectContaining({ card_ref: "11958" })],
      }),
    });

    const unauthorizedImage = await requestAdmin(env, `/scans/${scanId}/image`, "GET");
    const imageResponse = await requestAdmin(
      env,
      `/scans/${scanId}/image`,
      "GET",
      undefined,
      login.data.access_token,
    );
    expect(unauthorizedImage.status).toBe(401);
    expect(imageResponse.status).toBe(200);
    expect(imageResponse.headers.get("cache-control")).toBe("private, no-store");
    expect(imageResponse.headers.get("content-type")).toBe("image/jpeg");
    expect(new Uint8Array(await imageResponse.arrayBuffer())).toEqual(new Uint8Array([1, 2, 3]));

    const invalidDate = await requestAdmin(
      env,
      "/scans?date_from=not-a-date",
      "GET",
      undefined,
      login.data.access_token,
    );
    expect(invalidDate.status).toBe(422);
  });

  it("manages permission records through admin users because only authorized emails may enter the console", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "super-permission", "permission@example.com", "correct-password", "super_admin");
    await seedAdmin(env, "operator-permission", "ops-permission@example.com", "correct-password", "operator");
    const login = await loginAdmin(env, "permission@example.com", "correct-password");

    const listResponse = await requestAdmin(env, "/permissions", "GET", undefined, login.data.access_token);
    const patchResponse = await requestAdmin(
      env,
      "/permissions/operator-permission",
      "PATCH",
      { status: "disabled" },
      login.data.access_token,
    );
    const patchBody = await patchResponse.json();

    expect(listResponse.status).toBe(200);
    expect(patchResponse.status).toBe(200);
    expect(patchBody).toEqual({
      success: true,
      data: expect.objectContaining({
        id: "operator-permission",
        email: "ops-permission@example.com",
        permission_status: "disabled",
      }),
    });
    expect(env.DB.adminUsers.find((row) => row.id === "operator-permission")?.status).toBe("disabled");
  });

  it("stores app version rules as structured config because the version drawer edits platform-specific rollout copy", async () => {
    const env = createTestEnv();
    await seedAdmin(env, "admin-version", "version@example.com", "correct-password", "operator");
    const login = await loginAdmin(env, "version@example.com", "correct-password");

    const patchResponse = await requestAdmin(
      env,
      "/app-versions/iOS",
      "PATCH",
      {
        min_supported_version: "1.0.0",
        recommended_version: "1.9.0",
        force_update: true,
        store_url: "https://apps.apple.com/app/kando",
        recommended_update_message: "优化首页加载速度",
        forced_update_message: "请更新至最新版本后继续使用。",
        status: "enabled",
      },
      login.data.access_token,
    );
    const listResponse = await requestAdmin(env, "/app-versions", "GET", undefined, login.data.access_token);
    const listBody = await listResponse.json();

    expect(patchResponse.status).toBe(200);
    expect(listResponse.status).toBe(200);
    expect(listBody).toEqual({
      success: true,
      data: {
        items: expect.arrayContaining([
          expect.objectContaining({
            platform: "iOS",
            min_supported_version: "1.0.0",
            recommended_version: "1.9.0",
            force_update: true,
            store_url: "https://apps.apple.com/app/kando",
            status: "enabled",
          }),
        ]),
      },
    });
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
    SCAN_IMAGES: new FakeR2() as unknown as R2Bucket,
  };
}

function userRow(
  id: string,
  email: string,
  createdAt = "2026-07-07T00:00:00.000Z",
): UserRow {
  return {
    id,
    email,
    password_hash: null,
    display_name: null,
    created_at: createdAt,
    updated_at: createdAt,
    deleted_at: null,
  };
}

function adminUserResults(db: FakeD1, values: unknown[]) {
  const [type, , q, , , identity, , platform, , dateFrom, , dateTo] = values as Array<string | null>;
  const latestPlatform = (accountType: "user" | "anonymous", id: string) =>
    [...db.scanRecords]
      .filter((row) => row.owner_type === accountType && row.owner_id === id)
      .sort((left, right) => right.created_at.localeCompare(left.created_at))[0]?.platform ?? "Unknown";
  const formalUsers = db.users.map((row) => ({
    account_type: "user" as const,
    id: row.id,
    email: row.email,
    device_id: null,
    created_at: row.created_at,
    status: row.deleted_at ? "disabled" : "active",
    identity: db.authIdentities.some((item) => item.user_id === row.id && item.provider === "google")
      ? "google"
      : db.authIdentities.some((item) => item.user_id === row.id && item.provider === "apple") ? "apple" : "email",
    platform: latestPlatform("user", row.id),
  }));
  const anonymousUsers = db.anonymousAccounts.map((row) => ({
    account_type: "anonymous" as const,
    id: row.id,
    email: null,
    device_id: row.device_id,
    created_at: row.created_at,
    status: row.upgraded_user_id ? "upgraded" : "guest",
    identity: "anonymous",
    platform: latestPlatform("anonymous", row.id),
  }));
  return [...formalUsers, ...anonymousUsers]
    .filter((row) => !type || row.account_type === type)
    .filter((row) => !q || row.id.toLowerCase().includes(q) || (row.email ?? row.device_id ?? "").toLowerCase().includes(q))
    .filter((row) => !identity || row.identity === identity)
    .filter((row) => !platform || row.platform.toLowerCase() === platform)
    .filter((row) => !dateFrom || row.created_at >= dateFrom)
    .filter((row) => !dateTo || row.created_at <= dateTo)
    .sort((left, right) => right.created_at.localeCompare(left.created_at));
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
