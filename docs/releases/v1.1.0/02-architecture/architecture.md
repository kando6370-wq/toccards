# v1.1.0 系统架构

## 1. 当前运行结构

```text
Flutter App -- RTMDet-Ins + PE-Core-T16 --+
                                           +--> Cloudflare Workers (`/api/v1`)
React Admin -- Worker assets ----+       |-- PlanetScale PostgreSQL（经 Hyperdrive）: 业务与目录真源
                                         |-- KV: 可重建缓存
                                         |-- R2: 扫描矫正卡面
                                         |-- Service Binding: `recognize-vec`
                                         +-- Apple / OAuth / 邮件 / 汇率

Marketing Web -----------------------> 独立 Cloudflare 静态站点
```

`apps/workers-api/src/index.ts` 是 API 组合入口。App 和 Admin 只通过 Workers 访问服务端数据；Workers 负责鉴权、所有者隔离、Premium 服务端授权、幂等与外部服务适配。Admin 静态产物由 `apps/workers-api/wrangler.toml` 的 assets 配置托管，Marketing 使用独立 Wrangler 配置。

## 2. 客户端与页面边界

### Flutter App

- `GoRouter` 暴露 Home、Collection、Scan、Search、Card Detail、Profile、Subscription 与辅助页面。
- `Riverpod` 管理业务状态和依赖；Repository/API Client 负责 HTTP 与本地存储边界。
- Scan 在端侧执行 RTMDet-Ins `640×640` 卡牌检测和 mask 四边形拟合，矫正到 `745×1043` 后由 PE-Core-T16 `384×384` 预处理生成 512 维向量；iOS 由原生 Core ML 执行两个模型，Android 由模型专用 `onnxruntime-android 1.23.0` minimal AAR 执行 ORT 格式模型，仅保留所需 CPU 算子和类型，也不再生成或兼容 RGB pHash。
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
| `/scan` | 向量识别编排、确认、服务端 Quota、R2 图片与 PostgreSQL 目录过滤 | `src/scan/routes.ts`、`quota.ts` |
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
| PlanetScale PostgreSQL | v1.1 业务、目录与价格域唯一真源；dev 迁移检查点已迁入 33 张业务表、270,577 行，并创建 7 张新价格域表 | 当前 dev 已使用；v1.1 prod 在生产 D1 数据迁移与冲突审计后通过同一 Hyperdrive 共用，运行环境、KV、R2 和 Apple 契约仍分离 |
| Hyperdrive | dev/prod 当前代码与 Wrangler 配置的唯一数据库连接入口，代码通过 Postgres.js 兼容层访问 | 查询缓存关闭；每请求或 cron 独立 client，后台任务结束后关闭；缺少 binding 立即失败 |
| KV | 目录查询和汇率等可重新获取数据 | 缓存失败不得改变授权或业务真值 |
| R2 | 扫描矫正卡面等对象 | 读取受 Admin 授权保护 |
| `VECTOR_RECOGNITION` | `recognize-vec` Worker 的 Service Binding | 只传 512 维向量；不经过公网识别上游，不提供 pHash 回退 |
| Flutter 安全存储 | 会话、已验证 Premium 缓存和待同步证据 | 只辅助本机体验，不替代服务端授权 |

PostgreSQL 结构以 `src/db/postgres/migrations/` 中的顺序 migration 为准；后续 schema 变更只允许增加 PostgreSQL 向前迁移。运行时代码仅创建 PostgreSQL 适配器，适配器提供 `prepare/bind/first/all/run/batch` 调用形状、把问号占位符转换为参数化查询，并把 `batch` 放在单一事务中顺序执行。共享 PostgreSQL 中 Apple inbox 以 `environment` 持久化队列归属，通知与校正 cron 只能领取当前 `APP_ENVIRONMENT` 对应的 Sandbox 或 Production 行；价格月历史只对同来源、同 `current:%` scope 的已发布 pointer 可见，单个月块 JSONB 文本不得超过 24 KiB。

## 6. 环境与部署

| 环境 | Worker | 域名 | 数据资源 |
|---|---|---|---|
| dev | `toccards-api-dev` | `api-dev.tcgcard.fun` | 正式 PostgreSQL Worker/Admin 已部署；共享 PG 为业务真源，dev KV/R2 与 `APP_ENVIRONMENT=development` 保持独立 |
| prod | `toccards-api-prod` | `api.tcgcard.fun` | 当前 100% 流量版本 `57213c10-d392-43a9-8d34-c6472fc3febc` 仍绑定 D1；v1.1 发布时迁移生产数据并切换到共享 PostgreSQL，prod KV/R2 与 `APP_ENVIRONMENT=production` 保持独立 |

Wrangler vars 保存非敏感环境配置，密钥通过 Worker secrets 注入。v1.1 dev 与 prod 共用业务 PostgreSQL 是本次明确的目标决策，但当前 prod 的 D1 → PostgreSQL 数据迁移和应用切换仍是独立发布门槛；`APP_ENVIRONMENT`、Apple Bundle/Product ID、KV、R2、域名和 Worker secrets 不得混用。部署脚本先构建共享认证和对应模式 Admin，再部署 Worker 与静态 assets。

## 7. 当前与目标架构的区分

dev 数据库迁移已经完成：PlanetScale PostgreSQL、Hyperdrive binding、目标 schema、Postgres.js 访问层、PostgreSQL 业务方言和新价格域读取已承载 dev；迁移检查点把 dev 的 33 张非价格业务表、270,577 行写入 PostgreSQL，并完成逐表行数与完整摘要校验，Hyperdrive 查询缓存已关闭。当前 v1.1 代码的 `fetch` 和 `scheduled` 缺少 Hyperdrive 时直接失败，不存在数据库降级路径。现网 prod 的 D1 仅属于待下线的 v1.0 运行事实，不是 v1.1 新代码的回退方案；prod 切换前必须另行完成生产 D1 数据迁移、与现有 PostgreSQL 数据的冲突审计及回滚演练。TimescaleDB 与 ClickHouse 仍只是 [数据库迁移研究](../03-data-api/research/database-migration-research.md) 和 [价格历史容量分析](../03-data-api/research/price-history-database-capacity-analysis.md) 中的后续候选，不属于本次实现。

## 8. 证据索引

- `apps/workers-api/src/index.ts`：路由组合与定时任务。
- `apps/workers-api/src/env.ts`、`wrangler.toml`：binding 与环境边界。
- `apps/workers-api/src/db/postgres/migrations/`：当前数据结构与顺序迁移。
- `apps/flutter-app/lib/app/router.dart`：App 页面入口。
- `apps/flutter-app/lib/shared/scan/`、`android/app/src/main/kotlin/com/cardai/tcg/ScanModelRuntime.kt`、`ios/Runner/ScanModelRuntime.swift`：端侧扫描识别共享逻辑与平台运行时。
- `apps/admin-web/src/App.tsx`：Admin 菜单与页面。
- `apps/workers-api/src/entitlements/`：Apple 证据、grant 和通知生命周期。
- [`scan-recognition.md`](../01-flows/scan-recognition.md)：Scan 检测、矫正、向量化、内部检索和制品验证契约。
