# TCG Card App v1.1 产品需求文档

> 文档类型：v1.1 版本差异文档  
> 文档状态：修订稿  
> 修订日期：2026-08-10  
> 适用对象：产品、客户端开发、测试

## 0. 文档范围

本文只详细描述 v1.1 新增或修改的内容：

- Subscription Page
- Subscription Success
- Subscription Paywall Modal
- Apple 支付购买流程
- Restore Purchase
- Premium 权益状态
- Premium 入口
- 首次安装 ATT 时机与 Singular 归因初始化
- Scan 免费额度
- Scan Queue Waiting 状态
- Portfolio Folder 免费限制
- Home Performance
- Card Detail Performance
- Purchase Price 缺失状态
- Performance 异常状态
- Profile 订阅状态

**除本章明确修改的内容外，其余页面结构、字段、业务流程和异常处理保持 v1.0 规则不变。**

本文不重复描述以下 v1.0 已有能力：

- Scan 基础识别、Review、Matched、Failed、No Match Found 和批量添加流程
- Portfolio / Wishlist 基础资产流程
- 游客资产与账号迁移流程
- Collection Item 字段与编辑流程
- Search、Collection、Card Detail 基础页面流程
- 删除账号等账号能力

## 0.1 需求边界

- 不修改 HTML Prototype。
- 不新增 v1.2 功能。
- 不修改已确定的 SKU、美区价格配置目标和四项 Premium Benefits。
- 当前评论中的确认规则覆盖旧 PRD 和旧任务草稿中的冲突内容。
- 本轮不增加或修改 Sports Card 产品需求及 UI。

### 0.1.1 Apple Subscription / Premium 上位规则优先级

涉及 Premium ownership、Premium 真值、StoreKit、服务端 entitlement、App Store Server Notifications、Apple Server API、Purchase / Restore 即时解锁、订阅生命周期状态同步与客户端 / 服务端状态冲突处理时，统一以《Apple Subscription & Premium 权益统一方案》为上位规则。

如本 PRD 旧文字与该统一方案冲突，以统一方案为准，并删除或改写旧冲突描述。本文只在 App 侧说明页面、交互、权限入口与客户端产品结果，不把 Premium 改写为 App UID / App 账号权益。

## 0.2 v1.1 页面交互定义规范

所有 v1.1 新增或修改页面的关键控件，均按以下粒度定义：

```text
看到什么 → 什么状态可操作 → 点击什么 → 执行什么 → 跳转哪里/打开什么 → 成功后什么 → 失败后什么 → 返回后保留什么
```

页面级交互优先使用下表结构。某列无业务含义时可写 `-`，但 v1.1 新增或修改的关键控件不得省略。

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| v1.1 关键控件 | 页面章节定义 | 页面章节定义 | 明确操作、参数、状态更新 | 明确页面、Tab、Modal、Sheet、网页或当前容器 | 明确成功后页面与状态 | 明确失败、取消、Pending 后页面与状态 | 明确保留的 Tab、Range、Tooltip、Queue、表单、来源参数或 `blocked_action` |

禁止使用未指定目标、容器、操作参数或恢复状态的泛化描述。任何 v1.1 关键控件必须明确写出具体页面、Tab、Modal、Sheet、网页容器、成功状态、失败状态和返回后保留内容。

如果 v1.0 已完整定义某个未修改控件，可写“沿用 v1.0 XX 章节”；如果 v1.1 改变了该控件结果，必须在本 PRD 重写差异。

## 0.3 全局异步请求、Loading 与 Timeout 规则

本节为 v1.1 全 App 统一规则，优先于旧文档中其他未明确的 Loading / Retry 描述。除本 PRD 明确列为例外的系统流程外，所有用户可感知、App 需要等待结果的业务请求，单次用户操作最大等待时间统一为 15 秒。

### 0.3.1 统一 15 秒 Deadline

```text
Request Start
→ Loading
→ 最长等待 15 秒
```

15 秒内：Success 正常处理；明确 Failure 立即失败，不继续等待；到 15 秒仍未得到有效结果则为 Timeout。

Timeout 后必须结束当前 Loading，当前请求结束，不继续等待该请求，不在同一次操作中继续自动请求，并立即进入对应失败状态或错误反馈。

不得出现 Loading 无限转圈、15 秒后仍保持不可操作、Timeout 后后台继续自动重试并再次覆盖页面、Timeout 后迟到旧请求覆盖新页面状态。

如果某功能存在内部自动重试机制，所有自动重试必须共享当前操作的 15 秒总 Deadline，不得按每次重试重新获得 15 秒。例如 StoreKit Product Loading 原有 1 秒 / 3 秒 / 8 秒自动重试可以继续在同一个 15 秒窗口内执行；只要当前操作总时间达到 15 秒，必须停止后续自动重试、结束 Loading 并报错。用户之后主动再次执行原操作，视为新的请求周期，重新获得新的 15 秒 Deadline。

### 0.3.2 适用场景

至少包括 Home 数据请求、Search 请求、Collection 列表、Folder 数据、Card Detail、Price History、Home Performance、Card Detail Performance、Performance Range 切换、货币切换相关数据、Collection Item 保存 / 更新、Folder 创建 / 修改、Scan 上传 / 识别请求、Scan Quota 服务端请求、StoreKit Product 读取、StoreKit entitlement 主动刷新、Restore Purchases、登录 / 注册等 App 业务接口，以及其他客户端需要等待服务端 / StoreKit 返回结果的业务请求。

如果 v1.0 某请求已有更短超时，可以继续使用更短时间；但任何用户可感知业务请求不得超过 15 秒。

### 0.3.3 不适用 15 秒强制终止的系统流程

| 系统流程 | 规则 |
| --- | --- |
| Apple 系统 Purchase Sheet | 用户已经进入 Apple 系统购买确认界面后，不使用 App 的 15 秒请求超时强制结束 Apple 购买；Face ID、密码输入、系统购买结果、Ask to Buy / Pending 均按 Apple 最终返回处理 |
| Purchase Pending | Pending 不是请求 Timeout；Apple 已经返回 Pending 后允许等待后续 Transaction Update，不得在 15 秒后自动变 Failed |
| ATT 系统弹窗 | 用户正在系统 ATT 弹窗上做选择时，不使用 15 秒规则强制关闭 |
| 系统浏览器 | Terms / Privacy 跳转浏览器后，不适用 15 秒规则 |

### 0.3.4 Timeout 统一结果

通用请求 Timeout 使用轻量 Toast：

```text
Request timed out. Please try again.
```

该 Toast 自动消失，不增加独立 Retry 大按钮；当前页面恢复可操作，用户之后可重新执行原动作。

如果当前功能已经有明确专属 Failed UI，优先使用专属 Failed UI：

| 场景 | Timeout 结果 |
| --- | --- |
| Restore Timeout | 使用 Restore Failed Alert，不使用通用 Timeout Toast |
| Scan 识别 Timeout | 使用 Scan Failed 状态，并按 Scan Quota 规则返还预占额度 |
| Performance 数据 Timeout | 进入 Network / Service Error，不生成虚假 No Data |

除 v1.1 本 PRD 明确覆盖的特殊错误 UI 外，网络错误、通用 Failure、Toast、页面 Error、Loading 样式继续沿用 v1.0 全局异常规范。v1.1 专属规则优先级更高，例如 Restore Failed 必须使用 Restore Failed Alert；Performance No Data 只用于真实无数据；Scan Waiting 不是 Loading / Error，不能因为停留超过 15 秒变 Failed。

### 0.3.5 迟到响应与上下文防覆盖

所有异步请求都必须支持“当前请求是否仍然有效”的判断。请求达到 15 秒 Timeout 后，该请求实例标记为 Expired。如果原请求之后才返回，不得直接更新当前 UI。

迟到响应不得覆盖用户后来选择的新 Range、新 Folder、新 Currency，不得重新打开已经关闭的 Modal，不得恢复已经失效的 `blocked_action`，不得把已经 Failed 的 Scan 重新插入 Queue，不得重复扣 Scan Quota，不得创建重复 Folder，不得重复保存 Collection Item。

任何请求返回结果前，必须检查当前 UI 上下文仍与发起请求时一致。至少包括 page、`card_id`、`collection_item_id`、`folder_id`、`selected_range`、currency、account user、request token。

示例：

```text
7D → 很快切 1M
→ 7D 晚返回不得覆盖 1M 数据

Folder A → Folder B
→ Folder A 晚返回不得覆盖 Folder B

USD → EUR
→ USD 请求晚返回不得覆盖 EUR
```

技术上可通过 `request_id`、`request_token`、`context_version`、`idempotency_key` 等方式实现。本 PRD 只要求产品结果正确，不强制具体技术方案。

### 0.3.6 写操作 Timeout 与幂等

对于 Create Folder、Add Collection Item、Scan Submit、Scan Quota 预占 / 结算，以及其他可能产生重复数据的 Create 操作，即使客户端 15 秒 Timeout，也必须避免用户重新点击后产生重复记录。

如果第一次请求实际上已经被服务端处理，第二次相同操作不得重复创建、重复扣额度或重复记录同一业务动作。Scan 继续使用已确认的唯一 Scan Request ID 和幂等规则。其他重要 Create 操作的技术方案由开发决定。

### 0.3.7 Unknown 权益状态下的主动操作

Unknown 不能直接等于 Free，也不能直接等于 Premium。用户在 Unknown 状态点击依赖 Premium 判断的功能时，先发起一次 entitlement Refresh，最长 15 秒。

适用示例包括 Home Performance、Card Detail Performance、普通历史图表 1Y、Add Folder 达到 Free 限制场景，以及 Scan 需要判断 Premium / Free 额度的场景。

| Entitlement Refresh 结果 | 后续处理 |
| --- | --- |
| Premium | 执行 Premium 逻辑 |
| Free | 执行 Free / Paywall 逻辑 |
| 15 秒 Timeout / Refresh Failed 且仍无法确认 | 保持当前页面；不自动当 Free 弹 Paywall；不自动当 Premium 放行；显示请求失败 / Timeout 反馈 |

Scan 场景不得因为权益 Unknown 而错误消费 Free Quota。

### 0.3.8 v1.1 图表时间范围统一规则

v1.1 起，所有支持时间范围切换的图表统一使用以下 Chart Range Selector：

```text
1D
7D
15D
1M
3M
1Y
```

顺序固定为 1D、7D、15D、1M、3M、1Y，默认 Range 统一为 1M。

该规则覆盖 v1.0 中原有的 1D / 7D / 1M / 6M / 12M / MAX 等旧 Chart Range 定义；v1.1 的 1D / 7D / 1M 重新按本节顺序、默认值和权限规则定义。

至少适用于：

- Home Overview 原有 Portfolio Chart
- Home Performance
- Card Detail Price History / Market Price Chart
- Card Detail Performance

本规则只修改 Chart Range Selector，不影响非图表时间范围选择器的比较周期，例如 Trending Today 的 24h Change、Search / Collection 的 30D Change、Card Detail Market Prices 的 7D Change、Today、Daily Change 或其他涨跌比较周期。

## 0.4 v1.1 核心规则速查

本节只汇总正文核心规则，便于产品、开发、测试快速查阅；具体实现与异常以对应正文章节为准。

| 功能 | Free | Premium | 订阅触发方式 | 成功后 | 核心异常 / 限制 |
| --- | --- | --- | --- | --- | --- |
| Premium ownership / 真值 | 未能证明存在有效 Apple-verified entitlement 时为 Free 或 Unknown | Apple Purchase / transaction / originalTransactionId 对应的 Apple 购买链路存在有效 Apple-verified entitlement 时为 Premium | - | Purchase / Restore 经 StoreKit verified 后客户端立即解锁，不等待 Server Notification 或 Admin 订单出现 | Apple 是最终权威数据源；StoreKit 是客户端即时验证通道，App Store Server Notifications V2 / Apple Server API 是服务端生命周期维护与校正通道；Premium 不属于 App UID，UID 只用于交易和业务关联；服务端不可用不得直接等于 Free |
| 图表 Range | 支持时间范围切换的图表统一为 1D / 7D / 15D / 1M / 3M / 1Y，默认 1M | 同 Free | - | - | 覆盖 v1.0 旧 Chart Range；不影响 24h / 7D / 30D Change 等比较周期 |
| Home Performance | 整体 Locked | 1D / 7D / 15D / 1M / 3M / 1Y，默认 1M | Unlock / 锁定区域 → Functional Paywall | Purchase：`Premium unlocked`；Restore：`Premium restored`；加载 Home Performance | Performance 整体属于 Premium，不做 Range 二次锁定 |
| Card Detail Performance | 整体 Locked | 1D / 7D / 15D / 1M / 3M / 1Y，默认 1M | Unlock / 锁定区域 → Functional Paywall | 返回当前 Card Detail Performance 并加载 | Scope 为当前 Collection Item，不聚合同卡其他 Item |
| Extended Price History | Home Overview Portfolio Chart 与 Card Detail Price History 可看 1D / 7D / 15D / 1M / 3M；1Y Locked | 1D / 7D / 15D / 1M / 3M / 1Y | 普通历史图表点击 1Y → Functional Paywall | 自动回到来源图表，选中并加载 1Y | 不适用于 v1.1 Performance；Performance 整体属于 Premium，不单独锁 1Y |
| Scan | 终身 10 次；账号用户多设备共享 Quota | Unlimited scans | quota=0 Capture / Gallery → Functional Paywall；Waiting Card → Functional Paywall；Scan Pro Card → Full Subscription Page | Waiting 已存在时自动 Waiting → Processing；quota=0 且图片未入 Queue 时仅返回 Scan，用户重新操作 | Waiting 不扣 Quota；Waiting 计入 Queue 10 张上限；服务端 Quota 为最终真值 |
| Portfolio Folder | 最多 2 个，包含默认 Folder | Unlimited Folders | Add Folder 达上限 → Functional Paywall | 自动打开 v1.0 Create Folder Modal | Premium 到期不删除已有 Folder；Free 并发创建不得突破 2 个 |
| Full Subscription Page | 冷启动 Free、顶部 Premium 入口、Profile Banner、Scan Pro Card | Premium 不展示升级入口 | 进入完整 Subscription Page | Purchase Success → Subscription Success；Restore Success → Source Page + `Premium restored` | Purchase Success 的正常出口为 Subscription Success 的 `Start Exploring` |
| Functional Paywall | Performance 锁定、普通历史图表 1Y、Scan 卡点、Folder 上限 | - | 功能卡点打开 Paywall | Purchase：`Premium unlocked`；Restore：`Premium restored`；存在可执行且仍有效的 `blocked_action` 时自动执行，否则按来源场景恢复页面状态 | 未获得 Premium 时统一不执行 `blocked_action`；目标失效时不强制恢复旧操作 |
| Restore | 可触发 | 可触发 | Subscription Page / Paywall / Profile 的 Restore Purchases | Success：`Premium restored`；Not Found：`No subscription found`；Failed / Timeout：Restore failed Alert | Restore Blocking Loading 最长 15 秒；Not Found 按最新 verified entitlements 刷新为 Free；Failed / Timeout 保持原权益 |
| Global Request | 适用 | 适用 | 用户可感知业务请求 | Success 正常处理 | 最大 15 秒；Timeout 结束 Loading；不继续本轮请求；迟到请求不得覆盖新状态 |

# 1. Version Overview

## 1.1 v1.1 目标

v1.1 新增 Premium Subscription System 和 Performance Feature，并在 v1.0 基础页面中增加必要的权限入口、限制状态、Apple 支付、Restore 和异常处理。

## 1.2 v1.1 新增范围

以下 Performance 内容全部为 v1.1 新增，不是对 v1.0 已有收益功能的优化：

- Home Performance
- Card Detail Performance
- Performance Tooltip
- Performance 时间范围
- Performance 锁定态
- Purchase Price 缺失状态
- Empty Portfolio 状态
- Partial Purchase Price Missing 状态
- No Purchase Price 状态

## 1.3 v1.0 字段沿用说明

以下 Collection Item 字段均为 v1.0 已有字段，不属于 v1.1 新增：

- Quantity
- Grader
- Condition
- Grade
- Language
- Finish
- Purchase Price
- Notes
- Total

Collection Item 字段与编辑流程沿用 v1.0。Purchase Price 为已有非必填字段，v1.1 仅新增该字段对 Performance 计算及异常状态的影响规则。

## 1.4 v1.1 Premium 能力

- Apple 支付购买与结果处理
- Restore Purchase
- Home Performance
- Card Detail Performance
- Extended Price History
- Unlimited Card Scanning
- Unlimited Portfolio Folders

# 2. 用户状态模型

本版本采用 Apple-verified entitlement 状态模型。用户身份分为游客和账号用户。账号用户支持同一账号在多个设备登录，并同步现有账号数据。

Premium 不属于 App UID。当前设备必须能够证明当前 Apple 购买上下文存在有效 Apple entitlement，不能仅凭 UID 从其他设备继承 Premium。

客户端 StoreKit 和服务端 Apple 生命周期状态都是 Apple 权威数据的不同验证通道。StoreKit 负责客户端即时验证；服务端负责 App Store Server Notifications V2、Apple Server API、订单与订阅生命周期维护及状态校正。

```text
Apple-verified entitlement state
├─ 客户端 StoreKit verified transaction / current entitlements
└─ 服务端 Apple verified lifecycle state

存在有效 Premium entitlement → Premium
不存在有效 Premium entitlement → Free
暂时无法确认 → Unknown / Cache / Timeout 兜底
```

用户身份、App 账号数据和 Premium 权益状态是独立维度，不互相替代。

## 2.1 用户身份

- 游客
- 账号用户

账号用户表示用户已登录 App 账号。允许同一个账号用户在多个设备同时或先后登录，例如设备 A 为账号用户 A、设备 B 也为账号用户 A，这是正常支持的使用场景。

游客不提供账号级跨设备同步能力。不同设备产生的游客身份互相独立，例如设备 A 的游客、设备 B 的游客不要求互通。

## 2.2 权益状态

- Free
- Premium

## 2.3 状态组合

| 用户身份 | 权益状态 | 说明 |
| --- | --- | --- |
| 游客 | Free | 未登录，受 Premium 限制 |
| 游客 | Premium | 未登录，当前 Apple 购买上下文存在有效 Premium entitlement |
| 账号用户 | Free | 已登录，受 Premium 限制 |
| 账号用户 | Premium | 已登录，当前 Apple 购买上下文存在有效 Premium entitlement |

## 2.4 权限判断原则

1. 所有订阅限制和 Premium 功能权限只判断权益状态，不判断用户身份。
2. 游客和账号用户均可购买和 Restore。
3. Free 状态用户显示订阅入口并受到 Premium 限制。
4. Premium 状态用户解锁 Premium 功能并隐藏升级入口。
5. Restore 对所有用户身份和权益状态可见。
6. 用户身份不影响 Paywall、Folder 数量和 Performance 权限判断；Scan 免费额度归属按账号用户或游客身份区分。
7. 用户身份只继续影响 v1.0 已有账号、游客资产、Scan 免费额度归属和迁移流程。
8. 游客不等于 Free，账号用户不等于 Premium。
9. 游客与账号用户均可直接购买 Premium，不要求登录、注册、创建账号或迁移 Premium。
10. 同一账号用户是否在其他设备为 Premium，不作为当前设备 Premium 判断条件。
11. 切换 App 账号不改变当前设备已验证的 Apple entitlement。
12. Premium 权限来自 Apple-verified entitlement state。
13. 客户端 StoreKit verified result 用于客户端即时判断和 Purchase / Restore 后即时解锁。
14. 服务端 Apple verified lifecycle state 用于后续自动续订、Grace Period、Billing Retry、Billing Recovery、Expired、Refund、Revoked 等生命周期状态维护与校正。
15. 服务端状态不能仅凭 UID 向一个没有当前 Apple 购买链路证明的设备授予 Premium。
16. 服务端不可用不得直接把已确认 Premium 用户降级为 Free；客户端应按当前 StoreKit verified result、最近一次有效本地 entitlement cache，以及 Unknown / Timeout 兜底规则处理。

## 2.5 Apple entitlement 与 App 账号

Premium ownership 不属于 App 账号。App 账号只用于 App 账号数据，例如：

- Portfolio 数据
- Wishlist 数据
- 用户账号数据
- 账号用户的 Scan 免费额度
- 订单用户唯一标识关联
- 后台统计
- 埋点用户识别

App 账号不承担 Premium ownership。禁止增加以下规则或字段：

- 一个 Apple 订阅只能绑定一个 App 账号
- `purchase_owner`
- `originalTransactionId → App account owner`
- 账号间订阅所有权迁移
- `order.user_id = premium_owner`；本版本明确为订单用户唯一标识不等于 Premium owner

PRD 和实现不得直接读取或比较 Apple ID 字符串。产品统一称为 Apple-verified entitlement。Apple 可验证交易 / entitlement 包括：

| 通道 | Apple 可验证数据 |
| --- | --- |
| 客户端 | StoreKit verified transaction；StoreKit current entitlements |
| 服务端 | App Store Server Notifications V2；Apple Server API；Apple verified transaction / renewal information |

UID 与 Apple transaction 可以建立业务关联，用于后台查询、订单统计、用户行为关联、客服排查、历史订单和通知补关联，但不得形成 `originalTransactionId → App account owner` 或 `UID → Premium owner` 关系。

统一数据归属如下：

| 数据维度 | 归属与跨设备规则 |
| --- | --- |
| App 账号数据 | 账号用户可跨设备同步，包括 Portfolio、Wishlist、用户资料、账号用户 Scan 免费额度和其他已有账号数据 |
| 游客数据 | 不做账号级跨设备同步；不同设备游客的 Portfolio、Wishlist、游客 Scan 额度和本地数据不要求互通 |
| Premium | 不属于 App 账号；当前设备必须能证明当前 Apple 购买上下文存在有效 Apple entitlement，且不得仅凭 App UID 在其他设备的 Premium 状态获得 Premium |

## 2.6 App 账号切换规则

只要当前 Apple 购买上下文仍存在有效 entitlement，App 账号切换不改变 Premium：

```text
游客 + Premium
→ 登录账号用户 A
→ 账号用户 + Premium
→ Logout
→ 游客 + Premium
→ 登录账号用户 B
→ 账号用户 + Premium
```

登录、注册和 Logout 本身均不得增加、取消、迁移或重新绑定 Premium。Logout 只切换用户身份和用户数据上下文，不清除有效 StoreKit entitlement。

如果当前 entitlement 为 Free：

```text
游客 + Free
→ 登录任意账号用户
→ 账号用户 + Free
```

即使该账号用户曾在其他 Apple 购买环境或设备购买 Premium，也不能仅凭 App 账号登录恢复 Premium。App 账号可跨设备，Premium 不跟 App 账号跨 Apple 购买上下文继承。

## 2.7 游客购买与注册

游客可从 Subscription Page 或 Paywall 直接购买。verified transaction 返回后立即成为游客 + Premium。

游客后续注册或登录时，只按 v1.0 规则迁移或切换用户资产数据；Premium 继续根据当前 Apple entitlement 判断，不执行游客 Premium → 账号用户 Premium 迁移。

游客注册成为新的账号用户时，游客已使用扫描次数继承到新注册账号。例如游客已使用 4 次、剩余 6 次，注册账号用户 A 后，账号用户 A 已使用 4 次、剩余 6 次。之后账号用户 A 在其他设备登录时仍共享已使用 4 次、剩余 6 次，不重新获得 10 次。

游客登录已有账号时，不合并游客扫描额度，切换到该账号用户自身已有的扫描额度。游客本地资产迁移规则继续沿用 v1.0 已确认规则，本轮不重新定义其他游客资产逻辑。

## 2.8 跨设备与 Apple 购买环境

App 登录账号支持多设备登录，但 Premium 权益不随 App 账号跨 Apple 购买上下文同步。当前设备必须先通过 StoreKit / Restore 获得有效 Apple entitlement，或者当前设备已经持有此前由 StoreKit verified 得到的、可证明属于同一 Apple 购买链路的可靠本地验证上下文。服务端 Apple lifecycle state 只能在已经确认同一 Apple 购买链路的基础上进行生命周期校正，不能单独通过 App UID 或后台订单记录为当前设备建立 Premium 资格。

设备 B Restore Success 的前提，是设备 B 当前 StoreKit / Apple 购买上下文本身能够恢复出有效 Apple entitlement；App UID 不参与 Restore 资格判断。

v1.1 不限制同一账号用户登录或同时使用的设备数量。本版本不新增：

- 设备数量上限
- 设备绑定
- Device List / Device Management
- 达到设备上限提示
- 自动踢出旧设备
- 手动解绑设备

同一账号用户可以在多个设备登录并同步现有账号数据。Premium 不得因为 App 账号在其他设备为 Premium 而直接授予当前设备 Premium。

```text
设备 A：
当前 Apple 购买上下文有有效 entitlement
→ Premium

设备 B：
即使登录与设备 A 相同 App UID
但当前 Apple 购买上下文无法验证有效 entitlement
→ 不得仅凭 UID 自动 Premium
```

设备 B Restore：

```text
设备 B
→ Restore Purchases
→ StoreKit / Apple 当前购买上下文验证
├─ 有有效 entitlement → Premium
└─ 无有效 entitlement → Not Found / Free
```

如果设备 A 与设备 B 登录同一个账号用户，且两台设备各自都通过 StoreKit 验证到同一个有效 Apple entitlement，则两个设备均为 Premium。这不属于 App 账号继承 Premium，原因是设备 B 自己验证到了 Apple entitlement，不是因为设备 A 与设备 B 登录了同一个 App UID。

设备 B 需要恢复购买时，用户使用 Restore Purchases。不得因为同一账号用户在设备 A 曾为 Premium 而直接授予设备 B Premium。

| 场景 | 当前 App 账号 | 当前设备 Apple entitlement | Premium 结果 |
| --- | --- | --- | --- |
| 设备 A | 账号用户 A | 有效 | Premium |
| 设备 B | 账号用户 A | 有效 | Premium |
| 设备 C | 账号用户 A | 无有效权益 | Free |
| 设备 A | 游客 | 有效 | Premium |
| 设备 B | 另一个游客身份 | 有效 | Premium |
| 设备 B | 另一个游客身份 | 无有效权益 | Free |

同一账号用户是否在其他设备为 Premium，不作为当前设备 Premium 判断条件。

## 2.9 entitlement 生命周期映射

客户端最终业务权限为 Free 或 Premium；Apple 生命周期状态单独维护：

| Apple 生命周期状态 | v1.1 权限结果 |
| --- | --- |
| ACTIVE | Premium |
| TRIAL / Trial Active | Premium |
| GRACE_PERIOD | Premium |
| BILLING_RETRY | Free |
| EXPIRED | Free |
| REFUNDED / REVOKED | 重新计算全部 Apple-verified entitlements；仍有其他有效 entitlement 则 Premium，否则 Free |
| 有效 Lifetime | Premium |
BILLING_RECOVERY Success → Premium

`Auto Renew = No` 不等于 Free。用户关闭自动续订后，在 `expiration_date` 之前仍保持 Premium。

## 2.10 内部权益加载状态

客户端内部权益加载状态为：

- Unknown
- Free
- Premium

Unknown 只表示当前 Apple-verified entitlement state 尚未确定，不是最终权益类型。该状态不得仅使用单一 `isPremium` 布尔值完整表达。客户端 StoreKit verified result 用于客户端即时判断；服务端 Apple verified lifecycle state 用于生命周期状态维护与校正；本地缓存仅用于启动加速、StoreKit 或服务端暂时不可用时的临时兜底。

## 2.11 本地权益缓存

本地保存最近一次已验证的权益数据，至少包含：

- `entitlement_status`
- `product_id`
- `product_type`
- `transaction_id`
- `original_transaction_id`
- `expiration_date`
- `last_verified_at`
- `is_lifetime`

`original_transaction_id` 用于识别当前设备此前已经验证过的 Apple 购买链路，并与服务端 lifecycle state 做同链路校正。不得把 `original_transaction_id` 解释为 App UID ownership，也不得形成 `UID → original_transaction_id → Premium owner`。

缓存只保存已验证结果。Purchase、Restore 成功或 Transaction 状态变化后，必须根据全部 current entitlements 重新计算权益并更新本地缓存。

## 2.12 启动与刷新规则

1. 启动时读取本地最近一次已验证权益，同时通过 StoreKit 刷新当前权益，并在服务端 Apple lifecycle state 可用且满足同购买链路校正条件时与 Apple 最新状态收敛。
2. StoreKit 刷新成功时，以验证结果更新本地缓存并刷新 UI；服务端存在更晚且可靠的 Apple 生命周期状态时，只有当前设备已经通过 StoreKit verified 获得该 Apple 购买链路，或当前设备本地 cache 已经保存此前 verified 的同一 `original_transaction_id`，才可按第 0.1.1 节上位规则进行生命周期校正。
3. StoreKit 刷新失败且本地存在仍有效的 Premium 记录时，临时保持 Premium。
4. StoreKit 刷新失败且本地记录为 Free 时，临时保持 Free，并继续后台刷新。
5. StoreKit 刷新失败且本地无记录时，进入 Unknown；进入 Home并继续后台刷新，不自动展示冷启动 Subscription Page。
6. 后续确认 Premium 时立即解锁 Premium 功能。
7. 后续确认 Free 时更新订阅入口和锁定态，但不得在用户使用过程中突然弹出完整 Subscription Page。
8. Purchase 或 Restore 成功后立即更新本地权益。
9. Transaction 状态变化后重新计算并更新本地权益。
10. 服务端不可用或暂无订单记录不得直接等于 Free。

服务端 lifecycle correction 只能用于当前设备已知的同一 Apple 购买链路。适用场景包括 Expired、Refund、Revoked、Billing Retry、Billing Recovery、Grace Period、Renewal 等生命周期校正。不得出现服务端因 `UID 100 = Premium`，而当前设备没有任何已验证 Apple purchase chain 时直接获得 Premium。

自动续订产品的 `expiration_date` 未过期时，本地 Premium 可作为临时兜底；已过期且 StoreKit 无法刷新时进入 Unknown，不允许无限期保持 Premium。已验证的 Lifetime 本地记录可临时保持 Premium，StoreKit 恢复后仍需重新验证。

### 2.12.1 Premium 使用过程中变为 Free

当 Apple-verified entitlement state 刷新确认用户从 Premium 变为 Free，例如订阅到期、Refund 或 Revoked：

1. 必须重新计算全部 Apple-verified entitlements；如果仍存在其他有效 Premium entitlement，则保持 Premium。
2. 只有无任何有效 Premium entitlement 时，才切换为 Free。
3. 不强制跳 Home。
4. 不自动弹完整 Subscription Page。
5. 不自动弹 Paywall。
6. 当前页面、当前 Card、当前 Tab、时间范围和滚动位置尽量保持。

