# Codex 最小交接上下文（2026-07-07）

## 1. 当前阶段一句话

**M0 / M1 已完成，后续主线从 M2 数据代理层开始。**

## 2. 真源说明

### 规则真源
- `CLAUDE.md`
- `docs/superpowers/claude-harness-rules.md`

### 计划真源
- `docs/tcg-card/05-plan/dev-plan.md`

### 运行态覆盖层
- `docs/superpowers/execution-status.md`

明确约束：
- `dev-plan.md` 是**只读计划真源**。
- `execution-status.md` 只负责展示**当前运行态、状态覆盖层与执行日志**。
- `docs/superpowers/plans` 与 `docs/superpowers/specs` 已落库完成，可作为**历史设计参考**，但后续开发主线仍以 `dev-plan.md` 当前里程碑顺序为准。

## 3. 当前状态结论

基于 `docs/superpowers/execution-status.md` 当前内容：
- M0 工程基建：`completed`
- M1 鉴权与账号：`completed`
- M2 数据代理层：`not_started`
- M3 及之后：`not_started`

因此不要把仓库当前状态理解为“已经进入功能全面开发后期”；真实情况是：
- **工程底座已稳定**
- **账号鉴权闭环已完成**
- **数据代理、资产 CRUD、核心页面、后台、上线准备尚未启动**

## 4. 当前“已完成”的准确含义

### M0 已完成
表示 Monorepo、Workers、D1 schema、CI、依赖方向校验、执行状态 hook/文档这类工程底座已具备继续开发条件。

### M1 已完成
表示账号鉴权开发闭环已完成，当前最真实的实现集中在：
- Workers auth route modules
- D1 schema
- `packages/auth-core`
- Flutter auth shell

但这里的“完成”并不等于“生产上线已打通”。M1 里仍有明显的 **mock-first / 凭证待补** 边界：
- Apple / Google OAuth 真实凭证仍是 TBD
- 邮件服务真实提供商 / API Key 仍是 TBD
- 真正的上线接入收口在 **M8**，不是 M1

因此不要直接把当前仓库当作“已具备生产 OAuth / 邮件发送能力”的状态来推进。

## 5. 当前真实实现重心

当前仓库里最成熟、最能代表既有实现风格的部分是：
- `apps/workers-api/src/auth/*`
- `apps/workers-api/src/db/schema.ts`
- `packages/auth-core/src/*`
- `apps/flutter-app/lib/features/auth/auth_controller.dart`

同时要避免被以下内容误导：
- `apps/admin-web` 当前仍主要是 M0 占位骨架
- `packages/api-client` / `packages/ui-kit` / `packages/workers-common` 仍偏 placeholder / 未来扩展点

## 6. 下一步切入建议

### 默认接力点
**从 M2 数据代理层开始，不要跳去 M3 / M4 / M7。**

### M2 的推荐推进顺序
优先按 `dev-plan.md` 的既有顺序理解与拆分：
1. `M2-1 DataSourceAdapter 抽象层`
2. `M2-3 Workers KV 缓存层`
3. `M2-4 Cache API 缓存层`
4. `M2-8 接口端点注册`

### M2 的实现策略
- 优先 **mock / adapter-first**
- 先搭接口骨架、缓存骨架、降级骨架
- 不要一上来绑定真实第三方服务商
- 不要先扩 schema，先尽量复用现有契约推进
- 后端风格优先沿用现有 Workers auth 模块：**route module 内直接处理 request parsing、SQL/D1、response**，不要默认新建 repository layer

## 7. 高风险约束

以下改动默认先确认：
- `apps/workers-api/src/db/schema.ts`
- `apps/workers-api/src/db/migrations/*`
- `apps/workers-api/wrangler.toml`
- `apps/workers-api/drizzle.config.ts`
- `docs/tcg-card/**`

补充约束：
- 完成门默认遵循 `pnpm build` + 相关单测
- 不要把 `execution-status.md` 当计划真源
- 不要假设 placeholder package 已成熟可复用

## 8. 最小阅读清单

### 第一层：规则层（先读）
- `/Users/git/kando/toC/kando-global-project/CLAUDE.md`
- `/Users/git/kando/toC/kando-global-project/docs/superpowers/claude-harness-rules.md`

### 第二层：状态与计划层（再读）
- `/Users/git/kando/toC/kando-global-project/docs/superpowers/execution-status.md`
- `/Users/git/kando/toC/kando-global-project/docs/tcg-card/05-plan/dev-plan.md`

### 第三层：实现锚点层（最后读）
- `/Users/git/kando/toC/kando-global-project/apps/workers-api/src/index.ts`
- `/Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/anonymous.ts`
- `/Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/register.ts`
- `/Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/login.ts`
- `/Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/session.ts`
- `/Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/forgot-password.ts`
- `/Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/account.ts`
- `/Users/git/kando/toC/kando-global-project/apps/workers-api/src/db/schema.ts`
- `/Users/git/kando/toC/kando-global-project/packages/auth-core/src/index.ts`
- `/Users/git/kando/toC/kando-global-project/apps/flutter-app/lib/features/auth/auth_controller.dart`

可选补充测试锚点：
- `/Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/anonymous.test.ts`

## 9. 可直接发给 Codex 的交接模板

```text
请基于以下最小上下文继续开发，不要先全仓漫游：

1) 先读规则：
- /Users/git/kando/toC/kando-global-project/CLAUDE.md
- /Users/git/kando/toC/kando-global-project/docs/superpowers/claude-harness-rules.md

2) 再读当前状态与计划真源：
- /Users/git/kando/toC/kando-global-project/docs/superpowers/execution-status.md
- /Users/git/kando/toC/kando-global-project/docs/tcg-card/05-plan/dev-plan.md

关键信息先记住：
- M0/M1 已完成，M2+ 未开始
- dev-plan.md 是只读计划真源
- execution-status.md 只是运行态覆盖层
- docs/superpowers/plans 与 docs/superpowers/specs 内容都已完成，可作历史参考
- 当前最真实实现集中在 workers auth / schema / flutter auth shell

3) 再读当前实现锚点：
- /Users/git/kando/toC/kando-global-project/apps/workers-api/src/index.ts
- /Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/anonymous.ts
- /Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/register.ts
- /Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/login.ts
- /Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/session.ts
- /Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/forgot-password.ts
- /Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/account.ts
- /Users/git/kando/toC/kando-global-project/apps/workers-api/src/db/schema.ts
- /Users/git/kando/toC/kando-global-project/packages/auth-core/src/index.ts
- /Users/git/kando/toC/kando-global-project/apps/flutter-app/lib/features/auth/auth_controller.dart

可选补充：
- /Users/git/kando/toC/kando-global-project/apps/workers-api/src/auth/anonymous.test.ts

继续开发时请遵守：
- 默认从 M2 数据代理层开始，不要跳主线
- 不要把 execution-status 当计划真源
- 不要假设 packages/api-client / ui-kit / workers-common 已经成熟
- 非必要不要改 schema.ts / migrations / wrangler.toml / drizzle.config.ts
- 优先沿用现有 workers auth 的实现风格：route module 内直接处理 SQL、D1、response
- 若做 M2，先按 dev-plan 用 mock adapter / cache / 降级骨架推进，再接真实第三方
```

## 10. 当前可附带说明的验证状态

如需把当前代码可运行状态一起交接，可附带说明本轮已验证：
- `pnpm build`
- `pnpm --filter @kando/workers-api test`
- `pnpm --filter @kando/auth-core test`
