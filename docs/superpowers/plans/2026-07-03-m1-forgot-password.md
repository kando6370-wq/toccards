# M1 Forgot Password Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Email forgot-password backend flow so Email-password users can request a reset code, exchange it for a short-lived reset token, and set a new password.

**Architecture:** Add a focused `apps/workers-api/src/auth/forgot-password.ts` module and register it from the existing auth route group. Reuse `verification_code` with `purpose = 'reset_password'`; keep reset-token signing private to the module and bind tokens to Email plus verification code id. Extend the existing Workers auth integration test harness without restructuring the large test file.

**Tech Stack:** TypeScript, Hono, Cloudflare Workers D1, WebCrypto HMAC-SHA256, Vitest, `@kando/auth-core`.

---

## File Structure

- Create: `apps/workers-api/src/auth/forgot-password.ts`
  - Owns `POST /auth/forgot-password/send-code`, `POST /auth/forgot-password/verify-code`, and `POST /auth/forgot-password/reset`.
  - Contains input parsing, Email normalization, reset-code D1 access, reset-token signing/verification, and password update.
- Modify: `apps/workers-api/src/auth/anonymous.ts`
  - Imports and registers `registerForgotPasswordRoutes(authRoutes)`.
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`
  - Extends `VerificationCodeRow.purpose` to include `reset_password`.
  - Adds request helpers and success/failure tests for the three endpoints.
  - Extends `FakeD1` with reset-code SQL branches and password update support.
- Read-only reference: `docs/superpowers/specs/2026-07-03-m1-forgot-password-design.md`

Do not modify database schema, migrations, Flutter UI, OAuth behavior, or existing login/session behavior.

---

### Task 1: Add Failing Forgot-Password Success Tests

**Files:**
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Extend test types and add response type**

Change:

```ts
type VerificationCodeRow = {
  id: string;
  email: string;
  code: string;
  purpose: "register";
  expires_at: string;
  used_at: string | null;
  created_at: string;
};
```

to:

```ts
type VerificationCodeRow = {
  id: string;
  email: string;
  code: string;
  purpose: "register" | "reset_password";
  expires_at: string;
  used_at: string | null;
  created_at: string;
};
```

Add near other response types:

```ts
type ForgotPasswordVerifyCodeSuccessResponse = {
  success: true;
  data: {
    reset_token: string;
  };
};
```

- [ ] **Step 2: Add request helpers**

Add these helpers near `requestLogin`:

```ts
async function requestForgotPasswordSendCode(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/forgot-password/send-code",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestForgotPasswordVerifyCode(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/forgot-password/verify-code",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function requestForgotPasswordReset(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/forgot-password/reset",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}
```

- [ ] **Step 3: Add success tests**

Add this block after the login describe block and before the anonymous account describe block:

```ts
describe("POST /api/v1/auth/forgot-password", () => {
  it("sends a reset code for a live Email-password user because password recovery starts with account ownership proof", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "reset-send-user",
      email: "reset-send@example.com",
      password_hash: await hashPassword("old-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestForgotPasswordSendCode(env, {
      email: "reset-send@example.com",
    });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        expires_in: 600,
        resend_after: 60,
      },
    });
    expect(db.verificationCodes).toHaveLength(1);
    expect(db.verificationCodes[0]).toEqual(
      expect.objectContaining({
        email: "reset-send@example.com",
        purpose: "reset_password",
        used_at: null,
      }),
    );
  });

  it("returns a reset token for a matching reset code because the new password step needs a short-lived proof", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "reset-verify-user",
      email: "reset-verify@example.com",
      password_hash: await hashPassword("old-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });
    const sendResponse = await requestForgotPasswordSendCode(env, {
      email: "reset-verify@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected reset verification code.");
    }

    const response = await requestForgotPasswordVerifyCode(env, {
      email: "reset-verify@example.com",
      code: code.code,
    });
    const body =
      (await response.json()) as ForgotPasswordVerifyCodeSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        reset_token: expect.any(String),
      },
    });
    expect(code.used_at).toBeNull();
  });

  it("resets the password and consumes the code because reset tokens must be single use", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);

    db.users.push({
      id: "reset-password-user",
      email: "reset-password@example.com",
      password_hash: await hashPassword("old-password"),
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const sendResponse = await requestForgotPasswordSendCode(env, {
      email: "reset-password@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected reset verification code.");
    }

    const verifyResponse = await requestForgotPasswordVerifyCode(env, {
      email: "reset-password@example.com",
      code: code.code,
    });
    const verifyBody =
      (await verifyResponse.json()) as ForgotPasswordVerifyCodeSuccessResponse;

    const response = await requestForgotPasswordReset(env, {
      email: "reset-password@example.com",
      reset_token: verifyBody.data.reset_token,
      new_password: "new-password",
    });
    const body = await response.json();
    const user = db.users[0];

    if (!user?.password_hash) {
      throw new Error("Expected updated user password hash.");
    }

    expect(response.status).toBe(200);
    expect(body).toEqual({ success: true, data: {} });
    expect(code.used_at).toEqual(expect.any(String));
    expect(await verifyPassword("new-password", user.password_hash)).toBe(true);
    expect(await verifyPassword("old-password", user.password_hash)).toBe(false);
  });
});
```

- [ ] **Step 4: Run tests to verify RED**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "forgot-password"
```

