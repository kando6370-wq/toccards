# Trending Today 数据采集与 PostgreSQL 写入指南

本文面向负责市场价格采集和 Trending 计算的独立程序开发者，说明如何向现有 PostgreSQL 价格域发布 `card_trending_snapshot`。本文是写入合同，不是数据库迁移脚本；示例中的参数、凭据和对象存储位置必须由目标环境配置提供。

权威 Schema 以 [`0001_price_domain.sql`](../../../../apps/workers-api/src/db/postgres/migrations/0001_price_domain.sql) 为准，完整价格域设计见 [PostgreSQL 价格域详细 DDL 设计](research/price-domain-postgresql-ddl.md)。若本文与当前 migration 冲突，以已执行 migration 为准并停止写入，不能自行绕过约束。

## 1. 结论与责任边界

采集程序不能只向 `card_trending_snapshot` 插入孤立数据。每条 Trending 行必须引用已经存在的 `cards_all` 卡牌和 `price_series` 价格序列，并与该序列当前已发布的 `price_current_snapshot` 金额、日期及 1D 基准完全一致。

完整发布链路为：

```text
外部 Market Price 数据
  -> price_source / price_series
  -> 已发布的 current:<source> 当前价批次
  -> 采集程序按已批准规则选择每张卡的 winning series
  -> 独立的 trending:global derived batch
  -> card_trending_snapshot
  -> current_price_pointer(scope_code = 'trending:global')
  -> GET /api/v1/cards/trending
  -> Flutter 首页和 View All
```

当前边界：

- 采集程序是可信服务端写入方，使用单独的最小权限 PostgreSQL 账号；不得复用 App、Admin 或 Worker 密钥。
- 当前 Workers 只提供 `GET /api/v1/cards/trending` 读取接口，没有 Trending 写入 API。
- PostgreSQL 是价格真源。不得读取或回退旧 D1 `tcg_price`，也不得写已废弃的 `trending_pin`。
- `card_trending_snapshot` 不是 View，不会自动从 `price_current_snapshot` 刷新；采集程序必须显式创建、校验并发布每个完整批次。
- `trending:global` 是单一全局指针，没有 dev/prod 环境列。当前环境共享同一 PostgreSQL 数据集时，向该 scope 发布测试数据会影响所有读取该数据集的环境。未取得真实数据写入授权前，应在隔离数据库或 PlanetScale 隔离分支验证。

## 2. 首次接入前必须确认

以下输入会改变业务结果，必须形成版本化配置并经产品和技术负责人确认。任一项未确认时，可以完成代码和隔离环境测试，但不得发布真实 `trending:global` pointer。

| 配置 | 最低要求 |
|---|---|
| 上游来源 | 来源名称、协议、鉴权、批次/游标、重放方式和原始文件保留位置 |
| 卡牌映射 | 上游记录如何唯一映射到 `cards_all.product_id`；禁止只按卡牌名称匹配 |
| Series winner | `source_code`、`metric_code`、Raw/Graded、condition、language、finish、grader/grade 的确定性优先级 |
| 1D 基准 | 当前点、24 小时比较目标、缺失点回退方向、允许的最大陈旧天数 |
| 业务日期 | 全局 Trending 使用的时区、日切时刻和 `business_date` 生成规则 |
| 排名字符规则 | 名称 A-Z 的大小写、Unicode 归一化和数据库 collation |
| 榜单规模 | 每批最大卡牌数、空批次和数量异常的告警阈值 |
| 对象存储 | 价格原始文件和 derived manifest 的专用 bucket、保留期和访问权限；不得复用扫描图片 `SCAN_IMAGES` |

已经固定的产品排序规则是：1D 涨幅降序、当前市场价降序、卡牌名称 A-Z。实现还应以 `card_ref ASC` 作为最终稳定键，避免前述字段完全相同时排名漂移。跨来源和多价格维度的 winner 选择规则尚不能从表结构推导，禁止使用无完整 `ORDER BY` 的 `LIMIT 1`。

## 3. 相关表及所有权

