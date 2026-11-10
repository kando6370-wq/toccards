# PokeScope 自然搜索词与官网内容覆盖

本次增量只涉及独立官网 `apps/cardscanfox-web`、生成的 `packages/website-content/data/articles.json` 和文档。业务 API、旧 Marketing、Admin、Flutter、数据库和生产绑定均不在变更范围。

## 证据与限制

2026-11-08 通过 Ego 浏览器读取用户提供的 PokeScope 美国桌面自然排名报表。链接参数为 2026-11-05，但 UI 实际可选快照为 2026-11-06。本次以 UI 为准。各行的 Timestamp 是供应商记录时间，不能视为关键词首次出现日期。

报表显示 55,239 个排名词。原生导出上限为 50,000 行，本次未购买剩余 5,239 行。取得的 50,000 行包含 43,421 个不同原始短语；其中 15,130 行 Traffic 大于 0，按规范化关键词和落地 URL 去重后为 14,812 条。Traffic、Search Volume 和 KD 都是第三方估算，不能表述为竞品实际访问、本站点击或流量预测。

导出样本的非零去重行 Traffic 合计为 62,927。按竞品 URL 结构分组，单卡详情约占 68.5%，角色页约占 13.6%，查价工具页约占 9.7%。这是样本行估算值的计算结果，不是实际独立访客比例。UI 不同汇总口径没有与样本数混加。

本次 Google 可见搜索仅核对 `pokemon card values checker`，结果包含价格数据库和查价工具。浏览器语言为 zh-CN，因此没有把这次搜索写成 US 无个性化排名。未恢复此前异常的 Google Trends 扫描，未读取本站 GSC 或 Keyword Planner，不能确认这些词最近一周上涨或新出现。

TypeSafe `jev-1.14.0` 用于 5 个产品词根的语义分类，均归入核心能力。Jev 未逐个审核 50,000 行。确定性去重、Traffic 加总和 URL 分组用代码完成；产品适配、页面归属与内容复核由 Codex 完成。原始导出和模型响应保留在忽略的 `.local` 目录，不进入公开站点或 Git。

[完整对比与实施报告](../../../seo-implementation/2026-11-08-pokescope-organic-implementation-plan.html)列出代表关键词、报表估算、归属页面和未验证项。报告中的 HOLD 只适用于热度、词龄和未来收益判断；用户已授权的真实产品内容补齐继续执行。

## 页面归属

| 搜索任务 | 页面 | 本次处理 |
| --- | --- | --- |
| 查 Pokémon card value、price、value checker | `/games/pokemon` | 改善英文标题、简介和首屏说明；继续使用现有真实目录筛选，不新建同义工具页 |
| pokemon card scanner | `/pokemon-card-scanner` | 保留原正文，追加不拍照时的目录查价入口 |
| gengar fossil holo、Gengar VMAX、TG06 | `/blog/gengar-card-values` | 新增指南，区分 05/62、20/62、157/264、271/264、TG06/TG30 |
| eevee full art、TG11、188/167 | `/blog/eevee-card-values` | 新增指南，区分 Trainer Gallery、Twilight Masquerade 和 Shiny Vault |
| mewtwo pokemon card、EX/GX/ex | `/blog/mewtwo-card-values` | 新增指南，区分 BREAKthrough、Shining Legends 和 Destined Rivals |
| NM/LP/MP、moderately played | `/blog/pokemon-card-condition-guide` | 新增卡况指南，引用 TCGplayer 和 PSA 官方标准 |
| PSA 9/10 与 raw 价格比较 | `/blog/raw-vs-graded-card-values` | 保留原正文，追加比较边界及卡况指南入口；不虚构固定价格倍率 |
| Pikachu、Rayquaza VMAX | 既有同名指南 | 从宝可梦目录建立入口，不创建重复页面 |
| trade calculator、鉴真、AI 评级 | 不新增页面 | 当前产品不能完成这些任务 |

新文章使用独立英文标题、简介、H1、作者、发布日期、Article schema、canonical 和来源链接。页面不写死卡牌金额；具体价格、原始条件与观察日期由真实详情页提供。没有将竞品正文、品牌导航词或未经核实的能力写入本站。