Expected: tests fail with 404 because the forgot-password routes are not registered.

- [ ] **Step 5: Leave failing tests uncommitted**

Do not commit this red state. Continue to Task 2 so the first implementation commit contains passing tests and code together.

---

### Task 2: Implement Send-Code, Verify-Code, and Reset Minimal Route

**Files:**
- Create: `apps/workers-api/src/auth/forgot-password.ts`
- Modify: `apps/workers-api/src/auth/anonymous.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Extend FakeD1 SQL constants**

Add these normalized SQL constants near the other auth SQL constants in `anonymous.test.ts`:

```ts
const SELECT_RESET_PASSWORD_USER_BY_EMAIL_SQL = normalizeSql(`
  SELECT id
  FROM user
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
  LIMIT 1
`);

const INSERT_RESET_PASSWORD_CODE_SQL = normalizeSql(`
  INSERT INTO verification_code
    (id, email, code, purpose, expires_at, used_at, created_at)
  VALUES (?, ?, ?, 'reset_password', ?, NULL, ?)
`);

const SELECT_LATEST_RESET_PASSWORD_CODE_SQL = normalizeSql(`
  SELECT id, code, expires_at, used_at, created_at
  FROM verification_code
  WHERE email = ? AND purpose = 'reset_password'
  ORDER BY created_at DESC
  LIMIT 1
`);

const SELECT_RESET_PASSWORD_CODE_BY_ID_SQL = normalizeSql(`
  SELECT id, code, expires_at, used_at
  FROM verification_code
  WHERE id = ? AND email = ? AND purpose = 'reset_password'
  LIMIT 1
`);

const UPDATE_RESET_PASSWORD_CODE_USED_SQL = normalizeSql(`
  UPDATE verification_code
  SET used_at = ?
  WHERE id = ? AND used_at IS NULL
`);

const UPDATE_RESET_PASSWORD_USER_SQL = normalizeSql(`
  UPDATE user
  SET password_hash = ?, updated_at = ?
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM verification_code
      WHERE id = ? AND used_at = ?
    )
`);
```

- [ ] **Step 2: Extend FakeD1 first() and run()**

In `FakeD1.first`, add branches for:

```ts
if (normalizedSql === SELECT_RESET_PASSWORD_USER_BY_EMAIL_SQL) {
  const [email] = values as [string];
  const user = this.users.find(
    (row) =>
      row.email === email &&
      row.deleted_at === null &&
      row.password_hash !== null,
  );

  return user ? ({ id: user.id } as T) : null;
}

if (normalizedSql === SELECT_LATEST_RESET_PASSWORD_CODE_SQL) {
  const [email] = values as [string];
  const code = this.verificationCodes
    .filter((row) => row.email === email && row.purpose === "reset_password")
    .sort((left, right) => right.created_at.localeCompare(left.created_at))
    .at(0);

  return code
    ? ({
        id: code.id,
        code: code.code,
        expires_at: code.expires_at,
        used_at: code.used_at,
        created_at: code.created_at,
      } as T)
    : null;
}

