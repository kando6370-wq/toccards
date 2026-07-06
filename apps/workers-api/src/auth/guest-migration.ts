import { verifyAccessToken } from "@kando/auth-core";
import { getBearerToken } from "./http-auth";

export type AnonymousAccountRow = { id: string };
export type SessionLookupRow = {
  id: string;
  owner_type: string;
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};
export type MigrationCounts = {
  migrated_folders: number;
  migrated_items: number;
  migrated_wishlist: number;
};

export type GuestMigrationGuard = {
  verificationCodeId?: string;
  verificationUsedAt?: string;
};

export type GuestMigrationStatements = {
  upgradeAccount: D1PreparedStatement;
  portfolioFolders: D1PreparedStatement;
  collectionItems: D1PreparedStatement;
  wishlistItems: D1PreparedStatement;
  userPreference: D1PreparedStatement;
};

type CompleteGuestMigrationGuard = Required<GuestMigrationGuard>;

const GUEST_ACCOUNT_UNAVAILABLE_MESSAGE = "Guest account is no longer available.";

const SELECT_LIVE_ANONYMOUS_ACCOUNT_SQL = `
  SELECT id
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`;

const SELECT_SESSION_BY_ID_SQL = `
  SELECT id, owner_type, owner_id, expires_at, revoked_at
  FROM session
  WHERE id = ?
  LIMIT 1
`;

const UPDATE_ANONYMOUS_PORTFOLIO_FOLDERS_SQL = `
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
`;

const UPDATE_ANONYMOUS_COLLECTION_ITEMS_SQL = `
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
`;

const UPDATE_ANONYMOUS_WISHLIST_ITEMS_SQL = `
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
`;

const UPDATE_ANONYMOUS_USER_PREFERENCE_SQL = `
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
`;

const UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_SQL = `
  UPDATE anonymous_account
  SET upgraded_user_id = ?
  WHERE id = ? AND upgraded_user_id IS NULL
    AND EXISTS (
      SELECT 1
      FROM verification_code
      WHERE id = ? AND used_at = ?
    )
`;

const UPDATE_ANONYMOUS_PORTFOLIO_FOLDERS_UNGUARDED_SQL = `
  UPDATE portfolio_folder
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`;

const UPDATE_ANONYMOUS_COLLECTION_ITEMS_UNGUARDED_SQL = `
  UPDATE collection_item
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`;

const UPDATE_ANONYMOUS_WISHLIST_ITEMS_UNGUARDED_SQL = `
  UPDATE wishlist_item
  SET owner_type = 'user', owner_id = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`;

const UPDATE_ANONYMOUS_USER_PREFERENCE_UNGUARDED_SQL = `
  UPDATE user_preference
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`;

const UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_UNGUARDED_SQL = `
  UPDATE anonymous_account
  SET upgraded_user_id = ?
  WHERE id = ? AND upgraded_user_id IS NULL
`;

export async function findVerifiedAnonymousAccount(
  db: D1Database,
  anonymousId: string | null,
  authorization: string | undefined,
  jwtSecret: string,
  now: Date,
): Promise<AnonymousAccountRow | null> {
  if (!anonymousId) {
    return null;
  }

  const token = getBearerToken(authorization);

  if (!token) {
    return null;
  }

  const verification = await verifyAccessToken(token, jwtSecret);

  if (
    !verification.valid ||
    verification.payload.owner_type !== "anonymous" ||
    verification.payload.owner_id !== anonymousId
  ) {
    return null;
  }

  const session = await db
    .prepare(SELECT_SESSION_BY_ID_SQL)
    .bind(verification.payload.session_id)
    .first<SessionLookupRow>();

  if (!isLiveAnonymousSession(session, anonymousId, now)) {
    return null;
  }

  return db
    .prepare(SELECT_LIVE_ANONYMOUS_ACCOUNT_SQL)
    .bind(anonymousId)
    .first<AnonymousAccountRow>();
}

export async function migrateGuestAssetsToUser(
  db: D1Database,
  anonymousId: string,
  userId: string,
  updatedAt: string,
  guard: GuestMigrationGuard,
): Promise<MigrationCounts> {
  const statements = createGuestMigrationStatements(
    db,
    anonymousId,
    userId,
    updatedAt,
    guard,
  );

  const results = await db.batch([
    statements.upgradeAccount,
    statements.portfolioFolders,
    statements.collectionItems,
    statements.wishlistItems,
    statements.userPreference,
  ]);

  return readMigrationCounts(results);
}

