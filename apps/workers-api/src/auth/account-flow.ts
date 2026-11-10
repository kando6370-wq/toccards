import { createId } from "../id";
import { reserveAccountUid } from "../account-uid";
import type { Database } from "../db/database";
import { mutationLockKey, runWithMutationLockStatements } from "../db/mutation-lock";
import {
  createGuestMigrationStatements,
  findVerifiedAnonymousAccount,
} from "./guest-migration";
import type { OAuthIdentity } from "./oauth-provider";
import { findLatestPlatformAccount, type AuthPlatform } from "./platform-account";
import {
  createUserSessionValues,
  type CreatedUserSession,
} from "./user-session";

type UserRow = {
  id: string;
};

type OAuthEmailUserRow = {
  id: string;
  status: "active" | "disabled";
};

type OAuthIdentityRow = {
  user_id: string;
};

export type OAuthAccountFlowResult = {
  userId: string;
  isNewUser: boolean;
  migrated: boolean;
  session: CreatedUserSession;
};

const OAUTH_AUTHORIZATION_FAILED_MESSAGE = "OAuth authorization failed.";
const GUEST_ACCOUNT_UNAVAILABLE_MESSAGE =
  "Guest account is no longer available.";

const SELECT_OAUTH_IDENTITY_SQL = `
  SELECT user_id
  FROM auth_identity
  WHERE auth_identity.provider = ?
    AND auth_identity.provider_uid = ?
  LIMIT 1
`;

const SELECT_LIVE_USER_BY_ID_SQL = `
  SELECT id
  FROM "user"
  WHERE id = ? AND status = 'active'
  LIMIT 1
`;

const SELECT_USER_BY_EMAIL_FOR_OAUTH_SQL = `
  SELECT id, status
  FROM "user"
  WHERE email = ? AND status <> 'deleted'
  LIMIT 1
`;

const INSERT_OAUTH_USER_SQL = `
  INSERT INTO "user"
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  VALUES (?, ?, NULL, NULL, ?, ?, NULL)
`;

const INSERT_AUTH_IDENTITY_SQL = `
  INSERT INTO auth_identity
    (id, user_id, provider, provider_uid, created_at)
  VALUES (?, ?, ?, ?, ?)
`;

const INSERT_OAUTH_USER_FOR_UPGRADED_GUEST_SQL = `
  INSERT INTO "user"
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  SELECT ?, ?, NULL, NULL, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM anonymous_account
    WHERE id = ? AND upgraded_user_id = ?
  )
`;

const INSERT_AUTH_IDENTITY_FOR_UPGRADED_GUEST_SQL = `
  INSERT INTO auth_identity
    (id, user_id, provider, provider_uid, created_at)
  SELECT ?, ?, ?, ?, ?
  WHERE EXISTS (
    SELECT 1
    FROM anonymous_account
    WHERE id = ? AND upgraded_user_id = ?
  )
`;

const INSERT_USER_PORTFOLIO_FOLDER_SQL = `
  INSERT INTO portfolio_folder
    (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
  VALUES (?, 'user', ?, 'Main', 1, 0, ?, ?)
`;

const INSERT_USER_PREFERENCE_SQL = `
  INSERT INTO user_preference
    (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
  VALUES (?, 'user', ?, 'USD', 0, NULL, ?, ?)
`;

const INSERT_USER_SESSION_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at, platform, user_id)
  SELECT ?, 'user', ?, ?, ?, ?, ?, NULL, ?, ?
  WHERE EXISTS (
    SELECT 1 FROM platform_account pa JOIN "user" u ON u.id = pa.user_id
    WHERE pa.id = ? AND pa.user_id = ? AND pa.platform = ?
      AND pa.status = 'active' AND u.status = 'active'
  )
`;

const INSERT_USER_SESSION_FOR_UPGRADED_GUEST_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at, platform, user_id)
  SELECT ?, 'user', ?, ?, ?, ?, ?, NULL, ?, ?
  WHERE EXISTS (
    SELECT 1
    FROM anonymous_account
    WHERE id = ? AND upgraded_user_id = ?
  )
`;

