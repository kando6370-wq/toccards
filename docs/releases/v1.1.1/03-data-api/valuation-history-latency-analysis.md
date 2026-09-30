# Portfolio 估值历史：90 天以上慢请求链路调研

## 0. 范围、证据等级与结论

- 日期：2026-09-30；代码为 `dev@d96042d`，未合并 main。仅调查 `GET /api/v1/portfolio/valuation-history` 的 Flutter 入口、鉴权、价格读取与估值计算，不修改业务实现、SQL、索引或部署。
- 已用 Git 对比确认本次关注的 portfolio、owner-auth、premium-access、postgres-price-store、PostgreSQL 适配器与生产后端基线 `7868f4c` 无差异；当前生产版本仍为 `1b806fe1-7516-4749-ac87-77c3c6c29deb` / 100%。不能把 dev 独有的扫描并行当成本接口变化。
- 结论分为 **代码明确体现**、**隔离样本实测**、**生产待确认**。本轮没有真实慢请求的 owner、folder、request ID 或完整计时，也没有生产数据库 EXPLAIN；不能给出生产根因已最终证实或 P95 已量化的结论。
- 核心发现：**90→91 的专属分支是一次 Premium 权益 SQL；90→365 的主要放大点是全部候选价格序列的长区间月度 JSON 读取与处理，并伴随串行分块等待。** 当前逐日估值已有二分查找和请求内缓存，不是每天重做全部 JSON.parse。

## 1. 业务总览与用户侧主线

该接口为 Home 的 Folder 资产市值历史提供日线、当前估值及 Most Valuable，不是购买成本/盈亏的 Performance 接口，也不使用外部实时行情 API。

Flutter 首次 Home `loadCoreDashboard()` 默认请求 `days=90`（不传 folder_id，返回当前 owner 全部 Folder）。1D/7D/15D/1M/3M 从已经返回的 90 天序列本地截取，切换这些档位不一定产生新请求。首次选择某 Folder 的 1Y 才调用 `days=365&folder_id=<当前Folder>`，并设置 `X-Local-Premium-State: verified`、单次 25 秒等待；请求进行中去重，成功后在当前 Home 状态保存该 Folder 的 1Y 数据。

若首次请求收到 `ENTITLEMENT_SYNC_REQUIRED`，客户端先修复权益，再重发一次。因而“图表切换很慢”可能包括网络、权益修复和第二次请求，必须与单条 API HTTP 耗时区分；不能把本地已缓存的 3M 点击时间当作一次 90D API 时间。

证据：`home_repository.dart:47–60,90–100,162–197`；`home_controller.dart:883–1012`；`portfolio_api_client.dart:863–880`。

## 2. 角色、权限与 90 天分界

实际查询参数名为 `days`，不是 `day`。默认 90、最大 365；非法/非正值回退默认，超过上限截为 365。

| 条件 | 行为 | 代价/边界 |
|---|---|---|
| 所有请求 | 验证 access token，查询 live session 与有效 owner | 正常授权路径 1 次 SQL |
| `days<=90` | 不检查 Premium，Free 可访问自己资产 | 仍需账号与 Folder 归属验证 |
| `days>90` | 串行执行当前 session 的 grant 与 purchase chain JOIN | 正常生产配置下额外 1 次 SQL；不是调用 Apple 验证服务 |
| 无服务端 grant，本机 verified | 409 / ENTITLEMENT_SYNC_REQUIRED | 本机头不能自行授权；可能触发客户端修复再请求 |
| 无 grant、无本机 verified | 403 / PREMIUM_REQUIRED | 提前返回，不执行历史估值 |
| 指定他人/不存在 Folder | 404；空 folder_id 为 422 | 不得用扩大查询范围绕过 owner 隔离 |

Premium SQL 有 `(session_id, entitlement_id, status, expires_at)` 索引，并 JOIN purchase chain，参数包含本次 `now.toISOString()`。2026-09-30 09:39 回读 Hyperdrive 查询缓存仍开启；但当前毫秒时间不断变化，不能假设该鉴权查询能复用跨请求的相同参数缓存。实际查询计划与缓存命中率未测，不把这一个额外查询直接断言为生产数秒慢请求的根因。

## 3. 服务端链路与查询数量

正常成功路径：

`Cloudflare fetch → 每请求 PostgreSQL 适配器 → Hono/CORS/Request-ID → authenticateOwner → [days>90: premiumAccess] → findFolder/listFolders → 事件基线与窗口 → 并行(价格链路, 当前卡牌信息) → 按日重放与估值 → Most Valuable → JSON`。

价格链路内部仍串行：

`loadPublishedPriceRows（每 40 个 card_ref 分块） → loadPriceHistoryBySeries（每 100 个 series_id 分块） → 月度 JSON 解析/校验/合并/排序 → 重新 JSON.stringify → 匹配实际估值序列`。

