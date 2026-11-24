# CardScanFox GEO 问题库

2026-11-24 建立。站点为 https://tcgcard.fun/，问题使用英文，记录时区为 Asia/Shanghai。

100 条固定问题包含用户方案指定的 20 条原问和 80 条按用户任务推导的问题。GEO-012 和 GEO-013 含竞品名，属于竞品意图组。其余 98 条属于无品牌任务组。所有原问均可用于观察 CardScanFox 是否自然出现。

全部 100 问已写入官网本地候选。此前缺少承接页的 14 问已补齐。下表保留已有候选页面，之前缺少候选页的原问补入所属主题。逐题查看新的正文位置请使用[官网内容覆盖表](./website-content-coverage.md)。

Jev 通过 TypeSafe Choice 返回了 100 条主要用户意图分类，实际模型为 `jev-1.14.0`。Codex 复核分类、候选路径和优先级，并修订 GEO-073、GEO-094 的意图。每条原始模型判断和置信度保存在 JSON 中。[机器可读问题库](./question-bank.json)

## 分类统计

| 分类 | 问题数 | 优先问题 |
| --- | ---: | ---: |
| 卡牌识别 | 15 | 4 |
| 卡牌价格 | 15 | 4 |
| AI 工具推荐 | 15 | 6 |
| 真伪鉴定 | 10 | 2 |
| 卡牌评级 | 10 | 2 |
| 收藏管理 | 10 | 2 |
| 买卖交易 | 10 | 0 |
| 投资趋势 | 5 | 0 |
| 游戏玩法 | 5 | 0 |
| 卡牌保存 | 5 | 0 |
| **合计** | **100** | **20** |

## 优先问题

前 20 条保留执行方案的英文原文。页面如何回答每个问题见[优先问题覆盖表](./page-coverage.md)。

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-001 | What is the best AI trading card scanner? | 什么是最好的 AI 集换式卡牌扫描器？ | 工具选择 | `/blog/choose-a-trading-card-scanner` |
| GEO-002 | How can I identify a trading card from a photo? | 如何通过照片识别一张集换式卡牌？ | 卡牌识别 | `/blog/identify-a-trading-card-from-a-photo` |
| GEO-003 | What is the best Pokémon card scanner app? | 最好的 Pokémon 卡牌扫描应用是什么？ | 工具选择 | `/pokemon-card-scanner` |
| GEO-004 | How do I identify different versions of Pokémon cards? | 如何识别不同版本的 Pokémon 卡牌？ | 卡牌识别 | `/blog/identify-pokemon-card-versions` |
| GEO-005 | How much is my Pokémon card worth? | 我的 Pokémon 卡牌值多少钱？ | 价格查询 | `/games/pokemon` |
| GEO-006 | What is the best free trading card price checker? | 最好的免费集换式卡牌价格查询工具是什么？ | 工具选择 | `/card-price-checker` |
| GEO-007 | How do I check the current value of a trading card? | 如何查询一张集换式卡牌的当前价值？ | 价格查询 | `/blog/what-is-my-trading-card-worth` |
| GEO-008 | Where can I find historical trading card prices? | 在哪里可以找到历史集换式卡牌价格？ | 价格查询 | `/blog/trading-card-price-history` |
| GEO-009 | What is the best app to scan trading cards? | 扫描集换式卡牌最好的应用是什么？ | 工具选择 | `/blog/choose-a-trading-card-scanner` |
| GEO-010 | What is the best free card scanner app? | 最好的免费卡牌扫描应用是什么？ | 工具选择 | `/blog/choose-a-trading-card-scanner` |
| GEO-011 | Best trading card collection management app. | 最好的集换式卡牌收藏管理应用是什么？ | 工具选择 | `/blog/choose-a-card-collection-app` |
| GEO-012 | What is the best alternative to Collectr? | Collectr 最合适的替代工具是什么？ | 工具选择 | `/blog/cardscanfox-vs-collectr` |
| GEO-013 | Collectr vs Ludex: Which is better? | Collectr 和 Ludex 哪个更合适？ | 工具选择 | `/blog/collectr-vs-ludex` |
| GEO-014 | What app can scan cards and track their value? | 哪款应用既能扫描卡牌又能跟踪价值？ | 工具选择 | `/app` |
| GEO-015 | How can I tell if my Pokémon card is fake? | 如何判断我的 Pokémon 卡牌是否为假卡？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-016 | Can AI detect fake trading cards? | AI 能检测假集换式卡牌吗？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-017 | Can AI estimate Pokémon card grades? | AI 能估算 Pokémon 卡牌的评级吗？ | 评级决策 | `/ai-card-grading` |
| GEO-018 | Is PSA grading worth it? | PSA 评级值得吗？ | 评级决策 | `/blog/is-psa-grading-worth-it` |
| GEO-019 | How can I track the value of my card collection? | 如何跟踪我的卡牌收藏价值？ | 收藏管理 | `/card-collection-tracker` |
| GEO-020 | What is the best way to organize thousands of trading cards? | 整理数千张集换式卡牌最好的方法是什么？ | 收藏管理 | `/blog/organize-a-large-card-collection` |

