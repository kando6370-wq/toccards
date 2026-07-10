# 原型业务与实际接口差距扫描

## 0. 结论说明

- 分析范围：全项目快速扫描，重点比较 Flutter / Admin 原型业务与 Workers 实际接口。
- 分析时间：2026-07-09。
- 前提假设：
  - “原型业务”指 Flutter 页面、Admin Web 页面、mock repository、demo 数据和产品文档中的 v1.0 业务流。
  - “实际接口”指 `apps/workers-api/src` 已挂载并可执行的 REST 路由、D1 schema、数据源适配层。
- 成功标准：能说明各业务模块是否已接真实接口、主要缺口在哪里、后续联调优先级如何排。

## 1. 总体判断

当前不是“接口没有做”，而是“接口和原型页面基本分开做完了，移动端主业务尚未集成接口”。

粗略差距：

| 维度 | 当前状态 | 差距判断 |
|---|---|---|
| Workers API | 鉴权、资产 CRUD、搜索/卡牌、偏好、后台接口大多已实现 | 接口覆盖度约 70% 到 80%，仍有若干 mock / 简化 / TBD |
| Flutter 主业务 | Home、Collection、Search、Card Detail、Feedback、Auth 均以 mock/local repository 为主 | 与真实 API 集成度约 10% 到 20% |
| Admin Web | 有真实 `fetch`，但带本地 demo 模式；页面模块与 Workers 后台接口部分对齐、部分偏运营原型 | 与真实 API 集成度约 50% 到 60% |
| 生产可上线性 | M8 全部未开始，OAuth、邮件、汇率、真机联调、生产配置仍待处理 | 距离生产闭环仍有明显差距 |

## 2. 模块差距

| 模块 | 原型/页面状态 | 实际接口状态 | 差距 |
|---|---|---|---|
| Auth 注册登录 | Flutter `LocalPlaceholderAuthRepository` 生成本地 token，本地模拟登录/注册/OAuth/忘记密码 | Workers 已有 `/auth/anonymous`、注册、登录、找回密码、OAuth callback、refresh、logout、me、delete、migrate-assets | UI 流程有，移动端未接真实鉴权；OAuth authorizer 也仍用 mock identity |
| Home | `MockHomeRepository` 返回本地 portfolio、chart、most valuable、trending | Workers 有 `/portfolio/folders`、`/portfolio/items`、`/cards/trending`、`/rates` 等原子接口 | 缺少 Flutter 聚合层；总资产、图表、most valuable 需由真实 items + prices 计算 |
| Collection | `MockCollectionRepository` 返回本地 portfolio/wishlist/folders | Workers 已有 folders/items/wishlist/preferences/collect CRUD | 页面未接 API；排序、筛选、分享目前主要是前端 mock 数据行为 |
| Search | `MockSearchRepository` 返回固定 games/cards/sets | Workers 有 `/cards/search`、`/sets/search`、`/cards/{card_ref}` | 页面未接搜索 API；games 列表没有独立真实端点，需从搜索结果或新增接口派生 |
| Card Detail | `MockCardDetailRepository` 返回固定详情、价格、sold listings、collection item | Workers 有 card detail、market prices、price series、sold listings、collect、portfolio item CRUD | 页面未接 API；详情页的收藏增删改仍停在本地状态/模拟数据层 |
| Feedback | `LocalFeedbackRepository` 只返回 `local-feedback-*` | API 文档要求 `POST /feedbacks`，但 Workers 当前未挂载前台 `/feedbacks`；后台可读写 `feedback_ticket` | 前台提交接口缺失，是明确业务缺口 |
| App Upgrade | Flutter 已通过 Dio 请求 `/app-config` | Workers 有公开 `/app-config`，后台有 `/admin/app-versions` 和 `/admin/app-config` | 这是移动端少数已接真实 API 的模块；仍依赖后台配置数据 |
| Scan | Flutter 为占位页，符合 v1.0 “真扫描延后” | Workers 后台有 `/admin/scans`，但使用 `SAMPLE_SCAN_RECORDS` | 前台占位合理；后台扫描记录是演示数据，不是生产扫描链路 |
| Admin | Admin Web 使用 `/api/v1/admin` 请求，开发模式支持 `demo_admin=1` | Workers 后台接口覆盖登录、用户、反馈、权限、版本、配置、trending pins、card overrides 等 | 基本能联调，但 Admin Web 菜单未覆盖 trending/card overrides，扫描是样例数据 |

## 3. 主要证据

| 结论 | 证据 |
|---|---|
| Workers API 已统一挂载在 `/api/v1` | `apps/workers-api/src/index.ts` |
| Auth 实际路由齐全 | `apps/workers-api/src/auth/anonymous.ts`、`account.ts`、`current.ts`、`register.ts`、`login.ts`、`forgot-password.ts`、`oauth.ts`、`session.ts` |
| 资产接口已实现 owner 隔离 CRUD | `apps/workers-api/src/portfolio/routes.ts` |
| 卡牌数据源接口已实现，但 trending/sold listings 仍部分为空 | `apps/workers-api/src/data-source/routes.ts`、`apps/workers-api/src/data-source/local-db-adapter.ts` |
| D1 schema 已覆盖账号、资产、反馈、运营配置、基础卡表 | `apps/workers-api/src/db/schema.ts` |
| Flutter 主业务仍为 mock/local | `apps/flutter-app/lib/features/*/*_repository.dart`、各 controller provider |
| 版本升级是 Flutter 侧少数真实 HTTP 接口 | `apps/flutter-app/lib/features/app_upgrade/app_upgrade_repository.dart` |
| Admin Web 有真实 fetch 和 demo fallback | `apps/admin-web/src/App.tsx` |
| 执行状态把 M1-M7 标为 completed，但 M8 联调/生产配置未开始 | `docs/superpowers/execution-status.md` |

## 4. 待确认问题

| 问题 | 影响 |
|---|---|
| 是否要优先做 Flutter 真实 API 集成，而不是继续补 UI 原型 | 影响下一轮任务切入点 |
| 前台 `POST /feedbacks` 是否要补 Workers 端点 | Profile 客服反馈目前无法真实落库 |
| Home Dashboard 是新增聚合接口，还是 Flutter 调多个原子接口后本地计算 | 影响性能、缓存和客户端复杂度 |
| games 列表是否需要独立端点 | Search 的 Game 筛选目前只有 mock 来源 |
| 汇率是否接受当前 mock，还是必须接第三方 | 影响货币切换是否可上线 |
| Admin 的扫描记录是否只是 v1.0 占位，还是后台必须接真实扫描流水 | 影响管理后台验收口径 |

## 5. 建议优先级

1. 先接 Flutter Auth 到真实 `/auth/*`，否则后续资产 API 没有可信 token。
2. 再接 Portfolio folders/items/wishlist/preferences，打通 Collection 和 Card Detail 的增删改。
3. 接 Search/Card Detail 的卡牌读取、价格、价格序列。
4. 补或确认 Home 聚合方案。
5. 补前台 `POST /feedbacks`。
6. 最后处理 M8：OAuth 凭证、邮件服务、卡牌基础数据导入、汇率、协议链接、真机联调和生产配置。

