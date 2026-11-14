# 官网按曝光记录收紧索引（2026-11-15）

## 决策与证据

用户最初要求保留约50页；读取GSC后，用户明确改为“只关闭无曝光页：先保留这140个有曝光页面，不硬凑50”。以此最新选择实施，不撤销已有曝光页索引资格。页面继续访问，保留正文与canonical，不返回404、不删除网址、不使用Search Console紧急移除或robots阻断。

正式sitemap只读读取原为1200个不同URL：88个其他页面＋1112个卡牌详情，没有筛选参数、私有页或预览域名。GSC人工处置显示未检测到问题；站点地图报告对sitemap.xml显示未知类型、无法抓取、发现0，上次提交11月12日；这不是整站0索引。GSC网页报告显示834已索引、285未索引（报告更新时间11月9日）；与本次sitemap数量不是同一口径。

GSC效果报告当前窗口为2026-10-12至2026-11-11，网页页签选择500行，读取完整140行，全部曝光>0、其中8页有点击；所有140个URL进入保留清单。不能将当前窗口缺少可见曝光写成永远零需求，也不将GSC隐私/数据延迟当作确定零值。原始导出保留于忽略目录`.local/sitemap-audit-20261115`，不上传私有原始指标到模型。

Google官方协议每个sitemap可含50000个URL/50MB；1200页不是数量超限或处罚证据。真实风险是抓取可达性、内容价值、重复和服务器响应，当前人工处置无问题也不证明算法绝无降权。本次收紧按用户发布策略执行，不声称可提高排名或解决GSC无法抓取。

## 最终规则

`content/index-policy.json`中的rollout.allowedPaths为244个URL路径：140个有曝光页，加上88个既有官网/关键词/核心页和61个首页/指南引用卡牌种子的并集。存在重叠，不能直接相加。数据时窗和目的随配置保存。未使用Jev判断曝光，精确URL匹配、计数和保留规则由代码完成；这类确定性任务遵循TypeSafe边界。

- 所有140个有曝光URL保留原索引资格，包括不在原sitemap中的91个URL；原来未在地图中不代表被关闭，本次不据此额外扩张地图。
- 无曝光但属于近期关键词、首页和核心产品路径的页按明确例外保留。首页继续说明TCG和体育卡，没有收窄为单一宝可梦产品。
- 清单外详情页、套装页返回原有内容与200，但meta robots及X-Robots-Tag为noindex,follow；保持canonical，允许爬虫读取noindex。
- 原卡牌发现批次从1112条收紧为65条，暂缓1047条；其他88条保留。正式sitemap目标共153条。91个曝光页原来就在sitemap之外，本次只保留其索引资格，不把它们算入153条。
- 原目录、筛选、卡牌详情及App功能保留。查询参数、404、无有效目录数据等原安全门槛继续生效。
- 手动prepare-launch-sitemap生成器也按清单筛选，后续重新生成不能意外恢复批量索引。没有新增cron或自动放量；重新开放须先更新依据与清单。

## 验收及交付边界

全部实现完成后，只检查发布策略、sitemap、原正文保留、Worker meta/header一致性与预览边界；不跑未改动的App、Admin、原业务API回归。本地构建生成124条HTML，46条原网址全文/原链接保留。官网全套76项首次75项通过，失败为旧测试仍假设任意有效卡页都可索引；将该场景改用明确保留ID并保留缺价索引断言后，相关catalog-seo 12项重跑全部通过。其余75项已经通过，无未解决失败。另独立逐个核对140个曝光URL可保留索引资格、清单244条、XML及manifest字节/hash、153条地图数均通过。生产Worker单测确认暂停页仍200且meta/header均noindex,follow，缓存与预览边界通过。本地Node24.3.0，与仓库固定22.23.4不同；正式构建与运行回读另记。内容提交f23b29e011e06ad63372a74d2fcc7f437badfbc9已推送main，官网Worker自动构建success，正式manifest回读同一sourceCommit。正式XML为88＋65＝153，抽查两个暂停详情均200且meta/header为noindex,follow；有曝光的Mew ex、Honesty Impact、2022 Panini Prizm套装，以及近期McDonald’s指南均200且index,follow。140个正曝光URL的全部清单匹配已通过本地规则逐项核验；线上仅抽查，不声称逐页重抓140页。最终Ego任务空间已不可用，未补做可见浏览器验收，正式验证以HTTP正文/响应头和manifest为准。Google需要重新抓取才处理noindex，不保证即时退出搜索结果；不向IndexNow当作新内容重复通知暂停页。GSC无法抓取仍须按真实Googlebot请求证据单独排查，本次不改WAF。

官方依据：
- https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap
- https://developers.google.com/search/docs/crawling-indexing/large-site-managing-crawl-budget
- https://developers.google.com/search/docs/essentials/spam-policies#scaled-content
