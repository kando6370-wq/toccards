# CardScanFox 独立预览与自动部署

新版官网与只读服务使用现有 monorepo 中的独立应用，不修改旧营销站、App API、Flutter 或现有发布配置。独立 Git 分支 `codex/cardscanfox-preview` 从 `origin/main` 建立，仅包含新版官网、只读服务、共享公开内容包、工作区登记和必要文档。原工作区的未提交改动保留。

## 自动部署配置

Cloudflare 账号：`dced4adca2f35cff247b39979058b934`。复用已存在的 GitHub 连接 `kando6370-wq/toccards`，不建立第二套 App 业务接口或新 CMS。

| 目标 | 发布分支 | 根目录 | 构建命令 | 输出或部署 |
|---|---|---|---|---|
| Pages `cardscanfox-git-preview` | `codex/cardscanfox-preview` | `/` | `pnpm --filter @kando/cardscanfox-web --fail-if-no-match build:ci` | `apps/cardscanfox-web/dist` |
| Worker `cardscanfox-site-data-preview` | `codex/cardscanfox-preview` | `/` | `pnpm --filter @kando/website-service --fail-if-no-match build:ci` | `pnpm --filter @kando/website-service --fail-if-no-match deploy:preview` |

Node 22、pnpm 11.9.0；禁用其他分支的预览构建。Pages 监听 `apps/cardscanfox-web/*`、`apps/website-service/*`、`packages/website-content/*`、`pnpm-*.yaml`、`package.json`。只读 Worker 监听相同范围中除官网应用目录之外的路径。构建包含受影响测试、类型检查和打包。失败保留上一成功版本。Pages 清单 `sourceCommit` 与 Cloudflare 部署的提交 SHA 应一致。

## 当前预览边界

原 `cardscanfox-preview.pages.dev` 为已上传的静态对比版本。新 Pages Git 项目通过 `build:pages` 生成服务端入口，使用 `SITE_DATA` binding 动态查询正式目录。108 个静态构建条目包括 46 个保护旧地址、32 个新增非单卡页面、30 个单卡评审页面；真实单卡地址不受这 30 条评审数据限制。

只读 Worker 当前通过现有正式库 Hyperdrive 执行只读事务，关闭公共域名与版本 URL。旧 App Worker、接口和绑定配置不修改。新服务与 App 复用数据库账户权限和连接池；独立限频、缓存与超时减少新增读取压力，不等于生产性能已经通过验收。正式域名切换与全量索引开放分别管理。预览维持 noindex、robots 禁止抓取，不提交 IndexNow。

## 内容真源

沿用本任务的[改版规格](../00-product/cardscanfox-website-redesign-spec.md)、[独立服务规格](../02-architecture/cardscanfox-website-service-spec.md)、[路由与搜索意图](../05-delivery/cardscanfox-website-route-seo-spec.md)及[单卡规模化索引方案](../05-delivery/cardscanfox-catalog-indexing.md)。旧归档代码与文档不因这次配置而回写。

## Pages 运行配置

Pages 项目的 `SITE_DATA` 绑定到 `cardscanfox-site-data-preview`，兼容日期 2026-11-07，开启 `nodejs_compat`。公开预览仅服务公开目录；独立 Worker 入口仍要求 Basic 认证。Git 构建生成 `_worker.js` 和包含全路径的 `_routes.json`，目录请求不能绕过服务端直接落到旧评审 HTML。发布清单仍可从 `/release-manifest.json` 回读。

## 价格区间修正

正式数据库集成阅读发现，价格展示投影把 micros 转为 text，而金额区间仍直接与整数比较，会触发 PostgreSQL 类型错误。区间比较改为显式 bigint；金额输出和零价语义保持。新增数据库回归覆盖低于 20、20 到 100、高于 100 三段。开发完成后在隔离 PostgreSQL 中回放修改前源码，同一低价筛选触发 42883；修后 39 项官网、26 项服务测试及类型/打包通过。Code Review 已核对金额类型、GET/HEAD 边界、预览访问控制、缓存版本与数据库读取预算；原 App 不在修改范围。

## 正式目录查询的索引匹配

