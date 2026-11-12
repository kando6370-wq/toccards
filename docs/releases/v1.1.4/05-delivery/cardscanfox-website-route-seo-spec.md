# CardScanFox 官网改版：网址保护与搜索意图规格

> 2026-11-07：用户已授权按搜索意图更新独立新版的标题和简介。元数据规则已进入本地代码；正式站未部署，Google 收录及点击效果未验证。

本文件与[主 Spec](../00-product/cardscanfox-website-redesign-spec.md)、[官网服务与数据隔离规格](../02-architecture/cardscanfox-website-service-spec.md)配套。

## 1. 已有网址保护规则

- 保持 `https://tcgcard.fun` 和全部既有路径。名称改为 CardScanFox 不触发换域名、换 slug 或全站重定向。
- 本轮 sitemap 有 46 个网址，逐项回读为 200。未获得本轮 Search Console 明细，因此不声称这 46 页分别有曝光或点击。
- 46 个网址是已知保护下限。实施前还要合并导航、内容源、Google Search Console、访问日志及已知外链中的非 sitemap 地址；有真实来源的旧网址都进入保护登记。
- 原有 `.html`、尾斜线和历史重定向响应先记录，再保持既有行为。不得把所有旧网址 301 到首页，也不得用 SPA 首页 200 冒充原页面。
- 下列文案按页面实际任务编写。当前生效的 Title 和 Description 以 `apps/cardscanfox-web/content/seo-pages.json` 为准；候选 H1 不自动覆盖原正文。旧地址、原 H1 和完整正文继续受保护。
- Card AI 仍是当前 App 和既有比较的查询名称。新网站可使用 CardScanFox 标识；商店、来源和注册主体使用真实名称。
- 比较文章仍使用 `/card-ai-vs-*`；归类到博客不改变地址。`/blog/` 保持尾斜线。法律页当前未输出 canonical，新增自指 canonical 需作为独立元数据变更核对。

## 2. 标题、简介与点击理由

每页先写用户要完成的任务，再说明页面实际能提供的答案。主题词靠前，品牌简短置后。
标题建议约 45–65 个英文字符，简介建议约 130–165 个字符；这是编辑提醒，不是 Google 的固定长度规则。超出时先保证意义完整，搜索展示会按设备截断。
卡牌页面优先出现卡名和全编号；文章优先表达版本区别、问题或比较维度。没有真实实测，不使用 fastest、most accurate、best overall 等结论。
不承诺 guaranteed price、real-time sold feed、unlimited free scan 或所有卡都有价格。
Google 可改写搜索标题和摘要。文案的点击收益需要在相近位置、查询、国家与设备条件下观察，不能把文案替换直接当成 CTR 提升。

## 3. 既有页面：逐页保留与文案草案

所有路径的动作均为“原址保留”。表格中的“原 checkout 缺失”记录首次盘点状态；这 13 篇文章已回收到独立新版，正文基线已纳入保护。

