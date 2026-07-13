# M1 Email Registration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the M1 email registration slice: PBKDF2 password hashes, register verification codes, user creation, optional anonymous asset migration, and user session issuance.

**Architecture:** Keep the current auth route shape. Add password hashing helpers to `packages/auth-core`, add a focused `apps/workers-api/src/auth/register.ts`, and register it from the existing `authRoutes`. Extend the current Workers auth test harness instead of creating a second FakeD1 copy.

**Tech Stack:** TypeScript, Hono, Cloudflare Workers WebCrypto, D1 SQL, Vitest, pnpm.

---

## File Structure

- Modify: `packages/auth-core/src/index.ts`
  - Add versioned PBKDF2-SHA256 password hashing and verification.
- Modify: `packages/auth-core/src/index.test.ts`
  - Add password hash tests.
- Create: `apps/workers-api/src/auth/register.ts`
  - Own `POST /auth/register/send-code` and `POST /auth/register/verify`.
- Modify: `apps/workers-api/src/auth/anonymous.ts`
  - Register the new routes on the existing `authRoutes`.
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`
  - Extend FakeD1 and add end-to-end registration tests.

## Scope Check

This plan implements one approved slice. It does not implement login, password reset, OAuth, real email delivery, Flutter UI, schema changes, or bcrypt/argon2 dependencies.

## Task 1: Add PBKDF2 Password Hashing In auth-core

**Files:**
- Modify: `packages/auth-core/src/index.ts`
- Modify: `packages/auth-core/src/index.test.ts`

- [ ] **Step 1: Write failing tests**

Append these tests inside the existing `describe("auth-core token helpers", ...)` block in `packages/auth-core/src/index.test.ts`, and add `hashPassword` and `verifyPassword` to the import list:

```ts
  it("hashes passwords with a versioned PBKDF2 format so stored credentials can migrate safely", async () => {
    const hash = await hashPassword("correct horse battery staple");

    expect(hash).toMatch(/^pbkdf2-sha256\$v1\$\d+\$[A-Za-z0-9_-]+\$[A-Za-z0-9_-]+$/);
    expect(hash).not.toContain("correct horse battery staple");
  });

  it("verifies the matching password and rejects the wrong password because registration credentials gate user sessions", async () => {
    const hash = await hashPassword("correct horse battery staple");

    await expect(verifyPassword("correct horse battery staple", hash)).resolves.toBe(true);
    await expect(verifyPassword("wrong password", hash)).resolves.toBe(false);
  });

  it("rejects unsupported password hash versions without throwing so login can fail closed", async () => {
    await expect(
      verifyPassword("password", "pbkdf2-sha256$v2$210000$salt$hash"),
    ).resolves.toBe(false);
    await expect(
      verifyPassword("password", "argon2id$v1$memory$salt$hash"),
    ).resolves.toBe(false);
    await expect(verifyPassword("password", "not-a-password-hash")).resolves.toBe(false);
  });
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
pnpm --filter @kando/auth-core run test
```

Expected: fail because `hashPassword` and `verifyPassword` are not exported.

- [ ] **Step 3: Add minimal implementation**

In `packages/auth-core/src/index.ts`, add these exports after `refreshTokenExpiresAt`:

```ts
export const PASSWORD_HASH_ALGORITHM = "pbkdf2-sha256";
export const PASSWORD_HASH_VERSION = "v1";
export const PASSWORD_HASH_ITERATIONS = 210_000;

export async function hashPassword(password: string): Promise<string> {
  const salt = new Uint8Array(16);
  getCrypto().getRandomValues(salt);
  const hash = await derivePasswordHash(password, salt, PASSWORD_HASH_ITERATIONS);

  return [
    PASSWORD_HASH_ALGORITHM,
    PASSWORD_HASH_VERSION,
    String(PASSWORD_HASH_ITERATIONS),
    encodeBase64Url(salt),
    encodeBase64Url(hash),
  ].join("$");
}

