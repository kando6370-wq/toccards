# M4-6 加载/失败/空状态设计

日期：2026-07-07

## 背景

M4-6 对应 `docs/tcg-card/05-plan/dev-plan.md` 的「加载/失败/空状态」。当前 Home、Collection、Search 已有部分业务空状态，但没有统一 loading / failure UI，也没有页面级失败后的 `Refresh` 入口。`global-rules.md` 要求失败状态显示 `No content available` 与 `Refresh`，空状态和失败状态必须区分。

## 方案

采用 Flutter 本地 shared UI + 轻量状态接入：

- 新增 `apps/flutter-app/lib/shared/ui/load_state.dart`，集中定义 `No content available`、`Refresh`、页面/局部 loading、failure、empty UI 组件。
- Home / Collection / Search controller 继续沿用当前同步 mock repository；controller 在 `build()` 和 `refresh()` 中捕获 repository 异常，进入页面级 failure 状态。
- `Refresh` 只重跑当前页面 repository，不触发跨页面刷新，不接真实后端。
- 现有「成功但无数据」业务空状态保留，并逐步改用 shared empty/failure UI 文案，避免把空数据误报成加载失败。

## 设计取舍

推荐方案是「shared UI + 轻量 controller 状态」。它比每个页面各写一套 failure UI 更一致，也比把三个 controller 立即重构为 `AsyncNotifier` 更小、更贴合当前 mock-first 状态。真实网络 loading、10 秒超时、Toast 属于后续接 API / M4-7 范围，本任务不提前实现。

## 范围

交付内容：

- shared loading/failure/empty UI 组件。
- Home 页面 repository 失败时展示页面级 `No content available` + `Refresh`，点击后可恢复。
- Collection 页面 repository 失败时展示页面级 `No content available` + `Refresh`，点击后可恢复。
- Search 页面 repository 失败时展示页面级 `No content available` + `Refresh`，点击后可恢复。
- 现有 Collection/Search/Home 空状态继续表示「请求成功但无数据」。

非目标：

- 不实现 M4-7 Toast。
- 不实现真实网络请求、超时计时器或后台重试。
- 不修改 Workers、schema、migration、wrangler、drizzle 或 admin-web。
- 不修改 `docs/tcg-card/**`。
- 不实现 M4-8 Scan Tab 占位页。

## 验收

- shared UI 测试覆盖 loading、failure、empty 组件文案与 Refresh 回调。
- Home / Collection / Search controller 测试覆盖 repository 失败进入 failure、Refresh 成功恢复内容。
- Home / Collection / Search widget 测试覆盖页面级 failure 不白屏且有 Refresh。
- Focused Flutter tests、`dart run melos run test`、`flutter analyze`、format check 通过。
