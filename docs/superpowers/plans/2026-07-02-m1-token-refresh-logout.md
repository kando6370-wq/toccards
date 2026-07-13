# M1 Token 刷新与登出 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 `POST /api/v1/auth/token/refresh` 与 `POST /api/v1/auth/logout`，补齐当前匿名账号 session 的刷新和吊销闭环。

**Architecture:** `packages/auth-core` 继续只提供 token/hash helpers；`apps/workers-api` 新增独立 `session.ts` 路由模块负责 refresh/logout 的 HTTP 解析、D1 session 查询、owner 可用性校验和 session 吊销。现有 `authRoutes` 继续作为 `/api/v1/auth` 路由组入口。

**Tech Stack:** TypeScript、Hono、Cloudflare Workers、D1、Web Crypto、Vitest、pnpm、Wrangler。

---

## 范围与前提

- 只实现 `POST /api/v1/auth/token/refresh` 与 `POST /api/v1/auth/logout`。
- 不实现滚动 refresh token；刷新成功只返回新的 `access_token` 与 `expires_in`。
- 不实现 Email、OAuth、注册迁移、删除账号、Flutter token 管理或 schema 迁移。
- refresh token 入参是明文，查询前必须用 `hashRefreshToken` 转为入库 hash。
- session 可用条件：`revoked_at IS NULL` 且 `expires_at > now`。
- refresh 必须确认 owner 仍可用：匿名账号未升级，正式账号未软删。
- logout 必须绑定 access token 中的 `session_id`、`owner_type`、`owner_id`，不能用 A 的 access token 吊销 B 的 refresh token。
- `JWT_SECRET` 为空是服务端配置错误，返回 `500 / INTERNAL_ERROR`。

## 文件结构

- 新增 `apps/workers-api/src/auth/session.ts`：refresh/logout 路由注册与 session 查询/吊销逻辑。
- 修改 `apps/workers-api/src/auth/anonymous.ts`：导入并注册 `registerSessionRoutes(authRoutes)`。
- 修改 `apps/workers-api/src/auth/anonymous.test.ts`：扩展 FakeD1 的 session 查询与更新能力，补 refresh/logout 集成测试。
- 本计划默认不修改 `packages/auth-core`；如实现时发现 helper 缺口，先停止并报告具体缺口，不直接扩大范围。

---

### Task 1: 实现 `POST /auth/token/refresh`

**Files:**
- Create: `apps/workers-api/src/auth/session.ts`
- Modify: `apps/workers-api/src/auth/anonymous.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: 写 refresh 失败测试**

在 `apps/workers-api/src/auth/anonymous.test.ts` 中扩展 FakeD1：

```ts
type SessionLookupRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

const SELECT_SESSION_BY_REFRESH_TOKEN_SQL = normalizeSql(`
  SELECT id, owner_type, owner_id, expires_at, revoked_at
  FROM session
  WHERE refresh_token = ?
  LIMIT 1
`);

const SELECT_REFRESH_ANONYMOUS_OWNER_SQL = normalizeSql(`
  SELECT id
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`);

const SELECT_REFRESH_USER_OWNER_SQL = normalizeSql(`
  SELECT id
  FROM user
  WHERE id = ? AND deleted_at IS NULL
  LIMIT 1
`);
```

在 `FakeD1.first` 中新增三段匹配：

```ts
if (normalizedSql === SELECT_SESSION_BY_REFRESH_TOKEN_SQL) {
  const [refreshTokenHash] = values as [string];
  const session = this.sessions.find(
    (row) => row.refresh_token === refreshTokenHash,
  );

  return session
    ? ({
        id: session.id,
        owner_type: session.owner_type,
        owner_id: session.owner_id,
        expires_at: session.expires_at,
        revoked_at: session.revoked_at,
      } as T)
    : null;
}

