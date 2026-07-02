# M1 匿名账号实施计划

> **给执行代理的要求：** 执行本计划时必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`。所有任务使用 checkbox（`- [ ]`）追踪进度。

**目标：** 实现 `POST /api/v1/auth/anonymous` 最小闭环，让 App 能创建或复用匿名账号，拿到 token，并在 D1 中初始化默认 Portfolio 文件夹和用户偏好。

**架构：** `packages/auth-core` 只负责通用鉴权能力，包括 access token 签发、refresh token 生成与哈希，不依赖 tcg-card 业务表。`apps/workers-api` 负责 HTTP 校验、D1 写入、session 持久化和 `/api/v1/auth` 路由注册。本切片优先使用 D1 prepared statements，保持实现直接、可验证。

**技术栈：** TypeScript、Hono、Cloudflare Workers、D1、Web Crypto、Vitest、pnpm、Turborepo、Wrangler。

---

## 范围与前提

- 只实现匿名账号创建/复用，不实现 Email 注册、OAuth、找回密码、Flutter Auth UI、token refresh、logout 或删除账号。
- 对外路径为 `POST /api/v1/auth/anonymous`，因为当前 Workers 已在 `apps/workers-api/src/index.ts` 挂载 `/api/v1`。
- access token 有效期固定为 `900` 秒，对齐 `api-spec.md` §2.1。
- refresh token 有效期本切片先定为 `30` 天，因为 `session.expires_at` 必填，现有产品文档没有定义更短时长。
- Workers 环境必须提供 `JWT_SECRET`。测试中以内存 env 注入；本地 `wrangler dev` 使用被忽略的 `apps/workers-api/.dev.vars`。
- 匿名账号复用条件为 `device_id = request.device_id` 且 `upgraded_user_id IS NULL`。
- 不给 `anonymous_account.device_id` 增加唯一约束。理由：同一设备的游客账号升级后，后续仍应允许创建新的匿名账号。

## 文件结构

- 修改 `packages/auth-core/package.json`：增加 `vitest` 和 `test: vitest run` 脚本。
- 修改 `packages/auth-core/src/index.ts`：导出 owner/session 类型、access token 签发、refresh token 生成、refresh token 哈希和过期常量。
- 新增 `packages/auth-core/src/index.test.ts`：验证 access token payload/signature、refresh token 生成、哈希和过期时间。
- 修改 `packages/auth-core/tsconfig.json`：排除测试文件，避免构建输出测试代码。
- 修改 `apps/workers-api/package.json`：增加 `@kando/auth-core`、`ulid`、`vitest` 和 `test` 脚本。
- 新增 `apps/workers-api/src/env.ts`：集中导出 Workers `Env` 类型。
- 新增 `apps/workers-api/src/auth/anonymous.ts`：实现请求校验、匿名账号查找/创建、session 写入和响应结构。
- 新增 `apps/workers-api/src/auth/anonymous.test.ts`：用轻量 fake D1 验证端点行为。
- 修改 `apps/workers-api/src/index.ts`：注册 `/api/v1/auth` 路由。
- 修改 `.gitignore`：忽略 `apps/workers-api/.dev.vars`，避免提交本地 secret。

---

### 任务 1：补测试入口并写失败用例

**文件：**
- 修改：`apps/workers-api/package.json`
- 新增：`apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **步骤 1：安装依赖并增加 test 脚本**

运行：

```powershell
pnpm --filter @kando/workers-api add @kando/auth-core@workspace:* ulid
pnpm --filter @kando/workers-api add -D vitest
```

确认 `apps/workers-api/package.json` 至少包含：

```json
{
  "scripts": {
    "dev": "wrangler dev",
    "build": "wrangler deploy --dry-run --outdir dist",
    "type-check": "tsc --noEmit -p tsconfig.json",
    "test": "vitest run",
    "db:generate": "drizzle-kit generate",
    "db:migrate:local": "wrangler d1 migrations apply kando-db --local"
  },
  "dependencies": {
    "@kando/auth-core": "workspace:*",
    "drizzle-orm": "^0.38.0",
    "hono": "^4.6.0",
    "ulid": "^2.3.0"
  }
}
```

