# Search 模块 PRD

> **定位**：Search 用于用户查找卡牌和系列，并快速将卡牌加入当前选中 Portfolio 文件夹或 Wishlist。
>
> **日期**：2026-06-30
>
> **上游来源**：
> - 原始底稿 [`docs/tcg_cord_docs/search.md`](../../../tcg_cord_docs/search.md)
> - 跨切面规则 [`./global-rules.md`](./global-rules.md)（涨跌公式 / 失败 / Toast / 货币 / 确认弹窗——本文档只引用，不重复定义）
> - 术语表 [`../glossary.md`](../glossary.md)
> - 数据模型 [`../../03-data-api/data-model.md`](../../03-data-api/data-model.md)
> - API 规范 [`../../03-data-api/api-spec.md`](../../03-data-api/api-spec.md)

---

## 目录

1. [页面定位](#一页面定位)
2. [页面入口](#二页面入口)
3. [顶部搜索区](#三顶部搜索区)
4. [Cards Tab 列表统一结构](#四cards-tab-列表统一结构)
5. [TCG 单卡字段](#五tcg-单卡字段)
6. [体育卡字段](#六体育卡字段)
7. [Sealed Product 字段](#七sealed-product-字段)
8. [其他特殊收藏品字段](#八其他特殊收藏品字段)
9. [Cards 列表汇总](#九cards-列表汇总)
10. [涨跌百分比展示规则](#十涨跌百分比展示规则)
11. [字段展示优先级](#十一字段展示优先级)
12. [Qty 字段规则](#十二qty-字段规则)
13. [Collect / Collected 规则](#十三collect--collected-规则)
14. [Wishlist 爱心规则](#十四wishlist-爱心规则)
15. [快捷加入默认 Collection Item](#十五快捷加入默认-collection-item)
16. [Cards 列表展示规则](#十六cards-列表展示规则)
17. [Sets Tab](#十七sets-tab)
18. [加载与异常](#十八加载与异常)

---

## 一、页面定位

Search 页面包含两个 Tab：

1. **Cards**：搜索 / 浏览卡牌。
2. **Sets**：搜索 / 浏览系列。

Game / IP 筛选项控制下方两个 Tab 的数据范围。Cards 和 Sets 两个 Tab 的数据、搜索结果、列表状态互不关联。

---

## 二、页面入口

| 入口 | 说明 |
|---|---|
| 底部导航 Search | 主入口 |
| Scan 页面右上角 Search 图标 | 从 Scan 跳转 |
| Home 空状态 Search Cards 按钮 | Home 无数据时引导 |
| Scan 失败 / 无匹配时兜底 | 用户手动查找卡牌 |
| Wishlist / Portfolio 相关页面搜索入口 | 查找新卡牌 |

---

## 三、顶部搜索区

### 3.1 页面字段

| 字段 / 控件 | 页面展示 | 说明 |
|---|---|---|
| 搜索框 | `Search cards, sets, or characters` | 输入关键词 |
| 相机图标 | 搜索框右侧 | 进入 Scan |
| 清除按钮 | 搜索后出现 `×` | 清空搜索词 |
| Game / IP 下拉 | 当前展示 Pokémon | 控制 Cards / Sets 数据范围 |
| Tab | Cards、Sets | 切换卡牌和系列 |

### 3.2 规则

1. 进入 Search 默认展示 Cards Tab。
2. 默认 Game / IP 为 Pokémon。
3. 用户可输入卡牌名、系列名、角色名等关键词；接口调用 `searchCards`（见 api-spec §数据代理端点）。
4. 搜索框右侧相机图标点击后进入 Scan 页面。
5. 输入关键词后出现清除按钮。
6. 点击清除按钮后清空关键词，并恢复当前 Game / IP 下当前 Tab 的默认列表。
7. Game / IP 下拉用于切换搜索范围。
8. 切换 Game / IP 后，当前 Tab 列表刷新为对应 Game / IP 数据；同时清空当前搜索词，避免用户误以为某 IP 下无数据。
9. Cards 和 Sets 两个 Tab 互不关联：Cards 的搜索结果不影响 Sets；Sets 的搜索结果不影响 Cards；两个 Tab 各自保留搜索状态，切换后再切回仍维持搜索结果，不自动重置。

---

## 四、Cards Tab 列表统一结构

Cards Tab 以双列卡片展示可收藏对象，包括：

1. TCG 单卡（Pokémon、Yu-Gi-Oh!、Magic、One Piece 等）
2. 体育卡
3. 评级卡
4. 套盒 / 卡包 / 整箱（Sealed Product）
5. 其他特殊收藏品

所有类型在列表中统一展示以下基础结构：

```
图片
名称
当前价格
30D Change 百分比
归属信息
版本 / 状态信息
Qty
Collect / Collected
Wishlist 爱心
```

### 全局展示规则

1. Search 列表只展示涨跌百分比，不展示涨跌金额。
2. 涨跌百分比固定使用 30D Change（见 `global-rules.md §一`）。
3. 涨跌百分比不随货币切换变化（见 `global-rules.md §七`）。
4. 当前价格跟随用户当前货币展示。
5. 当前价格缺失时展示 `--`。
6. 涨跌百分比缺失时展示 `-/-`。
7. 涨跌百分比为正数时展示 `+`，负数时展示 `-`。
8. Qty 表示当前账号在当前选中文件夹中的持有数量。
9. Wishlist 不影响 Qty。

---

## 五、TCG 单卡字段

适用于 Pokémon、Yu-Gi-Oh!、Magic、One Piece 等普通单卡。

### 5.1 展示字段

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 图片 | 卡牌封面，缺图展示占位图（见 `global-rules.md §六`） | image |
| 卡牌名称 | 主标题，超长省略 | Squirtle |
| 当前价格 | 当前市场参考价 | $32.13 |
| 30D Change % | 只展示百分比，不展示金额 | (+4.76%) |
| 系列名 | 卡牌所属系列 | Mega Evolution Promos |
| 稀有度 / 编号 | 卡牌版本信息 | Promo · 039 |
| Finish / Variant | 工艺 / 版本 | Holofoil |
| Qty | 当前选中文件夹持有数量 | Qty: 0 / Qty: 1 |
| Collect / Collected | 加入 / 取消加入当前 Portfolio | Collect |
| Heart | 加入 / 移除 Wishlist | 空心 / 实心 |

### 5.2 推荐展示结构

未加入：
```
Squirtle
$32.13
(+4.76%)
Mega Evolution Promos
Promo · 039
Holofoil
Qty: 0        Collect    ♡
```

已加入当前 Portfolio：
```
Squirtle
$32.13
(+4.76%)
Mega Evolution Promos
Promo · 039
Holofoil
Qty: 1        Collected    ♥
```

### 5.3 字段规则

1. 卡牌名称为主标题。
2. 系列名用于说明卡牌归属。
3. 稀有度 / 编号用于区分同名卡不同版本。
4. Finish / Variant 用于展示 Holofoil、Reverse Holo、Sealed 等状态。
5. 当前价格展示市场参考价，不代表用户 Portfolio 资产价值。
6. 点击 Collect 后，Portfolio 中该卡的价值按 Collection Item 规则计算。

---

## 六、体育卡字段

体育卡 Search 列表只保留必要识别字段，不展示过多扩展信息。

### 6.1 展示字段

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 图片 | 体育卡图 / 评级封装图，缺图展示占位图 | Michael Jordan 卡图 |
| 球员名 + 卡号 | 主标题 | Michael Jordan #57 |
| 当前价格 | 当前市场参考价 | $18,500.00 |
| 30D Change % | 只展示百分比，不展示金额 | (+7.25%) |
| 年份 + 系列 / 品牌 | 核心归属信息 | 1986 Fleer |
| 版本 / 子系列 | 卡牌版本信息 | Base |
| 评级状态 | Grader + Grade；未评级展示 Raw | BGS 9.5 / SGC 9 / Raw |
| Qty | 当前选中文件夹持有数量 | Qty: 0 / Qty: 1 |
| Collect / Collected | 加入 / 取消加入当前 Portfolio | Collect |
| Heart | 加入 / 移除 Wishlist | 空心 / 实心 |

### 6.2 推荐展示结构

评级体育卡：
```
Michael Jordan #57
$18,500.00
(+7.25%)
1986 Fleer
Base
BGS 9.5
Qty: 0        Collect    ♡
```

未评级体育卡：
```
Shohei Ohtani #17
$240.00
(+8.12%)
2024 Topps Chrome
Refractor
Raw
Qty: 0        Collect    ♡
```

### 6.3 字段规则

1. 体育卡主标题展示球员名 + 卡号。
2. 年份 + 系列 / 品牌为体育卡必要识别字段，必须展示。
3. 版本 / 子系列用于区分 Base、Refractor、Court Kings 5x7 等不同版本。
4. 评级卡展示 Grader + Grade，例如 BGS 9.5、SGC 9。
5. 未评级卡展示 Raw。
6. Search 列表不展示 Sport、Team、RC、Auto、Patch、Serial Number、Certification Number 等扩展字段；扩展字段可放在详情页或 Collection Item 中展示 / 编辑。
7. 价格缺失时展示 `--`；涨跌百分比缺失时展示 `-/-`。
8. 体育卡加入 Portfolio 后，Collection Item 需要保留 Quantity、Portfolio、Grader、Grade / Condition、Purchase Price、Notes 等收藏类字段。

---

## 七、Sealed Product 字段

适用于 Booster Box、Booster Pack、Elite Trainer Box、Case、Starter Deck、Structure Deck、Collection Box 等未拆封产品。

### 7.1 展示字段

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 图片 | 产品图，缺图展示占位图 | 盒图 / 包图 |
| 产品名称 | 主标题，超长省略 | Perfect Order Booster Box |
| 当前价格 | 当前市场参考价 | $222.61 |
| 30D Change % | 只展示百分比，不展示金额 | (+1.36%) |
| 系列名 | 产品所属系列 | Perfect Order |
| 状态 | 未拆封状态 | Sealed |
| Qty | 当前选中文件夹持有数量 | Qty: 0 / Qty: 1 |
| Collect / Collected | 加入 / 取消加入 Portfolio | Collect |
| Heart | 加入 / 移除 Wishlist | 空心 / 实心 |

### 7.2 推荐展示结构

```
Perfect Order Booster Box
$222.61
(+1.36%)
Perfect Order
Sealed
Qty: 0        Collect    ♡
```

### 7.3 字段规则

1. 主标题展示产品名称；第二层展示系列名；状态展示 Sealed。
2. Search 列表不强制展示 Product Type、Configuration、Language。
3. 如果产品名称中已包含 Booster Box、Elite Trainer Box、Collection 等信息，不再额外重复展示 Product Type。
4. Sealed Product 不展示 Card Number、Grader / Grade、Condition；状态以 Sealed 为主。
5. 价格缺失时展示 `--`；涨跌百分比缺失时展示 `-/-`。
6. Sealed Product 可加入 Portfolio，也可加入 Wishlist。
7. 加入 Portfolio 后，Collection Item 中保留 Quantity、Portfolio、Purchase Price、Notes 等收藏类字段。

---

## 八、其他特殊收藏品字段

其他特殊收藏品包括 Non-Sport Cards、特殊 Promo、Serialized / Auto / Patch / Memorabilia 特殊卡等。

Search 列表只保留通用必要字段，不展开过多特殊属性。

### 8.1 展示字段

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 图片 | 卡图 / 产品图 / 评级壳图，缺图展示占位图 | image |
| 名称 | 主标题，超长省略 | Darth Vader |
| 当前价格 | 当前市场参考价 | $86.00 |
| 30D Change % | 只展示百分比，不展示金额 | (+7.77%) |
| 系列 / IP / 年份品牌 | 归属信息 | Star Wars · Chrome Galaxy |
| 版本 / 状态 | 版本或状态信息 | Refractor · PSA 10 |
| Qty | 当前选中文件夹持有数量 | Qty: 0 |
| Collect / Collected | 加入 / 取消加入 Portfolio | Collect |
| Heart | 加入 / 移除 Wishlist | 空心 / 实心 |

### 8.2 推荐展示结构

```
Darth Vader
$86.00
(+7.77%)
Star Wars · Chrome Galaxy
Refractor · PSA 10
Qty: 0        Collect    ♡
```

特殊体育卡 / 限编卡示例：

```
CJ Stroud
$2,850.00
(+7.95%)
2023 Panini National Treasures
Auto Patch · PSA 9
Qty: 0        Collect    ♡
```

### 8.3 字段规则

1. 名称作为主标题。
2. 归属信息用于展示 IP、系列、年份品牌等。
3. 版本 / 状态信息用于展示 Variant、Raw、PSA 10、Auto Patch 等。
4. Search 列表不展示 Serial Number、Certification Number、详细签名认证、详细限编编号等复杂字段；复杂字段放在详情页或 Collection Item 中展示 / 编辑。
5. 价格缺失时展示 `--`；涨跌百分比缺失时展示 `-/-`。

---

## 九、Cards 列表汇总

| 类型 | 主标题 | 价格 | 涨跌 | 归属信息 | 版本 / 状态 | 收藏字段 |
|---|---|---|---|---|---|---|
| TCG 单卡 | 卡牌名称 | 当前价格 | 30D % | 系列名 | 稀有度 / 编号 + Finish | Qty + Collect + Heart |
| 体育卡 | 球员名 + 卡号 | 当前价格 | 30D % | 年份 + 系列 / 品牌 | 版本 / 子系列 + 评级状态 | Qty + Collect + Heart |
| Sealed Product | 产品名称 | 当前价格 | 30D % | 系列名 | Sealed | Qty + Collect + Heart |
| 其他特殊收藏品 | 名称 | 当前价格 | 30D % | IP / 系列 / 年份品牌 | 版本 / 状态 | Qty + Collect + Heart |

---

## 十、涨跌百分比展示规则

涨跌幅计算公式见 `global-rules.md §一`。

### 10.1 展示格式

| 状态 | 格式 |
|---|---|
| 上涨 | `(+4.76%)` |
| 下跌 | `(-4.17%)` |
| 无数据 | `-/-` |

### 10.2 规则

1. Search 列表固定展示 30D Change 百分比，不展示 7D、1D、1M 等其他周期。
2. Search 列表不展示涨跌金额。
3. 百分比保留 2 位小数。
4. 当前价格缺失时，涨跌百分比展示 `-/-`。
5. 30D Previous Price 缺失或为 0 时，涨跌百分比展示 `-/-`。
6. 百分比不随货币切换变化（见 `global-rules.md §七`）。

---

## 十一、字段展示优先级

### 11.1 TCG 单卡

图片 → 卡牌名称 → 当前价格 → 30D Change % → 系列名 → 稀有度 / 编号 → Finish → Qty → Collect / Heart

### 11.2 体育卡

图片 → 球员名 + 卡号 → 当前价格 → 30D Change % → 年份 + 系列 / 品牌 → 版本 / 子系列 → 评级状态 → Qty → Collect / Heart

### 11.3 Sealed Product

图片 → 产品名称 → 当前价格 → 30D Change % → 系列名 → Sealed → Qty → Collect / Heart

### 11.4 其他特殊收藏品

图片 → 名称 → 当前价格 → 30D Change % → IP / 系列 / 年份品牌 → 版本 / 状态 → Qty → Collect / Heart

---

## 十二、Qty 字段规则

Qty 表示当前账号在当前选中文件夹中的持有数量。

1. 未加入当前文件夹时展示 `Qty: 0`。
2. 已加入当前文件夹时展示对应数量，例如 `Qty: 1`。
3. 点击 Collect 快捷加入后，Qty 从 0 更新为 1。
4. 点击 Collected 取消加入后，Qty 更新为 0。
5. 如果同一对象在当前文件夹有多个 Collection Item，Qty 展示总数量。
6. Wishlist 不影响 Qty。
7. Qty 只统计当前选中文件夹，不统计其他文件夹。
8. TCG 单卡、体育卡、Sealed Product、特殊收藏品均展示 Qty。

---

## 十三、Collect / Collected 规则

1. Collect 表示该对象未加入当前选中文件夹。
2. 点击 Collect 后，将该对象一键加入当前选中的 Portfolio 文件夹（系统生成默认 Collection Item，见 §十五）。
3. 加入成功后按钮变为 Collected。
4. Collected 表示该对象已加入当前选中文件夹。
5. 再次点击 Collected，取消加入当前选中文件夹；取消成功后按钮恢复为 Collect。
6. 如果当前对象在其他文件夹中存在，但不在当前选中文件夹中，仍展示 Collect。
7. 如果同一对象在当前文件夹中存在多个 Collection Item，点击 Collected 不直接删除全部，进入详情页由用户手动管理，避免误删。
8. 操作失败时，Toast 见 `global-rules.md §四`。

---

## 十四、Wishlist 爱心规则

1. 空心爱心表示该对象未加入 Wishlist。
2. 点击空心爱心后将该对象加入 Wishlist；加入成功后爱心变为实心。
3. 实心爱心表示该对象已加入 Wishlist。
4. 再次点击实心爱心后将该对象从 Wishlist 移除；移除成功后爱心恢复为空心。
5. Wishlist 不计入 Home 总资产、不计入 Portfolio、不影响 Most Valuable、不影响 Qty。
6. 同一对象不可同时存在于 Portfolio 和 Wishlist；点击 Collect 自动移除 Wishlist。
7. 操作失败时，Toast 见 `global-rules.md §四`。

---

## 十五、快捷加入默认 Collection Item

用户从 Search 点击 Collect 后，系统生成默认 Collection Item，不进入编辑页。

### 15.1 TCG 单卡默认值

| 字段 | 默认值 |
|---|---|
| Quantity | 1 |
| Portfolio | 当前选中文件夹 |
| Grader | Raw / Ungraded |
| Condition | Near Mint |
| Language | 当前卡牌数据语言 |
| Finish | 当前卡牌 Finish |
| Purchase Price | 空 |
| Notes | 空 |

### 15.2 体育卡默认值

| 字段 | 默认值 |
|---|---|
| Quantity | 1 |
| Portfolio | 当前选中文件夹 |
| Grader | 若列表对象为评级卡则取列表 Grader；否则 Raw |
| Grade | 若列表对象为评级卡则取列表 Grade；否则空 |
| Condition | Raw 体育卡默认 Near Mint |
| Variant | 使用当前列表对象的版本 / 子系列数据 |
| Purchase Price | 空 |
| Notes | 空 |

### 15.3 Sealed Product 默认值

| 字段 | 默认值 |
|---|---|
| Quantity | 1 |
| Portfolio | 当前选中文件夹 |
| Status | Sealed |
| Product Type | 使用当前列表对象数据（后端存储字段，不在表单 UI 展示，见 `card-detail.md §7.3`） |
| Purchase Price | 空 |
| Notes | 空 |

### 15.4 其他特殊收藏品默认值

| 字段 | 默认值 |
|---|---|
| Quantity | 1 |
| Portfolio | 当前选中文件夹 |
| 状态字段 | 按对象类型带入 Raw / Graded / Sealed |
| Variant | 使用当前列表对象数据 |
| Purchase Price | 空 |
| Notes | 空 |

---

## 十六、Cards 列表展示规则

1. Cards 列表只展示当前 Game / IP 范围内的数据；默认 Game / IP 为 Pokémon。
2. 列表默认排列顺序**以第三方聚合数据为准**（见 `global-rules.md §十五 冲突3`）；搜索结果亦按此口径排序。
3. 切换 Game / IP 后，Cards 列表刷新为新 Game / IP 下的数据。
4. 名称超长时省略；系列名 / 产品名超长时省略。
5. 当前价格按用户当前货币展示，保留 2 位小数；价格缺失时展示 `--`（见 `global-rules.md §七`）。
6. 涨跌百分比缺失时展示 `-/-`。
7. 点击卡片非按钮区域，进入对应详情页（未加入 Portfolio / 已加入 Portfolio 两态，见 card-detail.md）。
8. Search 页价格为市场参考价，不代表用户 Portfolio 资产价值。
9. 用户点击 Collect 加入 Portfolio 后，Portfolio 中该对象的价值按 Collection Item 规则计算。
10. 接口：`searchCards(query, options)`（见 api-spec 数据代理端点）。

---

## 十七、Sets Tab

Sets Tab 用于搜索 / 浏览系列。

1. Sets Tab 展示当前 Game / IP 范围内的系列列表。
2. Sets 默认排列顺序**以第三方聚合数据为准**（见 `global-rules.md §十五 冲突3`）。
3. 搜索时接口参考 `searchCards(query, options)` 内部 set 层级结果（见 api-spec；⚠️ TBD：取决于厂商是否提供 Sets 专用搜索接口）。
4. Cards 和 Sets 的搜索结果、列表状态互不关联。
5. Sets 加载失败时，按 `global-rules.md §二` 局部失败规则展示 `No content available` + `Refresh`。

---

## 十八、加载与异常

所有加载 / 失败 / Toast / 网络异常规则引用 `global-rules.md`，本节只列 Search 场景适用点：

| 场景 | 处理 |
|---|---|
| Cards 列表加载失败 | 局部失败（§2.1）：`No content available` + `Refresh` |
| Sets 列表加载失败 | 局部失败（§2.1）：`No content available` + `Refresh` |
| 整页初始化数据全部失败 | 整页失败弹窗（§2.2）：`No content available` + `Refresh` |
| Collect 操作失败 | 通用 Toast（§4.1）：`Something went wrong. Please try again.` |
| Wishlist 操作失败 | 通用 Toast（§4.1）：`Something went wrong. Please try again.` |
| 网络断开 | 网络异常 Toast（§五） |
| 图片缺失 | 占位图（§六） |
| 价格缺失 | `--`（§七） |
| 涨跌幅缺失 | `-/-`（§七） |