if (normalizedSql === SELECT_REFRESH_ANONYMOUS_OWNER_SQL) {
  const [id] = values as [string];
  const account = this.anonymousAccounts.find(
    (row) => row.id === id && row.upgraded_user_id === null,
  );

  return account ? ({ id: account.id } as T) : null;
}

if (normalizedSql === SELECT_REFRESH_USER_OWNER_SQL) {
  const [id] = values as [string];
  const user = this.users.find(
    (row) => row.id === id && row.deleted_at === null,
  );

  return user ? ({ id: user.id } as T) : null;
}
```

新增请求 helper：

```ts
async function requestTokenRefresh(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/token/refresh",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}
```

新增测试：

```ts
describe("POST /api/v1/auth/token/refresh", () => {
  it("returns a new access token for a live anonymous session because short-lived bearer tokens must be renewable", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-refresh");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestTokenRefresh(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = (await response.json()) as {
      success: true;
      data: { access_token: string; expires_in: number; refresh_token?: string };
    };

    expect(response.status).toBe(200);
    expect(body).toMatchObject({
      success: true,
      data: {
        access_token: expect.any(String),
        expires_in: 900,
      },
    });
    expect(body.data.refresh_token).toBeUndefined();

    const meResponse = await requestCurrentAccount(
      env,
      `Bearer ${body.data.access_token}`,
    );
    const meBody = (await meResponse.json()) as CurrentAccountSuccessResponse;

    expect(meResponse.status).toBe(200);
    expect(meBody.data).toMatchObject({
      owner_type: "anonymous",
      anonymous_id: anonymousBody.data.anonymous_id,
    });
  });

  it("returns 422 / VALIDATION_ERROR when refresh_token is blank because request shape is invalid", async () => {
    const env = createTestEnv();

    const response = await requestTokenRefresh(env, { refresh_token: "   " });
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toMatchObject({
      success: false,
      error: { code: "VALIDATION_ERROR" },
    });
  });

  it("returns 401 / UNAUTHORIZED for an unknown refresh token because bearer renewal requires a live session", async () => {
    const env = createTestEnv();

    const response = await requestTokenRefresh(env, {
      refresh_token: "missing-refresh-token",
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED for an expired session because refresh tokens are bounded by session lifetime", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-expired-refresh");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    fakeD1(env).sessions[0]!.expires_at = "2000-01-01T00:00:00.000Z";

    const response = await requestTokenRefresh(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED for a revoked session because logout must disable future refresh", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-revoked-refresh");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    fakeD1(env).sessions[0]!.revoked_at = "2026-07-02T00:00:00.000Z";

    const response = await requestTokenRefresh(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED when the session owner is no longer usable because credentials must map to a live account", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-upgraded-refresh");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    fakeD1(env).anonymousAccounts[0]!.upgraded_user_id = "user-id";

    const response = await requestTokenRefresh(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 500 / INTERNAL_ERROR when JWT_SECRET is blank because signing renewed tokens depends on server configuration", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-refresh-secret");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    env.JWT_SECRET = "   ";

    const response = await requestTokenRefresh(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expect(response.status).toBe(500);
    expect(body).toMatchObject({
      success: false,
      error: { code: "INTERNAL_ERROR" },
    });
  });
});
```

- [ ] **Step 2: 运行 RED**

```powershell
pnpm --filter @kando/workers-api run test
```

预期：新增 refresh 测试失败，主要原因是 `/api/v1/auth/token/refresh` 尚未注册，返回 `404`。

- [ ] **Step 3: 实现 refresh 路由**

创建 `apps/workers-api/src/auth/session.ts`，写入以下结构：

```ts
import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  hashRefreshToken,
  signAccessToken,
} from "@kando/auth-core";
import type { Hono, HonoRequest } from "hono";
import type { Env } from "../env";

type OwnerType = "anonymous" | "user";

type SessionLookupRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

const VALIDATION_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "refresh_token is required.",
  },
} as const;

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

const SELECT_SESSION_BY_REFRESH_TOKEN_SQL = `
  SELECT id, owner_type, owner_id, expires_at, revoked_at
  FROM session
  WHERE refresh_token = ?
  LIMIT 1
`;

