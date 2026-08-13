# D1 全量迁移数据库选型调研

> 调研日期：2026-08-13
> 适用范围：`apps/workers-api` 的全部 D1 数据迁移；Cloudflare Workers、KV、R2 和现有 HTTP API 边界继续保留。
> 结论性质：采购前技术选型。价格会随区域、税费、折扣和厂商调价变化，文中估算必须在下单当天用官方计算器复核。

## 1. 执行结论

### 1.1 推荐

**数据库选型：PostgreSQL 17。云服务首选：PlanetScale Postgres，通过 Cloudflare 控制台创建并由 Hyperdrive 连接。**

建议采购路径：

1. 先购买/创建 PlanetScale Postgres Single Node 开发实例，完成 SQLite 到 PostgreSQL 的方言改造、数据迁移和压测。
2. 生产环境购买 PlanetScale Postgres 高可用集群；初始规格以压测结果为准，不直接照搬 D1 容量推算 CPU。
3. 生产读写使用禁用查询缓存的 Hyperdrive 配置，保证登录、会话、资产和订阅授权的读后写一致性；只为明确允许短暂陈旧的目录查询配置缓存。
4. 长期增长的价格历史改为结构化明细表并按时间分区；图片、原始导入文件和冷历史继续放 R2，不能把无限增长 JSON 原样搬进 PostgreSQL 后继续追加。

选择 PlanetScale 的直接理由：

- Cloudflare 与 PlanetScale 有官方合作入口，可从 Cloudflare Dashboard 创建 Postgres、自动使用 Hyperdrive，并把 PlanetScale 用量合并到 Cloudflare 账单；这是候选中与 Cloudflare **产品级集成最深** 的方案。[CF-PS]
- PlanetScale Postgres 是标准 PostgreSQL，支持事务、外键、JSONB、全文搜索、表分区、逻辑复制和 Drizzle；可覆盖当前 D1 的事务与查询需求。[PS-COMPAT]
- 生产集群包含 1 个主节点和 2 个副本，跨 3 个可用区；默认每 12 小时备份，支持 PITR。需要注意默认备份保留仅 2 天，应为本项目配置至少 7 天保留并核算增量备份费用。[PS-PRICE][PS-BACKUP]
- 价格结构公开、可复算，开发 Single Node 从 5 美元/月起，高可用从 15 美元/月起；可先低成本验证再升级。[PS-PRICE]

### 1.2 备选

**第二选择：Amazon RDS for PostgreSQL。** 当公司需要更成熟的 AWS IAM/VPC/审计体系、更广实例选择、明确控制备份与维护策略，或者已有 AWS 运维和企业折扣时，选择 RDS。Cloudflare 有官方 RDS/Aurora Hyperdrive 指南，私网连接可使用 Workers VPC + Cloudflare Tunnel。[CF-AWS][CF-VPC]

RDS 没有 PlanetScale 的 Cloudflare 控制台创建和统一账单，但基础设施控制更强。不要选择 EC2 自建 PostgreSQL，除非团队愿意自行承担补丁、复制、备份恢复演练、监控、故障切换和磁盘扩容。

### 1.3 不选择的方案

- **不首选 Aurora PostgreSQL**：当前没有已验证的高并发、读副本或无服务器弹性需求，Aurora 增加计费和运维概念，属于过早投入。
- **不首选 Neon**：低流量和开发环境成本优秀，但生产所需 SLA、IP Allow、私网和日志导出处于较贵的 Scale 层；数据库持续在线时，按 CU-hour 计费优势下降。[NEON-PRICE]
- **不首选 Supabase**：当前已有自研认证、Workers API、KV 和 R2，不会使用其大部分 BaaS 能力；Pro 无 uptime SLA，7 天 PITR 另收 100 美元/月。[SUPA-PRICE]
- **不首选 DigitalOcean**：价格透明、产品简单，但真正高可用仍需至少一个 standby；Cloudflare 集成仅为标准 Hyperdrive 接入，不如 PlanetScale 深。[CF-DO][DO-MANAGED]
- **不首选 Google Cloud SQL / Azure Database for PostgreSQL**：两者均是合格托管 PostgreSQL，Cloudflare 也有官方接入指南，但本项目没有 GCP/Azure 现有资源、团队能力或合同折扣，无法抵消额外平台复杂度。[CF-GCP][CF-AZURE]

