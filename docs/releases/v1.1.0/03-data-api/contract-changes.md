# v1.1.0 契约变化

## 订阅与内购数据骨架

这些表的当前 PostgreSQL 结构位于 `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql`，dev 数据已完成迁移：

| 表 | 当前用途 |
|---|---|
| `billing_product` | 保存商店商品、计划与权益的映射。 |
| `billing_purchase_chain` | 保存按商店、环境和原始交易 ID 唯一的购买链当前状态。 |
| `billing_transaction` | 追加保存交易记录，账单金额使用整数 micros。 |
| `billing_entitlement_grant` | 保存购买链与 owner 的权益关联。 |
| `apple_server_notification` | 保存 Apple 通知载荷及处理状态。 |
| `billing_session_entitlement_grant` | 保存当前 live session 通过 Apple proof 获得的服务端授权。 |
| `billing_apple_purchase_challenge` | 保存 Fresh Purchase 的一次性 `appAccountToken` challenge。 |
| `billing_apple_verification_attempt` | 保存验证请求幂等结果、证据摘要和安全审计结果。 |
| `billing_apple_app_attest_challenge` | 保存绑定 session、request、key 与 Restore JWS 摘要的一次性 App Attest challenge。 |
| `billing_apple_app_attest_key` | 保存 Apple 验证后的安装级公钥、receipt、环境和递增 assertion counter。 |
| `apple_notification_inbox` | 在验签前保存完整 Apple 请求和 `signedPayload`，承载处理租约、失败终态与重试。 |

`billing_purchase_chain` 在 `0027` 增加 `state_effective_at`，防止较旧的客户端同步覆盖较新的 Apple 生命周期状态。

## Apple Fresh Purchase API

| API | 当前行为 |
|---|---|
| `GET /api/v1/entitlements/apple/lifecycle` | 只返回当前 live session 已证明、当前 App Store 环境的购买链状态，供 App 对本机 verified entitlements 做否决性校正；不能凭服务端 active 状态单独授权。 |
| `POST /api/v1/entitlements/apple/purchase-challenge` | 为当前 live session 和已配置 Product ID 签发 10 分钟一次性 UUID。 |
| `POST /api/v1/entitlements/apple/verify` | 仅接受 StoreKit 2 signed transaction；校验官方签名、环境、Bundle、SKU、有效期、撤销、Fresh Purchase 与 challenge 后写入当前 session grant。 |

验证接口要求 `Idempotency-Key` 与 body `request_id` 为同一 UUID。正式 Product ID、Bundle ID、Production App Apple ID 或 Apple Root CA 未配置时返回 `VERIFICATION_UNAVAILABLE`，不得创建 grant。

同一 session/request/evidence 处于有效处理租约时返回可重试的 `503 VERIFICATION_UNAVAILABLE`；证据摘要不一致、购买链已有更晚 lifecycle 等不可恢复冲突返回终态 `409 STATE_CONFLICT`。客户端补偿队列保留前者并移除后者。

## Apple Restore proof API

| API | 当前行为 |
|---|---|
| `POST /api/v1/entitlements/apple/app-attest/challenge` | 为 key 注册或 Restore 签发 10 分钟一次性 canonical client data；Restore 绑定 JWS SHA-256。 |
| `POST /api/v1/entitlements/apple/app-attest/register` | 验证 Apple App Attest 证书链、nonce、App ID、AAGUID 与 key ID，保存安装级公钥。 |
| `POST /api/v1/entitlements/apple/restore` | 验证 assertion、递增 counter、challenge 绑定及 Apple current entitlement JWS，只为当前 live session 写 `source=restore` grant。 |

Admin 已提供符合 v1.1 PRD 的订单查询、动态筛选选项、XLSX 导出和 Apple 通知 inbox 排障视图；Flutter 已提供订阅页面、购买入口和 StoreKit 抽象层。

Flutter 商品目录允许部分成功：只为非空配置 SKU 请求 StoreKit，未返回商品展示 `Unavailable` 且不可选择/购买，不使用固定美元价格伪造正式售价；默认 Yearly 不可用时按页面顺序选择第一个可用商品。购买点击时若所选商品尚未加载，会在同一次操作的 15 秒 Deadline 内重载；进入 Apple Purchase 流程后不以 15 秒强制终止。Pending 会保留页面、禁止重复购买及 Restore，但允许 Close；页面关闭后的迟到 verified Transaction Update 只更新当前 Premium，不恢复旧 Subscription Success 或 `blocked_action`。

Apple Revenue 只消费 `status=purchased`、本机验证后已激活且 StoreKit 完成无失败的事件；Restore、Pending、Cancelled、Failed、Unverified 均不进入收入队列。金额和币种读取已验证 StoreKit 2 JWS 的 Apple `price`（毫单位）与 `currency`，同时要求 JWS 与 PurchaseDetails 的 transaction/product ID 一致，不使用 Prototype 价格或商品目录价猜测交易金额。Firebase 使用标准 `purchase` 事件并携带 `transaction_id`、`product_id`、`plan_type`、`value`、`currency`、`quantity=1` 和 subscription 标识；本地持久化已上报 transaction ID 与待重试记录，上报失败不覆盖 Premium 或购买成功。

App 本机 Premium 使用 `Unknown/Free/Premium` 三态，不把尚未读取、读取超时或读取失败降级为 Free。启动读取已验证缓存后，通过 Apple verified `Transaction.currentEntitlements` 静默刷新并读取当前 session 已证明购买链的服务端 lifecycle 校正，不调用 `AppStore.sync()`；只有用户主动 Restore 才调用 `AppStore.sync()`。明确且不旧于 JWS 的失效校正只剔除匹配链，再用剩余全部 Apple entitlement 重算；服务端 active 不能单独授予，接口不可用不直接降级。自动续订缓存只有在 `expiresAt` 未过期时可临时授予本机 Premium，Lifetime 缓存可持续有效；过期缓存且刷新失败保持 Unknown。受限动作遇 Unknown 必须先刷新：刷新为 Premium 才执行，刷新为 Free 才显示 Functional Paywall，刷新仍失败则保持原页面且不发受限请求。该本机状态只用于 App 即时体验和向服务端表达同步需要，不能替代 session grant 授权。