当前处于 Premium 功能页面时：

- Home Performance 刷新为 Free 锁定态。
- Card Detail Performance 刷新为 Free 锁定态。
- 用户后续点击锁定区域或 Unlock CTA 时，按对应功能卡点规则打开 Paywall。

Scan：

- Premium 变 Free 后，恢复当前用户身份原有剩余 Free Scan Quota。
- Premium 期间发生的扫描不得消耗 Free Scan Quota。

Folder：

- Premium 变 Free 后不删除已有 Folder。
- Folder 总数超过 Free 上限时，仍可查看、切换、编辑、删除已有 Folder。
- Folder 总数超过或等于 Free 上限时禁止新增。
- 当 Folder 总数重新低于 Free 上限时，Free 可再次创建直到达到上限。

## 2.13 即时解锁与后端关系

Apple Purchase 返回 verified transaction 后，不等待 App Store Server Notification 或 Admin 订单出现：

```text
Apple Purchase
→ Transaction verified
→ 根据 current entitlements 更新本地状态为 Premium
→ UI 立即解锁
→ Subscription Success Page 或 Premium unlocked Toast
→ 异步同步 transaction 到服务端
→ 服务端验证并建立 transaction / originalTransactionId 链路
→ 后续由 App Store Server Notifications V2 / Apple Server API 持续维护生命周期
```

服务端 Apple 订单、App Store Server Notifications V2、Apple Server API 和生命周期数据用于订单统计、生命周期记录、退款处理、数据分析、问题排查、订阅状态维护与校正，以及交易发生时的用户唯一标识关联，不作为 App 账号的 Premium ownership 依据。

如果购买发生时用户已登录，订单可记录当前用户唯一标识（技术字段可为 uid）；游客购买时该字段可为空。后续游客 → 账号的数据补关联只改善后台统计完整性，不改变 Premium。

# 3. Subscription Page

## 3.1 页面用途

Subscription Page 用于：

- Free 状态用户的完整冷启动
- 首次启动完成注册登录或跳过登录后的订阅展示
- Profile 顶部 Subscription Banner 入口
- Home、Search、Collection、Profile 一级页面顶部订阅入口
- Scan 页面 Pro / scans remaining 状态卡片入口

Premium 状态用户不自动展示 Subscription Page。

## 3.2 固定内容

页面标题：

```text
Choose Your Plan
```

Plans / Products：

| Product | 美区配置目标 / Prototype 文案 | 选择规则 |
| --- | --- | --- |
| Weekly | `$4.99/week` | 可选 |
| Yearly | `$49.99/year` | 默认选中 |
| Lifetime Access | `$79.99 one-time purchase` | 可选；明确为一次性购买 |

Benefits：

- Unlimited Card Scanning
- Unlimited Portfolio Folders
- Track Portfolio Performance
- Extended Price History

操作：

- Close
- Subscribe
- Restore
- Terms of Use
- Privacy Policy

同一时间只能选中一个 Product。Premium Benefits 固定为以上四项。

正式 App 页面优先展示 StoreKit 返回的本地化价格和币种。固定美元价格只作为美区配置目标和 Prototype 文案，不作为所有地区的硬编码显示值；购买确认金额始终以 Apple 支付页面为准。

### 3.2.1 页面交互与控件规则

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Close | Subscription Page 已展示 | 页面未处于 Apple 系统购买弹窗内；非 Restore Blocking Loading；商品加载、商品失败、Purchase Cancelled/Pending/Failed、Restore Not Found/Failed 后仍可点 | 关闭完整 Subscription Page；不改变 Premium；不修改当前选中的 Product；不触发 Apple Purchase | 首次启动和冷启动进入 Home；Profile Banner 来源进入 Profile；Home/Search/Collection/Profile 顶部入口进入对应发起页；Scan Pro 卡片来源进入 Scan | 目标页按当前 Premium 状态渲染；关闭动作本身不授予 Premium；Scan 目标页保留当前 Free 额度与 Queue 状态 | - | 关闭前选中的 Product 只保留在本次 Subscription Page 实例内；页面关闭后不要求作为下次默认选中项；不清空 `source_page` / `entry_source` 日志 |
| Weekly Plan | 商品列表区域展示；商品加载中价格位显示 Loading；Product 未返回时可显示 Unavailable 或当前 Prototype 允许的不可用状态 | Product 已成功返回且当前无 StoreKit 业务操作；Restore Blocking Loading 或 Purchase 进行中不可点 | 若未选中，设为唯一 Selected；取消原 Selected；更新后续 Subscribe 使用的 `selected_product_id`；若已选中，保持 Selected | 当前 Subscription Page 的 Plan Radio Group | Selected UI 更新；不拉起 Apple Purchase | Product 元数据未成功返回时不可购买，不展示伪造价格 | 保留当前 `source_page`、`entry_source` 和页面滚动位置 |
| Yearly Plan | 商品列表区域展示；页面首次正常加载默认 Selected；商品加载中价格位显示 Loading；Product 未返回时可显示 Unavailable 或当前 Prototype 允许的不可用状态 | Product 已成功返回且当前无 StoreKit 业务操作；Restore Blocking Loading 或 Purchase 进行中不可点 | 若未选中，设为唯一 Selected；取消原 Selected；更新后续 Subscribe 使用的 `selected_product_id`；若已选中，保持 Selected | 当前 Subscription Page 的 Plan Radio Group | Selected UI 更新；不拉起 Apple Purchase | Yearly 不可用时按第 6.4 节自动选择第一个可用 Product；不可用 Product 不得继续 Selected 后 Purchase | 保留当前 `source_page`、`entry_source` 和页面滚动位置 |
| Lifetime Plan | 商品列表区域展示；商品加载中价格位显示 Loading；Product 未返回时可显示 Unavailable 或当前 Prototype 允许的不可用状态 | Product 已成功返回且当前无 StoreKit 业务操作；Restore Blocking Loading 或 Purchase 进行中不可点 | 若未选中，设为唯一 Selected；取消原 Selected；更新后续 Subscribe 使用的 `selected_product_id`；若已选中，保持 Selected | 当前 Subscription Page 的 Plan Radio Group | Selected UI 更新；不拉起 Apple Purchase | Product 元数据未成功返回时不可购买，不展示伪造价格 | 保留当前 `source_page`、`entry_source` 和页面滚动位置 |
| Subscribe | Subscription Page 已展示 | 当前无 Purchase / Restore 请求进行中；Selected Product 已成功返回，或允许本次点击在 15 秒 Deadline 内重新请求可用 Product；Purchase Pending 期间不可再次提交 | 读取当前 Selected Product；Subscribe 进入 Loading；禁止重复点击；商品已加载时调起 Apple Purchase；商品未加载时请求当前 Product，加载成功后同一次点击继续调起 Apple Purchase；不可用 SKU 不得购买 | Apple 系统购买弹窗；购买返回后回到 Subscription Page 或 Subscription Success | Success + verified：刷新 Premium，关闭 Subscription Page，进入 Subscription Success；Subscription Success 使用购买前保存的 `source_page` / `entry_source` | Cancelled/Failed、Purchase unavailable、Transaction Unverified：停留 Subscription Page，Premium 不变，Subscribe 恢复可点；Pending：停留 Subscription Page，显示 Pending 提示，Subscribe 暂不可再次提交，等待 Transaction Update；商品仍失败或 15 秒 Timeout 时展示第 6.4 节错误 | 保留当前选中 Product、`source_page`、`entry_source` 和页面滚动位置；Purchase 与 Restore 不得并发 |
| Restore | Subscription Page 已展示 | 当前无 Purchase / Restore 请求进行中 | 整个 Subscription Page 进入阻断式 Loading；调用 StoreKit 重新同步当前 Apple 购买上下文；最长 15 秒；Loading 期间 Close、Plans、Subscribe、Restore、Terms、Privacy、页面其他控件、Back / 业务返回均不可触发；请求完成前不改变 Premium、不关闭页面、不进入 Subscription Success | 当前 Subscription Page；StoreKit Restore 流程 | Success：恢复有效 Premium 后刷新 Premium，关闭 Subscription Page，按 `source_page` 返回来源页并展示 `Premium restored` Toast；首次启动/冷启动或来源丢失进入 Home；Profile Banner 进入 Profile；Home/Search/Collection/Profile 顶部入口进入对应发起页；Scan Pro 卡片来源进入 Scan 并刷新 Premium / `Unlimited scans` 状态；若当前有效 Queue 仍有 Waiting，则 Waiting 按原 Queue 顺序自动进入 Processing | Not Found：结束 Loading，按最新 verified current entitlements 刷新为 Free，停留 Subscription Page，展示 `No subscription found` Toast；Failed 或 15 秒 Timeout：结束 Loading，显示 Restore Failed Alert，点击 OK 后返回 Subscription Page，保持原权益状态；均不执行订阅成功跳转 | 保留当前选中 Product、`source_page`、`entry_source` 和页面滚动位置；Restore Timeout 后迟到 callback 不得关闭页面、显示成功 Toast 或执行旧动作；Queue 已按 v1.0 退出规则清理时不得恢复旧 Waiting |
| Terms of Use | Subscription Page 已展示 | Apple 系统购买弹窗显示期间不可点；Restore Blocking Loading 期间不可点 | 跳转系统浏览器，打开 App 官网 Terms of Use 页面；不关闭 Subscription Page 业务上下文；不触发购买 | 系统浏览器；URL 沿用 v1.0 当前正式配置，本 PRD 不编造 URL | 用户切回 App 后仍回到 Subscription Page | 协议页打开失败时按 v1.0 外部链接错误反馈处理；不改变 Premium | 保留购买前当前选中 Product、`source_page`、`entry_source` 和页面滚动位置 |
| Privacy Policy | Subscription Page 已展示 | Apple 系统购买弹窗显示期间不可点；Restore Blocking Loading 期间不可点 | 跳转系统浏览器，打开 App 官网 Privacy Policy 页面；不关闭 Subscription Page 业务上下文；不触发购买 | 系统浏览器；URL 沿用 v1.0 当前正式配置，本 PRD 不编造 URL | 用户切回 App 后仍回到 Subscription Page | 协议页打开失败时按 v1.0 外部链接错误反馈处理；不改变 Premium | 保留购买前当前选中 Product、`source_page`、`entry_source` 和页面滚动位置 |

## 3.3 首次安装权限与 ATT

ATT 请求只属于首次安装启动阶段，与 App 已有首次启动网络授权串行执行。

```text
App Launch
→ Splash
→ 执行现有网络授权流程
→ 网络授权流程结束
→ 检查 ATT Authorization Status
├─ notDetermined → 请求 ATT
├─ authorized → 不重复请求
├─ denied → 不重复请求
└─ restricted → 不重复请求
→ 继续 Onboarding / 登录 / Subscription 流程
```

规则：

1. 网络授权与 ATT 不允许同时弹出；必须等待现有网络授权流程结束后再检查 ATT。
2. 仅 `status = notDetermined` 时主动请求 ATT。
3. `authorized`、`denied`、`restricted` 均不重复请求，并正常继续进入 App。
4. ATT 拒绝或受限不得影响 App 使用、登录注册、Scan、Portfolio、Subscription 或 Apple Purchase。
5. ATT 不在每次冷启动重复请求；后续完整冷启动和后台回前台均不主动再次弹出。
6. Singular 在 ATT 流程结束后，根据最终 ATT 状态继续完成归因初始化。
7. Singular 账号相关 Key 与配置在账号申请完成后补充，未配置时不得阻断 App 主流程。
8. “网络授权”只指 App 已有的首次启动系统权限流程。不得为了 Singular 或 ATT 新增无业务需要的网络权限或额外权限弹窗。

后续 App 从后台回前台时，允许重新读取当前 ATT Authorization Status，并将最新状态同步给 Singular；但不得主动再次弹出 ATT 系统授权框。如果用户在系统 Settings 修改 ATT，App 只读取最新状态并更新归因上下文，不得阻断业务。

## 3.4 首次安装启动流程

首次安装启动顺序固定为：

```text
启动页
→ 现有网络授权流程
→ ATT 状态检查 / 必要时请求
→ 引导页 1
→ 引导页 2
→ 引导页 3
→ 注册登录 / 跳过
→ 检查 Premium 权益状态
├─ Free → Subscription Page
│  ├─ Close → Home
│  └─ Purchase Success → Subscription Success → Home
├─ Premium → Home
└─ Unknown → Home，并继续后台刷新
```

不得调整以上顺序。

## 3.5 后续完整冷启动

```text
启动页
→ 检查 Premium 权益状态
├─ Free → Subscription Page
│  ├─ Close → Home
│  └─ Purchase Success → Subscription Success → Home
├─ Premium → Home
└─ Unknown → Home，并继续后台刷新
```

- App 从后台回到前台不视为完整冷启动。
- 后台回前台不自动展示 Subscription Page。
- Unknown 不进入 Free 分支，也不自动展示 Subscription Page。
- 后续完整冷启动不主动再次请求 ATT。

进入页面时必须记录：

- `source_page`：Home / Search / Scan / Collection / Profile / onboarding / cold_start
- `entry_source`：首次启动、冷启动、Profile Banner、Home/Search/Collection/Profile 顶部入口、Scan Pro 卡片

## 3.6 Subscription Page 关闭与成功流转

Subscription Page 只能通过以下方式关闭：

1. 点击页面关闭按钮。
2. Apple 购买成功并进入 Subscription Success。
3. Restore 成功并恢复为 Premium。

关闭后的流转：

| 来源 | 点击关闭按钮 | Apple Purchase Success | Restore Success |
| --- | --- | --- | --- |
| 首次启动 | Home | Subscription Success → Home | Home |
| 后续完整冷启动 | Home | Subscription Success → Home | Home |
| Profile Banner | 返回 Profile | Subscription Success → Profile | 返回并刷新 Profile Premium 状态 |
| Home / Search / Collection / Profile 顶部入口 | 返回 Home / Search / Collection / Profile 中的实际发起页 | Subscription Success → Home / Search / Collection / Profile 中的实际发起页 | 返回实际发起页并刷新 Premium 状态 |
| Scan Pro 卡片 | 返回 Scan | Subscription Success → Scan；若当前有效 Queue 仍有 Waiting，则 Waiting 按原 Queue 顺序自动进入 Processing | 返回 Scan 并刷新 Premium / Unlimited scans 状态；若当前有效 Queue 仍有 Waiting，则 Waiting 按原 Queue 顺序自动进入 Processing |

以下结果不自动关闭页面：

- Purchase Cancelled
- Purchase Pending
- Purchase Failed
- Restore Not Found
- Restore Failed
- Restore Timeout
- 商品加载失败
- Product Loading Timeout

# 4. Subscription Success

Subscription Success 是 Apple Purchase 成功后的 Full Page，不是 Modal。页面视觉、文案与结构以 `prototype-handoff/subscription_success_spec.md` 和当前 `html/subscription_success.html` 原型为准。

## 4.1 使用范围

只有用户从完整 Subscription Page 主动购买成功后进入 Subscription Success。Restore 成功与功能卡点 Paywall Modal 购买成功均不进入本页。

首次启动：

```text
Splash
→ Onboarding
→ Sign In / Sign Up / Skip
→ Entitlement Check
→ Free
→ Subscription Page
→ Apple Purchase Success
→ Subscription Success
→ Start Exploring
→ Home
```

后续完整冷启动 Free 用户：

```text
Splash
→ Entitlement Check
→ Free
→ Subscription Page
→ Apple Purchase Success
→ Subscription Success
→ Start Exploring
→ Home
```

Profile Premium Banner：

```text
Profile
→ Premium Banner
→ Subscription Page
→ Apple Purchase Success
→ Subscription Success
→ Start Exploring
→ Profile
```

Home / Search / Collection / Profile 一级页面顶部订阅入口：

```text
Home / Search / Collection / Profile
→ Subscription Entry
→ Subscription Page
→ Apple Purchase Success
→ Subscription Success
→ Start Exploring
→ 进入 Home / Search / Collection / Profile 中的实际发起页
```

Scan Pro 卡片入口：

```text
Scan
→ Pro / scans remaining 卡片
→ Subscription Page
→ Apple Purchase Success
→ Subscription Success
→ Start Exploring
→ Scan
→ 如果当前有效 Queue 仍有 Waiting
→ Waiting 按原 Queue 顺序自动进入 Processing
```

进入 Subscription Page 时必须保留 `source_page` 与 `entry_source`。Subscription Success 使用该来源状态返回，不得将所有购买成功场景统一返回 Home。无法识别来源时，兜底进入 Home Premium。

如果用户已经确认退出 Scan 并按 v1.0 规则清理 Queue，Subscription Success 返回 Scan 时不得恢复已经被清除的 Waiting，也不得重新创建旧 Queue。

## 4.2 页面内容

页面名称：Subscription Success。

Title：

```text
You're Premium!
```

Subtitle：

```text
Your premium features are now unlocked.
```

Premium Benefits：

- Unlimited Card Scanning
- Unlimited Portfolio Folders
- Track Portfolio Performance
- Extended Price History

主按钮：

```text
Start Exploring
```

Wishlist 不属于 Premium，不得增加其他权益。

## 4.3 页面状态与交互

1. 页面只在 verified transaction 已将本地 entitlement 更新为 Premium 后展示。
2. `Start Exploring` 点击前，页面不自动跳转。
3. 点击 `Start Exploring` 后按 `source_page` / `entry_source` 返回 Home、Profile、Scan 或 Home / Search / Collection / Profile 中的实际发起页。
4. 返回目标页后必须展示 Premium 状态并刷新相关入口与锁定态。
5. Subscription Success 不叠加 Paywall、Success Modal 或第二次确认弹窗。
6. Subscription Success 是购买完成后的终态页面，正常出口只有 `Start Exploring`。
7. 不得通过系统返回手势、Back 按钮或导航栈回到已经完成购买的旧 Subscription Page；旧 Subscription Page 不应继续保留在可返回导航栈中。

### 4.3.1 页面交互与控件规则

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Start Exploring | Subscription Success 已展示 | 页面未处于跳转中；同一页面实例只允许一次正常点击跳转 | 读取进入 Subscription Page 时保存并传入本页的 `source_page` / `entry_source`；不再次检查购买；不再次弹 Paywall；不得返回旧 Subscription Page | `source_page=onboarding` 或 `cold_start` 进入 Home；Profile Banner 来源进入 Profile；Home/Search/Collection/Profile 顶部入口进入对应发起页；`source_page=Scan` 且 `entry_source=scan_pro_card` 进入 Scan；`source_page` 丢失或无法识别时进入 Home | 目标页以 Premium 状态渲染，隐藏升级入口，刷新锁定态和 Premium 功能数据；Scan 目标页展示 Premium / Unlimited scans 状态 | 跳转失败时停留 Subscription Success，按钮恢复可点；不得重新发起 Apple Purchase | 保留本次成功购买产生的 Premium 状态；不保留 Subscription Page 或 Plan 选择作为后续返回栈/默认项 |

# 5. Subscription Paywall Modal

## 5.1 内容关系

Subscription Page 与 Subscription Paywall Modal 使用完全一致的：

- Title
- Benefits
- Plans / Products
- 默认选中项
- Subscribe
- Restore
- Terms of Use
- Privacy Policy

两者只在展示容器和进入来源上不同。

## 5.2 展示形式

Paywall 是 App 内大弹窗，展示形式以当前 UI稿 为准。

- 背景页面保留在弹窗后方。
- 弹窗内容可以在容器内滚动。
- 不增加其他手势或键盘关闭方式。
- 不改变 Subscription Page 的方案内容。

## 5.3 触发来源

- Home Performance 锁定区域或 Unlock CTA
- Card Detail Performance 锁定区域或 Unlock CTA
- Home Overview Portfolio Chart 中 Free 点击 1Y 触发的 Extended Price History 权益卡点
- Card Detail Price History 中 Free 点击 1Y 触发的 Extended Price History 权益卡点
- Scan 剩余额度入口或额度不足
- Portfolio Folder 达到 Free 上限
- 其他 Premium 功能操作卡点

## 5.4 关闭方式

Paywall Modal 只能通过以下方式关闭：

1. 点击弹窗关闭按钮。
2. 点击弹窗外区域。
3. Apple 购买成功。
4. Restore 成功并恢复为 Premium。

以下结果不得自动关闭：

- Purchase Cancelled
- Purchase Pending
- Purchase Failed
- Restore Not Found
- Restore Failed
- 商品加载失败

## 5.5 关闭后状态恢复

关闭后必须恢复触发前页面的：

- 当前 Tab
- 滚动位置
- 表单输入
- 已选 Performance 时间范围
- Scan Queue
- 已加载数据
- 被阻断操作及其必要参数

功能卡点 Paywall 存在可恢复动作时，必须保存可恢复的 `blocked_action` / action token。quota = 0 Capture / Gallery 这类本次图片尚未进入 Queue 的来源只保存来源上下文，不保存可自动执行扫描的 `blocked_action`。不得叠加多个 Paywall Modal。

Paywall 打开后，原业务目标可能已经失效，例如 Collection Item 被删除、Folder 被另一设备删除、Card 上下文已经退出、Scan Queue 已经清空或 Waiting Item 已经不存在。此时如果 Purchase / Restore 成功，Premium 仍正常授予，成功 Toast 仍正常展示；但不得强制执行失效 `blocked_action`，不得重新创建已删除 Item、恢复已退出 Queue、跳回不存在的 Folder 或打开失效 Card 上下文。应留在当前有效页面，或按当前页面安全兜底逻辑处理。

## 5.6 Premium 成功后的来源恢复

| 触发来源 | 成功后结果 |
| --- | --- |
| Home Performance | 关闭 Paywall，显示成功反馈，刷新并自动展示当前 Performance |
| Card Detail Performance | 关闭 Paywall，显示成功反馈，刷新当前 Performance Tab 并展示内容 |
| Extended Price History - Home Overview Portfolio Chart | 关闭 Paywall，显示成功反馈，返回 Home Overview，保持当前 Folder，并自动选择和加载 1Y Portfolio Chart |
| Extended Price History - Card Detail Price History | 关闭 Paywall，显示成功反馈，返回同一个 Card Detail，并自动选择和加载 1Y Price History |
| Folder 限制 | 关闭 Paywall，显示成功反馈，并自动打开 v1.0 Create Folder 弹窗 |
| Scan - 已存在 Waiting | 关闭 Paywall，显示成功反馈，恢复原 Scan 页面与 Queue，并让 Waiting 按原 Queue 顺序进入 Processing |
| Scan - quota = 0 且图片未进入 Queue | 关闭 Paywall，显示成功反馈，返回原 Scan 页面；不自动打开相机 / Gallery，不创建 Scan Item，用户重新点击 Capture 或 Gallery |
| 其他功能卡点 | 关闭 Paywall 并显示成功反馈；如存在可执行且仍有效的 `blocked_action`，则自动执行；如不存在可自动执行的 `blocked_action`，则按来源场景恢复页面状态 |

执行 `blocked_action` 前必须确认目标仍有效；如果目标已失效，按第 5.5 节失效规则处理，不强制恢复旧操作。

成功反馈按触发结果区分：

| 成功来源 | Toast |
| --- | --- |
| Purchase Success | `Premium unlocked` |
| Restore Success | `Premium restored` |

Toast 均无按钮并自动消失。功能卡点 Purchase Success 和 Restore Success 均不得进入 Subscription Success，不增加 Success Modal，不要求用户再次点击确认，也不得清空当前操作上下文。Restore Not Found / Restore Failed 不关闭 Paywall、不执行 `blocked_action`，且不得清空上述上下文。

## 5.7 Functional Paywall 未获得 Premium 统一规则

只要本次 Subscription Paywall 流程最终没有获得有效 Premium entitlement，则统一：

- 不执行 `blocked_action`。
- 不进入 Premium 内容。
- 不伪造成功状态。
- 保持或恢复原业务页面上下文。
- 原 Tab / Range / Queue / Folder / Card / Scroll 等按已有规则保留。
- 具体错误 UI 按 Subscription / Restore 章节定义。

包括但不限于 Close、Scrim、Purchase Cancelled、Purchase Pending、Purchase Failed、Purchase unavailable、Transaction Unverified、Product Loading Failed、Product Timeout、Restore Not Found、Restore Failed 和 Restore Timeout。

特殊规则：

- Pending：原 Paywall 保持打开并等待 Transaction Update；当前容器内 Subscribe 暂不可再次提交。
- Restore Not Found：按最新 verified current entitlements 重新计算最终权益；没有任何有效 Premium entitlement 时刷新为 Free。
- Restore Failed / Timeout：因为没有成功获得可靠 StoreKit 结果，保持原权益状态。

各功能章节不再需要重复枚举所有 Subscription 异常结果；页面存在特殊状态保留逻辑时，只描述该页面特有规则。

## 5.8 页面交互与控件规则

Plan、商品 Loading、Subscribe 购买结果和 Restore 结果的基础规则与 Subscription Page 一致；Paywall Modal 的差异在于容器为 App 内 Modal，成功后恢复被拦截功能上下文，不进入 Subscription Success。

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Weekly Plan | Paywall Modal 已打开；商品加载中价格位显示 Loading；Product 未返回时可显示 Unavailable 或当前 Prototype 允许的不可用状态 | Product 已成功返回且当前无 StoreKit 业务操作；Restore Blocking Loading 或 Purchase 进行中不可点 | 若未选中，设为唯一 Selected；取消原 Selected；更新后续 Subscribe 使用的 `selected_product_id`；若已选中，保持 Selected | 当前 Paywall Modal 的 Plan Radio Group | Selected UI 更新；不拉起 Apple Purchase | Product 元数据未成功返回时不可购买，不展示伪造价格 | 保留背景页、`blocked_action`、触发前 Tab/Range/Queue/表单/滚动位置 |
| Yearly Plan | Paywall Modal 已打开；首次正常加载默认 Selected；商品加载中价格位显示 Loading；Product 未返回时可显示 Unavailable 或当前 Prototype 允许的不可用状态 | Product 已成功返回且当前无 StoreKit 业务操作；Restore Blocking Loading 或 Purchase 进行中不可点 | 若未选中，设为唯一 Selected；取消原 Selected；更新后续 Subscribe 使用的 `selected_product_id`；若已选中，保持 Selected | 当前 Paywall Modal 的 Plan Radio Group | Selected UI 更新；不拉起 Apple Purchase | Yearly 不可用时按第 6.4 节自动选择第一个可用 Product；不可用 Product 不得继续 Selected 后 Purchase | 保留背景页、`blocked_action`、触发前 Tab/Range/Queue/表单/滚动位置 |
| Lifetime Plan | Paywall Modal 已打开；商品加载中价格位显示 Loading；Product 未返回时可显示 Unavailable 或当前 Prototype 允许的不可用状态 | Product 已成功返回且当前无 StoreKit 业务操作；Restore Blocking Loading 或 Purchase 进行中不可点 | 若未选中，设为唯一 Selected；取消原 Selected；更新后续 Subscribe 使用的 `selected_product_id`；若已选中，保持 Selected | 当前 Paywall Modal 的 Plan Radio Group | Selected UI 更新；不拉起 Apple Purchase | Product 元数据未成功返回时不可购买，不展示伪造价格 | 保留背景页、`blocked_action`、触发前 Tab/Range/Queue/表单/滚动位置 |
| Subscribe | Paywall Modal 已打开 | 当前无 Purchase / Restore 请求进行中；Selected Product 已成功返回，或允许本次点击在 15 秒 Deadline 内重新请求可用 Product；Purchase Pending 期间不可再次提交 | 读取当前 Selected Product；Subscribe 进入 Loading；禁止重复点击；商品已加载时调起 Apple Purchase；商品未加载时请求当前 Product，加载成功后同一次点击继续调起 Apple Purchase；不可用 SKU 不得购买 | Apple 系统购买弹窗；购买返回后回到 Paywall Modal 或触发前页面 | Success + verified：关闭 Modal，刷新 Premium，显示 `Premium unlocked` Toast；如存在可执行且仍有效的 `blocked_action`，自动执行该 `blocked_action`；如不存在可自动执行的 `blocked_action`，只按来源场景恢复页面状态 | 未获得 Premium 时按第 5.7 节统一规则处理；Pending：Modal 保持打开，显示 Pending 提示，Subscribe 暂不可再次提交，等待 Transaction Update | 保留背景页、触发前 Tab/Range/Queue/表单/滚动位置、当前选中 Product 和 `blocked_action`；Purchase 与 Restore 不得并发 |
| Restore | Paywall Modal 已打开 | 当前无 Purchase / Restore 请求进行中 | 整个 Paywall 进入阻断式 Loading；调用 StoreKit 重新同步当前 Apple 购买上下文；最长 15 秒；Loading 期间 Plans、Subscribe、Restore、Close、Scrim、Terms、Privacy、Paywall 其他控件均不可触发，背景页仍不可操作；请求完成前不改变 Premium、不关闭 Paywall、不执行 `blocked_action` | 当前 Paywall Modal；StoreKit Restore 流程 | Success：关闭 Modal，刷新 Premium，显示 `Premium restored` Toast；如存在可执行且仍有效的 `blocked_action`，则自动执行；如不存在可自动执行的 `blocked_action`，则按来源场景恢复页面状态 | Not Found：结束 Loading，按最新 verified current entitlements 刷新为 Free，Modal 继续显示，显示 `No subscription found` Toast，`blocked_action` 继续保存但不执行；Failed 或 15 秒 Timeout：结束 Loading，显示 Restore Failed Alert，点击 OK 后回到原 Paywall，保持原权益状态，`blocked_action` 继续保存但不执行 | 保留背景页、触发前 Tab/Range/Queue/表单/滚动位置、当前选中 Product 和 `blocked_action`；Restore Timeout 后迟到 callback 不得关闭 Paywall、显示成功 Toast 或执行旧动作；失效 `blocked_action` 不得强制执行 |
| Close | Paywall Modal 已打开 | Apple 系统购买弹窗未展示；非 Restore Blocking Loading；商品加载、商品失败、Purchase Cancelled/Pending/Failed、Restore Not Found/Failed 后仍可点 | 关闭 Modal；不执行 `blocked_action`；不改变 Premium；不触发购买 | 触发前页面的同一页面实例和同一容器 | 背景页恢复可操作 | - | 保留触发前 Tab、Range、Tooltip、Queue、表单、滚动位置和已加载数据；`blocked_action` 可清除或标记为未执行，不能误执行 |
| Scrim | Paywall Modal 已打开且 UI 定义存在弹窗外遮罩 | Apple 系统购买弹窗未展示；非 Restore Blocking Loading | 与 Close 相同：关闭 Modal；不执行 `blocked_action`；不改变 Premium；不触发购买 | 触发前页面的同一页面实例和同一容器 | 背景页恢复可操作 | - | 与 Close 相同 |
| Terms of Use | Paywall Modal 已打开 | Apple 系统购买弹窗未展示；非 Restore Blocking Loading | 跳转系统浏览器，打开 App 官网 Terms of Use 页面；不关闭 Paywall 业务上下文；不触发购买 | 系统浏览器；URL 沿用 v1.0 当前正式配置，本 PRD 不编造 URL | 用户切回 App 后仍回到 Paywall Modal | 协议页打开失败时按 v1.0 外部链接错误反馈处理；不改变 Premium | 保留当前选中 Product、背景页、`blocked_action`、触发前 Tab/Range/Queue/表单/滚动位置 |
| Privacy Policy | Paywall Modal 已打开 | Apple 系统购买弹窗未展示；非 Restore Blocking Loading | 跳转系统浏览器，打开 App 官网 Privacy Policy 页面；不关闭 Paywall 业务上下文；不触发购买 | 系统浏览器；URL 沿用 v1.0 当前正式配置，本 PRD 不编造 URL | 用户切回 App 后仍回到 Paywall Modal | 协议页打开失败时按 v1.0 外部链接错误反馈处理；不改变 Premium | 保留当前选中 Product、背景页、`blocked_action`、触发前 Tab/Range/Queue/表单/滚动位置 |

