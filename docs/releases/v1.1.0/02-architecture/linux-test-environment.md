# Linux 测试环境与 Cloudflare 正式环境兼容设计

## 状态

- 日期：2026-08-26
- 分支基线：`dev@8e22c1d`
- 状态：实现已完成；本地 PostgreSQL migration 已验证，API/Web 镜像启动待可访问 Docker Hub 或配置可信镜像代理后补验
- 环境边界：Linux 为隔离测试环境；Cloudflare 继续承载 dev/prod Worker；现网 prod v1.0 D1 切换不属于本任务

## 背景与架构纠正

最新 `dev` 已完成 PostgreSQL/Hyperdrive 切换。运行入口通过 `HYPERDRIVE.connectionString` 创建现有 `PostgresDatabase`，业务路由仍调用统一 `Database` 契约。仓库规则明确禁止为 v1.1 新增或恢复 D1 路径。

因此 Linux 测试环境不再采用旧讨论中的 SQLite 方案，而是连接一个独立 PostgreSQL 容器。Cloudflare 与 Linux 共享同一个 `PostgresDatabase`、同一套 PostgreSQL migration、全部 Hono 路由和业务规则；差异只存在于运行入口、资源适配器和配置文件。

## 目标

1. 同一个 Git commit 可先部署 Linux 测试环境，再部署 Cloudflare dev/prod。
2. Linux 使用独立 PostgreSQL、内存 KV、本地扫描图片目录和独立 OCR 测试接口。
3. Cloudflare 继续使用 Hyperdrive、KV、R2、Workers Assets 和 Cron Triggers。
4. 后续业务版本只开发一套路由、SQL 和业务逻辑。
5. Linux 不读取正式数据库、R2、KV、密钥或外部正式接口。

## 非目标

- 不修改现网 prod v1.0 D1，也不执行 v1.1 prod 数据迁移或流量切换。
- 不新增 D1、SQLite、Miniflare 数据库回退路径。
- 不在第一版引入 Redis、MinIO、Kubernetes 或多 API 副本。
- 不在仓库提交 Linux 服务器真实域名、密码、Token 或证书私钥。

## 总体结构

```text
共享应用与业务代码
├── Hono routes / middleware
├── PostgresDatabase
├── PostgreSQL migrations
└── OAuth / Mail / OCR / Billing / Scan / Admin contracts

Cloudflare 运行时
├── Hyperdrive -> PostgreSQL
├── Workers KV
├── R2
├── Workers Assets
└── Cron Triggers

Linux 测试运行时
├── Node.js HTTP server -> PostgreSQL container
├── In-memory KV adapter
├── Local filesystem object-storage adapter
├── Caddy -> Admin SPA + API reverse proxy
└── Node interval -> scheduled jobs
```

## 共享代码边界

### Hono 应用

将路由注册和 CORS 从 Cloudflare Worker 入口抽取为共享应用模块。Cloudflare 入口和 Linux Node 入口都调用同一个 Hono app，不复制 API 路由。

允许来源由 `ALLOWED_ORIGINS` 配置覆盖；未配置时继续使用当前 Cloudflare 默认列表，保证现有部署行为不变。

### PostgreSQL

Linux 直接复用 `apps/workers-api/src/db/postgres-database.ts`：

- Cloudflare 从 Hyperdrive binding 取得连接串。
- Linux 从 `DATABASE_URL` 取得连接串。
- 两者执行 `apps/workers-api/src/db/postgres/migrations/*.sql`。
- 后续不得创建 Linux 专用 SQL 或 SQLite migration。

### KV

Linux 第一版使用带 TTL 的进程内 KV，只实现当前业务使用的字符串 `get` 和 `put`。服务重启后缓存清空是允许行为；数据库和业务结果不能依赖缓存持久化。

### 扫描图片

Linux 使用本地文件目录代替 R2，实现当前使用的 `put/get/delete`。对象 key 与 Cloudflare 保持一致，数据库继续保存对象 key。文件目录通过 Docker volume 持久化。

### 定时任务

Cloudflare 保留 5 分钟 Cron Trigger。Linux 入口使用单进程 interval 调用同一组通知重试与 Server API 校正函数，并禁止任务重叠执行。

### Admin 静态资源

Admin 继续构建同一份 React/Vite 应用：

- Cloudflare 使用 Workers Assets。
- Linux 使用 Caddy 托管 SPA，并将 `/api/*` 与 `/share/*` 转发给 Node API。
- Linux Admin API 地址使用同源相对路径 `/api/v1/admin`。

## 配置边界

Linux 真实配置存放在服务器 `.env`，仓库只提交 `.env.example`：

```dotenv
LINUX_TEST_SITE_ADDRESS=http://localhost
POSTGRES_DB=toccards_test
POSTGRES_USER=toccards
POSTGRES_PASSWORD=replace-me
DATABASE_URL=postgres://toccards:replace-me@db:5432/toccards_test
PORT=3000
ALLOWED_ORIGINS=http://localhost
OBJECT_STORAGE_PATH=/data/scan-images
OCR_SERVICE_BASE_URL=https://replace-with-test-recognize.example.com
JWT_SECRET=replace-with-independent-test-secret
SCHEDULED_TASK_INTERVAL_SECONDS=300
APP_ENVIRONMENT=development
```

OAuth、Apple、ZeptoMail、Mixpanel 和 Singular 配置全部使用测试凭证。缺失的可选外部配置保持现有受控错误语义，不允许回退到 Cloudflare 正式值。

## 数据与安全隔离

- PostgreSQL volume、扫描图片 volume、JWT secret 和外部服务凭证均为 Linux 测试专用。
- Linux 容器内数据库端口默认不映射到公网。
- 只有 Caddy 暴露 HTTP/HTTPS；API 和 PostgreSQL 位于 Compose 内部网络。
- migration runner 使用独立 ledger 表记录已执行的 PostgreSQL migration。
- Linux 环境禁止配置正式 PlanetScale/Hyperdrive 连接串。

## 日常发布流程

```text
开发共享功能
→ 构建并部署 Linux 测试环境
→ 完成受影响功能验收
→ 使用同一 commit 执行 Cloudflare dev/prod 流程
```

只有基础设施接口新增能力时才需要同时扩展 Cloudflare/Linux 适配器。普通 API、页面、业务规则和 PostgreSQL migration 只实现一次。

## 验收范围

全部实现完成后再测试，仅覆盖受影响面：

- Node API 启动、健康检查和 CORS
- PostgreSQL migration 与现有 `PostgresDatabase`
- 登录、资产、卡牌、扫描和 Admin 的代表性请求
- 内存 KV TTL
- 本地扫描图片写入、读取和删除
- OCR 请求只指向测试接口
- Linux scheduled jobs 不重叠
- Admin SPA 同源 API 代理
- Cloudflare prod/dev dry-run 仍通过

Flutter UI、iOS/Android 打包和未涉及页面不属于本任务验证范围。

## 完成标准

- Linux 可通过一条 Docker Compose 命令启动完整测试环境。
- Linux 与 Cloudflare 使用同一套业务代码和 PostgreSQL migration。
- Linux 重启后 PostgreSQL 数据和扫描图片保留，内存缓存允许清空。
- Linux 不依赖 D1、Hyperdrive、Cloudflare KV 或 R2。
- Cloudflare 现有入口、bindings、Cron 和静态资源行为不变。
