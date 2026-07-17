import {
  hashPassword,
  hashRefreshToken,
  signAccessToken,
  verifyPassword,
} from "@kando/auth-core";
import { describe, expect, it, vi } from "vitest";

vi.mock("../mail/verification-email", () => ({
  sendVerificationEmail: vi.fn().mockResolvedValue("message-id"),
}));

vi.mock("./oauth-provider", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./oauth-provider")>();
  const resolveTestIdentity = (
    value: string | null,
    prefix: string,
    provider: "google" | "apple",
  ) => {
    const parts = value?.split(":") ?? [];
    if (
      parts.length !== 3 ||
      parts[0] !== prefix ||
      !/^[A-Za-z0-9._-]{1,128}$/.test(parts[1]) ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(parts[2])
    ) {
      return null;
    }
    return { provider, providerUid: parts[1], email: parts[2].toLowerCase() };
  };
  return {
    ...actual,
    resolveGoogleIdentity: async (input: { idToken: string | null }) =>
      resolveTestIdentity(input.idToken, "mock-google", "google"),
    resolveAppleIdentity: async (input: { idToken: string | null }) =>
      resolveTestIdentity(input.idToken, "mock-apple", "apple"),
  };
});

import app, { type Env as AppEnv } from "../index";
import { migrateGuestAssetsToUser } from "./guest-migration";

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
  login_method?: "email" | "google" | "apple" | null;
  refresh_token: string;
  expires_at: string;
  created_at: string;
  revoked_at: string | null;
};

type SessionLookupRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  login_method?: "email" | "google" | "apple" | null;
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

type AuthIdentityRow = {
  id: string;
  user_id: string;
  provider: "google" | "apple";
  provider_uid: string;
  created_at: string;
};

type VerificationCodeRow = {
  id: string;
  email: string;
  code: string;
  purpose: "register" | "reset_password";
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
    login_method: "email" | "google" | "apple" | null;
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
    login_method: "email";
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
    login_method: "email";
    access_token: string;
    refresh_token: string;
    expires_in: number;
  };
};

type OAuthSuccessResponse = {
  success: true;
  data: {
    user_id: string;
    email: string;
    login_method: "google" | "apple";
    access_token: string;
    refresh_token: string;
    expires_in: number;
    is_new_user: boolean;
    migrated: boolean;
  };
};