## 2. 当前项目对数据库的真实要求

本结论以当前代码和迁移为依据，不以旧 PRD 推断：

| 当前事实 | 选型影响 | 仓库证据 |
|---|---|---|
| 单个 D1 同时保存卡牌目录、价格、用户、会话、资产、扫描、Admin 和订阅 | 全量迁移需要通用 OLTP 数据库，不能只买搜索库或时序库 | `src/db/migrations/0000_famous_vector.sql` 至 `0034_billing_auto_renew_snapshot.sql` |
| 用户资产依赖 `owner_type + owner_id` 隔离，订阅依赖 session grant、challenge、通知幂等和额度原子结算 | 必须支持可靠事务、唯一约束、行锁/条件更新和可恢复备份 | `src/portfolio/routes.ts`、`src/billing/`、`src/scan/quota.ts` |
| 卡牌搜索、详情和 Trending 会关联 `cards_all` 与 `tcg_price` | 全库放入同一个 PostgreSQL 集群可保留 JOIN；按多个 D1 分片会产生跨库查询问题 | `src/data-source/local-db-adapter.ts` |
| `tcg_price` 把多个等级的价格历史保存为 TEXT JSON 数组 | 原样迁移仍会产生大行重写、容量和索引问题 | `src/db/migrations/0021_consolidate_tcg_price.sql` |
| Worker 代码直接使用 `D1Database.prepare/bind/first/all/batch` | 不是仅替换连接字符串；必须引入 PostgreSQL driver 和数据访问适配层 | `src/env.ts`、`apps/workers-api/src/**/*.ts` |
| 当前 Wrangler 只有一个 `DB` D1 binding | dev/prod 都要新增 Hyperdrive binding，并最终移除 D1 binding 和 D1 迁移命令 | `apps/workers-api/wrangler.toml`、`package.json` |

因此数据库类型应选择 PostgreSQL，而不是 MongoDB、DynamoDB、ClickHouse 或单纯对象存储。PostgreSQL 能用关系约束和事务承载账号/订阅，同时用 JSONB、全文索引和表分区承载目录与热历史。

## 3. 候选服务商比较

评分口径：5 为最好。Cloudflare 适配重点看官方 Hyperdrive 指南、原生购买/账单和私网能力；成本重点看低负载起步、100 GB 常驻生产和 HA 增量；可靠性重点看 HA、备份/PITR 和恢复边界。

| 服务商与产品 | CF 适配 | 成本 | 可靠性/控制 | 结论 |
|---|---:|---:|---:|---|
| **PlanetScale Postgres** | **5** | 4 | 4 | **本项目首选**；CF 原生创建、Hyperdrive、统一账单，生产默认三节点 |
| Amazon RDS for PostgreSQL | 4 | 4 | **5** | 企业控制首选；成熟，但网络与账单配置更多 |
| Neon Postgres | 4 | **5（低负载）** / 3（常驻） | 4 | dev/预发布优秀；生产 Scale 成本需实测 |
| DigitalOcean Managed PostgreSQL | 4 | 4 | 4 | 简单透明；HA 需增加 standby |
| Supabase Postgres | 4 | 4 | 3 | BaaS 能力与现有架构重复，Pro 缺 SLA/PITR 偏贵 |
| Google Cloud SQL for PostgreSQL | 4 | 3 | 5 | 技术可行；无现有 GCP 协同优势 |
| Azure Database for PostgreSQL Flexible Server | 4 | 3 | 5 | 技术可行；无现有 Azure 协同优势 |

“Cloudflare 适配最好”需要区分两层：

- **所有候选均可通过 Hyperdrive 使用标准 PostgreSQL driver 连接。** Cloudflare 分别发布了 PlanetScale、AWS、Neon、Supabase、DigitalOcean、Google 和 Azure 的官方接入文档。[CF-PS][CF-AWS][CF-NEON][CF-SUPA][CF-DO][CF-GCP][CF-AZURE]
- **PlanetScale 是唯一在本次候选中由 Cloudflare 官方提供 Dashboard 创建和统一账单的产品**，所以集成深度最高。[CF-PS]

## 4. 经济成本比较

### 4.1 统一示例

