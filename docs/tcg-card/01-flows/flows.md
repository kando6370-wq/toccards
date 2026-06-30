# 业务流程图

> **定位**：本文件汇总 tcg-card v1.0 核心业务端到端流程图，使用 Mermaid flowchart TD 语法绘制，每图配文字说明并链接对应模块 PRD。
>
> **日期**：2026-06-30
>
> **来源**：
> - Auth 模块 PRD [`../00-product/modules/auth.md`](../00-product/modules/auth.md)
> - Profile 模块 PRD [`../00-product/modules/profile.md`](../00-product/modules/profile.md)
> - Home 模块 PRD [`../00-product/modules/home.md`](../00-product/modules/home.md)
> - Collection 模块 PRD [`../00-product/modules/collection.md`](../00-product/modules/collection.md)
> - Search 模块 PRD [`../00-product/modules/search.md`](../00-product/modules/search.md)
> - Card Detail 模块 PRD [`../00-product/modules/card-detail.md`](../00-product/modules/card-detail.md)
> - 全局规则 [`../00-product/modules/global-rules.md`](../00-product/modules/global-rules.md)

---

## 目录

1. [注册 / 登录 / 找回密码端到端](#一注册--登录--找回密码端到端)
2. [游客使用→注册迁移 / 游客→登录已有账号](#二游客使用注册迁移--游客登录已有账号)
3. [Search → Collect 加入 Portfolio](#三search--collect-加入-portfolio)
4. [卡牌详情 添加 / 编辑 / 移除 Collection Item](#四卡牌详情-添加--编辑--移除-collection-item)
5. [文件夹切换对 Home / Collection 的联动](#五文件夹切换对-home--collection-的联动)
6. [货币切换刷新链路](#六货币切换刷新链路)

---

## 一、注册 / 登录 / 找回密码端到端

> 对应 PRD：[auth.md](../00-product/modules/auth.md)

### 说明

用户通过两个入口进入 Auth 流程：Profile 未登录态点击 **Sign in / Sign up**，或 Onboarding 结束页引导。进入后选择注册 / 登录方式（Google / Apple / Email），三条路径最终都收敛到「进入 App」。Email 流程内置验证码校验与密码设置；Google / Apple 走 OAuth 授权码回调。找回密码独立于注册/登录，从 Email 登录页的 Forgot password 入口触发。

```mermaid
flowchart TD
    ENTRY["入口\n· Profile 未登录态点击 Sign in / Sign up\n· Onboarding 引导"]
    METHOD["选择注册 / 登录方式"]
    GOOGLE["Continue with Google"]
    APPLE["Continue with Apple"]
    EMAIL_INPUT["输入邮箱"]

    ENTRY --> METHOD
    METHOD --> GOOGLE
    METHOD --> APPLE
    METHOD --> EMAIL_INPUT

    %% Google flow
    GOOGLE --> GOOGLE_AUTH["拉起 Google 原生授权页"]
    GOOGLE_AUTH -->|"用户取消"| METHOD
    GOOGLE_AUTH -->|"授权成功"| GOOGLE_CB["POST /auth/oauth/google/callback\n(含 anonymous_id)"]
    GOOGLE_CB -->|"is_new_user=true"| MIGRATE_SUCCESS["游客资产迁移\n→ 进入 App (新用户 Toast)"]
    GOOGLE_CB -->|"is_new_user=false"| LOGIN_SUCCESS["进入 App (登录 Toast)\n游客资产不迁移"]
    GOOGLE_CB -->|"授权码无效 / 第三方异常"| AUTH_ERR["Toast: Authorization failed."]
    AUTH_ERR --> METHOD

    %% Apple flow
    APPLE --> APPLE_AUTH["拉起 Apple 原生授权页"]
    APPLE_AUTH -->|"用户取消"| METHOD
    APPLE_AUTH -->|"授权成功"| APPLE_CB["POST /auth/oauth/apple/callback\n(含 anonymous_id)"]
    APPLE_CB -->|"is_new_user=true"| MIGRATE_SUCCESS
    APPLE_CB -->|"is_new_user=false"| LOGIN_SUCCESS
    APPLE_CB -->|"授权码无效 / 第三方异常"| AUTH_ERR

    %% Email flow
    EMAIL_INPUT --> EMAIL_FMT{"客户端校验\n邮箱格式"}
    EMAIL_FMT -->|"格式错误"| EMAIL_ERR["展示格式错误提示"]
    EMAIL_ERR --> EMAIL_INPUT
    EMAIL_FMT -->|"格式正确"| SEND_CODE["POST /auth/register/send-code"]
    SEND_CODE -->|"CONFLICT (已注册)"| LOGIN_FLOW
    SEND_CODE -->|"RATE_LIMITED"| RATE_ERR["提示 60 秒后重试"]
    RATE_ERR --> EMAIL_INPUT
    SEND_CODE -->|"成功"| CODE_PAGE["验证码输入页 (60s 倒计时)"]

    CODE_PAGE -->|"验证码错误"| CODE_ERR["Incorrect verification code."]
    CODE_ERR --> CODE_PAGE
    CODE_PAGE -->|"验证码过期"| CODE_EXPIRE["Code expired. Please request a new code."]
    CODE_EXPIRE --> CODE_PAGE
    CODE_PAGE -->|"Resend"| SEND_CODE
    CODE_PAGE -->|"验证码正确"| PWD_PAGE["Set Password 页面"]

    PWD_PAGE -->|"密码 < 8 位"| PWD_LEN["禁止提交"]
    PWD_LEN --> PWD_PAGE
    PWD_PAGE -->|"两次不一致"| PWD_MISMATCH["Passwords do not match."]
    PWD_MISMATCH --> PWD_PAGE
    PWD_PAGE -->|"通过 → Create Account"| REGISTER["POST /auth/register/verify\n(含 anonymous_id)"]
    REGISTER -->|"成功"| MIGRATE_SUCCESS
    REGISTER -->|"失败"| REG_ERR["展示错误提示"]
    REG_ERR --> PWD_PAGE

    %% Login flow
    LOGIN_FLOW["输入密码页 (邮箱已注册)"]
    LOGIN_FLOW -->|"Forgot password"| FORGOT_START
    LOGIN_FLOW --> SIGN_IN["POST /auth/login"]
    SIGN_IN -->|"密码错误"| PWD_WRONG["Incorrect password. Please try again."]
    PWD_WRONG --> LOGIN_FLOW
    SIGN_IN -->|"成功"| LOGIN_SUCCESS

    %% Forgot password
    FORGOT_START["Reset Password 页面"]
    FORGOT_START --> FORGOT_EMAIL["输入邮箱并提交"]
    FORGOT_EMAIL --> FORGOT_FMT{"格式校验"}
    FORGOT_FMT -->|"错误"| FMT_ERR2["格式错误提示"]
    FMT_ERR2 --> FORGOT_EMAIL
    FORGOT_FMT -->|"正确"| FORGOT_SEND["POST /auth/forgot-password/send-code"]
    FORGOT_SEND -->|"邮箱未注册"| NOT_REG["Email not registered."]
    NOT_REG --> FORGOT_EMAIL
    FORGOT_SEND -->|"RATE_LIMITED"| RATE_ERR2["60 秒后重试"]
    RATE_ERR2 --> FORGOT_EMAIL
    FORGOT_SEND -->|"成功"| FORGOT_CODE["验证码输入页"]
    FORGOT_CODE -->|"错误"| CODE_ERR2["Incorrect verification code."]
    CODE_ERR2 --> FORGOT_CODE
    FORGOT_CODE -->|"过期"| CODE_EXPIRE2["Code expired."]
    CODE_EXPIRE2 --> FORGOT_CODE
    FORGOT_CODE -->|"正确"| FORGOT_VERIFY["POST /auth/forgot-password/verify-code\n→ 获取 reset_token"]
    FORGOT_VERIFY --> NEW_PWD["Set New Password 页面"]
    NEW_PWD -->|"< 8 位 / 不一致"| PWD_ERR3["校验失败提示"]
    PWD_ERR3 --> NEW_PWD
    NEW_PWD -->|"通过 → Reset Password"| RESET["POST /auth/forgot-password/reset"]
    RESET -->|"token 无效 / 过期"| TOKEN_ERR["Code expired. 返回验证码页"]
    TOKEN_ERR --> FORGOT_CODE
    RESET -->|"成功"| RESET_OK["Toast: Password reset successfully.\n返回邮箱登录页"]
    RESET_OK --> LOGIN_FLOW
```

---

## 二、游客使用→注册迁移 / 游客→登录已有账号

> 对应 PRD：[global-rules.md §十四](../00-product/modules/global-rules.md)、[profile.md §三](../00-product/modules/profile.md)、[auth.md §八](../00-product/modules/auth.md)

### 说明

App 首次启动时，后端自动创建 `anonymous_account`（持有 JWT，关联 `device_id`），用户可在游客状态下完整使用 Portfolio、Wishlist、Search 等功能，产生的数据均存储在该匿名账号下。

当游客选择**注册新账号**时，客户端在注册请求中携带 `anonymous_id`，后端将游客资产迁移到新账号（`migrated=true`）；若迁移在注册请求中失败，可通过 `POST /auth/migrate-assets` 显式重试。

当游客选择**登录已有账号**时，游客资产**不迁移、不合并**，登录后展示该账号资产。

```mermaid
flowchart TD
    GUEST["游客状态\n(anonymous_account + JWT)"]
    USE["使用 App\n(Portfolio / Wishlist / Search / Scan 等)"]
    GUEST --> USE
    USE --> TRIGGER["Profile 点击 Sign in / Sign up\n→ 调起 Auth 弹窗"]

    TRIGGER --> AUTH_CHOICE{"注册新账号\n还是\n登录已有账号?"}

    %% 注册路径
    AUTH_CHOICE -->|"注册新账号\n(Email/Google/Apple 新用户)"| REG["完成注册流程\n(携带 anonymous_id)"]
    REG --> MIGRATE{"后端迁移\n游客资产"}
    MIGRATE -->|"migrated=true\n(迁移成功)"| MIGRATED["进入 App (登录态)\n展示迁移后新账号资产\n原游客资产不再独立展示"]
    MIGRATE -->|"迁移失败"| MIG_FAIL["保留游客本地资产\n展示专用失败提示\n账号保持登录态\n可稍后重试 POST /auth/migrate-assets"]
    MIG_FAIL --> MIGRATED_RETRY["用户重试迁移"]
    MIGRATED_RETRY --> MIGRATE

    %% 登录路径
    AUTH_CHOICE -->|"登录已有账号\n(Email/Google/Apple 已有账号)"| LOGIN["完成登录流程\n(不携带 anonymous_id 用于迁移)"]
    LOGIN --> LOGIN_DONE["进入 App (登录态)\n展示该账号资产\n游客资产不迁移、不合并\n游客资产保持不变"]

    %% 登出后
    MIGRATED --> LOGOUT_OPT["可能的后续操作: 退出登录"]
    LOGIN_DONE --> LOGOUT_OPT
    LOGOUT_OPT -->|"POST /auth/logout"| BACK_GUEST["回到游客态\n若本地仍有游客资产则展示\n否则展示空游客状态"]
    BACK_GUEST --> GUEST
```

---

## 三、Search → Collect 加入 Portfolio

> 对应 PRD：[search.md §十三](../00-product/modules/search.md)、[search.md §十五](../00-product/modules/search.md)

### 说明

用户在 Search 的 Cards 列表中浏览或搜索卡牌，通过 Collect 按钮快捷加入当前选中 Portfolio 文件夹（系统自动生成默认 Collection Item，无需填写表单）。若已在 Wishlist 中，加入 Portfolio 后系统自动将其从 Wishlist 移除（同一对象不可同时在两处）。Collected 再次点击可撤销加入。

```mermaid
flowchart TD
    SEARCH_ENTRY["进入 Search 页 Cards Tab"]
    BROWSE["浏览 / 搜索卡牌列表\n(当前 Game/IP 范围)"]
    SEARCH_ENTRY --> BROWSE

    BROWSE --> CARD_ITEM["卡牌列表项\n展示: 名称 / 价格 / 30D% / Qty / Collect / Heart"]

    CARD_ITEM --> CHECK_COLLECT{"Collect / Collected 状态"}

    %% Not collected
    CHECK_COLLECT -->|"Collect (未加入当前文件夹)"| CLICK_COLLECT["用户点击 Collect"]
    CLICK_COLLECT --> POST_ITEM["POST /portfolio/items\n(加入当前选中文件夹\n系统生成默认 Collection Item)"]
    POST_ITEM -->|"成功"| COLLECTED_STATE["按钮变为 Collected\nQty: 0 → 1\n若原在 Wishlist → 自动移除 Wishlist\n(Workers 副作用)"]
    POST_ITEM -->|"失败"| COLLECT_FAIL["Toast: Something went wrong. Please try again."]
    COLLECT_FAIL --> CARD_ITEM

    %% Already collected (single item)
    CHECK_COLLECT -->|"Collected (已加入当前文件夹\n且只有 1 条 Collection Item)"| CLICK_COLLECTED["用户再次点击 Collected"]
    CLICK_COLLECTED --> DEL_ITEM["DELETE /portfolio/items/{id}"]
    DEL_ITEM -->|"成功"| UNCOLLECTED_STATE["按钮恢复 Collect\nQty 更新为 0"]
    DEL_ITEM -->|"失败"| DEL_FAIL["Toast: Something went wrong. Please try again."]
    DEL_FAIL --> CARD_ITEM

    %% Multiple items
    CHECK_COLLECT -->|"Collected (当前文件夹有多条 Collection Item)"| GO_DETAIL["进入卡牌详情页\n由用户手动管理 (避免误删)"]

    %% Wishlist heart
    CARD_ITEM --> CHECK_HEART{"Wishlist 爱心状态"}
    CHECK_HEART -->|"空心 (未加入 Wishlist)"| CLICK_HEART["点击空心爱心"]
    CLICK_HEART --> POST_WISH["POST /wishlist"]
    POST_WISH -->|"成功"| HEART_FULL["爱心变实心\n已加入 Wishlist"]
    POST_WISH -->|"失败"| WISH_FAIL["Toast: Something went wrong. Please try again."]
    WISH_FAIL --> CARD_ITEM

    CHECK_HEART -->|"实心 (已在 Wishlist)"| CLICK_HEART_REMOVE["点击实心爱心"]
    CLICK_HEART_REMOVE --> DEL_WISH["DELETE /wishlist/{id}"]
    DEL_WISH -->|"成功"| HEART_EMPTY["爱心恢复空心"]
    DEL_WISH -->|"失败"| WISH_DEL_FAIL["Toast: Something went wrong. Please try again."]
    WISH_DEL_FAIL --> CARD_ITEM

    COLLECTED_STATE --> BROWSE
    UNCOLLECTED_STATE --> BROWSE
    HEART_FULL --> BROWSE
    HEART_EMPTY --> BROWSE
```

> **互斥说明**：
> - **强制方向（PRD 明确）**：同对象不可同时在 Portfolio 与 Wishlist。点击 **Collect 加入 Portfolio 时，若对象已在 Wishlist，自动移除 Wishlist**（search.md §十三、§十四.6，Workers 副作用，已在上图 `COLLECTED_STATE` 节点体现）。
> - **反向行为 ⚠️ TBD**：对象已在 Portfolio（Collected 状态）时点击空心 Heart 加入 Wishlist 的行为，PRD 未明确。建议：已 Collect 状态下 Heart 禁用，或加入 Wishlist 时先移出 Portfolio——待产品确认。本图 Heart 加入 Wishlist 路径仅陈述成功加入 Wishlist，不在成功节点上断言互斥裁决。

---

## 四、卡牌详情 添加 / 编辑 / 移除 Collection Item

> 对应 PRD：[card-detail.md](../00-product/modules/card-detail.md)

### 说明

卡牌详情页有两种状态：**未加入 Portfolio** 展示基础信息 + Price Tab；**已加入 Portfolio** 额外展示 Collection Item Tab，支持编辑和移除。

- **添加**：从未加入状态点击 Add to Portfolio，填写 Collection Item 信息后保存，卡牌进入当前文件夹。
- **编辑**：从已加入状态进入编辑页，修改数量 / 文件夹 / Grader / 品相等，保存后刷新相关数据。
- **移除**：点击 Remove from Portfolio，经二次确认弹窗后删除，返回 Collection 列表并刷新 Home 数据。

```mermaid
flowchart TD
    ENTRY_UNOWNED["进入详情页\n(未加入 Portfolio 状态)\n展示: 基础信息 + Price Tab"]
    ENTRY_OWNED["进入详情页\n(已加入 Portfolio 状态)\n展示: 基础信息 + Collection Item Tab + Price Tab"]

    %% Add to Portfolio
    ENTRY_UNOWNED --> ADD_BTN["点击 Add to Portfolio (右上角)"]
    ADD_BTN --> ADD_FORM["Collection Item 添加页\n填写: Quantity / Portfolio / Grader /\nCondition-Grade / Language / Finish /\nPurchase Price / Notes"]
    ADD_FORM --> FORM_VALIDATE{"表单校验"}
    FORM_VALIDATE -->|"Quantity 错误"| QTY_ERR["提示文案 (量必须为正整数)"]
    QTY_ERR --> ADD_FORM
    FORM_VALIDATE -->|"通过 → Save"| SAVE_NEW["POST /portfolio/items"]
    SAVE_NEW -->|"成功"| OWNED_STATE["切换为已加入状态\n刷新: Home 总资产 / 图表 /\nMost Valuable / Collection 列表"]
    SAVE_NEW -->|"失败"| SAVE_FAIL["停留编辑页\n保留用户输入\nToast: Something went wrong."]
    SAVE_FAIL --> ADD_FORM

    %% Edit Collection Item
    ENTRY_OWNED --> EDIT_BTN["点击 Edit item"]
    EDIT_BTN --> EDIT_FORM["编辑 Collection Item 页\n(Cancel / Save changes)"]
    EDIT_FORM -->|"Cancel"| ENTRY_OWNED
    EDIT_FORM --> EDIT_VALIDATE{"表单校验"}
    EDIT_VALIDATE -->|"Quantity 错误"| QTY_ERR2["提示文案"]
    QTY_ERR2 --> EDIT_FORM
    EDIT_VALIDATE -->|"通过 → Save changes"| SAVE_EDIT["PATCH /portfolio/items/{id}"]
    SAVE_EDIT -->|"成功"| EDIT_OK["返回已加入状态\n刷新 Collection Item 展示\n刷新: Home 总资产 / 图表 / Most Valuable /\nCollection 列表 / 对应文件夹"]
    SAVE_EDIT -->|"失败"| EDIT_FAIL["停留编辑页\n保留用户输入\nToast: Something went wrong."]
    EDIT_FAIL --> EDIT_FORM

    %% Remove from Portfolio
    ENTRY_OWNED --> REMOVE_BTN["点击 Remove from Portfolio"]
    REMOVE_BTN --> CONFIRM_MODAL["二次确认弹窗\n(Cancel / Remove)"]
    CONFIRM_MODAL -->|"Cancel"| ENTRY_OWNED
    CONFIRM_MODAL -->|"Remove"| DELETE_ITEM["DELETE /portfolio/items/{id}"]
    DELETE_ITEM -->|"成功"| REMOVE_OK["返回 Collection Portfolio 列表\n刷新: Home 总资产 / 图表 /\nMost Valuable / Collection 列表"]
    DELETE_ITEM -->|"失败"| REMOVE_FAIL["不删除数据\n停留当前页\nToast: Something went wrong."]
    REMOVE_FAIL --> ENTRY_OWNED

    %% Remove from Wishlist (for cards in Wishlist but not Portfolio)
    ENTRY_UNOWNED --> WISHLIST_BTN["点击 Remove from Wishlist\n(已在 Wishlist 的卡牌)"]
    WISHLIST_BTN --> CONFIRM_WISH["二次确认弹窗\n(Cancel / Remove)"]
    CONFIRM_WISH -->|"Cancel"| ENTRY_UNOWNED
    CONFIRM_WISH -->|"Remove"| DEL_WISH2["DELETE /wishlist/{id}"]
    DEL_WISH2 -->|"成功"| WISH_REMOVED["从 Wishlist 移除\n返回上一页"]
    DEL_WISH2 -->|"失败"| WISH_FAIL2["不删除\nToast: Something went wrong."]
    WISH_FAIL2 --> ENTRY_UNOWNED
```

---

## 五、文件夹切换对 Home / Collection 的联动

> 对应 PRD：[home.md §八](../00-product/modules/home.md)、[collection.md §十一](../00-product/modules/collection.md)

### 说明

文件夹切换入口位于 Home 顶部文件夹名称和 Collection 顶部文件夹名称（两处共享同一弹窗逻辑）。切换后，Home 总资产卡片（总金额 / 图表 / Most Valuable）和 Collection - Portfolio 列表同时刷新至新文件夹数据；Trending Today 和 Wishlist 不受文件夹影响。冷启动后默认展示星标（default）文件夹；本次会话手动切换优先级高于默认，但不跨冷启动。

```mermaid
flowchart TD
    COLD_START["冷启动\n默认展示星标文件夹 (is_default=1)"]
    COLD_START --> HOME_SHOW["Home: 展示星标文件夹\n总资产 / 图表 / Most Valuable"]
    COLD_START --> COL_SHOW["Collection: 展示星标文件夹\nPortfolio 列表"]

    HOME_SHOW --> CLICK_FOLDER_HOME["点击 Home 顶部文件夹名称\n打开文件夹弹窗"]
    COL_SHOW --> CLICK_FOLDER_COL["点击 Collection 顶部文件夹名称\n打开文件夹弹窗"]

    CLICK_FOLDER_HOME --> FOLDER_MODAL["文件夹切换弹窗\n(文件夹列表 + 当前选中标识 + 星标标识\n新建 / 编辑 / 删除 / 排序)"]
    CLICK_FOLDER_COL --> FOLDER_MODAL

    FOLDER_MODAL -->|"点击文件夹行"| SWITCH_FOLDER["切换到选中文件夹\nPATCH /preferences\n(last_selected_folder_id)"]
    SWITCH_FOLDER -->|"成功"| REFRESH_BOTH["Home + Collection 同步刷新\n· Home: 总资产 / 图表 / Most Valuable 更新\n· Collection Portfolio: 列表刷新为新文件夹数据\n· Trending Today: 不刷新\n· Wishlist: 不刷新"]
    SWITCH_FOLDER -->|"失败"| SWITCH_FAIL["保留原文件夹\nToast: Something went wrong."]
    SWITCH_FAIL --> FOLDER_MODAL

    FOLDER_MODAL -->|"+ Add new"| NEW_FOLDER["新建文件夹弹窗\n(Name 必填 / 最多 50 字符)\nPOST /portfolio/folders"]
    NEW_FOLDER -->|"成功"| FOLDER_MODAL
    NEW_FOLDER -->|"名称重复"| DUP_ERR["Portfolio name already exists"]
    DUP_ERR --> NEW_FOLDER
    NEW_FOLDER -->|"失败"| NEW_FAIL["Toast: Something went wrong."]
    NEW_FAIL --> FOLDER_MODAL

    FOLDER_MODAL -->|"编辑图标"| EDIT_FOLDER["编辑文件夹弹窗\nPATCH /portfolio/folders/{folder_id}"]
    EDIT_FOLDER -->|"成功"| FOLDER_NAME_SYNC["Home + Collection 文件夹名称同步更新"]
    FOLDER_NAME_SYNC --> FOLDER_MODAL
    EDIT_FOLDER -->|"失败"| EDIT_FAIL["Toast: Something went wrong."]
    EDIT_FAIL --> FOLDER_MODAL

    FOLDER_MODAL -->|"删除图标 (非默认文件夹)"| DELETE_CONFIRM["删除确认弹窗\n(Cancel / Delete)"]
    DELETE_CONFIRM -->|"Cancel"| FOLDER_MODAL
    DELETE_CONFIRM -->|"Delete"| DEL_FOLDER["DELETE /portfolio/folders/{folder_id}\n(ON DELETE CASCADE: 删除内部所有 Collection Item)"]
    DEL_FOLDER -->|"成功"| DEL_OK["若删除的是当前选中文件夹\n→ 自动切换到默认文件夹\nHome + Collection 数据同步刷新"]
    DEL_FOLDER -->|"失败"| DEL_FAIL["保留原文件夹\nToast: Something went wrong."]
    DEL_FAIL --> FOLDER_MODAL

    REFRESH_BOTH --> HOME_SHOW
    REFRESH_BOTH --> COL_SHOW
    DEL_OK --> HOME_SHOW
    DEL_OK --> COL_SHOW

    FOLDER_MODAL -->|"拖动排序"| REORDER["PATCH /portfolio/folders/reorder\n更新 sort_order"]
    REORDER -->|"成功"| ORDER_SYNC["排序结果同步到 Home + Collection 文件夹列表"]
    ORDER_SYNC --> FOLDER_MODAL
    REORDER -->|"失败"| REORDER_FAIL["回滚到调整前顺序\nToast: Something went wrong."]
    REORDER_FAIL --> FOLDER_MODAL
```

---

## 六、货币切换刷新链路

> 对应 PRD：[global-rules.md §七](../00-product/modules/global-rules.md)、[home.md §九](../00-product/modules/home.md)

### 说明

货币切换入口位于 Home 右上角货币码。点击后弹出 `Select currency` 弹窗，选择新货币后，客户端调用汇率接口（`GET /rates`）获取换算比率，并持久化用户偏好（`PATCH /preferences`）。切换成功后，App 内**所有**金额字段同步换算（Home 总资产、Collection 当前价值、Search 卡牌价格、卡牌详情价格等）；**涨跌百分比不变**。货币偏好与账号绑定，游客账号同样有效。

```mermaid
flowchart TD
    HOME_TOP["Home 右上角货币码入口\n(如 USD)"]
    HOME_TOP --> CURRENCY_MODAL["Select Currency 弹窗\n(USD / EUR / JPY / GBP / CAD / AUD / NZD / SGD)"]

    CURRENCY_MODAL --> CHECK_SAME{"点击的货币\n是否与当前相同?"}
    CHECK_SAME -->|"相同"| NO_OP["不重复调用接口\n弹窗关闭"]
    CHECK_SAME -->|"不同"| FETCH_RATE["GET /rates\n(获取汇率)"]

    FETCH_RATE -->|"成功"| SAVE_PREF["PATCH /preferences\n(currency = 新货币码)"]
    SAVE_PREF -->|"成功"| CONVERT_ALL["所有金额字段同步换算\n· Home: 总资产 / 30D Change 金额\n· Collection Portfolio: 当前价值\n· Wishlist: 市场参考价\n· Search 列表: 卡牌价格\n· Card Detail: 市场价格 / Market Prices\n弹窗关闭\n右上角货币码更新"]
    SAVE_PREF -->|"失败"| SWITCH_FAIL["保持原货币\nToast: Something went wrong."]

    FETCH_RATE -->|"失败"| SWITCH_FAIL

    CONVERT_ALL --> PERCENTAGE_NOTE["注意: 涨跌百分比不随货币切换变化\n(Home 30D% / Trending Today 当日% /\nMost Valuable 涨跌% / Collection 30D% /\nSearch 30D% 均不变)"]

    SWITCH_FAIL --> CURRENCY_MODAL
    NO_OP --> HOME_SHOW["返回 Home"]
    PERCENTAGE_NOTE --> HOME_SHOW
```
