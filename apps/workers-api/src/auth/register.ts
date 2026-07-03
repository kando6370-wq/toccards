import type { Hono } from "hono";
import { ulid } from "ulid";
import type { Env } from "../env";

type UserRow = {
  id: string;
};

const REGISTER_CODE_EXPIRES_IN_SECONDS = 600;
const REGISTER_CODE_RESEND_AFTER_SECONDS = 60;
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

  if (typeof rawEmail !== "string") {
    return null;
  }

  const email = rawEmail.trim().toLowerCase();

  return email.length > 0 ? email : null;
}

function isValidEmail(email: string): boolean {
  return email.length <= EMAIL_MAX_LENGTH && EMAIL_PATTERN.test(email);
}

function createVerificationCode(): string {
  const values = new Uint32Array(1);
  crypto.getRandomValues(values);

  return String(values[0] % 1000000).padStart(6, "0");
}
