# v1.1.0 系统架构

## 1. 当前运行结构

```text
Flutter App --------------------+
                                 +--> Cloudflare Workers (`/api/v1`)
React Admin -- Worker assets ----+       |-- PlanetScale PostgreSQL（经 Hyperdrive）: 业务与目录真源
                                         |-- KV: 可重建缓存
                                         |-- R2: 扫描图片
                                         +-- Apple / OAuth / recognize-vec / 邮件 / 汇率

Marketing Web -----------------------> 独立 Cloudflare 静态站点
```

上图仅为 prod 的 Cloudflare 部署结构。`apps/workers-api/src/app.ts` 组合共享 Hono 路由、CORS 与定时任务；`src/index.ts` 负责 Cloudflare fetch/scheduled 适配和每请求/定时任务的 PostgreSQL 连接生命周期。App 和 Admin 通过 API 访问服务端数据；共享路由负责鉴权、所有者隔离、Premium 服务端授权与幂等。prod Admin 静态产物由 `wrangler.toml` 的 assets 配置托管，Marketing 使用独立 Wrangler 配置。

dev 的 Linux Node 入口 `src/linux/server.ts` 复用相同 Hono 应用和 `PostgresDatabase`：从 `DATABASE_URL` 连接独立 PostgreSQL，使用带 TTL 的内存 KV 与本地图片卷；标准部署由 Caddy 托管 Admin 并反向代理 API/share，离线模式使用 Node 静态服务。App `APP_ENV=test` 与 Admin development 默认请求此 Linux 入口；API 使用 `APP_ENVIRONMENT=development`，经 HTTP 复用独立 CF 向量识别服务。旧 CF dev 不再运行或发布，见[Linux 测试环境](linux-test-environment.md)。

dev 扫描识别使用端侧 RTMDet-Ins 与 PE-Core-T16，Linux API 通过 HTTP 向 `recognize-vec` 只发送向量；候选补全、Queue、额度、目录、资产和图片读写留在 Linux PostgreSQL/本地卷。上图仅描述 prod，其运行协议与仓库配置的区别按实际部署版本核验；详见[扫描识别链路](../01-flows/scan-recognition.md)。

## 2. 客户端与页面边界

### Flutter App

- `GoRouter` 暴露 Home、Collection、Scan、Search、Card Detail、Profile、Subscription 与辅助页面。
- `Riverpod` 管理业务状态和依赖；Repository/API Client 负责 HTTP 与本地存储边界。
- `dart-packages/subscription-core` 封装 StoreKit/Play 商品、购买和 Restore 抽象；当前 v1.1 产品激活的是 Apple/iOS 购买路径。
- Premium 本地状态使用 `unknown/free/premium` 三态，不能把无法验证直接降为 Free。

### Admin

- React SPA 使用独立 Admin 会话访问 `/api/v1/admin`。
- 当前菜单覆盖安装、订单、Apple 通知、用户、反馈、扫描、权限和 App 版本。
- 页面隐藏不是最终授权；`apps/workers-api/src/admin/routes.ts` 继续执行角色校验。

## 3. Workers 服务边界

| 路由域 | 主要职责 | 证据入口 |
|---|---|---|
| `/auth` | 游客身份、注册、登录、OAuth、会话、资产迁移与删除账号 | `src/auth/anonymous.ts`、`account-flow.ts` |
| `/cards`、`/games`、`/sets`、`/rates` | 目录、搜索、价格、历史、趋势和汇率 | `src/data-source/routes.ts` |
| `/portfolio`、`/collection`、`/folders`、`/wishlist` | 资产、Folder、估值和 Performance | `src/portfolio/routes.ts` |
| `/scan` | 识别、确认、服务端 Quota 与受保护图片（prod R2、dev 本地卷） | `src/scan/routes.ts`、`quota.ts` |
| `/entitlements/apple` | 生命周期查询、Fresh Purchase、App Attest 与 Restore | `src/entitlements/routes.ts`、`restore-routes.ts` |
| `/apple/notifications/v2` | Apple 通知原文接收、验签、归约与补偿 | `src/entitlements/apple-notification-routes.ts` |
| `/admin` | 独立 Admin 鉴权、查询、运营配置和 XLSX | `src/admin/routes.ts` |

