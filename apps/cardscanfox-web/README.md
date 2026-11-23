# Card AI 独立官网

Card AI 正式官网，独立于既有 `marketing-web`，沿用原域名和网址。使用交付包中的 Card AI 标识和浅色布局。

## 当前实现范围

- 回收并导入线上 46 个已知网址的完整主内容。旧内容保留在导入真源；除下述已合并查价页外，文章、比较页和法律正文保持原路径；13 篇原 checkout 没有的文章已回收。
- 导入时检查源文件哈希和可见主文本，保留卡号、表格、日期、FAQ、链接和图片说明，清理旧脚本及事件属性。原始快照用于核验，生成的正文、署名和元数据统一使用 Card AI。
- 新首页、卡种/系列目录、单卡、价格概览、工具、帮助、数据方法和本机 Saved 使用真实路径和服务端 HTML。
- 新首页重新编排产品内容；完整旧首页另保留在可阅读的原 App 介绍折叠区，后续正文编辑须单独评审。
- 原博客列表和卡表筛选可继续操作。按已批准的内容修订维护正文；通用 Pokémon 查价博客合并到中心页，见下节。按用户后续要求，`content/seo-pages.json` 已应用按搜索意图编写的标题和简介；`content/seo-proposals.json` 保留初版草案作对照。
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

2026-11-10 的答案方案继续使用现有网址、卡表和检索入口。首页保留 TCG 与体育卡范围，区分网页文字查价、手机 App 扫描和独立 Chrome 扩展。2026-11-23 起，首页与下载页的 Android 按钮指向 `com.cardai.tcg` 的 Google Play 正式商品页。Mew 152/128、151/165 与 Bubble Mew 232/091 分开说明；角色名、清单条目和缺失价格不自动构成相同印次或完整覆盖。

旧页可见的 `faq-item` 是对应 FAQPage 的唯一文本来源；`scripts/import-legacy.mjs` 在导入时生成等价结构化数据。首页、查价、Mew 与 Manga 系列的新增问答由 `content/answer-faqs.json` 同时生成正文与 Schema。获批修改的旧页在 `source-baseline.json` 保留前版哈希和本轮批准记录；卡表行、卡号和历史价格观察日期继续保留。

目录服务限流或不可用时，HTML 仍返回 503；上游 429 显示暂时繁忙说明，并保留合法的 `Retry-After`。未知故障保持一般不可用说明。首页产品正文可用时继续返回 200，并显示目录状态；不回退成评审价格，不自动重试。直接 `/site-api/v1/*` 响应继续保留上游状态。日志仅记录受控原因与状态，不记录上游正文或连接信息。

此改动不调整数据服务的每数据中心 30 次/60 秒配置阈值，也不把该近似阈值称为全网硬上限。历史批量 503 还可能来自其他故障；低频地址恢复正常不证明全部历史失败均由限流引起。

## 账号删除申请

`/Account/AccountSetup` 保留公开删除入口与 noindex 策略，Help 和页脚可进入。用户选择 Android／iOS、填写账号邮箱后，页面专用脚本 `/assets/account-deletion.js` 在本地准备邮件草稿或复制文本；不向官网提交账号资料，也不调用删除 API。草稿不是已发送或已受理，剪贴板不可用时提供手动复制回退。输入变更会清理旧草稿，iOS 订阅不自动取消的说明只在对应平台显示。

无法使用原账号邮箱或没有 JavaScript 时，仍可通过固定客服邮箱和人工协助模板申请。客服核验、超级管理员受控执行、第三方数据处理和处理时限属于独立运营环节；本轮不新增 Admin Web 删除按钮或官网写服务。设计、实际实现和验收边界见[方案文档](../../docs/releases/v1.1.4/00-product/cardscanfox-account-deletion-design.md)。


## 免费额度与推荐依据

