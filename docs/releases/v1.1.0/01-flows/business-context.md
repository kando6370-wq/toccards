# v1.1.0 业务上下文

## 0. 文档说明

- 分析范围：全项目业务主线，重点记录 v1.1 相对 v1.0 的订阅、额度、Performance 和 Admin 增量。
- 分析基线：`dev@cea5d4e`，2026-08-14。
- 范围边界：当前检出代码、Schema/迁移、运行配置和测试；不把远程环境历史证据外推为当前实时状态。
- 上一版本未变化流程继续参考 [v1.0.0 业务流程](../../v1.0.0/01-flows/flows.md)。

结论等级：

- **代码明确体现**：存在路由、校验、Schema、配置或测试直接证据。
- **根据代码推断**：多个实现线索一致，但没有显式产品说明。
- **待确认**：当前代码与 PRD 不足以冻结业务口径。

## 1. 业务总览与主线

### 1.1 系统定位

Card AI 面向交易卡牌用户提供目录搜索、图片识别、Wishlist/Collection、Folder 管理、估值和 Performance。iOS 用户可通过 Apple 购买 Premium，获得无限扫描、更多 Folder、Performance 和扩展价格历史；内部运营人员通过 Admin 查看安装、用户、反馈、扫描、订单和 Apple 通知，并维护版本与权限。

### 1.2 完整业务闭环

```text
首次启动 -> 游客/账号身份 -> 搜索或扫描卡牌 -> Review/确认
       -> Wishlist 或 Collection -> 估值/Performance -> 编辑、移动或删除

受限功能 -> Subscription -> StoreKit verified Purchase/Restore
         -> 本机即时 Premium -> 服务端 session grant
         -> Apple 通知/Server API 维护购买链生命周期

业务记录 -> Admin 查询、排障、反馈处理与版本运营
```

正常闭环以“可信身份下创建/维护资产并获得可解释估值”为主。Premium 是同一闭环中的能力门槛，不是 UID 资产；Apple purchase chain 与当前 session proof 决定服务端受限操作。

### 1.3 模块地图

| 模块 | 业务职责 | 用户入口 | 关键证据 | 置信度 |
|---|---|---|---|---|
| 身份与账号 | 游客、邮箱/OAuth、会话、资产迁移和删除 | App 启动、Account | `src/auth/anonymous.ts`、`account-flow.ts` | 代码明确体现 |
| 卡牌发现 | 游戏、系列、卡牌、价格和趋势 | Home、Search、Card Detail | `src/data-source/routes.ts` | 代码明确体现 |
| 扫描 | 相机/相册识别、候选 Review、确认入库 | Scan | `src/scan/routes.ts`、`scan_page.dart` | 代码明确体现 |
| Portfolio | Folder、Collection、Wishlist、估值与历史 | Collection、Card Detail | `src/portfolio/routes.ts` | 代码明确体现 |
| Subscription | 商品、Purchase、Restore、本机三态 | Subscription/Paywall | `subscription_controller.dart`、`subscription-core` | 代码明确体现 |
| Apple 生命周期 | 购买链、session grant、通知、校正 | 无直接用户页面 | `src/entitlements/`、迁移 `0025-0029` | 代码明确体现 |
| Performance | Home/单 Item 的自然时间范围表现 | Home、Card Detail | `src/portfolio/performance.ts` | 代码明确体现 |
| Admin | 查询、排障、权限和版本运营 | React Admin | `apps/admin-web/src/App.tsx`、`src/admin/routes.ts` | 代码明确体现 |
| Marketing | 产品、法律、搜索发现 | `tcgcard.fun` | `apps/marketing-web/` | 代码明确体现 |

## 2. 用户角色与权限体系

### 2.1 角色清单

