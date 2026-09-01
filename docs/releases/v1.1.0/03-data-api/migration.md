# v1.1.0 数据迁移

## PostgreSQL 正式迁移检查点（2026-08-17）

R1 数据库基础批次已通过只在本机运行的 Wrangler remote preview，把 `0000_business_schema.sql` 与 `0001_price_domain.sql` 应用到 Hyperdrive `tcg-cards-db` 指向的 PlanetScale PostgreSQL。实机返回数据库 `postgres`、schema `public`、PostgreSQL `18.6 (Debian 18.6-1.pgdg12+2)`；目标现有 41 张表（33 张 D1 业务表、7 张新价格域表和 `postgres_migration`）、119 个索引、428 个约束及 2 个价格发布保护 trigger。两份 migration 的 SHA-256 已记录，重复执行只返回 `alreadyApplied`，未重复建表。

后续 schema-only 检查已把 `0002_apple_inbox_environment.sql`、`0003_price_history_visibility_guard.sql` 与 `0004_price_history_month_payload_limit.sql` 应用到同一目标 PostgreSQL。实机 inventory 现为 5 条 migration、41 张表、119 个索引、432 个已验证约束和 4 个价格发布保护 trigger。`0002` 为共享库中的 Apple inbox 增加持久化 `environment`，把 payload 去重和 processing 索引改为环境隔离；`0003` 增加 immediate 写入 trigger 与 deferred 可见性 trigger：月块写入时 batch 必须是同来源 `current:%` scope 的 `validated` 状态，提交时必须已发布且正被同 scope pointer 指向，禁止 published batch 事后补写或沿用旧 lineage 改写内容；`0004` 把单个月块的 JSONB 文本限制为 24 KiB。幂等复跑时五条 migration 均返回 `alreadyApplied`，事务内回滚探针实际验证合法原子发布可提交到约束检查点，published 事后写、同 lineage 改内容和超过 24 KiB 均被拒绝；同一探针还通过生产适配器经 Hyperdrive 实际执行当前价与历史价查询，验证完整 SQL 和问号参数转换可被目标 PostgreSQL 解析。本次仍返回 `migratedTables=0`、`verifiedTables=0`，只升级并核验 schema，不代表业务数据已经迁移。

正式迁移已在 dev API 进入维护状态后完成。冻结源清单为 33 张非价格业务表、270,577 行；runner 返回 `migratedTables=33`、`verifiedTables=33`，逐表源/目标行数和完整 SHA-256 摘要全部一致，其中 `cards_all=267682`、`sets=2060`、`apple_notification_inbox=34`。最大表 `cards_all` 使用 536 批，最大编码负载 326,059 bytes；`scan_record` 与 Apple inbox 的最大负载分别为 436,822 bytes 和 494,124 bytes，均低于 512 KiB 硬上限。`tcg_price`、`price_sync_state`、`cards_new`、`d1_migrations` 与 `_cf_KV` 明确排除，目标不存在旧 `tcg_price`；旧 `tcg_price` 的 1,053,034 行没有进入 PostgreSQL。切换状态只读复核确认 `price_source`、`price_series`、`price_ingest_batch`、`price_current_snapshot`、`current_price_pointer`、`price_history_month`、`card_trending_snapshot` 七张新价格表均为 0 行，34 条 Apple inbox 行全部标记为 `Sandbox`，不存在 `Production` 行。

本次正式切换时使用的迁移工具固定表顺序、列名和唯一 keyset 游标，并在每次正式执行前枚举 live D1 全表；忽略 `sqlite_%` 内部表后，实际表必须严格等于 33 张业务表与 5 张显式排除表，任何新增未分类表都会停止迁移。每批最多 500 行且编码负载硬上限为 512 KiB，D1 查询按累计 JSON 字节先行裁剪，单行超限直接失败；请求顺序复用单个 Hyperdrive client。写入按固定游标执行 `ON CONFLICT (cursor) DO UPDATE`，使迁移窗口内仍在运行的 dev D1 更新可通过重跑收敛；逐表校验按相同排序比较源/目标完整行 SHA-256。物理删除不会被静默复制，若迁移窗口内出现源删除，最终行数或摘要校验必须失败并停止切换。`--verify-cutover-state` 禁止与 schema-only 组合，且必须同时使用完整 `--verify-only` 或正式迁移及 `--confirm-source-write-frozen`；runner 只有在 33 表完整摘要全部通过后才检查七张价格空表与 Apple inbox 环境。迁移工具只接受运行时生成的 Bearer token，专用 Worker 未部署。

