# 关键状态机

> **定位**：本文件汇总 tcg-card v1.0 关键业务对象的状态机，使用 Mermaid stateDiagram-v2 语法绘制，每图配文字说明并链接对应模块 PRD。
>
> **日期**：2026-06-30
>
> **来源**：
> - 全局规则 [`../00-product/modules/global-rules.md`](../00-product/modules/global-rules.md)（spec §4.5 / §十四 游客口径）
> - Auth 模块 PRD [`../00-product/modules/auth.md`](../00-product/modules/auth.md)
> - Profile 模块 PRD [`../00-product/modules/profile.md`](../00-product/modules/profile.md)
> - Home 模块 PRD [`../00-product/modules/home.md`](../00-product/modules/home.md)
> - Collection 模块 PRD [`../00-product/modules/collection.md`](../00-product/modules/collection.md)
> - Search 模块 PRD [`../00-product/modules/search.md`](../00-product/modules/search.md)
> - Card Detail 模块 PRD [`../00-product/modules/card-detail.md`](../00-product/modules/card-detail.md)
> - Scan 模块 PRD [`../00-product/modules/scan.md`](../00-product/modules/scan.md)（Scan 状态机为 future 留档）

---

## 目录

1. [账号身份状态机](#一账号身份状态机)
2. [收藏对象状态机](#二收藏对象状态机)
3. [Portfolio 文件夹状态机](#三portfolio-文件夹状态机)
4. [Scan 扫描项状态机（future 留档）](#四scan-扫描项状态机future-留档)

---

## 一、账号身份状态机

> 对应 PRD：[global-rules.md §十四](../00-product/modules/global-rules.md)、[auth.md](../00-product/modules/auth.md)、[profile.md](../00-product/modules/profile.md)
>
> 对齐口径：spec §4.5、global-rules §十四（匿名账号同步机制、注册迁移、登录不合并）

### 说明

App 首次启动时后端自动创建 `anonymous_account`（持有 JWT，关联 `device_id`），用户始终处于「游客态」或「正式账号登录态」之一。

核心规则（来自 global-rules §十四）：
- **游客注册新账号**：资产迁移到新账号（`POST /auth/register/verify` 携带 `anonymous_id`），迁移失败时账号仍登录但资产保留在游客侧，可重试 `POST /auth/migrate-assets`。
- **游客登录已有账号**：游客资产**不迁移、不合并**，登录后展示该账号资产。
- **退出登录**：切回游客态；若本地仍有游客资产则展示，否则展示空游客状态。
- **删除账号**：账号资产按隐私合规处理；切回游客态；已删除账号资产**不**回退为游客资产。

```mermaid
stateDiagram-v2
    [*] --> GuestState : App 首次启动\n后端创建 anonymous_account

    state GuestState {
        [*] --> GuestActive
        GuestActive : 游客态 (anonymous_account)\n可使用 Portfolio / Wishlist / Search / Scan 等功能\n资产存储在后端匿名账号下
    }

    state RegisteredState {
        [*] --> LoggedIn
        LoggedIn : 正式账号登录态\n展示账号绑定资产\n(Portfolio / Wishlist / 文件夹 / 偏好等)
    }

    GuestState --> RegisteredState : 游客注册新账号\n(携带 anonymous_id)\n后端迁移游客资产到新账号\n(migrated=true)

    GuestState --> MigrationFailed : 注册成功但迁移失败\n账号已创建且登录\n游客资产保留本地

    MigrationFailed : 迁移失败态\n账号已登录\n游客资产尚未迁移
    MigrationFailed --> RegisteredState : 重试 POST /auth/migrate-assets\n迁移成功

    GuestState --> RegisteredState : 游客登录已有账号\n游客资产不迁移不合并\n展示该账号资产

    RegisteredState --> GuestState : 退出登录 (POST /auth/logout)\n账号资产不删除\n切回游客态\n若有游客资产则展示\n否则展示空游客状态

    RegisteredState --> AccountDeleted : 删除账号 (DELETE /auth/account)\n经二次确认弹窗

    state AccountDeleted {
        [*] --> DeletedCleanup
        DeletedCleanup : 账号已删除\n资产按隐私合规处理\nApp 切换为游客态\n已删除账号资产不回退为游客资产
    }

    AccountDeleted --> GuestState : 切回游客态\n若本地有旧游客资产则展示\n否则展示空游客状态
```

---

## 二、收藏对象状态机

> 对应 PRD：[search.md §十三](../00-product/modules/search.md)、[search.md §十四](../00-product/modules/search.md)、[card-detail.md §十](../00-product/modules/card-detail.md)、[collection.md §九](../00-product/modules/collection.md)

### 说明

每个收藏对象（卡牌 / Sealed Product / 其他）相对于当前账号和当前选中文件夹，存在三种互斥状态：**未收藏**、**在 Wishlist** 中、**在 Portfolio** 中。

**核心互斥规则**（来自 search.md §十四 规则 6、collection.md §九.3）：
- 同一对象**不可同时存在于 Portfolio 和 Wishlist**。
- 点击 Collect（加入 Portfolio）时，若对象已在 Wishlist，后端 Workers 副作用自动将其从 Wishlist 移除。
- 从 Wishlist 加入 Portfolio 后，自动从 Wishlist 移除。
- Remove from Portfolio 后，不影响 Wishlist 状态（即 Portfolio 和 Wishlist 移除彼此独立）。

注意：Portfolio 状态是相对「当前选中文件夹」的；同一对象可在不同文件夹中有不同 Collection Item，但 Wishlist 跨文件夹全局唯一。

```mermaid
stateDiagram-v2
    [*] --> Uncollected

    Uncollected : 未收藏\n(Collect 按钮空心 / Heart 空心)\nQty: 0

    state Wishlist {
        [*] --> InWishlist
        InWishlist : 在 Wishlist 中\n(Heart 实心)\n不计入 Home 总资产\n不计入 Most Valuable\n不影响 Qty
    }

    state Portfolio {
        [*] --> InPortfolio
        InPortfolio : 在当前文件夹 Portfolio 中\n(Collected 按钮 / Heart 空心)\nQty >= 1\n计入 Home 总资产\n参与 Most Valuable 排序
    }

    Uncollected --> Wishlist : 点击空心 Heart\nPOST /wishlist

    Wishlist --> Uncollected : 点击实心 Heart (移除 Wishlist)\nDELETE /wishlist/{id}\n或在 Card Detail 点击 Remove from Wishlist\n(经二次确认弹窗)

    Uncollected --> Portfolio : 点击 Collect\nPOST /portfolio/items\n(系统生成默认 Collection Item)

    Portfolio --> Uncollected : 点击 Collected (撤销单条)\nDELETE /portfolio/items/{id}\n或 Card Detail 点击 Remove from Portfolio\n(经二次确认弹窗)

    Wishlist --> Portfolio : 从 Wishlist 加入 Portfolio\n(Card Detail Add to Portfolio\n或 Search Collect 按钮)\nPOST /portfolio/items\n→ Workers 副作用自动移除 Wishlist\n[互斥: 不可同时在两者中]

    note right of Portfolio
        互斥规则:
        加入 Portfolio 时若已在 Wishlist
        → 后端自动移除 Wishlist
        Remove from Portfolio 不影响 Wishlist
    end note
```

---

## 三、Portfolio 文件夹状态机

> 对应 PRD：[home.md §八](../00-product/modules/home.md)、[collection.md §十一](../00-product/modules/collection.md)

### 说明

Portfolio 文件夹（`portfolio_folder`）有以下几个维度的状态：是否为「默认文件夹」（星标）、是否为「当前选中文件夹」、生命周期（存在 / 删除）。

核心规则：
- **默认文件夹**（`is_default=1`）唯一，不可删除，可编辑名称；冷启动后 Home 和 Collection 始终展示默认文件夹。
- **当前选中文件夹**：用户手动切换后，本次会话内此文件夹优先级高于默认；下次冷启动重置为默认文件夹。
- **删除**：只有非默认文件夹可删除，需经二次确认弹窗；删除后内部所有 Collection Item 级联删除（`ON DELETE CASCADE`）；若删除的是当前选中文件夹，自动切换到默认文件夹。

```mermaid
stateDiagram-v2
    [*] --> NormalFolder : POST /portfolio/folders\n新建文件夹\n(非默认 / 非选中)

    NormalFolder : 普通文件夹\n(非默认 / 非当前选中)

    DefaultFolder : 默认文件夹\n(is_default=1 / 星标)\n不可删除\n冷启动后 Home+Collection 默认展示

    SelectedFolder : 当前选中文件夹\n(本次会话优先于默认)\n下次冷启动重置为默认文件夹

    DefaultAndSelected : 默认且当前选中\n(既是星标又是本次会话选中)

    NormalFolder --> SelectedFolder : 用户手动切换到该文件夹\nPATCH /preferences\n(last_selected_folder_id)

    DefaultFolder --> DefaultAndSelected : 用户手动切换到默认文件夹\n(或冷启动时默认展示)

    SelectedFolder --> NormalFolder : 用户切换到其他文件夹\n(本文件夹退出选中状态)

    DefaultAndSelected --> DefaultFolder : 用户切换到其他文件夹\n(默认文件夹退出选中\n但保持默认状态)

    NormalFolder --> DefaultFolder : 点击星标设为默认\nPATCH /portfolio/folders/{id}/set-default\n(原默认文件夹自动取消星标)

    DefaultFolder --> NormalFolder : 另一文件夹被设为新默认\n(本文件夹自动取消星标)

    NormalFolder --> EditedFolder : 编辑文件夹名称\nPATCH /portfolio/folders/{id}
    DefaultFolder --> EditedFolder : 编辑文件夹名称 (默认文件夹可编辑名称)\nPATCH /portfolio/folders/{id}
    SelectedFolder --> EditedFolder : 编辑文件夹名称
    EditedFolder --> NormalFolder : 保存成功 (普通文件夹)
    EditedFolder --> DefaultFolder : 保存成功 (默认文件夹)
    EditedFolder --> SelectedFolder : 保存成功 (选中文件夹)

    EditedFolder : 名称编辑中\n(Home + Collection 名称同步更新后)

    NormalFolder --> [*] : 删除 (需二次确认弹窗)\nDELETE /portfolio/folders/{id}\n内部 Collection Item 级联删除\n若是当前选中文件夹 → 自动切换到默认文件夹

    SelectedFolder --> [*] : 删除当前选中文件夹\n→ 自动切换到默认文件夹\nHome + Collection 数据刷新

    note right of DefaultFolder
        默认文件夹不可删除
        删除图标隐藏或置灰
    end note
```

---

## 四、Scan 扫描项状态机（future 留档）

> **⚠️ 注意：本节描述的 Scan 扫描识别功能在 v1.0 不实现。**
> **v1.0 Scan Tab 仅交付占位页（展示「扫描功能即将上线」引导 + 跳转 Search 按钮），不打开相机，不请求相机权限。**
> 本节内容完整保留原始扫描识别设计，供后续版本参考。
>
> 对应 PRD：[scan.md §二十八（Future）](../00-product/modules/scan.md)

### 说明（Future）

在 Future 版本中，每次拍摄生成一个扫描项，独立经历以下状态流转：`Scanning`（识别中）→ `Matched`（识别成功并找到匹配卡牌）/ `Failed`（识别失败 / 超时 / 网络失败）→ 用户操作后进入 `Added`（已加入 Portfolio）或 `Deleted`（已删除）。

核心规则（Future）：
- `Scanning` 状态不阻塞继续拍摄，多个扫描项可并行处于 `Scanning`。
- `Failed` 状态可重试（回到 `Scanning`）或删除。
- `Matched` 状态须用户手动确认并点击 Add 才进入 `Added`，扫描结果不自动保存。
- 同时只允许最多 10 个待处理扫描项（`Scanning` + `Matched` + `Failed` 合计），上限时拍摄按钮不可用。
- `Added` 和 `Deleted` 状态从待处理列表移除，释放名额。

```mermaid
stateDiagram-v2
    [*] --> Scanning : 用户点击拍摄按钮\n生成扫描项\n初始状态 Scanning

    Scanning : Scanning\n正在识别中\n(异步识别, 不阻塞继续拍摄)\n可执行: 删除

    Scanning --> Matched : 识别成功\n找到第三方数据源匹配卡牌
    Scanning --> Failed : 识别失败\n(超时 30s / 网络失败 / 图片不可用)

    Matched : Matched\n已识别并找到匹配卡牌\n可执行: Done → 编辑 Collection Item → Add / 删除

    Failed : Failed\n识别失败\n可执行: 重试 / 删除\n不进入 Collection Item 添加流程

    Failed --> Scanning : 用户点击重试

    Matched --> Added : 用户点击 Add this card\n(单张) 或 Add all cards (批量)\n卡牌加入目标 Portfolio\nPOST /portfolio/items

    Matched --> Deleted : 用户删除该扫描项

    Failed --> Deleted : 用户删除该扫描项

    Added : Added\n已加入 Portfolio\n从待处理列表移除\n释放待处理名额

    Deleted : Deleted\n已删除扫描项\n从待处理列表移除\n释放待处理名额

    Added --> [*]
    Deleted --> [*]

    note right of Scanning
        Future 版本状态机
        v1.0 不实现
        待处理上限: 10 个
        (Scanning + Matched + Failed 合计)
    end note
```
