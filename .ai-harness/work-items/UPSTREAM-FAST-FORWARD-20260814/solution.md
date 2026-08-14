# 上游纯快进范围说明

## 事实

- 用户已明确授权 `dev` 纯快进。
- `d7545e7` 是 `9591022` 的祖先，`dev` 与 `github/dev` 当前均为 `9591022ac55e8cc0726b59ccfb689dfa73b4d69c`。
- 快进只纳入 `cea5d4e` 与 `9591022`，没有 merge commit、rebase、强制更新或本地内容重写。

## 上游提交范围

`cea5d4e` 修改 Scan UI、资源、Golden、测试和当时的 v1.1 开发计划；`9591022` 只更新 Flutter 构建版本。精确路径如下：

- `apps/flutter-app/assets/scan/pro_badge.svg`
- `apps/flutter-app/lib/features/scan/scan_page.dart`
- `apps/flutter-app/pubspec.yaml`
- `apps/flutter-app/test/widget/goldens/rendered/figma_scan_before_328_10858_390x844.png`
- `apps/flutter-app/test/widget/goldens/rendered/figma_scan_recognizing_continuous_390x844.png`
- `apps/flutter-app/test/widget/goldens/rendered/figma_scan_revealing_continuous_390x844.png`
- `apps/flutter-app/test/widget/goldens/rendered/figma_scan_scanning_131_19516_390x844.png`
- `apps/flutter-app/test/widget/scan_page_test.dart`
- `docs/releases/v1.1.0/development-plan.md`

## 处理方式

本工作项只让 Harness 把上述已授权上游提交与文档重整写入范围分开归属。验证提交祖先关系、远程一致性和提交路径清单，并确认 8 个 App 路径在工作树中未被改写；旧开发计划路径的后续归类由文档重整工作项管理。不重新实现、修改、部署或发布上游业务内容。该操作不影响数据库 Schema、迁移、查询、索引、数据或环境。
