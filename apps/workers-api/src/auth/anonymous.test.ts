import { hashRefreshToken, signAccessToken } from "@kando/auth-core";
import { describe, expect, it, vi } from "vitest";
import app, { type Env as AppEnv } from "../index";

type TestEnv = AppEnv & { JWT_SECRET: string };

type AnonymousAccountRow = {
  id: string;
  device_id: string;
  created_at: string;
  upgraded_user_id: string | null;
};

type PortfolioFolderRow = {
  id: string;
  owner_type: "anonymous";
  owner_id: string;
  name: "Main";
  is_default: 1;
  sort_order: 0;
  created_at: string;
  updated_at: string;
};

type UserPreferenceRow = {
  id: string;
  owner_type: "anonymous";
  owner_id: string;
  currency: "USD";
  amount_hidden: 0;
  last_selected_folder_id: string | null;
  created_at: string;
  updated_at: string;
};

type SessionRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  refresh_token: string;
  expires_at: string;
  created_at: string;
  revoked_at: string | null;
};

type SessionLookupRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

type UserRow = {
  id: string;
  email: string;
  display_name: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

type VerificationCodeRow = {
  id: string;
  email: string;
  code: string;
  purpose: "register";
  expires_at: string;
  used_at: string | null;
  created_at: string;
};

type AnonymousSuccessResponse = {
  success: true;
  data: {
    anonymous_id: string;
    access_token: string;
    refresh_token: string;
    expires_in: number;
  };
};

type AccessTokenPayload = {
  owner_type: string;
  owner_id: string;
  session_id: string;
  iat: number;
  exp: number;
};

type CurrentAccountSuccessResponse = {
  success: true;
  data: {
    owner_type: "user" | "anonymous";
    user_id: string | null;
    anonymous_id: string | null;
    email: string | null;
    display_name: string | null;
    created_at: string;
  };
};

type RefreshSuccessResponse = {
  success: true;
  data: {
    access_token: string;
    refresh_token?: string;
    expires_in: number;
  };
};

type RegisterSendCodeSuccessResponse = {
  success: true;
  data: {
    expires_in: number;
    resend_after: number;
  };
};

const BASE64URL_ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

function decodeBase64Url(value: string): string {
  let bits = 0;
  let bitLength = 0;
  const bytes: number[] = [];

  for (const char of value) {
    const index = BASE64URL_ALPHABET.indexOf(char);
    if (index === -1) {
      throw new Error(`Invalid base64url character: ${char}`);
    }

    bits = (bits << 6) | index;
    bitLength += 6;

    if (bitLength >= 8) {
      bitLength -= 8;
      bytes.push((bits >> bitLength) & 0xff);
    }
  }

  return String.fromCharCode(...bytes);
}

function decodeJwtPayload(token: string): AccessTokenPayload {
  const [, payload] = token.split(".");
  if (!payload) {
    throw new Error("JWT payload is missing.");
  }

  return JSON.parse(decodeBase64Url(payload)) as AccessTokenPayload;
}

class FakeD1 {
  anonymousAccounts: AnonymousAccountRow[] = [];
  portfolioFolders: PortfolioFolderRow[] = [];
  userPreferences: UserPreferenceRow[] = [];
  sessions: SessionRow[] = [];
  users: UserRow[] = [];
  verificationCodes: VerificationCodeRow[] = [];
  failNextFirst = false;
  failNextRun = false;

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
  }

  async batch<T = unknown>(
    statements: FakeD1Statement[],
  ): Promise<D1Result<T>[]> {
    return Promise.all(statements.map((statement) => statement.run<T>()));
  }

  async first<T = unknown>(sql: string, values: unknown[]): Promise<T | null> {
    if (this.failNextFirst) {
      this.failNextFirst = false;
      throw new Error("Injected D1 first failure.");
    }

    const normalizedSql = normalizeSql(sql);

    if (normalizedSql === SELECT_REUSABLE_ANONYMOUS_ACCOUNT_SQL) {
      const [deviceId] = values as [string];
      const account = this.anonymousAccounts
        .filter(
          (row) =>
            row.device_id === deviceId && row.upgraded_user_id === null,
        )
        .sort((left, right) => right.created_at.localeCompare(left.created_at))
        .at(0);

      return account ? ({ id: account.id } as T) : null;
    }

    if (normalizedSql === SELECT_CURRENT_ANONYMOUS_ACCOUNT_SQL) {
      const [id] = values as [string];
      const account = this.anonymousAccounts.find(
        (row) => row.id === id && row.upgraded_user_id === null,
      );

      return account
        ? ({ id: account.id, created_at: account.created_at } as T)
        : null;
    }

    if (normalizedSql === SELECT_CURRENT_USER_SQL) {
      const [id] = values as [string];
      const user = this.users.find(
        (row) => row.id === id && row.deleted_at === null,
      );

      return user
        ? ({
            id: user.id,
            email: user.email,
            display_name: user.display_name,
            created_at: user.created_at,
          } as T)
        : null;
    }

    if (normalizedSql === SELECT_USER_BY_EMAIL_SQL) {
      const [email] = values as [string];
      const user = this.users.find((row) => row.email === email);

      return user ? ({ id: user.id } as T) : null;
    }

    if (normalizedSql === SELECT_SESSION_BY_REFRESH_TOKEN_SQL) {
      const [refreshToken] = values as [string];
      const session = this.sessions.find(
        (row) => row.refresh_token === refreshToken,
      );

      if (!session) {
        return null;
      }

      const row: SessionLookupRow = {
        id: session.id,
        owner_type: session.owner_type,
        owner_id: session.owner_id,
        expires_at: session.expires_at,
        revoked_at: session.revoked_at,
      };

      return row as T;
    }

    if (normalizedSql === SELECT_REFRESH_ANONYMOUS_OWNER_SQL) {
      const [id] = values as [string];
      const account = this.anonymousAccounts.find(
        (row) => row.id === id && row.upgraded_user_id === null,
      );

      return account ? ({ id: account.id } as T) : null;
    }

    if (normalizedSql === SELECT_REFRESH_USER_OWNER_SQL) {
      const [id] = values as [string];
      const user = this.users.find(
        (row) => row.id === id && row.deleted_at === null,
      );

      return user ? ({ id: user.id } as T) : null;
    }

    throw new Error(`Unsupported first() SQL: ${normalizedSql}`);
  }

  async run<T = unknown>(sql: string, values: unknown[]): Promise<D1Result<T>> {
    if (this.failNextRun) {
      this.failNextRun = false;
      throw new Error("Injected D1 run failure.");
    }

    const normalizedSql = normalizeSql(sql);

    if (normalizedSql === INSERT_ANONYMOUS_ACCOUNT_SQL) {
      const [id, deviceId, createdAt] = values as [string, string, string];
      this.anonymousAccounts.push({
        id,
        device_id: deviceId,
        created_at: createdAt,
        upgraded_user_id: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_PORTFOLIO_FOLDER_SQL) {
      const [id, ownerId, createdAt, updatedAt] = values as [
        string,
        string,
        string,
        string,
      ];
      this.portfolioFolders.push({
        id,
        owner_type: "anonymous",
        owner_id: ownerId,
        name: "Main",
        is_default: 1,
        sort_order: 0,
        created_at: createdAt,
        updated_at: updatedAt,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_USER_PREFERENCE_SQL) {
      const [id, ownerId, createdAt, updatedAt] = values as [
        string,
        string,
        string,
        string,
      ];
      this.userPreferences.push({
        id,
        owner_type: "anonymous",
        owner_id: ownerId,
        currency: "USD",
        amount_hidden: 0,
        last_selected_folder_id: null,
        created_at: createdAt,
        updated_at: updatedAt,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_SESSION_SQL) {
      const [id, ownerId, refreshToken, expiresAt, createdAt] = values as [
        string,
        string,
        string,
        string,
        string,
      ];
      this.sessions.push({
        id,
        owner_type: "anonymous",
        owner_id: ownerId,
        refresh_token: refreshToken,
        expires_at: expiresAt,
        created_at: createdAt,
        revoked_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_VERIFICATION_CODE_SQL) {
      const [id, email, code, expiresAt, createdAt] = values as [
        string,
        string,
        string,
        string,
        string,
      ];
      this.verificationCodes.push({
        id,
        email,
        code,
        purpose: "register",
        expires_at: expiresAt,
        used_at: null,
        created_at: createdAt,
      });
      return okResult<T>();
    }

    if (normalizedSql === REVOKE_SESSION_SQL) {
      const [revokedAt, id] = values as [string, string];
      const session = this.sessions.find(
        (row) => row.id === id && row.revoked_at === null,
      );

      if (session) {
        session.revoked_at = revokedAt;
      }

      return okResult<T>();
    }

    throw new Error(`Unsupported run() SQL: ${normalizedSql}`);
  }
}

class FakeD1Statement {
  constructor(
    private readonly db: FakeD1,
    private readonly sql: string,
    private readonly values: unknown[] = [],
  ) {}

  bind(...values: unknown[]): FakeD1Statement {
    return new FakeD1Statement(this.db, this.sql, values);
  }

  first<T = unknown>(): Promise<T | null> {
    return this.db.first<T>(this.sql, this.values);
  }

  run<T = unknown>(): Promise<D1Result<T>> {
    return this.db.run<T>(this.sql, this.values);
  }
}

const SELECT_REUSABLE_ANONYMOUS_ACCOUNT_SQL = normalizeSql(`
  SELECT id
  FROM anonymous_account
  WHERE device_id = ? AND upgraded_user_id IS NULL
  ORDER BY created_at DESC
  LIMIT 1
`);

const SELECT_CURRENT_ANONYMOUS_ACCOUNT_SQL = normalizeSql(`
  SELECT id, created_at
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`);

const SELECT_CURRENT_USER_SQL = normalizeSql(`
  SELECT id, email, display_name, created_at
  FROM user
  WHERE id = ? AND deleted_at IS NULL
  LIMIT 1
`);

const SELECT_SESSION_BY_REFRESH_TOKEN_SQL = normalizeSql(`
  SELECT id, owner_type, owner_id, expires_at, revoked_at
  FROM session
  WHERE refresh_token = ?
  LIMIT 1
`);

const SELECT_REFRESH_ANONYMOUS_OWNER_SQL = normalizeSql(`
  SELECT id
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`);

const SELECT_REFRESH_USER_OWNER_SQL = normalizeSql(`
  SELECT id
  FROM user
  WHERE id = ? AND deleted_at IS NULL
  LIMIT 1
`);

const SELECT_USER_BY_EMAIL_SQL = normalizeSql(`
  SELECT id
  FROM user
  WHERE email = ?
  LIMIT 1
`);

const INSERT_ANONYMOUS_ACCOUNT_SQL = normalizeSql(`
  INSERT INTO anonymous_account (id, device_id, created_at, upgraded_user_id)
  VALUES (?, ?, ?, NULL)
`);

const INSERT_PORTFOLIO_FOLDER_SQL = normalizeSql(`
  INSERT INTO portfolio_folder
    (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
  VALUES (?, 'anonymous', ?, 'Main', 1, 0, ?, ?)
`);

const INSERT_USER_PREFERENCE_SQL = normalizeSql(`
  INSERT INTO user_preference
    (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
  VALUES (?, 'anonymous', ?, 'USD', 0, NULL, ?, ?)
`);

const INSERT_SESSION_SQL = normalizeSql(`
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'anonymous', ?, ?, ?, ?, NULL)
`);

const INSERT_VERIFICATION_CODE_SQL = normalizeSql(`
  INSERT INTO verification_code
    (id, email, code, purpose, expires_at, used_at, created_at)
  VALUES (?, ?, ?, 'register', ?, NULL, ?)
`);

const REVOKE_SESSION_SQL = normalizeSql(`
  UPDATE session
  SET revoked_at = ?
  WHERE id = ? AND revoked_at IS NULL
`);

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim();
}

function okResult<T = unknown>(): D1Result<T> {
  return { success: true, meta: {} } as D1Result<T>;
}

function createFakeD1(): D1Database & FakeD1 {
  return new FakeD1() as D1Database & FakeD1;
}

function createTestEnv(): TestEnv {
  return {
    DB: createFakeD1(),
    CACHE_KV: {} as KVNamespace,
    JWT_SECRET: "test-secret-with-at-least-32-characters",
  };
}

function fakeD1(env: TestEnv): FakeD1 {
  return env.DB as unknown as FakeD1;
}

async function requestAnonymous(
  env: TestEnv,
  deviceId: string,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/anonymous",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: deviceId }),
    },
    env,
  );
}

async function requestCurrentAccount(
  env: TestEnv,
  authorization?: string,
): Promise<Response> {
  const headers = authorization ? { Authorization: authorization } : undefined;

  return app.request(
    "/api/v1/auth/me",
    {
      method: "GET",
      headers,
    },
    env,
  );
}

async function requestRefreshToken(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/token/refresh",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestRegisterSendCode(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/register/send-code",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestLogout(
  env: TestEnv,
  authorization: string | undefined,
  body: unknown,
): Promise<Response> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };

  if (authorization) {
    headers.Authorization = authorization;
  }

  return app.request(
    "/api/v1/auth/logout",
    {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    },
    env,
  );
}

function expectUnauthorized(body: unknown, status: number): void {
  expect(status).toBe(401);
  expect(body).toEqual({
    success: false,
    error: { code: "UNAUTHORIZED", message: "Unauthorized." },
  });
}

function tamperJwtSignature(token: string): string {
  const parts = token.split(".");
  const signature = parts[2];

  if (!parts[0] || !parts[1] || !signature) {
    throw new Error("Expected a signed JWT.");
  }

  const replacement = signature[0] === "A" ? "B" : "A";
  return `${parts[0]}.${parts[1]}.${replacement}${signature.slice(1)}`;
}

describe("POST /api/v1/auth/register/send-code", () => {
  it("stores a normalized one-time register code because email registration must verify ownership before creating a user", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const response = await requestRegisterSendCode(env, {
      email: "  New.Owner@Example.COM  ",
    });
    const body = (await response.json()) as RegisterSendCodeSuccessResponse;
    const code = db.verificationCodes[0];

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        expires_in: 600,
        resend_after: 60,
      },
    });
    expect(db.verificationCodes).toHaveLength(1);
    expect(code).toEqual(
      expect.objectContaining({
        id: expect.any(String),
        email: "new.owner@example.com",
        purpose: "register",
        used_at: null,
      }),
    );
    expect(code?.code).toMatch(/^\d{6}$/);
    expect(Date.parse(code?.expires_at ?? "") - Date.parse(code?.created_at ?? "")).toBe(
      600000,
    );
  });

  it.each([
    {
      name: "missing email",
      body: {},
      message: "Please enter your email.",
    },
    {
      name: "blank email",
      body: { email: "   " },
      message: "Please enter your email.",
    },
    {
      name: "non-string email",
      body: { email: 42 },
      message: "Please enter your email.",
    },
    {
      name: "malformed email",
      body: { email: "not-an-email" },
      message: "Please enter a valid email address.",
    },
    {
      name: "overlong email",
      body: { email: `${"a".repeat(244)}@example.com` },
      message: "Please enter a valid email address.",
    },
  ])(
    "returns 422 / VALIDATION_ERROR for $name without a code because registration requires a usable inbox address",
    async ({ body, message }) => {
      const env = createTestEnv();
      const response = await requestRegisterSendCode(env, body);
      const responseBody = await response.json();

      expect(response.status).toBe(422);
      expect(responseBody).toEqual({
        success: false,
        error: {
          code: "VALIDATION_ERROR",
          message,
        },
      });
      expect(fakeD1(env).verificationCodes).toHaveLength(0);
    },
  );

  it("returns 409 / CONFLICT without a code because registration must not replace an active user", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.users.push({
      id: "existing-user",
      email: "owner@example.com",
      display_name: "Existing User",
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestRegisterSendCode(env, {
      email: "  OWNER@example.com ",
    });
    const body = await response.json();

    expect(response.status).toBe(409);
    expect(body).toMatchObject({
      success: false,
      error: { code: "CONFLICT" },
    });
    expect(db.verificationCodes).toHaveLength(0);
  });

  it("returns 409 / CONFLICT without a code for a soft-deleted email because user.email is globally unique and later user creation would fail", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.users.push({
      id: "deleted-user",
      email: "owner@example.com",
      display_name: "Deleted User",
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: "2026-07-03T00:00:00.000Z",
    });

    const response = await requestRegisterSendCode(env, {
      email: "  OWNER@example.com ",
    });
    const body = await response.json();

    expect(response.status).toBe(409);
    expect(body).toMatchObject({
      success: false,
      error: { code: "CONFLICT" },
    });
    expect(db.verificationCodes).toHaveLength(0);
  });

  it("returns 500 / INTERNAL_ERROR when the existing-user lookup fails because D1 errors must keep the API error contract", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const errorSpy = vi
      .spyOn(console, "error")
      .mockImplementation(() => undefined);
    db.failNextFirst = true;

    try {
      const response = await requestRegisterSendCode(env, {
        email: "owner@example.com",
      });
      const body = await response.json();

      expect(response.status).toBe(500);
      expect(body).toEqual({
        success: false,
        error: {
          code: "INTERNAL_ERROR",
          message: "Something went wrong. Please try again.",
        },
      });
      expect(db.verificationCodes).toHaveLength(0);
      expect(errorSpy).toHaveBeenCalledWith(
        "Failed to create register verification code.",
        expect.any(Error),
      );
    } finally {
      errorSpy.mockRestore();
    }
  });

  it("returns 500 / INTERNAL_ERROR when verification-code persistence fails because clients need the same retryable error shape", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const errorSpy = vi
      .spyOn(console, "error")
      .mockImplementation(() => undefined);
    db.failNextRun = true;

    try {
      const response = await requestRegisterSendCode(env, {
        email: "owner@example.com",
      });
      const body = await response.json();

      expect(response.status).toBe(500);
      expect(body).toEqual({
        success: false,
        error: {
          code: "INTERNAL_ERROR",
          message: "Something went wrong. Please try again.",
        },
      });
      expect(db.verificationCodes).toHaveLength(0);
      expect(errorSpy).toHaveBeenCalledWith(
        "Failed to create register verification code.",
        expect.any(Error),
      );
    } finally {
      errorSpy.mockRestore();
    }
  });
});