## 既有内容与索引发现

46 个旧网址和其受保护正文/原链接保持。新增补充块位于受保护的 `.legacy-content` 容器之外。三个旧页的补充块分别承接查价、App 扫描和 raw/graded 比较，不替换原文章。

新文章自动进入博客索引和 values 分类。新增 4 个文章路径加入正式索引策略。15 个指南内使用的卡牌详情身份已通过现有只读接口读取，均具备明确名称、套装、卡号和公开卡图。其中 3 个已经在网站地图中，追加其余 12 个后，卡牌 sitemap 从 1,081 条增至 1,093 条。原有 URL 全部保留。

`guideCardIds` 保存全部指南种子，后续手动生成发现批次时继续保留；没有启动全目录扫描或新增 Cron。正式非单卡页面从 79 个增至 83 个，正式 sitemap 总发现数为 1,176 条。这仍不是全量卡牌目录导出。

## 验证与发布

内容、元信息、内链和 sitemap 变更全部完成后进行影响面检查：独立官网构建通过，生成 118 条 HTML 路由；content-files、content-preservation、catalog-seo、pages-live 共 34 项通过。新指南的 25 个非卡牌内链、唯一 H1、canonical、index 策略和 sitemap 发现检查通过。保留全部 1,081 条原卡牌 URL。桌面 1440px 与移动端 390px 浏览器检查未见页面横向溢出；卡况表的 5 行正常呈现。初次检查发现宝可梦元信息中遗漏 intent/question 字段，补齐后重跑上述 34 项全部通过。

官网内容提交 `a524ffd83da9e5b1e9dc2afbdf3f2378e3ac13cf` 已推送 `origin/main`。正确 Cloudflare 账号 `dced4adca2f35cff247b39979058b934` 下的 `toccards-website` 和独立 `cardscanfox-site-data-preview` 自动构建均为 success。正式 `/release-manifest.json` 回读 sourceCommit 为同一提交，releaseId 为 `8cf94f607da0ff54d0634123f3da898272183c40ca3fa0b4e2190d760524cf00`。

正式站 10 个新增/更新内容页面的英文元信息、canonical 和 index 策略通过；4 个正文补充与博客索引链接再次逐一回读。Ego 浏览器确认新文章、目录中的 6 个指南入口及 Gengar 05/62 实际详情正常，后者明确显示版别、价格条件、观察日期。正式 sitemap 回读为 83 个非卡牌页面和 1,093 个卡牌详情，共 1,176 条。

本轮 22 个影响 URL 已全部通知 IndexNow，均收到 HTTP 200。首轮通用 skill 提交 18 个；其内容指纹使用正则截取 main/article，遇到嵌套 article 的首个结束标签会提前停止，导致 4 个实际变更页面被判定 content_unchanged。对这 4 个页面再次运行同一 skill 的公开页面资格检查，并确认完整正式 HTML 含新增内容后，按相同站点配置一次性补交，收到 HTTP 200。未修改全局 skill、历史去重状态或设置定时任务。两份回执位于忽略的 `.indexnow/reports/2026-11-08T07-01-13-640Z.json` 和 `.indexnow/reports/2026-11-08T07-05-49-149Z-body-update-supplement.json`。接口接收不等于搜索引擎已抓取、收录或获得流量。

未纳入本次验证：App 真机、扫描识别、登录、购买、业务数据库写入和全仓回归。这些功能不在本次变更影响面内。

## 第二批卡名与印次覆盖（2026-11-08）

用户继续授权后，沿用同一美国桌面竞品报表，不重复获取或扩大其 50,000 行上限，不恢复此前异常的 Trends 扫描。Google 可见搜索核对了 `charmander 151 card value`、`dragonite ex card value` 和 `bubble mew card number`；使用 en/US 参数，但不把账号下可见结果当作无个性化 US 排名。可见 TCGplayer 结果分别对应 Charmander 168/165、Dragonite EX Full Art 和 Mew ex 232/091。未采用广告、购物价、第三方访问估算或 AI 摘要作为本站价格事实。

