# 技术设计

## 目标

让共享 Premium 锁定组件统一呈现“正常内容预览 + 毛玻璃锁定层”。Home Free 状态使用静态 Performance 假数据作为预览；Pro 状态继续使用服务端返回数据。

## 实现边界

- `KandoPremiumLockedPanel` 直接内置静态 Performance 假数据，并在组件内部使用同一裁切区域叠加背景与现有 Figma 锁定层；调用方无需传入背景。
- 背景使用 `IgnorePointer` 和 `ExcludeSemantics`，不可点击、不可被辅助功能误读为真实数据。
- 内置预览按正常 Performance 的 `_PerformanceMetric`、`_PerformanceRangePicker` 与图表几何实现四项指标、间距、范围选择器和折线图。
- 静态数值仅是展示常量，不进入 `HomeState`、`HomePerformanceState` 或任何 API 请求。
- `!isPro`、`onUnlock` 与 Pro 分支顺序不变。

## 验证

- Widget 测试验证 Free 面板存在静态四项指标和图表，同时真实 Pro 区域仍由 entitlement 控制。
- 验证背景位于 `BackdropFilter` 下方、不可交互且不暴露语义。
- 验证 350px Figma 基准与 430px、Home 宽容器自适应。
- 运行 Home 定向测试、`flutter analyze`、Dart format 和 `git diff --check`。

## 数据库与文档

无数据库、API、Schema、配置、架构或部署影响。此变更是用户明确要求的视觉状态调整，不修改版本业务契约。
