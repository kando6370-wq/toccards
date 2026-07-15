import { hashPassword } from "@kando/auth-core";
import type { Hono } from "hono";
import type { Env } from "../env";
import { createId } from "../id";
import { sendVerificationEmail } from "../mail/verification-email";
import {
  createGuestMigrationStatements,
  findVerifiedAnonymousAccount,
} from "./guest-migration";
import { hasSigningSecret } from "./http-auth";
import { createUserSessionValues } from "./user-session";

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
  anonymousId: string | null;
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

const CODE_EXPIRED_RESPONSE = {
  success: false,
  error: { code: "VALIDATION_ERROR", message: "Code expired. Please request a new code." },
} as const;

const STALE_ANONYMOUS_ACCOUNT_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Guest account is no longer available.",
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

const RATE_LIMITED_RESPONSE = {
  success: false,
  error: { code: "RATE_LIMITED", message: "Please try again later." },
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
  SELECT ?, ?, ?, 'register', ?, NULL, ?
  WHERE NOT EXISTS (
    SELECT 1 FROM verification_code
    WHERE email = ? AND purpose = 'register' AND used_at IS NULL
      AND created_at > ?
  )
`;

const DELETE_VERIFICATION_CODE_SQL = `
  DELETE FROM verification_code WHERE id = ? AND used_at IS NULL
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

const INSERT_MIGRATED_USER_SQL = `
  INSERT INTO user
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  SELECT ?, ?, ?, NULL, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
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
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  SELECT ?, 'user', ?, 'email', ?, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
`;

const INSERT_MIGRATED_USER_SESSION_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at)
  SELECT ?, 'user', ?, 'email', ?, ?, ?, NULL
  WHERE EXISTS (
    SELECT 1
    FROM verification_code
    WHERE id = ? AND used_at = ?
  )
    AND EXISTS (
      SELECT 1
      FROM anonymous_account
      WHERE id = ? AND upgraded_user_id = ?
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
      const resendWindowStartedAt = new Date(
        now.getTime() - REGISTER_CODE_RESEND_AFTER_SECONDS * 1000,
      ).toISOString();

      const code = createVerificationCode();
      const verificationCodeId = createId();
      const result = await c.env.DB.prepare(INSERT_VERIFICATION_CODE_SQL)
        .bind(
          verificationCodeId,
          email,
          code,
          expiresAt,
          createdAt,
          email,
          resendWindowStartedAt,
        )
        .run();
      if (result.meta.changes === 0) {
        return c.json(RATE_LIMITED_RESPONSE, 429);
      }
      if (result.meta.changes !== 1) {
        return c.json(INTERNAL_ERROR_RESPONSE, 500);
      }
      try {
        await sendVerificationEmail(c.env, email, code, "register");
      } catch (error) {
        await c.env.DB.prepare(DELETE_VERIFICATION_CODE_SQL)
          .bind(verificationCodeId)
          .run();
        throw error;
      }

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

  routes.post("/register/verify-code", async (c) => {
    const input = await readRegisterVerifyInput(c.req);
    if (!input.email || !isValidEmail(input.email) ||
        !input.code || !VERIFICATION_CODE_PATTERN.test(input.code)) {
      return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
    }
    try {
      const latest = await c.env.DB.prepare(SELECT_LATEST_REGISTER_CODE_SQL)
        .bind(input.email).first<VerificationCodeRow>();
      if (!latest || latest.code !== input.code) {
        return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
      }
      if (!isUsableRegisterCode(latest, input.code, new Date())) {
        return c.json(CODE_EXPIRED_RESPONSE, 422);
      }
      return c.json({ success: true, data: {} });
    } catch (error) {
      console.error("Failed to verify register code.", error);
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

      if (
        verificationCode?.code === input.code &&
        verificationCode.used_at === null &&
        isExpiredRegisterCode(verificationCode, now)
      ) {
        return c.json(CODE_EXPIRED_RESPONSE, 422);
      }
      if (!isUsableRegisterCode(verificationCode, input.code, now)) {
        return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
      }

      const existingUser = await c.env.DB.prepare(SELECT_USER_BY_EMAIL_SQL)
        .bind(input.email)
        .first<UserRow>();

      if (existingUser) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      const anonymousAccount = await findVerifiedAnonymousAccount(
        c.env.DB,
        input.anonymousId,
        c.req.header("Authorization"),
        c.env.JWT_SECRET,
        now,
      );
      const createdAt = now.toISOString();
      const userId = createId();
      const passwordHash = await hashPassword(input.password);
      const session = await createUserSessionValues(
        userId,
        c.env.JWT_SECRET,
        now,
      );

      if (anonymousAccount) {
        const migrationStatements = createGuestMigrationStatements(
          c.env.DB,
          anonymousAccount.id,
          userId,
          createdAt,
          {
            verificationCodeId: verificationCode.id,
            verificationUsedAt: createdAt,
          },
        );
        const results = await c.env.DB.batch([
          c.env.DB.prepare(UPDATE_VERIFICATION_CODE_USED_SQL).bind(
            createdAt,
            verificationCode.id,
          ),
          migrationStatements.upgradeAccount,
          c.env.DB.prepare(INSERT_MIGRATED_USER_SQL).bind(
            userId,
            input.email,
            passwordHash,
            createdAt,
            createdAt,
            verificationCode.id,
            createdAt,
            anonymousAccount.id,
            userId,
          ),
          migrationStatements.portfolioFolders,
          migrationStatements.collectionItems,
          migrationStatements.wishlistItems,
          migrationStatements.userPreference,
          c.env.DB.prepare(INSERT_MIGRATED_USER_SESSION_SQL).bind(
            session.sessionId,
            userId,
            session.hashedRefreshToken,
            session.expiresAt,
            createdAt,
            verificationCode.id,
            createdAt,
            anonymousAccount.id,
            userId,
          ),
        ]);
        const [
          codeResult,
          upgradeResult,
          userResult,
          portfolioFoldersResult,
          collectionItemsResult,
          wishlistItemsResult,
          userPreferenceResult,
          sessionResult,
        ] = results;
        const assetResults = [
          portfolioFoldersResult,
          collectionItemsResult,
          wishlistItemsResult,
          userPreferenceResult,
        ];

        if (codeResult?.meta.changes !== 1) {
          return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
        }

        if (results.length !== 8 || assetResults.some((result) => !result)) {
          return c.json(INTERNAL_ERROR_RESPONSE, 500);
        }

        if (upgradeResult?.meta.changes !== 1) {
          return c.json(STALE_ANONYMOUS_ACCOUNT_RESPONSE, 422);
        }

        if (
          userResult?.meta.changes !== 1 ||
          sessionResult?.meta.changes !== 1
        ) {
          return c.json(INTERNAL_ERROR_RESPONSE, 500);
        }
      } else {
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
            createId(),
            userId,
            createdAt,
            createdAt,
            verificationCode.id,
            createdAt,
          ),
          c.env.DB.prepare(INSERT_USER_PREFERENCE_SQL).bind(
            createId(),
            userId,
            createdAt,
            createdAt,
            verificationCode.id,
            createdAt,
          ),
          c.env.DB.prepare(INSERT_USER_SESSION_SQL).bind(
            session.sessionId,
            userId,
            session.hashedRefreshToken,
            session.expiresAt,
            createdAt,
            verificationCode.id,
            createdAt,
          ),
        ]);

        if (results[0]?.meta.changes !== 1) {
          return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
        }

        if (
          results.length !== 5 ||
          results.slice(1).some((result) => result?.meta.changes !== 1)
        ) {
          return c.json(INTERNAL_ERROR_RESPONSE, 500);
        }
      }

      return c.json({
        success: true,
        data: {
          user_id: userId,
          email: input.email,
          login_method: "email",
          access_token: session.accessToken,
          refresh_token: session.refreshToken,
          expires_in: session.expiresIn,
          migrated: anonymousAccount !== null,
        },
      });
    } catch (error) {
      if (isUserEmailUniqueConstraintError(error)) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

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
    return { email: null, code: null, password: null, anonymousId: null };
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
  const rawAnonymousId =
    body && typeof body === "object"
      ? (body as { anonymous_id?: unknown }).anonymous_id
      : undefined;
  const anonymousId =
    typeof rawAnonymousId === "string" ? rawAnonymousId.trim() : "";

  return {
    email: normalizeEmail(rawEmail),
    code: typeof rawCode === "string" ? rawCode.trim() : null,
    password: typeof rawPassword === "string" ? rawPassword : null,
    anonymousId: anonymousId.length > 0 ? anonymousId : null,
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

function isUserEmailUniqueConstraintError(error: unknown): boolean {
  return (
    error instanceof Error &&
    error.message.includes("UNIQUE constraint failed: user.email")
  );
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

function isExpiredRegisterCode(row: VerificationCodeRow, now: Date): boolean {
  const expiresAt = Date.parse(row.expires_at);
  return !Number.isFinite(expiresAt) || expiresAt <= now.getTime();
}

function createVerificationCode(): string {
  const values = new Uint32Array(1);
  crypto.getRandomValues(values);

  return String(values[0] % 1000000).padStart(6, "0");
}