export async function verifyPassword(
  password: string,
  storedHash: string,
): Promise<boolean> {
  const [algorithm, version, iterationsValue, saltValue, hashValue, extra] =
    storedHash.split("$");

  if (
    algorithm !== PASSWORD_HASH_ALGORITHM ||
    version !== PASSWORD_HASH_VERSION ||
    extra !== undefined ||
    !iterationsValue ||
    !saltValue ||
    !hashValue
  ) {
    return false;
  }

  const iterations = Number(iterationsValue);
  if (!Number.isSafeInteger(iterations) || iterations <= 0) {
    return false;
  }

  let salt: Uint8Array;
  let expectedHash: Uint8Array;

  try {
    salt = decodeBase64Url(saltValue);
    expectedHash = decodeBase64Url(hashValue);
  } catch {
    return false;
  }

  const actualHash = await derivePasswordHash(password, salt, iterations);
  return signatureMatches(actualHash, expectedHash);
}
```

Extend `WebCryptoLike.subtle` with PBKDF2 support:

```ts
    importKey(
      format: "raw",
      keyData: Uint8Array,
      algorithm: "PBKDF2",
      extractable: false,
      keyUsages: readonly ["deriveBits"],
    ): Promise<unknown>;
    deriveBits(
      algorithm: {
        name: "PBKDF2";
        hash: "SHA-256";
        salt: Uint8Array;
        iterations: number;
      },
      key: unknown,
      length: number,
    ): Promise<ArrayBuffer>;
```

Because `importKey` is already declared for HMAC, use overloads rather than replacing the existing HMAC signature.

Add this helper near `signHs256`:

```ts
async function derivePasswordHash(
  password: string,
  salt: Uint8Array,
  iterations: number,
): Promise<Uint8Array> {
  const crypto = getCrypto();
  const key = await crypto.subtle.importKey(
    "raw",
    encodeText(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      hash: "SHA-256",
      salt,
      iterations,
    },
    key,
    256,
  );

  return new Uint8Array(bits);
}
```

- [ ] **Step 4: Verify auth-core**

Run:

```powershell
pnpm --filter @kando/auth-core run test
pnpm --filter @kando/auth-core run type-check
pnpm --filter @kando/auth-core run build
```

Expected: all pass.

- [ ] **Step 5: Commit**

Run:

```powershell
git add packages\auth-core\src\index.ts packages\auth-core\src\index.test.ts
git commit -m "feat(auth): add pbkdf2 password hashing"
```

## Task 2: Add Register send-code Route

**Files:**
- Create: `apps/workers-api/src/auth/register.ts`
- Modify: `apps/workers-api/src/auth/anonymous.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Write failing route tests**

In `apps/workers-api/src/auth/anonymous.test.ts`, add these types near the other row types:

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

type RegisterSendCodeSuccessResponse = {
  success: true;
  data: {
    expires_in: number;
    resend_after: number;
  };
};
```

Add `verificationCodes: VerificationCodeRow[] = [];` to `FakeD1`.

Add this request helper near the other request helpers:

```ts
async function requestRegisterSendCode(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/register/send-code",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}
```

Add these SQL constants near the other normalized SQL constants:

```ts
const SELECT_ACTIVE_USER_BY_EMAIL_SQL = normalizeSql(`
  SELECT id
  FROM user
  WHERE email = ? AND deleted_at IS NULL
  LIMIT 1
`);

const INSERT_VERIFICATION_CODE_SQL = normalizeSql(`
  INSERT INTO verification_code
    (id, email, code, purpose, expires_at, used_at, created_at)
  VALUES (?, ?, ?, 'register', ?, NULL, ?)
`);
```

Extend `FakeD1.first`:

```ts
    if (normalizedSql === SELECT_ACTIVE_USER_BY_EMAIL_SQL) {
      const [email] = values as [string];
      const user = this.users.find(
        (row) => row.email === email && row.deleted_at === null,
      );

      return user ? ({ id: user.id } as T) : null;
    }
```

Extend `FakeD1.run`:

```ts
    if (normalizedSql === INSERT_VERIFICATION_CODE_SQL) {
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
        purpose: "register",
        expires_at: expiresAt,
        used_at: null,
        created_at: createdAt,
      });
      return okResult<T>();
    }
