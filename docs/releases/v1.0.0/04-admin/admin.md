# v1.0.0 管理后台

Admin 是由 `apps/admin-web` 构建的 React SPA，静态产物随 Workers assets 部署。它使用独立的管理员账号和 `/api/v1/admin` API，不复用 App 用户会话。

## 登录与会话

- 登录字段为已授权邮箱和密码；成功后取得 Admin Access/Refresh Token。
- 刷新和退出由 `/admin/auth/refresh`、`/admin/auth/logout` 处理。
- `admin_user.status` 必须为 `active` 才能正常使用后台。
- 登录页“设置密码”表单当前只校验两次密码一致并提示联系超级管理员，没有提交密码的后端 API。

## 当前 UI 菜单

| 分组 | 页面 | 能力 |
|---|---|---|
| 数据统计 | 安装统计 | 按时间、平台、环境等查看安装数据 |
| 用户管理 | 用户列表 | 筛选正式/匿名用户并查看详情 |
| 用户管理 | 用户反馈 | 查看反馈、详情并更新处理状态 |
| 用户管理 | 权限管理 | 创建管理员、调整角色与状态 |
| 卡牌管理 | 扫描记录管理 | 筛选识别记录、查看图片、系统结果与用户确认 |
| App 版本管理 | 版本管理 | 维护 iOS/Google 的版本与升级行为 |

`operator` 和 `super_admin` 当前看到相同菜单；操作授权由 Workers 后端再次校验。

## 角色权限

| 操作 | `operator` | `super_admin` |
|---|---:|---:|
| 查看安装、用户、反馈、扫描、版本和配置 | 是 | 是 |
| 更新反馈状态、应用版本和一般配置 | 是 | 是 |
| 创建/更新 Trending Pin 与 Card Override | 是 | 是 |
| 禁用 App 正式用户 | 否 | 是 |
| 创建管理员、修改管理员角色/状态 | 否 | 是 |
| 删除 Trending Pin 或 Card Override | 否 | 是 |

权限依据是 `apps/workers-api/src/admin/routes.ts` 的显式 `super_admin` 判断；仅隐藏前端按钮不能替代后端授权。

## 用户与反馈

- 用户列表同时覆盖正式用户和匿名账号，详情路径包含 `accountType` 与 UID。
- 禁用只适用于正式用户路径 `/users/user/:id/disable`，且仅 `super_admin` 可执行。
- 反馈支持列表、详情和状态更新；处理人取当前 Admin 身份。

## 扫描审计

后台可按平台、识别状态、确认状态、是否修改结果等条件筛选。详情展示 R2 原图、设备信息、系统候选、置信度、最终卡牌和是否加入收藏。图片端点要求有效 Admin Token，并返回 `private, no-store`。

## 版本与运营配置

- 当前 UI 暴露 iOS/Google 版本管理，数据存入 `app_config`。
- Workers 还实现 `/app-config`、`/trending-pins` 和 `/card-overrides` 管理 API。
- 当前 UI 菜单没有 Trending Pin、Card Override 或通用 App Config 页面；这些 API 能力不应被描述为可从现有页面操作。
- Card Override 可覆盖名称/图片等返回字段；图片上传写入覆盖记录。Trending Pin 控制趋势列表固定项和排序。

## 部署边界

Admin 没有独立生产部署。`pnpm --filter @kando/workers-api deploy:dev|prod` 会先构建相应模式的 Admin，再由 Worker assets 一起发布。验证时应分别检查 `/api/v1/health` 和根 SPA 页面。

证据：`apps/admin-web/src/App.tsx`、`apps/admin-web/src/api.ts`、`apps/workers-api/src/admin/routes.ts`、`apps/workers-api/wrangler.toml`。