| 编号 | 原路径 | 当前 HTTP | 当前 canonical | 本地材料 | 主搜索意图 |
| --- | --- | --- | --- | --- | --- |
| LEG-01 | `/` | 200 | 自指 | 有本地 HTML | 产品认知与下载 |
| LEG-02 | `/basketball-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-03 | `/bulk-card-scanner` | 200 | 自指 | 有本地 HTML | 批量整理实体卡的 App 流程 |
| LEG-04 | `/card-ai-vs-collx` | 200 | 自指 | 有本地 HTML | 商业比较，选择查价及收藏工具 |
| LEG-05 | `/card-ai-vs-ludex` | 200 | 自指 | 有本地 HTML | 商业比较，扫描后收藏还是售卖 |
| LEG-06 | `/card-collection-tracker` | 200 | 自指 | 有本地 HTML | 选择收藏及价值追踪工具 |
| LEG-07 | `/card-identifier` | 200 | 自指 | 有本地 HTML | 从照片识别卡牌，选择工具 |
| LEG-08 | `/card-price-checker` | 200 | 自指 | 有本地 HTML | 查自己的单卡价值及操作方法 |
| LEG-09 | `/card-scanner-comparison-2026` | 200 | 自指 | 有本地 HTML | 比较扫描 App、额度和适用场景 |
| LEG-10 | `/chrome-extension` | 200 | 自指 | 有本地 HTML | 浏览器图片识别工具 |
| LEG-11 | `/digimon-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-12 | `/digital-card-binder` | 200 | 自指 | 有本地 HTML | 组织数字卡册与文件夹 |
| LEG-13 | `/dragon-ball-super-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-14 | `/flesh-and-blood-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-15 | `/football-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-16 | `/graded-card-tracker` | 200 | 自指 | 有本地 HTML | 管理已经评级的卡 |
| LEG-17 | `/lorcana-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-18 | `/mtg-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-19 | `/one-piece-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-20 | `/pokemon-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-21 | `/soccer-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-22 | `/star-wars-unlimited-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-23 | `/yugioh-card-scanner` | 200 | 自指 | 有本地 HTML | 寻找特定卡种扫描与收藏工具 |
| LEG-24 | `/blog/` | 200 | 自指 | 有本地 HTML | 浏览收藏知识和对比文章 |
| LEG-25 | `/blog/ascended-heroes-card-list` | 200 | 自指 | **已回收，原 checkout 缺失** | 查系列卡表与具体印次 |
| LEG-26 | `/blog/chaos-rising-card-list` | 200 | 自指 | **已回收，原 checkout 缺失** | 查系列卡表和参考价 |
| LEG-27 | `/blog/charizard-151-card-value` | 200 | 自指 | **已回收，原 checkout 缺失** | 区分 151 喷火龙编号并查价值 |
| LEG-28 | `/blog/charizard-gx-card-values` | 200 | 自指 | **已回收，原 checkout 缺失** | 区分 GX 版本、印章与促销卡 |
| LEG-29 | `/blog/cufant-card-values` | 200 | 自指 | **已回收，原 checkout 缺失** | 区分 Cufant 实体卡及价格 |
| LEG-30 | `/blog/ivysaur-card-values` | 200 | 自指 | **已回收，原 checkout 缺失** | 区分 Ivysaur 151 与初代卡 |
| LEG-31 | `/blog/mega-charizard-x-ex-card-value` | 200 | 自指 | **已回收，原 checkout 缺失** | 确认 Mega Charizard X ex 具体印次 |
| LEG-32 | `/blog/mew-gg10-card-value` | 200 | 自指 | **已回收，原 checkout 缺失** | 定位 Mew GG10/GG70 印次 |
| LEG-33 | `/blog/moonbreon-card-value` | 200 | 自指 | **已回收，原 checkout 缺失** | 把昵称解析为实际单卡 |
| LEG-34 | `/blog/phantasmal-flames-card-list` | 200 | 自指 | **已回收，原 checkout 缺失** | 查系列卡表与价格参考 |
| LEG-35 | `/blog/pikachu-card-values` | 200 | 自指 | **已回收，原 checkout 缺失** | 按版本查 Pikachu 价值 |
| LEG-36 | `/blog/pokemon-card-values` | 200 | 自指 | **已回收，原 checkout 缺失** | 学习按名称、系列、编号查值 |
| LEG-37 | `/blog/rayquaza-vmax-card-values` | 200 | 自指 | **已回收，原 checkout 缺失** | 比较 Rayquaza VMAX 多印次 |
| LEG-38 | `/blog/pokemon-tcg-set-card-lists` | 200 | 自指 | 有本地 HTML | 查多个 Pokémon 系列官方卡表 |
| LEG-39 | `/blog/dungeon-crawler-carl-trading-cards` | 200 | 自指 | 有本地 HTML | 辨别收藏卡发行与不同产品 |
| LEG-40 | `/blog/minior-pokemon-card-guide` | 200 | 自指 | 有本地 HTML | 辨别 Minior 实体 TCG 版本 |
| LEG-41 | `/blog/scanning-cards-from-watsontcg` | 200 | 自指 | 有本地 HTML | 购买后如何识别支持的单卡 |
| LEG-42 | `/blog/pokemon-tcg-30th-celebration-card-prices` | 200 | 自指 | 有本地 HTML | 区分周年套卡、单卡和产品 |
| LEG-43 | `/blog/what-is-my-trading-card-worth` | 200 | 自指 | 有本地 HTML | 学习估值步骤 |
| LEG-44 | `/blog/raw-vs-graded-card-values` | 200 | 自指 | 有本地 HTML | 理解裸卡与已评级卡价格差异 |
| LEG-45 | `/privacy` | 200 | 当前缺失，单独补齐 | 有本地 HTML | 了解隐私和数据处理 |
| LEG-46 | `/terms` | 200 | 当前缺失，单独补齐 | 有本地 HTML | 了解网站使用条款 |

### LEG-01 `/`

- 搜索意图：产品认知与下载。
- 当前线上标题：`Card AI: TCG Card Scanner, Price Checker & Collection Tracker`。
- 候选 Title：`TCG Card Scanner & Collection Tracker | CardScanFox`。
- 候选 H1：`Scan cards. Track your collection.`。
- 候选 Description：`Identify trading cards, confirm the printing and check available prices. Organize owned cards and a separate Wishlist in the Card AI app.`。
- 保留与差异化：首页保留 /；新品牌与现有 Card AI App 的关系必须清楚。

### LEG-02 `/basketball-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Basketball Card Scanner & Value Checker | Card AI`。
- 候选 Title：`Basketball Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`Basketball card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely Basketball card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对球员、年份、系列、编号与平行版本；本页保留原功能意图，不改成公共卡库列表。

### LEG-03 `/bulk-card-scanner`

- 搜索意图：批量整理实体卡的 App 流程。
- 当前线上标题：`Bulk Card Scanner: Scan a Stack of Cards at Once | Card AI`。
- 候选 Title：`Bulk Card Scanner: Review a Stack of Cards | CardScanFox`。
- 候选 H1：`Scan a stack. Confirm each card.`。
- 候选 Description：`Queue up to 10 card photos in the Card AI app. Review each match, confirm printing details, then add the copies you own to your collection.`。
- 保留与差异化：保留批量整理意图；10 张队列不等于免费额度，也不宣称同一照片识别整桌卡。

### LEG-04 `/card-ai-vs-collx`

- 搜索意图：商业比较，选择查价及收藏工具。
- 当前线上标题：`Card AI vs CollX: Prices and Collection | Card AI`。
- 候选 Title：`Card AI vs CollX: Price & Collection Workflows | CardScanFox`。
- 候选 H1：`Card AI vs CollX: what does the price represent?`。
- 候选 Description：`Compare documented Card AI and CollX workflows for card variants, condition, price context and collections. See source dates and limits before choosing.`。
- 保留与差异化：归入博客对比分类，原路径和 Card AI 查询词保留。

### LEG-05 `/card-ai-vs-ludex`

- 搜索意图：商业比较，扫描后收藏还是售卖。
- 当前线上标题：`Card AI vs Ludex: Scan, Price and List | Card AI`。
- 候选 Title：`Card AI vs Ludex: Compare the Next Step | CardScanFox`。
- 候选 H1：`Card AI vs Ludex: what happens after the scan?`。
- 候选 Description：`Compare documented scan review, price research, collection and listing workflows. Choose by your next task, with sources and testing limits explained.`。
- 保留与差异化：不改为 /blog/... 或 /cardscanfox-vs-ludex；没有实测不写准确率赢家。

### LEG-06 `/card-collection-tracker`

- 搜索意图：选择收藏及价值追踪工具。
- 当前线上标题：`Card Collection Tracker & Value App | Card AI`。
- 候选 Title：`Card Collection Tracker & Portfolio App | CardScanFox`。
- 候选 H1：`Know what you own. Follow your collection.`。
- 候选 Description：`Track owned trading cards, quantities and available collection value. Keep a separate Wishlist and organize confirmed holdings in the Card AI app.`。
- 保留与差异化：重在持仓与价值；不与卡册页重复目录组织内容。

### LEG-07 `/card-identifier`

- 搜索意图：从照片识别卡牌，选择工具。
- 当前线上标题：`Trading Card Identifier From a Photo | Card AI`。
- 候选 Title：`Trading Card Identifier From a Photo | CardScanFox`。
- 候选 H1：`Find the card. Confirm the printing.`。
- 候选 Description：`Identify likely trading card matches from a photo. Check the set, number, language and finish before saving the confirmed record in the Card AI app.`。
- 保留与差异化：本页是 App 功能说明，不能伪装成网页可直接扫描的工具。

### LEG-08 `/card-price-checker`

- 搜索意图：查自己的单卡价值及操作方法。
- 当前线上标题：`How Much Is This Card Worth? Card Price Checker | Card AI`。
- 候选 Title：`What Is Your Card Worth? Card Price Checker | CardScanFox`。
- 候选 H1：`Find the price for your exact card.`。
- 候选 Description：`Learn how to check a trading card price by set, number, finish and condition. Explore dated references and continue your own lookup in the Card AI app.`。
- 保留与差异化：保留主要查价说明入口；/prices 是目录概览，不另做同文的关键词页。

### LEG-09 `/card-scanner-comparison-2026`

- 搜索意图：比较扫描 App、额度和适用场景。
- 当前线上标题：`Trading Card Scanner Apps Compared in 2026 | Card AI`。
- 候选 Title：`Trading Card Scanner Apps Compared: 2026 Guide | CardScanFox`。
- 候选 H1：`Which card scanner fits your collection?`。
- 候选 Description：`Compare card scanner workflows, free-scan limits, price context and collection tools. Read the dated sources and choose what fits the cards you own.`。
- 保留与差异化：保留年份 URL；内容复核后更新日期，不为次年复制同一意图。

### LEG-10 `/chrome-extension`

- 搜索意图：浏览器图片识别工具。
- 当前线上标题：`Chrome Card Recognizer for Pokémon and TCG | Card AI`。
- 候选 Title：`Chrome Card Recognizer for Pokémon & TCG | CardScanFox`。
- 候选 H1：`Identify a card image while you browse.`。
- 候选 Description：`Select a card image on a webpage, adjust the crop and review likely matches with the Chrome recognizer. Check available reference prices and coverage.`。
- 保留与差异化：保留真实 Chrome Web Store 链接、UTM 与扩展边界；不加入 App 的收藏能力。

### LEG-11 `/digimon-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Digimon Card Scanner & Value Checker | Card AI`。
- 候选 Title：`Digimon Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`Digimon card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely Digimon card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对卡号、补充包、语言与平行图；本页保留原功能意图，不改成公共卡库列表。

### LEG-12 `/digital-card-binder`

- 搜索意图：组织数字卡册与文件夹。
- 当前线上标题：`Digital Card Binder & Collection Catalog | Card AI`。
- 候选 Title：`Digital Card Binder: Organize Your Cards | CardScanFox`。
- 候选 H1：`Give every card a place in your collection.`。
- 候选 Description：`Organize confirmed card holdings into folders in the Card AI app. Keep printing, quantity, raw condition and existing slab grades with each copy.`。
- 保留与差异化：重在分类和文件夹；不承诺导入导出或完整套卡完成率。

### LEG-13 `/dragon-ball-super-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Dragon Ball Super Card Scanner & Value Checker | Card AI`。
- 候选 Title：`Dragon Ball Super Card Scanner: Check Coverage | CardScanFox`。
- 候选 H1：`Dragon Ball Super card scanning: check the supported record first.`。
- 候选 Description：`Learn how to check Dragon Ball Super card coverage before scanning. Confirm a catalog match, printing details and available price context in the Card AI app.`。
- 保留与差异化：覆盖需要重新核对；目录缺口不能以标题承诺填补；本页保留原功能意图，不改成公共卡库列表。

### LEG-14 `/flesh-and-blood-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Flesh and Blood Card Scanner & Value Checker | Card AI`。
- 候选 Title：`Flesh and Blood Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`Flesh and Blood card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely Flesh and Blood card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对系列、卡号、工艺与语言；本页保留原功能意图，不改成公共卡库列表。

### LEG-15 `/football-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Football Card Scanner: Check Football Card Values | Card AI`。
- 候选 Title：`Football Card Scanner: Check Coverage | CardScanFox`。
- 候选 H1：`Football card scanning: check the supported record first.`。
- 候选 Description：`Learn how to check Football card coverage before scanning. Confirm a catalog match, printing details and available price context in the Card AI app.`。
- 保留与差异化：覆盖需要重新核对；保留 URL 和已有用户价值；本页保留原功能意图，不改成公共卡库列表。

### LEG-16 `/graded-card-tracker`

- 搜索意图：管理已经评级的卡。
- 当前线上标题：`Graded Card Tracker: Raw vs Graded Values | Card AI`。
- 候选 Title：`Graded Card Tracker: Keep Each Copy Separate | CardScanFox`。
- 候选 H1：`Track the grade already on your slab.`。
- 候选 Description：`Record existing PSA, BGS, CGC or SGC grades alongside raw card holdings. Check available grade-specific prices without mixing different copies.`。
- 保留与差异化：不承诺照片预测评级、送评、鉴定或所有等级都有价格。

### LEG-17 `/lorcana-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Lorcana Card Scanner & Value Checker | Card AI`。
- 候选 Title：`Lorcana Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`Lorcana card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely Lorcana card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对系列、全编号、语言与工艺；本页保留原功能意图，不改成公共卡库列表。

### LEG-18 `/mtg-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`MTG Card Scanner & Collection Tracker | Card AI`。
- 候选 Title：`MTG Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`MTG card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely MTG card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对系列、编号、语言与 foil 状态；本页保留原功能意图，不改成公共卡库列表。

