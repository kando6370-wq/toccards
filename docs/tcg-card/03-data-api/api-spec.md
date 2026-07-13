# tcg-card REST API 规范

> **定位**：定义 tcg-card v1.0 全量 REST 接口契约，包括鉴权、资产、数据代理、后台四类端点。
> **日期**：2026-06-30
> **来源**：
> - 数据模型 [`docs/tcg-card/03-data-api/data-model.md`](./data-model.md)
> - 卡牌数据源适配层 [`docs/tcg-card/03-data-api/third-party.md`](./third-party.md)
> - 架构 [`docs/tcg-card/02-architecture/architecture.md`](../02-architecture/architecture.md)
> - 跨切面规则 [`docs/tcg-card/00-product/modules/global-rules.md`](../00-product/modules/global-rules.md)（文案/错误码/金额规则见此，本文档不重复定义）
> - 原始 PRD：`docs/tcg-card/source-tcg-card-docs/注册登录.md`、`个人中心.md`、`全局用其他补充事项.md`

---

## 1. 通用约定

### 1.1 Base URL

```
生产：https://<workers-domain>/api/v1
```

所有端点均以 `/api/v1` 为前缀（下文省略前缀，直接写路径）。

### 1.2 鉴权

- 所有端点（含匿名账号端点）均使用 **JWT Bearer Token**：

  ```
  Authorization: Bearer <access_token>
  ```

- Access Token 由 Workers 签发，有效期短（建议 15 分钟）；Refresh Token 存于 D1 `session` 表，用于续签。
- 匿名账号与正式账号均持有 JWT，`session.owner_type` 区分（`anonymous` / `user`）。
- 需要正式账号的端点若收到匿名 JWT，返回 `AUTH_REQUIRED`（见 §1.4）。
- 后台端点另加管理员角色校验（见 §5 后台接口）。

### 1.3 统一响应包络

成功响应：

```json
{
  "success": true,
  "data": { ... }
}
```

分页响应（`data` 替换为列表格式）：

```json
{
  "success": true,
  "data": {
    "items": [ ... ],
    "total": 100,
    "page": 1,
    "page_size": 20
  }
}
```

