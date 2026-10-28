# Cards 创建时间排序与索引

更新日期：2026-10-28（Asia/Shanghai）。已随 `dev@b9702b81` 发布 kd201，PostgreSQL `0016` 已登记并独立验收；prod 尚未执行本次迁移或发布。运行证据见[dev 发布记录](../05-delivery/VERIFICATION.md#dev-cards-index-deployment-20261028)。

## 查询与缓存

`GET /api/v1/cards/search` 按最终产品要求使用：

```sql
ORDER BY created_at DESC NULLS LAST, product_id DESC
```

卡牌按目录创建时间倒序，空创建时间置后；相同创建时间按字符串商品 ID 降序，保证同一数据快照内分页顺序确定。后续更新卡牌不再提升其排序。此规则覆盖 Search Cards 首屏、关键词搜索及共用该接口的 Sets 内卡牌列表；独立 Sets 系列列表仍使用 `s.name ASC, s.set_id ASC`。

首次加载继续先取 `/games` 返回的首个 Game，再以空关键词、`page=1`、`page_size=40` 查询。筛选、分页参数、响应字段、价格选择和客户端解析不变，继续使用 V1。搜索 KV 命名空间改为 `v14`，避开按创建时间倒序、ID 升序生成的 `v13` 及按更新时间排序的 `v12` 缓存；TTL 仍为 1 小时。

本节替代归档[数据契约](../../v1.1.0/03-data-api/contract-changes.md#postgresql-查询切换)中 Card Search 的更新时间排序及搜索缓存版本说明，其他契约不变。实现见[查询适配器](../../../../apps/workers-api/src/data-source/local-db-adapter.ts)及[搜索缓存](../../../../apps/workers-api/src/data-source/kv-cache.ts)。

## PostgreSQL 0016 索引替换

[0016_cards_all_created_order_indexes.sql](../../../../apps/workers-api/src/db/postgres/migrations/0016_cards_all_created_order_indexes.sql)先创建新索引，再删除对应旧索引：

| 查询范围 | 新索引 | 替换的旧索引 |
|---|---|---|
| 全目录 | `idx_cards_all_created_product` | `idx_cards_all_updated_product` |
| Game | `idx_cards_all_game_created_product` | `idx_cards_all_game_updated_product` |
| Game＋SetCode | `idx_cards_all_game_set_created_product` | `idx_cards_all_game_set_updated_product` |

三个索引的排序尾列均为 `created_at DESC NULLS LAST, product_id DESC`；后两者分别保留 `lower(game)` 与 `lower(game), lower(set_code)` 前导表达式，使原有 Game／SetCode 筛选能力继续存在。Set ID 筛选仍复用 Game 索引，不额外新增与本次替换无关的索引。

仓库审计未发现活跃查询继续按 `cards_all.updated_at` 排序或筛选：卡牌详情、Scan 候选和 Portfolio 目录补全按 `product_id` 查询，Trending 通过 `product_id` 关联并按榜单 rank 排序。Admin 的 `ORDER BY updated_at` 属于 `card_override` 表，不属于本次删除范围。dev 发布前已检查索引使用统计和当时的活跃查询，但未安装 `pg_stat_statements`，未取得全部外部采集程序或临时 SQL 历史；prod 的使用情况仍须独立核查。

按用户确认，仅删除上述三组旧排序索引，保留 `updated_at` 字段、其他列、业务数据、主键、其他索引及 trigram 索引。迁移使用 `IF NOT EXISTS`／`IF EXISTS` 支持重复执行；不修改已执行的 `0000`，也不修改退役 D1 schema、迁移或工具。

## 应用与回退边界

Linux 发布包、预检和迁移脚本会自动发现新增的 PostgreSQL SQL 文件，无需更改迁移清单。`migrate.sh` 在事务内执行迁移：新索引建立失败会回滚，旧索引删除安排在新索引创建之后。普通建索引会影响目录写入，删除索引还可能等待表锁；执行前必须按目标环境确认备份、空间、写入负载、锁等待和发布窗口。dev/prod 使用独立数据库，须分别核验和授权执行。

大表线上应用沿用[既有索引迁移方式](../../v1.1.0/03-data-api/migration.md#目录搜索-trigram-索引0013devprod-已分别执行)：在事务外按同一定义用 `CREATE INDEX CONCURRENTLY` 预建新索引，回读完整索引定义及 `indisvalid/indisready`，确认查询计划；同名索引存在并不代表定义正确或可用。确认新查询已切换、外部 SQL 无旧排序需求后，可在事务外逐个 `DROP INDEX CONCURRENTLY` 删除旧索引，再由幂等迁移登记目标环境 ledger。不得将 `CONCURRENTLY` 放入现有事务式迁移，也不把单次本地计划当作线上耗时保证。

应用代码回退不会改变数据兼容性，但旧更新时间查询可能失去排序索引；如需恢复旧查询性能，使用新的 PostgreSQL 迁移或经授权的并发建索引步骤恢复 [0000 中的三个原索引定义](../../../../apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql)，无需删除新索引或回填数据。不得回写已执行迁移文件。

本地验证及未执行项记录在[当前版本验证记录](../05-delivery/VERIFICATION.md#cards-search-order-indexes-20261028)。
