import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashRefreshToken,
  refreshTokenExpiresAt,
  signAccessToken,
  verifyPassword,
} from "@kando/auth-core";
import type { Hono } from "hono";
import type { Env } from "../env";
import { createId } from "../id";
import { reserveAccountUid } from "../account-uid";
import { mutationLockKey, runWithMutationLockStatements } from "../db/mutation-lock";
import type { DatabaseStatement } from "../db/database";
import { authenticateOwner } from "../owner-auth";
import { resolveIdentityAuthPlatform } from "./identity-platform";
import { findLatestPlatformAccount } from "./platform-account";

type LoginUserRow = {
  id: string;
  email: string;
  password_hash: string;
};

type LoginInput = {
  email: string | null;
  password: string | null;
  platform: unknown;
};

const EMAIL_MAX_LENGTH = 254;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const EMAIL_REQUIRED_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Please enter your email.",
  },
} as const;

const INVALID_EMAIL_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Please enter a valid email address.",
  },
} as const;

const INCORRECT_PASSWORD_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Incorrect password. Please try again.",
  },
} as const;

const DUMMY_LOGIN_PASSWORD_HASH =
  "pbkdf2-sha256$v1$100000$AAECAwQFBgcICQoLDA0ODw$n9d-PfgjYCpuBQORe6IZg6Op-rlL_-TOqIyWwG54xHI";

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const UNAUTHORIZED_RESPONSE = {
  success: false,
  error: { code: "UNAUTHORIZED", message: "Unauthorized." },
} as const;

const REGISTRATION_REQUIRED_RESPONSE = {
  success: false,
  error: { code: "REGISTRATION_REQUIRED", message: "Please register this platform account." },
} as const;

const SELECT_LOGIN_USER_BY_EMAIL_SQL = `
  SELECT id, email, password_hash
  FROM "user"
  WHERE email = ? AND status = 'active' AND password_hash IS NOT NULL
  LIMIT 1
`;

const INSERT_LOGIN_USER_SESSION_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at, platform, user_id)
  SELECT ?, 'user', ?, 'email', ?, ?, ?, NULL, ?, ?
  WHERE EXISTS (
    SELECT 1 FROM platform_account pa JOIN "user" u ON u.id = pa.user_id
    WHERE pa.id = ? AND pa.user_id = ? AND pa.platform = ?
      AND pa.status = 'active' AND u.status = 'active'
  )