### LEG-19 `/one-piece-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`One Piece Card Scanner & Value Checker | Card AI`。
- 候选 Title：`One Piece Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`One Piece card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely One Piece card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对完整卡号、版本及平行图；保留官方卡表链接；本页保留原功能意图，不改成公共卡库列表。

### LEG-20 `/pokemon-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Pokemon Card Scanner App & Value Checker | Card AI`。
- 候选 Title：`Pokémon Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`Pokémon card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely Pokémon card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对系列、全编号、语言与闪卡工艺；本页保留原功能意图，不改成公共卡库列表。

### LEG-21 `/soccer-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Soccer Card Scanner: Check Soccer Card Values | Card AI`。
- 候选 Title：`Soccer Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`Soccer card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely Soccer card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对球员、年份、系列、编号和平行版本；本页保留原功能意图，不改成公共卡库列表。

### LEG-22 `/star-wars-unlimited-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Star Wars Unlimited Card Scanner & Value Checker | Card AI`。
- 候选 Title：`Star Wars Unlimited Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`Star Wars Unlimited card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely Star Wars Unlimited card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对系列、卡号、版本与工艺；本页保留原功能意图，不改成公共卡库列表。

### LEG-23 `/yugioh-card-scanner`

- 搜索意图：寻找特定卡种扫描与收藏工具。
- 当前线上标题：`Yu-Gi-Oh! Card Scanner & Value Checker | Card AI`。
- 候选 Title：`Yu-Gi-Oh! Card Scanner: Identify Your Printing | CardScanFox`。
- 候选 H1：`Yu-Gi-Oh! card scanning: confirm the copy you own.`。
- 候选 Description：`Find likely Yu-Gi-Oh! card matches in the Card AI app. Confirm the set, full number and printing details, then check available prices for your copy.`。
- 保留与差异化：核对全卡号、版本、稀有度与语言；本页保留原功能意图，不改成公共卡库列表。

