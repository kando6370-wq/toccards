# M4-2 Collection 页面设计

日期：2026-07-07

## 背景

本设计承接 `docs/tcg-card/05-plan/dev-plan.md` 中的 M4-2「Collection 页面」任务。当前状态是：M2 mock 数据代理层、M3 资产 CRUD 与 M4-1 Home 页面已完成；M2-2 真实第三方厂商适配仍受外部厂商选择阻塞，不进入本任务；M7 管理后台由 `m7-admin` worktree 并行开发，本任务不触碰后台范围。

本轮遵循以下约束：

- `docs/tcg-card/05-plan/dev-plan.md` 是只读计划真源，不修改。
- 不修改 `docs/tcg-card/**`。
- 不修改 Workers D1 schema、migration、`wrangler.toml` 或 `drizzle.config.ts`。
- 不修改 `apps/admin-web`、Admin API、Admin 文档或 M7 相关文件。
- 不新增共享 package，不假设 `packages/api-client`、`packages/ui-kit` 已成熟可复用。
- Flutter 侧继续沿用 M4-1 的 mock-first、Riverpod、本地模块风格。

## 推荐方案

对 M4-2 有三种可行路径：

1. 直接接入 M3 Workers API。
   - 优点：更接近端到端。
   - 缺点：会把鉴权、本地 dev server、数据补全、失败态和联调问题提前压进 M4-2，且当前 Collection PRD 还依赖价格/涨跌展示，真实数据口径仍受第三方数据源影响。

2. 完全静态 Collection 页面。
   - 优点：实现最短。
   - 缺点：无法验证文件夹、Tab、搜索、排序、筛选、金额隐藏等核心行为，后续替换成本高。

3. mock repository + Riverpod 状态模型 + PRD 对齐 UI。
   - 优点：覆盖核心交互与测试意图，保持实现局部，后续可替换 repository 接真实 API。
   - 缺点：本任务不验证真实网络联调。

采用方案 3。用户已授权普通决策按推荐项执行，因此本设计将方案 3 作为执行方案。

## 范围

M4-2 交付 Flutter Collection 第一版可演示页面，包含：

1. `/collection` 路由。
2. Home 底部导航点击 Collection 后进入真实 Collection 页面。
3. Collection 页面底部导航选中 Collection；Home/Profile 仍可跳转。
4. 顶部标题 `Collection`。
5. 当前 Portfolio 文件夹入口，默认复用 Home mock 文件夹语义。
6. `Portfolio` / `Wishlist` 双 Tab。
7. 当前 Tab 搜索。
8. 当前 Tab 排序与筛选入口。
9. Portfolio 当前文件夹汇总：总金额、卡牌条数、评级卡条数。
10. Portfolio 列表：卡牌信息、数量、状态、当前价值、30D Change。
11. Wishlist 列表：卡牌信息、当前市场价、30D Change，不展示数量，不计入资产汇总。
12. 金额隐藏开关，Collection 内金额字段显示 `••••••`。
13. Portfolio 空状态、Wishlist 空状态、搜索/筛选无结果状态。

## 非目标

以下内容不在 M4-2 中实现：

- 真实 Workers API 接入。
- 真实价格、价格序列、汇率、涨跌算法。
- 完整全局失败态、全局 Toast 组件和网络异常体系，这些留给 M4-6、M4-7。
- iOS 原生分享弹窗，只保留分享按钮或入口占位，不调原生能力。
- 卡牌详情页跳转和 Collection Item 编辑，这些留给 M5。
- Search、Scan 完整页面，这些分别留给 M4-3、M4-8。
- 后台、Admin、M7 相关任何能力。
- 数据库结构、迁移或 Workers 配置变更。

## 模块结构

新增 Flutter 模块位于 `apps/flutter-app/lib/features/collection/`：

- `collection_models.dart`：定义 Collection 展示模型、Tab、排序、筛选状态与条目类型。
- `collection_repository.dart`：定义 `CollectionRepository` 接口与 `MockCollectionRepository`。
- `collection_controller.dart`：提供 Riverpod provider、`CollectionState` 与交互方法。
- `collection_page.dart`：组合 UI，只消费 controller 状态，不直接放置业务数据。

最小修改现有 Flutter 文件：

- `apps/flutter-app/lib/app/router.dart`：新增 `/collection` route。
- `apps/flutter-app/lib/features/home/home_page.dart`：Collection 底部导航从占位 SnackBar 改为 `context.go('/collection')`。
- 测试文件按需新增或调整，只覆盖本任务相关行为。

不抽共享底部导航组件。M4-1 的 Home 底部导航目前仍是页面内实现；为了减少改动，本任务只做必要接线。若后续多个页面重复明显，再在单独任务中抽公共组件。

## 数据模型

`CollectionDashboard` 包含：

- `folders`：文件夹列表，复用 `HomeFolder` 语义或定义等价轻模型。
- `portfolioByFolderId`：每个文件夹的 Portfolio 条目。
- `wishlistItems`：Wishlist 条目。

`CollectionCardItem` 展示字段包含：

- `id`
- `cardRef`
- `name`
- `setName`
- `number`
- `language`
- `finish`
- `grader`
- `condition`
- `grade`
- `quantity`
- `marketValueUsd`
- `change30dPercent`
- `game`
- `createdAtSort`