| 角色/身份 | 业务含义 | 主要能力 | 证据 | 置信度 |
|---|---|---|---|---|
| 游客 | 设备建立的匿名业务所有者 | 搜索、扫描、收藏、Wishlist、偏好；可升级账号 | `auth/anonymous.ts`、`owner-auth.ts` | 代码明确体现 |
| 正式用户 | 邮箱、Google 或 Apple 登录的业务所有者 | 游客能力 + 账号/跨设备资产同步 | `auth/register.ts`、`oauth.ts`、`account.ts` | 代码明确体现 |
| 当前 Apple 购买上下文 | 当前设备 StoreKit 证据与当前服务端 session proof | 本机 Premium；有 live grant 时调用服务端 Premium 功能 | `subscription_entitlement_cache.dart`、`premium-access.ts` | 代码明确体现 |
| `operator` | 日常运营管理员 | 查看和更新一般运营数据 | `admin/routes.ts` | 代码明确体现 |
| `super_admin` | 高权限管理员 | operator 能力 + 禁用用户、管理管理员、删除特定运营配置 | `admin/routes.ts` 显式角色判断 | 代码明确体现 |
| Apple | 购买与订阅生命周期的外部权威源 | StoreKit 交易、Notifications V2、Server API | `entitlements/` | 代码明确体现 |

### 2.2 页面与操作权限

| 身份 | 可见/可用能力 | 受限能力 | 权限判断 |
|---|---|---|---|
| 游客/正式用户 | Home、Search、Scan、Collection、Card Detail、Profile | Premium 功能需可信权益 | Flutter Router + Workers 当前 owner/session |
| 本机 `unknown` | 可用非 Premium 能力 | 受限动作先刷新，不能直接按 Free 拒绝 | `subscription_controller.dart` |
| 本机 Premium、无 session grant | 本机 Premium UI | 服务端受限动作返回 `ENTITLEMENT_SYNC_REQUIRED` | `premium-access.ts`、集成测试 |
| 明确 Free | 非 Premium 能力与剩余额度 | Premium 动作返回 `PREMIUM_REQUIRED` | Folder/Performance/历史路由 |
| operator/super_admin | 当前 Admin 菜单相同 | 最终写操作由 Workers 再校验 | `App.tsx` + `admin/routes.ts` |

### 2.3 数据隔离

- App 业务资产按服务端解析的 `owner_type + owner_id` 过滤，不能信任客户端自报所有者。
- Access Token 同时携带可信 `session_id`；Premium 服务端授权读取该 session 的 active grant，而不是只按 UID 查询。
- Sandbox 与 Production 通过 purchase chain 的 `environment` 隔离。
- Admin 使用独立 `admin_user` 和 Admin Token，不复用 App session。
- R2 扫描图片读取需要有效 Admin 身份，响应使用私有缓存策略。

证据：`apps/workers-api/src/owner-auth.ts`、`src/entitlements/premium-access.ts`、`src/admin/routes.ts`。

## 3. 核心业务流程

### 3.1 启动与身份建立

1. App 读取本地会话、环境配置和已验证 Premium 缓存。
2. 无有效身份时调用 `POST /api/v1/auth/anonymous` 建立匿名账号和 session。
3. 用户可通过邮箱、Google 或 Apple 登录；Access Token 过期时使用同一 session 的 Refresh Token 换新。
4. 游客注册或绑定后，服务端把 Folder、Collection、Wishlist、偏好和扫描记录迁移到正式 UID。
5. 登出撤销 session；删除账号按正式/匿名类型清理或失效业务数据。

异常：刷新失败后客户端清理无效会话；验证码错误/过期、重复邮箱和禁用账号由服务端拒绝。证据：`auth/`、`auth_session_interceptor.dart`。

### 3.2 搜索、Wishlist 与 Collection

1. 用户按游戏搜索 Card 或 Set，并进入卡牌详情。
2. 详情加载图片、市场价、价格历史和 TCGplayer 商品外链；已成交记录继续通过独立入口查询。
3. 用户可加入 Wishlist，或选择 Folder、数量、Raw/评级、品相、评级机构/分数、语言、工艺和购买价后收藏。
4. 收藏写入同步产生 `collection_item_event`；同卡 Wishlist 被移除。
5. 后续编辑、数量变化、Folder Move 或删除继续写事件，用于历史估值和 Performance。

关键约束：数量至少为 1；同所有者、Folder、卡牌、finish、language 组合唯一；目标 Folder 必须属于当前所有者。证据：`src/db/schema.ts`、`portfolio/routes.ts`、`portfolio/collect.test.ts`。