### LEG-24 `/blog/`

- 搜索意图：浏览收藏知识和对比文章。
- 当前线上标题：`Card AI Blog: Trading Card Values & Collecting Guides`。
- 候选 Title：`Trading Card Guides & App Comparisons | CardScanFox`。
- 候选 H1：`Better information. Better collecting.`。
- 候选 Description：`Learn to identify card printings, understand dated prices and organize a collection. Read practical guides, app comparisons and clearly labelled perspectives.`。
- 保留与差异化：博客主目录保留尾斜线；分类只组织入口，不复制正文。

### LEG-25 `/blog/ascended-heroes-card-list`

- 搜索意图：查系列卡表与具体印次。
- 当前线上标题：`Ascended Heroes Card List and Prices | Card AI`。
- 候选 Title：`Ascended Heroes Card List & Printing Guide | CardScanFox`。
- 候选 H1：`Ascended Heroes: find the printing before the price.`。
- 候选 Description：`Explore the Ascended Heroes card-list guide. Check full card numbers, available catalog records and dated references before comparing your copy.`。
- 保留与差异化：保留已有官方来源及价格日期；目录覆盖不等于完整官方卡表。

### LEG-26 `/blog/chaos-rising-card-list`

- 搜索意图：查系列卡表和参考价。
- 当前线上标题：`Chaos Rising Card List and Price Snapshot | Card AI`。
- 候选 Title：`Chaos Rising Card List & Price References | CardScanFox`。
- 候选 H1：`Chaos Rising card list and price references.`。
- 候选 Description：`Use the Chaos Rising guide to match card names and full numbers. Separate catalog coverage from the dated prices available for individual printings.`。
- 保留与差异化：保留已发布卡表解释，不改成只有目录链接的薄页。

### LEG-27 `/blog/charizard-151-card-value`

- 搜索意图：区分 151 喷火龙编号并查价值。
- 当前线上标题：`Charizard 151 Card Values by Number | Card AI`。
- 候选 Title：`Charizard 151 Values: 006, 183 or 199? | CardScanFox`。
- 候选 H1：`Which Charizard 151 printing do you own?`。
- 候选 Description：`Compare Charizard 151 records 006/165, 183/165 and 199/165. Match the artwork and full number before using a dated raw or graded price reference.`。
- 保留与差异化：保持具体编号的独立比较价值。

### LEG-28 `/blog/charizard-gx-card-values`

- 搜索意图：区分 GX 版本、印章与促销卡。
- 当前线上标题：`Charizard GX Values: Hidden Fates, SV49 and SM211 | Card AI`。
- 候选 Title：`Charizard GX Values: SV49, SM211 & More | CardScanFox`。
- 候选 H1：`Identify your Charizard GX before checking its value.`。
- 候选 Description：`Separate Charizard GX printings by set, full number and product stamp. Review Hidden Fates and promo records before comparing available prices.`。
- 保留与差异化：不得把不同印次价格混合为角色统一价格。