| 表 | 采集程序用途 | 写入要求 |
|---|---|---|
| `cards_all` | 校验 `card_ref` | 只读；目录卡不存在时拒绝该记录 |
| `price_source` | 标识外部来源和 Kando 派生来源 | 通常由平台一次性预配；运行时只读 |
| `price_series` | 保存来源记录、卡牌和价格维度，提供 `winning_series_id` | Trending 发布阶段只读；若同一程序负责价格导入，按价格域 DDL 的外部唯一键单独 upsert |
| `price_ingest_batch` | 记录输入、checksum、计数、状态和发布时间 | 每次 Trending 生成一个独立 batch |
| `price_current_snapshot` | 验证 winner 的当前价和 1D 基准 | 只读取 `current:%` pointer 指向的已发布批次 |
| `card_trending_snapshot` | 保存一个 Trending batch 的稳定排名和固化价格证据 | loading batch 完整写入；发布后不可修改 |
| `current_price_pointer` | 原子选择当前可见的 Trending batch | 只在发布或回退事务中写 `trending:global` |

Trending batch 的 `source_id` 应指向一个 `source_kind='derived'` 的稳定来源，例如 `kando-derived`。`winning_series_id` 仍指向真实外部价格序列，因此同一个 Trending batch 可以包含不同外部来源的 winner。

一次性预配由数据库管理员执行，不应成为每轮采集任务的一部分：

```sql
INSERT INTO price_source (source_code, display_name, source_kind)
VALUES ('kando-derived', 'Kando Derived', 'derived')
ON CONFLICT (source_code) DO NOTHING;

SELECT source_id, source_code, display_name, source_kind, is_active
FROM price_source
WHERE source_code = 'kando-derived';
```

查询必须恰好返回一条 `source_kind='derived' AND is_active=true` 的记录，否则采集程序显式失败。

## 4. `card_trending_snapshot` 字段合同

| 字段 | 写入规则 |
|---|---|
| `batch_id` | 本轮 `price_ingest_batch.batch_id`，其 `scope_code` 必须是 `trending:global` |
| `rank` | 从 1 开始、连续且不重复；同一 batch 内决定 API 分页顺序 |
| `card_ref` | 必须精确等于 `cards_all.product_id`；同一 batch 每张卡只能出现一次 |
| `winning_series_id` | 必须是 active `price_series.series_id`，且该 series 的 `card_ref` 与本行相同 |
| `observed_on` | winner 当前价格实际使用的来源业务日期，格式 `YYYY-MM-DD` |
| `amount_micros` | 当前 USD 价格，整数 micros；`1 USD = 1,000,000 micros` |
| `baseline_1d_on` | 24 小时比较目标实际命中的价格日期；允许按已批准规则回退，但不能晚于 `observed_on` |
| `baseline_1d_amount_micros` | 基准 USD 价格，必须大于 0 |
| `change_1d_percent` | STORED generated column，禁止写入；数据库按下式保留 6 位小数计算 |
| `created_at` | 省略，由数据库 `now()` 写入 |

数据库计算公式：

```text
change_1d_percent = round(
  (amount_micros - baseline_1d_amount_micros)
  * 100 / baseline_1d_amount_micros,
  6
)
```

例如当前价 `$54.00` 写为 `54000000`，基准价 `$30.00` 写为 `30000000`，数据库生成 `80.000000`。金额转换必须使用 Decimal 或任意精度整数，禁止先转 IEEE-754 浮点再乘 `1,000,000`。当前 Worker 会把 micros 转换为 USD 数值返回，所以 `winning_series_id` 必须满足 `price_series.currency_code='USD'`。

以下数据不能进入 Trending manifest：

- 当前价缺失或小于等于 0。
- 1D 基准缺失或小于等于 0。
- 生成涨幅小于等于 0。
- 当前价或基准来自未发布、非当前 pointer 指向的 batch。
- winner 与 `card_ref`、币种或固化金额/日期不一致。
- 超过已批准最大陈旧天数的当前点或基准点。

正常下跌、零涨幅或缺少基准的卡牌是“业务过滤”，不计入 `rejected_record_count`；无法解析、映射冲突、重复或违反合同的数据才是 rejected record。任何 rejected record 都必须阻止整批发布。

## 5. Manifest、checksum 与幂等键

每个 Trending batch 必须有一个不可变、可重放的 derived manifest。建议至少包含：

```json
{
  "schema_version": 1,
  "scope_code": "trending:global",
  "business_date": "2026-08-18",
  "generator_version": "collector-version",
  "rule_version": "approved-rule-version",
  "input_current_batch_ids": [123, 456],
  "rows": [
    [1, "card-ref", 789, "2026-08-18", 54000000, "2026-08-17", 30000000]
  ]
}
```

