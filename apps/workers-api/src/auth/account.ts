import { verifyAccessToken } from "@kando/auth-core";
import type { Hono } from "hono";
import type { Env } from "../env";
import { migrateGuestAssetsToExistingUser } from "./guest-migration";
import { getBearerToken, hasSigningSecret } from "./http-auth";
import { mutationLockKey, runWithMutationLockStatements } from "../db/mutation-lock";

type OwnerType = "anonymous" | "user";

type SessionLookupRow = {
  id: string;
  owner_type: string;
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
  platform: "ios" | "android" | null;
  user_id: string | null;
};

type ValidSessionLookupRow = SessionLookupRow & {
  owner_type: OwnerType;
  platform: "ios" | "android";
};

type AuthenticatedOwner = {
  owner_type: OwnerType;
  owner_id: string;
  user_id: string | null;
  platform: "ios" | "android";
  session_id: string;
};

export type DeletablePlatformOwner = Pick<
  AuthenticatedOwner,
  "owner_type" | "owner_id" | "user_id" | "platform"
>;

type OwnerRow = {
  id: string;
  status: string;
};

type AnonymousAccountForMigrationRow = {
  id: string;
  upgraded_user_id: string | null;
  platform: "ios" | "android";
};

const UNAUTHORIZED_RESPONSE = {
  success: false,
  error: { code: "UNAUTHORIZED", message: "Unauthorized." },
} as const;

const AUTH_REQUIRED_RESPONSE = {
  success: false,
  error: { code: "AUTH_REQUIRED", message: "Auth required." },
} as const;

const NOT_FOUND_RESPONSE = {
  success: false,
  error: { code: "NOT_FOUND", message: "Not found." },
} as const;

const CONFLICT_RESPONSE = {
  success: false,
  error: { code: "CONFLICT", message: "Guest account is no longer available." },
} as const;

const ACCOUNT_ACTION_FAILED_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Unable to complete this action. Please try again later.",
  },
} as const;

const VALIDATION_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "anonymous_id is required.",
  },
} as const;

const SELECT_SESSION_BY_ID_SQL = `
  SELECT id, owner_type, owner_id, expires_at, revoked_at, platform, user_id
  FROM session
  WHERE id = ?
  LIMIT 1
`;

const SELECT_ACCOUNT_ANONYMOUS_OWNER_SQL = `
  SELECT id, status
  FROM anonymous_account
  WHERE id = ? AND status IN ('active', 'deleting', 'deleted')
  LIMIT 1
`;

const SELECT_ACCOUNT_USER_OWNER_SQL = `
  SELECT pa.id, pa.status
  FROM platform_account pa
  JOIN "user" u ON u.id = pa.user_id AND u.status IN ('active', 'deleted')
  WHERE pa.id = ? AND pa.user_id = ? AND pa.platform = ? AND pa.status IN ('active', 'deleting', 'deleted')
  LIMIT 1
`;

const SELECT_ANONYMOUS_ACCOUNT_FOR_MIGRATION_SQL = `
  SELECT id, upgraded_user_id, platform
  FROM anonymous_account
  WHERE id = ?
  LIMIT 1
`;

const MARK_PLATFORM_DELETING_SQL = `UPDATE platform_account
  SET status = 'deleting', updated_at = ?
  WHERE id = ? AND user_id = ? AND platform = ? AND status IN ('active', 'disabled')`;
const MARK_ANONYMOUS_DELETING_SQL = `UPDATE anonymous_account
  SET status = 'deleting'
  WHERE id = ? AND platform = ? AND status = 'active'`;
const SELECT_OWNER_SCAN_IMAGES_SQL = `SELECT image_url FROM scan_record
  WHERE owner_type = ? AND owner_id = ? AND image_url IS NOT NULL`;
