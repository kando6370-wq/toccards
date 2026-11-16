# CardScanFox 页面搜索意图与页面任务

本次按用户指定的页面问题实施，不扩展为热词或搜索量研究。用户已确认：iOS 已可下载；Android 仍待上线；已上线的 Google 商店产品是 TCG Card Recognizer Chrome 扩展。网站使用英文任务标题、简介和界面，不翻译来源卡牌的专有名称。

## 页面归属原则

| 页面族 | 访客要解决的问题 | 核心动作 |
|---|---|---|
| 首页 | Card AI 是什么，能否帮助我识别和管理收藏？ | 了解识别、确认、价格和收藏流程，再选择下载平台 |
| 卡牌目录与单卡 | 我手中的卡对应哪个印次，参考价是多少？ | 按名称/系列/编号搜索，确认印次、语言、工艺与成色 |
| 游戏与系列目录 | 我要浏览的卡种或系列里有哪些已入库卡牌？ | 选择卡种/系列，分页浏览具体记录 |
| 价格查询 | 我这张卡应比较哪个价格？ | 搜索具体印次，核对币种、来源、日期和价格维度 |
| 7 天涨幅榜 | 哪些同口径裸卡价格在一周内涨幅最高？ | 比较百分比和前后金额，打开相同价格序列的详情 |
| 近期高价榜 | 近期已发布裸卡参考价最高的是哪些印次？ | 查看 Top 100，核对版本、来源与观测日期 |
| App 与原扫描工具页 | 这个工具是否支持我的卡和整理流程？ | 了解工具边界，进入 iOS/Android/Chrome 平台选择 |
| 下载页 | 从哪里下载合适的平台版本？ | iOS 去 App Store；Android 显示 Coming soon；扩展去 Chrome Web Store |
| 博客与分类 | 哪篇指南能解释版本、卡表、估值或工具差异？ | 找到对应主题，阅读保留原地址的文章 |
| 帮助与数据方法 | 我为什么看到这个价格或这个状态？ | 理解来源、日期、成色、历史缺口与使用边界 |
| Saved | 我保存的网页卡牌参考在哪里？ | 返回本浏览器书签；App 持仓不在网页修改 |
| 隐私/条款 | 数据如何处理、使用规则是什么？ | 阅读原有法律内容与联系渠道 |

同一意图尽量由一个明确页面承担。`/pokemon-card-scanner` 等原地址负责“选择扫描工具”；`/games/pokemon` 负责“浏览卡库”；具体 `/cards/{id}` 负责“精确印次与价格”。原官方卡表文章继续承担对应 checklist 需求，系列目录不宣称是完整官方卡表。原导入真源保留；2026-11-15 按用户要求将通用 Pokémon 查价博客并入中心页，见下文。

## 单卡与动态页面模板

单卡标题先放卡名、编号和系列标识，再说明 Price & Card Details。简介说明具体印次、已知语言/工艺/成色、真实价格日期，以及是否确有 30 天趋势。缺价明确写缺价；缺历史不添加趋势承诺。来源名称中出现非英文专有名时保留，不凭空生成英译卡名。

动态游戏和系列同样有实际名称与独立说明；筛选参数页不作为新的关键词落地页。分页参数维持原筛选，前后游标不混用。

## 81 个固定页面的主要任务

Title 与 Description 的逐页可执行真源为 [seo-pages.json](../../../../apps/cardscanfox-web/content/seo-pages.json)。下表逐个登记页面任务；新增 Markdown 文章沿用自身显式元数据。