`rows` 内字段顺序依次为 `rank`、`card_ref`、`winning_series_id`、`observed_on`、`amount_micros`、`baseline_1d_on`、`baseline_1d_amount_micros`。

Schema 只要求两个 checksum 是 64 位 lowercase SHA-256，没有固定“规范化内容”的跨语言编码算法。采集程序与平台必须在首次接入时共同冻结该算法并提供测试向量；下面是建议合同，不是 migration 已经强制的事实：

1. `input_object_key` 保存 manifest 的持久化对象键或 URI，不能使用本机临时路径。
2. `input_checksum_sha256` 是完整 manifest 原始字节的 lowercase SHA-256。
3. 建议把 `content_checksum_sha256` 定义为最终 `rows` 按 `rank` 排序后，以 RFC 8785 JSON Canonicalization Scheme 编码所得 UTF-8 字节的 lowercase SHA-256。
4. `idempotency_key` 建议使用 `trending-v1:<business_date>:<input_checksum_sha256>`；同一输入重试必须使用同一个 key。
5. manifest 必须先持久化并校验 checksum，再创建数据库 batch。重试时读取同一对象，不能临时重新序列化后声称是同一输入。

如果采集程序语言没有可靠的 RFC 8785 实现，应共同选择另一种确定性编码并提供黄金样本，不能各语言自行约定 JSON 空格、键顺序或 Unicode 转义。

## 6. 写入流程

### 6.1 创建或恢复 loading batch

参数：`$1=derived source_id`、`$2=business_date`、`$3=idempotency_key`、`$4=input_object_key`、`$5=input_checksum_sha256`。

```sql
INSERT INTO price_ingest_batch (
  scope_code,
  source_id,
  business_date,
  idempotency_key,
  input_object_key,
  input_checksum_sha256
)
VALUES ('trending:global', $1, $2, $3, $4, $5)
ON CONFLICT (scope_code, idempotency_key) DO NOTHING
RETURNING batch_id, status;
```

没有返回行时，读取既有 batch：

```sql
SELECT batch_id, source_id, business_date, input_object_key,
       input_checksum_sha256, content_checksum_sha256, status
FROM price_ingest_batch
WHERE scope_code = 'trending:global'
  AND idempotency_key = $1;
```

只有所有输入元数据完全相同才能按第 8 节恢复。相同 key 对应不同 checksum 或对象键属于幂等冲突，必须停止。

### 6.2 在 staging 中生成和校验候选

Trending 列表通常较小，但仍应使用临时 staging + `COPY` 或有界多行参数化 INSERT，不能逐行并发写数据库。下面的 staging 仅存在于当前事务：

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;

CREATE TEMP TABLE staging_card_trending (
  expected_rank integer NOT NULL,
  card_ref text NOT NULL,
  winning_series_id bigint NOT NULL,
  observed_on date NOT NULL,
  amount_micros bigint NOT NULL,
  baseline_1d_on date NOT NULL,
  baseline_1d_amount_micros bigint NOT NULL
) ON COMMIT DROP;

-- 使用驱动的 COPY API 或有界多行参数化 INSERT 写入 staging_card_trending。
```

随后执行集合校验。结果中的每个错误计数都必须为 0，`row_count` 必须等于 manifest 行数且大于 0：

```sql
WITH candidate AS (
  SELECT staging.*,
         series.card_ref AS series_card_ref,
         series.currency_code,
         series.is_active,
         cards.product_id AS catalog_card_ref,
         round(
           (staging.amount_micros - staging.baseline_1d_amount_micros)::numeric
           * 100 / NULLIF(staging.baseline_1d_amount_micros, 0),
           6
         ) AS calculated_change
  FROM staging_card_trending AS staging
  LEFT JOIN price_series AS series
    ON series.series_id = staging.winning_series_id
  LEFT JOIN cards_all AS cards
    ON cards.product_id = staging.card_ref
),
ranked AS (
  SELECT candidate.*,
         row_number() OVER (
           ORDER BY calculated_change DESC,
                    amount_micros DESC,
                    coalesce((
                      SELECT name FROM cards_all
                      WHERE product_id = candidate.card_ref
                    ), candidate.card_ref) COLLATE "C" ASC,
                    card_ref ASC
         )::integer AS calculated_rank
  FROM candidate
)
SELECT
  count(*) AS row_count,
  count(*) - count(DISTINCT card_ref) AS duplicate_card_count,
  count(*) - count(DISTINCT winning_series_id) AS duplicate_winner_count,
  count(*) FILTER (WHERE catalog_card_ref IS NULL) AS missing_card_count,
  count(*) FILTER (WHERE series_card_ref IS NULL) AS missing_series_count,
  count(*) FILTER (WHERE series_card_ref IS DISTINCT FROM card_ref) AS series_card_mismatch_count,
  count(*) FILTER (WHERE NOT coalesce(is_active, false)) AS inactive_series_count,
  count(*) FILTER (WHERE currency_code IS DISTINCT FROM 'USD') AS non_usd_count,
  count(*) FILTER (
    WHERE amount_micros <= 0
       OR baseline_1d_amount_micros <= 0
       OR baseline_1d_on > observed_on
       OR calculated_change <= 0
  ) AS invalid_value_count,
  count(*) FILTER (WHERE expected_rank <> calculated_rank) AS rank_mismatch_count
