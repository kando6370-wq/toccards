# CardScanFox 正式切换

用户于 2026-11-08 明确授权：使用 delta reign pokemon 与 pokemon upc 30th anniversary，合并主分支并推送，正式域名切换新版，生成网站地图，缩短无关测试。

## 内容与意图

新增 `/blog/delta-reign-pokemon` 回答扩展包身份、发行及卡牌查价步骤；新增 `/blog/pokemon-upc-30th-anniversary` 回答 UPC Day/Night、官方内容及密封产品与单卡的区别。保留旧周年卡价文章与 46 个原路径/正文。事实采用 Pokémon 官方发布/产品展示，未填造单卡清单、密封产品报价、库存或购买建议。

Jev 本轮返回：Delta 归属指南，confidence 0.91；UPC 归属指南但 confidence 0.22。Codex 根据官方内容和现有功能复核两者归属，不据此声称搜索量或排名证据。

## 发布目标

在新应用内新增 `wrangler.production.jsonc`，目标固定为 dced4adca2f35cff247b39979058b934 账号的现有官网 Worker `toccards-website`，保留 `tcgcard.fun/*` 路由，改为部署独立新应用，复用新只读服务 `cardscanfox-site-data-preview`。原营销源文件与 App/API/Admin/Flutter 不修改。新配置生产模式显式开启，预览 Pages 入口继续强制 noindex。

正式构建命令为 `pnpm --filter @kando/cardscanfox-web build`，部署命令为 `pnpm --filter @kando/cardscanfox-web exec wrangler deploy --config wrangler.production.jsonc`，仓库根目录执行，生产分支 main。正式源版本从 release-manifest 回读。旧 Worker 版本保留，失败可通过版本回退恢复。

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