预期：`pnpm-lock.yaml` 只因上述依赖变化而更新。

- [ ] **步骤 2：写匿名账号端点的失败测试**

创建 `apps/workers-api/src/auth/anonymous.test.ts`，覆盖四个意图：

- `device_id` 为空时返回 `422 / VALIDATION_ERROR`，因为无法隔离匿名资产归属。
- 首次请求时创建 `anonymous_account`，同时初始化 `portfolio_folder(Main)`、`user_preference` 和 `session`。
- 相同 `device_id` 且仍为游客时复用同一个 `anonymous_id`，但创建新的 session。
- 相同 `device_id` 只有已升级账号时，不复用旧账号，而是创建新的匿名账号。

测试文件需要导入：

```ts
import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import app from "../index";
```

测试环境使用：

```ts
function createTestEnv(): Env {
  return {
    DB: createFakeD1(),
    CACHE_KV: {} as KVNamespace,
    JWT_SECRET: "test-secret-with-at-least-32-characters",
  };
}
```

同文件内新增 `FakeD1`，包含 `anonymousAccounts`、`portfolioFolders`、`userPreferences`、`sessions` 四个数组，并实现本端点会用到的 D1 行为：

```ts
prepare(sql).bind(...values).first()
prepare(sql).bind(...values).run()
batch(statements)
```

FakeD1 只需要识别本计划列出的 SQL，不做通用 SQL 解析。

- [ ] **步骤 3：确认测试按预期失败**

运行：

```powershell
pnpm --filter @kando/workers-api run test
```

预期：失败原因是 `/api/v1/auth/anonymous` 尚未实现，或 `Env` 尚未声明 `JWT_SECRET`。如果失败原因是依赖安装或测试框架加载错误，先修测试入口，不进入实现。

---

### 任务 2：实现 auth-core 的 token 最小能力

**文件：**
- 修改：`packages/auth-core/package.json`
- 修改：`packages/auth-core/src/index.ts`
- 新增：`packages/auth-core/src/index.test.ts`
- 修改：`packages/auth-core/tsconfig.json`

- [ ] **步骤 1：替换占位导出**

在 `packages/auth-core/src/index.ts` 中实现并导出：

```ts
export type OwnerType = "user" | "anonymous";

export interface AccessTokenPayload {
  owner_type: OwnerType;
  owner_id: string;
  session_id: string;
}

export const ACCESS_TOKEN_EXPIRES_IN_SECONDS = 900;
export const REFRESH_TOKEN_EXPIRES_IN_DAYS = 30;

export async function signAccessToken(
  payload: AccessTokenPayload,
  secret: string,
  now = new Date(),
): Promise<string>;

export function createRefreshToken(): string;

export async function hashRefreshToken(refreshToken: string): Promise<string>;

export function refreshTokenExpiresAt(now = new Date()): string;
```

实现要求：

- `signAccessToken` 使用 Web Crypto HMAC SHA-256 签发 HS256 JWT。
- JWT header 为 `{ "alg": "HS256", "typ": "JWT" }`。
- JWT payload 包含 `owner_type`、`owner_id`、`session_id`、`iat`、`exp`。
- `createRefreshToken` 使用 `crypto.getRandomValues` 生成 32 字节随机值，并转为 base64url 字符串。
- `hashRefreshToken` 使用 SHA-256，将 refresh token 哈希为小写 hex 字符串后入库。
- `refreshTokenExpiresAt` 返回当前时间加 30 天的 ISO 字符串。
- 不新增第三方 JWT 依赖。

- [ ] **步骤 2：补充 auth-core 测试入口**

`packages/auth-core/package.json` 需要包含：

