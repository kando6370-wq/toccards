import { hashPassword } from "@kando/auth-core";
import type { Hono } from "hono";
import type { Env } from "../env";
import { createId } from "../id";
import { sendVerificationEmail } from "../mail/verification-email";

type LiveEmailPasswordUserRow = {
  id: string;
};

type LatestResetCodeRow = {
  id: string;
  code: string;
  expires_at: string;
  used_at: string | null;
  created_at: string;
};

type ResetCodeRow = {
  id: string;
  code: string;
  expires_at: string;
  used_at: string | null;
};

type VerifyCodeInput = {
  email: string | null;
  code: string | null;
};

type ResetPasswordInput = {
  email: string | null;
  newPassword: string | null;
  resetToken: string | null;
};

type ResetTokenPayload = {
  email: string;
  verification_code_id: string;
  exp: number;
};

const RESET_CODE_EXPIRES_IN_SECONDS = 600;
const RESET_CODE_RESEND_AFTER_SECONDS = 60;
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

const EMAIL_NOT_REGISTERED_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Email not registered. Please check your email or create a new account.",
  },
} as const;

const RATE_LIMITED_RESPONSE = {
  success: false,
  error: {
    code: "RATE_LIMITED",
    message: "Please try again later.",
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
  error: {
    code: "VALIDATION_ERROR",
    message: "Code expired. Please request a new code.",
  },
} as const;

const INVALID_PASSWORD_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Password must be at least 8 characters.",
  },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const SELECT_LIVE_EMAIL_PASSWORD_USER_SQL = `
  SELECT id
  FROM user
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
  LIMIT 1
`;

const INSERT_RESET_CODE_SQL = `
  INSERT INTO verification_code
    (id, email, code, purpose, expires_at, used_at, created_at)
  SELECT ?, ?, ?, 'reset_password', ?, NULL, ?
  WHERE NOT EXISTS (
    SELECT 1
    FROM verification_code
    WHERE email = ? AND purpose = 'reset_password'
      AND used_at IS NULL
      AND created_at > ?
  )
`;

const DELETE_VERIFICATION_CODE_SQL = `
  DELETE FROM verification_code WHERE id = ? AND used_at IS NULL
`;

const SELECT_LATEST_RESET_CODE_SQL = `
  SELECT id, code, expires_at, used_at, created_at
  FROM verification_code
  WHERE email = ? AND purpose = 'reset_password'
  ORDER BY created_at DESC
  LIMIT 1
`;

const SELECT_RESET_CODE_BY_ID_EMAIL_SQL = `
  SELECT id, code, expires_at, used_at
  FROM verification_code
  WHERE id = ? AND email = ? AND purpose = 'reset_password'
  LIMIT 1
`;

const UPDATE_RESET_CODE_USED_SQL = `
  UPDATE verification_code
  SET used_at = ?
  WHERE id = ? AND used_at IS NULL
`;

const UPDATE_LIVE_EMAIL_PASSWORD_USER_SQL = `
  UPDATE user
  SET password_hash = ?, updated_at = ?
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM verification_code
      WHERE id = ? AND used_at = ?
    )
`;

