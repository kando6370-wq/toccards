# Android 与 iOS 双端数据隔离方案

方案日期：2026 年 11 月 3 日  
适用项目：Kando / Card AI  
适用范围：Android Google Play 首发、现有 iOS、共享 API、账号体系和业务数据  
状态：供产品、研发和测试评审；推荐项和待决策项不代表已经批准或实现

## 1 方案结论

产品最新要求为 Android 与 iOS 的用户业务数据不互通。

推荐采用以下模型：

> 同一个邮箱或 Google 身份可以登录 Android 和 iOS，但服务端为两个平台创建相互独立的数据空间。两端的收藏、文件夹、愿望单、扫描记录、偏好、额度、功能权限和订阅权益互不可见，也不会自动复制或合并。

目标结构如下：

```text
共享登录身份 user
├─ iOS data space
│  ├─ 文件夹
│  ├─ 收藏卡牌和历史事件
│  ├─ 愿望单
│  ├─ 扫描记录
│  ├─ 用户偏好和额度
│  └─ Apple 订阅权益
└─ Android data space
   ├─ 文件夹
   ├─ 收藏卡牌和历史事件
   ├─ 愿望单
   ├─ 扫描记录
   ├─ 用户偏好和额度
   └─ Android 免费功能资格
```

不建议仅在 Flutter 页面隐藏另一端数据。当前服务端业务数据只按 `owner_type + owner_id` 归属，同一账号在两端会天然读取同一份数据。隔离必须由服务端鉴权和数据归属层保证。

## 2 需求定义

### 2.1 双端不互通的推荐含义

- Android 创建的收藏、文件夹、愿望单和扫描记录，iOS 不可见。
- iOS 创建的收藏、文件夹、愿望单和扫描记录，Android 不可见。
- 两端各自保存货币、隐藏金额、最后选择文件夹等偏好。
- 两端各自计算扫描额度、Premium 能力和功能访问状态。
- Apple 购买、Restore、退款和订阅生命周期只影响 iOS。
- Android 全功能免费资格只影响 Android。
- 同一平台在换机或重装后，登录同一正式账号可以恢复该平台的数据。
- 游客数据仍有卸载或换机后无法找回的现有边界。

### 2.2 本方案推荐共享的内容

以下只作为登录身份和账号管理信息共享，不属于业务数据互通：

- 基础 `user` 身份。
- 经过验证的邮箱。
- Google OAuth 身份。
- 账号状态，例如 active、disabled、deleted。
- 法务、风控和客服需要的全局账号标识。

Apple OAuth 身份仍可绑定在基础用户上，但 Android 不显示 Apple 登录入口。

### 2.3 本方案不做的事情

- 不把 iOS 历史数据复制到 Android。
- 不把 Android 数据同步回 iOS。
- 不把 Apple 购买链转移给 Android。
- 不因为 Android 免费而把整个用户永久标记为 Apple Premium。
- 不自动合并两个已经存在且各自有资产的正式账号。
- 不根据扫描记录中的历史 platform 字段猜测并拆分全部历史资产。
- 不恢复或新增 D1。
- 不改动冻结版本文档。

## 3 当前实现和冲突

当前业务数据归属只包含：

```text
owner_type: anonymous | user
owner_id
```

当前鉴权返回：

```text
owner_type
owner_id
session_id
```

没有数据空间或可信平台维度。因此同一正式用户的所有 session 最终访问相同 `owner_id`。

### 3.1 当前受影响的数据

| 数据 | 当前归属字段 | 双端隔离要求 |
|---|---|---|
| 文件夹 | `owner_type + owner_id` | 按 iOS/Android 数据空间隔离 |
| 收藏卡牌 | `owner_type + owner_id + folder_id` | 文件夹和卡牌均不得跨空间访问 |
| 收藏历史事件 | `owner_type + owner_id` | Performance 历史分别计算 |
| 愿望单 | `owner_type + owner_id` | 两端分别维护 |
| 用户偏好 | `owner_type + owner_id` | 两端货币和显示偏好分别维护 |
| 扫描记录 | `owner_type + owner_id` | 两端记录互不可见 |
| 扫描额度 | `owner_type + owner_id + session_id` | Android 免费和 iOS 原额度分别计算 |
| 估值历史 | 基于 owner 的收藏和事件 | 按数据空间分别计算 |
| Performance | 基于 owner 的收藏和事件 | 按数据空间分别计算 |