失败响应：

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "面向用户的文案"
  }
}
```

### 1.4 通用错误码

| code | HTTP 状态 | 触发场景 | 面向用户文案 |
|---|---|---|---|
| `UNAUTHORIZED` | 401 | 缺少或无效 JWT | — （客户端调起登录） |
| `AUTH_REQUIRED` | 403 | 匿名账号访问需正式账号的端点 | — （客户端调起注册引导） |
| `FORBIDDEN` | 403 | 无权限（如非管理员） | — |
| `NOT_FOUND` | 404 | 资源不存在 | — |
| `VALIDATION_ERROR` | 422 | 请求体字段校验失败 | 各字段级提示（见具体端点） |
| `CONFLICT` | 409 | 唯一约束冲突（如邮箱已注册） | 各端点定义 |
| `RATE_LIMITED` | 429 | 频率限制（如验证码 60 秒内重发） | — |
| `INTERNAL_ERROR` | 500 | 通用服务端错误 | Something went wrong. Please try again. |
| `NETWORK_ERROR` | — | 客户端无网络（由客户端本地判断） | No internet connection. Please check your network and try again. |

> 跨切面文案（局部/整页内容不可用、Toast 文案、金额缺失展示等）统一见 `global-rules.md`，本文档不重复定义。

### 1.5 分页 / 排序 / 筛选 Query 约定

| 参数 | 类型 | 说明 |
|---|---|---|
| `page` | integer | 页码，从 1 开始，默认 1 |
| `page_size` | integer | 每页条数，默认 20，最大 100 |
| `sort_by` | string | 排序字段（各端点定义可选值） |
| `sort_order` | string | `asc` / `desc`，默认 `desc` |

---

## 2. 鉴权与账号接口

### 2.1 创建 / 获取匿名账号

**用途**：App 首次启动时上报 `device_id`，Workers 创建或复用 `anonymous_account`，签发 JWT。

```
POST /auth/anonymous
```

请求体：

```json
{
  "device_id": "string"  // App 生成的设备唯一标识，必填
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "anonymous_id": "01JXXXXXX",        // anonymous_account.id
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_in": 900                   // access_token 有效秒数
  }
}
```

错误：

| code | 触发条件 |
|---|---|
| `VALIDATION_ERROR` | `device_id` 为空 |
| `INTERNAL_ERROR` | D1 写入失败 |

> Workers 内部逻辑：先查 `anonymous_account` 是否已存在同 `device_id` 记录；若存在且未升级则复用，若不存在则新建，并自动初始化 `portfolio_folder`（name="Main", is_default=1）和 `user_preference`（currency='USD', amount_hidden=0）。

---

### 2.2 邮箱注册 —— 发送验证码

**用途**：向未注册邮箱发送 6 位验证码。

```
POST /auth/register/send-code
```

请求体：

```json
{
  "email": "string"  // 必填，统一转小写、去首尾空格
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "expires_in": 600,      // 验证码有效秒数（10 分钟）
    "resend_after": 60      // 60 秒后可重发
  }
}
```

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | 邮箱为空 | Please enter your email. |
| `VALIDATION_ERROR` | 邮箱格式错误 | Please enter a valid email address. |
| `VALIDATION_ERROR` | 邮箱超 254 字符 | Email must be 254 characters or less. |
| `CONFLICT` | 邮箱已注册 | — （客户端切换至登录流程） |
| `RATE_LIMITED` | 同邮箱 60 秒内重复请求 | — |

> Workers 内部逻辑：向 D1 `verification_code` 写入记录（purpose='register'，expires_at=now+10min），并通过邮件服务（⚠️ TBD：Resend/SES）发送验证码。

---

### 2.3 邮箱注册 —— 验证验证码并完成注册

**用途**：校验验证码 + 设置密码 + 创建正式账号。

```
POST /auth/register/verify
```

请求体：

```json
{
  "email": "string",
  "code": "string",          // 6 位数字验证码
  "password": "string",      // 明文密码（Workers 侧 bcrypt hash 后存储）
  "anonymous_id": "string"   // 可选：当前匿名账号 ID，用于资产迁移
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "user_id": "01JXXXXXX",       // user.id
    "email": "user@example.com",  // user.email
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_in": 900,
    "migrated": true              // 是否完成了匿名资产迁移
  }
}
```

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | 验证码不为 6 位数字 | Incorrect verification code. |
| `VALIDATION_ERROR` | 验证码错误 | Incorrect verification code. |
| `VALIDATION_ERROR` | 验证码已过期 | Code expired. Please request a new code. |
| `VALIDATION_ERROR` | 密码少于 8 位 | — |
| `VALIDATION_ERROR` | 验证码已使用 | Code expired. Please request a new code. |
| `CONFLICT` | 邮箱已注册 | — |
| `INTERNAL_ERROR` | 账号创建失败 | Something went wrong. Please try again. |

> Workers 内部逻辑：
> 1. 校验 `verification_code`（purpose='register'，expires_at > now，used_at IS NULL）。
> 2. 创建 `user` 记录（id=ULID, email, password_hash=bcrypt(password)）。
> 3. 初始化 `portfolio_folder`（Main, is_default=1）和 `user_preference`。
> 4. 若 `anonymous_id` 非空：将该匿名账号下所有资产表（`portfolio_folder`、`collection_item`、`wishlist_item`、`user_preference`）的 owner_type 批量更新为 `user`、owner_id 更新为新 user.id；并回填 `anonymous_account.upgraded_user_id`。
> 5. 签发 JWT，写入 `session`（owner_type='user'）。
> 6. 将 `verification_code.used_at` 设为当前时间。

---

### 2.4 邮箱登录

**用途**：已注册邮箱账号使用密码登录。

```
POST /auth/login
```

请求体：

```json
{
  "email": "string",
  "password": "string"
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "user_id": "01JXXXXXX",
    "email": "user@example.com",
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_in": 900
  }
}
```

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | 邮箱格式错误 | Please enter a valid email address. |
| `VALIDATION_ERROR` | 邮箱未注册 | — （客户端切换至注册流程） |
| `VALIDATION_ERROR` | 密码错误 | Incorrect password. Please try again. |
| `VALIDATION_ERROR` | 账号已软删除 | — |

---

### 2.5 找回密码 —— 发送验证码

```
POST /auth/forgot-password/send-code
```

请求体：

```json
{
  "email": "string"
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "expires_in": 600,
    "resend_after": 60
  }
}
```

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | 邮箱格式错误 | Please enter a valid email address. |
| `VALIDATION_ERROR` | 邮箱未注册 | Email not registered. Please check your email or create a new account. |
| `RATE_LIMITED` | 60 秒内重复请求 | — |

---

### 2.6 找回密码 —— 验证验证码

**用途**：验证验证码，获取一次性重置凭证（reset_token）用于后续重置密码请求。

```
POST /auth/forgot-password/verify-code
```

请求体：

```json
{
  "email": "string",
  "code": "string"
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "reset_token": "string"   // 短期有效凭证（Workers 内存或 KV 存储，有效期 10 分钟）
  }
}
```

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | 验证码错误 | Incorrect verification code. |
| `VALIDATION_ERROR` | 验证码已过期 | Code expired. Please request a new code. |

---

### 2.7 找回密码 —— 重置密码

```
POST /auth/forgot-password/reset
```

请求体：

```json
{
  "email": "string",
  "reset_token": "string",   // §2.6 返回的凭证
  "new_password": "string"   // 新密码，至少 8 位
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

客户端收到成功后展示 Toast：`Password reset successfully.`，并返回邮箱登录页。

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | reset_token 无效 / 已过期 | Code expired. Please request a new code. |
| `VALIDATION_ERROR` | 新密码少于 8 位 | — |
| `INTERNAL_ERROR` | 更新失败 | Something went wrong. Please try again. |

---

### 2.8 Google OAuth 回调

**用途**：接收 Google OAuth 授权码，由 Workers 换取用户信息，创建或登录账号。

```
POST /auth/oauth/google/callback
```

请求体：

```json
{
  "code": "string",             // Google OAuth authorization code
  "redirect_uri": "string",     // 与授权时一致
  "anonymous_id": "string"      // 可选：匿名账号 ID，用于注册时迁移资产
}
```

> ⚠️ TBD：Google OAuth Client ID / Secret（见 Spec §6 TBD #4）。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "user_id": "01JXXXXXX",
    "email": "user@gmail.com",
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_in": 900,
    "is_new_user": true,      // true = 新注册，false = 已有账号登录
    "migrated": true          // 是否完成了匿名资产迁移（仅 is_new_user=true 时有意义）
  }
}
```

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | 授权码无效 / 过期 | Authorization failed. Please try again. |
| `INTERNAL_ERROR` | 第三方接口异常 | Authorization failed. Please try again. |

> Workers 内部逻辑：
> 1. 用授权码换取 Google access_token，获取 `provider_uid`（Google sub）和邮箱。
> 2. 查 `auth_identity`（provider='google', provider_uid）：若存在则查关联 user，直接登录；若不存在则：
>    a. 创建 `user` 记录（password_hash=NULL）。
>    b. 创建 `auth_identity` 记录。
>    c. 初始化 `portfolio_folder` 和 `user_preference`。
>    d. 若 `anonymous_id` 非空，执行资产迁移（同 §2.3）。
> 3. 签发 JWT，写入 `session`。

---

### 2.9 Apple OAuth 回调

```
POST /auth/oauth/apple/callback
```

请求体：

```json
{
  "code": "string",             // Apple authorization code
  "id_token": "string",         // Apple identity token
  "anonymous_id": "string"      // 可选：匿名账号 ID
}
```

> ⚠️ TBD：Apple Service ID / Team ID / Key ID（见 Spec §6 TBD #4）。

成功响应（200）：同 §2.8 格式。

错误：同 §2.8。

> Workers 内部逻辑：验证 Apple id_token（JWT 签名 + aud + exp），提取 `sub` 作为 `provider_uid`，后续逻辑同 §2.8。

---

### 2.10 刷新 Token

```
POST /auth/token/refresh
```

请求体：

```json
{
  "refresh_token": "string"
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",   // 可选：滚动刷新时返回新 refresh_token
    "expires_in": 900
  }
}
```

错误：

| code | 触发条件 |
|---|---|
| `UNAUTHORIZED` | refresh_token 无效 / 已过期 / 已吊销（session.revoked_at 非 NULL） |

---

### 2.11 登出

```
POST /auth/logout
```

请求头：需 JWT（任意 owner_type）。

请求体：

```json
{
  "refresh_token": "string"   // 吊销对应 session
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

> Workers 内部逻辑：将 `session.revoked_at` 设为当前时间。

---

### 2.12 删除账号

**用途**：正式账号软删除。需正式账号 JWT。

```
DELETE /auth/account
```

请求头：需正式账号 JWT。

请求体：无。

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

客户端：退出登录，返回游客态。

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `AUTH_REQUIRED` | 匿名账号尝试调用 | — |
| `INTERNAL_ERROR` | 更新失败 | Unable to complete this action. Please try again later. |

> 注：此为来源 PRD 指定的场景专用失败文案，作为通用 Toast 的例外；最终以 global-rules.md 文案表为准。

> Workers 内部逻辑：将 `user.deleted_at` 设为当前时间；吊销该用户所有 `session`（revoked_at = now）；资产数据按隐私合规策略处理（⚠️ TBD：具体留存/清除规则）。

> ⚠️ TBD（游客态删除账号）：profile §6.3 要求游客态也提供 Delete account 入口（苹果审核）。最终方案二选一——(a) 扩展本端点接受匿名 JWT，删除 `anonymous_account` 及其游客资产；(b) 新增针对 `anonymous_account` 的独立删除端点。当前本端点仍为正式账号软删除、匿名调用返回 `AUTH_REQUIRED`。详见 §6 TBD #10。

---

### 2.13 匿名账号升级 / 资产迁移（独立端点）

**用途**：注册或 OAuth 成功后，若客户端希望显式重试失败的资产迁移，可调用此端点。

```
POST /auth/migrate-assets
```

请求头：需正式账号 JWT（owner_type='user'）。

请求体：

```json
{
  "anonymous_id": "string"   // anonymous_account.id
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "migrated_folders": 2,
    "migrated_items": 15,
    "migrated_wishlist": 3
  }
}
```

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `NOT_FOUND` | anonymous_id 不存在 | — |
| `CONFLICT` | 该匿名账号已被升级（upgraded_user_id 已回填） | — |
| `INTERNAL_ERROR` | 迁移写入失败 | Something went wrong. Please try again later. |

> 注：此为来源 PRD 指定的场景专用失败文案，作为通用 Toast 的例外；最终以 global-rules.md 文案表为准。

---

### 2.14 获取当前账号信息

```
GET /auth/me
```

请求头：需 JWT（任意 owner_type）。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "owner_type": "user",          // 'user' | 'anonymous'
    "user_id": "01JXXXXXX",        // user.id（owner_type='user' 时）
    "anonymous_id": null,          // anonymous_account.id（owner_type='anonymous' 时）
    "email": "user@example.com",   // owner_type='anonymous' 时为 null
    "display_name": null,          // user.display_name
    "created_at": "2026-06-30T..."
  }
}
```

---

## 3. 资产接口

> 所有资产端点均需 JWT（任意 owner_type）；Workers 从 JWT 中提取 `owner_type` + `owner_id` 作为数据隔离依据。

### 3.1 Portfolio 文件夹

#### 3.1.1 获取文件夹列表

```
GET /portfolio/folders
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "01JXXXXXX",
        "name": "Main",
        "is_default": true,      // portfolio_folder.is_default = 1
        "sort_order": 0,         // portfolio_folder.sort_order
        "created_at": "...",
        "updated_at": "..."
      }
    ]
  }
}
```

> 按 `sort_order` ASC 返回，`is_default=true` 的文件夹在排序中可排首位（由前端处理 / Workers 保证）。

---

#### 3.1.2 创建文件夹

```
POST /portfolio/folders
```

请求体：

```json
{
  "name": "string"   // 文件夹名称，必填，同一 owner 唯一
}
```

成功响应（201）：

```json
{
  "success": true,
  "data": {
    "id": "01JXXXXXX",
    "name": "My Folder",
    "is_default": false,
    "sort_order": 100,
    "created_at": "...",
    "updated_at": "..."
  }
}
```

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | name 为空 | — |
| `CONFLICT` | 同一 owner 下已有同名文件夹 | — |
| `INTERNAL_ERROR` | 写入失败 | Something went wrong. Please try again. |

---

#### 3.1.3 更新文件夹

```
PATCH /portfolio/folders/{folder_id}
```

请求体（所有字段均可选）：

```json
{
  "name": "string"
}
```

成功响应（200）：返回更新后的完整文件夹对象（同 §3.1.2）。

错误：

| code | 触发条件 |
|---|---|
| `NOT_FOUND` | folder_id 不存在或不属于当前 owner |
| `CONFLICT` | 改名后与已有文件夹重名 |

---

#### 3.1.4 删除文件夹

```
DELETE /portfolio/folders/{folder_id}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