export function createGuestMigrationStatements(
  db: D1Database,
  anonymousId: string,
  userId: string,
  updatedAt: string,
  guard: GuestMigrationGuard,
): GuestMigrationStatements {
  const verificationGuard = resolveVerificationGuard(guard);

  if (verificationGuard) {
    return {
      upgradeAccount: db
        .prepare(UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_SQL)
        .bind(
          userId,
          anonymousId,
          verificationGuard.verificationCodeId,
          verificationGuard.verificationUsedAt,
        ),
      portfolioFolders: db
        .prepare(UPDATE_ANONYMOUS_PORTFOLIO_FOLDERS_SQL)
        .bind(
          userId,
          updatedAt,
          anonymousId,
          verificationGuard.verificationCodeId,
          verificationGuard.verificationUsedAt,
          anonymousId,
          userId,
        ),
      collectionItems: db
        .prepare(UPDATE_ANONYMOUS_COLLECTION_ITEMS_SQL)
        .bind(
          userId,
          updatedAt,
          anonymousId,
          verificationGuard.verificationCodeId,
          verificationGuard.verificationUsedAt,
          anonymousId,
          userId,
        ),
      wishlistItems: db
        .prepare(UPDATE_ANONYMOUS_WISHLIST_ITEMS_SQL)
        .bind(
          userId,
          anonymousId,
          verificationGuard.verificationCodeId,
          verificationGuard.verificationUsedAt,
          anonymousId,
          userId,
        ),
      userPreference: db
        .prepare(UPDATE_ANONYMOUS_USER_PREFERENCE_SQL)
        .bind(
          userId,
          updatedAt,
          anonymousId,
          verificationGuard.verificationCodeId,
          verificationGuard.verificationUsedAt,
          anonymousId,
          userId,
        ),
    };
  }

  return {
    upgradeAccount: db
      .prepare(UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_UNGUARDED_SQL)
      .bind(userId, anonymousId),
    portfolioFolders: db
      .prepare(UPDATE_ANONYMOUS_PORTFOLIO_FOLDERS_UNGUARDED_SQL)
      .bind(userId, updatedAt, anonymousId, anonymousId, userId),
    collectionItems: db
      .prepare(UPDATE_ANONYMOUS_COLLECTION_ITEMS_UNGUARDED_SQL)
      .bind(userId, updatedAt, anonymousId, anonymousId, userId),
    wishlistItems: db
      .prepare(UPDATE_ANONYMOUS_WISHLIST_ITEMS_UNGUARDED_SQL)
      .bind(userId, anonymousId, anonymousId, userId),
    userPreference: db
      .prepare(UPDATE_ANONYMOUS_USER_PREFERENCE_UNGUARDED_SQL)
      .bind(userId, updatedAt, anonymousId, anonymousId, userId),
  };
}

function readMigrationCounts(results: D1Result[]): MigrationCounts {
  if (results[0]?.meta.changes !== 1) {
    throw new Error(GUEST_ACCOUNT_UNAVAILABLE_MESSAGE);
  }

  return {
    migrated_folders: results[1]?.meta.changes ?? 0,
    migrated_items: results[2]?.meta.changes ?? 0,
    migrated_wishlist: results[3]?.meta.changes ?? 0,
  };
}

function resolveVerificationGuard(
  guard: GuestMigrationGuard,
): CompleteGuestMigrationGuard | null {
  const hasCodeId = typeof guard.verificationCodeId === "string";
  const hasUsedAt = typeof guard.verificationUsedAt === "string";

  if (!hasCodeId && !hasUsedAt) {
    return null;
  }

  if (hasCodeId && hasUsedAt) {
    return {
      verificationCodeId: guard.verificationCodeId as string,
      verificationUsedAt: guard.verificationUsedAt as string,
    };
  }

  throw new Error("Incomplete guest migration guard.");
}

function isLiveAnonymousSession(
  session: SessionLookupRow | null,
  anonymousId: string,
  now: Date,
): boolean {
  const expiresAt = session ? Date.parse(session.expires_at) : NaN;

  return (
    !!session &&
    session.owner_type === "anonymous" &&
    session.owner_id === anonymousId &&
    session.revoked_at === null &&
    Number.isFinite(expiresAt) &&
    expiresAt > now.getTime()
  );
}
