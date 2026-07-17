# Profile 业务审计

## 0. 文档说明

- 分析范围：Flutter Profile/Account/Customer Support、Auth、Feedback、App Config、Legal 页面及生产 Cloudflare 配置。
- 设计真源：Figma 游客态 `142:10259`、登录态 `142:10380`、Account `142:10166`、Customer Support `235:3503`。
- 产品规则：`TCG_PRD_整合版.md` 第三章。
- 结论等级：`代码明确`、`代码推断`、`待确认`。本文不以进度文档状态作为完成证据。

## 1. 业务总览与主线

Profile 负责账号入口、账号只读信息、客服反馈、评分、分享、协议、退出和账号删除。主线为：启动时用真实 session 校验当前身份 -> Profile 按游客/用户展示 -> 用户执行原生动作或调用 Workers -> Auth 状态变化后回到游客态或刷新账号态 -> 资产继续按 owner 隔离。

| 模块 | 职责 | 真实入口 | 结论 |
|---|---|---|---|
| Profile | 展示身份和公共动作 | `ProfilePage` | 代码明确 |
| Account | 展示邮箱、ID、登录方式并执行退出/删除 | `AccountPage` | 代码明确 |
| Customer Support | 校验并提交反馈 | `POST /feedback` | 代码明确 |
| Score / Share | iOS 评分弹窗、App Store 回退、系统分享 | `in_app_review`、`share_plus` | 代码明确 |
| Terms / Privacy | 从运营配置读取 URL 并用系统浏览器打开 | `GET /app-config` | 代码明确 |

## 2. 角色、权限与数据隔离

| 身份 | 可见内容 | 服务端边界 | 证据 | 结论 |
|---|---|---|---|---|
| 游客 | Sign in、Support、Score、Share、协议、Version、Delete Account | 匿名 JWT；反馈和删除均重新鉴权 | `profile_page.dart`、`owner-auth.ts` | 代码明确 |
| 登录用户 | 邮箱、用户 ID、Account、Support、公共动作、Log Out | 用户 JWT；`/auth/me` 校验 session | `auth/current.ts`、`profile_page.dart` | 代码明确 |
| 未认证请求 | 不可提交反馈或删除账号 | 401 | `feedback/routes.ts`、`auth/account.ts` | 代码明确 |

Profile 的页面显隐不是权限边界。反馈和账号删除均由 Workers 重新认证 owner；Portfolio/Wishlist/Scan 等数据按 owner 查询，账号切换后不会混用。

## 3. 核心流程与异常

| 流程 | 正常结果 | 失败结果 | 结论 |
|---|---|---|---|
| 游客登录/注册 | 当前页调起 Auth Sheet；成功后刷新用户态 | 保持游客态并显示错误 | 代码明确 |
| 已有账号登录 | 不迁移当前游客资产 | 登录失败保持原状态 | 代码明确 |
| 新账号注册/OAuth 首次绑定 | 迁移已证明归属的游客资产 | 迁移失败保留可重试状态 | 代码明确 |
| Log Out | 撤销用户 session，创建新游客 session，云端资产保留 | 网络失败保持用户态 | 代码明确 |
| Delete Account | 二次确认后删除/软删账号数据，回到新游客态 | 保持原页面并显示统一失败文案 | 代码明确 |
| Submit Feedback | 写入 `feedback_ticket`，成功提示后回 Profile | 保留输入并允许重试 | 代码明确 |
| Score | 优先请求 iOS 原生评分；不可用时打开评论页 | 显示通用失败 Toast | 代码明确；App Store URL 待配置 |
| Share | 调起系统分享 App Store URL | 取消不报错；调起失败显示 Toast | 代码明确；App Store URL 待配置 |
| Terms / Privacy | 从 `/app-config` 读取真实 URL 并外部打开 | 缺配置或打开失败显示 Toast | 代码明确 |

## 4. 核心实体

| 实体 | 关键字段 | 生命周期 | 证据 |
|---|---|---|---|
| `AuthSession` | ownerType、token、userId、email、loginMethod | 启动恢复、刷新、退出或删除后替换 | `auth_models.dart` |
| `user` | email、display_name、deleted_at | 用户删除采用软删除 | `db/schema.ts` |
| `anonymous_account` | device_id、upgraded_user_id | 游客创建、升级或删除后失效 | `db/schema.ts` |
| `feedback_ticket` | email、types、functions、message、status | 创建为 open，供后台处理 | `db/schema.ts` |
| `app_config` | app_store_url、terms_url、privacy_url | 运营配置，客户端运行时读取 | `app-config/routes.ts` |

## 5. 业务规则与设计冲突