FROM ranked;
```

还必须确认每行固化值与某个当前可见的 published snapshot 完全一致。下面的查询必须返回 0：

```sql
SELECT count(*) AS unpublished_or_mismatched_price_count
FROM staging_card_trending AS staging
WHERE NOT EXISTS (
  SELECT 1
  FROM price_series AS series
  JOIN price_current_snapshot AS current
    ON current.series_id = series.series_id
  JOIN current_price_pointer AS pointer
    ON pointer.batch_id = current.batch_id
   AND pointer.scope_code LIKE 'current:%'
  JOIN price_ingest_batch AS batch
    ON batch.batch_id = current.batch_id
   AND batch.scope_code = pointer.scope_code
   AND batch.source_id = series.source_id
   AND batch.status = 'published'
  WHERE series.series_id = staging.winning_series_id
    AND series.card_ref = staging.card_ref
    AND series.currency_code = 'USD'
    AND series.is_active
    AND current.observed_on = staging.observed_on
    AND current.amount_micros = staging.amount_micros
    AND current.baseline_1d_on = staging.baseline_1d_on
    AND current.baseline_1d_amount_micros = staging.baseline_1d_amount_micros
);
```

应用层还要检查 manifest 的 `input_current_batch_ids` 与上述实际 pointer batch 集合一致，并执行已批准的最大陈旧天数、业务时区和 winner 规则校验。

### 6.3 写入快照

全部校验通过后，在同一 staging 事务中写入目标表。`change_1d_percent` 和 `created_at` 不在 INSERT 列表中：

```sql
WITH ranked AS (
  SELECT staging.*,
         row_number() OVER (
           ORDER BY round(
                      (amount_micros - baseline_1d_amount_micros)::numeric
                      * 100 / baseline_1d_amount_micros,
                      6
                    ) DESC,
                    amount_micros DESC,
                    coalesce(cards.name, staging.card_ref) COLLATE "C" ASC,
                    staging.card_ref ASC
         )::integer AS calculated_rank
  FROM staging_card_trending AS staging
  JOIN cards_all AS cards
    ON cards.product_id = staging.card_ref
)
INSERT INTO card_trending_snapshot (
  batch_id,
  rank,
  card_ref,
  winning_series_id,
  observed_on,
  amount_micros,
  baseline_1d_on,
  baseline_1d_amount_micros
)
SELECT $1,
       calculated_rank,
       card_ref,
       winning_series_id,
       observed_on,
       amount_micros,
       baseline_1d_on,
       baseline_1d_amount_micros
FROM ranked
ORDER BY calculated_rank;

COMMIT;
```

`$1` 是仍处于 `loading` 的 Trending batch ID。INSERT 必须恰好写入 manifest 行数；任何主键、唯一键、外键或 CHECK 失败都回滚整次 staging 事务。

### 6.4 把 batch 标记为 validated

参数：`$1=batch_id`、`$2=manifest row count`、`$3=content_checksum_sha256`。

```sql
WITH stats AS (
  SELECT count(*) AS row_count,
         count(DISTINCT winning_series_id) AS distinct_series_count,
         min(observed_on) AS min_observed_on,
         max(observed_on) AS max_observed_on
  FROM card_trending_snapshot
  WHERE batch_id = $1
)
UPDATE price_ingest_batch AS batch
SET expected_series_count = stats.row_count,
    loaded_series_count = stats.row_count,
    distinct_series_count = stats.distinct_series_count,
    rejected_record_count = 0,
    min_observed_on = stats.min_observed_on,
    max_observed_on = stats.max_observed_on,
    content_checksum_sha256 = $3,
    status = 'validated',
    validated_at = now(),
    updated_at = now()
