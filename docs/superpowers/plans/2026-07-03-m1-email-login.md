# M1 Email Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `POST /api/v1/auth/login` so registered Email users can sign in with a PBKDF2 password hash and receive a user session.

**Architecture:** Add a focused `apps/workers-api/src/auth/login.ts` route module and register it from the existing auth route group. Reuse `@kando/auth-core` for password verification, refresh token hashing, expiry calculation, and access token signing. Extend the existing Workers auth integration test harness without restructuring the large test file.

**Tech Stack:** TypeScript, Hono, Cloudflare Workers D1, Vitest, `@kando/auth-core`.

---

## File Structure

- Create: `apps/workers-api/src/auth/login.ts`
  - Owns `POST /auth/login`.
  - Contains request parsing, email normalization, password verification, session insert, and response shaping for Email login only.
- Modify: `apps/workers-api/src/auth/anonymous.ts`
  - Imports and registers `registerEmailLoginRoutes(authRoutes)`.
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`
  - Adds request helper and response type for login.
  - Extends `FakeD1` with login user lookup and direct user session insert SQL support.
  - Adds focused tests for success and failure paths.
- Read-only reference: `docs/superpowers/specs/2026-07-03-m1-email-login-design.md`
  - Source of behavior and acceptance criteria.

Do not modify database schema, migrations, `packages/auth-core`, Flutter UI, OAuth, or forgot-password behavior in this plan.

---

### Task 1: Add Failing Email Login Success Tests

**Files:**
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Add login response type**

In `apps/workers-api/src/auth/anonymous.test.ts`, add this type after `RegisterVerifySuccessResponse`:

```ts
type LoginSuccessResponse = {
  success: true;
  data: {
    user_id: string;
    email: string;
    access_token: string;
    refresh_token: string;
    expires_in: number;
  };
};
```

- [ ] **Step 2: Add login request helper**

In the helper section near `requestRegisterVerify`, add:

```ts
async function requestLogin(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/login",
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

Add this block after the `POST /api/v1/auth/register/verify` describe block and before the anonymous account describe block:

```ts
describe("POST /api/v1/auth/login", () => {
  it("creates a new user session because registered email owners must be able to return after registration", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const password = "correct-password";

    const sendResponse = await requestRegisterSendCode(env, {
      email: "login.owner@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const registerResponse = await requestRegisterVerify(env, {
      email: "login.owner@example.com",
      code: code.code,
      password,
    });
    expect(registerResponse.status).toBe(200);
    const existingUserSessionCount = db.sessions.filter(
      (row) => row.owner_type === "user",
    ).length;

    const response = await requestLogin(env, {
      email: "login.owner@example.com",
      password,
    });
    const body = (await response.json()) as LoginSuccessResponse;

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: {
        user_id: expect.any(String),
        email: "login.owner@example.com",
        access_token: expect.any(String),
        refresh_token: expect.any(String),
        expires_in: 900,
      },
    });

    const loginSession = db.sessions.at(-1);

    if (!loginSession) {
      throw new Error("Expected login session.");
    }

    expect(db.sessions.filter((row) => row.owner_type === "user")).toHaveLength(
      existingUserSessionCount + 1,
    );
    expect(loginSession.owner_type).toBe("user");
    expect(loginSession.owner_id).toBe(body.data.user_id);
    expect(loginSession.refresh_token).toBe(
      await hashRefreshToken(body.data.refresh_token),
    );
    expect(loginSession.refresh_token).not.toBe(body.data.refresh_token);

    const currentResponse = await requestCurrentAccount(
      env,
      `Bearer ${body.data.access_token}`,
    );
    const currentBody =
      (await currentResponse.json()) as CurrentAccountSuccessResponse;

    expect(currentResponse.status).toBe(200);
    expect(currentBody.data).toEqual(
      expect.objectContaining({
        owner_type: "user",
        user_id: body.data.user_id,
        anonymous_id: null,
        email: "login.owner@example.com",
      }),
    );
  });

  it("normalizes email before password verification because login input should match registration input rules", async () => {
    const env = createTestEnv();
    const db = fakeD1(env);
    const password = "correct-password";

    const sendResponse = await requestRegisterSendCode(env, {
      email: "mixed.login@example.com",
    });
    expect(sendResponse.status).toBe(200);
    const code = db.verificationCodes[0];

    if (!code) {
      throw new Error("Expected register verification code.");
    }

    const registerResponse = await requestRegisterVerify(env, {
      email: "mixed.login@example.com",
      code: code.code,
      password,
    });
    expect(registerResponse.status).toBe(200);

    const response = await requestLogin(env, {
      email: "  Mixed.Login@Example.COM  ",
      password,
    });
    const body = (await response.json()) as LoginSuccessResponse;

    expect(response.status).toBe(200);
    expect(body.data.email).toBe("mixed.login@example.com");
  });
});
```

- [ ] **Step 4: Run tests to verify failure**

Run:

```powershell
pnpm --filter @kando/workers-api run test
```

Expected: the two new login tests fail with `404` because `/api/v1/auth/login` is not registered.

- [ ] **Step 5: Leave failing tests uncommitted**

Do not commit this red state. Keep the failing tests in the worktree and continue to Task 2 so the first commit contains tests plus implementation that pass together.

---

### Task 2: Implement Minimal Email Login Route

**Files:**
- Create: `apps/workers-api/src/auth/login.ts`
- Modify: `apps/workers-api/src/auth/anonymous.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Add SQL constants to the test harness**

In `apps/workers-api/src/auth/anonymous.test.ts`, add these normalized SQL constants near the other SQL constants:

```ts
const SELECT_LOGIN_USER_BY_EMAIL_SQL = normalizeSql(`
  SELECT id, email, password_hash
  FROM user
  WHERE email = ? AND deleted_at IS NULL AND password_hash IS NOT NULL
  LIMIT 1
`);

const INSERT_LOGIN_USER_SESSION_SQL = normalizeSql(`
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'user', ?, ?, ?, ?, NULL)
`);
```

- [ ] **Step 2: Extend FakeD1 first() for login lookup**

In `FakeD1.first`, before the final unsupported SQL throw, add:

```ts
if (normalizedSql === SELECT_LOGIN_USER_BY_EMAIL_SQL) {
  const [email] = values as [string];
  const user = this.users.find(
    (row) =>
      row.email === email &&
      row.deleted_at === null &&
      row.password_hash !== null,
  );

  return user
    ? ({
        id: user.id,
        email: user.email,
        password_hash: user.password_hash,
      } as T)
    : null;
}
```

- [ ] **Step 3: Extend FakeD1 run() for login session insert**

In `FakeD1.run`, before the final unsupported SQL throw, add:

```ts
if (normalizedSql === INSERT_LOGIN_USER_SESSION_SQL) {
  const [id, ownerId, refreshToken, expiresAt, createdAt] = values as [
    string,
    string,
    string,
    string,
    string,
  ];

  this.sessions.push({
    id,
    owner_type: "user",
    owner_id: ownerId,
    refresh_token: refreshToken,
    expires_at: expiresAt,
    created_at: createdAt,
    revoked_at: null,
  });
  return okResult<T>();
}
```

- [ ] **Step 4: Create login route module**

Create `apps/workers-api/src/auth/login.ts`:

```ts
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
```

- [ ] **Step 5: Register login routes**

In `apps/workers-api/src/auth/anonymous.ts`, add the import:

```ts
import { registerEmailLoginRoutes } from "./login";
```

Then register it after `registerEmailRegistrationRoutes(authRoutes);`:

```ts
registerEmailLoginRoutes(authRoutes);
```

- [ ] **Step 6: Run success tests**

Run:

```powershell
pnpm --filter @kando/workers-api run test
```

Expected: the login success tests pass, and existing tests stay green.

- [ ] **Step 7: Commit success coverage and minimal implementation**

```powershell
git add apps/workers-api/src/auth/login.ts apps/workers-api/src/auth/anonymous.ts apps/workers-api/src/auth/anonymous.test.ts
git commit -m "feat(auth): add email login"
```

---

### Task 3: Add Email Login Failure Coverage

**Files:**
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Extend auth-core test import**

At the top of `apps/workers-api/src/auth/anonymous.test.ts`, change the auth-core import to include `hashPassword`:

```ts
import {
  hashPassword,
  hashRefreshToken,
  signAccessToken,
  verifyPassword,
} from "@kando/auth-core";
```

- [ ] **Step 2: Add shared assertion helper**

Near `expectUnauthorized`, add:

```ts
function expectIncorrectPassword(body: unknown, status: number): void {
  expect(status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message: "Incorrect password. Please try again.",
    },
  });
}
```

- [ ] **Step 3: Add failure tests inside the login describe block**

Append these tests inside `describe("POST /api/v1/auth/login", ...)`:

```ts
it("returns a uniform password error for an unknown email because login must not reveal account existence", async () => {
  const env = createTestEnv();

  const response = await requestLogin(env, {
    email: "missing@example.com",
    password: "correct-password",
  });
  const body = await response.json();

  expectIncorrectPassword(body, response.status);
  expect(fakeD1(env).sessions).toHaveLength(0);
});