> **数据库边界修正（2026-08-25）**：本页已完成的 33 表、270,577 行迁移与 Worker 切换是 dev 检查点。只读 Cloudflare 回查确认现网 prod 100% 流量版本 `57213c10-d392-43a9-8d34-c6472fc3febc` 仍绑定 D1 `6a22aeca-e7e9-4064-a301-f18c4a0acb41`，没有 Hyperdrive。v1.1 prod 目标才是迁移生产 D1 数据并切换到 dev 共用的 PlanetScale PostgreSQL；切换前必须单独完成生产数据清单、主键/账号/业务冲突审计、完整摘要验证和回滚演练。v1.1 新 schema、代码、测试和后续修复仍只允许基于 PostgreSQL，不得为旧 prod D1 新增功能或回退路径；上述旧迁移 runner 仍仅作为历史证据，不得复用。

## Trending Pin 废弃（2026-08-18）

`trending_pin` 及 `/api/v1/admin/trending-pins*` 已无当前业务消费者，予以废弃。Flutter 首页与 View All 的 Trending Today 不读取该表，仍通过 `/api/v1/cards/trending` 消费 PostgreSQL `card_trending_snapshot`。

- PostgreSQL 新增向前迁移 `0005_drop_trending_pin.sql`，D1 本地/测试迁移链新增 `0035_drop_trending_pin.sql`；历史建表迁移保持不变。
- 两份迁移均只执行 `DROP TABLE trending_pin`，不使用 `CASCADE`。D1 到 PostgreSQL 清单不再迁移该表，并把旧 D1 源表列为显式排除项，避免重新创建已废弃表。
- 2026-08-18 在不再暴露旧 Admin API 的 dev Worker/Admin 已部署后，经用户单独授权执行 PostgreSQL `0005`。一次性 Wrangler remote dev 入口仅绑定共享 `HYPERDRIVE`，没有 D1、KV、R2、路由或定时任务；执行前 ledger 仅含 `0000-0004`，`trending_pin` 存在但为 0 行，且无外键引用或依赖视图。迁移在 advisory lock 保护的单个事务内执行原始 `DROP TABLE` 并写入 `postgres_migration`，最终记录与 Git 提交 LF 内容一致的 checksum `0f0e9a7804803cad4be2705d3974e12afc70c11da97f8e1f06e02b24f090dab6`、应用时间 `2026-08-18T09:21:56.628Z`；Windows 工作树首次产生的 CRLF checksum 已在确认表不存在且 ledger 精确匹配后，于同一 advisory lock 保护的事务中校正为上述规范值。事务内及事务外复核均确认 ledger 已包含 `0005` 且 `public.trending_pin` 不存在。一次性会话随后关闭，未部署专用 Worker，全程未连接或查询 D1。
- PostgreSQL drop 前可通过回滚 Worker 恢复旧接口；drop 后若必须恢复，需先按历史 DDL 重建空表，历史置顶配置只能从数据库备份恢复。

## PostgreSQL 并发写锁（2026-08-19）

`0006_mutation_lock.sql` 为共享 PostgreSQL 新增 `public.mutation_lock(lock_key text PRIMARY KEY)`，与 D1 本地/测试迁移 `0036_mutation_lock.sql` 对齐。该表保存确定性作用域锁键，不保存业务结果；新 Worker 的账号 UID、匿名账号、验证码、Folder、Wishlist/Collection 和 Scan Quota 写路径依赖此表完成事务级并发串行化。Admin Card Override 图片上传不依赖该表，而是通过 `card_ref` 唯一键上的单条原子 UPSERT 处理并发首次写入。

2026-08-19 经用户明确授权，在部署依赖该表的新 Worker 与配套 Admin assets 前先执行 PostgreSQL `0006`。一次性 Wrangler remote preview 仅绑定共享 Hyperdrive `7d71bcd0bcf64e518a23a852ced76d66`，没有 D1、KV、R2、路由或定时任务。执行前目标为 `postgres/public`、PostgreSQL `18.6`，ledger 精确包含 `0000-0005` 且 `public.mutation_lock` 不存在；迁移在 `pg_advisory_xact_lock(hashtext('kando-postgres-schema'))` 保护的单个事务内执行原始 DDL并写入 `postgres_migration`。事务内及事务外复核均确认 `0006` checksum 为 `aac5595a2e350acc6659b58712a1802a09b9fddf4d4de2cd63be4998a9f7eaea`、`applied_at=2026-08-19T01:09:56.371Z`，表仅含非空 `lock_key text` 主键且为 0 行。一次性会话随后关闭，未部署专用 Worker，全程未连接、查询或写入 D1。

该迁移是向前兼容的 expand 变更：旧 Worker 忽略新表，新 Worker 在表缺失时显式失败。迁移提交后的回滚策略是继续保留空锁表并回滚 Worker version；不得在仍有新 Worker 流量时删除 `mutation_lock`。

