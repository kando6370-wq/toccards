# 技术设计

## 目标

卡牌详情页未订阅的 Performance 状态复用 `KandoPremiumLockedPanel`，保持现有订阅和数据业务逻辑不变。

## 实现边界

- `_CardPerformance` 的 `!isPro` 分支、`onUnlock` 回调及 `_unlockPerformance` 流程保持不变。
- `_CardPerformanceLocked` 改为组合 `KandoPremiumLockedPanel`，保留原标题、说明、按钮文案以及 `card-detail-performance-locked`、`card-detail-unlock-performance` Key。
- Pro 状态继续由 `CardPerformanceController` 按 Item ID 请求服务端 Performance 数据，范围选择、失败、无数据和购买价缺失状态不变。
- 不新增组件参数，不修改共享组件内部模拟数据，不引入平台分支。

## 验证

- Widget 测试验证 Free 状态包含共享组件的模拟预览与模糊层，同时不显示测试服务端数据。
- 既有 Pro 测试继续验证服务端 Item Performance、范围选择和图表交互。
- 运行相关 Widget 测试、`flutter analyze`、Dart format 和 `git diff --check`。

## 数据库与文档

无数据库、API、Schema、配置、架构、部署或运维影响；仅替换现有 Free 锁定状态的 UI 组合实现。
