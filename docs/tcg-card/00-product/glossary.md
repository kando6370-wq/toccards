# tcg-card 术语表（Glossary）

> **定位**：本文档是 tcg-card 项目所有文档的术语统一来源，凡涉及下列概念，均以本表口径为准。
> **最后更新**：2026-06-30
> **上游来源**：
> - Spec：[`docs/superpowers/specs/2026-06-30-tcg-card-preparation-design.md`](../../superpowers/specs/2026-06-30-tcg-card-preparation-design.md) —— 重点 §2、§4
> - 原始 PRD：[`docs/tcg-card/source-tcg-card-docs/`](../source-tcg-card-docs/)

---

## 说明

- 英文标识符（字段名 / 接口名 / 枚举值）大小写遵循本表，各模块文档保持一致。
- 跨切面规则（涨跌计算公式、货币换算、失败状态）不在本表重复，见 [`modules/global-rules.md`](modules/global-rules.md)。

---

## 术语条目

### Portfolio

**英文标识符**：`Portfolio`

**中文释义**：用户持有资产集合。Portfolio 中的卡牌参与 Home 总资产计算、图表、Most Valuable 排序。

**用法**：用户将已拥有的卡牌加入 Portfolio；每个 Portfolio Folder（文件夹）下维护一组 Portfolio 卡牌；Collection 页面 Portfolio Tab 展示当前选中文件夹内的全部持有卡牌；价值 = 各 Collection Item 当前市场价 × 数量之和（缺价卡不计入）。

---

### Wishlist

**英文标识符**：`Wishlist`

**中文释义**：心愿单。用户想关注或计划购买但暂未持有的卡牌列表。

**用法**：Wishlist **不参与**总资产计算、Home 图表、Most Valuable 排序；Wishlist 无文件夹；同一对象不可同时存在于 Portfolio 和 Wishlist——点击 Collect 时自动从 Wishlist 移除；Collection 页面 Wishlist Tab 展示全量心愿单。

---

### Folder / Portfolio Folder

**英文标识符**：`Folder`（数据库表名建议 `folders`）

**中文释义**：Portfolio 文件夹。用于将用户持有卡牌分组管理（如"Sealed Collection"、"High Value Cards"）。

**用法**：每个文件夹独立维护一组 Portfolio 卡牌；Home 和 Collection 的 Portfolio 数据都以当前选中文件夹为范围；文件夹可新建、重命名、排序、删除（default folder 除外）；Wishlist 无文件夹。

---

### default folder

**英文标识符**：`default_folder`（字段 `is_default: boolean`）

**中文释义**：默认文件夹（星标文件夹）。App 冷启动后默认展示的文件夹，以小星星标识。

**用法**：全局唯一，不可删除；首次创建时系统自动生成名为 "Main" 的 default folder；用户可通过点击星标切换；手动切换文件夹的优先级高于 default folder，但只持续到下一次冷启动——下一次冷启动重新回到 default folder。

---

### Collection Item

**英文标识符**：`CollectionItem`（数据库表名建议 `collection_items`）

**中文释义**：用户持有记录。记录用户对某张具体卡牌的一次持有行为，包含数量、状态（Raw / Graded / Sealed）、价格口径字段、购买价格、备注等。

**用法**：同一张卡可存在多条 Collection Item（例如同时持有 Raw 和 PSA 9 各一张，视为两条记录）；`Quantity` 参与当前价值计算（当前价值 = 单张市场价 × Quantity）；`Purchase Price` 仅作为用户成本记录，**不参与**市场价值计算；Collection Item 中的 `Grader`/`Condition`/`Grade` 字段决定该条记录的价格取值口径（Raw 取 Raw 市场价；Graded 按评级机构和等级取价）。

---

### Grader

**英文标识符**：`Grader`（枚举值见下）

**中文释义**：评级机构 / 评级状态标识符。用于标注卡牌是否经过专业评级，以及评级机构。

**枚举值**：
| 枚举值 | 说明 |
|---|---|
| `Raw` | 未评级（未经专业机构鉴定） |
| `PSA` | Professional Sports Authenticator |
| `BGS` | Beckett Grading Services |
| `CGC` | Certified Guaranty Company |
| `SGC` | Sportscard Guaranty |
| `TAG` | TAG Grading |
| `AGS` | Apex Grading Services |

**用法**：`Grader = Raw` 时取 Raw 市场价；`Grader` 为评级机构时，需配合 `Grade`（评级等级）共同决定 Graded 市场价；Raw 品相（`Condition`）与评级状态不可混用。

---

### Condition

**英文标识符**：`Condition`（Raw 品相，枚举值如 `Near Mint`、`Lightly Played`、`Moderately Played` 等，依第三方数据源口径为准）

**中文释义**：Raw 品相。仅在 `Grader = Raw` 时使用，描述未评级卡牌的实物品相等级。

**用法**：`Condition` 与 `Grader = Raw` 配合使用；卡牌被标记为评级卡（Grader ≠ Raw）后，`Condition` 字段隐藏或置灰，不可填写，避免品相与评级状态混用；快捷加入 Portfolio 时，Raw 卡默认 `Condition = Near Mint`。

---

### Grade