# 6. Apple 支付购买流程

## 6.1 v1.1 范围

v1.1 产品范围包含：

- App Store 商品读取
- Apple 支付流程拉起
- Purchase 结果处理
- Restore Purchase
- 购买或 Restore 成功后的客户端 Premium 状态刷新
- 服务端 App Store Server Notifications V2 / Apple Server API 生命周期状态维护与校正所需的产品结果约束

## 6.2 暂不定义

- Notification Route URL
- 数据库表名 / Schema
- Worker
- Queue
- JWS Library
- Apple Server API SDK 选择
- Retry framework
- 数据库拆表方式
- 服务端接口具体字段
- 以 App 账号作为客户端 Premium access 真值
- 将服务端 entitlement 解释为 UID ownership
- App 账号与订阅 ownership 绑定
- 人工订阅权益管理功能
- SKU 升级或降级

产品能力必须做，不等于 App PRD 必须定义技术实现。上述服务端 Apple 能力的产品结果必须符合《Apple Subscription & Premium 权益统一方案》：服务端维护 Apple 购买链路生命周期状态，用于续订、Grace Period、Billing Retry、Expired、Refund、Revoked 等状态维护与校正，但不把 Premium 归属改为 App UID。

## 6.2.1 v1.1 Apple 后端基础依赖

为满足本版本 Subscription 生命周期和 Admin 订单 / 苹果通知能力，v1.1 必须具备以下服务端基础能力：

1. App Store Server Notifications V2 接收入口。
2. Apple JWS 验签。
3. Notification Payload 解码。
4. 原始 `signedPayload` 保存。
5. Decoded Payload 保存。
6. `transactionId` / `originalTransactionId` 提取与链路维护。
7. Notification 幂等处理。
8. 重复通知防重复建单 / 防重复处理。
9. Notification 业务消费失败可恢复 / 可重试。
10. Refund / Revoked / Expired / Grace Period / Billing Retry / Billing Recovery 生命周期处理。
11. Notification 乱序 / 晚到保护。
12. 必要时使用 Apple Server API 查询当前交易 / 订阅状态进行校正。
13. Production / Sandbox 隔离。
14. App 与服务端 Apple lifecycle state 的同步能力。

这些属于 v1.1 必须具备的后端依赖，不是未来版本能力，也不是当前已经存在、无需开发的能力。具体技术实现仍按第 6.2 节保持开发自由度。

## 6.3 Subscribe 原则

1. `Subscribe` 始终可见，是支付调用和用户主动再次尝试的唯一入口。
2. 商品已加载时，点击 `Subscribe` 直接拉起 Apple 购买。
3. 商品未加载时，点击 `Subscribe` 立即重新请求当前选中商品；加载成功后在同一次点击流程中继续拉起 Apple 购买，用户无需再次点击。
4. 商品加载或购买进行中显示 Loading，并暂时禁止重复点击；请求结束后恢复可点击，不得永久禁用。
5. 页面中不增加独立商品重载或再次尝试按钮。
6. 以下非支付依赖失败不得阻止 Apple 购买：
   - 业务接口
   - 埋点接口
   - 页面推荐接口
   - 用户资料接口
   - 非必要配置接口
7. Purchase Failed 或 User Cancelled 后不得自动再次拉起 Apple 购买，必须由用户再次主动点击 `Subscribe`；Purchase Pending 期间当前订阅容器内 `Subscribe` 暂不可再次提交，直到明确 Failed 或容器上下文失效。
8. 同一个 Subscription Page 或 Paywall 同一时间只能存在一个 StoreKit 业务操作；Purchase 已开始时 Restore 不可触发，Restore Blocking Loading 期间 Subscribe 不可触发，不得出现 Purchase + Restore 同时运行。

## 6.4 商品加载与自动重试

1. Subscription Page 或 Paywall 打开时立即请求 StoreKit 商品。
2. 临时失败时后台最多自动重试 3 次，建议间隔为 1 秒、3 秒、8 秒，但所有自动重试必须共享本次 Product Loading 的 15 秒总 Deadline。
3. 网络恢复或 App 重新进入前台时可以主动刷新一次商品；刷新同样受 15 秒上限和上下文有效性约束。
4. 同一时间只允许一个商品加载请求。
5. 自动重试达到上限或本次操作总时间达到 15 秒后停止，不得无限请求。
6. 只允许自动重试商品加载，不得自动重新发起 Apple 购买。
7. 不展示伪造价格。
8. 只有 StoreKit 实际成功返回的 Product 可 Selected、可购买，并展示真实本地化价格。
9. 未成功返回的 Product 不允许购买，不使用 Prototype 美元价格冒充正式价格；UI 可以显示 `Unavailable` 或保持当前 Prototype 允许的不可用状态。
10. 正常情况下 Yearly 默认 Selected；如果 Yearly 不可用，自动选择当前第一个可用 Product，优先顺序为 Weekly → Lifetime。
11. 如果全部 Product 不可用，`Subscribe` 仍保留；用户点击 `Subscribe` 可重新请求 Products，本次操作最多 15 秒。
12. 用户点击 `Subscribe` 后商品仍加载失败或 Product Loading 15 秒 Timeout 时使用 Toast：

```text
Unable to connect to the App Store. Please try again.
```

13. Page 或 Modal 保持可关闭，但 Restore Blocking Loading 期间除外。
14. 用户再次点击 `Subscribe` 可再次尝试，并开启新的 15 秒请求周期。
15. 不增加独立商品加载操作按钮。

### 6.4.1 Product 前后台刷新

App 从后台回前台时可以重新刷新 StoreKit Product 元数据。

- 如果原 Selected Product 仍可用，保持 Selected。
- 如果原 Selected Product 已经不可用，切换到第一个可用 Product。
- 不得保留一个不可购买 SKU 为 Selected 后继续 Purchase。
- 价格始终以最新 StoreKit 返回的本地化价格为准。

## 6.5 Purchase 结果

### Success

- Apple Transaction 验证成功后刷新 Premium 权益状态并立即更新本地权益缓存。
- 解锁 Premium 功能。
- 从完整 Subscription Page 购买：关闭 Subscription Page并进入 Subscription Success；点击 `Start Exploring` 后，首次启动/冷启动进入 Home，Profile Banner 进入 Profile，Home / Search / Collection / Profile 顶部入口进入实际发起页，Scan Pro 卡片入口进入 Scan；若 Scan 当前有效 Queue 仍有 Waiting，则 Waiting 按原 Queue 顺序自动进入 Processing。
- 从 Paywall Modal 购买：自动关闭 Paywall，显示 `Premium unlocked` Toast，并继续执行仍有效的被阻断操作。
- 不等待 App Store Server Notification 或后台订单同步后再解锁。

### User Cancelled

- 停留当前 Page 或 Modal。
- 不改变 Premium 状态。
- 不显示错误 Toast。
- `Subscribe` 恢复可点击。
- 不自动重新拉起 Apple 购买。

### Pending

- 停留当前 Page 或 Modal。
- 暂不授予 Premium 权限。
- `Subscribe` 暂不可再次提交新的 Purchase。
- `Restore` 不与该 Purchase 并发。
- Close 仍允许用户主动离开。
- 使用 Toast 提示购买仍在处理中。
- 等待后续交易状态更新。
- 不自动重新拉起 Apple 购买。
- Pending 超过 15 秒不得自动变 Failed。

Purchase Pending 文案：

```text
Purchase pending
Your purchase is still being processed.
```

如果当前 UI 只允许单行 Toast：

```text
Purchase is still being processed.
```

Pending 期间：

1. 不授予 Premium。
2. 不自动关闭当前订阅容器。
3. 不自动再次购买，且当前 Subscription Page / Paywall 实例内 `Subscribe` 暂不可再次提交。
4. `Restore` 不与该 Purchase 并发。
5. Close 仍允许用户主动离开。
6. 等待 StoreKit 后续 Transaction 更新。

后续 Transaction verified Success 时：

- 如果用户仍停留在原 Subscription Page / Paywall，且原业务上下文仍有效，则按照正常 Purchase Success 继续处理。
- 如果用户已经关闭 Subscription Page、关闭 Paywall、切换页面、App 重新进入，或原 `blocked_action` 已失效，则只更新 Premium、更新本地 entitlement cache、刷新当前页面 Premium 状态。
- 如果 App 处于前台，显示轻量 `Premium unlocked` Toast。
- 不自动重新打开旧 Paywall。
- 不自动重新打开 Subscription Page。
- 不自动进入旧 Subscription Success Page。
- 不自动执行已经失效的 `blocked_action`。
- 不强制用户回到之前页面。

后续 Transaction 明确 Failed 时：

- 结束 Pending 状态。
- `Subscribe` 恢复可操作。
- 按 Purchase Failed 处理。

### Failed

- 停留当前 Page 或 Modal。
- 不改变 Premium 状态。
- `Subscribe` 恢复可点击。
- 使用 Toast 展示失败信息。
- 不增加独立商品加载操作按钮。
- 不自动重新拉起 Apple 购买。

普通 Purchase Failed 文案：

```text
Something went wrong. Please try again.
```

### Purchase unavailable

如果 Apple 购买能力当前不可用，或者 StoreKit 无法正常开始购买：

- 不授予 Premium。
- 不关闭 Subscription Page / Paywall。
- `Subscribe` 恢复可点。
- 不自动重试 Purchase。
- 用户之后主动点击 `Subscribe` 可再次尝试。

反馈文案：

```text
Purchases are unavailable right now. Please try again later.
```

### Transaction Verification Failed / Unverified

只有 verified transaction 才能授予 Premium。如果 Apple 返回 Transaction 但客户端验证失败 / unverified：

- 不授予 Premium。
- 不进入 Subscription Success。
- 不执行 `blocked_action`。
- 不记录成功收入。
- 当前 Page / Paywall 保持。
- `Subscribe` 恢复可用。
- 按 Purchase Failed 处理。

不得因为 Apple 弹窗显示支付完成但本地 Transaction 未验证成功，就直接解锁 Premium。如果后续 Transaction Listener 得到 verified 结果，再按后续 Transaction Success 规则处理。

## 6.6 订阅页打开期间权益已经变 Premium

用户停留 Subscription Page / Paywall 期间，当前设备可能通过 StoreKit Transaction Update 或 entitlement refresh 确认已经变为 Premium。若当前没有正在进行的 Purchase / Restore：

| 当前容器 | 处理 |
| --- | --- |
| Subscription Page | 更新 Premium；自动关闭 Subscription Page；返回 `source_page`；显示 `Premium unlocked`；不再允许用户继续 Subscribe |
| Functional Paywall，`blocked_action` 仍有效 | 更新 Premium；自动关闭 Paywall；显示 `Premium unlocked` Toast；执行 `blocked_action` |
| Functional Paywall，`blocked_action` 已失效 | 更新 Premium；关闭 Paywall；显示 `Premium unlocked` Toast；不执行旧操作 |

## 6.7 App 切后台 / 被杀时的订阅流程

Product Loading / Restore 期间 App 进入后台，允许系统正常处理生命周期。回到前台时，如果原请求上下文已经失效，不恢复旧 Loading，重新按当前页面状态判断。Restore 不得因为 App 重新进入前台重新开始旧 Restore 请求。

Apple Purchase 过程中如果用户切后台，不得自行把 Purchase 判定为 Failed，以后续 StoreKit Transaction 结果为准。

App 被杀 / 重启后，以下临时 UI 状态不跨 App 重启恢复：

- Subscription Success Page
- Paywall
- Restore Loading
- Restore Failed Alert
- 旧 `blocked_action`
- 旧 Product Loading

重新启动后走正常 Startup Entitlement Check。如果已确认 Premium，按 Premium 启动流程进入 App，不重新播放旧 Subscription Success；如果 Free，按正常 Free 冷启动规则处理。

## 6.8 Subscription Exception Matrix

| 场景 | 是否 Premium | UI / 状态 | 是否关闭订阅容器 | 是否自动重试 |
| --- | --- | --- | --- | --- |
| Product Loading Success | 不变 | 正常显示 StoreKit 价格 | 否 | - |
| Product Partial Success | 不变 | 可用 SKU 正常；缺失 SKU 不可购买 | 否 | 15 秒 Deadline 内允许 |
| Product All Failed / Timeout | 不变 | `Unable to connect to the App Store. Please try again.` | 否 | Timeout 后否 |
| Purchase Success + Verified | Premium | 正常成功流程 | 是 | 否 |
| User Cancelled | 不变 | 无错误 Toast | 否 | 否 |
| Purchase Pending | 不变 | `Purchase pending` Toast；当前容器内 Subscribe 暂不可再次提交，Close 仍可离开 | 否 | 等 Transaction Update |
| Purchase Failed | 不变 | `Something went wrong. Please try again.` | 否 | 否 |
| Purchase unavailable | 不变 | `Purchases are unavailable right now. Please try again later.` | 否 | 否 |
| Transaction Unverified | 不变 | 按 Purchase Failed | 否 | 否 |
| Restore Success | Premium | `Premium restored` Toast | 是；Profile 保持 | 否 |
| Restore Not Found | Free | `No subscription found` Toast | 否 | 否 |
| Restore Failed | 不变 | Restore Failed Alert | 否 | 否 |
| Restore Timeout 15s | 不变 | Restore Failed Alert | 否 | 否 |
| External Entitlement → Premium | Premium | `Premium unlocked` | 根据当前容器自动恢复 | - |
| App 重启后发现 Premium | Premium | 按正常 Premium 启动 | 不恢复旧订阅 UI | - |
| Analytics / 后台订单同步失败 | Premium 保持 | 不展示购买失败 | 已按成功流程关闭 | 后台自行处理 |

# 7. Restore Purchase

## 7.1 入口

- Subscription Page
- Subscription Paywall Modal
- Profile

所有用户身份和权益状态均可使用 Restore Purchases：

- 游客
- 账号用户
- Free
- Premium

Restore 是否成功，只根据当前 StoreKit / Apple 购买上下文能够恢复出的有效 Premium entitlement 判断。Restore 不与 App 账号绑定，不根据 App 账号历史 Premium 状态、另一设备 Premium 状态或订单用户唯一标识直接授予 Premium。

## 7.2 Loading 与防重复

用户点击 `Restore Purchases` 后：

1. 立即发起 StoreKit Restore / Sync。
2. 当前 Restore 所在整个页面 / 容器进入阻断式 Loading。
3. 禁止重复创建多个 Restore 请求。
4. Restore 最长 Loading 时间为 15 秒。

不同入口的阻断范围：

| Restore 入口 | Blocking Loading 范围 | Loading 期间不可操作 |
| --- | --- | --- |
| Subscription Page | 整个 Subscription Page；页面内容可以保持可见 | Close、Weekly / Yearly / Lifetime、Subscribe、Restore、Terms、Privacy、页面其他点击控件、Back / 业务返回操作 |
| Subscription Paywall Modal | 整个 Paywall；背景页仍不可操作 | Plans、Subscribe、Restore、Close、Scrim、Terms、Privacy、Paywall 其他控件 |
| Profile | 当前 Profile 页面 / 容器 | Profile 所有业务操作 |

Restore 过程中：

- 不改变当前 Premium 状态。
- 不提前关闭 Subscription Page。
- 不提前关闭 Paywall。
- 不提前执行 `blocked_action`。
- 不进入 Subscription Success。
- 不显示 `Premium unlocked` 或购买成功 Toast。
- 不允许 Subscribe 与 Restore 并发。

Restore 结果返回后结束 Loading，并按 Restore Success / Restore Not Found / Restore Failed 分支处理。15 秒内未得到有效 Restore 结果时，本次 Restore Attempt 结束，Loading 结束，页面恢复可操作，并按 Restore Failed 处理。

## 7.3 Restore 结果统一表

| Restore结果 | UI反馈 | 按钮 | 原 Subscription Page / Paywall | Premium | 后续操作 |
| --- | --- | --- | --- | --- | --- |
| Success | `Premium restored` 信息 Toast | 无 | 自动关闭 | Premium | 返回来源；如存在可执行且仍有效的 `blocked_action`，功能 Paywall 自动执行该 `blocked_action`；如不存在可自动执行的 `blocked_action`，只按来源场景恢复页面状态 |
| Not Found | `No subscription found` 信息 Toast | 无 | 保持打开 | Free | 按最新 verified current entitlements 刷新为 Free；用户继续 Subscribe / Restore / Close |
| Failed | Restore Failed Alert | OK | 保持打开 | 不变 | OK 后返回原容器，可再次 Restore |
| Timeout 15s | Restore Failed Alert | OK | 保持打开 | 不变 | OK 后返回原容器，可再次 Restore；迟到 callback 不得恢复旧交互 |

Profile 场景不关闭或打开订阅容器：

| Restore结果 | Profile 结果 |
| --- | --- |
| Success | 保持 Profile，刷新为 Premium 状态，显示 `Premium restored` Toast |
| Not Found | 保持 Profile，按最新 verified current entitlements 刷新为 Free，显示 `No subscription found` Toast |
| Failed | 保持 Profile，保持原权益状态，显示 Restore Failed Alert，点击 OK 后返回 Profile |
| Timeout 15s | 保持 Profile，保持原权益状态，显示 Restore Failed Alert，点击 OK 后返回 Profile |

## 7.4 Restore Success

Restore 完成后，StoreKit 成功验证到至少一个当前有效 Premium entitlement，即为 Restore Success。

Restore Success 不是新购买成功。

结果：

- Premium 立即生效。
- 更新本地 entitlement cache。
- 刷新当前页面 Premium 状态。
- 不进入 Subscription Success Page。
- 不展示 `You're Premium!`。
- 不展示 `Premium unlocked`。
- 使用 Restore 专属 Toast。

Restore Success Toast：

| 元素 | 规则 |
| --- | --- |
| 结构 | 小型 Success Icon + Title + Description |
| Title | `Premium restored` |
| Description | `Your premium access is ready to use.` |
| 按钮 | 无 |
| Close icon | 无 |
| 展示方式 | 自动消失，不阻断用户后续操作 |
| 时长 | 约 2.5-3 秒 |
| 形态 | Toast，不做 Modal，不做 Full Page |

### Subscription Page → Restore Success

```text
Subscription Page
→ Restore Purchases
→ Loading
→ Restore Success
→ 更新 Premium
→ 自动关闭 Subscription Page
→ 按进入 Subscription Page 时保存的 source_page 返回
→ 在返回后的目标页面展示 Premium restored Toast
```

来源返回规则：

| Subscription Page 来源 | Restore Success 返回 |
| --- | --- |
| 首次启动 Subscription Page | Home + `Premium restored` Toast |
| 后续冷启动 Subscription Page | Home + `Premium restored` Toast |
| Profile Banner | Profile，刷新 Premium 状态 + `Premium restored` Toast |
| Home 顶部入口 | Home，刷新 Premium 状态 + `Premium restored` Toast |
| Search 顶部入口 | Search，刷新 Premium 状态 + `Premium restored` Toast |
| Collection 顶部入口 | Collection，刷新 Premium 状态 + `Premium restored` Toast |
| Profile 顶部入口 | Profile，刷新 Premium 状态 + `Premium restored` Toast |
| Scan Pro Card | Scan，刷新为 Premium / `Unlimited scans` + `Premium restored` Toast；若当前有效 Queue 仍有 Waiting，则 Waiting 按原 Queue 顺序自动进入 Processing；若 Queue 已按 v1.0 退出规则清理，则不恢复旧 Waiting |
| `source_page` 丢失 | Home + `Premium restored` Toast |

### Paywall Modal → Restore Success

功能卡点中的 Restore Success：

```text
Paywall Modal
→ Restore Purchases
→ Loading
→ Restore Success
→ Premium 立即生效
→ 自动关闭 Paywall
→ 返回原页面
→ 显示 Premium restored Toast
→ 如存在购买前保存且仍有效的 blocked_action，则自动执行
```

不需要用户再次点击 Continue。

| Paywall 来源 | Restore Success 后 |
| --- | --- |
| Home Performance Locked | 保持当前 Home、Performance Tab、当前时间范围、滚动位置；自动展示 Home Performance |
| Card Detail Performance | 保持当前 Card、当前 Tab、当前时间范围、滚动位置；自动展示当前 Card 的 Performance |
| Extended Price History | 按 `source_chart` 返回 Home Overview Portfolio Chart 或 Card Detail Price History，并自动选择和展示购买前点击的 1Y 历史范围 |
| Portfolio Folder Limit | 自动继续原 Add Folder 操作；若 v1.0 原流程是打开 Create Folder Modal，则自动打开 Create Folder Modal |
| Scan - 已存在 Waiting Item | 适用于批量扫描额度不足、Waiting Card Body 触发 Paywall、Failed Retry 因 quota = 0 转为 Waiting；继续使用 `blocked_action=resume_waiting_scan`；保留当前 Queue；Waiting 按原 Queue 顺序自动进入 Processing 并提交识别；不要求用户重新拍摄 |
| Scan - quota = 0 且 Capture / Gallery 图片未进入 Queue | 只保存 `source_context=scan_quota_zero`；没有 Waiting Item，也没有可自动执行的扫描 `blocked_action`；Restore Success 后返回 Scan，显示 `Premium restored`，页面进入可扫描状态；用户必须重新点击 Capture 或 Gallery；不得自动打开 Camera / Gallery、创建 Scan Item、提交识别或恢复未入 Queue 的图片 |

### Profile 直接 Restore → Success

Profile 直接点击 Restore Purchases 成功后：

- 保持 Profile 页面。
- 刷新为 Premium 状态。
- 更新 Premium 相关 UI。
- 显示 `Premium restored` Toast。
- 不发生额外页面跳转。

## 7.5 Restore Not Found

Restore 调用正常完成，并已重新读取 current entitlements，但当前 Apple 购买上下文不存在任何有效 Premium entitlement，即为 Restore Not Found。

结果：

- 根据最新 verified current entitlements 将当前最终权益状态更新为 Free。
- 不关闭当前 Subscription Page。
- 不关闭当前 Paywall。
- Profile 保持当前页面。
- 不执行 `blocked_action`。
- 不进入 Subscription Success。

如果用户原来只是因为过期本地缓存暂时显示 Premium，Restore Not Found 后应刷新为 Free。如果仍存在至少一个有效 Premium entitlement，则不属于 Not Found，必须按 Restore Success 处理。

Restore Not Found Toast：

| 元素 | 规则 |
| --- | --- |
| 结构 | Neutral / Info Icon + Title + Description |
| Title | `No subscription found` |
| Description | `We couldn’t find an active purchase to restore.` |
| 按钮 | 无 |
| Close icon | 无 |
| 展示方式 | 自动消失，使用中性提示视觉，不使用强烈 Error 风格 |
| 时长 | 约 2.5-3 秒 |
| 形态 | Toast，不做 Modal |

| 入口 | Not Found 后 |
| --- | --- |
| Subscription Page | Subscription Page 保持打开；显示 `No subscription found` Toast；用户仍可选择 Plan、Subscribe、再次 Restore 或 Close |
| Paywall Modal | Paywall 保持打开；显示 `No subscription found` Toast；用户仍可 Subscribe、再次 Restore 或 Close；`blocked_action` 继续保存但不执行 |
| Profile | 保持 Profile；显示 `No subscription found` Toast；按最新 verified current entitlements 刷新为 Free |

## 7.6 Restore Failed

Restore 因网络异常、StoreKit 异常、系统异常、Restore 请求失败或无法正常完成验证等技术异常失败，即为 Restore Failed。

Restore Failed 与 Restore Not Found 必须严格区分：

- Not Found：请求成功，只是没有有效购买。
- Failed：Restore 请求本身发生异常。

Restore Failed UI 保持当前 UI Prototype 已确认的 Alert / Modal：

| 元素 | 固定内容 |
| --- | --- |
| Title | `Restore failed` |
| Body | `Something went wrong. Please try again later.` |
| CTA | `OK` |

要求：

- 保留 OK 按钮。
- 不增加独立 Retry 按钮。
- 不自动消失。
- 保持原权益状态。

| 入口 | Failed 后 |
| --- | --- |
| Subscription Page | 显示 Restore Failed Alert；点击 OK 关闭 Alert 并返回原 Subscription Page；Subscription Page 保持打开；之后可再次点击 Restore Purchases |
| Paywall Modal | 显示 Restore Failed Alert；点击 OK 关闭 Alert 并回到原 Paywall；Paywall 保持打开；`blocked_action` 继续保存但不执行；之后可再次 Restore、Subscribe 或 Close |
| Profile | 显示 Restore Failed Alert；点击 OK 关闭 Alert 并保持 Profile；保持原权益状态 |

### 7.6.1 Restore Timeout 与迟到结果

Restore 最大 Loading 时间为 15 秒。15 秒未得到有效 Restore 结果时：

1. 当前 Restore Attempt 结束。
2. Loading 结束。
3. 页面 / 容器恢复可操作。
4. 按 Restore Failed 处理，继续使用 `Restore failed` Alert。
5. Premium 不改变。
6. `blocked_action` 不执行。

点击 OK 后：

| 入口 | OK 后 |
| --- | --- |
| Subscription Page | 回 Subscription Page |
| Paywall | 回 Paywall |
| Profile | 回 Profile |

该 Restore Attempt 已经 Timeout 后，迟到的 Restore callback 不得再显示 Restore Success Toast，不得自动关闭原 Subscription Page，不得自动关闭 Paywall，不得执行旧 `blocked_action`，不得强制跳转页面。

如果之后独立的 StoreKit entitlement 监听确认当前设备确实已经存在有效 Premium entitlement，则正常更新 Premium 状态，并按第 6.6 节“订阅页打开期间权益已经变 Premium”或第 2.12.1 节“Premium 使用过程中变为 Free / Premium 状态刷新”处理；不得恢复已经 Timeout 的旧 Restore 交互。

## 7.7 异步 Loading 与防重复点击

所有 v1.1 异步关键控件必须使用同一防重复原则：请求中防止重复提交，不永久禁用页面；所有用户可感知请求遵循第 0.3 节 15 秒上限。Restore 是明确例外：Restore 请求中锁定当前 Restore 所在整个页面 / 容器，而不是只锁定 Restore 控件。

| 控件/动作 | 请求中状态 | 重复点击规则 | 完成结果 | 失败结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- |
| Subscribe | 当前 Subscribe 显示 Loading | 禁止同一 Page/Modal 的 Subscribe 重复提交；不得同时发起多个 Apple Purchase；Purchase 进行中 Restore 不可触发 | Success、Cancelled、Pending、Failed、Purchase unavailable、Transaction Unverified 按第 6.5 节处理；请求结束后控件按结果恢复或跳转 | 恢复可点；停留当前 Page/Modal；保留当前 Product；Product Loading 受 15 秒 Deadline 限制 | 保留选中 Product、`source_page` / `entry_source` 或 `blocked_action` |
| Restore | 整个 Subscription Page / Paywall / Profile 当前容器进入 Blocking Loading | 禁止当前容器所有业务操作；禁止重复 Restore；Restore 进行中 Subscribe 不可触发 | Success、Not Found、Failed、Timeout 按第 7 章处理；请求结束后页面关闭或恢复可操作 | Not Found 后恢复可操作并停留当前 Page/Modal/Profile；Failed 或 Timeout 后 OK 关闭 Alert 并恢复可操作 | Restore Success / Not Found / Failed / Timeout 均不得清空原业务上下文；Timeout 后迟到 callback 不得恢复旧交互 |
| Collection Item 保存 | 保存按钮或表单保存动作显示 Loading | 禁止同一表单重复保存；不禁止用户查看已输入内容；本次保存最长 15 秒 | 保存成功后按 v1.0 返回目标，并在 Card Detail Performance 来源场景刷新 Performance | 保存失败或 Timeout 后恢复可点，保留输入内容，使用 v1.0 错误反馈或通用 Timeout Toast | 保留当前表单、`card_id`、`collection_item_id` 和来源 Tab；写操作需避免重复保存 |
| Scan 提交 / Capture / Gallery Submit | 当前提交动作显示处理中；进入 Queue 的项展示 Processing 或 Waiting | 同一图片或同一提交动作不得重复创建多个扫描项；用户可继续添加新的独立扫描项时沿用 v1.0 多项并行规则 | 成功发送进入 Processing；识别结果按 Queue 状态更新 | 请求未发送、上传失败、网络异常或超时时恢复可操作并按第 9.5 节返还或不消耗额度；识别 Timeout 使用 Scan Failed 状态 | 保留 Queue、图片、顺序、剩余额度和滚动位置；迟到结果不得重插已删除或已 Failed 的旧项 |
| Performance Range 数据切换 | 当前 Range 控件或图表区域展示 Loading | 同一 Range 请求未完成前禁止重复请求同一 Range；允许取消旧请求或忽略旧返回以最后一次用户选择为准；本次切换最长 15 秒 | 成功后更新 Selected Range、图表、指标并关闭旧 Tooltip | 失败或 Timeout 后恢复可点，不自动切换到失败 Range，不生成虚假数据；Timeout 进入 Network / Service Error | 保留当前页面、点击前有效 Range、旧图表或错误状态、Tab 和滚动位置；迟到旧 Range 不得覆盖新 Range |

# 8. Premium 入口与限制

## 8.1 一级页面顶部入口

以下一级页面顶部显示订阅小标识：

- Home
- Search
- Collection
- Profile

