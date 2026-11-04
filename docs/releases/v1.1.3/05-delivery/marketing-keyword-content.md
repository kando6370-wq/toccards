# Marketing keyword content

2026-10-29 增量。产品能力和旧页面归属继续以 [Card AI 产品定位](../../v1.1.2/00-product/card-ai-product-positioning.md)与 [Marketing GEO and SEO content](../../v1.1.2/05-delivery/marketing-geo-seo-content.md) 为基线。

## 页面归属

| 搜索意图 | 本次页面 |
| --- | --- |
| `pokemon tcg card prices` | `/card-price-checker` 的 Pokemon 查价小节；扫描流程仍属于 `/pokemon-card-scanner` |
| Prismatic Evolutions、White Flare、Surging Sparks、Paldean Fates、Shrouded Fable 的实体卡清单与印次核对 | `/blog/pokemon-tcg-set-card-lists`；从 `/pokemon-card-scanner` 和博客入口链接 |
| `one piece tcg card list` | `/one-piece-card-scanner` 链接发行方的完整卡表，并说明单卡搜索与价格核对 |
| 30th Celebration Ultra-Premium Collection | 保持 `/blog/pokemon-tcg-30th-celebration-card-prices` 的既有归属，不新增同意图页面 |

## 事实边界

- 美国和澳大利亚的 Google Trends 相关查询用于发现措辞。相对上涨不表示绝对搜索量或页面机会已经通过完整搜索结果验证。
- 2026-10-29 对生产只读 `/api/v1/sets/search` 与 `/api/v1/cards/search` 的回查，确认 PRE、WHT、SSP、PAF、SFA 有 Pokemon 系列记录和单卡样本，One Piece 有系列记录。目录存在不证明官方卡表完全覆盖，也不保证每张卡有价格。
- 新指南引用发行方的卡牌资料。`One Piece TCG card list` 使用发行方完整卡表作为真源；Card AI 只提供其目录内的单卡搜索与可用价格。
- Premium Figure Collection、Unova Poster Collection 和 booster bundle 是密封商品。官网只说明其与具体单卡的关系，不声称 App 估算未拆封商品价值。
- 找店、模拟器、数字卡牌游戏、送评服务和未证实支持的新卡种不归入本次实体单卡页面。

## 2026-10-30 搜索摘要与意图增量

- Search Console 近 7 天（10 月 22–28 日）显示 DCC 文章 747 次曝光、59 次点击；`card-price-checker` 为 22 次曝光、0 次点击。后者样本小，不能仅凭 0 点击判定页面失败。
- DCC 文章的 title、H1 和 description 以高曝光的实体卡及 Series 1 为主，简介再说明第三方卡表和卡包商品页。正文区分第三方 100 张卡表与未核实的发行方完整清单，并标明 2026-10-30 所见的缺货状态；不把零售页、游戏卡或卡表混成同一产品。公开目录未返回 DCC 记录，因此正文不再肯定宣称支持扫描该卡种。
- `/card-price-checker` 的 title、H1 和 description 直接回答“这张卡值多少钱”，并明确扫描、目录查询和价格展示发生在 Card AI App 中；不宣称官网可直接估价。
- 此次只改以上两页的搜索摘要及其对应内容、生成入口和 sitemap 日期。点击率变化须在搜索结果更新后用可比的查询与页面窗口观察；本次本地修改不等于排名或点击改善。

## 现有官网路径优化（2026-10-30）

首页和生成的内容页在页眉提供识别、查价、收藏与 App 比较入口。首页首屏突出 Card AI、扫描到查价的任务和 App Store 下载；产品界面图在桌面位于文案旁，在手机位于文案下方。宽度不超过 359px 且高度不超过 620px 时隐藏首屏产品图，避免它遮挡文字和下载入口。