Scan API 的 Quota 查询、识别提交和确认写入统一从请求发起时计算 15 秒总 Deadline，不再把 Dio 连接和响应阶段分别累计。Deadline 到达后客户端取消本次等待并返回 `REQUEST_TIMEOUT`；迟到成功响应不能更新当前操作。识别重试继续复用服务端 `request_id` / `Idempotency-Key`，因此客户端 Timeout 不改变服务端额度预占、最终结算和响应重放契约。

Portfolio API 的 Folder、Collection Item、Wishlist、Dashboard 与估值历史请求同样统一使用从调用发起计时的 15 秒总 Deadline；到期取消客户端等待并返回通用 Timeout 文案，迟到响应不能完成已经过期的保存或覆盖当前读取状态。Create Folder、Quick Collect、完整 Collection Item Create 与 Add Wishlist 均发送 UUID `Idempotency-Key`；Timeout 后按稳定 owner、创建入口及规范化名称、完整 Item 草稿或 card ref 复用该 Key，即使 access token 已刷新也不改变。服务端以 Key 作为新资源 ID，同 Key/相同语义返回原资源，同 Key/不同字段返回 `409`，非法 Key 返回 `422`。网络失败、客户端 Deadline、HTTP `408`/`5xx` 或成功响应 DTO 无法解析等无法确定服务端是否已提交的结果均保留原 Key；成功或 `401`、`403`、`409`、`422` 等明确终态响应后清除，后续主动创建才是新操作。Quick Collect 与完整 Create 使用不同操作域，不会互相重放。旧客户端不带 Key 时继续兼容。该客户端边界不拆分 Folder Move 与字段编辑的原子 `PATCH`。

## Collection Item 重复规则

Quick Collect、完整 Collection Item Create 与 Scan Confirm 使用相同重复身份：`owner_type + owner_id + folder_id + card_ref + finish + language + grader + condition + grade`。Raw Item 以 `grader=Raw + condition` 区分品相，评级卡以 `grader + grade` 区分评级机构和分数；因此 `Raw NM`/`Raw LP`、`PSA 9`/`PSA 10`、`PSA 10`/`BGS 10` 可以在同一 Folder 分别收藏。只有上述身份字段全部相同时返回 `409 DUPLICATE_COLLECTION_ITEM`；`quantity`、购买价、币种和备注不参与重复身份，不能用这些字段创建同一状态的第二条 Item。

PostgreSQL `0008_collection_item_grading_identity.sql` 用包含完整评级状态的唯一索引替换旧的 `card_ref + finish + language` 索引。现有数据受旧索引约束，天然满足新索引，无需回填。该迁移已于 2026-08-20 应用到 dev/prod 共用的 PostgreSQL Schema，因此两套 Worker 面向的数据库约束已经同时变更；执行与回滚边界见 [migration.md](migration.md)。

Card Data API 的 Home 推荐、Search、Set/Card Detail、市场价与 Price History 请求也使用同一 15 秒总 Deadline；到期取消当前客户端等待并返回 `REQUEST_TIMEOUT`。Search 和 Range Controller 继续以当前请求代次决定是否接纳响应，因此旧查询或旧 Range 的迟到结果不能覆盖用户后续选择。

Auth API 的每次 HTTP 请求已使用 15 秒 Deadline。启动时 `validateStoredSession` 从业务操作开始计时，`/auth/me → token refresh → /auth/me` 内部校验链的每一步只获得当前剩余预算，不会重新获得 15 秒。到期取消客户端等待并进入现有网络失败处理，不返回迟到 session；OAuth 继续沿用统一授权失败文案，不因 Deadline 引入新的用户可见错误类型。

Currency Rate API 的 `/rates` 请求使用 15 秒总 Deadline。并发货币切换继续共享同一个在途汇率请求；Timeout 后取消客户端等待、清除共享 Future，保持原货币与已有缓存不变，迟到汇率不会写入缓存，用户下一次主动操作可重新请求。

Apple entitlement 的 purchase challenge、Fresh Purchase JWS 同步、App Attest challenge/register、Restore proof verify 与 lifecycle 校正等 Workers HTTP 请求统一使用 15 秒 Deadline。HTTP Timeout 映射为可重试的 `REQUEST_TIMEOUT/408`，迟到响应不能被当作 grant 成功；补偿队列保留证据后续重试。该限制不作用于 Apple Purchase Sheet、`AppStore.sync()` 或 App Attest 原生计算阶段，也不以 proof HTTP 失败撤销本机 StoreKit verified 的即时 Premium。

根启动流程在 Onboarding 完成后执行一次最长 15 秒的静默 entitlement Refresh。首次启动使用 `source=onboarding`，后续完整冷启动使用 `source=cold_start`；明确 Free 展示完整 Subscription Page，Premium 或 Unknown 进入 Home。该门禁不监听前后台切换，也不在 App 使用过程中因状态变为 Free 自动展示 Subscription Page。启动静默失败不显示主动操作错误 Toast；用户主动点击 Premium 受限功能时仍使用带失败反馈的 Refresh。

Subscription Page 固定使用 `Choose Your Plan` 和四项 Premium Benefits；Subscription Success 固定使用 `You're Premium!`、`Your premium features are now unlocked.`、相同四项权益及 `Start Exploring`。Wishlist 不属于 Premium，Success 不提供额外的 `Manage subscription` 正常出口。