迁移后使用仓库标准 `deploy:dev` 部署当前工作树的 Worker 与 Admin assets。Cloudflare deployment `5e19fc97-32d2-4962-acf0-a53e18891fb9` 将 version `98670000-bd7d-42b0-8264-7bb9aa61fe10`（number `176`）置于 100% dev 流量；版本回读确认绑定 dev KV、共享 Hyperdrive 和 dev R2，未绑定 D1。部署后原数据库兼容性故障链路已恢复：Search、Set 卡牌列表、卡牌 `21986` 详情、21 组市场价和 7 个价格曲线点均返回成功；10 个游戏的 Search、3 个 Pokemon Set，以及 `21986`、`91408`、`488038`、`124595`、`219614` 五张卡的详情/市场价/价格曲线扩展矩阵共 28 个请求均返回 `200` 和有效业务结构。公开分享页也已从 `500` 恢复为含正确卡牌内容与 OG 元数据的 `200`，但独立验收发现 iOS/Android 商店回退 URL 均错误指向 YouTube；修正共享 `admin.app_version.ios` / `admin.app_version.google` 配置并复验前，不得宣称分享业务流完整通过。Admin HTML 引用本次构建的 `index-DNPsU3yc.js`，其 10 个 JS/CSS 资源逐个返回 `200` 且与本地构建 SHA-256 一致；未授权 Admin API 仍返回 `401 UNAUTHORIZED`。该检查不替代真实 PostgreSQL 双连接竞争、dev 登录态多设备或 production 部署验收。

keyset 扫描不是跨批次数据库快照，不能在 dev D1 持续写入时作为最终一致性证明。本次先把 dev deployment `36969b9d-2065-4a42-a1ca-3e742f51ea3d` 的 version `4382c55f-bf0c-4018-b108-675f04f817aa` 切为 100% 维护流量：health 返回 `maintenance/databaseWrites=frozen`，业务请求和 Apple 回调均返回 503，scheduled handler 不执行；冻结后 inbox、cards 与 session 计数连续两次稳定。runner 随后收到 `--confirm-source-write-frozen` 才执行正式迁移。该维护版本是切换门禁，不是最终业务版本；必须由 PostgreSQL 正式版本部署和烟测替换后才能结束维护状态。

2026-08-17 dev 切换检查点中，仓库的目标 dev/prod Wrangler 配置已引用同一个 Hyperdrive ID，环境仍由各自域名、`APP_ENVIRONMENT`、Apple、KV 与 R2 配置区分；Hyperdrive 查询缓存已关闭并回读为 `disabled=true`。当时正式 dev Worker/Admin deployment `6c0697d0-f9bb-423e-8b68-1ab0509e7729`、version `73766f12-d888-4e94-ba2c-f990ef00ec43` 以 100% 流量替换维护版本，完成 health、目录/价格空域、Admin 和未授权边界烟测。2026-08-25 重新回读 production version 后确认其仍绑定 D1，不得再把仓库目标配置解释为现网 prod 已切 PostgreSQL。

较早资源预配检查点（同为 2026-08-17，早于上述 R1）：已通过 Cloudflare 与 PlanetScale 官方集成创建 Hyperdrive 配置，Cloudflare 配置名创建时为 `tcg-cards`，随后按当前 PlanetScale 名称重命名为 `tcg-cards-db`（ID 始终为 `7d71bcd0bcf64e518a23a852ced76d66`）；目标为 PlanetScale `product-kando/tcg-cards-db`（创建时名称为 `product-kando/tcg_cards`）的 `main` 分支、数据库 `postgres`，PlanetScale控制台显示 Postgres version `18.6`。Cloudflare 创建向导返回连接成功，详情页显示 PostgreSQL / PlanetScale，查询缓存保持默认启用。两侧重命名后复核：Hyperdrive 配置 ID、PostgreSQL 连接目标、数据库名、缓存参数和连接上限均未变化，PlanetScale 显示存在 PgBouncer 连接；Cloudflare 详情页的 PlanetScale 跳转链接仍指向已返回 404 的旧名称，这是陈旧的控制台元数据，不应据此重复创建连接或轮换凭据。该较早检查点只完成连接资源预配，当时未添加 binding、执行 schema、迁移、业务写入或部署；其后续状态以上述 R1 检查点为准。

2026-08-17 较早 dev 补充核验（早于本次正式迁移）：`toccards-api-dev` 部署对应提交 `df8e6d7c8ae6695d3f0366b17725abd65615e8d8`，`APP_ENVIRONMENT=development`、`APPLE_IAP_BUNDLE_ID=com.kando.kandoApp.beta`，Apple Root CA 与 App Store Server API Issuer ID/Key ID/Private Key 的 Secret 配置项均存在。远程 dev D1 的 `apple_notification_inbox` 与 `apple_server_notification` 表当时存在，5 分钟通知重试任务正在运行；inbox 当时为空。App Store Connect Sandbox Server URL 已保存为 `https://api-dev.tcgcard.fun/api/v1/apple/notifications/v2`。空 JSON 请求返回 `400 INVALID_REQUEST`，在写 D1 前即被拒绝，只证明请求到达业务校验。该段是切换前历史证据；当前通知运行和数据边界以文档顶部 PostgreSQL-only 约束为准，不得据此重新查询 D1。