真实接入先确认 health 正常；列表和单卡价格曾在 2.15–2.24 秒返回 503，日志为 PostgresError。阅读现有生产 migration 发现 `idx_price_series_card_qualifiers` 的谓词为 `WHERE is_active`，新服务使用 `is_active IS TRUE`。隔离 PostgreSQL 以 20,000 条价格数据执行实际查询计划，修改前对 `price_series` 做 Seq Scan，改用既有谓词后能使用部分索引。只调整新服务的条件表达式，不执行生产索引或 schema 变更。新增计划回归保护此索引；日志只增加 SQLSTATE 和耗时，不记录连接串或 SQL 参数。部署后按原请求回读，列表、详情、搜索、系列页与 30 天历史均返回 200。Charizard 714372 的当前价 125.41 USD、观测日 2026-11-07 与原正式接口一致；30 天历史返回 29 个点。原 30 条评审数据以外的卡牌 100 也取得真实服务端 HTML。局部计划和这些样本不代替全库性能或 App 真机验收。

该索引修正的 27 项服务测试、类型检查与 dry-run 已通过。Code Review 确认布尔谓词在 WHERE 中保持相同筛选语义，新增测试使用实际查询计划核对既有索引；日志不包含凭据或 SQL 参数。没有运行无影响面的 App／Admin／Flutter 测试。

## 浏览与排序范围

真实目录的默认浏览、关键词搜索与分页不要求选择系列。按名称、价格或观测日期排序要求先选择系列；目录和价格页显示这一操作并按范围提供排序选项。未限定系列的排序请求返回 400，不执行遍历全库的排序 SQL。真实接入中，无系列的全局价格排序曾触及查询预算而返回 503，因此不把它暴露为可用选项。指定系列时同时增加所属游戏条件，以复用现有目录索引，不修改生产索引。真实目录的空结果文案不再声称只有 30 条评审数据。

范围排序与真实空状态调整后，40 项官网、28 项服务测试、类型检查和打包通过。Code Review 核对服务端必须选择系列的限制、前端排序选项、系列与所属游戏条件，以及零价/缺价、旧正文和私有 Worker 认证边界。原 App、Admin、Flutter 和旧营销站没有源码或部署配置变更。

## 目录统计、双向分页与价格榜单

官网独立服务新增 `SITE_CACHE` KV，仅保存公开目录统计与价格榜单，不保存账户、持仓或业务写数据。缺失 namespace ID 时由已固定目标账号的 Wrangler 自动创建，首次创建后应回读并固定 ID。旧 App 的 KV、数据库 schema、接口、生产 Worker 与已有调度不修改。

新增服务每 5 分钟检查缓存；成功快照未满 1 小时则不读数据库。刷新使用单个只读一致性事务，顺序生成目录统计、近七天涨幅和近期最高价 Top 100。后台单语句上限 30 秒、总预算 110 秒；普通目录请求仍为 1.5 秒/4.5 秒。失败保留上一完整快照，15 分钟后再试。榜单请求只读快照，不执行全库排名 SQL。

两榜仅纳入启用卡种中有卡图、有卡号的单卡，排除密封产品与评级价；币种 USD，裸卡成色为 NM 或来源未指定。每个卡牌记录保留一个符合条件的价格序列，展示其语言、工艺和来源；链接携带 series 以便详情保持同一价格维度。涨幅按同一序列的精确七日正百分比排序，零/缺失基准排除；高价榜按最新七日窗口内的已发布当前金额排序，不称为拍卖纪录。

普通目录只列有卡图的单卡，与原 App 的公开单卡目录规则一致。统计按同一范围生成，普通、卡种和系列浏览可显示统计时点的总数/页数。搜索或多维筛选未取得可靠总数时显示当前页和双向按钮，不伪造总页数。`after`/`before` 游标互斥，按同一 ID 顺序读取；带游标时不再叠加 OFFSET。价格页固定 48 条，避免前后页大小不一致导致跳过记录。

页面任务与元数据见 [逐页搜索意图](../05-delivery/cardscanfox-page-intents.md)。

本轮开发完成后，官网 43 项、服务 34 项测试通过，相关类型检查和打包通过；索引/排名/分页逻辑使用隔离 PostgreSQL 验证。机械设计检查提示关闭的图片预览容器默认 img 与 HTML 正则匹配两项 warning；前者只在打开时设置图片，后者是正则表达式，不是页面图片元素。两项为已有实现的明确例外，未扩展为无关重构。Code Review 核对双向游标不叠加 OFFSET、统计范围与单卡过滤一致、排名不混成色/评级/时间窗口，以及预览不开放索引和旧正文保留。

首次部署已创建并回读独立 KV `cardscanfox-site-data-preview-site-cache`，ID `dfe3ba256b38476ea575654d983c7ead`，现已固定到新服务配置，后续发布复用同一公开快照缓存。