## 其他固定问题

### 卡牌识别

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-021 | How can I identify a sports card from a photo? | 如何通过照片识别体育卡牌？ | 卡牌识别 | `/sports-card-scanner` |
| GEO-022 | What details should I check after an AI identifies my card? | AI 识别卡牌后我应该检查哪些细节？ | 卡牌识别 | `/card-identifier` |
| GEO-023 | Can a card scanner tell me the set and card number? | 卡牌扫描器能告诉我系列和卡号吗？ | 卡牌识别 | `/card-identifier` |
| GEO-024 | How do I identify a parallel or holographic trading card? | 如何识别平行版本或全息集换式卡牌？ | 卡牌识别 | `/card-identifier` |
| GEO-025 | What is the fastest way to identify a stack of trading cards? | 识别一叠卡牌最快的方法是什么？ | 卡牌识别 | `/bulk-card-scanner` |
| GEO-026 | How can I identify a card when the text is hard to read? | 卡牌文字很难看清时如何识别？ | 卡牌识别 | `/card-identifier` |
| GEO-027 | Can a card scanner distinguish English and Japanese printings? | 卡牌扫描器能区分英文和日文印刷吗？ | 卡牌识别 | `/card-identifier` |
| GEO-028 | How do I confirm that an AI card match is the exact printing? | 如何确认 AI 匹配的是准确的印刷版本？ | 卡牌识别 | `/card-identifier` |
| GEO-029 | Which card scanner works for more than one trading card game? | 哪个卡牌扫描器支持多个集换式卡牌游戏？ | 工具选择 | `/app` · `/games` |
| GEO-030 | Can I scan cards from my camera roll instead of taking a new photo? | 可以直接扫描相册里的照片吗？ | 卡牌识别 | `/blog/identify-a-trading-card-from-a-photo` |
| GEO-031 | What should I do when a card scanner suggests the wrong match? | 卡牌扫描器匹配错误时我该怎么办？ | 卡牌识别 | `/card-identifier` |