### 3.2 当前账号唯一约束

- 未删除用户的邮箱全局唯一。
- OAuth 身份按 `provider + provider_uid` 全局唯一。
- session 当前直接关联 `owner_type + owner_id`。

这套结构更适合“身份共享、数据空间隔离”。如果改成两套完全独立账号，还要修改邮箱和 OAuth 身份的唯一约束。

## 4 两种可选方案

### 4.1 方案 A 共享身份 数据空间隔离

| 项目 | 规则 |
|---|---|
| 同一邮箱 | 可以登录两端 |
| 同一 Google 身份 | 可以登录两端 |
| 基础 user | 共用 |
| iOS/Android 业务数据 | 完全隔离 |
| iOS Apple 购买 | 只影响 iOS |
| Android 免费资格 | 只影响 Android |
| 删除当前平台数据 | 可以单独实现 |
| 未来调整策略 | 相对容易 |

优点：

- 不破坏现有邮箱和 OAuth 身份唯一规则。
- 用户不需要维护两个相同邮箱的密码。
- 同平台换机恢复逻辑清晰。
- 客服仍能通过一个基础账号定位两端数据空间。
- 将来产品调整隔离规则时仍有明确的数据归属。

风险：

- “删除账号”需要重新定义当前平台与整个账号的范围。
- Admin、分析和客服必须明确平台空间。
- session 和游客迁移需要较系统的改造。

**本方案推荐采用方案 A。**

### 4.2 方案 B 账号完全分离

方案 B 的含义是同一邮箱和 Google 身份在 Android、iOS 也属于两个不同账号。

需要修改：

- 邮箱唯一键改为 `platform + email`。
- OAuth 身份唯一键增加平台维度。
- 注册、登录、密码重置和邮箱验证全部增加平台。
- Apple/Google 身份在不同平台允许重复注册。
- 删除、封禁、客服、风控、数据导出和分析按平台处理。
- 未来账号合并需要专门的数据迁移和冲突解决。

方案 B 成本高，容易造成用户使用同一邮箱却出现两套密码、两次删号、两份客服记录等困惑。只有产品明确要求“连登录账号也完全没有关系”时才应采用。

## 5 推荐数据模型

### 5.1 平台数据空间

新增平台数据空间，例如：

```text
account_data_space
- id
- user_id
- platform          ios | android
- status            active | deleted | disabled
- created_at
- updated_at
- deleted_at

UNIQUE(user_id, platform)
```

对正式用户，每个平台最多有一个有效数据空间。

匿名用户可以继续以 anonymous owner 运行，但匿名账号或 session 同样必须具有服务端确定的平台空间。

### 5.2 session

session 推荐增加或等价保存：

```text
session
- id
- user_id                 基础登录身份
- owner_type
- data_space_id           当前请求的数据 owner
- platform_scope          ios | android
- installation_id         可选 Android 安装关联
- refresh_token
- expires_at
- revoked_at
- login_method
```

服务端鉴权后的上下文建议为：

```text
AuthenticatedOwner
- owner_type
- owner_id                当前 data_space_id 或匿名 owner
- user_id                 正式用户身份 可空
- platform_scope
- session_id
```

业务路由只能使用鉴权上下文中的 `owner_id` 和 `platform_scope`。不得接受客户端在业务请求中临时传 `workspace_id` 或切换平台。

### 5.3 复用现有 owner 查询

为减少改造面，正式用户业务表中的 `owner_id` 可以代表当前数据空间 ID，而不再直接代表 `user.id`。

这样多数现有业务查询仍保持：

```sql
WHERE owner_type = ? AND owner_id = ?
```

但 `owner_id` 由受信 session 提供。任何需要验证真实用户身份的功能使用单独的 `user_id`，不能再把业务 `owner_id` 直接连接到 `user` 表。

### 5.4 数据库完整性

需要同步核对并更新：

