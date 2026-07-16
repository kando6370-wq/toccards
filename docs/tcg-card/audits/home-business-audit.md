# HOME 业务审计

## 0. 文档说明

- 分析范围：Flutter HOME 页面、真实卡牌与 Portfolio API、Workers 估值逻辑及 D1 资产历史。
- 设计真源：Figma `DjacfTioobtRy59SnqH7SY`，HOME 正常态 `131:21335`、失败态 `131:21496`。
- 产品口径：`TCG_PRD_整合版.md` 第 1.1、4、5、10 章。
- 证据规则：仅以可执行代码、自动化测试、生产 API 返回和 CI 为证据；进度文档中的完成标记不作为证据。

## 1. 业务总览与主线

HOME 是当前 Portfolio 文件夹的资产概览，不管理 Wishlist。完整主线为：匿名或登录会话确定 owner -> 读取文件夹、用户偏好与 90 天估值 -> 按当前文件夹展示总资产、真实历史曲线和 Most Valuable -> 独立读取 Trending Today -> 切换文件夹或货币后同步偏好 -> 从卡片进入 Collection、Search 或 Card Detail。

| 模块 | 业务职责 | 真实接口 | 结论 |
|---|---|---|---|
| Portfolio 概览 | 当前文件夹总价值与历史曲线 | `GET /portfolio/valuation-history` | 代码明确 |
| Most Valuable | 当前文件夹单条 Collection Item 单价排序 | `GET /portfolio/valuation-history` | 代码明确 |
| Trending Today | 全局当日市场涨幅列表，不受文件夹影响 | `GET /cards/trending` | 代码明确 |
| 文件夹 | HOME 与 Collection 共享选中项 | `GET /portfolio/folders`、偏好接口 | 代码明确 |
| 货币与隐藏金额 | owner 级偏好并作用于 HOME 金额 | Portfolio preferences、汇率接口 | 代码明确 |

## 2. 用户角色与权限

| 身份 | 页面能力 | 数据范围 | 服务端证据 | 结论 |
|---|---|---|---|---|
| 游客 | 浏览 HOME、切换文件夹/货币、管理匿名资产 | `owner_type=anonymous` 与当前匿名 `owner_id` | `auth/anonymous.ts`、`owner-auth.ts` | 代码明确 |
| 登录用户 | 与游客相同，并使用迁移后的账号资产 | `owner_type=user` 与当前 `owner_id` | `auth/guest-migration.ts`、`owner-auth.ts` | 代码明确 |
| 未认证请求 | Trending 可公开读取；Portfolio 数据返回 401 | 不得读取 owner 资产 | `data-source/routes.ts`、`portfolio/routes.ts` | 代码明确 |

Flutter 页面可见性不是权限边界。Portfolio 文件夹、估值与偏好均在 Workers 重新校验 Bearer Token，并按 owner 过滤。

## 3. 核心业务流程

### 3.1 页面加载

Auth 恢复或创建匿名会话 -> 并行读取 folders、valuation history、preferences -> 生成每个文件夹的总资产、1D/7D/15D/1M/3M 曲线和 Most Valuable -> 独立读取 Trending -> 按偏好恢复文件夹、货币和金额隐藏状态 -> 渲染 Figma HOME。

### 3.2 页面联动

| 动作 | 处理 | 下游影响 | 证据 |
|---|---|---|---|
| 切换文件夹 | 更新 owner 偏好与共享 folder provider | HOME、Collection 使用同一文件夹 | `HomeController.selectFolder()` |
| 切换货币 | 读取真实 USD 汇率后更新偏好 | 总资产、卡片和曲线 tooltip 同步换算 | `HomeController.selectCurrency()` |
| 隐藏金额 | 更新 owner 偏好 | HOME 与 Collection 同步隐藏 | `HomeController.toggleAmountHidden()` |
| View Most Valuable | 进入 Collection Portfolio 并按单价降序 | 管理当前文件夹资产 | `HomePage` 路由与 `collectionInitialSortProvider` |
| View Trending | 进入 Search | 保留市场数据业务入口 | `HomePage` 路由 |

### 3.3 异常流程

| 场景 | 当前行为 | 是否保留其他数据 | 证据 |
|---|---|---|---|
| folders/preferences/valuation 核心请求失败 | HOME 保留上次 Dashboard，曲线与 Most Valuable 显示 Figma 失败面板 | Trending 保留并显示图片占位 | `HomeController._resolveDashboard()`、Figma `131:21496` |
| Trending 请求失败 | 仅 Trending 显示 `No content available / Refresh` | 总资产、曲线、Most Valuable 保持可用 | `04a555f`、HOME 测试 |
| Trending 局部刷新 | 只重新调用真实 Trending feed | 不重新加载 Portfolio Dashboard | `HomeController.refreshTrending()` 测试 |
| Trending 成功但无结果 | 显示空状态，不冒充请求失败 | 是 | `_TrendingSection` |

## 4. 核心数据实体

| 实体 | 关键字段 | HOME 用途 | 证据 |
|---|---|---|---|
| `portfolio_folder` | owner、name、is_default、sort_order | 文件夹选择与默认文件夹 | `db/schema.ts` |
| `collection_item` | folder_id、card_ref、定价状态、quantity | 当前资产和 Most Valuable | `db/schema.ts` |
| `collection_item_event` | item_id、event_type、effective_at、定价快照 | 历史日期的资产回放 | `0004_collection_item_event.sql` |
| `user_preference` | currency、amount_hidden、last_selected_folder_id | HOME/Collection 共享偏好 | `db/schema.ts` |
| `cards_all` / `tcgplayer_skus` | 卡牌信息与价格历史 | Trending、当前价与历史价 | `db/schema.ts` |