### 3.3 扫描与服务端额度

1. App 拍照或选图，使用 RTMDet-Ins 检测卡牌 mask、拟合四边形并矫正为 `745×1043`，再使用 PE-Core-T16 生成 512 维向量；iOS 使用原生 Core ML，Android 使用仅包含两个模型所需算子和类型的 ONNX Runtime 1.23.0 minimal AAR，提交矫正图片、向量、`request_id` 和同值 `Idempotency-Key`。
2. Workers 先按当前 session grant 判断 Premium；Free 请求以一条条件 INSERT 原子预占额度。
3. 矫正图片写入 R2；主 Worker 通过 `VECTOR_RECOGNITION` Service Binding 调用 `recognize-vec`，向量检索返回成功候选、无匹配或失败。
4. 技术失败释放预占；成功识别消费额度并返回最新 Quota。
5. 用户在 Review 选择结果，调用 `/scan/:scan_id/confirm` 创建收藏记录。

检测、预处理、双端运行时、向量协议、制品体积及验证边界详见[扫描识别流程](scan-recognition.md)。

Quota 状态：

```text
reserved -> consumed
reserved -> released
```

- Free 终身上限为 10；`remaining = max(0, 10 - reserved - consumed)`。
- 同一 request 重试返回已有结果；60 秒 processing lease 过期后允许接管。
- Premium 请求记录审计但不消耗 Free 额度。
- App Queue 的 Processing、Waiting、Done 是客户端展示状态；删除 Processing 不取消已发出的服务端结算，但后台结果不会把已删 Item 插回 UI。

证据：`src/scan/quota.ts`、`routes.ts`、`quota.integration.test.ts`、`scan_page_test.dart`。

### 3.4 Premium Purchase、Restore 与生命周期

#### Fresh Purchase

1. App 从 StoreKit 加载已配置商品并展示本地化价格。
2. Purchase 成功必须是 StoreKit verified transaction；客户端立即写入已验证缓存并解锁本机 Premium。
3. App 仅在 signed transaction 的 `transactionReason=PURCHASE` 时使用一次性 challenge 调用 `/entitlements/apple/verify`；`RENEWAL` 不进入 Fresh Purchase 队列。
4. Workers 验证 Bundle、环境、Product ID、nonce/证据、幂等和交易新旧，写 purchase chain、transaction 与当前 session grant。

#### Restore

1. App 执行 StoreKit Restore/current entitlements。
2. 有有效本机 entitlement 时立即恢复本机 Premium。
3. 服务端 Restore 还要求 App Attest challenge/assertion 和 Apple 证据，为当前 session 建立 grant。
4. Restore Not Found、Cancelled、Pending 或 Failed 不执行来源动作恢复。
5. Performance 遇到 `ENTITLEMENT_SYNC_REQUIRED` 时，可用已读取的 current entitlement 静默执行一次相同的 App Attest proof；成功后仅重试原请求一次，失败后等待用户显式刷新。

#### 生命周期

```text
TRIAL/ACTIVE/GRACE_PERIOD/LIFETIME -> 服务端 Premium 可用
BILLING_RETRY/EXPIRED             -> grant expired
REFUND/REVOKE                     -> grant revoked
```

Notifications V2 先进入 inbox，再验签、解析和按 `(signedDate, notificationUUID)` 归约。不可比较或 `REFUND_REVERSED` 进入 Server API 校正；5 分钟 cron 重试失败 inbox 和校正任务。

证据：`subscription_controller.dart`、`entitlements/routes.ts`、`restore-routes.ts`、`apple-notification-routes.ts`、[Premium 权益契约](../03-data-api/entitlement-contract.md)。

### 3.5 Folder 与 Performance