> **连带效果**：`collection_item.folder_id` 有 DB 级 `ON DELETE CASCADE`，删除文件夹时该文件夹下的所有 `collection_item` 也被删除。同时将 `user_preference.last_selected_folder_id` 置 NULL（若指向被删文件夹）。客户端需刷新 Home 总资产。

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `NOT_FOUND` | folder_id 不存在或不属于当前 owner | — |
| `FORBIDDEN` | 尝试删除默认文件夹（is_default=1） | — |
| `INTERNAL_ERROR` | 删除失败 | Something went wrong. Please try again. |

---

#### 3.1.5 设置默认文件夹

```
PATCH /portfolio/folders/{folder_id}/set-default
```

请求体：无。

成功响应（200）：返回更新后的文件夹对象（is_default=true）。

> Workers 内部逻辑：在单个事务中将当前 owner 所有文件夹的 `is_default` 改为 0，再将目标 folder 改为 1。

---

#### 3.1.6 更新文件夹排序

```
PATCH /portfolio/folders/reorder
```

请求体：

```json
{
  "orders": [
    { "folder_id": "01JXXXXXX", "sort_order": 0 },
    { "folder_id": "01JYYYYYY", "sort_order": 1 }
  ]
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

---

### 3.2 Collection Item（Portfolio 持有记录）

#### 3.2.1 获取 Collection Item 列表

```
GET /portfolio/items
```

Query 参数：

| 参数 | 说明 |
|---|---|
| `folder_id` | 筛选特定文件夹；不传则返回所有文件夹的 item |
| `page` / `page_size` | 分页（默认 page=1, page_size=20） |
| `sort_by` | `created_at`（默认）\| `updated_at` \| `card_ref` |
| `sort_order` | `asc` / `desc`（默认 `desc`） |

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "01JXXXXXX",
        "folder_id": "01JFOLDER",
        "card_ref": "...",
        "object_type": "tcg",
        "grader": "PSA",
        "condition": null,
        "grade": 9.0,
        "language": "English",
        "finish": "Holofoil",
        "quantity": 1,
        "purchase_price": 50.00,
        "purchase_currency": "USD",
        "notes": null,
        "created_at": "...",
        "updated_at": "..."
      }
    ],
    "total": 42,
    "page": 1,
    "page_size": 20
  }
}
```

