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