- Free 所有者最多有 2 个 Folder（包含默认 Folder）；条件 INSERT 在服务端防止多设备并发越限。
- 当前 session 有 active grant 时可超过上限；同 UID 的另一 session 不自动继承。
- Home Performance 可按 Folder 聚合；Card Detail Performance 必须有明确 `collection_item_id`，同卡多 Item 时不猜测聚合。
- Home Premium Performance 的 Top Performers 只读取当前 Folder 的当前持仓快照；每条 Collection Item 独立排序，Range 切换不改变榜单，金额隐藏不隐藏 Return。该模块不扩展到 Home Overview 或 Card Detail 页面。
- Range 为 `1D/7D/15D/1M/3M/1Y`，默认 1M；历史从可靠起点开始，数据不足返回 `partial_history=true`，不补虚假点。
- 1Y 价格历史只接受当前 live session grant；普通公开历史接口仍限制到 90 天。

证据：`portfolio/routes.ts`、`performance.ts`、`folder-premium.integration.test.ts`、`performance-premium.integration.test.ts`。

### 3.6 Admin 订单与 Apple 通知

1. Fresh Purchase/Restore 的 Apple 签名交易可先写入交易暂存证据并维护当前 session 权益；它们不直接成为 Admin 订单。
2. 已验签、已解码的 Notifications V2 建单事件按 `environment + transactionId` 新建或晋升暂存记录，并写入来源通知 UUID；Admin 订单页只查询这些通知确认记录。
3. Admin 订单页按 UID、订单、国家、SKU、状态、时间、续订、环境和扣款次数组合查询；扣款序号只在通知确认记录之间计算。
4. 订单导出复用同一筛选，最多 10,000 行 XLSX。
5. 通知页查询 inbox/结构化通知；只有打开详情时返回 decoded payload，不返回 signed JWS。
6. 失败记录保留 processing status 和错误，供排障；Admin 不能人工改 Premium。

证据：`admin/routes.ts`、`admin/xlsx.ts`、`billing-routes.integration.test.ts`、[Admin 实现文档](../04-admin/admin.md)。

### 3.7 反馈与版本运营

- 用户提交反馈后初始保存为 `open`；Admin 展示归并为 `pending`，可更新为 `processed` 或 `ignored`。
- Admin 管理 iOS/Google 最低版本、最新版本、强制升级和商店 URL；App 通过公共 `/app-config` 获取。
- Workers 另有 Card Override 和通用 App Config API，但当前 Admin 菜单没有对应页面，不能描述为 UI 已提供。旧 Trending Pin API 与 `trending_pin` 表已废弃；Trending Today 继续由 `card_trending_snapshot` 提供。

## 4. 状态与核心数据实体

### 4.1 状态模型

| 对象 | 主要状态/生命周期 | 证据 |
|---|---|---|
| 用户 | `active -> disabled/deleted`；anonymous 可升级为 user | `schema.ts`、`auth/account.ts` |
| Session | issued -> refreshed -> revoked/expired | `auth/session.ts` |
| 本机 Premium | `unknown/free/premium` | `subscription_entitlement_cache.dart` |
| Purchase chain | `TRIAL/ACTIVE/GRACE_PERIOD/LIFETIME/BILLING_RETRY/EXPIRED/REVOKED` | `apple-notification-routes.ts` |
| Session grant | `active/expired/revoked` | migration `0026`、`premium-access.ts` |
| Notification inbox | pending/processing/processed 与各类失败/校正状态 | migration `0029` |
| Scan | processing -> success/no_match/failed；pending -> confirmed | `scan/routes.ts` |
| Scan Quota request | reserved -> consumed/released | `scan/quota.ts` |
| Collection Item | 创建 -> 编辑/移动/增减 -> 删除；事件为 upsert/delete | `portfolio/routes.ts` |
| Feedback | open/pending -> processed/ignored（含旧值归并） | `feedback/routes.ts`、`admin/routes.ts` |
| Admin | active/disabled；operator/super_admin | `admin/routes.ts` |

### 4.2 实体与关系

