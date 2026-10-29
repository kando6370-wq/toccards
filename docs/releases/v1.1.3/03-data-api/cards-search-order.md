# Cards 与 Sets 排序及索引

更新日期：2026-10-29（Asia/Shanghai）。Cards 与 Sets 数值排序已随 `dev@867c6fd8` 发布 kd201 并独立验收，见[本次 dev 发布记录](../05-delivery/VERIFICATION.md#dev-numeric-search-deployment-20261029)。Cards 固定过滤 `has_image = 2` 的增量已随本地 `dev@32cbf499` 合并，尚未推送或部署；Sets 不增加图片条件。本轮无新增 migration，2026-10-28 已随 `dev@b9702b81` 执行的 `0016` 保持原样，历史证据见[索引发布记录](../05-delivery/VERIFICATION.md#dev-cards-index-deployment-20261028)；prod 尚未执行本次数值排序发布、图片过滤增量或该索引迁移。

## 查询与缓存

`GET /api/v1/cards/search` 按 2026-10-29 确认的规则使用：

```sql
AND cards_all.has_image = 2
ORDER BY created_at DESC NULLS LAST,
  CASE WHEN product_id ~ '^[0-9]+$'
    THEN product_id::numeric ELSE NULL
  END DESC NULLS LAST,
  product_id DESC
```

`has_image = 2` 是共享 Cards 查询的固定目录条件：无论空关键词首屏、关键词搜索、后续分页，还是 Sets 内复用 `/cards/search` 的卡牌列表，都不返回其他图片状态的记录。该条件不改变卡牌详情、Trending、Scan 或 Portfolio 的独立 SQL；`has_image` 的存储值不随查询修改。

卡牌先按目录创建时间倒序，空创建时间置后。在同一创建时间组内（含同时为空），只将完全由 ASCII 数字组成的 ID 转为 `numeric` 排序键并降序排列，例如 `700 > 80 > 9`；非纯数字 ID 的排序键为 NULL，排在该时间组的纯数字 ID 后。数值相同或均为非数字时，按原字符串 `product_id DESC` 决定先后，为同一数据快照内的分页提供唯一稳定键。较新创建的非数字卡牌仍排在较旧创建的数字卡牌前，不按数值 ID 改写创建时间的主顺序。

`product_id` 的存储、关联与 API `card_ref` 保持原字符串，不裁剪、提取或重建标识；`0010` 和 `10` 均保留，数值键相同后由原字符串兜底，`A12`、`sports:12` 不提取为 `12`。只有列表排序派生键使用数值，其他标识契约不变。使用 `numeric` 而非 `bigint`，支持超过 64 位整数范围的数字 ID；并未定义无限长度数字的准入规则，目标数据库上线前仍须核查实际数字长度。

后续更新卡牌不提升其创建时间排序。此规则覆盖 Search Cards 首屏、关键词搜索及共用该接口的 Sets 内卡牌列表；独立 Sets 系列列表按下节的 `set_id` 规则排序。

首次加载继续先取 `/games` 返回的首个 Game，再以空关键词、`page=1`、`page_size=40` 查询；服务端同时应用 `cards_all.has_image = 2`。请求参数、响应字段、价格选择和客户端解析不变，继续使用 V1。搜索 KV 命名空间改为 `v17`，缓存键加入图片条件，不复用过滤前的 `v16` 响应；TTL 仍为 1 小时。

本文替代归档[数据契约](../../v1.1.0/03-data-api/contract-changes.md#postgresql-查询切换)中 Cards／Sets 的排序及 Card Search 缓存版本约定，其他接口的稳定排序规则保持不变。实现见[查询适配器](../../../../apps/workers-api/src/data-source/local-db-adapter.ts)及[搜索缓存](../../../../apps/workers-api/src/data-source/kv-cache.ts)。

## Sets 系列列表

`GET /api/v1/sets/search` 移除名称升序，改为：

```sql
ORDER BY CASE WHEN s.set_id ~ '^[0-9]+$'
  THEN s.set_id::numeric ELSE NULL
END DESC NULLS LAST,
s.set_id DESC
```

纯数字系列 ID 按数值降序，非纯数字排在其后；数值相同或均非数字时按原始字符串 ID 降序。`0010` 与 `10` 保持不同标识，`A12` 等不提取数字。名称只参与搜索匹配，不参与排序；这里没有创建时间主排序。转换仅产生排序键，数据库和 API 中的 `set_id` 继续为原字符串，并继承 `numeric` 的范围边界。

Game、关键词匹配、非空 `set_code` 过滤、响应字段和分页参数保持不变。Search 初始预载第 1 页 40 条；正常加载后首次切换到 Sets，客户端从第 1 页重新按每页 40 条加载到末页，保持服务端顺序。Sets 查询仍只读取 `sets` 表，不关联 `cards_all`，也不增加 `has_image` 条件。Sets 查询不经过现有 KV／Cache API 结果缓存，本次无需增加 Sets 缓存版本；从单个 Set 进入后的卡牌分页复用 `/cards/search`，因此使用 Cards 的 `has_image = 2` 与 `v17` 规则。

2026-10-29 dev 只读检查确认 `sets` 共 2,978 条，其中纯数字 ID 2,078 条、最长 7 位，非纯数字最长 5 字符。Pokemon 新排序首屏在单次样本中使用原 Game 索引筛选后 Sort，执行 1.768 ms。本次不增加索引或 migration；该样本不代表一般性能或 prod 验收。行为与测试见[Sets 验证记录](../05-delivery/VERIFICATION.md#sets-numeric-id-order-20261029)。

## PostgreSQL 0016 索引替换

[0016_cards_all_created_order_indexes.sql](../../../../apps/workers-api/src/db/postgres/migrations/0016_cards_all_created_order_indexes.sql)先创建新索引，再删除对应旧索引：

| 查询范围 | 新索引 | 替换的旧索引 |
|---|---|---|
| 全目录 | `idx_cards_all_created_product` | `idx_cards_all_updated_product` |
| Game | `idx_cards_all_game_created_product` | `idx_cards_all_game_updated_product` |
| Game＋SetCode | `idx_cards_all_game_set_created_product` | `idx_cards_all_game_set_updated_product` |

三个索引的排序尾列仍为 `created_at DESC NULLS LAST, product_id DESC`；后两者分别保留 `lower(game)` 与 `lower(game), lower(set_code)` 前导表达式，使原有 Game／SetCode 筛选能力继续存在。本次数值排序实现不修改 `0016`、不新增迁移，也不删除字段或索引。现有索引可提供创建时间前缀，但不能直接满足新增的 `CASE ... ::numeric` 次级排序；同时间记录可能需要 Incremental Sort，Set 筛选也可能使用 Bitmap Scan＋Sort，不能继续承诺无额外排序。

2026-10-29 对 kd201 dev 进行只读候选 SQL 检查：2,405,301 条目录记录中纯数字 ID 为 268,639 条，最长 8 位；非纯数字 ID 最长 9 字符。Pokemon 最大同时间组有 29,684 张卡，空关键词首屏使用 Game 索引＋Incremental Sort，单次执行 81.133 ms；Set `23881` 使用 Game Bitmap Scan＋Sort，单次执行 26.783 ms。本次保留现有索引完成业务规则，后续若需消除额外排序，可依据目标环境负载另行增加匹配的表达式索引；不把上述 dev 单次样本当作正式性能指标或 prod 已验证结果。

仓库审计未发现活跃查询继续按 `cards_all.updated_at` 排序或筛选：卡牌详情、Scan 候选和 Portfolio 目录补全按 `product_id` 查询，Trending 通过 `product_id` 关联并按榜单 rank 排序。Admin 的 `ORDER BY updated_at` 属于 `card_override` 表，不属于旧索引删除范围。2026-10-28 dev 发布前已检查索引使用统计和当时的活跃查询，但未安装 `pg_stat_statements`，未取得全部外部采集程序或临时 SQL 历史；prod 及后续目标环境的索引使用与查询计划仍须独立核查。

按用户确认，仅删除上述三组旧排序索引，保留 `updated_at` 字段、其他列、业务数据、主键、其他索引及 trigram 索引。迁移使用 `IF NOT EXISTS`／`IF EXISTS` 支持重复执行；不修改已执行的 `0000`，也不修改退役 D1 schema、迁移或工具。

## 应用与回退边界

Linux 发布包、预检和迁移脚本会自动发现新增的 PostgreSQL SQL 文件，无需更改迁移清单。`migrate.sh` 在事务内执行迁移：新索引建立失败会回滚，旧索引删除安排在新索引创建之后。普通建索引会影响目录写入，删除索引还可能等待表锁；执行前必须按目标环境确认备份、空间、写入负载、锁等待和发布窗口。dev/prod 使用独立数据库，须分别核验和授权执行。

大表线上应用沿用[既有索引迁移方式](../../v1.1.0/03-data-api/migration.md#目录搜索-trigram-索引0013devprod-已分别执行)：在事务外按同一定义用 `CREATE INDEX CONCURRENTLY` 预建新索引，回读完整索引定义及 `indisvalid/indisready`，确认查询计划；同名索引存在并不代表定义正确或可用。确认新查询已切换、外部 SQL 无旧排序需求后，可在事务外逐个 `DROP INDEX CONCURRENTLY` 删除旧索引，再由幂等迁移登记目标环境 ledger。不得将 `CONCURRENTLY` 放入现有事务式迁移，也不把单次本地计划当作线上耗时保证。

应用代码回退不会改变数据兼容性，但旧更新时间查询可能失去排序索引；如需恢复旧查询性能，使用新的 PostgreSQL 迁移或经授权的并发建索引步骤恢复 [0000 中的三个原索引定义](../../../../apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql)，无需删除新索引或回填数据。不得回写已执行迁移文件。

2026-10-28 索引实现的历史验证见[原记录](../05-delivery/VERIFICATION.md#cards-search-order-indexes-20261028)；此前仅按创建时间排序的验证见[对应历史记录](../05-delivery/VERIFICATION.md#cards-created-only-order-20261029)。本次数值次级排序的验证见[当前记录](../05-delivery/VERIFICATION.md#cards-numeric-id-order-20261029)，`has_image = 2` 目录过滤及兼容结果见[图片条件验证](../05-delivery/VERIFICATION.md#cards-has-image-filter-20261029)。
