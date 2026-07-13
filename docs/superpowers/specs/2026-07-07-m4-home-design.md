# M4-1 Home 页面设计

日期：2026-07-07

## 背景

本设计承接 `docs/tcg-card/05-plan/dev-plan.md` 中的 M4-1「Home 页面」任务。M2 mock 数据代理层与 M3 资产 CRUD 已可支撑 UI 联调，但真实第三方数据源、完整涨跌算法、完整货币换算和全局异常态属于后续任务，不在本设计中提前实现。

本设计遵循以下约束：

- `docs/tcg-card/05-plan/dev-plan.md` 仍是只读计划真源。
- 不修改 `docs/tcg-card/**`。
- 不修改 Workers D1 schema、migration、`wrangler.toml` 或 `drizzle.config.ts`。
- 不新增共享 package，不假设 `packages/api-client`、`packages/ui-kit` 已成熟可复用。
- 当前阶段以 Flutter Home 可演示页面为目标，先使用稳定 mock 数据。

## 已确认选择

用户已确认采用：

- 范围方案：A，mock-first Home UI 壳 + Riverpod 状态模型。
- 布局方向：A1，PRD-aligned single scroll。

## 范围

M4-1 交付 Home 的第一版可演示首页。`/` 路由从 Profile 改为 Home，Profile 保留在底部导航和 `/profile` 路由中。

Home 采用单列滚动结构：

1. 顶部 `Overview` 与货币入口。
2. Portfolio 总资产卡片。
3. Most Valuable 区域。
4. Trending Today 区域。
5. 底部 5 Tab 导航。

M4-1 不实现完整 Collection、Search、Scan 页面。底部导航可以保留入口，但未完成的 Tab 只显示轻量占位或禁用式轻提示，避免把 M4-2、M4-3、M4-8 混入本任务。

## 非目标

以下内容不在 M4-1 中实现：

- 真实 Workers Home 聚合接口接入。
- 真实 `GET /rates` 汇率请求与偏好持久化。
- 完整涨跌算法。
- 全局 Toast 组件。
- 完整网络失败、Refresh 与跨页面空状态体系。
- 完整 Collection、Search、Scan 页面。
- Home Performance Tab。
- 数据库结构或迁移变更。

## 模块结构

新增 Flutter 模块位于 `apps/flutter-app/lib/features/home/`：

- `home_models.dart`：定义 `HomeDashboard`、`PortfolioSummary`、`HomeFolder`、`HomeCardHighlight`、`TrendingCard` 等展示模型。
- `home_repository.dart`：定义 `HomeRepository` 接口和 `MockHomeRepository`。
- `home_controller.dart`：提供 Riverpod controller/provider，负责加载 dashboard 与 Home 内交互状态。
- `home_page.dart`：组合 UI，只消费 provider 状态，不直接放置 mock 数据或业务判断。

路由变更位于 `apps/flutter-app/lib/app/router.dart`：

- `/` 指向 `HomePage`。
- `/profile` 指向现有 `ProfilePage`。
- `/account` 保持现有账号页面。

如需占位页面，优先保持在 Flutter app 内部实现为简单页面或轻提示，不引入新的导航体系。

## 数据流

数据流为：

`HomePage -> homeControllerProvider -> HomeRepository`

M4-1 中 `HomeRepository` 默认由 `MockHomeRepository` 提供稳定 mock 数据。controller 负责维护当前文件夹、当前货币、金额隐藏状态、图表周期和 dashboard 状态。页面只根据状态渲染。

后续 M4-4、M4-5、M4-6 可以替换 repository 或扩展 controller，而不需要重写页面结构。

## 交互

### 货币入口

点击右上角货币码后打开底部弹窗。弹窗提供 `USD`、`CNY`、`JPY` 等 mock 货币。选择后页面金额按 mock 汇率刷新；百分比不变化；不调用真实 `GET /rates`，不持久化偏好。

### 文件夹切换

点击 Portfolio 卡片中的文件夹名称后打开底部弹窗。弹窗展示 mock 文件夹列表。切换文件夹后，Portfolio 总资产、图表与 Most Valuable 更新；Trending Today 保持不变。

### 资产隐藏

点击眼睛按钮后隐藏或显示 Home 内资产金额。隐藏时资产金额显示为 `••••••`。M4-1 只在 Home 内存态生效，不写入真实偏好接口。

### 图表周期

`1D / 7D / 1M / 3M / 6M / MAX` 可切换。M4-1 中切换 mock 曲线和选中态，不实现真实历史价格算法。

### 底部导航

Home 与 Profile 可跳转。Collection、Search、Scan 只保留入口，展示轻量占位或轻提示，完整页面留给后续 M4 子任务。

## 状态

M4-1 默认 mock repository 返回成功状态。

本任务包含最小空状态：当当前文件夹没有可展示的 Most Valuable 卡牌时，Most Valuable 区域展示 `No cards in this portfolio yet`，页面不白屏。

完整网络失败态、Refresh、全局 Toast 与跨页面加载规则留给 M4-6、M4-7。

## 测试策略

实现阶段按 TDD 推进，先写 Flutter 测试再写实现。测试应验证行为意图：

- 启动后 `/` 展示 Home，而不是 Profile，证明冷启动默认进入资产概览。
- Home 展示 Portfolio 总资产、当前文件夹、Most Valuable、Trending Today，证明 M4-1 核心信息层级成立。
- 切换文件夹后 Portfolio Summary 和 Most Valuable 更新，但 Trending Today 不变，证明 Home 的文件夹作用域正确。
- 切换货币后金额展示更新，百分比保持不变，证明货币只影响金额展示。
- 点击隐藏金额后资产金额显示为 `••••••`，证明隐私开关行为成立。
- 空 portfolio 时展示 `No cards in this portfolio yet`，证明无资产时不白屏。

## 验收

M4-1 完成时应满足：

- `/` 路由进入 Home 页面。
- Home 页面以 A1 单列结构展示 Portfolio、Most Valuable、Trending Today。
- 文件夹、货币、金额隐藏、图表周期交互可在 mock 数据上演示。
- Profile 仍可访问。
- 未完成的 Collection、Search、Scan 不被误实现为完整页面。
- Flutter 相关验证通过：优先运行 `dart run melos run test`，必要时补 `flutter analyze`。
- 如本轮只修改 Flutter，不默认运行 Workers 全量测试；最终汇报必须明确说明验证范围。

## 决策记录

- 选择 mock-first 是为了避免把 M4-4 涨跌算法、M4-5 汇率换算、M4-6 加载失败状态提前合并到 M4-1。
- 选择 A1 单列结构是为了直接贴合 Home PRD 的信息层级，并减少第一版页面的设计分叉。
- Home 模块先留在 Flutter app 内部，不抽到共享 package，因为当前共享 UI/API package 仍处于占位阶段。
