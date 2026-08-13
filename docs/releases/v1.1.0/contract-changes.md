# v1.1.0 契约变化

## 订阅与内购数据骨架

当前实现新增以下 D1 表，迁移见 `apps/workers-api/src/db/migrations/0025_billing_admin.sql`：

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

Portfolio API 的 Folder、Collection Item、Wishlist、Dashboard 与估值历史请求同样统一使用从调用发起计时的 15 秒总 Deadline；到期取消客户端等待并返回通用 Timeout 文案，迟到响应不能完成已经过期的保存或覆盖当前读取状态。Create Folder、Quick Collect、完整 Collection Item Create 与 Add Wishlist 均发送 UUID `Idempotency-Key`；Timeout 后按稳定 owner、创建入口及规范化名称、完整 Item 草稿或 card ref 复用该 Key，即使 access token 已刷新也不改变。服务端以 Key 作为新资源 ID，同 Key/相同语义返回原资源，同 Key/不同字段返回 `409`，非法 Key 返回 `422`。成功或明确的非 Timeout 响应后客户端清除 Key，后续主动创建是新操作；Quick Collect 与完整 Create 使用不同操作域，不会互相重放。旧客户端不带 Key 时继续兼容。该客户端边界不拆分 Folder Move 与字段编辑的原子 `PATCH`。

Card Data API 的 Home 推荐、Search、Set/Card Detail、市场价与 Price History 请求也使用同一 15 秒总 Deadline；到期取消当前客户端等待并返回 `REQUEST_TIMEOUT`。Search 和 Range Controller 继续以当前请求代次决定是否接纳响应，因此旧查询或旧 Range 的迟到结果不能覆盖用户后续选择。

Auth API 的每次 HTTP 请求已使用 15 秒 Deadline。启动时 `validateStoredSession` 从业务操作开始计时，`/auth/me → token refresh → /auth/me` 内部校验链的每一步只获得当前剩余预算，不会重新获得 15 秒。到期取消客户端等待并进入现有网络失败处理，不返回迟到 session；OAuth 继续沿用统一授权失败文案，不因 Deadline 引入新的用户可见错误类型。

Currency Rate API 的 `/rates` 请求使用 15 秒总 Deadline。并发货币切换继续共享同一个在途汇率请求；Timeout 后取消客户端等待、清除共享 Future，保持原货币与已有缓存不变，迟到汇率不会写入缓存，用户下一次主动操作可重新请求。

Apple entitlement 的 purchase challenge、Fresh Purchase JWS 同步、App Attest challenge/register、Restore proof verify 与 lifecycle 校正等 Workers HTTP 请求统一使用 15 秒 Deadline。HTTP Timeout 映射为可重试的 `REQUEST_TIMEOUT/408`，迟到响应不能被当作 grant 成功；补偿队列保留证据后续重试。该限制不作用于 Apple Purchase Sheet、`AppStore.sync()` 或 App Attest 原生计算阶段，也不以 proof HTTP 失败撤销本机 StoreKit verified 的即时 Premium。

根启动流程在 Onboarding 完成后执行一次最长 15 秒的静默 entitlement Refresh。首次启动使用 `source=onboarding`，后续完整冷启动使用 `source=cold_start`；明确 Free 展示完整 Subscription Page，Premium 或 Unknown 进入 Home。该门禁不监听前后台切换，也不在 App 使用过程中因状态变为 Free 自动展示 Subscription Page。启动静默失败不显示主动操作错误 Toast；用户主动点击 Premium 受限功能时仍使用带失败反馈的 Refresh。

Subscription Page 固定使用 `Choose Your Plan` 和四项 Premium Benefits；Subscription Success 固定使用 `You're Premium!`、`Your premium features are now unlocked.`、相同四项权益及 `Start Exploring`。Wishlist 不属于 Premium，Success 不提供额外的 `Manage subscription` 正常出口。

