# Codex 最小交接上下文（2026-07-08，M7 管理后台收口）

## 1. 当前阶段一句话

**`codex/m7-admin` 已完成 M7 管理后台（M7-1 至 M7-7）收口并通过本轮验证；此前 2026-07-07 交接中“M7 未启动”的结论已被本分支状态覆盖。**

## 2. 真源说明

### 规则真源
- `CLAUDE.md`
- `docs/superpowers/claude-harness-rules.md`

### 计划真源
- `docs/tcg-card/05-plan/dev-plan.md`

### 运行态覆盖层
- `docs/superpowers/execution-status.md`

明确约束：
- `dev-plan.md` 是只读计划真源。
- `execution-status.md` 负责展示当前执行态、状态覆盖层与执行日志。
- 本文件是交接快照，不替代计划或状态真源。

## 3. 当前状态结论

基于 `docs/superpowers/execution-status.md` 当前内容：
- M0 工程基建：`completed`
- M1 鉴权与账号：`completed`
- M2 数据代理层：`in_progress`，已完成 7 / 8，`M2-2` 仍为 `todo`
- M3 核心资产 CRUD：`completed`
- M4 三大页面：`completed`
- M5 卡牌详情：`in_progress`，已完成 3 / 5，`M5-4` 进行中
- M6 Profile / 客服 / 启动引导：`not_started`
- M7 管理后台：`completed`
- M8 iOS 联调 / 上线准备：`not_started`

不要把本分支理解为全项目上线完成；M7 后台已收口，但 M2-2、M5 后续、M6、M8 仍需独立推进。

## 4. M7 本轮完成范围

Workers API：
- Admin 登录、刷新、登出接口
- Admin access token 与 app token 隔离
- Admin session 校验中间件
- 用户列表、详情、禁用
- 反馈工单列表、详情、状态流转
- 运营配置读取与更新
- Trending pin 创建、更新、删除
- card override 列表、创建、更新、删除、补图
- D1 管理员初始化脚本：`pnpm --filter @kando/workers-api admin:init -- --email admin@example.com --password <password> [--local] [--execute]`

Admin Web：
- 登录页与 session 持久化
- 后台布局、侧边菜单和退出
- 用户管理、反馈工单、运营配置、Trending Pin、卡牌覆盖模块页面

## 5. 关键约束与冲突说明

- 本分支没有改 `apps/workers-api/src/db/schema.ts`、`apps/workers-api/src/db/migrations/*`、`wrangler.toml` 或 `drizzle.config.ts`。
- M7 复用既有 D1 表：`admin_user`、`session`、`user`、`anonymous_account`、`feedback_ticket`、`app_config`、`trending_pin`、`card_override`。
- 不要假设生产管理员账号已存在；需要用 `admin:init` 生成或执行初始化 SQL。
- 与 `m2-data-adapter` 当前 HEAD（`66e73e3`）的三方 merge 检查已通过：`apps/workers-api/src/index.ts` 和 `docs/superpowers/execution-status.md` 均可自动合并。
- 为避免 `execution-status.md` 在多 worktree 并行推进时抢写“当前任务”，本分支保留 m2 最新的 `M5-4` 当前任务状态，同时在 M7 子任务覆盖层和日志中记录 M7 完成。
- 后续若多个 worktree 再次同时更新 `execution-status.md`，仍需以最新真实任务状态为准，避免静默覆盖另一分支的当前任务。

## 6. 最小阅读清单

### 规则与状态
- `CLAUDE.md`
- `docs/superpowers/claude-harness-rules.md`
- `docs/superpowers/execution-status.md`
- `docs/tcg-card/05-plan/dev-plan.md`

### M7 实现锚点
- `apps/workers-api/src/admin/routes.ts`
- `apps/workers-api/src/admin/routes.test.ts`
- `apps/workers-api/src/index.ts`
- `apps/workers-api/scripts/create-admin.mjs`
- `apps/admin-web/src/App.tsx`
- `packages/auth-core/src/index.ts`

## 7. 继续推进建议

- 若继续处理 M7，先从 review、联调和合并准备开始，不要再扩后台新模块。
- 若接回 M2，请进入 `m2-data-adapter` worktree 单独检查；当前 M7 与 m2 的 merge-tree 已验证无冲突。
- 完成门仍遵循 `pnpm build` + 相关单测；涉及 admin-web 时补 `pnpm --filter @kando/admin-web build`。

## 8. 本轮验证记录

本轮已验证：
- `pnpm --filter @kando/workers-api test`
- `pnpm --filter @kando/auth-core test`
- `pnpm --filter @kando/admin-web build`
- `pnpm build`
