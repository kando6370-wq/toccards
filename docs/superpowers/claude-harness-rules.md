# Claude Code Harness Rules

## 1. 目标

本项目的 Claude Code harness 规则服务于两个并行目标：

1. **快速开发模式**：尽量减少高频本地开发命令的权限打断，优先完成局部改动与局部验证。
2. **长期运行模式**：支持 `/loop`、持续推进、阶段性总结，但必须有明确的停机条件与验证门。

仓库默认使用中文输出；命令、代码、路径保留原文。

---

## 2. 双模式并存

### 2.1 快速开发模式

适用场景：
- 单包修复
- 局部功能开发
- 单测转绿
- 类型错误修复

要求：
- 每轮只推进一个最小增量
- 优先跑局部验证，不默认跑前后端联调
- 不主动触碰高契约面文件
- 优先复用现有实现与数据库结构

### 2.2 长期运行模式

适用场景：
- `/loop` 驱动的多轮实现-验证
- 按 `docs/superpowers/plans/*.md` 分阶段推进
- 长时间观察 build/test/dev server 状态

每个长期任务都必须先定义：
1. 循环目标
2. 作用域
3. 单轮动作
4. 单轮验证
5. 停机条件

推荐节奏：
- 每轮只做一个最小改动
- 每轮都要有局部验证
- 连续 2~3 轮无实质进展立即停
- 阶段结束后再跑较宽验证链

---

## 3. 数据库确认规则

- 原则上优先复用已有数据库结构、表、迁移与 D1 绑定。
- 以下任何动作都必须先通知用户并确认：
  - 新增表 / 列 / 索引 / 约束
  - 修改 `schema.ts`
  - 新增或改动 migration
  - 修改 D1 绑定或 `wrangler.toml`
  - 修改 `drizzle.config.ts`

高风险数据库文件：
- `apps/workers-api/src/db/schema.ts`
- `apps/workers-api/src/db/migrations/*`
- `apps/workers-api/wrangler.toml`
- `apps/workers-api/drizzle.config.ts`

---

## 4. 任务完成门

每次任务完成后，默认必须执行：

### 4.1 TS / Web / Workers 侧
- `pnpm build`
- `pnpm --filter @kando/workers-api test`
- `pnpm --filter @kando/auth-core test`
- 如涉及 admin-web，则补 `pnpm --filter @kando/admin-web build`

### 4.2 Dart / Flutter 侧
- `flutter pub get`
- `dart run melos run test`
- 需要时补 `flutter analyze`

### 4.3 关于联调与 App 打包
- 当前阶段**不要求每次任务完成都做前后端联调**。
- 当前阶段优先走 **Web/H5 风格验证** 和局部测试闭环。
- 完整 App 打包很慢，因此应作为后续统一阶段验证，而不是每轮任务的默认动作。

说明：
- 当前仓库并没有真正的 H5 客户端产物，但 `apps/admin-web` + Workers 本地验证可以承担“轻量 Web 验证”的角色。
- Flutter 侧暂时更适合用 `dart run melos run test` 与 `flutter analyze` 做日常验证，完整 App 打包与联调后置。

---

## 5. 执行状态文档

执行状态文档：
- `docs/superpowers/execution-status.md`

要求：
- 每次任务开始后更新一次
- 每次任务完成后更新一次
- 至少记录：状态、开始时间、完成时间、任务摘要
- 复杂任务还应补充：已完成事项、验证结果、剩余风险

默认由 hook 自动写入基础记录；交付前允许人工补充更完整总结。

---

## 6. 工具边界

### 用 `/loop`
适合：
- 改一点 -> 验一点 -> 再推进
- 局部修复或阶段性推进

### 用 Monitor
适合：
- 看日志
- 看 dev server 状态
- 看长任务状态变化

### 用后台 Bash
适合：
- 等 server ready
- 等 build / test 结束

### 不要用 Cron 做代码主循环
Cron 只适合墙钟周期检查，不适合作为代码实现的主推进方式。

---

## 7. 高风险 stop rules

一旦满足以下任一条件，默认应暂停并要求人工确认：

1. 要修改数据库结构或 migration
2. 要修改 `docs/tcg-card/**`
3. 要修改 `.gitlab-ci.yml`
4. 要修改 `wrangler.toml` / `drizzle.config.ts`
5. 需要 deploy / push / 远程资源变更
6. 连续 2~3 轮循环没有实质进展
7. 任务从局部修复扩大为跨包/跨层重构

---

## 8. 参考基线

- 仓库常用命令与架构：`CLAUDE.md`
- TS/Dart 标准验证链：`.gitlab-ci.yml`
- 工作区与依赖方向：`docs/tcg-card/02-architecture/monorepo.md`
- 计划驱动范式：`docs/superpowers/plans/*.md`
