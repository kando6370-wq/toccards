# Home 模块 PRD

> **定位**：Home 是用户进入 App 后查看收藏资产概览的首页，核心展示当前选中文件夹的总价值、价值变化趋势、文件夹内最高价值卡牌，以及二级市场当日升值幅度最高的卡牌。Home 不承载 Wishlist 管理、完整 Portfolio 列表管理，不展示订阅 / PRO 相关内容。
>
> **日期**：2026-06-30
>
> **上游来源**：
> - 原始底稿 [`docs/tcg-card/source-tcg-card-docs/home页说明.md`](../../source-tcg-card-docs/home页说明.md)
> - 跨切面规则 [`./global-rules.md`](./global-rules.md)（涨跌公式 / 失败 / Toast / 货币 / 确认弹窗——本文档只引用，不重复定义）
> - 术语表 [`../glossary.md`](../glossary.md)
> - 数据模型 [`../../03-data-api/data-model.md`](../../03-data-api/data-model.md)
> - API 规范 [`../../03-data-api/api-spec.md`](../../03-data-api/api-spec.md)

---

## 目录

1. [页面定位](#一页面定位)
2. [页面入口](#二页面入口)
3. [顶部区域](#三顶部区域)
4. [Portfolio 总资产卡片](#四portfolio-总资产卡片)
5. [资产隐藏](#五资产隐藏)
6. [Most Valuable 区域](#六most-valuable-区域)
7. [Trending Today 区域](#七trending-today-区域)
8. [文件夹管理弹窗](#八文件夹管理弹窗)
9. [货币切换弹窗](#九货币切换弹窗)
10. [无数据 / 空状态](#十无数据--空状态)
11. [加载失败状态](#十一加载失败状态)
12. [核心交互规则](#十二核心交互规则)
13. [数据展示规则](#十三数据展示规则)
14. [与其他模块关系](#十四与其他模块关系)

---

## 一、页面定位

Home 是用户冷启动后默认看到的首页，聚焦**资产概览**：当前选中文件夹的总价值与趋势、最高价值卡牌（Most Valuable）、以及不受文件夹影响的市场热榜（Trending Today）。

Home 不承载：
- Wishlist 管理
- 完整 Portfolio 列表管理
- 订阅 / PRO 入口（当前版本已移除）

---

## 二、页面入口

| 入口 | 说明 |
|---|---|
| 冷启动 App | 默认进入 Home |
| 底部导航 Home | 随时可回到 Home |
| Scan 添加卡牌后返回 | 可见资产变化 |
| Search 添加到 Portfolio 后返回 | 可见资产变化 |
| Collection 修改 Portfolio 卡牌后返回 | 总资产 / 图表 / Most Valuable 刷新 |

---

## 三、顶部区域

| 区域 | 字段 / 控件 | 说明 |
|---|---|---|
| 顶部 Tab | Overview | 默认展示；当前版本主要入口 |
| 顶部 Tab | Performance | **延后（1.0.1）**，本文档不定义其交互与数据 |
| 右上角 | 货币入口（当前货币码） | 点击打开货币选择弹窗（见[§九](#九货币切换弹窗)） |

**规则**：
- Home 默认进入 Overview Tab。
- 右上角货币入口展示当前选中的货币码（如 `USD`）。

---

## 四、Portfolio 总资产卡片

### 4.1 页面字段

| 字段 | 页面展示 / 说明 |
|---|---|
| 模块标题 | `PORTFOLIO` |
| 当前文件夹名称 | 如 `Main`，点击后打开文件夹切换弹窗 |
| 总资产金额 | 当前选中文件夹内所有 Portfolio 卡牌的当前总价值；格式见[global-rules §七](./global-rules.md#七金额与百分比规则) |
| 资产隐藏按钮 | 金额右侧眼睛图标（见[§五](#五资产隐藏)） |
| 30 天变化文案 | `+$0.00 in the last 30 days`；固定展示过去 30 天，不随图表周期变化 |
| 图表 | 当前选中文件夹价值趋势曲线 |
| 时间维度 | `1D`、`7D`、`1M`、`3M`、`6M`、`MAX` |

### 4.2 图表取价规则

Home 图表和总资产金额根据 `collection_item.grader` 字段决定每张卡牌的价格口径：

| `grader` 值 | 价格来源 |
|---|---|
| `Raw` | 取该卡对应 Raw 市场价 |
| `PSA` / `BGS` / `CGC` / `SGC` / `TAG` / `AGS` | 按 `grader` + `grade` 取对应 Graded 市场价 |

**总价值计算**：
```
总资产 = Σ (每条 collection_item 的单张市场价 × quantity)
```
- 同一张卡存在多条 `collection_item`（如 Raw 一张、PSA 9 一张），分别取价后各自乘以 `quantity` 再累加。
- 缺少当前市场价的卡牌：价格展示 `--`，**不计入总资产**（引用 [global-rules §十五 冲突1](./global-rules.md#冲突-1缺价卡展示与计算口径)）。
- 涨跌计算公式见 [global-rules §一](./global-rules.md#一涨跌幅计算公式)。

### 4.3 图表数据规则

- 图表从卡牌被收藏进文件夹之日起开始追踪；卡牌加入文件夹之前的历史不计入。
- 卡牌从文件夹删除后，从删除时间点起不再计入图表，删除前的历史数据保留。
- 如果删除发生在当前图表周期内，删除造成的资产减少体现在该周期的资产变化中。
- 某日期缺价时，优先使用距离该时间点最近的前一个有效价格；如无任何有效历史价格，则该时间点不计入资产（曲线断裂）。
- 卡牌被重新加入 Portfolio 后，视为新的 `collection_item` / 新持有周期，从重新加入时间开始计入图表。

### 4.4 图表交互规则

- 点击时间维度，图表按所选周期刷新；**不改变**当前总资产金额。
- 30 天变化文案固定展示过去 30 天，**不随图表周期变化**。
- 点击或长按曲线点位时，展示该日期和对应总资产金额。
- 历史数据仅有 1 个点时，图表展示水平线 / 单点，**不展示空白**。
- 用户快速切换图表周期（`1D` / `7D` / `1M` / `3M`）时，以**最后一次**选择的周期结果为准，旧请求返回后**不得覆盖**当前图表；请求中统一展示 loading（见 [global-rules §三](./global-rules.md#三全局-loading-动效)），失败时展示**当前周期**的局部失败状态。
- 图表数据加载中时展示局部 loading（见 [global-rules §三](./global-rules.md#三全局-loading-动效)）。
- 图表加载失败时展示模块内局部失败状态（见[§十一](#十一加载失败状态)），不弹出整页弹窗。

---

## 五、资产隐藏

- 总资产金额右侧展示眼睛图标。
- 点击后隐藏当前 Overview 中所有资产金额，金额显示为 `••••••`。
- 再次点击后恢复显示。
- **Home / Collection 金额隐藏状态双向同步**：
  - 用户在 Home 隐藏资产金额 → 进入 Collection - Portfolio 时金额同步隐藏。
  - 用户在 Collection 恢复显示 → 返回 Home 时金额同步恢复显示。
- 隐藏状态通过 `user_preference.amount_hidden` 字段持久化（`PATCH /preferences`，见 [api-spec §3.4](../../03-data-api/api-spec.md#34-用户偏好)）；游客账号同样生效（见 [global-rules §七](./global-rules.md#七金额与百分比规则) 和 [data-model §4.4](../../03-data-api/data-model.md#44-user_preference用户偏好)）。

---

## 六、Most Valuable 区域

该区域展示当前选中文件夹内**单张**价值最高的卡牌。与图表时间维度不关联。

### 6.1 展示字段

**TCG 卡牌 / 体育卡**

| 字段 | 展示规则 |
|---|---|
| 模块标题 | `Most Valuable` |
| 卡牌名称 | 展示卡牌名称，超长省略 |
| 状态 | Raw 卡展示 `Near Mint · Holofoil`；Graded 卡展示 `PSA 10 (GEM-MT) · Holofoil` |
| 当前单张价格 | 该 `collection_item` 当前单张市场价 |
| 30D Change | 固定展示 30 天涨跌幅；计算公式见 [global-rules §1.5](./global-rules.md#15-home-most-valuable-涨跌) |
| View All | 点击进入 Collection - Portfolio 列表（按单张价值降序） |

**体育卡附加字段**

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 球员 / 卡牌名称 | 主标题 | Shohei Ohtani |
| Sport / 年份 / 品牌 | 副信息 | Baseball · 2024 Topps Chrome |
| Team / Insert / Card Number | 版本信息，空间不足可省略 Team | Dodgers · Refractor · #17 |
| 状态 | Raw 展示品相；Graded 展示评级 | Near Mint / PSA 10 |
| Special Tags | 有则展示，与状态或版本同行 | RC、Auto、Patch、/99 |
| 当前单张价格 | 右侧金额 | $240 |
| 30D Change | 右侧百分比 | +8.12% |

**Sealed Products（套盒 / 卡包 / 整箱）**

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 产品名称 | 主标题 | Evolving Skies Booster Box |
| IP / Game + Set | 副信息 | Pokémon · Evolving Skies |
| Product Type + Configuration | 规格信息 | Booster Box · 36 Packs |
| 状态 | 展示 Sealed / Opened | Sealed · English |
| 当前单件价格 | 右侧金额 | $780 |
| 30D Change | 右侧百分比 | +5.34% |

### 6.2 展示逻辑

- Most Valuable 只统计**当前选中文件夹**内的 Portfolio 卡牌；Wishlist 卡牌不参与。
- 排序按单张卡牌价值从高到低（`collection_item` 按 `grader` / `grade` 对应市场价取价）。
- **数量不影响排序**：同一张卡持有多张，仍按单张价值排序（见 [global-rules §1.5](./global-rules.md#15-home-most-valuable-涨跌)）。
- 同一张卡存在多个状态（Raw / PSA 9 / PSA 10），视为不同 `collection_item` 分别参与排序。
- 首页只展示价值**最高**的一张。
- 缺少市场价的卡牌不参与排序（引用 [global-rules §十五 冲突1](./global-rules.md#冲突-1缺价卡展示与计算口径)）。
- 相同单张价值时排序规则：① 30 天涨幅较高者优先；② 涨幅相同时最近添加时间较晚者优先；③ 仍相同时按名称 A-Z 升序（完整 tie-break 链以 [global-rules §十五 冲突2](./global-rules.md#冲突-2most-valuable-相同单张价值时的排序优先级) 为准）。
- 当前文件夹无卡牌时展示 `No cards in this portfolio yet`，不展示具体卡牌项。
- 点击 **View All** 进入 Collection - Portfolio 列表，按单张卡牌价值降序展示（此为该入口的特殊排序；从此路径进入后切换到其他页面再返回 Portfolio，则恢复 Portfolio 本身的排序规则）。

### 6.3 字段冲突规避

- Raw condition 和 Graded 状态不混在同一行。
- Raw 卡：展示 `LP` / `NM` / `MP` 等品相。
- Graded 卡：只展示 `PSA 9`、`BGS 9.5`、`CGC 10` 等评级信息，不混入 condition 文字。

---

## 七、Trending Today 区域

该区域展示二级市场（eBay / TCGPlayer）当天升值幅度最高的卡牌，**不受当前文件夹和用户收藏影响**。

### 7.1 页面字段

| 字段 | 说明 |
|---|---|
| 模块标题 | `Trending Today` |
| View 入口 | 点击进入 Trending 完整列表，保留当天涨幅降序 |
| 卡牌图片 | 缺图展示占位图（见 [global-rules §六](./global-rules.md#六图片缺失规则)） |
| 卡牌名称 | 超长省略 |
| IP / Game | Pokémon、Yu-Gi-Oh!、Magic 等 |
| Set / 系列 | 卡牌所属系列 |
| 当前市场价 | 按当前货币展示 |
| 当日涨跌幅 | 当天涨跌幅百分比 |

### 7.2 数据规则

- 首页展示 **3 条**；数据不足时按实际数量展示。
- 排序按当天涨幅百分比降序；相同时 tie-break：① 涨幅百分比相同 → 当前市场价高者优先；② 仍相同 → 按名称 A-Z 升序。
- 当日涨跌幅 = 当前价格相对前一日收盘价（或最近 24 小时均价）的变化比例；口径以数据源为准，全局统一。
- 当日涨跌幅正数展示 `+`，负数展示 `-`；**货币切换后涨跌幅不变**（见 [global-rules §七](./global-rules.md#七金额与百分比规则)）。
- 接口：`GET /cards/trending`（见 [api-spec §4.6](../../03-data-api/api-spec.md#46-获取-trending-today)）。Workers 先合并运营置顶（`trending_pin` 表），后接第三方数据。
- 点击 View 后进入 Trending 完整列表，保留 Trending 排序。
- 点击单张卡牌进入**普通**卡牌详情页（非 Portfolio Collection Item 详情）。
- 用户在详情页添加到 Portfolio，默认加入当前选中的文件夹。

---

## 八、文件夹管理弹窗

点击 Home 中当前文件夹名称后，打开文件夹切换弹窗。

### 8.1 文件夹列表弹窗

| 字段 / 控件 | 说明 |
|---|---|
| 文件夹列表 | 展示用户已有 Portfolio 文件夹，按 `sort_order` 排序 |
| 当前选中标识 | 左侧小标识 / 单选状态 |
| 默认文件夹标识 | 小星星（`portfolio_folder.is_default = 1`） |
| 编辑入口 | 文件夹右侧编辑图标 |
| 删除入口 | 文件夹右侧删除图标（默认文件夹置灰 / 隐藏） |
| 拖动排序 | 按住文件夹左侧小标识可上下拖动（见[§8.4](#84-排序规则)） |
| 新建按钮 | `+ Add new`，点击进入新建文件夹弹窗 |

### 8.2 文件夹核心概念

- **文件夹**对应数据模型中的 `portfolio_folder`（见 [data-model §4.1](../../03-data-api/data-model.md#41-portfolio_folder-portfolio-文件夹)）。
- 小星星（`is_default = 1`）表示**默认文件夹**，用于 App 冷启动后的默认展示。
- 默认文件夹不可删除；默认文件夹只能有一个（Workers 事务保证）。
- 切换文件夹优先级高于默认文件夹：用户手动切换后，下一次冷启动前 Home 和 Portfolio 跟随本次切换；下次冷启动恢复星标文件夹（通过 `user_preference.last_selected_folder_id` 记录手动切换状态）。

### 8.3 切换文件夹

- 点击文件夹行后，Home 总资产、图表、Most Valuable 立即刷新；Trending Today 不随文件夹切换变化。
- Collection - Portfolio 同步切换到该文件夹。
- 弹窗关闭后，Home 顶部文件夹名称同步更新。
- 切换失败时：保留原文件夹，展示通用失败 Toast（见 [global-rules §四](./global-rules.md#四操作失败-toast)）。

### 8.4 排序规则

- 按住文件夹左侧小标识，上下拖动调整顺序，更新 `portfolio_folder.sort_order`（`PATCH /portfolio/folders/reorder`）。
- 排序结果同步到 Collection - Portfolio 文件夹列表。
- 排序后自动保存；保存失败时回滚到调整前顺序并展示失败 Toast。

### 8.5 新建文件夹弹窗

点击 `+ Add new` 后打开新建弹窗（`POST /portfolio/folders`）。

| 字段 | 页面展示 |
|---|---|
| 弹窗标题 | `Add new portfolio` |
| 输入项标题 | `Name of portfolio` |
| 输入框 placeholder | `Name` |
| 返回按钮 | 左下角返回箭头（返回文件夹列表） |
| 保存按钮 | `Save` |

**表单校验**：

| 场景 | 提示文案 |
|---|---|
| 名称为空或仅空格 | `Please enter a portfolio name.`（引用 [global-rules §13.1](./global-rules.md#131-通用文案全局生效)） |
| 名称重复 | `Portfolio name already exists` |
| 名称超过 50 字符 | `Maximum 50 characters.` |
| 输入为空 | Save 按钮置灰，无法点击 |

**规则**：
- 新建成功后回到文件夹列表弹窗；新文件夹**不自动**成为默认文件夹。
- 创建失败时展示失败 Toast（见 [global-rules §四](./global-rules.md#四操作失败-toast)）。

### 8.6 编辑文件夹弹窗

点击文件夹右侧编辑图标，进入编辑弹窗（`PATCH /portfolio/folders/{folder_id}`）。

| 字段 | 说明 |
|---|---|
| 弹窗标题 | `Edit portfolio` |
| 输入项标题 | `Name of portfolio` |
| 输入框 | 默认填入当前文件夹名称 |
| 返回按钮 | 返回文件夹列表 |
| 保存按钮 | `Save` |

**规则**：
- 保存成功后，Home 和 Collection 中该文件夹名称同步更新。
- 编辑当前选中文件夹时，Home 顶部名称立即更新。
- 默认文件夹允许编辑名称，但不可删除。
- 保存失败时展示失败 Toast；名称重复时提示 `Portfolio name already exists.`

### 8.7 删除文件夹规则

删除非默认文件夹需经**确认弹窗**（见 [global-rules §九](./global-rules.md#九确认弹窗规则)）。

| 字段 | 页面展示 |
|---|---|
| 弹窗标题 | `Are you sure you want to delete this cards portfolio?` |
| 按钮 | `Cancel`（取消）、`Delete`（确认删除） |

**规则**：
- 接口：`DELETE /portfolio/folders/{folder_id}`（见 [api-spec §3.1](../../03-data-api/api-spec.md)）。
- 删除后该文件夹内所有 `collection_item` 随之删除（`ON DELETE CASCADE`）。
- 默认文件夹不可删除，删除入口隐藏或置灰。
- 当前选中文件夹被删除后，自动切换到默认文件夹，Home 和 Portfolio 数据同步刷新。
- 删除失败时保留原文件夹并展示失败 Toast。

### 8.8 设置默认文件夹

- 点击文件夹右侧小星星，将该文件夹设为默认（`PATCH /portfolio/folders/{folder_id}/set-default`）。
- 默认文件夹唯一；设置新默认文件夹后，旧默认文件夹自动取消星标。
- 当前正在查看的文件夹不一定等于默认文件夹。

---

## 九、货币切换弹窗

点击右上角货币入口后，打开 `Select currency` 弹窗（`GET /rates` + `PATCH /preferences`）。

### 9.1 支持币种

| 货币码 | 名称 |
|---|---|
| USD | US Dollar |
| EUR | Euro |
| JPY | Japanese Yen |
| GBP | British Pound |
| CAD | Canadian Dollar |
| AUD | Australian Dollar |
| NZD | New Zealand Dollar |
| SGD | Singapore Dollar |

### 9.2 规则

- 当前货币使用单选态。
- 点击未选中货币后，调用汇率接口进行换算；成功后 App 内**所有**金额字段同步换算，弹窗自动关闭，右上角货币码更新。
- **百分比（涨跌幅）不随货币切换变化**（见 [global-rules §七](./global-rules.md#七金额与百分比规则)）；以下涨跌幅均不变：Home 30 天变化、Trending Today 当日涨跌幅、Most Valuable 涨跌幅。
- 点击当前已选货币，不重复调用接口。
- 切换失败时保持原货币，展示失败 Toast（见 [global-rules §四](./global-rules.md#四操作失败-toast)）。

---

## 十、无数据 / 空状态

**触发条件**：当前选中文件夹没有任何 Portfolio 卡牌（首次进入 App / 删除全部卡牌 / 新建空文件夹）。

| 字段 / 控件 | 页面展示 |
|---|---|
| 标题 | `Add your first card` |
| 说明 | `Start tracking your collection value, price trends, and top cards.` |
| 主按钮 | `Scan a Card` |
| 次入口 | `Search Cards` |
| Most Valuable 空文案 | `No cards in this portfolio yet` |
| Trending Today | 不受文件夹空状态影响，正常展示 |

**规则**：
- 点击 `Scan a Card` 进入 Scan；点击 `Search Cards` 进入 Search。
- 空文件夹下 Most Valuable 不展示卡牌，只展示空文案。
- Trending Today 是市场数据，空状态下仍展示；若 Trending Today 加载失败，只在该模块展示错误状态，不影响 `Scan a Card` / `Search Cards` 点击。

---

## 十一、加载失败状态

### 11.1 整页加载失败

所有核心数据全部请求失败时，展示全局失败弹窗（见 [global-rules §2.2](./global-rules.md#22-整页数据加载失败)）：

| 字段 | 内容 |
|---|---|
| 标题 | `No content available` |
| 按钮 | `Refresh`（重新请求整页） |

### 11.2 模块局部加载失败

仅某模块加载失败时，在该模块原数据区域展示局部失败状态（见 [global-rules §2.1](./global-rules.md#21-局部数据加载失败)），不使用整页弹窗：

| 模块 | 失败文案 | Refresh 行为 |
|---|---|---|
| 图表（含 30 天变化） | `No content available` + `Refresh` | 只重试图表数据 |
| Most Valuable | `No content available` + `Refresh` | 只重试 Most Valuable 数据 |
| Trending Today | `No content available` + `Refresh` | 只重试 Trending 数据；点击 View 也等于重新请求 |

- 用户可下拉刷新全部数据。
- 失败后不清空其他模块已加载内容。

### 11.3 图表两种空表区分（重要）

图表"画不出曲线"存在两种**不可混淆**的情形，处理方式不同：

| 情形 | 含义 | 处理 |
|---|---|---|
| **局部失败** | 周期内有持仓，但所有卡牌均无可用价格 | 进入图表局部失败状态，文案 `No content available` + `Refresh`（见[§11.2](#112-模块局部加载失败)） |
| **业务空状态** | 周期内本就无持仓 / 无有效计价资产 | 当前总资产展示 `$0.00`、图表展示空状态（**不画无意义曲线**）、变化百分比展示 `-/-`、Most Valuable 展示空状态（口径见 [global-rules §16.5](./global-rules.md#165-当前总资产为-0)） |

- 业务空状态属"无数据"而非"失败"，**不弹错误 Toast**。
- 二者不得相互套用文案或交互。

---

## 十二、核心交互规则

### 12.1 冷启动初始化

- 冷启动时，Home / Portfolio **始终**默认展示**星标（default）文件夹**（`portfolio_folder.is_default = 1`）；冷启动**忽略** `user_preference.last_selected_folder_id`，不以该字段作为默认。
- `user_preference.last_selected_folder_id` 是"本次会话当前文件夹"指针：用户手动切换文件夹时更新该字段，仅在本次会话内生效；下一次冷启动重新回到星标文件夹（冷启动不读取该字段作为默认，因此无论该字段是否清空，默认始终是星标文件夹）。
- 默认货币取 `user_preference.currency`；无保存记录时默认 USD。
- 数据范围：总资产金额、30 天变化、图表、Most Valuable 受当前文件夹影响；Trending Today 不受影响。

### 12.2 文件夹切换（见[§八](#八文件夹管理弹窗)）

### 12.3 Most Valuable 查看更多

- 点击 View All，进入 Collection - Portfolio，按单张卡牌价值降序排列，默认展示当前文件夹。
- 此为从 Home 进入的特殊排序；切换到其他页面再返回 Portfolio 时，恢复 Portfolio 本身的排序规则。

### 12.4 Trending Today 查看更多

- 点击 View，进入 Trending 完整列表，保持当天涨幅降序。
- 点击卡牌进入普通卡牌详情页。
- 从详情页添加到 Portfolio 后，默认加入当前选中文件夹。

### 12.5 操作失败通用规则

切换文件夹 / 新建 / 编辑 / 排序 / 删除 / 切换货币等所有操作失败时，均展示失败 Toast，详见 [global-rules §四](./global-rules.md#四操作失败-toast)。

---

## 十三、数据展示规则

### 13.1 总资产金额

- 按当前选中文件夹计算；使用当前货币展示；保留 2 位小数，使用千分位。
- 缺价卡不计入总资产（引用 [global-rules §十五 冲突1](./global-rules.md#冲突-1缺价卡展示与计算口径)）。
- 周期起点资产为 0 时，变化百分比展示 `-/-`（口径见 [global-rules §16.4](./global-rules.md#164-周期起点资产为-0)，home 不重复定义）。
- 文件夹为空时展示空状态，不展示无意义曲线。

### 13.2 图表

- 展示当前选中文件夹总价值变化；按 `collection_item` 状态取价（Raw 卡取 Raw 市场价，Graded 卡取对应 Graded 价）。
- `quantity` 参与总价值计算。
- 切换货币后图表金额换算，百分比不变。
- 切换文件夹后图表刷新。

### 13.3 Most Valuable

详见[§六](#六most-valuable-区域)。

### 13.4 Trending Today

详见[§七](#七trending-today-区域)。

### 13.5 货币规则

详见[§九](#九货币切换弹窗)与 [global-rules §七](./global-rules.md#七金额与百分比规则)。

---

## 十四、与其他模块关系

### 14.1 Home 与 Collection（Portfolio）

- Home 展示当前选中文件夹的 Portfolio 资产。
- 文件夹切换后 Home 和 Collection - Portfolio 页面同步（`user_preference.last_selected_folder_id`）。
- Portfolio 内卡牌编辑后，Home 总资产、图表、Most Valuable 需要刷新。

### 14.2 Home 与 Wishlist

- Wishlist 不计入 Home 总资产、图表、Most Valuable。
- Trending Today 可以出现 Wishlist 中的卡牌，但 Home 不展示 Wishlist 状态标识。

### 14.3 Home 与 Scan

- 空状态点击 `Scan a Card` 进入 Scan。
- Scan 添加成功后，卡牌默认加入当前选中文件夹，Home 刷新。

### 14.4 Home 与 Search

- 空状态点击 `Search Cards` 进入 Search。
- Search 添加到 Portfolio 后，默认加入当前选中文件夹，Home 刷新。
- 添加到 Wishlist 不影响 Home 资产。

### 14.5 Home 与 Card Detail

- Most Valuable 点击卡牌进入 **Portfolio** 卡牌详情页（`collection_item` 详情）。
- Trending Today 点击卡牌进入**普通**卡牌详情页。
- 用户在 Portfolio 卡牌详情页编辑 `collection_item` 后，Home 根据保存信息更新价格。
- 用户在详情页 Remove 后，Home 对应文件夹数据刷新。
