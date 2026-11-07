# CardScanFox 独立官网

既有 `marketing-web` 的独立改版候选，保留旧项目、域名和网址。使用已确认的几何狐狸标识与浅色视觉。

## 当前实现范围

- 回收并导入线上 46 个已知网址的完整主内容。20 篇旧博客、3 个比较页和法律正文保持原路径；13 篇原 checkout 没有的文章已回收。
- 导入时检查源文件哈希和可见主文本，保留卡号、表格、日期、FAQ、链接和图片说明，清理旧脚本及事件属性。
- 新首页、卡种/系列目录、单卡、价格概览、工具、帮助、数据方法和本机 Saved 使用真实路径和服务端 HTML。
- 新首页重新编排产品内容；完整旧首页另保留在可阅读的原 App 介绍折叠区，后续正文编辑须单独评审。
- 原博客列表和卡表筛选可继续操作。旧网址、原 H1 和正文保持。按用户后续要求，`content/seo-pages.json` 已应用按搜索意图编写的标题和简介；`content/seo-proposals.json` 保留初版草案作对照。
- 独立只读数据服务支持本地捕获快照及新增 PostgreSQL 只读接口；默认预览仍读取 30 条真实捕获快照。单卡只提供固定 30 天摘要与 App 引导，不改变现有 App 的历史接口、订阅或额度。

按用户 2026-11-07 的要求，本期不建设官网管理后台、账号、角色、CMS 写接口或官网数据库。页面和文章在项目文件维护。生产数据出口、真实全量目录和正式接管仍需对应来源与发布授权。

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

候选名为 `cardscanfox-website-preview`，不声明生产 Route/Custom Domain，也不绑定原业务库。`run_worker_first` 使 HTML 和素材都先经过预览访问控制。

远程预览必须配置独立 `PREVIEW_USERNAME` 和至少 12 字符的随机 `PREVIEW_PASSWORD`，且不能使用示例值。缺少凭据时拒绝访问；版本 URL 也不应绕过这层检查。不要提交 `.dev.vars`。

绑定 `SITE_DATA` 的服务目标是独立 `cardscanfox-site-data-preview`。只有取得目标环境授权后才创建/部署服务或设置远程 Secret。

预览响应 `noindex/nofollow`、`no-store`，robots 禁止抓取，预览不发布 sitemap、不提交 IndexNow。正式候选必须同时配置真实服务模式和明确的 PUBLISH_READY 开关，默认拒绝启用；后续接管仍需独立批准，并遵守原 URL、缓存、访问控制和回退验证。

## 内容与数据来源

旧内容来自 `tcgcard.fun` 2026-11-06 的已知 sitemap 页面。当前只证明这些已知 URL 的迁入；非 sitemap、GSC 历史地址和外链仍需补齐。来源署名、App Store、支持邮箱与现有 App 名称使用真实状态。

卡图和价格为本地评审数据，原观测日期保留。生产再展示许可和读模型出口没有因本地实现而自动获批。禁止将用户扫描原图用作公开卡图。

规格入口：`docs/releases/v1.1.2/00-product/cardscanfox-website-redesign-spec.md`。

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

该命令拒绝缺失已有 URL、修改保护标记、缺失保护正文、资产改动和未登记文件。回退也需同样对照；动态数据地址和非 sitemap 历史地址还需合并真实访问记录，不能只靠静态清单证明覆盖。

`content/index-policy.json` 在正式模式保留旧 46 页及已登记栏目的索引。单卡采用真实数据与身份完整性规则，合格详情可索引，无须手填几十万网址。Saved、草稿、搜索/筛选组合不进入 sitemap。

`wrangler.production.example.jsonc` 是未生效的正式候选配置，不含正式域名 Route，`PUBLISH_READY=false` 默认拒绝正式模式。正式启用需批准目标和构建，确认独立真实数据服务，再明确设置该开关。正式响应会移除预览认证和 noindex，并按索引策略生成 sitemap；公开 API 拒绝评审快照。示例配置不是一次部署授权。

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

更多规则见 `docs/releases/v1.1.2/05-delivery/cardscanfox-catalog-indexing.md`。目前没有读取 GSC 查询和收录基线，不宣称文案已提高点击率或所有卡牌已被收录。

## Git 自动部署

独立发布分支为 `codex/cardscanfox-preview`。只推送此分支不会推进 `main` 或 `dev`。Cloudflare 目标账号固定为 `dced4adca2f35cff247b39979058b934`。原手工上传项目 `cardscanfox-preview` 保留用于对比。

新 Pages Git 项目 `cardscanfox-git-preview` 复用现有仓库连接。根目录 `/`，构建命令 `pnpm --filter @kando/cardscanfox-web --fail-if-no-match build:ci`，输出目录 `apps/cardscanfox-web/dist`。Node 使用 22，pnpm 使用 11.9.0。构建失败不替换上一成功部署。发布清单记录 `CF_PAGES_COMMIT_SHA`，用于回读核对实际发布提交。

Pages 构建命令现在生成 `_worker.js` 和全路径 `_routes.json`，通过 `SITE_DATA` Service Binding 取得真实目录并服务端渲染。108 个静态构建条目继续保留，单卡动态地址不限于原 30 条评审记录。公开 Pages 预览维持 noindex/no-store、robots 禁止抓取；独立 Workers 入口仍保留 Basic 认证。数据失败返回 503，首页保留产品说明，不以旧快照替代真实价格。

新只读服务使用独立 Workers Builds，配置见 `apps/website-service/README.md`。新增数据服务复用正式库现有 Hyperdrive；原 App 代码、接口和绑定配置不修改。正式域名切换与索引开放分别管理。

`worker/pages.ts` 是 Pages 的独立入口。Pages 项目的生产环境需设置 `SITE_DATA` → `cardscanfox-site-data-preview`，兼容日期为 2026-11-07，并开启 `nodejs_compat`。`wrangler.pages.jsonc` 记录同一配置供显式 CLI 使用；Git 项目的根目录仍是仓库根，运行时绑定按控制台配置生效。`build:pages` 在暂存目录完成服务端包编译后才替换完整产物。