Scan 页面是一级页面例外：不展示顶部 Premium Crown / Subscription Icon。Scan 页面使用 Pro / scans remaining 状态卡片承接主动订阅入口。

规则：

- Free 状态用户显示。
- Premium 状态用户隐藏升级入口。
- 上述 Home / Search / Collection / Profile 顶部入口点击后进入完整 Subscription Page，并保存 `source_page` / `entry_source`。

### 8.1.1 页面交互与控件规则

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Home 顶部 Premium 入口 | Home 一级页面；Free 状态 | 当前无 Subscription Page 打开中 | 记录 `source_page=Home`、`entry_source=top_subscription_entry`；打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 后进入 Subscription Success，Start Exploring 后进入 Home Premium；Restore Success 后关闭 Subscription Page，返回 Home Premium 并显示 `Premium restored` Toast | Close、Cancelled、Pending、Failed、Restore Not Found/Failed 后按第 3.6 节留在或回到 Home Free；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留 Home 的 Overview/Performance Tab、Performance Range、Tooltip、滚动位置和已加载数据 |
| Search 顶部 Premium 入口 | Search 一级页面；Free 状态 | 当前无 Subscription Page 打开中 | 记录 `source_page=Search`、`entry_source=top_subscription_entry`；打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 后进入 Subscription Success，Start Exploring 后进入 Search Premium；Restore Success 后关闭 Subscription Page，返回 Search Premium 并显示 `Premium restored` Toast | Close、Cancelled、Pending、Failed、Restore Not Found/Failed 后按第 3.6 节留在或回到 Search Free；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留 Search 当前输入、筛选状态、滚动位置和已加载数据 |
| Scan 顶部 Premium Crown / Subscription Icon | Scan 一级页面；任意权益状态；该入口不展示 | - | 不显示，用户无法点击 | - | - | - | Scan 的主动订阅入口由 Pro / scans remaining 状态卡片承担 |
| Collection 顶部 Premium 入口 | Collection 一级页面；Free 状态 | 当前无 Subscription Page 打开中 | 记录 `source_page=Collection`、`entry_source=top_subscription_entry`；打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 后进入 Subscription Success，Start Exploring 后进入 Collection Premium；Restore Success 后关闭 Subscription Page，返回 Collection Premium 并显示 `Premium restored` Toast | Close、Cancelled、Pending、Failed、Restore Not Found/Failed 后按第 3.6 节留在或回到 Collection Free；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留 Portfolio/Wishlist Tab、Folder Sheet 状态、当前 Folder、搜索输入、滚动位置和已加载数据 |
| Profile 顶部 Premium 入口 | Profile 一级页面；Free 状态 | 当前无 Subscription Page 打开中 | 记录 `source_page=Profile`、`entry_source=top_subscription_entry`；打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 后进入 Subscription Success，Start Exploring 后进入 Profile Premium；Restore Success 后关闭 Subscription Page，返回 Profile Premium 并显示 `Premium restored` Toast | Close、Cancelled、Pending、Failed、Restore Not Found/Failed 后按第 3.6 节留在或回到 Profile Free；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留 Profile 当前滚动位置和已加载账号数据 |
| Premium 状态顶部 Premium 入口 | 任一一级页面；Premium 状态 | - | 不显示，用户无法点击 | - | - | - | - |

## 8.2 二级页面

所有二级页面顶部均不显示订阅小标识，包括但不限于：

- Card Detail
- Collection Item 编辑页
- Search Result Detail
- Folder 二级页
- 其他详情页

二级页面内的锁定功能通过锁定区域或 Unlock CTA打开 Paywall。

## 8.3 Profile Subscription Banner

- Free 状态：显示升级 Banner；用户点击 Banner 或 `Upgrade Now` 后记录 `source_page=Profile`、`entry_source=profile_banner`，打开完整 Subscription Page。
- Premium 状态：不显示升级 Banner，展示 Premium 状态。
- 不增加 SKU 切换、续期日期或订阅管理入口。

## 8.4 Wishlist

Wishlist 不属于 Premium 权益。Free 与 Premium 状态均可正常使用 Wishlist，完整页面、数据和交互保持 v1.0 规则不变，不新增锁定入口或 Paywall。

## 8.5 Portfolio Folder 限制

- Free 状态最多 2 个 Portfolio Folder（总数），包含默认 Folder。
- Free 首次已有 1 个默认 Folder 时，最多额外创建 1 个 Folder；总数达到 2 后再次 Add Folder 打开 Paywall。
- Premium 状态 Folder 数量不限。
- 达到上限后点击新增 Folder，打开 Paywall且不创建 Folder。
- Premium 到期不删除已有 Folder。
- Premium 到期或权益变 Free 后，已经超过 Free 限制时仍可查看、切换、编辑、删除已有 Folder，但不能继续新增。
- 当 Folder 总数重新低于 2 时，Free 可再次创建，直到总数达到 2。

除本节明确修改的内容外，Folder 的基础流程保持 v1.0 规则不变。

### 8.5.1 页面交互与控件规则

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Add Folder / Add New Folder | Collection 的 Folder Bottom Sheet 已打开 | Premium 状态，或 Free 状态且 Folder 总数少于 2 | 沿用 v1.0 Add Folder 点击结果；如果 v1.0 结果为打开 Create Folder 弹窗，则打开该弹窗 | v1.0 Create Folder 弹窗或已有 Folder 创建容器 | 保存成功后创建 Folder，刷新 Folder 列表并选中或展示 v1.0 定义的目标 Folder | 保存失败时保留输入内容，不创建 Folder，展示 v1.0 已有错误反馈 | 保留 Collection 的 Portfolio/Wishlist Tab、搜索输入、滚动位置和 Folder Sheet 来源 |
| Add Folder / Add New Folder（Free Folder 总数已达 2） | Collection 的 Folder Bottom Sheet 已打开；Free 状态；Folder 总数 = 2，默认 Folder 计入总数 | 可点 | 不创建 Folder；保存 `blocked_action=create_folder` 及当前 Folder Sheet 来源；打开 Subscription Paywall Modal | Subscription Paywall Modal | Purchase Success：关闭 Paywall，显示 `Premium unlocked` Toast，自动打开 v1.0 Create Folder 弹窗；Restore Success：关闭 Paywall，刷新 Premium，显示 `Premium restored` Toast，自动打开 v1.0 Create Folder 弹窗 | Close/Scrim/Cancelled/Failed/Pending/Restore Not Found/Restore Failed：关闭或停留 Paywall 后不创建 Folder，不打开 Create Folder 弹窗；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留 Collection 当前 Tab、当前 Folder、Folder Sheet 来源、搜索输入、滚动位置和已加载列表；Restore Not Found / Failed 不清空 `blocked_action` |

### 8.5.2 Free Folder 多设备并发创建

Free 最多 2 个 Folder，账号数据又支持多设备同步。因此创建 Folder 时不能只依赖客户端当前显示数量，服务端创建前必须再次检查当前账号 Folder 数量。

示例：

```text
当前只有默认 Folder，共 1 个
设备 A 与设备 B 同时 Add Folder

其中一个成功：
总数 → 2

另一个请求到服务端：
→ 最新总数已达 2
→ 创建失败
→ 不创建第 3 个 Folder
→ 刷新当前 Folder List
→ 按最新 Free 限制状态显示
```

不得出现 Free 账号因为多设备并发拥有 3 个新建 Folder。

### 8.5.3 Collection Item Folder Move 交互与异常

Collection Item 跨 Folder 移动的历史归属规则沿用第 14 章已定义的 Folder Move 历史归属规则：全部可可靠还原的 Performance 历史随 Collection Item 整体迁移到目标 Folder。本节只定义 Move 操作的交互和异常。

用户确认 Move：

```text
Confirm Move
→ Move Loading
→ 最长 15 秒
→ 防止重复提交
```

Move 结果必须保持原子性，不得出现 Source 已删除 Item 但 Target 没有加入、Target 加入但 Source 仍重复存在、Performance 历史只迁移一半等半迁移状态。

| Move 结果 | 处理 |
| --- | --- |
| Success | Collection Item 归属 Target Folder；完整可可靠还原历史归属 Target Folder；Source Folder 立即重新计算；Target Folder 立即重新计算；当前 Portfolio / Folder List 刷新；当前 Home Performance 如果受影响则刷新 |
| Failed / Timeout | Item 继续属于原 Source Folder；不进行部分迁移；Performance 归属保持原状态；页面恢复可操作；使用现有错误反馈 / Timeout 规则 |
| Target Folder 已失效 | 服务端 Move 失败；不移动 Collection Item；刷新 Folder List；Item 继续保持有效 Source Folder 归属 |
| Source Folder 也已失效 | 按现有远端 Folder 删除规则处理，回默认 Folder / 最新有效状态；不得自行恢复已删除 Folder |

Move Success 后不得等待第二天才显示移动结果。Move Failed / Timeout 的迟到旧请求仍按第 0.3 节 request context + 幂等规则处理，不得造成重复 Move。

# 9. Scan 免费额度

基础 Scan 页面、识别状态、Review 和添加资产流程保持 v1.0 不变。v1.1 只新增额度、Paywall 和额度结算规则。

## 9.1 权益规则

Premium 与 Scan 免费额度是两个独立状态系统：

- Premium：按当前设备 Apple-verified entitlement state 判断。
- Free Scan Quota：账号用户按 App 账号归属并跨设备共享；游客按游客身份独立。

### Free 状态

- 最多 10 次扫描额度。
- 页面展示剩余额度。
- 额度归零后显示：

```text
0 scans remaining
```

Scan 页面不展示顶部 Premium Crown / Subscription Icon。Free 状态使用独立 Premium 状态卡片作为主动订阅入口，卡片展示：

```text
Pro
X scans remaining
Tap to get unlimited scans
```

该卡片同时承担免费扫描额度展示、Premium 权益提示和 Scan 页面主动订阅入口。

### Premium 状态

- 展示：

```text
Unlimited scans
```

- 不受 Free 额度限制。
- Premium 期间不消耗当前账号用户或当前游客身份的 Free Scan Quota。

### 账号用户额度归属

每个账号用户终身 10 次免费扫描。同一账号用户在多个设备登录时，使用同一份累计额度。

示例：

```text
账号用户 A 终身免费额度 = 10
设备 A 使用 3 次
设备 B 登录账号用户 A
设备 B 剩余 7 次
```

换设备不得重新获得 10 次。后端 / 账号数据负责保持已登录账号 Scan 额度一致。

### 账号用户多设备 Scan Quota 并发

账号用户的 Free Scan Quota 跨设备共享，因此服务端必须作为最终额度真值。多设备同时发起 Free Scan 时：

1. 服务端原子判断并预占额度。
2. 同一份剩余额度不得被多个设备重复占用。
3. Remaining 不得小于 0。
4. 客户端本地剩余额度不得覆盖服务端最新额度。

示例：

```text
账号用户 A
Remaining = 1

设备 A 和设备 B 同时发起 Scan

设备 A 先成功预占：
Remaining 1 → 0
设备 A → 正常提交 → Processing

设备 B：
服务端确认 Remaining = 0
→ 不提交识别请求
→ 不扣额度
→ 按现有 quota = 0 规则进入 Subscription Paywall
```

不得出现：

- 两台设备同时消费最后 1 次额度。
- Remaining = -1。
- 客户端本地剩余额度覆盖服务端最新额度。

每个 Scan 提交应有唯一请求标识用于额度预占与结算幂等，避免网络重试或重复回调造成重复扣减。技术实现方式由开发决定，但产品结果必须满足：同一张扫描请求最多结算一次，同一份 Free Quota 最多消费一次。

### 游客额度归属

每个游客身份独立终身 10 次。由于游客不做账号级多设备同步，不同设备的游客额度不要求互通。

卸载重装不额外为了恢复游客额度实现强设备唯一识别方案，继续沿用已确认规则。

### Premium 与额度分离示例

```text
账号用户 A 剩余 6 次免费扫描

设备 A：StoreKit 有 Premium → Premium → 不消耗 6 次 Free 额度
设备 B：StoreKit 无 Premium → Free → 使用账号用户 A 共享的 6 次额度
设备 B 扫描 1 次成功 → 账号用户 A 剩余 5 次
设备 A 之后 Premium 到期 → Free → 账号用户 A 剩余仍为 5 次
```

### 9.1.1 Scan Pro 卡片交互

Scan Pro 卡片是用户在 Scan 页面主动进入完整 Subscription Page 的入口。它不同于 Free quota = 0 后由 Capture 或 Waiting 触发的功能卡点 Paywall。

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Pro / scans remaining 卡片 | Scan 页面；Free 状态；展示 `Pro`、`X scans remaining`、`Tap to get unlimited scans` | 当前无 Subscription Page 或 Paywall 打开中 | 记录 `source_page=Scan`、`entry_source=scan_pro_card`；打开完整 Subscription Page；不创建 Waiting；不发送识别请求；不执行 `blocked_action` | Subscription Page Full Page | Purchase Success：进入 Subscription Success；点击 Start Exploring 后返回 Scan，刷新为 Premium / `Unlimited scans`，如果当前有效 Queue 仍有 Waiting，则 Waiting 按原 Queue 顺序自动进入 Processing；Restore Success：关闭 Subscription Page，返回 Scan，刷新 Premium / `Unlimited scans`，显示 `Premium restored` Toast，如果当前有效 Queue 仍有 Waiting，则 Waiting 按原 Queue 顺序自动进入 Processing | Close、Cancelled、Pending、Failed、Restore Not Found/Restore Failed：返回或停留 Scan Free，保留原剩余额度与 Queue；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK；不自动提交新扫描 | 保留 Scan Queue、相机/相册状态、滚动位置、剩余额度展示；如果用户已确认退出 Scan 并按 v1.0 清理 Queue，则不恢复已清除的 Waiting，不重新创建旧 Queue |
| Pro / scans remaining 卡片 | Scan 页面；Premium 状态 | - | 不显示 Free 态卡片，用户无法点击 | - | - | - | Scan 页面展示 Premium / `Unlimited scans` 状态 |

## 9.2 Scan Queue 状态

Scan Queue 状态统一为：

| 状态 | UI 文案 | 定义 | 是否已发送识别请求 | 是否消耗额度 | 是否进入 Review Your Matches |
| --- | --- | --- | --- | --- | --- |
| Waiting | `Waiting to scan` | 已进入 Queue，但因 Free 额度不足尚未提交 | 否 | 否 | 否 |
| Processing | `Processing` | 识别请求已提交，等待处理结果 | 是 | 已预占，按结果结算 | 否 |
| Matched | `Matched` | 请求完成且识别成功 | 是 | 是 | 是 |
| Failed | `Failed` | 请求已提交但识别或技术处理失败 | 是 | 否或返还预占额度 | 否 |
| No Match Found | `No Match Found` | 请求完成但未识别到匹配卡牌 | 是 | 是 | 否 |

Waiting 是尚未提交请求的 Queue 状态，不是识别结果状态。Waiting 不属于 Processing、Matched、Failed 或 No Match Found，不允许按识别失败逻辑 Retry。小卡片只有单行状态时只展示 `Waiting to scan`，不增加长说明。

No Match Found 不进入 Review Your Matches，不参与 Done 带入，沿用 v1.0 Search Manually / Delete 流程。No Match Found 成功完成识别后仍按现有规则消耗 1 次 Free Scan 额度。

Scan Queue 最大待处理数量沿用 v1.0 的 10 张上限。Waiting 属于 Queue Item，因此 Waiting、Processing、Matched、Failed、No Match Found 只要仍存在于待处理 Queue 中，均占用 1 个 Queue 位置。不得因为 Waiting 尚未发送请求而突破 10 张上限。

### Done Enabled

`Done` 是否可点击只判断：

```text
Matched Item Count > 0
AND
Processing Item Count = 0
```

Waiting 不参与 Done Enabled / Disabled 判断。Failed 不参与 Done 禁用判断。No Match Found 不参与 Done 禁用判断。

| Queue状态 | Done |
| --- | --- |
| Only Waiting | Disabled |
| Only Failed | Disabled |
| Only No Match Found | Disabled |
| Waiting + Failed | Disabled |
| Waiting + No Match Found | Disabled |
| Matched | Enabled |
| Matched + Waiting | Enabled |
| Matched + Failed | Enabled |
| Matched + No Match Found | Enabled |
| Matched + Waiting + Failed + No Match Found | Enabled |
| 任意组合中存在 Processing | Disabled |

核心原则：Waiting 本身不能导致 Done Disabled。只有没有任何 Matched，或仍存在 Processing，才导致 Done 不可点击。

### 9.2.1 Scan 页面交互与控件规则

v1.1 统一使用上方 Done Enabled 公式。Processing 是唯一会因为“扫描仍未完成”而阻止 Done 的 Queue 状态。Waiting 可以继续留在 Scan Queue 中等待后续处理，不是 Review 的前置阻塞条件。

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Done | Scan 页面已打开 | Queue 中至少 1 张 Matched，且不存在 Processing | 沿用 v1.0：1 张 Matched 进入单张 Review；2 张及以上 Matched 进入多张 Review；Failed 和 No Match Found 不进入 Add all cards；Waiting 不进入 Review | Review Your Matches + Collection Item | 仅 Matched 项进入 Review；进入 Review 前不自动保存 Portfolio；Review 完成后已收藏的 Matched 项从待处理 Scan Queue 移除 | 如果进入 Review 失败，停留 Scan 并保留 Queue | Waiting、Failed、No Match Found 继续按现有规则保留或处理；Waiting 不删除、不变成 Failed、不消耗额度，并保持原 Queue 顺序 |
| Done（无 Matched） | Queue 中不存在 Matched；可存在 Waiting、Failed 或 No Match Found | 不可点击 | 无操作 | 当前 Scan 页面 | - | - | 保留完整 Queue |
| Done（存在 Processing） | Queue 中存在 Processing；可同时存在 Matched、Waiting、Failed 或 No Match Found | 不可点击 | 无操作 | 当前 Scan 页面 | Processing 结束后重新计算 Done Enabled；若存在至少 1 张 Matched，则 Done 可点击 | - | 保留完整 Queue |
| Waiting Card Body | Queue 中存在因 Free 额度不足尚未提交的扫描项；点击区域为非删除区域 | 不可进入 Review；不允许 Tap to Retry；不发识别请求；不扣扫描额度 | 打开 Subscription Paywall Modal；保存 `blocked_action=resume_waiting_scan`；这是功能卡点 Paywall，不进入完整 Subscription Page | Subscription Paywall Modal | Purchase Success：更新 Premium，关闭 Paywall，显示 `Premium unlocked` Toast，Waiting 按原 Queue 顺序进入 Processing 并自动继续扫描；Restore Success：更新 Premium，关闭 Paywall，显示 `Premium restored` Toast，Waiting 按原 Queue 顺序进入 Processing 并自动继续扫描 | Paywall Close：返回原 Scan 页面，Waiting 保持；Purchase Cancelled/Pending/Failed：Waiting 保持且不得变成 Failed；Restore Not Found：Paywall 保持并显示 `No subscription found` Toast，Waiting 保持；Restore Failed：显示 Restore Failed Alert，OK 后回到 Paywall，Waiting 保持 | 保留当前 Scan Queue、当前 Waiting Items、当前滚动位置、Queue 顺序、已有 Matched / Failed / No Match Found 状态和 `blocked_action` |
| Waiting Card Delete / Remove | Queue 中存在因 Free 额度不足尚未提交的扫描项；点击区域为 Waiting 卡片上的 Delete / Remove 按钮 | 删除操作沿用现有 Queue Item 删除能力；Delete / Remove 点击优先级高于 Card Body 点击 | 只删除当前 Waiting Item；必须阻止事件向 Card Body 冒泡；不得同时打开 Subscription Paywall Modal；不发识别请求；不扣扫描额度 | 当前 Scan Queue | 该 Waiting Item 从 Queue 移除 | 删除失败时按现有 Queue Item 删除失败反馈处理；其他 Queue Item 状态不变 | 不消耗 Scan 额度；其他 Queue Item、Queue 顺序、已有 Matched / Failed / No Match Found 状态保持不变 |
| Capture / Gallery Submit | Scan 页面可提交新扫描项 | Premium 状态，或 Free 状态且剩余额度大于 0 | 创建扫描项并提交识别请求；Free 状态预占 1 次额度；Premium 状态不消耗 Free quota | 当前 Scan Queue | 新扫描项进入 Processing；识别后按 v1.0 进入 Matched/Failed/No Match Found | 请求发送前失败或上传失败时不消耗额度或返还预占额度；失败项按 v1.0 Failed 规则展示 | 保留已有 Queue、相机/相册来源和滚动位置 |
| Capture / Gallery Submit（Free quota = 0） | Scan 页面可提交新扫描项；Free 状态；点击前剩余额度已经为 0 | 可点 | 直接打开 Subscription Paywall Modal；不创建新的 Waiting Item；不创建 Scan Item；不向 Queue 新增本次图片；不发送识别请求；不扣额度；只保存 `source_context=scan_quota_zero` 等来源上下文，不保存可自动执行扫描的 `blocked_action` | Subscription Paywall Modal | Purchase Success：关闭 Paywall，显示 `Premium unlocked` Toast，返回 Scan，页面进入可扫描状态；Restore Success：关闭 Paywall，显示 `Premium restored` Toast，返回 Scan；用户需要重新点击 Capture 或 Gallery | 未获得 Premium 时按第 5.7 节统一规则处理；不创建 Waiting，不自动提交 | 保留打开 Paywall 前已有 Scan Queue、滚动位置和相机/相册来源；不得自动打开相机 / Gallery，不得伪造一张未进入 Queue 的 Waiting 图片 |
| Capture / Gallery Submit（Queue 已满） | 当前待处理 Queue 中 Waiting / Processing / Matched / Failed / No Match Found 合计 = 10 | 不可新增第 11 张 | Capture 不创建新 Item，不发送请求；Gallery 不允许新增超过剩余 Queue 容量的图片 | 当前 Scan 页面 | 使用当前 App 轻量提示样式说明本批 Queue 已满 | - | 保留现有 Queue、顺序、状态和滚动位置 |
| Failed Retry | Queue 中存在 Failed Item | Premium，或 Free 状态按服务端确认可重新预占额度 | 沿用 v1.0 Retry 入口；Premium 不消耗 Free Quota；Free + Remaining > 0 时服务端重新原子预占 1 次；Free + Remaining = 0 时不发送请求，当前 Failed Item 转为 `Waiting to scan` 并打开 Paywall | 当前 Scan Queue 或 Subscription Paywall Modal | 预占成功后 Failed → Processing；Free quota = 0 且 Purchase / Restore 成功后 Waiting → Processing | 预占失败或服务端确认 Remaining = 0 时刷新为 `0 scans remaining` 并按 quota = 0 逻辑处理 | 保留原图片；用户不用重新拍摄；Retry 必须重新判断额度 |
| Processing Delete / Remove | v1.0 已支持删除 Processing Item；请求已成功发送 | 删除操作可用 | UI 立即移除该 Queue Item；标记该 Item 已被用户删除；不立即返还 Free Quota；后台仍完成本次 Request 最终额度结算 | 当前 Scan Queue | Matched / No Match Found 最终消耗 1 次；技术 Failed / Timeout / Service Error 最终返还预占额度 | 迟到识别结果不得把已删除卡片重新插回 Scan Queue | 保留其他 Queue Item 状态；已删除 Item 不重新出现 |

Waiting Card 存在两个点击区域：

| 点击区域 | 结果 |
| --- | --- |
| Card Body | 打开 Subscription Paywall Modal，保存 `blocked_action=resume_waiting_scan` |
| Delete / Remove Button | 删除当前 Waiting Item，不打开 Paywall |

Delete / Remove 事件必须阻止向 Card Body 冒泡，避免用户点击删除时同时打开 Paywall。Waiting Card Body 打开的 Paywall 是功能卡点 Paywall，不是完整 Subscription Page。

## 9.3 单张 Capture

- 可用额度大于 0：提交当前卡牌，预占 1 次额度。
- 点击前可用额度已经为 0：直接打开 Subscription Paywall Modal。
- quota = 0 的单张 Capture / Gallery Submit 不创建新的 Waiting Item，不向 Queue 新增本次图片，不发送识别请求，不扣额度。
- 打开 Paywall 时只保存 `source_context=scan_quota_zero` 等来源上下文，并保留打开前已有 Scan Queue；不得保存可自动执行 Capture / Gallery 的扫描 `blocked_action`。
- Purchase 或 Restore 成功获得 Premium 后关闭 Paywall 并返回 Scan；页面进入可扫描状态，用户重新点击 Capture 或 Gallery。
- 不得自动打开相机、自动打开 Gallery、自动创建 Scan Item、自动提交识别或自动恢复一张从未进入 Queue 的图片。

## 9.4 批量额度不足

示例：Free Remaining = 2，Scan Queue 有 4 张卡。

1. 按 Queue 顺序提交 Card A、Card B。
2. Card A、Card B 分别预占额度并进入 Processing。
3. Card C、Card D 不发送识别请求，状态为 Waiting。
4. Card C、Card D 继续保留在 Queue，不得删除或丢失。
5. 可用额度显示 `0 scans remaining`。
6. 自动打开 Subscription Paywall Modal。
7. 用户关闭 Paywall 后，Card C、Card D 继续保持 Waiting。
8. Purchase Cancelled、Failed、Pending 后，Waiting 状态保持不变。
9. Restore Not Found 或 Failed 后，Waiting 状态保持不变。
10. Purchase 成功后关闭 Paywall、显示 `Premium unlocked`；Restore 成功后关闭 Paywall、显示 `Premium restored`；Purchase 或 Restore 成功获得 Premium 后，Card C、Card D 按原 Queue 顺序从 Waiting 自动进入 Processing 并提交请求。

### 9.4.1 Matched + Waiting 示例

示例：Free Remaining = 2，Scan Queue 有 4 张卡。

1. Card A = Matched。
2. Card B = Matched。
3. Card C = Waiting。
4. Card D = Waiting。
5. 当前 Processing Count = 0，Matched Count = 2。
6. `Done` = Enabled。

用户无需购买 Premium、删除 Waiting 或等待 Waiting 完成，即可先处理已经 Matched 的 Card A / Card B。

点击 `Done` 后进入 Review Your Matches。Review 中只带入 Card A / Card B。Card C / Card D 不进入 Review、不被删除、不变成 Failed、不消耗额度，继续保留在原 Scan Queue，状态继续为 Waiting。

如果 Review 中 Card A / Card B 成功完成收藏，Card A / Card B 从待处理 Scan Queue 中移除。返回 Scan 后，Card C / Card D 仍然存在、仍然为 Waiting，并保持原 Queue 顺序。

## 9.5 额度预占与逐张结算

采用“提交时预占、结果返回后按单张结算”的规则。

每个 Scan 提交必须具备唯一请求标识，用于额度预占、结果结算、网络重试和重复回调的幂等处理。同一张扫描请求最多结算一次，同一份 Free Scan Quota 最多消费一次。

| 单张结果 | 额度规则 |
| --- | --- |
| Waiting | 不消耗，不预占 |
| 用户在请求发送前取消 | 不消耗 |
| 请求未成功发送 | 不消耗 |
| 上传失败 | 不消耗或返还预占额度 |
| 网络异常 | 不消耗或返还预占额度 |
| 请求超时 | 不消耗或返还预占额度 |
| 服务异常 | 不消耗或返还预占额度 |
| Failed | 不消耗或返还预占额度 |
| Matched | 消耗 1 次 |
| No Match Found | 消耗 1 次 |
| No Match 后进入 Manual Search | 不额外消耗 |

批量扫描逐张结算，不得整批统一扣除或返还。

### 9.5.1 额度返还后的 Waiting 自动递补

Free 状态下，如果某个 Processing Item 因 Failed、Upload Failure、Network Error、Timeout 或 Service Error 导致预占的 Free Scan Quota 被返还，且当前 Queue 中仍存在 Waiting，则按原 Queue 顺序从最前 Waiting 开始重新尝试额度预占。

预占成功后：

```text
Waiting → Processing
→ 自动提交识别
```

持续到 Free Remaining 再次变为 0，或 Queue 中不存在 Waiting。

示例：

```text
Remaining = 2

A → Processing
B → Processing
C → Waiting

A → Matched
B → Failed，返还 1 次

Remaining 恢复 1
→ C 自动预占 1 次
→ C Waiting → Processing
```

不要求用户点击 C。

### 9.5.2 Failed Retry 与额度

Failed Item 沿用 v1.0 Retry 交互，但 v1.1 补充额度规则：

| 用户状态 | Retry 结果 |
| --- | --- |
| Premium | 不消耗 Free Quota；Failed → Processing |
| Free + Remaining > 0 | 服务端重新原子预占 1 次；成功后 Failed → Processing |
| Free + Remaining = 0 | 不发送识别请求；当前 Failed Item 转为 `Waiting to scan`；打开 Subscription Paywall Modal；保存 `blocked_action=resume_waiting_scan` |

Free + Remaining = 0 时，用户不用重新拍摄图片。Purchase / Restore 成功后，该 Waiting Item 按原 Queue 顺序进入 Processing。

### 9.5.3 Processing 删除后的 Quota 处理

如果 v1.0 允许用户删除 Processing Item，且识别请求已经成功发送：

1. 用户删除 Processing 卡片后，UI 立即移除该 Queue Item。
2. 标记该 Item 已被用户删除。
3. 不得立即返还 Free Quota，原因是识别请求已经真实提交。
4. 后台仍完成本次 Request 最终额度结算。
5. 从 UI Queue 删除成功后，该 Item 立即不再计入 `Processing Item Count`，并立即按当前可见 Queue 重新计算 `Done Enabled`。

示例：

```text
删除前：
Matched = 2
Processing = 1
Done = Disabled

删除 Processing Item 后：
Matched = 2
Processing = 0
Done = Enabled
```

后台仍在等待该删除 Item 的 Quota 最终结算时，不得继续阻塞 Done；后台结算只影响 Free Scan Quota，不影响已经从当前 UI Queue 删除的 Item 状态。

最终结算：

| 迟到结果 | Quota |
| --- | --- |
| Matched | 消耗 1 次 |
| No Match Found | 消耗 1 次 |
| 技术 Failed / Timeout / Service Error | 返还预占额度 |

迟到识别结果不得把已经删除的卡片重新插回 Scan Queue。

## 9.6 Queue 保留