- 文件夹名称唯一约束。
- 收藏卡牌 SKU 唯一约束。
- 愿望单唯一约束。
- 用户偏好唯一约束。
- owner 相关索引。
- folder 和 collection item 的归属一致性。
- 事件历史、估值和 Performance 查询。
- 扫描额度及补偿记录。
- 删除、迁移、Admin 和统计查询。

不能只在部分 SELECT 增加 platform 条件。任何遗漏的 UPDATE、DELETE、唯一约束或统计查询都可能造成跨端泄漏或误删。

## 6 历史数据迁移

### 6.1 迁移原则

当前已有正式业务数据全部认定为 iOS 数据。

- 为每个现有正式用户建立 iOS 数据空间。
- 现有文件夹、收藏、愿望单、偏好、扫描和额度历史全部保留在 iOS。
- Android 首次登录创建新的空数据空间、默认文件夹和默认偏好。
- 不复制 iOS 数据到 Android。
- 不删除或重新解释现有 Apple 购买、订单、购买链和 entitlement。

### 6.2 减少数据改写的选择

可以评估让现有 iOS 数据空间 ID 沿用原 `user.id`：

- 现有业务表的 `owner_id` 不需要批量改写。
- 新 Android 数据空间使用新 ID。
- session 增加真实 `user_id`，避免把 data space ID 误当用户 ID。
- 旧 iOS session 缺少新字段时按兼容规则解析为 iOS 空间。

是否采用这一方式，需要在实施前结合外键、Admin 查询和购买授权对 owner 的依赖完成验证。

### 6.3 禁止的迁移方式

- 不根据 `scan_record.platform` 拆分其他业务表。
- 不根据最近登录设备猜测历史收藏属于哪一端。
- 不把现有数据同时复制到两个平台。
- 不以清空现有用户数据作为迁移手段。
- 不在没有备份、回查和回退方案时执行生产迁移。

## 7 登录场景

| 场景 | 推荐结果 |
|---|---|
| 新 Android Google 用户 | 创建/绑定基础用户，进入全新 Android 数据空间 |
| 新 Android 邮箱用户 | 创建/登录基础用户，进入 Android 数据空间 |
| 新 iOS 用户 | 进入 iOS 数据空间 |
| 同一 Google 身份登录双端 | 基础 user 相同，数据空间不同 |
| 同一邮箱密码登录双端 | 基础 user 相同，数据空间不同 |
| Apple-only 用户首次使用 Android | 使用 Google/邮箱或新注册进入 Android 空间，不展示 iOS 数据 |
| Apple 邮箱与 Google 邮箱相同 | 可以绑定同一基础 user，但数据仍不互通 |
| Apple 隐藏邮箱与 Google 邮箱不同 | 不自动认定同一身份；Android 创建或登录自己的基础账号 |
| Google 身份已属于另一个 user | 拒绝覆盖，明确账号冲突 |
| Android 退出后重登 | 回到原 Android 数据空间 |
| Android 换机后登录 | 恢复 Android 数据，不显示 iOS 数据 |
| iOS 换机或 Restore 登录 | 恢复 iOS 数据和原购买流程 |

在数据隔离要求下，Apple-only 用户不再需要为了同步 iOS 资产而强制绑定 Google。但产品仍需确认是否希望同一自然人在后台被识别为同一基础 user。

## 8 游客和资产迁移

### 8.1 游客创建

- Android 游客只创建 Android 匿名数据。
- iOS 游客只创建 iOS 匿名数据。
- 匿名 session 的平台由服务端会话确定。
- 客户端提交的 platform 只能作为输入信号，不能单独决定业务 owner。

### 8.2 游客升级为新账号

- Android 游客资产只迁入 Android 数据空间。
- iOS 游客资产只迁入 iOS 数据空间。
- 迁移后的正式用户在另一端首次登录时仍得到空数据空间。
- 文件夹、收藏、愿望单、偏好、扫描和额度迁移必须保持同一平台范围。

### 8.3 游客登录已有账号

沿用当前“不自动合并已有账号”的安全方向：

- 不把游客数据静默合并到已有正式账号。
- 不跨端迁移游客数据。
- 登录前明确当前游客资产的处理结果。
- 不能因登录已有账号而把 iOS 和 Android 数据混合。

