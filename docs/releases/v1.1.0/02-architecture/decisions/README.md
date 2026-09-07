# v1.1.0 架构决策索引

本页只索引已生效边界和待决研究，不把调研建议伪装成已实施 ADR。新增正式 ADR 时应记录日期、状态、上下文、选择、替代方案、影响和回滚条件。

## 已生效边界

| 决策 | 状态 | 依据 |
|---|---|---|
| Workers 是 App/Admin 的服务端安全边界 | 已采用 | `apps/workers-api/src/index.ts`、`wrangler.toml` |
| PlanetScale PostgreSQL 经 Cloudflare Hyperdrive 作为业务与目录真源，KV 仅为可重建缓存 | v1.1 dev 已采用；prod 配置已准备但未部署 | `src/db/postgres-database.ts`、`src/db/postgres/migrations/`、`wrangler.toml` |
| dev/prod 共用 PostgreSQL 数据集，但运行环境、Apple、KV、R2、域名和 secrets 保持隔离 | v1.1 已采用 | [系统架构](../architecture.md)、[数据迁移](../../03-data-api/migration.md) |
| Premium 服务端能力按当前 live session grant 授权，不按 UID 授权 | v1.1 已采用 | [Premium 权益契约](../../03-data-api/entitlement-contract.md) |
| Apple 通知先持久化、幂等处理并允许定时补偿/Server API 校正 | v1.1 已采用 | `src/entitlements/apple-notification-routes.ts` |
| 原始 PRD 与已发布 v1.0.0 冻结，当前实现文档按版本增量维护 | 已采用 | [v1.1 文档入口](../../README.md) |

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
- Apple 生产 SKU、密钥、Sandbox/TestFlight 和发布操作方案。