- 额度不足打开 Paywall时不清空 Queue。
- 用户主动关闭 Paywall时不清空 Queue。
- Purchase Cancelled、Pending、Failed 不清空 Queue，Waiting 状态不变。
- Restore Not Found 或 Failed 不清空 Queue，Waiting 状态不变。
- 只要当前 Scan Queue 仍然有效，且用户在当前 Scan 流程中成功获得 Premium，已有 Waiting Items 均按原 Queue 顺序自动进入 Processing。
- 上述规则适用于 Waiting Card → Paywall、批量额度不足 → Paywall、Scan Pro / scans remaining Card → Full Subscription Page 的 Purchase Success 或 Restore Success。
- 如果用户已经确认退出 Scan 并按 v1.0 规则清理 Queue，不恢复已经被清除的 Waiting，也不重新创建旧 Queue。
- Waiting 不参与 Review Your Matches，也不计入扫描额度消耗。
- Waiting 计入 Scan Queue 最大 10 张上限。
- Waiting 本身没有识别 Request Timer，停留多久都不得因为 15 秒规则自动变成 Failed。15 秒识别 Timeout 从 Waiting → Processing 且识别请求真正发送成功之后开始计算。

## 9.6.1 Scan Queue 达到 10 张

当前 Queue 最大待处理数量为 10 张。

```text
remaining_queue_capacity = 10 - current_queue_count
```

当 `current_queue_count = 10`：

- 用户点击 Capture：不创建第 11 个 Item，不发送请求。
- 用户打开 Gallery：不允许新增超过剩余 Queue 容量的图片。
- `remaining_queue_capacity = 0` 时，不允许新增扫描项，并使用当前 App 轻量提示样式说明本批 Queue 已满。

不得因为 Waiting 尚未发送请求而突破 10 张上限。

## 9.6.2 Scan Quota 刷新时机

账号用户 Scan Quota 以服务端为最终真值，至少在以下场景刷新：

- 进入 Scan。
- 登录成功。
- 切换账号用户成功。
- App 从后台回前台。
- Scan 额度预占完成。
- Scan 额度结算完成。
- Scan Failed 返还 Quota 完成。
- 多设备服务端返回 Quota 冲突。

如果客户端显示 `Remaining = 1`，但服务端已经是 0，提交时服务端拒绝预占：

```text
→ 不发送识别
→ 客户端立即刷新为 0 scans remaining
→ 按 quota = 0 逻辑处理
```

不得使用旧本地 Quota 强行提交。

## 9.7 Waiting 存在时退出 Scan

Waiting 属于未处理 Queue Item。当 Queue 中仍存在 Waiting，用户主动退出当前 Scan 流程时，沿用 v1.0“存在未完成 / 未收藏扫描内容时退出确认”交互：

```text
Scan
→ 用户点击 Close / Exit
→ Queue 存在 Waiting
→ 弹出 v1.0 已有退出确认
```

规则：

1. 用户取消退出时，保持 Scan，Waiting 继续保留。
2. 用户确认退出时，按 v1.0 退出 Scan 规则清理本次未完成 Queue，Waiting 随本次未完成 Queue 一起清除。
3. 清除 Waiting 不扣 Scan 额度。
4. 不得因为 Waiting 存在而禁止退出。
5. 不为 Waiting 单独新增第二套退出弹窗。

## 9.8 已结算额度与后续删除

Matched 识别成功并完成 Scan 额度结算，或 No Match Found 已经完成额度结算后，用户未来删除 Portfolio Item、Scan 记录或 Collection Item，均不得返还已经消耗的 Free Scan Quota。

Scan Quota 衡量已经完成的扫描机会，不是当前 Portfolio 资产数量。

# 10. Performance Feature

本章只定义 v1.1 新增的 Performance 图表。v1.0 普通历史图表除第 0.3.8 节统一 Chart Range Selector 与第 13.3 节 Extended Price History 权限规则外，其余数据定义、价格计算、图表样式与 Tooltip 规则保持不变。

## 10.1 统一时间范围

所有 v1.1 Performance 时间范围与第 0.3.8 节 App 全局图表 Range 规则保持一致，统一为：

- 1D
- 7D
- 15D
- 1M
- 3M
- 1Y

默认 Range 为 1M。

所有 v1.1 Performance 统一使用业务自然日，业务时区与日切继续沿用 v1.0。不得使用小时级滚动窗口；新增 1D 不新增小时级数据需求，当前历史数据仍沿用现有日节点模型。

| Range | 边界规则 |
| --- | --- |
| 1D | 当前业务自然日 |
| 7D | 包含今天在内最近 7 个业务自然日，即 Today + 前 6 日 |
| 15D | 包含今天在内最近 15 个业务自然日，即 Today + 前 14 日 |
| 1M | 当前业务日期向前 1 个自然月至当前业务日期，不是固定 30 天 |
| 3M | 当前业务日期向前 3 个自然月至当前业务日期，不是固定 90 天 |
| 1Y | 当前业务日期向前 1 个自然年至当前业务日期，不是固定 365 天 |

如果 Collection Item 加入时间晚于 Range 起点，图表只从 `performance_start_at` 开始产生该 Item 的有效数据。对于 v1.1 上线前已有 Collection Item，若可靠历史晚于 `performance_start_at`，则按第 10.4.1 节从 `performance_history_available_from` 开始展示。加入 Portfolio 前或可靠历史开始前不得补虚假持仓数据。

1Y Performance 仍为 v1.1 首发能力，不得因 Legacy 数据不足而删除 1Y、隐藏 1Y、降级为 3M 或取消 Premium Benefit。Selected Range = 1Y 只表示用户选择 1 年理论范围，不代表必须伪造完整 1 年历史点。若可靠 Performance 历史不足 1 年，1Y 仍正常选中，图表只展示最早可靠历史时间至当前业务日期的有效历史。

## 10.2 统一 Tooltip 数量规则

所有 v1.1 Performance 图表点击日期节点后，Tooltip 必须展示该日期当天的 Qty。

格式：

```text
Qty: 12 (+2)
Qty: 10 (-2)
Qty: 10
```

规则：

1. Qty 表示点击日期当天的持有数量。
2. 括号内表示与上一个统计节点相比的数量变化。
3. 数量无变化时仍显示 Qty，但不显示 `(+0)`。
4. Qty 不是事件数量。
5. Tooltip 内容必须来自当前点击日期，不使用当前实时数据替代历史数据。
6. 图表无可用数据时不展示虚假 Tooltip。

## 10.3 统一图表交互

1. 点击图表数据节点，显示对应日期 Tooltip。
2. 点击其他节点，Tooltip 切换到新日期。
3. 切换时间范围后，关闭旧 Tooltip并刷新图表数据。
4. Performance 整个功能属于 Premium；Free 用户看到 Performance 锁定态，点击锁定区域或 Unlock CTA 打开 Paywall。
5. Premium 用户获得 1D、7D、15D、1M、3M、1Y 全部范围；Performance 内部不再单独设置 Range 锁定项。
6. Free 用户不得查看 1D / 7D / 15D / 1M / 3M Performance 后只在 1Y 弹 Paywall；用户已经 Premium 后，点击 Performance 1Y 不得再次弹 Paywall。

### 10.3.1 Performance 默认 Range

Home Performance 和 Card Detail Performance 默认 Range 均为 1M。

规则：

1. 同一页面实例内，保留用户最后选择的 Range。
2. 重新创建页面实例或冷启动重新进入时，默认 1M。
3. 不把 Extended Price History 的 Range 记忆规则混入 Performance。

## 10.4 Purchase Price 生效时间与 Quantity 历史

Purchase Price 页面不新增日期字段。每个 Collection Item 使用：

- `performance_start_at`：首次加入 Portfolio 的时间
- `purchase_price_effective_at`：首次加入 Portfolio 的时间

规则：

1. 创建 Collection Item 时填写 Purchase Price，从首次加入 Portfolio 的时间开始参与 Performance。
2. 创建时未填写、后续补填 Purchase Price 时，该价格追溯至最初加入 Portfolio 的时间，并重新计算从加入时间开始的 Purchase Cost、Profit/Loss 和 Return。
3. 后续修改 Purchase Price 时，修改后的值追溯至最初加入 Portfolio 的时间，并重新计算历史 Performance。
4. 不使用填写或修改 Purchase Price 的操作时间作为统计起点。
5. Purchase Price 仍为非必填字段。
6. 每个历史日期使用当日有效 Quantity；Quantity 变化只从变化时间点起影响后续成本和价值，不得使用当前 Quantity 反向覆盖历史。
7. 一个 Collection Item 只保存一个单位 Purchase Price。
8. 同一张卡存在不同购买价格时，应创建多个 Collection Item 分别记录；每个 Item 独立记录加入时间、Quantity 和 Purchase Price。

示例：

```text
08/01：加入 Portfolio，Qty = 1，Purchase Price = NULL
08/10：用户填写 Purchase Price = $100

结果：08/01 起的 Purchase Cost 按 $100 × 当日有效 Qty 重新计算，
不是从 08/10 才开始计算。
```

### 10.4.1 Existing Collection Item 历史迁移

v1.1 上线时，对已有 Collection Item 进行 Performance 历史兼容。

对于 v1.1 上线前已经存在的 Collection Item：

```text
performance_start_at = existing created_at
purchase_price_effective_at = existing created_at
```

`created_at` 视为该 Item 首次进入 Portfolio 的可靠时间。Purchase Price 继续遵循现有规则：

1. 创建时已有 Purchase Price：从 `created_at` 起生效。
2. 后续补填 Purchase Price：逻辑上追溯至 `created_at`。
3. 后续修改 Purchase Price：逻辑上追溯至 `created_at`。

但实际 Performance 历史点仍受“历史资产状态是否能够可靠恢复”限制。v1.0 已有数据如果缺少某类历史事件或历史快照，不得使用当前最新状态反向覆盖整个历史，包括但不限于 Quantity、Grader、Grade、Condition、Language、Finish 和 Folder Move。

统一迁移原则：

```text
历史数据可可靠还原
→ 按真实历史生成 Performance

历史数据无法可靠还原
→ 不创建猜测事件
→ 不使用当前状态反向伪造过去
```

对于 Existing Collection Item，产品逻辑区分：

| 概念 | 含义 |
| --- | --- |
| `performance_start_at` | Collection Item 首次加入 Portfolio 的真实时间；Existing Item 使用 `created_at` |
| `performance_history_available_from` | 能够基于可靠资产状态生成 Performance 历史的最早时间 |

`performance_history_available_from` 是产品逻辑概念，不强制要求数据库必须使用该物理字段名。旧数据能够完整还原时，`performance_history_available_from = performance_start_at`；旧数据缺少必要历史状态时，`performance_history_available_from > performance_start_at`。

v1.0 Folder Move 不存在完整可可靠还原历史数据，因此 v1.1 不要求反向生成虚假的 Folder Move Event。对于 v1.1 上线时已经存在的 Collection Item，以迁移时当前 Folder 作为后续准确 Folder 历史的初始状态：

```text
v1.1 migration
→ 记录当前 Folder Snapshot
→ 从该时间起
→ Folder Move 按 v1.1 新规则完整记录
```

迁移时间之前，如果无法可靠判断该 Item 当时属于哪个 Folder，则不得把该 Item 的历史资产价值强行归入当前 Folder。Home Performance 中 Folder A / Folder B 的历史 Portfolio Performance 不得因为当前 Item 位于 Folder B，就把 `created_at` 至 `migration_at` 之间的全部历史价值归给 Folder B。

对于无法恢复完整可可靠还原历史事件的 Existing Item，v1.1 Migration 时记录当前可靠状态作为 Baseline，至少包括产品逻辑需要的 Quantity、Grader、Grade、Condition、Language、Finish 和 Current Folder。从该 Baseline 时间开始，后续每次变化都必须能够支持 Performance 历史还原。

从 v1.1 起，以下影响 Performance 的资产变化必须能够被历史还原：

- Quantity Change
- Grader Change
- Grade Change
- Condition Change
- Language Change
- Finish Change
- Folder Move
- Delete
- Add / Re-add Portfolio

产品不强制开发采用 Event Table、Snapshot Table、Version Table 或 Audit Log 中的具体哪一种，但最终必须满足可以根据目标日期 `t` 还原当时有效状态。不得继续只保存最新值，导致未来再次无法计算准确历史 Performance。

Purchase Price 仍然是特殊的可回溯字段。Existing Item 如果 `created_at = 2026/05/01`，v1.1 上线时 Purchase Price = NULL，用户在 2026/09/01 补填 Purchase Price = $100，则 `purchase_price_effective_at = 2026/05/01`。但只有在对应日期的 Quantity、Price Mapping、Folder attribution、Market Price 等必要状态可以可靠获得时，才能生成准确 Performance 点。不得因为 Purchase Price 可以追溯，就允许其他缺失历史字段使用当前值反向伪造。

历史不足不等于 Network Error，也不等于数据计算失败。如果 Selected Range 大于当前可靠历史，仍正常展示现有可用历史。例如 Selected = 1Y、Reliable history = 4M 时，展示 4M 有效历史，不生成不存在的历史点，也不新增复杂错误页。如果整个 Selected Range 内都不存在任何可靠 Performance 数据，按现有 No Data / Empty State 规则处理。
对 v1.1 Existing Collection Item，Folder Move 不得突破 performance_history_available_from 向前生成或迁移不存在的 Legacy Performance 历史；对于 v1.1 新建且历史完整的 Item，performance_history_available_from = performance_start_at。
## 10.5 数据刷新频率

### Market Price / 历史统计

Market Price 历史数据和已结束自然日的 Performance 统计节点，每个业务自然日形成 1 个日节点。历史日期原则上不因为普通前端刷新重复生成多个节点。

### 用户资产操作实时刷新

以下操作保存成功后，当前页面中的当前 Market Value、Total Paid、Profit/Loss、Return、Qty、Folder 当前总值必须立即刷新：

- Add Collection Item
- Delete Collection Item
- 修改 Quantity
- 修改 Purchase Price
- 修改 Price Mapping Attributes
- Folder Move

不得要求用户等到第二天才看到当前值变化。

### 当天 Performance 节点

今天属于尚未结束的自然日。当天最新 Performance 节点使用当前最新资产状态和当前当天有效 Market Price 实时重新计算。

示例：

```text
上午：Qty 1
下午修改：Qty 3

当天图表最后一个节点立即更新为 Qty 3 对应结果。
```

跨日后，前一自然日最终结果固化为历史日节点。

### 历史节点

已经结束的历史自然日不得因为当前 Quantity 变化反向覆盖，但以下明确允许回溯的规则除外：

- Purchase Price 回溯
- Folder 完整可可靠还原历史迁移
- 已定义的数据修正 / 重算

## 10.6 Performance 数据加载状态

Home Performance 和 Card Detail Performance 均需区分 Loading、Normal Data、Empty / No Data、Network / Service Error、Purchase Price Missing 相关业务状态。接口失败不得误判为 No Data。

| 状态 | 规则 |
| --- | --- |
| Loading | 展示当前 Prototype 既有 Loading / Skeleton；不生成虚假图表；不显示旧 Tooltip |
| Normal Data | 按当前 Range、当前权益和第 14 章计算口径展示指标、图表和 Tooltip |
| Partial History | Selected Range 大于当前可靠 Performance 历史时，正常展示现有可靠历史；不生成不存在的历史点，不视为 Network Error 或计算失败 |
| No Data | 仅业务数据确实不存在时使用，例如整个 Selected Range 无任何有效 Market Price；不得把 HTTP 失败、timeout 或 server error 显示成 No Data |
| Network / Service Error | 不生成虚假图表；保持当前页面与 Selected Range；按 App 现有网络错误反馈处理；不新增独立 Retry 大按钮；可按现有客户端自动重试机制处理 |
| Purchase Price Missing | 按 Home Partial / No Purchase Price 或 Card Detail Purchase Price 缺失业务状态展示，不得把缺失成本按 0 计算 |

## 10.7 多设备远端数据变化

账号用户支持多设备同步。如果当前页面依赖的数据被另一设备删除：

| 远端变化 | 当前页面处理 |
| --- | --- |
| Current Collection Item 被删除 | 停止旧 Performance 请求；不展示旧 Collection Item Performance；按 v1.0 Card Detail 最新数据状态刷新 |
| Current Folder 被删除 | 自动切换默认 Folder；加载默认 Folder 数据 |

旧 Collection Item / 旧 Folder 请求晚返回时，不得覆盖当前最新页面状态或默认 Folder 数据。

# 11. Home Performance

Home Performance 为 v1.1 新增 Premium 功能。

## 11.1 页面进入与锁定

- 点击 Performance Tab 进入 Performance。
- Free 状态进入后显示锁定态。
- 点击锁定区域或 Unlock CTA 打开 Paywall。
- Premium 状态展示完整 Performance。
- Home Overview 的 Most Valuable 按单张 Unit Market Price 排序，Quantity 不影响排名，展示单张 Unit Market Price。
- 除上述 Most Valuable 排序和展示口径外，Home 原有 v1.0 内容保持原流程，不新增其他 Performance 卡牌榜单。

### 11.1.1 页面交互与控件规则

当前 Prototype 交互为：点击 `Performance` Tab 只切换到 Performance 容器；Free 状态展示锁定态，不因点击 Tab 立即打开 Paywall。Paywall 由锁定区域或 `Unlock Performance` 触发。

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Overview Tab | Home 页面展示 Header Tab | 始终可点 | 切换到 Home Overview 容器；不打开 Paywall | Home 当前页面 Overview 容器 | 展示 v1.0 Overview 内容 | - | 保留 Home 当前数据、底部导航状态；关闭 Performance Tooltip |
| Performance Tab | Home 页面展示 Header Tab | 始终可点 | 切换到 Home Performance 容器；不跳页；不直接打开 Paywall | Home 当前页面 Performance 容器 | Premium：展示完整 Performance；Free：展示 Performance 锁定态 | 数据加载失败时展示已定义异常或空状态，不打开 Paywall | 保留当前 Home 页面实例、滚动位置；Premium 保留已选 Performance Range |
| Unlock Performance CTA / 锁定区域 | Free 状态 Performance 锁定态 | Paywall 未打开 | 保存 `blocked_action=open_home_performance`，打开 Subscription Paywall Modal | Subscription Paywall Modal | Purchase Success：关闭 Modal，显示 `Premium unlocked`，回到 Home Performance，加载并展示完整 Performance；Restore Success：关闭 Modal，显示 `Premium restored`，回到 Home Performance，加载并展示完整 Performance | Close/Scrim/Cancelled/Failed/Pending/Restore Not Found/Restore Failed：回到 Home Performance 锁定态，不自动切换 Premium 内容；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留 Home Performance Tab、滚动位置、购买前 Range 或默认 Range、已加载 Overview 数据；Restore Not Found / Failed 不清空 `blocked_action` |
| 顶部 Premium 入口 | Home 一级页面；Free 状态 | Subscription Page 未打开 | 记录 `source_page=Home`、`entry_source=top_subscription_entry`；打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 进入 Subscription Success，Start Exploring 后进入 Home Premium；Restore Success 后关闭 Subscription Page，返回 Home Premium 并显示 `Premium restored` Toast | Close、Cancelled、Pending、Failed、Restore Not Found/Failed 后回到 Home Free；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留 Home Tab、Range、Tooltip、滚动位置和已加载数据；Premium 状态不显示该入口 |

### 11.1.2 Home Overview Portfolio Chart Range

Home Overview 原有 Portfolio Chart 属于普通历史图表，不属于 v1.1 Performance。其 Chart Range Selector 统一为 1D / 7D / 15D / 1M / 3M / 1Y，默认 1M。

| 权益状态 | Home Overview Portfolio Chart 可查看 Range |
| --- | --- |
| Free | 1D、7D、15D、1M、3M |
| Premium | 1D、7D、15D、1M、3M、1Y |

Free 用户点击 1Y 时，按第 13.3 节 Extended Price History 规则打开 Functional Subscription Paywall Modal；不得立即切换 Selected Range，不得请求 1Y 数据。Purchase / Restore 成功后返回 Home Overview，保持当前 Folder，并自动选择和加载 1Y Portfolio Chart。未获得 Premium 时保持进入 Paywall 前的原 Selected Range、当前 Folder、Overview Tab、滚动位置和已加载图表数据。

## 11.2 正常状态

展示 Total Paid、Market Value、Profit/Loss、Return、Performance Chart 和 1D / 7D / 15D / 1M / 3M / 1Y。字段类型和公式见第 14 章。

Home Performance 曲线的纵轴值为当前 Folder 的 Portfolio Market Value(t)，不是 Purchase Cost 或 Profit/Loss。这样在 Purchase Price全部缺失时仍可沿用同一 Market Value 曲线，不生成虚假收益曲线。

Tooltip：

- Date
- Market
- Portfolio
- Qty

### 11.2.1 Performance Time Range 交互

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1D | Home Performance 展示 | Premium 且 1D 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 1D 数据 | Home Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 1D | 数据请求失败时保留页面在 Performance，1D 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留 Home Performance Tab、滚动位置；失败时保留点击前 Range |
| 7D | Home Performance 展示 | Premium 且 7D 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 7D 数据 | Home Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 7D | 数据请求失败时保留页面在 Performance，7D 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留 Home Performance Tab、滚动位置；失败时保留点击前 Range |
| 15D | Home Performance 展示 | Premium 且 15D 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 15D 数据 | Home Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 15D | 数据请求失败时保留页面在 Performance，15D 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留 Home Performance Tab、滚动位置；失败时保留点击前 Range |
| 1M | Home Performance 展示 | Premium 且 1M 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 1M 数据 | Home Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 1M | 数据请求失败时保留页面在 Performance，1M 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留 Home Performance Tab、滚动位置；失败时保留点击前 Range |
| 3M | Home Performance 展示 | Premium 且 3M 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 3M 数据 | Home Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 3M | 数据请求失败时保留页面在 Performance，3M 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留 Home Performance Tab、滚动位置；失败时保留点击前 Range |
| 1Y | Home Performance 展示 | Premium 且 1Y 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 1Y 数据 | Home Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 1Y | 数据请求失败时保留页面在 Performance，1Y 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留 Home Performance Tab、滚动位置；失败时保留点击前 Range |

### 11.2.2 图表点击与 Info 交互

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Chart Point / Event Marker | Home Performance Chart 有有效节点 | Premium 且当前 Range 数据已加载 | 展示当前节点 Tooltip；Tooltip 内容读取点击日期的历史数据 | Home Performance Chart 内 Tooltip | Tooltip 展示 Date、Market、Portfolio、Qty；点击另一节点时切换为新节点内容 | 节点数据缺失时不展示虚假 Tooltip；保留当前图表 | 保留当前 Range 和 Performance Tab |
| Chart 无节点区域 | Home Performance Chart 已展示 | 当前无 Apple Purchase 或数据请求阻塞 | 关闭当前 Tooltip | Home Performance Chart | Tooltip 隐藏 | - | 保留当前 Range、图表和滚动位置 |
| Partial Purchase Price Info | Partial Purchase Price Missing 状态展示信息图标 | 始终可点 | 打开小型 Popover，显示 `Profit and return are calculated only from cards with purchase prices.`；不跳页；不打开 Paywall | Home Performance 当前信息图标旁 Popover | Popover 展示说明文案 | - | 保留当前 Range、Tooltip 和滚动位置；再次点击 Info 或点击 Popover 外部区域关闭 Popover |

Home Performance 的 Chart Tooltip 和 Partial Purchase Price Info Popover 不得同时存在：

- 打开 Info 时关闭 Chart Tooltip。
- 点击 Chart Point 时关闭 Info Popover。
- 切 Range 时两者全部关闭。
- 切 Folder 时两者全部关闭。
- 离开 Performance 时两者全部关闭。

### 11.2.3 Home Performance 切换 Folder

用户当前位于 Home → Performance → 1M → Folder A 时，切换 Folder B：

1. 保持 Performance Tab。
2. 保持当前 Range，例如 1M。
3. 关闭旧 Chart Tooltip。
4. 关闭 Info Popover。
5. 加载 Folder B Performance。
6. 成功后更新 Folder B 所有指标与 Chart。

如果 Folder B 为空，进入 Empty Portfolio 状态。如果请求失败或 15 秒 Timeout，不得让 Folder A 晚到旧请求覆盖当前 Folder B 选择；保留当前选择状态并展示对应错误反馈。

### 11.2.4 Home 金额隐藏与 Performance

Home 已有金额 Eye 隐藏能力继续影响 Home Performance。金额隐藏时，以下金额全部使用 v1.0 隐藏样式：

- Total Paid
- Market Value
- Profit/Loss
- Chart 金额轴
- Tooltip Market
- Tooltip Portfolio
- 其他 Home Performance 金额

Qty 继续正常显示。Return 属于百分比，继续按现有百分比显示规则处理，不因为金额隐藏自动消失。切换 Overview / Performance 时保持同一个 Eye 隐藏状态。

## 11.3 计算范围

- 数据范围跟随当前选中的 Portfolio Folder。
- 目标日期 `t` 只包含该日期已加入且尚未删除的有效 Collection Item。
- Item 加入前不参与历史点；删除后不参与删除时间后的点；删除前历史保留。
- Market Value 只统计目标日期有有效 Market Price 的 Portfolio Item。
- Wishlist、未收藏卡牌、Failed 和 No Match Found 不参与 Performance。
- 每个历史点使用目标日期有效 Quantity，不使用当前 Quantity 回写过去。
- 金额集合、价格兜底和 Folder 历史归属见第 14 章。

## 11.4 Partial Purchase Price Missing

场景：部分 Portfolio Item 有 Purchase Price，部分没有。

定义集合 `P(t)`：目标日期同时满足“在当前 Folder 的 Portfolio 中有效存在、Purchase Price 非 NULL、Market Price 有效”的 Collection Items。

```text
Paid Market Value(t) = Σ[i∈P(t)] Unit Market Price_i(t) × Quantity_i(t)
Total Paid(t) = Σ[i∈P(t)] Unit Purchase Price_i × Quantity_i(t)
Profit/Loss(t) = Paid Market Value(t) - Total Paid(t)
Return(t) = Profit/Loss(t) ÷ Total Paid(t) × 100%
```

规则：

1. 缺失 Purchase Price 不得按 0 计算。
2. Total Paid、Paid Market Value、Profit/Loss 和 Return 使用完全相同的 `P(t)`，不得用全部 Portfolio Market Value 减去部分资产成本。
3. 页面 Market Value 仍使用全部具有有效 Market Price 的 Portfolio Item，因此可以大于 Paid Market Value。
4. `Total Paid(t) = 0` 时 Return 展示 `--`，不得展示 Infinity 或 NaN。
5. Performance 正常展示，但必须说明收益计算覆盖范围。

示例：A、B 有 Purchase Price，C 无 Purchase Price；A/B 当前市场价值合计 `$800`，成本合计 `$500`，C 当前市场价值 `$200`：

```text
Market Value = $800 + $200 = $1,000
Total Paid = $500
Profit/Loss = $800 - $500 = +$300
Return = $300 ÷ $500 × 100% = +60%
```

信息图标点击后显示：

```text
Profit and return are calculated only from cards with purchase prices.
```

## 11.5 No Purchase Price

场景：当前 Portfolio Folder 中所有 Item 均无 Purchase Price。

展示：

- Market Value
- Price Trend
- Qty

不展示：

- Total Paid
- Profit/Loss
- Return

提示：

```text
Add purchase prices to track profit and return.
```

不得将缺失成本按 0 计算。

## 11.6 Empty Portfolio

- 展示现有 Empty State。
- 不展示 Performance 指标、曲线或 Tooltip。
- 不生成虚假数据。
- 引导用户按现有流程添加 Portfolio Item。

# 12. Card Detail Performance

Card Detail Performance 为 v1.1 新增 Premium 功能。

## 12.1 页面入口

- 所有 Card Detail 顶部均不显示订阅小标识。
- Free 状态通过 Performance 锁定区域或 Unlock CTA 打开 Paywall。
- Premium 状态展示完整 Performance。
- Performance 只针对已有 Portfolio ownership data 的 Card Detail。
- Card Detail Performance 只计算当前 Card Detail 上下文中的 `current Collection Item`，不聚合同一卡牌下的其他 Collection Item。
- 同一卡牌存在多个 Collection Item 时，继续沿用 v1.0 的具体 Collection Item 详情上下文，不新增 Collection Item 选择器 UI。

示例：

```text
Card A

Item A：Raw，Purchase Price $100
Item B：PSA 10，Purchase Price $500

进入 Item A 对应 Card Detail → Performance 只计算 Item A
进入 Item B 对应 Card Detail → Performance 只计算 Item B
```

Home Performance 继续按当前 Folder 内全部有效 Collection Items 聚合。

### 12.1.1 页面交互与控件规则

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Performance Tab | Card Detail 存在 Portfolio ownership data；Tab 可见 | 始终可点 | 切换到当前 Card Detail 的 Performance Tab；不创建新的 Card Detail | 当前 Card Detail Performance Tab | Premium：展示完整 Performance 或已定义异常状态；Free：展示 Performance 锁定态 | 数据加载失败时停留 Performance Tab，展示已有错误反馈或已定义异常状态 | 保留当前 `card_id`、`collection_item_id`、Card Detail 页面实例和滚动位置 |
| Unlock Card Performance CTA / 锁定区域 | Free 状态 Card Detail Performance 锁定态 | Paywall 未打开 | 保存 `blocked_action=open_card_performance`、当前 `card_id`、`collection_item_id`、Tab 和 Range；打开 Subscription Paywall Modal | Subscription Paywall Modal | Purchase Success：关闭 Modal，显示 `Premium unlocked`，回到当前 Card Detail Performance Tab，加载完整 Performance；Restore Success：关闭 Modal，显示 `Premium restored`，回到当前 Card Detail Performance Tab，加载完整 Performance | Close/Scrim/Cancelled/Failed/Pending/Restore Not Found/Restore Failed：回到当前 Card Detail Performance 锁定态，不自动切换 Premium 内容；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留当前 Card Detail、`card_id`、`collection_item_id`、Performance Tab、购买前 Range、滚动位置和已加载卡牌数据；Restore Not Found / Failed 不清空 `blocked_action` |
| 1D | Card Detail Performance 展示 | Premium 且 1D 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 1D 数据 | 当前 Card Detail Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 1D | 数据请求失败时保留页面在 Performance，1D 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留当前 `card_id`、`collection_item_id`；失败时保留点击前 Range |
| 7D | Card Detail Performance 展示 | Premium 且 7D 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 7D 数据 | 当前 Card Detail Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 7D | 数据请求失败时保留页面在 Performance，7D 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留当前 `card_id`、`collection_item_id`；失败时保留点击前 Range |
| 15D | Card Detail Performance 展示 | Premium 且 15D 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 15D 数据 | 当前 Card Detail Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 15D | 数据请求失败时保留页面在 Performance，15D 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留当前 `card_id`、`collection_item_id`；失败时保留点击前 Range |
| 1M | Card Detail Performance 展示 | Premium 且 1M 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 1M 数据 | 当前 Card Detail Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 1M | 数据请求失败时保留页面在 Performance，1M 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留当前 `card_id`、`collection_item_id`；失败时保留点击前 Range |
| 3M | Card Detail Performance 展示 | Premium 且 3M 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 3M 数据 | 当前 Card Detail Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 3M | 数据请求失败时保留页面在 Performance，3M 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留当前 `card_id`、`collection_item_id`；失败时保留点击前 Range |
| 1Y | Card Detail Performance 展示 | Premium 且 1Y 数据范围可用 | 设为 Selected；取消旧 Range；关闭旧 Tooltip；请求或读取 1Y 数据 | 当前 Card Detail Performance Chart | 图表、指标和 Tooltip 可用节点刷新为 1Y | 数据请求失败时保留页面在 Performance，1Y 控件恢复可点，展示已有错误反馈；不生成虚假图表 | 保留当前 `card_id`、`collection_item_id`；失败时保留点击前 Range |
| Chart Point | Card Detail Performance Chart 有有效节点 | Premium 且当前 Range 数据已加载 | 展示当前节点 Tooltip；Tooltip 内容读取点击日期的历史数据 | 当前 Card Detail Performance Chart 内 Tooltip | Tooltip 展示 Date、Daily Change、Market Value、Profit/Loss、Qty；Purchase Price 缺失状态展示 Date、Daily Change、Market Value、Qty；点击另一节点时切换为新节点内容 | 节点数据缺失时不展示虚假 Tooltip；保留当前图表 | 保留当前 Range、`card_id`、`collection_item_id` |
| Chart 无节点区域 | Card Detail Performance Chart 已展示 | 当前无 Apple Purchase 或数据请求阻塞 | 关闭当前 Tooltip | 当前 Card Detail Performance Chart | Tooltip 隐藏 | - | 保留当前 Range、`card_id`、`collection_item_id` 和滚动位置 |