---

#### 3.2.2 创建 Collection Item

```
POST /portfolio/items
```

请求体：

```json
{
  "folder_id": "string",          // 必填；portfolio_folder.id，必须属于当前 owner
  "card_ref": "string",           // 必填；cards_all.product_id
  "object_type": "tcg",           // 必填；'tcg' | 'sports' | 'sealed' | 'other'
  "grader": "Raw",                // 必填；'Raw' | 'PSA' | 'BGS' | 'CGC' | 'SGC' | 'TAG' | 'AGS'
  "condition": "Near Mint",       // grader='Raw' 时必填，其他情况为 null（⚠️ TBD：枚举见 §6 #5）
  "grade": null,                  // grader≠'Raw' 时必填；Raw 时为 null
  "language": "English",          // 可选
  "finish": "Holofoil",           // 可选
  "quantity": 1,                  // 必填，≥1
  "purchase_price": 50.00,        // 可选
  "purchase_currency": "USD",     // purchase_price 非 null 时必填
  "notes": "string"               // 可选，最多 500 字符
}
```

成功响应（201）：返回创建的 collection_item 完整对象。

> **副作用**：若该 `card_ref` 存在于当前 owner 的 `wishlist_item` 中，Workers 自动将其从 Wishlist 中删除（glossary 定义：Collect 操作自动移出 Wishlist）。

错误：

| code | 触发条件 |
|---|---|
| `VALIDATION_ERROR` | 必填字段缺失、grader 与 condition/grade 逻辑冲突、quantity<1 |
| `NOT_FOUND` | folder_id 不存在或不属于当前 owner |

---

#### 3.2.3 获取单个 Collection Item

```
GET /portfolio/items/{item_id}
```

成功响应（200）：返回 collection_item 完整对象。

错误：

| code | 触发条件 |
|---|---|
| `NOT_FOUND` | item_id 不存在或不属于当前 owner |

---

#### 3.2.4 更新 Collection Item

```
PATCH /portfolio/items/{item_id}
```

请求体（所有字段均可选，只传需要修改的字段）：

```json
{
  "grader": "PSA",
  "grade": 10.0,
  "condition": null,
  "language": "English",
  "finish": "Holofoil",
  "quantity": 2,
  "purchase_price": 100.00,
  "purchase_currency": "USD",
  "notes": "updated note"
}
```

成功响应（200）：返回更新后的 collection_item 完整对象。

错误：

| code | 触发条件 |
|---|---|
| `NOT_FOUND` | item_id 不存在或不属于当前 owner |
| `VALIDATION_ERROR` | 字段逻辑冲突（同创建校验） |

---

#### 3.2.5 删除 Collection Item

```
DELETE /portfolio/items/{item_id}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

> **副作用**：客户端需刷新 Home 总资产。

---

#### 3.2.6 移动 Collection Item 到其他文件夹

```
PATCH /portfolio/items/{item_id}/move
```

请求体：

```json
{
  "folder_id": "string"   // 目标文件夹 ID，必须属于当前 owner
}
```

成功响应（200）：返回更新后的 collection_item 完整对象。

---

### 3.3 Wishlist

#### 3.3.1 获取 Wishlist 列表

```
GET /wishlist
```

Query 参数：`page` / `page_size` / `sort_by`（`created_at` 默认）/ `sort_order`。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "01JXXXXXX",
        "card_ref": "...",
        "created_at": "..."
      }
    ],
    "total": 5,
    "page": 1,
    "page_size": 20
  }
}
```

---

#### 3.3.2 加入 Wishlist

```
POST /wishlist
```

请求体：

```json
{
  "card_ref": "string"   // 必填
}
```

成功响应（201）：

```json
{
  "success": true,
  "data": {
    "id": "01JXXXXXX",
    "card_ref": "...",
    "created_at": "..."
  }
}
```

错误：

| code | 触发条件 |
|---|---|
| `CONFLICT` | 该 card_ref 已在当前 owner 的 Wishlist 中（wishlist_item 唯一约束） |

---

#### 3.3.3 从 Wishlist 移除