## 5. 业务规则与计算

| 规则 | 公式或约束 | 当前实现 |
|---|---|---|
| 当前总资产 | 当前文件夹内有有效市场价的 Collection Item `单价 x quantity` 之和 | Workers 计算 |
| 历史资产 | 按 `collection_item_event` 在每个日期重放当时存在的 Item，再匹配当日价格 | Workers 计算，删除前历史不回写 |
| 曲线范围 | 从同一 91 点响应截取 2/8/16/31/91 点 | Flutter `HomeChartRange` |
| 曲线 tooltip | 日期取 `series[].date`，金额取同一索引 `value_usd` 并按当前货币格式化 | `bcc5737`；不再使用硬编码日期/价格 |
| Most Valuable | 按单条 Item 当前单价排序，不乘 quantity | Workers 估值响应 |
| 30D Change | `(current - previous30d) / previous30d`；基准无效时显示 `--` | `MarketChange` |
| Trending | 服务端按当日涨幅排序，HOME 取前三条有效价格记录 | `loadTrendingCards()` |

## 6. 上下游与影响面

| 依赖 | 方向 | 失败影响 | 证据 |
|---|---|---|---|
| Auth session | 上游 | 无 owner 时不能读取 Portfolio | `homeRepositoryProvider` |
| Collection Item CRUD | 上游 | 新增、编辑、移动、删除改变当前与后续估值 | `collection_item_event` |
| D1 卡牌/价格 | 上游 | 缺价 Item 不计入总资产和 Most Valuable | `valuation-history.ts` |
| Collection | 下游 | HOME 文件夹选择与 View all 影响 Collection 初始状态 | 页面路由测试 |
| Search/Card Detail | 下游 | Trending 卡片与列表进入真实卡牌详情和收藏流程 | HOME widget 测试 |

## 7. 行业术语

| 术语 | 含义 |
|---|---|
| Portfolio | 按文件夹组织并参与资产统计的已拥有卡牌集合 |
| Collection Item | 一条独立持有记录，同卡可有多条且状态不同 |
| Valuation History | 按资产事件和历史市场价重建的每日文件夹价值 |
| Most Valuable | 当前文件夹中单条 Collection Item 的最高单价项 |
| Trending Today | 与用户资产无关的市场当日涨幅排序 |

## 8. 证据索引

| 编号 | 文件/位置 | 说明 |
|---|---|---|
| E1 | `apps/flutter-app/lib/features/home/home_repository.dart` | HOME 聚合、真实 Trending 与历史日期映射 |
| E2 | `apps/flutter-app/lib/features/home/home_controller.dart` | 页面状态、偏好和 Trending 局部恢复 |
| E3 | `apps/flutter-app/lib/features/home/home_page.dart` | Figma 页面结构、失败/空状态与动态 tooltip |
| E4 | `apps/flutter-app/lib/shared/portfolio/portfolio_api_client.dart` | `/portfolio/valuation-history` 合约 |
| E5 | `apps/workers-api/src/portfolio/valuation-history.ts` | 当前值、历史值和 Most Valuable 计算 |
| E6 | `apps/workers-api/src/data-source/routes.ts` | `/cards/trending` 数据源 |
| E7 | `docs/tcg-card/source-tcg-card-docs/20260708/TCG_PRD_整合版.md:1226` | HOME 产品规则 |
| E8 | Figma `131:21335`、`131:21496` | HOME 正常态与失败态 |

## 9. 待确认问题与上线阻断

| 问题 | 影响 | 当前决定 |
|---|---|---|
| iOS 商店旧截图仍含硬编码曲线假值 | 截图不能用于 App Store | 必须基于当前代码和生产数据重拍 |
| 生产价格最新日期集中在 2026-07-06 至 2026-07-08 | Trending 与估值新鲜度可能不足 | 不插测试价格掩盖，作为数据管线上线依赖 |
| Graded 真实价格源未接入 | Graded Item 不计入资产值 | 保持 `--`，不以 Raw 冒充 |
| 曲线触摸/拖动交互未在 PRD 明确定义 | 当前显示真实采样点，但用户不能拖动选择 | 以 Figma 当前静态态为准，后续需产品确认交互 |

## 10. 本轮验证记录

| 验证项 | 结果 | 证据 |
|---|---|---|
| 生产 Trending | 成功返回 10 条真实卡牌；前三条包含 `card_ref`、当前价与 1D 基准价 | 2026-07-16 生产 API smoke |
| 生产 valuation | 新匿名文件夹成功返回 91 个连续 `date/value_usd` 点；测试账号随后删除 | 2026-07-16 生产 API smoke |
| Flutter 聚焦测试 | 42 项通过 | Repository、Controller、HOME widget |
| Flutter 全量测试 | 335 项通过、1 项明确跳过 | 2026-07-16 本地验证 |
| Flutter analyze | 无问题 | 2026-07-16 本地验证 |
| iOS unsigned Release | `04a555f` 上 Ruby、Fastlane、Pods、lockfile 无漂移及 Release 构建全部成功 | GitHub Actions run `29510010922` |
| 代码提交 | 动态真实 tooltip 与 Trending 局部失败分段提交 | `bcc5737`、`04a555f` |
