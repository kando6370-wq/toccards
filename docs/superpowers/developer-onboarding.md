# Developer Onboarding for Claude Harness

## 1. 先看什么

新开发人员接手这个仓库时，先按下面顺序阅读：

1. `CLAUDE.md`
2. `docs/superpowers/claude-harness-rules.md`
3. `docs/superpowers/execution-status.md`
4. `docs/tcg-card/README.md`

含义：
- `CLAUDE.md`：仓库级工作准则、常用命令、架构边界
- `claude-harness-rules.md`：Claude Code 的快速开发 / 长期任务规则
- `execution-status.md`：当前任务推进状态
- `docs/tcg-card/README.md`：产品与架构文档入口

---

## 2. 这个仓库的基本工作方式

本仓库不是“自由发挥式开发”，而是：

- 文档驱动
- 计划驱动
- 分步验证
- 保守改动
- 中文输出

特别注意：
- 根 `README.md` 不是实现真相源
- 真正的产品/架构依据在 `docs/tcg-card/`
- `apps -> packages` 是单向依赖
- `apps/workers-api/src/db/schema.ts` 与 `docs/tcg-card/**` 属于高契约面文件

---

## 3. 开发时先遵守的几条硬规则

### 3.1 数据库规则

原则上优先复用已有数据库结构。

以下改动必须先确认：
- 新增/修改表、列、索引、约束
- 修改 migration
- 修改 `schema.ts`
- 修改 D1 / Wrangler / Drizzle 相关配置

关键文件：
- `apps/workers-api/src/db/schema.ts`
- `apps/workers-api/src/db/migrations/*`
- `apps/workers-api/wrangler.toml`
- `apps/workers-api/drizzle.config.ts`

### 3.2 任务完成规则

每次任务完成后，默认要执行：
- `pnpm build`
- `pnpm --filter @kando/workers-api test`
- `pnpm --filter @kando/auth-core test`
- 涉及 admin-web 时补 `pnpm --filter @kando/admin-web build`

Flutter 侧：
- 当前环境如果有 `flutter`，会补 `flutter pub get` 与 `dart run melos run test`
- 如果没有 `flutter`，脚本会跳过，不应伪称 Flutter 已验证通过

### 3.3 状态文档规则

每次任务开始与完成，都要更新：
- `docs/superpowers/execution-status.md`

当前已接入 hook 自动写基础状态，但复杂任务在交付前仍要人工补充总结。

---

## 4. 推荐开发模式

### 快速开发模式
适合：
- 单包修复
- 小功能开发
- 单测转绿
- 局部类型修复

做法：
- 每轮只动一小块
- 每轮只跑局部验证
- 不默认做前后端联调
- 不默认做完整 App 打包

### 长期任务模式
适合：
- `/loop` 持续推进
- 多轮实现-验证
- 按计划文档推进

要求：
- 每轮都必须有目标
- 每轮都必须有验证
- 连续 2~3 轮无进展就停
- 触碰高契约面就停下确认

---

## 5. 为什么当前优先 Web/H5 风格验证

当前仓库里，完整 App 打包与前后端联调成本比较高，日常开发不适合作为默认门槛。

因此当前建议是：
- 平时优先使用 `admin-web + workers-api` 做轻量 Web 风格验证
- Flutter 侧优先用 `dart run melos run test` / `flutter analyze`
- 真正完整的 App 打包与联调后置到阶段收口

这不是说 Flutter 不重要，而是把“慢验证”从“每轮任务”移动到“阶段里程碑”。

---

## 6. 你最常用的入口

### TS / Workers / Admin Web
- `pnpm build`
- `pnpm type-check`
- `pnpm lint`
- `pnpm --filter @kando/workers-api test -- src/auth/anonymous.test.ts`
- `pnpm --filter @kando/workers-api dev`
- `pnpm --filter @kando/admin-web dev`

### Flutter / Dart
- `flutter pub get`
- `dart run melos run analyze`
- `dart run melos run test`
- `cd apps/flutter-app && flutter analyze`
- `cd apps/flutter-app && flutter run`

---

## 7. 交付前自检

在说“完成”之前，至少确认：

1. 是否碰了数据库相关文件？如果碰了，是否已确认？
2. 是否跑过 build？
3. 是否跑过自动化单测？
4. 如果 Flutter 未验证，是否明确说明“因环境缺少 flutter 被跳过”？
5. 是否更新了 `docs/superpowers/execution-status.md`？
6. 是否说明了未做前后端联调？

---

## 8. 交接给下一个人时怎么说

推荐交接话术：

> 先读 `CLAUDE.md` 和 `docs/superpowers/claude-harness-rules.md`。数据库相关改动必须先确认。每次任务完成后默认要执行 build + unit test。当前阶段优先走 Web/H5 风格轻验证，不要求每轮都做完整 App 打包与联调。任务状态记录在 `docs/superpowers/execution-status.md`。
