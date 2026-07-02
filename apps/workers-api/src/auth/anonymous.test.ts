import { hashRefreshToken } from "@kando/auth-core";
import { describe, expect, it } from "vitest";
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
  owner_type: "anonymous";
  owner_id: string;
  refresh_token: string;
  expires_at: string;
  created_at: string;
  revoked_at: string | null;
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

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
  }

  async batch<T = unknown>(
    statements: FakeD1Statement[],
  ): Promise<D1Result<T>[]> {
    return Promise.all(statements.map((statement) => statement.run<T>()));
  }

  async first<T = unknown>(sql: string, values: unknown[]): Promise<T | null> {
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

    throw new Error(`Unsupported first() SQL: ${normalizedSql}`);
  }

  async run<T = unknown>(sql: string, values: unknown[]): Promise<D1Result<T>> {
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