if (normalizedSql === SELECT_RESET_PASSWORD_CODE_BY_ID_SQL) {
  const [id, email] = values as [string, string];
  const code = this.verificationCodes.find(
    (row) =>
      row.id === id &&
      row.email === email &&
      row.purpose === "reset_password",
  );

  return code
    ? ({
        id: code.id,
        code: code.code,
        expires_at: code.expires_at,
        used_at: code.used_at,
      } as T)
    : null;
}
```

In `FakeD1.run`, add branches for:

```ts
if (normalizedSql === INSERT_RESET_PASSWORD_CODE_SQL) {
  const [id, email, code, expiresAt, createdAt] = values as [
    string,
    string,
    string,
    string,
    string,
  ];

  this.verificationCodes.push({
    id,
    email,
    code,
    purpose: "reset_password",
    expires_at: expiresAt,
    used_at: null,
    created_at: createdAt,
  });
  return okResult<T>();
}

if (normalizedSql === UPDATE_RESET_PASSWORD_CODE_USED_SQL) {
  const [usedAt, id] = values as [string, string];
  const code = this.verificationCodes.find(
    (row) => row.id === id && row.used_at === null,
  );

  if (code) {
    code.used_at = usedAt;
  }

  return okResult<T>(code ? 1 : 0);
}

if (normalizedSql === UPDATE_RESET_PASSWORD_USER_SQL) {
  const [passwordHash, updatedAt, email, codeId, usedAt] = values as [
    string,
    string,
    string,
    string,
    string,
  ];
  const code = this.verificationCodes.find(
    (row) => row.id === codeId && row.used_at === usedAt,
  );
  const user = this.users.find(
    (row) =>
      row.email === email &&
      row.deleted_at === null &&
      row.password_hash !== null &&
      code,
  );

  if (user) {
    user.password_hash = passwordHash;
    user.updated_at = updatedAt;
  }

  return okResult<T>(user ? 1 : 0);
}
```

- [ ] **Step 3: Create forgot-password module**

Create `apps/workers-api/src/auth/forgot-password.ts` with:

```ts
import { hashPassword } from "@kando/auth-core";
import type { Hono } from "hono";
import { ulid } from "ulid";
import type { Env } from "../env";