```json
{
  "scripts": {
    "test": "vitest run",
    "type-check": "tsc --noEmit -p tsconfig.json"
  },
  "devDependencies": {
    "vitest": "^4.1.9"
  }
}
```

新增 `packages/auth-core/src/index.test.ts`，覆盖 access token 的 owner/session payload 绑定、HS256 签名、refresh token 随机性、refresh token 哈希和 30 天过期时间。

- [ ] **步骤 3：校验 auth-core 类型和测试**

运行：

```powershell
pnpm --filter @kando/auth-core run test
pnpm --filter @kando/auth-core run type-check
```

预期：通过。

- [ ] **步骤 3：再次运行 Workers 测试**

运行：

```powershell
pnpm --filter @kando/workers-api run test
```

预期：仍因路由未实现而失败。若出现 token helper 编译错误，先修 `packages/auth-core/src/index.ts`。

---

### 任务 3：实现匿名账号路由

**文件：**
- 新增：`apps/workers-api/src/env.ts`
- 新增：`apps/workers-api/src/auth/anonymous.ts`
- 修改：`apps/workers-api/src/index.ts`

- [ ] **步骤 1：新增共享 Env 类型**

创建 `apps/workers-api/src/env.ts`：

```ts
export interface Env {
  DB: D1Database;
  CACHE_KV: KVNamespace;
  JWT_SECRET: string;
}
```

- [ ] **步骤 2：新增匿名账号路由模块**

创建 `apps/workers-api/src/auth/anonymous.ts`。模块导出：

```ts
export const authRoutes = new Hono<{ Bindings: Env }>();
```

端点行为：

