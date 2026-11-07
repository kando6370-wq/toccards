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

同一意图尽量由一个明确页面承担。`/pokemon-card-scanner` 等原地址负责“选择扫描工具”；`/games/pokemon` 负责“浏览卡库”；具体 `/cards/{id}` 负责“精确印次与价格”。原官方卡表文章继续承担对应 checklist 需求，系列目录不宣称是完整官方卡表。旧 46 个地址和文章正文保留。

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