`;

const INSERT_PLATFORM_ACCOUNT_SQL = `INSERT INTO platform_account
  (id, user_id, platform, status, created_at, updated_at, deleted_at)
  VALUES (?, (SELECT id FROM "user" WHERE id = ? AND status = 'active'),
    ?, 'active', ?, ?, NULL)`;
const INSERT_PLATFORM_FOLDER_SQL = `INSERT INTO portfolio_folder
  (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
  VALUES (?, 'user', ?, 'Main', 1, 0, ?, ?)`;
const INSERT_PLATFORM_PREFERENCE_SQL = `INSERT INTO user_preference
  (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
  VALUES (?, 'user', ?, 'USD', 0, NULL, ?, ?)`;

export function registerEmailLoginRoutes(
  routes: Hono<{ Bindings: Env }>,
): void {
  routes.post("/login", async (c) => {
    const input = await readLoginInput(c.req);

    if (!input.email) {
      return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    }

    if (!isValidEmail(input.email)) {
      return c.json(INVALID_EMAIL_RESPONSE, 422);
    }

    if (!input.password) {
      return c.json(INCORRECT_PASSWORD_RESPONSE, 422);
    }

    const platformResult = await resolveIdentityAuthPlatform(
      c.env,
      c.req.header("Authorization"),
      input.platform,
    );
    if (platformResult.status !== "ok") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const user = await c.env.DB.prepare(SELECT_LOGIN_USER_BY_EMAIL_SQL)
        .bind(input.email)
        .first<LoginUserRow>();

      const passwordMatches = await verifyPassword(
        input.password,
        user?.password_hash ?? DUMMY_LOGIN_PASSWORD_HASH,
      );

      if (!user || !passwordMatches) {
        return c.json(INCORRECT_PASSWORD_RESPONSE, 422);
      }

      const now = new Date();
      const createdAt = now.toISOString();
      let platformAccount = await findLatestPlatformAccount(
        c.env.DB,
        user.id,
        platformResult.platform,
      );
      if (platformAccount?.status === "deleted") {
        return c.json(REGISTRATION_REQUIRED_RESPONSE, 409);
      }
      if (platformAccount && platformAccount.status !== "active") {
        return c.json(INCORRECT_PASSWORD_RESPONSE, 422);
      }
      const lockedStatements: DatabaseStatement[] = [];
      if (!platformAccount) {
        const dataSpaceId = await reserveAccountUid(c.env.DB, createdAt);
        lockedStatements.push(
          c.env.DB.prepare(INSERT_PLATFORM_ACCOUNT_SQL).bind(
            dataSpaceId, user.id, platformResult.platform, createdAt, createdAt,
          ),
          c.env.DB.prepare(INSERT_PLATFORM_FOLDER_SQL).bind(
            createId(), dataSpaceId, createdAt, createdAt,
          ),
          c.env.DB.prepare(INSERT_PLATFORM_PREFERENCE_SQL).bind(
            createId(), dataSpaceId, createdAt, createdAt,
          ),
        );
        platformAccount = {
          id: dataSpaceId, user_id: user.id, platform: platformResult.platform, status: "active",
        };
      }
      const sessionId = createId();
      const refreshToken = createRefreshToken();
      const hashedRefreshToken = await hashRefreshToken(refreshToken);

      lockedStatements.push(c.env.DB.prepare(INSERT_LOGIN_USER_SESSION_SQL).bind(
          sessionId,
          platformAccount.id,
          hashedRefreshToken,
          refreshTokenExpiresAt(now),
          createdAt,
          platformResult.platform,
          user.id,
          platformAccount.id,
          user.id,
          platformResult.platform,
        ));
      const sourceAuth = c.req.header("Authorization")
        ? await authenticateOwner(c.env, c.req.header("Authorization"))
        : null;
      if (sourceAuth?.status === "ok" && sourceAuth.owner.owner_type === "anonymous") {
        lockedStatements.push(c.env.DB.prepare(
          "UPDATE app_installation SET uid = ? WHERE uid = ?",
        ).bind(platformAccount.id, sourceAuth.owner.owner_id));
      }
      const lockedResults = await runWithMutationLockStatements(
        c.env.DB,
        await mutationLockKey("platform-account-delete", user.id),
        lockedStatements,
      );
      const sessionResultIndex = sourceAuth?.status === "ok" &&
          sourceAuth.owner.owner_type === "anonymous"
        ? lockedResults.length - 2
        : lockedResults.length - 1;
      if (lockedResults[sessionResultIndex]?.meta.changes !== 1) {
        return c.json(INCORRECT_PASSWORD_RESPONSE, 422);
      }

      const accessToken = await signAccessToken(
        {
          owner_type: "user",
          owner_id: platformAccount.id,
          session_id: sessionId,
        },
        c.env.JWT_SECRET,
        now,
      );

      return c.json({
        success: true,
        data: {
          user_id: user.id,
          platform: platformResult.platform,
          data_space_id: platformAccount.id,
          email: user.email,
          login_method: "email",
          access_token: accessToken,
          refresh_token: refreshToken,
          expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
        },
      });
    } catch (error) {
      console.error("Failed to login with email.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });
}

async function readLoginInput(request: {
  json(): Promise<unknown>;
}): Promise<LoginInput> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { email: null, password: null, platform: null };
  }

  const rawEmail =
    body && typeof body === "object"
      ? (body as { email?: unknown }).email
      : undefined;
  const rawPassword =
    body && typeof body === "object"
      ? (body as { password?: unknown }).password
      : undefined;
  const rawPlatform = body && typeof body === "object"
    ? (body as { platform?: unknown }).platform
    : undefined;

  return {
    email: normalizeEmail(rawEmail),
    password:
      typeof rawPassword === "string" && rawPassword.length > 0
        ? rawPassword
        : null,
    platform: rawPlatform,
  };
}

function normalizeEmail(rawEmail: unknown): string | null {
  if (typeof rawEmail !== "string") {
    return null;
  }

  const email = rawEmail.trim().toLowerCase();

  return email.length > 0 ? email : null;
}

function isValidEmail(email: string): boolean {
  return email.length <= EMAIL_MAX_LENGTH && EMAIL_PATTERN.test(email);
}

function hasSigningSecret(secret: unknown): secret is string {
  return typeof secret === "string" && secret.trim().length > 0;
}