为避免拿免费套餐与生产 HA 混比，采用以下示例：

- 计价区域：美国东部；每月 730 小时；美元未税价。
- 数据库：100 GB；持续在线；不含超额公网流量、额外备份、技术支持和汇率。
- 这是采购预算示例，不是性能等价测试。不同产品的 CPU、突发额度、存储副本和 HA 拓扑并不完全等价。

| 产品与示例规格 | 可复算月费 | 说明 |
|---|---:|---|
| PlanetScale PS-40 ARM HA，4 GB/节点、1 主 2 副本、100 GB | **约 $119.25** | $83 集群 + `(100-10)×$0.125` 主盘 + `2×100×$0.125` 副本盘；100 GB/月生产公网 egress 和 2 倍磁盘的备份空间包含在内。[PS-PRICE] |
| AWS RDS `db.t4g.medium` Multi-AZ、100 GB gp3 | **约 $117.17** | AWS 2026-08-13 Price List API 美东价：`$0.129×730 + $0.23×100`；未计超额备份、流量和 T4g CPU credits。[AWS-PRICE] |
| Neon Launch，平均 1 CU、100 GB、全天运行 | **约 $112.38 起** | `$0.106×730 + $0.35×100`；未计 instant restore。Launch 没有 SLA/IP Allow/私网；Scale 同负载仅计算+存储约 `$197.06`。[NEON-PRICE] |
| Supabase Pro + Medium 4 GB + 100 GB General Purpose | **约 $86.50** | `$25 + $60 - $10 compute credit + (100-8)×$0.125`；7 天 PITR 另加 $100/月，Pro 无 uptime SLA。[SUPA-PRICE] |
| DigitalOcean 2 vCPU/4 GiB + 100 GiB，单节点 | **约 $82.34 起** | 官方价格页显示计算约 $60.84/月、磁盘 $0.215/GiB/月；真正 HA 至少增加 1 个 standby，最终以配置器为准。[DO-PRICE][DO-MANAGED] |
| Google Cloud SQL / Azure Flexible Server | **下单日计算器核价** | 区域、机型、HA、磁盘和承诺折扣组合较多；公开静态页不能给出对本项目可靠的单一总价，不在本文伪造精确值。[GCP-PRICE][AZURE-PRICE] |

### 4.2 成本判断

- **最低账单不等于最低总成本。** Supabase/DO 单节点便宜，但当前全库包含订阅和资产真值；生产故障、PITR 缺口和人工恢复的成本应纳入判断。
- PlanetScale 与 RDS 在上述 HA 示例中处于同一约 117–119 美元/月量级。PlanetScale 多一个可读副本和 Cloudflare 原生集成；RDS 示例是一个跨 AZ standby，通常不用于读取。
- Neon 只有在计算能经常休眠或维持很低平均 CU 时显著省钱；全天 API、价格同步和 cron 会降低 scale-to-zero 收益。
- Hyperdrive 在 Workers Paid 中查询不限量，连接池与查询缓存无额外费用，Cloudflare 不对 Hyperdrive 数据传输收费；源数据库厂商仍可能收 egress。[CF-HD-PRICE]
- 生产稳定后，RDS 可评估 1 年/3 年 Reserved Instance；PlanetScale、Neon 则按各自用量模型优化。迁移压测前不要购买长期承诺。

## 5. 推荐目标架构

```text
Flutter App / React Admin
          |
Cloudflare Workers (Hono)
          |
          +-- Hyperdrive (事务路径禁用查询缓存)
          |       |
          |       +-- PlanetScale Postgres
          |              +-- 账号、会话、资产、订阅、Admin
          |              +-- 卡牌目录、SKU、当前价格
          |              +-- 结构化热历史（按月分区）
          |
          +-- KV：可重建的目录/汇率缓存
          +-- R2：扫描图、卡图、原始导入、冷历史归档
```

Hyperdrive 不会在写入后自动失效已有查询缓存。登录、session、权限、配额、收藏和订阅必须使用禁用缓存的配置或不可缓存事务读取；目录搜索可在定义 TTL 后使用缓存。[CF-PS]

## 6. PostgreSQL 数据模型调整

全量迁移不等于逐列照搬。建议保持业务含义，改变不适合增长的物理模型：

