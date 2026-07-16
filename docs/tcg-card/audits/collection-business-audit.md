# Collection 业务审计

## 0. 文档说明

- 分析范围：Flutter Collection 页面、Portfolio/Wishlist API、D1 资产与价格表，以及 PRD 第八章。
- 设计真源：Figma `DjacfTioobtRy59SnqH7SY`，Portfolio `142:10516`、Wishlist `847:15418`。
- 结论等级：`代码明确` 表示可执行代码有直接证据；`代码推断` 表示多处证据一致但缺少显式产品声明；`待确认` 表示当前实现或数据源不足。
- 本文记录审计事实，不以进度文档中的完成标记作为验收证据。

## 1. 业务总览与主线

Collection 是用户管理已拥有卡牌与关注卡牌的核心页面。完整闭环为：游客或登录用户通过 Search、Scan、Card Detail 将卡牌加入 Portfolio 或 Wishlist -> 服务端按 owner 保存记录 -> Collection 按当前文件夹展示每一条 Collection Item -> 按该条记录的状态取得当前价及 30D 基准 -> 用户可筛选、移动、编辑或删除 -> Home 资产与历史估值同步刷新。

| 模块 | 业务职责 | 入口/接口 | 结论 |
|---|---|---|---|
| Portfolio | 管理已拥有资产和文件夹 | `/portfolio/folders`、`/portfolio/items` | 代码明确 |
| Wishlist | 管理关注但未拥有的卡牌 | `/wishlist` | 代码明确 |
| Collection 页面 | 搜索、筛选、排序、汇总并导航详情 | `CollectionPage`、`CollectionController` | 代码明确 |
| 价格数据 | Raw SKU 当前价和历史价 | `tcgplayer_skus.price_history` | 代码明确 |
| Home | 消费当前文件夹的资产与历史估值 | `/portfolio/valuation-history` | 代码明确 |

## 2. 用户角色与权限

| 身份 | 页面与操作 | 数据范围 | 证据 | 结论 |
|---|---|---|---|---|
| 游客 | 可建文件夹、增删改 Collection Item、管理 Wishlist | `owner_type=anonymous` 且 `owner_id` 为当前匿名账号 | `owner-auth.ts: authenticateOwner()`；`portfolio/routes.ts` | 代码明确 |
| 登录用户 | 与游客相同，并可接收游客资产迁移 | `owner_type=user` 且 `owner_id` 为当前用户 | `auth/guest-migration.ts`；`portfolio/routes.ts` | 代码明确 |
| 未认证请求 | 不可读取或修改 Collection 数据 | 返回 401 | `portfolio/routes.ts: createPortfolioRoutes()` | 代码明确 |

前端页面可见性不是权限边界。所有 Portfolio、Wishlist、偏好查询及写入均在 Workers 重新鉴权并按 owner 过滤。

## 3. 核心业务流程

### 3.1 Portfolio

选择当前文件夹 -> 加载该 owner 的文件夹和资产 -> 按 `folder_id` 限定展示 -> 每条 Collection Item 按 Grader、Condition/Grade、Language、Finish 匹配价格 -> 计算当前价值与 30D Change -> 编辑、移动或删除后刷新 Collection 和 Home。

| 动作 | 服务端结果 | 下游影响 | 结论 |
|---|---|---|---|
| 新增资产 | 写入 `collection_item` 和 `collection_item_event`，并删除同卡 Wishlist | Collection、Home、Qty、历史曲线 | 代码明确 |
| 编辑资产 | 更新状态字段并追加 `upsert` 事件 | 当前价格、汇总、历史曲线 | 代码明确 |
| 移动文件夹 | 更新 `folder_id` 并追加 `upsert` 事件 | 原/目标文件夹汇总与历史 | 代码明确 |
| 删除资产 | 删除当前记录并追加 `delete` 事件 | 删除后不再计入资产，删除前历史保留 | 代码明确 |

### 3.2 Wishlist

加入 Wishlist -> 服务端拒绝已存在于 Portfolio 的卡牌 -> Collection Wishlist 展示市场参考价 -> 加入 Portfolio 成功后自动删除 Wishlist。Portfolio 删除后不会自动恢复 Wishlist。

### 3.3 异常流程

| 场景 | 当前行为 | 风险/要求 | 结论 |
|---|---|---|---|
| 卡牌基础数据缺失 | 资产记录仍应保留 | 展示基础兜底，价格 `--` | PRD 明确，接口整改待完成 |
| 市场价缺失 | 可保存资产，数值为空 | 不计入总资产、Most Valuable | 代码明确 |
| 默认文件夹删除 | 服务端返回 403 | UI 应保留原状态并提示 | 代码明确 |
| 同卡加入 Wishlist 与 Portfolio | Portfolio 优先，Wishlist 写入冲突或被删除 | 不允许共存 | 代码明确 |

## 4. 核心数据实体

