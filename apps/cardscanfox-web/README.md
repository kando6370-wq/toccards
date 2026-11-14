# CardScanFox 独立官网

CardScanFox 当前正式官网，独立于既有 `marketing-web`，保留原域名和网址。使用已确认的几何狐狸标识与浅色视觉。

## 当前实现范围

- 回收并导入线上 46 个已知网址的完整主内容。20 篇旧博客、3 个比较页和法律正文保持原路径；13 篇原 checkout 没有的文章已回收。
- 导入时检查源文件哈希和可见主文本，保留卡号、表格、日期、FAQ、链接和图片说明，清理旧脚本及事件属性。
- 新首页、卡种/系列目录、单卡、价格概览、工具、帮助、数据方法和本机 Saved 使用真实路径和服务端 HTML。
- 新首页重新编排产品内容；完整旧首页另保留在可阅读的原 App 介绍折叠区，后续正文编辑须单独评审。
- 原博客列表和卡表筛选可继续操作。旧网址、原 H1 和正文保持。按用户后续要求，`content/seo-pages.json` 已应用按搜索意图编写的标题和简介；`content/seo-proposals.json` 保留初版草案作对照。
- 独立只读数据服务支持本地捕获快照及新增 PostgreSQL 只读接口；默认预览仍读取 30 条真实捕获快照。单卡只提供固定 30 天摘要与 App 引导，不改变现有 App 的历史接口、订阅或额度。

按用户 2026-11-07 的要求，不建设官网管理后台、账号、角色、CMS 写接口或官网数据库。页面和文章在项目文件维护。正式站已接管原域名；后续生产变更仍需取得发布授权并完成独立验收。

## 本地运行

在仓库根目录安装锁定依赖：

```bash
pnpm install --frozen-lockfile
pnpm --filter @kando/website-service dev
```

另开一个终端：

```bash
pnpm --filter @kando/cardscanfox-web dev
```

官网：`http://127.0.0.1:8890`。只读服务：`http://127.0.0.1:8891/site-api/v1/health`。进程只绑定 loopback；使用 Ctrl-C 停止。端口可由 `CARDSCANFOX_PORT` / `SITE_DATA_PORT` 指定。

本地没有访问 App 生产 API 的自动回退。服务停止时 `/site-api/v1/*` 明确返回 503，已捕获的静态页面仍可阅读。

## 构建与检查

开发和必要文档完成后，按影响运行：

```bash
pnpm --filter @kando/cardscanfox-web build
pnpm --filter @kando/cardscanfox-web type-check
pnpm --filter @kando/website-service type-check
pnpm --filter @kando/cardscanfox-web test
pnpm --filter @kando/website-service test
pnpm --filter @kando/cardscanfox-web dry-run
pnpm --filter @kando/website-service build
pnpm lint
pnpm type-check
```

`build` 重新导入受保护源文件，生成全部已登记路径。`dist/route-manifest.json` 可查看候选路径。生成物不是手工编辑真源。

## 目录

- `content/legacy/`：获授权的旧站原 HTML 与捕获基线，用作可重复内容导入。不是运行日志或源码目录的实时替代。
- `scripts/import-legacy.mjs`：解析、清洗、保留正文并生成共享内容数据。
- `src/render.mjs`：独立路由与完整 HTML。原型的 hash 路由不进入这里。
- `public/`：本地字体、品牌、卡图快照和新版样式/交互。
- `worker/index.ts`：预览访问控制、响应头、静态素材与新只读服务绑定。Env 由 Wrangler 生成。
- `test/`：完整旧内容、链接、卡表、缺价、真实 404 及预览边界回归。

## Cloudflare 边界

正式官网由 Worker `toccards-website` 托管，Route 为 `tcgcard.fun/*`，生效配置为 `wrangler.production.jsonc`。正式 Worker 通过 `SITE_DATA` 绑定独立只读服务 `cardscanfox-site-data-preview`；不新增官网写接口或直接业务库写入。

私有 Worker 预览 `cardscanfox-website-preview` 与公开 Pages 预览 `cardscanfox-git-preview` 继续用于对比和发布前验证，不声明生产 Route/Custom Domain。私有预览的 `run_worker_first` 使 HTML 和素材都先经过预览访问控制。

私有 Worker 预览必须配置独立 `PREVIEW_USERNAME` 和至少 12 字符的随机 `PREVIEW_PASSWORD`，且不能使用示例值。缺少凭据时拒绝访问；版本 URL 也不应绕过这层检查。公开 Pages 预览使用独立入口，不要求 Basic 认证，但保留预览的 noindex／no-store 边界。不要提交 `.dev.vars`。