export function isOAuthAuthorizationFailedError(error: unknown): boolean {
  return (
    error instanceof Error && error.message === OAUTH_AUTHORIZATION_FAILED_MESSAGE
  );
}

export function isGuestAccountUnavailableError(error: unknown): boolean {
  return (
    error instanceof Error && error.message === GUEST_ACCOUNT_UNAVAILABLE_MESSAGE
  );
}

export async function completeOAuthAccountFlow(
  db: Database,
  identity: OAuthIdentity,
  jwtSecret: string,
  anonymousId: string | null,
  authorization: string | undefined,
  now: Date,
  platform: AuthPlatform,
): Promise<OAuthAccountFlowResult> {
  try {
    return await completeOAuthAccountFlowOnce(
      db,
      identity,
      jwtSecret,
      anonymousId,
      authorization,
      now,
      platform,
    );
  } catch (error) {
    if (!isOAuthUniqueConstraintError(error)) {
      throw error;
    }

    return completeOAuthAccountFlowOnce(
      db,
      identity,
      jwtSecret,
      anonymousId,
      authorization,
      now,
      platform,
    );
  }
}

async function completeOAuthAccountFlowOnce(
  db: Database,
  identity: OAuthIdentity,
  jwtSecret: string,
  anonymousId: string | null,
  authorization: string | undefined,
  now: Date,
  platform: AuthPlatform,
): Promise<OAuthAccountFlowResult> {
  const existingIdentity = await db
    .prepare(SELECT_OAUTH_IDENTITY_SQL)
    .bind(identity.provider, identity.providerUid)
    .first<OAuthIdentityRow>();

  if (existingIdentity) {
    const existingIdentityUser = await db
      .prepare(SELECT_LIVE_USER_BY_ID_SQL)
      .bind(existingIdentity.user_id)
      .first<UserRow>();

    if (!existingIdentityUser) {
      throw new Error(OAUTH_AUTHORIZATION_FAILED_MESSAGE);
    }

    return createPlatformSignInOrRegistrationResult(
      db,
      existingIdentityUser.id,
      identity,
      jwtSecret,
      now,
      platform,
      anonymousId,
      authorization,
    );
  }

  const existingEmailUser = await db
    .prepare(SELECT_USER_BY_EMAIL_FOR_OAUTH_SQL)
    .bind(identity.email)
    .first<OAuthEmailUserRow>();

  if (existingEmailUser) {
    if (existingEmailUser.status !== "active") {
      throw new Error(OAUTH_AUTHORIZATION_FAILED_MESSAGE);
    }

    return bindIdentityAndSignIn(
      db,
      existingEmailUser.id,
      identity,
      jwtSecret,
      now,
      platform,
      anonymousId,
      authorization,
    );
  }

  return createOAuthUser(
    db,
    identity,
    jwtSecret,
    anonymousId,
    authorization,
    now,
    platform,
  );
}

function isOAuthUniqueConstraintError(error: unknown): boolean {
  const postgresError = error as {
    code?: unknown; constraint_name?: unknown; constraint?: unknown;
  };
  return (
    error instanceof Error &&
    (error.message.includes("UNIQUE constraint failed: user.email") ||
      error.message.includes(
        "UNIQUE constraint failed: auth_identity.provider, auth_identity.provider_uid",
      ) ||
      (postgresError.code === "23505" && (
        [postgresError.constraint_name, postgresError.constraint].some((constraint) =>
          constraint === "uq_user_non_deleted_email" ||
          constraint === "uq_auth_identity_provider" ||
          constraint === "uq_platform_account_live_user_platform")
      )))
  );
}

