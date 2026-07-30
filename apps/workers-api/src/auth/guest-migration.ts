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
  collectionItemEvents: D1PreparedStatement;
  wishlistItems: D1PreparedStatement;
  userPreference: D1PreparedStatement;
  scanRecords: D1PreparedStatement;
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

const UPDATE_ANONYMOUS_COLLECTION_ITEM_EVENTS_SQL = `
  UPDATE collection_item_event
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

const UPDATE_ANONYMOUS_SCAN_RECORDS_SQL = `
  UPDATE scan_record
  SET owner_type = 'user', owner_id = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1 FROM verification_code
      WHERE id = ? AND used_at = ?
    )
    AND EXISTS (
      SELECT 1 FROM anonymous_account
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

const UPDATE_ANONYMOUS_COLLECTION_ITEM_EVENTS_UNGUARDED_SQL = `
  UPDATE collection_item_event
  SET owner_type = 'user', owner_id = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`;

const UPDATE_ANONYMOUS_SCAN_RECORDS_UNGUARDED_SQL = `
  UPDATE scan_record
  SET owner_type = 'user', owner_id = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1 FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`;

const UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_UNGUARDED_SQL = `
  UPDATE anonymous_account
  SET upgraded_user_id = ?
  WHERE id = ? AND upgraded_user_id IS NULL
`;

const REMAP_CONFLICTING_COLLECTION_ITEMS_TO_USER_FOLDER_SQL = `
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
`;

const UPDATE_EXISTING_USER_COLLECTION_ITEM_EVENTS_SQL = `
  UPDATE collection_item_event
  SET folder_id = COALESCE((
    SELECT target.id
    FROM portfolio_folder source
    JOIN portfolio_folder target
      ON target.owner_type = 'user'
      AND target.owner_id = ?
      AND target.name = source.name
    WHERE source.id = collection_item_event.folder_id
      AND source.owner_type = 'anonymous'
      AND source.owner_id = ?
    LIMIT 1
  ), folder_id), owner_type = 'user', owner_id = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
    )
`;

const DELETE_CONFLICTING_ANONYMOUS_PORTFOLIO_FOLDERS_SQL = `
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
`;

const REMAP_ANONYMOUS_USER_PREFERENCE_FOLDER_SQL = `
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
`;

const UPDATE_NON_CONFLICTING_ANONYMOUS_PORTFOLIO_FOLDERS_SQL = `
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
`;

const DELETE_CONFLICTING_ANONYMOUS_WISHLIST_ITEMS_SQL = `
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
`;

const UPDATE_NON_CONFLICTING_ANONYMOUS_WISHLIST_ITEMS_SQL = `
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
`;

const DELETE_CONFLICTING_ANONYMOUS_USER_PREFERENCE_SQL = `
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
`;

const UPDATE_NON_CONFLICTING_ANONYMOUS_USER_PREFERENCE_SQL = `
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
    statements.collectionItemEvents,
    statements.wishlistItems,
    statements.userPreference,
    statements.scanRecords,
  ]);

  return readMigrationCounts(results);
}

export async function migrateGuestAssetsToExistingUser(
  db: D1Database,
  anonymousId: string,
  userId: string,
  updatedAt: string,
): Promise<MigrationCounts> {
  const results = await db.batch([
    db
      .prepare(UPDATE_ANONYMOUS_ACCOUNT_UPGRADED_UNGUARDED_SQL)
      .bind(userId, anonymousId),
    db
      .prepare(REMAP_CONFLICTING_COLLECTION_ITEMS_TO_USER_FOLDER_SQL)
      .bind(
        userId,
        anonymousId,
        updatedAt,
        anonymousId,
        userId,
        anonymousId,
        anonymousId,
        userId,
      ),
    db
      .prepare(UPDATE_EXISTING_USER_COLLECTION_ITEM_EVENTS_SQL)
      .bind(userId, anonymousId, userId, anonymousId, anonymousId, userId),
    db
      .prepare(REMAP_ANONYMOUS_USER_PREFERENCE_FOLDER_SQL)
      .bind(
        userId,
        anonymousId,
        updatedAt,
        anonymousId,
        userId,
        anonymousId,
        anonymousId,
        userId,
      ),
    db
      .prepare(DELETE_CONFLICTING_ANONYMOUS_PORTFOLIO_FOLDERS_SQL)
      .bind(anonymousId, userId, anonymousId, userId),
    db
      .prepare(UPDATE_NON_CONFLICTING_ANONYMOUS_PORTFOLIO_FOLDERS_SQL)
      .bind(userId, updatedAt, anonymousId, userId, anonymousId, userId),
    db
      .prepare(UPDATE_ANONYMOUS_COLLECTION_ITEMS_UNGUARDED_SQL)
      .bind(userId, updatedAt, anonymousId, anonymousId, userId),
    db
      .prepare(DELETE_CONFLICTING_ANONYMOUS_WISHLIST_ITEMS_SQL)
      .bind(anonymousId, userId, anonymousId, userId),
    db
      .prepare(UPDATE_NON_CONFLICTING_ANONYMOUS_WISHLIST_ITEMS_SQL)
      .bind(userId, anonymousId, userId, anonymousId, userId),
    db
      .prepare(DELETE_CONFLICTING_ANONYMOUS_USER_PREFERENCE_SQL)
      .bind(anonymousId, userId, anonymousId, userId),
    db
      .prepare(UPDATE_NON_CONFLICTING_ANONYMOUS_USER_PREFERENCE_SQL)
      .bind(userId, updatedAt, anonymousId, userId, anonymousId, userId),
    db
      .prepare(UPDATE_ANONYMOUS_SCAN_RECORDS_UNGUARDED_SQL)
      .bind(userId, anonymousId, anonymousId, userId),
  ]);

  if (results[0]?.meta.changes !== 1) {
    throw new Error(GUEST_ACCOUNT_UNAVAILABLE_MESSAGE);
  }

  return {
    migrated_folders:
      (results[4]?.meta.changes ?? 0) + (results[5]?.meta.changes ?? 0),
    migrated_items: results[6]?.meta.changes ?? 0,
    migrated_wishlist: results[8]?.meta.changes ?? 0,
  };
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
      scanRecords: db
        .prepare(UPDATE_ANONYMOUS_SCAN_RECORDS_SQL)
        .bind(
          userId,
          anonymousId,
          verificationGuard.verificationCodeId,
          verificationGuard.verificationUsedAt,
          anonymousId,
          userId,
        ),
      collectionItemEvents: db
        .prepare(UPDATE_ANONYMOUS_COLLECTION_ITEM_EVENTS_SQL)
        .bind(
          userId,
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
    collectionItemEvents: db
      .prepare(UPDATE_ANONYMOUS_COLLECTION_ITEM_EVENTS_UNGUARDED_SQL)
      .bind(userId, anonymousId, anonymousId, userId),
    wishlistItems: db
      .prepare(UPDATE_ANONYMOUS_WISHLIST_ITEMS_UNGUARDED_SQL)
      .bind(userId, anonymousId, anonymousId, userId),
    userPreference: db
      .prepare(UPDATE_ANONYMOUS_USER_PREFERENCE_UNGUARDED_SQL)
      .bind(userId, updatedAt, anonymousId, anonymousId, userId),
    scanRecords: db
      .prepare(UPDATE_ANONYMOUS_SCAN_RECORDS_UNGUARDED_SQL)
      .bind(userId, anonymousId, anonymousId, userId),
  };
}

function readMigrationCounts(results: D1Result[]): MigrationCounts {
  if (results[0]?.meta.changes !== 1) {
    throw new Error(GUEST_ACCOUNT_UNAVAILABLE_MESSAGE);
  }

  return {
    migrated_folders: results[1]?.meta.changes ?? 0,
    migrated_items: results[2]?.meta.changes ?? 0,
    migrated_wishlist: results[4]?.meta.changes ?? 0,
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
