# M1 鉴权验证与当前账号实施计划

> **给执行代理的要求：** 执行本计划时必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`。所有任务使用 checkbox（`- [ ]`）追踪进度。

**目标：** 实现 access token 验签基础能力和 `GET /api/v1/auth/me`，让匿名账号创建后返回的 token 能被后续受保护接口识别。

**架构：** `packages/auth-core` 负责 HS256 JWT 验签和 payload 校验，保持与 Workers 业务表解耦。`apps/workers-api` 增加 Bearer token 解析和当前 owner 查询逻辑，并在现有 `/api/v1/auth` 路由组内注册 `/me`。本切片只验证 access token，不实现 refresh/logout/Email/OAuth。

**技术栈：** TypeScript、Hono、Cloudflare Workers、D1、Web Crypto、Vitest、pnpm、Turborepo、Wrangler。

---

## 范围与前提

- 只实现 `verifyAccessToken`、Workers 鉴权 helper、`GET /api/v1/auth/me`。
- 不实现 `POST /auth/token/refresh`、`POST /auth/logout`、Email 注册、OAuth、密码哈希、Flutter UI。
- access token 使用上一切片签发的 HS256 JWT。
- 验签必须检查：三段 JWT、header `alg=HS256` 且 `typ=JWT`、签名匹配、`exp` 未过期、payload 中 `owner_type` / `owner_id` / `session_id` 类型合法。
- `/auth/me` 只需支持匿名账号和正式账号查询，但测试优先覆盖匿名账号；正式账号查询按 `user` 表结构返回。
- session 是否已吊销留给 refresh/logout 切片统一处理。本切片仅通过 access token 验签识别 owner，不查询 `session.revoked_at`。

## 文件结构

- 修改 `packages/auth-core/src/index.ts`：导出 `VerifiedAccessTokenPayload` 和 `verifyAccessToken`。
- 修改 `packages/auth-core/src/index.test.ts`：补验签成功、签名错误、过期、结构错误测试。
- 新增 `apps/workers-api/src/auth/current.ts`：实现 Bearer token 解析、鉴权错误响应、`GET /me` 当前账号查询。
- 修改 `apps/workers-api/src/auth/anonymous.ts`：在同一个 `authRoutes` 上注册 `GET /me`，或从 `current.ts` 导入注册函数。
- 修改 `apps/workers-api/src/auth/anonymous.test.ts`：扩展 fake D1 支持当前账号查询，并补匿名账号创建后调用 `/auth/me` 的集成测试。
- 可新增 `apps/workers-api/src/auth/current.test.ts`：若把 `/auth/me` 独立测试更清晰，则创建该文件。

---

### 任务 1：为 auth-core 补 access token 验签

**文件：**
- 修改：`packages/auth-core/src/index.ts`
- 修改：`packages/auth-core/src/index.test.ts`

- [x] **步骤 1：先写失败测试**

在 `packages/auth-core/src/index.test.ts` 中新增测试：

- `verifyAccessToken` 能验证 `signAccessToken` 生成的 token，并返回 `owner_type`、`owner_id`、`session_id`、`iat`、`exp`。
- 使用错误 secret 验签返回失败。
- 过期 token 返回失败。
- 非三段 token、非 JSON header/payload、`alg` 不是 `HS256`、payload 缺字段时返回失败。

建议 API 设计：

```ts
export interface VerifiedAccessTokenPayload extends AccessTokenPayload {
  iat: number;
  exp: number;
}

export type VerifyAccessTokenResult =
  | { valid: true; payload: VerifiedAccessTokenPayload }
  | { valid: false; reason: "malformed" | "invalid_signature" | "expired" };

