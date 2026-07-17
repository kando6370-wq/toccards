# Collection 业务审计

## 0. 文档说明

- 分析范围：Flutter Collection 页面、Portfolio/Wishlist API、D1 资产与价格表，以及 PRD 第八章。
- 设计真源：Figma `DjacfTioobtRy59SnqH7SY`，Portfolio `142:10516`、Wishlist `847:15418`。
- 结论等级：`代码明确` 表示可执行代码有直接证据；`代码推断` 表示多处证据一致但缺少显式产品声明；`待确认` 表示当前实现或数据源不足。
- 本文记录审计事实，不以进度文档中的完成标记作为验收证据。
- 审计日期：2026-07-17。

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

冷启动时 `selectedPortfolioFolderProvider` 重新为空，Controller 选择星标默认文件夹；本次运行内从 Home 或 Collection 手动选择后，该内存状态优先并跨页面同步。服务端虽保存 `last_selected_folder_id`，Flutter 冷启动加载时不读取它，符合“下一次冷启动回到默认文件夹”的 PRD 规则。

| 动作 | 服务端结果 | 下游影响 | 结论 |
|---|---|---|---|
| 新增资产 | 写入 `collection_item` 和 `collection_item_event`，并删除同卡 Wishlist | Collection、Home、Qty、历史曲线 | 代码明确 |
| 编辑资产 | 同一 Item PATCH 原子更新状态字段与可选 `folder_id`，并在同一 D1 batch 追加 `upsert` 事件 | 当前价格、原/目标文件夹汇总与历史曲线 | 代码明确 |
| 纯移动文件夹 | `/portfolio/items/:item_id/move` 更新 `folder_id` 与 `folder_joined_at`，并追加 `upsert` 事件 | 原/目标文件夹汇总与历史 | 代码明确 |
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
| Collection 直接分享入口 | Figma Portfolio `142:10516` 无卡片分享按钮；点击卡片进入 Card Detail 后使用 iOS 原生分享 | 采用 Figma 真源，PRD 的“列表直接分享”文案待清理 | 代码明确/文档冲突 |

## 4. 核心数据实体

| 实体 | 关键字段 | 关系与生命周期 | 证据 |
|---|---|---|---|
| `portfolio_folder` | owner、name、is_default、sort_order | 一个 owner 有多个文件夹；默认文件夹不可删除 | `db/schema.ts` |
| `collection_item` | folder_id、folder_joined_at、card_ref、grader、condition/grade、language、finish、quantity | 一张卡可有多条独立资产记录；仅移动文件夹时刷新加入当前文件夹时间 | `db/schema.ts`、`0005_collection_item_folder_joined_at.sql` |
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
| 默认排序 | Portfolio 按 `folder_joined_at` 倒序；Wishlist 按 `created_at` 倒序 | Workers 列表默认值和 Flutter `Newest` 使用同一业务时间；普通字段编辑不改变该时间 | 代码明确 |
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
| E1 | `apps/flutter-app/lib/features/collection/collection_repository.dart` | Collection dashboard 单接口加载与业务时间映射 |
| E2 | `apps/flutter-app/lib/features/collection/collection_controller.dart` | 文件夹范围、筛选、排序与汇总 |
| E3 | `apps/flutter-app/lib/shared/portfolio/portfolio_api_client.dart` | Flutter Portfolio/Wishlist API 合约 |
| E4 | `apps/workers-api/src/portfolio/routes.ts` | owner 鉴权、CRUD、分页与互斥规则 |
| E5 | `apps/workers-api/src/portfolio/valuation-history.ts` | Raw SKU 匹配、当前值和历史值 |
| E6 | `apps/workers-api/src/db/schema.ts`、`0005_collection_item_folder_joined_at.sql` | D1 实体、加入当前文件夹时间与旧数据回填 |
| E7 | `docs/tcg-card/source-tcg-card-docs/20260708/TCG_PRD_整合版.md:1852` | Collection 产品规则 |
| E8 | Figma `142:10516`、`847:15418` | Portfolio/Wishlist 页面设计真源 |
| E9 | `apps/flutter-app/lib/shared/portfolio/portfolio_providers.dart` | 本次运行内 Home/Collection 文件夹联动；冷启动状态重新为空 |

## 9. 待确认问题与上线阻断

| 问题 | 影响 | 当前决定 |
|---|---|---|
| 没有真实 Graded 价格源 | Graded Item 当前价、30D Change、总资产均无法计算 | 显示 `--`，不以 Raw 冒充；接入数据源前作为上线依赖 |
| 生产价格历史覆盖率与新鲜度不足 | 4066 个目录 product 中仅 10 个存在 SKU 价格，最新日期为 2026-04-12 | 不插测试价格掩盖；外部采集程序补齐前为 P0 数据管线上线依赖 |
| 实时浏览器视觉验收未完成 | 无法对当前 LAN Web 与 Figma 做实时像素对照 | 浏览器运行时失败：`failed to write kernel assets: 系统找不到指定的路径 (os error 3)`；iOS 截图前必须补验 |

## 10. 本轮整改与验证

| 项目 | 结果 | 证据 |
|---|---|---|
| Collection 聚合接口 | 已完成；单次返回文件夹、偏好、完整 Portfolio/Wishlist、卡牌展示字段、当前价和 30D 基准 | `816679e`；`GET /collection/dashboard` |
| 100 条静默截断 | Collection 主页面已消除；聚合接口不分页，自动化测试覆盖 101 条资产 | `collection-dashboard.test.ts` |
| Flutter N+1 | 已消除；Collection Repository 只调用聚合接口，旧逐卡卡牌/价格/曲线调用为零 | `96ebfe3`；`collection_controller_test.dart` |
| Graded 定价 | 保持空价，不使用 Raw 冒充 | `collection-dashboard.test.ts` |
| 编辑时移动 | Flutter Item PATCH 发送 `folder_id`；Workers 在同一 batch 更新文件夹、字段和历史事件，目标文件夹按 owner 校验 | `1545251`、`8d9b776`；生产真实 API 闭环 |
| 默认排序 | 新增并回填 `folder_joined_at`；移动刷新、普通编辑保持不变，Portfolio 默认按该时间倒序 | `07ff54c`、`7c53d9b`；`items.test.ts` |
| Workers 验证 | 26 个文件、242 项测试、TypeScript 类型检查与 dry-run 构建通过 | 2026-07-17 最新 HEAD 验证 |
| Flutter 验证 | 344 项通过、1 项原生 OpenCV 条件测试跳过；`flutter analyze` 无问题 | 2026-07-17 最新 HEAD 验证 |
| 生产部署 | 0005 已应用；当前 Workers 版本 `1c9c6511-f395-4848-8885-dbf9a0eb58ef` | Cloudflare 生产回读 |
| 生产真实业务 smoke | 临时游客 Main：`9359 / Escape Artist` 先加入 Wishlist，再创建 Quantity `2` 的 Portfolio Item；Dashboard 返回当前价 `0.21`、30D 基准 `0.20`，Wishlist 自动归零；临时账号已删除 | 生产 API 2026-07-17 实测 |
| 生产数据覆盖 | `collection_item` 仅 5 条且全部 Raw；`tcgplayer_skus` 61 行、10 个 product，目录 4066 个 product，最新价格 2026-04-12 | 生产 D1 只读聚合 2026-07-17 |

代码主链路已闭环；仍未解除的上线依赖是外部采集程序负责的生产价格覆盖率/新鲜度和真实 Graded 价格源。这两项不得用测试价格掩盖，也不能把代码测试通过写成运营数据已就绪。