2026-08-13 已在远程 dev D1 `cards_basic_information_all_dev` 连续应用 `0025` 至 `0034`，Wrangler 随后返回 `No migrations to apply`；订阅购买链、session grant、通知 inbox、Scan Quota 表及订单事实/汇率/自动续订快照字段均经远程只读 SQL 核对存在。prod 与开发者常用 local 当时仍未执行这些 v1.1 迁移。dev Worker 与 Admin 的手动部署及后续 `dev` push 自动发布均通过，健康接口、Admin HTML 和实际 JS 资源均返回 HTTP 200。上述环境事实是 2026-08-13 历史快照；当前部署与配置状态必须重新查询 Cloudflare 后确认。该快照中 Apple Product ID、Root CA 与 Server API 密钥仍未配置，因此部署成功不代表 Apple 购买闭环可用。

2026-08-12 已使用 Wrangler 4.106.0 在独立 `--local --persist-to` 空库中按顺序执行 `0000` 至 `0033`，34 条迁移全部成功；重复 apply 返回无待执行迁移，关键 v1.1 表及订单事实/汇率快照列均存在。2026-08-13 新增 `0034` 后，Workers 自动化完整迁移链已验证 `0000` 至 `0034` 共 35 条迁移；`0034` 也已在独立 D1 测试中验证历史订单保持空快照及 `0/1/NULL` 约束。Wrangler 实际空库证据仍只到 `0033`，不得改写为已手工执行 `0034`。这批本地与自动化证据在各自验证时不代表开发者常用 local、远程 dev 或 prod 已执行，也不能替代带真实历史数据的预迁移审计；远程 dev 的较晚执行结果以上文 2026-08-13 远程迁移记录为准。

历史检查点（2026-08-13，早于上文同日远程 dev 迁移）：Wrangler 只读列举确认远程 dev 与 prod 当时均待执行 `0025` 至 `0033`；本分支随后新增且当时未远程执行 `0034`，所以该检查点的待执行范围为 `0025` 至 `0034`。两环境 Secret 列表当时均未包含 Apple Root CA 或 App Store Server API 的 Issuer ID、Key ID、Private Key。该检查没有执行迁移、写入 Secret 或部署 Worker；不得把这一历史待迁移状态解释为当前远程 dev 状态。

2026-08-13 又通过 Wrangler 只读导出远程 dev D1，并只在仓库外的本地 SQLite 副本执行 `0025` 至 `0033`。导出基线包含 `0000` 至 `0024` 共 25 条迁移、67 个 `collection_item`、145 条 `collection_item_event`、36 个 Folder、1,053,034 条 `tcg_price`、267,682 条 `cards_all`、167 条 `scan_record`、86 条 session 和 30 条 installation。九条 v1.1 迁移连续成功，单条耗时 9-45 ms，`0031` 为 17 ms；迁移后 `quick_check=ok`、外键检查无错误，核心表行数不变。

`0031` 的真实历史不变量为：67/67 个 Existing Item 的 `performance_start_at` 与 `purchase_price_effective_at` 等于原 `created_at`，67 个 Item 使用同一迁移时刻作为 `performance_history_available_from`；145 条 Event 没有删除或重排，其中与现存 Item 关联的 77 条继承可靠历史起点，其余 68 条已删除 Item 的历史事件保持原样。该结果证明迁移不会把当前 Folder 或属性伪造成早于可靠起点的历史，但 dev 最大 owner 只有 24 条 Event、12 个现存 Item，不代表重度收藏用户规模。

同一副本上，代码实际使用的 Performance Event/价格 SQL 各运行 20 次，中位数分别为 6.71 ms 和 7.72 ms；Admin 订单表为空，空列表与计数 SQL 中位数分别为 6.52 ms 和 6.41 ms。计时包含本地 sqlite3 进程启动，但不包含 Cloudflare 网络、D1 远程调度或 Worker JavaScript 计算。由于缺少有订单样本和大资产 owner，这些结果只能排除当前 dev 小样本下的明显数据库退化，不能宣称满足 App 15 秒或 Admin 普通查询 3 秒的发布门槛。该副本预演完成时远程 dev/prod 均未执行 v1.1 迁移；远程 dev 的后续执行结果见上文 2026-08-13 远程迁移记录。

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

Apple JWS 验签采用官方 `@apple/app-store-server-library`，`apps/workers-api/wrangler.toml` 启用 `nodejs_compat`。Cloudflare 禁止该库的 `jsrsasign` 依赖在 Worker 全局作用域生成随机值，因此验签器与 Server API Client 必须在请求或定时任务处理期间动态加载。dev 已通过真实 Worker 启动校验并部署；production 的实时 deployment 状态需在独立发布任务中重新核验。

## 0028 Apple App Attest Restore