const DELETE_OWNER_COLLECTION_EVENTS_SQL = `DELETE FROM collection_item_event WHERE owner_type = ? AND owner_id = ?`;
const DELETE_OWNER_COLLECTION_ITEMS_SQL = `DELETE FROM collection_item WHERE owner_type = ? AND owner_id = ?`;
const DELETE_OWNER_FOLDERS_SQL = `DELETE FROM portfolio_folder WHERE owner_type = ? AND owner_id = ?`;
const DELETE_OWNER_WISHLIST_SQL = `DELETE FROM wishlist_item WHERE owner_type = ? AND owner_id = ?`;
const DELETE_OWNER_PREFERENCE_SQL = `DELETE FROM user_preference WHERE owner_type = ? AND owner_id = ?`;
const DELETE_OWNER_SCAN_QUOTA_SQL = `DELETE FROM scan_quota_request WHERE owner_type = ? AND owner_id = ?`;
const DELETE_OWNER_SCAN_RECORDS_SQL = `DELETE FROM scan_record WHERE owner_type = ? AND owner_id = ?`;
const DELETE_OWNER_ENTITLEMENTS_SQL = `DELETE FROM billing_entitlement_grant WHERE owner_type = ? AND owner_id = ?`;
const DELETE_OWNER_SESSION_ENTITLEMENTS_SQL = `DELETE FROM billing_session_entitlement_grant
  WHERE session_id IN (SELECT id FROM session WHERE owner_type = ? AND owner_id = ?)`;
const DELETE_OWNER_APP_ATTEST_CHALLENGES_SQL = `DELETE FROM billing_apple_app_attest_challenge
  WHERE session_id IN (SELECT id FROM session WHERE owner_type = ? AND owner_id = ?)`;
const DELETE_OWNER_APP_ATTEST_KEYS_SQL = `DELETE FROM billing_apple_app_attest_key
  WHERE registered_session_id IN (SELECT id FROM session WHERE owner_type = ? AND owner_id = ?)`;
const DELETE_OWNER_FEEDBACK_SQL = `DELETE FROM feedback_ticket WHERE uid = ?`;
const DELETE_OWNER_INSTALLATIONS_SQL = `DELETE FROM app_installation WHERE uid = ?`;
const DELETE_RELATED_GUEST_FEEDBACK_SQL = `DELETE FROM feedback_ticket WHERE uid IN (
  SELECT id FROM anonymous_account WHERE upgraded_user_id = ? AND platform = ?
)`;
const DELETE_RELATED_GUEST_INSTALLATIONS_SQL = `DELETE FROM app_installation WHERE uid IN (
  SELECT id FROM anonymous_account WHERE upgraded_user_id = ? AND platform = ?
)`;
const REVOKE_RELATED_GUEST_SESSIONS_SQL = `UPDATE session SET revoked_at = ?
  WHERE owner_type = 'anonymous' AND owner_id IN (
    SELECT id FROM anonymous_account WHERE upgraded_user_id = ? AND platform = ?
  ) AND revoked_at IS NULL`;
const ANONYMIZE_RELATED_GUESTS_SQL = `UPDATE anonymous_account
  SET device_id = 'deleted:' || id, status = 'deleted', deleted_at = ?
  WHERE upgraded_user_id = ? AND platform = ?`;
const MARK_PLATFORM_DELETED_SQL = `UPDATE platform_account
  SET status = 'deleted', deleted_at = ?, updated_at = ?
  WHERE id = ? AND status = 'deleting'`;
const MARK_ANONYMOUS_DELETED_SQL = `UPDATE anonymous_account
  SET device_id = 'deleted:' || id, status = 'deleted', deleted_at = ?
  WHERE id = ? AND status = 'deleting'`;
const DELETE_AUTH_IDENTITIES_IF_LAST_SQL = `DELETE FROM auth_identity
  WHERE user_id = ? AND NOT EXISTS (
    SELECT 1 FROM platform_account WHERE user_id = ? AND status IN ('active', 'disabled', 'deleting')
  )`;
const DELETE_VERIFICATION_CODES_IF_LAST_SQL = `DELETE FROM verification_code
  WHERE email = (SELECT email FROM "user" WHERE id = ?)
    AND NOT EXISTS (
      SELECT 1 FROM platform_account
      WHERE user_id = ? AND status IN ('active', 'disabled', 'deleting')
    )`;
