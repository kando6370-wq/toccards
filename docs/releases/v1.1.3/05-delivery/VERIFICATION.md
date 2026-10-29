# v1.1.3 实际验证记录

启用日期：2026-10-26（Asia/Shanghai）。

本文件只记录 v1.1.3 启用后的代码、配置、数据、构建、部署和业务验收结果。创建版本目录本身没有修改业务代码、数据库、远程配置或运行环境，也不构成新的验证通过。

本版本初始运行基线见 [v1.1.2 生产收尾记录](../../v1.1.2/05-delivery/VERIFICATION.md#prod-app-1-0-6-monthly-admission-20261026)。以下按时间分别记录本地增量、实际部署与运行验证；历史记录不替代当前远端状态回读。

<a id="dev-numeric-search-deployment-20261029"></a>
## Linux dev 数值排序合并发布（2026-10-29 11:37–11:54）

- Git 与范围：按用户授权将 `codex/dev-1.0.7scan@695ee6597547c8bb5d4d6aad19d790196c99bb80` 合入 `dev@afca10dcf4557bfee87ef53444a4d8d1eff7b618`，生成并推送合并提交 `867c6fd84ddaacdaf7523402b0ab8bd70feb56ab`，远端回读一致。唯一冲突文件为 Cards／Sets 说明文档，保留昨天的 `0016` 部署事实与今天的新规则；API、客户端与测试代码均与来源分支一致。本轮只发布数值排序和 Cards 缓存 `v16`，没有 schema、migration、部署脚本、Admin 业务或 Flutter 制品变更。
- 合并后检查：5 个 Workers 定向文件／57 项、根 `pnpm type-check` 与 `pnpm lint` 通过；完整旧 App 源码合同为服务端 8 项、固定 1.0.4／1.0.5 各 24 项通过，证据目录 `.dart_tool/app-compatibility/run-B17Z6Q/`。干净合并提交的 `deploy:dry-run:dev` 完成 API／Admin 构建与 bundle 3／3；watcher 独立通过 Workers 11 文件／116 项、Node 预检／静态服务 13／13 及 bundle 3／3。
- 发布与备份：推送后既有 watcher 自动发布 `branch-dev-867c6fd84dda-20261029114956`，未并发手工发布或设置强制重发。发布前后实际预检 `pendingMigrations=[]`，原 17 项 `0000–0016` 均显示已应用并跳过，migration 容器退出 0，无新迁移登记。发布前 custom-format 备份 `toccards-test-20261029-114959-before-branch-dev-867c6fd84dda-20261029114956.dump` 为 1,136,738,709 字节，独立 `pg_restore --list` 读取 336 个非注释条目，未做恢复演练。
- 运行与产物：11:54 独立回读 `current`、manifest、`shared/current-release`、watcher `last-seen`／`last-deployed` 指向本次合并版本，失败标记不存在。API／DB healthy、Web running，原 PostgreSQL 数据卷与私有 `.env` 完整哈希保持。运行 API、Linux release 与同提交本地构建 SHA-256 均为 `336dbb68104cc6f7ed28740eb1f3476847a0ba36d769c09dec9ef32861971ba2`；Admin 11 个 HTML／JS／CSS 的 release、容器和 HTTP 原始字节全部一致。ledger 仍为 17 项／最新 `0016`，既有三个创建时间索引 valid/ready，旧更新时间排序索引仍不存在，`updated_at` 字段保留。
- 排序与 HTTP：默认 Pokemon Cards 前两页共 80 条、Set `2282` 内卡牌前两页共 80 条，都与数据库按创建时间／纯数字 ID 数值／原字符串 ID 的顺序逐项一致；Cards 两页无重复。Sets 从第 1 页按 40 条加载至第 17 页，共 663 条，与数据库按纯数字 `set_id` 数值降序、原字符串降序的完整结果一致且无重复；该真实 Pokemon 样本中的 Set ID 均为纯数字，混合非数字／前导零／超 bigint 场景仍以本地 PostgreSQL 回归为证据。开发机 health 和 Admin 返回 200，未登录 auth/me 与 Admin 苹果通知 options 返回 401。
- 边界：prod／Cloudflare、Secret、watcher 配置和业务数据未主动改写；公开 GET 仅按既有逻辑回填 dev 内存缓存。未进行真实登录态 Admin、真实图片识别、真机扫描、备份恢复、完整 Workers／Flutter 测试或生产性能验收。既有数值排序的额外 Sort 成本仍存在，不把本轮功能验收扩展为性能提升；此前 81.133 ms／1.768 ms 等只读计划样本保持其单次证据边界。后续仅记录本文档的 dev 提交不强制重建，运行提交与 Git 文档提交分别说明。

<a id="dev-cards-index-deployment-20261028"></a>
## Linux dev 合并发布与 Cards 索引替换（2026-10-28 18:03–18:21）

- Git 与范围：按用户授权将 `codex/dev-1.0.7scan@6a1f053dfc73a299f786ef71a9d77e00b6f07282` 合入 `dev@5cc5ae0ab204af287065a28071dc585eb50e4cad`，合并提交 `b9702b81c4cdf13ad5b420994f70db273a6cd2df` 已推送 `github/dev` 并回读一致。唯一冲突为本验证文件顶部的独立记录，保留两边历史；业务代码无冲突。发布包含 Cards 排序／缓存／索引和 Admin 苹果通知 SKU 下拉筛选，不包含生产或 Flutter 制品发布。
- 合并后验证：Workers 定向 5 文件／58 项、Admin 80／80、根 `pnpm type-check` 和 `pnpm lint` 通过；兼容源码合同为服务端 8 项、固定 App 1.0.4／1.0.5 各 24 项，证据位于忽略目录 `.dart_tool/app-compatibility/run-5ZTd5C/`。干净 dev 的 `deploy:dry-run:dev` 完成 Admin 和 Linux API 构建，bundle 测试 3／3；watcher 随后独立通过 Workers 11 文件／116 项、Node 预检／静态服务 13／13、bundle 3／3，再构建发布。
- 索引预建：发布前独立确认 kd201 为 `toccards_test`、PostgreSQL 18.6、ledger 16 项至 `0015`，目录估计 2,405,301 行，磁盘剩余 319 GB，无活跃锁等待。旧 Game 更新时间索引有历史扫描记录，另两旧排序索引统计为 0；仓库已无相应排序读取，预检时无活跃外部 `cards_all.updated_at` 查询，未安装 `pg_stat_statements`，因此不宣称核实了全部外部历史 SQL。持有既有 watcher／deploy 锁，先生成 `toccards-test-20261028-180641-before-created-indexes-6a1f053d.dump`，1,136,430,871 字节、`pg_restore --list` 读取 336 个非注释条目。18:10:29–18:10:59 依次 `CREATE INDEX CONCURRENTLY` 建立三个新索引，各约 9–10 秒；完整定义及 `indisvalid/indisready=true` 回读通过，旧索引此时保留，ledger 未提前登记。
- watcher 发布：既有每两分钟 watcher 自动接收新 dev，无手工并发发布或强制重发；release 为 `branch-dev-b9702b81c4cd-20261028181556`。实际预检仅待执行 `0016`，发布前备份 `toccards-test-20261028-181558-before-branch-dev-b9702b81c4cd-20261028181556.dump` 为 1,136,440,496 字节，独立 `pg_restore --list` 读取 339 个非注释条目。migration 事务跳过已存在的新索引、删除指定三个旧索引并登记 `0016` 后提交；ledger 变为 17 项，最新为 `0016_cards_all_created_order_indexes.sql`，后续预检无待迁移。两个备份均保留，未做恢复演练。
- 运行验收：`current`／manifest／`last-seen-sha`／`last-deployed-sha` 在发布后均指向 `b9702b81`，失败标记不存在；DB／API healthy、Web running、migration exited/0。原 PostgreSQL 数据卷与私有 `.env` 保留，环境文件前后 SHA-256 一致。API 运行文件、Linux release 与同提交 Windows 本地构建 SHA-256 均为 `74b0259cb127a641b5a4013fc28b36842e71543c5db340206497bdc1e97fef71`；0016 运行文件与 Git 原始 LF 字节 SHA-256 同为 `530cfbdc0f9979a5212bc0c1d8179720b893a3766cf3348ede3cff52368268aa`。Admin 全部 11 个 HTML／JS／CSS 的 release、容器和 HTTP 原始字节一致。
- 业务只读验收：开发机 health／Admin 返回 200，未登录 auth/me 和 Admin 苹果通知 options 均为 401。默认 Pokemon 的 Cards 第 1、2 页共 80 条，以及 Set `23881` 的第 1、2 页共 80 条，均与数据库按 `created_at DESC NULLS LAST, product_id DESC` 查询的 ID 顺序逐项一致；Cards 两页无重复。新三索引均有效、旧三索引已不存在、`updated_at` 字段保留。发布后真实全字段首屏 SQL 使用 `idx_cards_all_game_created_product`，无额外 Sort，单次执行 0.153 ms、规划 1.585 ms；不代表一般 P95、价格查询或 App 端到端耗时。
- 边界：本轮只修改 dev，prod／Cloudflare、Secret、watcher 配置和业务数据未主动改写；公开 GET 会按既有逻辑回填 dev 内存缓存。未执行真实 Admin 登录／SKU 下拉操作、真实图片识别、iOS／Android 真机、备份恢复或全部业务验收。上述运行提交与后续仅补充本文档的 dev 提交分别记录，不因文档提交强制重复部署。

## Linux dev 手工重新部署（2026-10-28 15:57–16:10）

- 来源与路径：从干净的本地 `dev@239a8955fd72ec23b1efcbd6a59740f6a86fe54c` 手工发布，release 为 `manual-dev-239a8955-20261028155740`，manifest 记录 `branch=dev`、`working_tree_dirty=false`、`source=deploy-dev`。当时本地 `dev` 比 `github/dev@b08d02f2` 领先 9 个提交，未擅自 push；部署前确认 watcher 与 deploy 锁均空闲，发布期间持有 watcher 锁，现有 watcher 配置和状态文件未修改。
- 构建与预检：`deploy:dry-run:dev` 完成 Admin development 构建（1,526 个模块）、Linux API bundle 及 bundle 测试 3／3。上传包为 2,141,339 字节，SHA-256 `7ae8be36a6452cfd211d68ed9f292adb63b94d71a440ab688aa8d21afbef6c18`，服务器逐字节哈希一致后解包。服务器预检确认数据库 `toccards_test`、PostgreSQL 18、向量与 pHash 两套识别服务可达、`pendingMigrations=[]`。
- 数据与运行：发布前 custom-format 备份 `toccards-test-20261028-155743-before-manual-dev-239a8955-20261028155740.dump` 为 1,136,296,495 字节；独立 `pg_restore --list` 成功读取 351 项，未执行恢复演练。migration 容器退出 0，ledger 数量保持 16；DB／API 均为 running/healthy，Web running。`current` 与 `shared/current-release` 均指向本次 manual release，失败标记为空；运行 `/app/server.mjs` 与 release 文件 SHA-256 同为 `4d2d81d9ae4792c454928233dd0e73b86b08917abb2f400513faef65a990179f`。
- 独立烟测与稳定性：开发机访问 `http://192.168.50.201:8080/api/v1/health` 返回 200／`{"status":"ok"}`，Admin 根路径返回 200，未登录 `/api/v1/auth/me` 返回 401。16:06、16:08、16:10 三个 watcher 周期均确认远端仍为 `b08d02f2` 且没有新提交，当前 manual release 未被覆盖；watcher 的 `last-seen`／`last-deployed` 保持 `b08d02f2`，这是手工发布未改状态文件的预期结果，后续远端 `dev` 新提交仍可能替换当前运行版本。
- 边界：prod、Cloudflare、数据库 schema、私有环境值和 watcher 配置未修改；未执行真实 Admin 登录、真实图片识别、真机扫描、备份恢复或业务验收。本轮没有重跑完整 Admin／Workers／Flutter 测试，部署前验证仅为上述构建和 Linux bundle 3／3；当前源码既有四张相机 Golden 差异没有因部署而关闭。部署执行阶段未夹带 Git commit／push，本记录的 Git 交付由后续独立提交完成。

<a id="sets-numeric-id-order-20261029"></a>
## Sets 系列列表按纯数字 ID 倒序（2026-10-29）

- 范围：在 `codex/dev-1.0.7scan@80740bbd` 加前述未提交 Cards 数值排序改动的工作区中，按用户要求将 `GET /api/v1/sets/search` 从 `s.name ASC, s.set_id ASC` 改为纯数字 `set_id::numeric DESC NULLS LAST`、原字符串 `set_id DESC`。只有完全匹配 `^[0-9]+$` 的 ID 转换；非数字置后，前导零与 API 原字符串身份保持。该系列列表不增加创建时间主键，Game／关键词／非空 set_code 过滤不变。
- 只读预检：kd201 dev `sets` 为 2,978 条、纯数字 2,078 条且最长 7 位，非数字最长 5 字符；Pokemon 首屏候选 SQL 使用 `idx_sets_game_name_search` 做 Bitmap Scan 后 Sort，单次执行 1.768 ms、规划 0.471 ms、共享缓存命中 43 块。只执行只读事务，没有替换运行代码、数据库写入或缓存回填；prod 未查。
- 验证：`pnpm --filter @kando/workers-api test src/data-source/set-search.postgres.test.ts src/db/postgres/cards-created-order-indexes.test.ts src/data-source/local-db-adapter.test.ts src/data-source/kv-cache.test.ts src/data-source/routes.test.ts --maxWorkers=1` 最终 5 文件／57 项通过，Workers `type-check` 通过。真实 PostgreSQL 适配器覆盖数字／非数字／前导零／超 bigint 范围 ID 的 4／4／2 三页排序，名称不影响顺序，原 Game、set_code 和关键词过滤保留；SQL 断言明确没有 name 排序。
- 首轮修正与旧端：首轮 56 项通过／1 项失败，原因是测试将数值同为 0 的 `0`／`000` 文本倒序期望写反；正确次序为 `000` 在前，修正测试后整组重跑 57／57，业务 SQL 未因测试失败调整。完整 `pnpm test:app-compatibility` 通过，当前服务端 8 项、固定 App 1.0.4／1.0.5 各 24 项，证据目录 `.dart_tool/app-compatibility/run-3bxrmo/`；旧客户端源码、基线及合同断言不变，不代表真机验收。
- 审查：独立 Code Review 未发现代码阻断；现行合同已移除 Sets 名称排序，历史记录保留，`git diff --check` 通过。
- 边界：无新增 migration 或索引；Sets 查询原本不走结果缓存，Cards `v16` 保持。本次尚未合并 dev 或部署；未运行全量 Workers／Flutter 测试或打包，只验证受影响查询和兼容调用方。原有 Cards 排序改动继续保留，不修改已执行的 `0016` 或固定旧端基线。

<a id="cards-numeric-id-order-20261029"></a>
## Cards 同创建时间内按纯数字 ID 排序（2026-10-29）

- 范围：基于 `codex/dev-1.0.7scan@80740bbd`，按用户确认的新规则依次排序 `created_at DESC NULLS LAST`、纯数字 ID 的 `numeric` 值降序／非数字置后、原字符串 ID 降序。只用派生值排序，原 ID、API 字段、查询过滤、价格与鉴权边界不变；Search Cards 和 Sets 内卡牌列表共用规则，搜索缓存改为 `v16`。
- 只读预检：kd201 `toccards_test`／PostgreSQL 18.6 的只读事务确认目录 2,405,301 行，纯数字 ID 268,639 行、最长 8 位，非数字最长 9 字符。Pokemon 最大同创建时间组 29,684 张；候选 SQL 的首屏 Game 索引＋Incremental Sort 样本为 81.133 ms、共享缓存命中 3,851 块，Set `23881` 的 Bitmap Scan＋Sort 为 26.783 ms、命中 6,445 块。该检查未替换运行代码、建立索引、写入业务数据或回填 HTTP 缓存；不能代表一般 P95／P99、端到端耗时或 prod。
- 索引决策：本次保持最小业务改动，不修改已执行的 `0016`，不新增排序列、migration 或表达式索引。现有索引不能完整覆盖新增的数值排序，需要额外排序；这项性能代价已明确记录，不把 SQL 正确性等同于无性能变化。
- 本地验证：`pnpm --filter @kando/workers-api test src/db/postgres/cards-created-order-indexes.test.ts src/data-source/local-db-adapter.test.ts src/data-source/kv-cache.test.ts src/data-source/routes.test.ts --maxWorkers=1` 为 4 文件／55 项通过，Workers `type-check` 通过。真实 PostgreSQL 适配器覆盖混合 ID、前导零、超 `bigint` 范围数字、时间主顺序、NULLS LAST、Game／Set 隔离和三页 10 张卡不重不漏；缓存测试确认旧 `v15` 结果不会替代新规则。6,000 条合成数据的三个浏览查询仍可用既有创建时间前缀索引，不再要求无 Sort。
- 旧端与审查：完整 `pnpm test:app-compatibility` 通过，服务端 8 项、固定 App 1.0.4／1.0.5 各 24 项，证据目录 `.dart_tool/app-compatibility/run-kdCIDt/`；旧端基线、源码和客户端断言未改，继续验证字符串 ID、分页、零价／缺价。独立 Code Review 无正确性阻断，`git diff --check` 通过；当前排序变更不将 ID 的身份判断或传输转为数值。
- 边界：本次尚未合并 dev、执行迁移或部署；未运行全量 Workers／Flutter 测试、制品构建、真机或生产数据验证，仅覆盖受影响查询与旧端源码合同。此前创建时间单键排序的记录保留为历史，不作为本次验证结果。

<a id="cards-created-only-order-20261029"></a>
## Cards 仅按创建时间排序（2026-10-29）

- 范围：在 `codex/dev-1.0.7scan@6a1f053d` 上按用户新要求，将共享 Cards SQL 改为仅 `ORDER BY created_at DESC NULLS LAST`，移除 `product_id DESC`，搜索缓存提升为 `v15`。Search Cards 与 Sets 内卡牌列表共用此规则；请求／响应、价格和权限边界保持。
- 索引与分页：保留已执行的 PostgreSQL `0016` 和三个组合索引，本次无新增 migration；索引前缀继续支持创建时间排序。相同时间记录不规定先后，不再保证这些记录跨页时的稳定边界；现有索引可能仍返回 ID 降序，不能将其视为接口契约。
- 验证：`pnpm --filter @kando/workers-api test src/db/postgres/cards-created-order-indexes.test.ts src/data-source/local-db-adapter.test.ts src/data-source/kv-cache.test.ts src/data-source/routes.test.ts --maxWorkers=1` 为 4 文件／55 项通过，Workers `type-check` 通过。SQL 断言精确限制仅有创建时间排序；PostgreSQL 用例验证时间顺序、NULLS LAST，并对同时间记录仅校验集合；6,000 条合成数据的三种空词查询仍采用既有索引、无额外 Sort，不据此保证线上耗时。
- 旧端验证：完整 `pnpm test:app-compatibility` 通过，服务端 8 项、固定 App 1.0.4／1.0.5 各 24 项，证据目录为 `.dart_tool/app-compatibility/run-faY91C/`。当前合同使用明确不同创建时间的目录样本验证分页与零价／缺价，固定旧端基线、源码和客户端合同断言不变；这不能证明同时间记录跨页时不重复或遗漏，也不代表真机或正式制品验收。
- 审查：独立 Code Review 未发现代码阻断问题，文档明确本次规则替代 Card Search 原有的 ID 唯一稳定键约定；`git diff --check` 通过，`0016` 迁移及固定旧端基线无改动。
- 边界：本次尚未合并 dev、执行远端查询、迁移或部署；未运行全量 Workers／Flutter 测试或打包，仅验证受影响查询与兼容调用方。2026-10-28 的开发和验收记录保留历史含义，不作为本次改动的验证结果。

<a id="cards-search-order-indexes-20261028"></a>
## Cards 创建时间排序与索引替换（2026-10-28）

- 范围：本地 `codex/dev-1.0.7scan` 的排序修改开始于 `eb281316cba82bcf05929fc2b1b796846c6ce2ca`，验证时基线为包含并行 Admin 提交的 `eafeeb6a4a5fa17563c903d42eab9741a1579b4b`，叠加本次未提交改动。按最终要求将 Cards 查询改为 `created_at DESC NULLS LAST, product_id DESC`，KV 搜索缓存使用 `v14`；用户明确旧索引删除范围不包含 `updated_at` 字段。
- 实现：新增 PostgreSQL `0016_cards_all_created_order_indexes.sql`，先创建全目录／Game／Game＋SetCode 三个创建时间排序索引，再删除对应的三个旧更新时间排序索引。新索引保留旧的筛选前导列；未修改其他索引、字段、数据、已执行迁移或退役 D1 实现。仓库活跃 SQL 审计未发现旧排序依赖，外部采集和临时 SQL 尚未核查。行为、执行方式与回退见 [Cards 排序与索引](../03-data-api/cards-search-order.md)。
- 本地 PostgreSQL 与查询验证：`pnpm --filter @kando/workers-api test src/db/postgres/cards-created-order-indexes.test.ts src/data-source/local-db-adapter.test.ts src/data-source/kv-cache.test.ts src/data-source/routes.test.ts --maxWorkers=1` 为 4 文件／55 项通过。新增 PGlite 用例验证事务内重复迁移仅替换指定三组索引，保留其他索引、字段与数据；真实适配器验证创建时间、ID 降序、空时间置后及跨页结果。6,000 条合成数据经 `ANALYZE` 后，空关键词的全目录／Game／Game＋SetCode 三种查询计划分别采用对应新索引，均无额外 Sort；不据此推断关键词检索的计划或线上耗时。
- 静态与旧端验证：Workers `type-check`、Dart 格式检查及兼容测试文件的 `flutter analyze --no-pub` 通过。完整 `pnpm test:app-compatibility` 通过：当前 Hono API 合同 8 项，固定 App 1.0.4+161 与 1.0.5+163 源码各 24 项；源码基线及旧客户端保持不变，只按已批准的新排序更新当前测试的页序与零价／缺价所在位置。结果保存在忽略目录 `.dart_tool/app-compatibility/run-gXMuPG/report.json`，证据类型为 `git-source-contracts-only`，不代表签名制品或真机验收。
- 首轮失败与修正：初版计划测试使用关键词 `card`，规划器估算选择性后采用 Seq Scan＋Sort，因此该轮为 54 项通过／1 项失败；改为实际首屏的空关键词验证索引有序输出，未禁用顺序扫描或更改业务 SQL。新测试漏导入 Node `URL` 引发类型检查失败，显式导入后复跑通过。前述失败不记为通过；最终定向测试与类型检查均已重跑。
- 最终审查：独立 Code Review 无阻断发现，`git diff --check` 及新文档入口／相对路径检查通过；前面误写入 v1.1.0 的本次排序说明已移至 v1.1.3，归档文件恢复为无差异。
- 环境边界：尚未执行 dev/prod 迁移、远端索引统计／`EXPLAIN ANALYZE`、真实规模锁等待／耗时验证或部署；本地索引与合成数据验证不代表线上性能或外部查询兼容性已确认。本次仅覆盖查询、迁移和直接兼容调用方，未运行全量 Workers／Flutter 测试或打包；并行 Admin 变更不属于本记录。

## Review 偶发图片与价格丢失修复（2026-10-28）

- 基线与证据：基于本地 `codex/dev-1.0.7scan@94b7f79e38408ae673405d1bdb82c6d0249b7b74`。用户反馈 production App `1.0.6 (182)` 偶发进入 Review 后有候选名称但图片占位、价格为 `--`。调查已核对该包发布源 `557166b` 的相关加载函数与本地一致，并在修复前用临时 Widget 测试稳定复现：后台详情先成功，随后 `loadTarget` 完成，打开 Review 的旧缓存快照把图片覆盖回 `null`。截图对应三张候选的公开生产详情、主要行情请求与 JPEG 图片在调查时均正常；这些只读检查不代表取得了用户当次手机请求日志。
- 最小修复：只修改 `scan_page.dart` 的 `_openReview`。图片地址为 `null` 的临时候选仍需补取详情；等待结束后与实时 `_reviewCards` 合并，保留此间后台已完成的图片和价格。详情成功但无行情仍有图片地址，不重复请求。原候选基本资料降级、选卡顺序、收藏确认、扫描识别／额度、图片传输及其他页面不变，未改 API、仓库或数据模型。实际行为见[扫描识别链路](../01-flows/scan-recognition.md#review-图片与详情加载修正2026-10-28)。并行 Admin／Workers 工作不属于本修复。
- 回归：Windows Flutter 3.44.7／Dart 3.12.2 下，新增四个 Widget 用例 4／4 通过，覆盖占位补取、后台先成功后的数据保留、首轮详情失败后重试，以及图片有效但价格为空时不重复读取。`flutter analyze --no-pub lib/features/scan/scan_page.dart test/widget/scan_page_test.dart` 无问题。完整 `flutter test --no-pub --concurrency=1 --no-track-widget-creation test/widget/scan_page_test.dart test/scan_review_repository_test.dart` 为 137 项通过、4 项相机阶段 Golden 失败；Review Golden、候选选择、收藏确认、失败降级及 iOS／Android 既有行为测试均通过，不能将完整集合记为全通过。
- Golden 与反证：四个失败项为 pre-scan／scanning／recognition／reveal 的 390×844 截图，差异依次为 13.81%、14.28%、15.19%、14.93%。使用原 HEAD 源码的隔离副本重跑，四张实际输出 PNG 的 SHA-256 与修复后逐一相同，确认是本次修改前已有差异，未修改或重录 Golden。原源码跑新增用例时前三项按预期失败；仅恢复旧快照合并时，时序用例仍以 `Expected 图片 URL / Actual null` 失败。隔离文件均已清理。最终使用 `--name '^(?!Figma (?:scan pre-scan|scan scanning|recognition|scan reveal) renders at the 390x844 baseline$)'` 明确排除这四项，原两文件其余 137／137 通过；首次使用不支持的 `--exclude-name` 参数退出 64，未运行测试，不记为通过。
- 审查与边界：独立 Code Review 及补测后的复审均无阻断发现，`git diff --check` 通过。未修改相机／Review 布局、版本号或依赖，未做 iOS／Android 真机、APK／IPA 构建、正式包重测、Git commit／push 或远端部署。本次是客户端本地修复，生产 `1.0.6 (182)` 不会因此自动更新；线上生效仍需后续客户端打包与发布。

## iOS 测试环境内部安装包 1.0.6 (189)（2026-10-28）

- 构建输入：从构建前干净且与实时同名远端一致的 `codex/dev-1.0.7scan@885a78c54c43a2f9705dbc544be21cbf650bf2b6` 构建；相对 188 新增扫描汇总／额度提示与结果卡间距、大屏定位框等比放大、相机画面提亮及失败预留时的队列满提示校正，没有依赖、iOS 工程或环境配置变化。当前分支与 `origin/dev` 已分叉，本包只代表当前功能分支，未擅自切换或合并 dev。脚本从 `1.0.6+188` 显式选择 `1.0.6 (189)`，构建前 dev health 返回 `{"status":"ok"}`；成功后仅将 `pubspec.yaml` 同步为 `1.0.6+189`。
- 工具链与依赖：使用 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1。构建前 `flutter pub get --enforce-lockfile`、脚本内依赖解析及完整 `flutter analyze` 均退出 0；根 `pubspec.lock` 与 iOS `Podfile.lock` SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有依赖锁更新。Swift Package Manager 与 ML Kit Apple Silicon iOS 26+ 模拟器提示仍存在，本轮 CocoaPods、真机 Release Archive 和 IPA 导出成功，不把未来／模拟器兼容提示记为已解决。新提交对应的定向组件、布局和静态检查结果见本文件下方各功能记录；本轮未重跑完整 Widget 或 Flutter 测试。
- 环境与签名：最终内部 IPA 为 `com.kando.kandoApp.beta`、`1.0.6 (189)`、MinimumOSVersion 16.0；测试 API `http://192.168.50.201:8080/api/v1` 命中一次且生产 API 不存在。内置 `GoogleService-Info.plist` 与仓库 test 文件逐字节一致，Firebase project 为 `card-ai---test`、Google App ID 为 `1:490325688457:ios:923f77a6242705bc0f8658`。Runner 与 42 个 Framework 共 43 个组件逐个通过严格签名校验，全部为 Apple Development `kancloud cq (578WZAD3DU)`、Team `B95U3272HR`；最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`，application identifier 为 `B95U3272HR.com.kando.kandoApp.beta`。profile UUID `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。
- 符号：IPA 的 43 个唯一 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，missing／extra 均为 0；45 条 DWARF 中两组为重复 UUID 副本。逐个验证 45 个实际 DWARF 二进制后为 44／45 通过；只有 `App.framework.dSYM` 退出 1，包含 169 次既有 Flutter AOT address range 错误及两条汇总。UUID 覆盖完整，但不能写成全部 dSYM 深检通过。
- 制品与边界：`Card AI Test.ipa` 为 42,977,376 字节，SHA-256 `897971ed7f82fa9f5e72ebf5a061546cabea7bd393ebd0f62b75d2b51847e09a`；`dSYMs.zip` 为 63,897,276 字节，SHA-256 `ef32dc8af9d5ca0cf06db67b18fff614982e58a9e61be8d5c989cb62b109e19a`。两份 ZIP 完整性通过，保存 IPA 与构建输出逐字节一致；独立展开比对确认 IPA 的 384 个文件及 dSYM 的 134 个文件均与当前 xcarchive 一致。制品位于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-189/`；完整保存后当前保留 187、188、189，并经 Finder 独立回读确认 186 已移入废纸篓。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push；未执行真实扫描、扫描 Golden 或真机 OCR／pHash。

## Admin 苹果通知消息 SKU 下拉选项（2026-10-28）

- 范围：基于本地 `codex/dev-1.0.7scan@eb281316cba82bcf05929fc2b1b796846c6ce2ca`，按用户确认将 SKU 输入框改为可搜索、可清空的单选下拉，选项取当前后台可见的全部通知记录，跨分页去重。选择后点击查询生效，保留既有完整匹配、组合条件、分页和重置行为；刷新同步更新列表与选项，选项加载失败明确提示。合同见[后台增量](../04-admin/admin.md#苹果通知消息-sku-筛选2026-10-28)。
- 接口：既有 V1 `GET /api/v1/admin/apple-notifications/options` 保留 `items`，新增 `skus`，从 `product_id` 排序去重并排除无值项，沿用列表的 Bundle／业务环境隔离，不按页面筛选条件收缩。该接口仅供 Admin 使用，可兼容增加独立字段，无需 V2；没有修改 App API、通知处理、共享数据写入、schema 或 migration。
- 验证：开发与必要文档完成后，`pnpm --filter @kando/admin-web test` 为 80／80 通过；新增行为测试执行真实页面函数，覆盖当前页外 SKU、查询草稿、UID 组合、分页、清空、重置、列表／选项同时刷新和失败重试入口。`pnpm --filter @kando/workers-api test src/admin/apple-notification-sku.postgres.test.ts src/admin/routes.test.ts --pool=threads --maxWorkers=1` 沿用既有 `.wrangler` 排除项，2 文件／22 项通过；PostgreSQL/PGlite 覆盖去重、空值、跨分页、Bundle／环境隔离及原 SKU 精确匹配。Admin 与 Workers 的 `type-check`、`pnpm lint` 均通过；Admin `run build:dev` 成功构建 1,526 个模块。上述命令均退出 0。
- 审查与边界：独立 Code Review 未发现阻断问题，本次范围的 `git diff --check` 通过。未进行真实 Admin 登录浏览器交互或线上数据库性能验收；因改动仅涉及 Admin 只读接口与页面，未运行全量 Workers、Flutter 或旧 App 源码兼容编排。开发验证阶段未连接 dev／prod 数据库，未执行部署、远端 migration、Git commit／push 或远程配置写入。上线需要配套发布 Admin 与 API；仅发布前端而旧 API 未返回 `skus` 时下拉选项为空。其他并行任务的改动不属于本次 SKU 下拉交付。

## Admin 苹果通知消息 SKU 筛选（2026-10-28）

- 范围：基于本地 `codex/dev-1.0.7scan@94b7f79e38408ae673405d1bdb82c6d0249b7b74`，在“数据统计 → 苹果通知消息”增加 SKU 输入筛选。前端查询时去除首尾空格，分页／刷新保留当前值，重置清空 SKU；桌面宽屏使用五列并让创建时间跨两列，中等宽度三列、小屏两列且操作区占满一行。完整合同见[后台增量](../04-admin/admin.md#苹果通知消息-sku-筛选2026-10-28)。
- 服务端：`GET /api/v1/admin/apple-notifications` 新增可选 `sku` 参数，按 `apple_server_notification.product_id` 大小写敏感完整匹配，并与现有条件使用 AND 语义；列表和总数复用同一 where。未传 SKU 时，没有结构化行／SKU 的失败 inbox 继续可见。没有新增数据库字段、migration、写入路径、D1 实现或通知处理变化。
- 验证：Admin 全量 Node 测试 79／79 通过；Workers 使用 PostgreSQL/PGlite 的新增测试与既有 Admin 路由测试共 2 文件／21 项通过，覆盖 SKU 命中、前缀不命中、大小写不同不命中、列表／总数一致及无筛选时失败 inbox 保留。`pnpm --filter @kando/admin-web run build:dev` 成功转换 1,526 个模块；`pnpm lint` 通过；根 `pnpm type-check` 的 7 个 TypeScript package 全部通过。
- 失败与审查：首次 Workers 类型检查因新增测试使用了 DOM `URL` 类型而退出 2；显式导入 `node:url` 的 `URL` 后，同一类型检查及定向测试通过。首次只读 Code Review 指出普通文本的 `LOWER(...)` 会破坏 Product ID 大小写语义；改为参数化原值匹配并补隔离测试后，复审未发现遗留问题。
- 边界：本轮未使用真实 Admin 登录态进行浏览器查询，未连接 dev／prod 数据库，未运行完整 Workers 测试、部署、migration、Git commit／push 或远程配置写入。本地源码和构建通过不代表 dev／prod 已上线该筛选。

## Linux dev 手工重新部署（2026-10-28 11:09–11:16）

- 来源与发布路径：从干净的本地 `dev@81559fcd21776d62609e93651eab30b5239a1467` 手工发布，release 为 `manual-dev-81559fcd-20261028110937`，manifest 明确记录 `branch=dev`、`working_tree_dirty=false`、`source=deploy-dev`。当时本地 `dev` 比 `github/dev@550de72` 领先 10 个提交；本轮没有擅自 push，现有 watcher 仍跟踪远端 `dev`。部署前确认 watcher 与 deploy 锁均空闲，发布期间持有 watcher 锁，11:10／11:12 的 cron 仅记录已有检查正在执行，没有并发启动第二轮发布。
- 构建与预检：本地 `deploy:dry-run:dev` 完成 Admin development 构建（1,526 个模块）、Linux API bundle 及 bundle 测试 3／3；上传包为 2,141,192 字节，SHA-256 `2bbc022e1fc533467639b699030a926ed29dabfb905db79a7836598478332ed2`，服务器回读一致后才解包。服务器预检确认独立数据库 `toccards_test`、PostgreSQL 18、向量与 pHash 两套识别服务可达、`pendingMigrations=[]`。
- 数据与运行状态：发布前 custom-format 备份为 `toccards-test-20261028-110941-before-manual-dev-81559fcd-20261028110937.dump`，1,136,224,507 字节；独立 `pg_restore --list` 成功读取 351 项，未执行恢复演练。migration 容器退出 0，ledger 数量保持 16；DB／API 均为 running/healthy，Web running。`current` 与 `shared/current-release` 均指向本次 manual release，失败标记为空；运行 `/app/server.mjs` 与 release 文件 SHA-256 同为 `e371d20c6302fa53d53189889a5c4623d85b6cb6491ca2ecf901f654df8460ca`。
- 独立烟测与 watcher：开发机访问 `http://192.168.50.201:8080/api/v1/health` 返回 200／`{"status":"ok"}`，Admin 根路径返回 200，未登录 `/api/v1/auth/me` 返回 401。11:14 与 11:16 两个 watcher 周期均确认远端仍为 `550de72` 且没有新提交，当前 manual release 未被覆盖；watcher 的 `last-seen` 保持 `550de72`、`last-deployed` 保持历史 `6709b47`，这是手工发布未改 watcher 状态文件的预期结果，后续远端 `dev` 新提交仍可能由 watcher 替换当前运行版本。
- 合并前后验证与边界：Admin 全量 79／79、Workers 扫描／类型筛选定向 60／60、两端 TypeScript 检查及 Flutter 全量 analyze 通过；Flutter 扫描／订阅定向集合 245 项通过，4 张扫描页 390×844 Golden 与当前渲染存在 13.81%～15.19% 差异，未重录掩盖。prod、Cloudflare、数据库 schema、私有环境值和 watcher 配置未修改；未执行真实账号登录、真实图片识别、真机扫描、备份恢复或业务验收。部署执行阶段未夹带 Git commit／push，本记录的 Git 交付由后续独立提交完成。

## Admin 扫描记录卡牌类型筛选（2026-10-28）

- 基线与范围：从干净的 `codex/dev-1.0.7scan@c13cb90f4207d8b65545b471986829645f2bfd14` 开始本地修改。“卡牌管理 → 扫描记录管理”新增 TCG／SPORTS 类型筛选，选择后点击查询生效，分页保留类型，清除／重置恢复全部。用户已明确确认历史缺类型记录只在“全部”中显示，不推断回填；完整规则见[扫描识别链路](../01-flows/scan-recognition.md#管理后台按卡牌类型筛选2026-10-28)。
- 实现：复用 `GET /api/v1/admin/scans`，可选 `card_type=0|1` 同时参与 PostgreSQL 列表与总数查询，其他条件和 Admin 鉴权保持。扫描请求中的已校验类型保存到既有 `system_result.card_type`，成功、未命中和上游失败的审计记录均覆盖；兼容向量与 pHash 路径共用该写入点，不修改 App 扫描响应，无新增数据库列、migration 或 D1 路径。
- 前端验证：`pnpm --filter @kando/admin-web test` 最终 79／79 通过，新增测试执行真实页面处理函数，覆盖草稿／查询时机、TCG 的字符串 `0`、SPORTS、UID 组合、分页、清除和重置。首轮 78 项通过、1 项因测试夹具未提供 CommonJS `exports` 而失败；补齐夹具后同范围重跑全通过，未调整生产逻辑或放宽断言。Admin `type-check`、`pnpm lint` 通过；`pnpm --filter @kando/admin-web run build:dev` 成功构建 1,526 个模块。首次省略 `run` 的构建调用退出 1 且无输出，不记为通过。
- 后端验证：在 `apps/workers-api` 使用本机 Node 执行 Vitest，按标准参数 `--exclude "**/.wrangler/**" --pool=threads --maxWorkers=1` 分别运行当前源码的 `src/scan/routes.test.ts`（57／57）、`src/admin/routes.test.ts`（19／19）及新增 `src/admin/scan-card-type.postgres.test.ts`（3／3），合计 3 文件／79 项通过。新增测试使用 PGlite 和既有 PostgreSQL 迁移，覆盖旧记录、类型、分页总数、组合条件、非法枚举和鉴权；既有扫描测试补充持久化断言，包括无候选的失败记录。Workers `type-check` 通过。早期直接 Vitest 调用遗漏既有 `.wrangler` 排除项，混入生成副本并出现 Windows 进程异常 `3221226505`；这些轮次不作为当前源码通过证据。
- 审查与边界：独立 Code Review 未发现需返工问题，`git diff --check` 通过。未运行全仓 Workers／Flutter 测试、真实后台登录交互或线上数据库性能验收；未提交／推送 Git、部署 dev/prod、执行远端迁移或历史数据回填。类型保存从目标环境部署此服务端代码后的新扫描开始生效，本地测试不代表线上已出现该筛选。

## iOS 测试环境内部安装包 1.0.6 (188)（2026-10-28）

- 构建输入：从构建前干净且与实时同名远端一致的 `codex/dev-1.0.7scan@b1c37e7fa26e86747195ca62ec7d9b8ada8a6ff1` 构建；相对 187 新增十张活动卡牌队列容量顶部提示及测试、扫描链路与验证文档，没有依赖、iOS 工程或环境配置变化。当前分支与 `origin/dev` 已分叉，本包只代表当前功能分支，未擅自切换或合并 dev。脚本从 `1.0.6+187` 显式选择 `1.0.6 (188)`，构建前 dev health 返回 `{"status":"ok"}`；成功后仅将 `pubspec.yaml` 同步为 `1.0.6+188`。
- 工具链与依赖：使用 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1。构建前 `flutter pub get --enforce-lockfile`、脚本内依赖解析及完整 `flutter analyze` 均退出 0；根 `pubspec.lock` 与 iOS `Podfile.lock` SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有依赖锁更新。Swift Package Manager 与 ML Kit Apple Silicon iOS 26+ 模拟器提示仍存在，本轮 CocoaPods、真机 Release Archive 和 IPA 导出成功，不把未来／模拟器兼容提示记为已解决。新功能提交已有两项定向组件测试 2／2 记录，本轮未重跑 Widget 测试或完整 Flutter 测试。
- 环境与签名：最终内部 IPA 为 `com.kando.kandoApp.beta`、`1.0.6 (188)`、MinimumOSVersion 16.0；测试 API `http://192.168.50.201:8080/api/v1` 命中一次且生产 API 不存在。内置 `GoogleService-Info.plist` 与仓库 test 文件逐字节一致，Firebase project 为 `card-ai---test`、Google App ID 为 `1:490325688457:ios:923f77a6242705bc0f8658`。Runner 与 42 个 Framework 共 43 个组件逐个通过严格签名校验，全部为 Apple Development `kancloud cq (578WZAD3DU)`、Team `B95U3272HR`；最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`，application identifier 为 `B95U3272HR.com.kando.kandoApp.beta`。profile UUID `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。
- 符号：IPA 的 43 个唯一 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，missing／extra 均为 0；45 条 DWARF 中两组为重复 UUID 副本。逐个验证 45 个实际 DWARF 二进制后为 44／45 通过；只有 `App.framework.dSYM` 退出 1，包含 169 次既有 Flutter AOT address range 错误及两条汇总。UUID 覆盖完整，但不能写成全部 dSYM 深检通过。
- 制品与边界：`Card AI Test.ipa` 为 42,976,855 字节，SHA-256 `db433e5b874c5ffc123807c2e4ae42cd8662309f7362ca61abb755458af7db62`；`dSYMs.zip` 为 63,897,278 字节，SHA-256 `68b632f8d22f3f64d635735deaba6fc1bba8481ead9730eb13dcd648da4d0a46`。两份 ZIP 完整性通过，保存 IPA 与构建输出逐字节一致；独立展开比对确认 IPA 的 384 个文件及 dSYM 的 134 个文件均与当前 xcarchive 一致。制品位于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-188/`；完整保存后当前保留 186、187、188，并经 Finder 独立回读确认 185 已移入废纸篓。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push；未执行真实第 11 次扫描、扫描 Golden 或真机 OCR／pHash。

## 订阅兜底三卡下移（2026-10-28）

- 根据用户提供的 iPhone 截图，仅将 iOS 本地三卡且无试用开关时，权益区与首张商品之间的间距从 62 调至 86 逻辑像素。三张商品整体下移 24 像素；卡间 20 像素、固定购买区、远端后台配置和 Android 分支不变。初始 414×896 Widget 几何测量中，真实商品兜底的末卡到按钮上沿为 43px；调整后该测试通过。最终新增回归改为商品全量失败的固定参考价分支，确认首卡距权益区 86px、末卡与按钮仍有间隔，并断言实际进入离线兜底；原 62px 布局无法满足首卡断言。
- 最终 `flutter test --no-pub --concurrency=1 --no-track-widget-creation test/subscription_display_test.dart test/subscription_restore_ui_test.dart` 退出 0，108／108 通过，涵盖 Page／Modal 兜底、远端商品和 Android 既有路径；`flutter analyze --no-pub` 退出 0。独立只读 Code Review 未发现阻断问题。
- 根据用户后续指定，使用 `flutter run --no-pub --flavor test --debug -d 00008030-001C08311E28802E --dart-define-from-file=config/test.json` 在有线 iPhone 11（iOS 18.7.8）完成 Debug 构建、安装和启动，Flutter VM Service 已连接。设备当前断网，测试 API 的订阅展示配置请求失败；828×1792 截图确认页面进入本地兜底，三张商品卡、Retry 和购买按钮均可见，末卡与按钮无重叠。随后 detach 调试连接并再次抓屏，App 仍保持在该页面。此画面验证的是断网固定参考价分支，不代表联网 StoreKit 报价或远端配置布局已在真机验收。
- 用户更改目标设备前，iPhone 13 已通过 `devicectl` 安装过同一 Debug 包；其后续 `flutter run` 在安装启动阶段按用户指示停止，未做真机布局验收，也未卸载已有应用以免影响设备数据。

## iOS 测试环境内部安装包 1.0.6 (187)（2026-10-28）

- 构建输入：从构建前干净且与实时同名远端一致的 `codex/dev-1.0.7scan@c13cb90f4207d8b65545b471986829645f2bfd14` 构建；该提交在 186 后新增扫描页顶部间距、额度提示文字和定位框四角等视觉调整及对应测试，没有依赖、iOS 工程或环境配置变化。当前分支与 `origin/dev` 已分叉，本包只代表当前功能分支，未擅自切换或合并 dev。脚本从 `1.0.6+186` 显式选择 `1.0.6 (187)`，构建前 dev health 返回 `{"status":"ok"}`；成功后仅将 `pubspec.yaml` 同步为 `1.0.6+187`。
- 工具链与依赖：使用 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1。构建前 `flutter pub get --enforce-lockfile`、脚本内依赖解析及完整 `flutter analyze` 均退出 0；根 `pubspec.lock` 与 iOS `Podfile.lock` SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有依赖锁更新。Swift Package Manager 与 ML Kit Apple Silicon iOS 26+ 模拟器提示仍存在，本轮 CocoaPods、真机 Release Archive 和 IPA 导出成功，不把未来／模拟器兼容提示记为已解决。
- 环境与签名：最终内部 IPA 为 `com.kando.kandoApp.beta`、`1.0.6 (187)`、MinimumOSVersion 16.0；测试 API `http://192.168.50.201:8080/api/v1` 存在且生产 API 不存在。内置 `GoogleService-Info.plist` 与仓库 test 文件逐字节一致，Firebase project 为 `card-ai---test`。Runner 与 42 个 Framework 共 43 个组件逐个通过严格签名校验，全部为 Apple Development `kancloud cq (578WZAD3DU)`、Team `B95U3272HR`；最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`，application identifier 为 `B95U3272HR.com.kando.kandoApp.beta`。profile UUID `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。
- 符号：IPA 的 43 个唯一 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，missing／extra 均为 0；45 条 DWARF 中两组为重复 UUID 副本。直接对展开后的 dSYM bundle 深检时，ZIP 中的 `._*` AppleDouble 资源辅助文件使 45 个 bundle 都误报非目标文件，不能记为有效检查；改为逐个验证 45 个实际 DWARF 二进制后为 44／45 通过。只有 `App.framework.dSYM` 退出 1，包含 169 次既有 Flutter AOT address range 错误及两条汇总；UUID 覆盖完整，但不能写成全部 dSYM 深检通过。
- 制品与边界：`Card AI Test.ipa` 为 42,974,722 字节，SHA-256 `6cc5f73ebce54e4ff1d6ce567d77a5993041d5e56f87fe0866a29589382faa4f`；`dSYMs.zip` 为 63,897,049 字节，SHA-256 `77bd0479136380f3cd6ee00a22bb06dc6c68572ed69e77e36ddd07991b1f7bb0`。两份 ZIP 完整性通过，保存 IPA 与构建输出逐字节一致；独立展开比对确认 IPA 的 384 个文件及 dSYM 的 134 个文件均与当前 xcarchive 一致。制品位于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-187/`；完整保存后当前保留 185、186、187，并经 Finder 独立回读确认 184 已移入废纸篓。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push；未重跑全量 Flutter 测试、扫描 Golden 或真机 OCR／pHash。

## 扫描页顶部操作区间距收紧（2026-10-27）

- 将系统顶部安全区与关闭／卡牌类型／闪光灯操作行之间的固定间距从 36px 缩小 20px 至 16px；按钮尺寸、横向位置、顶部背景透明状态及点击逻辑不变。取景框继续通过共享几何与顶部操作区保留 29px 最小间距，并按安全区和可用高度自适应。
- 定向 390×844 布局测试 1/1 通过，操作行从 `safeTop+36` 精确上移到 `safeTop+16`，标准尺寸取景框保持 `x=68, y=154, 254×363`。首次非 Golden 集合有 128 项通过、2 项尺寸快照失败：顶部新增空间使 iPhone 8 取景框从约 150.44×215 扩为 164.44×235，紧凑 Android 从约 128.75×184 扩为 142.74×204；两者比例、29px 上下间距、扫描线和遮罩均保持。更新这两项预期后同一集合 130/130 通过，相关静态分析无问题。待扫描实际图人工回读确认按钮行上移；Golden 因当前累计视觉增量及既有 macOS 字体差异以 9.05% 失败且未重录。test flavor 已向有线 iOS 18.7.8 设备热重载成功，尚待用户真机确认。

## 扫描额度提示文字样式校正（2026-10-27）

- 对照用户提供的 UI 原图，将 `Tap to get unlimited scans` 从整句共用下划线拆为两个富文本片段：仅 `Tap to` 使用品牌黄色及同色下划线，` get unlimited scans` 显式使用 `#E4E3D3` 且不带下划线；前方额度文字同为 `#E4E3D3`，不使用默认纯白。额度数值、PRO 徽章、整条提示尺寸、点击区域及订阅入口逻辑不变。
- 定向 Widget 测试 1/1 通过，逐段断言文字、显式颜色及下划线样式；排除 5 项 390×844 Golden 后，`scan_page_test.dart` 其余 130/130 项通过，相关源码与测试的 `flutter analyze --no-pub` 无问题。待扫描实际图人工回读确认仅 `Tap to` 变为品牌色，整行未换行或错位；该图包含当前未收口视觉增量及既有 macOS 字体差异，Golden 以 7.05% 失败且未重录。test flavor 已向有线 iOS 18.7.8 设备热重载成功，尚待用户真机确认。

## 扫描页定位框四角补齐（2026-10-27）

- 设计与范围：对照 Figma `3901:8241` 及用户提供的原始 UI 截图，在既有 254×363、11px 圆角光晕上补齐四个高亮 L 形转角；每个角段长 36px、转角半径 11px、品牌色描边 4px。进一步对照确认角与角之间只有低强度黄绿色光晕，因此移除整圈 0.91px 白色到橄榄色渐变实线；四个角的路径中心线统一向内偏移半个描边宽度 2px，使 4px 描边外沿与取景框四条边对齐且不再被边界裁切。取景框几何、相机裁剪、扫描线、识别遮罩、OCR／pHash、结果区和操作控件均未修改，iOS／Android 继续共用同一 Flutter painter。
- 验证：顶部控件与定位框定向 Widget 测试 1/1 通过，新增离屏像素断言覆盖四个角各自的横／竖两段，并约束上边与左边中部透明度低于 80，防止光晕再次变成可见实线；排除 5 项 390×844 Golden 后，`scan_page_test.dart` 其余 130/130 项通过。相关源码与测试的 `flutter analyze --no-pub` 返回 `No issues found`。首次像素测试没有将 `PictureRecorder.toImage` 放入 `tester.runAsync`，运行 1 分 50 秒无结果后被主动中断，不计为通过；按仓库既有像素测试模式修正后同一用例退出 0。
- 视觉与真机：重新生成但未接受的待扫描实际图已人工回读，确认四个粗高亮圆角段完整显示、描边外沿对齐四边且暗光晕中段没有实线；该 Golden 因本次定位框、上项顶部背景移除及既有 macOS 文字像素差异共计 7.00% 失败，未重录混合差异。test flavor 真机调试进程已向有线 iOS 18.7.8 设备再次热重载成功，尚待用户在真实相机画面确认视觉效果；测试 Firebase 外网请求出现超时日志，不影响本地热重载，不扩展为网络或识别验收。

## 扫描页顶部操作区背景移除（2026-10-27）

- 范围：基于 `codex/dev-1.0.7scan@d93d0be1` 的本地未提交增量，移除扫描页顶部操作区整块 20px 背景模糊、半透明底色、0.5px 底部分隔及安全区实色带，让相机画面直接延伸到屏幕顶部。关闭按钮、卡牌类型胶囊、闪光灯按钮各自的背景、尺寸、位置、点击和业务逻辑均保持不变。本项覆盖下方“扫描卡牌类型顶部提示样式”中“顶部仍保留背景模糊和底部分隔”的历史状态。
- 验证：顶部控件样式与布局定向 Widget 测试 1/1 通过，明确断言整块 navigation surface 和 safe band 不存在、操作区内只剩卡牌类型胶囊自身的 `BackdropFilter`；排除 5 项 390×844 Golden 后，`scan_page_test.dart` 其余 130/130 项通过。对 `scan_page.dart` 和 `scan_page_test.dart` 的 `flutter analyze --no-pub` 返回 `No issues found`，`git diff --check` 通过。
- Golden 与边界：4 项相机阶段 390×844 Golden 按预期失败，像素差异为 6.00%～9.38%；实际输出确认顶部整块遮罩已消失，但当前 macOS 渲染与仓库基线还包含既有页面文字像素差异，因此没有把无关跨平台差异一并重录。Review Golden 不受本次相机顶部区域修改影响，本轮未运行。
- 真机调试：以 test flavor 和 `config/test.json` 在有线设备 `00008030-001C08311E28802E`（iOS 18.7.8）完成 Debug Xcode 构建、安装与启动，Flutter Dart VM Service 连接成功；目标 Bundle 与接口继续由既有 test 配置选择。构建只出现仓库已知的 Swift Package Manager／模拟器 arm64 兼容提示。本轮尚未收到用户对扫描页顶部视觉效果的确认，不把成功启动扩展为视觉验收、OCR／pHash 或真实识别通过；未执行 Git commit／push或远程部署。

## iOS 测试环境内部安装包 1.0.6 (186)（2026-10-27）

- 构建输入：从构建前干净且与实时同名远端一致的 `codex/dev-1.0.7scan@83836efd003723d4715bc66d4e9a43f7a418adf0` 原样重打；该提交只归档 185 的版本号和验证记录，185 后没有业务源码或依赖变化。本分支不是 `origin/dev` 最新状态，本包只代表当前 `codex/dev-1.0.7scan`。脚本从 `1.0.6+185` 显式选择 `1.0.6 (186)`，dev health 返回 `{"status":"ok"}`；成功后仅将 `pubspec.yaml` 同步为 `1.0.6+186`。
- 工具链与依赖：使用 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1。构建前 `flutter pub get --enforce-lockfile`、脚本内依赖解析及完整 `flutter analyze` 均退出 0；根 `pubspec.lock` 与 iOS `Podfile.lock` SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有依赖锁更新。Swift Package Manager 与 ML Kit Apple Silicon iOS 26+ 模拟器提示同 185，本轮 CocoaPods、真机 Release Archive 和 IPA 导出成功，不把未来／模拟器兼容提示记为已解决。
- 环境与签名：最终内部 IPA 为 `com.kando.kandoApp.beta`、`1.0.6 (186)`、MinimumOSVersion 16.0；测试 API `http://192.168.50.201:8080/api/v1` 存在且生产 API 不存在。`GoogleService-Info.plist` 与仓库 test 文件逐字节一致，Firebase project 为 `card-ai---test`，生产 Firebase project／app ID／storage bucket 均不存在；生产 Google OAuth audience 仍是既有 Workers 验签合同例外，本轮未做真机 Google 登录。Runner 与 42 个 Framework 共 43 个 Mach-O 均通过严格签名校验，全部为 Apple Development `kancloud cq (578WZAD3DU)`、Team `B95U3272HR`；最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`。profile UUID `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。
- 符号：IPA 的 43 个唯一 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，missing／extra 均为 0；45 条 DWARF 中两组为 `cupertino_http` 与 `objective_c` 的重复 UUID 副本。逐 bundle `dwarfdump --verify` 为 44／45 通过；只有 `App.framework.dSYM` 退出 1，包含 169 次 Flutter AOT address range 错误及两条汇总。排除临时路径后，其输出与保存的 185 对应文件逐字节一致，确认不是 186 新增；UUID 覆盖完整，但仍不能写成全部 dSYM 深检通过。
- 制品与边界：`Card AI Test.ipa` 为 42,974,357 字节，SHA-256 `87f9fcd9dd32669eee58cfdda7bb0c218eda5779cdb2eb0f03b61c7773a57aca`；`dSYMs.zip` 为 63,896,975 字节，SHA-256 `b714c900b19f67c5d034dbd0d37b3a06082cb9523db7cd042d2853d398eb0c5e`。两份 ZIP 完整性通过，保存 IPA 与构建输出逐字节一致；独立展开比对确认 IPA 的 384 个文件及 dSYM 的 134 个文件均与当前 xcarchive 一致。制品位于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-186/`；完整保存后最旧的 183 已移入废纸篓，当前保留 184、185、186。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push；未重跑全量 Flutter 测试、扫描 Golden 或真机 OCR／pHash。

## iOS 测试环境内部安装包 1.0.6 (185)（2026-10-27）

- 构建输入：构建前本地与实时远端均为干净的 `codex/dev-1.0.7scan@32afefb521177b316f7280018e0083afbe866116`，包含年试用 SKU 及重新对齐的扫描页 Figma 样式。脚本从工程 `1.0.6+184` 显式选择 `1.0.6 (185)`；dev health 返回 `{"status":"ok"}`。成功构建后只将 `pubspec.yaml` 同步为 `1.0.6+185`。
- 工具链与失败处理：首次调用误用本机已升级的 Flutter 3.47.8／Dart 3.13.7，`pub get` 因 SDK 约束将 6 个传递依赖改为新版并由新迁移器改写两份 `analysis_options.yaml`，随后 `flutter analyze` 以 `unawaited_return_in_try_block` 退出 1；该轮没有生成 IPA，也没有更新版本。确认仓库 iOS 基线后，恢复全部工具生成变更及临时源码验证，使用独立的 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1 重跑。`flutter pub get --enforce-lockfile`、图片组件定向测试 3／3、独立全量 `flutter analyze --no-pub` 及发布脚本内的全量 analyze 均退出 0。脚本更新版本后回查又发现根锁文件呈现同一组 3.47.8 自动重解结果，已再次精确恢复；最终根 `pubspec.lock` 与 iOS `Podfile.lock` SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有项目依赖锁更新。
- 环境：最终内部 IPA 为 `com.kando.kandoApp.beta`，版本 `1.0.6 (185)`；测试 API `http://192.168.50.201:8080/api/v1` 存在，生产 API 不存在。内置 `GoogleService-Info.plist` 与仓库 test 文件逐字节一致，Firebase project 为 `card-ai---test`，生产 Firebase project／app ID／storage bucket 均不存在。Google OAuth audience 按既有 Workers 验签合同继续固定使用生产 Client ID，183／184／185 均相同，属于已知例外，不代表 Firebase SDK 串到生产；本轮未做真机 Google 登录验收。
- 构建提示：`google_mlkit_commons`、`google_mlkit_text_recognition`、`sign_in_with_apple` 仍未支持 iOS Swift Package Manager；ML Kit 相关 Pod 仍提示 Apple Silicon iOS 26+ 模拟器 arm64 兼容性。本轮目标为真机 Release Archive，CocoaPods、Xcode Archive 和 IPA 导出均成功，不把上述未来／模拟器提示记为已解决。
- 签名与符号：Runner 与 42 个 Framework 共 43 个 Mach-O 均通过严格签名校验，全部为 Apple Development `kancloud cq (578WZAD3DU)`、Team `B95U3272HR`；最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`，application identifier 为 `B95U3272HR.com.kando.kandoApp.beta`。profile UUID `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。IPA 的 43 个唯一 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，missing／extra 均为 0；45 条 DWARF 中两条为重复 UUID 副本。独立 `dwarfdump --verify` 深检有 44／45 个 bundle 通过，`App.framework.dSYM` 退出 1，并报告 169 次 Flutter AOT `DIE address ranges are not contained by parent ranges` 及两条汇总错误；保存的 184 对应文件同样为 171 条错误，确认不是 185 新增。UUID 覆盖完整，但不能写成全部 dSYM 深检通过。
- 制品与边界：`Card AI Test.ipa` 为 42,974,353 字节，SHA-256 `3381891e492fbb3b03fd7d8ecbdb70c6e0ba11176a77bc3775e60319e7d14281`；`dSYMs.zip` 为 63,897,837 字节，SHA-256 `5e494bf4fecdef02e2970c31f4a961555a43cf5001b7be10c7d2e2c5ae887ebf`。两份 ZIP 完整性通过，保存 IPA 与构建输出逐字节一致；制品位于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-185/`。新版本完整保存后，最旧的 181 已移入废纸篓，当前保留 183、184、185。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push；未重跑全量 Flutter 测试、扫描 Golden 或真机 OCR／pHash。

## 订阅兜底页与年试用 SKU（2026-10-27）

- 来源与范围：开始时基线为 `codex/dev-1.0.7scan@013a234f17ecf4a13ea507607b8ec4aa5dcac268` 加本地未提交修改；保留并行扫描页工作。按 Figma `3512:10546`／`3512:10763` 将本地 Page／Modal 兜底改为普通周、独立年试用、终身三卡，默认年试用；正式注册 `CardAi.yearly.trial`，测试注册 `cardx.year.trial`。原长期商品集合保留。具体价格、选中态文案和原型周期冲突取舍见[订阅本地兜底页](../01-flows/subscription-display.md)。没有修改服务端 V1、数据库、远端展示配置或 Android 购买分支。
- 购买保护：代码路径审查发现离线 `TRY FOR FREE` 点击后，`prepareFallbackPurchase` 原先只核对真实商品 ID／类型；若免费优惠已消失，后续两次商品事实一致仍可能继续付费。现在先显示已加载商品的中性文案并停止此次购买，用户须再次确认。按先开发及文档、再测试的约定，未在修改前运行失败测试；完成后在隔离临时副本中仅移除新增保护，同一回归用例按预期失败（应返回 null，实际返回 SubscriptionProduct），真实源码用例通过。临时 Dart 文件已清理，未改工作区真实源码做反证。
- 定向验证：`flutter test --no-pub --concurrency=1 --no-track-widget-creation test/subscription_display_test.dart test/subscription_restore_ui_test.dart test/release_config_test.dart test/subscription_product_registry_test.dart` 退出 0，122／122 通过。覆盖 390×844 下真实商品与离线 Page／Modal 三档、试用／非试用文案、完整年价与年周期、终身无周期、按精确年试用 SKU 重查、优惠消失阻止首次付费、原远端关联试用及长期注册／恢复边界。测试中的商店与注册表为受控替身，不代表真实 StoreKit 或服务端准入通过。
- 静态与视觉检查：订阅模块及上述四个测试文件的 `flutter analyze --no-pub` 无问题。另通过两项临时渲染用例生成完整页／弹窗三种选择的六张 390×844 预览并检查试用、终身状态；输出位于忽略的 `apps/flutter-app/build/subscription-fallback-preview/`。预览使用 Windows 本机字体代替部分系统字体，完整页原生视频未播放，不能作为 iOS 像素级或真机视频验收。独立 Code Review 发现的优惠消失保护和周期归一化作用域问题均已修复并复核关闭；`git diff --check` 通过。
- 工具与未验边界：首次沙箱内 Dart 格式化已写入文件，但写 SDK 外 telemetry session 失败而退出 1，不记为通过；后续受控 Flutter 检查通过。未运行全仓 Flutter／Workers 测试、APK／IPA 构建、CI、iOS／Android 真机或真实商店购买／Restore；未执行 Git commit／push、dev/prod 部署、后台商品审批、Apple 写操作、数据库迁移或业务写入。新年试用的 Apple 可售状态、实际三天免费优惠、各环境准入与 Singular 事件映射仍需在对应平台验证。

## iOS 测试环境内部安装包 1.0.6 (184)（2026-10-27）

- 构建输入：从构建前干净且与实时远端一致的 `codex/dev-1.0.7scan@76068ec82cb9674f4250e4a2bfe599e29561d033` 构建，包含扫描卡牌类型顶部提示样式提交。脚本按工程 `1.0.6+183` 显式选择 `1.0.6 (184)`，完整保存后仅将 `pubspec.yaml` 同步为 `1.0.6+184`；分支名不会自动改变营销版本。构建前 dev health 返回 `{"status":"ok"}`。
- 环境与构建：最终内部 IPA 为 `com.kando.kandoApp.beta`，只包含测试 API `http://192.168.50.201:8080/api/v1`，Firebase plist 与仓库 test 文件逐字节一致，项目为 `card-ai---test`；生产 API、生产 Firebase project/app ID 不存在。Google OAuth audience 按既有 Workers 验签合同继续固定使用生产 Client ID，属于已知例外，不代表混入生产 Firebase。Flutter 3.44.5／Dart 3.12.2／Xcode 27.1 下，发布脚本完成配置校验、依赖解析、`flutter analyze`、`flutter clean`、test flavor Release Archive、基础 IPA 和内部 IPA 校验；analyze 无问题。根 `pubspec.lock` 与 iOS `Podfile.lock` 的 SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有依赖锁漂移。
- 构建提示：`google_mlkit_commons`、`google_mlkit_text_recognition`、`sign_in_with_apple` 尚未支持 iOS Swift Package Manager；ML Kit 相关 Pod 另提示缺少 Apple Silicon iOS 26+ 模拟器 arm64 支持。本轮目标是真机 Release Archive，CocoaPods 和 Xcode 构建成功；这些未来／模拟器兼容提示未解决，也不扩展为真机 OCR 已验收。
- 签名与符号：Runner 与 42 个 Framework 共 43 个组件逐个通过严格签名校验，均为 `Apple Development: kancloud cq (578WZAD3DU)`、Team `B95U3272HR`。最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`；profile UUID `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。IPA 的 43 个唯一 arm64 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，缺失／额外均为 0；45 个 DWARF 条目中两个为同 UUID 副本，45/45 均与当前 Archive 字节一致。
- 测试：在 macOS 使用提交记录中的单并发、关闭 widget creation tracking 参数运行完整 `scan_page_test.dart`，130 项通过、5 个 390x844 Golden 像素比较失败，差异为 0.63%～3.85%；没有修改或重录 Golden。明确排除这 5 个 Golden 后，其余 130/130 项通过。该结果不能写成完整集合全通过；未执行真机相机、OCR／pHash、真实识别服务或人工视觉验收。
- 制品与边界：`Card AI Test.ipa` 为 42,974,836 字节，SHA-256 `d89708a5e579f43d433d002034587a11d155e24d36f3faeb6c6e2601b2863cec`；`dSYMs.zip` 为 63,896,828 字节，SHA-256 `50d398a1cd73a0fbf533ca8ea110d7a8fe38b5a50be3009302dc8c1b3155e269`。两份 ZIP 完整性通过，保存 IPA 与构建输出逐字节一致；制品位于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-184/`。新版本完整保存后才将 180 移入废纸篓，当前保留 181、183、184。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push。

## 扫描卡牌类型顶部提示样式（2026-10-27）

### 下拉菜单对齐与选中态（2026-10-28）

- 扫描页 TCG／Sports Card 菜单改为顶部类型胶囊实际宽度的 `2/3` 并水平居中，总高度为外部 42px 类型胶囊的两倍（84px），两项各 42px 且取消额外上下留白。菜单外框顶部向上覆盖胶囊底边 2px 以遮住相交处边框；左上／右上角为直角，底部继续保留 12px 圆角。窄屏下继续跟随胶囊的实际自适应宽度，没有修改顶部关闭／闪光灯布局。
- 展开菜单内当前类型使用品牌黄色 `KandoColors.accent`，另一项保留普通文字色；切换后高亮随 `_selectedCardType` 更新。仅调整 Flutter 弹层布局与视觉状态，没有修改 `card_type=0/1`、扫描接口或识别调用链。
- 定向组件测试 1／1 通过，实际断言菜单项为胶囊宽度的 `2/3`、菜单总高度为胶囊的两倍、中心线一致、菜单外框顶部向上覆盖胶囊底边 2px、顶部直角／底部 12px 圆角，以及 TCG／Sports Card 切换后的品牌黄色选中态；扫描页实现与测试文件的 `flutter analyze --no-pub` 无问题，`git diff --check` 通过。当前工作区以 test flavor 和 `config/test.json` 在有线 iPhone 11（iOS 18.7.8，`00008030-001C08311E28802E`）完成 Debug 重构建、安装、启动及 Dart VM Service 连接；设备上的 Firebase 外网请求曾出现超时，不影响本地 UI 调试，也不记为网络验收通过。尚未收到用户对菜单视觉结果的确认，不把启动成功扩展为真机视觉验收或扫描识别通过。

### 扫描汇总与结果卡间距（2026-10-28）

- 对照用户提供的 UI 图与 iPhone 11 真机图，将额度提示条与下方扫描结果卡轨道的间距从原 3px 增至 15px；结果卡轨道和底部快门保持原位，因此 `Scanned / Total` 行与额度提示条整体上移 12px。取景框继续使用原 `254×363` 最大基准及既有自适应几何，没有随本次底部间距调整移动。
- Premium／无限额度不显示额度提示条时，不再把原 42px 提示条和其上方 9px 间距留在汇总行下方；改为将这 51px 放到 `Scanned / Total` 上方，使汇总行下移且其底部到扫描结果卡轨道同样保持 15px。Free 布局不变，结果卡、取景框和快门位置不变。
- 结果卡横向 `ListView` 继续复用与上方额度提示条相同的左右 16px 边界，但将绘制裁切从 `Clip.none` 收紧为 `Clip.hardEdge`；横向滚动中的卡牌不会再绘制到提示条宽度之外，卡片尺寸、间距、顺序和滚动物理保持不变。
- 390×844 精确布局测试 1／1、iPhone 12／8／大屏 iPhone及紧凑／小屏／大屏 Android 的 Free／Premium 连续扫描布局测试 12／12 通过；新增逐变体断言确认 Free 提示条到结果卡、Premium 汇总行到结果卡均为 15px，并覆盖取景框不移动、汇总区与取景框不重叠、结果卡轨道与快门不重叠。扫描页实现及测试文件的定向 `flutter analyze --no-pub` 无问题，`git diff --check` 通过。首次真机热重载前连接丢失，未记为成功；随后同一工作区在有线 iPhone 11 完成 Debug 重构建、安装、启动及 Dart VM Service 连接。Firebase／Google 外网请求仍有超时，不记为网络或真实识别验收通过。

### 大屏定位框等比放大（2026-10-28）

- 保留现有 `254×363` 基准和小屏等比缩小分支；视口宽或高超过 `390×844` 时，才计算大屏放大候选。候选按 `254:363` 等比放大，并要求距离左右安全区、顶部操作区底边以及最早可能出现的底部汇总区均至少 35 个 Flutter 逻辑像素；任一方向空间不足时由更紧的方向限制比例。
- Free／Premium 共用同一保守边界，权益变化不会导致定位框尺寸跳动。相机裁剪、扫描线、识别／揭示遮罩和四角 painter 继续读取同一 `_scanViewfinderGeometry`，未修改 OCR／pHash、扫描接口、额度或结果列表业务。
- 新增 iPhone 11 `414×896`／顶部安全区 44 的公式回归，运行时按可用空间计算为约 `291.09×416`，与上下内容均保持 35px；该数值仅为测试期望，不作为运行时机型特判或固定尺寸。新增回归 1／1、原小屏自适应 2／2、连续扫描 Free／Premium 布局 12／12、Figma 基准布局 1／1 均通过；相关实现与测试的定向 `flutter analyze --no-pub` 无问题，`git diff --check` 通过。

### 扫描相机画面提亮（2026-10-28）

- 仅降低正常扫描状态下两层既有深色遮罩的不透明度：全屏 `0x0D0F08` 遮罩由约 10% 调整为约 7%（8-bit alpha `0x12`），同色径向暗角边缘由 85% 调整为 75%。颜色、暗角中心与半径、控件层级及识别／揭示状态遮罩均未修改。对应控件回归 1／1 通过，相关实现与测试的定向 `flutter analyze --no-pub` 无问题，`git diff --check` 通过；调亮版已重新构建、安装并启动到有线 iPhone 12 Pro Max，设备网络不可用导致 Firebase／测试 API 超时，不记为网络验收通过。

### 十张活动卡牌顶部提示（2026-10-28）

- 复用项目 `showKandoTopToast` 信息类型和默认 3 秒时长。当 Free 用户已有 10 张活动卡牌但服务端权威免费额度仍大于 0，或当前为 Premium／无限额度时，再次触发拍照或相册扫描显示 `Collect or remove cards to scan more`；不创建第 11 张卡、不调用识别源、不扣额度。Free 额度已耗尽时保留原 `Scan queue is full` 分支，避免错误提示用户仅需移除卡牌。
- 2026-10-28 补充失败预留回归：服务端 `remainingScans` 包含活动预留，10 张均失败时可能暂时为 0，而用户可见的 `displayRemainingScans` 仍为 10，旧判断因此错误显示 `Scan queue is full`。队列满提示现以展示剩余额度补充判断，仅改变提示选择；拍照和相册仍拒绝创建第 11 项，服务端额度门禁、预留及扣减均未修改。新增 Free 失败预留拍照／相册回归 1／1、既有 Premium 队列满提示回归 1／1 通过；相关实现及测试的定向 `flutter analyze --no-pub` 无问题，`git diff --check` 通过。
- 两项定向组件测试 2／2 通过：Free 场景使用 10 个失败结果保持 10 次剩余额度，并从相册入口验证未打开选择器；Premium 场景使用 10 个已完成结果并从拍照入口验证未发起第 11 次扫描。测试同时断言信息类型、2.999 秒仍显示、3 秒自动消失。扫描页实现及测试文件的 `flutter analyze --no-pub` 无问题，`git diff --check` 通过；修改已热重载至有线 iPhone 11。本轮未执行真实第 11 次真机扫描、服务端额度写入、完整 Flutter 测试、原生构建、Git commit／push 或远端部署。

- 设计与范围：按 Figma 完整扫描页 `3305:21640` 重做 Flutter 扫描页样式，并以类型胶囊 `3305:21722`、取景框 `3305:21737`、额度提示 `3305:22294`、结果区 `3305:22304`、底部快门区 `3305:22349` 的属性为准。390×844 基线下，类型胶囊为 209×42px；取景框为 `x=68, y=154, 254×363px`、11px 圆角、0.91px 渐变边框及品牌色阴影；额度提示为 `x=16, y=573, 358×42px` 单行文案；结果轨道从 `y=618` 开始，卡片可见面板约 202×76px；底部控制区增加 8px 水平内边距。顶部仍保留 20px 背景模糊和 0.5px 底部分隔，控制项按设计只显示关闭、卡牌类型和闪光灯。
- 业务边界：继续复用 `_selectedCardType`、`ScanCardType.tcg/sports`、PopupMenu、`onCardTypeChanged` 及既有拍照／相册／重试／额度升级／结果操作调用链；没有修改 `card_type=0/1`、扫描接口、OCR／pHash、额度计算、订阅、候选、确认入库、Analytics、权限或路由。Figma 顶部没有搜索图标，因此仅移除该视觉快捷入口；既有 `/search` 路由及 No Match 卡片的 `Search Manually` 入口保持并由原测试继续覆盖。
- 布局兼容：扫描计数、额度提示和结果轨道使用固定 162px 下部状态槽，Free／Premium、扫描前／结果出现后均不移动取景框；底部安全区由快门区吸收，不再重复压缩取景框。iPhone 8、iPhone 12、大小屏 iOS 与 compact／small／large Android 的 Free／Premium 变体继续断言取景框、结果轨道和快门互不覆盖；取景框比例按设计精确使用 `254/363`。
- 本地验证：更新四张受扫描页样式影响的 390×844 Golden 后，`flutter test --no-pub --concurrency=1 --no-track-widget-creation test/widget/scan_page_test.dart` 在不更新 Golden 的复跑中 135/135 通过；四张图已逐张原样回读，未重录 Review Golden。显式使用当前 Flutter SDK 运行全量 `analyze --no-pub` 返回 `No issues found`。首次默认 `flutter analyze --no-pub` 约三分钟无任何输出后被主动终止，不计为通过；随后显式入口验证成功。
- 未执行：未制作 APK／IPA、未运行 iOS／Android 原生编译、模拟器或真机视觉验收，未执行 Git commit／push、dev/prod 部署、数据库或远程配置操作。本地 Golden 证明当前测试字体和 390×844 渲染输出，不证明真实相机画面、设备字体或所有系统安全区已由人工验收。

## iOS 测试环境内部安装包 1.0.6 (183)（2026-10-26）

- 构建输入：从构建前干净且与实时远端一致的 `codex/dev-1.0.7scan@fc7073fd747c97391cab8556d02df7f99a961ed5` 构建。分支名不会自动改变 App 营销版本；脚本按 `pubspec.yaml` 的 `1.0.6+182` 选择 `1.0.6 (183)`，完整保存后仅将工程版本同步为 `1.0.6+183`。dev health 在构建前返回 `{"status":"ok"}`。
- 环境与构建：最终内部 IPA 为 `com.kando.kandoApp.beta`，只包含测试 API `http://192.168.50.201:8080/api/v1` 与 Firebase `card-ai---test`，生产 API／Firebase 字符串不存在。Flutter 3.44.5／Dart 3.12.2／Xcode 27.1 下，发布脚本完成配置校验、锁定依赖解析、`flutter analyze`、`flutter clean`、test flavor Release Archive、App Store 基础 IPA 与内部 IPA 校验；analyze 无问题。根 `pubspec.lock` 与 iOS `Podfile.lock` 的 SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有依赖锁漂移。构建仅提示 `google_mlkit_commons`、`google_mlkit_text_recognition`、`sign_in_with_apple` 尚不支持 iOS Swift Package Manager；本轮 CocoaPods 安装和 Xcode 构建成功，未把未来兼容提示写成已解决。
- 签名与符号：IPA 的 Runner 与 42 个 Framework 共 43 个组件逐个严格签名校验通过，均为 `Apple Development: kancloud cq (578WZAD3DU)`；最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`。profile UUID 为 `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。IPA 的 43 个唯一 arm64 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，缺失／额外均为 0；45 个 DWARF 条目中两个是同 UUID 副本，不影响覆盖。
- 测试：首次运行扫描相关单元／组件完整集合时，179 项通过、5 个 390x844 Golden 像素比较失败；失败项均为 macOS 与现有图像基线差异，未修改或重录 Golden。明确排除这 5 个 Golden 后，以相同测试文件和 test 配置重跑其余 179/179 项通过。该结果不能写成完整集合全通过，真机 OCR／pHash 与真实识别服务仍未验收。
- 制品与边界：`Card AI Test.ipa` 为 42,972,634 字节，SHA-256 `056f20185ba55731e9f48bc937243114c83fae691cebd8336b48f67294dde156`；`dSYMs.zip` 为 63,896,903 字节，SHA-256 `c0e988e6bccf8d4ede7ca01f42aebf3b8798bfa6f26611db687cb6e0ef2127f2`，两份 ZIP 完整性通过。制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-183/`；完整保存后才将 179 移入废纸篓，当前保留 180、181、183。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push。

## Linux dev 重新部署（2026-10-26）

- 来源与授权：用户明确要求重新部署 kd201 dev。发布源为已推送且工作区干净的 `dev@19fd9e1fe853da33205e9df7e4274e49030eab61`；该提交是 `codex/dev-1.0.7scan` 合入 dev 的 merge commit。prod 未操作。
- 首次失败与保护边界：既有 watcher 获取目标提交并完成定向检查、Admin development 构建及 Linux API 打包，但发布预检因服务器私有 `shared/.env` 缺少新版本必需的 `PHASH_RECOGNITION_BASE_URL` 明确失败。失败发生在数据库备份、migration、容器重建和 `current` 切换之前；旧 release `branch-dev-675034ac3de6-20261022101743` 继续运行，不能把首次尝试写成部署成功。
- 配置补齐：在 watcher 锁保护下先备份私有配置为 `.env.20261026-161724.pre-phash`，权限保持 `600`，随后只补充仓库合同规定的非敏感 origin `PHASH_RECOGNITION_BASE_URL=https://recognize.tcgcard.fun`。原 `VECTOR_RECOGNITION_BASE_URL`、旧兼容键及其他私有值未改写，密码、Secret 和完整 `.env` 未写入日志或仓库。
- 首次成功发布：使用 `TOCCARDS_FORCE_DEPLOY=1` 复用现有 watcher、发布锁、预检、备份和应用回退流程。预检回读独立 `toccards_test`、PostgreSQL 18、两套识别服务可达且 `pendingMigrations=[]`；release `branch-dev-19fd9e1fe853-20261026162214` 成功切换，manifest、`current`、`shared/current-release`、`last-seen-sha` 和 `last-deployed-sha` 当时均与目标提交一致，失败标记清除。
- 重复部署纠正：为让 watcher 立即读取随后推送的纯验证文档提交 `6709b476c5b03b2b9f5d6d09f1af570b22a89e04`，Agent 错误地再次使用 `TOCCARDS_FORCE_DEPLOY=1`；该标志会绕过“无 Linux 部署影响”判断，因此发生了一次不必要但完整受锁、预检、备份和回退保护的第二次部署。最终 release 为 `branch-dev-6709b476c5b0-20261026164423`，上一 release 为 `branch-dev-19fd9e1fe853-20261026162214`；manifest、`current`、`shared/current-release` 和 `last-deployed-sha` 保持 `6709b47`，失败标记不存在。`6709b47` 只修改本文档，业务构建输入及最终 API／Admin 哈希与首次成功发布一致。后续本记录的纯文档纠正提交由正常 cron 判定为无 Linux 部署影响，只推进 `last-seen-sha`，不替换运行 release；不得再用强制模式推进纯文档基线。
- 数据与备份：首次发布前 custom-format 备份 `toccards-test-20261026-162217-before-branch-dev-19fd9e1fe853-20261026162214.dump` 为 1,136,064,025 字节；重复部署又生成 `toccards-test-20261026-164425-before-branch-dev-6709b476c5b0-20261026164423.dump`，大小 1,136,064,102 字节。两份备份均由独立 `pg_restore --list` 读取成功并各输出 351 行，未执行恢复演练。最终 migrate 容器 exited/0；ledger 保持 16 项，最新为 `0015_trial_conversion_status.sql`，两轮均没有新增或执行 migration。
- 运行产物与容器：DB、API 均为 running/healthy，Web running，三者重启计数均为 0。release 与运行容器的 API `server.mjs` SHA-256 同为 `1dd2f32060f49f38a7b255af100c7a425609239003264bdcc96f1dce97e9cdb8`；Admin `index.html` SHA-256 同为 `6dcb9513f6a21f0abe77f689000bbaabd78d32ce1be67037cd72ef2459ef0f14`。
- HTTP 与识别健康：服务器本机及开发机分别回读 `http://192.168.50.201:8080/api/v1/health` 为 200／`status=ok`，Admin 首页为 200 且包含 `Kando Admin` 标题，未登录 `auth/me` 为 401。API 容器只读回查向量 health 为 512／cosine／Top 5，pHash health 为 768／euclidean／Top 5／`cards_phash`，两者均返回 200；最近十分钟 API 日志未匹配 error、fatal、uncaught 或 unhandled。
- 验收边界：本轮未使用真实账号登录 Admin，未发送真实或合成识别请求，未验证扫描写库、额度、OCR 命中率、真实图片准确率、旧 App 安装包、iOS／Android 真机、外部回调或数据库恢复；没有执行 Git 业务代码修改、prod 部署、商店发布或生产数据操作。health、产物哈希和容器状态不等于上述业务闭环已经验收。

## 扫描记录 OCR 文本展示（2026-10-26）

基线为 `codex/dev-1.0.7scan@8f4763a4567b30d0f9964bfb3b1054e4cd420b9f` 加本地未提交增量。pHash/OCR 扫描把经过请求校验的文本写入既有 `scan_record.system_result.ocr_text`：有文本保存字符串，OCR 成功但无文本保存空字符串，OCR 缺失及旧向量请求保存 `null`。没有新增数据库字段或 migration；既有 Admin 扫描详情 API 原样解析 `system_result`，旧记录缺少该键时仍可读取。

Admin “扫描详情 → 系统识别结果”在现有候选数量右侧增加“OCR 文本”。字符串原样展示；`null`、字段缺失及空字符串均展示为空白，不使用通用的 `-` 占位，也不改变列表、筛选、候选卡牌或其他 Admin 模块。

实际本地验证：

- Workers `src/scan/routes.test.ts` 与 `src/admin/routes.test.ts` 共 2 文件／76 项通过，覆盖 pHash 文本规范化后持久化、OCR 缺失／空字符串、旧向量 `null`、Admin 详情回传。
- Admin 全量 Node 测试 78 项通过，其中新增意图测试约束 OCR 字段位置与空白展示；Admin TypeScript 检查通过。
- Workers 首次 TypeScript 检查因 `buildSystemResult` 参数未显式包含运行时已排除的 `null` 类型而退出 2；仅修正参数类型为 `string | null | undefined` 后，同一类型检查退出 0，并重跑上述 76 项通过。
- Admin development 构建通过：Vite 转换 1,526 个模块并生成静态产物。本轮未启动远端环境、未执行 migration／数据库写入、Git commit／push 或 dev/prod 部署；未以真实 Admin 登录态和现有扫描记录进行浏览器交互验收。

## 扫描 pHash／OCR 选择性集成（2026-10-26）

本地基线为 `codex/dev-1.0.7scan@8d8d2bb03e31af63b01e7f3e519fd3e6970e009b` 加未提交增量，来源为 `dev-xiangyang@2c56e9f12901c33d22684c869ac29d42f3ee77c3`。本轮未执行整分支 merge，只移植扫描识别、直接平台桥、依赖、双识别服务配置／预检及对应文档；版本号、订阅、Admin、历史归档回写和其他无关业务未引入。

当前 App 使用 RTMDet 矫正卡面，并行计算 RGB pHash 与 ML Kit Latin OCR，OCR 经规则化后作为可选 `ocr_text`；体育卡发送 `card_type=1`。当前 App 与线上低版本 App 均调用 `POST /api/v1/scan/recognize`：服务端只收到 `r/g/b` 字段组时转发到 `PHASH_RECOGNITION_BASE_URL`，只收到 512 维 `vector` 时继续使用 `VECTOR_RECOGNITION`，两组同时出现或均缺失时返回 422。当前 Flutter 源码不再构建旧向量识别；插件向量入口、额度、R2、目录补全、扫描审计和 confirm 契约保持。PE-Core 转换产物保留在 source-only 模型目录，但已从 Android/iOS bundle 与原生运行入口移除。

实际本地验证：

- Flutter 扫描相关测试：`flutter test --no-pub ...` 退出 0，共 173 项；覆盖 pHash 位序／Pillow 对照、OCR 规则化、OCR 失败降级、RTMDet 裁剪、API multipart、Sports `card_type=1`、额度／重试及 Scan 页面共享流程。
- 模型 bundle 清理后重跑核心 Flutter 测试，退出 0，共 23 项；针对性 `flutter analyze --no-pub` 退出 0。首次 analyze 因 `scan_text_recognizer_native.dart` 的冗余 `dart:typed_data` import 退出 1，删除该 import 后以相同范围重跑通过。
- Workers 定向测试：`src/scan/routes.test.ts`、`src/legal/routes.test.ts`、`src/linux/config.test.ts` 共 3 文件／70 项通过；覆盖同一路径的旧向量与当前 pHash 分流、双字段歧义拒绝、OCR 缺失／空字符串、非法哈希、Sports 类型、配置缺失释放额度、目录／审计及隐私披露。
- 按“当前源码只构建新协议、服务端兼容生产旧包”的边界将新旧请求收敛到原 `/scan/recognize` 后，重跑 Flutter API／编排 25 项、Workers 上述 70 项及 Workers TypeScript 检查，均退出 0；未新增第二条识别路由。
- Workers TypeScript 检查通过；Linux bundle 与 preflight 的 Node 测试 11 项通过。随后 `deploy:dry-run:dev` 再运行 bundle 3 项并完成 Linux 打包，明确未连接 SSH、未执行 migration 或部署。
- `pnpm test:app-compatibility` 退出 0：当前 PostgreSQL API 合同 8/8、固定 App 1.0.4+161 与 1.0.5+163 各 24/24。该编排不覆盖扫描；旧向量扫描兼容证据来自本轮 Workers 路由测试，不能把固定合同结果扩展为旧包真机扫描通过。
- `pnpm lint` 通过。生产 Worker dry-run 通过，保留 `VECTOR_RECOGNITION` Service Binding，并加入 `PHASH_RECOGNITION_BASE_URL=https://recognize.tcgcard.fun`；没有上传、切流或修改远端配置。
- Android test Debug APK 在接口收敛后重新构建通过：`apps/flutter-app/build/app/outputs/flutter-apk/app-debug.apk`，256,916,611 字节，SHA-256 `23f4448a1904e6758a6bd403eb17a082e896fddde36d4470db4c23c269ff8c8e`。包内断言确认 PE-Core 资源不存在、RTMDet 与 ML Kit OCR 资源存在。构建仅出现仓库既有 Gradle 8.12、AGP 8.9.1、Kotlin 2.1.0 的未来弃用警告，未在本任务升级工具链。

未验证与边界：

- Windows 无法执行 Xcode／CocoaPods／iOS 模拟器或真机构建；`Podfile.lock` 与 Xcode PE-Core 引用已按依赖和 bundle 变更更新，但 iOS 编译、签名、ML Kit Latin OCR、App Attest entitlement 和 IPA 解包仍待 macOS 补验。
- 未向 `recognize.tcgcard.fun` 发送真实或合成识别请求，也未实时回读其公开 health；preflight 使用受控测试服务验证 768/euclidean/Top 5/`cards_phash` 合同。真实图片准确率、OCR 命中率、弱网／超时、真机性能和外部服务当前状态未验。
- 未运行完整 Workers 默认测试、全仓 Flutter 测试、iOS 构建或真实旧 App 安装包扫描；未执行数据库 migration／业务写入、Git commit／push、dev/prod 部署或商店发布。

后续记录按时间倒序追加，并明确以下信息：

- 来源提交、工作区是否干净、目标环境与授权范围；
- 实际执行的检查、结果、失败、重试和未运行项；
- 本地、CI、dev、prod、商店与真机证据边界；
- 回退点、数据影响、外部平台影响及用户反馈是否由 Agent 独立复验。
