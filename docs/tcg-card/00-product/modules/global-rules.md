# 全局规则 —— 跨切面单一真相源

> **定位**：本文件是 tcg-card v1.0 所有跨切面规则的**唯一真相源**。
> 架构、数据模型、API Spec、各模块 PRD 均**引用**本文件，不在自身文档中重复定义以下规则。
>
> **日期**：2026-06-30
>
> **来源**：
> - 原始底稿 [`docs/tcg-card/source-tcg-card-docs/全局用其他补充事项.md`](../../source-tcg-card-docs/全局用其他补充事项.md)
> - API 规范 [`docs/tcg-card/03-data-api/api-spec.md`](../../03-data-api/api-spec.md)
> - 模块 PRD：`个人中心.md`、`卡牌详情.md`、`collection说明.md`、`home页说明.md`

---

## 目录

1. [涨跌幅计算公式](#一涨跌幅计算公式)
2. [加载、失败、空状态规则](#二加载失败空状态规则)
3. [全局 Loading 动效](#三全局-loading-动效)
4. [操作失败 Toast](#四操作失败-toast)
5. [全局网络异常 Toast](#五全局网络异常-toast)
6. [图片缺失规则](#六图片缺失规则)
7. [金额与百分比规则](#七金额与百分比规则)
8. [登录与账号规则](#八登录与账号规则)
9. [确认弹窗规则](#九确认弹窗规则)
10. [刷新规则](#十刷新规则)
11. [防重复点击规则](#十一防重复点击规则)
12. [状态优先级](#十二状态优先级)
13. [统一文案表](#十三统一文案表)
14. [游客状态与资产规则](#十四游客状态与资产规则)
15. [已固化口径（原 PRD 冲突解消）](#十五已固化口径原-prd-冲突解消)
16. [统计口径汇总](#十六统计口径汇总)
17. [价格来源、唯一性与异常价格口径](#十七价格来源唯一性与异常价格口径)
18. [时区口径](#十八时区口径)
19. [公共卡牌后台变更口径](#十九公共卡牌后台变更口径)

---

## 一、涨跌幅计算公式

### 1.1 通用公式

```
涨跌幅 = (当前价格 - 周期起点价格) / 周期起点价格 × 100%
```

### 1.2 周期价格取值

| 周期 | 计算口径 |
|---|---|
| 7D Change % | (当前价格 - 7 天前价格) / 7 天前价格 × 100% |
| 30D Change % | (当前价格 - 30 天前价格) / 30 天前价格 × 100% |
| 3M / 6M Change % | (当前价格 - 周期起点价格) / 周期起点价格 × 100% |

**说明**：
- 周期起点价格取该周期起点当天的有效市场价。
- 如果周期起点当天无价格，优先使用该时间点之前最近一次有效价格。
- 如果没有任何有效历史价格，则涨跌金额展示 `--`，涨跌幅展示 `-/-`。

### 1.3 Portfolio 总资产涨跌

```
总资产涨跌幅 = (当前文件夹资产价值 - 周期起点时该文件夹总资产) / 周期起点时该文件夹总资产 × 100%
```

### 1.4 Collection Item 当前价值与涨跌

```
Collection Item 当前价值 = 当前市场价格 × 数量
单条 Collection Item 涨跌幅 = (当前市场价格 - 周期起点时市场价格) / 周期起点时市场价格 × 100%
```

**说明**：
- 涨跌幅按**单张**价格变化计算。
- `Quantity` 只影响涨跌金额，不影响涨跌百分比。
- 因此同一张卡 Qty 1 和 Qty 3 的涨跌百分比相同，但涨跌金额不同。

### 1.5 Home Most Valuable 涨跌

```
Most Valuable 涨跌 = (当前单卡市场价 - 30D 前单卡市场价) / 30D 前单卡市场价 × 100%
```

**说明**：
- Most Valuable 按**单张**当前市场价排序；`Quantity` 不影响排序。
- `Quantity` 不影响 Most Valuable 的涨跌幅。
- 如需展示涨跌金额，展示单张涨跌金额，不展示总持仓涨跌金额。
- 如果 30 天前无有效价格，涨跌幅展示 `-/-`。

### 1.6 Search 列表涨跌

```
Search 列表涨跌 = (Current Market Price - 30D Previous Market Price) / 30D Previous Market Price × 100%
```

**说明**：Search 列表只展示 30D Change 百分比，不展示涨跌金额（见 §七、`search.md`）。

---

## 二、加载、失败、空状态规则

### 2.1 局部数据加载失败

App 内任一页面中，如果只是某个模块 / 某个区域的数据加载失败，**不使用整页弹窗**，只在该模块空白区域展示局部失败状态。

| 元素 | 内容 |
|---|---|
| 文案 | `No content available` |
| 按钮 | `Refresh` |

**规则**：
- 展示在失败模块原本的数据区域内，不遮挡其他已加载内容。
- 点击 `Refresh` 只重新加载该模块数据。
- 刷新中展示统一 loading 动效；刷新成功后恢复模块内容；刷新失败后继续展示局部失败状态。

**适用场景**：Home Most Valuable / Home Trending Today / Price 图表 / Market Prices / Shop 列表 / Search Cards 列表 / Search Sets 列表 / Collection Portfolio 局部数据 / Collection Wishlist 局部数据 / Review Your Matches 中单个价格或总价。

### 2.2 整页数据加载失败

如果页面核心数据**全部**加载失败，展示全局失败弹窗。

| 元素 | 内容 |
|---|---|
| 标题 | `No content available` |
| 按钮 | `Refresh` |

**规则**：
- 当页面所有核心数据都加载失败时展示弹窗，弹窗不展示多余说明。
- 点击 `Refresh` 重新加载整页数据；刷新成功后关闭弹窗；刷新失败后保留弹窗。
- 用户可通过返回按钮离开页面。

**适用场景**：卡牌详情页基础信息整体加载失败 / Collection 页面核心列表整体加载失败 / Search 页面初始化数据整体加载失败 / Profile 账号信息和基础入口整体加载失败 / Scan Details 整体加载失败。

---

## 三、全局 Loading 动效

所有需要加载的场景使用同一个动态图 / loading 组件，不同页面不得使用不同风格的 loading。

| 场景 | Loading 类型 |
|---|---|
| 首屏加载 | 页面级 loading |
| 模块刷新 | 局部 loading |
| 按钮提交 | 按钮内 loading |
| 列表分页 | 列表底部 loading |

**规则**：
- Loading 超过 10 秒仍无结果时，进入失败状态。
- Loading 不应遮挡底部导航，除非是全屏流程页。

**适用场景**：页面初始化 / 列表加载 / 搜索请求 / 筛选排序刷新 / 图表刷新 / 价格数据刷新 / 扫描识别中 / 添加到 Portfolio / 加入或移除 Wishlist / 保存 Collection Item / 提交客服反馈。

---

## 四、操作失败 Toast

### 4.1 通用失败 Toast

大多数可恢复的操作失败统一使用通用 Toast：

```
Something went wrong. Please try again.
```

**适用场景**：切换文件夹、切换货币、筛选排序等常规操作失败。

> **适用界定**：通用 Toast 适用于大多数可恢复的操作失败，包括切换、保存、添加、移除、删除等；操作失败时不改变数据状态，用户可重新操作。**具体以 §4.2 枚举清单为准，枚举清单优先于字面定义。** 账号删除、退出登录、官网链接打开、提交反馈、游客资产迁移等特殊场景使用专用文案（见 §九确认弹窗流程 + §13.2 场景专用文案）。

### 4.2 Toast 通用规则

- Toast 不需要按钮，自动显示 2–3 秒后消失。
- Toast 不阻塞用户操作，不使用遮罩。
- Toast 固定展示在底部导航上方，不遮挡底部导航。
- 操作失败后，恢复操作前状态。
- 如果当前操作打开了临时弹窗 / 底部弹窗，失败后关闭该临时层并返回上一稳定页面。
- 如果当前操作是表单保存 / 添加 / 提交，失败后停留当前页面并保留用户输入内容，不强制返回，避免用户丢数据。
- 如果是删除、移除等高风险操作失败，不删除数据，停留当前页面并展示 Toast。

**通用 Toast 适用按钮操作**：切换文件夹失败 / 新建文件夹失败 / 编辑文件夹失败 / 删除文件夹失败 / 切换货币失败 / 加入 Portfolio 失败 / 移除 Portfolio 失败 / 加入 Wishlist 失败 / 移除 Wishlist 失败 / 保存 Collection Item 失败 / 分享调起失败。

> **静默例外**：评分 / App Store 跳转失败**不弹 Toast**（评分为可选操作，跳转失败静默处理，留在原页面）。

> **注意**：以下场景使用场景专用失败文案，不使用通用 Toast——详见 §十三统一文案表中的"场景专用失败文案例外"。

---

## 五、全局网络异常 Toast

网络异常统一使用以下专用文案（场景专用，非通用 Toast）：

```
No internet connection. Please check your network and try again.
```

**规则**：
- 无网络时展示该 Toast，不清空页面已加载数据。
- 当前操作失败并恢复操作前状态。
- 用户恢复网络后，可点击 `Refresh` 或重新操作。
- 适用于：扫描识别 / 搜索 / 价格刷新 / 添加 Portfolio / 保存 Collection Item 等所有依赖网络的操作。

**关于离线暂存（v1.0 范围说明）**：部分离线资产暂存（离线保存、Pending sync、Sync failed / Retry）为 v1.0 之后的后续能力，当前版本不支持。无网络时，所有依赖网络的操作按本节处理——操作失败并恢复操作前状态，展示网络异常 Toast；不提供离线本地暂存与自动补传。
> 注：本条按产品最新决策，覆盖源文档《卡牌异常总结》§十一.3「1.0 支持部分离线资产暂存」的表述，以本口径为准。

---

## 六、图片缺失规则

| 场景 | 降级展示 |
|---|---|
| 卡牌图片缺失 | 统一卡牌占位图 |
| Set 封面缺失 | 统一系列占位图 |
| 评级封装图缺失 | 普通卡牌图 |
| 图片加载失败 | 展示占位图，不弹错误 Toast |

图片重试加载不影响页面其他数据展示。

---

## 七、金额与百分比规则

| 规则 | 说明 |
|---|---|
| 默认货币 | USD |
| 切换货币 | 调用汇率接口，所有金额字段跟随换算 |
| 百分比 | 不随货币切换变化，始终按原始市场价格序列计算 |
| 金额精度 | 默认保留 2 位小数，使用千分位 |
| 金额缺失 | 展示 `--` |
| 涨跌幅缺失 | 展示 `-/-` |
| 正向变化 | 展示 `+` |
| 负向变化 | 展示 `-` |
| 汇率换算失败 | 该金额展示 `--`，且不参与当前总资产计算 |
| 资产隐藏 | 用户资产金额被隐藏时，Portfolio 和 Home 中资产金额同步隐藏 |

**百分比不随货币切换变化（涵盖性说明）**：所有涨跌百分比始终按原始市场价格序列计算，不因货币切换或汇率换算而变化。该规则统一覆盖：Home 图表涨跌百分比、Most Valuable 30D Change、Trending Today 涨跌幅、Search 列表 30D Change、Collection 列表 30D Change、Card Detail Market Prices 7d change，以及其他展示涨跌百分比的场景。

---

## 八、登录与账号规则

- 用户的 Portfolio、Wishlist、Collection Item、文件夹、扫描添加记录、货币偏好、金额隐藏偏好均与账号绑定。
- 游客状态下，用户可正常进行 Portfolio、Wishlist、Scan、Search 快捷收藏、Collection Item 编辑等资产相关操作，不强制登录（详见 §十四）。
- 仅"注册 / 登录"入口本身进入账号流程；资产操作不拦截登录。
- 登录成功后刷新当前页面状态。
- 退出登录后，不展示账号资产数据。
- 删除账号需要二次确认。
- 删除账号后，该账号相关数据按隐私规则处理。

---

## 九、确认弹窗规则

以下操作必须二次确认：

- 删除账号
- 删除 Portfolio 文件夹
- Remove from Portfolio
- Remove from Wishlist
- 退出扫描且存在未保存扫描结果

**规则**：
- 二次确认弹窗必须包含取消按钮。
- 取消后不改变数据。
- 确认失败后不改变数据，并按场景展示失败提示：普通删除 / 移除操作使用通用 Toast（§4.1）；删除账号、退出登录等账号级操作使用场景专用失败文案（§13.2）。
- 删除类按钮使用明确动词，例如 `Delete`、`Remove`、`Exit`。

---

## 十、刷新规则

- `Refresh` 只刷新当前失败区域或当前页面。
- 局部失败的 `Refresh` 不刷新整页。
- 整页失败弹窗的 `Refresh` 刷新整页。
- 刷新中展示统一 loading 动效。
- 多次点击 `Refresh` 时需要防重复请求。
- 刷新失败时保留失败状态。

---

## 十一、防重复点击规则

所有会产生数据变化的按钮，请求中不可重复点击。

**规则**：
- 请求中按钮展示 loading 或置灰。
- 请求成功后更新状态。
- 请求失败后恢复原按钮状态。

**适用按钮**：`Collect` / `Collected` / Wishlist 爱心 / `ADD TO MAIN` / `Save changes` / `Delete` / `Remove` / `Submit Feedback` / `Refresh`。

---

## 十二、状态优先级

页面展示状态优先级（从高到低）：

1. 权限阻断状态
2. 整页加载失败
3. 页面加载中
4. 页面空状态
5. 页面正常数据状态
6. 局部模块加载失败
7. Toast 操作反馈

**说明**：
- 权限阻断优先于数据加载。
- 整页失败优先于局部失败。
- 空状态和失败状态必须区分：空状态表示请求成功但无数据；失败状态表示请求失败或内容不可用。
- 局部模块加载失败不是整页状态，不影响页面其他区域展示；它在"页面正常数据状态"内按模块独立展示，不因优先级排序低于正常数据而被隐藏。

---

## 十三、统一文案表

### 13.1 通用文案（全局生效）

| 场景 | 统一文案 |
|---|---|
| 局部内容不可用 | `No content available` |
| 局部刷新按钮 | `Refresh` |
| 整页内容不可用弹窗 | `No content available` |
| 整页刷新按钮 | `Refresh` |
| 通用操作失败 Toast | `Something went wrong. Please try again.` |
| 网络异常 Toast | `No internet connection. Please check your network and try again.` |
| 价格缺失 | `--` |
| 涨跌幅缺失 | `-/-` |
| Wishlist 移除按钮 | `Remove from Wishlist` |
| Portfolio 移除按钮 | `Remove from Portfolio` |
| 扫描结果未保存退出提示 | `Your scan results haven't been saved. If you exit now, they will be lost.` |
| Quantity 为 0 或负数（不允许保存） | `Quantity must be at least 1.` |
| Quantity 非整数（不允许保存） | `Quantity must be a whole number.` |
| 公共数据不可用 Price Tab 标题 | `Price data unavailable` |
| 公共数据不可用 Price Tab 说明 | `This card's public data is no longer available.` |
| 公共数据不可用 Price Tab 按钮 | `Refresh` |

### 13.2 场景专用失败文案例外

以下场景**不使用**通用 Toast，使用专用失败文案。各模块 PRD 应直接引用此处定义，不重复撰写。

| 场景 | 专用失败文案 | 适用边界 |
|---|---|---|
| 删除账号失败 / 退出登录失败 | `Unable to complete this action. Please try again later.` | Account 页 Delete 操作 / Profile 及 Account 页 Log Out 操作失败 |
| 提交反馈失败 | `Unable to submit feedback. Please try again later.` | Customer Support 页 Submit Feedback 操作失败 |
| 游客资产迁移失败 | `Something went wrong. Please try again later.` | 注册成功但后端资产迁移步骤失败（与通用 Toast 文案相近但语义更严重，特指迁移场景） |
| 官网链接打开失败 | `Unable to open this page. Please try again later.` | Profile 页 Terms of Use / Privacy Policy 跳转失败 |
| 网络异常 | `No internet connection. Please check your network and try again.` | 所有依赖网络的操作在无网络时（客户端本地判断） |

**通用 vs 专用适用边界说明**：
- **通用 Toast** 适用于大多数可恢复的操作失败：切换文件夹、切换货币、筛选排序、加入或移除收藏等。这类操作失败后用户可立即重试，无须额外上下文说明。
- **专用文案** 适用于以下情形之一：① 涉及账号级高风险操作（删除账号、退出登录）；② 涉及外部系统（官网链接、邮件、OAuth）；③ 涉及无网络的明确判断；④ 涉及数据迁移不可逆场景。

---

## 十四、游客状态与资产规则

### 14.1 游客身份定义

App 支持游客状态使用。用户未注册 / 未登录时，也可以在 App 内进行主要功能操作，并产生游客资产。

技术实现：App 首次启动且未登录时，系统在后端创建一个 `anonymous_account`（持有 JWT）并关联本地 `device_id`，用于绑定游客资产。（见 api-spec §2.1）

游客资产绑定 anonymous_account 并在服务端备份；客户端本地可缓存游客资产，但服务端 anonymous_account 为游客资产的主数据来源。

**游客资产包括**：Portfolio 文件夹 / Collection Item / Wishlist / 扫描添加记录 / Search 快捷收藏记录 / 货币偏好 / 金额隐藏偏好 / 文件夹排序和默认文件夹设置 / 其他与用户收藏资产相关的资产数据。

### 14.2 游客状态可用功能

游客状态下，用户可以正常使用：浏览 Home / 使用 Search / 使用 Scan / 添加卡牌到 Portfolio / 添加卡牌到 Wishlist / 新建、编辑、删除 Portfolio 文件夹 / 编辑 Collection Item / 查看卡牌详情 / 切换货币 / 隐藏或显示金额 / 其他不强依赖账号的操作。

### 14.3 注册新账号 —— 游客资产迁移

游客注册新账号成功后，系统将当前 anonymous_account 下的游客资产迁移到该新注册账号下。

**迁移范围**：Portfolio 文件夹 / Collection Item / Wishlist / 扫描添加记录 / 文件夹排序 / 默认文件夹 / 货币偏好 / 金额隐藏偏好 / 其他 anonymous_account 下游客资产相关配置。

**迁移成功后**：用户进入登录态，后续所有资产操作均归属该账号；Home、Collection、Wishlist、Search Qty、Collected 状态等页面刷新为新账号资产数据；原游客资产不再作为独立游客资产重复展示。

**迁移失败处理**：
1. 游客资产仍保留在 anonymous_account 下，不删除资产及本地缓存，不得标记为已迁移。
2. 展示专用失败提示（见 §13.2 "游客资产迁移失败"）。
3. 新账号保持登录态；为避免"注册成功 → 看到空资产"，优先保留当前游客资产展示并提示稍后重试同步，迁移成功后再切换为正式账号资产。
4. 用户可稍后重试资产迁移；需在后台保留待迁移状态，避免重复注册。

**迁移成功后需刷新的模块**：Home 当前总资产 / Home 图表 / Home Most Valuable / Collection - Portfolio / Collection - Wishlist / Search 列表 Qty / Search 列表 Collect / Collected 状态 / Search 列表 Wishlist 爱心状态 / Card Detail 收藏状态 / Profile 账号状态 / 文件夹列表 / 默认文件夹状态。

### 14.4 登录已有账号 —— 游客资产不迁移

游客状态下登录已有账号时，**不自动迁移**当前游客资产。

**规则**：登录成功后 App 切换为该账号资产数据；游客资产仍保留在原 anonymous_account 下，不与已有账号资产合并；后续新增 / 编辑 / 删除资产均归属当前登录账号。登录已有账号后，原 anonymous_account 资产仍保留。

**注册 vs 登录的核心区别**：

| 场景 | 游客资产处理 | 登录后展示 |
|---|---|---|
| 游客注册新账号 | 迁移到新账号 | 展示迁移后的新账号资产 |
| 游客登录已有账号 | 不迁移、不合并 | 展示已有账号资产 |

### 14.5 退出登录后处理

- 当前账号资产不删除；本地展示切回游客状态。
- 如果客户端仍持有该 anonymous_account 绑定关系，则退出登录后切回游客状态并展示该 anonymous_account 游客资产；否则展示空游客状态。
- 不允许继续展示刚退出账号的资产数据。

### 14.6 删除账号后处理

- 账号资产按删除账号规则（隐私合规）处理；App 切换为游客状态。
- 不将已删除账号资产回退为游客资产。
- 如果本地存在旧游客资产，按游客身份继续展示；否则展示空游客状态。

---

## 十五、已固化口径（原 PRD 冲突解消）

本节记录原始各模块 PRD 中存在分歧的 5 条口径，以本文件为准，各模块 PRD **不得**保留旧措辞。

### 冲突 1：缺价卡展示与计算口径

**固化结论**：
- 缺少当前市场价的卡牌，价格字段展示 `--`。
- 该卡**不计入** Home 总资产，也**不参与** Most Valuable 排序。
- 这适用于 Collection Item 价格缺失、Market Prices 字段缺失等所有缺价场景。

**依据**：来自 `全局用其他补充事项.md §二`、`home页说明.md §6.3`、`卡牌详情.md §11.6`。

### 冲突 2：Most Valuable 相同单张价值时的排序优先级

**固化结论**：当两张卡单张价值相同时，排序规则依次为：
1. 30 天涨幅较高者优先；
2. 涨幅相同时，最近添加时间较晚者优先；
3. 仍相同时，按卡牌名称 A-Z 升序。

**依据**：来自 `home页说明.md §6.3`、`卡牌异常总结.md`（排序与排名异常）。

### 冲突 3：数据来源口径统一

**固化结论**：
- **数据来源**：以第三方聚合数据为准，App 不自行维护价格数据库；卡牌价格、历史价格序列均来自第三方数据适配层（见 `third-party.md`）。
- **默认排序**：Search / 系列列表等默认排序不再以"本地数据库入库时间"为业务口径，改为使用第三方数据适配层返回的默认排序字段（如 `release_date`、`updated_at`、`market_rank`、`provider_order`）；具体排序字段由接口返回，前端按接口结果展示。
- 原 PRD 中"入库时间倒序""数据库无匹配"等措辞作废。

**依据**：`api-spec.md §4.5`、`third-party.md`。

### 冲突 4：游客资产口径（重要修正）

> ⚠️ **此处修正了原 PRD "仅本地、不跨设备、卸载丢失" 的旧措辞。**

**固化结论（新口径）**：
- 游客资产通过后端 `anonymous_account`（匿名账号）机制同步，与 `device_id` 绑定，存储于后端 D1 数据库。（见 `api-spec.md §2.1`、`api-spec.md §4.5`）
- 游客注册新账号时，通过 `POST /auth/register/verify`（含 `anonymous_id`）或独立迁移端点 `POST /auth/migrate`，将匿名账号资产迁移到正式账号。
- **旧措辞作废**：原 `全局用其他补充事项.md §十四` 中"游客资产仅在当前设备本地可用"、"游客资产不具备跨设备同步能力"、"用户卸载 App 后游客资产可能丢失"，均为**历史旧措辞**，已被后端匿名账号方案覆盖，**不再适用**。
- 游客资产的跨设备同步能力取决于实现阶段对 `device_id` 绑定策略的具体设计，最终以 api-spec 为准。

**依据**：`api-spec.md §2.1`、`§2.3`、`§2.13`。

### 冲突 5：全局文案 / Toast / 空状态 / 失败状态的单一真相源

**固化结论**：全局文案、Toast 文案、空状态文案、失败状态文案，**以本文件 §十三为唯一真相源**。

各模块 PRD（Profile / Home / Collection / Search / Card Detail / Scan）遇到文案定义时：
- 通用场景直接引用 `global-rules.md §十三`，不在模块内重复定义。
- 场景专用文案在 `§13.2 场景专用失败文案例外` 中集中登记，模块 PRD 引用此处。
- 如发现模块 PRD 与本文件不一致，以本文件为准，模块 PRD 需更新。

---

## 十六、统计口径汇总

> 本节集中收纳跨切面的资产统计口径，作为 Home / Collection / Search / Card Detail 等模块的统一引用来源。涉及缺价不计入、Most Valuable 排序等已固化项，仍以 §十五为准，本节不重复其结论。

### 16.1 价格口径与取价

- **价格口径不混用**：Raw / Graded / Sealed 使用不同的价格口径，相互之间不混用。
- **Search Qty**：Search 列表中的 Qty = 当前选中文件夹内该卡所有**有效** Collection Item 的数量总和；同一张卡的多条记录（如 Raw、PSA 10、PSA 9）数量累加。
- **同卡多条不强制合并**：同一张卡的多条 Collection Item 不强制合并，列表分别展示；每条独立取价。

### 16.2 资产变更只影响变更时间点之后（全局原则）

- 所有资产变更只影响变更时间点**之后**的统计，不回写历史。
- 适用于：Quantity 修改、Language / Finish 修改、卡牌跨 Portfolio 移动，以及其他持有信息变更。
- **卡牌跨 Portfolio 移动**：自移动时间点起，原 Portfolio 不再计入该卡、目标 Portfolio 开始计入该卡；原 Portfolio 历史保留，目标 Portfolio 移动前的历史不补算。

### 16.3 资产计入的时间边界

- 资产按变更时间点边界计入：卡牌加入前不计入、删除后不计入。
- 查看长周期图表时，周期前半段只统计当时已存在的资产；卡牌加入前的图表点不计入该卡价值。

### 16.4 周期起点资产为 0

- 周期变化金额从 0 起算。
- 变化百分比展示 `-/-`（避免除以 0）。
- 当前总资产正常展示。

### 16.5 当前总资产为 0

- 当前总资产展示 `$0.00`。
- 图表后续展示 0 / 空状态。
- 变化百分比展示 `-/-`。
- Most Valuable 展示空状态。

### 16.6 精度与四舍五入

- 计算使用原始精度，不以展示值参与计算。
- 多个资产先累加原始值，再统一格式化，末端再四舍五入。
- 金额默认保留 2 位小数。
- 涨跌百分比默认 2 位小数；绝对值小于 0.01% 但不为 0 时展示 `<0.01%`；起始值为 0 时展示 `-/-`，不计算无限大涨幅。

### 16.7 Wishlist 与收藏状态口径

- **Wishlist 不计入资产**：Wishlist 不计入 Home 当前总资产、不计入 Home 图表、不计入 Most Valuable、不影响 Portfolio Qty。
- **Portfolio 与 Wishlist 互斥**：同一张卡不可同时存在于 Portfolio 和 Wishlist；加入 Portfolio 成功时，若 Wishlist 已有该卡则自动从 Wishlist 移除。
- **Collected 状态范围**：Collected 仅代表该卡已存在于「当前选中文件夹」；该卡在其他文件夹时不展示 Collected。
- **Collected 与 Heart 互斥**：Collected 与 Heart（Wishlist）状态互斥，Collected 态下不可同时为 Hearted 态。

---

## 十七、价格来源、唯一性与异常价格口径

### 17.1 价格来源与可信度

- 资产估值优先使用成交价 / Sold Listings。
- 仅有挂牌价、无成交价时，标记为低可信价格。
- Home 当前总资产不直接使用单个高挂牌价，避免资产虚高。
- Market Price 优先基于成交价格计算，不直接使用单个在售挂牌价作为资产估值。
- Shop 可展示在售商品，但不等同于资产估值价格。

### 17.2 卡牌唯一性与取价字段

- **唯一性**：卡牌唯一性由 Set、编号、Language、Finish、Variant 共同决定，不能只按名称判断。
- **状态判断**：Search / Scan / Collection / Wishlist 的 Collected / Heart / Qty 状态均以 `card_id` / `product_id` 为准；同名不同 Variant 状态独立。
- **取价字段**：Language、Finish / Variant 是价格取值字段；不同取值不合并估值。
- **修改后取价**：用户修改 Language / Finish 后，从保存时间点起按新取值计价；若该取值无价，则当前价值展示 `--`。

### 17.3 负价格 / 0 价格

- 价格为负数视为异常，不展示、不计入资产。
- 价格为 0 统一按缺失处理，展示 `--`（采用文档 1.0 建议，不展示 `$0.00`）。

### 17.4 刷新与延迟口径

- 资产变更（保存 / 删除 / 移动）成功后，自动刷新相关模块：Home 当前总资产、Home 图表、Most Valuable、Collection / Portfolio 列表、Search Qty / Collected、Card Detail。
- 价格数据可能延迟，页面展示最新可用价；Home 不展示价格更新时间。
- 若价格缺失，则加入成功但资产金额不增加。
- 多端并发：同一 Collection Item 被多端同时编辑时，采用「最后保存覆盖」（last-write-wins），以服务端最终落库结果为准；v1.0 不提供冲突提示（后续版本再考虑）。

---

## 十八、时区口径

> 本节为正式口径（非参考）。

- 所有资产变更时间统一保存 UTC timestamp。
- 7D / 30D / 1M 等统计周期统一按用户「固定统计时区」计算，不随设备当前时区变化。
- 固定统计时区默认为注册 / 首次进入 App 时的设备时区；用户跨地区或设备时区变化，不会自动改变图表统计口径。
- 后续若支持手动修改统计时区，仅影响修改之后的图表展示与周期边界计算，历史资产变更的 UTC 时间不变。

---

## 十九、公共卡牌后台变更口径

> 公共卡牌因数据问题被后台变更（Delisted / Merged / Unavailable）时的统一处理口径。后台变更**不直接删除**用户已收藏的 Collection Item。

### 19.1 Delisted（下架）

- 卡牌从 Search 公共列表下架，但用户 Portfolio / Wishlist 中已有记录继续展示。
- 价格仍可用则继续参与统计；价格不可用则展示 `--`，且不计入 Home 当前总资产和 Most Valuable。

### 19.2 Merged（合并）

- 用户已收藏的 Collection Item 自动关联到新的 canonical `card_id`。
- 用户填写的持有信息（Quantity / Portfolio / Grader / Condition / Grade / Language / Finish / Purchase Price / Notes 等）保持不变。
- 后续价格与基础信息按新的 canonical `card_id` 取。

### 19.3 Unavailable（不可用）

- 不删除记录，页面展示最近一次可用的基础信息缓存。
- 当前价格展示 `--`，涨跌幅展示 `-/-`，从异常开始不计入 Home 当前总资产和 Most Valuable。
- 用户仍可编辑或移除该 Collection Item。
- Price Tab 不按普通加载失败处理，使用专用文案（见 §13.1）：`Price data unavailable` / `This card's public data is no longer available.` / `Refresh`。

### 19.4 历史统计

- 变为 Unavailable 之前已生成的历史资产快照保留，Home 历史图表中该卡此前的历史价值可继续展示。
- Unavailable 之后，该卡不再参与新的当前总资产计算，之后的图表点不计入该卡价值。
- 若后续该卡恢复 active 或 merged 到 canonical `card_id`，则从恢复 / 合并时间点起重新参与资产统计。