### 8.4 卸载和换机

匿名数据可能仍留在服务端，但客户端失去匿名凭据后不能保证找回。

已注册账号可在同一平台重新登录恢复对应空间。换平台登录不会恢复另一端空间。

## 9 Android 免费与 iOS 订阅

### 9.1 权益隔离

| 权益来源 | 作用范围 |
|---|---|
| Apple 有效订阅 | iOS session 和 iOS data space |
| Apple Restore | iOS |
| Apple 退款或撤销 | 只改变 iOS 权益 |
| Android 免费策略 | Android session 和 Android data space |
| Android 安装验证 | 只用于 Android 免费资格 |

Android 免费不得写入：

- Apple billing product。
- Apple purchase chain。
- Apple entitlement grant。
- Apple 订单、收入或退款记录。

iOS Apple 订阅也不得让 Android 读取 iOS 业务数据。

### 9.2 功能规则

| 功能 | Android | iOS |
|---|---|---|
| 扫描 | 按 Android 免费策略开放 | 按原免费/订阅规则 |
| 文件夹 | Android 数据空间内免费开放 | 按原规则 |
| 估值历史 | 只读取 Android 收藏历史 | 只读取 iOS 收藏历史 |
| Performance | 只计算 Android 空间 | 只计算 iOS 空间 |
| 订阅页 | 不展示 | 保持现有规则 |
| Restore | 不展示 | 保持 Apple 流程 |

## 10 终端和平台可信度

### 10.1 服务端决定数据空间

数据空间不能由单个业务请求的客户端参数决定。

推荐流程：

1. App 在创建匿名会话、注册、登录或刷新 session 时提供平台输入。
2. 服务端结合合法客户端版本、已有 session、应用证明等信息确定平台。
3. 创建绑定 `platform_scope + data_space_id` 的 session。
4. 后续所有业务接口从 session 读取数据空间。
5. 刷新 token 时继承原平台，不接受客户端改成另一平台。

### 10.2 Android

正式 Google Play 版本推荐结合 Play Integrity 确认包名、签名、安装认可状态和请求绑定信息，再发放 Android 免费资格。

Play Integrity 主要用于降低伪造 Android 免费资格的风险。数据隔离的最终边界仍由服务端 session 和 data space 保证。

### 10.3 iOS

旧 iOS App 没有新增数据空间字段时，服务端必须默认进入 iOS 数据空间并保持原 Apple entitlement 行为。

缺少新字段不能：

- 把旧 iOS 请求识别为 Android。
- 让旧 iOS 读到 Android 空间。
- 让已有 Premium 降级。
- 修改 Restore 或购买链归属。

## 11 删除账号和隐私

当前“删除账号”会影响整个基础用户，这与平台数据隔离后的产品含义存在冲突。

### 11.1 推荐提供两个动作

#### 删除当前平台数据

- 删除当前 session 对应的数据空间及其业务数据。
- 保留基础登录身份。
- 保留另一个平台的数据空间和 session。
- Android 删除不影响 iOS Apple 购买链。
- iOS 删除不自动取消 Apple 自动续费。

该操作不应继续笼统命名为“删除账号”，建议使用“删除 Android 数据”或“删除当前平台数据”。

#### 删除整个 Card AI 账号

- 删除或停用基础 user。
- 删除 Android 和 iOS 两个数据空间。
- 撤销全部 session。
- 清理或按法务要求保留必要记录。
- 明确提醒 Apple 自动续费不会因删除 App 账号而自动取消。

### 11.2 如果只保留一个按钮

产品必须明确它表示：

- 删除当前平台数据；或者
- 删除双端全部账号和数据。

UI、隐私政策、官网删除入口、客服和 Google Play Data Safety 必须使用同一口径。

### 11.3 数据导出

建议区分：

- 导出当前平台数据。
- 导出整个账号的全部数据。

隐私请求是否一次包含两个平台，需要由法务与产品确认，内部数据隔离不能成为拒绝合法完整请求的理由。

## 12 Admin 客服和数据分析

### 12.1 Admin

Admin 用户详情需要显示：