describe("POST /api/v1/auth/anonymous", () => {
  it("returns 422 / VALIDATION_ERROR when device_id is blank because anonymous assets cannot be isolated", async () => {
    const env = createTestEnv();
    const response = await requestAnonymous(env, "   ");
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toMatchObject({
      success: false,
      error: { code: "VALIDATION_ERROR" },
    });
    expect(fakeD1(env).anonymousAccounts).toHaveLength(0);
    expect(fakeD1(env).sessions).toHaveLength(0);
  });

  it("returns 500 / INTERNAL_ERROR without D1 writes when JWT_SECRET is blank because partial sessions would be unusable", async () => {
    const env = createTestEnv();
    env.JWT_SECRET = "   ";

    const response = await requestAnonymous(env, "device-invalid-secret");
    const body = await response.json();
    const db = fakeD1(env);

    expect(response.status).toBe(500);
    expect(body).toMatchObject({
      success: false,
      error: { code: "INTERNAL_ERROR" },
    });
    expect(db.anonymousAccounts).toHaveLength(0);
    expect(db.portfolioFolders).toHaveLength(0);
    expect(db.userPreferences).toHaveLength(0);
    expect(db.sessions).toHaveLength(0);
  });

  it("initializes an isolated guest asset space without persisting plaintext refresh token for the first device request", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const response = await requestAnonymous(env, "device-first");
    const body = (await response.json()) as AnonymousSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toMatchObject({
      success: true,
      data: {
        anonymous_id: expect.any(String),
        access_token: expect.any(String),
        refresh_token: expect.any(String),
        expires_in: 900,
      },
    });

    const anonymousId = body.data.anonymous_id;
    const accessPayload = decodeJwtPayload(body.data.access_token);

    expect(accessPayload).toMatchObject({
      owner_type: "anonymous",
      owner_id: anonymousId,
      session_id: db.sessions[0]?.id,
    });
    expect(accessPayload.exp - accessPayload.iat).toBe(900);
    expect(db.anonymousAccounts).toEqual([
      expect.objectContaining({
        id: anonymousId,
        device_id: "device-first",
        upgraded_user_id: null,
      }),
    ]);
    expect(db.portfolioFolders).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousId,
        name: "Main",
        is_default: 1,
        sort_order: 0,
      }),
    ]);
    expect(db.userPreferences).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousId,
        currency: "USD",
        amount_hidden: 0,
        last_selected_folder_id: null,
      }),
    ]);
    expect(db.sessions).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousId,
        revoked_at: null,
      }),
    ]);
    expect(db.sessions[0]?.refresh_token).toBe(
      await hashRefreshToken(body.data.refresh_token),
    );
  });

  it("reuses the same anonymous_id for the same guest device while creating a new non-plaintext refresh token session", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    const firstResponse = await requestAnonymous(env, "device-returning");
    const firstBody =
      (await firstResponse.json()) as AnonymousSuccessResponse;
    const secondResponse = await requestAnonymous(env, "device-returning");
    const secondBody =
      (await secondResponse.json()) as AnonymousSuccessResponse;

    expect(secondResponse.status).toBe(200);
    expect(secondBody.data.anonymous_id).toBe(firstBody.data.anonymous_id);
    const secondAccessPayload = decodeJwtPayload(
      secondBody.data.access_token,
    );

    expect(secondAccessPayload).toMatchObject({
      owner_type: "anonymous",
      owner_id: firstBody.data.anonymous_id,
      session_id: db.sessions[1]?.id,
    });
    expect(db.anonymousAccounts).toHaveLength(1);
    expect(db.sessions).toHaveLength(2);
    expect(db.sessions[0]?.id).not.toBe(db.sessions[1]?.id);
    expect(db.sessions.map((session) => session.owner_id)).toEqual([
      firstBody.data.anonymous_id,
      firstBody.data.anonymous_id,
    ]);
    expect(secondBody.data.refresh_token).not.toBe(
      firstBody.data.refresh_token,
    );
    expect(db.sessions[1]?.refresh_token).not.toBe(
      db.sessions[0]?.refresh_token,
    );
    expect(db.sessions[1]?.refresh_token).not.toBe(
      secondBody.data.refresh_token,
    );
    expect(db.sessions[1]?.refresh_token).toBe(
      await hashRefreshToken(secondBody.data.refresh_token),
    );
  });

  it("creates a new anonymous account when the same device only has upgraded accounts", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.anonymousAccounts.push({
      id: "upgraded-anonymous-id",
      device_id: "device-upgraded",
      created_at: "2026-07-02T00:00:00.000Z",
      upgraded_user_id: "user-id",
    });

    const response = await requestAnonymous(env, "device-upgraded");
    const body = (await response.json()) as AnonymousSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.anonymous_id).not.toBe("upgraded-anonymous-id");
    expect(db.anonymousAccounts).toHaveLength(2);
    expect(db.anonymousAccounts[1]).toEqual(
      expect.objectContaining({
        id: body.data.anonymous_id,
        device_id: "device-upgraded",
        upgraded_user_id: null,
      }),
    );
    expect(db.sessions).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: body.data.anonymous_id,
      }),
    ]);
  });
});

