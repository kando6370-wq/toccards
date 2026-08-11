# v1.0.0 D1 数据模型

当前 Drizzle schema 定义 22 张表，数据库迁移范围为 `0000` 至 `0024`。

## 卡牌目录与价格

| 表 | 用途 | 关键标识 |
|---|---|---|
| `cards_all` | 卡牌/商品基础资料 | `product_id`，对外作为 `card_ref` |
| `games` | 游戏目录 | `game_id` |
| `sets` | 系列目录 | 唯一 `set_id`，另有展示用 `set_code` |
| `tcg_price` | SKU、卡况、语言、版本和价格历史 | 自然键唯一索引，关联 `product_id` |

这些表由外部数据流程维护，Workers 以读取为主。价格历史字段保存 JSON 序列，服务端解析后输出数值和日期。

## 账号与会话

| 表 | 用途 |
|---|---|
| `user` | 正式用户、账号状态与删除流程字段 |
| `anonymous_account` | 匿名账号 |
| `account_uid` | UID 分配/占用记录 |
| `app_installation` | 安装标识、平台、环境与绑定账号 |
| `auth_identity` | 邮箱、Google、Apple 等身份映射 |
| `session` | App Refresh Token 会话，含所有者与撤销/过期时间 |
| `verification_code` | 注册和找回密码验证码 |

正式与匿名账号共享业务访问模式，但存储在不同账号表中。`auth_identity` 允许一个正式用户关联多个登录方式。

## 用户资产

| 表 | 用途 | 核心约束 |
|---|---|---|
| `portfolio_folder` | 收藏文件夹 | 同一所有者名称唯一 |
| `collection_item` | 当前收藏持仓 | 数量 `>= 1`，同文件夹/卡牌/语言/工艺唯一 |
| `collection_item_event` | 收藏变更事件 | 保留用于历史估值的持仓快照 |
| `wishlist_item` | 愿望单 | 同一所有者、卡牌唯一 |
| `scan_record` | 图片、识别候选、系统结果和用户确认 | 所有者索引、识别/确认状态 |
| `user_preference` | 货币等偏好 | 每个所有者一行 |

以上表使用 `owner_type + owner_id`：`owner_type` 为 `user` 或 `anonymous`。SQLite 不建立跨两张账号表的多态外键，引用完整性和访问隔离由 Workers 强制执行。

## Admin 与运营

| 表 | 用途 |
|---|---|
| `admin_user` | 管理员账号、密码摘要、角色与状态 |
| `card_override` | 卡牌名称/图片等运营覆盖 |
| `trending_pin` | 趋势卡牌固定排序 |
| `app_config` | 版本、升级提示、商店和法律链接配置 |
| `feedback_ticket` | 用户反馈及处理状态；新建默认 `open`，Admin 有效状态为 `pending/processed/ignored` |

`admin_user.role` 为 `super_admin` 或 `operator`，状态为 `active` 或 `disabled`。运营覆盖不修改外部导入的基础卡牌行。

反馈读取兼容旧存量状态：`open`、`in_progress` 映射为 `pending`，`closed` 映射为 `processed`；Admin 更新后保存新状态值。

## 关键关系与规则

- `collection_item.folder_id -> portfolio_folder.id`，且服务端同时验证所有者一致。
- 用户资产、扫描和会话均按所有者建立查询索引。
- `scan_record` 保存 R2 object key、原始上游响应、可审计候选、系统结果和用户结果。
- 收藏写入同时写 `collection_item_event`；删除也留下事件，以支持按时间回放持仓。
- 时间统一存 ISO 8601 UTC 文本；布尔存 INTEGER 0/1；业务主键主要使用 ULID 文本。

证据：`apps/workers-api/src/db/schema.ts`、`apps/workers-api/src/db/migrations/`。
