# v1.0.0 Monorepo 边界

## 目录职责

| 路径 | 职责 | 工作区 |
|---|---|---|
| `apps/flutter-app` | iOS/Android/Web 客户端 | Dart workspace |
| `apps/workers-api` | Hono API、D1 schema/迁移、Worker 部署入口 | pnpm workspace |
| `apps/admin-web` | React 管理后台 | pnpm workspace |
| `apps/marketing-web` | 营销/法律 Web 应用 | pnpm workspace |
| `packages/auth-core` | 共享认证与密码学能力 | pnpm workspace |
| `packages/api-client` | TypeScript API 客户端边界 | pnpm workspace |
| `packages/ui-kit` | TypeScript UI 共享边界 | pnpm workspace |
| `packages/workers-common` | Workers 通用能力 | pnpm workspace |

根 `pnpm-workspace.yaml` 纳入 `packages/*`、Admin、Marketing 和 Workers。根 Dart `pubspec.yaml` 的 workspace 仅纳入 `apps/flutter-app`；仓库中未注册的 Dart 目录不属于 v1.0.0 正式工作区。

## 依赖方向

```text
apps/* -> packages/*
packages/* -X-> apps/*
```

`scripts/check-dep-direction.mjs` 扫描 package manifest，禁止共享包依赖任何应用包。Flutter 与 TypeScript 之间通过 HTTP 契约协作，不建立源码依赖。

## 变更归属

- 移动端交互和状态：`apps/flutter-app/lib/features/`。
- HTTP 路由与授权：`apps/workers-api/src/`。
- 数据结构：同步修改 `src/db/schema.ts` 和新的顺序 SQL 迁移。
- Admin 页面：`apps/admin-web/src/`；接口仍由 Workers 提供。
- 跨应用确定性逻辑：只有实际复用时才放入 `packages/`。

## 常用验证

| 范围 | 命令 |
|---|---|
| 依赖方向 | `pnpm lint` |
| TypeScript 类型 | `pnpm type-check` |
| Workers | `pnpm --filter @kando/workers-api test` |
| Admin | `pnpm --filter @kando/admin-web test` |
| Flutter 分析 | `dart run melos run analyze` |
| Flutter 测试 | `dart run melos run test` |

证据：`package.json`、`pnpm-workspace.yaml`、根 `pubspec.yaml`、`scripts/check-dep-direction.mjs`。