## 12.2 正常状态

顶部指标：

- Purchase Cost
- Market Value
- Profit/Loss
- Return

图表 Tooltip：

- Date
- Daily Change
- Market Value
- Profit/Loss
- Qty

Qty 遵循第 10.2 节统一规则。

数值口径：

```text
Purchase Cost(t) = Unit Purchase Price × Quantity(t)
Market Value(t) = Unit Market Price(t) × Quantity(t)
Profit/Loss(t) = Market Value(t) - Purchase Cost(t)
Return(t) = Profit/Loss(t) ÷ Purchase Cost(t) × 100%
```

正常状态 Performance Chart 的纵轴值为 `Profit/Loss(t)`。Tooltip 的 Daily Change 为 `Profit/Loss(t) - Profit/Loss(previous node)`；Market Value、Profit/Loss 和 Qty 均读取点击日期的历史值。Purchase Cost 为 0 时 Return 展示 `--`。

## 12.3 Purchase Price 缺失

展示：

- Market Value
- Price Trend

不展示：

- Purchase Cost
- Profit/Loss
- Return

提示：

```text
Add purchase price to calculate your card performance.
```

Button：

```text
Edit Collection Item
```

点击后切换到当前 Card Detail 的 Collection Item Tab，不打开新的 Card Detail 页面。

### 12.3.1 Edit Collection Item 交互

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Edit Collection Item | Card Detail Performance 的 Purchase Price 缺失状态 | 当前 Card Detail 存在 `card_id` 和 `collection_item_id`；无保存请求进行中 | 使用当前 `card_id` / `collection_item_id`；切换到当前 Card Detail 已有 Collection Item 编辑上下文；不创建新的 Card Detail；不跳到其他卡牌 | 当前 Card Detail 内 Collection Item Tab / 既有 Collection Item 编辑容器 | 保存成功后回到当前 Card Detail Performance Tab，重新计算并刷新 Performance；若 Purchase Price 已补全则展示正常状态 | 保存失败时保留用户输入内容，不更新 Performance，使用 v1.0 Collection Item 已有错误反馈；取消编辑时回到当前 Card Detail，Performance 不刷新 | 保留当前 Card Detail、`card_id`、`collection_item_id`、Performance Tab 来源、购买前 Range 和滚动位置 |

Tooltip 展示：

- Date
- Daily Change
- Market Value
- Qty

Purchase Price 缺失状态的历史曲线使用 `Market Value(t)`，不使用 Profit/Loss 曲线。此时 Daily Change 定义为 `Market Value(t) - Market Value(previous node)`。

## 12.4 Free 解锁与成功返回

- 点击锁定区域打开 Paywall。
- Purchase 成功后，关闭 Paywall、显示 `Premium unlocked`，刷新当前 Performance Tab并自动继续展示 Performance。
- Restore 成功后，关闭 Paywall、显示 `Premium restored`，并刷新当前 Performance Tab。
- 保持当前 Card、Tab、滚动位置和已选时间范围。

# 13. Market Price 与历史价格

## 13.1 单日 Market Price 缺失

Performance 图表沿用 v1.0 历史价格兜底逻辑：

1. 优先取该日期之前最近的有效价格。
2. 之前没有有效价格时，取该日期之后最近的有效价格。
3. 单日缺失不导致图表断裂。
4. 单日缺失不展示独立异常页面。

示例 1：

```text
08/01 = $10
08/02 = NULL
08/03 = $12
```

08/02 使用之前最近的有效价格 `$10`。

示例 2：

```text
08/01 = NULL
08/02 = NULL
08/03 = $12
```

08/01 与 08/02 均因之前没有有效价格，使用之后最近的有效价格 `$12`。

## 13.2 整个时间范围无有效价格

- 仅当整个所选时间范围均没有任何有效 Market Price 时展示无数据状态。
- 无数据状态使用现有 Prototype 或 v1.0 空状态。
- 不自行新增复杂异常页面。
- 无可用数据时不展示虚假 Tooltip。

## 13.3 Extended Price History

Extended Price History 是独立 Premium Benefit，适用于当前仍允许 Free 查看短周期历史的普通历史图表，不适用于 v1.1 Home Performance 或 Card Detail Performance 图表。

v1.1 至少覆盖：

1. Home Overview 原有 Portfolio Chart
2. Card Detail Price History / Market Price Chart

v1.1 不修改上述普通历史图表已有的数据定义、市场价格计算、图表样式或 Tooltip 计算，只新增统一 Chart Range Selector 与 1Y 可查看范围限制。

### 13.3.1 Range 与权限

普通历史图表统一使用 1D / 7D / 15D / 1M / 3M / 1Y，默认 1M。

| 权益状态 | 普通历史图表可查看 Range |
| --- | --- |
| Free | 1D、7D、15D、1M、3M |
| Premium | 1D、7D、15D、1M、3M、1Y |

Free 用户最多查看 3M 历史；1Y 为 Premium Locked。Premium 用户可查看 1D、7D、15D、1M、3M、1Y。

### 13.3.2 Free 点击 1Y

Free 用户在普通历史图表点击 1Y 时：

```text
普通历史图表
→ 当前 Range 为任一 Free 可用 Range：1D / 7D / 15D / 1M / 3M
→ 点击 1Y
→ 不立即切换 Selected Range
→ 不请求 1Y 数据
→ 保存原 Selected Range
→ 保存 requested_range=1Y
→ 保存 source_chart
→ 保存当前页面上下文
→ 打开 Subscription Paywall Modal
```

继续使用统一 blocked_action：

```text
open_extended_price_history
```

来源上下文：

| 来源图表 | source_chart | 必须保存的上下文 |
| --- | --- | --- |
| Home Overview Portfolio Chart | `home_overview` | 当前 Folder、Overview Tab、Scroll、原 Selected Range、`requested_range=1Y` |
| Card Detail Price History | `card_detail_price` | `card_id`、当前页面上下文、当前 Scroll、原 Selected Range、`requested_range=1Y` |

### 13.3.3 成功后恢复

Purchase Success：

| 来源图表 | 成功后结果 |
| --- | --- |
| Home Overview Portfolio Chart | Premium 生效；关闭 Paywall；显示 `Premium unlocked`；返回同一个 Home；保持 Overview；保持当前 Folder；自动选中 1Y；加载 1Y Portfolio Chart |
| Card Detail Price History | Premium 生效；关闭 Paywall；显示 `Premium unlocked`；返回同一个 Card Detail；自动选中 1Y；加载 1Y Price History |

Restore Success：

| 来源图表 | 成功后结果 |
| --- | --- |
| Home Overview Portfolio Chart | Premium 生效；关闭 Paywall；显示 `Premium restored`；返回同一个 Home；保持 Overview；保持当前 Folder；自动选中 1Y；加载 1Y Portfolio Chart |
| Card Detail Price History | Premium 生效；关闭 Paywall；显示 `Premium restored`；返回同一个 Card Detail；自动选中 1Y；加载 1Y Price History |

不要求用户再次点击 1Y。

### 13.3.4 未成功

普通历史图表 Free 点击 1Y 打开 Paywall 后，如果最终没有获得 Premium，均不切换到 1Y、不请求 1Y 数据、不执行 `open_extended_price_history`。

- Paywall Close
- Scrim
- Purchase Cancelled
- Purchase Pending
- Purchase Failed
- Purchase unavailable
- Transaction Unverified
- Product Loading Failed
- Product Timeout
- Restore Not Found
- Restore Failed
- Restore Timeout

规则：

1. 保持进入 Paywall 前的原 Selected Range。
2. 保持当前页面。
3. 保持 Folder / Card / Tab / Scroll。
4. 保留已加载图表数据。
5. Pending 继续沿用现有 Purchase Pending 规则，不得因为点击过 1Y 就提前切换 Selected Range。

### 13.3.5 Premium 变 Free 时普通历史图表为 1Y

如果用户当前为 Premium，正在普通历史图表查看 1Y，随后 Apple-verified entitlement state 刷新确认变为 Free：

1. 不弹 Paywall。
2. 不离开当前页面。
3. 1Y 恢复锁定。
4. 自动切换到 Free 允许的最长 Range：3M。
5. 加载 3M 数据。
6. 保持当前 Folder / Card / Tab / Scroll。

适用于：

1. Home Overview Portfolio Chart
2. Card Detail Price History

以后 Free 用户再次点击 1Y，正常打开 Functional Paywall。Free 重新进入普通历史图表时，不得继续恢复之前 Premium 保存的 1Y Selected 状态。

### 13.3.6 默认 Range

Home Overview Portfolio Chart 与 Card Detail Price History 首次创建页面实例、冷启动重新进入时，默认 Range 均为 1M。同一页面实例内，可以保留用户本次最后选择的 Range。

# 14. 数值数据来源与计算口径

本章是 v1.1 所有金额、百分比、数量、涨跌值和历史图表点位的统一计算规范。页面章节与本章冲突时，以页面中的特定状态规则为准。

## 14.1 数据类型

| 类型 | 含义 | 示例 |
| --- | --- | --- |
| Direct | 数据库或 API 直接返回，客户端只读取和格式化 | Card Name、Collection Item 的 Purchase Price、Market Price API 的 Unit Market Price |
| Derived | 使用 Direct 数据或历史状态计算 | Item Market Value、Portfolio Market Value、Total Paid、Profit/Loss、Return、Daily Change |
| State | 由 App 业务状态决定 | Premium、Free、Unknown、Empty Portfolio、Partial Purchase Price Missing |

客户端不得把 Derived 字段当作新的 Direct 真值反向参与后续计算；页面已格式化、缩写或四舍五入后的字符串也不得作为计算输入。

### 14.1.1 计算责任

| 数据 | 责任层 | 前端规则 |
| --- | --- | --- |
| Card / Collection Item 基础字段 | Card、Collection API / 数据库 Direct 返回 | 读取并展示，不自行改写语义 |
| 当前 Collection Item Total 编辑预览 | 前端使用 Unit Market Price × 当前表单 Quantity 实时计算 | 仅作编辑预览，保存或刷新后以统一数据接口结果校准 |
| Portfolio / Performance 当前指标 | Performance 聚合接口按本章公式返回原始数值 | 前端不使用格式化字符串二次计算 |
| Performance 历史点、Daily Change、Market/Portfolio 拆分 | Performance 聚合接口根据历史价格和资产事件计算 | 前端只负责时间范围选择、Tooltip 展示和最终格式化 |
| Price Change / Trending Change | Price 数据接口返回当前价与比较价；Change 可由同一接口按第 14.10 节公式计算 | 不混用不同接口或不同时间口径重新计算 |
| Premium | Apple-verified entitlement state 映射出的 State | 不从 App 账号或订单用户唯一标识推导；StoreKit 用于客户端即时验证，服务端 Apple lifecycle state 用于后续维护与校正 |
| 账号用户 Free Scan Quota | App 账号 | 同一账号用户多设备共享累计额度 |
| 游客身份 Free Scan Quota | 当前游客身份 | 不要求跨设备互通 |

现有资料未提供实际 endpoint 名称和数据库 schema；本 PRD 使用逻辑接口与产品字段名，不得由 Agent 编造物理表名。开发在技术设计中映射实际接口，但不得改变公式和时间口径。

## 14.2 统一符号与时间点

- `t`：当前展示时点或用户点击的历史图表节点。
- `t_prev`：`t` 的上一个统计节点。若图表范围开始前存在紧邻的有效统计节点，应使用该节点；若整个历史中不存在前序节点，Daily Change 及其拆分展示 `--`。
- `I_i(t)`：Collection Item `i` 在 `t` 是否有效存在于 Portfolio；加入前为 0，加入后为 1，删除时间点及之后为 0。
- `Q_i(t)`：Item `i` 在 `t` 的有效 Quantity。
- `MP_i(t)`：Item `i` 在目标日期 `t` 根据当时有效的 Grader、Grade、Condition、Language、Finish 等 Price Mapping Attributes 得到的有效 Unit Market Price。
- `PP_i`：Item `i` 的 Unit Purchase Price；用户未填写时为 NULL，不等于 0。
- `F_i(t)`：Item `i` 在 `t` 的 Portfolio Folder 归属。

统计节点可以由后端快照或事件重建，技术实现方式由开发决定，但输出结果必须符合加入、删除、Quantity、Purchase Price 与 Price Mapping Attributes 生效规则。不得用当前最新 Price Mapping Attributes 反向覆盖全部历史。

## 14.3 Collection Item Market Value

**字段：** Collection Item Market Value / Total / Current Value  
**类型：** Derived  
**数据来源：** Market Price API 的有效 Unit Market Price + Collection Item 在目标时点的 Quantity。

```text
Item Market Value_i(t) = MP_i(t) × Q_i(t)
```

当前值使用当前有效价格与当前 Quantity；历史值使用目标日期有效价格与目标日期 Quantity。

示例：

```text
Unit Market Price = $20
Quantity = 3
Item Market Value = $20 × 3 = $60
```

异常：

- `MP_i(t)` 缺失时，历史点按第 13 章兜底；当前值没有有效价格时展示 `--`，不按 0 计算。
- `Q_i(t)` 不得用当前 Quantity 反向覆盖历史。
- Purchase Price 不参与 Market Value 计算。

## 14.4 Portfolio Market Value

**字段：** Portfolio Market Value / Home 当前总资产  
**类型：** Derived  
**数据来源：** 当前选中 Folder 在目标时点有效的 Collection Items、各 Item 的 `MP_i(t)` 与 `Q_i(t)`。

定义 `M_F(t)`：在 `t` 属于 Folder `F`、已加入且未删除、并有有效 Market Price 的 Collection Items。

```text
Portfolio Market Value_F(t)
= Σ[i∈M_F(t)] MP_i(t) × Q_i(t)
```

示例：

```text
Card A: Price = $10, Qty = 2
Card B: Price = $20, Qty = 3
Portfolio Market Value = $10×2 + $20×3 = $80
```

范围与事件：

1. Wishlist、未收藏卡牌、No Match Found 自定义卡牌不参与。
2. Item 加入 Portfolio 前不参与历史点。
3. Item 删除后不参与删除时间点及后续点；删除前历史保留。
4. Quantity 变化从变更时间点起影响后续点。
5. 当前选中 Folder 只统计该 Folder 的资产。
6. Market Price 无效的 Item 不进入 `M_F(t)`，但基础卡牌信息仍可展示。

v1.1 上线后发生的 Collection Item 跨 Folder 移动，完整可可靠还原历史数据随 Collection Item 一起归属目标 Folder。源 Folder 中该 Item 的当前及历史统计全部移除；目标 Folder 从该 Item 的 performance_history_available_from 起获得全部可可靠还原的 Performance 历史；对于历史完整的 v1.1 新建 Item，performance_history_available_from = performance_start_at。`performance_start_at`、Purchase Price 历史、Quantity 历史和 Market Price 历史不变。

v1.0 Existing Collection Item 的 Folder Move 历史迁移按第 10.4.1 节处理。若 v1.0 缺少可还原历史归属的完整事件或快照，不得把当前 Folder 反向推断为该 Item 从 `created_at` 起的全部历史 Folder。迁移时当前 Folder 只作为 `migration_at` 之后的后续准确历史 Baseline。

## 14.5 Purchase Price 与 Total Paid

**Purchase Price 类型：** Direct，用户输入的单张购买价格。  
**Item Purchase Cost / Total Paid 类型：** Derived。

```text
Item Purchase Cost_i(t) = PP_i × Q_i(t)
```

Home Performance 的 Total Paid 使用第 11.4 节 `P(t)`：

```text
Total Paid(t) = Σ[i∈P(t)] PP_i × Q_i(t)
```

示例：

```text
Purchase Price = $100 each
Qty = 3
Item Purchase Cost = $300
```

规则：

1. Purchase Price 为单张价格，非整条 Item 总价。
2. NULL 不等于 0；未填写不得作为零成本参与计算。
3. 用户明确填写 0 时属于有效数值成本，但相关 Return 的分母为 0，Return 展示 `--`。
4. Purchase Price 的回溯生效时间沿用第 10.4 节。
5. 同卡不同购买批次通过多个 Collection Item 分别记录。

## 14.6 Profit / Loss 与 Return

**类型：** Derived。

Card Detail：

```text
Profit/Loss_i(t) = Item Market Value_i(t) - Item Purchase Cost_i(t)
Return_i(t) = Profit/Loss_i(t) ÷ Item Purchase Cost_i(t) × 100%
```

Home Partial Purchase Price：

```text
Paid Market Value(t) = Σ[i∈P(t)] MP_i(t) × Q_i(t)
Profit/Loss(t) = Paid Market Value(t) - Total Paid(t)
Return(t) = Profit/Loss(t) ÷ Total Paid(t) × 100%
```

异常：

- Purchase Price 为 NULL：不参与成本、Profit/Loss 和 Return。
- Market Price 无效：该 Item 不进入 `P(t)`。
- 分母为 0：Return 展示 `--`，不得返回 Infinity、NaN 或伪造 0%。
- 金额正数显示 `+`，负数显示 `-`，零值不强制显示正号；最终符号与小数格式沿用页面金额格式。

## 14.7 Home Performance 图表点位与 Tooltip

Home 曲线每个节点必须生成以下 Derived 数据：

```text
Date(t) = 统计节点日期
Market Value(t) = Portfolio Market Value_F(t)
Qty(t) = Σ 当前 Folder 在 t 有效 Item 的 Q_i(t)
Daily Change(t) = Market Value(t) - Market Value(t_prev)
Qty Change(t) = Qty(t) - Qty(t_prev)
```

为拆分 Market 与 Portfolio，统一把不存在时的 Quantity 视为 0，并对 `t_prev` 与 `t` 的 Item 并集计算：

```text
Market Change(t)
= Σ [MP_i(t) - MP_i(t_prev)] × Q_i(t_prev)

Portfolio Change(t)
= Daily Change(t) - Market Change(t)
```

解释：

- Market Change 只隔离原有持仓因单位市场价格变化产生的价值变化。
- Portfolio Change 是资产新增、删除与 Quantity 变化产生的剩余变化。
- 两者必须满足 `Daily Change = Market Change + Portfolio Change`。
- 新增 Item 在 `t_prev` 的 Quantity 视为 0；删除 Item 在 `t` 的 Quantity 视为 0。
- Daily Change 只作为 Home Performance 的内部计算中间值和校验值，不在 Home Performance Tooltip 中额外展示。

示例：上一节点持有 10 张、单价 `$10`；当前节点单价 `$12` 且新增 2 张：

```text
Previous Market Value = $10 × 10 = $100
Current Market Value = $12 × 12 = $144
Daily Change = $144 - $100 = +$44
Market Change = ($12 - $10) × 10 = +$20
Portfolio Change = $44 - $20 = +$24
Qty = 12 (+2)
```

Home Performance Tooltip 只展示 Date、Market、Portfolio、Qty。Market 或 Portfolio 为 0 时可按现有 UI 规则省略对应明细行，但 Qty 必须展示，Qty 无变化仍展示 `Qty: N`。不得在 Home Performance Tooltip 中额外展示 Daily Change 行。

## 14.8 Card Detail Performance 图表点位

正常状态：

```text
Chart Value(t) = Profit/Loss_i(t)
Daily Change(t) = Profit/Loss_i(t) - Profit/Loss_i(t_prev)
Market Value(t) = MP_i(t) × Q_i(t)
Qty(t) = Q_i(t)
```

Tooltip 展示 Date、Daily Change、Market Value、Profit/Loss、Qty。

Purchase Price 缺失状态：

```text
Chart Value(t) = Market Value_i(t)
Daily Change(t) = Market Value_i(t) - Market Value_i(t_prev)
Qty(t) = Q_i(t)
```

Tooltip 展示 Date、Daily Change、Market Value、Qty，不展示 Profit/Loss、Return 或 Purchase Cost。

若 `t_prev` 不存在，Daily Change 展示 `--`。Market Price 在整个范围无有效数据时进入 No Data，不展示虚假点位。

## 14.9 历史 Quantity

Quantity 是 Collection Item 的 Direct 历史状态，Performance 使用目标日期有效值。

```text
08/01: Qty = 1
08/05: Qty 修改为 3

08/01 历史点使用 Qty 1
08/05 及之后使用 Qty 3
```

Quantity 变化从事件生效时间点起影响后续 Market Value、Purchase Cost、Profit/Loss、Return 和 Qty，不反向覆盖过去。产品只定义结果；开发可选择事件流或历史快照实现。

有效 Collection Item 必须满足 Quantity >= 1。Quantity = 0 或负数不可保存。删除资产必须通过既有 Remove/Delete 操作完成，不使用 Qty = 0 表示删除或资产不存在。

### 14.9.1 Price Mapping Attributes 历史规则

以下 Collection Item 字段会影响 Unit Market Price 的取价口径：

- Grader
- Grade
- Condition
- Language
- Finish

统称为 `Price Mapping Attributes`。

用户修改 Grader / Grade / Condition / Language / Finish 并保存成功后，新取价口径从保存成功时间点开始生效，不得反向覆盖修改之前已经形成的历史价格口径。

示例：

```text
08/01：Raw + Near Mint
08/10：修改为 PSA 9 并保存

08/01 - 08/09：使用原 Raw + Near Mint 价格口径
08/10 起：使用 PSA 9 价格口径
```

不同字段历史生效规则：

| 字段/操作 | 历史生效规则 |
| --- | --- |
| Purchase Price | 修改后追溯至 `performance_start_at`，重新计算历史 |
| Quantity | 从修改时间点向后生效，不回写过去 |
| Grader | 从保存成功时间点向后生效 |
| Grade | 从保存成功时间点向后生效 |
| Condition | 从保存成功时间点向后生效 |
| Language | 从保存成功时间点向后生效 |
| Finish | 从保存成功时间点向后生效 |
| Folder Move | v1.1 上线后发生的 Move：Collection Item 完整可可靠还原历史整体迁移到目标 Folder，Move 请求必须按第 8.5.3 节原子完成；v1.0 Existing Item 缺少历史 Move 事件时，不反向伪造旧 Folder 归属，按第 10.4.1 节从 migration Baseline 起记录后续历史 |
| Delete | 删除时间点及之后不再参与，删除前历史保留 |

### 14.9.2 删除后重新收藏同一卡牌

Collection Item 被删除后，删除前历史保留，删除时间及之后不再参与当前资产。

如果用户之后再次收藏同一卡牌：

1. 创建新的 Collection Item。
2. 新的 Collection Item 拥有新的 `performance_start_at`。
3. 从重新加入 Portfolio 的时间重新开始历史。
4. 不得自动恢复旧 Collection Item 的历史身份。
5. 旧 Item 历史仍作为历史记录存在，但不与新 Item 合并为同一 Collection Item 历史。

## 14.10 Price Change / Trending Change

**类型：** Derived；数据来源为 Market Price API 的当前有效 Unit Market Price 与比较时点有效 Unit Market Price。

```text
Change Amount = Current Price - Comparison Price
Change % = (Current Price - Comparison Price) ÷ Comparison Price × 100%
```

现有页面口径：

- Trending Today：比较当前与 24 小时前价格。
- Search、Collection、Home Most Valuable：30D Change，比较当前与 30 天前价格。
- Card Detail Market Prices：7D Change，比较当前与 7 天前价格。

比较时点缺少精确价格时使用第 13 章方向优先级兜底。Comparison Price 缺失或为 0 时展示 `-/-`，不得展示 Infinity 或 NaN。百分比不受货币切换影响。

Today / 7D / 30D 的业务时区与日切逻辑沿用 v1.0。日统计每天更新一次。

## 14.11 货币切换

支持币种沿用 v1.0：USD、EUR、JPY、GBP、CAD、AUD、NZD、SGD。

Market Price 基础币种统一为 USD。具体物理接口字段由技术方案映射，不作为产品 Pending 项。如果 Market Price API 已直接返回目标币种金额，则直接使用目标币种原始值。如果需要从基础币种换算，汇率方向定义为“1 USD 可兑换多少 Target Currency”：

```text
Target Amount(t)
= USD Amount(t) × FX Rate(USD → Target, t)
```

汇率接口、刷新机制沿用 v1.0。历史资产金额以 USD 原始值保存；用户切换币种时，使用当前有效 USD → 目标币种汇率统一换算历史金额。缓存只影响性能，不改变产品结果。

切换币种成功后，所有金额从 USD 原始金额重新换算并刷新；百分比使用未格式化金额计算，币种切换前后数值应保持不变。切换失败时保持原币种。

## 14.12 金额与百分比精度

1. 内部计算使用数据源原始精度，不在单卡步骤提前四舍五入。
2. Portfolio 求和、Profit/Loss 和 Return 完成后，UI 最终一步才按当前货币/页面规则格式化。
3. 百分比使用未缩写、未格式化的原始金额计算，最后再格式化。
4. K / M / B 仅为展示缩写，不改变真实值，不得把缩写值作为下一步输入。
5. 所有币种完整金额统一保留 2 位小数。
6. 根据当前页面允许的最大展示宽度判断是否需要缩写。
7. 判断长度时按最终完整展示字符串计算，包括货币符号、正负号、千分位、数字、小数点和小数位。
8. 超过页面允许长度后使用 K / M / B。
9. 缩写最多保留 2 位小数。
10. 缩写后的无意义尾 0 删除。
11. K / M / B 只用于展示，不参与计算。

示例：

```text
真实金额 = 1,245,600.238
计算输入 = 1245600.238
UI 可显示 = $1.25M
```

```text
Market Value = 103
Cost = 100
Return = (103 - 100) ÷ 100 × 100% = 3%
```

### 14.12.1 页面展示长度基准

表中的字符串用于定义 UI 可承受的展示宽度，不是要求该数值永远完整显示。实际金额先按当前金额格式生成完整字符串；如果完整字符串超过该区域基准宽度，则使用 K / M / B。

| 页面/区域 | 完整金额展示长度基准 |
| --- | --- |
| Home 顶部 Portfolio | `¥12,450.88` 对应展示宽度 |
| Home Trending Today 价格 | `NZ$10,000,000.11` 对应展示宽度 |
| Scan Result 卡片价格 | `NZ$10,000,000.11` 对应展示宽度 |
| Review Your Matches - Our Match 价格 | `NZ$10,000,000` 对应展示宽度 |
| Review Your Matches - Top Match 价格 | `NZ$10,000,000.11` 对应展示宽度 |
| Collection Portfolio 总金额 | `NZ$10,000,000` 对应展示宽度 |
| Collection / Search 卡牌列表价格 | `NZ$10,000,000.11` 对应展示宽度 |

### 14.12.2 K / M / B

| 单位 | 含义 |
| --- | --- |
| K | Thousand |
| M | Million |
| B | Billion |

示例：

| 原始数值 | 展示 |
| --- | --- |
| 10,000 | 10K |
| 10,500 | 10.5K |
| 12,450 | 12.45K |
| 1,000,000 | 1M |
| 1,250,000 | 1.25M |
| 10,000,000 | 10M |
| 1,250,000,000 | 1.25B |

不得展示：

```text
10.00K
10.50K
1000K
1000M
```

应分别展示为：

```text
10K
10.5K
1M
1B
```

如果缩写四舍五入后达到 1000 个当前单位，必须升级单位。例如 `999.995K` 不得展示为 `1000K`，应展示为 `1M`；`1000M` 应展示为 `1B`。

### 14.12.3 负零处理

任何经过计算或格式化产生的 `-0`、`-0.00`、`-0%`，如果真实结果在显示精度上为 0，统一显示为 `0`、`0.00`、`0%`，不得显示负零。

## 14.13 NULL 与异常显示

1. NULL 表示数据不存在，不自动等价为 0。
2. Purchase Price NULL：不参与成本和收益计算。
3. Market Price NULL：历史按第 13 章兜底；当前仍无有效值时金额展示 `--` 并排除计算。
4. Daily Change 基准值不存在：Daily Change 展示 `--`。
5. 百分比分母为 0：Performance Return 展示 `--`；Price Change 展示 `-/-`。
6. 无可用历史数据：不绘制虚假曲线或 Tooltip。

# 15. Profile 订阅状态

## 15.1 Free 状态

- 顶部显示订阅小标识。
- 显示 Subscription Banner。
- Banner 点击打开完整 Subscription Page，并记录 `source_page=Profile`、`entry_source=profile_banner`。
- Restore 可见。

## 15.2 Premium 状态

- 隐藏顶部升级入口。
- 不显示升级 Banner。
- 展示 Premium 状态。
- Restore 仍可见。
- 不展示 SKU 切换或订阅升级入口。

## 15.3 页面交互与控件规则