it("returns a uniform password error for the wrong password because failed authentication must not create sessions", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "wrong-password-user",
    email: "wrong-password@example.com",
    password_hash: await hashPassword("correct-password"),
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: null,
  });

  const response = await requestLogin(env, {
    email: "wrong-password@example.com",
    password: "incorrect-password",
  });
  const body = await response.json();

  expectIncorrectPassword(body, response.status);
  expect(db.sessions).toHaveLength(0);
});

it("returns a uniform password error for a soft-deleted user because removed accounts must not be revived", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "deleted-login-user",
    email: "deleted-login@example.com",
    password_hash: await hashPassword("correct-password"),
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: "2026-07-03T01:00:00.000Z",
  });

  const response = await requestLogin(env, {
    email: "deleted-login@example.com",
    password: "correct-password",
  });
  const body = await response.json();

  expectIncorrectPassword(body, response.status);
  expect(db.sessions).toHaveLength(0);
});

it("returns a uniform password error for an OAuth-only user because password login requires a stored password hash", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "oauth-only-login-user",
    email: "oauth-only@example.com",
    password_hash: null,
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: null,
  });

  const response = await requestLogin(env, {
    email: "oauth-only@example.com",
    password: "correct-password",
  });
  const body = await response.json();

  expectIncorrectPassword(body, response.status);
  expect(db.sessions).toHaveLength(0);
});