- 解析 JSON body，读取并 trim `device_id`。
- `device_id` 为空或不是字符串时返回：

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "device_id is required."
  }
}
```

HTTP 状态为 `422`。

- 查找可复用匿名账号：

```sql
SELECT id
FROM anonymous_account
WHERE device_id = ? AND upgraded_user_id IS NULL
ORDER BY created_at DESC
LIMIT 1
```

- 若不存在，则新建匿名账号，并初始化默认文件夹和偏好：

```sql
INSERT INTO anonymous_account (id, device_id, created_at, upgraded_user_id)
VALUES (?, ?, ?, NULL)
```

```sql
INSERT INTO portfolio_folder
  (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
VALUES (?, 'anonymous', ?, 'Main', 1, 0, ?, ?)
```

```sql
INSERT INTO user_preference
  (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
VALUES (?, 'anonymous', ?, 'USD', 0, NULL, ?, ?)
```

账号、文件夹、偏好三条初始化写入使用 `DB.batch`。session 单独写入；如果 session 写入失败，下次请求可以复用已创建的匿名账号并重新创建 session。

- 每次成功请求都创建一条 session：

```sql
INSERT INTO session
  (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
VALUES (?, 'anonymous', ?, ?, ?, ?, NULL)
```

其中 `refresh_token` 入库存储 `hashRefreshToken(refreshToken)` 的结果，响应返回原始 refresh token。

- 成功响应：

```json
{
  "success": true,
  "data": {
    "anonymous_id": "01JXXXXXX",
    "access_token": "eyJ...",
    "refresh_token": "string",
    "expires_in": 900
  }
}
```

- D1 或 token 签发异常时返回 `500 / INTERNAL_ERROR`，文案为 `Something went wrong. Please try again.`。

- [ ] **步骤 3：注册路由**

修改 `apps/workers-api/src/index.ts`：

```ts
import { Hono } from "hono";
import { authRoutes } from "./auth/anonymous";
import type { Env } from "./env";

const app = new Hono<{ Bindings: Env }>();

const api = app.basePath("/api/v1");

api.get("/health", (c) => c.json({ status: "ok" }));
api.route("/auth", authRoutes);

app.notFound((c) => c.json({ error: "NOT_FOUND" }, 404));

export default app;
```

- [ ] **步骤 4：运行端点测试**

运行：

```powershell
pnpm --filter @kando/workers-api run test
```

预期：通过。若 fake D1 与路由 SQL 不一致，只有在路由 SQL 已对齐本计划和 `api-spec.md` 时，才调整 fake D1。

---

### 任务 4：补本地 secret 防提交规则

**文件：**
- 修改：`.gitignore`

- [ ] **步骤 1：忽略 Workers 本地变量文件**

在 `.gitignore` 增加：

```gitignore
apps/workers-api/.dev.vars
```

- [ ] **步骤 2：本地手工联调时创建 secret**

只在需要本地 `wrangler dev` 时运行：

```powershell
Set-Content -LiteralPath 'apps/workers-api\.dev.vars' -Value 'JWT_SECRET=local-dev-secret-with-at-least-32-characters'
```

预期：`git status --short` 不显示 `apps/workers-api/.dev.vars`。

---

### 任务 5：验证构建、类型和本地 Worker 行为

**文件：**
- 读取：任务 1 到任务 4 涉及的所有文件
- 修改：无

- [ ] **步骤 1：运行聚焦验证**

```powershell
pnpm --filter @kando/auth-core run type-check
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run build
```

预期：全部退出码为 `0`。

- [ ] **步骤 2：运行顶层 TS 验证**

```powershell
pnpm run build
pnpm run type-check
pnpm run lint
```

预期：全部退出码为 `0`。

- [ ] **步骤 3：通过本地 Wrangler 验证端点**

先应用本地 D1 迁移：

```powershell
pnpm --filter @kando/workers-api run db:migrate:local
```

启动 Worker：

```powershell
pnpm --filter @kando/workers-api run dev -- --port 8787 --local
```

另开 shell 调用成功路径：

```powershell
Invoke-WebRequest -Uri 'http://127.0.0.1:8787/api/v1/auth/anonymous' -Method POST -ContentType 'application/json' -Body '{"device_id":"local-device-1"}' -UseBasicParsing
```

预期：HTTP `200`，响应包含 `success: true`、`anonymous_id`、`access_token`、`refresh_token`、`expires_in: 900`。

再调用校验失败路径：

```powershell
Invoke-WebRequest -Uri 'http://127.0.0.1:8787/api/v1/auth/anonymous' -Method POST -ContentType 'application/json' -Body '{"device_id":""}' -UseBasicParsing
```

预期：HTTP `422`，响应包含 `success: false` 和 `error.code: "VALIDATION_ERROR"`。

- [ ] **步骤 4：确认最终变更范围**

```powershell
git status --short
git diff --stat
```

预期：变更只包含本计划列出的文件，以及任务 1 引入依赖导致的 `pnpm-lock.yaml` 更新。

- [ ] **步骤 5：提交本切片**

所有验证通过后运行：

```powershell
git add .gitignore apps/workers-api/package.json apps/workers-api/src/index.ts apps/workers-api/src/env.ts apps/workers-api/src/auth/anonymous.ts apps/workers-api/src/auth/anonymous.test.ts packages/auth-core/package.json packages/auth-core/src/index.ts packages/auth-core/src/index.test.ts packages/auth-core/tsconfig.json pnpm-lock.yaml docs/superpowers/plans/2026-07-02-m1-anonymous-account.md
git commit -m "feat(m1): add anonymous account endpoint"
```

---

## 自检记录

- 覆盖 `api-spec.md` §2.1：请求校验、创建/复用、token 响应、默认文件夹初始化、用户偏好初始化。
- 覆盖数据表：`anonymous_account`、`portfolio_folder`、`user_preference`、`session`。
- 明确不包含：Email、OAuth、Flutter UI、refresh endpoint、logout endpoint、删除账号。
- 已显式处理冲突：不新增 `device_id` 唯一约束，避免同设备升级后无法重新创建游客账号。
- 已记录剩余风险：同 `device_id` 并发首启时，当前 schema 还没有“未升级匿名账号唯一”约束，可能创建多个未升级匿名账号；需后续 schema/迁移小切片处理。