`content/answer-faqs.json` 的 `/help` 问答在首页、App、下载和帮助页复用，并生成等价 FAQPage。iPhone 的累计 10 次免费成功扫描与 10 张独立图片的队列容量分开说明；失败与无匹配不消耗成功额度，Premium 条件由 App 内实际报价说明。Android App 通过 Google Play 分发。独立 Chrome 扩展使用名称 TCG Card Recognizer。

获批正文更正只更新相应 `source-baseline.json` 条目，并保留前版批准哈希，不全量重设保护基线。当前目录、榜单、账号删除与分阶段索引策略保留。功能与来源可以支持有范围的引用，识别性能和竞品优劣仍需真实同条件证据。

## 2026-11-15 答案页与品牌归属

DCC 直接提供发行方 #001–100 卡表、包内容、产品区分、购买渠道和带日期价格。两篇现有周年文章分别负责 UPC 产品与 191 张主集/RGB/Classic 单卡清单和带日期价格，不新增周年 URL。

`/games/pokemon` 是通用 Pokémon 查卡/查价中心；`/pokemon-card-scanner` 是拍照工具页。旧 `/blog/pokemon-card-values` 的角色指南表、编号读法与价格日期说明迁入中心页，其干净 URL 和 `.html` URL 通过 `src/redirects.mjs` 返回 301。查询参数保留。旧源文件留作可复现内容导入；该地址不生成重复 HTML、不进入 sitemap 或索引 allowlist。既有 release:compare 会将这次有意的路径合并和正文更新列为差异，不能宣称无变化通过。

网页品牌、按钮、作者和发布者统一为 CardScanFox。下载页明确现有 App Store 名称为 Card AI: TCG Card Scanner；真实商店 URL、法律正文与账号删除身份保持对应既有应用。

后续内容先指定唯一页面归属，优先维护卡价、各系列扫描及比较页面；每页给具体答案及来源日期，避免同意图重复建页。外链工作需另按渠道和实际接受结果实施，不把提交记录当作已获得链接。本轮不请求编入索引、不提交 IndexNow。当前只完成本地修改，正式站状态不能据此更新。

## 网页扫描首批（2026-11-15，本地候选）

`/pokemon-card-scanner` 与 `/sports-card-scanner` 在本页提供单张照片选择、相机文件入口、端侧模型推理、候选比较及同页文字查询。首次主动识别才加载约26 MiB模型和WASM，初始页面不下载模型。主标题、可索引内容和普通文字查询均服务端输出；模型不会生成卡名、价格或评级。

`POST /site-api/v1/recognize` 只接受512维有限非零向量及TCG=0/Sports=1类型，可选`game=pokemon`仅过滤TCG；照片不发送到识别网关。官网Worker通过独立`WEB_VECTOR_RECOGNITION`绑定调用现有`recognize-vec/production`，通过既有`SITE_DATA`补已发布详情。绑定未配置时新入口503，限频429，目录失败明确503，缺价保持缺价。现有App鉴权、额度、扫描记录、R2及目录数据库均不写入。

本地候选配置新增独立`WEB_SCANNER_RATE_LIMITER`：6次/60秒/IP；preview namespace=2026111501，production namespace=2026111502。未修改已有目录预算：一次识别最多读取5个详情，目录现有预算仍可能先触发。照片仅在浏览器处理；向量和公开详情请求联网，不声明完全离线。扫描页单独允许WASM执行和blob图片，其他页面保持原CSP。

同页文字查询由官网将读取映射至既有`/page-data`契约，不为只读目录服务新增写接口。静态本地服务器只增加POST body转发和MJS/WASM MIME；没有将客户端自报IP作为可信CF IP。默认本地预览不伪造生产绑定，缺少绑定时页面会显示服务暂不可用；真实端到端匹配须在具有绑定的获授权环境验收。

AI Grade尚未实现，用户已确认本批只做网页扫描与SEO。未建立AI评级工具页，不用已有slab评级字段冒充照片预测。低量卡种页、卡页和已有曝光URL不在本批批量删除、301或noindex范围。月搜/KD/DR/外链预算仍须匹配原报告口径；本批不宣称进前十或流量收益。