- 基础 user。
- iOS data space 状态和数据摘要。
- Android data space 状态和数据摘要。
- 当前查看的平台。
- Apple 购买和 entitlement 只显示在 iOS 范围。
- Android 免费资格只显示在 Android 范围。

任何修改、删除或导出操作都必须明确目标数据空间，不能只凭 user ID 操作全部业务表。

### 12.2 客服

客服处理问题时至少确认：

- 用户使用的平台。
- 对应 session 或 data space。
- 登录方式。
- 问题涉及业务数据还是基础账号。

不能因为邮箱相同就把两端数据视为同一份。

### 12.3 分析和归因

- Firebase、Mixpanel、Singular 等事件增加平台或 data space 维度。
- Android 免费使用不记录为 Apple 订阅收入。
- 跨端活跃用户统计可以按基础 user 去重，但业务行为统计应按数据空间区分。
- 崩溃、设备和版本分析继续按实际平台记录。
- 不把数据隔离误报为用户数据丢失。

## 13 API 与旧版本兼容

### 13.1 兼容原则

- 新 session 字段和响应字段对旧客户端可选。
- 旧 iOS 请求省略平台字段时保持原 iOS 行为。
- 不改变现有 V1 字段含义和错误包络。
- 新访问来源不能直接加入旧客户端无法处理的枚举。
- 必须不兼容时只为受影响功能局部新增 V2，保留 V1。
- 不通过客户端版本或自报平台绕过服务端授权。

### 13.2 旧 Android 包

旧 Android 包可能仍使用共享 owner 或不认识新数据空间，因此不能直接视为已满足隔离要求。

推荐：

- Google Play 首发使用支持平台数据空间的新版本。
- 已有旧测试包通过 Android 独立版本配置要求升级。
- 服务端不能因旧包传入 `android` 就自动授予跨端数据访问或免费资格。
- 旧 Android session 应撤销、重新登录或经过明确迁移后绑定 Android 数据空间。

## 14 实施步骤

### 阶段 0 产品确认

确认：

- 登录身份是否允许双端共用。
- 现有数据是否全部归 iOS。
- Android 是否必须从空数据开始。
- 删除是当前平台还是全账号。
- Admin 是否允许内部同时查看两个空间。
- 数据导出和隐私删除的范围。
- 非 Google Play Android 是否支持。
- 未来是否可能恢复数据互通。

### 阶段 1 数据和 session 设计

- 设计 `account_data_space`。
- 明确 iOS 历史 owner 的兼容映射。
- 给 session 增加基础 user 和数据空间归属。
- 修改鉴权上下文。
- 设计 Android session 的可信平台判定。
- 定义迁移、回退和备份方案。

### 阶段 2 业务查询隔离

逐项覆盖：

- 文件夹。
- 收藏卡牌。
- 收藏历史事件。
- 愿望单。
- 用户偏好。
- 扫描记录。
- 扫描额度。
- 估值历史。
- Portfolio Performance。
- 单卡 Performance。
- Admin 和统计查询。
- 删除与数据导出。

### 阶段 3 登录和游客迁移

- 匿名创建绑定平台。
- 邮箱注册和登录创建正确平台 session。
- Google OAuth 创建正确平台 session。
- Apple OAuth 只进入 iOS。
- 游客升级只迁入当前平台。
- session refresh 保持原平台。
- 退出和换账号清理本地缓存。

### 阶段 4 Android 免费和 iOS 回归

- Android 读取 Android 空间并开放约定功能。
- iOS 只读取 iOS 空间并保持订阅。
- Apple 购买、Restore、通知和退款不回归。
- Android 不显示 Apple 登录和订阅入口。

### 阶段 5 发布和迁移

- 本地完成迁移回放和回退验证。
- Linux dev 部署并验证两个平台空间。
- 生成正式 Android AAB，通过 Play 测试轨道验证。
- 单独验证旧 iOS 正式包。
- 生产迁移前备份并只读核对影响数量。
- 生产发布后分别验证 iOS、Android 和 Admin。

## 15 验收矩阵

以下均为实施后需要执行的验收，本方案阶段尚未执行。