| 实体 | 关键字段 | 关系与生命周期 | 证据 |
|---|---|---|---|
| `portfolio_folder` | owner、name、is_default、sort_order | 一个 owner 有多个文件夹；默认文件夹不可删除 | `db/schema.ts` |
| `collection_item` | folder_id、card_ref、grader、condition/grade、language、finish、quantity | 一张卡可有多条独立资产记录 | `db/schema.ts` |
| `collection_item_event` | item_id、完整定价状态、event_type、effective_at | 保存不可变 upsert/delete 历史 | `0004_collection_item_event.sql` |
| `wishlist_item` | owner、card_ref、created_at | owner 内同卡唯一，不属于文件夹 | `db/schema.ts` |
| `user_preference` | currency、amount_hidden、last_selected_folder_id | owner 级 Collection/Home 共享偏好 | `db/schema.ts` |
| `cards_all` | product_id、game、set_name、name、image_url | Collection 展示数据上游 | `db/schema.ts` |
| `tcgplayer_skus` | product_id、condition、language、variant、price_history | Raw 当前价和 30D 基准上游 | `db/schema.ts` |

## 5. 业务规则与计算

| 规则 | 公式/约束 | 当前状态 | 结论 |
|---|---|---|---|
| Portfolio 当前价值 | 匹配市场单价 x Quantity | Raw 可计算；Graded 无真实数据时为空 | 代码明确 |
| Portfolio 总值 | 当前文件夹有效 Item 当前价值之和 | Wishlist 与缺价项不计入 | 代码明确 |
| 30D Change | `(当前单价 - 30D 基准价) / 30D 基准价` | 缺任一价格时为空 | 代码明确 |
| Raw 取价 | Raw + Condition，并受 Language、Finish 约束 | D1 SKU 支持 | 代码明确 |
| Graded 取价 | Grader + Grade | D1 无评级价格源，不得用 Raw 冒充 | 待确认/上线依赖 |
| 默认排序 | 加入当前文件夹或 Wishlist 时间倒序 | Flutter 本地执行 | 代码明确 |
| 缺失值排序 | 价格或涨跌幅缺失项置底 | 需要自动化测试持续保护 | 代码推断 |

## 6. 上下游与影响面

| 依赖 | 方向 | 失败影响 | 证据 |
|---|---|---|---|
| Auth session | 上游 | 无法确定 owner，Collection 返回 401 | `owner-auth.ts` |
| D1 资产表 | 上游 | 文件夹、资产或 Wishlist 无法加载/写入 | `portfolio/routes.ts` |
| `cards_all` / `tcgplayer_skus` | 上游 | 基础信息或价格显示为空，但不得删除用户资产 | `valuation-history.ts` |
| Home | 下游 | 文件夹选择、金额隐藏、资产价值与曲线需刷新 | `home_repository.dart` |
| Search/Card Detail/Scan | 上下游 | 收藏状态、Qty、加入/移除结果需刷新 | PRD 全局联动规则 |

## 7. 术语

| 术语 | 含义 | 结论 |
|---|---|---|
| Collection Item | 一条独立持有记录，同卡可有多条 | 代码明确 |
| Portfolio | 按文件夹组织且参与资产统计的已拥有卡牌 | 代码明确 |
| Wishlist | 不参与资产统计的关注卡牌列表 | 代码明确 |
| Raw | 未经评级机构封装的卡牌，按 Condition 取价 | 代码明确 |
| Graded | 经 PSA/BGS 等机构评级的卡牌，按 Grader + Grade 取价 | PRD 明确，数据源待确认 |
| Finish/Variant | Normal、Holofoil 等印刷版本，是价格匹配维度 | 代码明确 |

## 8. 证据索引

| 编号 | 文件/位置 | 说明 |
|---|---|---|
| E1 | `apps/flutter-app/lib/features/collection/collection_repository.dart` | 当前加载链路与逐卡请求 |
| E2 | `apps/flutter-app/lib/features/collection/collection_controller.dart` | 文件夹范围、筛选、排序与汇总 |
| E3 | `apps/flutter-app/lib/shared/portfolio/portfolio_api_client.dart` | Flutter Portfolio/Wishlist API 合约 |
| E4 | `apps/workers-api/src/portfolio/routes.ts` | owner 鉴权、CRUD、分页与互斥规则 |
| E5 | `apps/workers-api/src/portfolio/valuation-history.ts` | Raw SKU 匹配、当前值和历史值 |
| E6 | `apps/workers-api/src/db/schema.ts` | D1 实体、索引与约束 |
| E7 | `docs/tcg-card/source-tcg-card-docs/20260708/TCG_PRD_整合版.md:1852` | Collection 产品规则 |
| E8 | Figma `142:10516`、`847:15418` | Portfolio/Wishlist 页面设计真源 |

## 9. 待确认问题与上线阻断

| 问题 | 影响 | 当前决定 |
|---|---|---|
| 没有真实 Graded 价格源 | Graded Item 当前价、30D Change、总资产均无法计算 | 显示 `--`，不以 Raw 冒充；接入数据源前作为上线依赖 |
| 当前 Flutter 按卡请求基础信息、市场价、30D 曲线 | 数据量增长后产生严重 N+1 和超时 | 改为服务端 Collection dashboard 批量接口 |
| 旧列表客户端固定 `page_size=100` 且不翻页 | 第 101 条起静默不可见 | dashboard 必须返回 owner 的完整集合，旧列表只保留其他页面兼容 |
| 生产价格历史覆盖率与新鲜度不足 | 大量价格和 30D Change 为空或陈旧 | 不插测试价格掩盖；列为数据管线上线依赖 |
