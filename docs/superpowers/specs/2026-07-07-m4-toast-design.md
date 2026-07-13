# M4-7 Toast 全局组件设计

日期：2026-07-07

## 背景

M4-7 对应 `docs/tcg-card/05-plan/dev-plan.md` 的「Toast 全局组件」。`global-rules.md` 要求通用操作失败 Toast 使用固定文案 `Something went wrong. Please try again.`，自动显示 2-3 秒，不阻塞用户操作，不使用遮罩，并固定在底部导航上方。当前 Flutter 页面直接调用 `ScaffoldMessenger.showSnackBar`，样式和入口未统一。

## 方案

采用 Flutter shared UI helper 包装现有 `SnackBar`，不引入新的 overlay 系统：

- 新增 `apps/flutter-app/lib/shared/ui/toast.dart`。
- 定义通用文案常量：`genericFailureToastText`、`networkFailureToastText`。
- 定义 `kandoToastDuration = Duration(seconds: 2)`。
- 提供 `buildKandoToast(String message)`、`showKandoToast(BuildContext, {required String message})`、`showKandoFailureToast(BuildContext)`、`showKandoNetworkToast(BuildContext)`。
- `showKandoToast` 先隐藏当前 SnackBar，再展示新 Toast，避免连续轻提示堆叠。
- 现有 Home / Collection / Search 中的 coming-soon SnackBar 改为调用 shared Toast helper，保留原文案。

## 取舍

推荐方案是「shared SnackBar wrapper」。它满足当前 M4-7 的全局入口与文案统一要求，也保持 Flutter 原生 Scaffold / bottomNavigationBar 的行为，风险比自建 Overlay、全局 navigator key 或 Riverpod toast queue 更低。真正的队列、优先级、动画细节和跨异步业务失败接入可在后续具体操作失败场景中扩展。

## 范围

交付内容：

- Shared Toast helper 和 widget/unit 测试。
- Home / Collection / Search 直接 SnackBar 调用迁移到 shared helper。
- 覆盖通用失败、网络失败、coming-soon 自定义文案展示。

非目标：

- 不实现 M4-8 Scan Tab。
- 不接入真实后端失败流。
- 不改 Workers、schema、migration、wrangler、drizzle、admin-web 或 M7。
- 不修改 `docs/tcg-card/**`。

## 验收

- Toast helper 测试覆盖通用文案、网络文案、2 秒时长、floating behavior、替换当前 Toast。
- Home / Collection / Search widget 测试覆盖 coming-soon 操作仍显示统一 Toast。
- Focused Flutter tests、`dart run melos run test`、`flutter analyze`、format check 通过。
