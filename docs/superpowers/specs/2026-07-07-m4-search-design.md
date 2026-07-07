# M4-3 Search 页面设计

日期：2026-07-07

## 背景

本设计承接 `docs/tcg-card/05-plan/dev-plan.md` 中的 M4-3「Search 页面」任务。当前状态是：M2 mock 数据代理层、M3 资产 CRUD、M4-1 Home 页面与 M4-2 Collection 页面已完成；M7 管理后台由 `m7-admin` worktree 并行开发，本任务不触碰后台范围。

本轮遵循以下约束：

- `docs/tcg-card/05-plan/dev-plan.md` 是只读计划真源，不修改。
- 不修改 `docs/tcg-card/**`。
- 不修改 Workers D1 schema、migration、`wrangler.toml` 或 `drizzle.config.ts`。
- 不修改 `apps/admin-web`、Admin API、Admin 文档或 M7 相关文件。
- Flutter 侧继续沿用 M4-1/M4-2 的 mock-first、Riverpod、本地模块风格。
- 用户已授权普通决策按推荐项执行，因此本设计不再逐项请求人工审批。

## 推荐方案

对 M4-3 有三种可行路径：

1. 直接接入 Workers `/cards/search`、`/sets/search`、Collect 和 Wishlist 端点。
   - 优点：更接近最终数据流。
   - 缺点：会把鉴权、网络失败态、真实第三方数据、详情页跳转和 Toast 体系提前压进 M4-3，容易与 M4-6/M4-7/M5 交叉。

2. 完全静态 Search 页面。
   - 优点：实现最短。
   - 缺点：无法验证 Cards/Sets 搜索状态独立、Game/IP 切换、Qty、Collect/Wishlist 互斥等核心行为。

3. mock repository + Riverpod 状态模型 + PRD 对齐 UI。
   - 优点：覆盖 Search 页核心交互，保持实现局部，后续可替换 repository 接真实 API。
   - 缺点：本任务不验证真实网络联调。

采用方案 3。

## 范围

M4-3 交付 Flutter Search 第一版可演示页面，包含：

1. `/search` 路由。
2. Home、Collection 底部导航点击 Search 后进入真实 Search 页面。
3. Search 页面底部导航选中 Search；Home、Collection、Profile 仍可跳转。
4. 顶部搜索框，提示文案 `Search cards, sets, or characters`。
5. 搜索框右侧 Scan 图标；点击后进入 Scan 占位入口语义，真实 Scan 页留给 M4-8。
6. 输入关键词后显示清除按钮；点击清除恢复当前 Game/IP 下当前 Tab 默认列表。
7. Game/IP 选择器，默认 `Pokemon`；切换 Game/IP 时清空当前 Tab 搜索词并刷新列表。
8. `Cards` / `Sets` 双 Tab；两个 Tab 的搜索词和结果状态相互独立。
9. Cards 双列列表，展示图片占位、名称、当前价格、30D Change、归属信息、版本/状态、Qty、Collect/Collected、Wishlist 心形。
10. Sets 列表，展示系列名、Game/IP、发行信息和数量摘要。
11. Collect 点击后当前卡 Qty 从 0 变 1，按钮变为 Collected，并自动移除 Wishlist。
12. Collected 点击后当前卡 Qty 归 0，按钮恢复 Collect。
13. Wishlist 心形点击后在空心/实心间切换；Collected 状态下心形不展示为实心。
14. 缺价展示 `--`，缺涨跌展示 `-/-`。
15. Cards/Sets 空结果状态展示 `No matching results found.`。

## 非目标

以下内容不在 M4-3 中实现：

- 真实 Workers API 接入。
- 真实第三方搜索、图片加载、分页、缓存、网络失败恢复。
- CardDetail 页面跳转与详情页两态，这些留给 M5。
- 全局加载/失败/空状态体系，这些留给 M4-6。
- 全局 Toast 组件，这留给 M4-7。
- Scan 真功能或完整 Scan 页面，这留给 M4-8。
- 真实货币换算和偏好持久化，这留给 M4-5 或后续接 API。
- 后台、Admin、M7 相关任何能力。
- 数据库结构、迁移或 Workers 配置变更。

## 模块结构

新增 Flutter 模块位于 `apps/flutter-app/lib/features/search/`：

- `search_models.dart`：定义 Game/IP、Tab、卡牌类型、Search card、Search set 与展示状态。
- `search_repository.dart`：定义 `SearchRepository` 接口与 deterministic mock data。
- `search_controller.dart`：提供 Riverpod provider、`SearchState` 与交互方法。
- `search_page.dart`：组合 UI，只消费 controller 状态，不直接放置业务数据。

最小修改现有 Flutter 文件：

- `apps/flutter-app/lib/app/router.dart`：新增 `/search` route。
- `apps/flutter-app/lib/features/home/home_page.dart`：Search 底部导航进入 `/search`。
- `apps/flutter-app/lib/features/collection/collection_page.dart`：Search 底部导航进入 `/search`。
- 测试文件按需新增或调整，只覆盖本任务相关行为。

不在本任务抽公共底部导航组件。Home/Collection/Search 当前重复成本可控，抽象会扩大改动面；等 Scan/Profile 页面齐备后再统一判断。

