# 首页 Pokémon TCG 与 Pokémon card prices

日期：2026-11-10。站点：tcgcard.fun。基线：main@0633fba4。范围：用户指定两个词加入现有英文首页，含正式发布；不新增页面、不扩成全站关键词发现。

| 输入 | 用户任务与证据 | 归属及处理 |
| --- | --- | --- |
| K-001 pokemon tcg | Ego en/US 可见搜索包含官方游戏、系列、玩法和 TCG Live；不是单一查价意图。Jev identify 置信度 0.36，Codex 认定宽泛混合任务 | P-001 首页作为收藏与价格工具的入口；不冒充官方玩法/数字游戏站 |
| K-002 pokemon card prices | 可见结果为 TCGplayer、PriceCharting 等价格指南；Jev price_buy 置信度 1.0。本站现有目录可以按名字/套装/卡号找印次，详情包含来源、条件和日期 | P-001 改善现有首页；主要完整查价任务仍在 /games/pokemon，首页自然链接过去 |

用户未提供 GSC 指标；本次不推断流量、新鲜度、热度或排名收益。已核对正式宝可梦目录的搜索与价格信息。浏览器参数 en/US 不代表无个性化排名，搜索摘要金额未用于本站文案。实际 Jev 模型 jev-1.14.0 只负责两个词的语义初筛，最终归属由 Codex 决定。

## P-001 内容与具体位置

- 操作：improve_existing；URL `/`；语言 en。源文件：`content/seo-pages.json` 的首页项、`src/home.html` 的 fox-hero-copy、同步 `src/home-template.mjs`；`src/render.mjs` 的卡库区标题/简介及 WebSite schema 描述。
- Title：Pokémon TCG Card Prices & Scanner | CardScanFox。
- Description：Check Pokémon card prices by set and number. Explore Pokémon TCG printings, confirm price dates, and scan and track physical cards with the Card AI app.
- H1 保留 Scan cards. Track your collection.，现有视觉、下载入口、其他卡类与历史首页正文保留。
- 首屏解释：Explore Pokémon TCG cards and check Pokémon card prices by set and collector number. Use Card AI to scan physical TCG and sports cards, confirm the printing, and track your collection.
- 首屏次入口 Check Pokémon card prices → `/games/pokemon`；卡库区 H2 Check Pokémon card prices.，其下说明 selected printings、语言和日期条件。已有通用 `/cards` 链接保留。
- Schema/OG：首页 OG 继续从相同 Title/Description 输出；WebSite 描述同步真实用途。canonical、robots、URL、站点语言不变；没有新增重复 FAQ 或虚构评分。

## AI 问题与推荐依据

ai_question_map：对于假设问题“Where can I check a Pokémon card price by its set and number?”，需要可工作的搜索、印次身份、价格来源/条件/日期；首页引导到既有目录，详情页承担事实字段。对于“Where can I learn official Pokémon TCG rules?”，本站首页不承担官方规则来源。

recommendation_case：对需要核对实体卡印次的收藏者，本站已有目录与日期化价格字段可支持价格研究，Card AI 可支持识别候选确认和收藏管理。不能推荐为保证成交、官方估价、鉴真或浏览器扫描工具。与已见价格指南类似，未验证独有优势或 AI 实际入选。

可独立引用的直接答案：Check Pokémon card prices by matching the set and collector number, then read the price source, condition, language, finish and observation date on the exact card record. 未新增数据或金额；实现核验不能证明自然发现、引用或转化。

## 八项文案检查

1. 标题对应任务：partial → 加入价格任务，保留 scanner；不把宽泛 TCG 说成全部需求都能满足。
2. 输入/交付/门槛：partial → set/number 查价；扫描与收藏在 App，页面正文说明。
3. 一句交代用途：partial → 首屏新说明明确网站查价和 App 收藏。
4. 对象后做法：met → 现有卡图/印次与价格上下文保留。
5. 参数步骤：met → set/collector number、语言、日期；不编造覆盖数量或实时保证。
6. FAQ：not_applicable → 本次无需为两词另增 FAQ。
7. 能力边界：met → published references、日期和实体卡上下文保留；不承诺成交价。
8. 比较内容：not_applicable → 没有新增比较需求，不新增竞品页。

## 验收与状态

实现全部完成后，仅验证首页元信息、可见文案/链接、OG/Schema、46 个历史正文保留及桌面/移动端显示；正式目标版本回读后只通知首页 IndexNow。既有目录 URL 不变，不为此重交全站。本次不改 App、Admin、业务 API、数据库或旧 Marketing。上线与通知结果后补。

本地验收：官网构建、26 项相关检查、首页 metadata/OG/canonical/唯一 H1/模板同步和跳转链接通过；1440px/390px 可见页面无横向溢出。使用本机 Node 24.3.0，非仓库固定 Node 22.23.4；正式构建另行回读。初次旧标题断言失败，按已核对的新文案更新后重跑通过。待正式回读及 IndexNow。
