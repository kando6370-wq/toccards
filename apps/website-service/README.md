# 官网独立只读服务

按用户要求新增官网服务，复核既有 App 后端的表结构与已发布价格规则。没有修改 `apps/workers-api`、原 Admin、Flutter、旧 V1、迁移或原生产绑定。没有新增 CMS、官网账号、管理写接口或数据库。

## 两种运行方式

- `CATALOG_MODE=snapshot`：本地评审模式，30 条真实捕获记录。只读，不连接数据库，不代表全库。
- `CATALOG_MODE=postgres`：当前远程配置。按用户 2026-11-07 的接入要求，新增服务复用正式库现有 Hyperdrive `tcg-cards-db`（ID `7d71bcd0bcf64e518a23a852ced76d66`），独立封装现有查询规则。原 App Worker、旧接口和原绑定配置不修改。

本地默认：`pnpm --filter @kando/website-service dev`，监听 `127.0.0.1:8891`。

真实本地模式从专用环境变量 `SITE_CATALOG_DATABASE_URL` 取连接串；不要把原业务写凭据复制到这里，不把连接串放在命令行或源码。前端以 `WEBSITE_CATALOG_MODE=service` 对接新服务。未配置连接时明确返回 503，不转发旧业务 API。

## 新接口

公共前缀 `/site-api/v1`。仅 GET/HEAD；其他方法 405。

| 地址 | 功能及参数 |
| --- | --- |
| `/health` | 数据模式、版本与服务状态。真实模式实际读取目录元数据。 |
| `/games` | `games.load=1` 的可浏览游戏。未知数量为 null。 |
| `/cards`、`/prices` | q、game、set、language、finish、price、sort、page、pageSize、after。pageSize 1–48；q 最长 128；page 1–500。 |
| `/cards/{id}` | 完整字符串 ID、印次、参考价、来源/指标/观测日。可用 `series` 选择明确的公开价格上下文。 |
| `/cards/{id}/trend` | 只接受 `days=30`；可传 series。condition/grader/language/finish 若传入，必须与选定序列一致，不隐式换价。 |
| `/sets` | q、game、page、pageSize。系列源数量与独立核实数量分开。 |
| `/sets/{id}` | 系列身份和对应卡牌分页。 |
| `/page-data` | `path` 加相应筛选参数，单次只读事务取得一个页面所需元数据、结果、所选卡牌和同维度趋势。 |

price：all、available、missing、under20、20to100、over100。sort：featured、name、recent、price-asc、price-desc。featured 使用 product_id 稳定排序并支持 after 游标；其他排序使用受限页码。缺价固定放末尾，0 是有效金额。

真实分页返回 total=null、totalKind=not-computed、returnedCount、hasMore、nextPage、nextCursor。不执行每次全库 COUNT，不把本页条数当总数。响应元数据包含 requestId、catalogVersion、snapshotCapturedAt、datasetMode。真实 catalogVersion 仅标识价格发布指针，versionScope=price-publication-pointers、directorySnapshot=false；目录没有全局发布版本，不声称跨请求是一致快照。

错误区分 400 非法参数、404 真实不存在、503 数据库/预算/数据质量不可用。未知参数、重复参数和超过 30 天的请求被拒绝。失败不伪装成功空结果。

## 只读查询与价格语义

- 仅查询 cards_all、games、sets、price_source、price_series、price_ingest_batch、current_price_pointer、price_current_snapshot、price_history_month。
- 价格必须来自有效来源、有效序列、USD，以及当前指针指向的 published 批次。草稿批次、停用来源或停用序列不公开。
- 列表默认在 Raw 中按既有 App 的 NM、EN、Normal 优先级，再以 30 天变化、观测日期及固定来源/序列键选择，并公开所选来源、metric、语言和工艺。语言/工艺筛选先限定候选序列，再选择价格。
- 详情可选同一卡牌的明确 series；跨卡牌选取被拒绝。评级价与 Raw 不混用。
- 趋势同一 series、同一确认维度，以价格观测日为末日的 30 个自然日，只读取有效发布链中的月历史；缺口不补线，不生成预测点。页面没有逐日表或悬浮明细。
- micros 原值使用字符串输出；安全范围内才转换为展示金额，精度异常直接失败，不静默四舍五入成另一价格。
- 每次数据库操作是 `REPEATABLE READ READ ONLY` 事务；每次请求的客户端最多 2 个连接，单语句超时 1500ms、锁超时 750ms，并检查 4500ms 操作预算。不运行迁移、DDL、业务写入或任意客户端 SQL。
- Cloudflare 内部成功响应缓存 60 秒；错误和 health 不缓存。缓存键含部署版本与规范参数，不含账户数据。命中缓存不消耗数据库读取预算；未命中时，独立原生限频 binding `CATALOG_READ_BUDGET` 每个 Cloudflare 数据中心最多放行 30 次/60 秒，超出返回 429，不连接数据库。此限频不是全网统一并发上限。公开 API 响应保持 no-store；原 V1 缓存语义不变。