| 控件/区域 | 显示条件 | 可点击条件 | 点击行为 | 目标页面/容器 | 成功结果 | 失败/取消结果 | 状态保留 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Premium Banner / Upgrade Now | Profile；游客或账号用户；Free 状态 | Subscription Page 未打开 | 记录 `source_page=Profile`、`entry_source=profile_banner`；打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 进入 Subscription Success，Start Exploring 后进入 Profile Premium；Restore Success 后关闭 Subscription Page，返回 Profile Premium 并显示 `Premium restored` Toast | Close、Cancelled、Pending、Failed、Restore Not Found/Failed 后回到 Profile Free；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留 Profile 滚动位置、账号状态和已加载数据；不清空 `source_page` |
| Premium Banner | Profile；Premium 状态 | - | 不显示，用户无法点击 | - | - | - | - |
| 顶部 Premium 入口 | Profile；Free 状态 | Subscription Page 未打开 | 记录 `source_page=Profile`、`entry_source=top_subscription_entry`；打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 进入 Subscription Success，Start Exploring 后进入 Profile Premium；Restore Success 后关闭 Subscription Page，返回 Profile Premium 并显示 `Premium restored` Toast | Close、Cancelled、Pending、Failed、Restore Not Found/Failed 后回到 Profile Free；Restore Not Found 显示 `No subscription found` Toast；Restore Failed 显示 Alert + OK | 保留 Profile 滚动位置、账号状态和已加载数据 |
| 顶部 Premium 入口 | Profile；Premium 状态 | - | 不显示，用户无法点击 | - | - | - | - |
| Restore | Profile；所有用户身份和权益状态 | 当前无 Restore 请求进行中 | Restore 进入 Blocking Loading；禁止重复点击；调用 StoreKit 重新同步当前 Apple 购买上下文；请求完成前不跳转、不进入 Subscription Success | 当前 Profile 页面 | Success：刷新 Profile 为 Premium 状态，更新 Premium 相关 UI，隐藏升级 Banner 和顶部 Premium 入口，显示 `Premium restored` Toast；不进入 Subscription Success | Not Found：Profile 保持当前页面，按最新 verified current entitlements 刷新为 Free，显示 `No subscription found` Toast；Failed / Timeout：显示 Restore Failed Alert，点击 OK 后保持 Profile，并保持原权益状态 | 保留 Profile 当前页面、滚动位置、账号状态和已加载数据；不创建 Subscription Page 或 Paywall；Restore Success / Not Found / Failed / Timeout 均不得清空上下文 |

# 16. 不支持订阅升级

v1.1 不支持：

- Weekly 与 Yearly 之间升级或降级
- 已有订阅用户切换自动续订 SKU
- 按比例抵扣或退款
- 立即生效或下周期生效的方案切换
- Lifetime 与周期订阅之间转换

Premium 状态用户不展示升级 CTA 或其他 SKU 切换入口。

# 17. v1.1 Navigation & Interaction Matrix

本章是 v1.1 新增或修改交互的汇总矩阵。页面级详细规则以第 3-15 章为准；本章用于让开发快速确认入口、目标容器和返回状态。

| 当前页面 | 用户状态 | 控件 | 点击前状态 | 点击结果 | 目标 | 返回规则 |
| --- | --- | --- | --- | --- | --- | --- |
| Subscription Page | Free / 游客 / 账号用户 | Weekly Plan | Yearly 或 Lifetime 已 Selected；商品价格可为 Loading | Weekly 变 Selected，原 Plan 取消 Selected，`selected_product_id=weekly`；不拉起 Apple Purchase | 当前 Subscription Page Plan Radio Group | 留在 Subscription Page，保留 `source_page`、`entry_source` 和页面滚动位置 |
| Subscription Page | Free / 游客 / 账号用户 | Yearly Plan | 页面首次正常加载默认 Selected；或其他 Plan 已 Selected | Yearly 变 Selected，原 Plan 取消 Selected，`selected_product_id=yearly`；不拉起 Apple Purchase | 当前 Subscription Page Plan Radio Group | 留在 Subscription Page，保留 `source_page`、`entry_source` 和页面滚动位置 |
| Subscription Page | Free / 游客 / 账号用户 | Lifetime Plan | Weekly 或 Yearly 已 Selected；商品价格可为 Loading | Lifetime 变 Selected，原 Plan 取消 Selected，`selected_product_id=lifetime`；不拉起 Apple Purchase | 当前 Subscription Page Plan Radio Group | 留在 Subscription Page，保留 `source_page`、`entry_source` 和页面滚动位置 |
| Subscription Page | Free / 游客 / 账号用户 | Subscribe | 已有唯一 Selected Product；当前无 Purchase / Restore 请求；Product 可用或可在本次点击中请求；Purchase Pending 期间不可再次提交 | Subscribe 显示 Loading，禁止重复点击；Product 未加载时在 15 秒 Deadline 内请求；可用后购买当前 `selected_product_id` 对应 Apple Product | Apple 系统购买弹窗 | Success + verified 进入 Subscription Success；Cancelled/Failed/Purchase unavailable/Transaction Unverified 停留 Subscription Page 且 Subscribe 恢复可点；Pending 停留 Subscription Page，显示 Pending 提示，Subscribe 暂不可再次提交，Close 可离开，等待 Transaction Update；保留选中 Product、`source_page`、`entry_source` |
| Subscription Page | Free / 游客 / 账号用户 | Close | 页面已展示；未处于 Apple 系统购买弹窗；非 Restore Blocking Loading | 关闭完整 Subscription Page；不改变 Premium；不修改当前 SKU；不触发购买 | 首次启动/冷启动进入 Home；Profile Banner 进入 Profile；Home/Search/Collection/Profile 顶部入口进入实际发起页；Scan Pro 卡片入口进入 Scan | 目标页按当前 Premium 状态渲染；不保留 Plan 作为下次默认项；不清空本次来源日志 |
| Subscription Page | Free / 游客 / 账号用户 | Restore | 当前无 Purchase / Restore 请求 | 整个 Subscription Page 进入 Blocking Loading；最长 15 秒；期间 Close、Plan、Subscribe、Restore、Terms、Privacy、Back 均不可操作 | 当前 Subscription Page | Success：关闭 Page，按 `source_page` 返回来源页并显示 `Premium restored` Toast；Scan Pro 卡片入口进入 Scan 并刷新 `Unlimited scans`，若当前有效 Queue 仍有 Waiting，则 Waiting 按原 Queue 顺序自动进入 Processing。Not Found：按最新 verified current entitlements 刷新为 Free，停留 Subscription Page，显示 `No subscription found` Toast。Failed / Timeout：保持原权益，Restore Failed Alert，OK 后停留 Subscription Page；Timeout 迟到 callback 不得关闭 Page 或跳转 |
| Subscription Page | Free / 游客 / 账号用户 | Terms / Privacy | 页面已展示；Apple 系统购买弹窗未展示；非 Restore Blocking Loading | 跳转系统浏览器，打开 App 官网 Terms of Use / Privacy Policy 对应页面；不关闭订阅业务上下文；不触发购买 | 系统浏览器；URL 沿用 v1.0 当前正式配置 | 用户切回 App 后仍显示 Subscription Page，保留购买前选中 Plan、`source_page`、`entry_source`、页面滚动位置 |
| Subscription Success | Premium | Start Exploring | Subscription Success 已展示；按钮未触发过跳转 | 读取 `source_page` / `entry_source`；不再次检查购买；不再次弹 Paywall；同一页面实例只允许一次正常跳转；不得通过 Back / 侧滑返回旧 Subscription Page | 首次启动/冷启动进入 Home；Profile Banner 进入 Profile；Home/Search/Collection/Profile 顶部入口进入实际发起页；Scan Pro 卡片入口进入 Scan；来源丢失进入 Home | 目标页按 Premium 渲染；Scan 目标页刷新为 Premium / `Unlimited scans` 状态；Scan Pro 来源且当前有效 Queue 仍有 Waiting 时，Waiting 按原 Queue 顺序自动进入 Processing；跳转失败时停留 Subscription Success，按钮恢复可点，不重新发起购买 |
| Subscription Paywall Modal | Free / 游客 / 账号用户 | Weekly / Yearly / Lifetime Plan | Modal 已打开；Yearly 首次正常加载默认 Selected；商品价格可为 Loading | 点击未选中 Plan 后该 Plan 变唯一 Selected；点击已选 Plan 保持 Selected；不拉起 Apple Purchase | 当前 Paywall Modal Plan Radio Group | 保留背景页、`blocked_action`、Tab、Range、Queue、表单和滚动位置 |
| Subscription Paywall Modal | Free / 游客 / 账号用户 | Subscribe | Modal 已打开；当前无 Purchase / Restore 请求；Product 可用或可在本次点击中请求；Purchase Pending 期间不可再次提交 | Subscribe 显示 Loading，禁止重复点击，购买当前 Selected Product；Purchase 期间 Restore 不可触发 | Apple 系统购买弹窗 | Success + verified 关闭 Modal、显示 `Premium unlocked` Toast；如存在可执行且仍有效的 `blocked_action`，则自动执行；如不存在可自动执行的 `blocked_action`，则按来源场景恢复页面状态；未获得 Premium 时按 Functional Paywall 统一未成功规则处理；Pending 保持 Modal，显示 Pending 提示，Subscribe 暂不可再次提交，Close 可离开，等待 Transaction Update |
| Subscription Paywall Modal | Free / 游客 / 账号用户 | Restore | Modal 已打开；当前无 Purchase / Restore 请求 | 整个 Paywall 进入 Blocking Loading；最长 15 秒；期间 Plans、Subscribe、Restore、Close、Scrim、Terms、Privacy 均不可操作；背景页仍不可操作 | 当前 Paywall Modal | Success：关闭 Modal，显示 `Premium restored` Toast；如存在可执行且仍有效的 `blocked_action`，自动执行该 `blocked_action`；如不存在可自动执行的 `blocked_action`，只按来源场景恢复页面状态。Not Found：按最新 verified current entitlements 刷新为 Free，Modal 保持打开，显示 `No subscription found` Toast，`blocked_action` 继续保存但不执行。Failed / Timeout：保持原权益，Restore Failed Alert，OK 后回到原 Paywall；Timeout 迟到 callback 不得关闭 Paywall 或执行旧动作 |
| Subscription Paywall Modal | Free / 游客 / 账号用户 | Close / Scrim | Modal 已打开；Apple 系统购买弹窗未展示；非 Restore Blocking Loading | 关闭 Modal；不执行 `blocked_action`；不改变 Premium；不触发购买 | 触发前页面的同一页面实例和同一容器 | 停留触发前 Tab、Range、Tooltip、Queue、表单、滚动位置和已加载数据 |
| Subscription Paywall Modal | Free / 游客 / 账号用户 | Terms / Privacy | Modal 已打开；Apple 系统购买弹窗未展示；非 Restore Blocking Loading | 跳转系统浏览器，打开 App 官网 Terms of Use / Privacy Policy 对应页面；不关闭 Paywall 业务上下文；不触发购买 | 系统浏览器；URL 沿用 v1.0 当前正式配置 | 用户切回 App 后仍显示 Paywall Modal，保留当前 Plan、背景页、`blocked_action`、Tab、Range、Queue 和滚动位置 |
| Home | Free | Performance Tab | Home Header Tab 可见 | 切换到 Home Performance 容器；不跳页；不直接打开 Paywall | Home 当前页面 Performance 容器 | 显示 Performance 锁定态；保留 Home 页面实例和滚动位置 |
| Home | Premium | Performance Tab | Home Header Tab 可见 | 切换到 Home Performance 容器 | Home 当前页面 Performance 容器 | 显示完整 Performance；保留已选 Range 和已加载数据 |
| Home Performance | Free | Unlock Performance CTA / 锁定区域 | Performance 锁定态已展示 | 保存 `blocked_action=open_home_performance`，打开 Subscription Paywall Modal | Subscription Paywall Modal | Purchase Success：`Premium unlocked` Toast 后返回 Home Performance 并加载完整内容；Restore Success：`Premium restored` Toast 后返回 Home Performance 并加载完整内容；Close/Scrim/Cancelled/Failed/Pending/Restore Not Found 后仍显示锁定态 |
| Home | Free | 顶部 Premium 入口 | Home 一级页面，入口可见 | 记录 `source_page=Home`、`entry_source=top_subscription_entry`，打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 后 Start Exploring 进入 Home；Close/Cancelled/Pending/Failed/Restore Not Found 后回到 Home Free |
| Home Overview Portfolio Chart | Free | 1D / 7D / 15D / 1M / 3M | 普通历史图表；当前 Range 数据可用；无同 Range 请求进行中 | 设为 Selected；请求或读取对应 Range 数据 | Home Overview Portfolio Chart | 成功刷新图表；失败保留点击前 Range，控件恢复可点 |
| Home Overview Portfolio Chart | Free | 1Y | 当前为 Home Overview 普通历史图表；原 Range 为 1D / 7D / 15D / 1M / 3M | 不立即切换 Selected Range；不请求 1Y 数据；保存原 Range、`requested_range=1Y`、`source_chart=home_overview`、当前 Folder、Overview Tab、Scroll 和 `blocked_action=open_extended_price_history`；打开 Functional Paywall | Subscription Paywall Modal | Purchase Success 显示 `Premium unlocked`、Restore Success 显示 `Premium restored`；成功后返回 Home Overview，保持当前 Folder，自动选中并加载 1Y Portfolio Chart；未获得 Premium 时保持原 Range、Folder、Overview Tab、Scroll 和已加载图表数据 |
| Home Overview Portfolio Chart | Premium | 1D / 7D / 15D / 1M / 3M / 1Y | 普通历史图表；当前 Range 数据可用；无同 Range 请求进行中 | 设为 Selected；请求或读取对应 Range 数据 | Home Overview Portfolio Chart | 成功刷新图表；失败保留点击前 Range，控件恢复可点 |
| Scan | Free | Pro / scans remaining 卡片 | Scan 页面展示 `Pro`、`X scans remaining`、`Tap to get unlimited scans`；顶部 Premium 入口不显示 | 记录 `source_page=Scan`、`entry_source=scan_pro_card`，打开完整 Subscription Page；不创建 Waiting；不发送识别请求 | Subscription Page Full Page | Purchase Success 后进入 Subscription Success，Start Exploring 进入 Scan 并刷新 `Unlimited scans`；Restore Success 返回 Scan、刷新 Premium / `Unlimited scans` 并显示 `Premium restored` Toast；若当前有效 Queue 仍有 Waiting，则 Waiting 按原 Queue 顺序自动进入 Processing；Close/Cancelled/Pending/Failed/Restore Not Found 后回到 Scan Free 并保留 Queue；若 Queue 已按 v1.0 退出规则清理，则不恢复旧 Waiting |
| Home Performance | Premium | 1D / 7D / 15D / 1M / 3M / 1Y | 当前 Range 数据可用；无同 Range 请求进行中 | 选中点击 Range，取消旧 Range，关闭旧 Tooltip，请求或读取对应数据 | Home Performance Chart | 成功刷新图表和指标；失败保留点击前 Range，控件恢复可点 |
| Home Performance | Premium | Chart Point / 无节点区域 | 图表已加载 | 有效节点展示 Tooltip；点击另一节点切换 Tooltip；点击无节点区域关闭 Tooltip | Home Performance Chart Tooltip | 保留当前 Range、图表和滚动位置 |
| Home Performance | Premium | Partial Purchase Price Info | Partial Purchase Price Missing 状态显示 Info | 打开小型 Popover，展示 `Profit and return are calculated only from cards with purchase prices.` | Info 图标旁 Popover | 再次点击 Info 或点击 Popover 外部区域关闭 Popover，保留 Range 和 Tooltip 状态 |
| Card Detail | Free | Performance Tab | 当前 Card Detail 存在 `card_id` / `collection_item_id` | 切换到当前 Card Detail 的 Performance Tab；不创建新的 Card Detail | 当前 Card Detail Performance Tab | 显示锁定态；保留当前 Card Detail 页面实例和滚动位置 |
| Card Detail Performance | Free | Unlock CTA / 锁定区域 | 锁定态已展示 | 保存 `blocked_action=open_card_performance`、`card_id`、`collection_item_id`、Tab、Range，打开 Paywall | Subscription Paywall Modal | Purchase Success 显示 `Premium unlocked`，Restore Success 显示 `Premium restored`；成功后回到当前 Card Detail Performance 并加载完整内容；关闭、购买失败、Restore Not Found 或 Restore Failed 回到当前 Card Detail Performance 锁定态 |
| Card Detail Performance | Premium | 1D / 7D / 15D / 1M / 3M / 1Y | 当前 Range 数据可用；无同 Range 请求进行中 | 选中点击 Range，取消旧 Range，关闭旧 Tooltip，请求或读取对应数据 | 当前 Card Detail Performance Chart | 成功刷新图表和指标；失败保留点击前 Range，控件恢复可点 |
| Card Detail Performance | Premium | Chart Point / 无节点区域 | 图表已加载 | 有效节点展示 Tooltip；点击另一节点切换 Tooltip；点击无节点区域关闭 Tooltip | 当前 Card Detail Performance Chart Tooltip | 保留当前 Range、`card_id`、`collection_item_id` 和滚动位置 |
| Card Detail Performance | Premium | 当前 Collection Item | 同一卡牌存在多个 Collection Item | 只计算当前 Card Detail 上下文中的 `collection_item_id`，不聚合同卡其他 Collection Item | 当前 Card Detail Performance | 保留当前 Card、当前 Collection Item、当前 Tab 和滚动位置 |
| Card Detail Performance | Premium / Free | Edit Collection Item | Purchase Price 缺失状态；存在 `card_id` 和 `collection_item_id` | 使用当前 card / collection item 切换到既有 Collection Item 编辑上下文；不创建新的 Card Detail | 当前 Card Detail 内 Collection Item Tab / 编辑容器 | 保存成功回到当前 Card Detail Performance 并重新计算；保存失败保留输入内容且不更新 Performance |
| Card Detail Price History | Free | 1D / 7D / 15D / 1M / 3M | 普通历史图表；当前 Range 数据可用；无同 Range 请求进行中 | 设为 Selected；请求或读取对应 Range 数据 | Card Detail Price History | 成功刷新图表；失败保留点击前 Range，控件恢复可点 |
| Card Detail Price History | Free | 1Y | 当前为 Card Detail 普通历史图表；原 Range 为 1D / 7D / 15D / 1M / 3M | 不立即切换 Selected Range；不请求 1Y 数据；保存原 Range、`requested_range=1Y`、`source_chart=card_detail_price`、当前 Card Detail 上下文、当前 Scroll 和 `blocked_action=open_extended_price_history`；打开 Functional Paywall | Subscription Paywall Modal | Purchase Success：关闭 Paywall，显示 `Premium unlocked`，返回同一 Card Detail，自动选中并加载 1Y；Restore Success：关闭 Paywall，显示 `Premium restored`，返回同一 Card Detail，自动选中并加载 1Y；未获得 Premium 时保持原 Range、当前 Card、Scroll 和已加载图表数据 |
| Card Detail Price History | Premium | 1D / 7D / 15D / 1M / 3M / 1Y | 普通历史图表；当前 Range 数据可用；无同 Range 请求进行中 | 设为 Selected；请求或读取对应 Range 数据 | Card Detail Price History | 成功刷新图表；失败保留点击前 Range，控件恢复可点 |
| Scan | Free quota > 0 | Capture / Gallery Submit | Scan 页面可提交新图片 | 按 v1.0 创建扫描项并发送识别请求；Free 预占 1 次额度 | 当前 Scan Queue | 进入 Processing；发送前失败不消耗或返还预占额度，保留 Queue |
| Scan | Free quota = 0 | Capture / Gallery Submit | 点击前剩余额度已经为 0；本次图片尚未进入 Queue | 直接打开 Subscription Paywall Modal；不创建 Waiting；不创建 Scan Item；不向 Queue 新增本次图片；不发送识别请求；不扣额度；只保存 `source_context=scan_quota_zero` 等来源上下文，不保存可自动执行扫描的 `blocked_action` | Subscription Paywall Modal | Purchase Success 显示 `Premium unlocked`，Restore Success 显示 `Premium restored`；成功后返回 Scan，页面进入可扫描状态，用户重新点击 Capture 或 Gallery；未成功时按 Functional Paywall 统一未成功规则处理，不创建 Waiting，不伪造图片 |
| Scan | Premium | Capture / Gallery Submit | Scan 页面可提交新图片 | 按 v1.0 创建扫描项并发送识别请求；不消耗 Free quota | 当前 Scan Queue | 进入 Processing；发送失败按 v1.0 Failed 或上传失败规则处理 |
| Scan Queue | Free / Premium | Queue 最大数量 | Waiting / Processing / Matched / Failed / No Match Found 仍在待处理 Queue 中 | 每个 Item 均占用 1 个 Queue 位置，Waiting 也计入最大 10 张 | 当前 Scan Queue | 不得因为 Waiting 未发送请求而突破 10 张上限 |
| Scan | Free / Premium | Close / Exit | Queue 中存在 Waiting | 沿用 v1.0 未完成 / 未收藏扫描内容退出确认；不因 Waiting 禁止退出；不新增第二套弹窗 | v1.0 退出确认 | 取消退出：保留 Scan 和 Waiting；确认退出：按 v1.0 清理本次未完成 Queue，Waiting 一起清除且不扣额度 |
| Scan | Free / Premium | Done（Matched + no Processing） | Queue 中至少 1 张 Matched，且不存在 Processing；可同时存在 Waiting、Failed 或 No Match Found | 沿用 v1.0：1 张 Matched 进入单张 Review，2 张及以上 Matched 进入多张 Review；只携带 Matched | Review Your Matches + Collection Item | 仅 Matched 项进入 Review；Waiting 保留在 Scan Queue，不删除、不变成 Failed、不扣额度；失败时停留 Scan 并保留 Queue |
| Scan | Free / Premium | Done（Only Waiting / 无 Matched） | Queue 中不存在 Matched；可存在 Waiting、Failed 或 No Match Found | Done 不可点击 | 当前 Scan 页面 | 保留完整 Queue；Waiting 保持 Waiting |
| Scan | Free / Premium | Done（Matched + Processing + Waiting） | Queue 中存在 Processing；可同时存在 Matched 和 Waiting | Done 不可点击 | 当前 Scan 页面 | Processing 结束后重新计算 Done；若 Matched Item Count > 0 且 Processing Item Count = 0，则 Done 可点击，即使仍存在 Waiting |
| Scan | Free | Waiting Card Body | Queue 中存在 `Waiting to scan` 项；点击非删除区域 | 打开 Subscription Paywall Modal；保存 `blocked_action=resume_waiting_scan`；不可进入 Review；不允许 Tap to Retry；不发请求；不扣额度 | Subscription Paywall Modal | Purchase Success 显示 `Premium unlocked` Toast，Restore Success 显示 `Premium restored` Toast；成功后 Waiting 按原 Queue 顺序进入 Processing 并自动继续扫描；Paywall Close 返回 Scan 且 Waiting 保持；Purchase Cancelled/Pending/Failed、Restore Not Found 或 Restore Failed 后 Waiting 保持 |
| Scan | Free | Waiting Card Delete / Remove | Queue 中存在 `Waiting to scan` 项；点击 Delete / Remove 按钮 | 删除当前 Waiting Item；阻止事件向 Card Body 冒泡；不得打开 Paywall；不发请求；不扣额度 | 当前 Scan Queue | 当前 Waiting Item 从 Queue 移除；其他 Queue Item 状态不变 |
| Collection Folder Sheet | Free Folder 总数已达 2 | Add Folder / Add New Folder | Folder Sheet 已打开；默认 Folder 计入总数 | 不创建 Folder；保存 `blocked_action=create_folder`；打开 Paywall | Subscription Paywall Modal | Purchase Success 显示 `Premium unlocked`，Restore Success 显示 `Premium restored`；成功后关闭 Paywall 并自动打开 v1.0 Create Folder 弹窗；关闭、购买失败、Restore Not Found 或 Restore Failed 后不创建 Folder |
| Collection Item / Folder | Free / Premium | Confirm Folder Move | 用户选择 Target Folder 并确认 Move | Move 进入 Loading，最长 15 秒，防止重复提交；全部可可靠还原的 Performance 历史随 Collection Item 整体迁移 | Portfolio / Folder List / Home Performance | Success：Item 归属 Target Folder，完整可可靠还原历史归属 Target Folder，Source / Target Folder 立即重新计算，Folder List 和受影响 Home Performance 刷新 |
| Collection Item / Folder | Free / Premium | Folder Move Failed / Timeout | Move 请求失败或 15 秒 Timeout | 不进行部分迁移；Item 继续属于原 Source Folder；页面恢复可操作 | 当前页面 / Folder List | 使用现有错误反馈 / Timeout 规则；迟到旧请求不得造成重复 Move |
| Collection Item / Folder | Free / Premium | Folder Move Target 失效 | Target Folder 被另一设备删除 | 服务端 Move 失败；不移动 Collection Item；刷新 Folder List | 当前页面 / 默认 Folder 或最新有效状态 | Item 继续保持有效 Source Folder 归属；若 Source Folder 也失效，按远端 Folder 删除规则回默认 Folder / 最新有效状态，不恢复已删除 Folder |
| StoreKit Transaction Update | Purchase Pending 后续成功 | 原 Subscription Page / Paywall 仍有效 | 按正常 Purchase Success 继续处理 | 原订阅容器或触发前页面 | Page 来源进入 Subscription Success；Paywall 来源关闭 Modal、显示 `Premium unlocked`；如存在可执行且仍有效的 `blocked_action`，则自动执行；如不存在可自动执行的 `blocked_action`，则按来源场景恢复页面状态 |
| StoreKit Transaction Update | Purchase Pending 后续成功 | 用户已关闭原容器、切换页面、App 重新进入或原 `blocked_action` 已失效 | 更新 Premium 与本地 entitlement cache，刷新当前页面 Premium 状态；App 前台时显示 `Premium unlocked` Toast | 当前页面 | 不重新打开旧 Paywall / Subscription Page，不进入旧 Subscription Success，不执行失效 `blocked_action`，不强制跳回旧页面 |
| Home / Card Detail Performance | Premium 变 Free | Apple-verified entitlement state 经 StoreKit refresh，或服务端对当前设备已知同一 Apple 购买链路的 lifecycle correction，确认当前无有效 Premium entitlement | 重新计算全部 Apple-verified entitlements；仍存在其他有效 entitlement 时保持 Premium；不存在任何有效 entitlement 时当前 Performance 区域刷新为 Free 锁定态；不自动弹 Subscription Page 或 Paywall；不强制跳 Home | 当前页面当前 Tab | 保留当前页面、Card、Tab、Range 和滚动位置；用户后续点击 Unlock 再打开 Paywall；普通历史图表当前为 1Y 时自动切 3M |
| Profile | Free | Premium Banner / Upgrade Now | Banner 可见 | 记录 `source_page=Profile`、`entry_source=profile_banner`，打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 后 Start Exploring 进入 Profile；Restore Success 关闭 Subscription Page，返回 Profile 并显示 `Premium restored` Toast；Close/Cancelled/Pending/Failed/Restore Not Found 后回到 Profile Free |
| Profile | Free | 顶部 Premium 入口 | 入口可见 | 记录 `source_page=Profile`、`entry_source=top_subscription_entry`，打开完整 Subscription Page | Subscription Page Full Page | Purchase Success 后 Start Exploring 进入 Profile；Restore Success 关闭 Subscription Page，返回 Profile 并显示 `Premium restored` Toast；Close/Cancelled/Pending/Failed/Restore Not Found 后回到 Profile Free |
| Profile | Premium | Premium Banner / 顶部 Premium 入口 | Profile 已按 Premium 渲染 | 不显示，用户无法点击 | - | - |
| Profile | Free / Premium / Unknown | Restore | 当前无 Restore 请求 | 当前 Profile 进入 Blocking Loading；最长 15 秒；Profile 所有业务操作不可点击；请求完成前不跳转、不进入 Subscription Success | 当前 Profile 页面 | Success：保持 Profile，刷新 Premium UI，显示 `Premium restored` Toast；Not Found：保持 Profile，按最新 verified current entitlements 刷新为 Free，显示 `No subscription found` Toast；Failed / Timeout：显示 Restore Failed Alert，OK 后保持 Profile并保持原权益状态；迟到 callback 不得恢复旧交互 |
| Splash / 首次安装启动 | 未知 | 系统 ATT 弹窗 | 网络授权流程已结束；ATT status 为 `notDetermined` | 请求 ATT；用户选择授权或拒绝 | iOS ATT 系统弹窗 | ATT 返回后继续后续 Onboarding；authorized/denied/restricted 均不得阻止进入 App |
| Any Premium-gated action | Unknown | 依赖 Premium 判断的功能入口 | 当前权益状态 Unknown | 先发起 entitlement Refresh，最长 15 秒；不直接按 Free 或 Premium 处理 | 当前页面 | Premium：执行 Premium 逻辑；Free：执行 Free / Paywall 逻辑；Timeout / Failed 且仍 Unknown：保持当前页面，显示失败 / Timeout 反馈；Scan 不得错误消费 Free Quota |
| Subscription Page / Paywall | Free / 游客 / 账号用户 | Product Partial Load | 部分 StoreKit Product 成功、部分失败 | 可用 SKU 正常展示真实本地化价格并可购买；缺失 SKU 显示 Unavailable 或不可用状态 | 当前订阅容器 | Yearly 不可用时自动选择第一个可用 Product；不可用 SKU 不得使用 Prototype 价格购买 |
| Subscription Page / Paywall | Free / 游客 / 账号用户 | Product All Failed / Timeout | 所有 Product 均不可用或 Product Loading 达到 15 秒 | `Subscribe` 保留；用户点击可重新请求 Products；本次操作最多 15 秒 | 当前订阅容器 | 显示 `Unable to connect to the App Store. Please try again.`；Timeout 后不继续本轮自动请求 |
| Subscription Page / Paywall | Free / 游客 / 账号用户 | Purchase unavailable | Apple 购买能力不可用或 StoreKit 无法开始购买 | 不授予 Premium；不关闭订阅容器；Subscribe 恢复可点 | 当前订阅容器 | 显示 `Purchases are unavailable right now. Please try again later.`；不自动重试 Purchase |
| Subscription Page / Paywall | Free / 游客 / 账号用户 | Transaction Unverified | Apple 返回 Transaction 但客户端验证失败 / unverified | 不授予 Premium；不进入 Subscription Success；不执行 `blocked_action`；不记录成功收入 | 当前订阅容器 | 按 Purchase Failed 处理；后续 Transaction Listener 得到 verified 后再按后续 Success 处理 |
| Subscription Page / Paywall | Free / 游客 / 账号用户 | External entitlement → Premium | 当前无 Purchase / Restore；StoreKit Transaction Update 或 entitlement refresh 确认 Premium | 更新 Premium；关闭当前订阅容器；显示 `Premium unlocked` | Source Page 或触发前页面 | Subscription Page 返回 `source_page`；Paywall 如存在可执行且仍有效的 `blocked_action` 则自动执行；不存在或已失效则按当前页面恢复，不执行旧操作 |
| App Relaunch | 未知 | Startup Entitlement Check | App 被杀 / 重启后 | 不恢复旧 Paywall、Restore Loading、Restore Failed Alert、Subscription Success、旧 `blocked_action` 或旧 Product Loading | 正常启动流程 | 已确认 Premium 时按 Premium 启动；Free 时按正常 Free 冷启动；不重新播放旧 Subscription Success |
| Scan | Free | Quota 返还 + Waiting | Processing 因 Failed / Upload Failure / Network Error / Timeout / Service Error 返还预占额度，Queue 中仍有 Waiting | 按原 Queue 顺序从最前 Waiting 重新尝试额度预占 | 当前 Scan Queue | 预占成功后 Waiting → Processing 并自动提交；持续到 Remaining = 0 或没有 Waiting |
| Scan | Free / Premium | Failed Retry | Failed Item 可 Retry | Premium 不消耗 Free Quota；Free 重新向服务端原子预占；Free Remaining = 0 时 Failed → Waiting 并打开 Paywall | 当前 Scan Queue / Paywall | 成功预占后 Failed → Processing；用户不用重新拍摄；Retry 必须重新判断 Quota |
| Scan | Free / Premium | Processing Delete / Remove | v1.0 允许删除 Processing Item，且请求已发送 | UI 立即移除该 Item；该 Item 立即不再计入 Processing Item Count，并按当前可见 Queue 重新计算 Done；不立即返还 Free Quota；后台等待最终结算 | 当前 Scan Queue | Matched / No Match Found 消耗 1 次；技术 Failed / Timeout / Service Error 返还；后台 Quota 结算不得继续阻塞 Done；迟到结果不得重插已删除卡片 |
| Scan | Free / Premium | Queue = 10 再新增 | Queue 中待处理 Item 数 = 10 | Capture 不创建第 11 个 Item；Gallery 不能超过 `remaining_queue_capacity` | 当前 Scan 页面 | capacity = 0 时使用当前 App 轻量提示样式说明本批 Queue 已满 |
| Home Performance | Premium | 切换 Folder | 当前在 Performance Tab 和某个 Range | 保持 Performance Tab 与当前 Range；关闭旧 Tooltip 和 Info Popover；加载新 Folder Performance | Home Performance | 成功展示新 Folder 指标与 Chart；Empty Folder 展示 Empty Portfolio；失败 / Timeout 保持当前选择并展示错误，旧请求不得覆盖 |
| Home Overview Portfolio Chart | Premium → Free | 当前选中 1Y | 权益刷新确认变 Free | 不弹 Paywall；不离开 Home；1Y 恢复锁定；自动切换到 3M | Home Overview Portfolio Chart | 加载 3M 数据；保持当前 Folder、Overview Tab、Scroll；Free 重新进入不得恢复之前 Premium 保存的 1Y Selected |
| Card Detail Price History | Premium → Free | 当前选中 1Y | 权益刷新确认变 Free | 不弹 Paywall；不离开 Card Detail；1Y 恢复锁定；自动切换到 3M | Card Detail Price History | 加载 3M 数据；保持当前 Card、Tab、Scroll；Free 重新进入不得恢复之前 Premium 保存的 1Y Selected |
| Any Paywall | Free / 游客 / 账号用户 | `blocked_action` 目标失效 | Premium 成功时原 Item / Folder / Card / Queue / Waiting 已不存在 | Premium 正常授予并显示成功 Toast；不得强制执行失效 `blocked_action` | 当前有效页面或安全兜底 | 不重新创建已删除 Item，不恢复已退出 Queue，不跳回不存在的 Folder，不打开失效 Card |
| Functional Paywall | Free / 游客 / 账号用户 | 未获得 Premium | Close、Scrim、Purchase Cancelled / Pending / Failed、Purchase unavailable、Transaction Unverified、Product Loading Failed / Timeout、Restore Not Found / Failed / Timeout | 不执行 `blocked_action`；不进入 Premium 内容；不伪造成功状态；按 Subscription / Restore 章节展示错误 UI | 原业务页面 / 当前 Paywall | 保持或恢复原 Tab / Range / Queue / Folder / Card / Scroll；Pending 保持 Paywall 等待 Transaction Update；Restore Not Found 按最新 entitlement 刷新为 Free；Restore Failed / Timeout 保持原权益 |
| Collection Folder Sheet | Free | 多设备并发 Add Folder | 当前账号 Folder 数可能被其他设备同时修改 | 服务端创建前再次检查 Folder 总数 | Collection / Folder List | 已达 2 时不创建第 3 个 Folder，刷新 Folder List 并按最新 Free 限制状态显示 |
| App Foreground | 任意 | ATT Status Refresh | App 从后台回前台 | 读取当前 ATT Authorization Status 并同步给 Singular；不主动再次弹 ATT | 当前页面 | 不阻断业务；用户在 Settings 修改 ATT 时只更新归因上下文 |

