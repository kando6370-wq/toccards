# v1.1.0 架构决策索引

本页只索引已生效边界和待决研究，不把调研建议伪装成已实施 ADR。新增正式 ADR 时应记录日期、状态、上下文、选择、替代方案、影响和回滚条件。

## 已生效边界

| 决策 | 状态 | 依据 |
|---|---|---|
| 共享 Hono API 是 App/Admin 的服务端安全边界，prod Cloudflare 与 dev Linux 分别适配运行资源 | 已采用 | `src/app.ts`、`src/index.ts`、`src/linux/server.ts` |
| dev Linux 使用独立 PostgreSQL、内存 KV、本地图片卷，复用业务路由和 PostgreSQL migration；仅向量识别经 HTTP 复用 CF | 已部署并完成受控扫描验证 | [Linux 测试环境](../linux-test-environment.md) |
| prod 使用 PlanetScale PostgreSQL/Hyperdrive 作为业务与目录真源，KV 仅为可重建缓存 | 原 Cloudflare 正式部署保持不变 | `src/db/postgres-database.ts`、`src/db/postgres/migrations/`、`wrangler.toml` |
| 当前只有 prod 与 dev 两个业务环境，PostgreSQL 数据集和环境配置隔离；旧 CF dev 不再发布 | 已采用 | [系统架构](../architecture.md)、[数据迁移](../../03-data-api/migration.md) |
| Premium 服务端能力按当前 live session grant 授权，不按 UID 授权 | v1.1 已采用 | [Premium 权益契约](../../03-data-api/entitlement-contract.md) |
| Apple 通知先持久化、幂等处理并允许定时补偿/Server API 校正 | v1.1 已采用 | `src/entitlements/apple-notification-routes.ts` |
| 原始 PRD 与已发布 v1.0.0 冻结，当前实现文档按版本增量维护 | 已采用 | [v1.1 文档入口](../../README.md) |

旧 CF dev 曾与 prod 共用 Hyperdrive；其业务 Worker、域名和 cron 已退役，历史测试数据及旧 KV/R2 保留，不构成当前第三个业务环境。

## 待决研究

| 议题 | 当前建议 | 决策状态 |
|---|---|---|
| 价格历史物理模型 | 7 表结构与月 JSON 保护已建成；正式价格数据导入、R2 冷数据与目标规模压测仍待完成 | 部分实施，数据与压测待完成 |
| TimescaleDB | 作为逐日行方案对照压测 | 条件候选 |
| ClickHouse | 仅在未来全库分析需求成立时作为旁路 | 非当前真源方案 |
| PostgreSQL 扩容、HA 与生产负载指标 | 当前 PlanetScale Postgres 18.6 已接入；容量与 P95/P99 仍需真实负载复核 | 运行参数待验证 |

详细证据：

- [D1 全量迁移数据库选型调研](../../03-data-api/research/database-migration-research.md)
- [卡牌价格历史一年期性能与选型分析](../../03-data-api/research/price-history-database-capacity-analysis.md)

## 尚未形成正式决策

- Lifetime 本地已验证缓存的最长离线兜底时间。
- Android Premium 的销售与授权范围。
- Apple 生产 SKU 与配置已存在，Sandbox/TestFlight 完整购买矩阵及后续客户端发布验收仍未收口。
