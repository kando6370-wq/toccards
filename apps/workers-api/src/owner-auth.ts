import { verifyAccessToken } from "@kando/auth-core";
import type { Env } from "./env";
import { getBearerToken, hasSigningSecret } from "./auth/http-auth";

export type OwnerType = "anonymous" | "user";

export type AuthenticatedOwner = {
  owner_type: OwnerType;
  owner_id: string;
};

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

type OwnerRow = {
  id: string;
};

const SELECT_SESSION_BY_ID_SQL = `
SELECT id, owner_type, owner_id, expires_at, revoked_at
FROM session
WHERE id = ?
LIMIT 1
`;

const SELECT_ANONYMOUS_OWNER_SQL = `
SELECT id
FROM anonymous_account
WHERE id = ? AND upgraded_user_id IS NULL
LIMIT 1
`;

const SELECT_USER_OWNER_SQL = `
SELECT id
FROM user
WHERE id = ? AND status = 'active'
LIMIT 1
`;

export async function authenticateOwner(
  env: Pick<Env, "DB" | "JWT_SECRET">,
  authorization: string | undefined,
  now = new Date(),
): Promise<
  | { status: "ok"; owner: AuthenticatedOwner }
  | { status: "unauthorized" }
  | { status: "internal_error" }
> {
  const token = getBearerToken(authorization);

  if (!token) {
    return { status: "unauthorized" };
  }

  if (!hasSigningSecret(env.JWT_SECRET)) {
    return { status: "internal_error" };
  }

  const verification = await verifyAccessToken(token, env.JWT_SECRET, now);

  if (!verification.valid) {
    return { status: "unauthorized" };
  }

  const session = await env.DB.prepare(SELECT_SESSION_BY_ID_SQL)
    .bind(verification.payload.session_id)
    .first<SessionLookupRow>();

  if (
    !isLiveSession(session, now) ||
    session.owner_type !== verification.payload.owner_type ||
    session.owner_id !== verification.payload.owner_id
  ) {
    return { status: "unauthorized" };
  }

  const owner = await findOwner(env.DB, session);

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
      ? SELECT_ANONYMOUS_OWNER_SQL
      : SELECT_USER_OWNER_SQL;

  return db.prepare(sql).bind(session.owner_id).first<OwnerRow>();
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