## 数据模型

`SearchCatalog` 包含：

- `games`：Game/IP 选项，默认 `Pokemon`。
- `cards`：mock 卡牌列表。
- `sets`：mock 系列列表。

`SearchCard` 展示字段包含：

- `id`
- `game`
- `type`
- `name`
- `priceUsd`
- `change30dPercent`
- `setName`
- `metadataLine`
- `variantLine`
- `quantity`
- `isWishlisted`

`SearchSet` 展示字段包含：

- `id`
- `game`
- `name`
- `subtitle`
- `releaseText`
- `cardCountText`

Cards 和 Sets 的搜索结果都按当前 `selectedGame` 过滤。Cards 的 Qty、Collect 与 Wishlist 状态为页面内存态，后续接入 M3/M4 端点时由 repository 替换。

## 状态与数据流

数据流为：

`SearchPage -> searchControllerProvider -> SearchRepository`

controller 维护：

- 当前 Game/IP，默认 `Pokemon`。
- 当前 Tab，默认 Cards。
- Cards 搜索词。
- Sets 搜索词。
- Cards 本地状态 overrides，包括 Qty 与 Wishlist。

派生状态：

- `visibleCards`：当前 Game/IP + Cards 搜索词过滤。
- `visibleSets`：当前 Game/IP + Sets 搜索词过滤。
- `searchText`：按当前 Tab 返回对应搜索词。
- `hasQuery`：当前 Tab 搜索词是否非空。

## 交互

### 搜索与 Tab

进入 Search 默认展示 Cards。切换 Sets 后，Cards 搜索词和结果保留；Sets 使用自己的搜索词。再次切回 Cards 时恢复 Cards 原状态。

清除按钮只清空当前 Tab 的搜索词，不影响另一个 Tab。

### Game/IP

默认 Game/IP 为 `Pokemon`。切换 Game/IP 后：

- 当前 Tab 搜索词清空。
- 当前 Tab 列表刷新到新 Game/IP 的默认列表。
- 另一个 Tab 的搜索词不强行清空，等用户切换过去时仍保持独立状态。

这里显式选择“只清当前 Tab 搜索词”。PRD 要求切换 Game/IP 后清空当前搜索词，同时又要求 Cards/Sets 搜索状态互不关联；为避免跨 Tab 意外清空，本任务按当前 Tab 处理。

### Collect / Collected

点击 Collect：

- Qty 从 0 更新为 1。
- 按钮变为 Collected。
- Wishlist 状态置为 false。

点击 Collected：

- Qty 更新为 0。
- 按钮恢复 Collect。

若未来真实 API 发现同一卡在当前文件夹有多条 Collection Item，点击 Collected 应进入详情页管理；M4-3 mock 数据不模拟多条删除保护。

### Wishlist 心形

点击空心心形后加入 Wishlist；点击实心心形后移除 Wishlist。Collected 状态与 Heart 互斥：卡牌处于 Collected 时，心形按非实心展示，即使之前曾在 Wishlist 中。

## 测试策略

实现阶段按 TDD 推进，先写失败测试再写最小实现。

建议测试覆盖：

- controller 默认进入 Cards Tab、Pokemon Game/IP，并展示 Pokemon 卡牌。
- Cards 与 Sets 搜索词互不影响，切换 Tab 后恢复各自结果。
- 清除按钮只清空当前 Tab 搜索词。
- 切换 Game/IP 清空当前 Tab 搜索词并刷新列表。
- Collect 会把 Qty 从 0 变 1、按钮态变 Collected，并移除 Wishlist。
- Collected 再点击会把 Qty 归 0。
- Wishlist 心形可切换，Collected 时不展示实心。
- 缺价展示 `--`，缺涨跌展示 `-/-`。
- `/search` 路由可访问，Home/Collection 底部导航能进入 Search。

## 验收

M4-3 完成时应满足：

- `/search` 路由可访问。
- Home 和 Collection 底部导航 Search 进入真实 Search 页面。
- Search 页面展示搜索框、Game/IP 选择器、Cards/Sets 双 Tab。
- Cards 可按关键词和 Game/IP 过滤，展示 Qty、Collect、Wishlist、价格和 30D Change。
- Sets 可按关键词和 Game/IP 过滤。
- Cards/Sets 搜索状态相互独立。
- Collect/Wishlist 本地交互符合互斥规则。
- 空结果状态不白屏。
- 不触碰 M7/admin 范围。
- Flutter 相关测试、格式化与分析通过。
- 若只修改 Flutter 和执行状态文档，不默认运行 Workers 测试；最终汇报明确验证范围。

## 冲突与边界选择

- PRD 中 Scan 图标进入 Scan 页面，但 M4-8 才实现 Scan Tab 占位页。本任务只保留入口行为，不实现真 Scan。
- PRD 中点击卡片进入 CardDetail，但 M5 才实现详情页。本任务不新增半成品详情路由。
- PRD 中失败和 Toast 规则引用 global-rules；M4-6/M4-7 负责统一实现。本任务只做本地可演示状态，不伪造全局组件。
- Game/IP 切换与 Tab 搜索独立存在张力。本任务选择只清当前 Tab 搜索词，以满足“当前搜索词清空”和“两 Tab 状态互不关联”两个约束。