Home/Search/Collection/Profile 顶部入口仅在本机权益明确为 Free 时显示，Unknown/Premium 隐藏；四个入口均使用 `presentation=sheet` 打开 Subscription Bottom Sheet，并分别携带 `source=home/search/collection/profile` 与 `entry_source=top_subscription_entry`。Profile Banner 同样使用 Bottom Sheet，并携带 `source=profile&entry_source=profile_banner`；启动门禁使用 `onboarding/cold_start`，Scan Pro Card 使用 `scan`，两者仍打开完整 Subscription Page，Scan 顶部及二级页面不挂载入口。Bottom Sheet 的 Purchase/Restore Success 直接关闭并返回来源页，不进入 Subscription Success；完整页面的 Purchase Success 继续将来源及入口来源传入 Subscription Success，并通过 `push/pop` 保留来源页面实例。

## Admin 订单与通知契约

`0032_billing_order_facts.sql` 为 `billing_transaction` 增加 `business_status`、`charge_count` 和 `source_notification_uuid`。Fresh Purchase、Restore 与 Notifications V2 都可保存服务端验签通过的 Apple 交易证据并维护即时权益，但 Admin 订单真值只读取 `source_notification_uuid IS NOT NULL` 的通知确认记录；客户端路径写入的暂存交易不进入订单列表、动态筛选选项或 XLSX，也不参与扣款序号。建单类通知命中已有 `environment + transactionId` 时用通知解码字段晋升该记录。免费试用固定为 0；通知确认的成功付费按同一 `environment + originalTransactionId` 内的 `purchase_at + transactionId` 排序；重复通知不增加次数；退款不减序号、不重排。只有存在更早通知确认试用且尚无通知确认成功付费时才标记 `trial_conversion`，不从单独一条历史 `RENEWAL` 猜测试用转换。

`DID_CHANGE_RENEWAL_PREF + UPGRADE/DOWNGRADE` 只更新购买链的 `next_product_id`，不创建订单。`SUBSCRIBED + RESUBSCRIBE` 使用新的 `originalTransactionId` 时是该链首次付费，业务状态为 `initial_purchase`、扣款次数为 1；沿用已有 `originalTransactionId` 时视为同链续费，即使 Apple 交易原因为 `PURCHASE`，也按 `renewal` 计入下一次扣款。确定性重算保证同链只有第一笔实际付费保留 `initial_purchase`。

`0033_billing_exchange_rate_snapshot.sql` 为订单增加可审计的 USD 汇率快照。现有汇率服务口径为 `1 USD = rate × 原币种`，换算使用整数 micros 的除法与 half-away-from-zero 舍入；USD 使用 rate 1。快照固化 rate、base/quote、来源、生效/抓取时间、陈旧标记、换算版本和舍入模式。汇率不可用或币种不支持时订单照常入库，USD 及快照保持空，不以 0 或最新汇率猜测；已固化订单不随未来汇率变化重算。

`0034_billing_auto_renew_snapshot.sql` 为订单增加 nullable `auto_renew_snapshot`。Admin 展示、筛选和导出只读取订单事件快照，不读取 purchase chain 当前 `auto_renew`。Notifications V2 只有在当次已验签续订信息提供 `autoRenewStatus` 时写 `0/1`；Lifetime 固定写 `0`；Fresh Purchase、Restore 及历史订阅订单无法从交易 JWS 证明该值时保持 `NULL` 并显示 `--`，不以当前状态反向覆盖历史。

PostgreSQL `0007_billing_refund_status.sql` 为 `billing_transaction` 增加 nullable `business_status_before_refund`。`REFUND` 首次落地时保存退款前业务状态；重复退款保持原值。`REFUND_REVERSED` 只有在 Apple Server API 校正证明对应链路 active 后才恢复该状态并清空退款事实；历史已退款记录不猜测回填，退款前业务状态缺失时恢复为 `NULL`，不得继续标记为 `refunded` 或推断为其他订单类型。新 Worker 依赖该列，发布顺序必须为先迁移共享 PostgreSQL Schema、后部署 Worker；共享 Schema 已于 2026-08-19 应用 `0007` 并完成幂等复核，同日完成 dev Worker 与 Admin assets 部署。

Admin 订单列表对 nullable 订单状态、自动续期、原始金额、USD 金额与扣款次数统一显示 `--`；合法 `0` 仍显示金额或次数 0，`auto_renew=false` 显示“否”，不得把缺失值与零值混淆。Card Override 的图片上传按 `card_ref` 原子 UPSERT；并发首次上传只保留一条 override，已有行只更新图片 URL 与审计字段，必须保留原 `id`、`override_fields` 和 `is_missing_card`。

已验签的 Apple 建单类通知在尚无 App owner 关联时，仍可基于启用的 `billing_product` SKU 创建 purchase chain 与订单。该链以 `original_owner_type=unlinked`、空 `original_owner_id` 表达“Apple 事实已保存但 UID 未关联”；Admin 展示空 UID，UID 筛选和安装时间查询忽略空值。通知流程不会为 `unlinked` 链创建 session grant，未知或未启用 SKU 进入 `correction_required`，因此无 UID 订单记录不会成为 Premium 授权来源。之后只有 Fresh Purchase challenge 或 Restore App Attest 这类绑定 live session 的可信证明，才能把仍为 `unlinked` 的链补关联为当前 owner并创建当前 session grant；已关联 owner 不会被其他 session 改写。

Apple 通知先于客户端 Fresh Purchase proof 到达时，`POST /entitlements/apple/verify` 不把“交易已存在”单独视为重放。仅当已保存交易与 JWS 的 environment、transaction、original transaction、SKU、entitlement 一致，purchase chain 仍为 `unlinked` 或已属于同一 owner，chain 与交易均未撤销/退款且 Premium 生命周期仍有效，并且当前 session challenge 未消费且匹配 JWS `appAccountToken` 时，Worker 才原子消费 challenge、补关联 owner 并创建当前 session grant。该路径保留通知建立的订单、`source_notification_uuid`、扣款事实和较新的 lifecycle 状态，不重复建单；不同 owner、不同 challenge、过期、Billing Retry、Expired、Revoked 或 Refunded 仍返回 `409 REPLAY_REJECTED`。客户端本机已验证 Premium 后若受保护请求收到 `409 ENTITLEMENT_SYNC_REQUIRED`，先等待 Fresh Purchase 补偿队列并查询当前 session lifecycle；已有 active grant 即完成，否则继续 Restore proof。Home Overview 1Y 与 Performance 在此期间保持 loading、共享同一个同步任务并最多自动重试原请求一次，只有同步失败或重试仍失败时才展示现有顶部失败提示。