```
DELETE /wishlist/{item_id}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

---

### 3.4 用户偏好

#### 3.4.1 获取用户偏好

```
GET /preferences
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "currency": "USD",
    "amount_hidden": false,                // user_preference.amount_hidden = 0
    "last_selected_folder_id": null        // user_preference.last_selected_folder_id
  }
}
```

---

#### 3.4.2 更新用户偏好

```
PATCH /preferences
```

请求体（所有字段均可选）：

```json
{
  "currency": "JPY",
  "amount_hidden": true,
  "last_selected_folder_id": "01JXXXXXX"
}
```

> `currency` 为 ISO 4217 货币代码（⚠️ TBD：支持币种列表取决于汇率接口提供方，见 Spec §6 TBD #2）。

成功响应（200）：返回更新后的偏好完整对象（同 §3.4.1 格式）。

---

## 4. 数据代理接口

> 所有数据代理端点均经 Workers **适配层（DataSourceAdapter）+ 缓存**（KV / Cache API）读取当前 D1 中的卡牌基础数据表，不直连采集程序或外部数据源。端点可无 JWT 访问（仅需合法来源请求），但若携带 JWT，Workers 可根据账号偏好换算货币。
>
> 当前默认数据源：`cards_all` / `games` / `sets` / `tcgplayer_skus`。这些表由外部采集程序写入同一个 D1 数据库，Workers 只读查询。`card_ref` 统一使用 `cards_all.product_id`。
>
> 缓存策略、TTL、降级行为见 [`third-party.md`](./third-party.md) §4、§5；占位展示文案见 `global-rules.md`。

### 4.1 搜索卡牌

**适配层接口**：`searchCards(query, options)`（见 third-party.md §2.1）

```
GET /cards/search
```

Query 参数：

| 参数 | 说明 |
|---|---|
| `q` | 搜索关键词，必填 |
| `object_type` | 可选；`tcg` \| `sports` \| `sealed` \| `other` |
| `page` | 默认 1 |
| `page_size` | 默认 20，最大 100 |

> 缓存：Workers KV，TTL 1 小时（⚠️ TBD）。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "card_ref": "...",
        "name": "Charizard",
        "set_name": "Base Set",
        "set_code": "BS",
        "card_number": "4/102",
        "finish": "Holofoil",
        "language": "English",
        "object_type": "tcg",
        "image_url": "https://...",
        "rarity": "Rare Holo"
      }
    ],
    "total": 50,
    "page": 1,
    "page_size": 20
  }
}
```

降级行为：D1 基础表读取失败且无缓存时返回 `items: []`；客户端展示 "No content available" + Refresh。

---

### 4.2 搜索系列（Sets）

**适配层接口**：`searchCards(query, options)` 内部从 `cards_all` 搜索结果聚合 set 层级结果；后续如需更完整的 Set Tab，可直接查询 `sets` 表。

```
GET /sets/search
```

Query 参数：

| 参数 | 说明 |
|---|---|
| `q` | 搜索关键词，必填 |
| `game` | 可选；Game/IP 过滤（如 `pokemon`）（枚举来自 `games` / `cards_all.game`） |
| `page` / `page_size` | 分页 |

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "set_code": "BS",
        "set_name": "Base Set",
        "image_url": "https://...",
        "card_count": 102
      }
    ],
    "total": 10,
    "page": 1,
    "page_size": 20
  }
}
```

---

### 4.3 获取卡牌详情

**适配层接口**：`getCard(card_ref)`（见 third-party.md §2.1）

```
GET /cards/{card_ref}
```

> `card_ref` 需 URL encode。缓存：Workers KV，TTL 6 小时（⚠️ TBD）。
> Workers 返回数据时，先查 D1 `card_override`，有覆盖字段则合并后返回（覆盖层优先）。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "card_ref": "...",
    "name": "Charizard",
    "set_name": "Base Set",
    "set_code": "BS",
    "card_number": "4/102",
    "finish": "Holofoil",
    "language": "English",
    "object_type": "tcg",
    "image_url": "https://...",
    "rarity": "Rare Holo",
    "override_applied": false    // true = 数据包含覆盖层字段
  }
}
```

降级行为：D1 基础表读取失败且无 `card_override` 时，返回 404；客户端展示整页失败状态。

---

### 4.4 获取当前市场价（Market Prices）

**适配层接口**：`getMarketPrices(card_ref)`（见 third-party.md §2.1）

```
GET /cards/{card_ref}/market-prices
```

> 缓存：Cache API，TTL 30 分钟（⚠️ TBD）。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "card_ref": "...",
    "prices": [
      {
        "grader": "Raw",
        "grade": null,
        "condition": "Near Mint",
        "price": 1200.00,   // USD；null = 无数据，展示 "--"
        "currency": "USD"
      },
      {
        "grader": "PSA",
        "grade": 10.0,
        "condition": null,
        "price": 5000.00,
        "currency": "USD"
      }
    ],
    "updated_at": "2026-06-30T10:00:00Z"
  }
}
```

降级行为：返回 `prices: []`；客户端展示 "No content available" + Refresh；各价格展示 `--`。

---

### 4.5 获取价格序列（Price Series）

**适配层接口**：`getPriceSeries(card_ref, grader, grade, condition, days)`（见 third-party.md §2.1）

```
GET /cards/{card_ref}/price-series
```

Query 参数：

| 参数 | 类型 | 说明 |
|---|---|---|
| `grader` | string | 必填；`Raw` \| `PSA` \| `BGS` \| `CGC` \| `SGC` \| `TAG` \| `AGS` |
| `grade` | number | grader≠Raw 时必填 |
| `condition` | string | grader=Raw 时必填（枚举来自 `tcgplayer_skus.condition_code` / `condition_name`） |
| `days` | integer | 必填；`7` \| `30` \| `90` \| `180` \| `365` |

> 缓存：Cache API，TTL 30 分钟（⚠️ TBD）。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "card_ref": "...",
    "grader": "PSA",
    "grade": 10.0,
    "condition": null,
    "days": 30,
    "series": [
      { "date": "2026-06-01", "price": 4800.00 },
      { "date": "2026-06-30", "price": 5000.00 }
    ]
  }
}
```

降级行为：返回 `series: []`；图表展示 "No price data available"；涨跌幅展示 `-/-`。

---

### 4.6 获取 Trending Today

**适配层接口**：`getTrending()`（见 third-party.md §2.1）

```
GET /cards/trending
```

> 缓存：Workers KV，TTL 15 分钟（⚠️ TBD）。
> Workers 合并逻辑：先从 D1 `trending_pin`（active=1）取置顶卡牌，按 `rank` 排序置于列表首位，并按 `card_ref` 回查 `cards_all`；后接适配器 `getTrending()` 返回结果（过滤掉已置顶的卡牌，避免重复）；每张卡牌数据经 `card_override` 覆盖层合并。当前本地基础表没有算法 Trending 来源时，非置顶列表可为空。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "card_ref": "...",
        "name": "Charizard",
        "set_name": "Base Set",
        "image_url": "https://...",
        "pinned": true    // true = 运营置顶（来自 trending_pin）
      }
    ]
  }
}
```

降级行为：返回 `items: []`；客户端展示 "No content available" + Refresh。

---

### 4.7 获取成交记录（Sold Listings）

**适配层接口**：`getSoldListings(card_ref)`（见 third-party.md §2.1）

```
GET /cards/{card_ref}/sold-listings
```

> 缓存：Cache API，TTL 30 分钟（⚠️ TBD）。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "date": "2026-06-29",
        "title": "PSA 10 Charizard Base Set",
        "price": 5000.00,
        "currency": "USD",
        "platform": "eBay",
        "url": "https://..."
      }
    ]
  }
}
```