it("returns a uniform password error for a blank password because login needs a credential secret", async () => {
  const env = createTestEnv();

  const response = await requestLogin(env, {
    email: "blank-password@example.com",
    password: "",
  });
  const body = await response.json();

  expectIncorrectPassword(body, response.status);
  expect(fakeD1(env).sessions).toHaveLength(0);
});

it("returns 422 / VALIDATION_ERROR for blank email because login cannot identify the account lookup key", async () => {
  const env = createTestEnv();

  const response = await requestLogin(env, {
    email: "   ",
    password: "correct-password",
  });
  const body = await response.json();

  expect(response.status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message: "Please enter your email.",
    },
  });
  expect(fakeD1(env).sessions).toHaveLength(0);
});

it("returns 422 / VALIDATION_ERROR for invalid email because malformed account keys must not query users", async () => {
  const env = createTestEnv();

  const response = await requestLogin(env, {
    email: "invalid-email",
    password: "correct-password",
  });
  const body = await response.json();

  expect(response.status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message: "Please enter a valid email address.",
    },
  });
  expect(fakeD1(env).sessions).toHaveLength(0);
});

it("returns 422 / VALIDATION_ERROR for overlong email because login must enforce the shared email length rule", async () => {
  const env = createTestEnv();
  const overlongEmail = `${"a".repeat(245)}@example.com`;

  const response = await requestLogin(env, {
    email: overlongEmail,
    password: "correct-password",
  });
  const body = await response.json();

  expect(response.status).toBe(422);
  expect(body).toEqual({
    success: false,
    error: {
      code: "VALIDATION_ERROR",
      message: "Please enter a valid email address.",
    },
  });
  expect(fakeD1(env).sessions).toHaveLength(0);
});

