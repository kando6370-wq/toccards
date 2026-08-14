# Kando v1.1.0 文档信息架构设计

## 1. 目标与基线

- 工作范围：完整整理 `docs/releases/v1.1.0` 的实现类文档，并修正根导航与仓库说明。
- 当前代码基线：`dev@cea5d4e122c10b9a4e32a8699552288d13e9f57a`，已与 `github/dev` 纯快进同步。
- 冻结边界：`docs/releases/v1.0.0` 整体不得修改；`docs/releases/v1.1.0/00-product` 三份原始 PRD 不得修改。
- 实现事实权威顺序：当前代码与路由、Schema/迁移、运行配置、测试、带日期的远程证据、历史文档。
- 非目标：不修改业务代码、Schema、迁移、配置、测试和部署状态；不提交、不推送、不部署。

## 2. 设计原则

1. 版本目录继续沿用仓库现有 `docs/releases/vX.Y.Z` 规范，不另建平行文档体系。
2. `00-product` 只保存产品原件；实现事实进入 `01-flows` 至 `05-delivery`。
3. 当前运行架构与未来数据库方案分开：D1/KV/R2 是现状，PostgreSQL 与价格历史月度 JSON 是待决研究建议。
4. 代码完成、远程 dev 历史验证与发布验收分层描述；带日期的远程证据不得改写为当前实时状态。
5. 文档正文保持业务可读，关键结论使用仓库相对路径和符号作为证据，不把代码清单当作业务说明。
6. 原路径迁移保留 Git 历史；迁移后统一修复相对链接，禁止保留旧路径引用。

## 3. 目标目录

```text
README.md
docs/
  README.md
  releases/
    v1.0.0/                         # 完整冻结
    v1.1.0/
      README.md
      00-product/                   # 三份原始 PRD 冻结
      01-flows/
        requirements.md
        business-context.md
      02-architecture/
        architecture.md
        monorepo.md
        tech-stack.md
        decisions/README.md
      03-data-api/
        contract-changes.md
        entitlement-contract.md
        migration.md
        research/
          database-migration-research.md
          price-history-database-capacity-analysis.md
      04-admin/
        admin.md
      05-delivery/
        development-plan.md
        traceability-matrix.md
        app-store-connect-subscription-setup.md
```

## 4. 路径迁移

| 原路径（相对 `v1.1.0`） | 目标路径 |
|---|---|
| `requirements.md` | `01-flows/requirements.md` |
| `contract-changes.md` | `03-data-api/contract-changes.md` |
| `entitlement-contract.md` | `03-data-api/entitlement-contract.md` |
| `migration.md` | `03-data-api/migration.md` |
| `database-migration-research.md` | `03-data-api/research/database-migration-research.md` |
| `price-history-database-capacity-analysis.md` | `03-data-api/research/price-history-database-capacity-analysis.md` |
| `development-plan.md` | `05-delivery/development-plan.md` |
| `traceability-matrix.md` | `05-delivery/traceability-matrix.md` |
| `app-store-connect-subscription-setup.md` | `05-delivery/app-store-connect-subscription-setup.md` |

新增 `business-context.md`、三份当前架构文档、决策索引和 v1.1 Admin 实现文档。根 `README.md` 从 GitLab 模板改为项目入口，`docs/README.md` 和版本 `README.md` 作为唯一导航入口。

## 5. 内容边界

### 5.1 业务上下文

覆盖启动与身份、搜索与资产、扫描与额度、Premium 购买/恢复/生命周期、Performance、Admin 订单与通知、反馈和版本管理；角色区分游客、正式用户、当前 Apple 购买上下文、`operator`、`super_admin`。重要流程附代码证据并区分代码明确、推断和待确认。

### 5.2 架构

- 当前运行架构：Flutter App、React Admin、Marketing Web、Hono Worker、D1/KV/R2 与外部集成。
- v1.1 增量：`subscription-core`、Apple Notifications V2、session grant、Scan Quota、Performance、Billing Admin 和定时补偿。
- 工作区事实：pnpm 包含三个 Web/Worker App 与 `packages/*`；Dart workspace 包含 Flutter App 和 `dart-packages/subscription-core`。
- 工具链事实：Node `>=22`、pnpm `11.9.0`、Dart `^3.9.2`、Flutter App `>=3.44.0`；GitLab CI Flutter `3.44.0`，GitHub iOS CI `3.44.7`。

### 5.3 数据与交付

- 保留并重新归类现有契约、迁移和研究文档。
- `migration.md` 首段作为最新的带日期结论；早期远程状态明确标为历史检查点，避免同一文档出现无时间语义的冲突。
- 研究文档明确标识为候选决策，不将 PostgreSQL 推荐写成已实施架构。
- 交付文档继续区分仓库内代码证据、历史 dev 验证和外部发布验收。

## 6. 数据库影响

数据库影响为 `none`。本任务只移动和更新 Markdown/Agent 说明，不修改 Schema、迁移、查询、索引、数据、binding 或环境。现有迁移 `0000-0034` 仅作为文档证据。

## 7. 执行与 Review 策略

- 使用单代理连续执行。文档之间存在大量相对链接和共同导航，拆成多代理并行写入会增加冲突和事实漂移。
- 分三个连续任务：导航/架构、业务/Admin、数据/交付迁移与链接修复。
- 三个任务完成最窄验证后统一进入一个中风险 Review Batch，符合大任务按业务模块集中 Code Review 的规则。

## 8. 验收与验证

1. `git rev-parse HEAD:docs/releases/v1.0.0` 仍为 `3ad3141616d0c4c7f21429e56ce7c10f86236377`。
2. `git rev-parse HEAD:docs/releases/v1.1.0/00-product` 仍为 `c263648cb1a6e73f1f66501ebdbe73f01103150d`，并复核三份 PRD SHA-256。
3. 旧的 v1.1 根级实现文档路径全部消失，仓库 Markdown 不再引用旧路径。
4. 校验所有本地 Markdown 链接目标与标题锚点；外部链接只做语法检查，不声称网络可用。
5. 执行 `git diff --check`、Harness `doctor`、Runtime tests 和 `check --ci`。
6. Code Review 检查事实边界、冻结范围、链接、历史远程证据时态以及未授权业务改动。

## 9. 已知未决项

- Lifetime 本地缓存兜底最长时间仍是产品待决，文档不得代替产品设定。
- Android Premium 销售范围仍是产品待决；当前仅记录 Apple/iOS 已激活边界。
- PostgreSQL 供应商、价格历史最终物理模型和采购规格尚未批准。
- Apple 生产配置、Sandbox/TestFlight、真机、多设备、重度数据与真实订单规模验收不在本次文档整理中执行。