const ANONYMIZE_USER_IF_LAST_SQL = `UPDATE "user"
  SET email = ?, password_hash = NULL, display_name = NULL, status = 'deleted',
      deleted_at = ?, updated_at = ?
  WHERE id = ? AND NOT EXISTS (
    SELECT 1 FROM platform_account WHERE user_id = ? AND status IN ('active', 'disabled', 'deleting')
  )`;

const REVOKE_OWNER_SESSIONS_SQL = `
  UPDATE session
  SET revoked_at = ?
  WHERE owner_type = ? AND owner_id = ? AND revoked_at IS NULL
`;

export function registerAccountRoutes(routes: Hono<{ Bindings: Env }>): void {
  routes.delete("/account", async (c) => {
    const auth = await authenticateOwner(
      c.env.DB,
      c.req.header("Authorization"),
      c.env.JWT_SECRET,
      new Date(),
      true,
    );

    if (auth.status === "internal_error") {
      return c.json(ACCOUNT_ACTION_FAILED_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    try {
      await deletePlatformOwner(c.env, auth.owner, new Date());

      return c.json({ success: true, data: {} });
    } catch (error) {
      console.error("Failed to delete account.", error);
      return c.json(ACCOUNT_ACTION_FAILED_RESPONSE, 500);
    }
  });

  routes.post("/migrate-assets", async (c) => {
    const auth = await authenticateOwner(
      c.env.DB,
      c.req.header("Authorization"),
      c.env.JWT_SECRET,
      new Date(),
    );

    if (auth.status === "internal_error") {
      return c.json(ACCOUNT_ACTION_FAILED_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    if (auth.owner.owner_type === "anonymous") {
      return c.json(AUTH_REQUIRED_RESPONSE, 403);
    }

    const anonymousId = await readAnonymousId(c.req);

    if (!anonymousId) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    try {
      const hasGuestProof = await verifyAnonymousProof(
        c.env.DB,
        anonymousId,
        c.req.header("X-Anonymous-Authorization"),
        c.env.JWT_SECRET,
        new Date(),
      );

      if (!hasGuestProof) {
        return c.json(AUTH_REQUIRED_RESPONSE, 403);
      }

      const anonymousAccount = await c.env.DB.prepare(
        SELECT_ANONYMOUS_ACCOUNT_FOR_MIGRATION_SQL,
      )
        .bind(anonymousId)
        .first<AnonymousAccountForMigrationRow>();

      if (!anonymousAccount) {
        return c.json(NOT_FOUND_RESPONSE, 404);
      }

      if (anonymousAccount.platform !== auth.owner.platform) {
        return c.json(AUTH_REQUIRED_RESPONSE, 403);
      }

      if (anonymousAccount.upgraded_user_id !== null) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      const counts = await migrateGuestAssetsToExistingUser(
        c.env.DB,
        anonymousAccount.id,
        auth.owner.owner_id,
        new Date().toISOString(),
      );

      return c.json({ success: true, data: counts });
    } catch (error) {
      if (
        error instanceof Error &&
        error.message === "Guest account is no longer available."
      ) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      console.error("Failed to migrate guest assets.", error);
      return c.json(ACCOUNT_ACTION_FAILED_RESPONSE, 500);
    }
  });
}

export async function deletePlatformOwner(
  env: Env,
  owner: DeletablePlatformOwner,
  now: Date,
): Promise<void> {
  const nowIso = now.toISOString();
  const lockIdentity = owner.user_id ?? `anonymous:${owner.owner_id}`;
  const markStatement = owner.owner_type === "user"
    ? env.DB.prepare(MARK_PLATFORM_DELETING_SQL).bind(
        nowIso, owner.owner_id, owner.user_id, owner.platform,
      )
    : env.DB.prepare(MARK_ANONYMOUS_DELETING_SQL).bind(
        owner.owner_id, owner.platform,
      );
  const [markResult] = await runWithMutationLockStatements(
    env.DB,
    await mutationLockKey("platform-account-delete", lockIdentity),
    [
      markStatement,
      env.DB.prepare(REVOKE_OWNER_SESSIONS_SQL).bind(
        nowIso, owner.owner_type, owner.owner_id,
      ),
    ],
  );
  if (markResult?.meta.changes !== 1) {
    const row = owner.owner_type === "user"
      ? await env.DB.prepare(`SELECT status FROM platform_account
          WHERE id = ? AND user_id = ? AND platform = ?`)
          .bind(owner.owner_id, owner.user_id, owner.platform)
          .first<{ status: string }>()
      : await env.DB.prepare(`SELECT status FROM anonymous_account
          WHERE id = ? AND platform = ?`)
          .bind(owner.owner_id, owner.platform)
          .first<{ status: string }>();
    if (row?.status !== "deleting" && row?.status !== "deleted") {
      throw new Error("Platform account is not available for deletion.");
    }
  }

  const images = await env.DB.prepare(SELECT_OWNER_SCAN_IMAGES_SQL)
    .bind(owner.owner_type, owner.owner_id)
    .all<{ image_url: string }>();
  if ((images.results?.length ?? 0) > 0 && !env.SCAN_IMAGES) {
    throw new Error("Scan image storage is unavailable during account deletion.");
  }
  if (env.SCAN_IMAGES) {
    const imageKeys = [...new Set(
      (images.results ?? []).map((row) => row.image_url).filter(Boolean),
    )];
    for (let offset = 0; offset < imageKeys.length; offset += 1000) {
      await env.SCAN_IMAGES.delete(imageKeys.slice(offset, offset + 1000));
    }
  }

  const ownerBindings = [owner.owner_type, owner.owner_id] as const;
  const finalStatements = [
    env.DB.prepare(DELETE_OWNER_SESSION_ENTITLEMENTS_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_APP_ATTEST_CHALLENGES_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_APP_ATTEST_KEYS_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_ENTITLEMENTS_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_SCAN_QUOTA_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_COLLECTION_EVENTS_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_COLLECTION_ITEMS_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_WISHLIST_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_PREFERENCE_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_FOLDERS_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_SCAN_RECORDS_SQL).bind(...ownerBindings),
    env.DB.prepare(DELETE_OWNER_FEEDBACK_SQL).bind(owner.owner_id),
    env.DB.prepare(DELETE_OWNER_INSTALLATIONS_SQL).bind(owner.owner_id),
  ];
  if (owner.owner_type === "user") {
    if (!owner.user_id) throw new Error("User platform deletion requires a base user.");
    const userId = owner.user_id;
    finalStatements.push(
      env.DB.prepare(DELETE_RELATED_GUEST_FEEDBACK_SQL).bind(
        owner.owner_id, owner.platform,
      ),
      env.DB.prepare(DELETE_RELATED_GUEST_INSTALLATIONS_SQL).bind(
        owner.owner_id, owner.platform,
      ),
      env.DB.prepare(REVOKE_RELATED_GUEST_SESSIONS_SQL).bind(
        nowIso, owner.owner_id, owner.platform,
      ),
      env.DB.prepare(ANONYMIZE_RELATED_GUESTS_SQL).bind(
        nowIso, owner.owner_id, owner.platform,
      ),
      env.DB.prepare(MARK_PLATFORM_DELETED_SQL).bind(nowIso, nowIso, owner.owner_id),
      env.DB.prepare(DELETE_VERIFICATION_CODES_IF_LAST_SQL).bind(userId, userId),
      env.DB.prepare(DELETE_AUTH_IDENTITIES_IF_LAST_SQL).bind(userId, userId),
      env.DB.prepare(ANONYMIZE_USER_IF_LAST_SQL).bind(
        `deleted+${userId}@invalid.cardai.local`, nowIso, nowIso, userId, userId,
      ),
    );
  } else {
    finalStatements.push(env.DB.prepare(MARK_ANONYMOUS_DELETED_SQL).bind(
      nowIso, owner.owner_id,
    ));
  }
  await runWithMutationLockStatements(
    env.DB,
    await mutationLockKey("platform-account-delete", lockIdentity),
    finalStatements,
  );
}

async function authenticateOwner(
  db: D1Database,
  authorization: string | undefined,
  jwtSecret: unknown,
  now: Date,
  allowDeleting = false,
): Promise<
  | { status: "ok"; owner: AuthenticatedOwner }
  | { status: "unauthorized" }
  | { status: "internal_error" }
> {
  const token = getBearerToken(authorization);

  if (!token) {
    return { status: "unauthorized" };
  }

  if (!hasSigningSecret(jwtSecret)) {
    return { status: "internal_error" };
  }

  const verification = await verifyAccessToken(token, jwtSecret);

  if (!verification.valid) {
    return { status: "unauthorized" };
  }

  const session = await db
    .prepare(SELECT_SESSION_BY_ID_SQL)
    .bind(verification.payload.session_id)
    .first<SessionLookupRow>();

  if (
    !isUnexpiredSession(session, now) ||
    session.owner_type !== verification.payload.owner_type ||
    session.owner_id !== verification.payload.owner_id
  ) {
    return { status: "unauthorized" };
  }

  const owner = await findOwner(db, session);

  if (!owner) {
    return { status: "unauthorized" };
  }
  if (session.revoked_at !== null &&
      (!allowDeleting || (owner.status !== "deleting" && owner.status !== "deleted"))) {
    return { status: "unauthorized" };
  }

  return {
    status: "ok",
    owner: {
      owner_type: session.owner_type,
      owner_id: session.owner_id,
      user_id: session.user_id,
      platform: session.platform!,
      session_id: session.id,
    },
  };
}

async function findOwner(
  db: D1Database,
  session: ValidSessionLookupRow,
): Promise<OwnerRow | null> {
  const sql =
    session.owner_type === "anonymous"
      ? SELECT_ACCOUNT_ANONYMOUS_OWNER_SQL
      : SELECT_ACCOUNT_USER_OWNER_SQL;

  return session.owner_type === "anonymous"
    ? db.prepare(sql).bind(session.owner_id).first<OwnerRow>()
    : db.prepare(sql).bind(
        session.owner_id, session.user_id, session.platform,
      ).first<OwnerRow>();
}

async function verifyAnonymousProof(
  db: D1Database,
  anonymousId: string,
  authorization: string | undefined,
  jwtSecret: string,
  now: Date,
): Promise<boolean> {
  const token = getBearerToken(authorization);

  if (!token) {
    return false;
  }

  const verification = await verifyAccessToken(token, jwtSecret);

  if (
    !verification.valid ||
    verification.payload.owner_type !== "anonymous" ||
    verification.payload.owner_id !== anonymousId
  ) {
    return false;
  }

  const session = await db
    .prepare(SELECT_SESSION_BY_ID_SQL)
    .bind(verification.payload.session_id)
    .first<SessionLookupRow>();

  return (
    isLiveSession(session, now) &&
    session.owner_type === "anonymous" &&
    session.owner_id === anonymousId
  );
}

async function readAnonymousId(request: {
  json(): Promise<unknown>;
}): Promise<string | null> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return null;
  }

  const rawAnonymousId =
    body && typeof body === "object"
      ? (body as { anonymous_id?: unknown }).anonymous_id
      : undefined;

  if (typeof rawAnonymousId !== "string") {
    return null;
  }

  const anonymousId = rawAnonymousId.trim();

  return anonymousId.length > 0 ? anonymousId : null;
}

function isLiveSession(
  session: SessionLookupRow | null,
  now: Date,
): session is ValidSessionLookupRow {
  return (
    isUnexpiredSession(session, now) &&
    session.revoked_at === null
  );
}

function isUnexpiredSession(
  session: SessionLookupRow | null,
  now: Date,
): session is ValidSessionLookupRow {
  const expiresAt = session ? Date.parse(session.expires_at) : NaN;
  return (
    !!session &&
    (session.owner_type === "anonymous" || session.owner_type === "user") &&
    (session.platform === "ios" || session.platform === "android") &&
    (session.owner_type === "anonymous" || typeof session.user_id === "string") &&
    Number.isFinite(expiresAt) &&
    expiresAt > now.getTime()
  );
}