| API | 当前行为 |
|---|---|
| `GET /api/v1/admin/billing/transactions/options` | 只从通知确认订单动态返回国家代码与 SKU。 |
| `GET /api/v1/admin/billing/transactions` | 只返回通知确认订单，支持 PRD 组合筛选及 13 列订单事实；UID、订单 ID 精确匹配。 |
| `GET /api/v1/admin/billing/transactions/export` | 只导出当前筛选的全部通知确认订单；同步上限 10,000 行，超限显式失败。 |
| `GET /api/v1/admin/apple-notifications/options` | 从已验签结构化通知动态返回主/子通知类型。 |
| `GET /api/v1/admin/apple-notifications` | 以 `apple_notification_inbox` 为入口，包含验签、解析、校正和处理失败记录。 |
| `GET /api/v1/admin/apple-notifications/:detailId` | 仅返回基本信息、处理失败原因和 Decoded Payload；不返回原始 `signedPayload`。 |

UID 只用于关联查询与安装时间，不成为 Premium owner。安装时间取该 purchase chain 已关联 UID 的最早 `app_installation.first_seen_at`。XLSX 文本使用 inline string，避免以 `= + - @` 开头的外部值被 Excel 作为公式执行。

## Folder Premium 限制

`POST /api/v1/portfolio/folders` 当前契约：Free 用户最多拥有 2 个 Folder（包含默认 Folder）；有效当前 session grant 可突破该限制。同 owner 的创建先取得摘要锁，再在同一事务的 INSERT 中完成数量判断与 `MAX(sort_order) + 100` 计算；并发请求不能同时创建第 3 个 Folder，Premium 并发创建也不会得到重复排序值。客户端可发送 `X-Local-Premium-State: verified` 表示本机 StoreKit 已验证，但该头只会在无 grant 时触发 `409 ENTITLEMENT_SYNC_REQUIRED`，不能直接授权；明确 Free 超限返回 `403 PREMIUM_REQUIRED`。

Flutter Create Folder 在弹窗内等待服务端结果：保存中锁定输入、返回和重复提交；成功才关闭。普通失败保留名称并沿用通用错误反馈；`ENTITLEMENT_SYNC_REQUIRED` 保留名称并提示 Premium 正在同步；`PREMIUM_REQUIRED` 视为多设备下服务端最新限制，先刷新 Folder List，再进入 Functional Paywall，成功后用原名称重新打开 Create Folder，非成功不创建。

Collection Item 编辑与 Folder Move 继续使用单次 `PATCH /api/v1/portfolio/items/:item_id` 原子提交；Folder 变化和同次字段编辑不会拆成两个业务写请求。目标 Folder 已失效时服务端返回 `NOT_FOUND` 且不更新 Item；App 刷新 Folder/Item 真值，保持原 Source Folder，不展示半迁移结果。

## Scan Quota

| API | 当前行为 |
|---|---|
| `GET /api/v1/scan/quota` | 返回当前 owner 的终身 10 次 Free quota；有效当前 session grant 返回 `access=premium`、`unlimited=true`，本机 Premium 同步中返回 `ENTITLEMENT_SYNC_REQUIRED`。 |
| `POST /api/v1/scan/recognize` | 要求 body `request_id` 与 `Idempotency-Key` 为同一 UUID；在 R2/OCR 前原子预占。Matched/No Match 消耗，技术失败释放，Premium 不消耗 Free quota；成功及额度耗尽响应中的 quota 均包含 `access`、`unlimited`、`limit`、`reserved`、`consumed`、`remaining`，完成响应可用原 request ID 重放。 |

`scan_quota_request` 同时是额度账本和请求幂等真源。Free 的 `reserved + consumed` 最多 10；Free 预占按 owner 摘要锁串行，同 owner 多 session 并发不能预占同一最后额度。Premium 不取得 Free 配额锁，也不消耗 Free 次数。处理中租约为 60 秒，防止 Worker 中断永久占用；同一过期 lease 的并发接管只有一个请求获得处理权，released 请求不计入已用额度。Flutter 严格解析完整 quota，不再把缺失权益字段静默降级为 Free；Scan 以本机 Premium 或服务端 `unlimited=true` 的合并结果更新展示、额度拦截与请求同步保护，并在本机为 Free 时于页面生命周期内至少复核一次 StoreKit 权益。Quota Paywall 或 Scan Pro 返回 typed Purchase/Restore success 后，即使当前没有 Waiting Item，Scan 也会主动提交当前 StoreKit entitlement 并至少刷新一次服务端 Quota；收到 `ENTITLEMENT_SYNC_REQUIRED` 时复用同一个单任务同步周期，保留原图并在最多 15 秒的 Quota 确认窗口内等待。只有服务端确认 `unlimited=true` 后，Waiting 与权益同步中的 Item 才按 Queue 顺序自动递补；同步失败或超时保留同步状态，不改写为 No Match，也不消耗 Free 次数，后续扫描触发可重新开启同步周期。Processing 删除立即移除 UI，但保留原请求的后台观察；最终响应继续更新 Quota，缺少 Quota 时刷新服务端真值，且迟到结果不得重插卡片。

Functional Paywall 只在 typed Purchase/Restore success 后启动上述服务端权益同步；quota=0 且图片未入 Queue 时仍只返回 Scan，不自动打开相机或图库。Scan Pro Card 使用完整 Subscription Page：Purchase Success 经 Success Page 返回原 Scan 页面实例，Restore/外部解锁直接返回，因此当前 Queue 不会因重新创建路由而丢失。首次 quota 刷新延后到首帧，避免路由切换构建期修改 Riverpod provider。

## Performance 与 Extended Price History

