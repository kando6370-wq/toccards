import {
  hashRefreshToken,
  signAccessToken,
  verifyPassword,
} from "@kando/auth-core";
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
  owner_type: "anonymous" | "user";
  owner_id: string;
  name: "Main";
  is_default: 1;
  sort_order: 0;
  created_at: string;
  updated_at: string;
};

type UserPreferenceRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  currency: "USD";
  amount_hidden: 0;
  last_selected_folder_id: string | null;
  created_at: string;
  updated_at: string;
};

type CollectionItemRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  folder_id: string;
  card_ref: string;
  updated_at: string;
};

type WishlistItemRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  card_ref: string;
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
  password_hash: string | null;
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

type RegisterVerifySuccessResponse = {
  success: true;
  data: {
    user_id: string;
    email: string;
    access_token: string;
    refresh_token: string;
    expires_in: number;
    migrated: boolean;
  };
};

type LoginSuccessResponse = {
  success: true;
  data: {
    user_id: string;
    email: string;
    access_token: string;
    refresh_token: string;
    expires_in: number;
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
  collectionItems: CollectionItemRow[] = [];
  wishlistItems: WishlistItemRow[] = [];
  sessions: SessionRow[] = [];
  users: UserRow[] = [];
  verificationCodes: VerificationCodeRow[] = [];
  consumeNextRegisterCodeBeforeUpdate = false;
  failNextBatch = false;
  failNextFirst = false;
  failNextRun = false;
  createConflictingUserBeforeNextUserInsert = false;
  upgradeAnonymousBeforeUpgrade = false;

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
  }

  async batch<T = unknown>(
    statements: FakeD1Statement[],
  ): Promise<D1Result<T>[]> {
    if (this.failNextBatch) {
      this.failNextBatch = false;
      throw new Error("Injected D1 batch failure.");
    }

    const results: D1Result<T>[] = [];

    for (const statement of statements) {
      results.push(await statement.run<T>());
    }

    return results;
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

    if (normalizedSql === SELECT_LOGIN_USER_BY_EMAIL_SQL) {
      const [email] = values as [string];
      const user = this.users.find(
        (row) =>
          row.email === email &&
          row.deleted_at === null &&
          row.password_hash !== null,
      );

      return user
        ? ({
            id: user.id,
            email: user.email,
            password_hash: user.password_hash,
          } as T)
        : null;
    }

    if (normalizedSql === SELECT_LATEST_REGISTER_CODE_SQL) {
      const [email] = values as [string];
      const code = this.verificationCodes
        .filter((row) => row.email === email && row.purpose === "register")
        .sort((left, right) => right.created_at.localeCompare(left.created_at))
        .at(0);

      return code
        ? ({
            id: code.id,
            code: code.code,
            expires_at: code.expires_at,
            used_at: code.used_at,
          } as T)
        : null;
    }

    if (normalizedSql === SELECT_LIVE_ANONYMOUS_ACCOUNT_SQL) {
      const [id] = values as [string];
      const account = this.anonymousAccounts.find(
        (row) => row.id === id && row.upgraded_user_id === null,
      );

      return account ? ({ id: account.id } as T) : null;
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

    if (normalizedSql === SELECT_SESSION_BY_ID_SQL) {
      const [id] = values as [string];
      const session = this.sessions.find((row) => row.id === id);

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

    if (normalizedSql === INSERT_USER_ACCOUNT_SQL) {
      const [id, email, passwordHash, createdAt, updatedAt, codeId, usedAt] =
        values as [
          string,
          string,
          string,
          string,
          string,
          string,
          string,
        ];

      if (!this.hasConsumedRegisterCode(codeId, usedAt)) {
        return okResult<T>(0);
      }

      if (this.createConflictingUserBeforeNextUserInsert) {
        this.createConflictingUserBeforeNextUserInsert = false;
        this.users.push({
          id: "concurrent-user",
          email,
          password_hash: null,
          display_name: "Concurrent User",
          created_at: "2026-07-03T00:00:00.000Z",
          updated_at: "2026-07-03T00:00:00.000Z",
          deleted_at: null,
        });
      }

      if (this.users.some((row) => row.email === email)) {
        throw new Error("UNIQUE constraint failed: user.email");
      }

      this.users.push({
        id,
        email,
        password_hash: passwordHash,
        display_name: null,
        created_at: createdAt,
        updated_at: updatedAt,
        deleted_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_MIGRATED_USER_ACCOUNT_SQL) {
      const [
        id,
        email,
        passwordHash,
        createdAt,
        updatedAt,
        codeId,
        usedAt,
        anonymousId,
        upgradedUserId,
      ] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
        string,
        string,
        string,
      ];

      if (
        !this.hasConsumedRegisterCode(codeId, usedAt) ||
        !this.hasUpgradedAnonymousAccount(anonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      if (this.createConflictingUserBeforeNextUserInsert) {
        this.createConflictingUserBeforeNextUserInsert = false;
        this.users.push({
          id: "concurrent-user",
          email,
          password_hash: null,
          display_name: "Concurrent User",
          created_at: "2026-07-03T00:00:00.000Z",
          updated_at: "2026-07-03T00:00:00.000Z",
          deleted_at: null,
        });
      }

      if (this.users.some((row) => row.email === email)) {
        throw new Error("UNIQUE constraint failed: user.email");
      }

      this.users.push({
        id,
        email,
        password_hash: passwordHash,
        display_name: null,
        created_at: createdAt,
        updated_at: updatedAt,
        deleted_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_USER_PORTFOLIO_FOLDER_SQL) {
      const [id, ownerId, createdAt, updatedAt, codeId, usedAt] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
      ];

      if (!this.hasConsumedRegisterCode(codeId, usedAt)) {
        return okResult<T>(0);
      }

      this.portfolioFolders.push({
        id,
        owner_type: "user",
        owner_id: ownerId,
        name: "Main",
        is_default: 1,
        sort_order: 0,
        created_at: createdAt,
        updated_at: updatedAt,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_USER_USER_PREFERENCE_SQL) {
      const [id, ownerId, createdAt, updatedAt, codeId, usedAt] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
      ];

      if (!this.hasConsumedRegisterCode(codeId, usedAt)) {
        return okResult<T>(0);
      }

      this.userPreferences.push({
        id,
        owner_type: "user",
        owner_id: ownerId,
        currency: "USD",
        amount_hidden: 0,
        last_selected_folder_id: null,
        created_at: createdAt,
        updated_at: updatedAt,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_USER_SESSION_SQL) {
      const [id, ownerId, refreshToken, expiresAt, createdAt, codeId, usedAt] =
        values as [
          string,
          string,
          string,
          string,
          string,
          string,
          string,
        ];

      if (!this.hasConsumedRegisterCode(codeId, usedAt)) {
        return okResult<T>(0);
      }

      this.sessions.push({
        id,
        owner_type: "user",
        owner_id: ownerId,
        refresh_token: refreshToken,
        expires_at: expiresAt,
        created_at: createdAt,
        revoked_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_MIGRATED_USER_SESSION_SQL) {
      const [
        id,
        ownerId,
        refreshToken,
        expiresAt,
        createdAt,
        codeId,
        usedAt,
        anonymousId,
        upgradedUserId,
      ] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
        string,
        string,
        string,
      ];

      if (
        !this.hasConsumedRegisterCode(codeId, usedAt) ||
        !this.hasUpgradedAnonymousAccount(anonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      this.sessions.push({
        id,
        owner_type: "user",
        owner_id: ownerId,
        refresh_token: refreshToken,
        expires_at: expiresAt,
        created_at: createdAt,
        revoked_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === UPDATE_REGISTER_CODE_USED_SQL) {
      const [usedAt, id] = values as [string, string];

      if (this.consumeNextRegisterCodeBeforeUpdate) {
        this.consumeNextRegisterCodeBeforeUpdate = false;
        const concurrentlyUsedCode = this.verificationCodes.find(
          (row) => row.id === id && row.used_at === null,
        );

        if (concurrentlyUsedCode) {
          concurrentlyUsedCode.used_at = "2000-01-01T00:00:00.000Z";
        }
      }

      const code = this.verificationCodes.find(
        (row) => row.id === id && row.used_at === null,
      );

      if (code) {
        code.used_at = usedAt;
      }

      return okResult<T>(code ? 1 : 0);
    }

    if (normalizedSql === UPDATE_ANONYMOUS_PORTFOLIO_FOLDERS_SQL) {
      const [
        userId,
        updatedAt,
        anonymousId,
        codeId,
        usedAt,
        upgradedAnonymousId,
        upgradedUserId,
      ] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
        string,
      ];

      if (
        !this.hasConsumedRegisterCode(codeId, usedAt) ||
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      let changes = 0;
      for (const folder of this.portfolioFolders) {
        if (
          folder.owner_type === "anonymous" &&
          folder.owner_id === anonymousId
        ) {
          folder.owner_type = "user";
          folder.owner_id = userId;
          folder.updated_at = updatedAt;
          changes += 1;
        }
      }

      return okResult<T>(changes);
    }

    if (normalizedSql === UPDATE_ANONYMOUS_COLLECTION_ITEMS_SQL) {
      const [
        userId,
        updatedAt,
        anonymousId,
        codeId,
        usedAt,
        upgradedAnonymousId,
        upgradedUserId,
      ] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
        string,
      ];

      if (
        !this.hasConsumedRegisterCode(codeId, usedAt) ||
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      let changes = 0;
      for (const item of this.collectionItems) {
        if (item.owner_type === "anonymous" && item.owner_id === anonymousId) {
          item.owner_type = "user";
          item.owner_id = userId;
          item.updated_at = updatedAt;
          changes += 1;
        }
      }

      return okResult<T>(changes);
    }

    if (normalizedSql === UPDATE_ANONYMOUS_WISHLIST_ITEMS_SQL) {
      const [
        userId,
        anonymousId,
        codeId,
        usedAt,
        upgradedAnonymousId,
        upgradedUserId,
      ] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
      ];

      if (
        !this.hasConsumedRegisterCode(codeId, usedAt) ||
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      let changes = 0;
      for (const item of this.wishlistItems) {
        if (item.owner_type === "anonymous" && item.owner_id === anonymousId) {
          item.owner_type = "user";
          item.owner_id = userId;
          changes += 1;
        }
      }

      return okResult<T>(changes);
    }

    if (normalizedSql === UPDATE_ANONYMOUS_USER_PREFERENCE_SQL) {
      const [
        userId,
        updatedAt,
        anonymousId,
        codeId,
        usedAt,
        upgradedAnonymousId,
        upgradedUserId,
      ] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
        string,
      ];

      if (
        !this.hasConsumedRegisterCode(codeId, usedAt) ||
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      let changes = 0;
      for (const preference of this.userPreferences) {
        if (
          preference.owner_type === "anonymous" &&
          preference.owner_id === anonymousId
        ) {
          preference.owner_type = "user";
          preference.owner_id = userId;
          preference.updated_at = updatedAt;
          changes += 1;
        }
      }

      return okResult<T>(changes);
    }

    if (normalizedSql === UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_SQL) {
      const [userId, anonymousId, codeId, usedAt] = values as [
        string,
        string,
        string,
        string,
      ];

      if (!this.hasConsumedRegisterCode(codeId, usedAt)) {
        return okResult<T>(0);
      }

      if (this.upgradeAnonymousBeforeUpgrade) {
        this.upgradeAnonymousBeforeUpgrade = false;
        const concurrentlyUpgradedAccount = this.anonymousAccounts.find(
          (row) => row.id === anonymousId && row.upgraded_user_id === null,
        );

        if (concurrentlyUpgradedAccount) {
          concurrentlyUpgradedAccount.upgraded_user_id = "existing-user";
        }
      }

      const account = this.anonymousAccounts.find(
        (row) => row.id === anonymousId && row.upgraded_user_id === null,
      );

      if (account) {
        account.upgraded_user_id = userId;
      }

      return okResult<T>(account ? 1 : 0);
    }

    if (normalizedSql === REVOKE_SESSION_SQL) {
      const [revokedAt, id] = values as [string, string];
      const session = this.sessions.find(
        (row) => row.id === id && row.revoked_at === null,
      );

      if (session) {
        session.revoked_at = revokedAt;
      }

      return okResult<T>(session ? 1 : 0);
    }

    if (normalizedSql === INSERT_LOGIN_USER_SESSION_SQL) {
      const [id, ownerId, refreshToken, expiresAt, createdAt] = values as [
        string,
        string,
        string,
        string,
        string,
      ];

      this.sessions.push({
        id,
        owner_type: "user",
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

  private hasConsumedRegisterCode(id: string, usedAt: string): boolean {
    return this.verificationCodes.some(
      (row) => row.id === id && row.used_at === usedAt,
    );
  }

  private hasUpgradedAnonymousAccount(id: string, userId: string): boolean {
    return this.anonymousAccounts.some(
      (row) => row.id === id && row.upgraded_user_id === userId,
    );
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

const SELECT_SESSION_BY_ID_SQL = normalizeSql(`
  SELECT id, owner_type, owner_id, expires_at, revoked_at
  FROM session
  WHERE id = ?
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

const SELECT_LOGIN_USER_BY_EMAIL_SQL = normalizeSql(`
  SELECT id, email, password_hash
  FROM user
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
  LIMIT 1
`);

const SELECT_LATEST_REGISTER_CODE_SQL = normalizeSql(`
  SELECT id, code, expires_at, used_at
  FROM verification_code
  WHERE email = ? AND purpose = 'register'
  ORDER BY created_at DESC
  LIMIT 1
`);

const SELECT_LIVE_ANONYMOUS_ACCOUNT_SQL = normalizeSql(`
  SELECT id
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
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

const INSERT_USER_ACCOUNT_SQL = normalizeSql(`
  INSERT INTO user
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  SELECT ?, ?, ?, NULL, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`);

const INSERT_MIGRATED_USER_ACCOUNT_SQL = normalizeSql(`
  INSERT INTO user
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  SELECT ?, ?, ?, NULL, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const INSERT_USER_PORTFOLIO_FOLDER_SQL = normalizeSql(`
  INSERT INTO portfolio_folder
    (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
  SELECT ?, 'user', ?, 'Main', 1, 0, ?, ?
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`);

const INSERT_USER_USER_PREFERENCE_SQL = normalizeSql(`
  INSERT INTO user_preference
    (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
  SELECT ?, 'user', ?, 'USD', 0, NULL, ?, ?
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`);

const INSERT_USER_SESSION_SQL = normalizeSql(`
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  SELECT ?, 'user', ?, ?, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`);

const INSERT_MIGRATED_USER_SESSION_SQL = normalizeSql(`
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  SELECT ?, 'user', ?, ?, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const INSERT_LOGIN_USER_SESSION_SQL = normalizeSql(`
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'user', ?, ?, ?, ?, NULL)
`);

const UPDATE_REGISTER_CODE_USED_SQL = normalizeSql(`
  UPDATE verification_code
  SET used_at = ?
  WHERE id = ? AND used_at IS NULL
`);

const UPDATE_ANONYMOUS_PORTFOLIO_FOLDERS_SQL = normalizeSql(`
  UPDATE portfolio_folder
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM verification_code
      WHERE id = ? AND used_at = ?
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_ANONYMOUS_COLLECTION_ITEMS_SQL = normalizeSql(`
  UPDATE collection_item
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM verification_code
      WHERE id = ? AND used_at = ?
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_ANONYMOUS_WISHLIST_ITEMS_SQL = normalizeSql(`
  UPDATE wishlist_item
  SET owner_type = 'user', owner_id = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM verification_code
      WHERE id = ? AND used_at = ?
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_ANONYMOUS_USER_PREFERENCE_SQL = normalizeSql(`
  UPDATE user_preference
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM verification_code
      WHERE id = ? AND used_at = ?
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_SQL = normalizeSql(`
  UPDATE anonymous_account
  SET upgraded_user_id = ?
  WHERE id = ? AND upgraded_user_id IS NULL
    AND EXISTS (
      SELECT 1
      FROM verification_code
      WHERE id = ? AND used_at = ?
    )
`);

const REVOKE_SESSION_SQL = normalizeSql(`
  UPDATE session
  SET revoked_at = ?
  WHERE id = ? AND revoked_at IS NULL
`);

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim();
}

function okResult<T = unknown>(changes = 1): D1Result<T> {
  return {
    success: true,
    meta: {
      changes,
      duration: 0,
      last_row_id: 0,
      rows_read: 0,
      rows_written: changes,
      size_after: 0,
    },
  } as D1Result<T>;
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

async function requestRegisterVerify(
  env: TestEnv,
  body: unknown,
  authorization?: string,
): Promise<Response> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };

  if (authorization) {
    headers.Authorization = authorization;
  }

  return app.request(
    "/api/v1/auth/register/verify",
    {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestLogin(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/login",
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
      password_hash: null,
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
      password_hash: null,
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

describe("POST /api/v1/auth/register/verify", () => {
  it("creates a user session because verified email ownership upgrades the client to a durable account", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const password = "correct-password";
    const sendResponse = await requestRegisterSendCode(env, {
      email: "  New.Owner@Example.COM  ",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const response = await requestRegisterVerify(env, {
      email: " new.owner@example.COM ",
      code: code.code,
      password,
    });
    const body = (await response.json()) as RegisterVerifySuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        user_id: expect.any(String),
        email: "new.owner@example.com",
        access_token: expect.any(String),
        refresh_token: expect.any(String),
        expires_in: 900,
        migrated: false,
      },
    });
    expect(db.users).toHaveLength(1);
    const user = db.users[0];

    if (!user?.password_hash) {
      throw new Error("Expected user password hash.");
    }

    expect(user).toEqual(
      expect.objectContaining({
        id: body.data.user_id,
        email: "new.owner@example.com",
        display_name: null,
        deleted_at: null,
      }),
    );
    expect(user.password_hash).not.toBe(password);
    expect(await verifyPassword(password, user.password_hash)).toBe(true);
    expect(
      db.portfolioFolders.find(
        (row) => row.owner_type === "user" && row.owner_id === user.id,
      ),
    ).toEqual(
      expect.objectContaining({
        name: "Main",
        is_default: 1,
        sort_order: 0,
      }),
    );
    expect(
      db.userPreferences.find(
        (row) => row.owner_type === "user" && row.owner_id === user.id,
      ),
    ).toEqual(
      expect.objectContaining({
        currency: "USD",
        amount_hidden: 0,
        last_selected_folder_id: null,
      }),
    );
    const session = db.sessions.find(
      (row) => row.owner_type === "user" && row.owner_id === user.id,
    );

    if (!session) {
      throw new Error("Expected user session.");
    }

    expect(session.refresh_token).toBe(
      await hashRefreshToken(body.data.refresh_token),
    );
    expect(code.used_at).toEqual(expect.any(String));

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
        user_id: user.id,
        anonymous_id: null,
        email: "new.owner@example.com",
        display_name: null,
        created_at: user.created_at,
      },
    });
  });

  it("migrates live anonymous assets because registration upgrades should preserve guest work", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-register-migrate",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const anonymousId = anonymousBody.data.anonymous_id;
    const anonymousFolder = db.portfolioFolders.find(
      (row) => row.owner_type === "anonymous" && row.owner_id === anonymousId,
    );

    if (!anonymousFolder) {
      throw new Error("Expected anonymous folder.");
    }

    db.collectionItems.push({
      id: "collection-guest",
      owner_type: "anonymous",
      owner_id: anonymousId,
      folder_id: anonymousFolder.id,
      card_ref: "card-collection",
      updated_at: "2026-07-02T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "wishlist-guest",
      owner_type: "anonymous",
      owner_id: anonymousId,
      card_ref: "card-wishlist",
    });

    const sendResponse = await requestRegisterSendCode(env, {
      email: "migrate@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const response = await requestRegisterVerify(
      env,
      {
        email: "migrate@example.com",
        code: code.code,
        password: "correct-password",
        anonymous_id: ` ${anonymousId} `,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as RegisterVerifySuccessResponse;
    const userId = body.data.user_id;

    expect(response.status).toBe(200);
    expect(body.data.migrated).toBe(true);
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBe(userId);
    expect(db.portfolioFolders).toHaveLength(1);
    expect(db.userPreferences).toHaveLength(1);
    expect(db.portfolioFolders[0]).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: userId,
      }),
    );
    expect(db.userPreferences[0]).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: userId,
      }),
    );
    expect(db.collectionItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: userId,
        folder_id: db.portfolioFolders[0]?.id,
      }),
    );
    expect(db.wishlistItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: userId,
      }),
    );
  });

  it("creates default assets when anonymous_id lacks a bearer token because an id alone must not prove guest ownership", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-register-no-token-victim",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const anonymousId = anonymousBody.data.anonymous_id;

    const sendResponse = await requestRegisterSendCode(env, {
      email: "no-token-migrate@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const response = await requestRegisterVerify(env, {
      email: "no-token-migrate@example.com",
      code: code.code,
      password: "correct-password",
      anonymous_id: anonymousId,
    });
    const body = (await response.json()) as RegisterVerifySuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.migrated).toBe(false);
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBeNull();
    expect(
      db.portfolioFolders.filter(
        (row) => row.owner_type === "anonymous" && row.owner_id === anonymousId,
      ),
    ).toHaveLength(1);
    expect(
      db.userPreferences.filter(
        (row) => row.owner_type === "anonymous" && row.owner_id === anonymousId,
      ),
    ).toHaveLength(1);
    expect(
      db.portfolioFolders.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
    expect(
      db.userPreferences.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
  });

  it("creates default assets when the bearer token owner differs because guests must not migrate another anonymous account", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const victimResponse = await requestAnonymous(
      env,
      "device-register-mismatch-victim",
    );
    const victimBody =
      (await victimResponse.json()) as AnonymousSuccessResponse;
    const attackerResponse = await requestAnonymous(
      env,
      "device-register-mismatch-attacker",
    );
    const attackerBody =
      (await attackerResponse.json()) as AnonymousSuccessResponse;

    const sendResponse = await requestRegisterSendCode(env, {
      email: "mismatch-migrate@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const response = await requestRegisterVerify(
      env,
      {
        email: "mismatch-migrate@example.com",
        code: code.code,
        password: "correct-password",
        anonymous_id: victimBody.data.anonymous_id,
      },
      `Bearer ${attackerBody.data.access_token}`,
    );
    const body = (await response.json()) as RegisterVerifySuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.migrated).toBe(false);
    expect(db.anonymousAccounts.map((row) => row.upgraded_user_id)).toEqual([
      null,
      null,
    ]);
    expect(
      db.portfolioFolders.filter(
        (row) =>
          row.owner_type === "anonymous" &&
          row.owner_id === victimBody.data.anonymous_id,
      ),
    ).toHaveLength(1);
    expect(
      db.portfolioFolders.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
    expect(
      db.userPreferences.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
  });

  it("creates default assets when the matching anonymous session is revoked because stale session proof must not authorize migration", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-register-revoked-session",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const anonymousId = anonymousBody.data.anonymous_id;
    const session = db.sessions.find(
      (row) => row.owner_type === "anonymous" && row.owner_id === anonymousId,
    );

    if (!session) {
      throw new Error("Expected anonymous session.");
    }

    session.revoked_at = "2026-07-03T00:00:00.000Z";

    const sendResponse = await requestRegisterSendCode(env, {
      email: "revoked-session-migrate@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const response = await requestRegisterVerify(
      env,
      {
        email: "revoked-session-migrate@example.com",
        code: code.code,
        password: "correct-password",
        anonymous_id: anonymousId,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as RegisterVerifySuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.migrated).toBe(false);
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBeNull();
    expect(
      db.portfolioFolders.filter(
        (row) => row.owner_type === "anonymous" && row.owner_id === anonymousId,
      ),
    ).toHaveLength(1);
    expect(
      db.portfolioFolders.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
    expect(
      db.userPreferences.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
  });

  it("creates default assets when the matching anonymous session is expired because stale session proof must not authorize migration", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-register-expired-session",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const anonymousId = anonymousBody.data.anonymous_id;
    const session = db.sessions.find(
      (row) => row.owner_type === "anonymous" && row.owner_id === anonymousId,
    );

    if (!session) {
      throw new Error("Expected anonymous session.");
    }

    session.expires_at = "2000-01-01T00:00:00.000Z";

    const sendResponse = await requestRegisterSendCode(env, {
      email: "expired-session-migrate@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const response = await requestRegisterVerify(
      env,
      {
        email: "expired-session-migrate@example.com",
        code: code.code,
        password: "correct-password",
        anonymous_id: anonymousId,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as RegisterVerifySuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.migrated).toBe(false);
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBeNull();
    expect(
      db.portfolioFolders.filter(
        (row) => row.owner_type === "anonymous" && row.owner_id === anonymousId,
      ),
    ).toHaveLength(1);
    expect(
      db.portfolioFolders.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
    expect(
      db.userPreferences.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
  });

  it("returns 422 when a live anonymous account is upgraded before the migration gate because stale guest state must not create durable credentials", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-register-upgrade-race",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const anonymousId = anonymousBody.data.anonymous_id;
    const anonymousFolder = db.portfolioFolders.find(
      (row) => row.owner_type === "anonymous" && row.owner_id === anonymousId,
    );

    if (!anonymousFolder) {
      throw new Error("Expected anonymous folder.");
    }

    db.collectionItems.push({
      id: "collection-upgrade-race",
      owner_type: "anonymous",
      owner_id: anonymousId,
      folder_id: anonymousFolder.id,
      card_ref: "card-upgrade-race",
      updated_at: "2026-07-02T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "wishlist-upgrade-race",
      owner_type: "anonymous",
      owner_id: anonymousId,
      card_ref: "card-upgrade-race",
    });

    const sendResponse = await requestRegisterSendCode(env, {
      email: "upgrade-race@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    db.upgradeAnonymousBeforeUpgrade = true;

    const response = await requestRegisterVerify(
      env,
      {
        email: "upgrade-race@example.com",
        code: code.code,
        password: "correct-password",
        anonymous_id: anonymousId,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Guest account is no longer available.",
      },
    });
    expect(code.used_at).toEqual(expect.any(String));
    expect(db.users).toHaveLength(0);
    expect(
      db.sessions.filter((row) => row.owner_type === "user"),
    ).toHaveLength(0);
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBe("existing-user");
    expect(db.portfolioFolders).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousId,
      }),
    ]);
    expect(db.userPreferences).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousId,
      }),
    ]);
    expect(db.collectionItems).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousId,
        folder_id: anonymousFolder.id,
      }),
    ]);
    expect(db.wishlistItems).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousId,
      }),
    ]);
  });

  it("creates default assets for an invalid anonymous_id because registration must not fail on stale guest state", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "invalid-anonymous@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const response = await requestRegisterVerify(env, {
      email: "invalid-anonymous@example.com",
      code: code.code,
      password: "correct-password",
      anonymous_id: "missing-anonymous",
    });
    const body = (await response.json()) as RegisterVerifySuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.migrated).toBe(false);
    expect(
      db.portfolioFolders.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
    expect(
      db.userPreferences.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
  });

  it("keeps an upgraded anonymous account untouched because registration must not steal prior guest work", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-register-upgraded",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const anonymousId = anonymousBody.data.anonymous_id;
    const account = db.anonymousAccounts[0];
    const anonymousFolder = db.portfolioFolders[0];

    if (!account || !anonymousFolder) {
      throw new Error("Expected anonymous state.");
    }

    account.upgraded_user_id = "existing-user";
    db.collectionItems.push({
      id: "collection-upgraded",
      owner_type: "anonymous",
      owner_id: anonymousId,
      folder_id: anonymousFolder.id,
      card_ref: "card-upgraded",
      updated_at: "2026-07-02T00:00:00.000Z",
    });

    const sendResponse = await requestRegisterSendCode(env, {
      email: "upgraded-anonymous@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const response = await requestRegisterVerify(
      env,
      {
        email: "upgraded-anonymous@example.com",
        code: code.code,
        password: "correct-password",
        anonymous_id: anonymousId,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as RegisterVerifySuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.migrated).toBe(false);
    expect(account.upgraded_user_id).toBe("existing-user");
    expect(db.collectionItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousId,
      }),
    );
    expect(
      db.portfolioFolders.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
    expect(
      db.userPreferences.filter(
        (row) =>
          row.owner_type === "user" && row.owner_id === body.data.user_id,
      ),
    ).toHaveLength(1);
  });

  it("returns 422 for a reused code because one-time email proof must not create a second durable account", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const firstResponse = await requestRegisterVerify(env, {
      email: "owner@example.com",
      code: code.code,
      password: "correct-password",
    });
    expect(firstResponse.status).toBe(200);

    const response = await requestRegisterVerify(env, {
      email: "owner@example.com",
      code: code.code,
      password: "another-password",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Incorrect verification code.",
      },
    });
    expect(db.users).toHaveLength(1);
    expect(db.sessions).toHaveLength(1);
  });

  it("returns 422 for an expired code because stale inbox ownership proof must not create a user", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    code.expires_at = "2000-01-01T00:00:00.000Z";

    const response = await requestRegisterVerify(env, {
      email: "owner@example.com",
      code: code.code,
      password: "correct-password",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Incorrect verification code.",
      },
    });
    expect(db.users).toHaveLength(0);
    expect(db.sessions).toHaveLength(0);
    expect(code.used_at).toBeNull();
  });

  it("returns 422 for a short password because a verified email still needs a durable credential", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const response = await requestRegisterVerify(env, {
      email: "owner@example.com",
      code: code.code,
      password: "short",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Password must be at least 8 characters.",
      },
    });
    expect(db.users).toHaveLength(0);
    expect(db.sessions).toHaveLength(0);
    expect(code.used_at).toBeNull();
  });

  it("returns 500 / INTERNAL_ERROR when JWT_SECRET is blank because verified registration must not create unusable sessions", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    env.JWT_SECRET = "   ";

    const response = await requestRegisterVerify(env, {
      email: "owner@example.com",
      code: code.code,
      password: "correct-password",
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
    expect(db.users).toHaveLength(0);
    expect(db.sessions).toHaveLength(0);
    expect(code.used_at).toBeNull();
  });

  it("returns 500 / INTERNAL_ERROR when the registration batch fails because partially persisted credentials must not be reported as usable", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const errorSpy = vi
      .spyOn(console, "error")
      .mockImplementation(() => undefined);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    db.failNextBatch = true;

    try {
      const response = await requestRegisterVerify(env, {
        email: "owner@example.com",
        code: code.code,
        password: "correct-password",
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
      expect(db.users).toHaveLength(0);
      expect(db.sessions).toHaveLength(0);
      expect(code.used_at).toBeNull();
      expect(errorSpy).toHaveBeenCalledWith(
        "Failed to verify register code.",
        expect.any(Error),
      );
    } finally {
      errorSpy.mockRestore();
    }
  });

  it("returns 422 when the code is consumed between select and update because single-use proof must be atomically consumed", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    db.consumeNextRegisterCodeBeforeUpdate = true;

    const response = await requestRegisterVerify(env, {
      email: "owner@example.com",
      code: code.code,
      password: "correct-password",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Incorrect verification code.",
      },
    });
    expect(code.used_at).toEqual(expect.any(String));
    expect(db.users).toHaveLength(0);
    expect(
      db.portfolioFolders.filter((row) => row.owner_type === "user"),
    ).toHaveLength(0);
    expect(
      db.userPreferences.filter((row) => row.owner_type === "user"),
    ).toHaveLength(0);
    expect(db.sessions).toHaveLength(0);
  });

  it("returns 409 for an existing email during verify because send-code and account creation can race", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    db.users.push({
      id: "existing-user",
      email: "owner@example.com",
      password_hash: null,
      display_name: "Existing User",
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestRegisterVerify(env, {
      email: "owner@example.com",
      code: code.code,
      password: "correct-password",
    });
    const body = await response.json();

    expect(response.status).toBe(409);
    expect(body).toEqual({
      success: false,
      error: {
        code: "CONFLICT",
        message: "Email is already registered.",
      },
    });
    expect(db.users).toHaveLength(1);
    expect(db.sessions).toHaveLength(0);
    expect(code.used_at).toBeNull();
  });

  it("returns 409 for a soft-deleted email during verify because user.email remains globally reserved", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    db.users.push({
      id: "deleted-user",
      email: "owner@example.com",
      password_hash: null,
      display_name: "Deleted User",
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: "2026-07-03T00:00:00.000Z",
    });

    const response = await requestRegisterVerify(env, {
      email: "owner@example.com",
      code: code.code,
      password: "correct-password",
    });
    const body = await response.json();

    expect(response.status).toBe(409);
    expect(body).toEqual({
      success: false,
      error: {
        code: "CONFLICT",
        message: "Email is already registered.",
      },
    });
    expect(db.users).toHaveLength(1);
    expect(db.sessions).toHaveLength(0);
    expect(code.used_at).toBeNull();
  });

  it("returns 409 when user insert hits an email unique race because conflict semantics must survive concurrent registration", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sendResponse = await requestRegisterSendCode(env, {
      email: "race@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    db.createConflictingUserBeforeNextUserInsert = true;

    const response = await requestRegisterVerify(env, {
      email: "race@example.com",
      code: code.code,
      password: "correct-password",
    });
    const body = await response.json();

    expect(response.status).toBe(409);
    expect(body).toEqual({
      success: false,
      error: {
        code: "CONFLICT",
        message: "Email is already registered.",
      },
    });
    expect(db.users).toEqual([
      expect.objectContaining({
        id: "concurrent-user",
        email: "race@example.com",
      }),
    ]);
    expect(
      db.sessions.filter((row) => row.owner_type === "user"),
    ).toHaveLength(0);
  });
});

