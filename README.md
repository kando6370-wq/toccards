# Kando Global Project

Kando 是 Card AI 的 monorepo，包含 Flutter 客户端、Cloudflare Workers API、React 管理后台、营销站点及共享包。产品主线是卡牌搜索、扫描识别、收藏与估值；v1.1 在此基础上增加 Apple 订阅、Premium 权益、服务端扫描额度、Performance 和订单/通知后台。

当前 main 已合入 `dev@2d94c80`（2026-09-10）；Flutter 客户端版本为 `1.0.2+135`，以 `apps/flutter-app/pubspec.yaml` 为准。`docs/releases/v1.1.0` 是产品迭代文档目录，不代表安装包版本或商店发布状态。

## 系统概览

```text
Flutter App ------------+
                         +--> Cloudflare Workers (`/api/v1`)
React Admin -- assets ---+        |-- PlanetScale PostgreSQL（经 Hyperdrive）: 业务与目录真源
                                  |-- KV: 可重建缓存
                                  |-- R2: 受保护的扫描卡面图片
                                  |-- recognize-vec: Service Binding 向量检索
                                  +-- OAuth、邮件、汇率和 Apple 服务

Marketing Web -----------------> 独立 Cloudflare 静态站点
```

共享 Hono API 是 App 与 Admin 的服务端安全边界，路由组合位于 `apps/workers-api/src/app.ts`，Cloudflare 入口为 `src/index.ts`。客户端不得直连数据库或对象存储；Cloudflare 环境的 Admin 构建产物由 Workers assets 托管，营销站点独立部署。Cloudflare 测试环境 dev/test 与正式环境 prod 均已完成 PostgreSQL 迁移，D1 已废弃；2026-09-09 用户确认与 Cloudflare 回读一致，两环境均绑定同一个 PlanetScale PostgreSQL/Hyperdrive，回读版本均无 D1 binding。运行环境、Apple 配置、KV、R2、域名和 secrets 继续隔离。后续数据库变更仅涉及 PostgreSQL schema 和业务数据修复，见 [数据迁移](docs/releases/v1.1.0/03-data-api/migration.md)，不再安排 D1 移库任务。

`dev` 已合入 Linux 测试入口 `src/linux/server.ts`，复用同一 Hono 应用与 PostgreSQL migration，使用独立 PostgreSQL、进程内 KV 和本地图片卷；Admin 由 Caddy 托管，离线模式使用 Node 静态服务。Linux 尚未提供向量识别适配器，扫描不可用；架构与兼容缺口见 [Linux 测试环境](docs/releases/v1.1.0/02-architecture/linux-test-environment.md)。

`dev` 已合入端侧模型与 512 维向量识别，主 API 经 `VECTOR_RECOGNITION` 调用 `recognize-vec`。当前 App 要求 iOS 16+ 或 Android API 24+；Flutter Web 可用于其他页面开发，暂不支持扫描。扫描协议、平台资源及新旧 App 兼容边界见 [扫描识别链路](docs/releases/v1.1.0/01-flows/scan-recognition.md)。

## 仓库结构

| 路径 | 职责 |
|---|---|
| `apps/flutter-app` | iOS、Android 和 Web Flutter 客户端；扫描仅支持 iOS/Android |
| `apps/workers-api` | 共享 Hono API、PostgreSQL 访问层与 migrations、Cloudflare/Linux 运行入口 |
| `apps/admin-web` | React 管理后台 |
| `apps/marketing-web` | 营销、法律和公开站点 |
| `dart-packages/subscription-core` | 可配置的 Apple/Google 订阅业务模块 |
| `packages/*` | TypeScript 共享认证、API、UI 和 Workers 能力 |
| `deploy/linux` | Linux 测试环境 Compose、离线镜像、迁移与分支监听发布脚本 |
| `docs/releases` | 按版本冻结的产品输入与实现文档 |

完整边界见 [v1.1 Monorepo 文档](docs/releases/v1.1.0/02-architecture/monorepo.md)。

## 环境要求

- Node.js `>=22`
- pnpm `11.9.0`（以根 `packageManager` 为准）
- Dart SDK `^3.9.2`
- Flutter `>=3.44.0`

安装依赖：

```powershell
pnpm install --frozen-lockfile
flutter pub get
```

环境 URL、Cloudflare bindings 和第三方服务配置按目标环境注入。密钥只通过受控 secret 管理，不写入仓库。

## 本地开发

```powershell
# Flutter Web，使用测试环境配置
pnpm app:chrome:dev

# Workers API
pnpm --filter @kando/workers-api dev

# React Admin
pnpm --filter @kando/admin-web dev

# Marketing Web
pnpm --filter @kando/marketing-web dev
```

各进程仍需要其目标环境可用的配置和本地/远程 Cloudflare 资源；启动命令成功不等于 Apple、向量识别服务、邮件或生产资源已配置。

Linux API 与 Admin 构建使用 `pnpm --filter @kando/workers-api build:linux`。准备独立测试配置后的启动、数据库和日志操作见 [Linux 运维手册](docs/linux-test-environment/README.md)。

## 质量检查

```powershell
# TypeScript / Node
pnpm build
pnpm type-check
pnpm lint
pnpm --filter @kando/workers-api test
pnpm --filter @kando/admin-web test

# Dart / Flutter workspace
dart run melos run analyze
dart run melos run test
```

只运行与变更相关的最窄检查时，交付记录必须明确列出未运行项，不能把局部验证写成全仓通过。

## 部署边界

- Workers 与 Admin dev：`pnpm --filter @kando/workers-api run deploy:dev`。
- Workers 与 Admin prod：`pnpm --filter @kando/workers-api run deploy:prod`。
- Marketing：`pnpm --filter @kando/marketing-web run deploy`。
- iOS GitHub Actions 当前只执行 unsigned release compile gate，不等于签名、TestFlight 或真机验收。
- Linux 分支监听脚本默认每两分钟检查 `dev`，仅在相关路径变化时构建并部署 kd201；GitHub Linux workflow 仅支持手动触发。服务器安装与最近部署证据见 [自动部署手册](docs/releases/v1.1.0/05-delivery/linux-test-auto-deployment.md)，合入代码不代表服务器已运行该提交。
- iOS 发布脚本校验 IPA 后自动保存 IPA/dSYM，按 Bundle ID 分目录，测试保留最近 3 个版本、正式保留 7 个版本；具体命令与保留规则见 [Flutter 交付说明](apps/flutter-app/README.md#ipa-与符号文件保存)。

dev 后续发布以已合入向量识别的 `dev` 为来源。`dev-wxy`、`dev-xiangyang`、`dev-update-dio`、`dev-scan-page-update-ui` 已于 2026-09-09 清理，本地与远程均不再作为工作分支；文档中带提交号的旧分支名仅保留来源追踪含义。当前运行版本与验收范围见 [发布与验证](docs/releases/v1.1.0/05-delivery/VERIFICATION.md)。

部署、远程迁移、生产写入和发布都需要单独明确授权；Git push 不会自动代表这些操作已获授权。

## 文档入口

- [项目文档索引](docs/README.md)
- [v1.0.0 已发布冻结基线](docs/releases/v1.0.0/README.md)
- [v1.1.0 当前增量](docs/releases/v1.1.0/README.md)
- [v1.1.0 系统架构](docs/releases/v1.1.0/02-architecture/architecture.md)
- [v1.1.0 业务上下文](docs/releases/v1.1.0/01-flows/business-context.md)
