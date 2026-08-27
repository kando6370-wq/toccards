# v1.1.0 管理后台实现

## 1. 运行与身份边界

Admin 是 `apps/admin-web` 构建的 React SPA，静态产物由 Workers assets 托管。它使用独立 `admin_user`、Access/Refresh Token 和 `/api/v1/admin` API，不复用 App 用户会话。

- `admin_user.status` 必须为 `active`。
- 角色为 `operator` 或 `super_admin`。
- 前端菜单对两类角色相同；最终操作权限由 `apps/workers-api/src/admin/routes.ts` 校验。
- 登录页的“设置密码”当前只做表单提示，没有提交密码的后端 API，不能描述为可自助重置。

## 2. 当前菜单与能力

| 分组 | 页面 | 主要能力 | API |
|---|---|---|---|
| 数据统计 | 安装统计 | 安装总量、国家/平台、趋势和明细 | `/analytics/installations` |
| 数据统计 | 订单统计 | 组合筛选、分页、刷新、XLSX 导出 | `/billing/transactions*` |
| 数据统计 | 苹果通知消息 | 通知筛选、分页、详情和 decoded payload | `/apple-notifications*` |
| 用户管理 | 用户列表 | 正式/匿名用户查询、详情 | `/users*` |
| 用户管理 | 用户反馈 | 反馈列表、详情、处理状态 | `/feedbacks*` |
| 用户管理 | 权限管理 | 管理 Admin 账号、角色和状态 | `/permissions*` |
| 卡牌管理 | 扫描记录管理 | 条件筛选、识别/确认详情、受保护图片 | `/scans*` |
| App 版本管理 | 版本管理 | iOS/Google 版本和升级行为 | `/app-versions*` |

安装统计的趋势数据按日期正序返回，保证图表时间轴从左到右；明细列表在数据库分页前按首次安装日期倒序，同日期按 UID、国家和平台稳定排序，优先展示最近安装且避免跨页顺序漂移。

Workers 还实现通用 App Config 和 Card Override API，但当前 `App.tsx` 的 `MenuKey` 与 `menuGroups` 没有对应页面。这些是后端能力，不是当前可从 Admin UI 操作的页面。旧 Trending Pin API 已废弃，不再属于 Admin 能力。

## 3. 角色权限

| 操作 | operator | super_admin | 后端证据 |
|---|---:|---:|---|
| 查看当前菜单数据 | 是 | 是 | Admin 鉴权中间件 |
| 更新反馈、版本和一般 App Config | 是 | 是 | 对应 PATCH 路由 |
| 创建/更新 Card Override | 是 | 是 | 对应 POST/PATCH 路由 |
| 禁用正式 App 用户 | 否 | 是 | `PATCH /users/user/:id/disable` |
| 创建或修改 Admin 权限 | 否 | 是 | `/permissions` POST/PATCH |
| 删除 Card Override | 否 | 是 | 对应 DELETE 路由 |

正式用户禁用只接受 user 路径，不把匿名账号伪装成可禁用正式用户。角色限制必须保留在服务端；只隐藏按钮不足以授权。

## 4. 订单统计

### 4.1 查询

查询区有 11 类条件：UID、订单 ID、国家/地区、SKU、订单状态、当前订阅状态、安装时间、订单时间、自动续订、环境和扣款次数。两个时间范围各拆成 from/to，因此 API 接受 13 个筛选参数，并按 AND 语义组合。

列表固定 13 列：UID、订单 ID、国家/地区、安装时间、订单时间、SKU、订单状态、当前订阅状态、自动续订、环境、原始金额、USD 金额、扣款次数。默认按有效订单时间和创建时间倒序，分页大小由 API 限制到最多 100。

订单国家/地区直接取已验签 Apple 交易的 `storefront`。数据库和筛选值保留 Apple 原始 ISO 3166-1 alpha-3 代码；Admin 展示层同时兼容 alpha-3 storefront 与既有 alpha-2 安装国家码，并统一转换为中文名称。缺失值显示 `--`，非空但无法识别的代码显示“未知”；不得从交易币种或安装 IP 猜测订单国家。

输入异常处理：

