# M1 Email 登录流程设计

## 背景

当前 M1 已完成匿名账号、`GET /api/v1/auth/me`、`POST /api/v1/auth/token/refresh`、`POST /api/v1/auth/logout`，以及 Email 注册流程。注册流程已经在 `packages/auth-core` 中提供 PBKDF2-SHA256 版本化密码哈希，并在 user session 中只保存 refresh token hash。

本切片补齐 `POST /api/v1/auth/login`，让已注册的 Email 用户可以用邮箱和密码登录，并得到新的 user session。登录已有账号时不迁移、不合并当前游客资产。

## 范围

包含：

- `POST /api/v1/auth/login`。
- Email trim 后转小写，并沿用现有 Email 格式校验。
- 使用 `auth-core.verifyPassword` 校验 PBKDF2 版本化密码哈希。
- 登录成功后创建 `owner_type='user'` 的 session。
- refresh token 只存 hash，响应只返回一次明文 refresh token。
- 返回 access token、refresh token 和 `expires_in=900`。
- Workers 侧测试覆盖成功路径、错误路径和 session 写入语义。

不包含：

- 找回密码流程。
- Google / Apple OAuth。
- 匿名资产迁移或合并。
- Flutter Auth UI。
- 数据库 schema 或 migration 变更。
- 密码哈希算法变更。

## 路由组织

新增 `apps/workers-api/src/auth/login.ts`，由现有 `authRoutes` 注册。保持当前 `/api/v1/auth` 路由结构，不重命名 `anonymous.ts`，避免把本切片扩大成 auth 模块重构。

`login.ts` 只负责 Email 密码登录。注册、刷新、登出、当前账号查询继续留在现有模块中。

## 接口行为

`POST /auth/login` 请求体：

```json
{
  "email": "user@example.com",
  "password": "plain-password"
}
```

成功响应：

```json
{
  "success": true,
  "data": {
    "user_id": "01JXXXXXX",
    "email": "user@example.com",
    "access_token": "eyJ...",
    "refresh_token": "plain-refresh-token",
    "expires_in": 900
  }
}
```

处理流程：

1. 解析 JSON 请求体。
2. 读取 `email` 与 `password`。
3. `email` 做 trim 和 lowercase。
4. Email 为空返回 `422 / VALIDATION_ERROR / Please enter your email.`。
5. Email 格式错误或超过 254 字符返回 `422 / VALIDATION_ERROR / Please enter a valid email address.`。
6. password 不是非空字符串时，返回 `422 / VALIDATION_ERROR / Incorrect password. Please try again.`。
7. 查找 `user`：仅接受 `email = ?`、`deleted_at IS NULL`、`password_hash IS NOT NULL` 的正式 Email 账号。
8. 用户不存在、账号已软删除、OAuth-only 用户、密码错误，统一返回 `422 / VALIDATION_ERROR / Incorrect password. Please try again.`。
9. 密码正确后生成 session id、refresh token、refresh token hash、access token。
10. 写入 `session(owner_type='user', owner_id=user.id, refresh_token=<hash>, expires_at, created_at, revoked_at=NULL)`。
11. 返回登录成功响应。

## 安全口径

登录接口不暴露账号是否存在、是否软删除、是否 OAuth-only。除 Email 为空和格式错误外，认证失败统一使用密码错误响应：

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Incorrect password. Please try again."
  }
}
```

软删除账号同样按认证失败处理，不返回专用文案。

## 错误处理

- JSON 解析失败：`422 / VALIDATION_ERROR / Please enter your email.`。
- Email 为空：`422 / VALIDATION_ERROR / Please enter your email.`。
- Email 格式错误或超过 254 字符：`422 / VALIDATION_ERROR / Please enter a valid email address.`。
- password 缺失、为空、账号不可登录或密码错误：`422 / VALIDATION_ERROR / Incorrect password. Please try again.`。
- `JWT_SECRET` 缺失或空白：`500 / INTERNAL_ERROR / Something went wrong. Please try again.`。
- D1 查询或写入失败：`500 / INTERNAL_ERROR / Something went wrong. Please try again.`。

## 数据与依赖

读取：

- `user.id`
- `user.email`
- `user.password_hash`
- `user.deleted_at`

写入：

- `session.id`
- `session.owner_type = 'user'`
- `session.owner_id = user.id`
- `session.refresh_token = hashRefreshToken(refreshToken)`
- `session.expires_at = refreshTokenExpiresAt(now)`
- `session.created_at = now`
- `session.revoked_at = NULL`

依赖 `packages/auth-core`：

- `verifyPassword`
- `createRefreshToken`
- `hashRefreshToken`
- `refreshTokenExpiresAt`
- `signAccessToken`
- `ACCESS_TOKEN_EXPIRES_IN_SECONDS`

## 测试策略

`apps/workers-api`：

- 注册创建的 Email 用户可以登录，因为登录必须兼容注册写入的 PBKDF2 密码哈希。
- 登录成功返回 user access token，并且该 token 可调用 `/auth/me`。
- 登录成功创建 user session，refresh token 只存 hash，不存明文。
- Email 大小写和首尾空格归一化后仍可登录。
- 未知邮箱返回统一密码错误响应。
- 错误密码返回统一密码错误响应。
- 软删除用户返回统一密码错误响应。
- `password_hash IS NULL` 的 OAuth-only 用户返回统一密码错误响应。
- password 为空返回统一密码错误响应。
- `JWT_SECRET` 缺失返回 500，且不创建 session。
- session 写入失败返回 500。

`packages/auth-core`：

- 本切片不新增密码哈希算法测试；复用已有 `verifyPassword` 覆盖。

## 验收标准

- `POST /api/v1/auth/login` 行为符合本设计。
- 登录成功后返回的 access token 可识别为 `owner_type='user'`。
- 登录成功后 refresh token 明文不会写入 D1。
- 登录已有账号不迁移、不合并匿名资产。
- 不修改数据库 schema。
- 不实现找回密码、OAuth 或 Flutter UI。
- 本地聚焦验证通过：
  - `pnpm --filter @kando/auth-core run test`
  - `pnpm --filter @kando/auth-core run type-check`
  - `pnpm --filter @kando/auth-core run build`
  - `pnpm --filter @kando/workers-api run test`
  - `pnpm --filter @kando/workers-api run type-check`
  - `pnpm --filter @kando/workers-api run build`

## 风险

- 当前 FakeD1 测试集中在 `anonymous.test.ts`，新增登录测试会继续扩展同一测试夹具，短期内文件会继续变大。实现阶段应只补必要 SQL 分支，不做测试框架重构。
- 账号枚举防护会让“未注册邮箱”和“密码错误”对后端响应不可区分；这是本设计的明确取舍，客户端若要切换到注册流程，应继续依赖注册发送验证码接口的 `409 / CONFLICT` 口径，而不是登录接口。
