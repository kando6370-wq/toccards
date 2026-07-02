# M1 Token 刷新与登出设计

## 背景

当前 M1 已完成匿名账号创建、access token 签发/验签，以及 `GET /api/v1/auth/me`。`session` 表已经保存哈希后的 refresh token、过期时间和 `revoked_at`，但还没有对外的刷新和登出端点。

本切片补齐 `POST /api/v1/auth/token/refresh` 与 `POST /api/v1/auth/logout` 的最小闭环，用于让客户端在 access token 过期后继续获取新的 access token，并在登出时吊销对应 session。

## 范围

包含：

- `POST /api/v1/auth/token/refresh`
- `POST /api/v1/auth/logout`
- refresh token 哈希查询、过期判断、吊销判断
- refresh 时确认 token 指向的 owner 仍可用
- logout 时确认 access token 与 refresh token 指向同一 session
- Workers 侧测试覆盖成功与关键失败路径

不包含：

- Email 注册、Email 登录、找回密码
- Google / Apple OAuth
- 匿名资产迁移
- 删除账号
- 滚动 refresh token
- Flutter token 管理层
- schema 迁移

## 设计决策

### 不滚动 refresh token

`/auth/token/refresh` 成功后只返回新的 `access_token` 和 `expires_in`，不返回新的 `refresh_token`。

API 规范中 `refresh_token` 是可选字段。滚动刷新虽然更安全，但会引入并发刷新、旧 token grace window、客户端替换失败后的恢复策略。当前项目还没有客户端 token 管理层，因此本切片先实现不滚动版本，保持行为稳定且可测试。

### Refresh 成功条件

Workers 接收明文 `refresh_token` 后先调用 `hashRefreshToken` 得到哈希值，再查询 `session.refresh_token`。

session 必须同时满足：

- `refresh_token = hash`
- `revoked_at IS NULL`
- `expires_at > now`

随后按 `session.owner_type` 查询 owner：

- `anonymous`：`anonymous_account.id = session.owner_id` 且 `upgraded_user_id IS NULL`
- `user`：`user.id = session.owner_id` 且 `deleted_at IS NULL`

owner 不存在或不可用时返回 `401 / UNAUTHORIZED`。

### Logout 绑定当前 access token

`POST /auth/logout` 需要 `Authorization: Bearer <access_token>` 和请求体中的 `refresh_token`。

Workers 先验 access token，再 hash refresh token 查询 session。可吊销的 session 必须同时满足：

- `session.id = access_token.session_id`
- `session.owner_type = access_token.owner_type`
- `session.owner_id = access_token.owner_id`
- `session.refresh_token = hash`
- `session.revoked_at IS NULL`

成功后将 `session.revoked_at` 更新为当前 ISO 时间。

已吊销、过期、不匹配或查不到 session 时统一返回 `401 / UNAUTHORIZED`。本切片不做“假成功”幂等登出，因为错误 token 不应被客户端视为已完成可信登出。

## HTTP 行为

### `POST /api/v1/auth/token/refresh`

请求体：

```json
{
  "refresh_token": "string"
}
```

成功响应：

```json
{
  "success": true,
  "data": {
    "access_token": "string",
    "expires_in": 900
  }
}
```

失败响应：

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Unauthorized."
  }
}
```

请求体缺失或 `refresh_token` 不是非空字符串时，返回 `422 / VALIDATION_ERROR`，避免把客户端请求格式错误混同为凭证无效。

### `POST /api/v1/auth/logout`

请求头：

```http
Authorization: Bearer <access_token>
```

请求体：

```json
{
  "refresh_token": "string"
}
```

成功响应：

```json
{
  "success": true,
  "data": {}
}
```

失败响应：

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Unauthorized."
  }
}
```

请求体缺失或 `refresh_token` 不是非空字符串时，返回 `422 / VALIDATION_ERROR`。

`JWT_SECRET` 为空属于服务端配置错误，返回与现有 auth 端点一致的 `500 / INTERNAL_ERROR`。

## 数据访问

新增查询只使用现有表：

- `session`
- `anonymous_account`
- `user`

不新增索引和迁移。本切片沿用当前 `session.refresh_token` 的唯一约束。

## 测试策略

优先扩展现有 Workers auth 测试和 FakeD1。

必须覆盖：

- 匿名账号创建后，使用 refresh token 成功刷新 access token。
- 刷新得到的 access token 可调用 `/auth/me`。
- 无效 refresh token 返回 `401 / UNAUTHORIZED`。
- 已过期 session 返回 `401 / UNAUTHORIZED`。
- 已吊销 session 返回 `401 / UNAUTHORIZED`。
- owner 不存在或不可用返回 `401 / UNAUTHORIZED`。
- logout 成功后 session 写入 `revoked_at`。
- logout 后同一个 refresh token 不能再刷新。
- access token 与 refresh token 不属于同一 session 时，logout 返回 `401 / UNAUTHORIZED`。
- 空白 `JWT_SECRET` 返回 `500 / INTERNAL_ERROR`。

## 成功标准

- `POST /api/v1/auth/token/refresh` 与 `POST /api/v1/auth/logout` 行为符合本设计。
- 不改变 `POST /auth/anonymous` 与 `GET /auth/me` 现有行为。
- 不实现滚动 refresh token。
- 本地聚焦验证通过：
  - `pnpm --filter @kando/auth-core run test`
  - `pnpm --filter @kando/auth-core run type-check`
  - `pnpm --filter @kando/auth-core run build`
  - `pnpm --filter @kando/workers-api run test`
  - `pnpm --filter @kando/workers-api run type-check`
  - `pnpm --filter @kando/workers-api run build`
- 顶层 TS 验证通过：
  - `pnpm run build`
  - `pnpm run type-check`
  - `pnpm run lint`
