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

## 现有官网路径优化（2026-10-30）

首页和生成的内容页在页眉提供识别、查价、收藏与 App 比较入口。首页首屏突出 Card AI、扫描到查价的任务和 App Store 下载；产品界面图在桌面位于文案旁，在手机位于文案下方。宽度不超过 359px 且高度不超过 620px 时隐藏首屏产品图，避免它遮挡文字和下载入口。

`/card-identifier`、`/pokemon-card-scanner`、`/card-price-checker` 和 `/card-collection-tracker` 的首段与下载标题明确说明操作在 Card AI App 内完成。首页价格文案使用“可用的已发布价格”，不把外部市场搜索称为 App 的成交记录。页面归属与产品能力沿用前述基线；官网没有新增网页识别或网页查价工具。
