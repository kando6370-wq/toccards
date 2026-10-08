# v1.1.0 技术栈

## 1. 应用与运行时

| 层 | 当前技术 | 证据 |
|---|---|---|
| 移动/Web App | Flutter、Dart、Riverpod、GoRouter、Dio；iOS `URLSession` / Android Cronet 原生 transport | `apps/flutter-app/pubspec.yaml`、`lib/shared/api/app_http_transport.dart` |
| 订阅模块 | `in_app_purchase`、StoreKit adapter | `dart-packages/subscription-core/pubspec.yaml` |
| API | TypeScript、共享 Hono 应用；prod 为 Cloudflare Workers，dev 为 Linux Node 22 / `@hono/node-server` | `apps/workers-api/package.json`、`src/app.ts`、`src/linux/server.ts` |
| 数据访问 | Postgres.js 适配器与 PostgreSQL 顺序 migrations；prod 经 Hyperdrive，dev 直连独立 PostgreSQL | `src/db/postgres-database.ts`、`src/db/postgres/migrations/` |
| Admin | React 18、Vite 6、Ant Design 5、TanStack Query 5 | `apps/admin-web/package.json` |
| Marketing | Cloudflare static assets/Workers | `apps/marketing-web/wrangler.jsonc` |
| dev 部署 | Linux Docker Compose、独立 PostgreSQL、进程内 KV、本地图片卷；标准 Caddy 或离线 Node 静态服务 | `deploy/linux/`、`src/linux/` |
| Monorepo | pnpm 11.9.0、Turborepo 2、Dart pub workspace、Melos 8 | 根 manifests |
| 测试 | Vitest 4、PGlite PostgreSQL、Node test runner、Flutter test；部分旧测试仍使用待清理的 Miniflare/D1 兼容基座 | 各应用 scripts、`src/test-support/pglite-database.ts` 与 test 目录 |

## 2. 工具链约束

| 工具 | 当前约束 |
|---|---|
| Node.js | `>=22` |
| pnpm | `11.9.0` |
| Dart SDK | `^3.9.2` |
| Flutter App / subscription-core | `>=3.44.0` |
| GitLab Flutter CI | `3.44.0` |
| GitHub iOS CI | `3.44.7` |

CI 的 Flutter 版本冲突是显式目标差异，不合并成虚构的统一版本。涉及复现或发布时按目标流水线选择；统一版本必须作为独立变更同时更新 manifest、CI 和 lockfile 验证。

## 3. Cloudflare 能力

下表只描述 prod 的业务资源。旧 CF dev Worker、业务域名与 cron 已退役；dev 仅复用独立 CF 向量识别服务和 Apple Sandbox 回调代理，不再向 Cloudflare 发布业务 API。

| 能力 | 当前用途 |
|---|---|
| Workers | API、分享页、定时补偿与 Admin assets 入口 |
| Hyperdrive | Workers 到共享 PlanetScale PostgreSQL 的连接边界，查询缓存已关闭 |
| PlanetScale PostgreSQL 18.6 | prod 的目录、账号、资产、扫描、订阅、通知、价格和运营真源；旧 CF dev 历史数据保留 |
| KV | 可重建目录/汇率缓存 |
| R2 | 扫描图片 |
| Wrangler 4.106.0 | 本地开发、迁移、dry-run 与环境部署 |

当前 `wrangler.toml` 使用 `nodejs_compat`，以支持 Apple 官方 App Store Server Library 在 Worker 请求/定时任务上下文中加载。

以上 bindings 属于 prod。dev Linux 使用独立 PostgreSQL；标准 Compose 默认 `postgres:18-alpine`，离线镜像安装 PostgreSQL 18，两者显式设置 `PGDATA=/var/lib/postgresql/data` 保留现有卷路径。2026-09-23 回读 kd201 API release `dev@f9feac7`：Node 22 运行包、PostgreSQL 18.6、原数据库卷与 14 项 migration ledger 均保留，API/DB healthy、Web running；标准镜像仅完成 Compose 配置验证，没有实际启动。

## 4. 外部与平台集成

