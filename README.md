# Kando Global Project

Kando 是 Card AI 的 monorepo，包含 Flutter 客户端、Cloudflare Workers API、React 管理后台、营销站点及共享包。产品主线是卡牌搜索、扫描识别、收藏与估值；v1.1 在此基础上增加 Apple 订阅、Premium 权益、服务端扫描额度、Performance 和订单/通知后台。

## 系统概览

```text
Flutter App ------------+
                         +--> Cloudflare Workers (`/api/v1`)
React Admin -- assets ---+        |-- PlanetScale PostgreSQL（经 Hyperdrive）: 业务与目录真源
                                  |-- KV: 可重建缓存
                                  |-- R2: 扫描图片
                                  +-- OAuth、邮件、OCR、汇率和 Apple 服务

Marketing Web -----------------> 独立 Cloudflare 静态站点
```

Workers 是 App 与 Admin 的服务端安全边界。客户端不得直连 PostgreSQL、KV 或 R2；Admin 构建产物由 Workers assets 托管，营销站点独立部署。当前 dev 已使用 PlanetScale PostgreSQL/Hyperdrive；截至 2026-08-25，现网 prod 仍运行 v1.0 D1 版本 `57213c10-d392-43a9-8d34-c6472fc3febc`。v1.1 prod 的目标是完成生产数据迁移与冲突审计后切换到 dev 共用的 PostgreSQL；运行环境、Apple 配置、KV、R2、域名和 secrets 继续隔离。

## 仓库结构

| 路径 | 职责 |
|---|---|
| `apps/flutter-app` | iOS、Android 和 Web Flutter 客户端 |
| `apps/workers-api` | Hono API、PostgreSQL/Hyperdrive 访问层、PostgreSQL migrations、Worker 部署入口 |
| `apps/admin-web` | React 管理后台 |
| `apps/marketing-web` | 营销、法律和公开站点 |
| `dart-packages/subscription-core` | 可配置的 Apple/Google 订阅业务模块 |
| `packages/*` | TypeScript 共享认证、API、UI 和 Workers 能力 |
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

各进程仍需要其目标环境可用的配置和本地/远程 Cloudflare 资源；启动命令成功不等于 Apple、OCR、邮件或生产资源已配置。

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

部署、远程迁移、生产写入和发布都需要单独明确授权；Git push 不会自动代表这些操作已获授权。

## 文档入口

- [项目文档索引](docs/README.md)
- [v1.0.0 已发布冻结基线](docs/releases/v1.0.0/README.md)
- [v1.1.0 当前增量](docs/releases/v1.1.0/README.md)
- [v1.1.0 系统架构](docs/releases/v1.1.0/02-architecture/architecture.md)
- [v1.1.0 业务上下文](docs/releases/v1.1.0/01-flows/business-context.md)