这些是代码默认上限，不是生产容量证明。当前复用同一 Hyperdrive 和原账户权限；只读事务限制本服务的 SQL 行为，不能表述为数据库账户已降权或连接池已完全隔离。数据库读取会占用生产资源；没有复制连接密码、创建账号、修改旧池上限、执行迁移或写业务数据。

## Cloudflare 配置

`wrangler.jsonc` 使用正式库的现有 Hyperdrive，关闭 workers.dev 和版本 URL，经新官网的 `SITE_DATA` binding 访问。绑定只出现在新服务中；原 App 配置保持原样。

`wrangler.database.example.jsonc` 是真实只读模式的待配置样例。Hyperdrive ID 为全零占位值，必须换为专供新服务的获准只读连接；不能复用原业务写连接。该文件没有实际远程资源，不可直接作为发布完成的证据。运行绑定由适用配置的 `wrangler types` 生成，不增加 D1。

独立预览 Worker 已建立 Git 构建连接。本次新增正式库绑定和读取预算；没有创建新 Hyperdrive 或账号。远程接通及性能结果以实际发布回读为准，代码配置本身不是成功证据。

## 可重复导出

可从新增服务导出一次完整游标遍历结果，用于核对。它不是跨请求的数据库一致快照；completeTraversal=true、consistentSnapshot=false，仍须单独核对目录变更和完整性：

```bash
pnpm --filter @kando/website-service export:snapshot --output=/absolute/new-snapshot.json --max-pages=20
```

`SITE_DATA_EXPORT_URL` 指向新增服务的 `/site-api/v1/`；默认 loopback。接口凭据只能从专用环境变量读取。该命令串行、按 after 游标读取，必须显式给页数预算；版本变化、重复游标、读取失败或预算耗尽均不替换已有文件。导出只含公开数据，publicationApproved 默认 false，不自动上线或开放索引。

## 验证范围

开发及文档完成后，运行本服务测试、类型检查、Wrangler 打包和受影响官网检查。PostgreSQL 查询使用隔离的本地 PostgreSQL 引擎和测试数据验证，不能据此宣称远程目标的权限或性能已通过。原 App 代码不变时不运行无关全量 App 回归。

几十万记录推荐流式格式：

```bash
pnpm --filter @kando/website-service export:snapshot --output=/absolute/catalog.ndjson --format=ndjson --max-pages=10000
```

NDJSON 按页写入临时文件，内存不累计全部原始对象。结尾包含完整遍历标记，成功后原子替换；失败仍保留旧文件。官网 sitemap 工具会拒绝没有结束标记的文件。该命令有显式读取预算，真实源和预算未批准前不执行远程导出。

## Git 自动部署

目标账号 `dced4adca2f35cff247b39979058b934`；仓库 `kando6370-wq/toccards`；发布分支 `codex/cardscanfox-preview`；Worker 名 `cardscanfox-site-data-preview`。根目录 `/`，构建命令 `pnpm --filter @kando/website-service --fail-if-no-match build:ci`，部署命令 `pnpm --filter @kando/website-service --fail-if-no-match deploy:preview`。构建环境 Node 22、pnpm 11.9.0。关闭非发布分支构建。

监听目录为 `apps/website-service/*`、`packages/website-content/*`、`pnpm-lock.yaml`、`pnpm-workspace.yaml`、`package.json`。当前配置复用正式库 Hyperdrive，关闭 workers.dev 和版本 URL，不包含数据库密码或迁移。此接入使用原账户权限和本服务只读事务；独立数据库账号与连接池不是已完成能力。