async function createPlatformSignInOrRegistrationResult(
  db: Database,
  userId: string,
  identity: OAuthIdentity,
  jwtSecret: string,
  now: Date,
  platform: AuthPlatform,
  anonymousId: string | null,
  authorization: string | undefined,
): Promise<OAuthAccountFlowResult> {
  let account = await findLatestPlatformAccount(db, userId, platform);
  const createdAt = now.toISOString();
  let registeredPlatform = false;
  let migratedPlatform = false;
  if (!account || account.status === "deleted") {
    const anonymousAccount = await findVerifiedAnonymousAccount(
      db, anonymousId, authorization, jwtSecret, now,
    );
    if (anonymousAccount && anonymousAccount.platform !== platform) {
      throw new Error(OAUTH_AUTHORIZATION_FAILED_MESSAGE);
    }
    const dataSpaceId = anonymousAccount?.id ?? await reserveAccountUid(db, createdAt);
    const statements = [
      db.prepare(`INSERT INTO platform_account
        (id, user_id, platform, status, created_at, updated_at, deleted_at)
        VALUES (?, (SELECT id FROM "user" WHERE id = ? AND status = 'active'),
          ?, 'active', ?, ?, NULL)`).bind(
          dataSpaceId, userId, platform, createdAt, createdAt,
        ),
    ];
    if (anonymousAccount) {
      migratedPlatform = true;
      const migration = createGuestMigrationStatements(
        db, anonymousAccount.id, dataSpaceId, createdAt, {},
      );
      statements.push(
        migration.upgradeAccount, migration.portfolioFolders, migration.collectionItems,
        migration.collectionItemEvents, migration.wishlistItems, migration.userPreference,
        migration.scanRecords, migration.consumedFreeScanQuota,
      );
    } else {
      statements.push(
        db.prepare(INSERT_USER_PORTFOLIO_FOLDER_SQL).bind(createId(), dataSpaceId, createdAt, createdAt),
        db.prepare(INSERT_USER_PREFERENCE_SQL).bind(createId(), dataSpaceId, createdAt, createdAt),
      );
    }
    const pendingSession = await createUserSessionValues(
      userId, dataSpaceId, platform, jwtSecret, now,
    );
    statements.push(db.prepare(INSERT_USER_SESSION_SQL).bind(
      pendingSession.sessionId, dataSpaceId, identity.provider,
      pendingSession.hashedRefreshToken, pendingSession.expiresAt, createdAt,
      platform, userId, dataSpaceId, userId, platform,
    ));
    const results = await runWithMutationLockStatements(
      db,
      await mutationLockKey("platform-account-delete", userId),
      statements,
    );
    const requiredIndexes = anonymousAccount
      ? [0, 1, results.length - 1]
      : [0, 1, 2, results.length - 1];
    if (requiredIndexes.some((index) => results[index]?.meta.changes !== 1)) {
      throw new Error("Failed to create platform account.");
    }
    account = { id: dataSpaceId, user_id: userId, platform, status: "active" };
    registeredPlatform = true;
    return {
      userId,
      isNewUser: true,
      migrated: migratedPlatform,
      session: pendingSession,
    };
  }
  if (account.status !== "active") throw new Error(OAUTH_AUTHORIZATION_FAILED_MESSAGE);
  const session = await createUserSessionValues(userId, account.id, platform, jwtSecret, now);

  const [sessionResult] = await runWithMutationLockStatements(
    db,
    await mutationLockKey("platform-account-delete", userId),
    [db.prepare(INSERT_USER_SESSION_SQL).bind(
      session.sessionId,
      account.id,
      identity.provider,
      session.hashedRefreshToken,
      session.expiresAt,
      createdAt,
      platform,
      userId,
      account.id,
      userId,
      platform,
    )],
  );
  if (sessionResult?.meta.changes !== 1) {
    throw new Error(OAUTH_AUTHORIZATION_FAILED_MESSAGE);
  }

  return { userId, isNewUser: registeredPlatform, migrated: migratedPlatform, session };
}