type ResetUserRow = { id: string };
type ResetCodeRow = {
  id: string;
  code: string;
  expires_at: string;
  used_at: string | null;
  created_at?: string;
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
const BASE64URL_ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

const EMAIL_REQUIRED_RESPONSE = {
  success: false,
  error: { code: "VALIDATION_ERROR", message: "Please enter your email." },
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
    message:
      "Email not registered. Please check your email or create a new account.",
  },
} as const;
const RATE_LIMITED_RESPONSE = {
  success: false,
  error: { code: "RATE_LIMITED", message: "Please try again later." },
} as const;
const INCORRECT_VERIFICATION_CODE_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Incorrect verification code.",
  },
} as const;
const EXPIRED_CODE_RESPONSE = {
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

const SELECT_RESET_PASSWORD_USER_BY_EMAIL_SQL = `
  SELECT id
  FROM user
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
  LIMIT 1
`;
const INSERT_RESET_PASSWORD_CODE_SQL = `
  INSERT INTO verification_code
    (id, email, code, purpose, expires_at, used_at, created_at)
  VALUES (?, ?, ?, 'reset_password', ?, NULL, ?)
`;
const SELECT_LATEST_RESET_PASSWORD_CODE_SQL = `
  SELECT id, code, expires_at, used_at, created_at
  FROM verification_code
  WHERE email = ? AND purpose = 'reset_password'
  ORDER BY created_at DESC
  LIMIT 1
`;
const SELECT_RESET_PASSWORD_CODE_BY_ID_SQL = `
  SELECT id, code, expires_at, used_at
  FROM verification_code
  WHERE id = ? AND email = ? AND purpose = 'reset_password'
  LIMIT 1
`;
const UPDATE_RESET_PASSWORD_CODE_USED_SQL = `
  UPDATE verification_code
  SET used_at = ?
  WHERE id = ? AND used_at IS NULL
`;
const UPDATE_RESET_PASSWORD_USER_SQL = `
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

    if (!email) return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    if (!isValidEmail(email)) return c.json(INVALID_EMAIL_RESPONSE, 422);

    try {
      const user = await c.env.DB.prepare(SELECT_RESET_PASSWORD_USER_BY_EMAIL_SQL)
        .bind(email)
        .first<ResetUserRow>();
      if (!user) return c.json(EMAIL_NOT_REGISTERED_RESPONSE, 422);

      const now = new Date();
      const latestCode = await c.env.DB.prepare(
        SELECT_LATEST_RESET_PASSWORD_CODE_SQL,
      )
        .bind(email)
        .first<ResetCodeRow>();
      if (isRecentUnusedCode(latestCode, now)) {
        return c.json(RATE_LIMITED_RESPONSE, 429);
      }

      const createdAt = now.toISOString();
      const expiresAt = new Date(
        now.getTime() + RESET_CODE_EXPIRES_IN_SECONDS * 1000,
      ).toISOString();

      await c.env.DB.prepare(INSERT_RESET_PASSWORD_CODE_SQL)
        .bind(ulid(), email, createVerificationCode(), expiresAt, createdAt)
        .run();

      return c.json({
        success: true,
        data: {
          expires_in: RESET_CODE_EXPIRES_IN_SECONDS,
          resend_after: RESET_CODE_RESEND_AFTER_SECONDS,
        },
      });
    } catch (error) {
      console.error("Failed to create reset password verification code.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });

  routes.post("/forgot-password/verify-code", async (c) => {
    const input = await readVerifyCodeInput(c.req);

    if (!input.email) return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    if (!isValidEmail(input.email)) return c.json(INVALID_EMAIL_RESPONSE, 422);
    if (!input.code || !VERIFICATION_CODE_PATTERN.test(input.code)) {
      return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
    }
    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const now = new Date();
      const code = await c.env.DB.prepare(SELECT_LATEST_RESET_PASSWORD_CODE_SQL)
        .bind(input.email)
        .first<ResetCodeRow>();

      if (!code || code.code !== input.code) {
        return c.json(INCORRECT_VERIFICATION_CODE_RESPONSE, 422);
      }
      if (!isUsableResetCode(code, now)) {
        return c.json(EXPIRED_CODE_RESPONSE, 422);
      }

      const resetToken = await signResetToken(
        {
          email: input.email,
          verification_code_id: code.id,
          exp:
            Math.floor(now.getTime() / 1000) +
            RESET_CODE_EXPIRES_IN_SECONDS,
        },
        c.env.JWT_SECRET,
      );

      return c.json({ success: true, data: { reset_token: resetToken } });
    } catch (error) {
      console.error("Failed to verify reset password code.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });

  routes.post("/forgot-password/reset", async (c) => {
    const input = await readResetInput(c.req);

    if (!input.email) return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    if (!isValidEmail(input.email)) return c.json(INVALID_EMAIL_RESPONSE, 422);
    if (!input.newPassword || input.newPassword.length < 8) {
      return c.json(INVALID_PASSWORD_RESPONSE, 422);
    }
    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const now = new Date();
      const resetToken = input.resetToken
        ? await verifyResetToken(input.resetToken, c.env.JWT_SECRET, now)
        : null;
      if (!resetToken || resetToken.email !== input.email) {
        return c.json(EXPIRED_CODE_RESPONSE, 422);
      }

      const code = await c.env.DB.prepare(SELECT_RESET_PASSWORD_CODE_BY_ID_SQL)
        .bind(resetToken.verification_code_id, input.email)
        .first<ResetCodeRow>();
      if (!isUsableResetCode(code, now)) {
        return c.json(EXPIRED_CODE_RESPONSE, 422);
      }

      const updatedAt = now.toISOString();
      const passwordHash = await hashPassword(input.newPassword);
      const results = await c.env.DB.batch([
        c.env.DB.prepare(UPDATE_RESET_PASSWORD_CODE_USED_SQL).bind(
          updatedAt,
          resetToken.verification_code_id,
        ),
        c.env.DB.prepare(UPDATE_RESET_PASSWORD_USER_SQL).bind(
          passwordHash,
          updatedAt,
          input.email,
          resetToken.verification_code_id,
          updatedAt,
        ),
      ]);

      if (
        results.length !== 2 ||
        results.some((result) => result?.meta.changes !== 1)
      ) {
        return c.json(EXPIRED_CODE_RESPONSE, 422);
      }

      return c.json({ success: true, data: {} });
    } catch (error) {
      console.error("Failed to reset password.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });
}

async function readEmail(request: { json(): Promise<unknown> }) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return null;
  }

  return normalizeEmail(
    body && typeof body === "object"
      ? (body as { email?: unknown }).email
      : undefined,
  );
}

async function readVerifyCodeInput(request: { json(): Promise<unknown> }) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return { email: null, code: null };
  }

  return {
    email: normalizeEmail(
      body && typeof body === "object"
        ? (body as { email?: unknown }).email
        : undefined,
    ),
    code:
      body && typeof body === "object" &&
      typeof (body as { code?: unknown }).code === "string"
        ? ((body as { code: string }).code.trim() || null)
        : null,
  };
}

async function readResetInput(request: { json(): Promise<unknown> }) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return { email: null, resetToken: null, newPassword: null };
  }

  return {
    email: normalizeEmail(
      body && typeof body === "object"
        ? (body as { email?: unknown }).email
        : undefined,
    ),
    resetToken:
      body && typeof body === "object" &&
      typeof (body as { reset_token?: unknown }).reset_token === "string"
        ? ((body as { reset_token: string }).reset_token.trim() || null)
        : null,
    newPassword:
      body && typeof body === "object" &&
      typeof (body as { new_password?: unknown }).new_password === "string"
        ? (body as { new_password: string }).new_password
        : null,
  };
}

function normalizeEmail(rawEmail: unknown): string | null {
  if (typeof rawEmail !== "string") return null;
  const email = rawEmail.trim().toLowerCase();
  return email.length > 0 ? email : null;
}

function isValidEmail(email: string): boolean {
  return email.length <= EMAIL_MAX_LENGTH && EMAIL_PATTERN.test(email);
}

function hasSigningSecret(secret: unknown): secret is string {
  return typeof secret === "string" && secret.trim().length > 0;
}

function isRecentUnusedCode(row: ResetCodeRow | null, now: Date): boolean {
  if (!row || row.used_at !== null || !row.created_at) return false;
  const createdAt = Date.parse(row.created_at);
  return (
    Number.isFinite(createdAt) &&
    now.getTime() - createdAt < RESET_CODE_RESEND_AFTER_SECONDS * 1000
  );
}

function isUsableResetCode(
  row: ResetCodeRow | null,
  now: Date,
): row is ResetCodeRow {
  if (!row || row.used_at !== null) return false;
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
  const encodedHeader = encodeJson({ alg: "HS256", typ: "JWT" });
  const encodedPayload = encodeJson(payload);
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await signHs256(signingInput, secret);
  return `${signingInput}.${encodeBase64Url(signature)}`;
}

async function verifyResetToken(
  token: string,
  secret: string,
  now: Date,
): Promise<ResetTokenPayload | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [encodedHeader, encodedPayload, encodedSignature] = parts as [
    string,
    string,
    string,
  ];

  try {
    const header = decodeJson(encodedHeader);
    if (
      !header ||
      typeof header !== "object" ||
      (header as { alg?: unknown }).alg !== "HS256" ||
      (header as { typ?: unknown }).typ !== "JWT"
    ) {
      return null;
    }

    const signature = decodeBase64Url(encodedSignature);
    const expectedSignature = await signHs256(
      `${encodedHeader}.${encodedPayload}`,
      secret,
    );
    if (!signatureMatches(signature, expectedSignature)) return null;

    const payload = decodeJson(encodedPayload);
    if (!isResetTokenPayload(payload)) return null;
    if (payload.exp <= Math.floor(now.getTime() / 1000)) return null;

    return payload;
  } catch {
    return null;
  }
}

async function signHs256(input: string, secret: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(input)),
  );
}

function encodeJson(value: unknown): string {
  return encodeBase64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function decodeJson(value: string): unknown {
  return JSON.parse(new TextDecoder().decode(decodeBase64Url(value)));
}

function encodeBase64Url(bytes: Uint8Array): string {
  let output = "";
  for (let index = 0; index < bytes.length; index += 3) {
    const firstByte = bytes[index] ?? 0;
    const hasSecondByte = index + 1 < bytes.length;
    const hasThirdByte = index + 2 < bytes.length;
    const secondByte = hasSecondByte ? bytes[index + 1] : 0;
    const thirdByte = hasThirdByte ? bytes[index + 2] : 0;
    const triplet = (firstByte << 16) | (secondByte << 8) | thirdByte;
    output += BASE64URL_ALPHABET[(triplet >> 18) & 0x3f];
    output += BASE64URL_ALPHABET[(triplet >> 12) & 0x3f];
    if (hasSecondByte) output += BASE64URL_ALPHABET[(triplet >> 6) & 0x3f];
    if (hasThirdByte) output += BASE64URL_ALPHABET[triplet & 0x3f];
  }
  return output;
}

function decodeBase64Url(value: string): Uint8Array {
  if (value.length % 4 === 1) throw new Error("Invalid base64url value.");
  let bits = 0;
  let bitLength = 0;
  const bytes: number[] = [];
  for (const char of value) {
    const index = BASE64URL_ALPHABET.indexOf(char);
    if (index === -1) throw new Error("Invalid base64url value.");
    bits = (bits << 6) | index;
    bitLength += 6;
    if (bitLength >= 8) {
      bitLength -= 8;
      bytes.push((bits >> bitLength) & 0xff);
      bits &= (1 << bitLength) - 1;
    }
  }
  return new Uint8Array(bytes);
}

function signatureMatches(actual: Uint8Array, expected: Uint8Array): boolean {
  if (actual.length !== expected.length) return false;
  let difference = 0;
  for (let index = 0; index < actual.length; index += 1) {
    difference |= actual[index] ^ expected[index];
  }
  return difference === 0;
}

function isResetTokenPayload(value: unknown): value is ResetTokenPayload {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    typeof (value as { email?: unknown }).email === "string" &&
    typeof (value as { verification_code_id?: unknown })
      .verification_code_id === "string" &&
    typeof (value as { exp?: unknown }).exp === "number" &&
    Number.isFinite((value as { exp: number }).exp)
  );
}
```

- [ ] **Step 4: Register routes**

In `apps/workers-api/src/auth/anonymous.ts`, add:

```ts
import { registerForgotPasswordRoutes } from "./forgot-password";
```

Then register after `registerEmailLoginRoutes(authRoutes);`:

```ts
registerForgotPasswordRoutes(authRoutes);
```

- [ ] **Step 5: Run tests**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "forgot-password"
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
```

Expected:

- Forgot-password focused tests pass.
- Full Workers API test suite passes.
- Type-check exits 0.

- [ ] **Step 6: Commit**

```powershell
git add apps/workers-api/src/auth/forgot-password.ts apps/workers-api/src/auth/anonymous.ts apps/workers-api/src/auth/anonymous.test.ts
git commit -m "feat(auth): add forgot password flow"
```

---

### Task 3: Add Forgot-Password Failure Coverage

**Files:**
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Add shared assertions**

Add near `expectIncorrectPassword`:

```ts
function expectEmailNotRegistered(body: unknown, status: number): void {
  expect(status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message:
        "Email not registered. Please check your email or create a new account.",
    },
  });
}

