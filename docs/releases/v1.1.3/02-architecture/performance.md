# 查询、缓存与列表性能

更新日期：2026-10-30（Asia/Shanghai）。本文描述性能优化及观测口径；当前增量已随 `dev@c5908c32` 发布 Linux dev，prod 尚未部署。dev 的单次计划与冷／热烟测不代表真实流量 P50/P95 或 prod 验收通过。

## 请求级观测

共享 API 继续输出一条 `api_request` 完成日志，并沿用 `request_id`、路由模板、HTTP 状态和总耗时。有 PostgreSQL 查询或目录缓存读取时，日志附加 `performance`：

- `sql.count`、`duration_ms`、`max_duration_ms`、`returned_rows`、`errors` 分别表示请求处理期间完成的查询数、客户端累计查询耗时、最慢单次耗时、返回行数和失败次数。
- `sql.statements` 按 SQL 指纹聚合相同指标；指纹为 SQL 去除首尾空白、合并连续空白后 SHA-256 的前 16 个十六进制字符。不记录 SQL 原文、绑定参数、缓存键或搜索词。它用于关联同一查询形状，不是 PostgreSQL 的 `queryid`。
- 每个请求最多保存 20 种指纹，额外查询仍计入总量，并通过 `overflow_count` 记录未展开的次数，防止日志随查询种类无限增大。
- `cache.kv` 记录 Cards 搜索结果 KV 读取的 `hit/miss/error`；`cache.cache_api` 记录行情与价格历史 Cache API 的对应计数。缓存异常与正常未命中分开，两者都继续走既有回源逻辑。未覆盖其他业务的 KV 用法。
- Node/Linux 与 Workers 使用 `AsyncLocalStorage` 隔离并发请求。完成日志只统计前台请求期间已结束的操作；响应结束后才完成的后台任务不补写这条日志。定时任务不借用 HTTP 请求指标。

SQL 时间包含连接排队、网络与驱动处理；并发查询耗时累加可能超过请求总耗时。`returned_rows` 不是扫描行数，既有数据库适配器 `meta.rows_read` 的兼容语义不变。索引效果仍需目标 PostgreSQL 的 `EXPLAIN (ANALYZE, BUFFERS)`，平台支持时结合 `pg_stat_statements`，不能从返回 40 行推断只扫描 40 行。

后续按同接口、相同参数规模、缓存命中状态比较请求 P50/P95、SQL 次数和时间。安装统计、扫描 Review 的多变体行情请求、大收藏账号的分页加载先用这些指标定位；本次不改其业务口径、价格变体组合或分页协议。

## Linux dev 缓存生命周期

Linux 的进程内 KV 为带 TTL 的条目维护一个 60 秒清扫计时器，使用 `unref`，无需再次访问旧键也会回收过期项；没有 TTL 条目后停止计时。读取过期值仍立即返回未命中。

可重建的 TTL 缓存最多保留 10,000 条、约 32 MiB 的 key/value UTF-16 字符估算量，超限先清理过期项，再按最旧写入顺序淘汰；单条超过预算时不保留，且不返回被覆盖的旧值。这是缓存预算，不是 Node 堆内存硬上限，也未包含对象和 metadata 的全部开销。

无 TTL 条目不参与容量淘汰，保留当前唯一的无 TTL 业务键——汇率提供商失败时使用的旧汇率兜底。未来新增无 TTL 业务键时须重新评估容量。Cloudflare prod 的原生 KV 路径不使用该 Map 实现。

## 客户端与后台

- Flutter Search 在一次线性遍历中叠加卡牌覆盖值并筛选，页面构建复用当前标签的可见列表；保持原顺序、收藏覆盖、分页与空态。该改动共用于 iOS/Android，不改变布局。
- Admin 扫描列表只查询列表响应使用的字段；`system_result` 仍可用于卡牌类型筛选，但不随列表行传输。详情继续读取完整记录，私有图片路由只读取图片键。
- Admin 列表和详情通过现有 TanStack Query 共享同一 token/path 的在途请求与 Blob。最后一个使用者卸载后不保留缓存，未完成请求可取消；各组件分别创建和撤销自己的 Object URL。继续使用 Bearer 鉴权、401 会话过期通知及 `private, no-store`，没有浏览器持久缓存或公共图片缓存。
- 图片复用减少列表已加载原图后打开详情的重复请求；列表首次加载仍下载原图。生成专用缩略图需要真实图片大小与网络基准，未在本次引入新的图片处理服务、存储格式或回填任务。

Cards 数据库优化见 [Cards 与 Sets 排序及索引](../03-data-api/cards-search-order.md#postgresql-0017-可见卡牌数值排序索引)。dev 发布证据、本地测试和未验边界见 [验证记录](../05-delivery/VERIFICATION.md#dev-performance-release-20261030)。
