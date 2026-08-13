# v1.1.0 数据迁移

2026-08-13 已在远程 dev D1 `cards_basic_information_all_dev` 连续应用 `0025` 至 `0034`，Wrangler 随后返回 `No migrations to apply`；订阅购买链、session grant、通知 inbox、Scan Quota 表及订单事实/汇率/自动续订快照字段均经远程只读 SQL 核对存在。prod 与开发者常用 local 仍未执行这些 v1.1 迁移。dev Worker 与 Admin 随后发布为 Cloudflare 版本 `244bf926-ecdd-442c-923c-ca417f54c50d`，健康接口、Admin HTML 和实际 JS 资源均返回 HTTP 200。Apple Product ID、Root CA 与 Server API 密钥仍未配置，因此部署成功不代表 Apple 购买闭环可用。

2026-08-12 已使用 Wrangler 4.106.0 在独立 `--local --persist-to` 空库中按顺序执行 `0000` 至 `0033`，34 条迁移全部成功；重复 apply 返回无待执行迁移，关键 v1.1 表及订单事实/汇率快照列均存在。2026-08-13 新增 `0034` 后，Workers 自动化完整迁移链已验证 `0000` 至 `0034` 共 35 条迁移；`0034` 也已在独立 D1 测试中验证历史订单保持空快照及 `0/1/NULL` 约束。Wrangler 实际空库证据仍只到 `0033`，不得改写为已手工执行 `0034`。这些证据不代表已在开发者常用 local、远程 dev 或 prod 执行，也不能替代带真实历史数据的预迁移审计。

2026-08-13 通过 Wrangler 只读列举确认：远程 dev 与 prod 当时均待执行 `0025` 至 `0033`；本分支随后新增且未远程执行 `0034`，因此当前待执行范围为 `0025` 至 `0034`。两环境 Secret 列表均未包含 Apple Root CA 或 App Store Server API 的 Issuer ID、Key ID、Private Key。该检查没有执行迁移、写入 Secret 或部署 Worker。

2026-08-13 又通过 Wrangler 只读导出远程 dev D1，并只在仓库外的本地 SQLite 副本执行 `0025` 至 `0033`。导出基线包含 `0000` 至 `0024` 共 25 条迁移、67 个 `collection_item`、145 条 `collection_item_event`、36 个 Folder、1,053,034 条 `tcg_price`、267,682 条 `cards_all`、167 条 `scan_record`、86 条 session 和 30 条 installation。九条 v1.1 迁移连续成功，单条耗时 9-45 ms，`0031` 为 17 ms；迁移后 `quick_check=ok`、外键检查无错误，核心表行数不变。

`0031` 的真实历史不变量为：67/67 个 Existing Item 的 `performance_start_at` 与 `purchase_price_effective_at` 等于原 `created_at`，67 个 Item 使用同一迁移时刻作为 `performance_history_available_from`；145 条 Event 没有删除或重排，其中与现存 Item 关联的 77 条继承可靠历史起点，其余 68 条已删除 Item 的历史事件保持原样。该结果证明迁移不会把当前 Folder 或属性伪造成早于可靠起点的历史，但 dev 最大 owner 只有 24 条 Event、12 个现存 Item，不代表重度收藏用户规模。

同一副本上，代码实际使用的 Performance Event/价格 SQL 各运行 20 次，中位数分别为 6.71 ms 和 7.72 ms；Admin 订单表为空，空列表与计数 SQL 中位数分别为 6.52 ms 和 6.41 ms。计时包含本地 sqlite3 进程启动，但不包含 Cloudflare 网络、D1 远程调度或 Worker JavaScript 计算。由于缺少有订单样本和大资产 owner，这些结果只能排除当前 dev 小样本下的明显数据库退化，不能宣称满足 App 15 秒或 Admin 普通查询 3 秒的发布门槛。该副本预演完成时远程 dev/prod 均未执行 v1.1 迁移；远程 dev 的后续执行结果见本文首段。

## 0025 Billing Admin 基础表

迁移 `0025_billing_admin.sql` 新增 `billing_product`、`billing_purchase_chain`、`billing_transaction`、兼容旧骨架的 owner grant 以及 `apple_server_notification`。后续 `0026` 至 `0034` 均在这些基础表上增加 session grant、验证、生命周期、订单事实、汇率及自动续订快照字段，因此远程环境必须从 `0025` 按编号连续执行，不可从 `0026` 起跳过。

- 迁移只新增表和索引，可先于 v1.1 Worker 上线。
- `billing_product` 不在 migration 中猜测写入候选 Product ID；商品冻结后由受控配置流程写入三个明确映射。
- `billing_entitlement_grant` 仅兼容早期骨架，服务端授权路径不得读取，也不得迁移为 session grant。
- 回滚前必须先停止 v1.1 Worker 对这些表的写入并导出订单/通知审计数据；仅在确认无下游迁移依赖后才能删除基础表。

## 0026 Session Entitlement Grant

迁移 `apps/workers-api/src/db/migrations/0026_session_entitlement_grant.sql` 新增 `billing_session_entitlement_grant`，用于保存当前有效 App session 与 Apple purchase chain 的服务端授权关系。