降级行为：返回 `items: []`；展示 "No content available" + Refresh。

---

### 4.8 汇率换算

**适配层接口**：⚠️ TBD（待汇率提供方确定后补充）

> ⚠️ TBD：汇率接口提供方（见 Spec §6 TBD #2）。

```
GET /rates
```

Query 参数：

| 参数 | 说明 |
|---|---|
| `base` | 基准货币，默认 `USD` |
| `targets` | 逗号分隔的目标货币代码，如 `JPY,EUR,GBP` |

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "base": "USD",
    "rates": {
      "JPY": 155.32,
      "EUR": 0.91,
      "GBP": 0.79
    },
    "updated_at": "2026-06-30T09:00:00Z"
  }
}
```

---

### 4.9 Collect 快捷加入（数据代理 + 资产写入复合端点）

**用途**：从搜索结果或卡牌详情页，直接将卡牌加入指定 Portfolio 文件夹（需 JWT）。

```
POST /cards/{card_ref}/collect
```

请求头：需 JWT（任意 owner_type）。

请求体：

```json
{
  "folder_id": "string",    // 必填；目标文件夹 ID（null 时使用默认文件夹）
  "object_type": "tcg",
  "grader": "Raw",
  "condition": "Near Mint",
  "grade": null,
  "language": "English",
  "finish": null,
  "quantity": 1,
  "purchase_price": null,
  "purchase_currency": null,
  "notes": null
}
```

成功响应（201）：返回创建的 collection_item 完整对象（同 §3.2.2）。

> **副作用**：若该 `card_ref` 存在于当前 owner 的 `wishlist_item` 中，Workers 自动将其从 Wishlist 中删除。

---

### 4.10 扫描识别代理

**用途**：App 上传卡牌图片到 Workers，由 Workers 鉴权、转发 OCR 服务并保存扫描审计记录，供后台扫描记录管理查询。

> Workers 运行环境需配置 `OCR_SERVICE_BASE_URL`，指向 `scanHTTP接口对接说明.md` 中的识别服务地址。Workers 默认向 OCR 服务提交 `retrieval=phash`、`top=5`，避免 App 直接暴露 OCR 服务拓扑。

```
POST /scan/recognize
Content-Type: multipart/form-data
Authorization: Bearer <access_token>
```

表单字段：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `image` | file | 是 | 待识别卡牌图片 |
| `platform` | string | 否 | App 平台，默认 `iOS` |
| `app_version` | string | 否 | App 版本，默认 `unknown` |
| `device_model` | string | 否 | 设备型号 |
| `os_version` | string | 否 | 系统版本 |
| `image_url` | string | 否 | 若 App/存储层已保存图片，可传后台展示 URL |

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "scan_id": "01JXXXXXX",
    "recognition_status": "success",
    "cards_detected": 1,
    "results": [
      {
        "index": 1,
        "matched": true,
        "candidates": [
          {
            "rank": 1,
            "card_ref": "11958",
            "name": "Bushi Tenderfoot",
            "game": "Magic: The Gathering",
            "set_code": "CHK",
            "card_number": "1",
            "confidence": 86.2
          }
        ]
      }
    ]
  }
}
```

错误：

| code | HTTP 状态 | 触发条件 |
|---|---|---|
| `UNAUTHORIZED` | 401 | 缺少或无效 App JWT |
| `VALIDATION_ERROR` | 422 | 未上传 `image` |
| `OCR_SERVICE_UNAVAILABLE` | 502 / 503 | OCR 服务未配置、不可达或返回失败 |

---

## 5. 后台接口

> 所有后台端点路径前缀为 `/admin`，需要 **Admin Token**（JWT，由 `/admin/auth/login` 签发）。鉴权基于独立 `admin_user` 表（见 data-model §5.1），与 App `user` / `session` 完全分离。匿名账号无权访问后台。
>
> Admin Token 在 HTTP Header 中传递方式与 §1.2 一致（`Authorization: Bearer <admin_token>`），但签发主体不同：Workers 识别 JWT `sub` 来自 `admin_user` 表，而非 `user` / `anonymous_account` 表；两套 Token 不可互用。

### 5.0 管理员鉴权

#### 5.0.1 管理员登录

**用途**：管理员使用邮箱 + 密码登录后台，获取 Admin Token。

```
POST /admin/auth/login
```

请求体：

```json
{
  "email": "string",    // admin_user.email，必填
  "password": "string"  // 明文密码，Workers 侧与 admin_user.password_hash 校验，必填
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "admin_id": "01JADMIN",         // admin_user.id
    "email": "admin@example.com",   // admin_user.email
    "role": "super_admin",          // 'super_admin' | 'operator'
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_in": 900               // access_token 有效秒数
  }
}
```

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | 邮箱为空 | Please enter your email. |
| `VALIDATION_ERROR` | 邮箱格式错误 | Please enter a valid email address. |
| `VALIDATION_ERROR` | 密码为空 | — |
| `VALIDATION_ERROR` | 邮箱不存在或密码错误 | Incorrect email or password. |
| `FORBIDDEN` | `admin_user.status = 'disabled'` | Your account has been disabled. |

> Workers 内部逻辑：查 `admin_user` 表匹配邮箱；bcrypt 校验密码；若 `status = 'disabled'` 则拒绝；签发 Admin Token（JWT `sub` 写入 `admin_user.id`，`role` 写入 payload）；Refresh Token 策略与普通 session 表相同（⚠️ TBD：可复用 `session` 表 `owner_type='admin'` 或使用独立表，实现阶段确认）。

---

#### 5.0.2 管理员登出

**用途**：吊销当前 Admin Refresh Token。

```
POST /admin/auth/logout
```

