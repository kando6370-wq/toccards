# tcg-card v1.0 分阶段开发计划

> **定位**：tcg-card v1.0 的里程碑划分、任务拆分、依赖关系、验收标准与 TBD 阻塞项汇总。纯计划文档，不含代码与测试用例。
> **日期**：2026-06-30
> **来源**：
> - 产品总览 [`../00-product/overview.md`](../00-product/overview.md)
> - 技术架构 [`../02-architecture/architecture.md`](../02-architecture/architecture.md)
> - Monorepo 划分 [`../02-architecture/monorepo.md`](../02-architecture/monorepo.md)
> - 技术选型 [`../02-architecture/tech-stack.md`](../02-architecture/tech-stack.md)
> - 数据模型 [`../03-data-api/data-model.md`](../03-data-api/data-model.md)
> - API 规范 [`../03-data-api/api-spec.md`](../03-data-api/api-spec.md)（TBD 汇总见 §6）
> - 卡牌数据源适配层 [`../03-data-api/third-party.md`](../03-data-api/third-party.md)
> - 模块 PRD [`../00-product/modules/`](../00-product/modules/)（auth / home / collection / search / card-detail / scan / profile / global-rules）
> - 流程与状态机 [`../01-flows/`](../01-flows/)
> - 管理后台 PRD [`../04-admin/admin.md`](../04-admin/admin.md)

---

## 目录