| API | 当前行为 |
|---|---|
| `GET /api/v1/portfolio/performance?range=...&folder_id=...` | 仅当前 session grant 可访问；返回指定 Folder 的指标、曲线、Item 数、`purchase_price_item_count`、市场价与购买价完整性状态，以及当前时点的 `top_performer_count`、完整有序 `top_performer_item_ids` 和最多 5 条 `top_performers`。 |
| `GET /api/v1/portfolio/items/:item_id/performance?range=...` | 仅当前 session grant 可访问；先校验 Item 归属，再只计算该 Collection Item，不聚合同卡其他 Item。 |
| `GET /api/v1/portfolio/valuation-history?days=...&folder_id=...` | `folder_id` 可选；提供时先校验当前 owner 的 Folder 归属且只返回该 Folder，省略时保持返回全部 Folder。`days<=90` 保持 Free 可用；`days>90`、最多 365 天时强制当前 session grant。本机 verified 头不能授权，只能触发 `ENTITLEMENT_SYNC_REQUIRED`。 |
| `GET /api/v1/cards/:card_ref/market-prices` | 继续公开当前市场价与最多 90 天 history；路由层统一裁剪，不能借此绕过 1Y Premium。 |
| `GET /api/v1/cards/:card_ref/price-series?days=...` | `days<=90` 保持公开；`days>90` 时要求 live session 和当前 session grant。本机 verified 头只能触发同步等待，不能授权。 |
| `POST /api/v1/cards/:card_ref/price-series/batch` | 任一请求 `days>90` 时整批使用同一 live session grant 校验；Raw 与 Graded 1Y 均通过该受保护入口加载，不回退到公开单请求。 |

Performance 与普通历史图表统一使用 `1D/7D/15D/1M/3M/1Y`，默认 `1M`。Home 与 Card Detail Performance 整体为 Premium；Home Overview 与 Card Detail Price History 仅 1Y 为 Premium。Functional Paywall Purchase/Restore 成功会返回原图表并自动加载 1Y，未获得 Premium 时不改变原 Range 或已加载数据，Premium 变 Free且当前为 1Y 时回退 3M。

Home Overview 首次选择 1Y 时只请求当前 Folder；请求期间立即选中 1Y、保留已有曲线并显示加载状态，重复点击复用同一请求，切换 Range 或 Folder 后的迟到响应不得覆盖最新选择。365 天估值查询只返回范围开始前每个相关 Item 的最后基线事件及范围内事件，再按一次日期遍历聚合 Folder；SKU 匹配、价格历史解析和日期价格在单次请求内复用。该优化保持估值、Folder Move、Most Valuable、Premium 和错误语义不变，不新增 Schema 或 migration。

Home Performance 的 `current` 与 `series[]` 点位提供 nullable `market_value_change_usd`、`market_change_usd`、`portfolio_change_usd`、`quantity_change`。服务端按未提前舍入的历史价格和数量计算 `Daily Change = Market Value(t) - Market Value(t_prev)`、`Market Change = sum((MP(t) - MP(t_prev)) * Q(t_prev))`，再以 `Portfolio Change = Daily Change - Market Change` 分离持仓变动；响应末端统一保留两位小数。Range 首点若范围外存在紧邻可靠日，仍使用该日作为 `t_prev`；只有全历史没有可信前序节点时四项才返回 `null`，客户端不得伪造为 0。Home Tooltip 固定展示 Date、Market、Portfolio、Qty，`Daily Change` 只作为内部计算中间值和 `Daily Change = Market Change + Portfolio Change` 校验值，不在 Tooltip 展示；Market 或 Portfolio 为 `null` 时对应行展示 `--`，有值时按 App 当前币种换算并遵循金额隐藏状态。Partial Purchase Price 说明使用 Info Popover，且与 Chart Tooltip 互斥。该响应扩展不新增数据库迁移。

Home Performance 的 Folder 归属遵循 App PRD 的整体迁移规则：每个 Item 以最新 Event 的 Folder 作为全部可靠历史的当前归属，再按目标日期还原 Quantity、价格映射和删除状态。v1.1 Folder Move 成功后，Source Folder 立即移除该 Item 的当前及全部可靠历史，Target Folder 从 `performance_history_available_from` 起获得完整可靠历史；不会把 Move 前的可靠片段继续留在 Source。Card Detail Performance 不按 Folder 过滤，仍只计算目标 `collection_item_id`。

冻结原始 PRD 中“不新增其他 Performance 卡牌榜单”的约束指 Home Overview 保持 v1.0 原流程；`Top Performers` 只在新增的 Home Premium Performance 容器展示，不扩展到 Home Overview 或 Card Detail。当前 Folder 内每个 Collection Item 独立参与，排除 Purchase Price 或当前 Market Price 缺失项，按未提前舍入的当前 Profit/Loss、可计算的 Return、Market Value 依次降序，最后以 `item_id` 稳定排序；响应末端才格式化金额与百分比。Purchase Price 为 0 时保留该 Item，但 Return 返回 `null`；全部亏损时仍返回相对最高项。Home 最多展示前 5 项；`Top Performers` 标题和 `View all` 始终显示，当前 Folder 没有卡牌或没有可入榜 Item 时列表为空并显示 `Add purchase prices to see your top performers.`。`View all` 使用服务端返回的完整有序 `top_performer_item_ids` 打开当前 Folder，并让已入榜 Item 保持相同顺序，未入榜 Item 按最近加入时间排在其后。该列表与 Range 无关，切换币种只由客户端换算金额，Return 数值不变。`purchase_price_item_count` 按当前 Folder 中 Purchase Price 有效的 Collection Item 数统计，不按 Quantity 展开。本次为现有响应的向后兼容字段扩展，不新增 Schema 或 migration。

