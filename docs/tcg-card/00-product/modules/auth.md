# Auth 模块 PRD

> **定位**：定义 tcg-card v1.0 注册、登录、找回密码的完整交互流程与校验规则。
>
> **日期**：2026-06-30
>
> **上游来源**：
> - 原始底稿 [`docs/tcg-card/source-tcg-card-docs/注册登录.md`](../../source-tcg-card-docs/注册登录.md)
> - 跨切面规则 [`./global-rules.md`](./global-rules.md)（失败 Toast / 网络异常 / 确认弹窗 / 游客迁移）
> - 接口规范 [`../../03-data-api/api-spec.md`](../../03-data-api/api-spec.md)

---

## 目录

1. [入口](#一入口)
2. [注册登录方式选择](#二注册登录方式选择)
3. [Email 注册流程](#三email-注册流程)
4. [Email 登录流程](#四email-登录流程)
5. [找回密码流程](#五找回密码流程)
6. [Google 登录 / 注册流程](#六google-登录--注册流程)
7. [Apple 登录 / 注册流程](#七apple-登录--注册流程)
8. [匿名账号升级（游客迁移）](#八匿名账号升级游客迁移)
9. [邮箱校验规则](#九邮箱校验规则)
10. [密码规则](#十密码规则)
11. [验证码规则](#十一验证码规则)
12. [成功 Toast](#十二成功-toast)
13. [全部错误文案](#十三全部错误文案)

---

## 一、入口

用户可从以下两处进入注册登录流程：

1. Profile 未登录态点击 **Sign in / Sign up**（在 Profile 页原地调起弹窗，不跳转新页面）。
2. Onboarding 结束页的注册 / 登录引导。

---

## 二、注册登录方式选择

进入流程后展示注册 / 登录选项页，包含以下三个入口（顺序如下）：

| 按钮文案 | 跳转流程 |
|---|---|
| Continue with Google | §六 Google 流程 |
| Continue with Apple | §七 Apple 流程 |
| Continue with Email | 进入邮箱输入页（§三 / §四） |

---

## 三、Email 注册流程

**触发条件**：用户输入的邮箱尚未注册（`POST /auth/register/send-code` 后端返回非 `CONFLICT`）。

### 3.1 流程步骤

```
用户点击 Continue with Email
  ↓
进入邮箱输入页
  ↓
用户输入邮箱并点击 Continue
  ↓
客户端校验邮箱格式（§九）
  ├─ 格式错误 → 展示错误提示（见 §十三）
  └─ 格式正确 → 调用 POST /auth/register/send-code
                    ├─ CONFLICT（邮箱已注册）→ 切换至登录流程（§四）
                    ├─ RATE_LIMITED → 提示 60 秒后重试
                    └─ 成功 → 进入验证码输入页
  ↓
用户输入 6 位验证码
  ├─ 错误 → "Incorrect verification code."
  ├─ 过期 → "Code expired. Please request a new code."
  └─ 正确 → 进入 Set Password 页面
  ↓
用户输入 Password 和 Confirm Password
  ├─ 密码少于 8 位 → 禁止提交（见 §十）
  ├─ 两次输入不一致 → "Passwords do not match."
  └─ 通过 → 用户点击 Create Account
  ↓
调用 POST /auth/register/verify（含 anonymous_id，见 §八）
  ├─ 成功（migrated=true / false）→ 展示注册成功 Toast，进入 App
  └─ 失败 → 见 §十三
```

### 3.2 接口引用

| 步骤 | 端点 |
|---|---|
| 发送注册验证码 | `POST /auth/register/send-code` — api-spec §2.2 |
| 验证验证码 + 完成注册 | `POST /auth/register/verify` — api-spec §2.3 |

### 3.3 倒计时 / 重发

验证码输入页展示 60 秒倒计时；倒计时结束后显示 **Resend code** 链接，点击重新调用 `POST /auth/register/send-code`。

---

## 四、Email 登录流程

**触发条件**：用户输入的邮箱已注册（`POST /auth/register/send-code` 返回 `CONFLICT`，或用户从登录入口进入）。

### 4.1 流程步骤

```
用户在邮箱输入页输入已注册邮箱
  ↓
系统识别邮箱已注册 → 进入密码输入页
  ↓
用户输入密码并点击 Sign in
  ↓
调用 POST /auth/login
  ├─ 密码错误 → "Incorrect password. Please try again."
  └─ 成功 → 展示登录成功 Toast，进入 App
```

### 4.2 接口引用

| 步骤 | 端点 |
|---|---|
| 邮箱密码登录 | `POST /auth/login` — api-spec §2.4 |

---

## 五、找回密码流程

**入口**：邮箱登录页点击 **Forgot password**。

### 5.1 流程步骤

```
用户点击 Forgot password → 进入 Reset Password 页面
  ↓
用户输入邮箱并提交
  ↓
客户端校验邮箱格式
  ├─ 格式错误 → "Please enter a valid email address."
  └─ 格式正确 → 调用 POST /auth/forgot-password/send-code
                    ├─ 邮箱未注册 → "Email not registered. Please check your email or create a new account."
                    ├─ RATE_LIMITED → 提示 60 秒后重试
                    └─ 成功 → 进入验证码输入页
  ↓
用户输入 6 位验证码
  ├─ 错误 → "Incorrect verification code."
  ├─ 过期 → "Code expired. Please request a new code."
  └─ 正确 → 调用 POST /auth/forgot-password/verify-code，获取 reset_token
  ↓
进入 Set New Password 页面
  ↓
用户输入 New Password 和 Confirm Password
  ├─ 密码少于 8 位 → 禁止提交
  ├─ 两次输入不一致 → "Passwords do not match."
  └─ 通过 → 用户点击 Reset Password
  ↓
调用 POST /auth/forgot-password/reset
  ├─ reset_token 无效 / 已过期 → "Code expired. Please request a new code."
  └─ 成功 → 展示 Toast："Password reset successfully."，返回邮箱登录页
```

### 5.2 接口引用

| 步骤 | 端点 |
|---|---|
| 发送找回密码验证码 | `POST /auth/forgot-password/send-code` — api-spec §2.5 |
| 验证验证码 | `POST /auth/forgot-password/verify-code` — api-spec §2.6 |
| 重置密码 | `POST /auth/forgot-password/reset` — api-spec §2.7 |

---

## 六、Google 登录 / 注册流程

### 6.1 流程步骤

```
用户点击 Continue with Google
  ↓
App 拉起 Google 原生授权页
  ├─ 用户取消授权 → 返回注册登录选项页，不创建账号
  └─ 授权成功 → App 获取 authorization_code
  ↓
调用 POST /auth/oauth/google/callback（含 anonymous_id，见 §八）
  ├─ is_new_user=true → 展示注册成功 Toast，进入 App
  ├─ is_new_user=false → 展示登录成功 Toast，进入 App
  └─ 授权码无效 / 第三方异常 → "Authorization failed. Please try again."
```

### 6.2 接口引用

| 步骤 | 端点 |
|---|---|
| Google OAuth 回调 | `POST /auth/oauth/google/callback` — api-spec §2.8 |

> ⚠️ TBD：Google OAuth Client ID / Secret（见 api-spec §6 TBD #1）。

---

## 七、Apple 登录 / 注册流程

### 7.1 流程步骤

```
用户点击 Continue with Apple
  ↓
App 拉起 Apple 原生授权页
  ├─ 用户取消授权 → 返回注册登录选项页，不创建账号
  └─ 授权成功 → App 获取 authorization_code 和 id_token
  ↓
调用 POST /auth/oauth/apple/callback（含 anonymous_id，见 §八）
  ├─ is_new_user=true → 展示注册成功 Toast，进入 App
  ├─ is_new_user=false → 展示登录成功 Toast，进入 App
  └─ 授权码无效 / 第三方异常 → "Authorization failed. Please try again."
```

### 7.2 接口引用

| 步骤 | 端点 |
|---|---|
| Apple OAuth 回调 | `POST /auth/oauth/apple/callback` — api-spec §2.9 |

> ⚠️ TBD：Apple Service ID / Team ID / Key ID（见 api-spec §6 TBD #1）。

---

## 八、匿名账号升级（游客迁移）

### 8.1 位置

游客迁移发生在 Auth 流程的**注册完成阶段**（Email 注册 §三、Google 新用户 §六、Apple 新用户 §七），与注册请求同步提交 `anonymous_id`。

**游客登录已有账号时不迁移**（见 global-rules.md §14.4）。

### 8.2 机制

- Email 注册：`POST /auth/register/verify` 请求体中携带 `anonymous_id`（api-spec §2.3）。
- Google / Apple 新用户注册：`POST /auth/oauth/*/callback` 请求体中携带 `anonymous_id`（api-spec §2.8、§2.9）。
- 若迁移在注册请求中失败，客户端可显式重试：`POST /auth/migrate-assets`（api-spec §2.13）。

### 8.3 规则引用

游客状态定义、迁移范围、迁移失败处理、退出后处理、删除账号后处理均引用 `./global-rules.md §十四`，本文档不重复定义。

---

## 九、邮箱校验规则

以下规则适用于所有需要输入邮箱的场景（注册、登录、找回密码、Customer Support 反馈表单）。

| 规则 | 说明 |
|---|---|
| 不能为空 | 必填 |
| 包含且仅含一个 `@` | 格式校验 |
| `@` 前后均需有有效内容 | 格式校验 |
| 域名部分包含至少一个 `.` | 格式校验 |
| 不允许空格 | 格式校验 |
| 最多 254 个字符 | 长度限制 |
| 提交前自动去除首尾空格并转小写 | 预处理 |

### 错误提示

| 场景 | 文案 |
|---|---|
| 邮箱为空 | `Please enter your email.` |
| 格式错误 | `Please enter a valid email address.` |
| 超 254 字符 | `Email must be 254 characters or less.` |

---

## 十、密码规则

| 规则 | 说明 |
|---|---|
| 最少 8 位 | 注册和重置密码均适用 |
| Password 与 Confirm Password 必须一致 | 客户端校验 |

### 错误提示

| 场景 | 文案 |
|---|---|
| 密码少于 8 位 | `Password must be at least 8 characters.` |
| 两次密码不一致 | `Passwords do not match.` |

---

## 十一、验证码规则

| 规则 | 说明 |
|---|---|
| 6 位数字 | 注册和找回密码均适用 |
| 有效期 10 分钟 | api-spec §2.2 `expires_in: 600` |
| 同一邮箱 60 秒内不可重复发送 | api-spec §2.2 `resend_after: 60` |
| 验证码输入错误可重新输入 | 允许多次输入 |
| 错误次数过多时需重新获取 | 由后端控制，前端提示引导重发 |

---

## 十二、成功 Toast

| 场景 | Toast 文案 |
|---|---|
| Email 注册成功 | `Welcome` / `Let's collect the cards.` |
| Email / Google / Apple 登录成功（已有账号） | `Welcome back` |
| Google / Apple 新用户注册成功 | `Welcome` / `Let's collect the cards.` |
| 重置密码成功 | `Password reset successfully.` |

> Toast 展示规则（展示时长、位置、不阻塞操作等）引用 `./global-rules.md §四`。

---

## 十三、全部错误文案

### 13.1 邮箱相关

| 场景 | 文案 |
|---|---|
| 邮箱为空 | `Please enter your email.` |
| 邮箱格式错误 | `Please enter a valid email address.` |
| 邮箱超 254 字符 | `Email must be 254 characters or less.` |
| 邮箱未注册（找回密码） | `Email not registered. Please check your email or create a new account.` |

### 13.2 验证码相关

| 场景 | 文案 |
|---|---|
| 验证码错误 | `Incorrect verification code.` |
| 验证码过期 / 已使用 | `Code expired. Please request a new code.` |

### 13.3 密码相关

| 场景 | 文案 |
|---|---|
| 密码少于 8 位 | `Password must be at least 8 characters.` |
| 两次密码不一致 | `Passwords do not match.` |
| Email 登录密码错误 | `Incorrect password. Please try again.` |

### 13.4 第三方授权相关

| 场景 | 文案 |
|---|---|
| Google / Apple 授权失败 | `Authorization failed. Please try again.` |

### 13.5 游客资产迁移失败

引用 `./global-rules.md` §十三文案表（专用失败文案）中"游客资产迁移失败"：`Something went wrong. Please try again later.`

### 13.6 通用 / 网络异常

网络异常文案、通用操作失败文案均引用 `./global-rules.md §十三`，本文档不重复定义。