```

Add tests:

```ts
describe("POST /api/v1/auth/register/send-code", () => {
  it("stores a normalized register code because email registration must verify ownership before creating a user", async () => {
    const env = createTestEnv();
    const response = await requestRegisterSendCode(env, {
      email: "  USER@Example.COM  ",
    });
    const body = (await response.json()) as RegisterSendCodeSuccessResponse;
    const db = fakeD1(env);

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: { expires_in: 600, resend_after: 60 },
    });
    expect(db.verificationCodes).toHaveLength(1);
    expect(db.verificationCodes[0]).toEqual(
      expect.objectContaining({
        email: "user@example.com",
        purpose: "register",
        used_at: null,
      }),
    );
    expect(db.verificationCodes[0]?.code).toMatch(/^\d{6}$/);
  });

  it("returns 422 when email is invalid because unusable addresses cannot receive registration codes", async () => {
    const env = createTestEnv();
    const response = await requestRegisterSendCode(env, {
      email: "not-an-email",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toMatchObject({
      success: false,
      error: { code: "VALIDATION_ERROR" },
    });
    expect(fakeD1(env).verificationCodes).toHaveLength(0);
  });

  it("returns 409 when the email already belongs to an active user because registration must not overwrite accounts", async () => {
    const env = createTestEnv();
    fakeD1(env).users.push({
      id: "existing-user",
      email: "owner@example.com",
      display_name: null,
      created_at: "2026-07-03T00:00:00.000Z",
      updated_at: "2026-07-03T00:00:00.000Z",
      deleted_at: null,
    });

    const response = await requestRegisterSendCode(env, {
      email: "OWNER@example.com",
    });
    const body = await response.json();

    expect(response.status).toBe(409);
    expect(body).toMatchObject({
      success: false,
      error: { code: "CONFLICT" },
    });
    expect(fakeD1(env).verificationCodes).toHaveLength(0);
  });
});
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
pnpm --filter @kando/workers-api run test
```

Expected: fail because `/auth/register/send-code` is not registered.

- [ ] **Step 3: Create register route**

Create `apps/workers-api/src/auth/register.ts`:

```ts
import { Hono } from "hono";
import { ulid } from "ulid";
import type { Env } from "../env";

const REGISTER_CODE_EXPIRES_IN_SECONDS = 600;
const REGISTER_CODE_RESEND_AFTER_SECONDS = 60;
const EMAIL_MAX_LENGTH = 254;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const VALIDATION_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Please enter a valid email address.",
  },
} as const;

const EMAIL_REQUIRED_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Please enter your email.",
  },
} as const;

