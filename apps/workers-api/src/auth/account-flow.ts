import { createId } from "../id";
import {
  createGuestMigrationStatements,
  findVerifiedAnonymousAccount,
} from "./guest-migration";
import type { OAuthIdentity } from "./oauth-provider";
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
  FROM user
  WHERE id = ? AND status = 'active'
  LIMIT 1
`;

const SELECT_USER_BY_EMAIL_FOR_OAUTH_SQL = `
  SELECT id, status
  FROM user
  WHERE email = ? AND status <> 'deleted'
  LIMIT 1
`;

const INSERT_OAUTH_USER_SQL = `
  INSERT INTO user
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  VALUES (?, ?, NULL, NULL, ?, ?, NULL)
`;

const INSERT_AUTH_IDENTITY_SQL = `
  INSERT INTO auth_identity
    (id, user_id, provider, provider_uid, created_at)
  VALUES (?, ?, ?, ?, ?)
`;

const INSERT_OAUTH_USER_FOR_UPGRADED_GUEST_SQL = `
  INSERT INTO user
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
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'user', ?, ?, ?, ?, ?, NULL)
`;

const INSERT_USER_SESSION_FOR_UPGRADED_GUEST_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  SELECT ?, 'user', ?, ?, ?, ?, ?, NULL
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
  db: D1Database,
  identity: OAuthIdentity,
  jwtSecret: string,
  anonymousId: string | null,
  authorization: string | undefined,
  now: Date,
): Promise<OAuthAccountFlowResult> {
  try {
    return await completeOAuthAccountFlowOnce(
      db,
      identity,
      jwtSecret,
      anonymousId,
      authorization,
      now,
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
    );
  }
}

async function completeOAuthAccountFlowOnce(
  db: D1Database,
  identity: OAuthIdentity,
  jwtSecret: string,
  anonymousId: string | null,
  authorization: string | undefined,
  now: Date,
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

    return createSignInResult(
      db,
      existingIdentityUser.id,
      identity,
      jwtSecret,
      now,
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
    );
  }

  return createOAuthUser(
    db,
    identity,
    jwtSecret,
    anonymousId,
    authorization,
    now,
  );
}

function isOAuthUniqueConstraintError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (error.message.includes("UNIQUE constraint failed: user.email") ||
      error.message.includes(
        "UNIQUE constraint failed: auth_identity.provider, auth_identity.provider_uid",
      ))
  );
}

async function createSignInResult(
  db: D1Database,
  userId: string,
  identity: OAuthIdentity,
  jwtSecret: string,
  now: Date,
): Promise<OAuthAccountFlowResult> {
  const session = await createUserSessionValues(userId, jwtSecret, now);
  const createdAt = now.toISOString();

  await db
    .prepare(INSERT_USER_SESSION_SQL)
    .bind(
      session.sessionId,
      userId,
      identity.provider,
      session.hashedRefreshToken,
      session.expiresAt,
      createdAt,
    )
    .run();

  return { userId, isNewUser: false, migrated: false, session };
}

async function bindIdentityAndSignIn(
  db: D1Database,
  userId: string,
  identity: OAuthIdentity,
  jwtSecret: string,
  now: Date,
): Promise<OAuthAccountFlowResult> {
  const session = await createUserSessionValues(userId, jwtSecret, now);
  const createdAt = now.toISOString();
  const results = await db.batch([
    db
      .prepare(INSERT_AUTH_IDENTITY_SQL)
      .bind(createId(), userId, identity.provider, identity.providerUid, createdAt),
    db
      .prepare(INSERT_USER_SESSION_SQL)
      .bind(
        session.sessionId,
        userId,
        identity.provider,
        session.hashedRefreshToken,
        session.expiresAt,
        createdAt,
      ),
  ]);

  if (results.some((result) => result?.meta.changes !== 1)) {
    throw new Error("Failed to bind OAuth identity.");
  }

  return { userId, isNewUser: false, migrated: false, session };
}

async function createOAuthUser(
  db: D1Database,
  identity: OAuthIdentity,
  jwtSecret: string,
  anonymousId: string | null,
  authorization: string | undefined,
  now: Date,
): Promise<OAuthAccountFlowResult> {
  const createdAt = now.toISOString();
  const userId = createId();
  const session = await createUserSessionValues(userId, jwtSecret, now);
  const anonymousAccount = await findVerifiedAnonymousAccount(
    db,
    anonymousId,
    authorization,
    jwtSecret,
    now,
  );

  if (anonymousAccount) {
    const migrationStatements = createGuestMigrationStatements(
      db,
      anonymousAccount.id,
      userId,
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
        userId,
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
          userId,
        ),
      migrationStatements.portfolioFolders,
      migrationStatements.collectionItems,
      migrationStatements.collectionItemEvents,
      migrationStatements.wishlistItems,
      migrationStatements.userPreference,
      migrationStatements.scanRecords,
      db
        .prepare(INSERT_USER_SESSION_FOR_UPGRADED_GUEST_SQL)
        .bind(
          session.sessionId,
          userId,
          identity.provider,
          session.hashedRefreshToken,
          session.expiresAt,
          createdAt,
          anonymousAccount.id,
          userId,
        ),
    ]);

    if (results[0]?.meta.changes !== 1) {
      throw new Error(GUEST_ACCOUNT_UNAVAILABLE_MESSAGE);
    }

    if (
      results.length !== 10 ||
      results[1]?.meta.changes !== 1 ||
      results[2]?.meta.changes !== 1 ||
      results[9]?.meta.changes !== 1
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
    db
      .prepare(INSERT_AUTH_IDENTITY_SQL)
      .bind(createId(), userId, identity.provider, identity.providerUid, createdAt),
    db
      .prepare(INSERT_USER_PORTFOLIO_FOLDER_SQL)
      .bind(createId(), userId, createdAt, createdAt),
    db
      .prepare(INSERT_USER_PREFERENCE_SQL)
      .bind(createId(), userId, createdAt, createdAt),
    db
      .prepare(INSERT_USER_SESSION_SQL)
      .bind(
        session.sessionId,
        userId,
        identity.provider,
        session.hashedRefreshToken,
        session.expiresAt,
        createdAt,
      ),
  ]);

  if (results.some((result) => result?.meta.changes !== 1)) {
    throw new Error("Failed to create OAuth user.");
  }

  return { userId, isNewUser: true, migrated: false, session };
}