同一点位同时增加 nullable `market_value_change_usd` 与 `profit_loss_change_usd`，供 Card Detail Performance 使用。两项均由服务端以未提前舍入的目标 Item 历史值和 `t_prev` 计算，Range 首点沿用范围外紧邻可靠节点；不存在可信前态或成本不可计算时返回 `null`。正常状态曲线使用 Profit/Loss，Tooltip 仅展示 Date、Daily Change、Market Value、Profit/Loss、Qty；Purchase Price 缺失状态曲线使用 Market Value，Tooltip 不得展示 Profit/Loss、Purchase Cost 或 Return。1D 单点仍可点击，切 Range 或离开 Performance 会销毁旧 Tooltip 状态。

`0031_performance_history.sql` 增加购买价、币种、生效时间、历史可用起点和 Folder 加入时间等事件事实。该迁移已在隔离空库及远程 dev 只读导出的本地副本执行并验证，并于 2026-08-13 应用到远程 dev；尚未应用到开发者常用 local 或 prod。

Card Detail 普通价格历史 1Y 的服务端防绕过已关闭：Free 仍可读取 1D 至 3M；1Y 要求当前 live session 的有效服务端 grant，同 UID 的另一 session 不继承。本机 verified 只区分 `ENTITLEMENT_SYNC_REQUIRED`，不能作为授权。该变更不新增 schema 或迁移。

## PostgreSQL 查询切换

Workers 业务 API 的路径、请求/响应字段、鉴权、owner 隔离、幂等、Premium 和错误语义保持不变；底层查询使用 PostgreSQL 方言。部署运行时的 `fetch` 与 `scheduled` 入口必须存在 `HYPERDRIVE`，缺失时立即失败，不允许读取其他数据库 binding 或执行任务。测试可继续通过直接调用 `app.request` 注入进程内 `DB` 适配器，但这不是部署运行时的回退路径。

Flutter 启动时校验已保存会话：只有 `/auth/me` 或 `/auth/token/refresh` 明确返回 `UNAUTHORIZED` 才判定会话失效并进入匿名账号恢复流程。PostgreSQL、配置或服务端内部错误必须保持显式失败，不能转换为“无会话”，避免短暂后端故障导致客户端错误切换 owner。

PostgreSQL 结果适配器必须在类型转换前把 SQL `NULL` 原样映射为 JavaScript `null`。该规则同时适用于 nullable `bigint` 与 `numeric`：价格 baseline/change 缺失、Collection Item 尚未绑定 `price_series_id`、订单金额未知时均保持原有空值语义，不得转换为 `0`、`NaN` 或查询失败。非空 `bigint` 仍必须处于 JavaScript 安全整数范围，非空 `numeric` 仍必须是有限数值；非法值继续显式失败。该修复不新增 Schema、迁移、数据回填或数据库回退。

所有使用 `LIMIT/OFFSET` 的目录、Portfolio 与 Admin 列表必须在既有业务主排序后追加唯一稳定键，避免同名、同时间记录因 PostgreSQL 未定义同键顺序而跨页重复或漏项。Card Search 保持 `updated_at DESC`，但对 nullable `updated_at` 显式使用 `NULLS LAST`，再按 `product_id ASC`；Set Search 同名时按 `set_id ASC`；Collection/Wishlist 的可选主排序同键时按 Item ID 升序；Admin 分页按对应资源主键升序，用户联合列表先按 `account_type`、再按 `id`。该修复不改变过滤、DTO、主排序方向、页码协议或 Schema。

同一规则适用于非分页的最新记录、有限批次和用户可见有序列表：Admin 最近 Scan/Installation、匿名账号复用、最新注册/重置验证码、Portfolio Folder、Apple 通知重试与 Server API 校正批次都在原主排序后追加各自唯一 ID；Admin 订单关联的通知 type/subtype 使用完全相同的 `signed_at DESC NULLS LAST, received_at DESC, id ASC`，避免 PostgreSQL 把空 `signed_at` 视为最新，或在并列时把两个字段取自不同通知。订阅 lifecycle 的 nullable `state_effective_at DESC` 同样显式 `NULLS LAST`；Admin 订单导出与列表保持相同的稳定顺序。上述变化只确定原排序完全相等时的结果，不改变业务过滤、正常主顺序、DTO、API 或 Schema。

### PostgreSQL 并发写保护

PostgreSQL 追加 `0006_mutation_lock.sql`。`mutation_lock` 仅以主键 `lock_key` 保存串行化键，不保存业务结果；动态身份使用 SHA-256 摘要，不把 owner ID 或邮箱明文写入锁表。账号 UID 使用全局锁保护既有 `MAX(uid) + 1`；Free Scan 与 Folder 使用 owner 级锁；注册和重置验证码分别使用规范化邮箱 + purpose 锁；同设备匿名账号创建使用 device 摘要锁，保证只有一个 live owner 及其默认数据。Wishlist、Quick Collect、完整 Collection Item Create 与 Scan Confirm 对同一 owner/card 使用同一锁，Scan Confirm 另取 owner/scan 锁，防止同一扫描的不同候选各自提交。一次操作需要多把锁时先去重并按字典序获取，避免反向锁顺序。锁和受保护写入必须处于同一个 `DB.batch` 事务，后到事务在取得锁后再执行条件查询/写入；API、UID 格式、Free Scan=10、Free Folder=2、验证码 60 秒窗口及既有错误码均不变。

部署顺序必须先执行 expand migration `0006`，再部署依赖锁表的新 Worker。旧 Worker 会忽略新增表，可在 migration 后继续运行；新 Worker 在表不存在时显式失败，不允许先部署代码。PostgreSQL migration manifest 按完整有序名称校验 ledger；runner 在计算 checksum 与执行前统一把 CRLF 和孤立 CR 规范为 LF，因此同一 migration 不会因 Windows Text loader 换行差异与远程 LF ledger 产生伪冲突，规范化之外的 SQL 内容变化仍必须显式失败。2026-08-19 已按该顺序执行共享 PostgreSQL `0006` 并部署依赖锁表的 dev Worker；该 schema 变更对共用数据库的 dev/prod 同时生效，prod Worker 部署仍是独立发布动作。执行、复核和回滚边界见 [migration.md](migration.md)；本次 Git 交付不重复执行迁移、部署或数据写入。