共享 Hono 边界为全部 `/api/v1/*` 请求校验或生成 UUID v4 `X-Request-ID`，在响应 Header 回显，并以路由模板记录不含 query、真实路径参数、身份和正文的结构化完成日志。Flutter/Admin 的每次物理 HTTP 尝试使用新 ID；业务 `request_id`/`Idempotency-Key` 继续按各自幂等规则复用。`/share/*`、静态资源、第三方调用及主 API 到 `recognize-vec` 的内部请求不传播该 Header。完整契约见[契约变化](../03-data-api/contract-changes.md#api-请求关联)。

prod Cloudflare Worker 的 5 分钟 cron 调用共享 `runScheduledTasks`，执行通知 inbox 和 Apple Server API 校正重试。dev Linux 单进程 interval 默认同为 300 秒，可通过 `SCHEDULED_TASK_INTERVAL_SECONDS` 设置；前一次任务未完成时跳过本次触发，退出时等待定时任务和后台请求完成后关闭数据库。通知请求先持久化并按 payload/notification UUID 幂等，再异步归约交易和购买链状态。旧 CF dev 的 cron 已退役。

## 4. v1.1 Premium 信任边界

```text
StoreKit verified transaction/current entitlement
              |
              +--> App 本机即时 Premium
              |
              +--> Fresh Purchase / Restore proof
                         |
                         +--> 当前 live session grant
                                      |
                                      +--> Scan / Folder / Performance / 1Y API

Apple Notifications V2 + Server API --> purchase chain lifecycle correction
```

- Apple transaction/purchase chain 是购买事实，不归属于 App UID。
- UID 用于业务账号、资产和 Admin 关联；服务端受限操作读取当前 live session grant。
- 本机 Premium 但缺少服务端 grant 时返回 `ENTITLEMENT_SYNC_REQUIRED`；明确 Free 才返回 `PREMIUM_REQUIRED`。
- Admin 是只读业务查询层，不提供人工授予或撤销 Premium 的能力。

详细规则见 [Premium 权益契约](../03-data-api/entitlement-contract.md)。

## 5. 数据与存储

| 资源 | 当前职责 | 一致性边界 |
|---|---|---|
| PlanetScale PostgreSQL | v1.1 正式业务、目录与价格域真源；旧 dev 迁移检查点已迁入 33 张业务表、270,577 行，并创建 7 张新价格域表 | 旧 CF dev/prod 曾通过同一 Hyperdrive 共用；旧业务 Worker 已退役，数据库及历史测试数据保留，Linux dev 使用独立 PostgreSQL |
| Hyperdrive | Cloudflare prod 的数据库连接入口，代码通过 Postgres.js 兼容层访问；旧 CF dev 曾复用该资源，业务 Worker 已退役 | 查询缓存关闭；每请求或 cron 独立 client，后台任务结束后关闭；缺少 binding 立即失败 |
| Linux PostgreSQL / 本地卷 | 隔离测试数据库与扫描图片，复用同一数据库适配器和 migration | 仅使用 Linux 测试 `DATABASE_URL`；进程级数据库连接在退出时关闭；不读取 Cloudflare 数据集 |
| KV | 目录查询和汇率等可重新获取数据 | 缓存失败不得改变授权或业务真值 |
| R2 | 扫描原图等对象 | 读取受 Admin 授权保护 |
| Flutter 安全存储 | 会话、已验证 Premium 缓存和待同步证据 | 只辅助本机体验，不替代服务端授权 |

PostgreSQL 结构以 `src/db/postgres/migrations/` 中的顺序 migration 为准；后续 schema 变更只允许增加 PostgreSQL 向前迁移。运行时代码仅创建 PostgreSQL 适配器，适配器提供 `prepare/bind/first/all/run/batch` 调用形状、把问号占位符转换为参数化查询，并把 `batch` 放在单一事务中顺序执行。Apple inbox 在各环境数据库中均以 `environment` 持久化队列归属，通知与校正任务只领取当前 `APP_ENVIRONMENT` 对应的 Sandbox 或 Production 行；价格月历史只对同来源、同 `current:%` scope 的已发布 pointer 可见，单个月块 JSONB 文本不得超过 24 KiB。

## 6. 环境与部署

| 环境 | 运行入口 | 地址 | 数据资源 |
|---|---|---|---|
| prod | `toccards-api-prod` | `api.tcgcard.fun` | PostgreSQL/Hyperdrive，无 D1；仓库配置通过 `VECTOR_RECOGNITION` Service Binding 调用 `recognize-vec`，prod KV/R2、production Apple 配置和 `APP_ENVIRONMENT=production` 独立。本轮未部署性能提交或 `0013`，现网协议仍需按独立 release 验证 |
| dev | Linux Node / `src/linux/server.ts` | `http://192.168.50.201:8080` | 独立 PostgreSQL、内存 KV、本地图片卷、`APP_ENVIRONMENT=development`；最近一次完整 SSH 回读为 `dev@baf0d7b`、ledger 14 项，`dev@7d9b0ca` 的请求 ID API/Admin 已由 HTTP 行为与确定性资源名确认对外生效，服务器 manifest/ledger 未复读 |

旧 CF dev 的 `toccards-api-dev`、`api-dev.tcgcard.fun` 与 cron 已退役，不属于当前环境表，也不得重新发布；其历史测试数据和旧 KV/R2 保留。Wrangler vars 和 Worker secrets 现在仅用于 prod，密钥不进入仓库。prod 保持原数据库、Apple、KV、R2、域名和部署方式；仓库 prod 配置包含向量绑定，但配置文件不能替代现网版本核验，见[发布与验证](../05-delivery/VERIFICATION.md)。dev 的密钥保存在 Linux 私有环境文件，发布不使用 Wrangler。D1 不作为新迁移或回滚目标。

Linux 的真实配置仅保存在服务器 `.env`。分支监听器默认每两分钟检查 `dev`，相关路径变化才执行定向检查、构建、数据库备份和版本化发布；GitHub Linux workflow 仅为手动触发选项。2026-09-21 最近一次完整基础设施检查点为 `branch-dev-baf0d7b53681-20260921151308`，当时 manifest、`current`、`last-deployed-sha`、API/DB/Web、migration、ledger 与备份均已核对。请求关联提交 `7d9b0ca` 推送后，dev health 的新 Header 与 Admin 主资源已切换，但非交互 SSH 被拒绝，本轮未重新读取上述服务器状态。API 与 watcher 分别使用自身环境文件中的代理配置；发布 SHA、备份与未验收边界见[验证记录](../05-delivery/VERIFICATION.md)。

当前源码将 `deploy:dev` 改为 Linux 发布包 + SSH，`deploy:dry-run:dev` 只构建归档。手工、监听器与 Runner 均复用同一个发布脚本，在备份前核对本地数据库凭据/18 大版本、待执行 migration 和 CF 识别契约；已有库不会因 `current` 链接缺失而跳过备份。标准与离线 PostgreSQL 默认均为 18，并保留原卷路径。旧 CF dev 已退役，prod 发布入口保持原状。

## 7. 当前与目标架构的区分

dev 历史迁移检查点把 33 张非价格业务表、270,577 行写入 PostgreSQL，并完成逐表行数与完整摘要校验。2026-09-07 预检记录确认 PostgreSQL `18.6` 的 `postgres/public` 已应用 `0000` 至 `0010`，checksum 与仓库 SQL 一致且未验证约束为 0；该记录不代表本轮重查数据库。后续 `0011` 的 development 初始化、完整迁移登记及 `0012` 回填状态分别见[数据迁移](../03-data-api/migration.md)。旧 CF dev 曾运行 PostgreSQL Worker，现已退役；prod 仍运行 PostgreSQL Worker。Cloudflare v1.1 `fetch` 和 `scheduled` 缺少 Hyperdrive 时直接失败，不存在数据库降级路径；旧 D1 不属于运行、回滚或灾备目标。D1 到 PostgreSQL 迁移已完成，不作为后续发布待办。TimescaleDB 与 ClickHouse 仍只是 [数据库迁移研究](../03-data-api/research/database-migration-research.md) 和 [价格历史容量分析](../03-data-api/research/price-history-database-capacity-analysis.md) 中的后续候选，不属于本次实现。

## 8. 证据索引

- `apps/workers-api/src/app.ts`：共享路由、CORS 和定时任务组合。
- `apps/workers-api/src/index.ts`：Cloudflare 请求/cron 与数据库生命周期适配。
- `apps/workers-api/src/linux/`、`deploy/linux/`：Linux 资源适配、Compose 与发布脚本。
- `apps/workers-api/src/env.ts`、`wrangler.toml`：binding 与环境边界。
- `apps/workers-api/src/db/postgres/migrations/`：当前数据结构与顺序迁移。
- `apps/flutter-app/lib/app/router.dart`：App 页面入口。
- `apps/admin-web/src/App.tsx`：Admin 菜单与页面。
- `apps/workers-api/src/entitlements/`：Apple 证据、grant 和通知生命周期。