1. [里程碑总览](#1-里程碑总览)
2. [M0 工程基建](#2-m0-工程基建)
3. [M1 鉴权与账号](#3-m1-鉴权与账号)
4. [M2 数据代理层](#4-m2-数据代理层)
5. [M3 核心资产 CRUD](#5-m3-核心资产-crud)
6. [M4 三大页面](#6-m4-三大页面)
7. [M5 卡牌详情](#7-m5-卡牌详情)
8. [M6 Profile / 客服 / 启动引导](#8-m6-profile--客服--启动引导)
9. [M7 管理后台](#9-m7-管理后台)
10. [M8 iOS 联调 / 上线准备](#10-m8-ios-联调--上线准备)
11. [关键路径与并行项](#11-关键路径与并行项)
12. [TBD 阻塞项汇总](#12-tbd-阻塞项汇总)

---

## 1. 里程碑总览

| 里程碑 | 主题 | 依赖 | 交付物 |
|---|---|---|---|
| M0 | 工程基建 | — | Monorepo 骨架 + Workers + D1 + CI |
| M1 | 鉴权与账号 | M0 | Auth 全流程（Email / Google / Apple / 匿名）可运行 |
| M2 | 数据代理层 | M0 | D1 卡牌基础数据适配层 + KV/Cache 缓存 + 降级 |
| M3 | 核心资产 CRUD | M1 | portfolio_folder / collection_item / wishlist_item / user_preference 全量接口 |
| M4 | 三大页面 | M1 M2 M3 | Home / Collection / Search App 页面可演示 |
| M5 | 卡牌详情 | M2 M3 | CardDetail 两态 + Price Tab + Collection Item 编辑 |
| M6 | Profile / 客服 / 引导 | M1 M3 | Profile 页面 + 客服工单提交 + Onboarding 引导 |
| M7 | 管理后台 | M1 M2 M3 | Admin Web 全功能可用 |
| M8 | iOS 联调 / 上线准备 | 全部里程碑 | 审核材料齐备，可提交 App Store |

> **平台约束**：v1.0 仅交付 iOS；Android 架构预留，不在关键路径（见 [`overview.md §2`](../00-product/overview.md)）。
>
> **延后项**：Scan 真扫描识别、Home Performance Tab 均不在 v1.0 关键路径（见 [`overview.md §4.2`](../00-product/overview.md)）。

---

## 2. M0 工程基建

**目标**：搭建可供所有后续里程碑依赖的工程底座。

### 主要任务

| # | 任务 | 说明 |
|---|---|---|
| M0-1 | 初始化 Monorepo 顶层结构 | `pnpm-workspace.yaml` / `turbo.json` / `melos.yaml` / 顶层 `package.json`，参见 [`monorepo.md §1`](../02-architecture/monorepo.md) |
| M0-2 | 初始化 `apps/workers-api` | Hono + Drizzle ORM + Cloudflare Workers 配置（`wrangler.toml`）；绑定 D1、KV |
| M0-3 | 初始化 `apps/flutter-app` | Flutter 项目脚手架；Riverpod / go_router / Dio / freezed 依赖引入 |
| M0-4 | 初始化 `apps/admin-web` | React + Vite + TypeScript + Ant Design + TanStack Query |
| M0-5 | 初始化 `packages/` 通用包 | `auth-core` / `api-client` / `ui-kit` / `workers-common` 目录与基础依赖，参见 [`monorepo.md §2`](../02-architecture/monorepo.md) |
| M0-6 | D1 Schema 初始化迁移 | 按 [`data-model.md`](../03-data-api/data-model.md) 全量建表（DDL + Drizzle 迁移文件） |
| M0-7 | CI 流水线 | GitLab CI（`.gitlab-ci.yml`）双 Job：TS 侧（`pnpm turbo build/type-check` + 依赖方向 lint）+ Dart 侧（`melos run analyze/test`），参见 [`tech-stack.md §2.5`](../02-architecture/tech-stack.md) |
| M0-8 | 依赖方向 Lint | 引入 `depcheck` 或自定义脚本，验证 `apps/ → packages/` 单向依赖，参见 [`monorepo.md §4`](../02-architecture/monorepo.md) |

### 验收标准

- `pnpm turbo build` 全量通过，无类型错误。
- `melos run build` / `flutter analyze` 通过。
- CI 双 Job 均绿（`.gitlab-ci.yml`：ts + dart）。
- Workers 本地 `wrangler dev` 可启动，`/api/v1/` 返回 404（路由未注册）而非崩溃。
- D1 迁移文件可幂等执行：`wrangler d1 migrations apply` 成功。

### 依赖与阻塞

- 无外部阻塞；可立即启动。

---

## 3. M1 鉴权与账号

**目标**：实现完整 Auth 流程（匿名账号、Email 注册/登录、Google OAuth、Apple OAuth、找回密码、账号升级、删除账号），配合 Flutter App 完成端到端联调。

**依赖里程碑**：M0

### 主要任务

| # | 任务 | 说明 |
|---|---|---|
| M1-1 | `packages/auth-core` 实现 | JWT 签发/校验、bcrypt/argon2 密码哈希、OAuth 回调通用流程，参见 [`monorepo.md §2.1`](../02-architecture/monorepo.md) |
| M1-2 | 匿名账号接口 | `POST /auth/anonymous`：创建/复用匿名账号 + 初始化 `portfolio_folder`(Main) + `user_preference`（`api-spec.md §2.1`） |
| M1-3 | Email 注册流程 | `POST /auth/register/send-code` + `POST /auth/register/verify`（含匿名资产迁移）（`api-spec.md §2.2–2.3`） |
| M1-4 | Email 登录 | `POST /auth/login`（`api-spec.md §2.4`） |
| M1-5 | 找回密码流程 | send-code / verify-code / reset 三步骤（`api-spec.md §2.5–2.7`） |
| M1-6 | Google OAuth 回调 | `POST /auth/oauth/google/callback`（`api-spec.md §2.8`） |
| M1-7 | Apple OAuth 回调 | `POST /auth/oauth/apple/callback`（`api-spec.md §2.9`） |
| M1-8 | Token 刷新 / 登出 | `POST /auth/token/refresh` + `POST /auth/logout`（`api-spec.md §2.10–2.11`） |
| M1-9 | 删除账号 / 资产迁移 | `DELETE /auth/account` + `POST /auth/migrate-assets`（`api-spec.md §2.12–2.13`） |
| M1-10 | 获取当前账号 | `GET /auth/me`（`api-spec.md §2.14`） |
| M1-11 | Flutter Auth UI | 注册/登录/找回密码页面；go_router 路由守卫（未登录重定向）；参见 [`modules/auth.md`](../00-product/modules/auth.md) |
| M1-12 | 匿名 → 正式升级 Flutter 侧 | 注册/OAuth 成功后触发资产迁移；登录时不迁移匿名资产（[`modules/auth.md`](../00-product/modules/auth.md) + [`data-model.md §3.2`](../03-data-api/data-model.md)） |

### 验收标准

- Email 注册 → 验证码验收 → 登录 → Token 刷新 → 登出全链路可演示。
- 匿名账号首次启动自动创建，匿名资产在注册后成功迁移到正式账号。
- 找回密码完整三步骤可演示（发码 → 验证 → 重置）。
- Google / Apple OAuth 回调在测试凭证下可走通（或 Mock 通过）。
- `DELETE /auth/account` 执行后账号被软删除，后续 JWT 失效。
- go_router 守卫：游客访问 Home 仍可进入（匿名态），访问需正式账号端点时弹出注册引导。

### 依赖与阻塞

- ⚠️ **TBD M1-A**：邮件服务（Resend / SES）账号与 API Key——阻塞 M1-3、M1-5 真实发送验证码。接口结构已定，开发阶段可 Mock 邮件发送，但生产前须完成选型（见 [`api-spec.md §6 #2`](../03-data-api/api-spec.md)、[`tech-stack.md §2.6`](../02-architecture/tech-stack.md)）。
- ⚠️ **TBD M1-B**：Apple / Google OAuth 开发者账号与凭证（Client ID / Secret / Service ID / Team ID / Key ID）——阻塞 M1-6、M1-7 生产可用（见 [`api-spec.md §6 #1`](../03-data-api/api-spec.md)）。开发阶段可用测试环境凭证或 Mock。

---

## 4. M2 数据代理层

**目标**：实现 Workers 数据代理层，对接当前项目 D1 中的卡牌基础数据表（`cards_all` / `games` / `sets` / `tcgplayer_skus`），提供搜索、详情、价格、Trending 置顶、成交记录降级等接口，并实现 KV/Cache 缓存与降级逻辑。基础数据由外部采集程序写入，Workers 只读查询。

**依赖里程碑**：M0

### 主要任务

| # | 任务 | 说明 |
|---|---|---|
| M2-1 | `DataSourceAdapter` 抽象层 | 可插拔适配器接口：`searchCards` / `getCard` / `getPriceSeries` / `getMarketPrices` / `getTrending` / `getSoldListings`；参见 [`third-party.md`](../03-data-api/third-party.md) |
| M2-2 | D1 卡牌基础数据适配实现 | 整合 `cards_basic_information_ddl.md` 的 `cards_all` / `games` / `sets` / `tcgplayer_skus` 到当前 D1，并实现只读 `DataSourceAdapter` |
| M2-3 | Workers KV 缓存层 | searchCards（TTL 1h）、trending（TTL 15min）；参见 [`tech-stack.md §2.4`](../02-architecture/tech-stack.md) |
| M2-4 | Cache API 缓存层 | market-prices / price-series / sold-listings（TTL 30min）；参见 [`tech-stack.md §2.4`](../02-architecture/tech-stack.md) |
| M2-5 | 降级兜底逻辑 | D1 基础表读取和缓存均失败时返回空数组或 404；客户端展示 "No content available"（见 [`api-spec.md §4`](../03-data-api/api-spec.md) 各端点降级说明） |
| M2-6 | card_override 覆盖层合并 | `GET /cards/{card_ref}` 和 `GET /cards/trending` 返回时先查 D1 `card_override` 覆盖，参见 [`api-spec.md §4.3`](../03-data-api/api-spec.md)、[`api-spec.md §4.6`](../03-data-api/api-spec.md) |
| M2-7 | 汇率接口代理 | `GET /rates`；参见 [`api-spec.md §4.8`](../03-data-api/api-spec.md) |
| M2-8 | 接口端点注册 | Hono 路由：`/cards/search`、`/sets/search`、`/cards/{card_ref}`、`/cards/{card_ref}/market-prices`、`/cards/{card_ref}/price-series`、`/cards/trending`、`/cards/{card_ref}/sold-listings`、`/rates` |

### 验收标准

- 使用 D1 卡牌基础数据适配器时，`GET /cards/search?q=charizard` 从 `cards_all` 返回结构化 JSON，分页正确。
- `GET /cards/{card_ref}/market-prices` 和 `price-series` 从 `tcgplayer_skus.price_history` 解析价格历史。
- 缓存命中时不再重复查询基础表（可通过日志或测试用例验证）。
- 基础表读取失败时接口仍按约定降级，无 500 崩溃。
- `card_override` 有记录的 card_ref 返回的数据中 `override_applied: true`，字段已合并。
- `trending_pin` 有 active 记录时，`GET /cards/trending` 按 `rank` 置顶并回查 `cards_all`。
- 汇率接口有响应（即使 Mock），结构符合 `api-spec.md §4.8`。

### 依赖与阻塞

- ⚠️ **TBD M2-A**：卡牌基础表导入任务与刷新频率——影响目录完整性、价格历史新鲜度和 Trending 非置顶数据是否可用。开发阶段以 D1 表结构和测试数据推进，生产前需确认采集程序写入节奏。
- ⚠️ **TBD M2-B**：汇率接口提供方——阻塞 M2-7 真实接入（见 [`api-spec.md §6 #3`](../03-data-api/api-spec.md)、[`tech-stack.md §3`](../02-architecture/tech-stack.md)）。
- ⚠️ **TBD M2-C**：各接口最终 TTL（取决于基础表刷新频率）——上线前须基于采集程序刷新策略确认（见 [`api-spec.md §6 #9`](../03-data-api/api-spec.md)）。

---

## 5. M3 核心资产 CRUD

**目标**：实现用户资产相关的全量 CRUD 接口（Portfolio 文件夹、持有记录、心愿单、用户偏好），支持匿名账号与正式账号。

**依赖里程碑**：M1（鉴权 JWT 中间件）

### 主要任务

| # | 任务 | 说明 |
|---|---|---|
| M3-1 | Portfolio 文件夹接口 | GET/POST/PATCH/DELETE + set-default + reorder（`api-spec.md §3.1`）；包含默认文件夹保护逻辑、CASCADE 删除 |
| M3-2 | Collection Item 接口 | GET/POST/PATCH/DELETE/move（`api-spec.md §3.2`）；grader/condition/grade 联动校验；Collect 时自动移出 Wishlist |
| M3-3 | Wishlist 接口 | GET/POST/DELETE（`api-spec.md §3.3`）；唯一约束保护 |
| M3-4 | 用户偏好接口 | GET/PATCH（`api-spec.md §3.4`）；currency 枚举校验（待汇率厂商确认） |
| M3-5 | owner 多态隔离中间件 | Workers 从 JWT 提取 `owner_type` + `owner_id`，所有资产查询自动过滤，参见 [`data-model.md §2`](../03-data-api/data-model.md) |
| M3-6 | Collect 快捷端点 | `POST /cards/{card_ref}/collect`（`api-spec.md §4.9`）；含自动移出 Wishlist 副作用 |

### 验收标准

- 创建匿名账号后，立即可操作文件夹和 Collection Item（`owner_type=anonymous`）。
- 注册升级后，原匿名资产的 `owner_type` 变为 `user`，查询结果一致。
- 默认文件夹（`is_default=1`）不可被 DELETE 接口删除（返回 `FORBIDDEN`）。
- 同一 `card_ref` Collect 后，对应 Wishlist 记录自动消失。
- `sort_order` 接口批量更新后，返回顺序反映新排序。

### 依赖与阻塞

- `card_ref` 统一使用 `cards_all.product_id`，影响 `collection_item.card_ref`、`wishlist_item.card_ref` 的实际值；接口结构不变。

---

## 6. M4 三大页面

**目标**：完成 Home / Collection / Search 三个核心 Flutter 页面，端到端可演示主要用户旅程。

**依赖里程碑**：M1（Auth）、M2（数据代理）、M3（资产 CRUD）

### 主要任务

| # | 任务 | 说明 |
|---|---|---|
| M4-1 | Home 页面 | Portfolio 概览、总资产金额/图表、Most Valuable、Trending Today、文件夹管理、货币切换；参见 [`modules/home.md`](../00-product/modules/home.md) |
| M4-2 | Collection 页面 | Portfolio Tab（按文件夹）+ Wishlist Tab；排序/筛选/搜索/分享；参见 [`modules/collection.md`](../00-product/modules/collection.md) |
| M4-3 | Search 页面 | Cards / Sets 双 Tab；快捷 Collect / Wishlist 操作；各卡类字段；参见 [`modules/search.md`](../00-product/modules/search.md) |
| M4-4 | 涨跌算法实现 | 参见 [`modules/global-rules.md`](../00-product/modules/global-rules.md)（涨跌幅算法规则） |
| M4-5 | 货币换算展示 | 调用 `GET /rates`；Home / Collection / CardDetail 统一货币展示；参见 [`modules/global-rules.md`](../00-product/modules/global-rules.md) |
| M4-6 | 加载/失败/空状态 | 全局规则实现：局部/整页加载态、失败态 + Refresh、空状态；参见 [`modules/global-rules.md`](../00-product/modules/global-rules.md) |
| M4-7 | Toast 全局组件 | 参见 [`modules/global-rules.md`](../00-product/modules/global-rules.md) §四 |
| M4-8 | Scan Tab 占位页 | 保留底部导航 Scan Tab；点进展示占位引导页，引导跳转 Search；**真扫描不实现**；参见 [`modules/scan.md`](../00-product/modules/scan.md)、[`overview.md §5`](../00-product/overview.md) |

### 验收标准

- Home 页面能展示资产总值（含货币切换）、Most Valuable 卡片列表、Trending Today 列表。
- Collection Portfolio Tab 按文件夹展示持有卡，支持排序/筛选；Wishlist Tab 可展示心愿单。
- Search 在 Cards Tab 输入关键词后返回结果，可点击 Collect / Wishlist 操作。
- Scan Tab 点击后展示占位引导页，不崩溃，不跳转扫描功能。
- 网络失败时各页面展示降级空状态，不白屏。
- 货币切换生效后，Home / Collection 总值刷新。

### 依赖与阻塞

- 依赖 M2 数据代理层可用（Mock 数据即可联调 UI）。
- M4-5 货币换算展示依赖 TBD M2-B（汇率提供方），开发阶段可 Mock 汇率。
- ⚠️ **TBD M4-A**：Scan 占位页文案（"扫描功能即将上线"，待最终文案确认）。见 [`overview.md §5`](../00-product/overview.md)。

---

## 7. M5 卡牌详情

**目标**：完成 CardDetail 页面两态（未加入 / 已加入）、Price Tab（市场价 + 价格序列图 + 成交记录）、Collection Item 编辑操作。

**依赖里程碑**：M2（数据代理）、M3（资产 CRUD）

### 主要任务

| # | 任务 | 说明 |
|---|---|---|
| M5-1 | CardDetail 未加入态 | 展示卡牌基本信息、价格概览、Collect / Wishlist 快捷操作；参见 [`modules/card-detail.md`](../00-product/modules/card-detail.md) |
| M5-2 | CardDetail 已加入态 | 展示已持有 Collection Item 列表、价格概览；参见 [`modules/card-detail.md`](../00-product/modules/card-detail.md) |
| M5-3 | Price Tab 实现 | 市场价格列表（按 grader/grade/condition 分维度）、价格序列图（7/30/90/180/365d 时间范围切换）、成交记录列表；参见 [`api-spec.md §4.4–4.7`](../03-data-api/api-spec.md) |
| M5-4 | Collection Item 增删改 | 在 CardDetail 页内新增/编辑/删除 Collection Item；grader / condition / grade 联动表单；参见 [`modules/card-detail.md`](../00-product/modules/card-detail.md) |
| M5-5 | 价格降级展示 | Price Tab 无数据时展示 `--`；图表无数据时展示占位文案；参见 [`api-spec.md §4.5`](../03-data-api/api-spec.md) |

> **延后**：Home Performance Tab（PRD 标注为 1.0.1 需求），接口预留但不实现页面，见 [`overview.md §4.2`](../00-product/overview.md)。

### 验收标准

- 从 Search 结果点入 CardDetail，未加入态展示正确，可快捷 Collect。
- Collect 后切换为已加入态，展示 Collection Item 列表。
- Price Tab 可切换时间范围，图表随之刷新。
- 市场价格按 grader/grade/condition 分维度展示，无数据项显示 `--`。
- 成交记录列表可展示平台、价格、日期；无数据时展示空状态。
- 新增 Collection Item 后 Home 总资产刷新（客户端需触发 Home 数据重载）。

### 依赖与阻塞

- 依赖 M2（市场价/价格序列/成交记录接口）、M3（Collection Item CRUD）。

---

## 8. M6 Profile / 客服 / 启动引导

**目标**：完成 Profile 模块（游客态/登录态）、客服反馈工单提交、首次启动引导页。

**依赖里程碑**：M1（Auth）、M3（资产 CRUD）

### 主要任务

| # | 任务 | 说明 |
|---|---|---|
| M6-1 | Profile 游客态 | 展示匿名账号信息、注册引导入口；参见 [`modules/profile.md`](../00-product/modules/profile.md) |
| M6-2 | Profile 登录态 | Account 详情（email / display_name）、评分 App、分享 App、删除账号；参见 [`modules/profile.md`](../00-product/modules/profile.md) |
| M6-3 | 客服反馈提交 | `POST /feedbacks`（`api-spec.md §5.2.4`）；types / functions 多选；message 限 1000 字符 |
| M6-4 | 启动引导页 | 首次启动展示引导图（从 `app_config.onboarding_images` 读取）；参见 [`modules/global-rules.md`](../00-product/modules/global-rules.md) |
| M6-5 | 删除账号流程 | 二次确认 → `DELETE /auth/account` → 退出至游客态；参见 [`modules/profile.md`](../00-product/modules/profile.md) |
| M6-6 | 订阅相关内容删除/隐藏 | Upgrade to Pro / Subscribe / PRO 标识等全部删除或隐藏；删除客服反馈 Function 字段中的 Subscription 枚举选项（区别于订阅入口删除）；参见 [`overview.md §4.3`](../00-product/overview.md) |

### 验收标准

- 游客态 Profile 显示匿名状态，登录后切换为登录态。
- 客服反馈表单提交成功后展示 Toast：`Feedback submitted. Thank you.`；message 超 1000 字时提交按钮禁用。
- 首次启动展示引导图（可用本地占位图测试），`app_config` 中配置图片 URL 后即可生效。
- 删除账号确认后账号软删除，App 退回游客态。
- 页面上无订阅相关入口、按钮或标识。

### 依赖与阻塞

- ⚠️ **TBD M6-A**：`terms_url` / `privacy_url` / `app_store_url` 实际值（影响 Profile 中协议链接与分享 App 功能）；M8 前须填入 `app_config`（见 [`api-spec.md §6 #7`](../03-data-api/api-spec.md)）。
- ⚠️ **TBD M6-B**：`Restore 恢复购买` 按钮——默认隐藏；若 App Store 审核要求保留则在 M8 前确认处理（见 [`overview.md §4.3`](../00-product/overview.md)）。

---

## 9. M7 管理后台

**目标**：完成 `apps/admin-web` 的全功能交付：用户管理、反馈工单、运营配置（App Config + Trending Pin）、卡牌数据运维（Card Override）；含 `admin_user` 独立鉴权。

**依赖里程碑**：M1（D1 数据库 + Workers 基础）、M3（资产表数据可查）、M2（card_override 覆盖层接口）

### 主要任务

| # | 任务 | 说明 |
|---|---|---|
| M7-1 | Admin 鉴权接口 | `POST /admin/auth/login`（基于 `admin_user` 表，独立 Admin JWT）；参见 [`admin.md §1.1`](../04-admin/admin.md)、[`api-spec.md §5`](../03-data-api/api-spec.md) |
| M7-2 | Admin Token 中间件 | Workers 后台接口鉴权中间件，校验 Admin JWT + 角色（`super_admin` / `operator`）；参见 [`data-model.md §5.1`](../03-data-api/data-model.md) |
| M7-3 | 用户管理模块 | 用户列表（正式 + 匿名）、详情、禁用账号（super_admin）；参见 [`admin.md §2`](../04-admin/admin.md)、[`api-spec.md §5.1`](../03-data-api/api-spec.md) |
| M7-4 | 反馈工单模块 | 工单列表、详情、状态流转（open / in_progress / closed）；参见 [`admin.md §3`](../04-admin/admin.md)、[`api-spec.md §5.2`](../03-data-api/api-spec.md) |
| M7-5 | 运营配置模块 | App Config 管理（onboarding_images / upgrade_prompt / announcement / 协议链接）；Trending Pin CRUD；参见 [`admin.md §4`](../04-admin/admin.md)、[`api-spec.md §5.3`](../03-data-api/api-spec.md) |
| M7-6 | 卡牌数据运维模块 | Card Override 列表/新增/编辑/删除；缺失卡录入；补图快捷操作；参见 [`admin.md §5`](../04-admin/admin.md)、[`api-spec.md §5.4`](../03-data-api/api-spec.md) |
| M7-7 | D1 管理员初始化 | 数据库初始化脚本创建首个 `super_admin` 账号（v1.0 无后台管理员管理界面）；参见 [`data-model.md §5.1`](../03-data-api/data-model.md) |

### 验收标准

- Admin 登录页可使用初始化的 `super_admin` 账号登录。
- 用户管理页面展示正式账号与匿名账号，支持按 email / device_id 搜索。
- `super_admin` 可禁用账号（弹出确认），`operator` 角色无禁用按钮。
- 工单列表支持状态筛选，可流转工单状态。
- Trending Pin 可创建/启停/删除；创建后前台 `GET /cards/trending` 返回置顶卡牌优先。
- Card Override 可新增覆盖（字段覆盖 + 补图），保存后前台卡牌详情 `override_applied: true`。

### 依赖与阻塞

- 无外部 TBD 阻塞（Admin 功能不依赖第三方凭证）；M7 可与 M4/M5/M6 并行推进。

---

## 10. M8 iOS 联调 / 上线准备

**目标**：解决全部 TBD 阻塞项，完成 iOS 真机联调，准备 App Store 审核材料，确认上线检查清单。

**依赖里程碑**：所有里程碑完成

### 主要任务

| # | 任务 | 说明 |
|---|---|---|
| M8-1 | OAuth 凭证填入 | Apple Service ID / Team ID / Key ID + Google OAuth Client ID / Secret 真实值配置到 Workers 环境变量（解除 TBD M1-B）；参见 [`api-spec.md §6 #1`](../03-data-api/api-spec.md) |
| M8-2 | 邮件服务上线 | 选定 Resend 或 SES，配置 API Key，端到端验证验证码邮件发送（解除 TBD M1-A）；参见 [`tech-stack.md §2.6`](../02-architecture/tech-stack.md) |
| M8-3 | 卡牌基础数据导入联调 | 确认外部采集程序已将 `cards_all` / `games` / `sets` / `tcgplayer_skus` 写入当前 D1（解除 TBD M2-A）；验证搜索/价格/Trending 置顶真实数据返回 |
| M8-4 | 汇率接口接入 | 接入选定汇率提供方（解除 TBD M2-B）；验证货币换算展示正确 |
| M8-5 | 协议链接配置 | 将 `terms_url` / `privacy_url` / `app_store_url` 真实值写入 `app_config`（解除 TBD M6-A）；参见 [`api-spec.md §6 #7`](../03-data-api/api-spec.md) |
| M8-6 | Restore 按钮审核决策 | 确认 App Store 审核是否要求保留 Restore 恢复购买按钮（解除 TBD M6-B）；按审核结果处理（见 [`overview.md §4.3`](../00-product/overview.md)） |
| M8-7 | iOS 真机联调 | Apple Login / Google OAuth 真机验证；推送通知（若有）；iOS 原生分享；深链测试 |
| M8-8 | TTL / 刷新频率确认 | 基于采集程序刷新策略确认各代理接口最终 TTL（解除 TBD M2-C）；调整 KV/Cache TTL 配置 |
| M8-9 | 性能与安全 review | Workers CPU 时间、D1 查询、KV 读写量估算；JWT 安全性审查 |
| M8-10 | App Store 审核材料 | 截图、App 描述（英文）、隐私政策 URL、年龄分级、审核说明 |
| M8-11 | 生产环境配置 | Workers Production 环境、D1 Production、KV Namespace 切换；域名绑定 |

### 验收标准

- iOS 真机 Apple Login 完整走通（授权 → 账号创建/登录 → JWT 获取）。
- 验证码邮件在真实邮箱收到，10 分钟内可用。
- 搜索真实卡牌数据返回、市场价格真实数据展示。
- 货币切换后资产总值以选定货币正确换算展示。
- Profile 中服务条款 / 隐私政策链接可正常打开。
- App Store 审核材料齐备，提交无被拒风险项（基于自检）。

### 依赖与阻塞

- M8 集中处理全部 TBD 阻塞项，所有 M1–M7 里程碑须在 M8 前完成功能开发。

---

## 11. 关键路径与并行项

### 11.1 关键路径（串行依赖链）

```
M0（工程基建）
  └─→ M1（鉴权）
        └─→ M3（资产 CRUD）
              └─→ M4（三大页面）
                    └─→ M8（上线准备）
```

M0 → M1 → M3 → M4 → M8 是最长依赖链，任何一环延误将直接推迟最终交付。

### 11.2 可并行推进项

| 并行组 | 条件 |
|---|---|
| M2（数据代理层）与 M1（鉴权） | 均仅依赖 M0，可同步启动 |
| M5（卡牌详情）与 M4（三大页面） | 均依赖 M2 + M3；M4 和 M5 的 Flutter UI 可拆人并行 |
| M6（Profile / 客服 / 引导）与 M4/M5 | M6 依赖 M1 + M3，与 M4/M5 无强依赖，可并行 |
| M7（管理后台）与 M4/M5/M6 | M7 依赖 M1 + M3 + M2（card_override），可与 App 端 UI 并行 |

### 11.3 可延后项（不阻塞 v1.0 主线）

| 项目 | 说明 |
|---|---|
| Scan 真扫描识别 | v1.0 仅占位页；真扫描为后续版本；架构接口预留（见 [`overview.md §4.2`](../00-product/overview.md)、[`modules/scan.md`](../00-product/modules/scan.md)） |
| Home Performance Tab | PRD 标注为 1.0.1 需求；v1.0 不交付页面，接口预留（见 [`overview.md §4.2`](../00-product/overview.md)） |
| Android 支持 | 架构预留，不在 v1.0 交付范围（见 [`overview.md §2`](../00-product/overview.md)） |

---

## 12. TBD 阻塞项汇总

| TBD 编号 | 待定项 | 影响里程碑 | 说明与来源 |
|---|---|---|---|
| TBD M1-A | 邮件服务提供商（Resend / SES）账号与 API Key | M1、M8 | 开发可 Mock；M8 前须选定并接入；见 [`tech-stack.md §2.6`](../02-architecture/tech-stack.md)、[`api-spec.md §6 #2`](../03-data-api/api-spec.md) |
| TBD M1-B | Apple / Google OAuth 凭证 | M1、M8 | 开发可用测试凭证；M8 真机联调前须配置生产凭证；见 [`api-spec.md §6 #1`](../03-data-api/api-spec.md) |
| TBD M2-A | 卡牌基础表导入任务与刷新频率 | M2、M8 | 外部采集程序需写入 `cards_all` / `games` / `sets` / `tcgplayer_skus`；影响目录完整性、价格历史新鲜度和 Trending 非置顶数据；见 [`third-party.md`](../03-data-api/third-party.md)、[`api-spec.md §6 #4`](../03-data-api/api-spec.md) |
| TBD M2-B | 汇率接口提供方 | M2、M4、M8 | 开发可 Mock 汇率数据；M8 前须接入；见 [`api-spec.md §6 #3`](../03-data-api/api-spec.md)、[`tech-stack.md §3`](../02-architecture/tech-stack.md) |
| TBD M2-C | 各代理接口最终 TTL | M2、M8 | 取决于基础表刷新频率；M8 前基于采集程序策略确认；见 [`api-spec.md §6 #9`](../03-data-api/api-spec.md) |
| TBD M4-A | Scan 占位页最终文案 | M4 | 默认"扫描功能即将上线"，待确认；见 [`overview.md §5`](../00-product/overview.md) |
| TBD M6-A | `terms_url` / `privacy_url` / `app_store_url` 实际值 | M6、M8 | M8 前须写入 `app_config`；见 [`api-spec.md §6 #7`](../03-data-api/api-spec.md) |
| TBD M6-B | Restore 恢复购买按钮 App Store 审核要求 | M6、M8 | 默认隐藏；审核需要则恢复；见 [`overview.md §4.3`](../00-product/overview.md) |
