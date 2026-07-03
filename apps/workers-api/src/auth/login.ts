import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashRefreshToken,
  refreshTokenExpiresAt,
  signAccessToken,
  verifyPassword,
} from "@kando/auth-core";
import type { Hono } from "hono";
import { ulid } from "ulid";
import type { Env } from "../env";

type LoginUserRow = {
  id: string;
  email: string;
  password_hash: string;
};

type LoginInput = {
  email: string | null;
  password: string | null;
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

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const SELECT_LOGIN_USER_BY_EMAIL_SQL = `
  SELECT id, email, password_hash
  FROM user
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
  LIMIT 1
`;

const INSERT_LOGIN_USER_SESSION_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'user', ?, ?, ?, ?, NULL)
`;

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

    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const user = await c.env.DB.prepare(SELECT_LOGIN_USER_BY_EMAIL_SQL)
        .bind(input.email)
        .first<LoginUserRow>();

      if (!user) {
        return c.json(INCORRECT_PASSWORD_RESPONSE, 422);
      }

      const passwordMatches = await verifyPassword(
        input.password,
        user.password_hash,
      );

      if (!passwordMatches) {
        return c.json(INCORRECT_PASSWORD_RESPONSE, 422);
      }

      const now = new Date();
      const createdAt = now.toISOString();
      const sessionId = ulid();
      const refreshToken = createRefreshToken();
      const hashedRefreshToken = await hashRefreshToken(refreshToken);

      await c.env.DB.prepare(INSERT_LOGIN_USER_SESSION_SQL)
        .bind(
          sessionId,
          user.id,
          hashedRefreshToken,
          refreshTokenExpiresAt(now),
          createdAt,
        )
        .run();

      const accessToken = await signAccessToken(
        {
          owner_type: "user",
          owner_id: user.id,
          session_id: sessionId,
        },
        c.env.JWT_SECRET,
        now,
      );

      return c.json({
        success: true,
        data: {
          user_id: user.id,
          email: user.email,
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
    return { email: null, password: null };
  }

  const rawEmail =
    body && typeof body === "object"
      ? (body as { email?: unknown }).email
      : undefined;
  const rawPassword =
    body && typeof body === "object"
      ? (body as { password?: unknown }).password
      : undefined;

  return {
    email: normalizeEmail(rawEmail),
    password:
      typeof rawPassword === "string" && rawPassword.length > 0
        ? rawPassword
        : null,
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