**英文标识符**：`Grade`（数值型，如 `9`、`9.5`、`10`）

**中文释义**：评级等级。仅在 `Grader` 为专业评级机构时使用，表示该评级机构给出的分数。

**用法**：`Grade` 与 `Grader`（非 Raw）共同确定 Graded 市场价的取值口径；如所选 `Grader` + `Grade` 组合无市场价，当前价值展示 `--`，但允许保存；`Grade` 不与 `Condition` 同时展示。

---

### Finish / Variant

**英文标识符**：`Finish`（工艺 / 版本，枚举值如 `Holofoil`、`Reverse Holo`、`1st Edition` 等，依第三方数据源为准）

**中文释义**：卡牌工艺或版本标识。用于区分同名卡牌的不同印制版本或特殊工艺。

**用法**：主要用于 TCG 单卡；`Finish` 影响卡牌的唯一标识（同名不同 Finish 视为不同卡牌）；Collection Item 中 `Finish` 字段可由用户在编辑时确认或修改；Search 列表和 Collection 列表均展示 `Finish`。

---

### Sealed Product

**英文标识符**：`SealedProduct`（对象类型标识符）

**中文释义**：套盒 / 卡包 / 整箱等未拆封产品。包括 Booster Box、Booster Pack、Elite Trainer Box、Case、Starter Deck、Structure Deck、Collection Box 等。

**用法**：Sealed Product 的 Collection Item 中展示 `Status = Sealed`（不展示 `Grader`/`Grade`/`Condition`）；价格取值以 Sealed 状态市场价为准；可加入 Portfolio 或 Wishlist；Portfolio 当前价值 = Sealed 市场价 × Quantity。

---

### Raw / Graded / Sealed（三类状态口径）

**英文标识符**：`Raw`、`Graded`、`Sealed`（Collection Item 状态分类）

**中文释义**：卡牌 / 产品的持有状态三分类，决定价格取值口径。

**用法**：
- **Raw**：未评级单卡；价格取 Raw 市场价；展示 `Condition`；不展示评级信息。
- **Graded**：已经专业评级的单卡；价格取对应 `Grader` + `Grade` 的 Graded 市场价；不展示 `Condition`。
- **Sealed**：未拆封产品；价格取 Sealed 市场价；不展示 `Grader`/`Grade`/`Condition`。

三类状态不可混用；各模块展示时严格按此口径区分。

---

### Trending Today

**英文标识符**：`TrendingToday`

**中文释义**：今日涨幅榜。展示二级市场（数据来自第三方聚合 API）当天升值幅度最高的卡牌列表。

**用法**：不受当前选中文件夹影响，不要求用户收藏；Home 首页展示 3 条；排序按当天涨幅百分比降序；涨跌幅不随货币切换变化；数据源为第三方聚合 API（⚠️ TBD：具体厂商待定），经 Workers 缓存后提供。

---

### Most Valuable

**英文标识符**：`MostValuable`

**中文释义**：最高价值卡。当前选中 Portfolio 文件夹内单张市场价最高的卡牌。

**用法**：只统计 Portfolio，不统计 Wishlist；按 Collection Item 状态取单张市场价（Raw 取 Raw 价、Graded 取对应评级价）；多 Quantity 不改变排序，排序以单张价值为准；同价值时按 30D 涨幅优先，再按最近添加时间优先；缺价卡不参与排序；固定展示 30D Change 百分比。

---

### Guest / Anonymous Account（游客匿名账号）

**英文标识符**：`GuestAccount`（后端实体 `anonymous_account`）

**中文释义**：游客匿名账号。用户未注册 / 未登录时，App 首次启动即在后端自动创建的匿名账号，绑定设备标识。

**用法（以 Spec §4.5 为唯一真相源，修正原 PRD 中"仅本地"的表述）**：
- 游客资产**实时同步到 D1**（后台用户管理可见游客账号）；
- 匿名账号**无登录凭证**，用户**无法跨设备登录恢复**（换设备 = 新匿名账号）；
- **注册** = 匿名账号升级为正式账号，资产保留（迁移到新账号）；
- **登录已有账号** = 不合并匿名资产，切换到已有账号资产。

---

### override layer（卡牌覆盖层）

**英文标识符**：`override`（D1 表名建议 `card_overrides`）

**中文释义**：卡牌数据覆盖层。存储于 D1，用于补充第三方聚合 API 缺失的卡牌、纠正数据错误、补充卡牌图片、存放运营数据（如 Trending 置顶）。

**用法**：读取卡牌数据时，覆盖层优先，无覆盖数据则回落第三方实时数据；管理后台"卡牌数据运维"模块负责维护覆盖层；App 端和管理后台均不直连第三方，统一经 Workers 代理。

---

### 30D Change

**英文标识符**：`change_30d`（字段）

**中文释义**：30 天涨跌幅。表示当前市场价相对 30 天前同口径市场价的变化百分比。

**用法**：计算公式见 `modules/global-rules.md`；展示在 Collection 卡牌列表、Wishlist 列表、Most Valuable 区域、Search 列表；**不随货币切换变化**（按原始价格序列计算）；30 天前无有效价格时展示 `-/-`；正数展示 `+`，负数展示 `-`。