绑定 `SITE_DATA` 的服务目标是独立 `cardscanfox-site-data-preview`。只有取得目标环境授权后才创建/部署服务或设置远程 Secret。

预览响应 `noindex/nofollow`、`no-store`，robots 禁止抓取，预览不发布 sitemap、不提交 IndexNow。正式站使用真实服务模式并已启用 `PUBLISH_READY`；后续发布仍须遵守原 URL、缓存、访问控制和回退验证。

## 内容与数据来源

旧内容来自 `tcgcard.fun` 2026-11-06 的已知 sitemap 页面。当前只证明这些已知 URL 的迁入；非 sitemap、GSC 历史地址和外链仍需补齐。来源署名、App Store、支持邮箱与现有 App 名称使用真实状态。

卡图和价格为本地评审数据，原观测日期保留。生产再展示许可和读模型出口没有因本地实现而自动获批。禁止将用户扫描原图用作公开卡图。

规格入口：[CardScanFox 官网改版规格](../../docs/releases/v1.1.4/00-product/cardscanfox-website-redesign-spec.md)。

## 文件内容维护（无管理后台）

新文章登记在 `content/articles.json`，正文放在 `content/articles/`。构建会校验元数据、清洗后的 HTML、文件路径和来源，草稿不生成公开路由。示例（先保持 `published: false`）：

```json
{
  "path": "/blog/a-specific-collector-question",
  "file": "specific-question.md",
  "published": false,
  "title": "Answer a Specific Collector Question | CardScanFox",
  "h1": "Answer the collector’s specific question",
  "description": "Describe the concrete answer and the evidence a reader will find.",
  "category": "identity",
  "author": "Use the actual author or responsible organization",
  "publishedAt": "2026-11-07",
  "sources": [{"label": "Name the actual primary source", "url": "https://tcg.pokemon.com/"}]
}
```

分类允许 identity、values、collecting、comparisons、opinion。正文从二级标题开始；脚本、iframe、事件属性和危险链接会使构建失败。新文章不能占用旧 46 个受保护网址，也不能因改标题自动改路径。

`content/blog-topics.json` 是现有文章的明确分类登记。此次 Jev 分类请求返回 HTTP 451，没有使用其结果；分类按已有公开正文核对。构建与请求路由不依赖模型。

## 新只读服务接入

前端默认 `CATALOG_MODE=snapshot`，继续使用本地真实评审数据。指定 `WEBSITE_CATALOG_MODE=service` 启动本地前端后，目录、单卡、系列和首页通过 `SITE_DATA` 调用新增服务的 `/site-api/v1/page-data`，使用首个 HTML 渲染数据。旧文章和功能页不依赖数据服务。

`wrangler.service-preview.example.jsonc` 指向新增真实只读服务，同时保留认证和 noindex，未绑定正式域名。

真实模式没有自动回退到旧 App API 或评审价格。目录失败返回 503；首页保留产品内容并明确提示目录不可用。Saved 书签仍只存浏览器，服务模式可加载当前构建以外的公开记录。

## 构建交付与回退检查

`build` 先校验全部旧正文和新文章，在暂存目录完成后替换 `dist`。失败保留上一完整产物。`dist/release-manifest.json` 包含完整文件哈希、路由、受保护正文哈希、数据版本及新前后端源码/锁文件哈希；`.local/previous-dist` 保留上一构建。

```bash
pnpm --filter @kando/cardscanfox-web release:compare /absolute/current-release /absolute/candidate-release
```

该命令先校验两个 release 各自的文件哈希和文件登记，再比较路由清单；它拒绝缺失已有 URL，以及受保护路由的保护标记或 `sourceBodyHash` 变化。已合法登记的 JS、CSS、图片等资产差异不会仅因内容变化被拒绝，仍需结合构建差异和发布验收人工核对。回退也需同样对照；动态数据地址和非 sitemap 历史地址还需合并真实访问记录，不能只靠静态清单证明覆盖。

`content/index-policy.json` 在正式模式保留旧 46 页及已登记栏目的索引。单卡采用真实数据与身份完整性规则，合格详情可索引，无须手填几十万网址。Saved、草稿、搜索/筛选组合不进入 sitemap。