const SELECT_REFRESH_ANONYMOUS_OWNER_SQL = `
  SELECT id
  FROM anonymous_account
  WHERE id = ? AND upgraded_user_id IS NULL
  LIMIT 1
`;

const SELECT_REFRESH_USER_OWNER_SQL = `
  SELECT id
  FROM user
  WHERE id = ? AND deleted_at IS NULL
  LIMIT 1
`;

export function registerSessionRoutes(routes: Hono<{ Bindings: Env }>): void {
  routes.post("/token/refresh", async (c) => {
    const refreshToken = await readRefreshToken(c.req);

    if (!refreshToken) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    if (!hasJwtSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    const now = new Date();
    const session = await findLiveSession(c.env.DB, refreshToken, now);

    if (!session || !(await ownerExists(c.env.DB, session))) {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const accessToken = await signAccessToken(
      {
        owner_type: session.owner_type,
        owner_id: session.owner_id,
        session_id: session.id,
      },
      c.env.JWT_SECRET,
      now,
    );

    return c.json({
      success: true,
      data: {
        access_token: accessToken,
        expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
      },
    });
  });
}

async function readRefreshToken(req: HonoRequest): Promise<string | null> {
  try {
    const body = await req.json();
    const refreshToken =
      body && typeof body === "object"
        ? (body as { refresh_token?: unknown }).refresh_token
        : undefined;

    return typeof refreshToken === "string" && refreshToken.trim().length > 0
      ? refreshToken
      : null;
  } catch {
    return null;
  }
}

function hasJwtSecret(secret: string): boolean {
  return typeof secret === "string" && secret.trim().length > 0;
}

async function findLiveSession(
  db: D1Database,
  refreshToken: string,
  now: Date,
): Promise<SessionLookupRow | null> {
  const refreshTokenHash = await hashRefreshToken(refreshToken);
  const session = await db
    .prepare(SELECT_SESSION_BY_REFRESH_TOKEN_SQL)
    .bind(refreshTokenHash)
    .first<SessionLookupRow>();

  if (!session || session.revoked_at !== null || !isFutureIso(session.expires_at, now)) {
    return null;
  }

  return session;
}

function isFutureIso(value: string, now: Date): boolean {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) && timestamp > now.getTime();
}

async function ownerExists(
  db: D1Database,
  session: SessionLookupRow,
): Promise<boolean> {
  if (session.owner_type === "anonymous") {
    const account = await db
      .prepare(SELECT_REFRESH_ANONYMOUS_OWNER_SQL)
      .bind(session.owner_id)
      .first<{ id: string }>();

    return account !== null;
  }

  const user = await db
    .prepare(SELECT_REFRESH_USER_OWNER_SQL)
    .bind(session.owner_id)
    .first<{ id: string }>();

  return user !== null;
}
```

- [ ] **Step 4: 注册 refresh 路由**

在 `apps/workers-api/src/auth/anonymous.ts` 增加导入：

```ts
import { registerSessionRoutes } from "./session";
```

在 `authRoutes` 创建后注册：

```ts
registerCurrentAccountRoutes(authRoutes);
registerSessionRoutes(authRoutes);
```

- [ ] **Step 5: 验证 refresh**

```powershell
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

预期：全部退出码为 `0`。

---

### Task 2: 实现 `POST /auth/logout`

**Files:**
- Modify: `apps/workers-api/src/auth/session.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: 写 logout 失败测试**

在 `apps/workers-api/src/auth/anonymous.test.ts` 中新增 SQL 常量：

```ts
const UPDATE_SESSION_REVOKED_AT_SQL = normalizeSql(`
  UPDATE session
  SET revoked_at = ?
  WHERE id = ? AND revoked_at IS NULL
`);
```

在 `FakeD1.run` 中新增：

```ts
if (normalizedSql === UPDATE_SESSION_REVOKED_AT_SQL) {
  const [revokedAt, id] = values as [string, string];
  const session = this.sessions.find(
    (row) => row.id === id && row.revoked_at === null,
  );

  if (session) {
    session.revoked_at = revokedAt;
  }

  return okResult<T>();
}
```

新增请求 helper：

```ts
async function requestLogout(
  env: TestEnv,
  authorization: string | undefined,
  body: unknown,
): Promise<Response> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };

  if (authorization) {
    headers.Authorization = authorization;
  }

  return app.request(
    "/api/v1/auth/logout",
    {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    },
    env,
  );
}
```

新增测试：

```ts
describe("POST /api/v1/auth/logout", () => {
  it("revokes the current session because logout must disable the matching refresh token", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-logout");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestLogout(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
      { refresh_token: anonymousBody.data.refresh_token },
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({ success: true, data: {} });
    expect(fakeD1(env).sessions[0]?.revoked_at).toEqual(expect.any(String));
  });

  it("prevents refresh after logout because revoked sessions must not mint new access tokens", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-logout-refresh");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    await requestLogout(env, `Bearer ${anonymousBody.data.access_token}`, {
      refresh_token: anonymousBody.data.refresh_token,
    });

    const response = await requestTokenRefresh(env, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 401 / UNAUTHORIZED when access token and refresh token belong to different sessions", async () => {
    const env = createTestEnv();
    const firstResponse = await requestAnonymous(env, "device-mismatch");
    const firstBody = (await firstResponse.json()) as AnonymousSuccessResponse;
    const secondResponse = await requestAnonymous(env, "device-mismatch");
    const secondBody = (await secondResponse.json()) as AnonymousSuccessResponse;

    const response = await requestLogout(env, `Bearer ${firstBody.data.access_token}`, {
      refresh_token: secondBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
    expect(fakeD1(env).sessions.every((session) => session.revoked_at === null)).toBe(true);
  });

  it("returns 401 / UNAUTHORIZED without Authorization because logout must be bound to a bearer session", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-logout-missing-auth");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestLogout(env, undefined, {
      refresh_token: anonymousBody.data.refresh_token,
    });
    const body = await response.json();

    expectUnauthorized(body, response.status);
  });

  it("returns 422 / VALIDATION_ERROR when refresh_token is blank because logout needs the session secret", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-logout-validation");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;

    const response = await requestLogout(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
      { refresh_token: "   " },
    );
    const body = await response.json();

    expect(response.status).toBe(422);
    expect(body).toMatchObject({
      success: false,
      error: { code: "VALIDATION_ERROR" },
    });
  });

  it("returns 500 / INTERNAL_ERROR when JWT_SECRET is blank because logout depends on access-token verification", async () => {
    const env = createTestEnv();
    const anonymousResponse = await requestAnonymous(env, "device-logout-secret");
    const anonymousBody =
      (await anonymousResponse.json()) as AnonymousSuccessResponse;
    env.JWT_SECRET = "   ";

    const response = await requestLogout(
      env,
      `Bearer ${anonymousBody.data.access_token}`,
      { refresh_token: anonymousBody.data.refresh_token },
    );
    const body = await response.json();

    expect(response.status).toBe(500);
    expect(body).toMatchObject({
      success: false,
      error: { code: "INTERNAL_ERROR" },
    });
  });
});
```

- [ ] **Step 2: 运行 RED**

```powershell
pnpm --filter @kando/workers-api run test
```

预期：新增 logout 测试失败，主要原因是 `/api/v1/auth/logout` 尚未注册，返回 `404`。

- [ ] **Step 3: 实现 logout 路由**

将 `apps/workers-api/src/auth/session.ts` 顶部 auth-core 导入调整为：

```ts
import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  hashRefreshToken,
  signAccessToken,
  verifyAccessToken,
} from "@kando/auth-core";
```

新增 SQL：

```ts
const UPDATE_SESSION_REVOKED_AT_SQL = `
  UPDATE session
  SET revoked_at = ?
  WHERE id = ? AND revoked_at IS NULL
`;
```

在 `registerSessionRoutes` 中追加：

```ts
routes.post("/logout", async (c) => {
  const token = getBearerToken(c.req.header("Authorization"));

  if (!token) {
    return c.json(UNAUTHORIZED_RESPONSE, 401);
  }

  if (!hasJwtSecret(c.env.JWT_SECRET)) {
    return c.json(INTERNAL_ERROR_RESPONSE, 500);
  }

  const verification = await verifyAccessToken(token, c.env.JWT_SECRET);

  if (!verification.valid) {
    return c.json(UNAUTHORIZED_RESPONSE, 401);
  }

  const refreshToken = await readRefreshToken(c.req);

  if (!refreshToken) {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }

  const now = new Date();
  const session = await findLiveSession(c.env.DB, refreshToken, now);

  if (
    !session ||
    session.id !== verification.payload.session_id ||
    session.owner_type !== verification.payload.owner_type ||
    session.owner_id !== verification.payload.owner_id
  ) {
    return c.json(UNAUTHORIZED_RESPONSE, 401);
  }

  await c.env.DB.prepare(UPDATE_SESSION_REVOKED_AT_SQL)
    .bind(now.toISOString(), session.id)
    .run();

  return c.json({ success: true, data: {} });
});
```

在同文件新增 Bearer helper：

```ts
function getBearerToken(authorization: string | undefined): string | null {
  if (!authorization) {
    return null;
  }

  const [scheme, token, extra] = authorization.trim().split(/\s+/);

  if (scheme !== "Bearer" || !token || extra) {
    return null;
  }

  return token;
}
```

- [ ] **Step 4: 验证 logout**

```powershell
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