| 原始地址或固定目录地址 | 主要搜索/使用任务 | 英文 Title |
|---|---|---|
| `/` | 产品认知与下载 | Trading Card Scanner & Collection Tracker \| CardScanFox |
| `/bulk-card-scanner` | 批量整理实体卡的 App 流程 | Bulk Card Scanner: Review a Stack of Cards \| CardScanFox |
| `/card-identifier` | 从照片识别卡牌，选择工具 | Trading Card Identifier App: Scan & Confirm \| CardScanFox |
| `/card-price-checker` | 查自己的单卡价值及操作方法 | Card Price Checker: What Is Your Card Worth? \| CardScanFox |
| `/card-collection-tracker` | 选择收藏及价值追踪工具 | Card Collection Tracker & Portfolio App \| CardScanFox |
| `/digital-card-binder` | 组织数字卡册与文件夹 | Digital Card Binder: Organize Your Cards \| CardScanFox |
| `/graded-card-tracker` | 管理已经评级的卡 | Graded Card Tracker: Keep Each Copy Separate \| CardScanFox |
| `/card-ai-vs-collx` | 商业比较，选择查价及收藏工具 | Card AI vs CollX: Price & Collection Workflows \| CardScanFox |
| `/card-ai-vs-ludex` | 商业比较，扫描后收藏还是售卖 | Card AI vs Ludex: Compare the Next Step \| CardScanFox |
| `/card-scanner-comparison-2026` | 比较扫描 App、额度和适用场景 | Trading Card Scanner Apps Compared: 2026 Guide \| CardScanFox |
| `/chrome-extension` | 浏览器图片识别工具 | TCG Card Recognizer for Chrome: Identify Card Images |
| `/blog/` | 浏览收藏知识和对比文章 | Trading Card Values, Card Lists & App Comparisons \| CardScanFox |
| `/blog/ascended-heroes-card-list` | 查系列卡表与具体印次 | Ascended Heroes Card List & Printing Guide \| CardScanFox |
| `/blog/chaos-rising-card-list` | 查系列卡表和参考价 | Chaos Rising Card List & Price References \| CardScanFox |
| `/blog/charizard-151-card-value` | 区分 151 喷火龙编号并查价值 | Charizard 151 Values: 006, 183 or 199? \| CardScanFox |
| `/blog/charizard-gx-card-values` | 区分 GX 版本、印章与促销卡 | Charizard GX Values: SV49, SM211 & More \| CardScanFox |
| `/blog/cufant-card-values` | 区分 Cufant 实体卡及价格 | Cufant Card Values by Set & Number \| CardScanFox |
| `/blog/ivysaur-card-values` | 区分 Ivysaur 151 与初代卡 | Ivysaur Card Values: 151 vs Base Set \| CardScanFox |
| `/blog/mega-charizard-x-ex-card-value` | 确认 Mega Charizard X ex 具体印次 | Mega Charizard X ex Value: Match the Number \| CardScanFox |
| `/blog/mew-gg10-card-value` | 定位 Mew GG10/GG70 印次 | Mew GG10 Value: Crown Zenith GG10/GG70 \| CardScanFox |
| `/blog/moonbreon-card-value` | 把昵称解析为实际单卡 | Moonbreon Value: Umbreon VMAX 215/203 \| CardScanFox |
| `/blog/phantasmal-flames-card-list` | 查系列卡表与价格参考 | Phantasmal Flames Card List & Prices \| CardScanFox |
| `/blog/pikachu-card-values` | 按版本查 Pikachu 价值 | Pikachu Card Values: Which Printing Is Yours? \| CardScanFox |
| `/blog/pokemon-card-values` | 学习按名称、系列、编号查值 | Pokémon Card Values by Name, Set & Number \| CardScanFox |
| `/blog/rayquaza-vmax-card-values` | 比较 Rayquaza VMAX 多印次 | Rayquaza VMAX Values: Compare the Printings \| CardScanFox |
| `/blog/pokemon-tcg-set-card-lists` | 查多个 Pokémon 系列官方卡表 | Pokémon TCG Set Card Lists & Lookup Guide \| CardScanFox |
| `/blog/dungeon-crawler-carl-trading-cards` | 辨别收藏卡发行与不同产品 | Dungeon Crawler Carl Cards: Release Guide \| CardScanFox |
| `/blog/minior-pokemon-card-guide` | 辨别 Minior 实体 TCG 版本 | Minior Pokémon Cards: Printings & Value Checks \| CardScanFox |
| `/blog/scanning-cards-from-watsontcg` | 购买后如何识别支持的单卡 | Scan Cards Bought at WatsonTCG \| CardScanFox |
| `/blog/pokemon-tcg-30th-celebration-card-prices` | 区分周年套卡、单卡和产品 | Pokémon 30th Celebration: Card Lists & Prices \| CardScanFox |
| `/blog/what-is-my-trading-card-worth` | 学习估值步骤 | What Is My Trading Card Worth? \| CardScanFox |
| `/blog/raw-vs-graded-card-values` | 理解裸卡与已评级卡价格差异 | Raw vs Graded Card Values: What Changes? \| CardScanFox |
| `/privacy` | 了解隐私和数据处理 | Card AI Privacy Policy \| CardScanFox |
| `/terms` | 了解网站使用条款 | Card AI Terms of Use \| CardScanFox |
| `/basketball-card-scanner` | 寻找特定卡种扫描与收藏工具 | Basketball Card Scanner: Identify Your Printing \| CardScanFox |
| `/digimon-card-scanner` | 寻找特定卡种扫描与收藏工具 | Digimon Card Scanner: Identify Your Printing \| CardScanFox |
| `/dragon-ball-super-card-scanner` | 寻找特定卡种扫描与收藏工具 | Dragon Ball Super Card Scanner: Check Coverage \| CardScanFox |
| `/flesh-and-blood-card-scanner` | 寻找特定卡种扫描与收藏工具 | Flesh and Blood Card Scanner: Identify Your Printing \| CardScanFox |
| `/football-card-scanner` | 寻找特定卡种扫描与收藏工具 | Football Card Scanner: Check Coverage \| CardScanFox |
| `/lorcana-card-scanner` | 寻找特定卡种扫描与收藏工具 | Lorcana Card Scanner: Identify Your Printing \| CardScanFox |
| `/mtg-card-scanner` | 寻找特定卡种扫描与收藏工具 | MTG Card Scanner: Identify Your Printing \| CardScanFox |
| `/one-piece-card-scanner` | 寻找特定卡种扫描与收藏工具 | One Piece Card Scanner: Identify Your Printing \| CardScanFox |
| `/pokemon-card-scanner` | 寻找特定卡种扫描与收藏工具 | Pokémon Card Scanner: Identify Your Printing \| CardScanFox |
| `/soccer-card-scanner` | 寻找特定卡种扫描与收藏工具 | Soccer Card Scanner: Identify Your Printing \| CardScanFox |
| `/star-wars-unlimited-card-scanner` | 寻找特定卡种扫描与收藏工具 | Star Wars Unlimited Card Scanner: Identify Your Printing \| CardScanFox |
| `/yugioh-card-scanner` | 寻找特定卡种扫描与收藏工具 | Yu-Gi-Oh! Card Scanner: Identify Your Printing \| CardScanFox |
| `/cards` | 按名称、系列或编号查找具体印次 | Trading Card Database: Find Cards & Prices \| CardScanFox |
| `/sets` | 按系列浏览已入库卡牌 | Trading Card Sets: Browse Cards & Prices \| CardScanFox |
| `/games` | 选择卡种后进入卡库 | Trading Card Games & Sports Card Database \| CardScanFox |
| `/prices` | 查具体卡牌当前价值 | Trading Card Prices & Value Lookup \| CardScanFox |
| `/prices/top-gainers` | 近七天同口径裸卡涨幅排行 | Top 100 Trading Card Price Gainers This Week \| CardScanFox |
| `/prices/most-valuable` | 近期已发布裸卡高价排行 | Top 100 Highest-Priced Trading Cards \| CardScanFox |
| `/app` | 了解扫描与收藏流程并选择工具 | Card AI: Scan, Price & Track Trading Cards \| CardScanFox |
| `/download` | 按平台下载或确认发布状态 | Download Card AI: iPhone, Android & Chrome \| CardScanFox |
| `/help` | 解决识别、价格与收藏使用疑问 | Card AI Help: Scanning, Prices & Collections \| CardScanFox |
| `/data-methodology` | 理解价格来源与比较边界 | How Card Prices Are Selected & Updated \| CardScanFox |
| `/saved` | 返回本浏览器收藏的卡牌参考 | Saved Trading Cards & Price References \| CardScanFox |
| `/blog/category/identity` | 辨别卡牌与查官方卡表 | Card Identification Guides & Set Lists \| CardScanFox |
| `/blog/category/values` | 理解卡价及版本、成色差异 | Trading Card Value Guides: Printing & Condition \| CardScanFox |
| `/blog/category/collecting` | 学习收藏组织与价值追踪 | Card Collecting Guides: Binders & Tracking \| CardScanFox |
| `/blog/category/comparisons` | 比较卡牌扫描和收藏工具 | Card Scanner App Comparisons & Guides \| CardScanFox |
| `/games/pokemon` | 浏览 Pokémon 的卡库与价格 | Pokémon Card Database: Sets & Prices \| CardScanFox |
| `/games/one-piece` | 浏览 One Piece 的卡库与价格 | One Piece Card Database: Sets & Prices \| CardScanFox |
| `/games/yugioh` | 浏览 Yu-Gi-Oh! 的卡库与价格 | Yu-Gi-Oh! Card Database: Sets & Prices \| CardScanFox |
| `/games/lorcana` | 浏览 Lorcana 的卡库与价格 | Lorcana Card Database: Sets & Prices \| CardScanFox |
| `/games/basketball` | 浏览 Basketball 的卡库与价格 | Basketball Card Database: Sets & Prices \| CardScanFox |
| `/games/mtg` | 浏览 Magic: The Gathering 的卡库与价格 | Magic: The Gathering Card Database: Sets & Prices \| CardScanFox |
| `/sets/set-b5d02f417546` | 浏览指定系列已入库印次 | ME: 30th Celebration Classic Collection: Browse Cards & Prices \| CardScanFox |
| `/sets/set-d3a57ebd2a6b` | 浏览指定系列已入库印次 | M6a: MEGA Expansion 30th Celebration (JP): Browse Cards & Prices \| CardScanFox |
| `/sets/set-9eeb37c90bf2` | 浏览指定系列已入库印次 | Nine Colours Gathering (Friend): Browse Cards & Prices \| CardScanFox |
| `/sets/set-e99f365c1ca2` | 浏览指定系列已入库印次 | One Piece Promotion Cards: Browse Cards & Prices \| CardScanFox |
| `/sets/set-f55a7ecc0bed` | 浏览指定系列已入库印次 | Rarity Collection 5: Browse Cards & Prices \| CardScanFox |
| `/sets/set-a9ce944051d8` | 浏览指定系列已入库印次 | Disney Lorcana Promo Cards: Browse Cards & Prices \| CardScanFox |
| `/sets/set-f9989f3c67f9` | 浏览指定系列已入库印次 | Golden Energy: Browse Cards & Prices \| CardScanFox |
| `/sets/set-6c5d26c52fca` | 浏览指定系列已入库印次 | Winterspell: Browse Cards & Prices \| CardScanFox |
| `/sets/set-6a45990b1a66` | 浏览指定系列已入库印次 | Shadow of Glory: Browse Cards & Prices \| CardScanFox |
| `/sets/set-d40f9aa20d26` | 浏览指定系列已入库印次 | Shining Synergy (Summon): Browse Cards & Prices \| CardScanFox |
| `/sets/set-cdfc299a9ad0` | 浏览指定系列已入库印次 | ME: 30th Celebration: Browse Cards & Prices \| CardScanFox |
| `/sets/set-d87314ba68c4` | 浏览指定系列已入库印次 | 2024 Panini Prizm: Browse Cards & Prices \| CardScanFox |
| `/sets/set-03121efbc4af` | 浏览指定系列已入库印次 | Oversize Cards: Browse Cards & Prices \| CardScanFox |
| `/sets/set-90fac8c03fb3` | 浏览指定系列已入库印次 | smL: Sun & Moon Family Pokemon Card Game (JP): Browse Cards & Prices \| CardScanFox |

