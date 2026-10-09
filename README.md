# Kando Global Project

Kando 是 Card AI 的 monorepo，包含 Flutter 客户端、Cloudflare Workers API、React 管理后台、营销站点及共享包。产品主线是卡牌搜索、扫描识别、收藏与估值；v1.1 在此基础上增加 Apple 订阅、Premium 权益、服务端扫描额度、Performance 和订单/通知后台。

当前增量文档入口为 [v1.1.2](docs/releases/v1.1.2/README.md)；[v1.1.1](docs/releases/v1.1.1/README.md) 已于 2026-10-09 原位归档，v1.1.0 开发归档与 v1.0.0 冻结基线保持不变。文档版本切换不修改 App 版本、Git tag 或生产环境，原有待验项继续保留。

最近一次生产修复来自 `main@4b31cba` 加未提交的插件 redirect 修复（dirty），不是纯提交构建。2026-10-09 16:08 发布 Worker `ac0654e0-5b71-457f-9ddf-6f478995e6d9`，16:09 回读为 100% 流量；现网代码与批准产物一致，原配置保留，用户随后反馈接口调用“可以了”。正确 Key 的候选详情逐字段对照、限频触发及真机等专项验收仍未独立完成。本轮未提交/推送或重新发布手机安装包；Flutter 源码版本仍为 `1.0.5+163`。详见 [v1.1.1 验证记录](docs/releases/v1.1.1/05-delivery/VERIFICATION.md)。

历史检查点：2026-10-09 15:05 已从干净的本地 `main@c253647` 发布插件识别到 prod。Worker `e8c5d1fb-0e4d-4eb0-8483-3a77a4ba08fb` 为 100% 流量，独立 Pages Admin `cda22b78-846e-4b91-b6fc-7a69a022c768` 为 production/success；双入口 22 个静态文件与批准产物一致。仅新增插件专用 60 次/60 秒限频绑定，保留现有生产 Key、变量、数据库资源、缓存与调度配置；无 migration 或 SQL 业务写请求。缺失 Key/错误认证拒绝验证已通过，正确 Key 下的生产识别、详情及限频仍待补验，不能用 dev 合成向量结果替代。该生产发布阶段未推送 main；随后发布记录已提交为 `dbc2091` 并推送 `github/main`，不代表新增一次已验收部署。完整命令、测试和未验项见 [v1.1.1 验证记录](docs/releases/v1.1.1/05-delivery/VERIFICATION.md)。

历史检查点：2026-10-08 已按干净的 `main@61b5420` 发布生产 API 和两个 Admin 入口。Worker version `4adbd0b7-3c67-4795-8ad0-c39795dc4be6` 回读为 100% 流量；独立 Pages `toccards-admin` deployment `39154bee-45d6-429d-8118-dfafed526ab7` 成功，两个入口的 HTML 与各 10 个 JS/CSS 均与同一批准构建逐字节一致。扫描 R2/向量并行和请求放置日志已上线 prod；Smart Placement、Hyperdrive 查询缓存、变量/绑定、cron、域名及 Pages 构建与自动部署配置保留原值。没有执行 migration、数据库业务写入或 Flutter/营销站发布；未独立重查生产 PostgreSQL ledger。旧 App 真机、真实扫描/登录态、性能与缓存一致性仍未验收。实际命令、初轮测试超时及复验、回退点和未执行项见 [v1.1.1 验证记录](docs/releases/v1.1.1/05-delivery/VERIFICATION.md)。

Linux dev 最近已验收检查点为 2026-10-09 14:19：watcher 发布 `dev@b621d76`，release 为 `branch-dev-b621d76501e6-20261009140959`。后续 Git `dev@c253647` 不自动等同于已验收的运行版本；本次文档同步未重新回读 Linux 环境。v1.1.0 开发记录已原位归档；v1.1.1 的 App 1.0.4+ 兼容契约与验收矩阵仍是未完成验收的设计稿，部署事实不替代真机业务闭环或性能验收。历史发布、数据库迁移与资源证据继续保留在对应版本的交付记录。

## 系统概览

当前业务环境只有 `prod` 和 `dev`：`prod` 保持原 Cloudflare 部署，`dev` 是 kd201 上的 Linux 环境。旧 Cloudflare dev 业务 Worker 已退役，不再是发布目标；保留的 CF 向量识别和独立 Apple 回调只是 dev 的外部依赖。下图为 prod；Linux dev 的部署与数据边界见图后说明。