### LEG-29 `/blog/cufant-card-values`

- 搜索意图：区分 Cufant 实体卡及价格。
- 当前线上标题：`Cufant Card Values: Shrouded Fable and Shiny Vault | Card AI`。
- 候选 Title：`Cufant Card Values by Set & Number | CardScanFox`。
- 候选 H1：`Which Cufant card matches your copy?`。
- 候选 Description：`Compare selected Cufant printings from Shrouded Fable and Shiny Vault. Check the complete number, finish and date before using a price reference.`。
- 保留与差异化：留存现有具体卡图、来源和参考样本。

### LEG-30 `/blog/ivysaur-card-values`

- 搜索意图：区分 Ivysaur 151 与初代卡。
- 当前线上标题：`Ivysaur Card Values: 151 and Base Set | Card AI`。
- 候选 Title：`Ivysaur Card Values: 151 vs Base Set | CardScanFox`。
- 候选 H1：`Ivysaur values start with the right set.`。
- 候选 Description：`Separate Ivysaur 151 and Base Set records by artwork and collector number. Confirm language, finish and condition before comparing dated values.`。
- 保留与差异化：内容保留印次比较；不用单卡数据详情替代全文。

### LEG-31 `/blog/mega-charizard-x-ex-card-value`

- 搜索意图：确认 Mega Charizard X ex 具体印次。
- 当前线上标题：`Mega Charizard X ex Values by Card Number | Card AI`。
- 候选 Title：`Mega Charizard X ex Value: Match the Number | CardScanFox`。
- 候选 H1：`Find the exact Mega Charizard X ex printing.`。
- 候选 Description：`Check the Phantasmal Flames set and full collector number for Mega Charizard X ex. Use the matching record and date when reviewing available prices.`。
- 保留与差异化：保留系列与编号核对流程。

### LEG-32 `/blog/mew-gg10-card-value`

- 搜索意图：定位 Mew GG10/GG70 印次。
- 当前线上标题：`Mew GG10 Card Value: Crown Zenith GG10/GG70 | Card AI`。
- 候选 Title：`Mew GG10 Value: Crown Zenith GG10/GG70 | CardScanFox`。
- 候选 H1：`Mew GG10: confirm Crown Zenith GG10/GG70.`。
- 候选 Description：`Identify Mew GG10 from Crown Zenith before checking its value. Keep the gallery prefix, full number and condition with each dated price reference.`。
- 保留与差异化：保留 GG 前缀语义。

### LEG-33 `/blog/moonbreon-card-value`

- 搜索意图：把昵称解析为实际单卡。
- 当前线上标题：`Moonbreon Card Value: Umbreon VMAX 215/203 | Card AI`。
- 候选 Title：`Moonbreon Value: Umbreon VMAX 215/203 | CardScanFox`。
- 候选 H1：`Moonbreon means a specific Umbreon VMAX printing.`。
- 候选 Description：`Match Moonbreon to Umbreon VMAX 215/203 from Evolving Skies. Check the exact printing, language and raw or graded state before comparing prices.`。
- 保留与差异化：昵称只作检索线索，不创建多个同文昵称页。

### LEG-34 `/blog/phantasmal-flames-card-list`

- 搜索意图：查系列卡表与价格参考。
- 当前线上标题：`Phantasmal Flames Card List and Prices | Card AI`。
- 候选 Title：`Phantasmal Flames Card List & Prices | CardScanFox`。
- 候选 H1：`Explore Phantasmal Flames by card and number.`。
- 候选 Description：`Use the Phantasmal Flames guide to find card-list references and selected catalog records. Confirm each printing before using its dated price.`。
- 保留与差异化：源事实与官网已验证卡表为准。

### LEG-35 `/blog/pikachu-card-values`

- 搜索意图：按版本查 Pikachu 价值。
- 当前线上标题：`Pikachu Card Values: Match the Printing | Card AI`。
- 候选 Title：`Pikachu Card Values: Which Printing Is Yours? | CardScanFox`。
- 候选 H1：`Find your Pikachu printing before its price.`。
- 候选 Description：`Pikachu appears across many releases. Compare the set, full number, language and finish to find a price reference that belongs to your copy.`。
- 保留与差异化：角色聚合解释页，不等同目录中任一单卡详情。

### LEG-36 `/blog/pokemon-card-values`

- 搜索意图：学习按名称、系列、编号查值。
- 当前线上标题：`Pokemon Card Values by Name, Set and Number | Card AI`。
- 候选 Title：`Pokémon Card Values by Name, Set & Number | CardScanFox`。
- 候选 H1：`Find a Pokémon card value by its exact printing.`。
- 候选 Description：`Start with the Pokémon name, set and full card number. Explore printing guides and learn how condition and price dates affect the reference you use.`。
- 保留与差异化：与 App 查价功能页按学习/操作分工，避免新增 /pokemon-price-checker 同文页。

### LEG-37 `/blog/rayquaza-vmax-card-values`

- 搜索意图：比较 Rayquaza VMAX 多印次。
- 当前线上标题：`Rayquaza VMAX Values: Printings and Prices | Card AI`。
- 候选 Title：`Rayquaza VMAX Values: Compare the Printings | CardScanFox`。
- 候选 H1：`Rayquaza VMAX values depend on the printing.`。
- 候选 Description：`Compare selected Rayquaza VMAX records from Evolving Skies, Crown Zenith and Trainer Gallery. Check set, number and condition before using prices.`。
- 保留与差异化：保留多个实物版本对照。

### LEG-38 `/blog/pokemon-tcg-set-card-lists`