## 证据与边界

本轮向 Jev 提交了 55 个公开页面/页面族的意图分类问题，服务返回 HTTP 451（区域不可用），没有采用任何模型分类结果。以上归属由 Codex 根据现有功能、正文、路由和用户指定问题复核；不把这些分类当作 Google 搜索量、排名、点击率或收录证据。

改动前 `/prices` 的服务器原始 HTML Title 为英文 `Dated Trading Card Price References | CardScanFox`；截图中的中文可能来自浏览器或扩展翻译。本次将其改为明确的英文价格查询 Title，并扩充对用户任务有用的简介。检验源 HTML 与浏览器实际 DOM，不能只依据插件的本地展示。

预览继续 noindex，不因接入真实数据或新增榜单开放收录。正式域名切换、索引开启与搜索引擎通知分别处理。

## 2026-11-08 已授权卡牌词实施

新增 `/blog/mega-rayquaza-ex-card-values` 承担 Mega Rayquaza 卡名消歧、具体编号和价格查找；Delta Reign 的 cards/chase cards 同属原 `/blog/delta-reign-pokemon`；30th UPC 各种简称由原 UPC 指南承接。对应 Title、Description 与正文已更新，不增加同义词薄页。见[本轮词与页面映射](cardscanfox-card-term-content-20261108.md)。


