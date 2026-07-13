# M0 完整基线核验设计
> 状态：已获用户批准，待执行计划拆分
> 日期：2026-07-01
> 类型：M0 工程基线核验设计

## 1. 背景与目标

当前项目是 TCG Card v1.0 monorepo，已完成多项 M0 工程基建提交，最近提交集中在 Flutter app、Admin Web、Dart workspace、GitLab CI、Workers API 与依赖方向 lint。

本次任务不是开发新功能，而是在进入 M1 鉴权与账号开发前，对 M0 工程基线做完整核验。目标是确认当前工程结构、脚本、CI、本地开发入口和 Workers API 基础条件是否足够稳定，可以作为 M1 的起点。

当前工作区存在用户确认保留的未提交改动：

- `apps/workers-api/package.json`
- `pnpm-lock.yaml`
- `pnpm-workspace.yaml`
- `.claude/`

核验过程必须保留这些改动，不回滚、不覆盖。

## 2. 成功标准

核验完成后必须给出明确结论：

- `可进入 M1`
- `可进入 M1 但有风险项`
- `不建议进入 M1`

结论必须基于实际检查或命令输出。若某项因环境、依赖、权限或外部服务缺失无法核验，必须显式说明，不能把跳过项描述为通过。

最低验收条件：

- TS 侧本地核验通过，或明确记录阻塞原因。
- Dart/Flutter 侧本地核验通过，或明确记录环境/代码阻塞原因。
- CI 命令与本地可执行脚本一致。
- 当前未提交改动被保留。
- 只修改核验所需的小范围配置或脚本问题。

## 3. 核验范围

M0 完整基线核验覆盖七层。

### 3.1 工作区状态

记录当前未提交改动，区分用户已有改动与本次核验产生的改动。不回滚用户改动，不清理 `.claude/`，不做无关格式化。

### 3.2 包管理

检查顶层 `package.json`、`pnpm-workspace.yaml`、`pnpm-lock.yaml` 与实际包目录是否一致，确认 workspace 包能被 pnpm 正确识别。

### 3.3 TS monorepo

验证 TS 侧脚本能覆盖：

- `apps/admin-web`
- `apps/workers-api`
- `packages/api-client`
- `packages/auth-core`
- `packages/ui-kit`
- `packages/workers-common`

重点确认 `pnpm`、Turborepo、各包脚本和 TypeScript 配置之间没有断裂。

### 3.4 Dart/Flutter workspace

验证顶层 Dart workspace、Melos 配置、`apps/flutter-app` 的 analyze/test/build 入口是否可用。优先使用项目已有脚本，不额外引入工具链。

### 3.5 依赖方向

确认 `apps -> packages` 的单向依赖规则仍能被 lint 或脚本表达。若当前规则只覆盖 TS 侧或 Dart 侧，需要明确说明覆盖边界。

### 3.6 Workers API

确认 `apps/workers-api` 具备本地启动与基础路由健康检查条件。核验重点是 M0 工程可启动性，不包含 M1 鉴权接口实现。

### 3.7 CI 对齐

检查 `.gitlab-ci.yml` 中的 TS 与 Dart job 命令是否能在本地找到对应脚本或等价命令，避免 CI 表达与本地开发入口不一致。

## 4. 明确不包含

本次核验不包含：

- M1 鉴权接口实现。
- D1 业务 schema 扩展。
- Flutter Auth UI。
- OAuth/邮件服务真实接入。
- 第三方卡牌数据源接入。
- 大范围目录迁移、工具链替换或架构重构。

## 5. 执行策略

执行顺序保持由轻到重：

1. 先阅读配置和脚本：`package.json`、workspace 配置、Turborepo 配置、CI、Dart/Melos 配置、Workers 配置。
2. 再运行本地核验命令：优先使用项目已有脚本；没有脚本时只做最小命令验证。
3. 对失败项做分类，而不是立即扩大修改范围。
4. 每修一个小问题就复验相关命令。
5. 最后输出 M0 基线结论和剩余风险项。

## 6. 修复策略

允许直接修复的小问题：

- 脚本命令缺失或名称与 CI 不一致。
- workspace 包未纳入。
- CI 命令与本地脚本不一致。
- 明显依赖声明遗漏。
- 低风险配置错误，且修复范围局限在相关配置文件内。

必须暂停确认的大问题：

- 架构边界变化。
- 包拆分或目录结构调整。
- 替换 pnpm、Turborepo、Melos、Flutter 或 Workers 工具链。
- 引入新框架。
- 大范围重构或格式化。
- 需要真实外部服务凭证的验证。

## 7. 预期产出

核验执行完成后应产出：

- 已运行命令及结果摘要。
- 如有修复，列出修改文件与原因。
- 未验证项与原因。
- M0 是否可进入 M1 的明确判断。
- 若存在风险项，给出下一步建议。

## 8. 后续衔接

本设计经用户审阅通过后，下一步应使用 `superpowers:writing-plans` 生成执行计划。执行计划应把核验拆成可逐步验证的任务，并在每个关键命令后设置检查点。