export function registerForgotPasswordRoutes(
  routes: Hono<{ Bindings: Env }>,
): void {
  routes.post("/forgot-password/send-code", async (c) => {
    const email = await readEmail(c.req);

    if (!email) {
      return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    }

    if (!isValidEmail(email)) {
      return c.json(INVALID_EMAIL_RESPONSE, 422);
    }

    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const user = await c.env.DB.prepare(SELECT_LIVE_EMAIL_PASSWORD_USER_SQL)
        .bind(email)
        .first<LiveEmailPasswordUserRow>();

      if (!user) {
        return c.json(EMAIL_NOT_REGISTERED_RESPONSE, 422);
      }

      const now = new Date();
      const createdAt = now.toISOString();
      const expiresAt = new Date(
        now.getTime() + RESET_CODE_EXPIRES_IN_SECONDS * 1000,
      ).toISOString();
      const resendWindowStartedAt = new Date(
        now.getTime() - RESET_CODE_RESEND_AFTER_SECONDS * 1000,
      ).toISOString();

      const code = createVerificationCode();
      const verificationCodeId = createId();
      const result = await c.env.DB.prepare(INSERT_RESET_CODE_SQL)
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
        await sendVerificationEmail(c.env, email, code, "reset_password");
      } catch (error) {
        await c.env.DB.prepare(DELETE_VERIFICATION_CODE_SQL)
          .bind(verificationCodeId)
          .run();
        throw error;
      }

      return c.json({
        success: true,
        data: {
          expires_in: RESET_CODE_EXPIRES_IN_SECONDS,
          resend_after: RESET_CODE_RESEND_AFTER_SECONDS,
        },
      });
    } catch (error) {
      console.error("Failed to create reset verification code.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });

  routes.post("/forgot-password/verify-code", async (c) => {
    const input = await readVerifyCodeInput(c.req);

    if (!input.email) {
      return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    }

    if (!isValidEmail(input.email)) {
      return c.json(INVALID_EMAIL_RESPONSE, 422);
    }

    if (!input.code || !VERIFICATION_CODE_PATTERN.test(input.code)) {
      return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
    }

    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const now = new Date();
      const latestCode = await c.env.DB.prepare(SELECT_LATEST_RESET_CODE_SQL)
        .bind(input.email)
        .first<LatestResetCodeRow>();

      if (!latestCode || latestCode.code !== input.code) {
        return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
      }

      if (!isUnusedUnexpiredCode(latestCode, now)) {
        return c.json(CODE_EXPIRED_RESPONSE, 422);
      }

      const resetToken = await signResetToken(
        {
          email: input.email,
          verification_code_id: latestCode.id,
          exp: Math.floor(now.getTime() / 1000) + RESET_CODE_EXPIRES_IN_SECONDS,
        },
        c.env.JWT_SECRET,
      );

      return c.json({
        success: true,
        data: { reset_token: resetToken },
      });
    } catch (error) {
      console.error("Failed to verify reset code.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });

  routes.post("/forgot-password/reset", async (c) => {
    const input = await readResetPasswordInput(c.req);

    if (!input.email) {
      return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    }

    if (!isValidEmail(input.email)) {
      return c.json(INVALID_EMAIL_RESPONSE, 422);
    }

    if (!input.newPassword || input.newPassword.length < 8) {
      return c.json(INVALID_PASSWORD_RESPONSE, 422);
    }

    if (!input.resetToken) {
      return c.json(CODE_EXPIRED_RESPONSE, 422);
    }

    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const now = new Date();
      const payload = await verifyResetToken(
        input.resetToken,
        c.env.JWT_SECRET,
        now,
      );

      if (!payload || payload.email !== input.email) {
        return c.json(CODE_EXPIRED_RESPONSE, 422);
      }

      const code = await c.env.DB.prepare(SELECT_RESET_CODE_BY_ID_EMAIL_SQL)
        .bind(payload.verification_code_id, input.email)
        .first<ResetCodeRow>();

      if (!isUnusedUnexpiredCode(code, now)) {
        return c.json(CODE_EXPIRED_RESPONSE, 422);
      }

      const usedAt = now.toISOString();
      const passwordHash = await hashPassword(input.newPassword);
      const results = await c.env.DB.batch([
        c.env.DB.prepare(UPDATE_RESET_CODE_USED_SQL).bind(
          usedAt,
          payload.verification_code_id,
        ),
        c.env.DB.prepare(UPDATE_LIVE_EMAIL_PASSWORD_USER_SQL).bind(
          passwordHash,
          usedAt,
          input.email,
          payload.verification_code_id,
          usedAt,
        ),
      ]);

      if (
        results.length !== 2 ||
        results[0]?.meta.changes !== 1 ||
        results[1]?.meta.changes !== 1
      ) {
        return c.json(CODE_EXPIRED_RESPONSE, 422);
      }

      return c.json({ success: true, data: {} });
    } catch (error) {
      console.error("Failed to reset password.", error);
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

async function readVerifyCodeInput(request: {
  json(): Promise<unknown>;
}): Promise<VerifyCodeInput> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { email: null, code: null };
  }

  const rawEmail =
    body && typeof body === "object"
      ? (body as { email?: unknown }).email
      : undefined;
  const rawCode =
    body && typeof body === "object"
      ? (body as { code?: unknown }).code
      : undefined;

  return {
    email: normalizeEmail(rawEmail),
    code: typeof rawCode === "string" ? rawCode.trim() : null,
  };
}

async function readResetPasswordInput(request: {
  json(): Promise<unknown>;
}): Promise<ResetPasswordInput> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { email: null, newPassword: null, resetToken: null };
  }

  const rawEmail =
    body && typeof body === "object"
      ? (body as { email?: unknown }).email
      : undefined;
  const rawNewPassword =
    body && typeof body === "object"
      ? (body as { new_password?: unknown }).new_password
      : undefined;
  const rawResetToken =
    body && typeof body === "object"
      ? (body as { reset_token?: unknown }).reset_token
      : undefined;
  const resetToken =
    typeof rawResetToken === "string" ? rawResetToken.trim() : "";

  return {
    email: normalizeEmail(rawEmail),
    newPassword: typeof rawNewPassword === "string" ? rawNewPassword : null,
    resetToken: resetToken.length > 0 ? resetToken : null,
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

function isUnusedUnexpiredCode(
  row: ResetCodeRow | LatestResetCodeRow | null,
  now: Date,
): row is ResetCodeRow | LatestResetCodeRow {
  if (!row || row.used_at !== null) {
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

async function signResetToken(
  payload: ResetTokenPayload,
  secret: string,
): Promise<string> {
  const encodedHeader = base64UrlEncodeJson({ alg: "HS256", typ: "JWT" });
  const encodedPayload = base64UrlEncodeJson(payload);
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await createHmacSha256Signature(signingInput, secret);

  return `${signingInput}.${base64UrlEncode(signature)}`;
}

async function verifyResetToken(
  token: string,
  secret: string,
  now: Date,
): Promise<ResetTokenPayload | null> {
  const [encodedHeader, encodedPayload, encodedSignature, extra] =
    token.split(".");

  if (
    !encodedHeader ||
    !encodedPayload ||
    !encodedSignature ||
    extra !== undefined
  ) {
    return null;
  }

  const header = decodeBase64UrlJson(encodedHeader);

  if (!isResetTokenHeader(header)) {
    return null;
  }

  const signature = base64UrlDecode(encodedSignature);

  if (!signature) {
    return null;
  }

  const expectedSignature = await createHmacSha256Signature(
    `${encodedHeader}.${encodedPayload}`,
    secret,
  );

  if (!constantTimeEqual(signature, expectedSignature)) {
    return null;
  }

  const payload = decodeBase64UrlJson(encodedPayload);

  if (!isResetTokenPayload(payload)) {
    return null;
  }

  if (payload.exp <= Math.floor(now.getTime() / 1000)) {
    return null;
  }

  return payload;
}

async function createHmacSha256Signature(
  value: string,
  secret: string,
): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(value),
  );

  return new Uint8Array(signature);
}

function base64UrlEncodeJson(value: unknown): string {
  return base64UrlEncode(new TextEncoder().encode(JSON.stringify(value)));
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64UrlDecode(value: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    return null;
  }

  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const paddingLength = (4 - (base64.length % 4)) % 4;

  try {
    const binary = atob(`${base64}${"=".repeat(paddingLength)}`);
    const bytes = new Uint8Array(binary.length);

    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }

    return bytes;
  } catch {
    return null;
  }
}

function decodeBase64UrlJson(value: string): unknown {
  const bytes = base64UrlDecode(value);

  if (!bytes) {
    return null;
  }

  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

function isResetTokenPayload(value: unknown): value is ResetTokenPayload {
  return (
    !!value &&
    typeof value === "object" &&
    typeof (value as { email?: unknown }).email === "string" &&
    typeof (value as { verification_code_id?: unknown })
      .verification_code_id === "string" &&
    typeof (value as { exp?: unknown }).exp === "number" &&
    Number.isFinite((value as { exp: number }).exp)
  );
}

function isResetTokenHeader(value: unknown): value is {
  alg: "HS256";
  typ: "JWT";
} {
  return (
    !!value &&
    typeof value === "object" &&
    (value as { alg?: unknown }).alg === "HS256" &&
    (value as { typ?: unknown }).typ === "JWT"
  );
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  let difference = left.length ^ right.length;
  const length = Math.max(left.length, right.length);

  for (let index = 0; index < length; index += 1) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }

  return difference === 0;
}