export async function verifyAccessToken(
  token: string,
  secret: string,
  now = new Date(),
): Promise<VerifyAccessTokenResult>;
```

运行：

```powershell
pnpm --filter @kando/auth-core run test
```

预期：RED，失败原因是 `verifyAccessToken` 未导出。

- [x] **步骤 2：实现最小验签代码**

在 `packages/auth-core/src/index.ts` 中实现：

- base64url decode helper。
- constant-time-ish 签名比较：长度不等直接 invalid；长度相等时逐字节 XOR 累积比较。
- secret 为空时抛出 `JWT secret is required.`，与 `signAccessToken` 保持一致。
- `exp <= nowSeconds` 判定为过期。

不要导出内部编码/解码 helper。

- [x] **步骤 3：验证 auth-core**

运行：

```powershell
pnpm --filter @kando/auth-core run test
pnpm --filter @kando/auth-core run type-check
pnpm --filter @kando/auth-core run build
```

预期：全部通过。

---

### 任务 2：实现 Workers 鉴权 helper 与 `/auth/me`

**文件：**
- 新增：`apps/workers-api/src/auth/current.ts`
- 修改：`apps/workers-api/src/auth/anonymous.ts`
- 修改：`apps/workers-api/src/auth/anonymous.test.ts`

- [x] **步骤 1：写 `/auth/me` 失败测试**

在 Workers 测试中新增用例：

- 先调用 `POST /api/v1/auth/anonymous` 获取 `access_token`。
- 再带 `Authorization: Bearer <access_token>` 调 `GET /api/v1/auth/me`。
- 断言响应：

```json
{
  "success": true,
  "data": {
    "owner_type": "anonymous",
    "user_id": null,
    "anonymous_id": "<anonymous_id>",
    "email": null,
    "display_name": null,
    "created_at": "<anonymous_account.created_at>"
  }
}
```

同时新增错误用例：

- 缺少 `Authorization` 返回 `401 / UNAUTHORIZED`。
- `Authorization` 不是 `Bearer <token>` 返回 `401 / UNAUTHORIZED`。
- token 签名错误返回 `401 / UNAUTHORIZED`。
- token 过期返回 `401 / UNAUTHORIZED`。

运行：

```powershell
pnpm --filter @kando/workers-api run test
```

预期：RED，失败原因是 `/auth/me` 未实现。

- [x] **步骤 2：实现 `current.ts`**

创建 `apps/workers-api/src/auth/current.ts`，导出：

```ts
export function registerCurrentAccountRoutes(
  routes: Hono<{ Bindings: Env }>,
): void;
```

实现细节：

- 从 `Authorization` header 解析 Bearer token。
- 调用 `verifyAccessToken(token, c.env.JWT_SECRET)`。
- 失败统一返回：

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Unauthorized."
  }
}
```

HTTP 状态为 `401`。

- `owner_type = "anonymous"` 时查询：

```sql
SELECT id, created_at
FROM anonymous_account
WHERE id = ? AND upgraded_user_id IS NULL
LIMIT 1
```

返回匿名账号响应。

- `owner_type = "user"` 时查询：

```sql
SELECT id, email, display_name, created_at
FROM user
WHERE id = ? AND deleted_at IS NULL
LIMIT 1
```

返回正式账号响应。

- 查询不到 owner 时返回 `401 / UNAUTHORIZED`，因为 token 指向不存在或不可用账号。

不要在本切片查询 `session.revoked_at`。

- [x] **步骤 3：注册路由**

在 `apps/workers-api/src/auth/anonymous.ts` 中导入并调用：

```ts
import { registerCurrentAccountRoutes } from "./current";

registerCurrentAccountRoutes(authRoutes);
```

保持 `POST /anonymous` 行为不变。

- [x] **步骤 4：验证 Workers**

运行：

```powershell
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

预期：全部通过。

---

### 任务 3：完整验证与提交

**文件：**
- 读取：本计划涉及的所有文件
- 修改：无

- [x] **步骤 1：运行聚焦验证**

```powershell
pnpm --filter @kando/auth-core run test
pnpm --filter @kando/auth-core run type-check
pnpm --filter @kando/auth-core run build
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

预期：全部退出码为 `0`。

- [x] **步骤 2：运行顶层 TS 验证**

```powershell
pnpm run build
pnpm run type-check
pnpm run lint
```

预期：全部退出码为 `0`。若 Wrangler 在沙箱内写用户目录日志出现 EPERM，但 dry-run 完成且 Turbo 退出码为 `0`，记录为环境日志写入问题。

- [x] **步骤 3：检查变更范围**

```powershell
git status --short
git diff --stat
```

预期：变更只包含：

- `packages/auth-core/src/index.ts`
- `packages/auth-core/src/index.test.ts`
- `apps/workers-api/src/auth/current.ts`
- `apps/workers-api/src/auth/anonymous.ts`
- `apps/workers-api/src/auth/anonymous.test.ts`
- `docs/superpowers/plans/2026-07-02-m1-auth-verify-me.md`

如实际新增 `current.test.ts`，也应包含在提交中。

- [x] **步骤 4：提交**

```powershell
git add packages/auth-core/src/index.ts packages/auth-core/src/index.test.ts apps/workers-api/src/auth/current.ts apps/workers-api/src/auth/anonymous.ts apps/workers-api/src/auth/anonymous.test.ts docs/superpowers/plans/2026-07-02-m1-auth-verify-me.md
git commit -m "feat(m1): add auth verification and me endpoint"
```

---

## 自检记录

- 覆盖 `api-spec.md` §1.2 和 §2.14：Bearer token、当前账号响应、401 错误。
- 明确不包含 refresh/logout/Email/OAuth。
- `session.revoked_at` 校验留给 token refresh/logout 切片处理，避免本切片扩大为完整 session 生命周期管理。
- 剩余风险：上一切片记录的同 `device_id` 并发首启唯一性仍需后续 schema/迁移小切片处理。