迁移新增 `billing_apple_app_attest_challenge` 与 `billing_apple_app_attest_key`。前者保存 session、purpose、request ID、key ID、JWS 摘要、canonical client data、唯一消费标记和幂等终态；后者保存 Apple 验证后的 P-256 公钥、receipt、环境与 assertion counter。迁移只新增表和索引，不修改现有数据，可先于应用代码部署，不从 UID、installation ID、owner grant 或历史交易回填。

回滚前必须先停用 App Attest challenge/register/restore 三个接口，再导出需要保留的重放审计数据，最后删除两张表。回滚会使新 session 无法通过 Restore 建立服务端 grant，但不影响 StoreKit 本机 Restore 结果。历史 Miniflare D1 测试验证过 session 隔离、单次消费、counter 和 grant 写入；当前运行结构以 PostgreSQL 等价表和测试为准，不再以远程 D1 migration 状态判断完成度。

## 0029 Apple Notification Lifecycle

迁移新增 `apple_notification_inbox`，先保存 Apple 请求 JSON、完整 `signedPayload`、SHA-256、接收时间、处理租约、重试次数和终态。该表允许通知 UUID、类型和环境为空，因此验签或解码失败也不会丢失原文。验签成功后再写现有 `apple_server_notification` 结构化表，并以 `inbox_id` 一对一关联。

`billing_purchase_chain` 新增生命周期、自动续订和下期方案的独立版本字段；`billing_transaction` 新增 `refund_completed_at`，避免以原购买时间冒充退款时间。全部为 nullable 增量列，不回填历史通知或推断历史状态。

兼容性与回滚：

- 旧代码会忽略新表和 nullable 列，迁移可先于新 Worker 上线。
- 新 Worker 必须在迁移后启用，否则接收入口会返回 `PERSISTENCE_FAILED`，不会向 Apple 假报已保存。
- 回滚先移除 App Store Connect 通知 URL或回退 Worker，再导出原始收件箱；SQLite 增量列保留，停用路由后才可删除新索引和收件箱表。
- `correction_required` 是待 Apple Server API 校正，不代表已消费完成；不得据此恢复 entitlement。

历史 Miniflare D1 测试验证过原文留存、幂等建单、乱序保护、失败恢复与环境隔离；当前运行结构以 PostgreSQL 等价表和环境隔离测试为准，不再以远程 D1 migration 状态判断完成度。

## 0032 Billing Order Facts

迁移为 `billing_transaction` 增加 nullable `business_status`、`charge_count` 和 `source_notification_uuid`，并增加订单状态与扣款次数查询索引。历史回填只使用现有确定性事实：退款状态、明确的零金额、Apple `PURCHASE`/`RENEWAL` 原因及同链交易时间；金额为空的历史交易保留空业务事实，不猜测试用、首次付费或恢复类型。迁移不为历史行猜测 `source_notification_uuid`，因此这些回填事实仍是存储层暂存数据，不会自动进入通知真值口径的 Admin 订单。

扣款次数按 `purchase_chain_id + environment` 隔离，通知确认的付费交易按 `purchase_at + transactionId` 排序；试用为 0，退款保留付费序号。Fresh Purchase/Restore 保存暂存交易后可以触发同链重算，但重算 SQL 只更新 `source_notification_uuid IS NOT NULL` 的通知确认记录；建单通知晋升暂存记录后才会占用 Admin 扣款序号。晚到的更早通知确认交易可以确定性修正序号。宽限恢复和重试恢复只由已验签通知及更新前 purchase-chain 状态确定，普通历史回填不猜测。

兼容性与回滚：

- 三列均为 nullable，旧 Worker 忽略新列；迁移可先于新 Worker 上线。
- 新 Admin 依赖这些列，必须在 `0032` 执行后上线；否则订单查询会显式失败。
- 回滚应用时停止读取新列并回退 Admin/Worker，保留新增列和已固化事实；不要删除列或重建旧表，以免丢失扣款序号审计数据。
- 本迁移不会修改、删除或重排 Apple 交易本身，也不会把 UID 变成 Premium owner。

历史 Miniflare D1 测试验证过试用为 0、付费顺序、晚到交易重排、重复交易幂等、退款保序、Restore 暂存写入、精确订单查询、动态选项、XLSX 和 inbox 失败详情；当前新增集成测试进一步保护客户端暂存记录不进入 Admin、通知到达后晋升及扣款序号只统计通知确认记录。当前运行结构以 PostgreSQL 等价表和对应集成测试为准。

无 UID Apple 订单复用现有非空 owner 列，不新增迁移：`original_owner_type='unlinked'` 且 `original_owner_id=''` 是明确的“尚未建立 App 业务关联”状态，不是匿名账号、UID 或 Premium owner。后续可信 Fresh Purchase/Restore 可以只在该状态下补真实 owner；Admin 查询忽略空 owner ID。该规则不回填或猜测历史链，也不创建 session grant。

## 0030 Scan Quota