async function bindIdentityAndSignIn(
  db: Database,
  userId: string,
  identity: OAuthIdentity,
  jwtSecret: string,
  now: Date,
  platform: AuthPlatform,
  anonymousId: string | null,
  authorization: string | undefined,
): Promise<OAuthAccountFlowResult> {
  const existing = await findLatestPlatformAccount(db, userId, platform);
  const createdAt = now.toISOString();
  const anonymousAccount = existing?.status === "active" ? null
    : await findVerifiedAnonymousAccount(db, anonymousId, authorization, jwtSecret, now);
  if (anonymousAccount && anonymousAccount.platform !== platform) {
    throw new Error(OAUTH_AUTHORIZATION_FAILED_MESSAGE);
  }
  const dataSpaceId = existing?.status === "active"
    ? existing.id
    : anonymousAccount?.id ?? await reserveAccountUid(db, createdAt);
  const session = await createUserSessionValues(userId, dataSpaceId, platform, jwtSecret, now);
  const statements = [
    db
      .prepare(INSERT_AUTH_IDENTITY_SQL)
      .bind(createId(), userId, identity.provider, identity.providerUid, createdAt),
    ...(existing?.status === "active" ? [] : [
      db.prepare(`INSERT INTO platform_account
        (id, user_id, platform, status, created_at, updated_at, deleted_at)
        VALUES (?, (SELECT id FROM "user" WHERE id = ? AND status = 'active'),
          ?, 'active', ?, ?, NULL)`).bind(
          dataSpaceId, userId, platform, createdAt, createdAt,
        ),
      ...(anonymousAccount ? Object.values(createGuestMigrationStatements(
        db, anonymousAccount.id, dataSpaceId, createdAt, {},
      )) : [
        db.prepare(INSERT_USER_PORTFOLIO_FOLDER_SQL).bind(createId(), dataSpaceId, createdAt, createdAt),
        db.prepare(INSERT_USER_PREFERENCE_SQL).bind(createId(), dataSpaceId, createdAt, createdAt),
      ]),
    ]),
    db
      .prepare(INSERT_USER_SESSION_SQL)
      .bind(
        session.sessionId,
        dataSpaceId,
        identity.provider,
        session.hashedRefreshToken,
        session.expiresAt,
        createdAt,
        platform,
        userId,
        dataSpaceId,
        userId,
        platform,
      ),
  ];
  const results = await runWithMutationLockStatements(
    db,
    await mutationLockKey("platform-account-delete", userId),
    statements,
  );

  const requiredIndexes = existing?.status === "active"
    ? [0, results.length - 1]
    : anonymousAccount
      ? [0, 1, 2, results.length - 1]
      : [0, 1, 2, 3, results.length - 1];
  if (requiredIndexes.some((index) => results[index]?.meta.changes !== 1)) {
    throw new Error("Failed to bind OAuth identity.");
  }

  return {
    userId,
    isNewUser: existing?.status !== "active",
    migrated: anonymousAccount !== null,
    session,
  };
}

