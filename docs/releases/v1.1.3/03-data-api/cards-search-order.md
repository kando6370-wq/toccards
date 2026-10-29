# Cards 创建时间排序与索引

更新日期：2026-10-29（Asia/Shanghai）。本次移除查询的 ID 次级排序，尚未部署；2026-10-28 的索引迁移 `0016` 保持原样。

## 查询与缓存

`GET /api/v1/cards/search` 按 2026-10-29 确认的规则使用：

```sql
ORDER BY created_at DESC NULLS LAST
```

卡牌只按目录创建时间倒序，空创建时间置后，不按字符串或数值商品 ID 二次排序。相同创建时间（含同时为空）的记录不规定先后，`LIMIT/OFFSET` 跨页落在这些记录中时，不保证分页边界稳定，可能重复或漏项；本次明确取消此前的 ID 稳定键约定。后续更新卡牌不再提升其排序。此规则覆盖 Search Cards 首屏、关键词搜索及共用该接口的 Sets 内卡牌列表；独立 Sets 系列列表仍使用 `s.name ASC, s.set_id ASC`。

首次加载继续先取 `/games` 返回的首个 Game，再以空关键词、`page=1`、`page_size=40` 查询。筛选、分页参数、响应字段、价格选择和客户端解析不变，继续使用 V1。搜索 KV 命名空间改为 `v15`，不复用含显式 ID 次级排序的 `v14` 缓存；TTL 仍为 1 小时。

本节替代归档[数据契约](../../v1.1.0/03-data-api/contract-changes.md#postgresql-查询切换)中 Card Search 的排序、ID 唯一稳定键及搜索缓存版本约定，其他接口的稳定排序规则保持不变。实现见[查询适配器](../../../../apps/workers-api/src/data-source/local-db-adapter.ts)及[搜索缓存](../../../../apps/workers-api/src/data-source/kv-cache.ts)。

## PostgreSQL 0016 索引替换

[0016_cards_all_created_order_indexes.sql](../../../../apps/workers-api/src/db/postgres/migrations/0016_cards_all_created_order_indexes.sql)先创建新索引，再删除对应旧索引：

| 查询范围 | 新索引 | 替换的旧索引 |
|---|---|---|
| 全目录 | `idx_cards_all_created_product` | `idx_cards_all_updated_product` |
| Game | `idx_cards_all_game_created_product` | `idx_cards_all_game_updated_product` |
| Game＋SetCode | `idx_cards_all_game_set_created_product` | `idx_cards_all_game_set_updated_product` |

三个索引的排序尾列仍为 `created_at DESC NULLS LAST, product_id DESC`；后两者分别保留 `lower(game)` 与 `lower(game), lower(set_code)` 前导表达式，使原有 Game／SetCode 筛选能力继续存在。这些已部署索引的前缀仍可支持仅按创建时间排序，2026-10-29 不修改 `0016`、不新增迁移，也不删除字段或索引。使用该索引时同时间记录可能恰好呈现 ID 降序，这不是 SQL 的次级排序承诺。Set ID 筛选仍复用 Game 索引。

仓库审计未发现活跃查询继续按 `cards_all.updated_at` 排序或筛选：卡牌详情、Scan 候选和 Portfolio 目录补全按 `product_id` 查询，Trending 通过 `product_id` 关联并按榜单 rank 排序。Admin 的 `ORDER BY updated_at` 属于 `card_override` 表，不属于旧索引删除范围。该结论不覆盖仓库外采集程序或临时 SQL 的全部历史；目标环境的索引使用与查询计划仍须按部署时独立核验。

按用户确认，仅删除上述三组旧排序索引，保留 `updated_at` 字段、其他列、业务数据、主键、其他索引及 trigram 索引。迁移使用 `IF NOT EXISTS`／`IF EXISTS` 支持重复执行；不修改已执行的 `0000`，也不修改退役 D1 schema、迁移或工具。

## 应用与回退边界

Linux 发布包、预检和迁移脚本会自动发现新增的 PostgreSQL SQL 文件，无需更改迁移清单。`migrate.sh` 在事务内执行迁移：新索引建立失败会回滚，旧索引删除安排在新索引创建之后。普通建索引会影响目录写入，删除索引还可能等待表锁；执行前必须按目标环境确认备份、空间、写入负载、锁等待和发布窗口。dev/prod 使用独立数据库，须分别核验和授权执行。

大表线上应用沿用[既有索引迁移方式](../../v1.1.0/03-data-api/migration.md#目录搜索-trigram-索引0013devprod-已分别执行)：在事务外按同一定义用 `CREATE INDEX CONCURRENTLY` 预建新索引，回读完整索引定义及 `indisvalid/indisready`，确认查询计划；同名索引存在并不代表定义正确或可用。确认新查询已切换、外部 SQL 无旧排序需求后，可在事务外逐个 `DROP INDEX CONCURRENTLY` 删除旧索引，再由幂等迁移登记目标环境 ledger。不得将 `CONCURRENTLY` 放入现有事务式迁移，也不把单次本地计划当作线上耗时保证。

应用代码回退不会改变数据兼容性，但旧更新时间查询可能失去排序索引；如需恢复旧查询性能，使用新的 PostgreSQL 迁移或经授权的并发建索引步骤恢复 [0000 中的三个原索引定义](../../../../apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql)，无需删除新索引或回填数据。不得回写已执行迁移文件。

2026-10-28 索引实现的历史验证见[原记录](../05-delivery/VERIFICATION.md#cards-search-order-indexes-20261028)；本次仅按创建时间排序的验证见[2026-10-29 记录](../05-delivery/VERIFICATION.md#cards-created-only-order-20261029)。
