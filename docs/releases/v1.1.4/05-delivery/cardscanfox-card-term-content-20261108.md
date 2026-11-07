# 周上升卡牌词内容实施

用户明确要求将已观察的四个关键词落到产品页面，合并 main 并推送。本轮只实施已采集的有效记录，不继续故障后的 Trends 扫描，也不声称完成六类卡牌研究。

## 归属与交付

| 词 | 美国网页搜索/过去一周原始读数 | 内容归属 | 动作 |
|---|---|---|---|
| mega rayquaza ex | +70%，相关指数 1 | /blog/mega-rayquaza-ex-card-values | 新建印次与价格查询指南，链接四个真实编号单卡 |
| delta reign chase cards | +400%，相关指数 6 | /blog/delta-reign-pokemon | 增加 chase 含义、官方已公布卡牌、版本比较与覆盖说明 |
| delta reign cards | +250%，相关指数 28 | /blog/delta-reign-pokemon | 同一篇扩展包指南承担卡牌、系列与查价意图 |
| pokemon upc 30th anniversary | +250%，相关指数 4 | /blog/pokemon-upc-30th-anniversary | 扩充 UPC 缩写与变体、Day/Night 和单卡查找入口 |

来源为 ego-browser TaskSpace 9/p1，2026-11-08 01:12（UTC+8）读取 Pokemon cards 的全部 50 条 Rising。原始记录在忽略目录 `apps/cardscanfox-web/.local/trends-card-names-20261108/pokemon-cards-7d.json`。读数是相关查询的相对增长和指数，不是绝对搜索量、新词年龄或排名证据。

## 产品与事实边界

只改新官网文章、公开内容包生成物、索引清单、单卡地图及其手动生成脚本。原 App/API/Admin/Flutter/旧官网代码不改，不改数据库或数据服务。

正式只读接口确认：Roaring Skies 的 61/108（98097）、76/108（98112）、105/108（98141），Ancient Origins 的 98/98（101520）为有编号、有图的实体单卡。指南不写死价格，链接详情查看带来源和日期的现有参考。排除同名 code card。官网确认 Delta Reign 的四张 Mega Evolution Pokémon ex 与 2026-11-06 发行；当前公开单卡列表为空，因此不生成虚假完整卡表、价格排行、pull rate 或 Delta Reign 单卡报价。UPC 使用既有官方产品展示来源，区分密封产品与单卡。

新文、旧文互相链接，并从博客与分类自然进入。新文加入栏目 sitemap；四个现有单卡均纳入卡牌 sitemap，其中一个已在原清单中；本轮新增三个，总数 1,059，原 1,056 个 URL 全部保留。手动地图生成脚本也保留这四个指南记录，避免下次生成撤回它们。

## Jev 与复核

本轮调用实际模型 jev-1.14.0 对四词对象做 Choice 分类。前三词分别为 card、expansion、expansion；UPC 被误分为 expansion（confidence 0.47）。Codex 根据官方 UPC 产品内容将其修正为密封产品意图，保留原有 UPC 指南。Jev 不负责判断趋势真实性、决定页面路由或生成 URL；这些由当前证据和确定性代码完成。当前 TypeSafe 在线文档读取不可用，按已读取的缓存 HTTP 合同调用，未杜撰接口参数。

## 验证与发布

按用户时序先完成内容、元数据、地图与文档，再做受影响官网构建、内容/SEO/原文保留检查和新链接回读。不运行无改动的 App/Admin/Flutter 或后端测试。正式版本生效后，仅通知本轮新改文章、博客/分类入口和新增地图单卡；通知不等同搜索引擎收录。

发布前验证：27 项受影响的内容、元数据、站点地图和原文保留合同通过（239ms）。构建 114 个静态条目，46 个保护旧地址正文及原链接均保留。三篇文章均为首屏 HTML 正文，有独立英文 Title/Description、自指 canonical 和站点地图入口。单卡地图保留原有顺序与全部地址，仅追加三个新发现地址。
