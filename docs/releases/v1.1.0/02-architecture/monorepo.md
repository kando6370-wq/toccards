# v1.1.0 Monorepo 边界

## 1. 工作区

| 路径 | 职责 | 工作区 |
|---|---|---|
| `apps/flutter-app` | iOS、Android、Web 客户端 | Dart workspace |
| `dart-packages/subscription-core` | 订阅购买/Restore 业务模块 | Dart workspace |
| `apps/workers-api` | 共享 Hono API、PostgreSQL 访问层与 migrations、Cloudflare/Linux 运行入口 | pnpm workspace |
| `apps/admin-web` | React Admin SPA | pnpm workspace |
| `apps/marketing-web` | 营销与法律站点 | pnpm workspace |
| `packages/auth-core` | 共享认证与密码能力 | pnpm workspace |
| `packages/api-client` | TypeScript API 客户端边界 | pnpm workspace |
| `packages/ui-kit` | TypeScript UI 共享边界 | pnpm workspace |
| `packages/workers-common` | Workers 通用能力 | pnpm workspace |

根 `pnpm-workspace.yaml` 管理 `packages/*` 和三个 TypeScript 应用。根 `pubspec.yaml` 管理 Flutter App 与 `subscription-core`，Melos 8 配置也位于该文件。

`deploy/linux/` 保存 Linux 测试环境的 Compose、离线镜像与发布脚本，不是独立 workspace 包。`src/app.ts` 组合共用路由；`src/index.ts` 适配 Cloudflare，`src/linux/server.ts` 适配 Node。

## 2. 依赖方向

```text
apps/* ----------------> packages/*
apps/flutter-app ------> dart-packages/subscription-core
packages/* ------------X apps/*
Flutter <---- HTTP ----> API (Cloudflare / Linux)
```

`scripts/check-dep-direction.mjs` 强制 TypeScript 共享包不得反向依赖应用。Flutter 与 Workers 通过 HTTP/JSON 契约协作，不建立跨语言源码依赖。

## 3. 变更归属

| 变更类型 | 首选位置 |
|---|---|
| Flutter 页面、状态、平台桥接 | `apps/flutter-app/lib/` 及平台目录 |
| 通用订阅商品/购买/Restore | `dart-packages/subscription-core/` |
| API、鉴权、业务事务和外部服务 | `apps/workers-api/src/` |
| Linux 运行适配与部署 | `apps/workers-api/src/linux/`、`deploy/linux/`；共用路由与 PostgreSQL migration |
| Schema 与迁移 | `apps/workers-api/src/db/postgres/migrations/`；后续数据库变更只允许新增 PostgreSQL 向前迁移 |
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
| Linux API 与 Admin 构建 | `pnpm --filter @kando/workers-api build:linux` |
| Dart/Flutter 分析 | `dart run melos run analyze` |
| Dart/Flutter 测试 | `dart run melos run test` |

`.dart_tool`、`node_modules`、`.turbo`、`.wrangler`、构建产物和本地缓存不是业务源文件。业务事实审计应搜索受版本控制的源码、配置、迁移和测试。

## 5. CI 边界

- GitLab CI 使用 Node 22 与 Flutter 3.44.0，执行 TypeScript build/type-check/lint 及 Dart workspace analyze/test。
- GitHub iOS workflow 使用 Flutter 3.44.7，在 `macos-15` 执行 CocoaPods/Fastlane 配置检查和 unsigned iOS release build。`push` 仅监听 dev 的相关路径，另支持相关路径的 `pull_request` 与手动 `workflow_dispatch`；main 的 push 事件不在该工作流触发范围内。
- 两条流水线版本不同；变更工具链时必须明确目标流水线并同步相关约束，不能把其中一条的通过外推为另一条已通过。
- GitHub Linux workflow 使用 Node 22，仅 `workflow_dispatch` 手动触发，构建后由 `toccards-kd201` 自托管 Runner 发布。现有自动路径是服务器每两分钟监听 `dev`；路径筛选、失败冷却和应用回滚见[自动部署手册](../05-delivery/linux-test-auto-deployment.md)，不得同时启用两种发布路径。

证据：`package.json`、`pnpm-workspace.yaml`、根 `pubspec.yaml`、`.gitlab-ci.yml`、`.github/workflows/ios-build.yml`、`.github/workflows/linux-test-deploy.yml`、`deploy/linux/ci/watch-branch.sh`。