## 2026-11-15 产品答案与引用依据

本次继续改善已有工具页，不新增同义词落地页。免费成功扫描额度、图片队列容量和公开平台状态分开说明：当前服务端 `FREE_SCAN_LIMIT=10`，按 owner 累计 consumed，不按日/月重置；识别失败或无匹配释放预留。Premium 的价格与当前购买条件以 App 内实际报价为准。

`content/answer-faqs.json` 的 `/help` 问答被首页、App、下载和帮助页复用，正文和 FAQPage 使用同一份文本；识别错配时先核对印次或文字检索，不把另一印次的价格当替代。帮助页原有账号删除、平台分流和价格日期说明继续保留。数据方法、两种价格榜、账号删除、目录、限流故障边界和现有分阶段索引策略不随这次文案调整。

已核实覆盖与未核实覆盖分开：Football、Dragon Ball Super、Naruto 的旧正文不能因通用卡种或语言字段而承诺完整支持；用户先核对具体目录记录。截图金额继续标为示例，未导入的成交列表不作为 App 功能描述；持仓估值只汇总已确认持仓和可用价格，缺价不等于零或实时可售金额。卡表、历史价格样本、原 URL/H1、外链与法律正文保留。

产品功能说明、数据来源和真实商店入口可以支持有条件的事实引用或候选推荐。准确率、识别速度、竞品优劣和真实成交结果需要同条件实测；本次不生成或声称这些结果。自然发现、页面引用、产品入选、访问和安装分别观察。指定网址可读不能证明无品牌问题下会被发现或推荐。

抓取诊断的范围：同一客户端网络下，默认 Python urllib 曾收到 Cloudflare 403/error 1010；使用如实描述用途的 User-Agent 后，首页与 robots 返回 200。该结果不能证明真实 OAI-SearchBot 的 IP 抓取成功或失败。目标账户日志未取得，不据此关闭 WAF/BIC。生产发布、真实设备识别和发布后的 AI 入选观察仍需分别取得证据。

本地检查使用 Node 22.23.4、pnpm 11.28.10：构建 124 条静态路由，46 个既有网址保留；官网 79 项测试、类型检查、dry-run 和 Code Review 通过。新增 3 项回归在 7fbe5ac 隔离基线中失败，在修订后通过。检查 27 个相关页面及 64 个不同站内目标；其中 `/cards/101520` 不在本地样本，单独回读正式地址为 200，其余目标由本地页面验证。下载、帮助和 App 页在 1280、390、320px 下没有页面横向溢出，新增问答可点击和键盘展开。索引配置、allowlist、sitemap、目录/榜单/账号删除实现没有差异；未部署或提交索引通知。


### 本次合并与正式回读

用户随后明确授权合并 `main` 并推送。代码提交 `2682ed953213c07ba6fbdb6a5e66a7dbfb215a9b` 已快进合入并推送 `origin/main`；合并后的 79 项官网测试通过。对应的 Cloudflare 官网／只读服务自动构建和 GitHub App compatibility 检查均成功。未手工更改生产绑定、数据库或索引配置。

正式 `/release-manifest.json` 回读的 `sourceCommit` 为上述代码提交，`releaseId` 为 `b3afc352577ba2b8f86febd40c2da433cb0a4d4a446072a2a9e1f74ef9178096`，保留 124 条构建路由。25 个实际内容变化页面逐一返回 200，canonical 与可索引状态正确；21 个非首页旧页的正文来源哈希与批准产物一致，首页、App、下载及 Help 均读到新增免费额度答案。

按项目 `.indexnow.json` 和全局 `indexnow-submit` skill，正式版本回读通过后仅通知这 25 个公开地址：22 个旧页（含首页）及 `/app`、`/download`、`/help`。两批分别为 20 和 5 个地址，接口均返回 HTTP 200，本次 `remainingRequested=0`。这表示通知已受理，不表示已收录、获得 AI 引用或带来安装。没有通知内容未变的数据方法、价格目录、单卡、系列、榜单、后台/API、预览及暂缓索引页面。

本段是代码提交 `2682ed95` 的正式验收补证；后续仅文档提交不作为新功能发布证据。

## 2026-11-15 答案优先修订

本轮以用户给定五项要求为实施范围，不新增热词页面，不提交 IndexNow 或请求编入索引。

| 用户需求 | 唯一页面归属 | 本地改动 |
| --- | --- | --- |
| DCC Series 1 卡表、pack、价格、购买及编号 | `/blog/dungeon-crawler-carl-trading-cards` | 发行方 #001–100 完整表；区分 Playmates/Borant 与 Renegade；来源与观察日期 |
| 周年 UPC Day/Night 内容与发售 | `/blog/pokemon-upc-30th-anniversary` | 内容物、日夜主题区别、2026-11-06 发售及商店带日期挂牌价 |
| 周年单卡清单与价格 | `/blog/pokemon-tcg-30th-celebration-card-prices` | 158 编号卡、3 RGB Mew、30 Classic；每卡原价格日期 |
| Pokémon 泛查卡及价格 | `/games/pokemon` | 迁入旧博客角色指南、编号读法、日期说明；旧博客及其 .html 301，保留 query |
| Pokémon 拍照工具 | `/pokemon-card-scanner` | 保留独立工具意图 |
| 具体系列与具体印次 | 现有卡表、`/sets/{id}`、`/cards/{id}`、角色指南 | 继续各自回答具体问题，不统一重定向 |