兼容性与数据规则：

- 迁移只新增表和索引，不修改现有业务表，可先于应用代码部署。
- 不从 `billing_entitlement_grant(owner_type, owner_id)` 回填。旧表只有 UID/owner 关联语义，不能证明当前 session 持有 Apple 购买上下文。
- Access Token Refresh 沿用同一 session，因此不复制 grant；Logout 撤销 session 后，鉴权层立即阻止旧 grant 使用。
- Sandbox 与 Production 通过关联 purchase chain 的 `environment` 强制隔离。
- 回滚仅在确认没有新代码读写该表后执行 `DROP TABLE billing_session_entitlement_grant`；生产回滚前应先导出审计数据。

本文件只记录迁移设计。该迁移已应用到远程 dev，尚未应用到开发者常用 local 或 prod 数据库。

## 0027 Apple Entitlement Verification

迁移新增 Fresh Purchase 一次性 challenge、验证请求幂等/审计表，并为购买链增加 `state_effective_at`。challenge 绑定 session 和 Product ID，消费时必须使用带条件更新确保只消费一次；验证尝试只保存证据 SHA-256 和安全响应，不在该表重复保存原始 JWS。`processing_expires_at` 提供 60 秒处理租约，使 Worker 中断后的同证据幂等请求可以恢复，且不允许有效租约期间并发接管。

该迁移是向后兼容新增。回滚前必须先停止 challenge/verify 接口写入，再删除两个新表；SQLite 已增加的 `state_effective_at` 不在原地回滚，旧代码会忽略该 nullable 列。该迁移已应用到远程 dev，尚未应用到常用 local 或 prod。

## Workers 运行兼容性

Apple JWS 验签采用官方 `@apple/app-store-server-library`，`apps/workers-api/wrangler.toml` 启用 `nodejs_compat`。Cloudflare 禁止该库的 `jsrsasign` 依赖在 Worker 全局作用域生成随机值，因此验签器与 Server API Client 必须在请求或定时任务处理期间动态加载。dev 已通过真实 Worker 启动校验并部署；prod 仍只有 dry-run 打包证据，尚未部署。

## 0028 Apple App Attest Restore

迁移新增 `billing_apple_app_attest_challenge` 与 `billing_apple_app_attest_key`。前者保存 session、purpose、request ID、key ID、JWS 摘要、canonical client data、唯一消费标记和幂等终态；后者保存 Apple 验证后的 P-256 公钥、receipt、环境与 assertion counter。迁移只新增表和索引，不修改现有数据，可先于应用代码部署，不从 UID、installation ID、owner grant 或历史交易回填。

回滚前必须先停用 App Attest challenge/register/restore 三个接口，再导出需要保留的重放审计数据，最后删除两张表。回滚会使新 session 无法通过 Restore 建立服务端 grant，但不影响 StoreKit 本机 Restore 结果。当前已通过真实 Miniflare D1 的 session 隔离、单次消费、counter 和 grant 写入测试；迁移已应用到远程 dev，尚未应用到常用 local 或 prod。

## 0029 Apple Notification Lifecycle

迁移新增 `apple_notification_inbox`，先保存 Apple 请求 JSON、完整 `signedPayload`、SHA-256、接收时间、处理租约、重试次数和终态。该表允许通知 UUID、类型和环境为空，因此验签或解码失败也不会丢失原文。验签成功后再写现有 `apple_server_notification` 结构化表，并以 `inbox_id` 一对一关联。

`billing_purchase_chain` 新增生命周期、自动续订和下期方案的独立版本字段；`billing_transaction` 新增 `refund_completed_at`，避免以原购买时间冒充退款时间。全部为 nullable 增量列，不回填历史通知或推断历史状态。

兼容性与回滚：

- 旧代码会忽略新表和 nullable 列，迁移可先于新 Worker 上线。
- 新 Worker 必须在迁移后启用，否则接收入口会返回 `PERSISTENCE_FAILED`，不会向 Apple 假报已保存。
- 回滚先移除 App Store Connect 通知 URL或回退 Worker，再导出原始收件箱；SQLite 增量列保留，停用路由后才可删除新索引和收件箱表。
- `correction_required` 是待 Apple Server API 校正，不代表已消费完成；不得据此恢复 entitlement。

当前已通过真实 Miniflare D1 的原文留存、幂等建单、乱序保护、失败恢复与环境隔离测试；`0029` 已应用到远程 dev，尚未应用到常用 local 或 prod。

## 0032 Billing Order Facts

迁移为 `billing_transaction` 增加 nullable `business_status`、`charge_count` 和 `source_notification_uuid`，并增加订单状态与扣款次数查询索引。历史回填只使用现有确定性事实：退款状态、明确的零金额、Apple `PURCHASE`/`RENEWAL` 原因及同链交易时间；金额为空的历史交易保留空业务事实，不猜测试用、首次付费或恢复类型。