Home/Search/Collection/Profile 顶部入口仅在本机权益明确为 Free 时显示，Unknown/Premium 隐藏；入口打开完整 Subscription Page，并分别携带 `source=home/search/collection/profile` 与 `entry_source=top_subscription_entry`。Profile Banner 使用 `source=profile&entry_source=profile_banner`；启动门禁使用 `onboarding/cold_start`，Scan Pro Card 使用 `scan`，Scan 顶部及二级页面不挂载入口。Purchase Success 将来源及入口来源传入 Subscription Success；四个一级页面和 Scan 通过 `push/pop` 返回原页面实例，`Start Exploring` 不重建来源页；功能卡点仍使用 `presentation=sheet`，不进入 Subscription Success。

## Admin 订单与通知契约

`0032_billing_order_facts.sql` 为 `billing_transaction` 增加 `business_status`、`charge_count` 和 `source_notification_uuid`。新交易由 Fresh Purchase、Restore 和 Notifications V2 三条已验证 Apple 证据链共享同一事实计算：免费试用固定为 0；成功付费按同一 `environment + originalTransactionId` 内的 `purchase_at + transactionId` 排序；重复交易不增加次数；退款不减序号、不重排。只有存在更早试用交易且尚无成功付费时才标记 `trial_conversion`，不从单独一条历史 `RENEWAL` 猜测试用转换。

`DID_CHANGE_RENEWAL_PREF + UPGRADE/DOWNGRADE` 只更新购买链的 `next_product_id`，不创建订单。`SUBSCRIBED + RESUBSCRIBE` 使用新的 `originalTransactionId` 时是该链首次付费，业务状态为 `initial_purchase`、扣款次数为 1；沿用已有 `originalTransactionId` 时视为同链续费，即使 Apple 交易原因为 `PURCHASE`，也按 `renewal` 计入下一次扣款。确定性重算保证同链只有第一笔实际付费保留 `initial_purchase`。

`0033_billing_exchange_rate_snapshot.sql` 为订单增加可审计的 USD 汇率快照。现有汇率服务口径为 `1 USD = rate × 原币种`，换算使用整数 micros 的除法与 half-away-from-zero 舍入；USD 使用 rate 1。快照固化 rate、base/quote、来源、生效/抓取时间、陈旧标记、换算版本和舍入模式。汇率不可用或币种不支持时订单照常入库，USD 及快照保持空，不以 0 或最新汇率猜测；已固化订单不随未来汇率变化重算。

已验签的 Apple 建单类通知在尚无 App owner 关联时，仍可基于启用的 `billing_product` SKU 创建 purchase chain 与订单。该链以 `original_owner_type=unlinked`、空 `original_owner_id` 表达“Apple 事实已保存但 UID 未关联”；Admin 展示空 UID，UID 筛选和安装时间查询忽略空值。通知流程不会为 `unlinked` 链创建 session grant，未知或未启用 SKU 进入 `correction_required`，因此无 UID 订单记录不会成为 Premium 授权来源。之后只有 Fresh Purchase challenge 或 Restore App Attest 这类绑定 live session 的可信证明，才能把仍为 `unlinked` 的链补关联为当前 owner并创建当前 session grant；已关联 owner 不会被其他 session 改写。

| API | 当前行为 |
|---|---|
| `GET /api/v1/admin/billing/transactions/options` | 从实际交易动态返回国家代码与 SKU。 |
| `GET /api/v1/admin/billing/transactions` | 支持 PRD 组合筛选及 13 列订单事实；UID、订单 ID 精确匹配。 |
| `GET /api/v1/admin/billing/transactions/export` | 导出当前筛选的全部结果为 XLSX；同步上限 10,000 行，超限显式失败。 |
| `GET /api/v1/admin/apple-notifications/options` | 从已验签结构化通知动态返回主/子通知类型。 |
| `GET /api/v1/admin/apple-notifications` | 以 `apple_notification_inbox` 为入口，包含验签、解析、校正和处理失败记录。 |
| `GET /api/v1/admin/apple-notifications/:detailId` | 仅返回基本信息、处理失败原因和 Decoded Payload；不返回原始 `signedPayload`。 |

