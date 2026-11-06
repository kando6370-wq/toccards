import type { Hono } from "hono";
import type { Env } from "../env";
import { authenticateOwner } from "../owner-auth";

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
  platform: "ios" | "android" | null;
  user_id: string | null;
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
  WHERE id = ? AND upgraded_user_id IS NULL AND status = 'active' AND platform = ?
  LIMIT 1
`;

const SELECT_CURRENT_USER_SQL = `
  SELECT id, email, display_name, created_at
  FROM "user"
  WHERE id = ? AND status = 'active'
  LIMIT 1
`;

const SELECT_CURRENT_SESSION_SQL = `
  SELECT id, owner_type, owner_id, login_method, expires_at, revoked_at, platform, user_id
  FROM session
  WHERE id = ?
  LIMIT 1
`;

export function registerCurrentAccountRoutes(
  routes: Hono<{ Bindings: Env }>,
): void {
  routes.get("/me", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const session = await c.env.DB.prepare(SELECT_CURRENT_SESSION_SQL)
      .bind(auth.owner.session_id)
      .first<SessionLookupRow>();
    if (!session) {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    if (auth.owner.owner_type === "anonymous") {
      const account = await c.env.DB.prepare(
        SELECT_CURRENT_ANONYMOUS_ACCOUNT_SQL,
      )
        .bind(auth.owner.owner_id, auth.owner.platform)
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
          platform: auth.owner.platform,
          data_space_id: account.id,
        },
      });
    }

    const user = await c.env.DB.prepare(SELECT_CURRENT_USER_SQL)
      .bind(auth.owner.user_id)
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
        platform: auth.owner.platform,
        data_space_id: auth.owner.data_space_id,
      },
    });
  });
}

function loginMethodOrNull(value: string | null): string | null {
  return value === "email" || value === "google" || value === "apple"
    ? value
    : null;
}