type ForgotPasswordVerifyCodeSuccessResponse = {
  success: true;
  data: { reset_token: string };
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
  authIdentities: AuthIdentityRow[] = [];
  verificationCodes: VerificationCodeRow[] = [];
  scanRecords: Array<{
    owner_type: "anonymous" | "user";
    owner_id: string;
    image_url: string | null;
  }> = [];
  consumeNextRegisterCodeBeforeUpdate = false;
  failNextBatch = false;
  failNextFirst = false;
  failNextRun = false;
  failRunOnSql: string | null = null;
  createConflictingUserBeforeNextUserInsert = false;
  createConflictingIdentityBeforeNextAuthIdentityInsert = false;
  concurrentResetCodeLookupBarrierSize = 0;
  concurrentResetCodeLookupResolutions: Array<() => void> = [];
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

    const snapshot = {
      anonymousAccounts: this.anonymousAccounts.map((row) => ({ ...row })),
      portfolioFolders: this.portfolioFolders.map((row) => ({ ...row })),
      userPreferences: this.userPreferences.map((row) => ({ ...row })),
      collectionItems: this.collectionItems.map((row) => ({ ...row })),
      wishlistItems: this.wishlistItems.map((row) => ({ ...row })),
      sessions: this.sessions.map((row) => ({ ...row })),
      users: this.users.map((row) => ({ ...row })),
      authIdentities: this.authIdentities.map((row) => ({ ...row })),
      verificationCodes: this.verificationCodes.map((row) => ({ ...row })),
      scanRecords: this.scanRecords.map((row) => ({ ...row })),
    };
    const results: D1Result<T>[] = [];

    try {
      for (const statement of statements) {
        results.push(await statement.run<T>());
      }
    } catch (error) {
      const concurrentUsers = this.users.filter(
        (user) =>
          user.id === "concurrent-user" &&
          !snapshot.users.some((snapshotUser) => snapshotUser.id === user.id),
      );
      const concurrentAuthIdentities = this.authIdentities.filter(
        (identity) =>
          identity.id === "concurrent-auth-identity" &&
          !snapshot.authIdentities.some(
            (snapshotIdentity) => snapshotIdentity.id === identity.id,
          ),
      );
      this.anonymousAccounts = snapshot.anonymousAccounts;
      this.portfolioFolders = snapshot.portfolioFolders;
      this.userPreferences = snapshot.userPreferences;
      this.collectionItems = snapshot.collectionItems;
      this.wishlistItems = snapshot.wishlistItems;
      this.sessions = snapshot.sessions;
      this.users = [...snapshot.users, ...concurrentUsers];
      this.authIdentities = [
        ...snapshot.authIdentities,
        ...concurrentAuthIdentities,
      ];
      this.verificationCodes = snapshot.verificationCodes;
      this.scanRecords = snapshot.scanRecords;
      throw error;
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

    if (normalizedSql === SELECT_LIVE_EMAIL_PASSWORD_USER_SQL) {
      const [email] = values as [string];
      const user = this.users.find(
        (row) =>
          row.email === email &&
          row.deleted_at === null &&
          row.password_hash !== null,
      );

      return user ? ({ id: user.id } as T) : null;
    }

    if (normalizedSql === SELECT_OAUTH_IDENTITY_SQL) {
      const [provider, providerUid] = values as [string, string];
      const identity = this.authIdentities.find(
        (row) => row.provider === provider && row.provider_uid === providerUid,
      );

      return identity ? ({ user_id: identity.user_id } as T) : null;
    }

    if (normalizedSql === SELECT_LIVE_USER_BY_ID_SQL) {
      const [id] = values as [string];
      const user = this.users.find(
        (row) => row.id === id && row.deleted_at === null,
      );

      return user ? ({ id: user.id } as T) : null;
    }

    if (normalizedSql === SELECT_USER_BY_EMAIL_FOR_OAUTH_SQL) {
      const [email] = values as [string];
      const user = this.users.find((row) => row.email === email);

      return user
        ? ({ id: user.id, deleted_at: user.deleted_at } as T)
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

    if (normalizedSql === SELECT_LATEST_RESET_CODE_SQL) {
      const [email] = values as [string];
      await this.waitForConcurrentResetCodeLookup();
      const code = this.verificationCodes
        .filter(
          (row) => row.email === email && row.purpose === "reset_password",
        )
        .sort((left, right) => right.created_at.localeCompare(left.created_at))
        .at(0);

      return code
        ? ({
            id: code.id,
            code: code.code,
            expires_at: code.expires_at,
            used_at: code.used_at,
            created_at: code.created_at,
          } as T)
        : null;
    }

    if (normalizedSql === SELECT_RESET_CODE_BY_ID_EMAIL_SQL) {
      const [id, email] = values as [string, string];
      const code = this.verificationCodes.find(
        (row) =>
          row.id === id &&
          row.email === email &&
          row.purpose === "reset_password",
      );

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

    if (normalizedSql === SELECT_ANONYMOUS_ACCOUNT_FOR_MIGRATION_SQL) {
      const [id] = values as [string];
      const account = this.anonymousAccounts.find((row) => row.id === id);

      return account
        ? ({
            id: account.id,
            upgraded_user_id: account.upgraded_user_id,
          } as T)
        : null;
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

    if (normalizedSql === SELECT_CURRENT_SESSION_SQL) {
      const [id] = values as [string];
      const session = this.sessions.find((row) => row.id === id);

      if (!session) {
        return null;
      }

      return {
        id: session.id,
        owner_type: session.owner_type,
        owner_id: session.owner_id,
        login_method: session.login_method ?? null,
        expires_at: session.expires_at,
        revoked_at: session.revoked_at,
      } as T;
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

  async all<T = unknown>(sql: string, values: unknown[]): Promise<D1Result<T>> {
    const normalizedSql = normalizeSql(sql);
    if (normalizedSql.startsWith("SELECT image_url FROM scan_record")) {
      const [ownerType, ownerId] = values as ["anonymous" | "user", string];
      const results = this.scanRecords.filter(
          (row) => row.owner_type === ownerType && row.owner_id === ownerId && row.image_url,
        ) as T[];
      return { ...okResult<T>(), results };
    }
    throw new Error(`Unsupported all() SQL: ${normalizedSql}`);
  }

  async run<T = unknown>(sql: string, values: unknown[]): Promise<D1Result<T>> {
    if (this.failNextRun) {
      this.failNextRun = false;
      throw new Error("Injected D1 run failure.");
    }

    const normalizedSql = normalizeSql(sql);

    if (this.failRunOnSql === normalizedSql) {
      this.failRunOnSql = null;
      throw new Error("Injected D1 run failure for SQL.");
    }

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
        login_method: null,
        refresh_token: refreshToken,
        expires_at: expiresAt,
        created_at: createdAt,
        revoked_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_VERIFICATION_CODE_SQL) {
      const [
        id,
        email,
        code,
        expiresAt,
        createdAt,
        guardedEmail,
        resendWindowStartedAt,
      ] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
        string,
      ];
      const hasRecentUnusedCode = this.verificationCodes.some(
        (row) =>
          row.email === guardedEmail &&
          row.purpose === "register" &&
          row.used_at === null &&
          row.created_at > resendWindowStartedAt,
      );
      if (hasRecentUnusedCode) {
        return okResult<T>(0);
      }
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

    if (normalizedSql.startsWith("DELETE FROM scan_record")) {
      const [ownerType, ownerId] = values as ["anonymous" | "user", string];
      const before = this.scanRecords.length;
      this.scanRecords = this.scanRecords.filter(
        (row) => row.owner_type !== ownerType || row.owner_id !== ownerId,
      );
      return okResult<T>(before - this.scanRecords.length);
    }

    if (normalizedSql.startsWith("UPDATE scan_record SET owner_type = 'user'")) {
      const [userId, anonymousId] = values as [string, string];
      const accountUpgraded = this.hasUpgradedAnonymousAccount(
        values.length === 6 ? String(values[4]) : String(values[2]),
        values.length === 6 ? String(values[5]) : String(values[3]),
      );
      const guardSatisfied = values.length !== 6 || this.verificationCodes.some(
        (row) => row.id === values[2] && row.used_at === values[3],
      );
      if (!accountUpgraded || !guardSatisfied) return okResult<T>(0);
      var changes = 0;
      for (const row of this.scanRecords) {
        if (row.owner_type === "anonymous" && row.owner_id === anonymousId) {
          row.owner_type = "user";
          row.owner_id = userId;
          changes += 1;
        }
      }
      return okResult<T>(changes);
    }

    if (normalizedSql === DELETE_VERIFICATION_CODE_SQL) {
      const [id] = values as [string];
      const index = this.verificationCodes.findIndex(
        (row) => row.id === id && row.used_at === null,
      );
      if (index < 0) return okResult<T>(0);
      this.verificationCodes.splice(index, 1);
      return okResult<T>();
    }

    if (normalizedSql === INSERT_RESET_CODE_SQL) {
      const [
        id,
        email,
        code,
        expiresAt,
        createdAt,
        guardedEmail,
        resendWindowStartedAt,
      ] = values as [
        string,
        string,
        string,
        string,
        string,
        string,
        string,
      ];

      const hasRecentUnusedResetCode = this.verificationCodes.some(
        (row) =>
          row.email === guardedEmail &&
          row.purpose === "reset_password" &&
          row.used_at === null &&
          row.created_at > resendWindowStartedAt,
      );

      if (hasRecentUnusedResetCode) {
        return okResult<T>(0);
      }

      this.verificationCodes.push({
        id,
        email,
        code,
        purpose: "reset_password",
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
        login_method: "email",
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
        login_method: "email",
        refresh_token: refreshToken,
        expires_at: expiresAt,
        created_at: createdAt,
        revoked_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_OAUTH_USER_SQL) {
      const [id, email, createdAt, updatedAt] = values as [
        string,
        string,
        string,
        string,
      ];

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
        password_hash: null,
        display_name: null,
        created_at: createdAt,
        updated_at: updatedAt,
        deleted_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_AUTH_IDENTITY_SQL) {
      const [id, userId, provider, providerUid, createdAt] = values as [
        string,
        string,
        "google" | "apple",
        string,
        string,
      ];

      if (
        !this.users.some(
          (row) => row.id === userId && row.deleted_at === null,
        )
      ) {
        return okResult<T>(0);
      }

      if (this.createConflictingIdentityBeforeNextAuthIdentityInsert) {
        this.createConflictingIdentityBeforeNextAuthIdentityInsert = false;
        this.authIdentities.push({
          id: "concurrent-auth-identity",
          user_id: userId,
          provider,
          provider_uid: providerUid,
          created_at: "2026-07-03T00:00:00.000Z",
        });
      }

      if (
        this.authIdentities.some(
          (row) =>
            row.provider === provider && row.provider_uid === providerUid,
        )
      ) {
        throw new Error(
          "UNIQUE constraint failed: auth_identity.provider, auth_identity.provider_uid",
        );
      }

      this.authIdentities.push({
        id,
        user_id: userId,
        provider,
        provider_uid: providerUid,
        created_at: createdAt,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_OAUTH_USER_FOR_UPGRADED_GUEST_SQL) {
      const [id, email, createdAt, updatedAt, anonymousId, upgradedUserId] =
        values as [string, string, string, string, string, string];

      if (!this.hasUpgradedAnonymousAccount(anonymousId, upgradedUserId)) {
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
        password_hash: null,
        display_name: null,
        created_at: createdAt,
        updated_at: updatedAt,
        deleted_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_AUTH_IDENTITY_FOR_UPGRADED_GUEST_SQL) {
      const [
        id,
        userId,
        provider,
        providerUid,
        createdAt,
        anonymousId,
        upgradedUserId,
      ] = values as [
        string,
        string,
        "google" | "apple",
        string,
        string,
        string,
        string,
      ];

      if (!this.hasUpgradedAnonymousAccount(anonymousId, upgradedUserId)) {
        return okResult<T>(0);
      }

      if (this.createConflictingIdentityBeforeNextAuthIdentityInsert) {
        this.createConflictingIdentityBeforeNextAuthIdentityInsert = false;
        this.authIdentities.push({
          id: "concurrent-auth-identity",
          user_id: userId,
          provider,
          provider_uid: providerUid,
          created_at: "2026-07-03T00:00:00.000Z",
        });
      }

      if (
        this.authIdentities.some(
          (row) =>
            row.provider === provider && row.provider_uid === providerUid,
        )
      ) {
        throw new Error(
          "UNIQUE constraint failed: auth_identity.provider, auth_identity.provider_uid",
        );
      }

      this.authIdentities.push({
        id,
        user_id: userId,
        provider,
        provider_uid: providerUid,
        created_at: createdAt,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_OAUTH_USER_PORTFOLIO_FOLDER_SQL) {
      const [id, ownerId, createdAt, updatedAt] = values as [
        string,
        string,
        string,
        string,
      ];

      if (
        !this.users.some(
          (row) => row.id === ownerId && row.deleted_at === null,
        )
      ) {
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

    if (normalizedSql === INSERT_OAUTH_USER_PREFERENCE_SQL) {
      const [id, ownerId, createdAt, updatedAt] = values as [
        string,
        string,
        string,
        string,
      ];

      if (
        !this.users.some(
          (row) => row.id === ownerId && row.deleted_at === null,
        )
      ) {
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

    if (normalizedSql === INSERT_OAUTH_USER_SESSION_SQL) {
      const [id, ownerId, loginMethod, refreshToken, expiresAt, createdAt] =
        values as [
          string,
          string,
          "google" | "apple",
          string,
          string,
          string,
        ];

      this.sessions.push({
        id,
        owner_type: "user",
        owner_id: ownerId,
        login_method: loginMethod,
        refresh_token: refreshToken,
        expires_at: expiresAt,
        created_at: createdAt,
        revoked_at: null,
      });
      return okResult<T>();
    }

    if (normalizedSql === INSERT_USER_SESSION_FOR_UPGRADED_GUEST_SQL) {
      const [
        id,
        ownerId,
        loginMethod,
        refreshToken,
        expiresAt,
        createdAt,
        anonymousId,
        upgradedUserId,
      ] = values as [
        string,
        string,
        "google" | "apple",
        string,
        string,
        string,
        string,
        string,
      ];

      if (!this.hasUpgradedAnonymousAccount(anonymousId, upgradedUserId)) {
        return okResult<T>(0);
      }

      this.sessions.push({
        id,
        owner_type: "user",
        owner_id: ownerId,
        login_method: loginMethod,
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

    if (normalizedSql === UPDATE_RESET_CODE_USED_SQL) {
      const [usedAt, id] = values as [string, string];
      const code = this.verificationCodes.find(
        (row) => row.id === id && row.used_at === null,
      );

      if (code) {
        code.used_at = usedAt;
      }

      return okResult<T>(code ? 1 : 0);
    }

    if (normalizedSql === UPDATE_LIVE_EMAIL_PASSWORD_USER_SQL) {
      const [passwordHash, updatedAt, email, codeId, usedAt] = values as [
        string,
        string,
        string,
        string,
        string,
      ];

      if (!this.hasConsumedResetCode(codeId, usedAt)) {
        return okResult<T>(0);
      }

      const user = this.users.find(
        (row) =>
          row.email === email &&
          row.deleted_at === null &&
          row.password_hash !== null,
      );

      if (user) {
        user.password_hash = passwordHash;
        user.updated_at = updatedAt;
      }

      return okResult<T>(user ? 1 : 0);
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

    if (normalizedSql === UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_UNGUARDED_SQL) {
      const [userId, anonymousId] = values as [string, string];

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

    if (
      normalizedSql === REMAP_CONFLICTING_COLLECTION_ITEMS_TO_USER_FOLDER_SQL
    ) {
      const [
        userId,
        anonymousId,
        updatedAt,
        ownerId,
        matchingUserId,
        matchingAnonymousId,
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
        string,
      ];

      if (
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      let changes = 0;
      for (const item of this.collectionItems) {
        if (item.owner_type !== "anonymous" || item.owner_id !== ownerId) {
          continue;
        }

        const sourceFolder = this.portfolioFolders.find(
          (folder) =>
            folder.id === item.folder_id &&
            folder.owner_type === "anonymous" &&
            folder.owner_id === matchingAnonymousId,
        );
        const targetFolder = sourceFolder
          ? this.portfolioFolders.find(
              (folder) =>
                folder.owner_type === "user" &&
                folder.owner_id === matchingUserId &&
                folder.name === sourceFolder.name,
            )
          : undefined;

        if (targetFolder && userId === matchingUserId && anonymousId === ownerId) {
          item.folder_id = targetFolder.id;
          item.updated_at = updatedAt;
          changes += 1;
        }
      }

      return okResult<T>(changes);
    }

    if (normalizedSql === REMAP_ANONYMOUS_USER_PREFERENCE_FOLDER_SQL) {
      const [
        userId,
        anonymousId,
        updatedAt,
        ownerId,
        matchingUserId,
        matchingAnonymousId,
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
        string,
      ];

      if (
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      let changes = 0;
      for (const preference of this.userPreferences) {
        if (
          preference.owner_type !== "anonymous" ||
          preference.owner_id !== ownerId ||
          preference.last_selected_folder_id === null
        ) {
          continue;
        }

        const sourceFolder = this.portfolioFolders.find(
          (folder) =>
            folder.id === preference.last_selected_folder_id &&
            folder.owner_type === "anonymous" &&
            folder.owner_id === matchingAnonymousId,
        );
        const targetFolder = sourceFolder
          ? this.portfolioFolders.find(
              (folder) =>
                folder.owner_type === "user" &&
                folder.owner_id === matchingUserId &&
                folder.name === sourceFolder.name,
            )
          : undefined;

        if (targetFolder && userId === matchingUserId && anonymousId === ownerId) {
          preference.last_selected_folder_id = targetFolder.id;
          preference.updated_at = updatedAt;
          changes += 1;
        }
      }

      return okResult<T>(changes);
    }

    if (normalizedSql === DELETE_CONFLICTING_ANONYMOUS_PORTFOLIO_FOLDERS_SQL) {
      const [anonymousId, userId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string];

      if (
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      const before = this.portfolioFolders.length;
      this.portfolioFolders = this.portfolioFolders.filter(
        (folder) =>
          !(
            folder.owner_type === "anonymous" &&
            folder.owner_id === anonymousId &&
            this.portfolioFolders.some(
              (target) =>
                target.owner_type === "user" &&
                target.owner_id === userId &&
                target.name === folder.name,
            )
          ),
      );

      return okResult<T>(before - this.portfolioFolders.length);
    }

    if (
      normalizedSql === UPDATE_NON_CONFLICTING_ANONYMOUS_PORTFOLIO_FOLDERS_SQL
    ) {
      const [userId, updatedAt, anonymousId, matchingUserId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string, string, string];

      if (
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      let changes = 0;
      for (const folder of this.portfolioFolders) {
        if (
          folder.owner_type === "anonymous" &&
          folder.owner_id === anonymousId &&
          !this.portfolioFolders.some(
            (target) =>
              target.owner_type === "user" &&
              target.owner_id === matchingUserId &&
              target.name === folder.name,
          )
        ) {
          folder.owner_type = "user";
          folder.owner_id = userId;
          folder.updated_at = updatedAt;
          changes += 1;
        }
      }

      return okResult<T>(changes);
    }

    if (normalizedSql === UPDATE_ANONYMOUS_PORTFOLIO_FOLDERS_UNGUARDED_SQL) {
      const [userId, updatedAt, anonymousId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string, string];

      if (!this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)) {
        return okResult<T>(0);
      }

      const hasFolderNameConflict = this.portfolioFolders.some(
        (folder) =>
          folder.owner_type === "anonymous" &&
          folder.owner_id === anonymousId &&
          this.portfolioFolders.some(
            (target) =>
              target.owner_type === "user" &&
              target.owner_id === userId &&
              target.name === folder.name,
          ),
      );

      if (hasFolderNameConflict) {
        throw new Error(
          "UNIQUE constraint failed: portfolio_folder.owner_type, portfolio_folder.owner_id, portfolio_folder.name",
        );
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

    if (normalizedSql === UPDATE_ANONYMOUS_COLLECTION_ITEMS_UNGUARDED_SQL) {
      const [userId, updatedAt, anonymousId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string, string];

      if (!this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)) {
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

    if (normalizedSql === UPDATE_ANONYMOUS_WISHLIST_ITEMS_UNGUARDED_SQL) {
      const [userId, anonymousId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string];

      if (!this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)) {
        return okResult<T>(0);
      }

      const hasWishlistConflict = this.wishlistItems.some(
        (item) =>
          item.owner_type === "anonymous" &&
          item.owner_id === anonymousId &&
          this.wishlistItems.some(
            (target) =>
              target.owner_type === "user" &&
              target.owner_id === userId &&
              target.card_ref === item.card_ref,
          ),
      );

      if (hasWishlistConflict) {
        throw new Error(
          "UNIQUE constraint failed: wishlist_item.owner_type, wishlist_item.owner_id, wishlist_item.card_ref",
        );
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

    if (normalizedSql === DELETE_CONFLICTING_ANONYMOUS_WISHLIST_ITEMS_SQL) {
      const [anonymousId, userId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string];

      if (
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      const before = this.wishlistItems.length;
      this.wishlistItems = this.wishlistItems.filter(
        (item) =>
          !(
            item.owner_type === "anonymous" &&
            item.owner_id === anonymousId &&
            this.wishlistItems.some(
              (target) =>
                target.owner_type === "user" &&
                target.owner_id === userId &&
                target.card_ref === item.card_ref,
            )
          ),
      );

      return okResult<T>(before - this.wishlistItems.length);
    }

    if (normalizedSql === UPDATE_NON_CONFLICTING_ANONYMOUS_WISHLIST_ITEMS_SQL) {
      const [userId, anonymousId, matchingUserId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string, string];

      if (
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      let changes = 0;
      for (const item of this.wishlistItems) {
        if (
          item.owner_type === "anonymous" &&
          item.owner_id === anonymousId &&
          !this.wishlistItems.some(
            (target) =>
              target.owner_type === "user" &&
              target.owner_id === matchingUserId &&
              target.card_ref === item.card_ref,
          )
        ) {
          item.owner_type = "user";
          item.owner_id = userId;
          changes += 1;
        }
      }

      return okResult<T>(changes);
    }

    if (normalizedSql === DELETE_CONFLICTING_ANONYMOUS_USER_PREFERENCE_SQL) {
      const [anonymousId, userId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string];

      if (
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      const hasUserPreference = this.userPreferences.some(
        (preference) =>
          preference.owner_type === "user" && preference.owner_id === userId,
      );
      const before = this.userPreferences.length;

      if (hasUserPreference) {
        this.userPreferences = this.userPreferences.filter(
          (preference) =>
            !(
              preference.owner_type === "anonymous" &&
              preference.owner_id === anonymousId
            ),
        );
      }

      return okResult<T>(before - this.userPreferences.length);
    }

    if (normalizedSql === UPDATE_NON_CONFLICTING_ANONYMOUS_USER_PREFERENCE_SQL) {
      const [userId, updatedAt, anonymousId, matchingUserId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string, string, string];

      if (
        !this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)
      ) {
        return okResult<T>(0);
      }

      const hasUserPreference = this.userPreferences.some(
        (preference) =>
          preference.owner_type === "user" &&
          preference.owner_id === matchingUserId,
      );

      if (hasUserPreference) {
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

    if (normalizedSql === UPDATE_ANONYMOUS_USER_PREFERENCE_UNGUARDED_SQL) {
      const [userId, updatedAt, anonymousId, upgradedAnonymousId, upgradedUserId] =
        values as [string, string, string, string, string];

      if (!this.hasUpgradedAnonymousAccount(upgradedAnonymousId, upgradedUserId)) {
        return okResult<T>(0);
      }

      const hasPreferenceConflict = this.userPreferences.some(
        (preference) =>
          preference.owner_type === "anonymous" &&
          preference.owner_id === anonymousId &&
          this.userPreferences.some(
            (target) =>
              target.owner_type === "user" && target.owner_id === userId,
          ),
      );

      if (hasPreferenceConflict) {
        throw new Error(
          "UNIQUE constraint failed: user_preference.owner_type, user_preference.owner_id",
        );
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

    if (normalizedSql === UPDATE_USER_DELETED_SQL) {
      const [deletedAt, updatedAt, id] = values as [string, string, string];
      const user = this.users.find(
        (row) => row.id === id && row.deleted_at === null,
      );

      if (user) {
        user.deleted_at = deletedAt;
        user.updated_at = updatedAt;
      }

      return okResult<T>(user ? 1 : 0);
    }

    if (normalizedSql === REVOKE_OWNER_SESSIONS_SQL) {
      const [revokedAt, ownerType, ownerId] = values as [
        string,
        "anonymous" | "user",
        string,
      ];
      let changes = 0;

      for (const session of this.sessions) {
        if (
          session.owner_type === ownerType &&
          session.owner_id === ownerId &&
          session.revoked_at === null
        ) {
          session.revoked_at = revokedAt;
          changes += 1;
        }
      }

      return okResult<T>(changes);
    }

    if (normalizedSql === DELETE_ANONYMOUS_PORTFOLIO_FOLDERS_SQL) {
      const [ownerId] = values as [string];
      const before = this.portfolioFolders.length;
      this.portfolioFolders = this.portfolioFolders.filter(
        (row) => row.owner_type !== "anonymous" || row.owner_id !== ownerId,
      );

      return okResult<T>(before - this.portfolioFolders.length);
    }

    if (normalizedSql === DELETE_ANONYMOUS_COLLECTION_ITEMS_SQL) {
      const [ownerId] = values as [string];
      const before = this.collectionItems.length;
      this.collectionItems = this.collectionItems.filter(
        (row) => row.owner_type !== "anonymous" || row.owner_id !== ownerId,
      );

      return okResult<T>(before - this.collectionItems.length);
    }

    if (normalizedSql === DELETE_ANONYMOUS_WISHLIST_ITEMS_SQL) {
      const [ownerId] = values as [string];
      const before = this.wishlistItems.length;
      this.wishlistItems = this.wishlistItems.filter(
        (row) => row.owner_type !== "anonymous" || row.owner_id !== ownerId,
      );

      return okResult<T>(before - this.wishlistItems.length);
    }

    if (normalizedSql === DELETE_ANONYMOUS_USER_PREFERENCE_SQL) {
      const [ownerId] = values as [string];
      const before = this.userPreferences.length;
      this.userPreferences = this.userPreferences.filter(
        (row) => row.owner_type !== "anonymous" || row.owner_id !== ownerId,
      );

      return okResult<T>(before - this.userPreferences.length);
    }

    if (normalizedSql === INVALIDATE_ANONYMOUS_ACCOUNT_SQL) {
      const [upgradedUserId, id] = values as [string, string];
      const account = this.anonymousAccounts.find(
        (row) => row.id === id && row.upgraded_user_id === null,
      );

      if (account) {
        account.upgraded_user_id = upgradedUserId;
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
        login_method: "email",
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

  private hasConsumedResetCode(id: string, usedAt: string): boolean {
    return this.verificationCodes.some(
      (row) =>
        row.id === id &&
        row.purpose === "reset_password" &&
        row.used_at === usedAt,
    );
  }

  private async waitForConcurrentResetCodeLookup(): Promise<void> {
    if (this.concurrentResetCodeLookupBarrierSize <= 0) {
      return;
    }

    await new Promise<void>((resolve) => {
      this.concurrentResetCodeLookupResolutions.push(resolve);

      if (
        this.concurrentResetCodeLookupResolutions.length ===
        this.concurrentResetCodeLookupBarrierSize
      ) {
        const resolutions = this.concurrentResetCodeLookupResolutions.splice(0);
        this.concurrentResetCodeLookupBarrierSize = 0;

        for (const release of resolutions) {
          release();
        }
      }
    });
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

  all<T = unknown>(): Promise<D1Result<T>> {
    return this.db.all<T>(this.sql, this.values);
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

const SELECT_CURRENT_SESSION_SQL = normalizeSql(`
  SELECT id, owner_type, owner_id, login_method, expires_at, revoked_at
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

const SELECT_LIVE_EMAIL_PASSWORD_USER_SQL = normalizeSql(`
  SELECT id
  FROM user
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
  LIMIT 1
`);

const SELECT_OAUTH_IDENTITY_SQL = normalizeSql(`
  SELECT user_id
  FROM auth_identity
  WHERE auth_identity.provider = ?
    AND auth_identity.provider_uid = ?
  LIMIT 1
`);

const SELECT_LIVE_USER_BY_ID_SQL = normalizeSql(`
  SELECT id
  FROM user
  WHERE id = ? AND deleted_at IS NULL
  LIMIT 1
`);

const SELECT_USER_BY_EMAIL_FOR_OAUTH_SQL = normalizeSql(`
  SELECT id, deleted_at
  FROM user
  WHERE email = ?
  LIMIT 1
`);

const SELECT_LATEST_REGISTER_CODE_SQL = normalizeSql(`
  SELECT id, code, expires_at, used_at
  FROM verification_code
  WHERE email = ? AND purpose = 'register'
  ORDER BY created_at DESC
  LIMIT 1
`);

const SELECT_LATEST_RESET_CODE_SQL = normalizeSql(`
  SELECT id, code, expires_at, used_at, created_at
  FROM verification_code
  WHERE email = ? AND purpose = 'reset_password'
  ORDER BY created_at DESC
  LIMIT 1
`);

const SELECT_RESET_CODE_BY_ID_EMAIL_SQL = normalizeSql(`
  SELECT id, code, expires_at, used_at
  FROM verification_code
  WHERE id = ? AND email = ? AND purpose = 'reset_password'
  LIMIT 1
`);

const SELECT_LIVE_ANONYMOUS_ACCOUNT_SQL = normalizeSql(`
  SELECT id
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`);

const SELECT_ANONYMOUS_ACCOUNT_FOR_MIGRATION_SQL = normalizeSql(`
  SELECT id, upgraded_user_id
  FROM anonymous_account
  WHERE id = ?
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
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'anonymous', ?, NULL, ?, ?, ?, NULL)
`);

const INSERT_VERIFICATION_CODE_SQL = normalizeSql(`
  INSERT INTO verification_code
    (id, email, code, purpose, expires_at, used_at, created_at)
  SELECT ?, ?, ?, 'register', ?, NULL, ?
  WHERE NOT EXISTS (
    SELECT 1 FROM verification_code
    WHERE email = ? AND purpose = 'register' AND used_at IS NULL
      AND created_at > ?
  )
`);

const DELETE_VERIFICATION_CODE_SQL = normalizeSql(`
  DELETE FROM verification_code WHERE id = ? AND used_at IS NULL
`);

const INSERT_RESET_CODE_SQL = normalizeSql(`
  INSERT INTO verification_code
    (id, email, code, purpose, expires_at, used_at, created_at)
  SELECT ?, ?, ?, 'reset_password', ?, NULL, ?
  WHERE NOT EXISTS (
    SELECT 1
    FROM verification_code
    WHERE email = ? AND purpose = 'reset_password'
      AND used_at IS NULL
      AND created_at > ?
  )
`);

const INSERT_OAUTH_USER_SQL = normalizeSql(`
  INSERT INTO user
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  VALUES (?, ?, NULL, NULL, ?, ?, NULL)
`);

const INSERT_AUTH_IDENTITY_SQL = normalizeSql(`
  INSERT INTO auth_identity
    (id, user_id, provider, provider_uid, created_at)
  VALUES (?, ?, ?, ?, ?)
`);

const INSERT_OAUTH_USER_FOR_UPGRADED_GUEST_SQL = normalizeSql(`
  INSERT INTO user
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  SELECT ?, ?, NULL, NULL, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM anonymous_account
    WHERE id = ? AND upgraded_user_id = ?
  )
`);

const INSERT_AUTH_IDENTITY_FOR_UPGRADED_GUEST_SQL = normalizeSql(`
  INSERT INTO auth_identity
    (id, user_id, provider, provider_uid, created_at)
  SELECT ?, ?, ?, ?, ?
  WHERE EXISTS (
    SELECT 1
    FROM anonymous_account
    WHERE id = ? AND upgraded_user_id = ?
  )
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

const INSERT_OAUTH_USER_PORTFOLIO_FOLDER_SQL = normalizeSql(`
  INSERT INTO portfolio_folder
    (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
  VALUES (?, 'user', ?, 'Main', 1, 0, ?, ?)
`);

const INSERT_OAUTH_USER_PREFERENCE_SQL = normalizeSql(`
  INSERT INTO user_preference
    (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
  VALUES (?, 'user', ?, 'USD', 0, NULL, ?, ?)
`);

const INSERT_USER_SESSION_FOR_UPGRADED_GUEST_SQL = normalizeSql(`
  INSERT INTO session
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  SELECT ?, 'user', ?, ?, ?, ?, ?, NULL
  WHERE EXISTS (
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
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  SELECT ?, 'user', ?, 'email', ?, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`);

const INSERT_MIGRATED_USER_SESSION_SQL = normalizeSql(`
  INSERT INTO session
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  SELECT ?, 'user', ?, 'email', ?, ?, ?, NULL
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
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'user', ?, 'email', ?, ?, ?, NULL)
`);

const INSERT_OAUTH_USER_SESSION_SQL = normalizeSql(`
  INSERT INTO session
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'user', ?, ?, ?, ?, ?, NULL)
`);

const UPDATE_REGISTER_CODE_USED_SQL = normalizeSql(`
  UPDATE verification_code
  SET used_at = ?
  WHERE id = ? AND used_at IS NULL
`);

const UPDATE_RESET_CODE_USED_SQL = normalizeSql(`
  UPDATE verification_code
  SET used_at = ?
  WHERE id = ? AND used_at IS NULL
`);

const UPDATE_LIVE_EMAIL_PASSWORD_USER_SQL = normalizeSql(`
  UPDATE user
  SET password_hash = ?, updated_at = ?
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM verification_code
      WHERE id = ? AND used_at = ?
    )
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

const UPDATE_ANONYMOUS_PORTFOLIO_FOLDERS_UNGUARDED_SQL = normalizeSql(`
  UPDATE portfolio_folder
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_ANONYMOUS_COLLECTION_ITEMS_UNGUARDED_SQL = normalizeSql(`
  UPDATE collection_item
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_ANONYMOUS_WISHLIST_ITEMS_UNGUARDED_SQL = normalizeSql(`
  UPDATE wishlist_item
  SET owner_type = 'user', owner_id = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_ANONYMOUS_USER_PREFERENCE_UNGUARDED_SQL = normalizeSql(`
  UPDATE user_preference
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_UNGUARDED_SQL = normalizeSql(`
  UPDATE anonymous_account
  SET upgraded_user_id = ?
  WHERE id = ? AND upgraded_user_id IS NULL
`);

const REMAP_CONFLICTING_COLLECTION_ITEMS_TO_USER_FOLDER_SQL = normalizeSql(`
  UPDATE collection_item
  SET folder_id = (
    SELECT target.id
    FROM portfolio_folder source
    JOIN portfolio_folder target
      ON target.owner_type = 'user'
      AND target.owner_id = ?
      AND target.name = source.name
    WHERE source.id = collection_item.folder_id
      AND source.owner_type = 'anonymous'
      AND source.owner_id = ?
    LIMIT 1
  ), updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM portfolio_folder source
      JOIN portfolio_folder target
        ON target.owner_type = 'user'
        AND target.owner_id = ?
        AND target.name = source.name
      WHERE source.id = collection_item.folder_id
        AND source.owner_type = 'anonymous'
        AND source.owner_id = ?
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const DELETE_CONFLICTING_ANONYMOUS_PORTFOLIO_FOLDERS_SQL = normalizeSql(`
  DELETE FROM portfolio_folder
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM portfolio_folder target
      WHERE target.owner_type = 'user'
        AND target.owner_id = ?
        AND target.name = portfolio_folder.name
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const REMAP_ANONYMOUS_USER_PREFERENCE_FOLDER_SQL = normalizeSql(`
  UPDATE user_preference
  SET last_selected_folder_id = (
    SELECT target.id
    FROM portfolio_folder source
    JOIN portfolio_folder target
      ON target.owner_type = 'user'
      AND target.owner_id = ?
      AND target.name = source.name
    WHERE source.id = user_preference.last_selected_folder_id
      AND source.owner_type = 'anonymous'
      AND source.owner_id = ?
    LIMIT 1
  ), updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM portfolio_folder source
      JOIN portfolio_folder target
        ON target.owner_type = 'user'
        AND target.owner_id = ?
        AND target.name = source.name
      WHERE source.id = user_preference.last_selected_folder_id
        AND source.owner_type = 'anonymous'
        AND source.owner_id = ?
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_NON_CONFLICTING_ANONYMOUS_PORTFOLIO_FOLDERS_SQL = normalizeSql(`
  UPDATE portfolio_folder
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND NOT EXISTS (
      SELECT 1
      FROM portfolio_folder target
      WHERE target.owner_type = 'user'
        AND target.owner_id = ?
        AND target.name = portfolio_folder.name
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const DELETE_CONFLICTING_ANONYMOUS_WISHLIST_ITEMS_SQL = normalizeSql(`
  DELETE FROM wishlist_item
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM wishlist_item target
      WHERE target.owner_type = 'user'
        AND target.owner_id = ?
        AND target.card_ref = wishlist_item.card_ref
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_NON_CONFLICTING_ANONYMOUS_WISHLIST_ITEMS_SQL = normalizeSql(`
  UPDATE wishlist_item
  SET owner_type = 'user', owner_id = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND NOT EXISTS (
      SELECT 1
      FROM wishlist_item target
      WHERE target.owner_type = 'user'
        AND target.owner_id = ?
        AND target.card_ref = wishlist_item.card_ref
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const DELETE_CONFLICTING_ANONYMOUS_USER_PREFERENCE_SQL = normalizeSql(`
  DELETE FROM user_preference
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM user_preference target
      WHERE target.owner_type = 'user' AND target.owner_id = ?
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_NON_CONFLICTING_ANONYMOUS_USER_PREFERENCE_SQL = normalizeSql(`
  UPDATE user_preference
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND NOT EXISTS (
      SELECT 1
      FROM user_preference target
      WHERE target.owner_type = 'user' AND target.owner_id = ?
    )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`);

const UPDATE_USER_DELETED_SQL = normalizeSql(`
  UPDATE user
  SET deleted_at = ?, updated_at = ?
  WHERE id = ? AND deleted_at IS NULL
`);

const REVOKE_OWNER_SESSIONS_SQL = normalizeSql(`
  UPDATE session
  SET revoked_at = ?
  WHERE owner_type = ? AND owner_id = ? AND revoked_at IS NULL
`);

const DELETE_ANONYMOUS_PORTFOLIO_FOLDERS_SQL = normalizeSql(`
  DELETE FROM portfolio_folder
  WHERE owner_type = 'anonymous' AND owner_id = ?
`);

const DELETE_ANONYMOUS_COLLECTION_ITEMS_SQL = normalizeSql(`
  DELETE FROM collection_item
  WHERE owner_type = 'anonymous' AND owner_id = ?
`);

const DELETE_ANONYMOUS_WISHLIST_ITEMS_SQL = normalizeSql(`
  DELETE FROM wishlist_item
  WHERE owner_type = 'anonymous' AND owner_id = ?
`);

const DELETE_ANONYMOUS_USER_PREFERENCE_SQL = normalizeSql(`
  DELETE FROM user_preference
  WHERE owner_type = 'anonymous' AND owner_id = ?
`);

const INVALIDATE_ANONYMOUS_ACCOUNT_SQL = normalizeSql(`
  UPDATE anonymous_account
  SET upgraded_user_id = ?
  WHERE id = ? AND upgraded_user_id IS NULL
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
    GOOGLE_CLIENT_ID: "test-google-client-id",
    APPLE_CLIENT_ID: "test-apple-client-id",
  };
}

class FakeScanImages {
  readonly keys = new Set<string>();

  async delete(keys: string | string[]): Promise<void> {
    for (const key of Array.isArray(keys) ? keys : [keys]) this.keys.delete(key);
  }
}

function fakeD1(env: TestEnv): FakeD1 {
  return env.DB as unknown as FakeD1;
}

async function seedLiveUserSession(
  env: TestEnv,
  userId: string,
  sessionId: string,
): Promise<string> {
  const db = fakeD1(env);
  db.users.push({
    id: userId,
    email: `${userId}@example.com`,
    password_hash: null,
    display_name: null,
    created_at: "2026-07-06T00:00:00.000Z",
    updated_at: "2026-07-06T00:00:00.000Z",
    deleted_at: null,
  });
  db.sessions.push({
    id: sessionId,
    owner_type: "user",
    owner_id: userId,
    refresh_token: await hashRefreshToken(`${sessionId}-refresh`),
    expires_at: "2999-01-01T00:00:00.000Z",
    created_at: "2026-07-06T00:00:00.000Z",
    revoked_at: null,
  });

  return signAccessToken(
    { owner_type: "user", owner_id: userId, session_id: sessionId },
    env.JWT_SECRET,
  );
}

describe("migrateGuestAssetsToUser", () => {
  it("migrates only the requested live guest assets with an empty guard because standalone migration must not steal other anonymous work", async () => {
    const db = createFakeD1();
    seedGuestMigrationRows(db, "anonymous-source");
    seedGuestMigrationRows(db, "anonymous-other");
    db.scanRecords.push(
      { owner_type: "anonymous", owner_id: "anonymous-source", image_url: "source.jpg" },
      { owner_type: "anonymous", owner_id: "anonymous-other", image_url: "other.jpg" },
    );

    const counts = await migrateGuestAssetsToUser(
      db,
      "anonymous-source",
      "user-target",
      "2026-07-06T00:00:00.000Z",
      {},
    );

    expect(counts).toEqual({
      migrated_folders: 1,
      migrated_items: 1,
      migrated_wishlist: 1,
    });
    expect(db.anonymousAccounts).toEqual([
      expect.objectContaining({
        id: "anonymous-source",
        upgraded_user_id: "user-target",
      }),
      expect.objectContaining({
        id: "anonymous-other",
        upgraded_user_id: null,
      }),
    ]);
    expect(
      db.portfolioFolders.find((row) => row.id === "folder-anonymous-source"),
    ).toEqual(expect.objectContaining({ owner_type: "user", owner_id: "user-target" }));
    expect(
      db.collectionItems.find(
        (row) => row.id === "collection-anonymous-source",
      ),
    ).toEqual(expect.objectContaining({ owner_type: "user", owner_id: "user-target" }));
    expect(
      db.wishlistItems.find((row) => row.id === "wishlist-anonymous-source"),
    ).toEqual(expect.objectContaining({ owner_type: "user", owner_id: "user-target" }));
    expect(
      db.portfolioFolders.find((row) => row.id === "folder-anonymous-other"),
    ).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-other",
      }),
    );
    expect(
      db.collectionItems.find((row) => row.id === "collection-anonymous-other"),
    ).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-other",
      }),
    );
    expect(
      db.wishlistItems.find((row) => row.id === "wishlist-anonymous-other"),
    ).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-other",
      }),
    );
    expect(db.scanRecords).toEqual([
      expect.objectContaining({ owner_type: "user", owner_id: "user-target" }),
      expect.objectContaining({ owner_type: "anonymous", owner_id: "anonymous-other" }),
    ]);
  });

  it("fails migration for an already upgraded guest because claimed guest assets must not move to another user", async () => {
    const db = createFakeD1();
    seedGuestMigrationRows(db, "anonymous-source", "existing-user");

    await expect(
      migrateGuestAssetsToUser(
        db,
        "anonymous-source",
        "user-target",
        "2026-07-06T00:00:00.000Z",
        {},
      ),
    ).rejects.toThrow("Guest account is no longer available.");

    expect(db.anonymousAccounts[0]).toEqual(
      expect.objectContaining({
        id: "anonymous-source",
        upgraded_user_id: "existing-user",
      }),
    );
    expect(db.portfolioFolders[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-source",
      }),
    );
    expect(db.collectionItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-source",
      }),
    );
    expect(db.wishlistItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-source",
      }),
    );
  });

  it("rejects an incomplete guard because verification-gated migration must not silently downgrade to an unguarded path", async () => {
    const db = createFakeD1();
    seedGuestMigrationRows(db, "anonymous-source");

    await expect(
      migrateGuestAssetsToUser(
        db,
        "anonymous-source",
        "user-target",
        "2026-07-06T00:00:00.000Z",
        { verificationCodeId: "code-only" },
      ),
    ).rejects.toThrow("Incomplete guest migration guard.");

    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBeNull();
    expect(db.portfolioFolders[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-source",
      }),
    );
  });
});

function seedGuestMigrationRows(
  db: FakeD1,
  anonymousId: string,
  upgradedUserId: string | null = null,
): void {
  db.anonymousAccounts.push({
    id: anonymousId,
    device_id: `device-${anonymousId}`,
    created_at: "2026-07-06T00:00:00.000Z",
    upgraded_user_id: upgradedUserId,
  });
  db.portfolioFolders.push({
    id: `folder-${anonymousId}`,
    owner_type: "anonymous",
    owner_id: anonymousId,
    name: "Main",
    is_default: 1,
    sort_order: 0,
    created_at: "2026-07-06T00:00:00.000Z",
    updated_at: "2026-07-06T00:00:00.000Z",
  });
  db.userPreferences.push({
    id: `preference-${anonymousId}`,
    owner_type: "anonymous",
    owner_id: anonymousId,
    currency: "USD",
    amount_hidden: 0,
    last_selected_folder_id: null,
    created_at: "2026-07-06T00:00:00.000Z",
    updated_at: "2026-07-06T00:00:00.000Z",
  });
  db.collectionItems.push({
    id: `collection-${anonymousId}`,
    owner_type: "anonymous",
    owner_id: anonymousId,
    folder_id: `folder-${anonymousId}`,
    card_ref: `card-${anonymousId}`,
    updated_at: "2026-07-06T00:00:00.000Z",
  });
  db.wishlistItems.push({
    id: `wishlist-${anonymousId}`,
    owner_type: "anonymous",
    owner_id: anonymousId,
    card_ref: `card-${anonymousId}`,
  });
}

describe("POST /api/v1/auth/oauth/google/callback", () => {
  it("google oauth creates an OAuth-only user because a new provider identity starts durable auth", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    const response = await requestGoogleOAuthCallback(env, {
      id_token: "mock-google:google-1:google.new@example.com",
    });
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        user_id: expect.any(String),
        email: "google.new@example.com",
        login_method: "google",
        access_token: expect.any(String),
        refresh_token: expect.any(String),
        expires_in: 900,
        is_new_user: true,
        migrated: false,
      },
    });
    expect(db.users).toEqual([
      expect.objectContaining({
        id: body.data.user_id,
        email: "google.new@example.com",
        password_hash: null,
        deleted_at: null,
      }),
    ]);
    expect(db.authIdentities).toEqual([
      expect.objectContaining({
        user_id: body.data.user_id,
        provider: "google",
        provider_uid: "google-1",
      }),
    ]);
    expect(db.sessions).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: body.data.user_id,
      }),
    ]);
  });

  it("google oauth signs in an existing identity because provider_uid is the stable login key", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-google-existing-identity",
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
      id: "collection-google-existing-identity",
      owner_type: "anonymous",
      owner_id: anonymousId,
      folder_id: anonymousFolder.id,
      card_ref: "card-google-existing-identity",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "wishlist-google-existing-identity",
      owner_type: "anonymous",
      owner_id: anonymousId,
      card_ref: "card-google-existing-identity",
    });
    db.users.push({
      id: "user-google-existing",
      email: "original@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: null,
    });
    db.authIdentities.push({
      id: "identity-google-existing",
      user_id: "user-google-existing",
      provider: "google",
      provider_uid: "google-existing",
      created_at: "2026-07-06T00:00:00.000Z",
    });

    const response = await requestGoogleOAuthCallbackWithAuthorization(
      env,
      {
        id_token: "mock-google:google-existing:new-email@example.com",
        anonymous_id: anonymousId,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data).toEqual(
      expect.objectContaining({
        user_id: "user-google-existing",
        email: "new-email@example.com",
        is_new_user: false,
        migrated: false,
      }),
    );
    expect(db.users).toHaveLength(1);
    expect(db.authIdentities).toHaveLength(1);
    expect(db.anonymousAccounts).toEqual([
      expect.objectContaining({ id: anonymousId, upgraded_user_id: null }),
    ]);
    expect(db.portfolioFolders[0]).toEqual(
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    );
    expect(db.collectionItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
    expect(db.wishlistItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
  });

  it("google oauth binds an existing live email because user.email is unique across auth methods", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-google-existing-email",
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
      id: "collection-google-existing-email",
      owner_type: "anonymous",
      owner_id: anonymousId,
      folder_id: anonymousFolder.id,
      card_ref: "card-google-existing-email",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "wishlist-google-existing-email",
      owner_type: "anonymous",
      owner_id: anonymousId,
      card_ref: "card-google-existing-email",
    });
    db.users.push({
      id: "user-email-existing",
      email: "shared@example.com",
      password_hash: await hashPassword("existing-password"),
      display_name: null,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestGoogleOAuthCallbackWithAuthorization(
      env,
      {
        id_token: "mock-google:google-shared:shared@example.com",
        anonymous_id: anonymousId,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data).toEqual(
      expect.objectContaining({
        user_id: "user-email-existing",
        email: "shared@example.com",
        is_new_user: false,
        migrated: false,
      }),
    );
    expect(db.users).toHaveLength(1);
    expect(db.authIdentities).toEqual([
      expect.objectContaining({
        user_id: "user-email-existing",
        provider: "google",
        provider_uid: "google-shared",
      }),
    ]);
    expect(db.anonymousAccounts).toEqual([
      expect.objectContaining({ id: anonymousId, upgraded_user_id: null }),
    ]);
    expect(db.portfolioFolders[0]).toEqual(
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    );
    expect(db.collectionItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
    expect(db.wishlistItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
  });

  it("google oauth signs in after a concurrent user email insert because duplicate callbacks must not become 500s", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.createConflictingUserBeforeNextUserInsert = true;

    const response = await requestGoogleOAuthCallback(env, {
      id_token: "mock-google:google-email-race:race@example.com",
    });
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data).toEqual(
      expect.objectContaining({
        user_id: "concurrent-user",
        email: "race@example.com",
        is_new_user: false,
        migrated: false,
      }),
    );
    expect(db.users).toEqual([
      expect.objectContaining({
        id: "concurrent-user",
        email: "race@example.com",
      }),
    ]);
    expect(db.authIdentities).toEqual([
      expect.objectContaining({
        user_id: "concurrent-user",
        provider: "google",
        provider_uid: "google-email-race",
      }),
    ]);
    expect(db.sessions).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: "concurrent-user",
      }),
    ]);
  });

  it("google oauth signs in after a concurrent identity bind because retried callbacks should use the stable provider key", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.users.push({
      id: "identity-race-user",
      email: "identity-race@example.com",
      password_hash: await hashPassword("existing-password"),
      display_name: null,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: null,
    });
    db.createConflictingIdentityBeforeNextAuthIdentityInsert = true;

    const response = await requestGoogleOAuthCallback(env, {
      id_token: "mock-google:google-identity-race:identity-race@example.com",
    });
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data).toEqual(
      expect.objectContaining({
        user_id: "identity-race-user",
        email: "identity-race@example.com",
        is_new_user: false,
        migrated: false,
      }),
    );
    expect(db.users).toHaveLength(1);
    expect(db.authIdentities).toEqual([
      expect.objectContaining({
        id: "concurrent-auth-identity",
        user_id: "identity-race-user",
        provider: "google",
        provider_uid: "google-identity-race",
      }),
    ]);
    expect(db.sessions).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: "identity-race-user",
      }),
    ]);
  });

  it("google oauth migrates a live guest only for a new user because registration transfers guest assets", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(env, "device-google-migrate");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    db.collectionItems.push({
      id: `collection-${anonymousBody.data.anonymous_id}`,
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      folder_id: `folder-${anonymousBody.data.anonymous_id}`,
      card_ref: `card-${anonymousBody.data.anonymous_id}`,
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: `wishlist-${anonymousBody.data.anonymous_id}`,
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: `card-${anonymousBody.data.anonymous_id}`,
    });

    const response = await requestGoogleOAuthCallbackWithAuthorization(
      env,
      {
        id_token: "mock-google:google-migrate:google.migrate@example.com",
        anonymous_id: anonymousBody.data.anonymous_id,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data).toEqual(
      expect.objectContaining({
        email: "google.migrate@example.com",
        is_new_user: true,
        migrated: true,
      }),
    );
    expect(
      db.anonymousAccounts.find(
        (row) => row.id === anonymousBody.data.anonymous_id,
      ),
    ).toEqual(expect.objectContaining({ upgraded_user_id: body.data.user_id }));
    expect(
      db.portfolioFolders.find(
        (row) => row.owner_id === body.data.user_id && row.owner_type === "user",
      ),
    ).toEqual(expect.objectContaining({ is_default: 1 }));
    expect(
      db.collectionItems.find(
        (row) => row.id === `collection-${anonymousBody.data.anonymous_id}`,
      ),
    ).toEqual(
      expect.objectContaining({ owner_type: "user", owner_id: body.data.user_id }),
    );
    expect(
      db.wishlistItems.find(
        (row) => row.id === `wishlist-${anonymousBody.data.anonymous_id}`,
      ),
    ).toEqual(
      expect.objectContaining({ owner_type: "user", owner_id: body.data.user_id }),
    );
  });

  it("google oauth does not half-create a migrated user when the guest is concurrently upgraded because guarded writes must depend on claimed ownership", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-google-upgrade-race",
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
      id: "collection-google-upgrade-race",
      owner_type: "anonymous",
      owner_id: anonymousId,
      folder_id: anonymousFolder.id,
      card_ref: "card-google-upgrade-race",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "wishlist-google-upgrade-race",
      owner_type: "anonymous",
      owner_id: anonymousId,
      card_ref: "card-google-upgrade-race",
    });
    db.upgradeAnonymousBeforeUpgrade = true;

    const response = await requestGoogleOAuthCallbackWithAuthorization(
      env,
      {
        id_token: "mock-google:google-race:google.race@example.com",
        anonymous_id: anonymousId,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = await response.json();

    expect(response.status).not.toBe(200);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Guest account is no longer available.",
      },
    });
    expect(db.users).toHaveLength(0);
    expect(db.authIdentities).toHaveLength(0);
    expect(
      db.sessions.filter((row) => row.owner_type === "user"),
    ).toHaveLength(0);
    expect(db.anonymousAccounts).toEqual([
      expect.objectContaining({ id: anonymousId, upgraded_user_id: "existing-user" }),
    ]);
    expect(db.portfolioFolders).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
    expect(db.collectionItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
    expect(db.wishlistItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
  });

  it("google oauth rejects a stale identity because a soft-deleted linked user must not create replacement accounts", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.users.push({
      id: "user-google-deleted",
      email: "deleted-identity@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: "2026-07-06T01:00:00.000Z",
    });
    db.authIdentities.push({
      id: "identity-google-deleted",
      user_id: "user-google-deleted",
      provider: "google",
      provider_uid: "google-deleted",
      created_at: "2026-07-06T00:00:00.000Z",
    });

    const response = await requestGoogleOAuthCallback(env, {
      id_token: "mock-google:google-deleted:fresh@example.com",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Authorization failed. Please try again.",
      },
    });
    expect(db.users).toHaveLength(1);
    expect(db.authIdentities).toHaveLength(1);
    expect(db.sessions).toHaveLength(0);
  });

  it("google oauth rejects a soft-deleted provider email because user.email uniqueness must not become a server error", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.users.push({
      id: "user-google-email-deleted",
      email: "deleted-email@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: "2026-07-06T01:00:00.000Z",
    });

    const response = await requestGoogleOAuthCallback(env, {
      id_token: "mock-google:google-deleted-email:deleted-email@example.com",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Authorization failed. Please try again.",
      },
    });
    expect(db.users).toHaveLength(1);
    expect(db.authIdentities).toHaveLength(0);
    expect(db.sessions).toHaveLength(0);
  });

  it("google oauth rejects malformed mock authorization because failed provider proof must not create accounts", async () => {
    const env = createTestEnv();

    const response = await requestGoogleOAuthCallback(env, {
      id_token: "bad-code",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Authorization failed. Please try again.",
      },
    });
    expect(fakeD1(env).users).toHaveLength(0);
    expect(fakeD1(env).authIdentities).toHaveLength(0);
  });

  it("google oauth rejects malformed provider UID because durable login keys must be constrained", async () => {
    const env = createTestEnv();

    const response = await requestGoogleOAuthCallback(env, {
      id_token: "mock-google:bad uid:baduid@example.com",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Authorization failed. Please try again.",
      },
    });
    expect(fakeD1(env).users).toHaveLength(0);
    expect(fakeD1(env).authIdentities).toHaveLength(0);
  });
});

describe("POST /api/v1/auth/oauth/apple/callback", () => {
  it("apple oauth creates an OAuth-only user because id_token proves a new provider identity", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    const response = await requestAppleOAuthCallback(env, {
      code: "apple-auth-code",
      id_token: "mock-apple:apple-1:apple.new@example.com",
    });
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        user_id: expect.any(String),
        email: "apple.new@example.com",
        login_method: "apple",
        access_token: expect.any(String),
        refresh_token: expect.any(String),
        expires_in: 900,
        is_new_user: true,
        migrated: false,
      },
    });
    expect(db.users).toEqual([
      expect.objectContaining({
        id: body.data.user_id,
        email: "apple.new@example.com",
        password_hash: null,
        deleted_at: null,
      }),
    ]);
    expect(db.authIdentities).toEqual([
      expect.objectContaining({
        user_id: body.data.user_id,
        provider: "apple",
        provider_uid: "apple-1",
      }),
    ]);
    expect(db.sessions).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: body.data.user_id,
      }),
    ]);
  });

  it("apple oauth signs in an existing identity because provider_uid is stable across sessions", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-apple-existing-identity",
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
      id: "collection-apple-existing-identity",
      owner_type: "anonymous",
      owner_id: anonymousId,
      folder_id: anonymousFolder.id,
      card_ref: "card-apple-existing-identity",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "wishlist-apple-existing-identity",
      owner_type: "anonymous",
      owner_id: anonymousId,
      card_ref: "card-apple-existing-identity",
    });
    db.users.push({
      id: "user-apple-existing",
      email: "original.apple@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: null,
    });
    db.authIdentities.push({
      id: "identity-apple-existing",
      user_id: "user-apple-existing",
      provider: "apple",
      provider_uid: "apple-existing",
      created_at: "2026-07-06T00:00:00.000Z",
    });

    const response = await requestAppleOAuthCallbackWithAuthorization(
      env,
      {
        code: "apple-auth-code",
        id_token: "mock-apple:apple-existing:new.apple@example.com",
        anonymous_id: anonymousId,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data).toEqual(
      expect.objectContaining({
        user_id: "user-apple-existing",
        email: "new.apple@example.com",
        is_new_user: false,
        migrated: false,
      }),
    );
    expect(db.users).toHaveLength(1);
    expect(db.authIdentities).toHaveLength(1);
    expect(db.anonymousAccounts).toEqual([
      expect.objectContaining({ id: anonymousId, upgraded_user_id: null }),
    ]);
    expect(db.collectionItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
    expect(db.wishlistItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
  });

  it("apple oauth binds an existing live email because one email maps to one user", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(
      env,
      "device-apple-existing-email",
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
      id: "collection-apple-existing-email",
      owner_type: "anonymous",
      owner_id: anonymousId,
      folder_id: anonymousFolder.id,
      card_ref: "card-apple-existing-email",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "wishlist-apple-existing-email",
      owner_type: "anonymous",
      owner_id: anonymousId,
      card_ref: "card-apple-existing-email",
    });
    db.users.push({
      id: "user-apple-email-existing",
      email: "apple.shared@example.com",
      password_hash: await hashPassword("existing-password"),
      display_name: null,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestAppleOAuthCallbackWithAuthorization(
      env,
      {
        code: "apple-auth-code",
        id_token: "mock-apple:apple-shared:apple.shared@example.com",
        anonymous_id: anonymousId,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data).toEqual(
      expect.objectContaining({
        user_id: "user-apple-email-existing",
        email: "apple.shared@example.com",
        is_new_user: false,
        migrated: false,
      }),
    );
    expect(db.users).toHaveLength(1);
    expect(db.authIdentities).toEqual([
      expect.objectContaining({
        user_id: "user-apple-email-existing",
        provider: "apple",
        provider_uid: "apple-shared",
      }),
    ]);
    expect(db.anonymousAccounts).toEqual([
      expect.objectContaining({ id: anonymousId, upgraded_user_id: null }),
    ]);
    expect(db.collectionItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
    expect(db.wishlistItems).toEqual([
      expect.objectContaining({ owner_type: "anonymous", owner_id: anonymousId }),
    ]);
  });

  it("apple oauth migrates a live guest only for a new user because existing-user login must not merge assets", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const anonymousResponse = await requestAnonymous(env, "device-apple-migrate");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    db.collectionItems.push({
      id: `collection-${anonymousBody.data.anonymous_id}`,
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      folder_id: `folder-${anonymousBody.data.anonymous_id}`,
      card_ref: `card-${anonymousBody.data.anonymous_id}`,
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: `wishlist-${anonymousBody.data.anonymous_id}`,
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: `card-${anonymousBody.data.anonymous_id}`,
    });

    const response = await requestAppleOAuthCallbackWithAuthorization(
      env,
      {
        code: "apple-auth-code",
        id_token: "mock-apple:apple-migrate:apple.migrate@example.com",
        anonymous_id: anonymousBody.data.anonymous_id,
      },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = (await response.json()) as OAuthSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data).toEqual(
      expect.objectContaining({
        email: "apple.migrate@example.com",
        is_new_user: true,
        migrated: true,
      }),
    );
    expect(
      db.anonymousAccounts.find(
        (row) => row.id === anonymousBody.data.anonymous_id,
      ),
    ).toEqual(expect.objectContaining({ upgraded_user_id: body.data.user_id }));
    expect(
      db.collectionItems.find(
        (row) => row.id === `collection-${anonymousBody.data.anonymous_id}`,
      ),
    ).toEqual(
      expect.objectContaining({ owner_type: "user", owner_id: body.data.user_id }),
    );
    expect(
      db.wishlistItems.find(
        (row) => row.id === `wishlist-${anonymousBody.data.anonymous_id}`,
      ),
    ).toEqual(
      expect.objectContaining({ owner_type: "user", owner_id: body.data.user_id }),
    );
  });

  it("apple oauth rejects missing id_token because provider identity cannot be proven", async () => {
    const env = createTestEnv();

    const response = await requestAppleOAuthCallback(env, {
      code: "apple-auth-code",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Authorization failed. Please try again.",
      },
    });
    expect(fakeD1(env).users).toHaveLength(0);
    expect(fakeD1(env).authIdentities).toHaveLength(0);
  });

  it("apple oauth rejects malformed mock authorization because failed provider proof must not create accounts", async () => {
    const env = createTestEnv();

    const response = await requestAppleOAuthCallback(env, {
      code: "apple-auth-code",
      id_token: "bad-token",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Authorization failed. Please try again.",
      },
    });
    expect(fakeD1(env).users).toHaveLength(0);
    expect(fakeD1(env).authIdentities).toHaveLength(0);
  });

  it("apple oauth rejects malformed provider UID because durable login keys must be constrained", async () => {
    const env = createTestEnv();

    const response = await requestAppleOAuthCallback(env, {
      code: "apple-auth-code",
      id_token: "mock-apple:bad uid:user@example.com",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Authorization failed. Please try again.",
      },
    });
    expect(fakeD1(env).users).toHaveLength(0);
    expect(fakeD1(env).authIdentities).toHaveLength(0);
  });

  it("apple oauth rejects malformed email because provider identity email must be usable for account lookup", async () => {
    const env = createTestEnv();

    const response = await requestAppleOAuthCallback(env, {
      code: "apple-auth-code",
      id_token: "mock-apple:valid-uid:not-an-email",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Authorization failed. Please try again.",
      },
    });
    expect(fakeD1(env).users).toHaveLength(0);
    expect(fakeD1(env).authIdentities).toHaveLength(0);
  });
});

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

async function requestGoogleOAuthCallback(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/oauth/google/callback",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestGoogleOAuthCallbackWithAuthorization(
  env: TestEnv,
  body: unknown,
  authorization: string,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/oauth/google/callback",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: authorization,
      },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestAppleOAuthCallback(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/oauth/apple/callback",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestAppleOAuthCallbackWithAuthorization(
  env: TestEnv,
  body: unknown,
  authorization: string,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/oauth/apple/callback",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: authorization,
      },
      body: JSON.stringify(body),
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

async function requestForgotPasswordSendCode(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/forgot-password/send-code",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestForgotPasswordVerifyCode(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/forgot-password/verify-code",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestForgotPasswordReset(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/forgot-password/reset",
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

async function requestDeleteAccount(
  env: TestEnv,
  authorization?: string,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/account",
    {
      method: "DELETE",
      headers: authorization ? { Authorization: authorization } : {},
    },
    env,
  );
}

async function requestMigrateAssets(
  env: TestEnv,
  body: unknown,
  authorization?: string,
  anonymousAuthorization?: string,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/migrate-assets",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(authorization ? { Authorization: authorization } : {}),
        ...(anonymousAuthorization
          ? { "X-Anonymous-Authorization": anonymousAuthorization }
          : {}),
      },
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

function expectIncorrectPassword(body: unknown, status: number): void {
  expect(status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message: "Incorrect password. Please try again.",
    },
  });
}

function expectEmailNotRegistered(body: unknown, status: number): void {
  expect(status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message:
        "Email not registered. Please check your email or create a new account.",
    },
  });
}

function expectExpiredResetCode(body: unknown, status: number): void {
  expect(status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message: "Code expired. Please request a new code.",
    },
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
        login_method: "email",
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
        login_method: "email",
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
        message: "Code expired. Please request a new code.",
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
        login_method: "email",
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

      expectIncorrectPassword(body, response.status);
      expect(deriveBits).toHaveBeenCalledTimes(1);
    } finally {
      deriveBits.mockRestore();
    }
  });

  it("returns a uniform password error for an unknown email because login must not reveal account existence", async () => {
    const env = createTestEnv();

    const response = await requestLogin(env, {
      email: "missing@example.com",
      password: "correct-password",
    });
    const body = await response.json();

    expectIncorrectPassword(body, response.status);
    expect(fakeD1(env).sessions).toHaveLength(0);
  });

  it("returns a uniform password error for the wrong password because failed authentication must not create sessions", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "wrong-password-user",
      email: "wrong-password@example.com",
      password_hash: await hashPassword("correct-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestLogin(env, {
      email: "wrong-password@example.com",
      password: "incorrect-password",
    });
    const body = await response.json();

    expectIncorrectPassword(body, response.status);
    expect(db.sessions).toHaveLength(0);
  });

  it("returns a uniform password error for a soft-deleted user because removed accounts must not be revived", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "deleted-login-user",
      email: "deleted-login@example.com",
      password_hash: await hashPassword("correct-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: "2026-07-03T01:00:00.000Z",
    });

    const response = await requestLogin(env, {
      email: "deleted-login@example.com",
      password: "correct-password",
    });
    const body = await response.json();

    expectIncorrectPassword(body, response.status);
    expect(db.sessions).toHaveLength(0);
  });

  it("returns a uniform password error for an OAuth-only user because password login requires a stored password hash", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "oauth-only-login-user",
      email: "oauth-only@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestLogin(env, {
      email: "oauth-only@example.com",
      password: "correct-password",
    });
    const body = await response.json();

    expectIncorrectPassword(body, response.status);
    expect(db.sessions).toHaveLength(0);
  });

  it("returns a uniform password error for a blank password because login needs a credential secret", async () => {
    const env = createTestEnv();

    const response = await requestLogin(env, {
      email: "blank-password@example.com",
      password: "",
    });
    const body = await response.json();

    expectIncorrectPassword(body, response.status);
    expect(fakeD1(env).sessions).toHaveLength(0);
  });

  it("returns 422 / VALIDATION_ERROR for blank email because login cannot identify the account lookup key", async () => {
    const env = createTestEnv();

    const response = await requestLogin(env, {
      email: "   ",
      password: "correct-password",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Please enter your email.",
      },
    });
    expect(fakeD1(env).sessions).toHaveLength(0);
  });

  it("returns 422 / VALIDATION_ERROR for invalid email because malformed account keys must not query users", async () => {
    const env = createTestEnv();

    const response = await requestLogin(env, {
      email: "invalid-email",
      password: "correct-password",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Please enter a valid email address.",
      },
    });
    expect(fakeD1(env).sessions).toHaveLength(0);
  });

  it("returns 422 / VALIDATION_ERROR for overlong email because login must enforce the shared email length rule", async () => {
    const env = createTestEnv();
    const overlongEmail = `${"a".repeat(245)}@example.com`;

    const response = await requestLogin(env, {
      email: overlongEmail,
      password: "correct-password",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toEqual({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Please enter a valid email address.",
      },
    });
    expect(fakeD1(env).sessions).toHaveLength(0);
  });

  it("returns 500 / INTERNAL_ERROR when JWT_SECRET is blank because login sessions need signed access tokens", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "secret-login-user",
      email: "secret-login@example.com",
      password_hash: await hashPassword("correct-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });
    env.JWT_SECRET = "   ";

    const response = await requestLogin(env, {
      email: "secret-login@example.com",
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
    expect(db.sessions).toHaveLength(0);
  });

  it("returns 500 / INTERNAL_ERROR when user lookup fails because login must fail loudly before issuing credentials", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.failNextFirst = true;

    const response = await requestLogin(env, {
      email: "lookup-failure@example.com",
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
    expect(db.sessions).toHaveLength(0);
  });

  it("returns 500 / INTERNAL_ERROR when session persistence fails because login must not return unstored refresh credentials", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "run-failure-login-user",
      email: "run-failure-login@example.com",
      password_hash: await hashPassword("correct-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });
    db.failNextRun = true;

    const response = await requestLogin(env, {
      email: "run-failure-login@example.com",
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
    expect(db.sessions).toHaveLength(0);
  });
});

describe("POST /api/v1/auth/forgot-password", () => {
  it("forgot-password sends a reset code for a live Email-password user because password recovery starts with account ownership proof", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "forgot-send-user",
      email: "forgot.send@example.com",
      password_hash: await hashPassword("old-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestForgotPasswordSendCode(env, {
      email: "  Forgot.Send@Example.COM  ",
    });
    const body = await response.json();
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
        email: "forgot.send@example.com",
        purpose: "reset_password",
        used_at: null,
      }),
    );
    expect(code?.code).toMatch(/^\d{6}$/);
  });

  it("forgot-password rate limits concurrent send-code writes because resend throttle must be enforced at the persistence boundary", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "forgot-send-race-user",
      email: "forgot.send.race@example.com",
      password_hash: await hashPassword("old-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });
    db.concurrentResetCodeLookupBarrierSize = 2;

    const responses = await Promise.all([
      requestForgotPasswordSendCode(env, {
        email: "forgot.send.race@example.com",
      }),
      requestForgotPasswordSendCode(env, {
        email: "forgot.send.race@example.com",
      }),
    ]);
    const bodies = await Promise.all(
      responses.map((response) => response.json()),
    );

    expect(responses.map((response) => response.status).sort()).toEqual([
      200,
      429,
    ]);
    expect(bodies).toContainEqual({
      success: false,
      error: {
        code: "RATE_LIMITED",
        message: "Please try again later.",
      },
    });
    expect(db.verificationCodes).toHaveLength(1);
  });

  it("forgot-password rejects an unknown email because password reset should only start for registered Email accounts", async () => {
    const env = createTestEnv();

    const response = await requestForgotPasswordSendCode(env, {
      email: "missing-reset@example.com",
    });
    const body = await response.json();

    expectEmailNotRegistered(body, response.status);
    expect(fakeD1(env).verificationCodes).toHaveLength(0);
  });

  it("forgot-password rejects an OAuth-only user because accounts without password_hash cannot reset a password", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "oauth-reset-user",
      email: "oauth-reset@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestForgotPasswordSendCode(env, {
      email: "oauth-reset@example.com",
    });
    const body = await response.json();

    expectEmailNotRegistered(body, response.status);
    expect(db.verificationCodes).toHaveLength(0);
  });

  it("forgot-password returns a reset token for a matching reset code because the new password step needs a short-lived proof", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "forgot-verify-user",
      email: "forgot.verify@example.com",
      password_hash: await hashPassword("old-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const sendResponse = await requestForgotPasswordSendCode(env, {
      email: "forgot.verify@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected reset verification code.");
    }

    const response = await requestForgotPasswordVerifyCode(env, {
      email: "forgot.verify@example.com",
      code: code.code,
    });
    const body =
      (await response.json()) as ForgotPasswordVerifyCodeSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: { reset_token: expect.any(String) },
    });
    expect(code.used_at).toBeNull();
  });

  it("forgot-password rejects a wrong reset code because only the latest emailed proof can mint a reset token", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "wrong-code-reset-user",
      email: "wrong-code-reset@example.com",
      password_hash: await hashPassword("old-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const sendResponse = await requestForgotPasswordSendCode(env, {
      email: "wrong-code-reset@example.com",
    });
    expect(sendResponse.status).toBe(200);

    const response = await requestForgotPasswordVerifyCode(env, {
      email: "wrong-code-reset@example.com",
      code: "000000",
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
  });

  it("forgot-password rejects an expired reset code because stale email proofs must not reset passwords", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "expired-code-reset-user",
      email: "expired-code-reset@example.com",
      password_hash: await hashPassword("old-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const sendResponse = await requestForgotPasswordSendCode(env, {
      email: "expired-code-reset@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected reset verification code.");
    }

    code.expires_at = "2000-01-01T00:00:00.000Z";

    const response = await requestForgotPasswordVerifyCode(env, {
      email: "expired-code-reset@example.com",
      code: code.code,
    });
    const body = await response.json();

    expectExpiredResetCode(body, response.status);
  });

  it("forgot-password resets the password and consumes the code because reset tokens must be single use", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const oldPassword = "old-password";

    db.users.push({
      id: "forgot-reset-user",
      email: "forgot.reset@example.com",
      password_hash: await hashPassword(oldPassword),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const sendResponse = await requestForgotPasswordSendCode(env, {
      email: "forgot.reset@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected reset verification code.");
    }

    const verifyResponse = await requestForgotPasswordVerifyCode(env, {
      email: "forgot.reset@example.com",
      code: code.code,
    });
    const verifyBody =
      (await verifyResponse.json()) as ForgotPasswordVerifyCodeSuccessResponse;
    expect(verifyResponse.status).toBe(200);
    expect(code.used_at).toBeNull();

    const response = await requestForgotPasswordReset(env, {
      email: "forgot.reset@example.com",
      new_password: "new-password",
      reset_token: verifyBody.data.reset_token,
    });
    const body = await response.json();
    const user = db.users[0];

    if (!user?.password_hash) {
      throw new Error("Expected updated user password hash.");
    }

    expect(response.status).toBe(200);
    expect(body).toEqual({ success: true, data: {} });
    expect(code.used_at).toEqual(expect.any(String));
    expect(await verifyPassword("new-password", user.password_hash)).toBe(true);
    expect(await verifyPassword(oldPassword, user.password_hash)).toBe(false);
  });

  it("forgot-password rejects replaying a reset token because each reset proof must be consumed once", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "replay-reset-user",
      email: "replay-reset@example.com",
      password_hash: await hashPassword("old-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const sendResponse = await requestForgotPasswordSendCode(env, {
      email: "replay-reset@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected reset verification code.");
    }

    const verifyResponse = await requestForgotPasswordVerifyCode(env, {
      email: "replay-reset@example.com",
      code: code.code,
    });
    const verifyBody =
      (await verifyResponse.json()) as ForgotPasswordVerifyCodeSuccessResponse;

    const firstReset = await requestForgotPasswordReset(env, {
      email: "replay-reset@example.com",
      new_password: "new-password",
      reset_token: verifyBody.data.reset_token,
    });
    expect(firstReset.status).toBe(200);

    const response = await requestForgotPasswordReset(env, {
      email: "replay-reset@example.com",
      new_password: "another-password",
      reset_token: verifyBody.data.reset_token,
    });
    const body = await response.json();

    expectExpiredResetCode(body, response.status);
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
        login_method: null,
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

describe("DELETE /api/v1/auth/account", () => {
  it("delete account soft-deletes a user because removed credentials must not authenticate again", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const password = "old-password";
    const sessionId = "delete-user-session";
    db.users.push({
      id: "delete-user",
      email: "delete-user@example.com",
      password_hash: await hashPassword(password),
      display_name: "Delete User",
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: null,
    });
    db.sessions.push({
      id: sessionId,
      owner_type: "user",
      owner_id: "delete-user",
      refresh_token: await hashRefreshToken("delete-refresh"),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-06T00:00:00.000Z",
      revoked_at: null,
    });
    const accessToken = await signAccessToken(
      { owner_type: "user", owner_id: "delete-user", session_id: sessionId },
      env.JWT_SECRET,
    );

    const response = await requestDeleteAccount(env, `Bearer ${accessToken}`);
    const body = await response.json();
    const loginResponse = await requestLogin(env, {
      email: "delete-user@example.com",
      password,
    });
    const loginBody = await loginResponse.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({ success: true, data: {} });
    expect(db.users[0]?.deleted_at).toEqual(expect.any(String));
    expect(db.users[0]?.updated_at).toBe(db.users[0]?.deleted_at);
    expectIncorrectPassword(loginBody, loginResponse.status);
  });

  it("delete account revokes all user sessions because deleted users must not refresh tokens", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.users.push({
      id: "delete-user-sessions",
      email: "delete-sessions@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: null,
    });
    for (const id of ["delete-user-session-a", "delete-user-session-b"]) {
      db.sessions.push({
        id,
        owner_type: "user",
        owner_id: "delete-user-sessions",
        refresh_token: await hashRefreshToken(id),
        expires_at: "2999-01-01T00:00:00.000Z",
        created_at: "2026-07-06T00:00:00.000Z",
        revoked_at: null,
      });
    }
    const accessToken = await signAccessToken(
      {
        owner_type: "user",
        owner_id: "delete-user-sessions",
        session_id: "delete-user-session-a",
      },
      env.JWT_SECRET,
    );

    const response = await requestDeleteAccount(env, `Bearer ${accessToken}`);

    expect(response.status).toBe(200);
    expect(db.sessions.map((session) => session.revoked_at)).toEqual([
      expect.any(String),
      expect.any(String),
    ]);
  });

  it("delete account retains private scan images and records because product policy requires permanent scan audit media", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const accessToken = await seedLiveUserSession(
      env,
      "delete-scan-user",
      "delete-scan-session",
    );
    const images = new FakeScanImages();
    const key = "scans/user/delete-scan-user/2026/07/scan-1.jpg";
    images.keys.add(key);
    env.SCAN_IMAGES = images as unknown as R2Bucket;
    db.scanRecords.push({
      owner_type: "user",
      owner_id: "delete-scan-user",
      image_url: key,
    });

    const response = await requestDeleteAccount(env, `Bearer ${accessToken}`);

    expect(response.status).toBe(200);
    expect(images.keys).toEqual(new Set([key]));
    expect(db.scanRecords).toEqual([
      {
        owner_type: "user",
        owner_id: "delete-scan-user",
        image_url: key,
      },
    ]);
  });

  it("delete account deletes anonymous guest assets because guest deletion must be irreversible", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-delete-assets");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const db = fakeD1(env);
    db.collectionItems.push({
      id: "delete-guest-collection",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      folder_id: db.portfolioFolders[0]?.id ?? "missing-folder",
      card_ref: "delete-card",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "delete-guest-wishlist",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: "delete-card",
    });

    const response = await requestDeleteAccount(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
    );

    expect(response.status).toBe(200);
    expect(
      db.portfolioFolders.some(
        (row) =>
          row.owner_type === "anonymous" &&
          row.owner_id === anonymousBody.data.anonymous_id,
      ),
    ).toBe(false);
    expect(
      db.collectionItems.some(
        (row) =>
          row.owner_type === "anonymous" &&
          row.owner_id === anonymousBody.data.anonymous_id,
      ),
    ).toBe(false);
    expect(
      db.wishlistItems.some(
        (row) =>
          row.owner_type === "anonymous" &&
          row.owner_id === anonymousBody.data.anonymous_id,
      ),
    ).toBe(false);
    expect(
      db.userPreferences.some(
        (row) =>
          row.owner_type === "anonymous" &&
          row.owner_id === anonymousBody.data.anonymous_id,
      ),
    ).toBe(false);
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toEqual(expect.any(String));
  });

  it("delete account revokes anonymous sessions because old guest identity must not be reused", async () => {
    const env = createTestEnv();
    const firstResponse = await requestAnonymous(env, "device-delete-session-a");
    const firstBody = (await firstResponse.json()) as AnonymousSuccessResponse;
    const db = fakeD1(env);
    db.sessions.push({
      id: "delete-anonymous-session-b",
      owner_type: "anonymous",
      owner_id: firstBody.data.anonymous_id,
      refresh_token: await hashRefreshToken("delete-anonymous-refresh-b"),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-06T00:00:00.000Z",
      revoked_at: null,
    });

    const response = await requestDeleteAccount(
      env,
      `Bearer ${firstBody.data.access_token}`,
    );

    expect(response.status).toBe(200);
    expect(
      db.sessions
        .filter((session) => session.owner_id === firstBody.data.anonymous_id)
        .map((session) => session.revoked_at),
    ).toEqual([expect.any(String), expect.any(String)]);
  });

  it("delete account returns 401 without bearer token because destructive actions require owner proof", async () => {
    const env = createTestEnv();

    const response = await requestDeleteAccount(env);
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("delete account returns 401 for a revoked session because destructive actions require a live session", async () => {
    const env = createTestEnv();
    const accessToken = await seedLiveUserSession(
      env,
      "delete-revoked-user",
      "delete-revoked-session",
    );
    const db = fakeD1(env);
    const user = db.users[0];
    const session = db.sessions[0];

    if (!user || !session) {
      throw new Error("Expected seeded user and session.");
    }

    session.revoked_at = "2026-07-06T01:00:00.000Z";

    const response = await requestDeleteAccount(env, `Bearer ${accessToken}`);
    const body = await response.json();

    expectUnauthorized(body, response.status);
    expect(user.deleted_at).toBeNull();
  });

  it("delete account returns 401 for an expired session because stale destructive proofs must not delete users", async () => {
    const env = createTestEnv();
    const accessToken = await seedLiveUserSession(
      env,
      "delete-expired-user",
      "delete-expired-session",
    );
    const db = fakeD1(env);
    const user = db.users[0];
    const session = db.sessions[0];

    if (!user || !session) {
      throw new Error("Expected seeded user and session.");
    }

    session.expires_at = "2000-01-01T00:00:00.000Z";

    const response = await requestDeleteAccount(env, `Bearer ${accessToken}`);
    const body = await response.json();

    expectUnauthorized(body, response.status);
    expect(user.deleted_at).toBeNull();
  });

  it("delete account returns 401 for token/session owner mismatch because one session must not delete another owner", async () => {
    const env = createTestEnv();
    const accessToken = await seedLiveUserSession(
      env,
      "delete-mismatch-user",
      "delete-mismatch-session",
    );
    const db = fakeD1(env);
    const user = db.users[0];
    const session = db.sessions[0];

    if (!user || !session) {
      throw new Error("Expected seeded user and session.");
    }

    session.owner_id = "other-user";

    const response = await requestDeleteAccount(env, `Bearer ${accessToken}`);
    const body = await response.json();

    expectUnauthorized(body, response.status);
    expect(user.deleted_at).toBeNull();
  });

  it("delete account rolls back anonymous deletion when a batch statement fails because partial guest deletion must not leak through", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(
      env,
      "device-delete-rollback",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const db = fakeD1(env);
    db.collectionItems.push({
      id: "delete-rollback-collection",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      folder_id: db.portfolioFolders[0]?.id ?? "missing-folder",
      card_ref: "rollback-card",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "delete-rollback-wishlist",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: "rollback-card",
    });
    db.failRunOnSql = DELETE_ANONYMOUS_COLLECTION_ITEMS_SQL;

    const response = await requestDeleteAccount(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = await response.json();

    expect(response.status).toBe(500);
    expect(body).toEqual({
      success: false,
      error: {
        code: "INTERNAL_ERROR",
        message: "Unable to complete this action. Please try again later.",
      },
    });
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBeNull();
    expect(db.sessions[0]?.revoked_at).toBeNull();
    expect(db.portfolioFolders).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
      }),
    ]);
    expect(db.collectionItems).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
      }),
    ]);
    expect(db.wishlistItems).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
      }),
    ]);
    expect(db.userPreferences).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
      }),
    ]);
  });
});

describe("POST /api/v1/auth/migrate-assets", () => {
  it("migrate-assets transfers guest assets to the current user because registration migration can be retried", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const accessToken = await seedLiveUserSession(
      env,
      "migrate-user",
      "migrate-user-session",
    );
    const anonymousResponse = await requestAnonymous(
      env,
      "device-migrate-source",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    db.collectionItems.push({
      id: "migrate-guest-collection",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      folder_id: db.portfolioFolders[0]?.id ?? "missing-folder",
      card_ref: "migrate-card",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "migrate-guest-wishlist",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: "migrate-card",
    });

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: anonymousBody.data.anonymous_id },
      `Bearer ${accessToken}`,
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        migrated_folders: 1,
        migrated_items: 1,
        migrated_wishlist: 1,
      },
    });
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBe("migrate-user");
    expect(db.portfolioFolders[0]).toEqual(
      expect.objectContaining({ owner_type: "user", owner_id: "migrate-user" }),
    );
  });

  it("migrate-assets merges guest defaults into an existing user because standalone retry must not collide with default assets", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const accessToken = await seedLiveUserSession(
      env,
      "migrate-existing-user",
      "migrate-existing-session",
    );
    db.portfolioFolders.push({
      id: "user-main-folder",
      owner_type: "user",
      owner_id: "migrate-existing-user",
      name: "Main",
      is_default: 1,
      sort_order: 0,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.userPreferences.push({
      id: "user-existing-preference",
      owner_type: "user",
      owner_id: "migrate-existing-user",
      currency: "USD",
      amount_hidden: 0,
      last_selected_folder_id: "user-main-folder",
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    const anonymousResponse = await requestAnonymous(
      env,
      "device-migrate-existing",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const guestFolder = db.portfolioFolders.find(
      (folder) => folder.owner_id === anonymousBody.data.anonymous_id,
    );

    if (!guestFolder) {
      throw new Error("Expected guest default folder.");
    }

    db.collectionItems.push({
      id: "migrate-existing-collection",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      folder_id: guestFolder.id,
      card_ref: "existing-card",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "migrate-existing-wishlist",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: "existing-card",
    });
    db.wishlistItems.push({
      id: "migrate-existing-new-wishlist",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: "new-card",
    });
    db.wishlistItems.push({
      id: "user-existing-wishlist",
      owner_type: "user",
      owner_id: "migrate-existing-user",
      card_ref: "existing-card",
    });

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: anonymousBody.data.anonymous_id },
      `Bearer ${accessToken}`,
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        migrated_folders: 1,
        migrated_items: 1,
        migrated_wishlist: 1,
      },
    });
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBe(
      "migrate-existing-user",
    );
    expect(
      db.portfolioFolders.find((folder) => folder.id === "user-main-folder"),
    ).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: "migrate-existing-user",
        name: "Main",
      }),
    );
    expect(db.collectionItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: "migrate-existing-user",
        folder_id: "user-main-folder",
      }),
    );
    expect(
      db.wishlistItems.find((item) => item.id === "user-existing-wishlist"),
    ).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: "migrate-existing-user",
        card_ref: "existing-card",
      }),
    );
    expect(
      db.wishlistItems.find(
        (item) => item.id === "migrate-existing-new-wishlist",
      ),
    ).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: "migrate-existing-user",
        card_ref: "new-card",
      }),
    );
    expect(db.userPreferences).toEqual([
      expect.objectContaining({
        id: "user-existing-preference",
        owner_type: "user",
        owner_id: "migrate-existing-user",
      }),
    ]);
    expect(
      db.portfolioFolders.some(
        (folder) =>
          folder.owner_type === "anonymous" &&
          folder.owner_id === anonymousBody.data.anonymous_id,
      ),
    ).toBe(false);
    expect(
      db.collectionItems.some(
        (item) =>
          item.owner_type === "anonymous" &&
          item.owner_id === anonymousBody.data.anonymous_id,
      ),
    ).toBe(false);
    expect(
      db.wishlistItems.some(
        (item) =>
          item.owner_type === "anonymous" &&
          item.owner_id === anonymousBody.data.anonymous_id,
      ),
    ).toBe(false);
    expect(
      db.userPreferences.some(
        (preference) =>
          preference.owner_type === "anonymous" &&
          preference.owner_id === anonymousBody.data.anonymous_id,
      ),
    ).toBe(false);
  });

  it("migrate-assets remaps migrated preference folder because deleted guest folders must not leave dangling selections", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const accessToken = await seedLiveUserSession(
      env,
      "migrate-preference-user",
      "migrate-preference-session",
    );
    db.portfolioFolders.push({
      id: "preference-user-main-folder",
      owner_type: "user",
      owner_id: "migrate-preference-user",
      name: "Main",
      is_default: 1,
      sort_order: 0,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    const anonymousResponse = await requestAnonymous(
      env,
      "device-migrate-preference",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const guestFolder = db.portfolioFolders.find(
      (folder) => folder.owner_id === anonymousBody.data.anonymous_id,
    );
    const guestPreference = db.userPreferences.find(
      (preference) => preference.owner_id === anonymousBody.data.anonymous_id,
    );

    if (!guestFolder || !guestPreference) {
      throw new Error("Expected guest default folder and preference.");
    }

    guestPreference.last_selected_folder_id = guestFolder.id;

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: anonymousBody.data.anonymous_id },
      `Bearer ${accessToken}`,
      `Bearer ${anonymousBody.data.access_token}`,
    );

    expect(response.status).toBe(200);
    expect(db.userPreferences).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: "migrate-preference-user",
        last_selected_folder_id: "preference-user-main-folder",
      }),
    ]);
    expect(
      db.portfolioFolders.some(
        (folder) =>
          folder.owner_type === "anonymous" &&
          folder.owner_id === anonymousBody.data.anonymous_id,
      ),
    ).toBe(false);
  });

  it("migrate-assets rolls back when migration batch fails because partial guest claims must not leak through", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const accessToken = await seedLiveUserSession(
      env,
      "migrate-rollback-user",
      "migrate-rollback-session",
    );
    const userSession = db.sessions.find(
      (session) => session.id === "migrate-rollback-session",
    );
    db.portfolioFolders.push({
      id: "rollback-user-main-folder",
      owner_type: "user",
      owner_id: "migrate-rollback-user",
      name: "Main",
      is_default: 1,
      sort_order: 0,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.userPreferences.push({
      id: "rollback-user-preference",
      owner_type: "user",
      owner_id: "migrate-rollback-user",
      currency: "USD",
      amount_hidden: 0,
      last_selected_folder_id: "rollback-user-main-folder",
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "rollback-user-wishlist",
      owner_type: "user",
      owner_id: "migrate-rollback-user",
      card_ref: "existing-card",
    });
    const anonymousResponse = await requestAnonymous(
      env,
      "device-migrate-rollback",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const guestFolder = db.portfolioFolders.find(
      (folder) => folder.owner_id === anonymousBody.data.anonymous_id,
    );
    const guestPreference = db.userPreferences.find(
      (preference) => preference.owner_id === anonymousBody.data.anonymous_id,
    );
    const anonymousSession = db.sessions.find(
      (session) => session.owner_id === anonymousBody.data.anonymous_id,
    );

    if (!guestFolder || !guestPreference || !userSession || !anonymousSession) {
      throw new Error("Expected migration rollback fixtures.");
    }

    guestPreference.last_selected_folder_id = guestFolder.id;
    db.collectionItems.push({
      id: "rollback-guest-collection",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      folder_id: guestFolder.id,
      card_ref: "rollback-card",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "rollback-guest-conflicting-wishlist",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: "existing-card",
    });
    db.wishlistItems.push({
      id: "rollback-guest-new-wishlist",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: "new-card",
    });
    db.failRunOnSql = REMAP_CONFLICTING_COLLECTION_ITEMS_TO_USER_FOLDER_SQL;

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: anonymousBody.data.anonymous_id },
      `Bearer ${accessToken}`,
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = await response.json();

    expect(response.status).toBe(500);
    expect(body).toEqual({
      success: false,
      error: {
        code: "INTERNAL_ERROR",
        message: "Unable to complete this action. Please try again later.",
      },
    });
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBeNull();
    expect(userSession.revoked_at).toBeNull();
    expect(anonymousSession.revoked_at).toBeNull();
    expect(
      db.portfolioFolders.find((folder) => folder.id === guestFolder.id),
    ).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
        name: "Main",
      }),
    );
    expect(db.collectionItems).toEqual([
      expect.objectContaining({
        id: "rollback-guest-collection",
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
        folder_id: guestFolder.id,
      }),
    ]);
    expect(
      db.wishlistItems.find(
        (item) => item.id === "rollback-guest-conflicting-wishlist",
      ),
    ).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
        card_ref: "existing-card",
      }),
    );
    expect(
      db.wishlistItems.find((item) => item.id === "rollback-guest-new-wishlist"),
    ).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
        card_ref: "new-card",
      }),
    );
    expect(db.userPreferences).toEqual([
      expect.objectContaining({
        id: "rollback-user-preference",
        owner_type: "user",
        owner_id: "migrate-rollback-user",
        last_selected_folder_id: "rollback-user-main-folder",
      }),
      expect.objectContaining({
        id: guestPreference.id,
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
        last_selected_folder_id: guestFolder.id,
      }),
    ]);
    expect(
      db.portfolioFolders.find((folder) => folder.id === "rollback-user-main-folder"),
    ).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: "migrate-rollback-user",
      }),
    );
    expect(
      db.wishlistItems.find((item) => item.id === "rollback-user-wishlist"),
    ).toEqual(
      expect.objectContaining({
        owner_type: "user",
        owner_id: "migrate-rollback-user",
        card_ref: "existing-card",
      }),
    );
  });

  it("migrate-assets returns 403 without anonymous proof because anonymous_id alone must not prove source ownership", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const accessToken = await seedLiveUserSession(
      env,
      "migrate-no-proof-user",
      "migrate-no-proof-session",
    );
    const anonymousResponse = await requestAnonymous(
      env,
      "device-migrate-no-proof",
    );
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: anonymousBody.data.anonymous_id },
      `Bearer ${accessToken}`,
    );
    const body = await response.json();

    expect(response.status).toBe(403);
    expect(body).toEqual({
      success: false,
      error: { code: "AUTH_REQUIRED", message: "Auth required." },
    });
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBeNull();
    expect(db.portfolioFolders[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
      }),
    );
  });

  it("migrate-assets returns 403 for mismatched anonymous proof because one guest token must not claim another guest", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const accessToken = await seedLiveUserSession(
      env,
      "migrate-mismatch-user",
      "migrate-mismatch-session",
    );
    const targetResponse = await requestAnonymous(
      env,
      "device-migrate-target",
    );
    const targetBody =
      (await targetResponse.json()) as AnonymousSuccessResponse;
    const otherResponse = await requestAnonymous(env, "device-migrate-other");
    const otherBody = (await otherResponse.json()) as AnonymousSuccessResponse;

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: targetBody.data.anonymous_id },
      `Bearer ${accessToken}`,
      `Bearer ${otherBody.data.access_token}`,
    );
    const body = await response.json();

    expect(response.status).toBe(403);
    expect(body).toEqual({
      success: false,
      error: { code: "AUTH_REQUIRED", message: "Auth required." },
    });
    expect(
      db.anonymousAccounts.find(
        (row) => row.id === targetBody.data.anonymous_id,
      )?.upgraded_user_id,
    ).toBeNull();
    expect(
      db.portfolioFolders.find(
        (row) => row.owner_id === targetBody.data.anonymous_id,
      ),
    ).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: targetBody.data.anonymous_id,
      }),
    );
  });

  it("migrate-assets returns 403 for missing anonymous account without guest proof because source state must not be disclosed", async () => {
    const env = createTestEnv();
    const accessToken = await seedLiveUserSession(
      env,
      "migrate-missing-user",
      "migrate-missing-session",
    );

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: "missing-anonymous" },
      `Bearer ${accessToken}`,
    );
    const body = await response.json();

    expect(response.status).toBe(403);
    expect(body).toEqual({
      success: false,
      error: { code: "AUTH_REQUIRED", message: "Auth required." },
    });
  });

  it("migrate-assets returns 404 for a missing anonymous account with valid guest proof because there is no source owner", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const accessToken = await seedLiveUserSession(
      env,
      "migrate-proven-missing-user",
      "migrate-proven-missing-session",
    );
    db.sessions.push({
      id: "missing-anonymous-session",
      owner_type: "anonymous",
      owner_id: "missing-anonymous",
      refresh_token: await hashRefreshToken("missing-anonymous-refresh"),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-06T00:00:00.000Z",
      revoked_at: null,
    });
    const anonymousAccessToken = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "missing-anonymous",
        session_id: "missing-anonymous-session",
      },
      env.JWT_SECRET,
    );

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: "missing-anonymous" },
      `Bearer ${accessToken}`,
      `Bearer ${anonymousAccessToken}`,
    );
    const body = await response.json();

    expect(response.status).toBe(404);
    expect(body).toEqual({
      success: false,
      error: { code: "NOT_FOUND", message: "Not found." },
    });
  });

  it("migrate-assets returns 409 for an already upgraded anonymous account because assets must not be stolen", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const sessionId = "migrate-upgraded-session";
    db.users.push({
      id: "migrate-upgraded-user",
      email: "migrate-upgraded@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-06T00:00:00.000Z",
      updated_at: "2026-07-06T00:00:00.000Z",
      deleted_at: null,
    });
    db.sessions.push({
      id: sessionId,
      owner_type: "user",
      owner_id: "migrate-upgraded-user",
      refresh_token: await hashRefreshToken("migrate-upgraded-refresh"),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-06T00:00:00.000Z",
      revoked_at: null,
    });
    seedGuestMigrationRows(db, "anonymous-upgraded-source", "existing-user");
    db.sessions.push({
      id: "anonymous-upgraded-session",
      owner_type: "anonymous",
      owner_id: "anonymous-upgraded-source",
      refresh_token: await hashRefreshToken("anonymous-upgraded-refresh"),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-06T00:00:00.000Z",
      revoked_at: null,
    });
    const accessToken = await signAccessToken(
      {
        owner_type: "user",
        owner_id: "migrate-upgraded-user",
        session_id: sessionId,
      },
      env.JWT_SECRET,
    );
    const anonymousAccessToken = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "anonymous-upgraded-source",
        session_id: "anonymous-upgraded-session",
      },
      env.JWT_SECRET,
    );

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: "anonymous-upgraded-source" },
      `Bearer ${accessToken}`,
      `Bearer ${anonymousAccessToken}`,
    );
    const body = await response.json();

    expect(response.status).toBe(409);
    expect(body).toEqual({
      success: false,
      error: {
        code: "CONFLICT",
        message: "Guest account is no longer available.",
      },
    });
    expect(db.anonymousAccounts[0]).toEqual(
      expect.objectContaining({
        id: "anonymous-upgraded-source",
        upgraded_user_id: "existing-user",
      }),
    );
    expect(db.portfolioFolders[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-upgraded-source",
      }),
    );
    expect(db.collectionItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-upgraded-source",
      }),
    );
    expect(db.wishlistItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-upgraded-source",
      }),
    );
    expect(db.userPreferences[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anonymous-upgraded-source",
      }),
    );
  });

  it("migrate-assets returns 403 for anonymous JWT because only durable users can claim guest assets", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-migrate-denied");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const db = fakeD1(env);
    db.collectionItems.push({
      id: "migrate-denied-collection",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      folder_id: db.portfolioFolders[0]?.id ?? "missing-folder",
      card_ref: "denied-card",
      updated_at: "2026-07-06T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "migrate-denied-wishlist",
      owner_type: "anonymous",
      owner_id: anonymousBody.data.anonymous_id,
      card_ref: "denied-card",
    });

    const response = await requestMigrateAssets(
      env,
      { anonymous_id: anonymousBody.data.anonymous_id },
      `Bearer ${anonymousBody.data.access_token}`,
    );
    const body = await response.json();

    expect(response.status).toBe(403);
    expect(body).toEqual({
      success: false,
      error: { code: "AUTH_REQUIRED", message: "Auth required." },
    });
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBeNull();
    expect(db.portfolioFolders[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
      }),
    );
    expect(db.collectionItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
      }),
    );
    expect(db.wishlistItems[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
      }),
    );
    expect(db.userPreferences[0]).toEqual(
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: anonymousBody.data.anonymous_id,
      }),
    );
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
        login_method: null,
        display_name: null,
        created_at: account?.created_at,
      },
    });
  });

  it("returns the active user account for a valid access token because upgraded clients should identify the durable owner", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.users.push({
      id: "user-current",
      email: "owner@example.com",
      password_hash: null,
      display_name: "Owner",
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: null,
    });
    db.sessions.push({
      id: "session-current",
      owner_type: "user",
      owner_id: "user-current",
      login_method: "google",
      refresh_token: await hashRefreshToken("current-refresh"),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-02T00:00:00.000Z",
      revoked_at: null,
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
        login_method: "google",
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

  it("returns 401 / UNAUTHORIZED when the access token session is missing because restored clients need live session proof", async () => {
    const env = createTestEnv();
    fakeD1(env).users.push({
      id: "missing-session-user",
      email: "missing-session@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: null,
    });
    const accessToken = await signAccessToken(
      {
        owner_type: "user",
        owner_id: "missing-session-user",
        session_id: "missing-current-session",
      },
      env.JWT_SECRET,
    );

    const response = await requestCurrentAccount(env, `Bearer ${accessToken}`);
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED when the access token session is revoked because logout must invalidate account restore", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    db.users.push({
      id: "revoked-current-user",
      email: "revoked-current@example.com",
      password_hash: null,
      display_name: null,
      created_at: "2026-07-02T00:00:00.000Z",
      updated_at: "2026-07-02T00:00:00.000Z",
      deleted_at: null,
    });
    db.sessions.push({
      id: "revoked-current-session",
      owner_type: "user",
      owner_id: "revoked-current-user",
      refresh_token: await hashRefreshToken("revoked-current-refresh"),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-02T00:00:00.000Z",
      revoked_at: "2026-07-02T01:00:00.000Z",
    });
    const accessToken = await signAccessToken(
      {
        owner_type: "user",
        owner_id: "revoked-current-user",
        session_id: "revoked-current-session",
      },
      env.JWT_SECRET,
    );

    const response = await requestCurrentAccount(env, `Bearer ${accessToken}`);
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
    fakeD1(env).sessions.push({
      id: "missing-owner-session",
      owner_type: "anonymous",
      owner_id: "missing-anonymous",
      refresh_token: await hashRefreshToken("missing-owner-refresh"),
      expires_at: "2999-01-01T00:00:00.000Z",
      created_at: "2026-07-02T00:00:00.000Z",
      revoked_at: null,
    });
    const accessToken = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "missing-anonymous",
        session_id: "missing-owner-session",
      },
      env.JWT_SECRET,
    );

    const response = await requestCurrentAccount(env, `Bearer ${accessToken}`);
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });
});