- Apple StoreKit、App Attest、App Store Server Notifications V2 与 Server API。
- Google/Apple OAuth；邮箱注册与找回密码使用 ZeptoMail。
- Flutter 移动端的业务 API、启动配置、分享缩略图和目录图片复用一个应用级 Native Dio Adapter：iOS 由单一 `URLSession` 协商 HTTP/2，并在 HTTPS 服务发布 `Alt-Svc` 时升级 HTTP/3；Android 使用 embedded Cronet，显式启用 HTTP/2 与 QUIC。协议失败按平台栈正常降级，不对失败的写请求另做换协议重试。Android 仅在 Cronet provider 明确不可用时按进程回退 Dart IO；`APP_HTTP_TRANSPORT=io` 只用于诊断或紧急构建回退，正式 test/production 配置固定并校验为 `native`。
- Scan 使用端侧 RTMDet-Ins 检测和 PE-Core-T16 向量化：iOS 16+ 使用 Core ML/Core Image，Android 使用最小 ONNX Runtime 与 Bitmap。dev Linux API 经 HTTP `VECTOR_RECOGNITION` 调用 `recognize-vec`，结构化记录与受保护图片留在本地 PostgreSQL/图片卷。此次 dev App 不包含或运行 ML Kit Latin OCR，不再提交端侧卡号提示；旧 OpenCV/pHash 移除，Web 暂不支持新端侧识别。prod 的 2026-09-21 已发布版本仍按其原有向量协议和独立验收判断，不能将本轮 dev 客户端或 `card_type` 增量当作 prod 已部署。
- dev Linux 配置以必填 `VECTOR_RECOGNITION_BASE_URL` 构造 HTTP `VECTOR_RECOGNITION`，向现有 CF 服务发送向量和 `card_type`（`0=TCG`、`1=Sports Card`，缺省为 `0`）；10 秒超时覆盖正文，业务数据库和图片卷保持本地。旧 OCR 字段已退出 dev 运行路径；服务端受控扫描与用户确认的客户端验收边界见[兼容设计](linux-test-environment.md#扫描兼容缺口)。
- Singular 的六个 test/production 套餐事件使用 `customRevenueWithAttributes` 上报 Apple verified 交易金额、币种和标识，独立持久化去重并补发此前入队的失败记录；Restore 和启动恢复不创建新收入。SDK API 返回不等于后台收件成功，详见[收入契约](../03-data-api/contract-changes.md#当前边界)。
- 汇率服务以 USD 为基准提供快照，KV 可缓存。
- Firebase Analytics/Crashlytics、Mixpanel、Singular 和 ATT 用于分析、归因与稳定性，不作为授权真源。Flutter 在 dev/prod 环境均开启 Mixpanel 移动端自动事件采集；Project Token 仍按环境加载。每次完整冷启动异步执行一次 Mixpanel 初始化，不阻塞 `runApp`；初始化失败后仅在当前进程内按 2 秒、5 秒、15 秒重试三次，成功后按原顺序补发初始化期间的内存事件，全部失败后停止重试并清空待发事件。表格定义的全部自定义事件共用同一属性组装入口；首次认证会话恢复完成前事件只暂存在内存，恢复为账号或游客后分别使用用户 UID 或匿名 ID 组装 `uid` 并发送，认证明确失败且没有可用身份时才发送空 `uid`。后续身份切换只影响切换后发生的事件，不回写已经组装的历史事件。

## 5. 配置和安全边界

- Flutter 通过 `--dart-define-from-file` 选择环境，`APP_ENV=test` 默认业务 API 为 `http://192.168.50.201:8080/api/v1`，production 和未配置值维持原生产 HTTPS API。正式配置同时设置 `APP_HTTP_TRANSPORT=native` 与 `cronetHttpNoPlay=true`；后者使 Android 构建内置 Cronet，不依赖 Google Play Services。Android 从同一参数选择指定 IP 的测试 HTTP 策略，iOS 由现有 test flavor 的独立 plist 配置；根 Melos 测试显式注入 `APP_ENV=test`。内网明文 test API 不能作为 HTTP/2 或 HTTP/3 协议验收目标。
- prod Worker 的公开 vars 与 bindings 在 `wrangler.toml` 声明；dev 业务配置位于 Linux 私有环境文件。
- Apple、JWT、邮件、分析等密钥必须使用 secret 管理，不进入源码、文档或测试夹具。
- dev 与 prod 使用独立 PostgreSQL 业务数据库；`APP_ENVIRONMENT`、Bundle ID、Product ID 白名单、存储、域名和密钥按环境隔离。旧 CF dev 的历史数据仍留在 prod 使用的共享数据库，不属于当前 Linux dev 的读写路径。
- Linux 配置只接受 `APP_ENVIRONMENT=development`，数据库、JWT、图片卷和外部凭据独立于 Cloudflare；必填环境变量缺失时启动失败。
- Admin 的 prod Vite 构建由 Worker assets 托管；dev Vite 构建使用同源 `/api/v1/admin`，由 Linux Caddy 或离线 Node 服务托管。
