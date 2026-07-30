import { verifyAccessToken } from "@kando/auth-core";
import type { Hono } from "hono";
import type { Env } from "../env";

type AnonymousAccountRow = {
  id: string;
  created_at: string;
};

type UserRow = {
  id: string;
  email: string;
  display_name: string | null;
  created_at: string;
};

type SessionLookupRow = {
  id: string;
  owner_type: string;
  owner_id: string;
  login_method: string | null;
  expires_at: string;
  revoked_at: string | null;
};

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

const SELECT_CURRENT_ANONYMOUS_ACCOUNT_SQL = `
  SELECT id, created_at
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`;

const SELECT_CURRENT_USER_SQL = `
  SELECT id, email, display_name, created_at
  FROM user
  WHERE id = ? AND status = 'active'
  LIMIT 1
`;

const SELECT_CURRENT_SESSION_SQL = `
  SELECT id, owner_type, owner_id, login_method, expires_at, revoked_at
  FROM session
  WHERE id = ?
  LIMIT 1
`;

export function registerCurrentAccountRoutes(
  routes: Hono<{ Bindings: Env }>,
): void {
  routes.get("/me", async (c) => {
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

    const session = await c.env.DB.prepare(SELECT_CURRENT_SESSION_SQL)
      .bind(verification.payload.session_id)
      .first<SessionLookupRow>();

    if (
      session === null ||
      !isLiveAccessSession(session, verification.payload, new Date())
    ) {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    if (verification.payload.owner_type === "anonymous") {
      const account = await c.env.DB.prepare(
        SELECT_CURRENT_ANONYMOUS_ACCOUNT_SQL,
      )
        .bind(verification.payload.owner_id)
        .first<AnonymousAccountRow>();

      if (!account) {
        return c.json(UNAUTHORIZED_RESPONSE, 401);
      }

      return c.json({
        success: true,
        data: {
          owner_type: "anonymous",
          user_id: null,
          anonymous_id: account.id,
          email: null,
          login_method: null,
          display_name: null,
          created_at: account.created_at,
        },
      });
    }

    const user = await c.env.DB.prepare(SELECT_CURRENT_USER_SQL)
      .bind(verification.payload.owner_id)
      .first<UserRow>();

    if (!user) {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    return c.json({
      success: true,
      data: {
        owner_type: "user",
        user_id: user.id,
        anonymous_id: null,
        email: user.email,
        login_method: loginMethodOrNull(session.login_method),
        display_name: user.display_name,
        created_at: user.created_at,
      },
    });
  });
}

function isLiveAccessSession(
  session: SessionLookupRow | null,
  payload: { owner_type: string; owner_id: string; session_id: string },
  now: Date,
): boolean {
  const expiresAt = session ? Date.parse(session.expires_at) : NaN;

  return (
    session !== null &&
    session.id === payload.session_id &&
    session.owner_type === payload.owner_type &&
    session.owner_id === payload.owner_id &&
    session.revoked_at === null &&
    Number.isFinite(expiresAt) &&
    expiresAt > now.getTime()
  );
}

function loginMethodOrNull(value: string | null): string | null {
  return value === "email" || value === "google" || value === "apple"
    ? value
    : null;
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
