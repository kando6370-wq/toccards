import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashPassword,
  hashRefreshToken,
  refreshTokenExpiresAt,
  signAccessToken,
} from "@kando/auth-core";
import type { Hono } from "hono";
import { ulid } from "ulid";
import type { Env } from "../env";

type UserRow = {
  id: string;
};

type VerificationCodeRow = {
  id: string;
  code: string;
  expires_at: string;
  used_at: string | null;
};

type RegisterVerifyInput = {
  email: string | null;
  code: string | null;
  password: string | null;
};

const REGISTER_CODE_EXPIRES_IN_SECONDS = 600;
const REGISTER_CODE_RESEND_AFTER_SECONDS = 60;
const EMAIL_MAX_LENGTH = 254;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const VERIFICATION_CODE_PATTERN = /^\d{6}$/;

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

const INCORRECT_VERIFICATION_CODE_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Incorrect verification code.",
  },
} as const;

const INVALID_PASSWORD_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Password must be at least 8 characters.",
  },
} as const;

const CONFLICT_RESPONSE = {
  success: false,
  error: {
    code: "CONFLICT",
    message: "Email is already registered.",
  },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const SELECT_USER_BY_EMAIL_SQL = `
  SELECT id
  FROM user
  WHERE email = ?
  LIMIT 1
`;

const INSERT_VERIFICATION_CODE_SQL = `
  INSERT INTO verification_code
    (id, email, code, purpose, expires_at, used_at, created_at)
  VALUES (?, ?, ?, 'register', ?, NULL, ?)
`;

const SELECT_LATEST_REGISTER_CODE_SQL = `
  SELECT id, code, expires_at, used_at
  FROM verification_code
  WHERE email = ? AND purpose = 'register'
  ORDER BY created_at DESC
  LIMIT 1
`;

const INSERT_USER_SQL = `
  INSERT INTO user
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  SELECT ?, ?, ?, NULL, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`;

const INSERT_USER_PORTFOLIO_FOLDER_SQL = `
  INSERT INTO portfolio_folder
    (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
  SELECT ?, 'user', ?, 'Main', 1, 0, ?, ?
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`;

const INSERT_USER_PREFERENCE_SQL = `
  INSERT INTO user_preference
    (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
  SELECT ?, 'user', ?, 'USD', 0, NULL, ?, ?
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`;

const INSERT_USER_SESSION_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  SELECT ?, 'user', ?, ?, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`;

const UPDATE_VERIFICATION_CODE_USED_SQL = `
  UPDATE verification_code
  SET used_at = ?
  WHERE id = ? AND used_at IS NULL
`;

export function registerEmailRegistrationRoutes(
  routes: Hono<{ Bindings: Env }>,
): void {
  routes.post("/register/send-code", async (c) => {
    const email = await readEmail(c.req);

    if (!email) {
      return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    }

    if (!isValidEmail(email)) {
      return c.json(INVALID_EMAIL_RESPONSE, 422);
    }

    try {
      const existingUser = await c.env.DB.prepare(SELECT_USER_BY_EMAIL_SQL)
        .bind(email)
        .first<UserRow>();

      if (existingUser) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      const now = new Date();
      const createdAt = now.toISOString();
      const expiresAt = new Date(
        now.getTime() + REGISTER_CODE_EXPIRES_IN_SECONDS * 1000,
      ).toISOString();

      await c.env.DB.prepare(INSERT_VERIFICATION_CODE_SQL)
        .bind(ulid(), email, createVerificationCode(), expiresAt, createdAt)
        .run();

      return c.json({
        success: true,
        data: {
          expires_in: REGISTER_CODE_EXPIRES_IN_SECONDS,
          resend_after: REGISTER_CODE_RESEND_AFTER_SECONDS,
        },
      });
    } catch (error) {
      console.error("Failed to create register verification code.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });

  routes.post("/register/verify", async (c) => {
    const input = await readRegisterVerifyInput(c.req);

    if (!input.email) {
      return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    }

    if (!isValidEmail(input.email)) {
      return c.json(INVALID_EMAIL_RESPONSE, 422);
    }

    if (!input.code || !VERIFICATION_CODE_PATTERN.test(input.code)) {
      return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
    }

    if (!input.password || input.password.length < 8) {
      return c.json(INVALID_PASSWORD_RESPONSE, 422);
    }

    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const now = new Date();
      const verificationCode = await c.env.DB.prepare(
        SELECT_LATEST_REGISTER_CODE_SQL,
      )
        .bind(input.email)
        .first<VerificationCodeRow>();

      if (!isUsableRegisterCode(verificationCode, input.code, now)) {
        return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
      }

      const existingUser = await c.env.DB.prepare(SELECT_USER_BY_EMAIL_SQL)
        .bind(input.email)
        .first<UserRow>();

      if (existingUser) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      const createdAt = now.toISOString();
      const userId = ulid();
      const sessionId = ulid();
      const refreshToken = createRefreshToken();
      const passwordHash = await hashPassword(input.password);
      const hashedRefreshToken = await hashRefreshToken(refreshToken);
      const accessToken = await signAccessToken(
        {
          owner_type: "user",
          owner_id: userId,
          session_id: sessionId,
        },
        c.env.JWT_SECRET,
        now,
      );

      const results = await c.env.DB.batch([
        c.env.DB.prepare(UPDATE_VERIFICATION_CODE_USED_SQL).bind(
          createdAt,
          verificationCode.id,
        ),
        c.env.DB.prepare(INSERT_USER_SQL).bind(
          userId,
          input.email,
          passwordHash,
          createdAt,
          createdAt,
          verificationCode.id,
          createdAt,
        ),
        c.env.DB.prepare(INSERT_USER_PORTFOLIO_FOLDER_SQL).bind(
          ulid(),
          userId,
          createdAt,
          createdAt,
          verificationCode.id,
          createdAt,
        ),
        c.env.DB.prepare(INSERT_USER_PREFERENCE_SQL).bind(
          ulid(),
          userId,
          createdAt,
          createdAt,
          verificationCode.id,
          createdAt,
        ),
        c.env.DB.prepare(INSERT_USER_SESSION_SQL).bind(
          sessionId,
          userId,
          hashedRefreshToken,
          refreshTokenExpiresAt(now),
          createdAt,
          verificationCode.id,
          createdAt,
        ),
      ]);

      if (results[0]?.meta.changes !== 1) {
        return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
      }

      const accountResults = results.slice(1);
      if (
        accountResults.length !== 4 ||
        accountResults.some((result) => result.meta.changes !== 1)
      ) {
        return c.json(INTERNAL_ERROR_RESPONSE, 500);
      }

      return c.json({
        success: true,
        data: {
          user_id: userId,
          email: input.email,
          access_token: accessToken,
          refresh_token: refreshToken,
          expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
          migrated: false,
        },
      });
    } catch (error) {
      console.error("Failed to verify register code.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });
}

async function readEmail(request: { json(): Promise<unknown> }): Promise<
  string | null
> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return null;
  }

  const rawEmail =
    body && typeof body === "object"
      ? (body as { email?: unknown }).email
      : undefined;

  return normalizeEmail(rawEmail);
}

async function readRegisterVerifyInput(request: {
  json(): Promise<unknown>;
}): Promise<RegisterVerifyInput> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { email: null, code: null, password: null };
  }

  const rawEmail =
    body && typeof body === "object"
      ? (body as { email?: unknown }).email
      : undefined;
  const rawCode =
    body && typeof body === "object"
      ? (body as { code?: unknown }).code
      : undefined;
  const rawPassword =
    body && typeof body === "object"
      ? (body as { password?: unknown }).password
      : undefined;

  return {
    email: normalizeEmail(rawEmail),
    code: typeof rawCode === "string" ? rawCode.trim() : null,
    password: typeof rawPassword === "string" ? rawPassword : null,
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

function isUsableRegisterCode(
  row: VerificationCodeRow | null,
  code: string,
  now: Date,
): row is VerificationCodeRow {
  if (!row || row.code !== code || row.used_at !== null) {
    return false;
  }

  const expiresAt = Date.parse(row.expires_at);

  return Number.isFinite(expiresAt) && expiresAt > now.getTime();
}

function createVerificationCode(): string {
  const values = new Uint32Array(1);
  crypto.getRandomValues(values);

  return String(values[0] % 1000000).padStart(6, "0");
}
