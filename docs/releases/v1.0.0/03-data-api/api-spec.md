# v1.0.0 API 契约概览

## 通用约定

- API 前缀：`/api/v1`；健康检查为 `GET /api/v1/health`。
- App 受保护接口使用 `Authorization: Bearer <access_token>`，令牌所有者为 `user` 或 `anonymous`。
- Admin 使用独立登录和 Admin Token，路径前缀为 `/api/v1/admin`。
- 成功响应通常为 `{ "success": true, "data": ... }`；错误响应使用稳定错误码和 HTTP 状态。
- 参数校验失败为 4xx；鉴权失败为 401/403；资源不存在为 404；重复或状态冲突为 409；上游 OCR 不可用为 502/503。

## 身份认证 `/auth`

| 方法与路径 | 用途 |
|---|---|
| `POST /anonymous` | 创建匿名账号和会话 |
| `POST /register/send-code` | 发送邮箱注册验证码 |
| `POST /register/verify-code`、`POST /register/verify` | 校验验证码并完成注册 |
| `POST /login` | 邮箱密码登录 |
| `POST /oauth/google/callback` | Google OAuth 登录/绑定 |
| `POST /oauth/apple/callback` | Apple 登录/绑定 |
| `POST /token/refresh` | 刷新会话令牌 |
| `POST /logout` | 撤销当前会话 |
| `GET /me` | 当前账号资料 |
| `POST /forgot-password/send-code`、`verify-code`、`reset` | 找回密码 |
| `DELETE /account` | 请求删除正式账号 |
| `POST /migrate-assets` | 将匿名资产迁移到正式账号 |

## 卡牌目录与价格

| 方法与路径 | 用途 |
|---|---|
| `GET /games` | 游戏列表 |
| `GET /sets/search` | 系列搜索；系列选择使用 `set_id` |
| `GET /cards/search` | 卡牌搜索与分页 |
| `GET /cards/trending` | 趋势卡牌 |
| `GET /cards/:card_ref` | 卡牌详情 |
| `GET /cards/:card_ref/image` | 卡牌图片重定向/代理 |
| `GET /cards/:card_ref/market-prices` | 各状态最新市场价 |
| `GET /cards/:card_ref/price-series` | 单一价格历史 |
| `POST /cards/:card_ref/price-series/batch` | 批量价格历史 |
| `GET /cards/:card_ref/sold-listings` | 成交记录 |
| `GET /rates` | 汇率快照 |

目录响应会合并启用的 `card_override`；价格端点使用 `no-store`，目录类查询可使用 Cache API/KV。

## 收藏、愿望单与偏好

| 路径组 | 操作 |
|---|---|
| `/portfolio/items` | 列表、新增、详情、编辑、移动、删除 |
| `/portfolio/folders` | 列表、新增、改名、排序、设默认、删除 |
| `/wishlist` | 列表、新增、删除 |
| `/cards/:card_ref/collect` | 从卡牌上下文快速收藏 |
| `/collection/dashboard` | 首页收藏汇总 |
| `/portfolio/valuation-history` | 组合估值历史 |
| `/preferences` | 读取和更新用户偏好 |

所有操作从令牌解析所有者，客户端不能指定他人的 `owner_id`。收藏数量必须大于等于 1；重复 SKU/文件夹等违反唯一约束时返回冲突。

## 扫描、反馈与公共配置

| 方法与路径 | 用途 |
|---|---|
| `POST /scan/recognize` | 上传图片和 RGB pHash，执行识别并创建扫描记录 |
| `POST /scan/:scan_id/confirm` | 确认候选并创建收藏条目 |
| `POST /feedback` | 创建用户反馈 |
| `GET /app-config` | 按平台读取版本、升级和链接配置 |
| `GET /legal/terms`、`privacy`、`support` | 法律与支持页面 |
| `GET /share/cards/:card_ref` | 卡牌 Web 分享页，不使用 `/api/v1` 前缀 |

扫描确认只允许选择该扫描保存的候选，要求目标文件夹属于当前所有者；成功入库后会删除同卡愿望单条目。

## Admin `/admin`

| 路径组 | 能力 |
|---|---|
| `/auth/login|refresh|logout` | 独立管理员会话 |
| `/analytics/installations` | 安装统计 |
| `/users` | 用户列表、详情和禁用 |
| `/feedbacks` | 反馈列表、详情和状态更新 |
| `/scans` | 扫描列表、详情和受保护图片 |
| `/permissions` | 管理员账号、角色和状态 |
| `/app-versions`、`/app-config` | 版本与应用配置 |
| `/trending-pins` | 趋势卡牌置顶 |
| `/card-overrides` | 卡牌字段/图片覆盖 |

`super_admin` 专属限制以服务端路由为准，详见 [`../04-admin/admin.md`](../04-admin/admin.md)。

证据：`apps/workers-api/src/index.ts` 及各 `routes.ts`。