describe("POST /api/v1/auth/login", () => {
  it("creates a new user session because registered email owners must be able to return after registration", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const password = "correct-password";

    const sendResponse = await requestRegisterSendCode(env, {
      email: "login.owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const registerResponse = await requestRegisterVerify(env, {
      email: "login.owner@example.com",
      code: code.code,
      password,
    });
    expect(registerResponse.status).toBe(200);
    const existingUserSessionCount = db.sessions.filter(
      (row) => row.owner_type === "user",
    ).length;

    const response = await requestLogin(env, {
      email: "login.owner@example.com",
      password,
    });
    const body = (await response.json()) as LoginSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        user_id: expect.any(String),
        email: "login.owner@example.com",
        access_token: expect.any(String),
        refresh_token: expect.any(String),
        expires_in: 900,
      },
    });

    const loginSession = db.sessions.at(-1);

    if (!loginSession) {
      throw new Error("Expected login session.");
    }

    expect(db.sessions.filter((row) => row.owner_type === "user")).toHaveLength(
      existingUserSessionCount + 1,
    );
    expect(loginSession.owner_type).toBe("user");
    expect(loginSession.owner_id).toBe(body.data.user_id);
    expect(loginSession.refresh_token).toBe(
      await hashRefreshToken(body.data.refresh_token),
    );
    expect(loginSession.refresh_token).not.toBe(body.data.refresh_token);

    const currentResponse = await requestCurrentAccount(
      env,
      `Bearer ${body.data.access_token}`,
    );
    const currentBody =
      (await currentResponse.json()) as CurrentAccountSuccessResponse;

    expect(currentResponse.status).toBe(200);
    expect(currentBody.data).toEqual(
      expect.objectContaining({
        owner_type: "user",
        user_id: body.data.user_id,
        anonymous_id: null,
        email: "login.owner@example.com",
      }),
    );
  });

  it("normalizes email before password verification because login input should match registration input rules", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const password = "correct-password";

    const sendResponse = await requestRegisterSendCode(env, {
      email: "mixed.login@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const registerResponse = await requestRegisterVerify(env, {
      email: "mixed.login@example.com",
      code: code.code,
      password,
    });
    expect(registerResponse.status).toBe(200);

    const response = await requestLogin(env, {
      email: "  Mixed.Login@Example.COM  ",
      password,
    });
    const body = (await response.json()) as LoginSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.email).toBe("mixed.login@example.com");
  });

  it("runs password verification for an unknown email because failed login paths must not expose account existence by cost", async () => {
    const env = createTestEnv();
    const deriveBits = vi.spyOn(crypto.subtle, "deriveBits");

    try {
      const response = await requestLogin(env, {
        email: "missing.login@example.com",
        password: "candidate-password",
      });
      const body = await response.json();

      expect(response.status).toBe(422);
      expect(body).toEqual({
        success: false,
        error: {
          code: "VALIDATION_ERROR",
          message: "Incorrect password. Please try again.",
        },
      });
      expect(deriveBits).toHaveBeenCalledTimes(1);
    } finally {
      deriveBits.mockRestore();
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
      password_hash: null,
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
      password_hash: null,
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
      password_hash: null,
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
      password_hash: null,
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