预期：全部退出码为 `0`。

---

### Task 3: 完整验证与提交

**Files:**
- Read: `docs/superpowers/specs/2026-07-02-m1-token-refresh-logout-design.md`
- Read: `docs/superpowers/plans/2026-07-02-m1-token-refresh-logout.md`
- Read: 本计划涉及的所有代码文件

- [ ] **Step 1: 运行聚焦验证**

```powershell
pnpm --filter @kando/auth-core run test
pnpm --filter @kando/auth-core run type-check
pnpm --filter @kando/auth-core run build
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

预期：全部退出码为 `0`。

- [ ] **Step 2: 运行顶层 TS 验证**

```powershell
pnpm run build
pnpm run type-check
pnpm run lint
```

预期：全部退出码为 `0`。若 Wrangler 写用户目录日志出现 `EPERM`，但 dry-run 完成且 Turbo 退出码为 `0`，记录为环境日志写入问题。

- [ ] **Step 3: 检查变更范围**

```powershell
git status --short
git diff --stat
git diff --check
```

预期变更只包含：

- `apps/workers-api/src/auth/session.ts`
- `apps/workers-api/src/auth/anonymous.ts`
- `apps/workers-api/src/auth/anonymous.test.ts`
- `docs/superpowers/plans/2026-07-02-m1-token-refresh-logout.md`

若实际修改了 `packages/auth-core`，必须说明具体 helper 缺口和对应测试。

- [ ] **Step 4: 提交**

```powershell
git add apps/workers-api/src/auth/session.ts apps/workers-api/src/auth/anonymous.ts apps/workers-api/src/auth/anonymous.test.ts docs/superpowers/plans/2026-07-02-m1-token-refresh-logout.md
git diff --cached --check
git commit -m "feat(m1): add token refresh and logout"
```

---

## 自检记录

- 覆盖已确认 spec：`docs/superpowers/specs/2026-07-02-m1-token-refresh-logout-design.md`。
- 明确不实现滚动 refresh token。
- 明确不实现 Email/OAuth/注册迁移/Flutter/schema。
- logout 绑定 access token session，防止跨 session 吊销。
- refresh 成功后可用新 access token 调 `/auth/me`，验证 owner 仍可识别。