Scan Waiting Card 点击矩阵：

| 当前状态 | 点击区域 | 结果 |
| --- | --- | --- |
| Waiting | Card Body | 打开 Subscription Paywall Modal，保存 `blocked_action=resume_waiting_scan` |
| Waiting | Delete / Remove | 删除该 Item，不打开 Paywall |
| Waiting + Paywall Purchase Success | - | 显示 `Premium unlocked` Toast，Waiting 按原 Queue 顺序进入 Processing |
| Waiting + Paywall Restore Success | - | 显示 `Premium restored` Toast，Waiting 按原 Queue 顺序进入 Processing |
| Waiting + Paywall Close | - | 返回 Scan，Waiting 保持 |

# 18. Google Analytics 订阅价值上报

本章只定义订阅收入和价值上报，不重新定义完整订阅漏斗埋点。现有自定义漏斗事件继续由 Mixpanel 埋点文档管理。

## 18.1 Google Analytics 职责

Firebase / Google Analytics 用于统计：

- 订阅和 Lifetime 购买收入
- 购买金额
- 购买币种
- 购买数量
- 不同 SKU 的收入和购买数量

正式收入统计以 Google Analytics 的应用内购买事件为准；财务对账仍以 App Store Connect 为准。

## 18.2 StoreKit 交易上报

Apple 交易成功后必须：

1. 验证 Apple Transaction。
2. 确认 Transaction 验证成功。
3. 更新本地 Premium 权益。
4. 完成 Apple Transaction。
5. 使用当前项目实际接入的 Firebase Analytics SDK 能力异步上报 Apple verified purchase。

不得上报未经验证的 Transaction。如果当前项目使用 Flutter，允许使用 Firebase Analytics Flutter SDK 对应的标准 Purchase / IAP 收入上报能力。PRD 只约束最终业务结果，不限定必须使用某个 Swift API；`Analytics.logTransaction(transaction)` 如在技术方案中出现，只能作为示例，不得作为强制实现。

## 18.3 收入字段与 SKU 区分

Google Analytics 的购买记录必须包含 Apple 交易对应的：

- `product_id`
- `value`
- `currency`
- `quantity`
- `transaction_id`
- Weekly、Yearly 适用的 subscription 标识

`product_id`、`value`、`currency`、`quantity` 等字段按 Firebase 当前实际 SDK 能力映射。不允许因为具体 SDK 调用形式不同而改变收入统计口径。

Weekly、Yearly、Lifetime 必须使用不同 Product ID。Google Analytics 和 Mixpanel 的订阅相关数据统一使用 `product_id` 与 `plan_type` 区分 SKU；`plan_type` 取值为 `weekly`、`yearly`、`lifetime`。

收入金额和币种以 Apple 已验证交易及 StoreKit 商品信息为准，不使用 Prototype 中写死的美元金额替代正式交易金额。

## 18.4 Mixpanel 范围

订阅漏斗相关自定义事件继续使用现有 Mixpanel 埋点方案，本 PRD 不展开定义 Paywall 曝光、SKU 选择、Subscribe 点击、Purchase 结果、Restore 等完整事件清单。

所有订阅相关 Mixpanel 自定义事件必须携带 `product_id` 与 `plan_type`。推荐使用统一事件名称加 SKU 参数，不为不同 SKU 创建大量重复事件名称。Mixpanel 自定义漏斗事件不作为 Google Analytics 收入来源。

## 18.5 防止重复收入

1. 每个 `transaction_id` 只能作为收入成功上报一次。
2. 购买回调、Transaction 更新监听和 App 重新启动恢复交易时均需进行幂等检查。
3. 同一交易不得同时重复发送 Firebase 交易记录、手动 `in_app_purchase` 收入事件或其他 Google Analytics 收入事件。
4. Mixpanel 事件不得造成 Google Analytics 收入重复统计。
5. Restore Success 只代表权益恢复，Restore 本身不得产生一笔新的 Purchase 收入。
6. 不得因为 Restore 重新枚举历史 Transaction 而重复上报 Google Analytics 收入。
7. 只有实际新的 Apple Transaction 才按照 `transaction_id` 幂等规则记录收入。
8. Purchase Pending 不记录 Revenue。
9. Transaction Unverified 不记录 Revenue。

## 18.6 上报失败处理

Firebase / Google Analytics 上报失败不得阻止 Apple 购买成功、Premium 权益解锁、Subscription Page 或 Paywall 关闭，以及 Restore 成功后的权限刷新。

处理顺序：

```text
Apple 交易验证成功
→ 更新 Premium 权益与本地缓存
→ 完成购买流程
→ 异步上报 Google Analytics 订阅价值
```

Analytics 上报失败可在后续重试，但不得向用户展示购买失败。

## 18.7 Singular 最终产品范围与验收

Singular 账号相关 Key / 正式配置在账号申请完成后补充。不得编造 SDK Key、App Key、Secret 或 Product 配置值。Singular 正式 Key / App 配置最晚必须在 Singular 归因联调与正式测试开始前完成，且不得晚于 v1.1 正式提审前的最终测试 / 验收阶段。Singular 配置尚未完成时，不得阻断 App 主业务开发和普通功能测试；但在进入正式归因验收前必须完成。

### 18.7.1 集成原则

Singular 初始化继续遵循当前 ATT 流程：

```text
App 首次安装
→ 已有网络授权流程结束
→ ATT 状态检查 / 必要时弹 ATT
→ 获取最终 ATT 状态
→ Singular 继续初始化归因能力
```

ATT Denied / Restricted 不得阻断 App 主流程。Singular 初始化失败不得阻断 Onboarding、Login、Home、Scan、Subscription 或 Apple Purchase。

### 18.7.2 本版本验收重点

正式配置完成后：

1. App 可以正常初始化 Singular，不产生 Crash，不阻断启动流程。
2. 使用测试设备产生项目最终实际配置的 Singular 事件后，Singular 后台能收到对应测试事件。
3. 使用可验证的测试投放 / 测试归因链路完成安装 / 打开 App 后，Singular 后台能产生归因记录，渠道归因符合实际测试来源。
4. Campaign / Ad Group / Creative 等维度以实际接入数据能力为准。
5. 不出现明显错误归因或重复归因。
6. 至少验证 ATT Authorized 和 ATT Denied 两种状态，App 均可正常进入主流程，Singular 均不应导致业务阻断。

归因结果以 Apple 隐私规则及 Singular 实际可获得数据为准，不要求 ATT Denied 时仍获得 IDFA。本 PRD 不新增完整 Singular 事件字典，不由 Agent 自行新增事件名称。

# 19. Out of Scope

- Notification Route URL、数据库表名 / Schema、Worker、Queue、JWS Library、Apple Server API SDK 选择、Retry framework、数据库拆表方式、服务端接口具体字段等具体技术设计
- 以 App 账号作为 Premium ownership 真值
- 将服务端 entitlement 解释为 UID Premium ownership
- App 账号与订阅 ownership 绑定
- `purchase_owner` 或 original transaction 到 App account owner 映射
- 账号间订阅转移
- 通过 App 账号本身，将一个 Apple 购买环境中的 Premium 权益同步或继承到另一个没有有效 Apple entitlement 的购买环境
- 人工订阅权益管理功能
- Weekly / Yearly 升级降级
- Lifetime 与订阅方案转换
- 按比例退款或抵扣
- Portfolio Insights
- Advanced Analytics
- Data Export
- Advanced Filter
- 未确认的 v1.2 功能
- 完整 Mixpanel 订阅漏斗事件定义
- Sports Card PRD 与 Sports Card UI 修改

# 20. Pending Configuration

以下内容属于待生成或待补充配置，不是尚未确定的产品规则：

1. Apple Weekly、Yearly、Lifetime 的正式 Product ID。
2. 尚未获得时的 Singular 正式 Key / 配置。

Apple Weekly / Yearly / Lifetime 正式 Product ID 最晚必须在 Subscription / StoreKit 正式联调开始前完成配置并冻结。在 Product ID 冻结前，可以继续使用 Pending Configuration 标记，但不得进入正式 Subscription 联调验收。

进入 StoreKit 正式联调后，Product ID 不应随意修改；如确需修改，必须同步更新 App、App Store Connect、Analytics 和测试配置。

Singular 正式 Key / App 配置最晚必须在 Singular 归因联调与正式测试开始前完成，且不得晚于 v1.1 正式提审前的最终测试 / 验收阶段。Singular 配置尚未完成时，不得阻断 App 主业务开发和普通功能测试；但在进入正式归因验收前必须完成。

# 21. 验收原则

1. Checklist 必须与本文逐条一致。
2. Page 与 Modal 的方案内容完全一致，仅容器和来源不同。
3. 权限只根据 Free/Premium 判断，与游客/账号用户独立。
4. Apple Purchase 和 Restore 的所有结果状态符合本文。
5. Scan 按 Queue 顺序部分提交并逐张结算额度。
6. 产品正文不再大量使用 UID 描述账号用户，仅技术字段场景允许保留“用户唯一标识（技术字段可为 uid）”。
7. Home Performance Tooltip 只展示 Date / Market / Portfolio / Qty。
8. Home Tooltip 不展示 Daily Change 行。
9. Daily Change 仍满足 Market + Portfolio，用于内部计算与校验。
10. Performance 整个功能属于 Premium，不存在 Performance 内部 Range 二次锁定。
11. 所有支持 Chart Range 切换的图表统一为 1D / 7D / 15D / 1M / 3M / 1Y。
12. 所有图表默认 1M；同一页面实例内可保留用户本次最后选择的 Range。
13. v1.0 原有 1D / 7D / 1M / 6M / 12M / MAX Chart Range 被 v1.1 规则覆盖；v1.1 最终 Range 为 1D / 7D / 15D / 1M / 3M / 1Y，默认 1M。
14. Home Overview Portfolio Chart 已纳入 Extended Price History，Free 可查看 1D / 7D / 15D / 1M / 3M，1Y 为 Premium Locked。
15. Card Detail Price History 已纳入 Extended Price History，Free 可查看 1D / 7D / 15D / 1M / 3M，1Y 为 Premium Locked。
16. Free 点击普通历史图表 1Y 时不得提前切换 Selected Range，不得请求 1Y 数据。
17. 普通历史图表 1Y Purchase / Restore 成功后，必须自动恢复原来源图表并加载 1Y。
18. 普通历史图表 1Y 未获得 Premium 时，必须保持原 Selected Range、页面上下文、Folder / Card / Tab / Scroll 和已加载图表数据。
19. Premium → Free 且普通历史图表正在 1Y 时，必须自动切换到 3M，不主动弹 Paywall，不离开当前页面。
20. Home Performance 整体为 Premium。
21. Card Detail Performance 整体为 Premium。
22. Performance Premium 用户 1D / 7D / 15D / 1M / 3M / 1Y 全部开放，不存在 1Y 二次卡点。
23. Card Detail Performance 只计算当前 Collection Item，不聚合同卡其他 Collection Item。
24. Purchase Price 回溯，Quantity 向后生效，Grader / Grade / Condition / Language / Finish 从修改保存时间向后生效。
25. 1D / 7D / 15D 使用业务自然日；1M 为 1 个自然月，不是固定 30 天；3M 为 3 个自然月；1Y 为 1 个自然年。
26. 用户资产操作后当前值与当天 Performance 节点立即刷新。
27. 历史统计保持每日节点。
28. 金额长度和 K / M / B 规则在 PRD 正文完整定义。
29. Free Folder 总数最多 2 个，包含默认 Folder。
30. quota = 0 时单张 Capture / Gallery 直接打开 Paywall，不创建 Waiting。
31. Waiting 计入 Queue 最大 10 张。
32. Waiting 存在时退出 Scan 沿用 v1.0 退出确认。
33. Purchase Pending 后续异步成功不恢复已经失效的旧 `blocked_action`。
34. Premium 使用中变 Free 不突然弹 Subscription Page。
35. Subscription Success 不能返回已完成购买的 Subscription Page。
36. Terms / Privacy 均跳转系统浏览器打开官网对应页面。
37. 返回 App 后 Subscription Page / Paywall 上下文保持。
38. Singular 正式配置后能收到实际已配置事件。
39. Singular 测试归因结果与实际测试来源一致。
40. ATT Authorized / Denied 均不得因为 Singular 阻断 App 主流程。
41. Performance Loading / No Data / Network Error 严格区分。
42. 删除后重新收藏同一卡牌创建新的 Collection Item 历史。
43. 已结算 Scan 额度不因后续删除资产而返还。
44. Apple-verified entitlement state、StoreKit 客户端即时验证、服务端 Apple 生命周期状态校正、本地缓存与 Unknown 兜底符合第 2 章和《Apple Subscription & Premium 权益统一方案》。
45. Subscription Page Purchase Success 进入第 4 章 Full Page；Start Exploring 后按来源返回。
46. Functional Paywall Purchase Success 不进入 Subscription Success Page，显示 `Premium unlocked`；如果存在可执行且仍有效的 `blocked_action`，则自动执行该 `blocked_action`；如果不存在可自动执行的 `blocked_action`，则只按该来源场景定义恢复页面状态。
47. 商品加载自动重试、同次点击继续购买和购买结果处理符合第 6 章。
48. Google Analytics 收入上报、SKU 区分和 `transaction_id` 幂等符合第 18 章；PRD 不强制使用某个 Swift API，Flutter Firebase Analytics SDK 对应的标准 Purchase / IAP 收入上报能力可以使用。
49. 只有 Apple Transaction verified 后才允许记录购买 Revenue；Restore、Purchase Pending 和 Transaction Unverified 均不得记录 Revenue。
50. Apple Weekly / Yearly / Lifetime 正式 Product ID 必须在 Subscription / StoreKit 正式联调前完成配置并冻结；冻结前不得进入正式 Subscription 联调验收。
51. Singular 正式 Key / App 配置必须在 Singular 归因联调与正式测试前完成，且不得晚于 v1.1 正式提审前的最终测试 / 验收阶段。
52. Pending Configuration 只保留 Apple 正式 Product ID 与 Singular 正式配置；已确认产品规则不得再标记为 Pending。
53. 首次安装网络授权与 ATT 串行执行，ATT 不阻断业务且不在后续冷启动重复请求。
54. Scan Queue Waiting 状态不发请求、不耗额度、不进 Review；获得 Premium 后按原顺序自动进入 Processing。
55. Waiting 本身不阻止 Done；Done Enabled 唯一公式为 `Matched Item Count > 0 AND Processing Item Count = 0`。
56. Matched + Waiting 且 Processing = 0 时，Done 必须可点击并进入 Review Your Matches。
57. Waiting 不进入 Review；Review 完成后 Waiting 仍保留在 Scan Queue，状态和原 Queue 顺序不变。
58. Paywall 关闭、购买失败、取消、Pending、Restore Failed 或 Restore Not Found 后 Waiting 保持 Waiting。
59. 任意 Queue 中只要存在 Processing，Done 不可点击；Only Waiting 时 Done 不可点击。
60. 同一账号用户允许在多个设备登录并同步现有账号数据。
61. v1.1 不设置 App 账号登录设备数量或同时在线设备数量上限。
62. v1.1 不新增设备绑定、Device List / Device Management、设备上限提示、自动踢出旧设备或手动解绑设备。
63. 同一账号用户在设备 A 为 Premium，不得直接导致设备 B 为 Premium。
64. 设备 B 只有在当前 Apple 购买上下文可证明存在有效 Apple entitlement 后才为 Premium；不得仅凭 App UID 在设备 A 为 Premium 而获得 Premium。
65. 如果设备 A 和设备 B 都能验证同一有效 Apple 购买，两台设备均可 Premium。
66. 游客数据不要求跨设备同步。
67. 账号用户的终身 10 次免费 Scan 额度跨设备共享。
68. 账号用户多设备同时发起 Free Scan 时，服务端必须原子判断并预占额度，Remaining 不得小于 0。
69. 客户端本地剩余额度不得覆盖服务端最新 Scan Quota。
70. 每个 Scan 提交必须有唯一请求标识，保证同一张扫描请求最多结算一次，同一份 Free Quota 最多消费一次。
71. Premium 期间不消耗当前用户身份的 Free Scan 额度。
72. Premium 与 App 账号 Scan 额度是两个独立状态系统。
73. Scan Pro / scans remaining Card 获得 Premium 后，只要当前有效 Queue 仍有 Waiting，Waiting 必须按原 Queue 顺序自动进入 Processing。
74. 如果用户已确认退出 Scan 并按 v1.0 清理 Queue，不恢复已清除的 Waiting，也不重新创建旧 Queue。
75. No Match Found 不进入 Review Your Matches，不参与 Done 带入，沿用 v1.0 Search Manually / Delete 流程，并在成功完成识别后消耗 1 次 Free Scan 额度。
76. Restore Success 不进入 Subscription Success，不展示 `Premium unlocked`，只展示 `Premium restored` 信息 Toast。
77. Restore Success Toast 无按钮、无 Close icon，并自动消失。
78. Subscription Page Restore Success 后自动关闭并返回来源；来源丢失时进入 Home。
79. Paywall Restore Success 后自动关闭并显示 `Premium restored`；如果存在可执行且仍有效的 `blocked_action`，则自动执行该 `blocked_action`；如果不存在可自动执行的 `blocked_action`，则只按该来源场景定义恢复页面状态。
80. Profile Restore Success 保持 Profile，刷新 Premium 状态和相关 UI。
81. Restore Not Found 显示 `No subscription found` 信息 Toast，不关闭 Subscription Page / Paywall，并按最新 verified current entitlements 刷新为 Free，不执行 `blocked_action`。
82. Restore Failed 使用 Restore Failed Alert + OK，不关闭原 Subscription Page / Paywall，点击 OK 后返回原容器。
83. Restore Not Found 与 Restore Failed 必须严格区分。
84. Restore 过程中禁止重复点击；Restore Success / Not Found / Failed 均不得清空原业务上下文。
85. 点击 Waiting 卡片主体会打开 Subscription Paywall Modal，且该 Paywall 是功能卡点 Paywall，不是完整 Subscription Page。
86. Waiting 卡片主体点击打开 Paywall 时必须保存 `blocked_action=resume_waiting_scan`，并保留 Scan Queue、Waiting Items、滚动位置、Queue 顺序、已有 Matched / Failed / No Match Found 状态。
87. 点击 Waiting 卡片 Delete / Remove 按钮只删除该 Waiting Item，不打开 Paywall。
88. Waiting 卡片 Delete / Remove 事件优先级高于 Card Body，必须阻止事件冒泡。
89. Waiting 删除不消耗 Scan 额度，其他 Queue Item 状态不变。
90. Waiting Card 触发 Paywall 后，Purchase Success 或 Restore Success 均自动让 Waiting 按原 Queue 顺序进入 Processing，不要求用户再次点击 Waiting Card。
91. Waiting Card 触发 Paywall 后，Paywall Close 返回原 Scan 页面，Waiting 保持，Queue 保持，不消耗额度，不自动删除卡片。
92. Waiting Card 触发 Paywall 后，Purchase Cancelled / Pending / Failed、Restore Not Found / Failed 均不得将 Waiting 改为 Failed 或删除 Waiting。
93. 所有用户可感知业务请求最大等待时间不得超过 15 秒，v1.0 已有更短超时可继续使用。
94. 15 秒 Timeout 后必须停止本轮 Loading 并报错。
95. Timeout 后不得在同一次操作中继续自动请求。
96. 迟到旧请求不得覆盖新页面上下文、旧 Range、旧 Folder、旧 Currency 或旧 `blocked_action`。
97. 自动 Retry 必须共享原 15 秒总 Deadline。
98. Apple Purchase 系统确认、Purchase Pending、ATT 系统弹窗和系统浏览器不适用普通 15 秒 Timeout。
99. Restore 期间整个 Subscription Page / Paywall / Profile 当前容器不可操作。
100. Restore 最长 Loading 15 秒。
101. Restore Timeout 统一进入 Restore Failed Alert。
102. Restore Timeout 后迟到 callback 不得继续旧 Restore 跳转、关闭容器或执行旧 `blocked_action`。
103. Purchase 与 Restore 不得并发。
104. Unknown 不得直接按 Free 或 Premium 处理；依赖 Premium 判断的主动操作必须先发起最长 15 秒 entitlement Refresh。
105. 部分 StoreKit SKU 加载失败不得影响其他正常 SKU 购买。
106. 不可用 SKU 不得使用 Prototype 价格购买。
107. Product All Failed / Timeout 使用 App Store 连接错误文案，Timeout 后不继续本轮自动请求。
108. Purchase unavailable 不授予 Premium、不关闭订阅容器、不自动重试 Purchase。
109. Transaction Unverified 不得授予 Premium、不得进入 Subscription Success、不得记录成功收入。
110. App 重启不得恢复旧 Paywall / Restore Loading / Restore Failed Alert / Subscription Success / 旧 `blocked_action`。
111. Restore 不得重复记录新 Purchase 收入。
112. Quota 返还后 Waiting 按 Queue 顺序自动递补。
113. Failed Retry 必须重新判断并预占 Free Quota；Free Remaining = 0 时 Failed Item 转为 Waiting 并打开 Paywall。
114. Processing 删除不得立即返还 Quota，必须等待最终请求结果结算。
115. Waiting 自身不启动 15 秒识别 Timeout。
116. Queue 达到 10 张不得新增第 11 张；Gallery 不得超过剩余 Queue 容量。
117. Scan 进入、回前台、预占、结算、返还和多设备冲突后使用服务端 Quota 刷新。
118. Home Overview、Home Performance、Card Detail Price History、Card Detail Performance 默认 Range 均为 1M；同一页面实例内保留用户最后选择 Range。
119. 切换 Folder 保持 Performance Tab 和当前 Range，并清除旧 Tooltip 与 Info Popover。
120. Tooltip 与 Info Popover 互斥。
121. Home 金额隐藏同步影响 Home Performance 金额，Qty 继续显示，Return 按百分比规则显示。
122. Premium → Free 时 Home Overview Portfolio Chart 或 Card Detail Price History 1Y 自动回 3M，不弹 Paywall，不离开当前页面。
123. 失效 `blocked_action` 不得在 Premium 成功后强制恢复。
124. Current Folder / Collection Item 远端删除后不得继续展示旧数据或让旧请求晚返回覆盖新状态。
125. Free Folder 并发创建不得突破总数 2 限制。
126. ATT 后台状态变化只刷新状态并同步 Singular，不重新主动弹授权框。
127. quota = 0 Capture / Gallery 打开 Paywall 时不得保存会自动执行 Capture / Gallery 的 `blocked_action`。
128. quota = 0 购买 / Restore 成功后只返回 Scan，用户重新 Capture / Gallery。
129. Waiting Premium 成功后仍必须自动 Waiting → Processing。
130. Restore Not Found 必须以最新 verified current entitlements 重新计算权益；没有有效 Premium entitlement 时刷新为 Free。
131. Restore Failed / Timeout 不得因为无法验证而擅自改变原权益。
132. Pending 期间当前 Subscription Page / Paywall 的 Subscribe 不得再次提交 Purchase。
133. Pending 不得因为 15 秒规则自动变 Failed。
134. Folder Move 必须原子完成，不允许半迁移。
135. Folder Move Failed / Timeout 保持原 Folder 归属。
136. Folder Move 成功后 Source / Target / Performance 立即刷新。
137. Processing Item UI 删除后立即不再计入 Processing Count。
138. Processing 删除后 Done 按当前可见 Queue 立即重新计算。
139. 后台 Quota 结算不得阻塞已删除 Processing Item 后的 Done。
140. Functional Paywall 只要未获得 Premium 就不得执行 `blocked_action`。
141. 各功能卡点不要求重复枚举所有 Subscription 异常，以统一未成功规则为准。
142. PRD 前部必须包含 `v1.1 核心规则速查`，且只汇总核心规则，不重定义业务。
143. Premium 不属于 App UID / App 账号；Apple transaction / originalTransactionId 对应的 Apple 购买链路是 Premium 购买身份基础。
144. Apple 是最终权威数据源；客户端 StoreKit verified transaction / current entitlements 与服务端 App Store Server Notifications V2 / Apple Server API 均为 Apple 状态验证通道。
145. Purchase / Restore 后 StoreKit verified 成功必须客户端立即解锁 Premium，不等待 Server Notification 或 Admin 订单出现。
146. 服务端负责自动续订、Grace Period、Billing Retry、Billing Recovery、Expired、Refund、Revoked 等生命周期状态维护与校正，但不得把 Premium 变成 UID 权益。
147. 服务端不可用不得直接把已确认 Premium 用户降级为 Free。
148. UID 只用于交易与业务关联、统计、查询和排查，不作为 Premium Owner。
146. Existing Collection Item 必须使用 `created_at` 作为 `performance_start_at`。
147. Existing Collection Item 必须使用 `created_at` 作为 Purchase Price 的逻辑生效起点，即 `purchase_price_effective_at = created_at`。
148. 1Y Performance 仍为 v1.1 首发能力，不得因 Legacy 数据不足删除、隐藏、降级或取消。
149. 历史不足 1Y 时，1Y Range 可以只展示实际可靠历史，不得为了补满 1Y 生成虚假历史点。
150. 不得使用当前 Folder 反向覆盖 v1.0 不可恢复的 Folder 历史。
151. v1.0 Folder Move 无历史时，以 v1.1 migration 当前 Folder 状态作为后续准确历史 Baseline。
152. v1.1 上线后的 Folder Move 必须能够准确还原历史。
153. v1.1 上线后的 Quantity / Grader / Grade / Condition / Language / Finish 变化必须能够准确还原历史。
154. Purchase Price 回溯不得导致其他缺失历史字段被伪造。
155. `performance_start_at` 与最早可靠 Performance 数据时间允许不同；后者可用 `performance_history_available_from` 等产品逻辑概念表达。
156. Existing Collection Item 的 Partial History 不得被误判为 Network Error；Selected Range 内存在可靠历史时应正常展示可用历史。