公开页品牌、按钮和组织署名统一为 CardScanFox；下载页解释真实商店中的 Card AI 名称。法律正文、账号删除应用身份、实际商店链接与产品能力限制保持有效。

Git 对照范围为 2026-11-03 至本轮基线 `97e2b0bc`。`3ab3d1c7`/`180a2c02` 主要完成迁移和官网切换；`0f340a26` 改过 7 篇旧博客、5 个工具页和首页；`2682ed95` 修改22个功能/比较页面，没有修改博客正文。20 篇旧博客中13篇在本轮之前的正文与导入基线一致；三个完整卡表仍有295/122/130张卡。故没有执行整站 Git revert：恢复三篇卡表的直接首段，重写 DCC、周年卡价和 Watson 操作答案，保留额度、平台及目录范围的事实纠正。

基线有32篇博客正文，另有1个博客列表和4个分类页；合并泛查价博客后为31篇正文。这不等于37篇文章。后续按核心需求维护既有页面，外链接受、真实流量、抓取和排名分别衡量。

Jev 1.14.0 对54个现有文章/工具/比较页做搜索意图预分类。Codex 复核所有权，并纠正 Pokémon 泛查价博客归属及 Yu-Gi-Oh 工具分类。最终路由、重定向与数据转换使用确定性代码，不依赖模型。测试在内容和文档完成后运行；正式发布、线上301与数周搜索表现需要独立验证。

本轮本地验收：官网测试85项通过；官网 type-check、123路由构建、Worker dry-run 与 git diff --check 通过；6个重点页面在1440/390/320像素下共18次浏览器检查，无页面横向溢出；独立Code Review无待修复项。运行环境为Node 22.23.1、pnpm 11.28.10；仓库声明Node ^22.23.4，因此未声称已在该最低补丁版本验收。未运行App/Admin/API/只读数据服务测试，这些实现未修改。未执行Git commit/push、dev/prod部署、线上新版验收、GSC索引请求或IndexNow。

## 核心扫描词第一批（2026-11-15）

本轮用户确认先做网页扫描与SEO，AI评级单列后续需求。首页承接`card scanner`并引导两个真实网页工具；`/pokemon-card-scanner`承接Pokemon照片识别；新`/sports-card-scanner`承接体育卡照片识别；`/card-price-checker`保留查价解释和入口；`/games/pokemon`继续使用已发布真实数据。周年卡价页Title/H1按`Pokémon 30th Anniversary Cards: Full Card List & Prices`调整，191张清单和原价格日期保留。

15个扫描页是不同卡种/运动的英文页面，不能写成多语种矩阵；18/13只是本次读取的CollX/Collectr sitemap loc数，不是整个产品页数。153是本站已收紧的sitemap发现批次，不是数据库记录上限。未按这些数字执行新一轮删页，未把800字作为保留门槛。现有AI Grade未实现，不建立虚假可用工具。

网页工具与iPhone App的免费扫描额度、保存记录分开。识别网关只读，独立服务绑定和防刷为本地配置候选；没有部署或变更远程资源。未声明网页扫描已在线可用，正式发布后还需真实图片匹配、目录预算和目标平台浏览器补验。首次约26 MiB资源加载不能用原HTML响应时间代替。

本批验证：官网109项测试通过；root type-check首次并行流程在Wrangler类型生成后等待，停止该流程后以`WRANGLER_SEND_METRICS=false pnpm exec turbo type-check --concurrency=1`完成9个任务；官网与只读服务另行直接`tsc --noEmit`通过。依赖方向、124路由构建、preview及production配置dry-run通过。独立审查已关闭首次模型加载取消和Sports分页前筛选/离线动态slug错误，最终无待修复P1/P2。

Ego在本地使用真实卡图实际运行模型，得到512维有限向量；模型仅主动识别时下载，原图未发送至识别网关。缺绑定场景明确503。取消/换图、同页查卡、捕获公开目录响应的候选显示已验证；该候选显示测试模拟匹配响应，不是生产识别准确率或完整线上端到端验收。物理手机相机、Safari真机、生产绑定和实际扫描流量下的目录预算未验收。本轮未commit/push、未部署、未提交索引或外链。

最终页面检查：4个重点页面在1440/390/320像素下12组无页面横向溢出、各1个H1、初始模型下载均0。首页双CTA小屏换行和扫描按钮禁用视觉已补齐，独立UI复审原P2已关闭，结论ship。HTML计划在桌面/手机均非空且无页面溢出，9项工作包筛选器可用。机械样式检查因解析库缺失降级；隐藏预览图的无src告警经截图核实不构成可见破图，不宣称完整机械检测通过。

## 第二步与第三步：合并与内容补齐（2026-11-16）

用户进一步明确授权执行第二、三步；这是第一批之后的新本地范围，不回写前述历史验收。`/card-identifier` 先升级为通用 TCG 真实工具，再承接4个有已记录曝光的卡种页：Digimon、Lorcana、Dragon Ball Super、Flesh and Blood分别301到同页相应章节，正文迁入编号/artwork/foil/promo/edition诊断。旧源保留，不输出旧页重复正文；干净URL与`.html`均单跳，query在fragment之前。站内链接改直达，四源路径退出sitemap及许可。此前140个正曝光URL中的一般Pokemon查价博客已迁至中心页，本轮再迁4页；这是经授权的URL合并，不是把有曝光页误删。

