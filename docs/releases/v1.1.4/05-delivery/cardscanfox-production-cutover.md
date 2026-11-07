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
