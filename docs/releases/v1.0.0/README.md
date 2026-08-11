# v1.0.0 已发布基线

本文档描述 Git tag `v1.0.0` 所对应的业务与工程基线。结论来自当前应用代码、D1 schema、迁移和部署配置；`00-product` 保存原始 PRD，不作为实现事实来源。

## 业务总览

Kando 是面向交易卡牌收藏者的移动应用。用户可以匿名开始使用或注册账号，通过目录搜索和图片识别找到卡牌，查看价格，加入收藏或愿望单，并在首页查看持仓价值。内部运营人员通过管理后台处理用户、反馈、扫描记录、权限和应用版本。

业务闭环：创建匿名身份或登录 -> 搜索/扫描卡牌 -> 查看卡牌和市场价格 -> 加入收藏/愿望单 -> 维护数量、卡况、评级和文件夹 -> 查看组合估值与历史 -> 账号升级时迁移匿名资产。

## 角色与数据范围

| 身份 | 主要能力 | 数据范围 |
|---|---|---|
| 匿名用户 | 搜索、扫描、收藏、愿望单、偏好 | 仅 `owner_type=anonymous` 且 `owner_id` 为自身 UID 的数据 |
| 注册用户 | 匿名能力、邮箱/Google/Apple 登录、账号删除 | 仅 `owner_type=user` 且 `owner_id` 为自身 UID 的数据 |
| `operator` | Admin 登录、查看用户/扫描、处理反馈、维护版本与部分配置 | 后台运营数据；高风险操作受后端限制 |
| `super_admin` | `operator` 能力及用户禁用、管理员权限维护、删除运营覆盖数据 | 后台全部受保护操作 |

Flutter 与 Workers 都使用用户身份，但最终访问控制在 Workers 中执行。Admin 使用独立的 `admin_user`、会话令牌和路由鉴权。

## 模块地图

| 模块 | 当前实现 |
|---|---|
| 身份认证 | 匿名账号、邮箱注册/登录/找回密码、Google/Apple OAuth、令牌刷新/退出、匿名资产迁移 |
| 卡牌目录 | 游戏、系列、卡牌搜索、详情、图片、趋势卡牌、价格序列、市场价格和成交记录 |
| 扫描识别 | 相机/相册取图、客户端 pHash、Workers 调用 OCR 服务、候选 Review、用户确认并加入收藏 |
| 收藏管理 | 收藏条目、文件夹、默认文件夹、排序、数量/卡况/评级/语言、估值和历史 |
| 用户服务 | 偏好、应用配置、升级提示、法律页面、反馈、账号删除 |
| 管理后台 | 安装统计、用户、反馈、扫描记录、管理员权限、应用版本；Workers 另提供运营配置接口 |

## 核心实体与规则

- 卡牌目录以 `cards_all.product_id` 作为 `card_ref`；系列选择使用唯一 `set_id`。
- 用户资产统一由 `owner_type + owner_id` 隔离，服务端查询必须同时匹配两列。
- 收藏数量必须大于等于 1；同一所有者下愿望单卡牌唯一，文件夹名称唯一。
- 持仓价值为与卡况/评级/语言等条件匹配的最新市场价乘以数量，服务端按两位小数输出；无匹配价格时该项价值为空或不计入汇总。
- 匿名账号升级后，资产所有者从匿名 UID 迁移到正式用户 UID。
- 扫描图片存入 R2；识别结果与用户确认分别保存，确认后创建收藏条目并移除同卡愿望单。

## 上下游依赖

Flutter App -> Workers API -> D1/KV/R2；Workers 还连接 Google/Apple OAuth、ZeptoMail、OCR 识别服务和汇率服务。Flutter 直接集成 Firebase 与 Mixpanel。Admin 静态产物由同一 Workers 部署通过 assets 托管。

## 术语

| 术语 | 含义 |
|---|---|
| `card_ref` | 卡牌业务引用，当前对应 `cards_all.product_id` |
| `set_id` | 系列唯一标识；`set_code` 只用于展示/兼容，不作为唯一选择键 |
| Raw | 未评级卡牌，价格匹配使用品相等字段 |
| Graded | 经 PSA、BGS、CGC 等机构评级的卡牌，价格匹配使用机构和分数 |
| Portfolio | 用户收藏资产及其文件夹、估值和历史 |
| Wishlist | 用户关注但尚未纳入收藏的卡牌 |
| Scan Review | 识别后由用户核对候选卡牌并确认的步骤 |

## 文档导航

- 原始 PRD：[`00-product/`](00-product/)
- 业务流程：[`01-flows/flows.md`](01-flows/flows.md)
- 状态模型：[`01-flows/state-machines.md`](01-flows/state-machines.md)
- 架构：[`02-architecture/architecture.md`](02-architecture/architecture.md)
- Monorepo：[`02-architecture/monorepo.md`](02-architecture/monorepo.md)
- 技术栈：[`02-architecture/tech-stack.md`](02-architecture/tech-stack.md)
- API：[`03-data-api/api-spec.md`](03-data-api/api-spec.md)
- 数据模型：[`03-data-api/data-model.md`](03-data-api/data-model.md)
- 外部依赖：[`03-data-api/third-party.md`](03-data-api/third-party.md)
- 扫描服务：[`03-data-api/scanHTTP接口对接说明.md`](03-data-api/scanHTTP接口对接说明.md)
- 管理后台：[`04-admin/admin.md`](04-admin/admin.md)

## 代码证据索引

| 范围 | 主要证据 |
|---|---|
| API 入口与部署 | `apps/workers-api/src/index.ts`、`apps/workers-api/wrangler.toml` |
| 身份与所有者隔离 | `apps/workers-api/src/auth/`、`apps/workers-api/src/owner-auth.ts` |
| 收藏与估值 | `apps/workers-api/src/portfolio/` |
| 搜索与价格 | `apps/workers-api/src/data-source/` |
| 扫描 | `apps/flutter-app/lib/features/scan/`、`apps/workers-api/src/scan/routes.ts` |
| Admin | `apps/admin-web/src/App.tsx`、`apps/workers-api/src/admin/routes.ts` |
| 数据结构 | `apps/workers-api/src/db/schema.ts`、`apps/workers-api/src/db/migrations/` |
