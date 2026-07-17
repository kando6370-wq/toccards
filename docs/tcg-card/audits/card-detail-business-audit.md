# Card Detail 业务审计

## 0. 文档说明

- 范围：Flutter Card Detail、Card Data/Portfolio API、Workers 卡牌与资产路由、生产 D1。
- 设计真源：Figma `DjacfTioobtRy59SnqH7SY`；节点 `40:30` 当前无法返回选中图层，因此本轮不把视觉一致性标记为已证明。
- 产品规则：`00-product/modules/card-detail.md` 与 `TCG_PRD_整合版.md` 第九章。
- 证据口径：仅采用代码、测试、生产 API 和提交；不采用进度文档的完成标记。
- 审计日期：2026-07-17。

## 1. 业务总览与主线

Card Detail 将公共卡牌信息、市场价格和当前 owner 的 Portfolio/Wishlist 状态合并为单卡业务入口。主线为：从 Home、Search、Collection 或 Scan 进入 -> 读取真实卡牌、价格、曲线、成交入口和资产状态 -> 新增、编辑或删除 Collection Item，或切换 Wishlist -> 刷新 Home、Collection 与 Search。

| 区域 | 真实接口 | 结论 |
|---|---|---|
| 基础信息 | `GET /cards/:card_ref` | 代码明确 |
| Market Prices | `GET /cards/:card_ref/market-prices` | 代码明确 |
| 价格曲线 | `GET /cards/:card_ref/price-series` | 代码明确 |
| Shop/成交入口 | `GET /cards/:card_ref/sold-listings` | 生产当前为 TCGplayer SKU 快照入口 |
| Collection Item | Portfolio Items CRUD | owner 级真实数据 |
| Wishlist | Wishlist CRUD | owner 级真实数据 |

## 2. 用户身份与权限

公共卡牌和行情接口可匿名读取。Collection Item 与 Wishlist 必须使用当前匿名或登录会话，Workers 重新验证 Bearer Token 并按 owner 隔离。游客登录后的资产迁移由 Auth 链路负责，Card Detail 通过会话变化重新加载。

## 3. 核心业务流程

1. 详情加载公共卡牌、市场价、五档周期曲线和成交入口，再叠加 folders、items、wishlist。
2. 未收藏卡展示 Price 与 Add to Portfolio；已收藏卡默认展示 Collection Item。
3. 新增 Item 优先使用 Home/Collection/Search 共享的当前文件夹，无有效选择时回退默认文件夹。
4. Quantity、Grader、Condition/Grade、Language、Finish、Purchase Price 和 Notes 通过真实 Portfolio API 保存。
5. Purchase Price 按当前 App 货币输入和展示，保存前换算为 USD；汇率缺失时显式拒绝保存，不丢弃表单。
6. 删除、Wishlist 或 Item 变更后失效 Home、Collection、Search 缓存。

异常规则：基础详情失败进入整页失败；价格缺失显示 `--`，涨跌基准缺失显示 `-/-`；表单失败保留输入；破坏性删除需二次确认。

## 4. 核心数据实体

| 实体 | 关键字段 | 用途 |
|---|---|---|
| `cards_all` | product_id、game、set、name、image | 公共身份 |
| `tcgplayer_skus` | condition、language、variant、price_history | Raw 市场价、曲线、交易入口 |
| `portfolio_folder` | owner、id、is_default | Collection Item 归属 |
| `collection_item` | card_ref、folder_id、定价状态、quantity、purchase_price | 用户持有记录 |
| `wishlist_item` | owner、card_ref | 未持有关注状态 |
| `collection_item_event` | item_id、event_type、定价快照 | Home 历史资产回放 |

## 5. 业务规则与计算

- 当前持有数量：同 card_ref 全部 Collection Item 的 quantity 之和。
- Item 市场价值：匹配状态的市场单价乘 quantity；Purchase Price 不参与估值。
- Market Prices 7D Change：`(current - previous7d) / previous7d * 100%`。
- Raw 使用 Condition；Graded 使用 Grader + Grade；两种状态不得混用。
- Purchase Price 输入：`USD value = selected currency value / USD rate`；显示时反向换算。
- Notes 上限 500 字符；Quantity 必须为正整数；Purchase Price 可为 0。

## 6. 上下游与影响面

| 依赖 | 方向 | 失败影响 |
|---|---|---|
| D1 卡牌/SKU | 上游 | 基础信息或价格不可用 |
| FX `/rates` | 上游 | 非 USD 金额不能可靠显示或保存 |
| Portfolio/Wishlist | 双向 | 资产状态无法加载或变更 |
| Home/Collection/Search | 下游 | 资产、Qty、Wishlist 和估值需要同步刷新 |
| TCGplayer | 下游 | Shop 链接离开 App 打开真实商品页 |

## 7. 行业术语

| 术语 | 含义 |
|---|---|
| Raw | 未评级卡，按 Condition 取价 |
| Graded | 经 PSA/BGS 等机构评级，按 Grader + Grade 取价 |
| Collection Item | 一条独立持有记录，同卡可有多条 |
| Purchase Price | 用户成本记录，不是市场估值 |

## 8. 证据索引

| 编号 | 文件/结果 | 说明 |
|---|---|---|
| E1 | `card_detail_repository.dart` | Card Data 与资产状态聚合 |
| E2 | `card_detail_controller.dart` | 状态、表单、货币与跨页失效 |
| E3 | `card_detail_page.dart` | 页面状态与操作入口 |
| E4 | `data-source/routes.ts`、`local-db-adapter.ts` | 生产详情、价格、曲线和成交路由 |
| E5 | `portfolio/routes.ts` | owner 鉴权及 Item/Wishlist 持久化 |
| E6 | `card_detail_controller_test.dart`、`card_detail_page_test.dart` | 业务意图与页面交互测试 |

## 9. 待确认问题与上线边界

| 问题 | 当前证据 | 后续要求 |
|---|---|---|
| Figma `40:30` 无法提取 Card Detail 图层 | MCP 连续返回“没有选中图层” | 上架截图前取得正确节点并完成 iOS 视觉验收 |
| Price 图表、Market Prices、Shop 未分区失败 | Repository 当前统一 Future 链，任一网络异常可令整页失败 | 按 PRD 拆分分区状态与局部 Refresh |
| Graded 生产价为空 | D1 adapter 对非 Raw 返回空 | 接入真实评级价格源前保持 `--`，不得用 Raw 冒充 |
| 历史非 USD purchase_currency | 当前新写入统一换算并存 USD；旧非 USD 行缺少回算证据 | 上线前审计生产行并迁移或补原币汇率换算 |
| sold listings 语义 | 当前由 SKU 最新价格生成，不是真实成交订单 | 产品若要求已成交记录，需接入真实成交数据源 |

## 10. 本轮验证记录

| 验证项 | 结果 |
|---|---|
| 生产卡牌 `9359` | 详情、4 档 Raw 市场价、30D 曲线和 4 条 TCGplayer 入口成功 |
| Flutter 定向测试 | Card Detail、页面、Currency 共 51 项通过 |
| Flutter 全量测试 | 338 项通过、1 项既有 OpenCV 条件跳过 |
| Flutter analyze | 无问题 |
| 分段提交 | `3cb0b65` 当前文件夹；`933be1e` Purchase Price 多币种 |