扣款次数按 `purchase_chain_id + environment` 隔离，付费交易按 `purchase_at + transactionId` 排序；试用为 0，退款保留付费序号。新 Worker 在 Fresh Purchase、Restore 和通知创建订单后都会重算该链，晚到的更早交易也能确定性修正序号。宽限恢复和重试恢复只由已验签通知及更新前 purchase-chain 状态确定，普通历史回填不猜测。

兼容性与回滚：

- 三列均为 nullable，旧 Worker 忽略新列；迁移可先于新 Worker 上线。
- 新 Admin 依赖这些列，必须在 `0032` 执行后上线；否则订单查询会显式失败。
- 回滚应用时停止读取新列并回退 Admin/Worker，保留新增列和已固化事实；不要删除列或重建旧表，以免丢失扣款序号审计数据。
- 本迁移不会修改、删除或重排 Apple 交易本身，也不会把 UID 变成 Premium owner。

当前真实 Miniflare D1 已验证试用为 0、付费顺序、晚到交易重排、重复交易幂等、退款保序、Restore 写入、精确订单查询、动态选项、XLSX 和 inbox 失败详情；`0032` 已应用到远程 dev，尚未应用到常用 local 或 prod。

无 UID Apple 订单复用现有非空 owner 列，不新增迁移：`original_owner_type='unlinked'` 且 `original_owner_id=''` 是明确的“尚未建立 App 业务关联”状态，不是匿名账号、UID 或 Premium owner。后续可信 Fresh Purchase/Restore 可以只在该状态下补真实 owner；Admin 查询忽略空 owner ID。该规则不回填或猜测历史链，也不创建 session grant。

## 0030 Scan Quota

迁移新增 `scan_quota_request`，同时保存 owner、发起 session、Free/Premium 模式、预占/消费/释放状态、处理租约、重试次数、Scan ID 和最终响应。该表既是额度账本也是请求幂等真源，不另设可与请求记录漂移的累计计数表。

兼容性与数据规则：

- 只新增表和索引，不修改现有 `scan_record`；旧 Worker 会忽略新表。
- 不从现有 `scan_record` 或客户端 `SharedPreferences` 回填历史消费。上线切换时所有 owner 从 10 次开始，避免把无法证明的历史扫描伪装成已结算额度。
- Free `reserved + consumed` 计入终身 10 次；released 与 Premium 请求不消耗 Free quota。
- 回滚先回退新 Worker，保留账本表以免未来重新上线时重置额度。确认永久放弃且已导出审计数据后才可删除表。

当前真实 Miniflare D1 已验证最后 1 次额度的多 session 并发、预占/结算幂等、技术失败释放、Premium 不扣 Free 和租约接管；`0030` 已应用到远程 dev，尚未应用到常用 local 或 prod。

## 0033 Billing Exchange Rate Snapshot

迁移为 `billing_transaction` 增加 nullable 汇率、base/quote、来源、生效时间、抓取时间、是否使用陈旧缓存、换算版本和舍入模式。新订单使用现有 USD 汇率服务；其口径为 `1 USD = rate × original currency`，因此按 `amount_usd_micros = round(amount_micros / rate)` 换算。USD 使用恒等 rate 1；其他币种使用 `frankfurter.dev` 已验证快照，版本为 `usd_divide_rate_v1`，正数 micros 采用 half-away-from-zero 舍入。

兼容性与回滚：

- 全部为 nullable 增量列，旧 Worker 会忽略，迁移可先于新 Worker 上线。
- 汇率或原始金额不可证明时订单仍入库，USD 金额与快照保持空；不得写 0 或猜测汇率。
- 历史订单不猜测回填。后续补算只允许填充当前为空的 USD 与快照列，不覆盖已经固化的订单事实。
- 回滚应用时停止读写新字段并回退 Worker；D1 不安全删除增量列，保留数据供审计。

当前汇率换算、USD 恒等和无汇率非阻断已有确定性测试；`0033` 已应用到远程 dev，尚未应用到常用 local 或 prod。

## 0034 Billing Auto-Renew Snapshot

迁移为 `billing_transaction` 增加 nullable `auto_renew_snapshot`，只允许 `0/1/NULL`。Admin 的自动续订展示、筛选和 XLSX 均读取订单快照，不再读取 `billing_purchase_chain.auto_renew` 当前值，避免后续关闭或恢复自动续订改写历史订单显示。

- Notifications V2 建单时，只有已验签 `signedRenewalInfo.autoRenewStatus` 才为订阅订单写 `0/1`；Lifetime 按产品规则固定写 `0`。
- Fresh Purchase / Restore 的 signed transaction 不包含可证明的 `autoRenewStatus`，订阅订单写 `NULL`；Admin 显示 `--`，不以当前链路状态猜测。
- 历史订单不回填。当前 purchase chain 的自动续订值不是历史订单事件快照，不能反向复制。
- 该列为 nullable 增量，旧 Worker 会忽略；新 Admin/Worker 依赖该列，必须先迁移再上线。回滚应用时停止读写新列并回退 Worker，保留已固化快照。

`0034` 已通过独立 D1 迁移测试和 `0000-0034` 自动化完整迁移链，并已通过 Wrangler 应用到远程 dev；尚未应用到常用 local 或 prod。