FROM stats
WHERE batch.batch_id = $1
  AND batch.scope_code = 'trending:global'
  AND batch.status = 'loading'
  AND stats.row_count = $2
  AND stats.row_count > 0
  AND stats.distinct_series_count = stats.row_count;
```

受影响行数必须等于 1。Schema 允许 0 行 batch，但采集程序默认不得用空批次清空线上 Trending；确需发布空榜必须有单独人工批准和告警记录。

### 6.5 原子发布 pointer

同一 scope 的发布必须串行。应用在事务内读取并保存旧 Trending pointer batch ID；首次发布时旧 ID 为空。下面参数为 `$1=new_batch_id`、`$2=updated_by`、`$3=input_current_batch_ids`、`$4=old_trending_batch_id`。

```sql
BEGIN;

SELECT pg_advisory_xact_lock(hashtextextended('trending:global', 0));

SELECT batch_id
FROM current_price_pointer
WHERE scope_code = 'trending:global'
FOR UPDATE;

SELECT batch_id
FROM price_ingest_batch
WHERE batch_id = $1
  AND scope_code = 'trending:global'
  AND status = 'validated'
FOR UPDATE;

-- 上一条必须恰好返回一行。

SELECT pointer.scope_code, pointer.batch_id
FROM current_price_pointer AS pointer
JOIN price_ingest_batch AS input_batch
  ON input_batch.batch_id = pointer.batch_id
 AND input_batch.scope_code = pointer.scope_code
 AND input_batch.status = 'published'
WHERE pointer.scope_code LIKE 'current:%'
  AND pointer.batch_id = ANY($3::bigint[])
FOR SHARE OF pointer, input_batch;

-- 返回的 batch_id 集合必须与 manifest 中去重后的 input_current_batch_ids 完全相等。
-- FOR SHARE 使这些输入 pointer 和 batch 在本事务结束前不能被切换或 supersede。

SELECT count(*) AS unpublished_or_mismatched_price_count
FROM card_trending_snapshot AS trend
WHERE trend.batch_id = $1
  AND NOT EXISTS (
    SELECT 1
    FROM price_series AS series
    JOIN price_current_snapshot AS current
      ON current.series_id = series.series_id
    JOIN current_price_pointer AS pointer
      ON pointer.batch_id = current.batch_id
     AND pointer.scope_code LIKE 'current:%'
    JOIN price_ingest_batch AS input_batch
      ON input_batch.batch_id = current.batch_id
     AND input_batch.scope_code = pointer.scope_code
     AND input_batch.source_id = series.source_id
     AND input_batch.status = 'published'
    WHERE current.batch_id = ANY($3::bigint[])
      AND series.series_id = trend.winning_series_id
      AND series.card_ref = trend.card_ref
      AND series.currency_code = 'USD'
      AND series.is_active
      AND current.observed_on = trend.observed_on
      AND current.amount_micros = trend.amount_micros
      AND current.baseline_1d_on = trend.baseline_1d_on
      AND current.baseline_1d_amount_micros = trend.baseline_1d_amount_micros
  );

-- 结果必须为 0；这里校验目标表，因为第 6.2 节的临时 staging 已在 COMMIT 后删除。

UPDATE price_ingest_batch
SET status = 'published',
    published_at = now(),
    updated_at = now()
WHERE batch_id = $1
  AND scope_code = 'trending:global'
  AND status = 'validated';

-- UPDATE 受影响行数必须等于 1。

INSERT INTO current_price_pointer (scope_code, batch_id, updated_at, updated_by)
VALUES ('trending:global', $1, now(), $2)
ON CONFLICT (scope_code) DO UPDATE
SET batch_id = EXCLUDED.batch_id,
    updated_at = EXCLUDED.updated_at,
    updated_by = EXCLUDED.updated_by;

