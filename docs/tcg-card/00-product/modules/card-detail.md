# Card Detail 模块 PRD

> **定位**：卡牌详情页展示单个收藏对象的基础信息、价格趋势、市场价格、交易入口，以及用户已收藏时的 Collection Item 信息。支持添加 / 编辑 / 移除 Portfolio 和 Wishlist。
>
> **日期**：2026-06-30
>
> **上游来源**：
> - 原始底稿 [`docs/tcg_cord_docs/卡牌详情.md`](../../../tcg_cord_docs/卡牌详情.md)
> - 跨切面规则 [`./global-rules.md`](./global-rules.md)（涨跌公式 / 失败 / Toast / 货币 / 确认弹窗——本文档只引用，不重复定义）
> - 术语表 [`../glossary.md`](../glossary.md)
> - 数据模型 [`../../03-data-api/data-model.md`](../../03-data-api/data-model.md)
> - API 规范 [`../../03-data-api/api-spec.md`](../../03-data-api/api-spec.md)

---

## 目录

1. [页面定位](#一页面定位)
2. [页面入口](#二页面入口)
3. [未加入 Portfolio 详情页](#三未加入-portfolio-详情页)
4. [未加入 Portfolio — 基础信息字段](#四未加入-portfolio--基础信息字段)
5. [已加入 Portfolio 详情页](#五已加入-portfolio-详情页)
6. [已加入 Portfolio — 基础信息字段](#六已加入-portfolio--基础信息字段)
7. [Collection Item 字段](#七collection-item-字段)
8. [Price Tab](#八price-tab)
9. [编辑 Collection Item 页面](#九编辑-collection-item-页面)
10. [Remove from Portfolio / Remove from Wishlist](#十remove-from-portfolio--remove-from-wishlist)
11. [状态与异常](#十一状态与异常)
12. [数据展示规则](#十二数据展示规则)

---

## 一、页面定位

收藏对象包括：

1. TCG 单卡
2. 体育卡
3. 评级卡
4. 套盒 / 卡包 / 整箱
5. 其他特殊收藏品

页面存在两种状态：

| 状态 | 说明 |
|---|---|
| **未加入 Portfolio** | 展示基础信息、Price、Market Prices、Shop；不展示用户持有信息 |
| **已加入 Portfolio** | 额外展示 Collection Item Tab；支持编辑、Remove from Portfolio、分享 |

---

## 二、页面入口

### 未加入 Portfolio 详情入口

| 入口 | 说明 |
|---|---|
| Search 列表点击卡牌 / 产品 | 主入口 |
| Wishlist 列表点击卡牌 / 产品 | Wishlist 浏览 |
| Trending Today 点击卡牌 / 产品 | Home 热榜 |
| Shop / Marketplace 场景中点击卡牌 / 产品 | 交易场景 |

### 已加入 Portfolio 详情入口

| 入口 | 说明 |
|---|---|
| Collection - Portfolio 列表点击卡牌 / 产品 | 主入口 |
| Home - Most Valuable 点击卡牌 / 产品 | Home 高价值卡片 |
| 扫描添加成功后从 Portfolio 列表进入 | Scan 流程完成后 |
| Portfolio 卡牌详情页编辑后返回 | 编辑流程内导航 |

---

## 三、未加入 Portfolio 详情页

### 3.1 页面通用字段

| 区域 | 字段 / 控件 | 说明 |
|---|---|---|
| 顶部 | 返回按钮 | 左上角返回 |
| 顶部 | Add to Portfolio 按钮 | 右上角文件夹加号，点击进入 Collection Item 添加流程 |
| 图片区 | 图片 | 展示卡牌图 / 体育卡图 / 产品图，缺图展示占位图（见 `global-rules.md §六`） |
| 基础信息 | 按对象类型展示 | TCG / 体育卡 / Sealed / 特殊卡字段不同（见 §四） |
| 操作入口 | View Sold Listings | 查看成交记录，接口 `getSoldListings(card_ref)` |
| Tab | Price | 当前展示价格页 |
| Price 图表 | Raw / Graded / Sealed 等价格图表 | 按对象类型展示，接口 `getPriceSeries(card_ref, ...)` |
| Market Prices | 不同状态市场价 | 按对象类型展示，接口 `getMarketPrices(card_ref)` |
| Shop | Marketplace 列表 | 日期、商品标题、价格、平台 |

### 3.2 页面规则

1. 未加入 Portfolio 的详情页不展示 Collection Item。
2. 未加入 Portfolio 的详情页不展示 Remove from Portfolio。
3. 未加入 Portfolio 的详情页展示 Price、Market Prices、Shop。
4. 点击 View Sold Listings 进入成交记录页或打开成交记录列表。
5. 页面右上角图标为 Add to Portfolio 按钮。
6. 点击 Add to Portfolio 后，进入 Collection Item 添加页，用户填写收藏信息后才加入 Portfolio。
7. 接口：`getCard(card_ref)`（见 api-spec 数据代理端点）。

---

## 四、未加入 Portfolio — 基础信息字段

### 4.1 TCG 单卡基础信息

适用于 Pokémon、Yu-Gi-Oh!、Magic、One Piece 等普通单卡。

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 卡牌名称 | 主标题 | Charizard ex |
| IP / Game | 所属 IP / 游戏 | Pokémon |
| Set / 系列 | 卡牌所属系列 | Obsidian Flames |
| 稀有度 / 编号 | 卡牌版本信息 | Special Illustration Rare · #223/197 |
| Finish / Variant | 工艺 / 版本 | Holofoil |
| Language | 卡牌语言 | English |

**规则**：
1. 卡牌名称为主标题。
2. IP / Game、Set、编号、Finish、Language 用于确认具体卡牌版本。
3. 同名但不同 Set、编号、语言、Finish 的卡牌视为不同卡牌。
4. Finish / Variant 缺失时可不展示；Language 缺失时可不展示。
5. 字段展示需和 Search 列表保持一致，但详情页可展示更完整文本，不需要省略到列表长度。

### 4.2 体育卡基础信息

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 球员名 + 卡号 | 主标题 | Michael Jordan #57 |
| 年份 + 系列 / 品牌 | 核心归属信息 | 1986 Fleer |
| 版本 / 子系列 | 卡牌版本信息 | Base |
| 评级状态 | Grader + Grade；未评级展示 Raw | BGS 9.5 / SGC 9 / Raw |

**规则**：
1. 体育卡主标题展示球员名 + 卡号。
2. 年份 + 系列 / 品牌为必要识别字段，必须展示。
3. 版本 / 子系列用于区分 Base、Refractor、Court Kings 5x7 等不同版本。
4. 评级卡展示 Grader + Grade；未评级卡展示 Raw。
5. 详情基础信息不展示 Sport、Team、RC、Auto、Patch、Serial Number、Certification Number 等扩展字段；如后续需要，可放入详情页扩展信息区，不放在首版基础信息字段中。
6. Add to Portfolio 时，Collection Item 中保留 Quantity、Portfolio、Grader、Grade / Condition、Purchase Price、Notes 等收藏类字段。

### 4.3 Sealed Product 基础信息

适用于 Booster Box、Booster Pack、Elite Trainer Box、Case、Starter Deck、Structure Deck、Collection Box 等未拆封产品。

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 产品名称 | 主标题 | Perfect Order Booster Box |
| 系列名 | 产品所属系列 | Perfect Order |
| 状态 | 未拆封状态 | Sealed |

**规则**：
1. Sealed Product 主标题展示产品名称；第二层展示系列名；状态展示 Sealed。
2. 如果产品名称中已包含 Booster Box、Elite Trainer Box、Collection 等信息，不再额外重复展示 Product Type。
3. 基础信息不展示 Card Number、Grader / Grade、Condition；不强制展示 Configuration、Language。
4. 如后续需要展示 Language / Configuration，可放在详情页扩展信息区，不放在首版基础信息字段中。
5. Add to Portfolio 时，Collection Item 中保留 Quantity、Portfolio、Status、Purchase Price、Notes 等收藏类字段。

### 4.4 其他特殊收藏品基础信息

包括：Non-Sport Cards、特殊 Promo、Serialized / Auto / Patch / Memorabilia 特殊卡、其他无法归类到普通 TCG 单卡 / 体育卡 / Sealed Product 的收藏对象。

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 名称 | 主标题 | Darth Vader |
| 系列 / IP / 年份品牌 | 归属信息 | Star Wars · Chrome Galaxy |
| 版本 / 状态 | 版本或状态信息 | Refractor · PSA 10 |

**规则**：
1. 名称作为主标题。
2. 归属信息用于展示 IP、系列、年份品牌等。
3. 版本 / 状态信息用于展示 Variant、Raw、PSA 10、Auto Patch 等。
4. 基础信息不展示 Serial Number、Certification Number、详细签名认证、详细限编编号等复杂字段；复杂字段后续可放在扩展信息区或 Collection Item 中展示 / 编辑。
5. Add to Portfolio 时，Collection Item 按对象类型带入 Raw / Graded / Sealed 等默认状态。

---

## 五、已加入 Portfolio 详情页

### 5.1 页面通用字段

| 区域 | 字段 / 控件 | 说明 |
|---|---|---|
| 顶部 | 返回按钮 | 左上角返回 |
| 顶部 | 分享按钮 | 右上角分享图标 |
| 图片区 | 图片 | 展示卡牌图 / 体育卡图 / 产品图，缺图展示占位图 |
| 基础信息 | 按对象类型展示 | TCG / 体育卡 / Sealed / 特殊卡字段不同（见 §六） |
| 操作入口 | View Sold Listings | 查看成交记录 |
| Tab | Collection Item、Price | 已加入 Portfolio 状态下展示两个 Tab |
| Collection Item | Ownership Summary | 用户持有信息 |
| Collection Item | Edit item | 编辑入口 |
| Collection Item | Quantity | 用户持有数量 |
| Collection Item | Portfolio | 所属文件夹 |
| Collection Item | Grader / Condition / Grade / Status | 按对象类型展示 |
| Collection Item | Language / Finish | TCG 单卡展示 |
| Collection Item | Purchase Price | 用户购买成本记录 |
| Collection Item | Notes | 用户备注 |
| 底部操作 | Remove from Portfolio | 从 Portfolio 移除 |

### 5.2 页面规则

1. 已加入 Portfolio 的详情页默认展示 Collection Item Tab。
2. 用户可切换到 Price Tab 查看价格趋势、Market Prices 和 Shop。
3. Collection Item 展示用户当前持有记录，不是公共基础信息。
4. 点击 Edit item 进入编辑 Collection Item 页面（见 §九）。
5. 点击分享按钮，调起 iOS 原生分享组件，可分享至第三方 App。
6. 点击 Remove from Portfolio 触发移除确认流程（见 `global-rules.md §九`）。
7. 移除成功后，该对象从当前 Portfolio 文件夹删除，Home 总资产、图表、Most Valuable、Collection Portfolio 列表需要刷新。
8. 如果该对象同时在 Wishlist 中，Remove from Portfolio 不影响 Wishlist 状态。
9. 如果同一对象在 Portfolio 中有多个 Collection Item，点击某一项进入的详情只编辑 / 删除当前 Collection Item。

---

## 六、已加入 Portfolio — 基础信息字段

已加入 Portfolio 的基础信息字段与未加入 Portfolio 保持一致，区别是额外展示 Collection Item Tab。

### 6.1 TCG 单卡基础信息

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 卡牌名称 | 主标题 | Charizard ex |
| IP / Game | 所属 IP / 游戏 | Pokémon |
| Set / 系列 | 卡牌所属系列 | Obsidian Flames |
| 稀有度 / 编号 | 卡牌版本信息 | Special Illustration Rare · #223/197 |
| Finish / Variant | 工艺 / 版本 | Holofoil |
| Language | 卡牌语言 | English |

### 6.2 体育卡基础信息

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 球员名 + 卡号 | 主标题 | Michael Jordan #57 |
| 年份 + 系列 / 品牌 | 核心归属信息 | 1986 Fleer |
| 版本 / 子系列 | 卡牌版本信息 | Base |
| 评级状态 | Grader + Grade；未评级展示 Raw | BGS 9.5 / SGC 9 / Raw |

### 6.3 Sealed Product 基础信息

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 产品名称 | 主标题 | Perfect Order Booster Box |
| 系列名 | 产品所属系列 | Perfect Order |
| 状态 | 未拆封状态 | Sealed |

### 6.4 其他特殊收藏品基础信息

| 字段 | 展示规则 | 示例 |
|---|---|---|
| 名称 | 主标题 | Darth Vader |
| 系列 / IP / 年份品牌 | 归属信息 | Star Wars · Chrome Galaxy |
| 版本 / 状态 | 版本或状态信息 | Refractor · PSA 10 |

---

## 七、Collection Item 字段

Collection Item 展示用户对当前对象的持有记录。不同对象类型字段有所不同，但尽量复用统一结构。

### 7.1 TCG 单卡 Collection Item 字段

| 字段 | 说明 |
|---|---|
| Quantity | 用户持有数量 |
| Portfolio | 当前所属文件夹 |
| Grader | Raw、PSA、BGS、TAG、CGC、AGS 等 |
| Condition / Grade | Raw 卡展示 Condition；Graded 卡展示 Grade |
| Language | 卡牌语言 |
| Finish | 工艺 / 版本 |
| Purchase Price | 用户购买成本记录 |
| Notes | 用户备注 |

**规则**：
1. Quantity 默认 1，必须为正整数。
2. Portfolio 默认当前目标文件夹。
3. Raw 卡使用 Condition；Graded 卡使用 Grader + Grade；两者不可混用。
4. Purchase Price 不参与当前市场价值计算；Notes 可为空。

### 7.2 体育卡 Collection Item 字段

| 字段 | 说明 |
|---|---|
| Quantity | 用户持有数量 |
| Portfolio | 当前所属文件夹 |
| Grader | Raw、PSA、BGS、SGC、CGC 等 |
| Condition / Grade | Raw 卡展示 Condition；Graded 卡展示 Grade |
| Purchase Price | 用户购买成本记录 |
| Notes | 用户备注 |

**规则**：
1. 体育卡 Collection Item 不展示 Sport、Team、RC、Auto、Patch、Serial Number、Certification Number 等扩展字段。
2. 评级体育卡使用 Grader + Grade 判断价格口径；未评级体育卡使用 Raw + Condition 判断价格口径。
3. 如果列表对象本身为评级卡，点击 Collect 后默认带入对应 Grader 和 Grade；如果为未评级卡，默认 Grader = Raw，Condition = Near Mint。
4. Purchase Price 不参与当前市场价值计算；Notes 可为空。

### 7.3 Sealed Product Collection Item 字段

| 字段 | 说明 |
|---|---|
| Quantity | 用户持有数量 |
| Portfolio | 当前所属文件夹 |
| Status | 默认 Sealed |
| Purchase Price | 用户购买成本记录 |
| Notes | 用户备注 |

**规则**：
1. Quantity 默认 1；Status 默认 Sealed；Sealed 状态参与价格取值。
2. Sealed Product 不展示 Grader / Grade、Condition、Language、Configuration、Product Type 等扩展字段。
3. Purchase Price 不参与当前市场价值计算。
4. Total = Sealed 当前市场价 × Quantity；如果价格缺失，Total 展示 `--`，仍允许保存。

### 7.4 其他特殊收藏品 Collection Item 字段

| 字段 | 说明 |
|---|---|
| Quantity | 用户持有数量 |
| Portfolio | 当前所属文件夹 |
| 状态字段 | 按对象类型展示 Raw / Graded / Sealed |
| Condition / Grade | Raw 展示 Condition；Graded 展示 Grade；Sealed 不展示 |
| Purchase Price | 用户购买成本记录 |
| Notes | 用户备注 |

**规则**：
1. 特殊收藏品按对象类型判断状态字段：Raw 使用 Condition；Graded 使用 Grader + Grade；Sealed 使用 Status = Sealed。
2. 不在首版 Collection Item 展示 Serial Number、Certification Number、签名认证等复杂字段。
3. Purchase Price 不参与当前市场价值计算；Notes 可为空。

---

## 八、Price Tab

Price Tab 展示价格趋势、不同状态下的市场价格，以及可跳转的交易网站信息。

### 8.1 图表与市场价格

| 区域 | 说明 |
|---|---|
| 图表切换 | RAW、GRADED |
| 图表时间周期 | 1M、3M、6M、12M、MAX |
| Market Prices 分组 | Ungraded、PSA、ACE、BGS 等 |
| Market Prices 表格列 | Grade / Condition、Market、7D Change |
| Shop | Marketplace 商品列表（日期、标题、价格、平台） |

### 8.2 接口

- 价格序列：`getPriceSeries(card_ref, grader, grade, condition, days)`
- 市场价格：`getMarketPrices(card_ref)`
- 成交记录：`getSoldListings(card_ref)`

### 8.3 规则

1. 价格图表、Market Prices、Shop 可分区加载，互不阻塞。
2. 数据加载失败时按局部失败规则处理（见 `global-rules.md §2.1`）。
3. Market 价格缺失时展示 `--`；7D Change 缺失时展示 `-/-`。
4. 无价格数据时图表展示 `No price data available.`。
5. 无价格数据不影响用户编辑 Collection Item；无价格数据的 Collection Item 不计入 Home 总资产和 Most Valuable 排序（见 `global-rules.md §十五 冲突1`）。

---

## 九、编辑 Collection Item 页面

编辑 Collection Item 页面用于修改用户已收藏对象的持有信息和价格取值口径。

### 9.1 页面通用字段

| 区域 | 字段 / 控件 | 说明 |
|---|---|---|
| 顶部 | 返回按钮 | 返回详情页 |
| 顶部 | 分享按钮 | 右上角分享 |
| 图片区 | 图片 | 当前对象图片 |
| 基础信息 | 按对象类型展示 | 与详情页基础信息一致 |
| 操作入口 | View Sold Listings | 查看成交记录 |
| Tab | Collection Item、Price | 当前停留 Collection Item |
| 编辑区 | Ownership Summary | 持有信息 |
| 编辑区 | Cancel | 取消编辑 |
| 编辑区 | Save changes | 保存修改 |

### 9.2 编辑页基础信息

编辑页顶部基础信息与详情页基础信息保持一致：

- **TCG 单卡**：卡牌名称、IP / Game、Set / 系列、稀有度 / 编号、Finish / Variant、Language
- **体育卡**：球员名 + 卡号、年份 + 系列 / 品牌、版本 / 子系列、评级状态
- **Sealed Product**：产品名称、系列名、状态 Sealed
- **其他特殊收藏品**：名称、系列 / IP / 年份品牌、版本 / 状态

### 9.3 编辑页表单字段

**TCG 单卡**

| 字段 | 说明 |
|---|---|
| Quantity | 数量 |
| Portfolio | 所属文件夹 |
| Grader | Raw、PSA、BGS、TAG、CGC、AGS |
| Condition / Grade | Raw 卡展示 Condition；Graded 卡展示 Grade |
| Language | 语言 |
| Finish | 工艺 / 版本 |
| Purchase Price | 用户购买成本 |
| Notes | 备注 |

**体育卡**

| 字段 | 说明 |
|---|---|
| Quantity | 数量 |
| Portfolio | 所属文件夹 |
| Grader | Raw、BGS、SGC、PSA、CGC 等 |
| Condition / Grade | Raw 展示 Condition；Graded 展示 Grade |
| Purchase Price | 用户购买成本 |
| Notes | 备注 |

**Sealed Product**

| 字段 | 说明 |
|---|---|
| Quantity | 数量 |
| Portfolio | 所属文件夹 |
| Status | Sealed |
| Purchase Price | 用户购买成本 |
| Notes | 备注 |

**其他特殊收藏品**

| 字段 | 说明 |
|---|---|
| Quantity | 数量 |
| Portfolio | 所属文件夹 |
| 状态字段 | Raw / Graded / Sealed |
| Condition / Grade | 按状态展示 |
| Purchase Price | 用户购买成本 |
| Notes | 备注 |

### 9.4 编辑规则

1. 点击已加入 Portfolio 详情页中的 Edit item 进入编辑状态。
2. 编辑页顶部基础信息保持展示，不因编辑状态变化。
3. 用户点击 Cancel 后放弃修改，返回详情页展示原数据。
4. 用户点击 Save changes 后保存修改；保存成功后返回已加入 Portfolio 详情页，并刷新 Collection Item 展示。
5. 保存失败时停留编辑页，用户已输入内容不得丢失；Toast 见 `global-rules.md §四`。
6. 保存成功后，Home、Collection、Most Valuable、图表等涉及该对象的数据需要按新字段刷新。

### 9.5 Quantity 规则

1. Quantity 必填，必须为正整数，不能为 0。
2. 修改 Quantity 后，该 Collection Item 当前价值随之变化：当前价值 = 对应市场价 × Quantity。
3. Quantity 修改后，Home 总资产需要同步更新。

### 9.6 Portfolio 规则

1. Portfolio 字段展示当前所属文件夹；用户可切换 Portfolio 文件夹。
2. 如果用户将对象移动到其他文件夹，保存后该对象从原文件夹移除，加入新文件夹。
3. 文件夹变更后：原文件夹总资产刷新；新文件夹总资产刷新；Home / Collection 中对应列表同步更新。
4. 如果保存失败，不改变原文件夹归属。

### 9.7 Grader / Condition / Grade 规则

1. Grader 用于决定该 Collection Item 的价格取值口径。
2. Raw 表示未评级；PSA / BGS / SGC / TAG / CGC / AGS 表示评级对象。
3. 用户选择 Raw 时，价格取 Raw / Ungraded 市场价。
4. 用户选择评级机构时，必须选择对应等级；评级机构和等级共同决定 Graded 市场价。
5. 如果所选评级机构 / 等级无市场价，当前价值展示 `--`，但允许保存。
6. Condition 用于 Raw 品相；用户选择评级机构后，Condition 隐藏或置灰，避免 Raw 品相和评级状态混用。

### 9.8 Purchase Price 规则

1. Purchase Price 是用户记录的购买成本，不参与当前市场价值计算。
2. Purchase Price 可为 0，按当前 App 货币展示；如果切换货币，Purchase Price 需要换算（见 `global-rules.md §七`）。

### 9.9 Notes 规则

1. Notes 为用户备注，可为空，保存后展示在 Collection Item 详情中。
2. 字数上限 500 字符。

### 9.10 表单校验

| 场景 | 提示文案 |
|---|---|
| Quantity 为空 | `Please enter a quantity.` |
| Quantity 为 0 或负数 | `Quantity must be at least 1.` |
| Quantity 非整数 | `Quantity must be a whole number.` |
| Purchase Price 非数字 | `Please enter a valid price.` |
| Notes 超长 | `Notes must be 500 characters or less.` |

---

## 十、Remove from Portfolio / Remove from Wishlist

### 10.1 Remove from Portfolio

已加入 Portfolio 详情页中展示 Remove from Portfolio 按钮。

**规则**：
1. 点击 Remove from Portfolio 后，展示二次确认弹窗（见 `global-rules.md §九`）。
2. 用户确认后，将当前 Collection Item 从 Portfolio 移除；该对象不再出现在对应 Portfolio 文件夹中。
3. 移除成功后，Home 总资产、Home 图表、Most Valuable、Collection 列表刷新。
4. 如果当前对象仅有这一条 Collection Item，移除后返回 Collection Portfolio 列表。
5. 如果同一对象还有其他 Collection Item，移除当前项后返回上一页或刷新详情。
6. Remove from Portfolio 不影响 Wishlist 状态。

### 10.2 Remove from Wishlist

未加入 Portfolio 且已加入 Wishlist 的详情页，底部展示 Remove from Wishlist 按钮。

**规则**：
1. 点击 Remove from Wishlist 后，展示二次确认弹窗（见 `global-rules.md §九`）。
2. 用户确认后，将当前对象从 Wishlist 移除；该对象不再出现在 Wishlist 列表中。
3. Remove from Wishlist 不影响 Portfolio 状态。

---

## 十一、状态与异常

所有跨切面异常规则引用 `global-rules.md`，以下为 Card Detail 场景的具体适用：

| 场景 | 处理 |
|---|---|
| 整页基础信息加载失败 | 整页失败弹窗（§2.2）：`No content available` + `Refresh`；用户可点击返回 |
| Price 图表加载失败 | 局部失败（§2.1）：`No content available` + `Refresh`；不影响基础信息、Market Prices、Shop |
| Market Prices 加载失败 | 局部失败（§2.1）：`No content available` + `Refresh` |
| Shop 加载失败 | 局部失败（§2.1）：`No content available` + `Refresh`；不阻塞整页 |
| 图表无数据 | `No price data available.` |
| Market 价格缺失 | `--` |
| 7D Change 缺失 | `-/-` |
| 保存 Collection Item 失败 | 停留编辑页，保留用户输入；Toast：`Something went wrong. Please try again.` |
| 网络断开 | 网络异常 Toast（§五）；已加载旧数据可继续展示；不清空用户输入 |
| 图片缺失 | 占位图（§六） |

---

## 十二、数据展示规则

### 12.1 金额规则

1. 所有金额按 App 当前选择货币展示，切换货币后详情页金额同步换算（见 `global-rules.md §七`）。
2. 金额保留 2 位小数；价格缺失展示 `--`；百分比不因货币切换变化。

### 12.2 Price 与 Collection Item 的关系

1. Price Tab 展示公共市场价格；Collection Item 展示用户持有记录。
2. 用户在 Collection Item 中选择 Raw / Graded、Condition、Language、Finish 等字段后，会影响该持有项的价格取值口径。
3. Home 总资产、Collection 当前价值、Most Valuable 都应使用 Collection Item 中保存后的字段取价。
4. Purchase Price 不参与市场价值，只用于用户成本记录。

### 12.3 Raw / Graded / Sealed 显示规则

1. Raw 对象展示 Condition；Graded 对象展示 Grader + Grade；Sealed Product 展示 Status = Sealed。
2. Raw 品相和评级状态不可混用；Sealed Product 不展示 Raw / Graded 作为主状态。