describe("POST /api/v1/auth/token/refresh", () => {
  it("issues a new access token without rotating refresh token because anonymous sessions keep a stable renewal credential", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-refresh");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestRefreshToken(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = (await response.json()) as RefreshSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        access_token: expect.any(String),
        expires_in: 900,
      },
    });
    expect(body.data.refresh_token).toBeUndefined();

    const currentResponse = await requestCurrentAccount(
      env,
      `Bearer ${body.data.access_token}`,
    );
    const currentBody =
      (await currentResponse.json()) as CurrentAccountSuccessResponse;

    expect(currentResponse.status).toBe(200);
    expect(currentBody.data).toMatchObject({
      owner_type: "anonymous",
      anonymous_id: anonymousBody.data.anonymous_id,
    });
  });

  it("returns 422 / VALIDATION_ERROR when refresh_token is blank because renewal must be tied to a real session secret", async () => {
    const env = createTestEnv();

    const response = await requestRefreshToken(env, {
      refresh_token: "   ",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "refresh_token is required.",
      },
    });
  });

  it("returns 401 / UNAUTHORIZED for an unknown refresh token because renewal must not mint identity from unrecognized secrets", async () => {
    const env = createTestEnv();

    const response = await requestRefreshToken(env, {
      refresh_token: "unknown-refresh-token",
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED for an expired session because stale renewal credentials must not extend access", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-refresh-expired",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const session = fakeD1(env).sessions[0];

    if (!session) {
      throw new Error("Expected anonymous session.");
    }

    session.expires_at = "2000-01-01T00:00:00.000Z";

    const response = await requestRefreshToken(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED for an unparseable session lifetime because malformed persistence must not extend access", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-refresh-malformed-expiry",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const session = fakeD1(env).sessions[0];

    if (!session) {
      throw new Error("Expected anonymous session.");
    }

    session.expires_at = "not-a-date";

    const response = await requestRefreshToken(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED for a revoked session because server-side logout must immediately block renewal", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-refresh-revoked",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const session = fakeD1(env).sessions[0];

    if (!session) {
      throw new Error("Expected anonymous session.");
    }

    session.revoked_at = "2026-07-02T00:00:00.000Z";

    const response = await requestRefreshToken(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED when an anonymous owner was upgraded because refresh must follow the live owner boundary", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-refresh-upgraded",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const account = fakeD1(env).anonymousAccounts[0];

    if (!account) {
      throw new Error("Expected anonymous account.");
    }

    account.upgraded_user_id = "user-upgraded";

    const response = await requestRefreshToken(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED for an untrusted persisted owner_type because malformed ownership must not sign access tokens", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-refresh-bad-owner-type",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const session = fakeD1(env).sessions[0];

    if (!session) {
      throw new Error("Expected anonymous session.");
    }

    fakeD1(env).users.push({
      id: session.owner_id,
      email: "admin-shaped@example.com",
      display_name: "Admin Shaped",
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: null,
    });
    (session as { owner_type: string }).owner_type = "admin";

    const response = await requestRefreshToken(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("issues a user access token from a live user session because migrated owners still need refresh continuity", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const refreshToken = "user-refresh-token";

    db.users.push({
      id: "user-refresh",
      email: "refresh-user@example.com",
      display_name: "Refresh User",
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: null,
    });
    db.sessions.push({
      id: "user-session-refresh",
      owner_type: "user",
      owner_id: "user-refresh",
      refresh_token: await hashRefreshToken(refreshToken),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-02T00:00:00.000Z",
      revoked_at: null,
    });

    const response = await requestRefreshToken(env, {
      refresh_token: refreshToken,
    });
    const body = (await response.json()) as RefreshSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        access_token: expect.any(String),
        expires_in: 900,
      },
    });

    const currentResponse = await requestCurrentAccount(
      env,
      `Bearer ${body.data.access_token}`,
    );
    const currentBody =
      (await currentResponse.json()) as CurrentAccountSuccessResponse;

    expect(currentResponse.status).toBe(200);
    expect(currentBody).toEqual({
      success: true,
      data: {
        owner_type: "user",
        user_id: "user-refresh",
        anonymous_id: null,
        email: "refresh-user@example.com",
        display_name: "Refresh User",
        created_at: "2026-07-02T00:00:00.000Z",
      },
    });
  });

  it("returns 401 / UNAUTHORIZED for a soft-deleted user owner because refresh must not revive removed accounts", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const refreshToken = "deleted-user-refresh-token";

    db.users.push({
      id: "user-refresh-deleted",
      email: "deleted-refresh-user@example.com",
      display_name: "Deleted Refresh User",
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: "2026-07-03T00:00:00.000Z",
    });
    db.sessions.push({
      id: "deleted-user-session-refresh",
      owner_type: "user",
      owner_id: "user-refresh-deleted",
      refresh_token: await hashRefreshToken(refreshToken),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-02T00:00:00.000Z",
      revoked_at: null,
    });

    const response = await requestRefreshToken(env, {
      refresh_token: refreshToken,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 500 / INTERNAL_ERROR when JWT_SECRET is blank because refreshed access tokens depend on server signing configuration", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-refresh-invalid-secret",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    env.JWT_SECRET = "   ";

    const response = await requestRefreshToken(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expect(response.status).toBe(500);
    expect(body).toEqual({
      success: false,
      error: {
        code: "INTERNAL_ERROR",
        message: "Something went wrong. Please try again.",
      },
    });
  });
});

describe("POST /api/v1/auth/logout", () => {
  it("revokes the matching session because logout must invalidate the renewal credential used by that device", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-logout");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const session = fakeD1(env).sessions[0];

    if (!session) {
      throw new Error("Expected anonymous session.");
    }

    const response = await requestLogout(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
      { refresh_token: anonymousBody.data.refresh_token },
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({ success: true, data: {} });
    expect(session.revoked_at).toEqual(expect.any(String));
  });

  it("blocks refresh after logout because revoked renewal credentials must not mint new access tokens", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-logout-refresh",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const logoutResponse = await requestLogout(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
      { refresh_token: anonymousBody.data.refresh_token },
    );
    expect(logoutResponse.status).toBe(200);

    const refreshResponse = await requestRefreshToken(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const refreshBody = await refreshResponse.json();

    expectUnauthorized(refreshBody, refreshResponse.status);
  });

  it("returns 401 / UNAUTHORIZED for mismatched session proofs because logout must not revoke another device", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const firstResponse = await requestAnonymous(
      env,
      "device-logout-first",
    );
    const firstBody = (await firstResponse.json()) as AnonymousSuccessResponse;
    const secondResponse = await requestAnonymous(
      env,
      "device-logout-second",
    );
    const secondBody =
      (await secondResponse.json()) as AnonymousSuccessResponse;

    const response = await requestLogout(
      env,
      `Bearer ${firstBody.data.access_token}`,
      { refresh_token: secondBody.data.refresh_token },
    );
    const body = await response.json();

    expectUnauthorized(body, response.status);
    expect(db.sessions).toHaveLength(2);
    expect(db.sessions.map((session) => session.revoked_at)).toEqual([
      null,
      null,
    ]);
  });

  it("returns 401 / UNAUTHORIZED without Authorization because refresh_token alone must not authorize revocation", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-logout-no-auth",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestLogout(env, undefined, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
    expect(fakeD1(env).sessions[0]?.revoked_at).toBeNull();
  });

  it("returns 401 / UNAUTHORIZED for Basic Authorization because logout can only be authorized by a bearer access token", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-logout-basic-auth",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestLogout(env, "Basic token", {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
    expect(fakeD1(env).sessions[0]?.revoked_at).toBeNull();
  });

  it("returns 401 / UNAUTHORIZED for a tampered access token because tampered ownership proof must not revoke a session", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-logout-tampered-token",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestLogout(
      env,
      `Bearer ${tamperJwtSignature(anonymousBody.data.access_token)}`,
      { refresh_token: anonymousBody.data.refresh_token },
    );
    const body = await response.json();

    expectUnauthorized(body, response.status);
    expect(fakeD1(env).sessions[0]?.revoked_at).toBeNull();
  });

  it("returns 422 / VALIDATION_ERROR when refresh_token is blank because logout must target a concrete session secret", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-logout-blank-refresh",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestLogout(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
      { refresh_token: "   " },
    );
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "refresh_token is required.",
      },
    });
    expect(fakeD1(env).sessions[0]?.revoked_at).toBeNull();
  });

  it("returns 500 / INTERNAL_ERROR when JWT_SECRET is blank because logout depends on trusted access token verification", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-logout-invalid-secret",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    env.JWT_SECRET = "   ";

    const response = await requestLogout(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
      { refresh_token: anonymousBody.data.refresh_token },
    );
    const body = await response.json();

    expect(response.status).toBe(500);
    expect(body).toEqual({
      success: false,
      error: {
        code: "INTERNAL_ERROR",
        message: "Something went wrong. Please try again.",
      },
    });
    expect(fakeD1(env).sessions[0]?.revoked_at).toBeNull();
  });
});