const CONFLICT_RESPONSE = {
  success: false,
  error: {
    code: "CONFLICT",
    message: "Email already registered.",
  },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const SELECT_ACTIVE_USER_BY_EMAIL_SQL = `
  SELECT id
  FROM user
  WHERE email = ? AND deleted_at IS NULL
  LIMIT 1
`;

const INSERT_VERIFICATION_CODE_SQL = `
  INSERT INTO verification_code
    (id, email, code, purpose, expires_at, used_at, created_at)
  VALUES (?, ?, ?, 'register', ?, NULL, ?)
`;

type UserLookupRow = {
  id: string;
};

export function registerEmailRegistrationRoutes(
  routes: Hono<{ Bindings: Env }>,
): void {
  routes.post("/register/send-code", async (c) => {
    let body: unknown;

    try {
      body = await c.req.json();
    } catch {
      return c.json(EMAIL_REQUIRED_RESPONSE, 422);
    }

    const emailResult = readNormalizedEmail(body);
    if (!emailResult.valid) {
      return c.json(emailResult.response, 422);
    }

    try {
      const existingUser = await c.env.DB.prepare(
        SELECT_ACTIVE_USER_BY_EMAIL_SQL,
      )
        .bind(emailResult.email)
        .first<UserLookupRow>();

      if (existingUser) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      const now = new Date();
      const createdAt = now.toISOString();
      const expiresAt = new Date(
        now.getTime() + REGISTER_CODE_EXPIRES_IN_SECONDS * 1000,
      ).toISOString();
      const code = createSixDigitCode();

      await c.env.DB.prepare(INSERT_VERIFICATION_CODE_SQL)
        .bind(ulid(), emailResult.email, code, expiresAt, createdAt)
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

type EmailResult =
  | { valid: true; email: string }
  | {
      valid: false;
      response: typeof EMAIL_REQUIRED_RESPONSE | typeof VALIDATION_ERROR_RESPONSE;
    };

function readNormalizedEmail(body: unknown): EmailResult {
  const rawEmail =
    body && typeof body === "object"
      ? (body as { email?: unknown }).email
      : undefined;

  if (typeof rawEmail !== "string") {
    return { valid: false, response: EMAIL_REQUIRED_RESPONSE };
  }

  const email = rawEmail.trim().toLowerCase();

  if (email.length === 0) {
    return { valid: false, response: EMAIL_REQUIRED_RESPONSE };
  }

  if (email.length > EMAIL_MAX_LENGTH || !EMAIL_PATTERN.test(email)) {
    return { valid: false, response: VALIDATION_ERROR_RESPONSE };
  }

  return { valid: true, email };
}

function createSixDigitCode(): string {
  const bytes = new Uint8Array(4);
  crypto.getRandomValues(bytes);
  const value =
    ((bytes[0] ?? 0) << 24) |
    ((bytes[1] ?? 0) << 16) |
    ((bytes[2] ?? 0) << 8) |
    (bytes[3] ?? 0);
  const positiveValue = value >>> 0;
  return String(positiveValue % 1_000_000).padStart(6, "0");
}
```

- [ ] **Step 4: Register the route**

In `apps/workers-api/src/auth/anonymous.ts`, add:

```ts
import { registerEmailRegistrationRoutes } from "./register";
```

Then call it after `registerSessionRoutes(authRoutes);`:

```ts
registerEmailRegistrationRoutes(authRoutes);
```

- [ ] **Step 5: Verify send-code**

Run:

```powershell
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
```

Expected: both pass.

- [ ] **Step 6: Commit**

Run:

```powershell
git add apps\workers-api\src\auth\register.ts apps\workers-api\src\auth\anonymous.ts apps\workers-api\src\auth\anonymous.test.ts
git commit -m "feat(auth): add register send code"
```

## Task 3: Add Register verify User Creation

**Files:**
- Modify: `apps/workers-api/src/auth/register.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Write failing verify tests**

In `apps/workers-api/src/auth/anonymous.test.ts`, import `verifyPassword` from `@kando/auth-core`.

Change `PortfolioFolderRow` and `UserPreferenceRow` owner types from only `"anonymous"` to `"anonymous" | "user"` so user defaults can be asserted.

Add response type:

```ts
type RegisterVerifySuccessResponse = {
  success: true;
  data: {
    user_id: string;
    email: string;
    access_token: string;
    refresh_token: string;
    expires_in: number;
    migrated: boolean;
  };
};
```

Add helper:

```ts
async function requestRegisterVerify(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/register/verify",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}
```

Add SQL constants:

```ts
const SELECT_LATEST_REGISTER_CODE_SQL = normalizeSql(`
  SELECT id, code, expires_at, used_at
  FROM verification_code
  WHERE email = ? AND purpose = 'register'
  ORDER BY created_at DESC
  LIMIT 1
`);

const INSERT_USER_SQL = normalizeSql(`
  INSERT INTO user
    (id, email, password_hash, display_name, created_at, updated_at, deleted_at)
  VALUES (?, ?, ?, NULL, ?, ?, NULL)
`);

const INSERT_USER_PORTFOLIO_FOLDER_SQL = normalizeSql(`
  INSERT INTO portfolio_folder
    (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
  VALUES (?, 'user', ?, 'Main', 1, 0, ?, ?)
`);

const INSERT_USER_PREFERENCE_SQL = normalizeSql(`
  INSERT INTO user_preference
    (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
  VALUES (?, 'user', ?, 'USD', 0, NULL, ?, ?)
`);

const INSERT_USER_SESSION_SQL = normalizeSql(`
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'user', ?, ?, ?, ?, NULL)
`);

const MARK_VERIFICATION_CODE_USED_SQL = normalizeSql(`
  UPDATE verification_code
  SET used_at = ?
  WHERE id = ? AND used_at IS NULL
`);
```

Add FakeD1 support for these SQL strings. For `SELECT_LATEST_REGISTER_CODE_SQL`, return `{ id, code, expires_at, used_at }` for the newest matching register code. For `INSERT_USER_SQL`, push a `UserRow` with `display_name: null` and `deleted_at: null`. For user folder/preference/session inserts, push rows with `owner_type: "user"`. For `MARK_VERIFICATION_CODE_USED_SQL`, update the matching row.

Add tests:

```ts
describe("POST /api/v1/auth/register/verify", () => {
  it("creates a user and user session because verified email ownership upgrades the client to a durable account", async () => {
    const env = createTestEnv();
    await requestRegisterSendCode(env, { email: "NewUser@example.com" });
    const code = fakeD1(env).verificationCodes[0]?.code;

    const response = await requestRegisterVerify(env, {
      email: " newuser@example.com ",
      code,
      password: "correct horse battery staple",
    });
    const body = (await response.json()) as RegisterVerifySuccessResponse;
    const db = fakeD1(env);

    expect(response.status).toBe(200);
    expect(body).toMatchObject({
      success: true,
      data: {
        user_id: expect.any(String),
        email: "newuser@example.com",
        access_token: expect.any(String),
        refresh_token: expect.any(String),
        expires_in: 900,
        migrated: false,
      },
    });
    expect(db.users).toEqual([
      expect.objectContaining({
        id: body.data.user_id,
        email: "newuser@example.com",
        display_name: null,
        deleted_at: null,
      }),
    ]);
    expect(db.users[0]?.password_hash).not.toBe("correct horse battery staple");
    await expect(
      verifyPassword(
        "correct horse battery staple",
        db.users[0]?.password_hash ?? "",
      ),
    ).resolves.toBe(true);
    expect(db.portfolioFolders).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: body.data.user_id,
        name: "Main",
      }),
    ]);
    expect(db.userPreferences).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: body.data.user_id,
        currency: "USD",
      }),
    ]);
    expect(db.sessions).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: body.data.user_id,
      }),
    ]);
    expect(db.sessions[0]?.refresh_token).toBe(
      await hashRefreshToken(body.data.refresh_token),
    );
    expect(db.verificationCodes[0]?.used_at).toEqual(expect.any(String));

    const currentResponse = await requestCurrentAccount(
      env,
      `Bearer ${body.data.access_token}`,
    );
    expect(currentResponse.status).toBe(200);
  });

  it("rejects reused verification codes because registration codes are single-use account creation proofs", async () => {
    const env = createTestEnv();
    await requestRegisterSendCode(env, { email: "reuse@example.com" });
    const code = fakeD1(env).verificationCodes[0]?.code;

    const firstResponse = await requestRegisterVerify(env, {
      email: "reuse@example.com",
      code,
      password: "correct horse battery staple",
    });
    expect(firstResponse.status).toBe(200);

    const secondResponse = await requestRegisterVerify(env, {
      email: "reuse@example.com",
      code,
      password: "correct horse battery staple",
    });
    const secondBody = await secondResponse.json();

    expect(secondResponse.status).toBe(422);
    expect(secondBody).toMatchObject({
      success: false,
      error: { code: "VALIDATION_ERROR" },
    });
    expect(fakeD1(env).users).toHaveLength(1);
  });

  it("rejects expired verification codes because old mailbox proofs must not create accounts", async () => {
    const env = createTestEnv();
    await requestRegisterSendCode(env, { email: "expired@example.com" });
    const verificationCode = fakeD1(env).verificationCodes[0];

    if (!verificationCode) {
      throw new Error("Expected verification code.");
    }

    verificationCode.expires_at = "2000-01-01T00:00:00.000Z";

    const response = await requestRegisterVerify(env, {
      email: "expired@example.com",
      code: verificationCode.code,
      password: "correct horse battery staple",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toMatchObject({
      success: false,
      error: { code: "VALIDATION_ERROR" },
    });
    expect(fakeD1(env).users).toHaveLength(0);
  });

  it("rejects short passwords before writing user data because weak registration credentials must not be persisted", async () => {
    const env = createTestEnv();
    await requestRegisterSendCode(env, { email: "short@example.com" });
    const code = fakeD1(env).verificationCodes[0]?.code;

    const response = await requestRegisterVerify(env, {
      email: "short@example.com",
      code,
      password: "short",
    });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toMatchObject({
      success: false,
      error: { code: "VALIDATION_ERROR" },
    });
    expect(fakeD1(env).users).toHaveLength(0);
  });
});
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
pnpm --filter @kando/workers-api run test
```

Expected: fail because `/auth/register/verify` and the new SQL operations are not implemented.

- [ ] **Step 3: Extend register route**

In `apps/workers-api/src/auth/register.ts`, extend imports:

```ts
import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashPassword,
  hashRefreshToken,
  refreshTokenExpiresAt,
  signAccessToken,
} from "@kando/auth-core";
```

Add constants:

```ts
const PASSWORD_MIN_LENGTH = 8;
const CODE_PATTERN = /^\d{6}$/;
```

Add SQL constants matching the test constants from Step 1.

Add route handler inside `registerEmailRegistrationRoutes` after `send-code`:

```ts
  routes.post("/register/verify", async (c) => {
    let body: unknown;

    try {
      body = await c.req.json();
    } catch {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const emailResult = readNormalizedEmail(body);
    if (!emailResult.valid) {
      return c.json(emailResult.response, 422);
    }

    const rawCode =
      body && typeof body === "object"
        ? (body as { code?: unknown }).code
        : undefined;
    const rawPassword =
      body && typeof body === "object"
        ? (body as { password?: unknown }).password
        : undefined;

    if (typeof rawCode !== "string" || !CODE_PATTERN.test(rawCode)) {
      return c.json(INCORRECT_CODE_RESPONSE, 422);
    }

    if (typeof rawPassword !== "string" || rawPassword.length < PASSWORD_MIN_LENGTH) {
      return c.json(WEAK_PASSWORD_RESPONSE, 422);
    }

    if (!(typeof c.env.JWT_SECRET === "string" && c.env.JWT_SECRET.trim().length > 0)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const existingUser = await c.env.DB.prepare(
        SELECT_ACTIVE_USER_BY_EMAIL_SQL,
      )
        .bind(emailResult.email)
        .first<UserLookupRow>();

      if (existingUser) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      const verificationCode = await c.env.DB.prepare(
        SELECT_LATEST_REGISTER_CODE_SQL,
      )
        .bind(emailResult.email)
        .first<RegisterCodeRow>();

      if (!isUsableRegisterCode(verificationCode, rawCode, new Date())) {
        return c.json(INCORRECT_CODE_RESPONSE, 422);
      }

      const now = new Date();
      const createdAt = now.toISOString();
      const userId = ulid();
      const sessionId = ulid();
      const refreshToken = createRefreshToken();
      const passwordHash = await hashPassword(rawPassword);
      const hashedRefreshToken = await hashRefreshToken(refreshToken);
      const expiresAt = refreshTokenExpiresAt(now);

      await c.env.DB.batch([
        c.env.DB.prepare(INSERT_USER_SQL).bind(
          userId,
          emailResult.email,
          passwordHash,
          createdAt,
          createdAt,
        ),
        c.env.DB.prepare(INSERT_USER_PORTFOLIO_FOLDER_SQL).bind(
          ulid(),
          userId,
          createdAt,
          createdAt,
        ),
        c.env.DB.prepare(INSERT_USER_PREFERENCE_SQL).bind(
          ulid(),
          userId,
          createdAt,
          createdAt,
        ),
        c.env.DB.prepare(MARK_VERIFICATION_CODE_USED_SQL).bind(
          createdAt,
          verificationCode.id,
        ),
        c.env.DB.prepare(INSERT_USER_SESSION_SQL).bind(
          sessionId,
          userId,
          hashedRefreshToken,
          expiresAt,
          createdAt,
        ),
      ]);

      const accessToken = await signAccessToken(
        {
          owner_type: "user",
          owner_id: userId,
          session_id: sessionId,
        },
        c.env.JWT_SECRET,
        now,
      );

      return c.json({
        success: true,
        data: {
          user_id: userId,
          email: emailResult.email,
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
```

Add missing response constants:

```ts
const INCORRECT_CODE_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Incorrect verification code.",
  },
} as const;

const WEAK_PASSWORD_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Password must be at least 8 characters.",
  },
} as const;
```

Add type and helper:

```ts
type RegisterCodeRow = {
  id: string;
  code: string;
  expires_at: string;
  used_at: string | null;
};

function isUsableRegisterCode(
  row: RegisterCodeRow | null,
  code: string,
  now: Date,
): row is RegisterCodeRow {
  if (!row || row.used_at !== null || row.code !== code) {
    return false;
  }

  const expiresAt = Date.parse(row.expires_at);
  return Number.isFinite(expiresAt) && expiresAt > now.getTime();
}
```

- [ ] **Step 4: Verify user registration**

Run:

```powershell
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
```

Expected: both pass.

- [ ] **Step 5: Commit**

Run:

```powershell
git add apps\workers-api\src\auth\register.ts apps\workers-api\src\auth\anonymous.test.ts
git commit -m "feat(auth): verify email registration"
```

## Task 4: Add Anonymous Asset Migration During Registration

**Files:**
- Modify: `apps/workers-api/src/auth/register.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Write failing migration tests**

Add SQL constants:

```ts
const SELECT_LIVE_ANONYMOUS_ACCOUNT_SQL = normalizeSql(`
  SELECT id
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`);

const MIGRATE_PORTFOLIO_FOLDERS_SQL = normalizeSql(`
  UPDATE portfolio_folder
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
`);

const MIGRATE_COLLECTION_ITEMS_SQL = normalizeSql(`
  UPDATE collection_item
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
`);

const MIGRATE_WISHLIST_ITEMS_SQL = normalizeSql(`
  UPDATE wishlist_item
  SET owner_type = 'user', owner_id = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
`);

const MIGRATE_USER_PREFERENCE_SQL = normalizeSql(`
  UPDATE user_preference
  SET owner_type = 'user', owner_id = ?, updated_at = ?
  WHERE owner_type = 'anonymous' AND owner_id = ?
`);

const MARK_ANONYMOUS_ACCOUNT_UPGRADED_SQL = normalizeSql(`
  UPDATE anonymous_account
  SET upgraded_user_id = ?
  WHERE id = ? AND upgraded_user_id IS NULL
`);
```

Add minimal row types and arrays for migration assertions:

```ts
type CollectionItemRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  folder_id: string;
  card_ref: string;
  updated_at: string;
};

type WishlistItemRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  card_ref: string;
};
```

Add `collectionItems: CollectionItemRow[] = [];` and `wishlistItems: WishlistItemRow[] = [];` to `FakeD1`.

Extend FakeD1 for the migration SQL strings. Each update should mutate matching in-memory rows and return `okResult<T>()`.

Add tests:

```ts
  it("migrates anonymous assets to the new user because registration upgrades should preserve guest work", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-register-upgrade");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    const anonymousId = anonymousBody.data.anonymous_id;
    const db = fakeD1(env);

    db.collectionItems.push({
      id: "collection-before-upgrade",
      owner_type: "anonymous",
      owner_id: anonymousId,
      folder_id: db.portfolioFolders[0]?.id ?? "folder-before-upgrade",
      card_ref: "card-before-upgrade",
      updated_at: "2026-07-03T00:00:00.000Z",
    });
    db.wishlistItems.push({
      id: "wishlist-before-upgrade",
      owner_type: "anonymous",
      owner_id: anonymousId,
      card_ref: "wish-before-upgrade",
    });

    await requestRegisterSendCode(env, { email: "upgrade@example.com" });
    const code = db.verificationCodes[0]?.code;

    const response = await requestRegisterVerify(env, {
      email: "upgrade@example.com",
      code,
      password: "correct horse battery staple",
      anonymous_id: anonymousId,
    });
    const body = (await response.json()) as RegisterVerifySuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.migrated).toBe(true);
    expect(db.anonymousAccounts[0]?.upgraded_user_id).toBe(body.data.user_id);
    expect(db.portfolioFolders).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: body.data.user_id,
        name: "Main",
      }),
    ]);
    expect(db.userPreferences).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: body.data.user_id,
      }),
    ]);
    expect(db.collectionItems).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: body.data.user_id,
      }),
    ]);
    expect(db.wishlistItems).toEqual([
      expect.objectContaining({
        owner_type: "user",
        owner_id: body.data.user_id,
      }),
    ]);
  });

  it("does not migrate when anonymous_id is already upgraded because assets must not be stolen from another owner", async () => {
    const env = createTestEnv();
    fakeD1(env).anonymousAccounts.push({
      id: "already-upgraded-anonymous",
      device_id: "device-upgraded-before-register",
      created_at: "2026-07-03T00:00:00.000Z",
      upgraded_user_id: "other-user",
    });
    await requestRegisterSendCode(env, { email: "nomigrate@example.com" });
    const code = fakeD1(env).verificationCodes[0]?.code;

    const response = await requestRegisterVerify(env, {
      email: "nomigrate@example.com",
      code,
      password: "correct horse battery staple",
      anonymous_id: "already-upgraded-anonymous",
    });
    const body = (await response.json()) as RegisterVerifySuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.migrated).toBe(false);
    expect(fakeD1(env).anonymousAccounts[0]?.upgraded_user_id).toBe("other-user");
  });
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
pnpm --filter @kando/workers-api run test
```

Expected: fail because verify ignores `anonymous_id` and migration SQL is unsupported.

- [ ] **Step 3: Implement migration**

In `apps/workers-api/src/auth/register.ts`, add migration SQL constants matching Step 1.

Read optional anonymous id in `verify`:

```ts
    const rawAnonymousId =
      body && typeof body === "object"
        ? (body as { anonymous_id?: unknown }).anonymous_id
        : undefined;
    const anonymousId =
      typeof rawAnonymousId === "string" && rawAnonymousId.trim().length > 0
        ? rawAnonymousId.trim()
        : null;