## 页面合并与内容侧第二、三步（2026-11-16，本地候选）

`/card-identifier` 是通用 TCG 扫描与文字查询 owner，复用网页模型和既有只读识别网关。照片请求为 `card_type:0` 且不带 `game`；Pokemon 专用模式仍为0加`game:pokemon`，体育模式仍为1。通用文字查询从真实 `/games` 选择可用 TCG，在分页前按游戏筛选；不会把体育记录混入通用 TCG 候选。

Digimon、Lorcana、Dragon Ball Super、Flesh and Blood 四个旧路径及 `.html` 别名单跳301到 `/card-identifier` 对应章节。`redirectLocation` 保留查询参数并置于fragment之前；旧正文留在导入源中，不作为重复正文发布。活跃站内链接直接到新owner章节，旧地址退出静态HTML、sitemap和allowlist。四页曾有曝光，因此这是有信息迁入的意图合并，不记作无曝光页面删除；不承诺排名信号即时转移。Dragon Ball Super覆盖未确认状态继续明确保留。

MTG、One Piece、Basketball和Football保留独立URL与H1，补充各自编号、印次、语言/工艺、serial/parallel和误配恢复流程，并指向适合的网页工具。Football不改成已确认支持。

周年卡价页保留191卡和原价格日期，在本页直接补充购买single、random booster、UPC固定promo的选择与官方零售商入口；UPC产品详解继续由现有独立页承接。`/games/pokemon` 保持真实发布价格读取，增加名称/编号、已有价格、周年卡表、扫描和估值指南导航，不改价格来源或生成金额。

卡页索引部分核对原始URL证据：142个许可卡页为82个有记录曝光卡和60个内容引用种子；后60个不能称为已核实有月搜索量。原发现批次的1047个暂停卡页继续保持无索引资格，详情可访问规则不改。本轮不再按65/66个地图卡数推断数据库太薄，也不把未见曝光当作永久零需求。既有品牌统一继续沿用。

## 网页预评级与同页价格查询（2026-11-16）

`/ai-card-grading` 使用官网独立 `POST /site-api/v1/pregrade`。前后两张照片经浏览器去原始元数据、压缩，再交 `WEB_PREGRADING_AI` Workers AI Scout 做可见状况判断。新增两个独立原生限频绑定；没有 App 登录、订阅、扫描记录、图片持久化或数据库变更。缺新绑定时明确 503；普通 Node 本地开发不模拟云模型，不会把目录匹配置信度当分数。真实模型验收需具备 Workers AI 的环境，不能把接口替身测试当作推理验收。费用和留白计算为常规代码。

`/card-price-checker` 在本页读取现有发布目录，只有有关键词或具体套卡才查询。价格仍受条件、来源、语言、工艺和日期约束。热门目录示例真源为 `content/pregrading-catalog-examples.json`，不是实物预评级样卡；不要给目录图编造背面或分数。

协议、费用来源、模型限制、配置与回滚范围见 [页面意图文档](../../docs/releases/v1.1.4/05-delivery/cardscanfox-page-intents.md#网页-ai-预评级与价格查询2026-11-16-后续增量)。构建会重新导入本批已批准的能力文案与隐私用途修改；旧发布记录和未验证项保持历史口径。

### 自动居中与评级参考补齐

`card-centering.js` 只用浏览器像素测量外框和连续印刷内框，结果与AI上传对象分开。`centering-view.js` 显示自动结果、两层框线及拖动/键盘校正；不可靠或全幅卡不输出默认比例。`grading-price-data.js` 同页读取现有公开价格references，按全部真实维度分组；完整同公司与匹配RAW数据才可填成本表。

`certified-grading-examples.json` 与六张原始图片登记三个2021 PSA专业参考；`grading-price-guide-examples.json` 登记另三张1999 Shadowless的PSA指导估值。样本年份、认证结果、指导估值与后台目录价格分开维护，不能互相映射。新增数据文件已进入构建指纹。所有代码和文档完成后才运行几何/接口/价格/图片完整性与浏览器检查。