it("returns 500 / INTERNAL_ERROR when JWT_SECRET is blank because login sessions need signed access tokens", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "secret-login-user",
    email: "secret-login@example.com",
    password_hash: await hashPassword("correct-password"),
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: null,
  });
  env.JWT_SECRET = "   ";

  const response = await requestLogin(env, {
    email: "secret-login@example.com",
    password: "correct-password",
  });
  const body = await response.json();

  expect(response.status).toBe(500);
  expect(body).toEqual({
    success: false,
    error: {
      code: "INTERNAL_ERROR",
      message: "Something went wrong. Please try again.",
    },
  });
  expect(db.sessions).toHaveLength(0);
});

it("returns 500 / INTERNAL_ERROR when user lookup fails because login must fail loudly before issuing credentials", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.failNextFirst = true;

  const response = await requestLogin(env, {
    email: "lookup-failure@example.com",
    password: "correct-password",
  });
  const body = await response.json();

  expect(response.status).toBe(500);
  expect(body).toEqual({
    success: false,
    error: {
      code: "INTERNAL_ERROR",
      message: "Something went wrong. Please try again.",
    },
  });
  expect(db.sessions).toHaveLength(0);
});

it("returns 500 / INTERNAL_ERROR when session persistence fails because login must not return unstored refresh credentials", async () => {
  const env = createTestEnv();
  const db = fakeD1(env);

  db.users.push({
    id: "run-failure-login-user",
    email: "run-failure-login@example.com",
    password_hash: await hashPassword("correct-password"),
    display_name: null,
    created_at: "2026-07-03T00:00:00.000Z",
    updated_at: "2026-07-03T00:00:00.000Z",
    deleted_at: null,
  });
  db.failNextRun = true;

  const response = await requestLogin(env, {
    email: "run-failure-login@example.com",
    password: "correct-password",
  });
  const body = await response.json();

  expect(response.status).toBe(500);
  expect(body).toEqual({
    success: false,
    error: {
      code: "INTERNAL_ERROR",
      message: "Something went wrong. Please try again.",
    },
  });
  expect(db.sessions).toHaveLength(0);
});
```

- [ ] **Step 4: Run tests**

Run:

```powershell
pnpm --filter @kando/workers-api run test
```

Expected: all `workers-api` tests pass.

- [ ] **Step 5: Commit failure coverage**

```powershell
git add apps/workers-api/src/auth/anonymous.test.ts
git commit -m "test(auth): cover email login failures"
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
- `workers-api` tests pass.
- `tsc --noEmit` exits 0.
- `wrangler deploy --dry-run --outdir dist` exits 0. If sandbox blocks Wrangler log writes but the command otherwise succeeds, rerun the same build command with approved sandbox escalation and record the clean result.

- [ ] **Step 3: Verify repository-level checks**

Run:

```powershell
pnpm run lint
pnpm run type-check
pnpm run build -- --force
```

Expected:
- dependency direction lint passes.
- Turbo type-check succeeds.
- forced Turbo build succeeds. If Wrangler needs to write logs outside the sandbox, rerun with approved sandbox escalation.

- [ ] **Step 4: Check git status**

Run:

```powershell
git status --short --branch
git log -5 --oneline
```

Expected:
- Worktree is clean.
- Recent log includes the Email login implementation commits.