```

Before building the batch:

```ts
      const liveAnonymousAccount = anonymousId
        ? await c.env.DB.prepare(SELECT_LIVE_ANONYMOUS_ACCOUNT_SQL)
            .bind(anonymousId)
            .first<{ id: string }>()
        : null;
      const migrated = Boolean(liveAnonymousAccount);
```

Replace the fixed `batch([...])` call with a mutable statement list:

```ts
      const statements = [
        c.env.DB.prepare(INSERT_USER_SQL).bind(
          userId,
          emailResult.email,
          passwordHash,
          createdAt,
          createdAt,
        ),
      ];

      if (migrated && anonymousId) {
        statements.push(
          c.env.DB.prepare(MIGRATE_PORTFOLIO_FOLDERS_SQL).bind(
            userId,
            createdAt,
            anonymousId,
          ),
          c.env.DB.prepare(MIGRATE_COLLECTION_ITEMS_SQL).bind(
            userId,
            createdAt,
            anonymousId,
          ),
          c.env.DB.prepare(MIGRATE_WISHLIST_ITEMS_SQL).bind(userId, anonymousId),
          c.env.DB.prepare(MIGRATE_USER_PREFERENCE_SQL).bind(
            userId,
            createdAt,
            anonymousId,
          ),
          c.env.DB.prepare(MARK_ANONYMOUS_ACCOUNT_UPGRADED_SQL).bind(
            userId,
            anonymousId,
          ),
        );
      } else {
        statements.push(
          c.env.DB.prepare(INSERT_USER_PORTFOLIO_FOLDER_SQL).bind(
            ulid(),
            userId,
            createdAt,
            createdAt,
          ),
          c.env.DB.prepare(INSERT_USER_PREFERENCE_SQL).bind(
            ulid(),
            userId,
            createdAt,
            createdAt,
          ),
        );
      }

      statements.push(
        c.env.DB.prepare(MARK_VERIFICATION_CODE_USED_SQL).bind(
          createdAt,
          verificationCode.id,
        ),
        c.env.DB.prepare(INSERT_USER_SESSION_SQL).bind(
          sessionId,
          userId,
          hashedRefreshToken,
          expiresAt,
          createdAt,
        ),
      );

      await c.env.DB.batch(statements);
