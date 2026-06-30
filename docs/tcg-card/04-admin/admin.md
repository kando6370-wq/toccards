# tcg-card 管理后台 PRD

> **定位**：定义 tcg-card v1.0 管理后台的功能范围、页面结构、字段映射、操作流程与异常处理。供后端接口对照、前端实现参考。  
> **日期**：2026-06-30  
> **视觉参考**（截图目录，范围冲突时以本文为准）：[`docs/tcg_cord_docs/ui/管理后台/`](../../../tcg_cord_docs/ui/管理后台/)  
>
> **来源引用**：
> - 数据模型 [`docs/tcg-card/03-data-api/data-model.md`](../03-data-api/data-model.md)
> - API 规范 [`docs/tcg-card/03-data-api/api-spec.md`](../03-data-api/api-spec.md) §5
> - 跨切面规则 [`docs/tcg-card/00-product/modules/global-rules.md`](../00-product/modules/global-rules.md)（失败/确认弹窗风格统一引用此处，不在本文重复定义）

---

## 目录

1. [通用规则](#1-通用规则)
2. [用户管理](#2-用户管理)
3. [反馈 / 客服工单](#3-反馈--客服工单)
4. [运营配置](#4-运营配置)
5. [卡牌数据运维](#5-卡牌数据运维)

---

## 1. 通用规则

### 1.1 鉴权与账号体系

管理后台**独立于 App 用户体系**，不共享 `user` 表或 App JWT。  
后台鉴权基于 `admin_user` 表（见 data-model.md §6），由独立的 Admin Token（JWT）签发。

**角色设计（v1.0）**：

| 角色 | 说明 |
|---|---|
| `super_admin` | 完整权限：读 + 写 + 角色管理 |
| `operator` | 受限权限：读 + 部分写（见各模块说明），不可进行账号禁用、角色变更等高风险操作 |

> 选择理由：v1.0 即支持双角色，避免后期需改鉴权模型。`super_admin` 管理后台核心操作，`operator` 负责日常运营配置与工单处理，职责分离清晰。预留 `role` 字段供后续扩展（见 data-model §6 `admin_user` 表）。

Admin Token 的签发逻辑独立于 App `/auth` 路径，使用 `/admin/auth` 路径（⚠️ TBD：admin 登录接口待补充到 api-spec §5 前置部分）。

### 1.2 列表通用约定

所有列表页遵循以下统一约定：

- **分页**：默认 `page=1, page_size=20`，最大 `page_size=100`，支持跳页。
- **排序**：默认按 `created_at DESC`；各页面可覆盖默认排序字段。
- **搜索**：搜索框为模糊匹配，搜索中展示加载态；无结果展示"暂无数据"空状态。
- **筛选**：筛选条件以 Tag / Dropdown 呈现，多个筛选条件之间为 AND 关系。
- **刷新**：列表数据加载失败时，按 `global-rules.md §二` 展示局部失败状态 + Refresh 按钮。

### 1.3 操作反馈

- **操作失败**：轻操作失败展示通用 Toast（文案见 `global-rules.md §四`）；高风险操作失败展示场景专用文案（见 `global-rules.md §13.2`）。
- **二次确认**：禁用账号等不可逆操作，需弹出确认弹窗（规则见 `global-rules.md §九`）。弹窗须包含取消按钮；确认失败后不改变数据并展示 Toast。
- **防重复点击**：所有提交/保存/删除按钮，请求中置灰或展示 loading（规则见 `global-rules.md §十一`）。

### 1.4 v1.0 范围边界

- **不含**订阅相关后台内容（含订阅工单、订阅配置）。
- **不含**管理员账号的后台创建/管理页（由数据库初始化或 super_admin 操作，v1.0 不含管理员管理界面）。

---

## 2. 用户管理

**定位**：提供正式账号与匿名账号的统一视图，支持搜索、详情查看和账号禁用操作。

**接口引用**：`api-spec.md §5.1`（`GET /admin/users`、`GET /admin/users/{account_type}/{id}`、`PATCH /admin/users/user/{id}/disable`）

### 2.1 用户列表页

**页面路径**：`/admin/users`

**筛选 / 搜索**：

| 控件 | 筛选字段 | 说明 |
|---|---|---|
| 账号类型 Tab / Dropdown | `type` | `全部` / `正式账号（user）` / `匿名账号（anonymous）` |
| 搜索框 | `q` | 正式账号按 `email` 模糊搜索；匿名账号按 `device_id` 搜索 |

**列表字段**：

| 字段 | 数据来源 | 说明 |
|---|---|---|
| 账号类型 | `account_type` | `user` 展示为"正式账号"；`anonymous` 展示为"匿名账号" |
| 账号 ID | `id` | `user.id` 或 `anonymous_account.id` |
| 邮箱 | `email` | 仅正式账号有值；匿名账号展示 `—` |
| 设备 ID | `device_id` | 仅匿名账号有值；正式账号展示 `—` |
| 注册时间 | `created_at` | 账号创建时间 |
| 状态 | `deleted_at`（正式账号）/ `upgraded_user_id`（匿名账号） | 正式账号：`正常` / `已禁用`；匿名账号：`游客` / `已升级` |

**操作**：

- 点击行 → 进入用户详情页（见 §2.2）。
- `super_admin` 可在列表行操作区域快捷禁用账号（二次确认，见 §2.3）。
- `operator` 只读，不可禁用。

**空状态**：无数据时展示"暂无用户数据"；搜索无结果时展示"未找到匹配用户"。

### 2.2 用户详情页

**页面路径**：`/admin/users/{account_type}/{id}`

**正式账号（user）详情字段**：

| 字段 | 数据来源 | 说明 |
|---|---|---|
| 账号 ID | `user.id` | ULID |
| 邮箱 | `user.email` | |
| 展示名 | `user.display_name` | 未设置时展示 `—` |
| 注册时间 | `user.created_at` | |
| 更新时间 | `user.updated_at` | |
| 账号状态 | `user.deleted_at` | NULL = 正常；非 NULL = 已禁用，展示禁用时间 |
| 第三方登录绑定 | `auth_identity[]` | 列出 `provider`（google / apple）和 `provider_uid` |
| 活跃 Session 数 | `session_count` | 当前未吊销的 session 数量 |

**资产汇总**（`asset_summary`，对应 `portfolio_folder` / `collection_item` / `wishlist_item` 表）：

| 字段 | 说明 |
|---|---|
| 文件夹数 | `folder_count` |
| 持卡数 | `item_count` |
| 心愿单数 | `wishlist_count` |

**匿名账号（anonymous_account）详情字段**：

| 字段 | 数据来源 | 说明 |
|---|---|---|
| 账号 ID | `anonymous_account.id` | ULID |
| 设备 ID | `anonymous_account.device_id` | |
| 创建时间 | `anonymous_account.created_at` | |
| 升级状态 | `anonymous_account.upgraded_user_id` | NULL = 仍为游客；非 NULL = 已升级，展示升级后的 user.id |
| 资产汇总 | 同正式账号 | 以 `owner_type='anonymous', owner_id=anonymous_account.id` 查询 |

> **说明**：后台用户管理须同时呈现正式账号与匿名账号，匿名账号（游客）全量可见，不过滤。管理员可通过 `upgraded_user_id` 追溯升级路径。

**操作（仅 super_admin）**：

- `禁用账号`按钮：仅对正式账号（`account_type=user`）显示；账号已禁用（`deleted_at` 非 NULL）时按钮变为`已禁用`并置灰。  
- 点击`禁用账号` → 弹出确认弹窗（`global-rules.md §九`）→ 确认后调用 `PATCH /admin/users/user/{id}/disable` → 成功后刷新详情页状态。

**异常**：
- 账号不存在：展示整页失败提示（`global-rules.md §二.2.2`）。
- 禁用失败：Toast 展示 `Something went wrong. Please try again.`。

### 2.3 禁用确认弹窗

- 标题：`禁用账号`
- 正文：`确认禁用该用户？禁用后该账号将无法登录，操作不可撤销（如需恢复请联系数据库管理员）。`
- 按钮：`取消` / `禁用`（`Disable`，高风险色）
- 禁用按钮点击后置灰 + loading，成功后关闭弹窗并刷新页面状态。

---

## 3. 反馈 / 客服工单

**定位**：管理 App 用户提交的 `feedback_ticket` 工单，支持列表浏览、详情查看与状态流转。

**接口引用**：`api-spec.md §5.2`（`GET /admin/feedbacks`、`GET /admin/feedbacks/{ticket_id}`、`PATCH /admin/feedbacks/{ticket_id}/status`）

**关联表**：`feedback_ticket`（data-model.md §5.4）

### 3.1 工单列表页

**页面路径**：`/admin/feedbacks`

**筛选 / 排序**：

| 控件 | 字段 | 说明 |
|---|---|---|
| 状态 Tab / Dropdown | `status` | `全部` / `Open` / `In Progress` / `Closed` |
| 排序 | `sort_by` + `sort_order` | `创建时间` / `更新时间`，默认 `created_at DESC` |

**列表字段**：

| 字段 | 数据来源 | 说明 |
|---|---|---|
| 工单 ID | `feedback_ticket.id` | |
| 联系邮箱 | `feedback_ticket.email` | |
| 反馈类型 | `feedback_ticket.types` | JSON 数组，展示为标签组，如 `Bug Report`、`Feature Request` |
| 功能模块 | `feedback_ticket.functions` | JSON 数组，展示为标签组，如 `Search`、`Scan` |
| 状态 | `feedback_ticket.status` | `Open`（蓝）/ `In Progress`（橙）/ `Closed`（灰） |
| 提交时间 | `feedback_ticket.created_at` | |

**操作**：点击行 → 进入工单详情页（见 §3.2）。

### 3.2 工单详情页

**页面路径**：`/admin/feedbacks/{ticket_id}`

**展示字段**：

| 字段 | 数据来源 | 说明 |
|---|---|---|
| 工单 ID | `feedback_ticket.id` | |
| 联系邮箱 | `feedback_ticket.email` | |
| 反馈类型 | `feedback_ticket.types` | 全部标签展示 |
| 功能模块 | `feedback_ticket.functions` | 全部标签展示 |
| 反馈内容 | `feedback_ticket.message` | 完整文本，最多 1000 字符 |
| 当前状态 | `feedback_ticket.status` | |
| 提交时间 | `feedback_ticket.created_at` | |
| 最后更新 | `feedback_ticket.updated_at` | |

**操作（`super_admin` 与 `operator` 均可）**：

- **状态流转**：通过 Dropdown 或 Action 按钮更新状态，调用 `PATCH /admin/feedbacks/{ticket_id}/status`。

**状态流转规则**：

```
open ──→ in_progress ──→ closed
  └─────────────────────────→
  └──────────────← (closed → in_progress，允许重新打开)
```

| 当前状态 | 可流转状态 |
|---|---|
| `open` | `in_progress`、`closed` |
| `in_progress` | `closed`、`open` |
| `closed` | `in_progress`（重新打开） |

**异常**：
- 工单不存在：展示整页失败提示。
- 状态更新失败：Toast 展示 `Something went wrong. Please try again.`。

### 3.3 v1.0 范围说明

- 不含回复/评论功能（⚠️ TBD：后续版本可考虑增加内部备注）。
- 不含订阅相关的工单类型。

---

## 4. 运营配置

**定位**：管理启动引导图、版本升级提示、公告、协议链接等 `app_config` KV 项，以及 Trending Today 的置顶（`trending_pin`）配置。

**接口引用**：`api-spec.md §5.3`（`GET/PATCH /admin/app-config`、`GET/POST/PATCH/DELETE /admin/trending-pins`）

**关联表**：`app_config`（data-model.md §5.3）、`trending_pin`（data-model.md §5.2）

### 4.1 App 配置管理

**页面路径**：`/admin/app-config`

**配置项列表**（对应 `app_config.key`）：

| 配置 Key | 展示名称 | value 说明 | 编辑形式 |
|---|---|---|---|
| `onboarding_images` | 启动引导图 | URL 数组（JSON），每项为一张引导图 URL | 多行 URL 输入列表；支持增删排序 |
| `upgrade_prompt` | 版本升级提示 | JSON：`{ "min_version": "1.0.0", "title": "...", "message": "...", "store_url": "..." }` | 多字段表单 |
| `announcement` | 首页公告 | JSON：`{ "title": "...", "body": "...", "expires_at": "ISO 8601" }` | 多字段表单 + 日期选择器 |
| `terms_url` | 服务条款链接 | 字符串 URL（⚠️ TBD：实际值待确认） | 单行 URL 输入 |
| `privacy_url` | 隐私政策链接 | 字符串 URL（⚠️ TBD：实际值待确认） | 单行 URL 输入 |
| `app_store_url` | App Store 下载链接 | 字符串 URL（⚠️ TBD：实际值待确认） | 单行 URL 输入 |

**权限**：`super_admin` 与 `operator` 均可查看和编辑所有配置项。

**操作流程**：

1. 页面展示全量配置项列表，每项显示当前 value、`updated_by`（管理员 `admin_user.id`）、`updated_at`。
2. 点击配置项 → 展开内联编辑表单，或进入独立编辑页（UI 二选一，⚠️ TBD）。
3. 保存 → 调用 `PATCH /admin/app-config/{key}`（`updated_by` 由 Workers 自动写入当前管理员 ID）。
4. 成功后刷新当前配置项显示值。

**异常**：
- 加载失败：展示局部失败状态 + Refresh（`global-rules.md §二.2.1`）。
- 保存失败：Toast 展示 `Something went wrong. Please try again.`。

### 4.2 Trending 置顶管理

**页面路径**：`/admin/trending-pins`（或作为运营配置的子 Tab）

**定位**：管理 Trending Today 列表中的运营置顶卡牌（`trending_pin` 表），置顶的 `card_ref` 优先展示在前台 Trending Today 列表首位（按 `rank` 排序）。

**列表字段**（对应 `trending_pin` 表）：

| 字段 | 数据来源 | 说明 |
|---|---|---|
| 置顶 ID | `trending_pin.id` | |
| 卡牌标识 | `trending_pin.card_ref` | 第三方卡牌唯一标识 |
| 排序 | `trending_pin.rank` | 数字越小越靠前；从 1 开始 |
| 状态 | `trending_pin.active` | `生效` / `暂停` |
| 最后更新 | `trending_pin.updated_at` | |

**操作**：

| 操作 | 权限 | 接口 |
|---|---|---|
| 新增置顶 | `super_admin`、`operator` | `POST /admin/trending-pins` |
| 修改排序 / 状态 | `super_admin`、`operator` | `PATCH /admin/trending-pins/{pin_id}` |
| 删除置顶 | `super_admin` | `DELETE /admin/trending-pins/{pin_id}` |

**新增置顶表单**：

| 字段 | 是否必填 | 说明 |
|---|---|---|
| `card_ref` | 必填 | 输入或从搜索框选择；若该 card_ref 已有置顶记录则报冲突错误 |
| `rank` | 必填 | 正整数，从 1 开始 |
| `active` | 必填，默认 `true` | 立即生效或暂存为暂停 |

**异常**：
- 新增时 card_ref 已存在：展示 `该卡牌已有置顶记录，请直接编辑`。
- 保存/删除失败：Toast 展示 `Something went wrong. Please try again.`。

---

## 5. 卡牌数据运维

**定位**：维护 `card_override` 覆盖层，支持字段纠错、补图，以及手动录入第三方无数据的缺失卡（`is_missing_card=1`）。

**接口引用**：`api-spec.md §5.4`（`GET/POST/PATCH/DELETE /admin/card-overrides`、`POST /admin/card-overrides/image-upload`）

**关联表**：`card_override`（data-model.md §5.1）

**权限**：`super_admin` 与 `operator` 均可增改 card_override；`super_admin` 可删除。

### 5.1 Card Override 列表页

**页面路径**：`/admin/card-overrides`

**筛选 / 搜索**：

| 控件 | 字段 | 说明 |
|---|---|---|
| 缺失卡筛选 | `is_missing_card` | `全部` / `仅缺失卡`（`is_missing_card=true`）/ `仅覆盖层`（`false`） |
| 搜索框 | `q` | 按 `card_ref` 模糊搜索 |

**列表字段**：

| 字段 | 数据来源 | 说明 |
|---|---|---|
| 卡牌标识 | `card_override.card_ref` | |
| 覆盖字段 | `card_override.override_fields` | JSON 预览（key 列表，如 `name, set_name`）；点击展开 |
| 图片 | `card_override.image_url` | 有值展示缩略图；NULL 展示 `—` |
| 缺失卡 | `card_override.is_missing_card` | `是` / `否` |
| 最后更新 | `card_override.updated_at` | |

**操作**：

- 点击行 → 进入 override 详情 / 编辑页（见 §5.2）。
- 列表顶部提供`新增覆盖`按钮（同时用于录入缺失卡）。

### 5.2 Card Override 编辑页

**页面路径**：`/admin/card-overrides/{override_id}`（编辑）；`/admin/card-overrides/new`（新增）

**表单字段**：

| 字段 | 是否必填 | 数据来源 | 说明 |
|---|---|---|---|
| `card_ref` | 必填（新增时） | `card_override.card_ref` | 编辑模式下只读，不可更改 |
| `override_fields` | 可选 | `card_override.override_fields` | 字段级 JSON 对象；支持结构化多行编辑（卡名、系列名、编号等子字段）；⚠️ TBD：可编辑子字段枚举取决于第三方数据模型 |
| `image_url` | 可选 | `card_override.image_url` | 补图 URL 输入；有值时展示预览 |
| `is_missing_card` | 必填，默认 `false` | `card_override.is_missing_card` | 勾选后表示该卡在第三方无数据，完全由覆盖层提供信息 |

**保存操作**：

- 新增：调用 `POST /admin/card-overrides`，成功后跳转至列表或该记录详情页。
- 编辑：调用 `PATCH /admin/card-overrides/{override_id}`，成功后刷新当前页。

**删除操作（仅 super_admin）**：

- 详情页底部展示`删除覆盖`按钮。
- 点击 → 弹出确认弹窗（`global-rules.md §九`，文案：`删除后该卡牌将恢复使用第三方数据，是否确认？`）。
- 确认 → 调用 `DELETE /admin/card-overrides/{override_id}`。

### 5.3 补图（快捷操作）

**定位**：无需进入编辑页，直接为指定 card_ref 更新图片 URL；若 override 记录不存在则自动创建。

**接口**：`POST /admin/card-overrides/image-upload`

**入口**：可在列表行操作区显示`补图`按钮，点击弹出轻量弹窗：

| 字段 | 必填 | 说明 |
|---|---|---|
| `card_ref` | 必填 | 预填（从列表行带入）或手动输入 |
| `image_url` | 必填 | 新图片 URL |

**成功**：Toast 展示 `图片已更新`；列表行缩略图刷新。

**异常**：
- card_ref 格式校验失败：字段级提示。
- 保存失败：Toast 展示 `Something went wrong. Please try again.`。

### 5.4 缺失卡录入

缺失卡录入使用 §5.2 的通用编辑表单，勾选 `is_missing_card = true` 并填写完整的 `override_fields`（至少包含卡名、系列等核心字段）和 `image_url`。

**录入后行为**：前台 `GET /cards/{card_ref}` 返回时 `override_applied=true`，卡牌详情完全由覆盖层驱动，不经第三方查询。

---

## 附录：字段约定

| 字段类型 | 格式 |
|---|---|
| 时间戳展示 | 本地时间（管理后台按运营时区展示，存储为 UTC） |
| `admin_user.id` 软引用 | 后台操作记录（`updated_by`）软引用 `admin_user.id`（不同于 App `user.id`），Workers 层在写入时自动填充 |
| 分页返回包络 | 遵循 `api-spec.md §1.3` 统一响应格式 |
