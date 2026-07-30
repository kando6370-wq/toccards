import { verifyAccessToken } from "@kando/auth-core";
import type { Hono } from "hono";
import type { Env } from "../env";
import { migrateGuestAssetsToExistingUser } from "./guest-migration";
import { getBearerToken, hasSigningSecret } from "./http-auth";

type OwnerType = "anonymous" | "user";

type SessionLookupRow = {
  id: string;
  owner_type: string;
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

type ValidSessionLookupRow = SessionLookupRow & {
  owner_type: OwnerType;
};

type AuthenticatedOwner = {
  owner_type: OwnerType;
  owner_id: string;
};

type OwnerRow = {
  id: string;
};

type AnonymousAccountForMigrationRow = {
  id: string;
  upgraded_user_id: string | null;
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
  SELECT id, owner_type, owner_id, expires_at, revoked_at
  FROM session
  WHERE id = ?
  LIMIT 1
`;

const SELECT_ACCOUNT_ANONYMOUS_OWNER_SQL = `
  SELECT id
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`;

const SELECT_ACCOUNT_USER_OWNER_SQL = `
  SELECT id
  FROM user
  WHERE id = ? AND status = 'active'
  LIMIT 1
`;

const SELECT_ANONYMOUS_ACCOUNT_FOR_MIGRATION_SQL = `
  SELECT id, upgraded_user_id
  FROM anonymous_account
  WHERE id = ?
  LIMIT 1
`;

const UPDATE_USER_DELETED_SQL = `
  UPDATE user
  SET status = 'deleted', deleted_at = ?, updated_at = ?
  WHERE id = ? AND status = 'active'
`;

const REVOKE_OWNER_SESSIONS_SQL = `
  UPDATE session
  SET revoked_at = ?
  WHERE owner_type = ? AND owner_id = ? AND revoked_at IS NULL
`;

const DELETE_ANONYMOUS_PORTFOLIO_FOLDERS_SQL = `
  DELETE FROM portfolio_folder
  WHERE owner_type = 'anonymous' AND owner_id = ?
`;

const DELETE_ANONYMOUS_COLLECTION_ITEMS_SQL = `
  DELETE FROM collection_item
  WHERE owner_type = 'anonymous' AND owner_id = ?
`;

const DELETE_ANONYMOUS_COLLECTION_ITEM_EVENTS_SQL = `
  DELETE FROM collection_item_event
  WHERE owner_type = 'anonymous' AND owner_id = ?
`;

const DELETE_ANONYMOUS_WISHLIST_ITEMS_SQL = `
  DELETE FROM wishlist_item
  WHERE owner_type = 'anonymous' AND owner_id = ?
`;

const DELETE_ANONYMOUS_USER_PREFERENCE_SQL = `
  DELETE FROM user_preference
  WHERE owner_type = 'anonymous' AND owner_id = ?
`;

const INVALIDATE_ANONYMOUS_ACCOUNT_SQL = `
  UPDATE anonymous_account
  SET upgraded_user_id = ?
  WHERE id = ? AND upgraded_user_id IS NULL
`;

export function registerAccountRoutes(routes: Hono<{ Bindings: Env }>): void {
  routes.delete("/account", async (c) => {
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

    try {
      const nowIso = new Date().toISOString();
      if (auth.owner.owner_type === "user") {
        await c.env.DB.batch([
          c.env.DB.prepare(UPDATE_USER_DELETED_SQL).bind(
            nowIso,
            nowIso,
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(REVOKE_OWNER_SESSIONS_SQL).bind(
            nowIso,
            "user",
            auth.owner.owner_id,
          ),
        ]);
      } else {
        await c.env.DB.batch([
          c.env.DB.prepare(DELETE_ANONYMOUS_PORTFOLIO_FOLDERS_SQL).bind(
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(DELETE_ANONYMOUS_COLLECTION_ITEMS_SQL).bind(
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(DELETE_ANONYMOUS_COLLECTION_ITEM_EVENTS_SQL).bind(
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(DELETE_ANONYMOUS_WISHLIST_ITEMS_SQL).bind(
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(DELETE_ANONYMOUS_USER_PREFERENCE_SQL).bind(
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(INVALIDATE_ANONYMOUS_ACCOUNT_SQL).bind(
            auth.owner.owner_id,
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(REVOKE_OWNER_SESSIONS_SQL).bind(
            nowIso,
            "anonymous",
            auth.owner.owner_id,
          ),
        ]);
      }

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

async function authenticateOwner(
  db: D1Database,
  authorization: string | undefined,
  jwtSecret: unknown,
  now: Date,
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
    !isLiveSession(session, now) ||
    session.owner_type !== verification.payload.owner_type ||
    session.owner_id !== verification.payload.owner_id
  ) {
    return { status: "unauthorized" };
  }

  const owner = await findOwner(db, session);

  if (!owner) {
    return { status: "unauthorized" };
  }

  return {
    status: "ok",
    owner: { owner_type: session.owner_type, owner_id: session.owner_id },
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

  return db.prepare(sql).bind(session.owner_id).first<OwnerRow>();
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
  const expiresAt = session ? Date.parse(session.expires_at) : NaN;

  return (
    !!session &&
    (session.owner_type === "anonymous" || session.owner_type === "user") &&
    session.revoked_at === null &&
    Number.isFinite(expiresAt) &&
    expiresAt > now.getTime()
  );
}