```

Return the actual migration flag:

```ts
          migrated,
```

- [ ] **Step 4: Verify migration**

Run:

```powershell
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
```

Expected: both pass.

- [ ] **Step 5: Commit**

Run:

```powershell
git add apps\workers-api\src\auth\register.ts apps\workers-api\src\auth\anonymous.test.ts
git commit -m "feat(auth): migrate anonymous assets on registration"
```

## Task 5: Final Verification

**Files:**
- Read: `packages/auth-core/src/index.ts`
- Read: `apps/workers-api/src/auth/register.ts`
- Read: `apps/workers-api/src/auth/anonymous.ts`
- Read: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Confirm no excluded dependency was added**

Run:

```powershell
Select-String -Path package.json,packages\auth-core\package.json,apps\workers-api\package.json,pnpm-lock.yaml -Pattern 'bcrypt|argon2' -CaseSensitive:$false
```

Expected: no output.

- [ ] **Step 2: Confirm no schema change**

Run:

```powershell
git diff HEAD~4..HEAD -- apps\workers-api\src\db\schema.ts apps\workers-api\src\db\migrations
```

Expected: no diff for schema or migrations.

- [ ] **Step 3: Run focused verification**

Run:

```powershell
pnpm --filter @kando/auth-core run test
pnpm --filter @kando/auth-core run type-check
pnpm --filter @kando/auth-core run build
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

Expected: all pass.

- [ ] **Step 4: Run repository-level checks**

Run:

```powershell
pnpm run lint
pnpm run type-check
pnpm run build
```

Expected: all pass. If root `type-check` or `build` exposes unrelated pre-existing failures, capture the exact failure and run the focused verification from Step 3 again before reporting.

- [ ] **Step 5: Inspect git state**

Run:

```powershell
git status --short --branch
git log -4 --oneline
```

Expected: clean working tree and the four feature commits from Tasks 1-4 plus the final verification state.