MTG、One Piece、Basketball、Football分别保留独立回答，补足约900词的实用核对步骤，保留原路径/H1。不同游戏的特殊印次和不同运动的编号/序号不能互相替代；Football与Dragon Ball Super的覆盖未确认状态不因搜索量建议而改为已支持。

第三步沿用已有191卡表、逐卡价格日期、UPC两页分工和真实Pokemon数据库读取。本轮在周年价页直接补single/booster/UPC购买选择，链接官方where-to-buy；不刷新旧价格/库存观察日。Pokemon中心页加5项实际导航，不编价格、不将缺价视为零。没有新增周年页。

卡页审计使用原始GSC窗口2026-10-12至2026-11-11的140个URL布尔归属、既有种子与暂停清单，未把私有原始指标发送Jev。当前142个许可卡页=82个正曝光+60个仅内容引用。65个发现卡页=5个正曝光+60个引用；另外77个正曝光卡页原本不在地图。1047个暂停发现卡页仍无索引资格。本轮保持卡级规则，60个引用种子的独立需求仍待数据核实，不自动关闭，也不宣称有搜索量。

Jev对9个公开页面做意图预分类。Codex核对曝光、能力、迁移内容和目标页后决定合并；精确URL集合、query/fragment组合、过滤和分页由常规代码完成。无需新App API、Schema、迁移或远程绑定；未推送、部署、做外链或提交索引。完成实现及文档后再统一运行影响面验证。

第二/三步本地验收：119项官网测试、官网type-check、依赖方向、120路由构建和production dry-run通过；独立Code Review无P1/P2。16个GET/HEAD/clean/html HTTP检查确认单跳301与query/fragment次序，4个浏览器迁移均到正确章节。8个受影响页面在1440/390/320宽度共24组无横向溢出，各1个H1，初始模型请求均0。通用TCG实际模型输出512维有限向量，识别参数0且不传game；非Pokemon候选显示/体育候选排除使用捕获的公开MTG数据作受控UI测试，不能当作生产准确率。文章修订日期16日，逐卡价格观察日期保持原值。

候选sitemap为84个静态URL+65个卡URL，共149；相对第一批候选减少4个合并源。卡级许可142不变，1047暂停卡无重开。历史140正曝光URL为135直接保留+5个已授权迁移，无不明移除。生产只抽查2个暂停卡仍200/noindex和1个Mew卡仍index；没有推送、部署或IndexNow，不宣称新合并已在线生效。

最终UI复审：返回扫描器锚点曾被sticky页头遮挡，已复现并对目标补齐现有150px滚动偏移。相同Return链接在320/390/1440宽度回归通过，标题均在页头下方；UI复审原P2已关闭（resolved/ship）。该小修只验证受影响锚点/布局并重做构建及dry-run，未重复未影响的App/Admin/API测试。实施HTML的21个工作包已完成本地验收；线上发布边界不变。

## 三轮官网优化的Git交付授权（2026-11-16）

用户明确要求将本会话官网改动合并主分支并推送。范围为前述答案恢复、品牌、网页扫描、四卡种合并、保留页与周年/查价入口；包含模型及许可证、生成内容与必要本地HTTP支持，不包含其他工作区或App/Admin/共享业务API/Flutter改动。main与分支共同基线为97e2b0bc；合并前重新拉取远端、核对范围并运行最终受影响检查，采用快进合并，保留其他工作区。

Git推送、Cloudflare自动构建和正式manifest/sourceCommit生效分别核验。当前正式代码回读为2682ed95，而main的97e2b0bc是后续文档提交；不能把两者混为上线状态。最终发布使用正式toccards-website，保留SITE_DATA并按候选配置新增独立向量/限频绑定；不发布旧marketing-web、业务API或移动端。本轮继续沿用最初不请求编入索引的限制，不提交IndexNow。后续成功/失败以实际平台和正式版本回读补证，不提前宣称上线。

合并前补验使用项目规定的Node 22.23.4（本地归档与Node官方SHASUMS256一致）和pnpm 11.28.10。当前待提交树重新构建120路由、119项官网测试、串行root type-check流程9任务及依赖方向均通过。独立交付审查确认105个文件均属已授权范围，模型/runtime/license未被ignore，最大文件14.24 MB，无私有原始GSC、凭据或无关应用改动。

## main交付与正式回读（2026-11-16）

功能提交`3099fbf92f0ab1a4a99ebf9d40937137c88e3c9a`已快进合并到main并推送，远端ref独立回读一致。本记录是功能提交之后的文档补证，不能把文档SHA当作官网sourceCommit。合并后的干净main使用Node22.23.4/pnpm11.28.10完成冻结安装、119项官网测试、39项目录服务测试、120路由构建、production dry-run；此前同一源码root type-check流程9任务和依赖方向通过。

Cloudflare Git自动构建/发布成功：官网Build `b277dac0-552a-40ac-802f-0ba87972b092`，CI报告Version `d8873425-d5d3-499c-af1e-2dd64b9a098b`；只读目录Build `97589ed3-73db-4af6-83c1-f82d5c8efb9f`，CI报告Version `4ca32ab5-4312-4a3a-ba1c-a2439f95ed8e`。同一功能SHA的Admin Pages与App compatibility均success。未手动发布其他目标；Cloudflare活动版本API因本机无可用token未独立读取，不宣称读取了100%流量配置。