describe("GET /api/v1/auth/me", () => {
  it("returns the active anonymous account for a valid access token because clients need the server-confirmed owner", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-current");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestCurrentAccount(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as CurrentAccountSuccessResponse;
    const account = fakeD1(env).anonymousAccounts[0];

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        owner_type: "anonymous",
        user_id: null,
        anonymous_id: anonymousBody.data.anonymous_id,
        email: null,
        display_name: null,
        created_at: account?.created_at,
      },
    });
  });

  it("returns the active user account for a valid access token because upgraded clients should identify the durable owner", async () => {
    const env = createTestEnv();
    fakeD1(env).users.push({
      id: "user-current",
      email: "owner@example.com",
      display_name: "Owner",
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: null,
    });
    const accessToken = await signAccessToken(
      {
        owner_type: "user",
        owner_id: "user-current",
        session_id: "session-current",
      },
      env.JWT_SECRET,
    );

    const response = await requestCurrentAccount(env, `Bearer ${accessToken}`);
    const body = (await response.json()) as CurrentAccountSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        owner_type: "user",
        user_id: "user-current",
        anonymous_id: null,
        email: "owner@example.com",
        display_name: "Owner",
        created_at: "2026-07-02T00:00:00.000Z",
      },
    });
  });

  it("returns 401 / UNAUTHORIZED without Authorization because identity must not be inferred from device state", async () => {
    const env = createTestEnv();

    const response = await requestCurrentAccount(env);
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED for non-Bearer Authorization because only access tokens establish API identity", async () => {
    const env = createTestEnv();

    const response = await requestCurrentAccount(env, "Basic token");
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED for an invalid token signature because tampered ownership must be rejected", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-tampered");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestCurrentAccount(
      env,
      `Bearer ${tamperJwtSignature(anonymousBody.data.access_token)}`,
    );
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 500 / INTERNAL_ERROR when JWT_SECRET is blank because token verification depends on server configuration", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-me-invalid-secret",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    env.JWT_SECRET = "   ";

    const response = await requestCurrentAccount(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = await response.json();

    expect(response.status).toBe(500);
    expect(body).toEqual({
      success: false,
      error: {
        code: "INTERNAL_ERROR",
        message: "Something went wrong. Please try again.",
      },
    });
  });

  it("returns 401 / UNAUTHORIZED for an expired token because stale session proofs must not identify an account", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-expired");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const accessToken = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
        session_id: "expired-session",
      },
      env.JWT_SECRET,
      new Date("2000-01-01T00:00:00.000Z"),
    );

    const response = await requestCurrentAccount(env, `Bearer ${accessToken}`);
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED when the token owner is missing because tokens are not a substitute for live accounts", async () => {
    const env = createTestEnv();
    const accessToken = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "missing-anonymous",
        session_id: "missing-session",
      },
      env.JWT_SECRET,
    );

    const response = await requestCurrentAccount(env, `Bearer ${accessToken}`);
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });
});