Portfolio 和 Wishlist 共用卡牌基础展示字段，但通过 `CollectionItemKind` 区分展示口径：

- Portfolio 展示数量、文件夹汇总、资产价值。
- Wishlist 不展示数量，不进入资产汇总。

## 状态与数据流

数据流为：

`CollectionPage -> collectionControllerProvider -> CollectionRepository`

controller 维护：

- 当前 Tab，默认 Portfolio。
- 当前文件夹，默认 Main。
- 当前货币，默认 USD。
- 金额隐藏状态，默认 false。
- Portfolio 搜索词、排序、筛选。
- Wishlist 搜索词、排序、筛选。

M4-2 中这些状态为页面内存态。后续可与 `user_preference.last_selected_folder_id`、`amount_hidden`、`currency` 接真实接口联动；本任务不提前写偏好接口。

## 交互

### Tab

进入 Collection 默认展示 Portfolio。切换到 Wishlist 后不显示文件夹汇总，但保留搜索和筛选入口。两个 Tab 的搜索、排序、筛选状态相互独立。

### 文件夹切换

点击当前文件夹名称打开底部弹窗。选择文件夹后：

- Portfolio 汇总更新。
- Portfolio 列表切换到该文件夹。
- Wishlist 不受影响。

Home 与 Collection 的真实双向持久联动留给接入偏好接口时处理。M4-2 先保证 Collection 内文件夹作用域正确，并在 mock 数据上保持与 Home 文件夹命名一致。

### 搜索

搜索作用于当前 Tab：

- Portfolio 搜索范围限定当前文件夹。
- Wishlist 搜索范围为全量 Wishlist。
- 搜索字段覆盖卡牌名、系列名、编号、Game/IP。
- 清空搜索词恢复当前筛选和排序下的列表。

### 排序与筛选

M4-2 实现最小可验证排序/筛选：

- Sort：`Newest`、`Value high to low`、`30D gain high to low`、`Name A-Z`。
- Game/IP：多选 mock 选项。
- Language：多选 mock 选项。

使用底部弹窗承载排序和筛选。点击 Apply 后关闭弹窗并刷新列表。点击 Clear 后清空当前 Tab 的筛选条件并恢复默认排序。

### 金额隐藏

点击眼睛图标后，Collection 内所有金额字段显示 `••••••`：

- Portfolio 汇总金额。
- Portfolio 条目当前价值。
- Wishlist 条目当前市场价。

涨跌百分比不隐藏，仍按 PRD 作为百分比展示。M4-2 不写入 `PATCH /preferences`。

### 空状态

Portfolio 当前文件夹无条目时展示：

- `No cards in this portfolio yet.`
- `Scan or search cards to start tracking your collection.`
- `Scan a Card`
- `Search Cards`

Wishlist 无条目时展示：

- `Your wishlist is empty.`
- `Save cards you want to collect later and keep an eye on their market value.`
- `Search Cards`

搜索或筛选无结果时展示：

- `No matching cards found.`

Scan/Search 按钮在 M4-2 中只保留入口语义；若目标页面尚未完成，仍显示轻量占位提示，不实现对应页面。

## 测试策略

实现阶段按 TDD 推进，先写失败测试再写最小实现。

建议测试覆盖：

- controller 默认进入 Portfolio Tab、Main 文件夹，并计算 Portfolio 汇总。
- 切换文件夹只改变 Portfolio 范围，不改变 Wishlist。
- 切换 Tab 后各 Tab 搜索、排序、筛选状态独立。
- 搜索限定当前 Tab 和当前文件夹，清空后恢复列表。
- 排序按价值、30D 涨幅、名称生效，缺价项排在底部。
- Game/IP 与 Language 筛选可组合生效。
- 金额隐藏后金额字段展示 `••••••`，百分比仍可见。
- Portfolio 空状态、Wishlist 空状态、无匹配状态不白屏。
- Home 底部导航点击 Collection 进入 Collection；Collection 底部导航可回 Home/Profile。

## 验收

M4-2 完成时应满足：

- `/collection` 路由可访问。
- Home 底部导航 Collection 进入真实 Collection 页面。
- Collection 页面展示 Portfolio/Wishlist 双 Tab。
- Portfolio 按当前文件夹展示 mock 持有卡，支持搜索、排序、筛选。
- Wishlist 展示 mock 心愿单，支持搜索、排序、筛选。
- Portfolio 汇总、数量、评级卡数量展示正确。
- 金额隐藏在 Collection 内对金额字段生效。
- 空状态和无匹配状态按 PRD 文案展示。
- 不触碰 M7/admin 范围。
- Flutter 相关测试、格式化与分析通过。
- 若只修改 Flutter 和执行状态文档，不默认运行 Workers 测试；最终汇报明确验证范围。

## 冲突与边界选择

- `dev-plan.md` 说 M4-2 包含分享，但原生分享能力会引入平台插件和 iOS 行为验证。本任务只保留分享入口语义，不调原生分享；真正原生分享可在后续 iOS 联调或 CardDetail 任务中单独落地。
- Collection 与 Home 的文件夹、货币、金额隐藏最终应通过偏好接口双向同步；M4-2 不提前接真实偏好写入，避免把 M4-5 和偏好联调揉进本任务。
- 不抽公共底部导航组件。当前重复成本小，抽象会扩大改动面；待 Search、Scan、Profile 页面齐备后再判断是否需要统一。