- 搜索意图：查多个 Pokémon 系列官方卡表。
- 当前线上标题：`Pokemon TCG Set Card Lists and Prices | Card AI`。
- 候选 Title：`Pokémon TCG Set Card Lists & Lookup Guide | CardScanFox`。
- 候选 H1：`Find the right Pokémon set and card number.`。
- 候选 Description：`Find official card-list references for selected Pokémon sets. Match a catalog set code and full number before looking up a physical single card.`。
- 保留与差异化：沿用已有多个系列目录入口，不复制官方全文或保证全覆盖。

### LEG-39 `/blog/dungeon-crawler-carl-trading-cards`

- 搜索意图：辨别收藏卡发行与不同产品。
- 当前线上标题：`Dungeon Crawler Carl Trading Cards: Series 1 Guide | Card AI`。
- 候选 Title：`Dungeon Crawler Carl Cards: Release Guide | CardScanFox`。
- 候选 H1：`Dungeon Crawler Carl trading cards: know the release.`。
- 候选 Description：`Distinguish Dungeon Crawler Carl collectible-card releases and related products. Check the actual single-card record before assuming catalog or price coverage.`。
- 保留与差异化：发行事实和目录覆盖分别核实；不宣称每套或每卡都已支持。

### LEG-40 `/blog/minior-pokemon-card-guide`

- 搜索意图：辨别 Minior 实体 TCG 版本。
- 当前线上标题：`Minior Pokemon Cards: Set Numbers and Value Checks | Card AI`。
- 候选 Title：`Minior Pokémon Cards: Printings & Value Checks | CardScanFox`。
- 候选 H1：`Identify the Minior card in your collection.`。
- 候选 Description：`Compare selected Minior Pokémon TCG printings by set and number. Keep physical trading cards separate from Pokémon GO encounters and game advice.`。
- 保留与差异化：不承接游戏攻略；保留官方卡表出处。

### LEG-41 `/blog/scanning-cards-from-watsontcg`

- 搜索意图：购买后如何识别支持的单卡。
- 当前线上标题：`Scan Cards Bought at WatsonTCG | Card AI`。
- 候选 Title：`Scan Cards Bought at WatsonTCG | CardScanFox`。
- 候选 H1：`Match the single card, not the retailer name.`。
- 候选 Description：`Bought cards at WatsonTCG? Identify each supported single by its game, set and number, then review the record in the Card AI app. Coverage varies.`。
- 保留与差异化：保留零合作声明，不把商店或全部库存当作支持卡种。

### LEG-42 `/blog/pokemon-tcg-30th-celebration-card-prices`

- 搜索意图：区分周年套卡、单卡和产品。
- 当前线上标题：`Pokemon 30th Anniversary: Card Lists & Prices | Card AI`。
- 候选 Title：`Pokémon 30th Celebration: Card Lists & Prices | CardScanFox`。
- 候选 H1：`Pokémon 30th Celebration: identify the card first.`。
- 候选 Description：`Separate 30th Celebration catalog groups, official card-list references and dated single-card price samples. Check set codes before valuing your copy.`。
- 保留与差异化：保留原观测日期，不能把旧快照写成当前价格；密封产品内容与单卡估值分开。

### LEG-43 `/blog/what-is-my-trading-card-worth`

- 搜索意图：学习估值步骤。
- 当前线上标题：`What Is My Trading Card Worth? | Card AI`。
- 候选 Title：`What Is My Trading Card Worth? | CardScanFox`。
- 候选 H1：`Work out which price applies to your card.`。
- 候选 Description：`Identify the printing, assess raw condition or record an existing slab grade, and check price context. Learn which reference can apply to your trading card.`。
- 保留与差异化：教学意图归此文；具体价格归对应单卡；功能操作归 /card-price-checker。

### LEG-44 `/blog/raw-vs-graded-card-values`

- 搜索意图：理解裸卡与已评级卡价格差异。
- 当前线上标题：`Raw vs Graded Card Values: What Changes | Card AI`。
- 候选 Title：`Raw vs Graded Card Values: What Changes? | CardScanFox`。
- 候选 H1：`Raw and graded prices answer different questions.`。
- 候选 Description：`Learn why raw condition and an existing slab grade belong to separate price records. Compare like-for-like printings without assuming a guaranteed grading premium.`。
- 保留与差异化：不把相关性写成保证评级溢价，不给无证据收益承诺。

### LEG-45 `/privacy`

- 搜索意图：了解隐私和数据处理。
- 当前线上标题：`Privacy Policy | Card AI`。
- 候选 Title：`Privacy Policy | CardScanFox`。
- 候选 H1：`Privacy Policy`。
- 候选 Description：`Read how the CardScanFox website and linked services handle information, including website analytics, local saved references and your privacy choices.`。
- 保留与差异化：法律正文保留；新增数据处理只有完成法务复核才可写入。本轮仅标题/摘要草案。

### LEG-46 `/terms`

- 搜索意图：了解网站使用条款。
- 当前线上标题：`Terms of Use | Card AI`。
- 候选 Title：`Terms of Use | CardScanFox`。
- 候选 H1：`Terms of Use`。
- 候选 Description：`Read the terms for using the CardScanFox website, its card information and dated price references, plus links to the terms that apply to the app.`。
- 保留与差异化：保留法律主体和 App 条款边界，不能通过视觉改版擅改合同。

## 4. 新增页面与模板

以下是本次新增资料能力的地址草案。它们不会替代上述旧地址。动态占位符由真实记录生成，不是待创建的字符串 URL。

### NEW-01 `/cards`

- 搜索意图：目录浏览与条件筛选。
- Title：`Trading Card Database: Find Your Printing | CardScanFox`。
- H1：`Explore the card catalog.`。
- Description：`Browse trading cards by game, set, name and number. Check each printing, language and dated reference before opening its card details.`。
- 开放与收录条件：目录投影与服务端 HTML 就绪后可开放；?q= 任意搜索及组合筛选默认 noindex,follow。

