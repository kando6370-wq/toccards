import { verifyAccessToken } from "@kando/auth-core";
import type { Env } from "./env";
import { getBearerToken, hasSigningSecret } from "./auth/http-auth";

export type OwnerType = "anonymous" | "user";

export type AuthenticatedOwner = {
  owner_type: OwnerType;
  owner_id: string;
  session_id: string;
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

const SELECT_ANONYMOUS_SESSION_BY_ID_SQL = `
SELECT session_record.id, session_record.owner_type, session_record.owner_id,
       session_record.expires_at, session_record.revoked_at
FROM session AS session_record
INNER JOIN anonymous_account AS owner_record
  ON owner_record.id = session_record.owner_id
 AND owner_record.upgraded_user_id IS NULL
WHERE session_record.id = ?
  AND session_record.owner_type = 'anonymous'
LIMIT 1
`;

const SELECT_USER_SESSION_BY_ID_SQL = `
SELECT session_record.id, session_record.owner_type, session_record.owner_id,
       session_record.expires_at, session_record.revoked_at
FROM session AS session_record
INNER JOIN "user" AS owner_record
  ON owner_record.id = session_record.owner_id
 AND owner_record.status = 'active'
WHERE session_record.id = ?
  AND session_record.owner_type = 'user'
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

  const sessionSql = verification.payload.owner_type === "anonymous"
    ? SELECT_ANONYMOUS_SESSION_BY_ID_SQL
    : SELECT_USER_SESSION_BY_ID_SQL;
  const session = await env.DB.prepare(sessionSql)
    .bind(verification.payload.session_id)
    .first<SessionLookupRow>();

  if (
    !isLiveSession(session, now) ||
    session.owner_type !== verification.payload.owner_type ||
    session.owner_id !== verification.payload.owner_id
  ) {
    return { status: "unauthorized" };
  }

  return {
    status: "ok",
    owner: {
      owner_type: session.owner_type,
      owner_id: session.owner_id,
      session_id: session.id,
    },
  };
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
