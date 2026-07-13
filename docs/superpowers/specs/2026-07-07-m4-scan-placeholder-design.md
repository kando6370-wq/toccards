# M4-8 Scan Tab 占位页设计

日期：2026-07-07

## 背景

M4-8 对应 `docs/tcg-card/05-plan/dev-plan.md` 的「Scan Tab 占位页」。`scan.md` 明确 v1.0 不实现真实扫描识别，只保留底部导航 Scan Tab，点击后展示占位引导页，并提供跳转 Search 的按钮。`overview.md §5` 给出默认标题「扫描功能即将上线」，该文案仍标记待最终确认；本实现采用该默认文案，不修改 `docs/tcg-card/**`。

## 方案

采用最小 Flutter 页面接入：

- 新增 `apps/flutter-app/lib/features/scan/scan_page.dart`。
- 新增 `/scan` 路由。
- Home / Collection / Search 底部导航点击 Scan 后进入 `/scan`，不再展示 coming-soon Toast。
- Scan 页面底部导航选中第三个 Tab，并可跳转 Home、Collection、Search、Profile。
- Scan 页面展示标题 `扫描功能即将上线`、说明文案和 `Search Cards` 按钮；按钮跳转 `/search`。
- 不请求相机权限，不打开相机，不实现拍摄、识别、批量扫描或结果确认。

## 取舍

推荐方案是「独立占位页 + 路由接入」。它比继续用 Toast 更符合 PRD，也避免把 Future 扫描流程提前设计进当前代码。按钮和底部导航都复用现有 GoRouter 导航模式，后续真扫描实现可直接替换 `ScanPage` 主体，不需要改 Home / Collection / Search 的入口。

## 范围

交付内容：

- Scan 占位页。
- `/scan` 路由。
- Home / Collection / Search 底部 Scan Tab 跳转到 Scan 页面。
- Scan 页面跳转 Search 的引导按钮。

非目标：

- 不实现真实扫描、相机权限、相机预览、闪光灯、识别、批量扫描、Review Your Matches。
- 不改 Workers、schema、migration、wrangler、drizzle、admin-web 或 M7。
- 不修改 `docs/tcg-card/**`。

## 验收

- Scan 页面 widget 测试覆盖占位文案、Search 按钮跳转、底部导航跳转。
- Home / Collection / Search widget 测试覆盖底部 Scan Tab 进入占位页。
- Focused Flutter tests、`dart run melos run test`、`flutter analyze`、format check 通过。