- 非法枚举、金额/次数或时间范围返回 `422`，不静默忽略。
- 查询、重置、刷新、翻页和导出在请求期间避免重复提交。
- 缺失值显示 `--`，但 `auto_renew=false` 必须显示“否”，不能误当空值。

证据：`apps/admin-web/src/App.tsx: BillingOrdersPage`、`apps/workers-api/src/admin/routes.ts: billingTransactionQuery()`、`billing-routes.integration.test.ts`。

### 4.2 订单事实

- Admin 订单统计的直接真值是已验签、已解码并完成业务清洗的 Apple 通知。Fresh Purchase/Restore 可先保存服务端验签通过的交易暂存证据并维护当前 session grant，但 `source_notification_uuid` 为空的记录不进入订单列表、筛选选项或 XLSX，也不参与 Admin 扣款序号。
- 建单类通知到达已有 `environment + transactionId` 时，会用通知中的已验签交易字段晋升暂存记录并写入来源通知 UUID；不会因唯一键冲突继续保留为客户端暂存口径。
- purchase chain 以 `environment + originalTransactionId` 唯一。
- 单笔交易以 `store + environment + transactionId` 幂等。
- Trial 扣款次数为 0；通知确认的有效非 Trial 收费按购买链时序累计，客户端暂存记录不占序号。
- Refund 更新原订单为 refunded、保存退款前业务状态并保留交易事实，不创建虚假收费订单；`REFUND_REVERSED` 经 Apple Server API 校正为 active 后恢复退款前状态。迁移前历史退款若没有该状态，则业务分类显示为未知，不继续显示退款，也不猜测订单类型。
- 自动续订显示使用交易发生时的 snapshot，不能被购买链后续状态倒灌。
- UID 仅用于业务关联；`unlinked` 购买链不是匿名用户，也不是 Premium owner。

来源：PostgreSQL 迁移 `0000_business_schema.sql`、`0007_billing_refund_status.sql`，`billing-order-facts.ts` 和集成测试。

### 4.3 XLSX 导出

- 导出复用当前查询筛选和排序。
- 0 行返回 not found；超过 10,000 行返回 `EXPORT_LIMIT_EXCEEDED`，不生成部分文件冒充全量。
- Workbook 包含订单列表之外的原始交易 ID、国家代码、币种、退款时间和 Apple 通知字段。
- `admin/xlsx.ts` 对可能触发公式的单元格做安全处理。

## 5. Apple 通知消息

### 5.1 列表与筛选

筛选项为 UID、原始交易 ID、订单 ID、环境、主通知类型、子通知类型和创建时间范围。列表显示 UID、原始交易 ID、订单 ID、主/子通知、SKU、环境、UTC+0 创建时间和详情操作，默认按 inbox 接收时间倒序。

主通知类型和子通知类型均为可搜索单选，选中主类型后子类型只显示对应实际组合；选项来自结构化通知实际数据，未知 Apple 类型直接显示原值。查询、重置、刷新和分页在列表请求期间禁用；空结果与加载失败使用固定业务文案，页码超过最新总页数时回退到最后一个有效页。

结构化通知与原始 inbox 使用 LEFT JOIN：验签、解析或处理失败时，即使没有结构化行，失败记录仍出现在列表，供排障。

### 5.2 详情与敏感内容

- 列表不返回完整 payload。
- 详情按需返回 decoded payload 和 processing error；抽屉先显示独立 Loading，请求失败显示固定错误和重试入口。
- 详情按“基本信息”和“完整通知内容（Decoded Payload）”分区；桌面基本信息两列、小屏一列，JSON 使用深色可滚动代码块。
- 前端只在用户主动操作时复制 JSON，成功提示“已复制通知内容”。
- API 不返回 `signed_payload`，避免把原始 JWS 暴露给浏览器。
- 未产生 decoded payload 时展示固定失败类型和 `last_error`，不显示伪造 JSON。
- 原始 JWS 已入 inbox 不代表已经生成明文；只有 Worker 完成外层通知及嵌套 transaction/renewal JWS 在线验签后才写 `decoded_payload`。可重试验签失败会由 5 分钟任务继续处理，成功后同一详情自动获得结构化字段和 Decoded Payload，无需人工改写数据库。