具体顺序：

1. 事件 SQL 的 `scoped_events` 先按 owner 读取并计算每 item 的最早事件时间；再找区间前的最新基线及区间内事件，最后收敛与指定 Folder 有关的 item。区间变长可能纳入更多已删除/已转移卡牌，扩大后续 card_ref 集合。该 CTE 涉及整个 owner 的历史窗口计算，不等同于索引直接只读本 Folder 的最近 N 天；实际代价需要执行计划证实。
2. 对历史涉及的 card_ref 加载全部 active/published/USD 价格行。这里没有先按收藏的 Raw/PSA、品相、语言、finish 或固定 price_series_id 限定序列，也没有传 `rawOnly`。
3. 对这些全部 series_id 加载日期窗口内的月度历史，以及窗口之前最近一月的基线；价格批次/发布可见性检查必须保留。
4. `loadCards` 只为当前持仓取元数据（每 80 个 card_ref），已经与价格读取并行。不是串行逐卡 N+1 目录查询。
5. 把历史转成 SkuRow 后，才通过 matchingPrice 筛选真正用于估值的序列。每一天重放 item 状态并求和，最后生成每 Folder 的 Most Valuable Top 3。

设历史涉及 C 个不同卡牌、已发布候选 S 条价格序列、当前持仓 Ccur 个不同卡牌，且未触发行数上限拆分，则 SQL 数约为：

`3 + I(days>90) + ceil(C/40) + ceil(S/100) + ceil(Ccur/80)`。

其中 3 为 session、Folder、事件；这是总 SQL 数，不是全部串行等待轮数，目录链路与价格链路有重叠。价格的两个分块循环自身是 `await` 顺序执行；连接池 max=5 不会自动把循环改成并发。40 卡当前价超过 1,000 行还会递归二分，可能增加额外查询。

## 4. 核心数据实体、读取量和计算规则

| 实体/表 | 作用 | 已有约束 |
|---|---|---|
| session + user/anonymous_account | 身份与 live owner | 失效/撤销不能继续授权 |
| billing_session_entitlement_grant + billing_purchase_chain | 当前 session Premium 权益 | 商品、环境、到期、撤销状态共同验证 |
| portfolio_folder + collection_item_event | Folder 范围及历史持仓事件 | 保留区间前基线；事件最多 10,000，超过显式失败 |
| current_price_pointer + price_ingest_batch | 仅允许已发布来源的行情 | 不能混入 staged/未发布批次 |
| price_series + price_current_snapshot | 当前候选价格序列及快照基线 | active/USD；Raw/graded 多序列可能对应同一卡牌 |
| price_history_month | 每序列每月 JSONB 点集 | 以 month_start 分区，主键 (series_id, month_start)；每 100 条序列最多读取 1,600 月行，超限显式失败 |
| cards_all | 当前持仓名称、卡号等 | 与价格独立并行读取 |

日估值 = 当日每个有效持仓的 `quantity × 当日或此前最近市场价` 求和，按金额精度处理。不将不存在的历史价填成未来价格；有 item 但缺市场价与空 Folder 的 UI 语义不同，合法零价仍是可用价。

当前 loadSkus 的历史起点为 `endDate - days - 30`，所以 90D 实际从约 120 天前取，365D 从约 395 天前取；再加整月边界及基线月。最终响应每 Folder 为 `days+1` 个点。Most Valuable 还会使用当前 canonical price，而历史估值可能绑定旧 price_series_id，因此后续不能简单把所有其他序列删掉。

已有优化必须保留：item 事件日期二分查找、价格日期二分查找、按事件对象缓存序列匹配、按历史值缓存解析/日期结果、只读取当前卡牌元数据。它们均是单请求缓存，不是跨 HTTP 请求的 valuation 结果缓存。

## 5. 隔离对照实测与慢点判断

### 5.1 方法及边界

Windows / Node v22.20.0；固定逻辑日期 2026-09-30，一个 Folder，每张卡一条 2025 年以来持仓事件。每卡 1 或 20 条候选序列，只有其中一条 Raw 用于估值；完整合成月度点从 2025-07 到 2026-09。调用**当前未修改的业务函数**，数据库替身按 SQL/参数返回受控行集，没有执行生产 PostgreSQL、Hyperdrive 或真实网络。

每个样本热身后重复 3 次取本机中位数；额外在忽略目录编译副本中加入阶段计时，不修改 src。以下时间只说明代码处理相同结构数据的相对增长，**不是生产延迟/P50/P95，也不代表真实用户每卡有 20 个序列**。

### 5.2 价格序列读取放大