### NEW-02 `/games`

- 搜索意图：按卡种选择目录。
- Title：`Trading Card Games & Sports Cards | CardScanFox`。
- H1：`Find your game. Explore its cards.`。
- Description：`Explore supported TCG and sports-card catalogs. Choose a game to browse sets, identify printings and inspect available dated prices.`。
- 开放与收录条件：只列已确认可浏览目录，不从营销文案推断支持范围。

### NEW-03 `/games/{gameSlug}`

- 搜索意图：某个卡种的资料目录。
- Title：`{Game} Cards, Sets & Price References | CardScanFox`。
- H1：`Explore {Game} cards and sets.`。
- Description：`Browse {Game} catalog records and represented sets. Confirm the card number, language and finish before using an available price reference.`。
- 开放与收录条件：逐卡种评审，需与旧 scanner 功能页有独立用途；占位符不能直接发布。

### NEW-04 `/sets`

- 搜索意图：按系列浏览。
- Title：`Trading Card Sets & Card Lists | CardScanFox`。
- H1：`Find the set. Match the card.`。
- Description：`Browse represented trading card sets, then open their cataloged singles. Check set codes and coverage before treating any list as complete.`。
- 开放与收录条件：准确说明目录覆盖，按游戏和年份过滤的任意组合不自动索引。

### NEW-05 `/sets/{publicSetId}`

- 搜索意图：指定系列卡表与单卡入口。
- Title：`{Set Name} Card List & Price References | CardScanFox`。
- H1：`{Set Name}: cards in the catalog.`。
- Description：`Explore cataloged {Set Name} singles with full numbers, images and available dated prices. Check coverage and exact printing before comparing cards.`。
- 开放与收录条件：区别现有解释型卡表文章；不能仅复制文章做同词竞争页。

### NEW-06 `/cards/{publicCardId}`

- 搜索意图：指定实物印次查资料与价格。
- Title：`{Card Name} {Card Number}: Price & Details | CardScanFox`。
- H1：`{Card Name} · {Card Number}`。
- Description：`Check {Card Name} {Card Number} from {Set Name}. Confirm language and finish, see the latest available reference and its date, then explore the 30-day trend.`。
- 开放与收录条件：需独立稳定记录、许可卡图、充分身份信息；缺价变体改摘要，不承诺一定有趋势。

### NEW-07 `/prices`

- 搜索意图：浏览已发布价格参考。
- Title：`Trading Card Price References by Printing | CardScanFox`。
- H1：`Read the price. Know the context.`。
- Description：`Explore dated trading card references by exact printing. Compare currency, observation date and condition before using a price for your copy.`。
- 开放与收录条件：不是交易市场、热度榜或保证实时行情；保留旧 /card-price-checker 的操作说明。

### NEW-08 `/app`

- 搜索意图：理解整体产品及安装。
- Title：`CardScanFox App: Scan, Review & Collect`。
- H1：`Scan, confirm and organize your cards.`。
- Description：`See how the Card AI app turns card photos into reviewed collection records. Explore Portfolio, folders, Wishlist and available card-price history.`。
- 开放与收录条件：链接已有功能页与真实商店，不能暗示 App 已完成名称变更。

### NEW-09 `/help`

- 搜索意图：解答产品与数据问题。
- Title：`CardScanFox Help: Cards, Prices & Collections`。
- H1：`Good questions. Clear answers.`。
- Description：`Find answers about card identification, dated price references, missing data, saved website records and collection management in the Card AI app.`。
- 开放与收录条件：公开帮助可索引；包含支持联系方式，不提供用户数据或私有工单。

### NEW-10 `/data-methodology`

- 搜索意图：核查价格与目录口径。
- Title：`Card Data & Price Reference Methodology | CardScanFox`。
- H1：`Understand the record behind the reference.`。
- Description：`Learn how catalog identities, published sources, price dates and missing coverage are represented on CardScanFox. Compare references with the right context.`。
- 开放与收录条件：仅发布可证实的方法与来源；不披露商业凭据或未获授权的完整数据。

### NEW-11 `/blog/category/{categorySlug}`

- 搜索意图：按主题阅读文章。
- Title：`{Topic} Guides & Comparisons | CardScanFox`。
- H1：`Explore {Topic}.`。
- Description：`Read practical {Topic} articles with sources, review dates and links to relevant card records and product workflows.`。
- 开放与收录条件：分类初期默认 noindex,follow；有独立导读、内容数量与用户价值后人工申请收录。

### NEW-12 `/saved`

- 搜索意图：回看本机保存的参考卡牌。
- Title：`Saved Card References | CardScanFox`。
- H1：`Your saved card references.`。
- Description：`Review the cards saved in this browser. These reference bookmarks are separate from the Portfolio and Wishlist you manage in the Card AI app.`。
- 开放与收录条件：私有个性化状态；允许 Google 读取页面以看到 noindex,nofollow，响应使用 no-store，不入 sitemap。robots 不再禁止 /saved，避免 Search Console 将预期排除报告为 robots 屏蔽。

### 单卡模板的缺失分支

- 缺价 Title 可仍为 `{Card Name} {Card Number}: Card Details | CardScanFox`。
- 缺价简介：`Identify {Card Name} {Card Number} from {Set Name}. Check its printing details and available catalog information. No published price is currently listed.`
- 确认过有效零价时展示 `$0.00`；未有价格时展示 `Price unavailable`。不通过改标题伪造价格可用性。
- 数据不足时不公开新索引页。已存在的受保护页则进入人工质量处理，不能因一次同步失败自动 noindex 或删除。