`wrangler.production.jsonc` 是当前生效的正式配置，目标为 `toccards-website`，Route 为 `tcgcard.fun/*`，并绑定独立真实只读服务。`wrangler.production.example.jsonc` 仅保留为未生效样例，不能作为当前生产状态或一次部署授权。正式响应移除预览认证，再按索引策略决定 robots；账号删除、Saved 等页面继续 noindex，公开内容按资格进入 sitemap；公开 API 拒绝评审快照。

手工正式构建前必须确认工作区干净且 HEAD 是批准的发布提交，将该提交的 40 位 SHA 注入构建环境，并排除优先级更高的旧 `CF_PAGES_COMMIT_SHA`。`build.mjs` 只从 `CF_PAGES_COMMIT_SHA` 或 `WORKERS_CI_COMMIT_SHA` 写入 `release-manifest.json` 的 `sourceCommit`；普通 `pnpm deploy:production` 不会自动注入该值。具体环境注入、生产命令和回读步骤以[生产切换记录](../../docs/releases/v1.1.4/05-delivery/cardscanfox-production-cutover.md#发布目标)为准。

## 单卡搜索意图与规模化 sitemap

`packages/website-content/src/seo.mjs` 根据实际卡名、编号、系列和价格状态生成 Title/Description。缺价不变成 0；无匹配历史时不写趋势承诺。卡牌、系列和文章保持一个明确的首选 URL，价格序列参数不扩成独立索引页。

`sitemap.xml` 正式输出 sitemap index，静态内容在 `/sitemaps/site.xml`。单卡分片由完整公开导出生成，默认每份至多 10,000 条，并检查 50,000 条/50MB 的协议上限。它不要求把几十万 HTML 文件打进一个 Worker 资源包。

```bash
pnpm --filter @kando/cardscanfox-web catalog:sitemaps --input=/absolute/catalog.ndjson --outdir=/absolute/catalog-sitemaps --max-urls=1000
```

`--games=pokemon,one-piece` 或 `--sets=某系列ID` 可指定首批范围。默认按稳定 ID 选取，不代表搜索热度；优先级需结合实际内容与 GSC 证据。

`--max-urls` 是本次发现预算，后续可扩大，不是索引总量上限。`--previous=/previous/catalog-sitemaps` 保留此前仍合格的网址；不允许因为调小预算而移除它们。身份或标题冲突会单独统计，不自动合并同名卡。报告包含缺失原因和元数据样例。

构建时通过 `CATALOG_SITEMAPS_DIR` 指向候选目录。构建校验全部分片哈希、主机、路径、条数与大小，失败不替换上一产物。未提供目录时不伪造全量卡牌 sitemap。`lastmod` 只用已知内容修改时间；缺失就省略，不使用构建日期全量刷新。

正式 HTML 加入按 Worker 版本隔离的缓存与 ETag/304，降低重复请求成本。预览、Saved、带身份头或参数的页面不进入公共 HTML 缓存。实际爬取压力仍需在真实只读目标测量。

更多规则见[单卡规模化索引方案](../../docs/releases/v1.1.4/05-delivery/cardscanfox-catalog-indexing.md)。目前没有读取 GSC 查询和收录基线，不宣称文案已提高点击率或所有卡牌已被收录。

## Git 自动部署

预览发布分支为 `codex/cardscanfox-preview`。只推送此分支不会推进 `main` 或 `dev`。`main` 已连接正式 Worker 自动构建，但只有提交命中 Cloudflare 当前配置的监听路径时才会触发；不得把任意一次 `main` 推送直接写成生产已发布。Cloudflare 目标账号固定为 `dced4adca2f35cff247b39979058b934`。原手工上传项目 `cardscanfox-preview` 保留用于对比。

新 Pages Git 项目 `cardscanfox-git-preview` 复用现有仓库连接。根目录 `/`，构建命令 `pnpm --filter @kando/cardscanfox-web --fail-if-no-match build:ci`，输出目录 `apps/cardscanfox-web/dist`。当前仓库要求 Node `^22.23.4`、pnpm `11.28.10`；远端构建环境版本仍须从实际部署回读。构建失败不替换上一成功部署。Pages 发布清单记录 `CF_PAGES_COMMIT_SHA`，用于回读核对实际发布提交。

Pages 构建命令生成 `_worker.js` 和全路径 `_routes.json`，通过 `SITE_DATA` Service Binding 取得真实目录并服务端渲染。2026-11-07 初始预览有 108 个静态构建条目；当前静态构建条数以 `dist/release-manifest.json` 为准，单卡动态地址不限于原 30 条评审记录。公开 Pages 预览维持 noindex/no-store、robots 禁止抓取；独立 Workers 入口仍保留 Basic 认证。数据失败返回 503，首页保留产品说明，不以旧快照替代真实价格。

提交、Cloudflare 自动构建和线上生效是三个独立状态。每次正式发布都要回读活动 version/deployment，并核对线上 `/release-manifest.json` 的 `sourceCommit` 与批准提交一致；只看到 Git 推送或构建记录不能宣称生产已更新。

新只读服务使用独立 Workers Builds，配置见 `apps/website-service/README.md`。新增数据服务复用正式库现有 Hyperdrive；原 App 代码、接口和绑定配置不修改。正式域名切换与索引开放分别管理。

`worker/pages.ts` 是 Pages 的独立入口。Pages 项目的生产环境需设置 `SITE_DATA` → `cardscanfox-site-data-preview`，兼容日期为 2026-11-07，并开启 `nodejs_compat`。`wrangler.pages.jsonc` 记录同一配置供显式 CLI 使用；Git 项目的根目录仍是仓库根，运行时绑定按控制台配置生效。`build:pages` 在暂存目录完成服务端包编译后才替换完整产物。

真实模式下，先选择系列并应用筛选，再提供按名称、价格和观测日期排序。全库浏览和关键词搜索仍使用目录顺序。价格页也提供系列选择。

## 用户问题与目录暂时繁忙

2026-11-10 的答案方案继续使用现有网址、卡表和检索入口。首页保留 TCG 与体育卡范围，直接区分网页文字查价、Card AI iPhone 扫描和独立 Chrome 扩展。Android 仍按当前正式下载状态标注 coming soon。Mew 152/128、151/165 与 Bubble Mew 232/091 分开说明；角色名、清单条目和缺失价格不自动构成相同印次或完整覆盖。

旧页可见的 `faq-item` 是对应 FAQPage 的唯一文本来源；`scripts/import-legacy.mjs` 在导入时生成等价结构化数据。首页、查价、Mew 与 Manga 系列的新增问答由 `content/answer-faqs.json` 同时生成正文与 Schema。获批修改的旧页在 `source-baseline.json` 保留前版哈希和本轮批准记录；卡表行、卡号和历史价格观察日期继续保留。

目录服务限流或不可用时，HTML 仍返回 503；上游 429 显示暂时繁忙说明，并保留合法的 `Retry-After`。未知故障保持一般不可用说明。首页产品正文可用时继续返回 200，并显示目录状态；不回退成评审价格，不自动重试。直接 `/site-api/v1/*` 响应继续保留上游状态。日志仅记录受控原因与状态，不记录上游正文或连接信息。

此改动不调整数据服务的每数据中心 30 次/60 秒配置阈值，也不把该近似阈值称为全网硬上限。历史批量 503 还可能来自其他故障；低频地址恢复正常不证明全部历史失败均由限流引起。

## 账号删除申请

`/Account/AccountSetup` 保留公开删除入口与 noindex 策略，Help 和页脚可进入。用户选择 Android／iOS、填写账号邮箱后，页面专用脚本 `/assets/account-deletion.js` 在本地准备邮件草稿或复制文本；不向官网提交账号资料，也不调用删除 API。草稿不是已发送或已受理，剪贴板不可用时提供手动复制回退。输入变更会清理旧草稿，iOS 订阅不自动取消的说明只在对应平台显示。

无法使用原账号邮箱或没有 JavaScript 时，仍可通过固定客服邮箱和人工协助模板申请。客服核验、超级管理员受控执行、第三方数据处理和处理时限属于独立运营环节；本轮不新增 Admin Web 删除按钮或官网写服务。设计、实际实现和验收边界见[方案文档](../../docs/releases/v1.1.4/00-product/cardscanfox-account-deletion-design.md)。


## 免费额度与推荐依据

`content/answer-faqs.json` 的 `/help` 问答在首页、App、下载和帮助页复用，并生成等价 FAQPage。累计 10 次免费成功扫描与 10 张独立图片的队列容量分开说明；失败与无匹配不消耗成功额度，Premium 条件由 App 内实际报价说明。Android 未公开发布，独立 Chrome 扩展使用真实名称 TCG Card Recognizer。

获批正文更正只更新相应 `source-baseline.json` 条目，并保留前版批准哈希，不全量重设保护基线。当前目录、榜单、账号删除与分阶段索引策略保留。功能与来源可以支持有范围的引用，识别性能和竞品优劣仍需真实同条件证据。
