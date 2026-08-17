# D1 到 PlanetScale PostgreSQL 正式迁移技术设计

## 决策

- dev 与 prod Worker 使用同一个 PlanetScale PostgreSQL 数据集和同一个 Hyperdrive 配置。环境仍由域名、`APP_ENVIRONMENT`、Apple 环境校验、KV、R2 和其他 Worker 变量区分；不在全部业务表增加环境列，也不建立 dev/prod 双 Schema。
- 运行期新增一层只实现现有 `prepare/bind/first/all/run/batch/exec` 合同的 PostgreSQL 适配器。业务模块继续使用同一数据库接口，避免在本次迁移中重写认证、资产、扫描和订阅流程。
- PostgreSQL driver 使用 Cloudflare 官方示例支持的 `postgres` 3.4.9。每次 fetch/scheduled 入口创建 client，`max=5`、`fetch_types=false`，请求完成后关闭；Hyperdrive 承担底层连接池。
- dev/prod 的 Wrangler 配置均把 `DB` D1 binding 替换为相同 ID 的 `HYPERDRIVE` binding。实际 app 内部仍注入名为 `DB` 的兼容接口，测试可继续注入 D1/Fake DB。
- Hyperdrive 查询缓存关闭。认证、session、资产、配额、订阅和 Admin 均要求读后写一致性，当前没有可证明安全的缓存 SQL 白名单。
- 旧 `tcg_price` 的 1,053,034 行和旧 `price_sync_state` 不迁移；目标价格域按 `price-domain-postgresql-ddl.md` 创建 7 张空表，业务读路径改读新表。

## 运行时与 SQL

- 适配器确定性地把 SQL 中不位于字符串、标识符或注释内的 `?` 转为 PostgreSQL `$1..$n`，参数数量不匹配时显式失败。
- `batch` 使用单个 PostgreSQL transaction 顺序执行，任一语句失败则整体回滚，并保留 D1 `meta.changes` 业务判断语义。
- 将运行时代码中的 SQLite 专用语法显式改为 PostgreSQL：`INSERT OR IGNORE` 改为 `ON CONFLICT DO NOTHING`，`GROUP_CONCAT` 改为 `string_agg`，移除 `INDEXED BY`。
- 普通业务表继续保存 ISO8601 UTC `text` 时间、0/1 `integer` 布尔和现有列名，避免改变 API 序列化与比较语义；金额 micros 使用 `bigint`，适配器在安全整数范围内转换为 JavaScript number。
- Admin、搜索和列表保留现有分页上限。价格批量查询使用集合 SQL，最多 100 个 series；历史读取按月份范围和 series 集合查询，不逐项 fan-out。

## 价格查询映射

- 卡牌搜索/详情先按 `price_series.card_ref` 读取 active series，再通过 `current_price_pointer -> price_current_snapshot` 读取已发布 current batch。
- Raw、评级机构、grade、condition、language、finish 从 `price_series` qualifier 映射回现有 API 字段；金额从 micros 确定性换算为 USD decimal。
- 30/90/365 天历史从 `price_history_month` 按月读取 JSONB points，并在 Worker 中执行现有窗口过滤和基准点保留规则。
- Trending 只读 `card_trending_snapshot` 当前已发布 batch，不再对全量价格表执行实时反连接。
- `sold-listings` 继续是现有价格序列的展示投影，不引入新的成交明细表。
- 新价格表为空时价格相关字段/列表返回现有的无价格形态，不伪造旧数据。

## PostgreSQL Schema

- 建立一份可重复执行的 PostgreSQL 基线 migration，覆盖当前应用使用的 33 张非价格业务表及索引/约束。
- 显式排除 `_cf_KV`、`d1_migrations`、空的 `cards_new`、`price_sync_state` 和旧 `tcg_price`。
- 追加 7 张价格域表：`price_source`、`price_series`、`price_ingest_batch`、`price_current_snapshot`、`current_price_pointer`、`price_history_month`、`card_trending_snapshot`。
- `collection_item` 与 `collection_item_event` 增加可空 `price_series_id`。因为本次不迁旧价格，现有资产不做猜测映射，字段保持 NULL，后续由正式价格导入器按已冻结 qualifier 规则回填。
- Schema 迁移记录使用独立 `postgres_migration` 表，migration 名称唯一、checksum 固定；不搬 D1 migration 历史。

## 数据迁移与校验

- 使用只在本机 `wrangler dev --remote` 运行的迁移 Worker，同时绑定 dev D1 为 `SOURCE_DB`、Hyperdrive 为 `HYPERDRIVE`；该入口不部署。
- 表清单、依赖顺序、列名和主键/rowid 游标在常规代码中固定，不由模型或运行时猜测。
- 每批同时限制最大行数和编码后字节数，最多 500 行且硬上限为 512 KiB；D1 查询先按累计 JSON 字节裁剪，任何单行超限都显式失败。目标写入按每表固定唯一游标执行多行 `INSERT ... ON CONFLICT (cursor) DO UPDATE`，使仍在运行的 dev D1 发生更新后可通过重跑收敛；物理删除由最终逐行摘要显式报错，不静默忽略。
- 迁移前创建 schema，迁移后逐表比较源/目标 count，验证外键、唯一约束、关键抽样 checksum；确认目标不存在 `tcg_price`，7 张新价格表为空。
- dev 切换前保留 D1 不写不删。回滚时停止 dev PG 写入并重新部署上一版 dev Worker 指回 D1；PG 已产生的新写入必须对账后才能回灌，不能盲切。
- 最终迁移与校验前必须先把 dev API 切入拒绝业务写入且暂停 cron 的维护状态；迁移 runner 缺少 `--confirm-source-write-frozen` 时拒绝执行完整迁移。仅传入参数不是冻结证据，验收必须同时记录维护版本已生效，避免无快照 keyset 校验漏掉迁移期间的并发更新。

## Hyperdrive 边界

- Cloudflare 2026-06-09 官方限制：单条 statement 最长 60 秒；缓存响应最大 50 MB，超过后仍返回但不缓存。
- 本项目把单次迁移负载控制在 512 KiB，业务列表保留分页，100-series 历史按月范围集合读取；所有响应在 Worker 序列化前设置应用级大小保护，禁止无界 `SELECT *`。
- 现有 Hyperdrive origin connection limit 为 15；Worker client `max=5`，禁止在 `Promise.all` 中为单项建立独立连接或 client。

## 提交与部署

1. PostgreSQL schema、driver、Hyperdrive 基础配置和迁移工具。
2. 运行时数据库适配器、价格/业务查询与回归测试。
3. dev 数据迁移证据、文档、配置收口和 dev 部署证据。

prod 只提交配置变更，不执行 migration、deploy 或任何 prod 写操作。