## 5. 页面归属和内链

| 查询任务 | 首选页面 | 内容页应如何连接 |
| --- | --- | --- |
| 单卡具体编号和价格 | 对应新单卡详情 | 旧指南保留版本解释，链接精确印次。 |
| 卡种扫描 App | 既有 `/{game}-card-scanner` | 卡种目录通过“在 App 扫描”链接到功能页。 |
| 系列卡表 | 有完整实用目录时的系列页；上线前沿用现有指南 | 若与既有指南任务实质相同，先增强原页，不机械新建同词竞争页。 |
| Card AI vs Ludex/CollX | 既有比较 URL | 博客分类可链接它，不另存正文。 |
| 裸卡和已评级价值差异 | 既有 raw-vs-graded 文章 | 链接评级追踪功能及相关单卡，彼此不复制整段正文。 |
| 如何查价与选择 App | 既有 price-checker 功能说明 | /prices 用于浏览数据概览；不能把功能页改为另一个相同列表。 |
| 导航博客主题 | /blog/ 和按需开放的分类 | 同一正文一个 canonical URL，标签不扩张为全部可索引组合。 |

## 6. 技术 SEO 与 GEO 规则

- 公开资料正文、Title、Description、H1、自指 canonical、面包屑及相关链接存在于首个 HTML。原型的 `#card-*` 不是正式 URL。
- 新目录的任意搜索、排序、筛选组合及空结果不进入 sitemap，默认 noindex,follow。可收录的精选分类由项目索引策略文件登记独立固定路由；必须自指 canonical，不能随意 canonical 到不等价内容。
- 分页固定有限范围与稳定排序。已开放的目录分页要有真实 `<a href>`、各自内容和自指 canonical；不把所有分页 canonical 到第一页。超范围请求不生成无限空页。
- sitemap 只含实际发布、允许收录、可回读的 canonical URL；lastmod 取内容或实质数据变更时间，不用每次构建时间全量刷新。
- 新分类可默认 noindex；但已被索引的旧页若要改变 robots，必须独立评审，不能被新模板默认值覆盖。
- JSON-LD 与正文一致。Article、BreadcrumbList、WebSite、Organization 按真实身份填写；无购买能力和可购买报价时，不用虚构 Offer 或评分制造富结果。
- 单卡的事实、价格口径、观测日期和来源公开可读。文章保留作者或审核责任、来源日期、实测范围与观点标记。
- `llms.txt` 可继续作为一致的公开内容清单。它不是 Google 排名或 AI 引用开关；不堆虚构 Schema，不隐藏 SEO 文本。
- 原型 /brand 比较与品牌素材下载属于设计评审面，不自动进入正式公开网站；正式确需品牌资源页时另行确认。

## 7. 上线前和上线后的观察

保护登记合并完毕后，对每个旧路由检查状态码、主内容、自指 canonical、robots、内链及 sitemap。仅 200 不证明原文章仍在。
新版前端独立部署，先在受限、noindex 的预览地址与旧站逐页比较。验收后由新版接管同一个 `https://tcgcard.fun` Host 和原路径，访客地址不变。域名的服务归属切换不意味着自动保留 SEO；原文、状态、canonical 和元数据仍需逐项检查。

预览的正文导航应能留在预览环境，正式来源配置要固定为获准的生产域名。预览不提交 sitemap/IndexNow，生产接管后必须移除预览认证和 noindex。执行步骤见服务规格第 9 节。

旧页面换肤与新目录开放分阶段验收。既有高曝光页面的标题可分批更新，保留替换前版本、日期和页面表现基线。
取得可用 Search Console 授权后，按 page/query/country/device 对照；缺少报告不是零需求。新目录的收录、曝光、点击和 App 商店点击分别记录。
只在获授权的正式发布完成并回读新版本后，按项目 IndexNow 配置提交本次变更 URL；本轮文档不执行提交，也不建立定时扫描。

## 8. 官方参考

- [Google：标题链接](https://developers.google.com/search/docs/appearance/title-link)：标题需清楚、独立且与主内容一致。
- [Google：摘要](https://developers.google.com/search/docs/appearance/snippet)：摘要可由正文自动生成，简介不是固定展示承诺。
- [Google：网站迁移](https://developers.google.com/search/docs/crawling-indexing/site-move-with-url-changes)：换域名、布局与系统宜分步处理。本次保持域名和既有路径。
- [Google：AI 搜索优化](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide)：继续依赖可访问、有独立价值的内容；无专用 AI 文件要求。

Jev 1.14.0 对 46 页公开标题/H1做过意图初分类；部分指南被误分为法律页或目录页，已由 Codex 逐页修正。本文中的意图、页面归属和文案由 Codex 负责，不代表搜索量验证或 CTR 实验结果。

## 8. 大规模卡牌索引实现

单卡标题与简介由共享 `packages/website-content/src/seo.mjs` 生成。实际卡名、全编号、系列名/代码和可用价格状态参与文案，标题不写会频繁变化的报价。价格缺失时使用 Card Details 和明确缺价的简介，不把缺价转换为零。

新增静态栏目按实际任务登记；单卡不逐条加入 newIndexPaths。正式模式下，真实已发布数据、稳定身份、编号、系列和公开目录图满足要求时可索引。预览始终 noindex。搜索/排序/价格序列等参数不建立额外可索引印次页。

几十万卡牌不在 Worker 构建时生成同等数量的 HTML 文件。详情保持 SSR；全量候选通过 NDJSON 流式处理，XML 按网址数和 UTF-8 字节数拆分，根 sitemap index 汇总。发现批次与单页索引资格分开。详见[卡牌目录规模与索引](cardscanfox-catalog-indexing.md)。