请求头：需 Admin Token。

请求体：

```json
{
  "refresh_token": "string"   // 当前 Admin Refresh Token，必填
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

---

#### 5.0.3 Admin Token 续签

**用途**：用 Admin Refresh Token 换取新 Admin Access Token。

```
POST /admin/auth/refresh
```

请求体：

```json
{
  "refresh_token": "string"   // 当前 Admin Refresh Token，必填
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",   // 可选：滚动刷新时返回新 refresh_token
    "expires_in": 900
  }
}
```

错误：

| code | 触发条件 |
|---|---|
| `UNAUTHORIZED` | refresh_token 无效 / 已过期 / 已吊销 |
| `FORBIDDEN` | 对应 `admin_user.status = 'disabled'` |

---

### 5.1 用户管理

#### 5.1.1 获取用户列表

**说明**：后台用户列表同时显示正式账号（`user` 表）和匿名账号（`anonymous_account` 表）。

```
GET /admin/users
```

Query 参数：

| 参数 | 说明 |
|---|---|
| `type` | `user` \| `anonymous` \| 不传（返回全部） |
| `q` | 搜索（正式账号按 email 模糊搜索；匿名账号按 device_id 搜索） |
| `page` / `page_size` | 分页 |

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "account_type": "user",
        "id": "01JXXXXXX",         // user.id
        "email": "user@example.com",
        "display_name": null,
        "created_at": "...",
        "deleted_at": null         // 非 null = 已软删除
      },
      {
        "account_type": "anonymous",
        "id": "01JANON",           // anonymous_account.id
        "device_id": "...",
        "created_at": "...",
        "upgraded_user_id": null   // 非 null = 已升级为正式账号
      }
    ],
    "total": 150,
    "page": 1,
    "page_size": 20
  }
}
```

---

#### 5.1.2 获取用户详情

```
GET /admin/users/{account_type}/{id}
```

> `account_type` 取 `user` 或 `anonymous`。

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "account_type": "user",
    "id": "01JXXXXXX",
    "email": "user@example.com",
    "display_name": null,
    "created_at": "...",
    "updated_at": "...",
    "deleted_at": null,
    "auth_identities": [
      { "provider": "google", "provider_uid": "..." }
    ],
    "session_count": 2,
    "asset_summary": {
      "folder_count": 3,
      "item_count": 42,
      "wishlist_count": 5
    }
  }
}
```

---

#### 5.1.3 禁用账号（软删除）

```
PATCH /admin/users/user/{id}/disable
```

请求体：

```json
{
  "reason": "string"   // 可选，管理员备注
}
```

成功响应（200）：

```json
{
  "success": true,
  "data": { "deleted_at": "2026-06-30T..." }
}
```

> Workers 内部逻辑：将 `user.deleted_at` 设为当前时间；吊销所有 session。

---

### 5.2 反馈工单管理

#### 5.2.1 获取工单列表

```
GET /admin/feedbacks
```

Query 参数：

| 参数 | 说明 |
|---|---|
| `status` | `open` \| `in_progress` \| `closed` |
| `page` / `page_size` | 分页 |
| `sort_by` | `created_at`（默认）\| `updated_at` |
| `sort_order` | `desc`（默认） |

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "01JXXXXXX",
        "email": "user@example.com",
        "types": ["Bug Report"],
        "functions": ["Search"],
        "message": "...",
        "status": "open",
        "created_at": "...",
        "updated_at": "..."
      }
    ],
    "total": 30,
    "page": 1,
    "page_size": 20
  }
}
```

---

#### 5.2.2 获取工单详情

```
GET /admin/feedbacks/{ticket_id}
```

成功响应（200）：返回单条工单完整对象（字段同 §5.2.1 列表项）。

---

#### 5.2.3 更新工单状态

```
PATCH /admin/feedbacks/{ticket_id}/status
```

请求体：

```json
{
  "status": "in_progress"   // 'open' | 'in_progress' | 'closed'
}
```

成功响应（200）：返回更新后的工单对象。

---

#### 5.2.4 提交用户反馈（前台端点）

> 此为前台用户端点（无需管理员权限），因与工单数据相关暂列于此；由 App 用户提交，JWT 可选（已登录则自动填充 email）。

```
POST /feedbacks
```

请求体：

```json
{
  "email": "string",            // 必填，格式校验同 §2.2
  "types": ["Bug Report"],      // 可选，JSON 数组；未选时按 ["Other"] 处理
  "functions": ["Search"],      // 可选，JSON 数组；未选时按 ["Other"] 处理
  "message": "string"           // 必填，最多 1000 字符
}
```

成功响应（201）：

```json
{
  "success": true,
  "data": {
    "id": "01JXXXXXX",
    "created_at": "..."
  }
}
```

客户端展示 Toast：`Feedback submitted. Thank you.`

错误：

| code | 触发条件 | 文案 |
|---|---|---|
| `VALIDATION_ERROR` | email 为空 | Please enter your email. |
| `VALIDATION_ERROR` | email 格式错误 | Please enter a valid email address. |
| `VALIDATION_ERROR` | message 为空 | Please enter your feedback. |
| `VALIDATION_ERROR` | message 超 1000 字符 | Message must be 1000 characters or less. |
| `INTERNAL_ERROR` | 写入失败 | Unable to submit feedback. Please try again later. |

> 注：此为来源 PRD 指定的场景专用失败文案，作为通用 Toast 的例外；最终以 global-rules.md 文案表为准。

---

### 5.3 运营配置

#### 5.3.1 获取 App 配置

```
GET /admin/app-config
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "configs": [
      {
        "key": "onboarding_images",
        "value": "[\"https://...\"]",
        "updated_by": "01JADMIN",
        "updated_at": "..."
      }
    ]
  }
}
```

---

#### 5.3.2 更新 App 配置

```
PATCH /admin/app-config/{key}
```

请求体：

```json
{
  "value": "string"   // JSON 字符串或纯字符串，取决于 key 类型
}
```

成功响应（200）：返回更新后的 app_config 记录。

> Workers 内部逻辑：将 `updated_by` 设为当前管理员 admin_user.id，`updated_at` 设为当前时间。

---

#### 5.3.3 获取 Trending Pin 列表