```text
card_price_current
  product_id, sku_key, grader, grade, condition, language, finish,
  price, currency, observed_at, change_1d_percent

card_price_observation
  product_id, sku_key, metric_type, observed_at, price, currency, source
  PARTITION BY RANGE (observed_at)
```

- `price_Ungraded`、`price_PSA_10` 等同类 JSON 数组拆成 observation 行，用 `metric_type/grader/grade` 表达维度。
- 当前价格独立保存，列表和详情不扫描历史表。
- 近期可交互历史留在 PostgreSQL；超出产品在线查询窗口的冷数据压缩为 Parquet/JSON.gz 放 R2。
- SQLite TEXT 时间迁移为 `timestamptz`，金额继续使用整数 micros 或 `numeric`，不能改成浮点。
- SQLite INTEGER 布尔改为 PostgreSQL `boolean`；JSON 字段按是否查询选择 `jsonb` 或普通 text。
- 保留现有 ULID 文本主键和 `owner_type + owner_id` 授权语义，迁移时补强能安全建立的外键和 CHECK。

## 7. 全量迁移影响与路线

### 7.1 必须改造的代码

1. `Env.DB: D1Database` 改为 `Env.HYPERDRIVE: Hyperdrive`，引入 Cloudflare 官方推荐的 `pg >= 8.16.3` 或兼容 Drizzle PostgreSQL driver。[CF-PG]
2. 将散落的 `prepare().bind().first()/all()` 和 `batch()` 收口为仓库级数据库接口；涉及资产、额度、通知和授权的批处理改为显式 PostgreSQL transaction。
3. 把 SQLite 专有 SQL 改成 PostgreSQL：反引号、`INSERT OR IGNORE`、部分 `ALTER TABLE`、`char(0)` 排序拼接、布尔整数和时间文本均需逐条审计。
4. 新建 PostgreSQL schema/migrations；旧 D1 迁移保留为历史证据，不直接拿 SQLite migration 在 PostgreSQL 执行。
5. Miniflare D1 集成测试迁移到真实临时 PostgreSQL；涉及并发、额度和幂等的测试必须验证行锁、隔离级别和事务回滚意图。

### 7.2 推荐阶段

| 阶段 | 退出条件 |
|---|---|
| 0. 盘点 | 得到 prod 每表行数、数据/索引大小、JSON 列占用、QPS、P95/P99、增长率；没有这些数据不得冻结生产规格 |
| 1. PostgreSQL 兼容层 | 空库迁移可重复执行；所有现有 Workers 测试转为 PostgreSQL 并通过 |
| 2. 数据转换 | D1 导出到暂存文件；确定性脚本完成类型、JSON 历史和约束转换；表级数量与校验和一致 |
| 3. 双写验证 | D1 仍为真源，PostgreSQL 影子写入；读结果、幂等、权限隔离和金额逐项比对 |
| 4. 灰度读 | dev 全量走 PostgreSQL；prod 只灰度只读目录，再灰度用户和订阅事务 |
| 5. 短停机切换 | 暂停写入、追平增量、最终校验、切换 Hyperdrive binding；保留可回切窗口 |
| 6. 退役 D1 | 观察期和恢复演练完成后再停止 D1 写入；删除 D1 资源需另行明确授权 |

SQLite/D1 不提供 PostgreSQL WAL，无法直接使用常规 CDC 做无缝复制。迁移工具应使用确定性导出、增量水位或应用双写；不能宣传“零停机”而没有实际同步机制。

## 8. 采购前必须补齐的数据

当前仓库无法证明真实生产负载，因此以下信息仍是采购规格的阻塞项，而不是选型阻塞项：

- D1 prod 的每表数据量、索引量和最近 30 天增长率。
- `tcg_price` 各 JSON 列平均/P95/最大长度及总占用。
- API 峰值 QPS、数据库查询/请求、P95/P99 和定时同步写入量。
- 用户主要地域；数据库区域应靠近主要写入流量和外部同步源，而不是机械选择美东。
- 可接受的 RPO/RTO；本文暂按生产需要 HA、PITR 和至少 7 天恢复窗口处理。
- 预计热历史保留窗口和每月 R2 归档量。

建议先采购低规格开发实例，取得 PostgreSQL 压测数据，再用以下生产候选做 A/B：

