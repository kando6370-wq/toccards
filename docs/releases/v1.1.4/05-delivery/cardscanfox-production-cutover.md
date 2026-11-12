# CardScanFox 正式切换

用户于 2026-11-08 明确授权：使用 delta reign pokemon 与 pokemon upc 30th anniversary，合并主分支并推送，正式域名切换新版，生成网站地图，缩短无关测试。

## 内容与意图

新增 `/blog/delta-reign-pokemon` 回答扩展包身份、发行及卡牌查价步骤；新增 `/blog/pokemon-upc-30th-anniversary` 回答 UPC Day/Night、官方内容及密封产品与单卡的区别。保留旧周年卡价文章与 46 个原路径/正文。事实采用 Pokémon 官方发布/产品展示，未填造单卡清单、密封产品报价、库存或购买建议。

Jev 本轮返回：Delta 归属指南，confidence 0.91；UPC 归属指南但 confidence 0.22。Codex 根据官方内容和现有功能复核两者归属，不据此声称搜索量或排名证据。

## 发布目标

在新应用内新增 `wrangler.production.jsonc`，目标固定为 dced4adca2f35cff247b39979058b934 账号的现有官网 Worker `toccards-website`，保留 `tcgcard.fun/*` 路由，改为部署独立新应用，复用新只读服务 `cardscanfox-site-data-preview`。原营销源文件与 App/API/Admin/Flutter 不修改。新配置生产模式显式开启，预览 Pages 入口继续强制 noindex。

正式应用为 `apps/cardscanfox-web`，生产分支为 `main`。`main` 相关路径推送已由既有 Cloudflare Git 集成自动发布；不是每次文档提交都必然触发构建，具体监听范围以控制台配置为准。推送成功、自动构建成功与正式流量生效分别验收，不能只凭 Git SHA 推断已上线。

手工正式发布在仓库根目录执行，须先取得目标环境授权并使用项目约束的工具链。构建器只从 `CF_PAGES_COMMIT_SHA` 或 `WORKERS_CI_COMMIT_SHA` 读取提交身份，不会自动执行 Git；普通 `build`／`deploy:production` 命令若缺少这两个变量，会生成 `sourceCommit:null`。以下 PowerShell 示例在干净工作区将同一完整 SHA 注入两个入口，避免旧环境变量优先级带入错误身份：

```powershell
if (git status --porcelain) { throw '发布工作区必须干净' }
$websiteSourceCommit = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $websiteSourceCommit -notmatch '^[a-f0-9]{40}$') { throw '无法确认完整发布提交' }
$env:CF_PAGES_COMMIT_SHA = $websiteSourceCommit
$env:WORKERS_CI_COMMIT_SHA = $websiteSourceCommit
pnpm --filter @kando/cardscanfox-web build
if ($LASTEXITCODE -ne 0) { throw '官网构建失败' }
$websiteManifest = Get-Content 'apps/cardscanfox-web/dist/release-manifest.json' -Raw | ConvertFrom-Json
if ($websiteManifest.sourceCommit -ne $websiteSourceCommit) { throw '产物提交身份不匹配' }
```

完成候选清单、保护路由、production dry-run、活动配置与回退点核对后，再使用 `pnpm --filter @kando/cardscanfox-web exec wrangler deploy --config wrangler.production.jsonc --keep-vars`，或按本页重发记录先 `versions upload`、比较候选，再 `versions deploy`。部署后回读活动版本及 `release-manifest.json`，核对完整 SHA 和批准的 release ID。旧 Worker 版本保留，失败可通过版本回退恢复。

## 网站地图与通知

`/sitemap.xml` 为索引，`/sitemaps/site.xml` 包含旧地址和已批准新栏目、文章；`/sitemaps/cards-00001.xml` 为实际查询的首批单卡。首批手动脚本仅读取两榜和 18 页 Pokémon 卡库，检查单卡资格、重复身份和标题，不冒充全库导出。分片及 manifest 纳入版本控制并校验计数/字节/哈希。卡牌详情的可索引资格不局限于首批 sitemap。保留原 IndexNow key 文件，只在正式版本生效后提交本次影响的 sitemap 公开地址。

## 验证范围

先完成修改，再运行新官网内容/SEO/生产边界合同、构建、生产 dry-run。官网 CI 去掉重复执行新服务测试/构建；新服务保持自身构建检查。不跑无改动的 App/Admin/Flutter 测试。正式回读检查两篇文章、旧 URL、分页、榜单、单卡、canonical、robots、sitemap 和版本，不把 HTTP 200 或通知成功说成 Google 收录。

本地发布前结果：官网 43 项测试、类型检查、静态构建和 production dry-run 通过。静态构建 113 条，46 个保护路径正文不变；首批单卡 sitemap 1,056 个（候选 1,063 个，排除 7 个资格/重复问题）。新注册两篇文章均由 Markdown 编译器处理。现有 IndexNow key 原字节复制至新官网资源，通过独立静态路由提供。

正式 `180a2c02` 已于 2026-11-08 回读生效，官网 Workers Build success，旧域名直接返回新页面。两文、原 scanner 地址、单卡和两榜均 200/index,follow/自指 canonical；两榜各 100 行；robots 放行公开内容并声明 sitemap；sitemap 索引两项、栏目/文章 68 项、单卡 1,056 项，原 key 200 且正文一致。浏览器确认博客有两篇新指南入口。

IndexNow 首批 60 URL 返回 202（收到、等待 key 验证），最后 7 URL 返回 403 UserForbiddedToAccessSite，另发现 `/games/one-piece` 404。报告位于忽略目录 `.indexnow/reports/2026-11-07T16-21-20-717Z.json`，按工具退避不持续重试，不把通知等同收录。正式 games 只读回读确认真实游戏名为 `One Piece Card Game`，其原自动 slug 为 game-62；新增明确 one-piece 别名修复稳定栏目地址，并补目录路由回归。该修复只改新只读服务。

