# Codex 最小交接上下文（2026-07-08，dev 合并后）

## 1. 当前接力点

**当前 worktree：`D:\Projects\kando-global-project`。**

**当前分支：`dev`。**

本次已将 `codex/m2-data-adapter` 与 `codex/m7-admin` 合入 `dev`。合并后的状态结论：

- M2 数据代理层：`in_progress`，7 / 8，`M2-2` 仍为 `todo`
- M4 三大页面：`completed`，8 / 8
- M5 卡牌详情：`completed`，5 / 5
- M6 Profile / 客服 / 启动引导：`completed`，6 / 6
- M7 管理后台：`completed`，7 / 7
- M8 iOS 联调 / 上线准备：`not_started`

不要再沿用旧交接中“M7 未启动”或“从 M6-2 继续”的结论；这些已被合并后的 `execution-status.md` 覆盖。

## 2. 真源说明

### 规则真源

- `CLAUDE.md`
- `docs/superpowers/claude-harness-rules.md`
- 本仓库 AGENTS 规则：始终简体中文、先思后码、外科手术式修改、TDD、关键步骤检查点、显式失败

### 计划真源

- `docs/tcg-card/05-plan/dev-plan.md`

### 运行态覆盖层

- `docs/superpowers/execution-status.md`

明确约束：

- `dev-plan.md` 是只读计划真源。
- `execution-status.md` 展示当前运行态、状态覆盖层与执行日志。
- `docs/superpowers/plans` 与 `docs/superpowers/specs` 只作为历史设计和实施参考。

## 3. 本轮合入范围

### m2-data-adapter

已合入：

- M4 Home / Collection / Search / Scan / Toast / 加载失败空状态 / 汇率展示 / 涨跌算法
- M5 CardDetail 未加入态、已加入态、Price Tab、Collection Item 增删改、价格降级展示
- M6 Profile 游客态、登录态、客服反馈、启动引导、删除账号流程、订阅内容隐藏
- Workers data-source / portfolio 相关 API 与测试
- portfolio 测试夹具 session 过期时间修正：`dfba486 test: keep portfolio auth sessions valid`

### m7-admin

已合入：

- Admin 登录、刷新、登出接口
- Admin access token 与 app token 隔离
- Admin session 校验中间件
- 用户管理、反馈工单、运营配置、Trending Pin、卡牌覆盖模块
- D1 管理员初始化脚本：`pnpm --filter @kando/workers-api admin:init -- --email admin@example.com --password <password> [--local] [--execute]`
- Admin Web 登录页、后台布局、侧边菜单、退出与各管理页面

## 4. 后续建议

推荐下一步优先级：

1. 处理 M2-2 第三方厂商适配实现。
2. 开始 M8 iOS 联调 / 上线准备。
3. 对合并后的 M7 后台做人工 review 与联调，不再扩新后台模块。

继续开发前至少阅读：

- `docs/superpowers/execution-status.md`
- `docs/tcg-card/05-plan/dev-plan.md`
- 与目标模块相邻的实现和测试

## 5. 高风险约束

以下路径仍需谨慎，除非当前任务明确要求：

- `docs/tcg-card/**`
- `apps/workers-api/src/db/schema.ts`
- `apps/workers-api/src/db/migrations/*`
- `apps/workers-api/wrangler.toml`
- `apps/workers-api/drizzle.config.ts`

保持：

- 非琐碎改动必须 TDD：先写失败测试，确认失败，再实现。
- Flutter tests 不要并发跑。
- 每个阶段完成后验证、提交、推送。
- 多 worktree 并行时，`execution-status.md` 以最新真实任务状态为准，避免静默覆盖另一分支进度。
