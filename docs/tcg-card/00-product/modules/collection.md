# Collection 模块 PRD

> **定位**：Collection 是用户管理卡牌资产和心愿单的核心页面，包含两个 Tab：Portfolio（用户已持有的卡牌资产）与 Wishlist（用户想关注 / 想购买的卡牌）。
>
> **日期**：2026-06-30
>
> **上游来源**：
> - 原始底稿 [`docs/tcg_cord_docs/collection说明.md`](../../../tcg_cord_docs/collection说明.md)
> - 跨切面规则 [`./global-rules.md`](./global-rules.md)（涨跌公式 / 失败 / Toast / 货币 / 确认弹窗——本文档只引用，不重复定义）
> - 文件夹管理规则 [`./home.md §八`](./home.md#八文件夹管理弹窗)（Collection 文件夹逻辑与 Home 完全一致，指向此节，不重复正文）
> - 术语表 [`../glossary.md`](../glossary.md)
> - 数据模型 [`../../03-data-api/data-model.md`](../../03-data-api/data-model.md)
> - API 规范 [`../../03-data-api/api-spec.md`](../../03-data-api/api-spec.md)

---

## 目录

1. [页面定位](#一页面定位)
2. [页面入口](#二页面入口)
3. [顶部区域](#三顶部区域)
4. [Portfolio Tab](#四portfolio-tab)
5. [金额隐藏（与 Home 联动）](#五金额隐藏与-home-联动)
6. [Portfolio 排序 / 筛选](#六portfolio-排序--筛选)
7. [Portfolio 搜索](#七portfolio-搜索)
8. [卡牌点击与分享](#八卡牌点击与分享)
9. [Wishlist Tab](#九wishlist-tab)
10. [Wishlist 排序、搜索、筛选](#十wishlist-排序搜索筛选)
11. [文件夹管理](#十一文件夹管理)
12. [异常状态](#十二异常状态)
13. [数据范围与展示规则](#十三数据范围与展示规则)
14. [业务规则](#十四业务规则)

---

## 一、页面定位

Collection 是用户管理卡牌资产的核心页面，包含两个 Tab：

| Tab | 说明 |
|---|---|
| Portfolio | 管理用户已持有、已加入文件夹的卡牌资产，参与 Home 总资产计算 |
| Wishlist | 管理想关注 / 想购买的卡牌，**不参与** Home 总资产；无文件夹 |

进入 Collection 后，默认展示 **Portfolio Tab**。

---

## 二、页面入口

| 入口 | 说明 |
|---|---|
| 底部导航 Collection | 随时进入 |
| Home Most Valuable → View All | 进入 Collection - Portfolio，按单张卡牌价值降序 |
| 卡牌详情页返回 | 返回 Collection 列表 |
| Scan 结果页添加卡牌到 Portfolio 后 | 可进入 Collection 查看 |
| Search 添加卡牌到 Portfolio / Wishlist 后 | 可进入 Collection 查看 |
| 冷启动后点击底部导航 Collection | 默认展示星标文件夹 Portfolio 数据 |

---

## 三、顶部区域

| 字段 / 控件 | 说明 |
|---|---|
| 页面标题 | `Collection` |
| 当前文件夹入口 | 展示当前 Portfolio 文件夹名称；点击打开文件夹切换弹窗（见[§十一](#十一文件夹管理)） |
| Tab | `Portfolio`、`Wishlist` |
| 搜索框 | 搜索当前 Tab 下的卡牌（见[§七](#七portfolio-搜索)、[§十](#十wishlist-排序搜索筛选)） |
| 筛选 / 排序入口 | 调整列表展示顺序或筛选条件（见[§六](#六portfolio-排序--筛选)） |

**规则**：
- 进入 Collection 后默认选中 Portfolio Tab。
- 当前文件夹默认取星标文件夹（`portfolio_folder.is_default = 1`）；用户手动切换后，切换优先级高于默认，直到下一次冷启动。
- Portfolio Tab 受当前文件夹影响；Wishlist Tab 无文件夹，不受影响。
- 用户从 Home 切换文件夹后进入 Collection，同步展示同一文件夹；从 Collection 切换文件夹后返回 Home，Home 也同步展示同一文件夹（通过 `user_preference.last_selected_folder_id` 联动）。

---

## 四、Portfolio Tab

Portfolio 展示当前文件夹内用户已收藏的卡牌资产，数据来源为 `GET /portfolio/items?folder_id=...`（见 [api-spec §3.2](../../03-data-api/api-spec.md#32-collection-itemportfolio-持有记录)）。

### 4.1 列表字段

| 字段 | 展示规则 | 备注 |
|---|---|---|
| 卡牌图片 | 展示卡牌封面；缺失时展示占位图（见 [global-rules §六](./global-rules.md#六图片缺失规则)） | Graded 卡展示评级封装图，Raw 卡展示普通卡图 |
| 卡牌名称 | 展示卡牌名称，超长省略 | 建议最多 2 行，超过后省略 |
| 卡牌语言 | 展示英文以外的语言，如 `CN`、`JP` | `collection_item.language` |
| 卡牌编号 | 展示卡牌编号 | 如 `#230`、`038`、`130/094` |
| Set / 系列 | 展示卡牌所属系列 | 如 The First Chapter、Mega Evolution Promos |
| Finish / Variant | 展示卡牌工艺或版本 | 如 Holofoil、Reverse Holo、1st Edition；`collection_item.finish` |
| Grader / Condition | Raw 卡展示 `Raw · Near Mint`；Graded 卡展示 `PSA 10`、`BGS 9.5` 等 | Raw condition 和 Graded 状态不可混用 |
| 数量 | 展示 `Qty: N`（`collection_item.quantity`） | 数量参与当前价值计算 |
| 当前价值 | 该 `collection_item` 的市场价值 = 当前单张市场价 × `quantity` | 见[§13.2](#132-取价规则) |
| 30D Change 涨跌幅 | 固定展示 30 天涨跌幅，不随 Home 图表周期变化 | 计算公式见 [global-rules §1.4](./global-rules.md#14-collection-item-当前价值与涨跌) |
| 金额隐藏图标 | 眼睛图标；与 Home 资产隐藏状态联动（见[§五](#五金额隐藏与-home-联动)） | 隐藏后金额字段显示 `••••` |

**顶部汇总信息**：

| 字段 | 展示规则 |
|---|---|
| 文件夹总金额 | 当前文件夹内卡牌总价值；精确到小数点后 2 位；使用千分位 |
| 卡牌总数量 | 当前文件夹内卡牌总条数 |
| 评级卡数量 | `grader ≠ 'Raw'` 的条数 |

### 4.2 展示规则

- Portfolio 只展示当前文件夹内的 `collection_item`；Wishlist 数据不进入此列表。
- 每条 `collection_item` 独立展示：同一张卡如有 Raw 和 PSA 9 各一条，分别作为两个资产项，避免价格口径混乱。
- 当前价值 = 对应市场价 × `quantity`（见 [global-rules §1.4](./global-rules.md#14-collection-item-当前价值与涨跌)）。
- 缺少当前市场价时：价格字段展示 `--`，该项**不计入总资产**（引用 [global-rules §十五 冲突1](./global-rules.md#冲突-1缺价卡展示与计算口径)）。
- 30D Change = 当前单张市场价相对 30 天前同口径市场价的变化比例；货币切换后涨跌幅**不变**；无足够历史价格时展示 `-/-`（见 [global-rules §一](./global-rules.md#一涨跌幅计算公式)）。
- Raw condition 和 Graded 状态不可混用：Raw 展示 `Raw · NM / LP / MP`；Graded 展示 `PSA 10 / BGS 9.5 / CGC 10`。

---

## 五、金额隐藏（与 Home 联动）

- Portfolio 数据卡片上有眼睛图标（与 Home 总资产区域图标联动）。
- 点击后，当前 Portfolio 列表中的**所有**金额类字段隐藏，显示为 `••••`。
- 再次点击后恢复显示。
- **Home / Collection 金额隐藏状态双向同步**：
  - 用户在 Home 隐藏资产金额 → 进入 Collection 时 Portfolio 金额保持隐藏。
  - 用户在 Collection 恢复显示 → Home 同步恢复显示。
- 隐藏状态通过 `user_preference.amount_hidden` 字段持久化（`PATCH /preferences`，见 [api-spec §3.4](../../03-data-api/api-spec.md#34-用户偏好)）；游客账号同样生效（见 [global-rules §七](./global-rules.md#七金额与百分比规则)）。

---

## 六、Portfolio 排序 / 筛选

筛选弹窗作用范围：当前选中文件夹的 Portfolio 卡牌（与 Wishlist 筛选互相独立）。

### 6.1 默认排序

- 默认按 `collection_item.created_at` 倒序：加入时间晚的卡牌排在上方。
- 默认无筛选条件。
- 用户手动修改排序后，下次冷启动前系统不自动重置排序。

### 6.2 Sort（单选）

- Sort 为单选，用户只能选择一个排序条件。
- 选中项高亮并展示选中标识。
- 点击其他排序项后替换当前排序条件。
- 点击 Apply Filters 后，列表按所选排序刷新；弹窗关闭。

### 6.3 Game / IP 筛选（多选）

- 支持多选；已选项高亮；再次点击已选项取消选择。
- 未选择任何 Game / IP 表示不限 IP。
- 收起态按逗号展示已选 IP；已选项过多时展示前 2 个 + `+N`。

### 6.4 Language 筛选（多选）

- 支持多选；已选项高亮；再次点击已选项取消选择。
- 未选择任何语言表示不限语言。
- 收起态按逗号展示，如 `English, Japanese`；过多时展示前 2 个 + `+N`。

### 6.5 展开 / 收起

- 默认进入筛选弹窗时，各模块为收起态。
- 点击模块右侧 `+` 展开；展开后右侧变为 `-`，点击 `-` 收起。
- 允许多个模块同时展开。
- 收起模块**不清空**该模块已选条件。

### 6.6 Apply Filters

- 点击 Apply Filters 后，应用排序与筛选条件；弹窗关闭，列表刷新。
- 搜索关键词、筛选条件、排序条件可以**同时生效**。
- 应用后无结果时展示无结果状态（见[§12.3](#123-搜索--筛选无结果)）。

### 6.7 数据保留规则

| 场景 | 规则 |
|---|---|
| 用户点击 Apply Filters | 筛选 / 排序条件保存 |
| 返回 Collection | 保持上次应用的筛选 / 排序 |
| 切换 Portfolio / Wishlist Tab | 各 Tab 独立保存筛选 / 排序 |
| 点击 Clear + Apply Filters | 清空当前 Tab 的筛选 / 排序 |
| 冷启动 | 筛选条件**不保留**；排序保留（用户设置过的排序在冷启动前不自动重置） |
| 切换文件夹 | 排序规则沿用当前设置；数据范围切换为新文件夹 |

- 用户修改的排序规则在当前设备 / 当前账号下保留；多设备不同步。

### 6.8 筛选 / 排序异常

| 场景 | 规则 |
|---|---|
| 筛选后无结果 | 展示 `No matching cards found.` |
| 筛选请求失败 | Toast：见 [global-rules §四](./global-rules.md#四操作失败-toast) |
| 排序请求失败 | 保持原列表顺序，Toast 提示失败 |
| 选项加载失败 | 当前模块展示失败提示，可点击重试 |
| 网络异常 | 不清空原列表，保留上一次成功结果 |
| 缺少价格的卡牌 | 价格排序时排在底部 |
| 缺少涨跌幅的卡牌 | 涨跌幅排序时排在底部 |

---

## 七、Portfolio 搜索

- 搜索框用于搜索当前 Portfolio Tab 下的卡牌；搜索范围限定在当前选中文件夹内。
- 支持搜索：卡牌名称、系列名、编号、IP / Game。
- 输入关键词点击搜索后显示结果；搜索结果仍遵循当前排序规则。
- 清空搜索词后恢复当前文件夹完整列表。
- 搜索无结果时展示：`No matching cards found.`

---

## 八、卡牌点击与分享

### 8.1 点击卡牌

- 点击 Portfolio 卡牌项，进入 **Portfolio 卡牌详情页**（`collection_item` 完整信息）。
- 用户在详情页修改 `collection_item` 后，返回时 Collection 列表数据刷新。
- 用户在详情页删除卡牌后，返回时该卡从当前文件夹移除。

### 8.2 分享卡牌

- 点击分享按钮，调起 iOS 原生分享弹窗组件。
- 分享内容包含：卡牌名称、卡牌编号、当前价格、App 卡牌详情链接（未安装 App 的用户打开链接时引导下载）。
- 如无可分享链接，至少分享卡牌名称和当前价格文本。
- 用户取消分享后停留当前页面，**不展示**错误提示。
- 分享调起失败时展示失败 Toast（见 [global-rules §四](./global-rules.md#四操作失败-toast)）。
- 分享不改变卡牌数据、排序或收藏状态。

---

## 九、Wishlist Tab

Wishlist 展示用户加入心愿单的卡牌（`wishlist_item`），数据来源为 `GET /wishlist`（见 [api-spec §3.3](../../03-data-api/api-spec.md#33-wishlist)）。

### 9.1 卡牌字段

| 字段 | 说明 |
|---|---|
| 卡牌图片 | 展示卡牌封面；缺失时展示占位图 |
| 卡牌名称 | 展示卡牌名称，超长省略 |
| 卡牌语言 | 展示英语以外的语言，如 `JP`、`CN` |
| 卡牌编号 | 如 `#230`、`038`、`130/094` |
| Set / 系列 | 如 The First Chapter、Mega Evolution Promos |
| Finish / Variant | 如 Holofoil |
| 当前市场价 | 展示当前价格（按当前货币） |
| 30D Change | 固定展示 30 天涨跌幅；计算公式见 [global-rules §一](./global-rules.md#一涨跌幅计算公式) |

### 9.2 与 Portfolio 的区别

| 维度 | Portfolio | Wishlist |
|---|---|---|
| 数量字段 | 展示 `Qty: N` | **不展示**数量 |
| 参与 Home 总资产 | 是 | **否** |
| 参与 Home 图表 | 是 | **否** |
| 参与 Most Valuable | 是 | **否** |
| 价格含义 | 用户资产价值 | 市场参考价 |
| 点击进入 | Portfolio 卡牌详情页（Collection Item 详情） | **普通**卡牌详情页 |
| 文件夹 | 受文件夹影响 | **无文件夹**，不受影响 |

### 9.3 Wishlist 加入 Portfolio

- 从 Wishlist 将卡牌加入 Portfolio 后，默认加入**当前选中文件夹**（若当前选中的不是星标文件夹，则加入当前选中文件夹）。
- 加入 Portfolio 后自动从 Wishlist 列表中移除（由 Workers 层在 `POST /portfolio/items` 副作用中处理，见 [api-spec §3.2.2](../../03-data-api/api-spec.md)）。

---

## 十、Wishlist 排序、搜索、筛选

### 10.1 默认排序

- 默认按 `wishlist_item.created_at` 倒序：加入时间晚的卡牌排在上方。
- 用户手动修改排序后，下次冷启动前不自动恢复默认排序。

### 10.2 搜索

- 搜索范围为 Wishlist 全量卡牌。
- 支持卡牌名称搜索；建议支持系列名、编号、IP / Game。
- 无结果展示：`No matching cards found.`

### 10.3 筛选

Wishlist 的筛选 / 排序逻辑与 Portfolio 一致（见[§六](#六portfolio-排序--筛选)），但范围限定为 Wishlist 卡牌，与 Portfolio 筛选状态互相独立。

---

## 十一、文件夹管理

Collection 的 Portfolio 文件夹逻辑与 Home 完全一致——包括文件夹切换、新建、编辑、排序、删除、设置默认等所有规则，详见 **[home.md §八 文件夹管理弹窗](./home.md#八文件夹管理弹窗)**，本文档不重复正文。

以下仅列出 Collection 视角的补充说明：

| 场景 | 补充说明 |
|---|---|
| 文件夹切换入口 | 点击 Collection 顶部文件夹名称 |
| 切换效果 | Collection - Portfolio 列表立即刷新；Home 同步联动 |
| 排序同步 | 文件夹排序结果同步到 Home 和 Collection 文件夹列表 |
| 编辑成功 | Home 和 Collection 中该文件夹名称同步更新 |
| 删除成功 | 若删除当前选中文件夹，自动切换到默认文件夹；Home 和 Collection 数据同步刷新 |

---

## 十二、异常状态

### 12.1 Portfolio 空状态

**触发条件**：当前文件夹没有任何 Portfolio 卡牌（新建空文件夹 / 删除全部卡牌 / 首次使用）。

| 字段 | 内容 |
|---|---|
| 标题 | `No cards in this portfolio yet.` |
| 说明 | `Scan or search cards to start tracking your collection.` |
| 主按钮 | `Scan a Card` |
| 次入口 | `Search Cards` |

- 点击 `Scan a Card` 进入 Scan；点击 `Search Cards` 进入 Search。
- 从 Scan / Search 添加成功后，返回 Portfolio 有数据状态。

### 12.2 Wishlist 空状态

**触发条件**：用户尚未添加 / 已移除所有 Wishlist 卡牌。

| 字段 | 内容 |
|---|---|
| 标题 | `Your wishlist is empty.` |
| 说明 | `Save cards you want to collect later and keep an eye on their market value.` |
| 主按钮 | `Search Cards` |

### 12.3 搜索 / 筛选无结果

- 展示：`No matching cards found.`
- 保留搜索框和筛选入口。
- 用户清空关键词或重置筛选后恢复列表。

### 12.4 加载中

- 首次进入 Collection 时展示列表骨架（见 [global-rules §三](./global-rules.md#三全局-loading-动效)）。
- 切换 Portfolio / Wishlist Tab 时展示局部 loading。
- 切换文件夹时展示局部 loading。
- 不整页阻断，底部导航保持可用。

### 12.5 加载失败

加载失败按作用范围分两类（引用 [global-rules §二](./global-rules.md#二加载失败空状态规则)）：

**整页弹窗失败**（核心数据全部加载失败）：

| 元素 | 内容 |
|---|---|
| 文案 | `No content available` |
| 主按钮 | `Refresh` |
| 次按钮 | `Cancel` |

适用场景：列表整体加载失败 / 页面核心数据请求失败。

**Toast 失败**（局部操作 / 状态切换失败，自动 2 秒消失）：

文案：`Something went wrong. Please try again.`（见 [global-rules §四](./global-rules.md#四操作失败-toast)）。

适用场景：筛选失败 / 文件夹切换失败 / 新建 / 编辑 / 删除文件夹失败 / 分享调起失败 / 卡牌数据刷新失败。

**通用补充规则**：
- 失败后不清空用户已有列表数据，优先保留旧数据。
- 内容类失败（图表 / 模块数据）用弹窗 + Refresh；局部操作失败用 Toast。

---

## 十三、数据范围与展示规则

### 13.1 Portfolio 数据范围

- Portfolio 只展示当前选中文件夹内的 `collection_item`；由 Home / Collection 手动切换状态或星标默认文件夹决定当前文件夹。
- 卡牌加入当前文件夹后出现在列表中；从文件夹移除后不再出现。
- Wishlist 数据独立，不进入 Portfolio 列表。
- 同一张卡可有多条 `collection_item`，按不同状态分别展示（如 Raw 和 PSA 9 各一条）。

### 13.2 取价规则

每条 `collection_item` 按 `grader` 字段决定价格口径：

| `grader` | 价格来源 |
|---|---|
| `Raw` | 取该卡 Raw 市场价（`condition` 字段参考） |
| `PSA` / `BGS` / `CGC` / `SGC` / `TAG` / `AGS` | 按 `grader` + `grade` 取对应 Graded 市场价 |

- **缺价卡口径**（引用 [global-rules §十五 冲突1](./global-rules.md#冲突-1缺价卡展示与计算口径)）：缺少当前市场价时，价格字段展示 `--`，该卡**不计入**总资产；不以购买价替代市场价。

### 13.3 涨跌幅

- Portfolio 和 Wishlist 列表统一展示 **30D Change**。
- 30D Change = (当前市场价 - 30 天前同口径市场价) / 30 天前同口径市场价 × 100%（见 [global-rules §1.4](./global-rules.md#14-collection-item-当前价值与涨跌)）。
- 涨跌幅正数展示 `+`，负数展示 `-`。
- 涨跌幅**不随货币切换变化**（见 [global-rules §七](./global-rules.md#七金额与百分比规则)）。
- 涨跌幅**不跟随 Home 图表周期变化**。
- 无足够历史价格时展示 `-/-`。

### 13.4 数量

- Portfolio 卡牌展示 `quantity`（`collection_item.quantity`）。
- 数量参与当前价值计算：当前价值 = 当前单张市场价 × `quantity`。
- 涨跌**百分比**不受 `quantity` 影响；涨跌**金额**受 `quantity` 影响（见 [global-rules §1.4](./global-rules.md#14-collection-item-当前价值与涨跌)）。
- Wishlist 不展示数量。

### 13.5 分享内容

- iOS 端调用苹果原生分享组件（见[§八](#八卡牌点击与分享)）。
- 建议包含：卡牌名称、卡牌编号、当前价格、App 卡牌详情链接。
- 未安装 App 的用户打开链接时展示官网页面，引导下载。

---

## 十四、业务规则

| 规则 | 说明 |
|---|---|
| 默认 Tab | Collection 默认进入 Portfolio Tab |
| Portfolio 与 Home | Portfolio 是资产集合，参与 Home 总资产、图表、Most Valuable |
| Wishlist 与 Home | Wishlist 不参与 Home 总资产、图表、Most Valuable |
| 文件夹联动 | Portfolio 文件夹切换同步影响 Home；Home 文件夹切换同步影响 Portfolio |
| 冷启动默认 | 冷启动后展示星标文件夹的 Portfolio 数据 |
| 手动切换优先级 | 手动切换文件夹优先级高于默认，持续至下一次冷启动 |
| 默认排序 | Portfolio 默认按加入文件夹时间倒序（`collection_item.created_at` desc）；Wishlist 默认按加入 Wishlist 时间倒序 |
| 排序持久化 | 用户修改排序后冷启动前不自动重置 |
| 分享 | 使用 iOS 原生分享组件 |
| 添加到 Portfolio | Search / Scan 添加到 Portfolio 时，默认加入**当前选中文件夹** |
| 添加到 Wishlist | Search 添加到 Wishlist 时，不影响 Portfolio 和 Home 总资产 |
| Wishlist → Portfolio | 从 Wishlist 加入 Portfolio 后，自动从 Wishlist 移除 |
| 详情页编辑后 | Card Detail 修改 `collection_item` 后，Collection 列表刷新对应数据 |
| 详情页删除后 | Card Detail 删除 Portfolio 卡牌后，Collection 列表移除该项 |
| 金额隐藏联动 | Home 和 Collection 金额隐藏状态双向同步（`user_preference.amount_hidden`） |