## Google Play 平台删号页面候选（2026-11-10）

为 Google Play Internal testing 准备公开账号删除说明，候选在新官网应用中新增 `/Account/AccountSetup`，说明 Android／iOS 平台范围、身份核验、另一端保留、旧会话撤销、重新注册及 iOS 订阅取消边界；页面保持公开可访问但 `noindex`，不加入 sitemap。`/privacy` 与旧首页保留的法律源同步平台范围删除文字。旧 `apps/marketing-web` 不作为发布入口，避免覆盖正式 `SITE_DATA` binding 和动态目录 Worker。

受保护快照只更新 `/privacy` 的正文哈希；首页原 `<main>` 正文哈希保持不变，其法律弹层源文件仅同步相同文字。候选 release manifest 为 123 条路由，相对线上 `1f808c78` 的 122 条路由无缺失，只新增删号页；显式批准的 protected 差异仅 `/privacy`。其余 45 条受保护路由不变。

本地使用 Node 22.23.4 完成官网 50／50 项测试、类型检查、静态构建、候选完整性校验及 production dry-run；构建 release ID 为 `685d68694945acf84c4168dc90ff826f9e1c7fab6c8f8618fb77338c76d27738`，dry-run 保留 `SITE_DATA`、assets、版本元数据及五项 production 变量。Windows 测试入口改用 `fileURLToPath`，受原字节保护的 legacy HTML 与 sitemap XML 固定 LF，未放宽哈希或正文保护。

本轮只准备本地候选，没有上传版本、切换流量、修改 Cloudflare 配置、提交 IndexNow 或填写 Play Console。正式发布前仍需使用修复后的共享 lockfile执行 frozen install，刷新活动 deployment／version／binding 回退点；发布后回读删号页、隐私页、动态目录、榜单、sitemap、robots 和 release manifest，并确认支持邮箱的实际处理流程。

## 账号删除申请页正式重发（2026-11-11）

用户明确要求重新部署官网。发布前回读确认：`main@b716ae1206b06331a25028f90fc24f3697021490` 已经由既有自动发布生效，活动 Worker 为 `cfa24a8a-7971-4bd8-a816-28e52d0afb31`、100% 流量，deployment `2cd39ad2-6dbe-48f3-9b13-60c49402e3f2`。本轮是在同一源码上显式重发，不将其记为功能首次生效。

从干净的同一提交使用 Node `22.23.4`、pnpm `11.28.10` 完成 `install --frozen-lockfile`、正式构建、完整文件清单验证及 production dry-run；123 条路由无缺失，46 条受保护旧页的正文哈希不变。提交前的 73/73 官网测试与类型检查见[实现验证记录](../00-product/cardscanfox-account-deletion-design.md#132-提交前同步2026-11-11)，本轮没有重复运行未改变源码的业务测试。Windows 工作树的 `public/_headers` 仅恢复为 HEAD 已批准的 LF 原字节；构建后的响应头规则与原生产完全一致，未修改规则、基线或 Git 内容。

先上传候选并逐项比较，再于 **2026-11-11 09:49:18（Asia/Shanghai）** 将 Worker version `cc262754-4590-4428-82bf-f2167bfa8521` 切至 100%，deployment `dd1fe5cb-4bdb-4d03-b8eb-b90a31a6314d`；随后独立回读活动版本一致。新 `release-manifest.json` 的 `sourceCommit=b716ae1206b06331a25028f90fc24f3697021490`，`releaseId=9c3307eb8c87b60b7150064e2b293df333aa5af0bbf70f576290c842023d6bed`，190 个登记文件。现网清单原字节与冻结构建一致。

候选与原生产的 Worker 脚本 etag、8 项绑定描述符及完整版本化运行配置相同，`SITE_DATA` 继续指向 `cardscanfox-site-data-preview`；assets 响应头、兼容日期及 `nodejs_compat` 保持一致。上传仅有账号删除脚本、CSS 和新发布清单 3 个不同原字节资源，其余 187 个复用已有资产。版本部署输出同步 `logpush=false`、observability enabled／sampling=1；发布前未独立读取这些非版本化设置，不宣称它们已逐项前后比对。未执行 triggers deploy，未重设 Route、域名或 cron。

正式域名完成 19 项 GET／HEAD 检查，全部返回 200。账号删除页的 canonical、安全响应头、`noindex, follow`、无默认平台和同源 module 正常，专用脚本、CSS、公共脚本原始字节及 SHA-256 均与冻结资源一致；Help／两处页脚／隐私入口可用，删除页未进入 sitemap。首页、目录、价格页、涨幅榜、单卡、隐私、条款、robots、sitemap 与 Saved 的索引／缓存边界均通过抽查。浏览器实际从 Help 展开删除问答并到达正式删除页，空字段校验和 Android／iOS 范围及条件订阅提示正常。手机布局沿用同一源码先前的 320／390px 本地验收，本轮未另做线上手机尺寸复验。

保留原 Worker version 作为回退点，未执行回退；未发布 App／共享 API／Admin／目录数据服务，未执行迁移、业务写入、Secret 操作、IndexNow 通知或 Play Console 填写。未发送真实邮件、打开有效邮件草稿、读取或改写系统剪贴板、操作真实账号或执行删号；客服收件、身份核验、自有数据与服务提供商删除仍需独立落实。发布证据与截图存放于被忽略的 `apps/cardscanfox-web/.local/prod-redeploy-b716ae12-20261111/`，不纳入源码或法律正文。