| 实体组 | 核心表 | 关系与生命周期 |
|---|---|---|
| 目录与价格 | `cards_all`、`games`、`sets`、`price_source`、`price_series`、`price_ingest_batch`、`price_current_snapshot`、`current_price_pointer`、`price_history_month`、`card_trending_snapshot` | Card 以 `product_id/card_ref` 关联已发布的当前价、历史和 Trending 快照；旧 `tcg_price` 不参与运行时查询 |
| 身份 | `user`、`anonymous_account`、`account_uid`、`auth_identity`、`session` | owner 通过 session 访问资产；OAuth identity 归属 user |
| 资产 | `portfolio_folder`、`collection_item`、`collection_item_event`、`wishlist_item` | Folder 一对多 Item；Event 保留 Item 历史 |
| 扫描 | `scan_record`、`scan_quota_request` | request 幂等预占/结算；scan 记录识别与确认 |
| 购买 | `billing_product`、`billing_purchase_chain`、`billing_transaction` | Product 映射 entitlement；chain 一对多 transaction |
| 授权 | `billing_session_entitlement_grant` | session + chain + entitlement 唯一，授权不按 UID 继承 |
| Apple 证据 | challenge、verification attempt、App Attest challenge/key | 一次性挑战、重放审计和设备证明 |
| 通知 | `apple_notification_inbox`、`apple_server_notification` | 原始请求与结构化通知一对零/一，失败仍保留 inbox |
| Admin/运营 | `admin_user`、`app_config`、`feedback_ticket`、`card_override` | 独立管理员身份与运营记录 |

当前运行字段、约束和索引以 `apps/workers-api/src/db/postgres/migrations/` 内的顺序 migration 为准；后续 schema 变更只允许新增 PostgreSQL 向前迁移。

## 5. 业务规则与计算公式

| 场景 | 规则/公式 | 边界 | 证据 |
|---|---|---|---|
| Free Scan | `remaining = max(0, 10 - reserved - consumed)` | Premium 不扣 Free；技术失败释放 | `scan/quota.ts` |
| Free Folder | `folder_count < 2` 时允许新建 | 2 个包含默认 Folder；条件 INSERT 防并发 | `portfolio/routes.ts: INSERT_FOLDER_SQL` |
| 收藏估值 | `item_value = matched_market_price * quantity` | 无匹配价不伪造；输出按金额规则舍入 | `portfolio/collection-dashboard.ts` |
| Performance 日变化 | `portfolio_change = market_value_change - market_change` | 首点使用范围外相邻可靠日；无前态为 null | `portfolio/performance.ts: calculatePerformance()` |
| Quantity 变化 | `quantity_change = current_quantity - previous_quantity` | 与市场变化分开展示 | `performance.ts` |
| USD 订单金额 | `amount_usd_micros = round(amount_micros / rate)` | USD rate=1；正数 micros half-away-from-zero | `entitlements/billing-currency.ts` |
| 扣款次数 | Trial 为 0；每个非 Trial 有效收费事实按购买链时序累计 | 退款保留原订单事实，不伪造新收费 | `billing-order-facts.ts` |
| 时间 | 服务端存储和 Admin 展示以 UTC/UTC+0 为主 | 客户端展示另按页面契约 | `schema.ts`、`App.tsx` |

所有者、额度、grant、通知和订单写入必须由服务端幂等/条件写保护；客户端重试不得重复扣额度、建单或授予权益。

## 6. 影响面与上下游依赖

| 系统/能力 | 上下游 | 交互 | 失败影响 |
|---|---|---|---|
| StoreKit/App Store | 上游 | 商品、交易、current entitlement | 商品不可售、购买/Restore 无法完成 |
| Apple Notifications/Server API | 上游校正 | JWS、通知、当前交易历史 | 生命周期延迟；inbox/校正任务应保留并重试 |
| `recognize-vec` Worker | 内部 Service Binding | 512 维卡牌向量检索 | Scan 失败并释放 Free 预占 |
| PlanetScale PostgreSQL / Hyperdrive | 核心真源与连接边界 | 参数化 PostgreSQL SQL | 账号、资产、额度、订阅和 Admin 不可用 |
| KV | 缓存 | 目录/汇率快照 | 可回源或显式失败，不能改变授权真值 |
| R2 | 对象存储 | 扫描矫正卡面 | 写入失败时识别失败；Admin 图片可能不可查看 |
| 邮件/OAuth | 身份上游 | 验证码和第三方登录 | 注册、找回或 OAuth 登录受阻 |
| Analytics/Attribution | 下游 | Firebase/Mixpanel/Singular | 统计缺失，不应阻断授权或购买 |
| Admin | 下游运营 | 查询、排障、配置 | 不影响 Apple 最终真值；不能人工改 Premium |