`/card-identifier`、`/pokemon-card-scanner`、`/card-price-checker` 和 `/card-collection-tracker` 的首段与下载标题明确说明操作在 Card AI App 内完成。查价页保留本日另一项搜索摘要更新的标题、H1、描述与首段。首页价格文案使用“可用的已发布价格”，不把外部市场搜索称为 App 的成交记录。页面归属与产品能力沿用前述基线；官网没有新增网页识别或网页查价工具。

## 2026-10-30 竞品热词与新词复核

- Ego Browser 查看了 PokeScope 的 30th Celebration 等套装指南、Ludex 的 2026 Topps Heritage Football 内容，以及 Google Search 和美国 Google Trends 的 7 天、30 天、90 天、12 个月窗口。竞品发布页面和搜索结果不能证明某个词给竞品带来多少点击。Similarweb 限定版只显示网站访问估算，自然搜索词和页面流量未解锁。
- `pokemon 30th celebration` 在美国 12 个月同图中于 9 月达到峰值，10 月下旬仍有兴趣但低于峰值，归为峰后仍有需求，不称 30 天新词或持续热词。`delta reign release date` 在 10 月的完整周有增长，发行方确认 11 月 6 日发售；Card AI 公开目录虽有 DLR 系列入口，按系列 ID 与代码查单卡均返回 0 条，因此不发布完整卡表或查价承诺。[发行方页面](https://tcg.pokemon.com/en-us/expansions/delta-reign/)只展示预览卡。
- Ludex 10 月 21 日发布的 `2026 topps heritage football` 是近期出现的措辞，但本次公开系列搜索没有找到相应 Card AI 记录。密封商品、网页直接查价和真伪鉴定词不进入 App 能力页面。AI 预测评级尚未进入当前公开 App；下一版计划见下节。
- `sc-domain:tcgcard.fun` 的可见效果报告覆盖 10 月 12–28 日，查询表显示 69 行；本轮未在该表看到 30th Celebration、Delta Reign 或 RGB Mew 查询。Search Console 只覆盖本站且可能省略低频查询，不能据此断言市场需求为零。Topps 官方页面出现机器人检查，本轮未继续操作或用该页面补充未经核实的事实。
- `mew rgb card price` 的精确词在 Trends 同图中样本过低，不能称热词或新词；Google Search 已出现针对具体 R/G/B 印次的价格页。Card AI [公开查询](https://api.tcgcard.fun/api/v1/cards/search?q=Mew%20RGB&game=Pokemon&page_size=20) 在 10 月 30 日返回 30C 的三条英文记录，R/RGB、G/RGB、B/RGB 的可用 USD 价格分别为 4,824.92、3,550.78、4,152.80，另有独立的日文 m6a 记录。价格响应没有市场观测时间字段，只能将这些数字标为本次查询所见的样本。
- 本次只给既有 `/blog/pokemon-tcg-30th-celebration-card-prices` 增加 RGB Mew 印次核对和日期样本，不新建同意图页面，也不改 App、API 或卡牌目录。Jev 用于词根与候选词的语义分轨初判；热度、新旧、产品适配与最终页面选择由 Codex 按可见证据复核。

## 下一版 AI 预估评级的搜索与 GEO 方案（2026-10-30）

产品负责人确认已有自有算法，计划在下一次版本迭代接入 Card AI。当前 `main`、`codex/dev-1.0.7scan` 和公开 App Store 1.0.6 尚未提供可核对的裸卡照片预估评级流程；因此本节是后续实施范围，不表示当前 App 已上线，也不改写现有官网的“当前不预测等级”说明。参考实现不能替代自有算法的输入、输出、准确率或运行方式证据，公开文案不说明其来源。

### 关键词与页面归属

| 查询意图 | 候选词 | 处理 |
| --- | --- | --- |
| 从裸卡照片获得非官方等级预估 | `AI card grading app`、`AI card grader`、`pokemon card grade predictor`、`card grading estimate from photo` | 下一版验收后由一个拟议的 `/ai-card-grading` 页面承接；不拆同义词页面 |
| 已有评级卡的价格与收藏记录 | `graded card price tracker`、`PSA card value tracker` | 保持 `/graded-card-tracker`，与预测任务分开 |
| 单独测量居中度 | `card centering scanner`、`pokemon card centering tool` | 自有算法是否输出可复核的居中度尚未确认，暂不承诺 |
| 正式送评或认证 | `PSA submission service`、`card authentication` | 排除；预估结果不等于评级机构的正式等级或真伪鉴定 |
| 免费或指定机构的预估 | `AI grading app free`、`PSA grade predictor` | 价格、额度、机构名称与输出含义待核对，不先写免费或官方关联承诺 |

Ego Browser 的美国 Google Search 样本显示，`AI card grading app` 结果以照片预估工具为主，`pokemon card grade predictor` 同时混有居中度工具，`PSA grade predictor app` 还混有官方送评 App。[PSA 官方等级标准](https://www.psacard.com/gradingstandards)也包含机构评审与主观判断，因此未来页面须把 AI 预估和正式等级分开。美国 Google Trends 同图比较中，`AI card grading` 与 `card grading app` 在 12 个月窗口有历史兴趣；最近 7 天按小时抽样多为 0，30 天窗口仍有低量信号。没有证据称它们是 30 天新词或当前热词，也不能把相对指数写成绝对搜索量。Jev 只对词根和用户任务做语义初分，最终意图、热度与归属由 Codex 复核。

### GEO 内容与上线条件

下一版页面在功能验收后，用可见正文直接回答“能否从照片预估等级”“预估与 PSA/BGS/CGC/SGC 正式评级有何区别”“结果依据什么、适用哪些卡、哪些情况无法判断”。真实输入照片要求、输出分数或区间、支持平台、图像处理位置、收费与额度、失败状态和已验证的准确率都尚未提供；这些问题先保留为待填字段，不生成肯定答案、截图、FAQ Schema 或性能数字。若功能只在部分平台可用，标题、下载入口和回答须按该平台限定。

启用公开 `/ai-card-grading` 页面前，需回读实际客户端入口、算法输出合同、服务端或端侧处理路径，以及 iOS/Android 对应版本；用真实照片走完成功、无法判定与重试路径，并确认用户可见文案。随后再更新相关的 `/graded-card-tracker`、Pokemon 扫描页、原始与评级卡指南和首页中“不预测等级”的旧表述，核对链接、canonical、sitemap、可见问答与结构化数据。GEO 的直接回答应引用真实产品结果和适用范围，不声称认证、保证 PSA 分数或保证转售价。上述证据未齐时，页面与索引激活均保持阻塞。

## 2026-11-04 竞品自然搜索词复核与官网落点

### 证据边界

- Similarweb 当前可见的是 PriceCharting 的网站表现：2026 年 9 月全球总访问量估算为 17.46M，自然搜索占 67.36%。关键词研究、搜索词列表和页面级搜索流量均显示“解锁”，所以不能把 17.46M 或 67.36% 分摊给某个关键词。锁定页出现的通用目录行与卡牌站点不一致，不作为关键词证据。
- Google 搜索结果可以证明某个词的结果页包含哪些竞品和落地页，但不能证明点击量。可见的搜索页面中，PokeScope、PriceCharting、Ludex、CollX、Collectr 和其他站点分别覆盖了查价、扫描、收藏或套装价格意图。
- 美国 Google Trends 的 30 天窗口中，`pokemon card price checker`、`pokemon card scanner app`、`card collection tracker` 的平均指数分别为 14、15、1；这不是搜索量。相关查询出现 `pokemon card value scanner`、`pokemon card value`、`pokemon card price checker app free`、`best free card scanner app`、`pokemon card collection` 和 `collectr`。这组词的低基数和 0 值较多，不能直接称为持续热词。
- 美国 Google Trends 的 30 天窗口中，`pokemon 30th celebration` 平均指数 49，`delta reign release date` 为 9，`2026 topps heritage football` 为 7。相关查询出现 `pokemon 30th upc`、`pokemon delta reign booster bundle`、`2026 topps football holiday` 等。它们有事件或商品驱动，但不等于 Card AI 目录支持。
- Card AI Search Console 当前可见区间（10 月 12 日至 11 月 1 日）汇总为 157 次点击、2,120 次曝光、7.4% CTR、平均排名 11.2；按点击排序的前 10 个查询由 Dungeon Crawler Carl 卡牌文章相关词占据，例如 `dungeon crawler carl trading cards checklist`（8 次点击、35 次曝光）和 `dungeon crawler carl trading cards list`（7 次点击、58 次曝光）。查询表共显示 92 行；本站尚未用这份表证明竞品词已经带来流量。

### 竞品词与页面策略

| 竞品/页面观察 | 可见词组 | 主要意图 | Card AI 处理 |
| --- | --- | --- | --- |
| PokeScope `/pokemon-card-value/` | `pokemon card value checker`、`pokemon card value calculator`、`pokemon card scanner app`、`most valuable pokemon cards`、`trending pokemon card values` | 搜索单卡价值、扫描后查价 | 把 `Pokemon card scanner app`、`Pokemon card value scanner` 放入现有 Pokemon 扫描页；把 `Pokemon card value checker` 放入现有查价页。`most valuable` 和实时价格承诺不作为当前功能文案 |
| PriceCharting `/category/pokemon-cards` | `Pokemon card prices`、`PSA & ungraded price guide`、`current & historic Pokemon card prices`、`Pokemon card centering calculator` | 查价、历史价格、居中工具 | 当前查价页已经覆盖 raw/graded price history；`card centering calculator` 属于下一版能力或观察词，不在当前官网承诺 |
| Ludex `/scan-and-price/` | `trading card scanner app`、`scan your card`、`estimated price`、`price report`、`add card to collection` | 扫描、估价、收藏或出售 | 保留现有扫描、价格、收藏路径；不写 Ludex 的 200 次/月额度、eBay 发布或“最快/最准确”比较结论 |
| CollX 首页 | `sports card scanner`、`current market price`、`track portfolio value`、`bulk scanning` | 体育卡扫描、组合价值、批量库存 | 现有体育扫描页和 collection tracker 可承接扫描与价值；不把批量库存、买卖社区写成 Card AI 功能 |
| Collectr/30th 结果页 | `30th celebration card list and prices`、`pokemon 30th upc` | 套装卡表、价格、密封商品 | 现有 30th Celebration 指南增加 `UPC` 的常用缩写；密封商品只作内容背景，不估算未拆封价值 |

### 本次官网增量

- `/pokemon-card-scanner`：标题使用 `Pokemon Card Scanner App & Value Checker`；FAQ 增加 `free Pokemon card scanner app` 和 `Pokemon card value scanner` 的自然问法。文案仍说明先确认印次，扫描不等于认证。
- `/card-price-checker`：FAQ 增加 `Pokemon card value checker`，明确按 Pokemon 名称、系列或卡号搜索，并查看选中记录的可用价格和历史。
- `/card-collection-tracker`：FAQ 增加 `Pokemon card collection tracker`，说明按 Pokemon 筛选并区分印次、语言、品相和已有评级。
- `/blog/pokemon-tcg-30th-celebration-card-prices`：将 Ultra-Premium Collection 标为常见缩写 `UPC`；不新建密封商品估值页。
- 不新增 `delta reign`、`2026 topps heritage football` 或 `pokemon card centering calculator` 页面。前两项在 Card AI 公开目录或产品范围中没有足够可交付记录，后一项需要真实算法输出后再做页面。
- AI 预测评级相关词仍属于下一版计划。当前公开页面继续保留“不预测等级”的事实说明，避免把搜索词写成已上线功能。

### 结论

本次可以确认的是竞品正在围绕“卡牌扫描 + 价值查询 + 收藏价值”建立页面族，并用具体套装、卡号和卡名承接长尾。不能确认的是它们每个词的实际点击分配，因为 Similarweb 的关键词层被锁定，Google Search 和 Trends 也不提供竞品的点击日志。Card AI 采用一词簇一页面：扫描词归 `/pokemon-card-scanner`，价值词归 `/card-price-checker`，收藏词归 `/card-collection-tracker`，30th 事件词归既有指南；不为每个同义词复制页面。

本轮 TypeSafe/Jev 语义分类请求返回 HTTP 451，未取得分类结果。以上词意、热度及页面归属由 Codex 复核；不把它们标为 Jev 判断。

可复核入口：[PokeScope 查价页](https://pokescope.app/pokemon-card-value/)、[PriceCharting 宝可梦目录](https://www.pricecharting.com/category/pokemon-cards)、[Ludex 扫描查价页](https://www.ludex.com/scan-and-price/)、[CollX 首页](https://collx.app/)、[Google Trends 美国 30 天对比](https://trends.google.com/trends/explore?date=today%201-m&geo=US&q=pokemon%20card%20price%20checker,pokemon%20card%20scanner%20app,card%20collection%20tracker)、[本站 Search Console 效果报告](https://search.google.com/search-console/performance/search-analytics?resource_id=sc-domain%3Atcgcard.fun)。这些入口的搜索结果与相对指数会随时间变化，文中的数值只代表 2026-11-04 的可见样本。

## 2026-11-04 竞品外链与 Card AI 获取机会

### 外链证据边界

- Semrush Backlink Analytics 当前可见 PokeScope 的根域估算为 3.1K 个引用域、16.9K 条 backlinks、月访问估算 140K、自然流量估算 95.8K、Authority Score 34。该报告显示 98% 的引用域处于 AS 0–10，不能把数量当作有效权威。PokeScope 的热门落地页包括首页（129 个引用域）、`/card/svp-88/`（120 个）和带 Product Hunt 参数的首页（15 个）。这些是第三方估算，不是本站或 Google 的点击数据。
- Semrush 对 Ludex 和 CollX 的引用域页只公开了前 10 个域名，更多结果要求试用或升级。Ludex 可见的相关域包括 `topai.tools`；CollX 可见的相关域包括 `wentzvillehobby.com`、`noobjectioncards.com`、`onmantel.com` 和 `mrcollector.net`。这些域名是引用域观察，不代表每个域名都有编辑认可或可申请入口。
- Semrush 对 PriceCharting 的可见相关域包括 `sportscardspro.com`、`tradingcardtrends.com`、`snug.cards` 和 `gradehaus.com`。其中大量链接来自同业、数据页或低权重域；不能把高 backlinks 数量直接转成 Card AI 的外链目标。
- Google Search Console 当前显示 `tcgcard.fun` 有 57 个外部链接，55 个指向隐私页，主要引荐网站为 `apple.com`（53 个）、`chrome-stats.com`（2 个）和 `google.com`（2 个）。这说明当前公开外链主要来自应用或隐私资料，不是内容媒体推荐。Search Console 是本站第一方延迟数据，不等于全网 backlink 总量。

### 已验证的公开链接

| 来源页 | 实际链接 | 指向 | 属性与判断 |
| --- | --- | --- | --- |
| [Mantel Hobby Awards](https://news.onmantel.com/the-hobby-awards-innovation-of-the-year/) | 页面中的 `Website` 链接 | CollX、Ludex | 公开行业媒体页面，链接未显示 `nofollow`；适合争取“收藏行业工具/产品故事”类型报道 |
| [Mantel Ludex founder interview](https://news.onmantel.com/the-latest-from-ludex-a-conversation-with-founder-and-ceo-brian-ludden/) | `Ludex`、`Desktop version here` 等 | Ludex | 公开采访页，说明创始人故事和产品数据是可行的编辑入口；不是目录提交 |
| [ScreenRant Celebrations price article](https://screenrant.com/pokemon-tcg-celebrations-expansion-valuable-cards-worth-money/) | `Pricecharting.com` | PriceCharting | 页面实际链接未显示 `nofollow`；属于卡牌价格内容中的数据来源引用，需先提供可核验数据 |
| [TheGamer Stellar Miracle price article](https://www.thegamer.com/pokemon-tcg-stellar-miracle-most-valuable/) | `PriceCharting.com` | PriceCharting | 页面实际链接带 `nofollow`；仍有品牌和主题相关性，但不应把它当作可传递权重的主要目标 |
| [PokeBeach forum sales thread](https://www.pokebeach.com/forums/threads/uk-selling-old-pok%C3%A9mon-card-collection.153083/) | 用户签名/帖子中的 collection 链接 | PriceCharting | 页面实际链接带 `ugc nofollow`；是用户内容，不适合作为主动发帖或评论渠道 |
| [PromoteProject TCG tag](https://www.promoteproject.com/tag/tcg) | `POKESCOPE.APP` | PokeScope | 公开产品目录直接链接；适合申请 Card AI 的准确产品资料，不应购买大量重复目录链接 |
| [Scout Forge PokeScope review](https://scoutforge.net/apps/pokescope) | `Visit website` 与文章链接 | PokeScope | 链接带 `nofollow`；可作为产品资料页或认领资料的观察对象，不作为权重目标 |

Google Search 还显示 Product Hunt 的 PokeScope 产品页、Sports Collectors Daily 的 CollX 报道和多个 Reddit 讨论，但本轮部分页面有安全验证或只显示搜索摘要，未把它们写成已验证的 HTML 外链。品牌提及、App Store 页面和社交帖子也不等于指向竞品官网的 backlink。

### Card AI 外链优先级

| 优先级 | 目标 | 我们需要准备的材料 | 方式 | 边界 |
| --- | --- | --- | --- | --- |
| P1 | Mantel 或其他收藏行业媒体 | 准确的扫描、印次确认、价格历史和收藏管理资料；真实版本号与素材说明；可复核的产品事实 | 使用现有官网及英文事实材料准备编辑选题或产品采访，先核实编辑渠道 | 不要求对方承诺 dofollow；不把未上线 AI 评级写入介绍 |
| P1 | ScreenRant、TheGamer 这类价格/套装文章 | 已核对的套装卡表、卡号、语言/印次差异和日期化价格快照 | 提供数据更正、补充资料或新套装研究，争取自然引用 | TheGamer 示例为 `nofollow`；外链属性不是唯一价值 |
| P2 观察 | Product Hunt | 准确产品页、演示图、支持平台、用户任务和当前限制 | 核对现有条目和实际提交要求后，准备一次产品或实质版本发布 | 竞品页面安全验证尚未通过，不能将此项写成可立即提交；页面是否产生推荐流量待验证 |
| 暂缓 | PromoteProject、Scout Forge、相关真实目录 | 英文产品简介、官网 URL、App Store URL、隐私和产品能力说明 | 仅在明确普通提交免费后评估一个匹配的资料页 | 用户已排除付费渠道；已知付费推广不做，普通提交费用不明先暂缓，当前无需登录 |
| P2 | Sports Collectors Daily、Mantel 的收藏管理主题 | 批量扫描、确认印次、收藏价值和价格历史的独立数据点 | 以行业数据、产品更新或实用指南为主题联系编辑 | 搜索结果中看见品牌不等于已获得链接；需人工接受 |
| P3 | Reddit、PokéBeach 等社区 | 能解决具体问题的卡牌识别、印次或价格数据说明 | 只在已有问题中给出完整答案，链接仅在被需要时提供 | 不发推广评论、不制造用户内容 backlink；`ugc/nofollow` 不应作为主要 SEO 目标 |

### 不建议复制的外链

- 不复制 PokeScope Semrush 列表中的大量 `.shop`、`.online`、`.site` 低权重域名。它们贡献数量，但与卡牌读者和编辑信任不匹配。
- 不把 `sportscardspro.com`、同业价格站或同一公司生态域名当作可以交换的链接。先确认所有权、主题和用户价值，再决定是否存在真实合作。
- 不把 AI 工具目录、论坛评论、用户签名、自动提交站和链接交换作为主策略。Google 将自动化链接、低质量目录、优化评论链接和过度交换列为垃圾链接风险。
- 不把“竞品被提及”当作“竞品获得高质量 backlink”。本次只有上表中的公开页面完成了链接属性或链接目标核对。

### 研究结论与下一步

Card AI 当前优先争取收藏行业媒体对实用资料的引用，并只评估明确免费的相关产品目录。现有官网、30th Celebration/RGB Mew 日期化价格样本和英文产品事实材料可供编辑查阅；本次不以新增官网页面作为前置条件。素材中的示意合成图和当前 App 限制须说明，不批量提交目录或发布社区评论。

本轮 Semrush 可见层仍是第三方估算，引用域完整导出、全部竞品交集和页面级流量均不可用。可见的前 10 行已经包含供应商 First Seen/Last Seen 日期；该样本不等于完整引用域时间线，Ahrefs 的首次发现分析仍未取得。TypeSafe/Jev 对来源路由的分类请求返回 HTTP 451；来源分组和优先级由 Codex 根据实际页面、链接属性和产品适配复核。以上调研阶段没有执行外联、目录提交、评论发布或代码变更；后续申请准备与发送结果见下节。

可复核入口：[Semrush PokeScope Backlink Analytics](https://www.semrush.com/analytics/backlinks/overview/?q=pokescope.app&searchType=domain)、[Semrush PokeScope Referring Domains](https://www.semrush.com/analytics/refdomains/report/?q=pokescope.app&searchType=domain)、[Semrush PriceCharting Referring Domains](https://www.semrush.com/analytics/refdomains/report/?q=pricecharting.com&searchType=domain)、[本站 Search Console Links](https://search.google.com/search-console/links?resource_id=sc-domain%3Atcgcard.fun)。

### 外链申请准备（2026-11-04）

[英文提交材料](../../../../apps/marketing-web/content/backlink-submission-kit.md)已准备：目录用产品名、短句、简介与功能条目，ScreenRant 和 TheGamer 编辑邮件，当前公开版本与素材说明。它不由官网生成器发布。ScreenRant 邮件已于 2026-11-04 21:10 经用户授权发出，并回查已发邮件；其他资料尚未提交。

- ScreenRant 和 TheGamer 的公开联系页分别确认 `editorial@screenrant.com` 和 `editorial@thegamer.com`，用途包括 Topic Ideas、Feedback、Corrections、Suggestions。两家同属 Valnet，首轮择一匹配选题，不批量重复投递。
- Scout Forge `/app-register` 明确要求登录或注册。PromoteProject 的 Submit startup 入口显示登录弹窗。两者的登录后字段、费用及实际审核规则尚未核实，不能称为免费或保证收录。
- Mantel 目前只有公开客户支持地址可见，未核实编辑收件渠道；不向客服地址发送营销选题。Product Hunt 继续保持观察状态。
- Apple 美国区官方 Lookup 本轮返回 Card AI: TCG Card Scanner、1.0.6、iOS 16+、Free，以及既有商店 URL。浏览器访问同一链接曾跳转到中国区首页，但官方 US 查询确认产品记录存在，因此不改商店 ID；不把仓库 1.0.7 上传记录写成已上架版本。
- 现有 30th Celebration 指南已在线包含 RGB Mew 小节。所有快照仍按原观察日期标注，不将 10 月数字写成 11 月实时市价。
- 用户确认保持现有官网视觉，品牌感受为准确、安心、可核对；本次没有新增官网页面、改模板或改导航。

用户随后明确只做免费渠道。Scout Forge 的 $39 Featured 包和 PromoteProject 的 $0.99/天、$5.99/周置顶推广已排除；普通提交是否免费仍未核实，因此两项暂缓，当前不要求用户登录。后续只评估无需付费的编辑引用及明确免费的相关资料页。

申请准备或邮件发出不等于新增外链。ScreenRant 完成一次投稿，尚无编辑接受或链接上线证据；未提交目录、创建外部账号、接受条款、购买服务或执行 Git push／部署。