正式release-manifest回读sourceCommit为同一3099fbf9，releaseId为`f01959c7bf5b3f0c3fadce258376a94830442e631a76fbea507d36e468c1434e`，120 routes/196 files，与批准主分支构建清单和指纹一致。正式HTTP检查125/129通过：73/77固定owner通过，DCC100唯一行、周年191价格日期行、三扫描入口、18条301、149条地图（84静态+65卡）、两暂停卡200/noindex与Mew index、JS/CSS原始SHA通过。模型/WASM HEAD返回200但size及ONNX MIME缺失未算独立通过；浏览器后续实际加载模型及WASM成功。

正式浏览器以公开卡图完成三种真实链路：通用TCG686490（0不带game）、Pokemon714372（0+pokemon）、Sports t8546993（1）均返回200 matched与5候选，输入卡均为第一候选，价格与观察日来自正式公开目录。只做三个烟测，不推算识别准确率；本轮没有使用模拟匹配响应，没有写App账户/额度/扫描记录。物理相机、Safari真机与负载/长时稳定性仍未验收。

4个中文系列地址目前404/noindex，未计为通过：`/sets/set-9eeb37c90bf2`、`/sets/set-f9989f3c67f9`、`/sets/set-6a45990b1a66`、`/sets/set-d40f9aa20d26`。resolver源码及其匹配用card字段与本轮前完全相同；历史正曝光集合不含这4个路径，但无旧线上HTTP记录，因此出现时间和发布因果未定。当前公开games列表不含Pokemon Chinese，与分类未启用的情况一致，仍不能证明具体set行是否存在。没有为此猜测性改数据、扩权限或掩盖404，需后续核对数据启用/映射。

全部原始回读、构建与浏览器证据位于任务外部artifact的delivery目录，不把私有原始GSC或日志加入docs。继续遵守本会话的索引请求限制，未提交GSC请求或IndexNow。

## 网页 AI 预评级与价格查询（2026-11-16 后续增量）

用户已更正产品事实：产品确有 AI 预评级。此前“整个产品不预测评级”的结论不再适用；身份识别、预评级和已有认证等级仍是三条不同流程。用户进一步选择本批新建轻量网页后端，不依赖尚未定位的 App 评级服务。本增量在 `codex/cardscanfox-pregrading` 实现，基线为 `main@19adda49`；前述 3099 发布记录保持历史状态，不用本地代码替代生产验收。

| 页面 | 本次唯一任务 | 用户动作 |
|---|---|---|
| `/ai-card-grading` | 免费照片预评级、人工留白比例计算及送评成本比较 | 同页上传正反面、查看可见状况与宽泛区间，再输入真实价格和费用比较 |
| `/card-price-checker` | 查询已发布的精确印次价格 | 同页 GET 搜索，核对版本、RAW 条件、来源和日期，打开同一价格系列 |
| `/pokemon-card-scanner` 等身份识别页 | 匹配目录记录 | 保留原向量识别，明确链接到单独预评级流程 |
| `/graded-card-tracker` | 记录已有评级 | 使用 slab 上的真实公司与分数，不把 AI 区间当成认证等级 |

### 预评级数据契约

新接口 `POST /site-api/v1/pregrade` 属于官网 Worker。请求仅接受 `front`、`back`，每面为 `{dataUrl,width,height}`。浏览器将原 JPEG/PNG/WebP 转为无原始 EXIF 的 JPEG，最长边不超过 1600，最短边至少 640，每张上传最多 1.5 MiB。后端再次校验实际 JPEG/PNG 文件头、尺寸、base64、整包 4,200,000 字节和两图重复；不接收远程 URL。

视觉服务为 `WEB_PREGRADING_AI` Workers AI binding，固定模型 `@cf/meta/llama-4-scout-17b-16e-instruct`。一次多图请求，无自动重试，模型等待最多 45 秒；上传读取 8 秒、限频调用各有短超时。个人 `WEB_PREGRADING_RATE_LIMITER` 为每 IP 每 60 秒 2 次；聚合 `WEB_PREGRADING_GLOBAL_LIMITER` 为每位置每 60 秒 10 次。Cloudflare 原生限频按位置执行，不能作为全球每日硬费用上限。预览和正式配置使用独立 namespace。新增 AI binding 不修改 SITE_DATA、向量服务、App 接口或业务数据；缺少任一新绑定、可信来源 IP 或服务时，只关闭预评级并明确失败。回滚到前一官网产物即可停用该入口；不涉及数据回滚或迁移。

响应保留两面的 quality、issues 和 centering/corners/edges/surface/print 五项可见观察；每项用 `none_visible/minor/moderate/major/unassessable`。只有双面合理、清晰且五项均可观察，才给宽泛范围。代码按最严重项映射为无可见问题 8–10、轻微 6–9、中等 3–7、严重 1–4。这是明确的产品启发式，未与 PSA/BGS/CGC 实物等级校准，不是模型置信度，更不是认证或交易担保。照片不足、反光、遮挡、非卡、错面等返回 `needs_better_photos` 和 `range:null`。数值留白比只由用户输入边距后用常规代码计算；视觉模型不得输出编造比例。

图片与结果只在当前浏览器页面及服务请求内存使用，不写账号、PostgreSQL、R2 或公开结果网址，不记录图片或完整模型输入。接口始终 `no-store` 和 `noindex`；公开工具主页面提供 SSR 内容，随机结果不生成 URL。发送前需勾选照片处理说明；隐私页补充 Cloudflare AI 的具体用途。原 App 的图片与账号流程不变。Cloudflare 计费、模型实际可用性与实测推理属于运行验收项；配置存在不等于已上线。