TypeSafe 在线文档本轮未能读取，复用已保存的正式 HTTP API/Choice 文档；实际 `jev-1.14.0` 完成 8 个候选词的预分类。Jev 将交易计算器误归为印次查价，置信度为 0.47，Codex 按产品能力纠正为排除。`greninja xy24 promo price spike` 保留为待核实词，不将词中的上涨断言写成当前事实。其余卡名归属由真实目录和已有页面覆盖决定。

新增三个页面：

- `/blog/charmander-151-card-value`：004/165 与 168/165 的编号、图案、语言、finish 和价格条件。
- `/blog/dragonite-ex-card-values`：Evolutions EX 72/108、106/108；Evolving Skies V 191/203、192/203；Fossil 04/62、19/62。
- `/blog/mew-ex-card-values`：Bubble Mew 232/091、216/091、151 的三种 Mew ex、205/165 金属卡和 Fusion Strike Mew V；与既有 Mew GG10 页区分。

既有 Charizard GX、Charizard 151 和 Mew GG10 三个页面保留全文及日期化价格样本，只在保护容器之外补充真实详情和新指南入口。宝可梦目录、既有通用查价指南、博客索引及 values 分类可以发现新文章。没有创建查价同义页面，也没有在文章中写死当前金额。

本批通过只读接口核对 20 个卡牌记录。19 个此前不在 sitemap 中，追加后为 1,112 个详情；原有 1,093 条全部保留。非卡牌索引页从 83 个增至 86 个，总发现数为 1,198。所有指南种子继续保存在 `guideCardIds`，不设置定时扫描。

第二批内容与发现路径完成后进行影响面检查：独立官网构建通过，生成 121 条 HTML；相关 34 项检查全部通过。新文章的 17 个卡牌链接均在候选 sitemap 中，16 个其他内链可正确解析；原有 1,093 条卡牌 URL 全部保留。1440px 桌面和 390px 移动端浏览器检查通过，三篇新文章无页面横向溢出。

第二批内容提交 `0b95d68e3de9389f528634d506df186a5960094a` 已推送 main。正确 Cloudflare 账号下官网和独立只读服务的自动构建均为 success。正式 manifest 回读 sourceCommit 为同一提交，releaseId 为 `bf73a4027f4c9b122686355138b2999c2c985693f48ec69be6119187a033d3a4`。10 个新增/更新内容页面的正式 HTML、canonical、索引策略和新增正文入口通过；正式 sitemap 为 86＋1,112 条。Ego 浏览器确认新文章、目录中的 9 个指南入口和独立 Mew 205/165 金属卡详情正常。

本批 29 个 URL 的 IndexNow 通知全部收到 HTTP 200。通用 skill 首轮提交 22 个；受前述嵌套 article 指纹限制影响的 7 个正文更新页，在重复核对页面资格与正式完整 HTML 新内容后一次性补交 7 个，HTTP 200。回执为 `.indexnow/reports/2026-11-08T07-34-25-423Z.json` 和 `.indexnow/reports/2026-11-08T07-35-23-463Z-batch-2-body-update-supplement.json`。没有修改全局 skill 或历史去重状态，没有定时任务。接口接收不等于抓取或收录。

本批未修改 App、原业务 API、Admin、旧 Marketing、数据库或 Cloudflare 绑定；未跑与官网内容无关的 App/业务回归。

## Delta-Herrschaft Pull Rate（2026-11-08）

用户指定 `pokemon delta herrschaft pull rate` 并要求按搜索意图加入官网。Ego 德国/德文参数下的可见搜索以抽卡概率、稀有度和 Mega-Rayquaza 命中率为主，不能用价格榜或卡表代替。实际 Jev `jev-1.14.0` 将其分类为 pull_probability（1.0），页面归属与内容由 Codex 复核。该单词需求不触发热词排名或全量 Trends 扫描。

新增 `/blog/pokemon-delta-herrschaft-pull-rate` 德文独立指南，标题为 `Delta-Herrschaft Pull Rate: SIR, Mega-Rayquaza & Daten`。Description 承诺对比早期 SIR/Mega-Rayquaza 估算、样本量和德文实体包的适用边界。既有 `/blog/delta-reign-pokemon` 保留原识别/系列内容，追加新指南入口；新文章进入博客与 collecting 分类和正式 sitemap。