```text
Flutter App ------------+
                         +--> Cloudflare Workers (`/api/v1`)
React Admin -- HTTPS ----+        |-- PlanetScale PostgreSQL（经 Hyperdrive）: 业务与目录真源
                                  |-- KV: 可重建缓存
                                  |-- R2: 受保护的扫描卡面图片
                                  |-- recognize-vec: Service Binding 向量检索
                                  +-- OAuth、邮件、汇率和 Apple 服务

Marketing Web -----------------> 独立 Cloudflare 静态站点
```

共享 Hono API 是 App 与 Admin 的服务端安全边界，路由组合位于 `apps/workers-api/src/app.ts`，Cloudflare 入口为 `src/index.ts`。客户端不得直连数据库或对象存储；Cloudflare 正式环境的 Admin 有两个入口：`admin.tcgcard.fun` 由 Pages 项目 `toccards-admin` 托管，`api.tcgcard.fun` 的副本由 Workers assets 托管；二者调用同一生产 API，但静态资源须分别发布和验收。营销站点独立部署。旧 Cloudflare dev/test 与正式环境 prod 均已完成 PostgreSQL 迁移，D1 已废弃；2026-09-09 用户确认与 Cloudflare 回读一致，两环境当时绑定同一个 PlanetScale PostgreSQL/Hyperdrive，回读版本均无 D1 binding。2026-09-17 旧 dev 业务 Worker 退役，但共享数据库及旧测试数据未删除；正式环境继续使用原资源。后续数据库变更仅涉及 PostgreSQL schema 和业务数据修复，见 [数据迁移](docs/releases/v1.1.0/03-data-api/migration.md)，不再安排 D1 移库任务。

`dev` 已合入 Linux 入口 `src/linux/server.ts`，复用同一 Hono 应用与 PostgreSQL migration，使用独立 PostgreSQL、进程内 KV 和本地图片卷；Admin 由 Caddy 托管，离线模式使用 Node 静态服务。App `test` 默认 API 为 `http://192.168.50.201:8080/api/v1`，Admin development 使用同源相对 API，本机开发由 Vite 代理到 Linux，向量检索经 HTTP 复用 CF。2026-09-30 11:10 回读确认 kd201 watcher 已自动发布 `dev@7516cfd`，release 为 `branch-dev-7516cfd2a06a-20260930110549`：current 指向的 manifest、current-release、last-seen/last-deployed 一致，失败标记不存在；发布日志报告 API/DB healthy、Web started、migration 检查成功、无待执行 migration，ledger 14 项。发布前备份 1,135,397,728 字节且临时文件已移除；受 DBX MCP 只读策略限制，本轮未独立运行容器/数据库检查、`pg_restore --list` 或恢复演练；11:13 内网只读烟测通过，HTML 与本地构建仅 CR 字符不同，验证边界见当前版本记录。1,135,376,623 字节发布前备份通过 `pg_restore --list`，未执行恢复演练。17:04 内网 Admin 入口引用的 10 个 JS/CSS 资源与该提交本地 dev 构建哈希一致，候选图预览代码已交付；真实登录态交互仍需补验。旧 CF dev 的业务 Worker、域名入口和 cron 已退役；独立 Apple Sandbox 回调、CF 向量识别和正式环境保留。验收与未执行项见 [Linux 测试环境](docs/releases/v1.1.0/02-architecture/linux-test-environment.md)及[当前验证记录](docs/releases/v1.1.1/05-delivery/VERIFICATION.md)。

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

最近一次插件生产修复为 2026-10-09 的 `main@4b31cba` 加未提交修复：Worker `ac0654e0`。Pages 保持已有 `a17f8f12`，双 Admin 静态文件发布前后未变；正确 Key 调用由用户反馈恢复，独立专项验收边界见本页开头及 v1.1.1 历史验证记录。以下为历史回读：2026-10-08 09:27 已从 `main@61b5420` 重新发布 prod API，version `4adbd0b7-3c67-4795-8ad0-c39795dc4be6` 回读为 100% 流量；09:29 同步重新发布独立 Pages Admin，deployment `39154bee-45d6-429d-8118-dfafed526ab7`。09:36 的新请求只读烟测、两个 Admin 入口的逐文件核验及控制面回读通过。Smart Placement 与 Hyperdrive 查询缓存仍同时开启，未切换定向 Placement，也不宣称性能或缓存一致性验收通过。本轮无 migration/schema 源码增量，未执行迁移、备份/恢复或重查 PostgreSQL ledger。当前证据见 [v1.1.1 验证记录](docs/releases/v1.1.1/05-delivery/VERIFICATION.md)；此前检查点见 [v1.1.0 发布与验证](docs/releases/v1.1.0/05-delivery/VERIFICATION.md)。

