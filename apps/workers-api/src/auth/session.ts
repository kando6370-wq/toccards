import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  hashRefreshToken,
  signAccessToken,
  verifyAccessToken,
} from "@kando/auth-core";
import type { Hono } from "hono";
import type { Env } from "../env";

type SessionLookupRow = {
  id: string;
  owner_type: string;
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

type OwnerType = "anonymous" | "user";

type ValidSessionLookupRow = SessionLookupRow & {
  owner_type: OwnerType;
};

type OwnerRow = {
  id: string;
};

const VALIDATION_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "refresh_token is required.",
  },
} as const;

const UNAUTHORIZED_RESPONSE = {
  success: false,
  error: {
    code: "UNAUTHORIZED",
    message: "Unauthorized.",
  },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const SELECT_SESSION_BY_REFRESH_TOKEN_SQL = `
  SELECT id, owner_type, owner_id, expires_at, revoked_at
  FROM session
  WHERE refresh_token = ?
  LIMIT 1
`;

const SELECT_REFRESH_ANONYMOUS_OWNER_SQL = `
  SELECT id
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`;

const SELECT_REFRESH_USER_OWNER_SQL = `
  SELECT id
  FROM user
  WHERE id = ? AND deleted_at IS NULL
  LIMIT 1
`;

const REVOKE_SESSION_SQL = `
  UPDATE session
  SET revoked_at = ?
  WHERE id = ? AND revoked_at IS NULL
`;

export function registerSessionRoutes(routes: Hono<{ Bindings: Env }>): void {
  routes.post("/token/refresh", async (c) => {
    const refreshToken = await readRefreshToken(c.req);

    if (!refreshToken) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    if (
      !(
        typeof c.env.JWT_SECRET === "string" &&
        c.env.JWT_SECRET.trim().length > 0
      )
    ) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    const session = await findLiveSession(c.env.DB, refreshToken, new Date());

    if (!session) {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const owner = await findOwner(c.env.DB, session);

    if (!owner) {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const now = new Date();
    const accessToken = await signAccessToken(
      {
        owner_type: session.owner_type,
        owner_id: session.owner_id,
        session_id: session.id,
      },
      c.env.JWT_SECRET,
      now,
    );

    return c.json({
      success: true,
      data: {
        access_token: accessToken,
        expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
      },
    });
  });

  routes.post("/logout", async (c) => {
    const token = getBearerToken(c.req.header("Authorization"));

    if (!token) {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    if (
      !(
        typeof c.env.JWT_SECRET === "string" &&
        c.env.JWT_SECRET.trim().length > 0
      )
    ) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    const verification = await verifyAccessToken(token, c.env.JWT_SECRET);

    if (!verification.valid) {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const refreshToken = await readRefreshToken(c.req);

    if (!refreshToken) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const now = new Date();
    const session = await findLiveSession(c.env.DB, refreshToken, now);

    if (
      !session ||
      session.id !== verification.payload.session_id ||
      session.owner_type !== verification.payload.owner_type ||
      session.owner_id !== verification.payload.owner_id
    ) {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    await c.env.DB.prepare(REVOKE_SESSION_SQL)
      .bind(now.toISOString(), session.id)
      .run();

    return c.json({ success: true, data: {} });
  });
}

async function readRefreshToken(request: {
  json(): Promise<unknown>;
}): Promise<string | null> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return null;
  }

  const rawRefreshToken =
    body && typeof body === "object"
      ? (body as { refresh_token?: unknown }).refresh_token
      : undefined;

  if (typeof rawRefreshToken !== "string") {
    return null;
  }

  const refreshToken = rawRefreshToken.trim();

  return refreshToken.length > 0 ? refreshToken : null;
}

async function findLiveSession(
  db: D1Database,
  refreshToken: string,
  now: Date,
): Promise<ValidSessionLookupRow | null> {
  const hashedRefreshToken = await hashRefreshToken(refreshToken);
  const session = await db
    .prepare(SELECT_SESSION_BY_REFRESH_TOKEN_SQL)
    .bind(hashedRefreshToken)
    .first<SessionLookupRow>();
  const expiresAt = session ? Date.parse(session.expires_at) : NaN;

  if (
    !session ||
    !hasSupportedOwnerType(session) ||
    session.revoked_at !== null ||
    !Number.isFinite(expiresAt) ||
    expiresAt <= now.getTime()
  ) {
    return null;
  }

  return session;
}

async function findOwner(
  db: D1Database,
  session: ValidSessionLookupRow,
): Promise<OwnerRow | null> {
  const sql =
    session.owner_type === "anonymous"
      ? SELECT_REFRESH_ANONYMOUS_OWNER_SQL
      : SELECT_REFRESH_USER_OWNER_SQL;

  return db.prepare(sql).bind(session.owner_id).first<OwnerRow>();
}

function getBearerToken(authorization: string | undefined): string | null {
  if (!authorization) {
    return null;
  }

  const [scheme, token, extra] = authorization.trim().split(/\s+/);

  if (scheme !== "Bearer" || !token || extra) {
    return null;
  }

  return token;
}

function hasSupportedOwnerType(
  session: SessionLookupRow,
): session is ValidSessionLookupRow {
  return session.owner_type === "anonymous" || session.owner_type === "user";
}