| 合成规模 | days | 历史 JSON 字节（十进制 MB） | helper SQL 数 / 历史分块数 | 本机 helper 中位耗时 |
|---|---:|---:|---:|---:|
| 20 卡 × 20 序列 | 90 | 1.96 MB | 7 / 4 | 约 105 ms |
| 20 卡 × 20 序列 | 91 | 1.96 MB | 7 / 4 | 约 105 ms |
| 20 卡 × 20 序列 | 365 | 5.86 MB | 7 / 4 | 约 308 ms |
| 80 卡 × 20 序列 | 90 | 7.84 MB | 20 / 16 | 约 434 ms |
| 80 卡 × 20 序列 | 91 | 7.84 MB | 20 / 16 | 约 415 ms |
| 80 卡 × 20 序列 | 365 | 23.42 MB | 20 / 16 | 约 1,269 ms |

80 卡的 365D 样本返回 24,000 条月历史行（分布于 16 个合法分块），但单 Folder 响应只有约 15.9 KB。另一个分阶段运行中，365D 总耗时中位约 1,206 ms，其中价格+目录处理约 1,181 ms，逐日重放约 23 ms；各阶段独立中位数不要求严格相加。

**支持的结论**：在多序列场景，读取/解析不使用的序列会明显放大工作量；应优先检查历史价格读取，而非首先重写已经缓存过的逐日循环。**不支持的结论**：不能据此断言生产当前就是 23 MB、1.2 秒或 SQL 一定很慢。

### 5.3 精确阈值 90→91

通过真实路由和本地签名测试 Token、数据库替身核对 10 卡 × 1 序列：days=90 正常请求执行 6 次 SQL，91/365 执行 7 次；新增的就是 Premium grant JOIN。固定日期下 90/91 落在同样的月范围，历史月行都为 50，helper 耗时相近。

探针另外人为给每个查询加入 20 ms 延迟，只用于展示 session→grant→Folder→events 的串行依赖，不将这些模拟路由时间用于生产结论。若真实 `days=91` 就明显比 90 慢，而持仓与月数据量相同，应优先实测 grant 查询及缓存/网络等待；若主要是从已缓存的 3M 切 1Y 慢，则先区分首次网络请求，再看长历史读取放大。

## 6. 影响面与后续优化方向（本轮未实施）

| 顺序 | 建议 | 必须保护的契约 |
|---|---|---|
| 先测量 | 对同一 owner、Folder、session 的 90/91/365 做冷暖对照，分解 session、grant、Folder、event SQL、当前价、历史分块、解析、重放和响应序列化 | 同时记录 C、S、月行数、历史字节数和 HTTP 状态；不采集 Token，不把 403/409 视为成功业务样本 |
| 优先收敛读取量 | 在加载全部长期月历史前，收敛到历史估值和当前 Most Valuable 实际需要的序列集合 | 保存的 price_series_id 稳定性、不可用时不猜测回退、canonical 排名、Raw/graded 和 qualifier 选择均不变；先设计响应等价回归 |
| 核对日期上界 | 检查是否可按 chart 与 30D 排名的区间并集取价，而非无条件 days+30 | 保留 carry-forward 基线月、历史开始前无价和 30D 对照；不能简单截掉基线 |
| 再处理串行等待 | 在读取量已受控后，评估历史分块的有界并发 | 尊重现有连接池和数据库承载，不直接调大连接池或无界 Promise.all |
| 以计划为依据优化事件 SQL | 检查窗口函数/CTE、排序、分区裁剪、基线子查询的实际 EXPLAIN | Folder 转移/删除/最早加入时间不可因过早 folder 条件过滤而失真，不猜测性加索引 |
| 精确阈值的独立分支 | 若 grant SQL 被证实占主要时间，再评估减少鉴权串行往返 | 不删除 >90 的 Premium 门禁，不信任本机 verified，不用长 TTL 私有数据缓存掩盖授权问题 |

loadSkus、matchingPrice、loadCards 同时被 collection-dashboard 与 performance 使用；任何后续共享实现修改都需验证这些调用方。Flutter 此接口调用由共享 Dart 实现承载，两端相同；不能只改一端或靠延长 25 秒超时“解决”慢请求。

## 7. 术语

- owner：资产归属主体，正式或匿名账号；session 是当前登录会话，Premium 不等于同 UID 所有 session 自动继承。
- series/SKU：卡牌的行情序列，可能按来源、评级、品相、语言及版本区分；同 card_ref 并不只有一条行情。
- baseline/carry-forward：请求窗口开始前的最近有效状态/价格，用于计算窗口初值，不是人为生成历史。
- valuation 与 performance：前者是历史资产市值；后者涉及投入、现金流、收益，不能混用公式。
- Worker CPU 与 wall：计算时间与包括网络等待的墙钟时间；本机 Node 样本不能代替生产两项指标。

## 8. 证据索引与验证结果

主要代码：