| 规则/冲突 | 当前决定 | 结论 |
|---|---|---|
| Type、Function 多选；空选按 Other | Flutter 与 Workers 双端执行 | 代码明确 |
| Email 必填且已登录用户自动填充 | Flutter 校验，Workers 再校验 | 代码明确 |
| Message 必填且最多 1000 字符 | Flutter 禁止超长提交，Workers 拒绝非法值 | 代码明确 |
| Figma 登录态含 Subscribe/Restore，PRD 3.1 明确 1.0 删除订阅 | 选择较新的 PRD 业务边界；当前代码不展示订阅；Figma 该节点待清理 | 明确冲突 |
| PRD 写 Account 标题，Figma Account 原型无可见标题 | 选择 Figma 视觉真源；保留 Account 语义标签 | 明确冲突 |

## 6. 上下游与影响面

| 依赖 | 方向 | 失败影响 | 证据 |
|---|---|---|---|
| Auth / OAuth / Email | 上游 | Profile 无法确定身份或切换账号 | `auth_controller.dart` |
| D1 / Workers | 上游 | 反馈、退出、删除失败 | `feedback/routes.ts`、`auth/account.ts` |
| App Config | 上游 | Score 回退、Share、协议链接不可用 | `profile_actions.dart` |
| App Store listing | 外部依赖 | `app_store_url` 无真实值 | 生产 `/app-config` 实测 |
| Portfolio/Wishlist/Scan | 下游 | 登录、退出、删除后需刷新 owner 数据 | PRD 全局联动规则 |

## 7. 术语

| 术语 | 含义 | 结论 |
|---|---|---|
| Guest / Anonymous | 有云端 owner 和 session、但未注册的游客账号 | 代码明确 |
| Login Method | EMAIL、GOOGLE 或 APPLE，只读展示 | 代码明确 |
| Score | iOS 原生评分请求及 App Store 评论页回退 | 代码明确 |
| Feedback Ticket | 用户提交并进入后台处理的客服工单 | 代码明确 |

## 8. 证据索引

| 编号 | 文件/位置 | 说明 |
|---|---|---|
| E1 | `apps/flutter-app/lib/features/profile/profile_page.dart` | 游客/登录 Profile 与公共动作 |
| E2 | `apps/flutter-app/lib/features/profile/account_page.dart` | Account 详情、退出和删除 |
| E3 | `apps/flutter-app/lib/features/profile/customer_support_page.dart` | 表单、校验、loading 与输入保留 |
| E4 | `apps/flutter-app/lib/features/profile/profile_actions.dart` | 原生评分、分享、协议跳转 |
| E5 | `apps/workers-api/src/feedback/routes.ts` | 真实反馈接口与服务端校验 |
| E6 | `apps/workers-api/src/auth/account.ts` | 真实账号删除 |
| E7 | `apps/workers-api/src/app-config/routes.ts` | 公开运行配置 |
| E8 | Figma `142:10259`、`142:10380`、`142:10166`、`235:3503` | Profile 设计真源 |
| E9 | `TCG_PRD_整合版.md:488` | Profile 业务规则 |

## 9. 生产验证与待确认项

生产验证（2026-07-17）：

- 真实 `POST /auth/anonymous` 创建匿名身份后，`GET /auth/me` 返回同一匿名 owner。
- 该匿名身份使用真实 `POST /feedback` 成功创建 open 工单；测试工单随后从远程 D1 删除，按工单 ID 查询剩余计数为 0。
- 该匿名身份使用真实 `DELETE /auth/account` 删除成功；原 access token 再请求 `GET /auth/me` 返回 401，证明旧 session 不可复用。
- Terms、Privacy、Support 三个 Legal 页面均返回 `200 text/html`。
- `/app-config` 已返回真实 `terms_url` 和 `privacy_url`；`app_store_url` 仍为 null。
- `/app-config.upgrade_prompt` 同样为 null；当前没有可用的升级跳转配置。
- Figma 游客态 `142:10259`、登录态 `142:10380`、Account `142:10166`、Customer Support `235:3503` 均已成功读取并与当前页面逐项核对。
- Flutter Profile 定向回归 42 项通过，覆盖登录入口、Account、Customer Support、退出、删除、失败重试及 Figma 画布约束。
- Workers 全量回归 28 个测试文件、249 项通过，TypeScript 类型检查与 dry-run 通过；覆盖反馈鉴权、账号删除、session 吊销、Scan 私有图片保留和估值事件 owner 迁移。
- Flutter 全量回归 237 项通过、1 项因缺少平台 dartcv 动态库明确跳过；`flutter analyze` 无问题。
- Cloudflare 当前生产 Worker 版本为 `8a482fcb-3e0f-4278-9fb3-f302a1545948`。

| 问题 | 影响 | 当前处理 |
|---|---|---|
| 生产 `app_store_url` 为 null | Share 必然失败；Score 原生弹窗不可用时无法回退评论页 | iOS App Store 记录建立后立即写入 D1，当前为上架阻断 |
| Figma 登录态仍含订阅区 | 设计与 PRD 冲突，易被后续误实现 | 以 PRD 为准，标记 Figma 待清理 |
| 原生评分弹窗是否实际展示由 iOS 系统决定 | 自动化测试只能验证调用路径 | TestFlight 真机验收 |
