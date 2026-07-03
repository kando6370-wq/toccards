# M1 Email 注册流程设计

## 背景

当前 M1 已完成匿名账号、`GET /api/v1/auth/me`、`POST /api/v1/auth/token/refresh` 和 `POST /api/v1/auth/logout`。下一步应补齐 `POST /api/v1/auth/register/send-code` 与 `POST /api/v1/auth/register/verify`，让匿名用户可以升级为正式邮箱账号。

邮件服务提供商尚未确定。本切片只实现可测试的注册闭环：验证码记录写入 D1，注册校验验证码后创建正式账号并签发 session。真实邮件发送留给后续接入邮件服务时替换。

## 范围

包含：

- `packages/auth-core` 新增 WebCrypto PBKDF2-SHA256 版本化密码哈希能力。
- `POST /api/v1/auth/register/send-code`。
- `POST /api/v1/auth/register/verify`。
- 邮箱归一化：trim 后转小写。
- 验证码生命周期：6 位数字、注册用途、10 分钟有效、一次性使用。
- 正式账号创建、默认 `portfolio_folder(Main)` 和 `user_preference` 初始化。
- 可选匿名资产迁移到新 user，并回填 `anonymous_account.upgraded_user_id`。
- user session 创建，返回 access token、refresh token 和 `expires_in`。
- Workers 侧测试覆盖成功路径与关键失败路径。

不包含：

- `POST /api/v1/auth/login`。
- 找回密码流程。
- Google / Apple OAuth。
- 真实邮件服务接入。
- 数据库 schema 或迁移变更。
- bcrypt / argon2 依赖接入。
- Flutter Auth UI。

## 设计决策

### 密码哈希

在 `packages/auth-core` 增加：

- `hashPassword(password: string): Promise<string>`
- `verifyPassword(password: string, storedHash: string): Promise<boolean>`

存储格式：

```text
pbkdf2-sha256$v1$<iterations>$<salt_base64url>$<hash_base64url>
```

默认使用 WebCrypto PBKDF2-SHA256，随机 salt，固定迭代次数。`verifyPassword` 必须解析版本字段，只接受当前支持的格式；未知算法或版本返回 `false`，不抛出可见错误。这样后续若升级到 Argon2id，可以通过新前缀做渐进迁移。

### 路由组织

新增 `apps/workers-api/src/auth/register.ts`，由现有 `authRoutes` 注册。保留当前 `/api/v1/auth` 路由结构，不重命名 `anonymous.ts`，避免把本切片扩大成 auth 模块重构。

### 发送验证码

`POST /auth/register/send-code` 行为：

- 请求体只接受 `email`。
- 邮箱为空、格式错误、超过 254 字符，返回 `422 / VALIDATION_ERROR`。
- 已存在未软删除 user 时，返回 `409 / CONFLICT`。
- 生成 6 位数字验证码。
- 写入 `verification_code`，字段为 normalized email、code、`purpose='register'`、`expires_at=now+10min`、`used_at=NULL`、`created_at=now`。
- 返回 `expires_in=600` 和 `resend_after=60`。
- 本切片不做 60 秒限流；该字段先按接口契约返回，限流可在邮件服务接入时补齐。

### 完成注册

`POST /auth/register/verify` 行为：

- 请求体接受 `email`、`code`、`password`、可选 `anonymous_id`。
- 邮箱按同一规则归一化和校验。
- code 必须是 6 位数字。
- password 至少 8 位。
- 查找当前 email 最新一条 `purpose='register'` 的验证码。
- 验证码不存在、错误、已使用或过期均返回 `422 / VALIDATION_ERROR`，文案按 API 规范。
- 创建 `user`，写入 PBKDF2 版本化 `password_hash`。
- 初始化 user 的 `portfolio_folder(Main)` 与 `user_preference`。
- 若传入 `anonymous_id` 且该匿名账号仍未升级，将该 anonymous owner 下的 `portfolio_folder`、`collection_item`、`wishlist_item`、`user_preference` 更新为新 user owner，并回填 `anonymous_account.upgraded_user_id`。
- 标记验证码 `used_at`。
- 创建 user session，refresh token 只存 hash。
- 签发 user access token。
- 返回 `user_id`、normalized `email`、`access_token`、明文一次性 `refresh_token`、`expires_in=900`、`migrated`。

### 事务边界

`verify` 的 user 创建、默认资产初始化、可选迁移、验证码消费和 session 创建必须作为一个批处理单元执行。当前 FakeD1 只模拟 batch，不保证真实事务语义；实现计划需在 Workers D1 能力范围内优先使用 `batch`，并通过测试确保失败不会被静默吞掉。

## 错误处理

- 请求 JSON 解析失败：`422 / VALIDATION_ERROR`。
- `JWT_SECRET` 缺失或空白：`500 / INTERNAL_ERROR`，且不写入 session。
- 重复邮箱：`409 / CONFLICT`。
- 验证码校验失败：`422 / VALIDATION_ERROR`。
- D1 写入失败：`500 / INTERNAL_ERROR`。

具体用户文案以 `docs/tcg-card/03-data-api/api-spec.md` 的 M1-3 定义为准。若 API 规范未给出明确文案，沿用现有 auth 端点的最小错误包络风格。

## 测试策略

`packages/auth-core`：

- hash 结果不包含明文密码。
- hash 格式包含算法、版本、迭代次数、salt 和 hash。
- 正确密码通过 `verifyPassword`。
- 错误密码返回 `false`。
- 未知算法或版本返回 `false`。

`apps/workers-api`：

- `send-code` 成功写入 normalized email 的 register 验证码。
- `send-code` 拒绝空邮箱、非法邮箱、超长邮箱。
- `send-code` 对已存在未删除 user 返回 conflict。
- `verify` 成功创建 user、默认 folder、preference、session，并返回 user token。
- `verify` 存储的 `password_hash` 不是明文密码，且可由 `verifyPassword` 验证。
- `verify` 标记验证码已使用，重复使用失败。
- `verify` 对错误 code、过期 code、短密码返回 validation error。
- `verify` 带有效 `anonymous_id` 时迁移匿名资产并回填升级关系。
- `verify` 不传 `anonymous_id` 时 `migrated=false`。
- `JWT_SECRET` 空白时不创建 user session。

## 验收标准

- `POST /api/v1/auth/register/send-code` 与 `POST /api/v1/auth/register/verify` 行为符合本设计。
- `auth-core` 暴露 PBKDF2 版本化密码哈希与验证函数。
- 不引入 bcrypt / argon2 依赖。
- 不修改数据库 schema。
- 不实现登录、找回密码、OAuth 或 Flutter UI。
- 本地聚焦验证通过：
  - `pnpm --filter @kando/auth-core run test`
  - `pnpm --filter @kando/auth-core run type-check`
  - `pnpm --filter @kando/auth-core run build`
  - `pnpm --filter @kando/workers-api run test`
  - `pnpm --filter @kando/workers-api run type-check`
  - `pnpm --filter @kando/workers-api run build`

## 风险

- 当前没有真实邮件服务，本切片只能证明验证码记录和注册逻辑，不证明邮件送达。
- 60 秒重发限制本切片不实现；如果产品要求开发期也限制，需要单独切片补充。
- FakeD1 与真实 D1 的批处理失败语义并不完全等价，实施时需要保持 SQL 简单并覆盖失败路径。
