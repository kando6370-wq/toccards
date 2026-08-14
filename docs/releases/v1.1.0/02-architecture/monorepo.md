# v1.1.0 Monorepo 边界

## 1. 工作区

| 路径 | 职责 | 工作区 |
|---|---|---|
| `apps/flutter-app` | iOS、Android、Web 客户端 | Dart workspace |
| `dart-packages/subscription-core` | 订阅购买/Restore 业务模块 | Dart workspace |
| `apps/workers-api` | Hono API、D1 Schema/迁移和部署入口 | pnpm workspace |
| `apps/admin-web` | React Admin SPA | pnpm workspace |
| `apps/marketing-web` | 营销与法律站点 | pnpm workspace |
| `packages/auth-core` | 共享认证与密码能力 | pnpm workspace |
| `packages/api-client` | TypeScript API 客户端边界 | pnpm workspace |
| `packages/ui-kit` | TypeScript UI 共享边界 | pnpm workspace |
| `packages/workers-common` | Workers 通用能力 | pnpm workspace |

根 `pnpm-workspace.yaml` 管理 `packages/*` 和三个 TypeScript 应用。根 `pubspec.yaml` 管理 Flutter App 与 `subscription-core`，Melos 8 配置也位于该文件。

## 2. 依赖方向

```text
apps/* ----------------> packages/*
apps/flutter-app ------> dart-packages/subscription-core
packages/* ------------X apps/*
Flutter <---- HTTP ----> Workers
```

`scripts/check-dep-direction.mjs` 强制 TypeScript 共享包不得反向依赖应用。Flutter 与 Workers 通过 HTTP/JSON 契约协作，不建立跨语言源码依赖。

## 3. 变更归属

| 变更类型 | 首选位置 |
|---|---|
| Flutter 页面、状态、平台桥接 | `apps/flutter-app/lib/` 及平台目录 |
| 通用订阅商品/购买/Restore | `dart-packages/subscription-core/` |
| API、鉴权、业务事务和外部服务 | `apps/workers-api/src/` |
| Schema 与迁移 | `src/db/schema.ts` + 新的顺序 SQL migration |
| Admin 页面 | `apps/admin-web/src/`；服务端授权仍在 Workers |
| 营销与法律内容 | `apps/marketing-web/` |
| 实际跨应用复用的 TS 能力 | `packages/*` |

不要为单一调用提前创建共享包，也不要在 App 内复制服务端授权规则。

## 4. 构建与验证

| 范围 | 命令 |
|---|---|
| TypeScript 全仓构建 | `pnpm build` |
| TypeScript 类型 | `pnpm type-check` |
| 依赖方向 | `pnpm lint` |
| Workers 测试 | `pnpm --filter @kando/workers-api test` |
| Admin 测试 | `pnpm --filter @kando/admin-web test` |
| Dart/Flutter 分析 | `dart run melos run analyze` |
| Dart/Flutter 测试 | `dart run melos run test` |

`.dart_tool`、`node_modules`、`.turbo`、`.wrangler`、构建产物和本地缓存不是业务源文件。业务事实审计应搜索受版本控制的源码、配置、迁移和测试。

## 5. CI 边界

- GitLab CI 使用 Node 22 与 Flutter 3.44.0，执行 TypeScript build/type-check/lint 及 Dart workspace analyze/test。
- GitHub iOS workflow 使用 Flutter 3.44.7，在 `macos-15` 执行 CocoaPods/Fastlane 配置检查和 unsigned iOS release build。
- 两条流水线版本不同；变更工具链时必须明确目标流水线并同步相关约束，不能把其中一条的通过外推为另一条已通过。

证据：`package.json`、`pnpm-workspace.yaml`、根 `pubspec.yaml`、`.gitlab-ci.yml`、`.github/workflows/ios-build.yml`。