旧 `tcg_price` 不参与运行时查询。Search、卡片详情、市场价、Price Series、Trending 和 Portfolio 估值统一读取 `price_source`、`price_series`、`price_ingest_batch`、`price_current_snapshot`、`current_price_pointer`、`price_history_month` 与 `card_trending_snapshot`。当前价只读取 `status=published` 且被 `current:%` pointer 指向的批次；月历史只读取同来源、同 scope 的 `published/superseded` lineage，并要求该来源和 scope 仍有已发布 current pointer。不同 scope 不能互相授权历史可见性；任何月块内容或 checksum 变化都必须记录新的 batch lineage，不能保留旧 `last_batch_id` 原地改写。PostgreSQL 的通用评级 `grader_code=GENERIC` 在 API 边界继续显示为既有 `Grade` 桶，Price Series 查询同时接受 `GENERIC` 与 `Grade`，避免数据库代码变化破坏收藏编辑和扫描确认的 PSA/BGS 共享等级估值。收藏编辑页打开已有 Item 时按该 Item 的 language 与 finish 重新加载市场价，后续切换语言或版本也只展示对应价格维度。七张新价格表为空时，市场价和 Trending 返回空集合，不回退旧价格结果或旧 KV Trending 缓存。Card Detail 的 Shop 从已发布 current snapshot 中只选择 `source_code=tcgplayer` 的 Raw 商品，按品相生成最多 4 条 TCGplayer 商品外链；`date` 与 `price` 表示当前商品价格快照，不得解释为已成交记录。其他价格来源不得混入 Shop，独立的 View Sold Listings 成交查询入口不受此映射影响。

公共数据接口必须区分 PostgreSQL 成功返回零行与查询失败：前者按既有契约返回正常空集合或 `404 NOT_FOUND`，后者返回非 2xx，使 Flutter 进入整页或局部失败态。Search、Sets、卡片详情、Market Prices、Price Series 与 Shop 不得捕获数据库异常后伪装为成功空数据或不存在。Flutter Trending Today 对成功空集合显示正常空态，仅在查询失败时显示失败重试；后续分页失败保留已加载卡片并提供局部重试。Flutter Search 的追加页失败同样保留已加载卡片和当前页码，停止滚动触发的自动重试，并通过列表底部操作重试同一下一页；成功后才推进页码和继续分页。缓存只可复用 PostgreSQL 切换后产生的有效响应，不得成为迁移前价格结果的回退通道。

价格变化窗口按页面语义固定：Trending Today 只消费 `change_1d_percent`，Search、Collection 和 Most Valuable 只消费 `change_30d_percent`，Card Detail Market Prices 只消费 `change_7d_percent`。Market Prices 响应通过 `previous_7d_price_usd` 直接返回 PostgreSQL `baseline_7d_amount_micros` 的美元值；Flutter 使用该字段计算 7D Change，不得从稀疏 Price Series 推导基准价。Workers 必须显式返回对应窗口字段，Flutter 不得把一个通用变化率跨页面复用；对应 baseline 不存在时保持 `null`，界面显示 `-/-`，不得伪装为 `0%`。

Home Most Valuable 与 Portfolio 总资产使用不同金额口径：`current_value_usd` 和历史 `series[].value_usd` 继续按单张市场价乘 `quantity` 汇总；`most_valuable[].price_usd` 与 `previous_30d_price_usd` 均为单张价格，`quantity` 不参与展示或排名。排名使用未提前舍入的当前单张价格降序；相同单价依次按已知 30D 涨幅降序、Collection Item 创建时间倒序、名称 A-Z 和稳定 `item_id` 排序。创建时间由该 Item 的首个事件 `effective_at` 表达，不把后续数量或属性编辑时间误当成加入时间。

`GET /api/v1/portfolio/valuation-history` 的每个 Folder 增加 `item_count` 与 `market_price_status`。`item_count` 是响应结束日该 Folder 中未删除的 Collection Item 数；至少一个当前 Item 存在可匹配的已发布 PostgreSQL 价格时状态为 `available`，否则为 `missing`，合法零价格仍属于 `available`。Flutter Home 以 `item_count=0` 显示添加卡牌引导；有 Item 且状态为 `missing` 时总额显示 `--` 和市场价格不可用状态，不把未知估值伪装为 `$0`，也不从其他来源补全。Flutter Collection 同样仅把 `null` 视为缺价：空 Folder 显示零总额，有 Item 且全部缺价时显示 `--`，至少一个价格已知时汇总已知值，合法零价格按 `$0.00` 展示。

Hyperdrive 查询边界固定如下：当前价格按最多 40 个 card ref 分块，单块最多接收 1,000 行；历史按最多 100 个 series 分块，单块最多接收 1,600 个自然月块；数据库把每个月块的 JSONB 文本限制为 24 KiB，因此一批历史 JSON 理论上限为 39,321,600 bytes（37.5 MiB），并为 50 MB 响应边界中的其他列与协议开销保留余量；单次历史范围最多 400 天；Portfolio 估值事件一次最多接收 10,000 行。超出任一行数或月块字节上限均显式失败，不截断后继续返回不完整业务结果。`POST /api/v1/cards/:card_ref/price-series/batch` 继续最多接收 100 项，但默认 PostgreSQL 实现改为当前快照集合查询加历史集合查询，不再对 100 项执行 `Promise.all` 查询扇出。Admin 安装分析不再读取完整 `app_installation` 后由 Worker 过滤：日期、平台与国家筛选在 SQL 执行，summary 固定返回一行、trend 只返回按日聚合行，分组明细在数据库 `LIMIT/OFFSET` 且 `page_size` 最大 100；环境筛选不匹配当前 Worker 时直接返回空统计，不查询共享数据库。