- PlanetScale：PS-20/PS-40 ARM HA，100 GB，7 天备份保留。
- AWS RDS：`db.t4g.medium` Multi-AZ，100 GB gp3，storage autoscaling 500 GB，7 天备份。

## 9. 证据索引

以下均为官方资料，已于 2026-08-13 核验：

- [CF-PS] [Cloudflare × PlanetScale Postgres](https://developers.cloudflare.com/hyperdrive/planetscale/)：Dashboard 创建、Hyperdrive、统一 Cloudflare 账单、缓存一致性提醒。
- [CF-AWS] [Cloudflare Hyperdrive 连接 AWS RDS/Aurora](https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-database-providers/aws-rds-aurora/)。
- [CF-NEON] [Cloudflare Hyperdrive 连接 Neon](https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-database-providers/neon/)。
- [CF-SUPA] [Cloudflare Hyperdrive 连接 Supabase](https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-database-providers/supabase/)。
- [CF-DO] [Cloudflare Hyperdrive 连接 DigitalOcean](https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-database-providers/digital-ocean/)。
- [CF-GCP] [Cloudflare Hyperdrive 连接 Google Cloud SQL](https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-database-providers/google-cloud-sql/)。
- [CF-AZURE] [Cloudflare Hyperdrive 连接 Azure Database for PostgreSQL](https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-database-providers/azure/)。
- [CF-VPC] [Workers VPC 私网连接（Cloudflare 推荐）](https://developers.cloudflare.com/hyperdrive/configuration/connect-to-private-database-vpc/)。
- [CF-PG] [Hyperdrive PostgreSQL driver 支持](https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/)：`pg` 为推荐 driver，最低版本 8.16.3。
- [CF-HD-PRICE] [Hyperdrive 定价](https://developers.cloudflare.com/hyperdrive/platform/pricing/)：Workers Paid 查询不限量，连接池/缓存无额外费用，不收 Hyperdrive egress。
- [PS-COMPAT] [PlanetScale Postgres 兼容性](https://planetscale.com/docs/postgres/postgres-compatibility)：事务、外键、JSONB、分区、全文检索、Drizzle 等。
- [PS-PRICE] [PlanetScale Postgres 定价](https://planetscale.com/docs/postgres/pricing)：实例、三节点 HA、存储、备份和网络价格。
- [PS-BACKUP] [PlanetScale Postgres 备份恢复](https://planetscale.com/docs/postgres/backups)：12 小时自动备份、默认 2 天保留和 PITR。
- [AWS-PRICE] [AWS RDS PostgreSQL 定价](https://aws.amazon.com/rds/postgresql/pricing/) 与 [AWS Price List API](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/us-east-1/index.json)。
- [AWS-HA] [RDS Multi-AZ](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html) 与 [RDS 存储](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html)。
- [NEON-PRICE] [Neon 定价](https://neon.com/pricing)：CU-hour、存储、恢复、SLA 和私网能力。
- [SUPA-PRICE] [Supabase 定价](https://supabase.com/pricing)：Pro、计算、磁盘、PITR 和 SLA 范围。
- [DO-PRICE] [DigitalOcean Managed Databases 定价](https://www.digitalocean.com/pricing/managed-databases)。
- [DO-MANAGED] [DigitalOcean Managed Databases](https://docs.digitalocean.com/products/databases/)：备份、PITR、自动故障切换及 standby 的 HA 条件。
- [GCP-PRICE] [Google Cloud SQL 定价](https://cloud.google.com/sql/pricing) 与 [HA](https://cloud.google.com/sql/docs/postgres/high-availability)。
- [AZURE-PRICE] [Azure PostgreSQL Flexible Server 定价](https://azure.microsoft.com/pricing/details/postgresql/flexible-server/) 与 [备份恢复](https://learn.microsoft.com/azure/postgresql/backup-restore/concepts-backup-restore)。

## 10. 决策有效期

本结论在以下条件变化时必须重评：用户主地域发生变化；数据超过 1 TB 或月增量显著上升；需要跨区域强一致/灾备；价格历史变成重分析负载；公司已有 AWS/GCP/Azure 企业合同；PlanetScale 与 Cloudflare 合作、价格或 PostgreSQL 兼容范围发生变化。