-- 首次发布时跳过；否则使用事务开始时保存的旧 batch ID。
UPDATE price_ingest_batch
SET status = 'superseded',
    updated_at = now()
WHERE batch_id = $4
  AND scope_code = 'trending:global'
  AND batch_id <> $1
  AND status = 'published';

COMMIT;
```

顺序不能调整：先把新 batch 设为 `published`，再切 pointer，最后 supersede 旧 batch。数据库 trigger 会拒绝 pointer 指向非 published batch，也会拒绝在 pointer 尚未移走时 supersede 旧 batch。任一步失败必须回滚整个事务。

## 7. 发布后验证

发布成功后至少执行以下只读检查：

```sql
SELECT pointer.scope_code,
       pointer.batch_id,
       batch.status,
       batch.business_date,
       batch.expected_series_count,
       batch.loaded_series_count,
       batch.content_checksum_sha256,
       pointer.updated_at,
       pointer.updated_by
FROM current_price_pointer AS pointer
JOIN price_ingest_batch AS batch
  ON batch.batch_id = pointer.batch_id
 AND batch.scope_code = pointer.scope_code
WHERE pointer.scope_code = 'trending:global';

SELECT count(*) AS row_count,
       min(rank) AS min_rank,
       max(rank) AS max_rank,
       count(DISTINCT rank) AS distinct_rank_count,
       count(DISTINCT card_ref) AS distinct_card_count,
       min(observed_on) AS min_observed_on,
       max(observed_on) AS max_observed_on
FROM card_trending_snapshot
WHERE batch_id = $1;
```

验收条件：

- pointer 指向新 batch，batch 状态为 `published`。
- `row_count = distinct_rank_count = distinct_card_count = max_rank`，且 `min_rank = 1`。
- 行数、日期范围和 checksum 与 manifest 一致。
- 第 6.5 节的发布前一致性查询返回 0，且当时锁定的 current batch 集合与 manifest 完全一致。
- `GET /api/v1/cards/trending?page=1&page_size=40` 返回相同顺序、USD 当前价、1D 基准价和涨幅。
- 首页只展示榜单前三张，View All 分页后顺序连续且没有重复卡牌。

当前 Worker 代码不会通过 KV 或 Cache API 缓存 Trending 结果；Hyperdrive 查询缓存属于目标连接的运行配置，发布器接入时必须确认其实际状态。只要任一层启用了 Trending 缓存，pointer 发布流程就必须同时定义缓存失效，不能假设数据库写入会自动清除外部缓存。

发布事务提交后，外部来源可以继续发布新的 current batch，并把 Trending manifest 中的输入 batch 变为 `superseded`；这是正常快照演进，不会使已经发布的 Trending 自动失效。后续审计应按 manifest 的 `input_current_batch_ids` 对账 `published/superseded` 输入快照，不能要求它们永久保持当前 pointer。

## 8. 重试、失败与回退

### 8.1 按 batch 状态处理重试

| 状态 | 处理 |
|---|---|
| `loading` | 仅当 input metadata 和 checksum 完全一致时恢复。若已有快照行，先从数据库读回并与 canonical manifest 逐字段、逐 rank 比对；一致则继续 validate，不一致则标记 failed |
| `validated` | 不再写快照；重新执行完整校验后进入发布事务 |
| `published` | 若 pointer 已指向该 batch，视为幂等成功；否则停止并人工排查状态竞争 |
| `superseded` | 历史成功批次，不得重写；只有正式回退流程可以重新发布 |
| `failed` | 不得复活或复用；修正输入后使用新的 manifest、checksum 和 idempotency key 创建新 batch |

不得对 `card_trending_snapshot` 使用 `ON CONFLICT DO UPDATE`，也不得向 `validated`、`published` 或 `superseded` batch 继续 INSERT。采集账号不应拥有该表的 UPDATE/DELETE 权限，但当前 Schema 没有按 batch 状态拦截 INSERT 的 immutable trigger，因此“校验后不再写行”仍是程序侧硬约束；若需要数据库强制，应另行批准 trigger 或受控存储过程变更，不能声称现有权限已经覆盖这一点。

### 8.2 发布前失败

无法通过校验的未发布 batch 应保留诊断信息并显式失败：

```sql
UPDATE price_ingest_batch
SET status = 'failed',
    failed_at = now(),
    failure_reason = $2,
    updated_at = now()
