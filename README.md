# Kando Global Project

Kando 是 Card AI 的 monorepo，包含 Flutter 客户端、Cloudflare Workers API、React 管理后台、营销站点及共享包。产品主线是卡牌搜索、扫描识别、收藏与估值；v1.1 在此基础上增加 Apple 订阅、Premium 权益、服务端扫描额度、Performance 和订单/通知后台。

本次合并源为 `dev@b75d81c`；当前 Flutter 客户端源码版本以 `apps/flutter-app/pubspec.yaml` 为准，为 `1.0.4+161`。2026-09-23 正式 IPA 上传时返回 processing；2026-09-28 美国区 App Store 公开页已显示 1.0.4，App Store Connect 后台处理详情与其他地区状态本轮未回读。最近一次已记录的 prod 发布是 2026-09-28 17:41 的 Smart Placement 有限样本试运行：保持原 `main@7868f4c` 业务源码不变，仅增加生产 Placement 配置，version `3ecee0b5-20e6-47a3-86f5-34f65f1d5465` 回读为 100% 流量；17:51 又按用户要求恢复现有 Hyperdrive 查询缓存，尚未完成性能或缓存一致性验收；prod PostgreSQL `0012/0013` 已在上一轮完成，本轮未运行 migration 或重查 ledger。2026-09-29 17:03 回读确认 kd201 已由 watcher 自动发布 `dev@c9f950e`，包含 Admin 候选图放大；API/DB healthy，运行 API bundle 与 release 一致，Admin 入口引用的 10 个资源与本地 dev 构建哈希一致。本次服务端发布不代表客户端真机业务闭环已验收。2026-09-28 用户确认 v1.1.0 开发阶段完成，开发记录已原位归档；v1.1.1 已明确从 App 1.0.4 起的服务端兼容方向，契约和验收矩阵仍属设计、未验收；2026-09-29 扫描 R2/向量并行增量已完成本地相关验证并自动发布 Linux dev，尚未部署 prod，真实批量识别/额度闭环未验收，见当前版本扫描流程及验证记录。产品迭代、Git 合并、服务端部署、安装包和商店发布分别记录。

## 系统概览

当前业务环境只有 `prod` 和 `dev`：`prod` 保持原 Cloudflare 部署，`dev` 是 kd201 上的 Linux 环境。旧 Cloudflare dev 业务 Worker 已退役，不再是发布目标；保留的 CF 向量识别和独立 Apple 回调只是 dev 的外部依赖。下图为 prod；Linux dev 的部署与数据边界见图后说明。

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

共享 Hono API 是 App 与 Admin 的服务端安全边界，路由组合位于 `apps/workers-api/src/app.ts`，Cloudflare 入口为 `src/index.ts`。客户端不得直连数据库或对象存储；Cloudflare 正式环境的 Admin 构建产物由 Workers assets 托管，营销站点独立部署。旧 Cloudflare dev/test 与正式环境 prod 均已完成 PostgreSQL 迁移，D1 已废弃；2026-09-09 用户确认与 Cloudflare 回读一致，两环境当时绑定同一个 PlanetScale PostgreSQL/Hyperdrive，回读版本均无 D1 binding。2026-09-17 旧 dev 业务 Worker 退役，但共享数据库及旧测试数据未删除；正式环境继续使用原资源。后续数据库变更仅涉及 PostgreSQL schema 和业务数据修复，见 [数据迁移](docs/releases/v1.1.0/03-data-api/migration.md)，不再安排 D1 移库任务。

`dev` 已合入 Linux 入口 `src/linux/server.ts`，复用同一 Hono 应用与 PostgreSQL migration，使用独立 PostgreSQL、进程内 KV 和本地图片卷；Admin 由 Caddy 托管，离线模式使用 Node 静态服务。App `test` 默认 API 为 `http://192.168.50.201:8080/api/v1`，Admin development 使用同源相对 API，本机开发由 Vite 代理到 Linux，向量检索经 HTTP 复用 CF。2026-09-29 17:03 回读确认 kd201 watcher 已自动发布 `dev@c9f950e`：current、manifest、last-seen/last-deployed 一致，API/DB healthy、Web running、migration 容器退出 0，失败标记为空；实际预检无待执行 migration，PostgreSQL ledger 为 14 项、最新 `0013`。1,135,376,623 字节发布前备份通过 `pg_restore --list`，未执行恢复演练。17:04 内网 Admin 入口引用的 10 个 JS/CSS 资源与该提交本地 dev 构建哈希一致，候选图预览代码已交付；真实登录态交互仍需补验。旧 CF dev 的业务 Worker、域名入口和 cron 已退役；独立 Apple Sandbox 回调、CF 向量识别和正式环境保留。验收与未执行项见 [Linux 测试环境](docs/releases/v1.1.0/02-architecture/linux-test-environment.md)及[当前验证记录](docs/releases/v1.1.1/05-delivery/VERIFICATION.md)。