费用比较只使用用户输入的 RAW、8/9/10 成交参考、送评、往返邮费保险和出售费率；同一费率同时扣除 RAW 和 graded 两侧。代码给三个分数各自净差及盈亏平衡售价，不从 AI 区间推导成交价。官方标准/费用核对于 2026-11-16：PSA Gem Mint 10 的居中描述为正面约 55/45、背面约 75/25，它只是综合标准的一部分；PSA Value 公开例为 $39.99、最高投保值 $500、估计 90–100 工作日；CGC Economy 公开例为 $20、最高值 $1,000、估计 90 工作日。页面保留官方来源链接、观察日及邮费/保险/税和其他适用要求，不把一个 tier 当作统一报价。

### 真实目录示例与价格查询

按用户指示复用现有卡牌详情接口，核对了 Charizard 714372、Pikachu 716991、Gengar ex 719554。示例仅展示真实目录图与 RAW Near Mint 价格，观察日期均为 2026-11-15，实际核对为 11-16；真源为 `content/pregrading-catalog-examples.json`。这些不是同一实物的正反面照片或 AI 评级样卡。接口没有提供可用背面，不补图；也没有同一公司、同语言/工艺的完整 8/9/10 价格组，不拼接 GENERIC、Normal、Holofoil 等不同维度。专业评级与 AI 对照结果仍需对应实物图片及可靠等级，目录示例不作准确率证据。

价格页初始不读取全目录。只有非空名称/编号或具体 set 才用既有 published page-data 查询，每页 24 条；保留游戏、套卡、语言、工艺、价格、排序和游标。全目录不支持的昂贵排序仍要求具体 set。价格为 RAW 发布参考，不自动当成送评后价值。缺价保留 null，真实零价保留零，未知条件不改成 Near Mint；错误 400/429/503 和非发布数据不回退成评审快照。原指南与 FAQ 保留在下方折叠区，查询参数页 noindex、canonical 回主入口。

本轮复核四个旧卡种 clean/html 地址的 GET/HEAD，16/16 已是 301，跟随后 4/4 目标 200；验收表的“仍为 200”是重定向跟随后状态，不是原响应。无需重写现有正确合并。卡页 142 许可、1047 暂停规则不变；不批量 noindex，不新增周年页。

Jev 1.14.0 已对 29 条公开能力文案做“全局否认/身份匹配边界/其他”分类。Codex 复核上下文后只修改与已确认预评级能力冲突的句子，并保留认证和市场价格边界；低置信度的“匹配不等于评级”没有按全局否认处理。路由、尺寸、价格查询、范围映射、计算、重试与限频均由代码完成。未将原始 GSC、用户照片或凭据发送 Jev。

验证顺序：所有功能和本节文档完成后，再运行受影响官网测试、类型、构建、production dry-run、浏览器操作和独立审查。测试替身通过不等于真实模型通过；本地完成、Git 提交/推送、平台发布、正式 HTTP、真实 AI 推理和搜索表现分别记录。本增量尚未执行 Git push、远程部署、索引通知或外链操作。

价格页错误恢复补充：独立 UI 审查发现上游 429 时通用错误页会丢失搜索表单；已在修改前用 `q=Charizard&game=pokemon` 和 429/Retry-After 60 复现，原输出 503 且 form/query 均缺失。修复仅在 checker 分支保留原表单、全部筛选和同一查询重试；400 保持 400，繁忙及不可用保持 503，429 的安全 Retry-After 透传。失败不给结果、不调用快照查询、保持 noindex。待完成此补充后重跑对应影响面验证与独立复审。

本地最终验证：Node 22.23.4（安装归档与 Node 官方 SHA256 一致）、pnpm 11.28.10。155 项官网测试全部通过；根串行 type-check 9 项成功（含缓存），错误恢复返工后另跑官网 type-check 通过；依赖方向和 diff 检查通过。121 路由构建、199 文件清单、production dry-run 通过。相对正式 3099 清单只新增 AI 页 HTML、该工具 JS/CSS 三个文件，无删除；内容/运行代码更新另由指纹覆盖。独立 Code Review 及价格页 UI 复审的两项 P2 已关闭，无待修复 P1/P2。

Ego 浏览器实际读取线上 published 目录，Charizard 查询同页返回 24 条，保留具体印次、来源、日期和 series 链接。两个工具页在 1440/390/320 宽度共 6 组均 1 个 H1、无页面横向溢出；价格表在手机内部横向滚动，页面 320/320、表格可视 292/内容 560。费用表用明确测试输入核对 grade8/9/10 净差与 $166.67 盈亏平衡；人工边距 4/6 与 5/5 得 40/60 与 50/50。双图真实文件规范化、发送同意、缺 binding 的明确失败及清空状态已操作。该双图来自公开目录，仅验证上传界面，不作为真实物理配对或 AI 评分证据。价格恢复使用受控 429 上游，按修复前同一输入回归得到 503、Retry-After 60、原 query/game 和表单均保留、noindex，并在 390px 截图复核。

未验证：目标 Cloudflare 账号的真实 Workers AI 多图/JSON Mode、响应时间、照片预评级效果与官方等级校准、物理相机及 Safari 真机。当前可见 Cloudflare 会话只提供另一个账号，目标配置账号不可访问；没有使用其他账号代替。上述测试中的 AI 响应为接口替身，不能记作真实模型通过；浏览器缺 binding 明确失败也不是模型成功。本地候选未推送、未部署，正式 sourceCommit 仍为 3099fbf9；未提交 GSC、IndexNow 或外链。公开页面可在发布授权后沿用既有 Git/Cloudflare 流程上线，再独立回读并做真实 AI 请求验收。