Admin 页面是只读排障层，不提供重放通知、改订单、改 lifecycle 或人工授予 Premium 的操作。

## 6. 其他运营页面

### 用户与反馈

- 用户列表覆盖正式与匿名身份，详情路径带 `accountType` 和 ID。
- 只有 super_admin 可禁用正式用户。
- Feedback 新建值 `open` 在 Admin 归并为 `pending`；运营可更新为 `pending/processed/ignored`，旧 `in_progress/closed` 读取时兼容映射。

### 扫描审计

- 可按平台、识别状态、确认状态和是否修改结果等筛选。
- 详情展示系统候选、置信度、用户确认和是否入库等事实。
- R2 图片端点要求 Admin Token，并返回私有、不可缓存响应。

### 版本管理

- UI 管理 iOS 与 Google 的最新/最低版本、强制升级和商店地址。
- 公共 `/app-config` 由 App 读取；Admin 更新应保留平台和环境边界。

## 7. API 与前端契约

| 契约 | 规则 |
|---|---|
| Admin 鉴权 | 独立 Access/Refresh Token；失效后不能继续请求受保护数据 |
| 分页 | 页码从 1 开始；后端限制 page size；前端越界时按响应总量回退 |
| 时间 | 订单和通知页面统一展示 UTC+0 |
| 空值 | UI 使用 `--`；布尔 false 和数字 0 不是空值 |
| 错误 | 查询失败显示固定业务文案；不得用空列表掩盖服务端错误 |
| 导出 | 与列表筛选一致；上限和空结果显式失败 |
| Payload | 仅详情按需加载 decoded payload；不返回 signed JWS |

## 8. 部署与验证边界

Admin 没有独立生产部署目标。Workers deploy 会先按 dev/prod 模式构建 `auth-core` 和 Admin，再由 Worker assets 发布。验证时至少区分 API health、SPA HTML 和实际 JS assets。

本次退款撤销依赖 `billing_transaction.business_status_before_refund`。该列是 nullable 向后兼容扩展，必须先应用 PostgreSQL `0007_billing_refund_status`，再部署读取该列的新 Worker；旧 Worker 可忽略该列，代码回滚时保留列。dev/prod 共用 PostgreSQL Schema，迁移会同时影响两套 Worker 所连接的数据结构，不能把 dev 部署与 Schema 迁移当作互相隔离的动作。共享 Schema 已于 2026-08-19 应用 `0007` 并完成幂等复核，同日完成 dev Worker 与 Admin assets 部署。本次发布以 version `ce9ee177-27a0-49fe-8e87-0a0f4414b620` 完成验收检查点：health 与 Admin HTML 返回 `200`，HTML 引用的 10 个 JS/CSS 资源全部返回 `200`，未授权订单 API 返回 `401`；实时流量版本以 Cloudflare deployment 回读为准。

仓库内证据：

- `apps/admin-web/test/billing-admin-intent.test.mjs`：订单/通知页面意图、空值和交互边界。
- `apps/workers-api/src/admin/billing-routes.integration.test.ts`：组合筛选、导出、通知失败记录和 payload 安全。
- `apps/workers-api/src/admin/routes.test.ts`：既有 Admin 路由与权限。
- `apps/workers-api/src/admin/cors-preflight.test.ts`：跨域预检边界。

外部仍需验收：有真实订单时的查询目标、10,000 行导出、Sandbox 通知/退款/恢复、目标环境 Secret、实际 Admin 会话和发布资源。历史 dev 部署记录不自动证明当前环境仍一致。

## 9. 待确认与禁止扩展

- 当前 PRD 未要求 Admin 人工调整 Premium，因此不得新增 grant/lifecycle 修改按钮。
- Card Override 和通用 App Config 是否补 UI 需独立产品需求；现有 API 不等于页面已交付。Trending Pin 已明确废弃，不应再补 UI 或调用旧接口。
- 生产订单保留期、审计访问范围和运营角色细分若需变化，应先补产品/安全决策和迁移设计。
- 未重新连接远程环境时，不得把旧的 dev 空订单样本、部署 ID 或 HTTP 200 写成当前实时结论。