| 编号 | 场景 | 预期结果 |
|---|---|---|
| I01 | 现有 iOS 用户升级新服务端 | 原数据、登录和订阅保持不变 |
| I02 | 旧 iOS App 不传新字段 | 进入 iOS 空间，不读取 Android 数据 |
| I03 | 同一 Google 身份登录 iOS 和 Android | 基础身份可相同，业务数据完全不同 |
| I04 | 同一邮箱密码登录双端 | 各自进入对应数据空间 |
| I05 | Android 首次登录已有 iOS 账号 | Android 为空，不复制 iOS 数据 |
| I06 | Android 新建文件夹和收藏 | iOS 不可见 |
| I07 | iOS 新建文件夹和收藏 | Android 不可见 |
| I08 | 两端同时创建同名文件夹 | 各自成功，不发生跨空间唯一键冲突 |
| I09 | 两端收藏同一张卡 | 分别保存，数量和估值互不影响 |
| I10 | Android 扫描记录 | iOS 扫描历史不可见 |
| I11 | iOS 扫描记录 | Android 扫描历史不可见 |
| I12 | 两端用户偏好 | 货币、隐藏金额和默认文件夹分别保存 |
| I13 | Android 免费扫描 | 只使用 Android 额度或免费策略 |
| I14 | iOS free 扫描 | 保持 iOS 原额度，不受 Android 影响 |
| I15 | iOS 有效订阅 | 只解锁 iOS，不改变 Android 购买事实 |
| I16 | Apple 过期、退款和撤销 | 只影响 iOS 权益 |
| I17 | Apple Restore | 恢复 iOS 权益，不复制 iOS 数据到 Android |
| I18 | Android 游客注册新账号 | 只迁移 Android 游客数据 |
| I19 | iOS 游客注册新账号 | 只迁移 iOS 游客数据 |
| I20 | 游客登录已有账号 | 不静默合并，不跨平台搬运数据 |
| I21 | Android 换机重登 | 恢复 Android 数据，不出现 iOS 数据 |
| I22 | iOS 换机重登 | 恢复 iOS 数据，不出现 Android 数据 |
| I23 | Android session 尝试提交 iOS workspace | 服务端拒绝或忽略客户端切换 |
| I24 | iOS session 尝试访问 Android 资源 ID | 返回无权或不存在，不泄漏对象信息 |
| I25 | Android session refresh | 平台和数据空间保持不变 |
| I26 | 伪造 platform、版本或 device_id | 不能切换数据空间 |
| I27 | 删除当前 Android 数据 | iOS 数据和 Apple 权益保留 |
| I28 | 删除当前 iOS 数据 | Android 数据保留，并正确提示 Apple 续费 |
| I29 | 删除整个账号 | 两端 session 撤销，数据按合同处理 |
| I30 | Admin 查看用户 | 两个空间清楚分开，修改目标明确 |
| I31 | 数据导出 | 按选定范围输出，无遗漏和跨空间混淆 |
| I32 | 分析事件 | Android 和 iOS 行为可分别统计 |
| I33 | 估值历史 | 只使用当前空间的收藏和事件 |
| I34 | Portfolio Performance | 两端计算结果互不影响 |
| I35 | 单卡 Performance | 只计算当前空间中的资产 |
| I36 | 文件夹删除 | 只能删除当前空间的文件夹和关联数据 |
| I37 | 并发双端写入 | 不产生跨空间锁冲突或覆盖 |
| I38 | 数据库迁移回放 | 现有数据全部进入 iOS，Android 无历史复制 |
| I39 | 迁移回退 | 可恢复到批准的迁移前状态且不丢数据 |
| I40 | Google Play 正式 AAB | 登录 Android 空间，免费功能和数据隔离均正确 |

## 16 风险和控制