function expectExpiredResetCode(body: unknown, status: number): void {
  expect(status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message: "Code expired. Please request a new code.",
    },
  });
}
```

- [ ] **Step 2: Add send-code failure tests**

Append inside `describe("POST /api/v1/auth/forgot-password", ...)`:

```ts
it("rejects an unknown email because password reset should only start for registered Email accounts", async () => {
  const env = createTestEnv();

  const response = await requestForgotPasswordSendCode(env, {
    email: "missing-reset@example.com",
  });
  const body = await response.json();

  expectEmailNotRegistered(body, response.status);
  expect(fakeD1(env).verificationCodes).toHaveLength(0);
});

it("rejects an OAuth-only user because accounts without password_hash cannot reset a password", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "oauth-reset-user",
    email: "oauth-reset@example.com",
    password_hash: null,
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: null,
  });

  const response = await requestForgotPasswordSendCode(env, {
    email: "oauth-reset@example.com",
  });
  const body = await response.json();

  expectEmailNotRegistered(body, response.status);
  expect(db.verificationCodes).toHaveLength(0);
});

it("rate limits repeated reset code requests because users should not receive duplicate codes inside 60 seconds", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "rate-reset-user",
    email: "rate-reset@example.com",
    password_hash: await hashPassword("old-password"),
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: null,
  });

  const firstResponse = await requestForgotPasswordSendCode(env, {
    email: "rate-reset@example.com",
  });
  expect(firstResponse.status).toBe(200);

  const response = await requestForgotPasswordSendCode(env, {
    email: "rate-reset@example.com",
  });
  const body = await response.json();

  expect(response.status).toBe(429);
  expect(body).toEqual({
    success: false,
    error: {
      code: "RATE_LIMITED",
      message: "Please try again later.",
    },
  });
  expect(db.verificationCodes).toHaveLength(1);
});
```

- [ ] **Step 3: Add verify/reset failure tests**

Append:

```ts
it("rejects a wrong reset code because only the latest emailed proof can mint a reset token", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "wrong-code-reset-user",
    email: "wrong-code-reset@example.com",
    password_hash: await hashPassword("old-password"),
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: null,
  });
  const sendResponse = await requestForgotPasswordSendCode(env, {
    email: "wrong-code-reset@example.com",
  });
  expect(sendResponse.status).toBe(200);

  const response = await requestForgotPasswordVerifyCode(env, {
    email: "wrong-code-reset@example.com",
    code: "000000",
  });
  const body = await response.json();

  expect(response.status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message: "Incorrect verification code.",
    },
  });
});