async function createOAuthUser(
  db: Database,
  identity: OAuthIdentity,
  jwtSecret: string,
  anonymousId: string | null,
  authorization: string | undefined,
  now: Date,
  platform: AuthPlatform,
): Promise<OAuthAccountFlowResult> {
  const createdAt = now.toISOString();
  const anonymousAccount = await findVerifiedAnonymousAccount(
    db,
    anonymousId,
    authorization,
    jwtSecret,
    now,
  );
  if (anonymousAccount && anonymousAccount.platform !== platform) {
    throw new Error(OAUTH_AUTHORIZATION_FAILED_MESSAGE);
  }
  const userId =
    anonymousAccount?.id ?? await reserveAccountUid(db, createdAt);
  const dataSpaceId = anonymousAccount?.id ?? (
    platform === "ios" ? userId : await reserveAccountUid(db, createdAt)
  );
  const session = await createUserSessionValues(userId, dataSpaceId, platform, jwtSecret, now);

  if (anonymousAccount) {
    const migrationStatements = createGuestMigrationStatements(
      db,
      anonymousAccount.id,
      dataSpaceId,
      createdAt,
      {},
    );
    const results = await db.batch([
      migrationStatements.upgradeAccount,
      db.prepare(INSERT_OAUTH_USER_FOR_UPGRADED_GUEST_SQL).bind(
        userId,
        identity.email,
        createdAt,
        createdAt,
        anonymousAccount.id,
        dataSpaceId,
      ),
      db.prepare(`INSERT INTO platform_account
        (id, user_id, platform, status, created_at, updated_at, deleted_at)
        VALUES (?, (SELECT id FROM "user" WHERE id = ? AND status = 'active'),
          ?, 'active', ?, ?, NULL)`).bind(
          dataSpaceId, userId, platform, createdAt, createdAt,
        ),
      db
        .prepare(INSERT_AUTH_IDENTITY_FOR_UPGRADED_GUEST_SQL)
        .bind(
          createId(),
          userId,
          identity.provider,
          identity.providerUid,
          createdAt,
          anonymousAccount.id,
          dataSpaceId,
        ),
      migrationStatements.portfolioFolders,
      migrationStatements.collectionItems,
      migrationStatements.collectionItemEvents,
      migrationStatements.wishlistItems,
      migrationStatements.userPreference,
      migrationStatements.scanRecords,
      migrationStatements.consumedFreeScanQuota,
      db
        .prepare(INSERT_USER_SESSION_FOR_UPGRADED_GUEST_SQL)
        .bind(
          session.sessionId,
          dataSpaceId,
          identity.provider,
          session.hashedRefreshToken,
          session.expiresAt,
          createdAt,
          platform,
          userId,
          anonymousAccount.id,
          dataSpaceId,
        ),
    ]);

    if (results[0]?.meta.changes !== 1) {
      throw new Error(GUEST_ACCOUNT_UNAVAILABLE_MESSAGE);
    }

    if (
      results.length !== 12 ||
      results[1]?.meta.changes !== 1 ||
      results[2]?.meta.changes !== 1 ||
      results[11]?.meta.changes !== 1
    ) {
      throw new Error("Failed to create migrated OAuth user.");
    }

    return { userId, isNewUser: true, migrated: true, session };
  }

  const results = await db.batch([
    db.prepare(INSERT_OAUTH_USER_SQL).bind(
      userId,
      identity.email,
      createdAt,
      createdAt,
    ),
    db.prepare(`INSERT INTO platform_account
      (id, user_id, platform, status, created_at, updated_at, deleted_at)
      VALUES (?, (SELECT id FROM "user" WHERE id = ? AND status = 'active'),
        ?, 'active', ?, ?, NULL)`).bind(
        dataSpaceId, userId, platform, createdAt, createdAt,
      ),
    db
      .prepare(INSERT_AUTH_IDENTITY_SQL)
      .bind(createId(), userId, identity.provider, identity.providerUid, createdAt),
    db
      .prepare(INSERT_USER_PORTFOLIO_FOLDER_SQL)
      .bind(createId(), dataSpaceId, createdAt, createdAt),
    db
      .prepare(INSERT_USER_PREFERENCE_SQL)
      .bind(createId(), dataSpaceId, createdAt, createdAt),
    db
      .prepare(INSERT_USER_SESSION_SQL)
      .bind(
        session.sessionId,
        dataSpaceId,
        identity.provider,
        session.hashedRefreshToken,
        session.expiresAt,
        createdAt,
        platform,
        userId,
        dataSpaceId,
        userId,
        platform,
      ),
  ]);

  const requiredIndexes = anonymousAccount
    ? [0, 1, 2, 3, results.length - 1]
    : results.map((_, index) => index);
  if (requiredIndexes.some((index) => results[index]?.meta.changes !== 1)) {
    throw new Error("Failed to create OAuth user.");
  }

  return { userId, isNewUser: true, migrated: false, session };
}