价格金额在 PostgreSQL 使用整数 `amount_micros`，API 边界转换为美元数值；月度 JSONB 同时支持紧凑 `{d,a}` 与既有 `{date,price}` 点位格式。空点数组是正常无历史数据；顶层非数组、非法日期、非法金额或不完整点位必须显式失败，不得过滤后返回空历史或部分历史。Search、Trending、Price Series 与 Market Prices 的缓存版本已分别提升，防止迁移前价格结果跨切换复用；Shop 使用的 `GET /api/v1/cards/:card_ref/sold-listings` 保持 `no-store`，只读取已发布 PostgreSQL TCGplayer current snapshot，不使用其他数据库来源。

## Apple Notifications V2

| API/任务 | 当前行为 |
|---|---|
| `POST /api/v1/apple/notifications/v2` | 无 App 用户鉴权；要求存在有界非空 `signedPayload`，允许 Apple 增加其他顶层字段并在 `request_json` 中原样保留；先写原始收件箱，再用 Apple 官方库验签并消费。原始落库失败返回非 2xx。 |
| 每 5 分钟 Cron | 重试 `pending`、`processing_failed` 或处理租约已过期的收件箱记录。 |
| Apple Server API 校正 | Cron 查询 `correction_required` 对应的现有 purchase chain，调用 Apple 当前订阅状态/交易接口并再次验签嵌套 JWS；只修正同链状态与已有 grant。 |

dev/prod 共用 PostgreSQL 后，`apple_notification_inbox.environment` 是通知队列的持久化归属。入站去重键为 `(environment, payload_sha256)`；通知重试、processing lease、完成/失败更新和 Server API 校正均同时过滤运行时环境。dev 只能领取 `Sandbox`，prod 只能领取 `Production`，不能由一个环境处理另一环境的队列。无法证明环境的既有 PostgreSQL 行会阻止 schema migration，不静默猜测。

Apple 官方 Node SDK 的证书吊销检查和 Server API 请求依赖 `node-fetch` 接口；Workers bundle 将该模块定向 alias 到原生 Worker `fetch` 兼容层，只补齐 SDK 实际使用的 `Headers`、请求超时和 `Response.buffer()`。证书验签仍保持 `onlineChecks=true`，网络失败继续进入可重试状态，不允许通过关闭在线检查或直接解析未验签 JWS 绕过安全边界。

未知但已验签的主通知类型和 Payload 字段会完整进入结构化通知及 Admin 动态选项/详情；在没有已定义业务语义时标记为 `processed`，不猜测建单或修改 purchase chain/grant。验签后的通知以 `notificationUUID` 幂等，新订单以 `environment + transactionId` 幂等。purchase chain 生命周期按 `(signedDate, notificationUUID)` 保护：更早事件不能覆盖更新状态，同一时点冲突进入 `correction_required`。Grace 保持 grant 有效至 `gracePeriodExpiresDate`，Billing Retry/Expired 使 grant 失效，Refund 修改原交易并撤销同链 grant；`REFUND_REVERSED` 等不能从通知本身确定终态的事件先进入校正，再由 Apple Server API 当前状态恢复受影响订单/链路。校正不会创建 owner/session grant，也不按 UID 传播 Premium。

## 当前边界

上述能力定位为 **App 订阅体验原型 + StoreKit 抽象层 + Admin/PostgreSQL 数据骨架**，不是生产可用的订阅闭环。当前至少存在以下上线阻塞：

- 客户端已在 Fresh Purchase 前尽力申请 challenge，并仅将 StoreKit 2 signed transaction 作为即时 Premium 证据异步上传；业务接口失败不反向覆盖本机购买成功。
- App 已将静默权益读取与主动 Restore 分离：启动只读取 Apple verified `Transaction.currentEntitlements`，用户主动 Restore 才调用 `AppStore.sync()`；Restore 实现 Success/Not Found/Failed/15 秒 Timeout 分流。`AppStore.sync()` 的 StoreKit `systemError` 可回退读取本机 current entitlements，但仅以 Apple verified 且命中配置 SKU 的证据判定 Success；无匹配权益仍保留同步失败，其他同步错误不回退。Success 不进入 Purchase Success，并在后台尽力完成 App Attest proof，不以 proof 同步失败覆盖本机成功。
- Workers 已有 Fresh Purchase、Restore、Notifications V2 与 Apple Server API 校正链；App Attest 原生代码尚未在 Xcode/真机验证，dev Apple Server API Secret 配置项已存在但内容有效性尚未通过真实调用证明，production 需独立配置。
- `billing_entitlement_grant` 旧 owner 关联只兼容保留，不参与授权。
- Scan Quota 与 Folder 限制已由服务端基于可信 grant 原子执行；Waiting/自动递补、Processing 删除后的后台结算和 `blocked_action=create_folder` 已按页面内最小上下文实现，非成功或目标失效不执行旧动作。
- Admin 已可查询原始收件箱失败记录；完整 Decoded Payload 只在授权用户主动打开详情时加载，`signedPayload` 默认不返回，复制 JSON 只由用户主动触发。最新 Admin PRD 未定义额外查看/复制审计表或审计查询功能，本版本不猜测新增该范围。
- 当前 App 没有 PRD 所述的首次安装网络授权弹窗。按 PRD 同时规定的“不得新增无业务需要权限”，实现没有伪造网络权限，而是在现有 Splash/启动预加载结束后、Onboarding 展示前执行 ATT：仅首次安装且状态为 `notDetermined` 时请求；冷启动不重复请求；后台回前台只读取最新状态并同步 Singular，不主动弹窗。`app_tracking_transparency`、Singular SDK 和 `NSUserTrackingUsageDescription` 已接入；Singular Key 通过 `SINGULAR_API_KEY` / `SINGULAR_SECRET_KEY` 构建参数注入，缺 Key 或 SDK 异常不阻断主流程。正式 Key 与 iOS 真机归因验证仍待完成。

订阅权益上线前必须以最新 v1.1 PRD 评审结论补齐服务端可信证据、会话级 grant、通知状态归约、幂等和异常处理，并完成 Sandbox、TestFlight 及服务端集成验收。