UID 只用于关联查询与安装时间，不成为 Premium owner。安装时间取该 purchase chain 已关联 UID 的最早 `app_installation.first_seen_at`。XLSX 文本使用 inline string，避免以 `= + - @` 开头的外部值被 Excel 作为公式执行。

## Folder Premium 限制

`POST /api/v1/portfolio/folders` 当前契约：Free 用户最多拥有 2 个 Folder（包含默认 Folder）；有效当前 session grant 可突破该限制。数量判断与 INSERT 在一条 SQL 中完成，并发请求不能同时创建第 3 个 Folder。客户端可发送 `X-Local-Premium-State: verified` 表示本机 StoreKit 已验证，但该头只会在无 grant 时触发 `409 ENTITLEMENT_SYNC_REQUIRED`，不能直接授权；明确 Free 超限返回 `403 PREMIUM_REQUIRED`。

Flutter Create Folder 在弹窗内等待服务端结果：保存中锁定输入、返回和重复提交；成功才关闭。普通失败保留名称并沿用通用错误反馈；`ENTITLEMENT_SYNC_REQUIRED` 保留名称并提示 Premium 正在同步；`PREMIUM_REQUIRED` 视为多设备下服务端最新限制，先刷新 Folder List，再进入 Functional Paywall，成功后用原名称重新打开 Create Folder，非成功不创建。

Collection Item 编辑与 Folder Move 继续使用单次 `PATCH /api/v1/portfolio/items/:item_id` 原子提交；Folder 变化和同次字段编辑不会拆成两个业务写请求。目标 Folder 已失效时服务端返回 `NOT_FOUND` 且不更新 Item；App 刷新 Folder/Item 真值，保持原 Source Folder，不展示半迁移结果。

## Scan Quota

| API | 当前行为 |
|---|---|
| `GET /api/v1/scan/quota` | 返回当前 owner 的终身 10 次 Free quota；有效当前 session grant 返回 `unlimited=true`，本机 Premium 同步中返回 `ENTITLEMENT_SYNC_REQUIRED`。 |
| `POST /api/v1/scan/recognize` | 要求 body `request_id` 与 `Idempotency-Key` 为同一 UUID；在 R2/OCR 前原子预占。Matched/No Match 消耗，技术失败释放，Premium 不消耗 Free quota；完成响应可用原 request ID 重放。 |

`scan_quota_request` 同时是额度账本和请求幂等真源。Free 的 `reserved + consumed` 最多 10；同 owner 多 session 并发不能预占同一最后额度。处理中租约为 60 秒，防止 Worker 中断永久占用；released 请求不计入已用额度。Flutter 已使用响应中的 quota 更新展示，并已接入 Waiting 与服务端确认 Unlimited 后的 Queue 顺序自动递补。Processing 删除立即移除 UI，但保留原请求的后台观察；最终响应继续更新 Quota，缺少 Quota 时刷新服务端真值，且迟到结果不得重插卡片。

Functional Paywall 只在 typed Purchase/Restore success 后恢复仍有效的 Waiting；quota=0 且图片未入 Queue时只返回 Scan，不自动打开相机或图库。Scan Pro Card 使用完整 Subscription Page：Purchase Success 经 Success Page 返回原 Scan 页面实例，Restore/外部解锁直接返回，因此当前 Queue 不会因重新创建路由而丢失。首次 quota 刷新延后到首帧，避免路由切换构建期修改 Riverpod provider。

## Performance 与 Extended Price History