迁移新增 `scan_quota_request`，同时保存 owner、发起 session、Free/Premium 模式、预占/消费/释放状态、处理租约、重试次数、Scan ID 和最终响应。该表既是额度账本也是请求幂等真源，不另设可与请求记录漂移的累计计数表。

兼容性与数据规则：

- 只新增表和索引，不修改现有 `scan_record`；旧 Worker 会忽略新表。
- 不从现有 `scan_record` 或客户端 `SharedPreferences` 回填历史消费。上线切换时所有 owner 从 10 次开始，避免把无法证明的历史扫描伪装成已结算额度。
- Free `reserved + consumed` 计入终身 10 次；released 与 Premium 请求不消耗 Free quota。
- 回滚先回退新 Worker，保留账本表以免未来重新上线时重置额度。确认永久放弃且已导出审计数据后才可删除表。

历史 Miniflare D1 测试验证过最后 1 次额度的多 session 并发、预占/结算幂等、技术失败释放、Premium 不扣 Free 和租约接管；当前运行结构以 PostgreSQL 等价表和对应集成测试为准。

## 0033 Billing Exchange Rate Snapshot

迁移为 `billing_transaction` 增加 nullable 汇率、base/quote、来源、生效时间、抓取时间、是否使用陈旧缓存、换算版本和舍入模式。新订单使用现有 USD 汇率服务；其口径为 `1 USD = rate × original currency`，因此按 `amount_usd_micros = round(amount_micros / rate)` 换算。USD 使用恒等 rate 1；其他币种使用 `frankfurter.dev` 已验证快照，版本为 `usd_divide_rate_v1`，正数 micros 采用 half-away-from-zero 舍入。

兼容性与回滚：

- 全部为 nullable 增量列，旧 Worker 会忽略，迁移可先于新 Worker 上线。
- 汇率或原始金额不可证明时订单仍入库，USD 金额与快照保持空；不得写 0 或猜测汇率。
- 历史订单不猜测回填。后续补算只允许填充当前为空的 USD 与快照列，不覆盖已经固化的订单事实。
- 历史 D1 回滚方案是停止读写新字段并保留增量列供审计；当前 PostgreSQL 运行时不得回退 D1，回滚必须基于 PostgreSQL 备份与向前修复另行设计。

当前汇率换算、USD 恒等和无汇率非阻断已有确定性测试；运行结构以 PostgreSQL 等价列为准，不再以远程 D1 migration 状态判断完成度。

## 0034 Billing Auto-Renew Snapshot

迁移为 `billing_transaction` 增加 nullable `auto_renew_snapshot`，只允许 `0/1/NULL`。Admin 的自动续订展示、筛选和 XLSX 均读取订单快照，不再读取 `billing_purchase_chain.auto_renew` 当前值，避免后续关闭或恢复自动续订改写历史订单显示。

- Notifications V2 建单时，只有已验签 `signedRenewalInfo.autoRenewStatus` 才为订阅订单写 `0/1`；Lifetime 按产品规则固定写 `0`。
- Fresh Purchase / Restore 的 signed transaction 不包含可证明的 `autoRenewStatus`，订阅订单写 `NULL`；Admin 显示 `--`，不以当前链路状态猜测。
- 历史订单不回填。当前 purchase chain 的自动续订值不是历史订单事件快照，不能反向复制。
- 该列为 nullable 增量，旧 Worker 会忽略；新 Admin/Worker 依赖该列，必须先迁移再上线。回滚应用时停止读写新列并回退 Worker，保留已固化快照。

`0034` 已通过独立 D1 迁移测试和 `0000-0034` 自动化完整迁移链；这是历史 schema 证据，当前运行结构以 PostgreSQL 等价列为准，不再执行或追踪远程 D1 migration。

## PostgreSQL 0007 Billing Refund Status

`0007_billing_refund_status.sql` 为 `billing_transaction` 增加 nullable `business_status_before_refund`。该列只保存 Apple `REFUND` 修改订单前的业务状态，使后续 `REFUND_REVERSED` 经 Apple Server API 校正为 active 时可以恢复原订单状态，而不是把所有撤销退款猜成统一状态。

- 不回填历史退款：既有 `business_status='refunded'` 行的退款前状态无法从现有列可靠证明，保持 `NULL`。
- 重复 `REFUND` 不覆盖已经保存的退款前状态；未证明 active 的 `REFUND_REVERSED` 不清除退款事实。
- 列为 nullable 向后兼容扩展；旧 Worker 会忽略，应用代码回滚时保留该列。
- 新 Worker 的退款与校正 SQL 依赖该列，必须先应用目标 PostgreSQL `0007` 再部署。2026-08-19 已通过仅绑定共享 Hyperdrive 的一次性 Wrangler remote preview 应用 `0007`，事务外复核确认目标列存在，幂等复跑返回 `alreadyApplied`；一次性 preview 随后关闭。同日按“先迁移、后应用”的顺序完成 dev Worker 与 Admin assets 部署；本次发布验收检查点的 Cloudflare version `ce9ee177-27a0-49fe-8e87-0a0f4414b620` 当时承载 100% dev 流量，回读确认使用共享 Hyperdrive 且无 D1 binding。该 Schema 当前直接影响 dev，并在 v1.1 prod 切换后成为两环境共享 Schema；不影响仍运行 D1 的现网 prod。