WHERE batch_id = $1
  AND scope_code = 'trending:global'
  AND status IN ('loading', 'validated');
```

`failure_reason` 只记录错误分类、计数和安全的对象键，不得写入凭据、完整供应商 payload 或个人数据。失败 batch 的行和审计记录默认保留；删除属于独立运维操作。

### 8.3 已发布批次回退

发现线上批次错误时，不能原地改数据。确认上一批快照完整后，使用与发布相同的 advisory lock 和单事务顺序：

1. 把目标旧 batch 从 `superseded` 条件更新为 `published`。
2. 把 `trending:global` pointer 切回旧 batch。
3. 把问题 batch 从 `published` 更新为 `superseded`。
4. 提交后重新执行第 7 节验证。

回退、删除 batch 或清理历史行都属于数据库写操作，必须按目标环境单独授权。不得通过 D1、旧 `tcg_price` 或 `trending_pin` 恢复。

## 9. 权限与运行要求

建议为 Trending 发布器建立独立数据库角色，权限收敛为：

- `SELECT`：`cards_all`、`price_source`、`price_series`、`price_current_snapshot`、`price_ingest_batch`、`card_trending_snapshot`、`current_price_pointer`。
- `INSERT`：`price_ingest_batch`、`card_trending_snapshot`、`current_price_pointer`。
- `UPDATE`：仅 `price_ingest_batch` 和 `current_price_pointer` 发布所需列。
- `USAGE`：`price_ingest_batch` identity sequence。
- `TEMP`：需要使用临时 staging/COPY 时授予。
- 不授予业务表 `DELETE`、永久 `CREATE`、`ALTER`、`DROP` 或 migration 权限。

程序要求：

- TLS 连接、凭据来自 secret manager，不进入源码、日志、manifest 或本文档。
- 所有 SQL 参数化；表名不由上游输入拼接。
- 同一 `trending:global` 发布使用数据库 advisory lock，应用重试使用有上限的指数退避。
- 对 serialization、连接中断和超时可以重试；对约束、checksum、映射或幂等冲突不能盲目重试。
- 记录 batch ID、业务日期、规则版本、输入/内容 checksum、行数、拒绝数、耗时和发布结果；不记录敏感 payload。
- 对长时间停留在 `loading`/`validated`、连续空候选、行数突降、价格或涨幅异常、基准过旧和 API 验证失败建立告警。

## 10. 交付验收清单

采集程序交付前应提供以下证据：

- [ ] 上游字段样例、卡牌映射和 winner 规则已批准并版本化。
- [ ] 金额到 micros 的黄金样本覆盖小数、极值、0、负数和超出 bigint。
- [ ] 1D 基准黄金样本覆盖精确命中、向前回退、向后回退、缺失和过旧。
- [ ] manifest canonicalization、input/content checksum 在目标语言中有固定测试向量。
- [ ] 同一输入执行两次只产生一个 batch，且第二次不会重复写行。
- [ ] 重复 card、错误 series、非 USD、未发布 current、0 基准、非正涨幅和 rank 漂移全部显式失败。
- [ ] 发布期间旧 pointer 持续可读，提交后一次切换到新 batch，不出现半批数据。
- [ ] 并发发布只有一个成功，其余任务读到最终状态后安全退出或重试。
- [ ] 采集账号不能 UPDATE/DELETE 快照行，程序也已验证不会向 validated/published/superseded batch 追加 INSERT；已知现有 Schema 不会替程序拦截后者。
- [ ] 隔离环境完成发布、API 比对、故障注入和 pointer 回退演练。
- [ ] 真实数据写入和目标环境权限已单独批准；没有把隔离测试结果冒充生产验证。

## 11. 参考

- [PostgreSQL 价格域详细 DDL 设计](research/price-domain-postgresql-ddl.md)
- [数据迁移与当前价格域状态](migration.md)
- [v1.1 Price Change / Trending Change 产品口径](../00-product/TCG_Card_App_v1.1_PRD.md#1410-price-change--trending-change)
- [v1.0 Trending Today 业务规则](../../v1.0.0/00-product/modules/home.md#七trending-today-区域)
- [`card_trending_snapshot` 建表 migration](../../../../apps/workers-api/src/db/postgres/migrations/0001_price_domain.sql)
- [Workers Trending 读取实现](../../../../apps/workers-api/src/data-source/local-db-adapter.ts)