## 7. 行业术语

| 术语 | 含义 | 业务上下文 |
|---|---|---|
| UID | App 业务账号标识 | 资产和运营关联，不是 Premium owner |
| originalTransactionId | Apple 购买链标识 | 与 environment 共同唯一标识 purchase chain |
| transactionId / order ID | 单笔 Apple 交易标识 | 订单幂等、金额和扣款次数 |
| Entitlement | Apple 当前有效购买资格 | 本机 StoreKit 与服务端 lifecycle 是两个获取通道 |
| Session grant | 当前 App session 的服务端 Premium 授权 | 服务端受限 API 的可信依据 |
| Grace Period | 续费失败后的宽限期 | 服务端 Premium 仍有效 |
| Billing Retry | Apple 继续重试扣款的状态 | 当前实现将服务端 grant 置为 expired |
| Lifetime | 一次性非消耗型终身商品 | purchase chain 状态 `LIFETIME` |
| Scan Quota | Free 扫描额度账本 | reserved/consumed/released 防并发重复 |
| Partial History | 目标 Range 早于可靠历史起点 | 返回真实片段，不补造历史 |
| Inbox | Apple 通知原始接收层 | 即使验签/解析失败也保留排障事实 |

## 8. 证据索引

| 编号 | 文件/符号 | 说明 |
|---|---|---|
| E1 | `apps/workers-api/src/index.ts` | API 路由与定时补偿入口 |
| E2 | `apps/workers-api/src/db/schema.ts` | 当前实体、约束和索引 |
| E3 | `apps/workers-api/src/owner-auth.ts` | owner 与 session 信任边界 |
| E4 | `apps/workers-api/src/scan/quota.ts` | Free Scan 原子额度规则 |
| E5 | `apps/workers-api/src/portfolio/routes.ts` | Folder/资产/Performance 路由与授权 |
| E6 | `apps/workers-api/src/portfolio/performance.ts` | Range、Partial History 与公式 |
| E7 | `apps/workers-api/src/entitlements/` | Apple 购买、Restore、通知和校正 |
| E8 | `apps/admin-web/src/App.tsx`、`src/admin/routes.ts` | Admin 页面和后端权限 |
| E9 | `apps/flutter-app/lib/features/subscription/` | 本机三态、Purchase/Restore 与来源动作 |
| E10 | `apps/workers-api/src/**/*integration.test.ts`、Flutter tests | 业务意图与并发/幂等证据 |

## 9. 待确认问题

| 问题 | 影响 | 当前处理 |
|---|---|---|
| Lifetime 已验证本地缓存最长离线时间是多少？ | 冷启动/离线 Premium 体验 | 产品待决，不擅自设时限 |
| Android 是否在 v1.1 销售 Premium？ | 商品、授权和跨端验收 | 当前只激活 Apple/iOS；保留抽象但不误售 |
| 独立价格上游导入、目标规模压测和冷数据方案何时验收？ | 价格 API 实数可用性与容量 | PlanetScale PostgreSQL/Hyperdrive 和 7 表结构已实施；迁移检查点七表为空，旧 `tcg_price` 被明确排除，需独立上游契约、R2 冷层和目标规模压测 |
| 后续 dev/prod 的迁移、Secret 和部署是否仍与 2026-08-17 记录一致？ | 发布判断 | 本次已重连核验 dev/prod deployment；Secret 仅核实配置项存在。远程状态会变化，后续发布前必须重新查询 |
| Apple 生产 SKU、Root CA、Server API 与 Sandbox/TestFlight 是否完成？ | 购买/通知发布验收 | 本次未验证，不宣称完成 |
| 重度 Portfolio、真实订单与多设备并发是否达标？ | Performance/Admin/Quota SLA | 自动化只证明仓库内逻辑，仍需目标规模验收 |
