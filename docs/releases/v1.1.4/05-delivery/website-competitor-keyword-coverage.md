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

本批通过只读接口核对 20 个卡牌记录。19 个此前不在 sitemap 中，追加后目标为 1,112 个详情；原有 1,093 条全部保留。非卡牌索引页目标从 83 个增至 86 个，总发现数目标为 1,198。所有指南种子继续保存在 `guideCardIds`，不设置定时扫描。

第二批内容与发现路径完成后进行影响面检查：独立官网构建通过，生成 121 条 HTML；相关 34 项检查全部通过。新文章的 17 个卡牌链接均在候选 sitemap 中，16 个其他内链可正确解析；原有 1,093 条卡牌 URL 全部保留。1440px 桌面和 390px 移动端浏览器检查通过，三篇新文章无页面横向溢出。

本批待 main 自动部署、正式回读及 29 个受影响 URL 的 IndexNow 通知。未修改 App、原业务 API、Admin、旧 Marketing、数据库或 Cloudflare 绑定。