内容核对官方德文发布公告、PokéZentrum 约 1,850 包的多来源汇总、TCGtalk 252 包的英语预发行样本。数值仅作为原作者报告的观测，不宣称已独立验证原始开包记录，不把未明确语言的汇总称作德国实测率，不混合样本；区分稀有度与单卡概率、均值与保底、实体包与 TCG Live。标题不承诺官方赔率或必出。页面没有提供虚构的 Delta-Herrschaft 完整卡表、价格或计算器。

文章文件支持可选 language=en/de，默认仍为 en；新文章 document lang 和 Article inLanguage 为 de，来源标题显示 Quellen。其他页面保持既有语言与 URL，不新增全站语言切换或错误的翻译 hreflang。

内容完成后构建通过，生成 122 条 HTML。相关 35 项检查通过，包括德文 document lang/Article inLanguage、非法语言拒绝和英文页保留 en；46 个老页原正文及链接保留。1440px/390px 浏览器检查无横向溢出，概率表有 5 行。内容提交 `1f808c7885d9ba29213d88a4c8f958a3a01f3a2f` 已推送 main，官网与独立只读服务的自动构建均 success。正式 manifest sourceCommit 为同一提交，releaseId 为 `6bda865ebf90a0ada518c6d9f514e06e1d9f1b5d8824ecdb641d2f560a12d0a9`。4 个影响页正式 HTML、德文语言及英语旧页保留、canonical、index 策略与内链通过；非卡牌 sitemap 87 条，详情 1,112 条，总计 1,199。Ego 正式页面回读通过。

4 个 URL 的 IndexNow 通知全部收到 HTTP 200：通用 skill 首轮接收 2 个，另外两个索引页因首个嵌套 article 指纹漏判，在核对完整新链接和页面资格后补交 2 个。回执 `.indexnow/reports/2026-11-08T13-52-08-538Z.json`、`.indexnow/reports/2026-11-08T13-54-01-383Z-delta-body-supplement.json`；未改全局 skill 或历史状态，不宣称已收录。原 App、业务 API、Admin、旧 Marketing 和数据库不变。

## 首页价格与 TCG 入口（2026-11-10）

用户指定 pokemon tcg、pokemon card prices 加入首页。保留产品 H1、历史正文与其他卡类，用首页 Title、Description、首屏说明、次入口和卡库 H2 自然承接查价。完整任务仍在既有 `/games/pokemon`，没有新增同义页。详情、研究证据、文案和验收见[内容方案](../../../content-plans/2026-11-10-home-pokemon-keywords.md)。官网构建及 26 项相关检查通过；桌面/手机无页面横向溢出。元信息、OG、唯一 H1、canonical、模板同步和查价链接通过；首次检查中旧 H2 文案断言失效，核对原因后更新断言并重跑通过。验证使用本机 Node 24.3.0（与仓库固定 22.23.4 不同）；Cloudflare 固定环境构建结果另行回读。正式内容提交 `35aad808ea8f02c599321d56ae64ab0d81d9894e` 已推送 main，Cloudflare 官网构建 success；正式 manifest 与同一 sourceCommit 匹配。Ego 正式首页 Title/Description、首屏、卡库 H2、canonical 及查价按钮进入 `/games/pokemon` 均已确认。仅首页通知 IndexNow，1 个 URL 收到 HTTP 200；回执 `.indexnow/reports/2026-11-10T09-51-31-827Z.json`。接收不等于收录或排名提升。

### 首页定位修正（2026-11-10）

用户明确要求仅加大 Pokémon 两词权重，不移除其他 TCG/体育卡定位。上一版把 Title 和首屏次入口收窄为 Pokémon，原因是错误地将特定获客词当作全站产品范围。现恢复 Title 的 TCG & Sports Card Scanner, Prices & Tracker、原首屏完整说明、Explore the cards→/cards；新增独立 Pokémon TCG / Pokémon card prices 段落和 /games/pokemon 链接。卡库 H2 恢复通用品类，WebSite 描述同步。未删除旧正文、功能或品类页面。构建与 26 项相关检查通过，首次新增断言因属性顺序写反失败，核对实际 HTML 后修正并重跑通过；待桌面/移动端及正式回读、首页 IndexNow 通知。