| 风险 | 影响 | 控制措施 |
|---|---|---|
| 某条查询遗漏数据空间 | 跨端数据泄漏 | 统一鉴权 owner；全面检索 owner 查询；集成测试覆盖读写删 |
| session owner 被错误当成 user | 登录或购买归属错误 | 明确区分 `user_id` 与 `data_space_id` |
| 历史数据错误拆分 | 数据丢失或错端显示 | 现有数据全部归 iOS，不做猜测拆分 |
| 游客迁入错误平台 | 数据跨端 | 使用服务端 session 平台决定目标空间 |
| 删除当前端误删全账号 | 双端数据丢失 | 拆分“删除平台数据”和“删除整个账号” |
| Apple 权益绑定到 Android | 财务和权限错误 | Apple 购买只关联 iOS session/空间 |
| Android 免费污染 iOS | iOS 收费失效 | 免费资格绑定 Android session，不写账号 Premium |
| Admin 无平台过滤 | 运营误操作 | 所有 Admin 操作明确 data space |
| 旧 App 绕过隔离 | 数据泄漏 | V1 兼容规则和旧 session 映射；必要时版本门禁 |
| 双端同一邮箱引起误解 | 客诉 | 登录后说明当前平台数据独立，不宣传同步 |

## 17 回退原则

- 数据库变更只使用 PostgreSQL migration。
- 迁移前完成备份、数据数量核对和恢复验证计划。
- 现有 iOS owner 不做不可逆的批量重写，或确保有明确映射表和回退脚本。
- Android 上线前，iOS 必须能够继续读取原数据。
- 回退服务端时不能让 Android session 读取 iOS owner。
- 若隔离功能异常，优先关闭 Android 新用户入口或要求升级，不能临时恢复跨端共享数据。
- 回退不撤销合法 Apple 购买事实，不删除用户资产。

## 18 产品必须确认的事项

| 决策 | 推荐答案 |
|---|---|
| 同一邮箱和 Google 是否可登录双端 | 可以，但数据空间不同 |
| 邮箱、密码和账号状态是否共享 | 共享基础身份 |
| 现有数据如何处理 | 全部归 iOS |
| Android 首次登录是否为空 | 是 |
| Apple-only 用户是否需要看到 iOS 资产 | 不需要，Android 独立开始 |
| 游客是否按平台隔离 | 是 |
| 删除当前平台数据是否保留另一端 | 是 |
| 是否同时提供删除整个账号 | 推荐提供 |
| Admin 是否可内部查看两个空间 | 可以，但必须清楚区分和控制权限 |
| 隐私导出是否包含双端 | 提供当前平台和全账号两种明确范围 |
| 未来是否可能重新互通 | 当前不互通；任何合并另立专项方案 |
| 是否支持侧载或无 GMS Android | 首发不承诺，另行评估 |

建议产品最终批准以下口径：

> 同一个邮箱或 Google 身份可以登录 iOS 和 Android，但两端业务数据完全隔离。现有数据全部属于 iOS，Android 首次登录从空数据空间开始。Android 免费资格只作用于 Android，Apple 订阅权益只作用于 iOS。删除当前平台数据不会影响另一端；删除整个账号才处理双端数据和共享登录身份。

## 19 源码依据

源码根目录：`D:/Projects/kando-global-project`。

| 依据 | 路径或定位 |
|---|---|
| 当前 owner 鉴权上下文 | `apps/workers-api/src/owner-auth.ts:5` |
| session 当前字段 | `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:52` |
| 邮箱唯一约束 | `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:13` |
| OAuth 身份唯一约束 | `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:41` |
| 文件夹归属 | `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:142` |
| 收藏归属 | `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:158` |
| 收藏历史事件 | `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:194` |
| 愿望单归属 | `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:225` |
| 用户偏好归属 | `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:236` |
| 扫描记录归属 | `apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:249` |
| 游客资产迁移 | `apps/workers-api/src/auth/guest-migration.ts:54` |
| 当前正式用户删号 | `apps/workers-api/src/auth/account.ts:143` |
| 当前业务 owner 查询 | `apps/workers-api/src/portfolio/routes.ts:138` |
| iOS 订阅与 Android 边界 | `docs/releases/v1.1.2/01-flows/subscription-display.md` |
| App API 兼容规则 | `docs/releases/v1.1.2/03-data-api/app-backward-compatibility-ai-guide.md` |
| 当前增量文档入口 | `docs/releases/v1.1.3/README.md` |

## 20 文档交付边界

本文件是双端数据隔离的设计与实施评估，不代表功能已经开发、数据库已经迁移、Android 已经上架或生产环境已经验证。

本轮未修改项目业务代码或仓库文档，未运行测试、构建、数据库迁移、远程部署、Google Play 发布或生产写操作。