it("rejects an expired reset code because stale email proofs must not reset passwords", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "expired-code-reset-user",
    email: "expired-code-reset@example.com",
    password_hash: await hashPassword("old-password"),
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: null,
  });
  const sendResponse = await requestForgotPasswordSendCode(env, {
    email: "expired-code-reset@example.com",
  });
  expect(sendResponse.status).toBe(200);
  const code = db.verificationCodes[0];

  if (!code) {
    throw new Error("Expected reset verification code.");
  }

  code.expires_at = "2000-01-01T00:00:00.000Z";

  const response = await requestForgotPasswordVerifyCode(env, {
    email: "expired-code-reset@example.com",
    code: code.code,
  });
  const body = await response.json();

  expectExpiredResetCode(body, response.status);
});

it("rejects replaying a reset token because each reset proof must be consumed once", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "replay-reset-user",
    email: "replay-reset@example.com",
    password_hash: await hashPassword("old-password"),
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: null,
  });
  const sendResponse = await requestForgotPasswordSendCode(env, {
    email: "replay-reset@example.com",
  });
  expect(sendResponse.status).toBe(200);
  const code = db.verificationCodes[0];

  if (!code) {
    throw new Error("Expected reset verification code.");
  }

  const verifyResponse = await requestForgotPasswordVerifyCode(env, {
    email: "replay-reset@example.com",
    code: code.code,
  });
  const verifyBody =
    (await verifyResponse.json()) as ForgotPasswordVerifyCodeSuccessResponse;

  const firstReset = await requestForgotPasswordReset(env, {
    email: "replay-reset@example.com",
    reset_token: verifyBody.data.reset_token,
    new_password: "new-password",
  });
  expect(firstReset.status).toBe(200);

  const response = await requestForgotPasswordReset(env, {
    email: "replay-reset@example.com",
    reset_token: verifyBody.data.reset_token,
    new_password: "another-password",
  });
  const body = await response.json();

  expectExpiredResetCode(body, response.status);
});
```

- [ ] **Step 4: Run tests and type-check**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "forgot-password"
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

```powershell
git add apps/workers-api/src/auth/anonymous.test.ts
git commit -m "test(auth): cover forgot password failures"
```

---

### Task 4: Final Verification

**Files:**
- Verify only, no planned edits.

- [ ] **Step 1: Verify auth-core**

Run:

```powershell
pnpm --filter @kando/auth-core run test
pnpm --filter @kando/auth-core run type-check
pnpm --filter @kando/auth-core run build
```

Expected:

- `auth-core` tests pass.
- `tsc --noEmit` exits 0.
- `tsc -p tsconfig.json` exits 0.

- [ ] **Step 2: Verify workers-api**

Run:

```powershell
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

Expected:

- Workers API tests pass.
- Workers API type-check exits 0.
- Wrangler dry-run build exits 0. If sandbox blocks Wrangler log writes, rerun the same command with approved sandbox escalation and record the clean result.

- [ ] **Step 3: Verify repository-level checks**

Run:

```powershell
pnpm run lint
pnpm run type-check
pnpm run build -- --force
```

Expected:

- Dependency direction lint passes.
- Turbo type-check succeeds.
- Forced Turbo build succeeds. If Wrangler needs to write logs outside the sandbox, rerun with approved sandbox escalation.

- [ ] **Step 4: Check git status**

Run:

```powershell
git status --short --branch
git log -5 --oneline
```

Expected:

- Worktree is clean.
- Recent log includes the forgot-password implementation commits.
