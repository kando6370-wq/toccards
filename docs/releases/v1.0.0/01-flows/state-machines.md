# v1.0.0 状态模型

本文仅记录代码中持久化或明确分支处理的状态。

## 用户账号

```text
anonymous -> registered user
active user -> deleted
active user -> disabled（Admin super_admin）
```

- 匿名升级时迁移资产所有者，不把匿名数据暴露给其他 UID。
- `user.status` 默认 `active`；正式账号删除同步写为 `deleted` 并撤销会话，匿名账号删除会清除匿名资产、失效匿名账号并撤销会话。
- 被禁用用户不能继续按正常账号使用受保护接口。

## 会话

```text
issued -> refreshed -> revoked/expired
```

- 登录或匿名创建签发 Access/Refresh Token。
- Refresh Token 只能在有效、未撤销会话中换新。
- 登出撤销会话；令牌过期或校验失败进入未认证状态。

## 扫描记录

识别状态：

```text
processing -> success
processing -> no_match
processing -> failed
```

确认状态：

```text
pending -> confirmed
```

- `success` 表示存在可供 Review 的识别结果；`no_match` 与 `failed` 分开保存。
- 确认可记录最终卡牌、是否修改系统结果、是否加入收藏和愿望单。

## 反馈工单

```text
open（新提交） -> pending（Admin 展示） -> processed
                                      -> ignored
```

Admin 读取时把旧存量 `in_progress` 映射为 `pending`、`closed` 映射为 `processed`；更新后直接持久化 `pending`、`processed` 或 `ignored`。

## 管理员

```text
active <-> disabled
operator <-> super_admin
```

只有 `super_admin` 可通过权限接口创建管理员或修改角色/状态。Admin 会话在登录、刷新和退出之间独立于 App 用户会话。

## 收藏条目

收藏条目没有业务状态枚举，其生命周期由操作表达：创建 -> 编辑/移动/增减数量 -> 删除。数量始终不得小于 1；变更写入 `collection_item_event`，估值历史可据此重建指定日期的持仓状态。

证据：`apps/workers-api/src/db/schema.ts`、`auth/`、`scan/routes.ts`、`feedback/routes.ts`、`admin/routes.ts`、`portfolio/`。