PostgreSQL migration manifest 测试保护 `0007` 的顺序与内容；远程 Schema 状态以上述实际迁移与复核记录为准。

## PostgreSQL 0008 Collection Item Grading Identity

`0008_collection_item_grading_identity.sql` 删除旧的 `uq_collection_item_folder_card_finish_language`，并创建 `uq_collection_item_folder_card_variant`。新唯一键为 `owner_type + owner_id + folder_id + card_ref + finish + language + grader + condition + grade`，与 Quick Collect、完整 Collection Item Create 和 Scan Confirm 的服务端重复查询一致。Raw 使用 condition 区分品相，评级卡使用 grader 与 grade 区分机构和分数。

- 新索引是在旧唯一键后增加评级维度，只放宽可共存的数据，不修改或回填现有 Item；旧索引下合法的数据一定满足新索引。
- 发布顺序为先应用共享 PostgreSQL `0008`，再部署使用新重复查询的 Worker。旧 Worker 在新索引下仍以旧查询拒绝多评级共存，不会写入超出旧应用语义的数据；新 Worker 若先于 migration 部署，旧索引仍会把不同评级写入拒绝为重复，因此功能不会完整生效。
- 应用代码回滚时可以保留新索引，旧 Worker 会恢复旧的查询行为。若必须恢复旧索引，必须先停止相关写入，并检查、导出和处理同一 `owner/folder/card/finish/language` 下已经共存的多评级 Item；未经单独的数据处理授权不得删除或合并这些记录，否则旧索引可能无法重建。
- 当前远程执行 `0008` 直接改变 dev 使用及 v1.1 prod 目标使用的 PostgreSQL Schema；现网 prod 仍运行 D1，因此在 prod 切换前不读取该约束。

2026-08-20 经用户明确授权，通过只绑定共享 Hyperdrive `7d71bcd0bcf64e518a23a852ced76d66` 的一次性 Wrangler remote preview 执行 `0008`；该 preview 没有 D1、KV、R2、路由或定时任务。执行前目标为 `postgres/public`、PostgreSQL 18.6，ledger 精确包含 `0000-0007`，旧索引存在、新索引不存在，84 条 Collection Item 按新完整身份计算的冲突组为 0。迁移在 `pg_advisory_xact_lock(hashtext('kando-postgres-schema'))` 保护的单个事务内执行并写入 ledger，checksum 为 `7d6edd0e996dabbb1f571790d13b9ef20b0a44ae3f3c7799d825b657df22e1f2`，`applied_at=2026-08-20T06:20:55.020Z`。

事务外复核确认旧索引已不存在，新 `uq_collection_item_folder_card_variant` 的实际定义包含 `owner_type`、`owner_id`、`folder_id`、`card_ref`、`finish`、`language`、`grader`、`condition` 和 `grade`；Collection Item 仍为 84 条且冲突组为 0。幂等复跑返回 `alreadyApplied` 且 checksum 一致，preview 随后关闭并删除本地临时执行器。本次操作没有主动部署 Worker；实时 deployment 状态需在发布任务中单独核验。

## PostgreSQL 0009 Apple Notification App Bundle Scope

`0009_apple_notification_app_bundle.sql` 为 `apple_notification_inbox` 增加非空 `app_bundle_id`。迁移前架构只有 beta Bundle 会产生 Sandbox inbox，因此既有 `Sandbox` 行确定性回填为 `com.kando.kandoApp.beta`；既有 `Production` 行回填为 `com.cardai.tcg`。去重约束改为 `app_bundle_id + environment + payload_sha256`，processing 索引在 environment 前增加 `app_bundle_id`，使 dev 与 production TestFlight 共用 Sandbox 数据库值时仍不能互抢通知租约。

- 兼容性：migration 通过 `trg_legacy_apple_notification_app_bundle` 为尚未升级的 PostgreSQL Worker 补齐其唯一可能产生的 Bundle，避免 `NOT NULL` 在切换窗口打断 dev 通知持久化；新 Worker始终显式写 Bundle，production TestFlight Sandbox 不依赖该 trigger。必须先应用 PostgreSQL `0009`，再升级 dev Worker并完成验证；prod 在完成生产 D1 数据迁移后直接切换到包含该修复的 v1.1 Worker。dev 新 Worker与 prod v1.1 切换都完成前不得设置 production App Sandbox URL。
- 回滚：应用代码可回退并保留新列、约束和索引。不得在已接收 production Bundle Sandbox 通知后恢复旧 `(environment, payload_sha256)` 唯一键，否则可能无法重建且会重新引入跨 App 抢租约风险。
- 环境影响：远程执行只影响 dev 使用及未来 v1.1 prod 将使用的 PostgreSQL Schema，不影响仍绑定 D1 的现网 prod；未修改 D1。