| API | 当前行为 |
|---|---|
| `GET /api/v1/portfolio/performance?range=...&folder_id=...` | 仅当前 session grant 可访问；返回指定 Folder 的指标、曲线、Item 数、市场价与购买价完整性状态。 |
| `GET /api/v1/portfolio/items/:item_id/performance?range=...` | 仅当前 session grant 可访问；先校验 Item 归属，再只计算该 Collection Item，不聚合同卡其他 Item。 |
| `GET /api/v1/portfolio/valuation-history?days=...` | `days<=90` 保持 Free 可用；`days>90`、最多 365 天时强制当前 session grant。本机 verified 头不能授权，只能触发 `ENTITLEMENT_SYNC_REQUIRED`。 |
| `GET /api/v1/cards/:card_ref/market-prices` | 继续公开当前市场价与最多 90 天 history；路由层统一裁剪，不能借此绕过 1Y Premium。 |
| `GET /api/v1/cards/:card_ref/price-series?days=...` | `days<=90` 保持公开；`days>90` 时要求 live session 和当前 session grant。本机 verified 头只能触发同步等待，不能授权。 |
| `POST /api/v1/cards/:card_ref/price-series/batch` | 任一请求 `days>90` 时整批使用同一 live session grant 校验；Raw 与 Graded 1Y 均通过该受保护入口加载，不回退到公开单请求。 |

Performance 与普通历史图表统一使用 `1D/7D/15D/1M/3M/1Y`，默认 `1M`。Home 与 Card Detail Performance 整体为 Premium；Home Overview 与 Card Detail Price History 仅 1Y 为 Premium。Functional Paywall Purchase/Restore 成功会返回原图表并自动加载 1Y，未获得 Premium 时不改变原 Range 或已加载数据，Premium 变 Free且当前为 1Y 时回退 3M。

Home Performance 的 `current` 与 `series[]` 点位增加 nullable `market_change_usd`、`portfolio_change_usd`、`quantity_change`。服务端按未提前舍入的历史价格和数量计算 `Market Change = sum((MP(t) - MP(t_prev)) * Q(t_prev))`，再以 `Portfolio Change = Daily Change - Market Change` 分离持仓变动；响应末端统一保留两位小数。Range 首点若范围外存在紧邻可靠日，仍使用该日作为 `t_prev`；只有全历史没有可信前序节点时三项才返回 `null`，客户端不得伪造为 0。Home Tooltip 只展示 Date、Market、Portfolio、Qty，不展示内部校验用 Daily Change；Partial Purchase Price 说明使用 Info Popover，且与 Chart Tooltip 互斥。该响应扩展不新增数据库迁移。

Home Performance 的 Folder 归属遵循 App PRD 的整体迁移规则：每个 Item 以最新 Event 的 Folder 作为全部可靠历史的当前归属，再按目标日期还原 Quantity、价格映射和删除状态。v1.1 Folder Move 成功后，Source Folder 立即移除该 Item 的当前及全部可靠历史，Target Folder 从 `performance_history_available_from` 起获得完整可靠历史；不会把 Move 前的可靠片段继续留在 Source。Card Detail Performance 不按 Folder 过滤，仍只计算目标 `collection_item_id`。

同一点位同时增加 nullable `market_value_change_usd` 与 `profit_loss_change_usd`，供 Card Detail Performance 使用。两项均由服务端以未提前舍入的目标 Item 历史值和 `t_prev` 计算，Range 首点沿用范围外紧邻可靠节点；不存在可信前态或成本不可计算时返回 `null`。正常状态曲线使用 Profit/Loss，Tooltip 仅展示 Date、Daily Change、Market Value、Profit/Loss、Qty；Purchase Price 缺失状态曲线使用 Market Value，Tooltip 不得展示 Profit/Loss、Purchase Cost 或 Return。1D 单点仍可点击，切 Range 或离开 Performance 会销毁旧 Tooltip 状态。

`0031_performance_history.sql` 增加购买价、币种、生效时间、历史可用起点和 Folder 加入时间等事件事实。该迁移已在隔离空库及远程 dev 只读导出的本地副本执行并验证；尚未写入远程 dev 或 prod。

Card Detail 普通价格历史 1Y 的服务端防绕过已关闭：Free 仍可读取 1D 至 3M；1Y 要求当前 live session 的有效服务端 grant，同 UID 的另一 session 不继承。本机 verified 只区分 `ENTITLEMENT_SYNC_REQUIRED`，不能作为授权。该变更不新增 schema 或迁移。

## Apple Notifications V2