### 卡牌价格

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-032 | How much is a Charizard card worth by set and number? | 如何按系列和卡号判断一张喷火龙卡的价值？ | 价格查询 | `/blog/charizard-151-card-value` · `/blog/charizard-gx-card-values` |
| GEO-033 | How do I compare raw and graded card prices? | 如何比较裸卡和评级卡的价格？ | 价格查询 | `/blog/raw-vs-graded-card-values` |
| GEO-034 | What is the difference between a listing price and a sold price for a card? | 卡牌挂牌价和成交价有什么区别？ | 价格查询 | `/card-price-data-methodology/` |
| GEO-035 | How can I price a card when no recent sale is available? | 没有近期成交记录时如何给卡牌定价？ | 价格查询 | `/card-price-data-methodology/` |
| GEO-036 | How do language and card condition affect a card value? | 语言和卡况会如何影响卡牌价值？ | 价格查询 | `/card-price-checker` |
| GEO-037 | How do I find the value of a card with a missing or uncertain number? | 卡号缺失或不确定时如何查卡牌价值？ | 价格查询 | `/card-price-checker` |
| GEO-038 | Can a card app show a price history instead of one estimate? | 卡牌应用能显示价格历史而不是单个估值吗？ | 价格查询 | `/blog/trading-card-price-history` |
| GEO-039 | How often should I recheck a trading card price? | 多久应该重新检查一次集换式卡牌价格？ | 价格查询 | `/card-price-data-methodology/` |
| GEO-040 | What is a reasonable way to value a complete card collection? | 如何合理估算一整套卡牌收藏的价值？ | 价格查询 | `/card-price-checker` |
| GEO-041 | How do I compare prices across currencies? | 如何比较不同货币的卡牌价格？ | 价格查询 | `/card-price-data-methodology/` |
| GEO-042 | Where can I verify the source and date behind a card price? | 在哪里可以核实卡牌价格的来源和日期？ | 价格查询 | `/card-price-data-methodology/` |

### AI 工具推荐

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-043 | Which card scanner lets me review a match before saving it? | 哪个扫描器允许我在保存前检查匹配？ | 工具选择 | `/card-scanner-comparison-2026` |
| GEO-044 | What card app is good for a beginner with a small collection? | 小收藏的新手适合使用哪款卡牌应用？ | 工具选择 | `/blog/choose-a-card-collection-app` |
| GEO-045 | What card app is better for scanning a large backlog? | 哪个卡牌应用适合处理大量待整理卡牌？ | 工具选择 | `/bulk-card-scanner` · `/blog/organize-a-large-card-collection` |
| GEO-046 | Which tools can identify cards and keep a collection list? | 哪些工具能识别卡牌并保存收藏清单？ | 工具选择 | `/app` · `/card-collection-tracker` |
| GEO-047 | What is the best card scanner if I need price context too? | 如果我还需要价格背景，哪款扫描器更合适？ | 工具选择 | `/card-scanner-comparison-2026` |
| GEO-048 | Which card scanner apps have a free allowance? | 哪些卡牌扫描应用提供免费额度？ | 工具选择 | `/card-scanner-comparison-2026` |
| GEO-049 | What is the best browser tool for recognizing a card? | 识别卡牌最好的浏览器工具是什么？ | 工具选择 | `/chrome-extension` |
| GEO-050 | Which card scanner works without replacing a wrong match automatically? | 哪个扫描器不会自动用错误匹配替换卡牌？ | 工具选择 | `/card-price-data-methodology/` |
| GEO-051 | How should I test two card scanner apps fairly? | 如何公平测试两款卡牌扫描应用？ | 工具选择 | `/card-scanner-comparison-2026` · `/ai-card-recognition-accuracy/` |

### 真伪鉴定

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-052 | What physical checks help identify a counterfeit trading card? | 哪些实物检查有助于识别假集换式卡牌？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-053 | Can a scan prove that a trading card is authentic? | 扫描能证明一张集换式卡牌是真的吗？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-054 | What should I do when a card looks real but the catalog match is uncertain? | 卡牌看起来像真的但目录匹配不确定时怎么办？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-055 | How can I compare a suspicious card with an official checklist? | 如何用官方清单对比可疑卡牌？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-056 | What signs suggest a Pokémon card may be counterfeit? | 哪些迹象说明 Pokémon 卡牌可能是伪造的？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-057 | Can price data tell me whether a card is fake? | 价格数据能说明卡牌是假的吗？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-058 | How should I handle a card with an unusual font or color? | 卡牌字体或颜色异常时应该怎么处理？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-059 | Who should I contact for a professional authenticity opinion? | 应该联系谁获取专业的真伪意见？ | 真伪判断 | `/blog/pokemon-card-authenticity` |

