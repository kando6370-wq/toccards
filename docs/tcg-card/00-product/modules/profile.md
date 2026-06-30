# Profile 模块 PRD

> **定位**：定义 tcg-card v1.0 Profile 页面（个人中心）的所有交互流程与规则，涵盖游客态 / 登录态 / Account 详情 / Customer Support / Score / Share / Terms & Privacy / Log Out。
>
> **日期**：2026-06-30
>
> **上游来源**：
> - 原始底稿 [`docs/tcg_cord_docs/个人中心.md`](../../../tcg_cord_docs/个人中心.md)
> - 跨切面规则 [`./global-rules.md`](./global-rules.md)（失败 Toast / 网络异常 / 确认弹窗 / 游客迁移）
> - 接口规范 [`../../03-data-api/api-spec.md`](../../03-data-api/api-spec.md)

> **v1.0 版本声明**：订阅相关内容（Upgrade to Pro / Subscribe / Unlock All / Go unlock / 订阅权益展示）**已全部删除**，不进入 v1.0。Restore 入口状态见 §十五。

---

## 目录

1. [页面入口](#一页面入口)
2. [Profile 游客态页面](#二profile-游客态页面)
3. [游客态点击 Sign in / Sign up](#三游客态点击-sign-in--sign-up)
4. [Profile 已登录态页面](#四profile-已登录态页面)
5. [Account 账号详情页](#五account-账号详情页)
6. [删除账号确认弹窗](#六删除账号确认弹窗)
7. [Customer Support 客户支持页](#七customer-support-客户支持页)
8. [Score 评分](#八score-评分)
9. [Share With Friends 分享 App](#九share-with-friends-分享-app)
10. [Terms Of Use / Privacy Policy](#十terms-of-use--privacy-policy)
11. [Log Out 退出登录](#十一log-out-退出登录)
12. [账号与卡牌资产绑定规则](#十二账号与卡牌资产绑定规则)
13. [状态与异常](#十三状态与异常)
14. [接口引用汇总](#十四接口引用汇总)
15. [v1.0 删除 / 隐藏项](#十五v10-删除--隐藏项)

---

## 一、页面入口

- 用户点击底部导航 **Profile** 进入。
- 未登录用户进入后展示**游客态页面**（§二）。
- 已登录用户进入后展示**登录态页面**（§四）。
- 点击账号区域进入 **Account 账号详情页**（§五）。
- 点击 **Customer Support** 进入客户支持页（§七）。
- 点击 **Terms Of Use / Privacy Policy** 跳转官网（§十）。

---

## 二、Profile 游客态页面

### 2.1 页面字段

| 区域 | 字段 / 按钮 | 说明 |
|---|---|---|
| Account | Sign in / Sign up | 登录 / 注册入口 |
| Support | Customer Support | 进入客户支持页 |
| Support | Score | 评分入口 |
| Support | Share With Friends | 分享 App |
| Others | Terms Of Use | 跳转官网协议页 |
| Others | Privacy Policy | 跳转官网隐私政策页 |
| 底部 | Version 1.0.0 | App 版本号 |

> **Log Out 在游客态不展示**（用户未登录，无可退出的账号）。

### 2.2 规则

- 游客态点击 Sign in / Sign up，在当前 Profile 页面原地调起注册 / 登录选项弹窗（不跳转新页面）。
- 弹窗内展示 Email / Apple / Google 注册 / 登录方式，具体逻辑以 Auth 模块 PRD（`auth.md`）为准。
- 游客态可点击 Customer Support、Score、Share With Friends、Terms Of Use、Privacy Policy。
- v1.0 不做订阅：Upgrade to Pro、Subscribe 相关区域已删除（见 §十五）。

---

## 三、游客态点击 Sign in / Sign up

```
用户点击 Sign in / Sign up
  ↓
在当前 Profile 页面上方原地调起注册 / 登录选项弹窗
  ↓
用户完成注册（新账号）
  ├─ 游客资产迁移到新账号（引用 global-rules.md §14.3）
  └─ Profile 自动刷新为已登录态
  ↓
用户完成登录（已有账号）
  ├─ 游客资产不迁移（引用 global-rules.md §14.4）
  └─ Profile 自动刷新为已登录态，展示该账号资产
```

> 游客状态定义、迁移范围、迁移失败处理、登录与注册区别均引用 `./global-rules.md §十四`，本文档不重复定义。

---

## 四、Profile 已登录态页面

### 4.1 页面字段

| 区域 | 字段 / 按钮 | 示例 / 说明 |
|---|---|---|
| 顶部卡片 | 用户邮箱 | `issuer@gmail.com`（当前登录账号） |
| 顶部卡片 | 用户 ID | `ID: 12345` |
| Account | 账号卡片（邮箱 + ID） | 点击进入 Account 详情页 |
| Support | Customer Support | 进入客户支持页 |
| Support | Score | 评分入口 |
| Support | Share With Friends | 分享 App |
| Others | Terms Of Use | 跳转官网 |
| Others | Privacy Policy | 跳转官网 |
| 底部 | Log Out | 退出登录 |
| 底部 | Version 1.0.0 | App 版本号 |

### 4.2 规则

- 展示当前登录用户的邮箱和用户 ID（`GET /auth/me` — api-spec §2.14）。
- 点击账号区域进入 Account 详情页（§五）。
- 用户卡牌资产与账号绑定（详见 §十二）。
- 用户切换账号后，只展示当前账号下的 Portfolio、Wishlist、扫描添加记录和相关收藏资产。
- 点击 Log Out 退出当前账号，返回游客态（§十一）。
- v1.0 不做订阅：订阅卡片和订阅入口已删除（见 §十五）。

---

## 五、Account 账号详情页

### 5.1 入口

Profile 已登录态点击账号卡片区域。

### 5.2 页面字段

| 字段 / 按钮 | 位置 / 说明 |
|---|---|
| 返回按钮 | 左上角，返回 Profile |
| 标题 | Account |
| 头像 / 首字母占位 | 用户头像占位（如字母 S） |
| 邮箱 | 当前账号邮箱（只读） |
| ID | 用户 ID（只读） |
| Login Method | 登录方式（只读，如 Email / Google / Apple） |
| Log Out | 退出登录按钮 |
| Delete account | 删除账号入口 |

### 5.3 规则

- 邮箱、ID、Login Method 为只读信息，不可在此页编辑。
- 点击 Log Out 执行退出登录流程（§十一）。
- 点击 Delete account 展示删除账号确认弹窗（§六）。
- 用户卡牌资产与账号绑定，删除账号会影响账号下所有资产数据，因此必须二次确认。

---

## 六、删除账号确认弹窗

### 6.1 触发

Account 详情页点击 **Delete account**。

### 6.2 弹窗内容

| 元素 | 内容 |
|---|---|
| 标题 | `Delete Account?` |
| 说明 | `This action is permanent and can't be undone.` |
| 次按钮 | `Cancel` |
| 主按钮 | `Delete` |

### 6.3 规则

- 点击 **Cancel** → 关闭弹窗，不删除账号，返回 Account 页。
- 点击 **Delete** → 调用 `DELETE /auth/account`（api-spec §2.12）。
  - 成功：退出登录，返回游客态 Profile；账号绑定资产按隐私合规要求处理（⚠️ TBD，见 api-spec §6 TBD #8）。
  - 失败：保留当前账号状态，展示专用失败文案（引用 `./global-rules.md §13.2`）：`Unable to complete this action. Please try again later.`
- 删除账号属于高风险操作，不允许无确认直接删除（引用 `./global-rules.md §九`）。

---

## 七、Customer Support 客户支持页

### 7.1 入口

Profile（游客态 / 登录态）点击 **Customer Support**。

### 7.2 页面字段

| 区域 | 字段 / 控件 | 说明 |
|---|---|---|
| 顶部 | 返回按钮（左上角）、标题 Customer Support | 页面头部 |
| 表单 | **Type**（多选）| Bug Report、Feature Request、Improvement、Other |
| 表单 | **Function**（多选）| Scan、Search、Collection、Portfolio、Wishlist、Account、Price Data、Other |
| 表单 | **Email**（必填）| 输入框，placeholder: `your@email.com` |
| 表单 | **Message**（必填）| 输入框，placeholder: `Tell us what's on your mind...` |
| 底部 | **Submit Feedback** 按钮 | 提交反馈 |

> **注**：v1.0 删除订阅，Function 选项中的 **Subscription** 已删除（见 §十五）。

### 7.3 Type 规则

- Type 支持多选，可选一个或多个；再次点击已选项取消选择。
- Type 非必填；未选时后端按 `["Other"]` 处理（api-spec §5.2.4）。

### 7.4 Function 规则

- Function 支持多选，可选一个或多个；再次点击已选项取消选择。
- Function 非必填；未选时后端按 `["Other"]` 处理（api-spec §5.2.4）。
- **Subscription 选项已在 v1.0 中删除**（见 §十五）。

### 7.5 Email 规则

| 规则 | 说明 |
|---|---|
| 必填 | 邮箱不能为空 |
| 格式校验 | 同 auth.md §九邮箱校验规则 |
| 已登录用户 | 进入页面时自动填入当前账号邮箱，用户可修改 |
| 游客用户 | 邮箱为空，需手动填写 |

错误提示：

| 场景 | 文案 |
|---|---|
| 邮箱为空 | `Please enter your email.` |
| 邮箱格式错误 | `Please enter a valid email address.` |

### 7.6 Message 规则

| 规则 | 说明 |
|---|---|
| 必填 | Message 为空不允许提交 |
| 最多 1000 字符 | 超长不允许提交 |

错误提示：

| 场景 | 文案 |
|---|---|
| Message 为空 | `Please enter your feedback.` |
| Message 超 1000 字符 | `Message must be 1000 characters or less.` |

### 7.7 Submit Feedback 规则

- 点击 Submit Feedback 后依次校验 Email 和 Message；校验失败在对应字段下展示错误提示。
- 校验通过后调用 `POST /feedbacks`（api-spec §5.2.4）。
- 提交中：按钮展示 loading，禁止重复点击（引用 `./global-rules.md §十一`）。
- 提交成功：展示成功 Toast：`Feedback submitted. Thank you.`；清空表单并返回 Profile。
- 提交失败：保留用户填写内容，展示专用失败文案（引用 `./global-rules.md §13.2`）：`Unable to submit feedback. Please try again later.`

### 7.8 接口引用

| 端点 | 说明 |
|---|---|
| `POST /feedbacks` — api-spec §5.2.4 | 提交用户反馈 |

---

## 八、Score 评分

### 8.1 入口

Profile 页面点击 **Score**。

### 8.2 规则

1. 优先调用 iOS 系统原生评分弹窗（`SKStoreReviewController`）。
2. 若系统当次不展示原生弹窗（展示频率已耗尽），则跳转 App Store 写评论页。
3. 用户关闭评分弹窗后返回 Profile。
4. 用户从 App Store 返回后回到 App。
5. 跳转 App Store 失败时留在原页面，不提示错误。此为 global-rules.md §4.2 的静默例外（评分 / App Store 跳转失败不弹 Toast，评分为可选操作）。

> iOS 原生评分弹窗存在系统级展示频率限制，不能保证每次点击均弹出。

---

## 九、Share With Friends 分享 App

### 9.1 入口

Profile 页面点击 **Share With Friends**。

### 9.2 规则

- 调起苹果原生分享弹窗（`UIActivityViewController`）。
- 分享内容：App Store 下载链接（⚠️ TBD，见 api-spec §6 TBD #7 `app_store_url`）。
- 用户可将链接分享到第三方 App。
- 用户取消分享后不提示错误，停留 Profile。
- 分享弹窗调起失败时，使用通用 Toast（引用 `./global-rules.md §四`）。

---

## 十、Terms Of Use / Privacy Policy

### 10.1 入口

Profile 页（游客态 / 登录态）的 Others 区域。

### 10.2 规则

| 入口 | 行为 |
|---|---|
| Terms Of Use | 跳转官网 Terms 页面（⚠️ TBD：`terms_url`，见 api-spec §6 TBD #7） |
| Privacy Policy | 跳转官网 Privacy 页面（⚠️ TBD：`privacy_url`，见 api-spec §6 TBD #7） |

- 两个协议页面不在 App 内本地展示，统一跳转外部链接（系统浏览器或 App 内 WebView，⚠️ TBD：需确认跳转方式）。
- 官网链接需在正式上线前配置完成。
- 跳转失败时，展示专用失败文案（引用 `./global-rules.md §13.2`）：`Unable to open this page. Please try again later.`

---

## 十一、Log Out 退出登录

### 11.1 入口

- Profile 已登录态页面底部 **Log Out**。
- Account 详情页中的 **Log Out**。

### 11.2 规则

- 点击 Log Out 后退出当前账号：调用 `POST /auth/logout`（api-spec §2.11）。
- 退出成功：返回游客态 Profile；账号绑定的云端卡牌资产不删除。
- 退出后，Portfolio、Wishlist、账号详情等账号资产数据不再展示。
- 用户再次登录同一账号后，恢复该账号绑定的资产。
- 退出失败：保留当前账号状态，展示专用失败文案（引用 `./global-rules.md §13.2`）：`Unable to complete this action. Please try again later.`
- 【建议】退出登录前可展示确认弹窗以避免误触（⚠️ TBD：当前原始 PRD 未画确认弹窗，需确认是否加入）。

### 11.3 接口引用

| 端点 | 说明 |
|---|---|
| `POST /auth/logout` — api-spec §2.11 | 吊销当前 session |

---

## 十二、账号与卡牌资产绑定规则

- 用户的 Portfolio 文件夹、Collection Item、Wishlist、扫描添加记录、文件夹排序 / 默认设置、货币偏好、金额隐藏偏好均与账号绑定（引用 `./global-rules.md §八`）。
- 已登录状态下新增、编辑、删除的卡牌资产归属于当前账号。
- 切换账号后，只展示新账号下的数据。
- 退出登录后 Profile 回到游客态；账号资产不删除，再次登录后恢复。
- 游客注册成功：游客资产迁移到新账号（引用 `./global-rules.md §14.3`）。
- 游客登录已有账号：游客资产不迁移、不合并（引用 `./global-rules.md §14.4`）。

---

## 十三、状态与异常

### 13.1 网络断开

无网络时统一使用专用文案（引用 `./global-rules.md §五`）：

```
No internet connection. Please check your network and try again.
```

适用场景：Restore（Restore 本身 ⚠️ TBD，按 §十五 决策保留）/ Submit Feedback / Log Out / Delete Account / 打开官网协议链接 / 账号信息刷新。

### 13.2 整页数据加载失败

Profile 账号信息和基础入口整体加载失败时，展示整页失败状态（引用 `./global-rules.md §2.2`）：`No content available` + `Refresh`。

### 13.3 场景专用失败文案

以下场景使用专用失败文案，均引用 `./global-rules.md §13.2`，本文档不重复定义：

| 场景 | 专用失败文案 |
|---|---|
| 删除账号失败 / 退出登录失败 | `Unable to complete this action. Please try again later.` |
| 提交反馈失败 | `Unable to submit feedback. Please try again later.` |
| 官网链接打开失败 | `Unable to open this page. Please try again later.` |

---

## 十四、接口引用汇总

| 场景 | 端点 | api-spec 节点 |
|---|---|---|
| 获取当前账号信息 | `GET /auth/me` | §2.14 |
| 退出登录 | `POST /auth/logout` | §2.11 |
| 删除账号 | `DELETE /auth/account` | §2.12 |
| 提交用户反馈 | `POST /feedbacks` | §5.2.4 |

---

## 十五、v1.0 删除 / 隐藏项

v1.0 不做订阅，以下内容**已删除，不进入首版**：

| 删除项 | 来源 |
|---|---|
| Upgrade to Pro | 原始 PRD §十五 |
| Unlock All | 原始 PRD §十五 |
| Go unlock | 原始 PRD §十五 |
| Subscribe | 原始 PRD §十五 |
| 所有订阅权益展示 | 原始 PRD §十五 |
| Customer Support — Function 选项 Subscription | 原始 PRD §8.3 |

**Restore（恢复购买）** ⚠️ TBD：
- 若 v1.0 无任何内购 / 订阅，建议隐藏 Restore。
- 若 App Store 审核需要保留恢复购买入口，需确认是否存在任何可恢复权益后再决定。
- **当前状态：标记为 ⚠️ TBD，待上线前最终确认。**
