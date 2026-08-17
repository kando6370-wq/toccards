# v1.1.0 系统架构

## 1. 当前运行结构

```text
Flutter App --------------------+
                                 +--> Cloudflare Workers (`/api/v1`)
React Admin -- Worker assets ----+       |-- D1: 业务与目录真源
                                         |-- KV: 可重建缓存
                                         |-- R2: 扫描图片
                                         +-- Apple / OAuth / OCR / 邮件 / 汇率

Marketing Web -----------------------> 独立 Cloudflare 静态站点
```

`apps/workers-api/src/index.ts` 是 API 组合入口。App 和 Admin 只通过 Workers 访问服务端数据；Workers 负责鉴权、所有者隔离、Premium 服务端授权、幂等与外部服务适配。Admin 静态产物由 `apps/workers-api/wrangler.toml` 的 assets 配置托管，Marketing 使用独立 Wrangler 配置。

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
| `/scan` | 识别、确认、服务端 Quota 与 R2 图片 | `src/scan/routes.ts`、`quota.ts` |
| `/entitlements/apple` | 生命周期查询、Fresh Purchase、App Attest 与 Restore | `src/entitlements/routes.ts`、`restore-routes.ts` |
| `/apple/notifications/v2` | Apple 通知原文接收、验签、归约与补偿 | `src/entitlements/apple-notification-routes.ts` |
| `/admin` | 独立 Admin 鉴权、查询、运营配置和 XLSX | `src/admin/routes.ts` |

Worker 的 5 分钟 cron 调用通知 inbox 和 Apple Server API 校正重试。通知请求先持久化并按 payload/notification UUID 幂等，再异步归约交易和购买链状态。

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
| D1 | 已部署 Worker 的当前业务真源；dev 也是正式迁移的只读源 | 完成冻结、迁移、校验和 dev 切换前不得停止或清理 |
| PlanetScale PostgreSQL | 已创建 33 张业务表与 7 张新价格域表，业务数据尚未迁入 | dev/prod 切换后共享业务数据；环境配置、KV、R2 和 Apple 契约仍分离 |
| Hyperdrive | 已为 dev/prod 目标配置同一连接，代码通过 Postgres.js 兼容层访问 | 查询缓存须在切换前关闭；每请求或 cron 独立 client，后台任务结束后关闭 |
| KV | 目录查询和汇率等可重新获取数据 | 缓存失败不得改变授权或业务真值 |
| R2 | 扫描原图等对象 | 读取受 Admin 授权保护 |
| Flutter 安全存储 | 会话、已验证 Premium 缓存和待同步证据 | 只辅助本机体验，不替代服务端授权 |

Drizzle `src/db/schema.ts` 与 SQL `0000-0034` 是冻结前 D1 演进事实；PostgreSQL 目标结构以 `src/db/postgres/migrations/0000_business_schema.sql` 至 `0004_price_history_month_payload_limit.sql` 为准。运行时代码保留现有 `prepare/bind/first/all/run/batch` 调用形状，PostgreSQL 适配器把问号占位符转换为参数化查询，并把 `batch` 放在单一事务中顺序执行。共享 PostgreSQL 中 Apple inbox 以 `environment` 持久化队列归属，通知与校正 cron 只能领取当前 `APP_ENVIRONMENT` 对应的 Sandbox 或 Production 行；价格月历史只对同来源、同 `current:%` scope 的已发布 pointer 可见，单个月块 JSONB 文本不得超过 24 KiB。

## 6. 环境与部署

| 环境 | Worker | 域名 | 数据资源 |
|---|---|---|---|
| dev | `toccards-api-dev` | `api-dev.tcgcard.fun` | D1 非价格数据已迁入共享 PG；当前为写入冻结维护版本，正式 PG Worker/Admin 待部署 |
| prod | `toccards-api-prod` | `api.tcgcard.fun` | 线上仍为 prod D1/KV/R2；目标为共享 PG + 独立 prod KV/R2，本任务不部署 prod |

Wrangler vars 保存非敏感环境配置，密钥通过 Worker secrets 注入。dev 与 prod 共用业务 PostgreSQL 是本次明确的成本决策，但 `APP_ENVIRONMENT`、Apple Bundle/Product ID、KV、R2、域名和 Worker secrets 不得混用。部署脚本先构建共享认证和对应模式 Admin，再部署 Worker 与静态 assets。

## 7. 当前与目标架构的区分

当前处于迁移切换窗口：PlanetScale PostgreSQL、Hyperdrive binding、目标 schema、Postgres.js 兼容访问层、PostgreSQL 业务方言和新价格域读取已经实现；dev D1 的 33 张非价格业务表、270,577 行已在写入冻结后迁入共享 PostgreSQL，并完成逐表行数与完整摘要校验，Hyperdrive 查询缓存也已关闭。dev 当前运行明确返回 503 的维护版本，只有正式 PostgreSQL Worker/Admin 部署并完成业务烟测后才能标记切换完成。prod 仍运行旧 D1 部署，本任务只准备配置而不部署。TimescaleDB 与 ClickHouse 仍只是 [数据库迁移研究](../03-data-api/research/database-migration-research.md) 和 [价格历史容量分析](../03-data-api/research/price-history-database-capacity-analysis.md) 中的后续候选，不属于本次实现。

## 8. 证据索引

- `apps/workers-api/src/index.ts`：路由组合与定时任务。
- `apps/workers-api/src/env.ts`、`wrangler.toml`：binding 与环境边界。
- `apps/workers-api/src/db/schema.ts`、`src/db/migrations/`：当前数据结构。
- `apps/flutter-app/lib/app/router.dart`：App 页面入口。
- `apps/admin-web/src/App.tsx`：Admin 菜单与页面。
- `apps/workers-api/src/entitlements/`：Apple 证据、grant 和通知生命周期。