- Linux dev：配置已验证的 SSH 目标 `TOCCARDS_SSH_TARGET` 后运行 `pnpm --filter @kando/workers-api run deploy:dev`；预检环境、PostgreSQL 18 和 CF 识别后，先备份再发布，不调用 Wrangler dev 部署。
- Workers API 与 API 域名下的 Admin 副本：`pnpm --filter @kando/workers-api run deploy:prod`，会一并发布当前工作区后端代码；仅发 Admin 时须沿用已核验的生产后端，不得直接打包 dev 的其他后端改动。
- Pages Admin prod：现有项目 `toccards-admin`，生产分支 `main`，域名 `admin.tcgcard.fun`；使用批准的 production 静态产物单独发布，不能以 Worker 副本更新替代。具体命令和双入口验收见 [Admin 增量](docs/releases/v1.1.1/04-admin/admin.md)。Pages 仍开启 main 自动部署；2026-10-08 回读确认既有自动构建和本轮批准产物均来自 `main@61b5420`，该提交已包含候选图片预览，不再存在本次改动尚未进入 main 的历史覆盖缺口。未来 main 变更及 Git 推送仍需独立授权。
- Marketing：`pnpm --filter @kando/marketing-web run deploy`。
- iOS GitHub Actions 的 push 触发仅覆盖 dev 的相关路径，另支持 PR 与手动触发；main 推送不代表该任务已执行。任务只执行 unsigned release compile gate，不等于签名、TestFlight 或真机验收。
- Linux 分支监听脚本默认每两分钟检查 `dev`，仅在相关路径变化时构建并部署 kd201；GitHub Linux workflow 仅支持手动触发。服务器安装与最近部署证据见 [自动部署手册](docs/releases/v1.1.0/05-delivery/linux-test-auto-deployment.md)，合入代码不代表服务器已运行该提交。
- iOS 发布脚本校验 IPA 后自动保存 IPA/dSYM，按 Bundle ID 分目录，测试保留最近 3 个版本、正式保留 7 个版本；具体命令与保留规则见 [Flutter 交付说明](apps/flutter-app/README.md#ipa-与符号文件保存)。

2026-10-09 已确认本地与远端 `main@dbc2091` 一致，已包含 `dev@c253647`；此前推送包含插件业务 `b621d76`、dev 发布记录 `c253647` 和 prod 发布记录 `dbc2091`。本地与远端均无 `dev-ext*` 分支，旧 `dev-extension` 名称仅作为历史发布来源保留。Git 提交号不代表对应 Worker、App 包或目标环境已完成发布或复验。`dev-wxy`、`dev-xiangyang`、`dev-update-dio`、`dev-scan-page-update-ui` 已于 2026-09-09 清理，本地与远程均不再作为工作分支；文档中带提交号的旧分支名仅保留来源追踪含义。最近已验收的运行版本与未验范围见 [v1.1.1 验证记录](docs/releases/v1.1.1/05-delivery/VERIFICATION.md)。

部署、远程迁移、生产写入和发布都需要单独明确授权；Git push 不会自动代表这些操作已获授权。

## 文档入口

- [项目文档索引](docs/README.md)
- [v1.0.0 已发布冻结基线](docs/releases/v1.0.0/README.md)
- [v1.1.0 开发归档](docs/releases/v1.1.0/README.md)
- [v1.1.1 开发归档](docs/releases/v1.1.1/README.md)
- [v1.1.2 当前开发文档入口](docs/releases/v1.1.2/README.md)
- [v1.1.0 系统架构](docs/releases/v1.1.0/02-architecture/architecture.md)
- [v1.1.0 业务上下文](docs/releases/v1.1.0/01-flows/business-context.md)