| API/任务 | 当前行为 |
|---|---|
| `POST /api/v1/apple/notifications/v2` | 无 App 用户鉴权；要求存在有界非空 `signedPayload`，允许 Apple 增加其他顶层字段并在 `request_json` 中原样保留；先写原始收件箱，再用 Apple 官方库验签并消费。原始落库失败返回非 2xx。 |
| 每 5 分钟 Cron | 重试 `pending`、`processing_failed` 或处理租约已过期的收件箱记录。 |
| Apple Server API 校正 | Cron 查询 `correction_required` 对应的现有 purchase chain，调用 Apple 当前订阅状态/交易接口并再次验签嵌套 JWS；只修正同链状态与已有 grant。 |

未知但已验签的主通知类型和 Payload 字段会完整进入结构化通知及 Admin 动态选项/详情；在没有已定义业务语义时标记为 `processed`，不猜测建单或修改 purchase chain/grant。验签后的通知以 `notificationUUID` 幂等，新订单以 `environment + transactionId` 幂等。purchase chain 生命周期按 `(signedDate, notificationUUID)` 保护：更早事件不能覆盖更新状态，同一时点冲突进入 `correction_required`。Grace 保持 grant 有效至 `gracePeriodExpiresDate`，Billing Retry/Expired 使 grant 失效，Refund 修改原交易并撤销同链 grant；`REFUND_REVERSED` 等不能从通知本身确定终态的事件先进入校正，再由 Apple Server API 当前状态恢复受影响订单/链路。校正不会创建 owner/session grant，也不按 UID 传播 Premium。

## 当前边界

上述能力定位为 **App 订阅体验原型 + StoreKit 抽象层 + Admin/D1 数据骨架**，不是生产可用的订阅闭环。当前至少存在以下上线阻塞：

- 客户端已在 Fresh Purchase 前尽力申请 challenge，并仅将 StoreKit 2 signed transaction 作为即时 Premium 证据异步上传；业务接口失败不反向覆盖本机购买成功。
- App 已将静默权益读取与主动 Restore 分离：启动只读取 Apple verified `Transaction.currentEntitlements`，用户主动 Restore 才调用 `AppStore.sync()`；Restore 实现 Success/Not Found/Failed/15 秒 Timeout 分流，Success 不进入 Purchase Success，并在后台尽力完成 App Attest proof，不以同步失败覆盖本机成功。
- Workers 已有 Fresh Purchase、Restore、Notifications V2 与 Apple Server API 校正链；App Attest 原生代码尚未在 Xcode/真机验证，Apple Server API Secret 尚未配置。
- `billing_entitlement_grant` 旧 owner 关联只兼容保留，不参与授权。
- Scan Quota 与 Folder 限制已由服务端基于可信 grant 原子执行；Waiting/自动递补、Processing 删除后的后台结算和 `blocked_action=create_folder` 已按页面内最小上下文实现，非成功或目标失效不执行旧动作。
- Admin 已可查询原始收件箱失败记录；完整 Decoded Payload 只在授权用户主动打开详情时加载，`signedPayload` 默认不返回，复制 JSON 只由用户主动触发。最新 Admin PRD 未定义额外查看/复制审计表或审计查询功能，本版本不猜测新增该范围。
- 当前 App 没有 PRD 所述的首次安装网络授权弹窗。按 PRD 同时规定的“不得新增无业务需要权限”，实现没有伪造网络权限，而是在现有 Splash/启动预加载结束后、Onboarding 展示前执行 ATT：仅首次安装且状态为 `notDetermined` 时请求；冷启动不重复请求；后台回前台只读取最新状态并同步 Singular，不主动弹窗。`app_tracking_transparency`、Singular SDK 和 `NSUserTrackingUsageDescription` 已接入；Singular Key 通过 `SINGULAR_API_KEY` / `SINGULAR_SECRET_KEY` 构建参数注入，缺 Key 或 SDK 异常不阻断主流程。正式 Key 与 iOS 真机归因验证仍待完成。

订阅权益上线前必须以最新 v1.1 PRD 评审结论补齐服务端可信证据、会话级 grant、通知状态归约、幂等和异常处理，并完成 Sandbox、TestFlight 及服务端集成验收。