- `apps/flutter-app/lib/features/home/home_repository.dart:47,94,162`；`home_controller.dart:883,990`；`shared/portfolio/portfolio_api_client.dart:863`。
- `apps/workers-api/src/portfolio/routes.ts:389–429`；`owner-auth.ts:authenticateOwner`；`entitlements/premium-access.ts:20–65`。
- `apps/workers-api/src/portfolio/valuation-history.ts:102–260,268–328,339–357,494–599,613–660`。
- `apps/workers-api/src/data-source/postgres-price-store.ts:36–205,207–260`；`db/postgres-database.ts:createPostgresDatabase/PostgresStatement`。
- `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql` 的 event 与 session grant 索引；`0001_price_domain.sql` 的 price-series 索引与月历史分区/主键。

本轮实际执行：

- `pnpm --filter @kando/workers-api exec vitest run src/portfolio/valuation-history.test.ts src/portfolio/performance-premium.integration.test.ts src/entitlements/premium-access.test.ts`：退出 0，3 文件/27 项通过、无跳过。它们覆盖语义与权限，不是生产性能压测。
- 两个本地 Node 探针均退出 0；无计时改写探针与仅在临时编译副本加计时的阶段探针，都放在忽略目录 `apps/workers-api/.wrangler/valuation-history-research-20260930`。原始样本结果不放入 docs；文档仅记录方法、结论及汇总。
- 生产 deployments 与 Hyperdrive GET 成功：Worker 仍为上述版本，查询缓存 disabled=false、origin_connection_limit=100，modified_on 仍为 2026-09-28。
- 对 2026-09-29 00:00（UTC+8）到 2026-09-30 本次调查时刻，限定生产服务与本接口路径、最多 25 条的临时 Telemetry 查询返回 **HTTP 403 / code 10000**；没有取得实际样本。没有扩大 OAuth 权限、绕过鉴权或伪造已取得日志。

官方语义参考：[Hyperdrive 查询缓存](https://developers.cloudflare.com/hyperdrive/configuration/query-caching/)、[Hyperdrive 使用与统计](https://developers.cloudflare.com/hyperdrive/observability/metrics/)、[PostgreSQL WITH/CTE](https://www.postgresql.org/docs/18/queries-with.html)。生产计划和缓存命中仍需实际测量，不能由文档推断已经发生。

## 9. 待确认问题与下一步验收

1. 慢的是原始 HTTP 请求还是点击 1Y 到图表显示？实际参数是 days=91、180 还是 365，是否指定 folder_id？返回 200 还是先 409 再重试？
2. 请提供不含 Token 的 URL 参数、耗时、发生时间或 X-Request-ID；再核对该 owner 的历史事件数、card_ref 数、候选 series 数。不能仅用当前 Folder item_count 估计历史工作量。
3. 需取得获授权的性能样本或日志读取能力，测量 grant、事件/价格各阶段 wall/CPU/行数/字节数；生产数据库执行计划仅在确认目标和受限只读方案后补验。
4. 本轮未跑生产 SQL/EXPLAIN、真实登录态请求、跨地域/冷暖缓存压测或完整 Worker 测试，也未修改业务源码、配置、迁移、Git 分支或部署。后续优化需独立确认范围，按响应等价与权限回归验证，而不是以“更快”代替正确性。


### 2026-09-30 10:00：生产实测前置检查

用户明确要求必须测试 prod，不接受以内网 dev 耗时替代。本轮计划使用同一个真实 Premium session/Folder，对 days=90/91/180/365 做低频串行 GET 对照；不新建账号、伪造 Token、改权益或执行业务写入。

目前未取得可用的生产 App Premium 会话。已核查常见显式测试凭据环境变量，均未设置；已检查仓库测试工具入口，未发现可直接使用的生产业务会话。浏览器连接初始化失败，无法从已有登录页面执行实际操作；没有扫描浏览器凭据库、读取无关历史文件或利用服务端签名密钥冒充用户。Cloudflare 管理授权不能替代 App live-session/Premium 授权。

仅执行 3 次生产公开健康 GET（每次间隔 1 秒，最大等待 15 秒），均为 HTTP 200。通过本机 curl 分别建立 HTTPS 请求，总耗时约 1.181 s、0.857 s、0.871 s，其中 TLS 完成时间约 0.902 s、0.585 s、0.579 s；这些值包含开发机网络与建连，**不是 valuation-history 耗时，也不证明生产业务查询已测**。没有发起无效 Token 的 90/365 对比或将 401/403 当作正常样本。

要执行受保护接口，需要用户提供获授权的生产 Premium 会话请求（建议将一条成功的 365D 请求保存为仓库外本地 cURL 文本，提供路径，不在报告或聊天中公开 Token）。拿到后再进行业务对照；当前生产 valuation-history 实测状态仍为“认证前置未满足”，不是通过。