2026-08-25 经用户明确授权，在 PlanetScale `product-kando/tcg-cards-db` 的 `main`、数据库 `postgres`、schema `public` 执行 `0009`。执行前 ledger 精确包含 `0000-0008`，`app_bundle_id` 不存在，旧唯一约束与 processing 索引定义匹配 migration 预期；251 条 inbox 全部为 `Sandbox`，非法 environment 与 `(environment, payload_sha256)` 冲突均为 0。PlanetScale Web Console 角色不是表 owner，首次 DDL 返回 `must be owner of table apple_notification_inbox`；事务随后显式回滚并复核列数与 ledger 均为 0，没有半完成状态。正式执行改用只绑定目标 Hyperdrive 的 Wrangler 4.125 remote preview，连接用户与表 owner 一致；migration 在 `pg_advisory_xact_lock(hashtext('kando-postgres-schema'))` 保护的单事务内执行并写入 ledger，规范化 LF checksum 为 `4d43602cf70dbeeab9978da1c773953d8b382bd2afff5e5579d57f3d9ac8fc11`，`applied_at=2026-08-25T08:08:35.877Z`。事务内与独立 PlanetScale Console 连接复核均确认：`app_bundle_id` 为非空列，253 条 inbox 全部归属 `com.kando.kandoApp.beta:Sandbox`，NULL/Bundle mismatch 为 0，legacy trigger、新三字段唯一约束和五字段 processing 索引均精确存在。preview 随后停止，本地临时执行文件已删除；未部署 dev/prod Worker、未修改 prod D1 或 App Store Connect URL。

## PostgreSQL 0010 Scan Record Environment

`0010_scan_record_environment.sql` 为 `scan_record` 增加非空 `environment`，只允许 `development/production`，并增加 `environment + created_at + id` 查询索引。现有 PostgreSQL scan 记录来自已确认完成的 dev D1 迁移，因此确定性回填为 `development`；新扫描由可信 Worker `APP_ENVIRONMENT` 显式写入，客户端请求不能指定环境。迁移保留数据库默认值 `development`，只用于迁移后、部署前兼容仍未传列的旧 dev Worker；新 Worker 缺少 `APP_ENVIRONMENT` 时释放已排队额度并返回 `503`，不能依赖该默认值掩盖配置错误。

- 兼容与顺序：先执行共享 PostgreSQL `0010`，再部署依赖该列的 Worker/Admin。旧 Worker 不读取该列，可以在 migration 后继续运行；新 Worker 在列不存在时必须显式失败，不能先部署代码。
- dev 迁移工具仍受 `--confirm-dev` 和固定 dev D1 binding 保护，`scan_record.targetValues.environment=development`。cutover 复核要求 development 行数等于 dev D1 源计数、production 为 0 且不存在未分类行。
- prod 边界：现网 prod 仍运行 v1.0 D1。未来 prod 数据迁移必须使用独立受控流程，把生产历史 scan 显式写为 `production`；prod Worker 必须通过 `APP_ENVIRONMENT=production` 显式写入，不得复用 dev-only runner 或依赖数据库默认值。
- 回滚：应用代码可回退并保留列、约束和索引。若要物理删除列，必须先回退所有读取/写入，再使用新的递增 PostgreSQL migration；不得修改已执行的 `0010`。

2026-08-31 经用户明确授权部署 dev，先执行 `0010` 再发布依赖它的 Worker/Admin。首次使用固定 dev D1 配置启动 schema-only remote preview 时，Cloudflare 在 preview 启动阶段返回 D1 database not found（code `10181`）；该次尚未连接或执行 PostgreSQL DDL。随后改用只绑定共享 Hyperdrive `7d71bcd0bcf64e518a23a852ced76d66` 的一次性 Wrangler remote preview，未绑定 D1、KV、R2、路由或定时任务。只读预检确认目标为 `postgres/public`、PostgreSQL 18.6，ledger 精确包含 `0000-0009`，环境列、约束和索引均不存在；migration 在 advisory lock 保护的单事务中只应用 `0010`。事务外复核确认 checksum 为 `6ef480092683760fc4f0a50b221ccea35fa58c3ad23c1ebfca30e4272bfde99f`、`applied_at=2026-08-31T08:28:04.491Z`，列为 `text NOT NULL`，约束已验证，索引存在，467 条扫描记录全部为 `development`。preview 随后正常关闭，临时配置已删除。之后部署 dev Worker/Admin version `be0a5923-8c81-485c-b8a3-b0a982fca912`；未执行 prod 部署、prod D1 迁移或生产写入。