```
GET /admin/trending-pins
```

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "01JXXXXXX",
        "card_ref": "...",
        "rank": 1,
        "active": true,       // trending_pin.active = 1
        "updated_by": "...",
        "updated_at": "..."
      }
    ]
  }
}
```

---

#### 5.3.4 创建 Trending Pin

```
POST /admin/trending-pins
```

请求体：

```json
{
  "card_ref": "string",   // 必填；cards_all.product_id
  "rank": 1,              // 必填；从 1 开始
  "active": true
}
```

成功响应（201）：返回创建的 trending_pin 记录。

错误：

| code | 触发条件 |
|---|---|
| `CONFLICT` | 该 card_ref 已有置顶记录（trending_pin.card_ref UNIQUE） |

---

#### 5.3.5 更新 Trending Pin

```
PATCH /admin/trending-pins/{pin_id}
```

请求体：

```json
{
  "rank": 2,
  "active": false
}
```

成功响应（200）：返回更新后的 trending_pin 记录。

---

#### 5.3.6 删除 Trending Pin

```
DELETE /admin/trending-pins/{pin_id}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

---

### 5.4 卡牌数据运维

#### 5.4.1 获取 Card Override 列表

```
GET /admin/card-overrides
```

Query 参数：

| 参数 | 说明 |
|---|---|
| `is_missing_card` | `true` \| `false`（筛选缺失卡） |
| `q` | 按 card_ref 模糊搜索 |
| `page` / `page_size` | 分页 |

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "01JXXXXXX",
        "card_ref": "...",
        "override_fields": { "name": "Custom Name" },  // JSON 已解析
        "image_url": "https://...",
        "is_missing_card": false,
        "updated_by": "...",
        "updated_at": "..."
      }
    ],
    "total": 10,
    "page": 1,
    "page_size": 20
  }
}
```

---

#### 5.4.2 创建 Card Override（含缺失卡录入）

```
POST /admin/card-overrides
```

请求体：

```json
{
  "card_ref": "string",           // 必填；若 is_missing_card=true 可自定义 ID
  "override_fields": {},          // 可选；JSON 对象，字段级覆盖
  "image_url": "string",          // 可选；覆盖图片 URL
  "is_missing_card": false        // 默认 false；true = 手动录入缺失卡
}
```

成功响应（201）：返回创建的 card_override 记录。

错误：

| code | 触发条件 |
|---|---|
| `CONFLICT` | 该 card_ref 已有 override 记录（card_override.card_ref UNIQUE） |

---

#### 5.4.3 更新 Card Override

```
PATCH /admin/card-overrides/{override_id}
```

请求体：

```json
{
  "override_fields": { "name": "Corrected Name" },
  "image_url": "https://new-image.example.com/card.jpg"
}
```

成功响应（200）：返回更新后的 card_override 记录。

---

#### 5.4.4 删除 Card Override

```
DELETE /admin/card-overrides/{override_id}
```

成功响应（200）：

```json
{
  "success": true,
  "data": {}
}
```

---

#### 5.4.5 补图（更新 image_url）

**用途**：专用端点，供运营快速为指定 card_ref 更新图片（若 override 记录不存在则自动创建）。按 card_ref 而非 override_id 寻址，故采用独立静态路径，避免与 `/card-overrides/{override_id}` 冲突。

```
POST /admin/card-overrides/image-upload
```

请求体：

```json
{
  "card_ref": "string",
  "image_url": "string"
}
```

成功响应（200）：返回对应的 card_override 记录（已创建或已更新）。

---

### 5.5 扫描记录管理

#### 5.5.1 获取扫描记录列表

```
GET /admin/scans
```

Query：

| 参数 | 类型 | 说明 |
|---|---|---|
| `uid` | string | 按 owner_id 模糊搜索 |
| `platform` | string | 平台，如 `iOS` |
| `app_version` | string | App 版本 |
| `recognition_status` | string | `success` / `no_match` / `failed` |
| `user_confirmation_status` | string | `pending` / `confirmed` 等 |
| `modified_result` | boolean | 用户是否修改识别结果 |

成功响应（200）：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "scan_id": "01JXXXXXX",
        "image_url": "",
        "uid": "anon-1",
        "platform": "iOS",
        "app_version": "1.0.0",
        "scan_time": "2026-07-10T09:00:00.000Z",
        "recognition_status": "success",
        "user_confirmation_status": "pending",
        "modified_result": false
      }
    ],
    "page": 1,
    "page_size": 20
  }
}
```

#### 5.5.2 获取扫描记录详情

```
GET /admin/scans/{scan_id}
```

成功响应（200）：在列表字段基础上返回 `device_model`、`os_version`、`system_result`、`user_result`、`candidates`。

---

## 6. TBD 汇总

| # | 待定项 | 影响端点 |
|---|---|---|
| 1 | OAuth Client ID / Secret（Google / Apple） | §2.8、§2.9 |
| 2 | 邮件服务提供商（Resend / SES） | §2.2、§2.5 |
| 3 | 汇率接口提供方 | §4.8、§3.4.2（currency 枚举） |
| 4 | 卡牌基础表导入任务与数据刷新频率 | 所有读取卡牌目录、价格历史和 card_ref 的端点 |
| 5 | condition / finish 枚举合法值（取决于 `tcgplayer_skus` 实际枚举） | §3.2.2、§4.5 |
| 6 | Admin Refresh Token 存储方案（复用 `session` 表 `owner_type='admin'` 或独立表，实现阶段确认） | §5.0.1–5.0.3 |
| 7 | terms_url / privacy_url / app_store_url 实际值 | §5.3.1（app_config key） |
| 8 | 资产隐私合规留存/清除策略（登录态删号 + 游客态 anonymous_account 删除统一口径） | §2.12 删除账号、profile §6.3 |
| 9 | 各接口最终 TTL（取决于基础表刷新频率） | §4.1–§4.7 |
| 10 | 游客态删除账号端点：复用 §2.12（扩展接受匿名 JWT）或新增 anonymous_account 独立删除端点 | §2.12、profile §6.3 |
| 11 | 扫描图片长期存储（如 R2）与后台图片留存策略 | §4.10、§5.5 |