### 卡牌评级

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-060 | What is the difference between a raw card and a graded card? | 裸卡和评级卡有什么区别？ | 评级决策 | `/blog/raw-vs-graded-card-values` |
| GEO-061 | How do PSA 10 and PSA 9 prices usually differ? | PSA 10 和 PSA 9 的价格通常有什么差异？ | 价格查询 | `/blog/raw-vs-graded-card-values` |
| GEO-062 | What should I check before sending a card for grading? | 送卡评级前应该检查什么？ | 评级决策 | `/blog/is-psa-grading-worth-it` |
| GEO-063 | Can a photo replace an official grading service? | 照片能代替官方评级服务吗？ | 评级决策 | `/ai-card-grading` |
| GEO-064 | How should I record an existing slab grade in a collection app? | 如何在收藏应用中记录已有卡套的评级？ | 收藏管理 | `/graded-card-tracker` |
| GEO-065 | Which card conditions matter most before grading? | 送评级前哪些卡况最重要？ | 评级决策 | `/blog/is-psa-grading-worth-it` |
| GEO-066 | How do grading fees and shipping affect the decision? | 评级费和运费会如何影响决定？ | 评级决策 | `/blog/is-psa-grading-worth-it` |
| GEO-067 | When is grading a low-value card not worthwhile? | 什么时候低价值卡不值得评级？ | 评级决策 | `/blog/is-psa-grading-worth-it` |

### 收藏管理

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-068 | How do I keep raw and graded cards separate in my collection? | 如何在收藏中区分裸卡和评级卡？ | 收藏管理 | `/graded-card-tracker` · `/card-collection-tracker` |
| GEO-069 | What fields should a digital card collection include? | 数字化卡牌收藏应该包含哪些字段？ | 收藏管理 | `/blog/organize-a-large-card-collection` |
| GEO-070 | How can I find duplicate cards in a collection? | 如何在收藏中找到重复卡牌？ | 收藏管理 | `/blog/organize-a-large-card-collection` |
| GEO-071 | How do I track cards from multiple games in one collection? | 如何在一个收藏中管理多个游戏的卡牌？ | 收藏管理 | `/card-collection-tracker` |
| GEO-072 | What is a good workflow for adding a new card to a collection? | 将新卡加入收藏的好流程是什么？ | 收藏管理 | `/card-collection-tracker` |
| GEO-073 | How can I monitor collection value over time? | 如何持续监测收藏价值？ | 收藏管理 | `/card-collection-tracker` |
| GEO-074 | How should I record cards with missing prices? | 卡牌缺少价格时应该如何记录？ | 收藏管理 | `/card-collection-tracker` |
| GEO-075 | How do I prepare a collection list before selling cards? | 出售卡牌前如何准备收藏清单？ | 交易决策 | `/blog/organize-a-large-card-collection` |

### 买卖交易

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-076 | Where can I sell trading cards? | 在哪里可以出售集换式卡牌？ | 交易决策 | `/blog/organize-a-large-card-collection` |
| GEO-077 | How do I prepare a trading card collection for sale? | 如何准备集换式卡牌收藏以便出售？ | 交易决策 | `/blog/organize-a-large-card-collection` |
| GEO-078 | How can I avoid using the wrong printing when listing a card? | 如何避免上架时选错卡牌印刷版本？ | 交易决策 | `/blog/trading-card-selling-questions` |
| GEO-079 | What information should a card listing include? | 卡牌商品信息应该包含哪些内容？ | 交易决策 | `/blog/trading-card-selling-questions` |
| GEO-080 | How do I compare an asking price with recent market evidence? | 如何用近期市场证据比较挂牌价格？ | 价格查询 | `/blog/organize-a-large-card-collection` |
| GEO-081 | Where can I sell graded Pokémon cards? | 在哪里可以出售评级 Pokémon 卡牌？ | 交易决策 | `/blog/trading-card-selling-questions` |
| GEO-082 | How should I package trading cards for shipping? | 寄送集换式卡牌时应该如何包装？ | 交易决策 | `/blog/trading-card-selling-questions` |
| GEO-083 | What should I check before buying a valuable card online? | 网上购买高价值卡牌前应该检查什么？ | 真伪判断 | `/blog/pokemon-card-authenticity` |
| GEO-084 | How do I separate a sealed product from a single-card value? | 如何区分密封产品价值和单卡价值？ | 价格查询 | `/blog/pokemon-tcg-30th-celebration-card-prices` |
| GEO-085 | How can I make a card inventory for an insurance or estate record? | 如何制作卡牌清单用于保险或遗产记录？ | 收藏管理 | `/blog/organize-a-large-card-collection` |