当前代码包含端侧模型与 512 维向量识别；dev Linux 经 HTTP、prod Cloudflare 经 Service Binding 调用 `recognize-vec`。当前 App 要求 iOS 16+ 或 Android API 24+；Flutter Web 可用于其他页面开发，暂不支持扫描。扫描协议、平台资源及新旧 App 兼容边界见 [扫描识别链路](docs/releases/v1.1.0/01-flows/scan-recognition.md)。

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

Linux dev API 与 Admin 构建使用 `pnpm --filter @kando/workers-api build:dev`，原 `build:linux` 为兼容别名。`deploy:dry-run:dev` 构建并生成不含私有配置的 Linux 发布包；`deploy:dev` 使用显式 `TOCCARDS_SSH_TARGET` 经 SSH 调用服务器发布脚本。直接运行 Node API 的 `dev`/`start:linux` 从进程环境读取配置，开发机需使用可达的本地 PostgreSQL 地址，不能直接使用 Compose 内部主机名 `db`。详见 [Linux 运维手册](docs/linux-test-environment/README.md)。

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

2026-09-28 17:41 已发布 prod Smart Placement 有限样本试运行，version `3ecee0b5-20e6-47a3-86f5-34f65f1d5465` 回读为 100% 流量；业务源码与原生产基线不变，Admin assets 未变化。17:51 按用户要求恢复现有 Hyperdrive 查询缓存，当前为 Smart 与查询缓存同时开启，未宣称性能或缓存一致性验收通过。本轮未执行 migration，PostgreSQL ledger 上次回读（2026-09-21）为 14 项，本轮未重查。当前运行配置与验证边界见 [v1.1.1 验证记录](docs/releases/v1.1.1/05-delivery/VERIFICATION.md)；此前发布、迁移/备份与资源证据见 [v1.1.0 发布与验证](docs/releases/v1.1.0/05-delivery/VERIFICATION.md)。

- Linux dev：配置已验证的 SSH 目标 `TOCCARDS_SSH_TARGET` 后运行 `pnpm --filter @kando/workers-api run deploy:dev`；预检环境、PostgreSQL 18 和 CF 识别后，先备份再发布，不调用 Wrangler dev 部署。
- Workers 与 Admin prod：`pnpm --filter @kando/workers-api run deploy:prod`。
- Marketing：`pnpm --filter @kando/marketing-web run deploy`。
- iOS GitHub Actions 的 push 触发仅覆盖 dev 的相关路径，另支持 PR 与手动触发；main 推送不代表该任务已执行。任务只执行 unsigned release compile gate，不等于签名、TestFlight 或真机验收。
- Linux 分支监听脚本默认每两分钟检查 `dev`，仅在相关路径变化时构建并部署 kd201；GitHub Linux workflow 仅支持手动触发。服务器安装与最近部署证据见 [自动部署手册](docs/releases/v1.1.0/05-delivery/linux-test-auto-deployment.md)，合入代码不代表服务器已运行该提交。
- iOS 发布脚本校验 IPA 后自动保存 IPA/dSYM，按 Bundle ID 分目录，测试保留最近 3 个版本、正式保留 7 个版本；具体命令与保留规则见 [Flutter 交付说明](apps/flutter-app/README.md#ipa-与符号文件保存)。

当前 main 合并结果已包含 `dev@ad88ee9`；Git 提交号不代表对应 Worker、App 包或目标环境已完成发布。`dev-wxy`、`dev-xiangyang`、`dev-update-dio`、`dev-scan-page-update-ui` 已于 2026-09-09 清理，本地与远程均不再作为工作分支；文档中带提交号的旧分支名仅保留来源追踪含义。当前运行版本与验收范围见 [发布与验证](docs/releases/v1.1.0/05-delivery/VERIFICATION.md)。

部署、远程迁移、生产写入和发布都需要单独明确授权；Git push 不会自动代表这些操作已获授权。

## 文档入口

- [项目文档索引](docs/README.md)
- [v1.0.0 已发布冻结基线](docs/releases/v1.0.0/README.md)
- [v1.1.0 开发归档](docs/releases/v1.1.0/README.md)
- [v1.1.1 开发文档入口](docs/releases/v1.1.1/README.md)
- [v1.1.0 系统架构](docs/releases/v1.1.0/02-architecture/architecture.md)
- [v1.1.0 业务上下文](docs/releases/v1.1.0/01-flows/business-context.md)