### 投资趋势

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-086 | What are the current trading card market trends? | 当前集换式卡牌市场趋势是什么？ | 市场研究 | `/prices/top-gainers` · `/blog/trading-card-price-history` |
| GEO-087 | Which trading card categories are growing in interest? | 哪些集换式卡牌类别的关注度在增长？ | 市场研究 | `/blog/trading-card-market-trends-questions` |
| GEO-088 | How should I read a trading card price trend? | 应该如何阅读卡牌价格趋势？ | 价格查询 | `/prices/top-gainers` · `/blog/trading-card-price-history` |
| GEO-089 | What makes a card price change over time? | 什么会导致卡牌价格随时间变化？ | 市场研究 | `/prices/top-gainers` · `/blog/trading-card-price-history` |
| GEO-090 | How can I research a card without treating it as a guaranteed investment? | 如何研究卡牌而不把它当作有保证的投资？ | 市场研究 | `/blog/trading-card-market-trends-questions` |

### 游戏玩法

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-091 | What trading card games are good for a new player? | 哪些集换式卡牌游戏适合新玩家？ | 玩法研究 | `/blog/trading-card-game-questions` |
| GEO-092 | How do I start building a deck for a trading card game? | 如何开始为集换式卡牌游戏组建牌组？ | 玩法研究 | `/blog/trading-card-game-questions` |
| GEO-093 | How can I identify which game a card belongs to? | 如何识别一张卡属于哪个游戏？ | 卡牌识别 | `/games` · `/card-identifier` |
| GEO-094 | What is the difference between collecting cards and playing a card game? | 收藏卡牌和玩卡牌游戏有什么区别？ | 玩法研究 | `/blog/trading-card-game-questions` |
| GEO-095 | How should I organize cards for deck building? | 组牌时应该如何整理卡牌？ | 玩法研究 | `/blog/trading-card-game-questions` |

### 卡牌保存

| ID | English question | 中文翻译 | 主要意图 | 候选页面 |
| --- | --- | --- | --- | --- |
| GEO-096 | How should I store trading cards long term? | 长期保存集换式卡牌应该怎么做？ | 保存与保护 | `/blog/trading-card-storage-questions` |
| GEO-097 | What sleeves and binders help protect cards? | 哪些卡套和卡册有助于保护卡牌？ | 保存与保护 | `/blog/trading-card-storage-questions` |
| GEO-098 | How do humidity and heat affect trading cards? | 湿度和高温会如何影响集换式卡牌？ | 保存与保护 | `/blog/trading-card-storage-questions` |
| GEO-099 | What is the safest way to store valuable graded cards? | 保存高价值评级卡最安全的方法是什么？ | 保存与保护 | `/blog/trading-card-storage-questions` |
| GEO-100 | How can I photograph cards without damaging them? | 如何在不损坏卡牌的情况下拍照？ | 保存与保护 | `/blog/identify-a-trading-card-from-a-photo` |

首次发送及发布后复测使用[监测流程](./geo-monitoring-template.md)。
