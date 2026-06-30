# tcg-card 文档中心

> **定位**：tcg-card v1.0 iOS 应用全量设计文档导航，供开发者 / AI 据此独立开始 v1.0 iOS 开发。
> **日期**：2026-06-30
> **原始资料**：`docs/tcg_cord_docs/`（9 份原始 PRD，已全量并入下列文档，冲突按 `docs/superpowers/specs/2026-06-30-tcg-card-preparation-design.md §7` 统一）

---

## 一句话简介

tcg-card 是一款 iOS 集卡管理应用，支持 TCG 单卡、体育卡、Sealed Product 等多类收藏对象的 Portfolio 管理、市场价格追踪与搜索，采用 Cloudflare Workers + D1 + Flutter 技术栈。

---

## 推荐阅读顺序

1. [`00-product/overview.md`](00-product/overview.md) — 产品定位与 v1.0 范围
2. [`00-product/glossary.md`](00-product/glossary.md) — 术语表（阅读其他文档前先建立共同语言）
3. [`02-architecture/architecture.md`](02-architecture/architecture.md) — 系统架构总览
4. [`02-architecture/tech-stack.md`](02-architecture/tech-stack.md) — 技术选型
5. [`02-architecture/monorepo.md`](02-architecture/monorepo.md) — Monorepo 结构
6. [`03-data-api/data-model.md`](03-data-api/data-model.md) — 数据模型（D1 Schema）
7. [`03-data-api/api-spec.md`](03-data-api/api-spec.md) — REST API 规范（含管理员鉴权）
8. [`03-data-api/third-party.md`](03-data-api/third-party.md) — 第三方适配层
9. [`00-product/modules/global-rules.md`](00-product/modules/global-rules.md) — 全局跨切面规则（文案/错误码/金额/图片）
10. [`00-product/modules/auth.md`](00-product/modules/auth.md) — 注册登录模块
11. [`00-product/modules/profile.md`](00-product/modules/profile.md) — 个人中心模块
12. [`00-product/modules/home.md`](00-product/modules/home.md) — 首页模块
13. [`00-product/modules/collection.md`](00-product/modules/collection.md) — Collection 模块
14. [`00-product/modules/search.md`](00-product/modules/search.md) — 搜索模块
15. [`00-product/modules/card-detail.md`](00-product/modules/card-detail.md) — 卡牌详情模块
16. [`00-product/modules/scan.md`](00-product/modules/scan.md) — 扫描模块（v1.0 占位）
17. [`01-flows/flows.md`](01-flows/flows.md) — 关键业务流程
18. [`01-flows/state-machines.md`](01-flows/state-machines.md) — 状态机
19. [`04-admin/admin.md`](04-admin/admin.md) — 后台管理系统
20. [`05-plan/dev-plan.md`](05-plan/dev-plan.md) — 开发计划与里程碑

---

## 完整文档目录树

```
docs/tcg-card/
├── README.md                              ← 本文件（导航入口）
│
├── 00-product/
│   ├── overview.md                        产品总览、v1.0 范围、底部导航
│   ├── glossary.md                        术语表
│   └── modules/
│       ├── global-rules.md                跨切面规则（文案/错误码/金额/图片/网络）
│       ├── auth.md                        注册登录（邮箱、Google、Apple、匿名）
│       ├── profile.md                     个人中心（账号、设置、货币、Feedback）
│       ├── home.md                        首页（Trending、资产总览、Portfolio）
│       ├── collection.md                  Collection（列表、筛选、文件夹管理）
│       ├── search.md                      搜索（Cards/Sets/Sealed/其他）
│       ├── card-detail.md                 卡牌详情（价格、Collection Item、编辑）
│       └── scan.md                        扫描（v1.0 占位页）
│
├── 01-flows/
│   ├── flows.md                           关键业务流程图（注册/添加卡牌/Wishlist 等）
│   └── state-machines.md                  状态机（Collection Item 状态流转）
│
├── 02-architecture/
│   ├── architecture.md                    系统架构（Workers/D1/Flutter/第三方）
│   ├── tech-stack.md                      技术选型（Cloudflare/Flutter/Dart/Resend）
│   └── monorepo.md                        Monorepo 结构（目录规范/包管理/类型共享）
│
├── 03-data-api/
│   ├── data-model.md                      D1 数据库 Schema（全表定义+关联）
│   ├── api-spec.md                        REST API 规范（鉴权/资产/代理/后台）
│   └── third-party.md                     第三方适配层接口（DataSourceAdapter）
│
├── 04-admin/
│   └── admin.md                           后台管理系统（运营配置/工单/用户/卡牌覆盖）
│
└── 05-plan/
    └── dev-plan.md                        开发计划（M1–M8 里程碑/依赖/验收标准/TBD）
```

---

## 术语表入口

核心术语定义见 [`00-product/glossary.md`](00-product/glossary.md)，涵盖：

- **Collection Item**：用户在 Portfolio 中持有的一条收藏记录（对应 D1 `collection_item` 表）。
- **Portfolio**：用户的收藏文件夹，可多个并存，每个 Collection Item 归属一个文件夹。
- **card_ref**：第三方卡牌唯一标识符，格式由接入厂商确定（⚠️ TBD）。
- **Sealed Product**：未拆封产品（Booster Box、ETB 等），区别于 TCG 单卡与体育卡。
- **Graded / Raw**：已评级卡（有 Grader + Grade）/ 未评级卡（Condition）。
- **Trending Today**：当天涨幅排行，数据来源第三方聚合 API，经 Workers 缓存。

完整术语列表见 glossary.md，跨切面规则（如金额格式、图片占位）见 [`global-rules.md`](00-product/modules/global-rules.md)。

---

## ⚠️ TBD 总清单

以下为各文档显式标注的待决策项，开发启动前须逐项确认。

### 外部依赖 / 凭证（阻塞生产上线）

| 编号 | 待定项 | 影响文档 / 端点 | 决策方 |
|---|---|---|---|
| TBD-1 | 第三方卡牌数据源厂商（TCGplayer / eBay / PriceCharting 等）及 API Key | `third-party.md`、`api-spec.md §4.1–§4.7`、`data-model.md`（card_ref 格式） | 产品/商务 |
| TBD-2 | 汇率接口提供方 | `api-spec.md §4.8`、`architecture.md §3.2`、`tech-stack.md §3` | 产品/研发 |
| TBD-3 | 邮件服务（Resend / SES）账号与 API Key | `api-spec.md §2.2`、`tech-stack.md §2.6` | 研发/运营 |
| TBD-4a | Apple OAuth 凭证（Service ID / Team ID / Key ID） | `api-spec.md §2.9`、`auth.md §五` | 研发/苹果开发者账号 |
| TBD-4b | Google OAuth 凭证（Client ID / Secret） | `api-spec.md §2.8`、`auth.md §四` | 研发 |
| TBD-5 | `terms_url` / `privacy_url` / `app_store_url` 实际值 | `api-spec.md §5.3.1`、`data-model.md §4.3`、`profile.md §十二` | 产品/法务 |
| TBD-6 | Admin Refresh Token 存储方案（复用 `session` 表 `owner_type='admin'` 还是独立表） | `api-spec.md §5.0.1–5.0.3` | 研发 |

### 产品决策

| 编号 | 待定项 | 影响文档 | 决策方 |
|---|---|---|---|
| TBD-7 | Scan 占位页最终文案（"扫描功能即将上线"） | `overview.md §5`、`scan.md §一` | 产品 |
| TBD-8 | Restore（恢复购买）按钮是否展示（App Store 审核要求待确认） | `overview.md §4.3`、`profile.md §十五` | 产品/苹果 |
| TBD-9 | Profile 退出登录前是否加确认弹窗 | `profile.md §十六` | 产品 |
| TBD-10 | Terms / Privacy 跳转方式（系统浏览器 vs App 内 WebView） | `profile.md §十二` | 产品 |
| TBD-11 | Wishlist 与 Portfolio 互斥裁决（已 Collected 对象点 Heart 行为未明确） | `flows.md` | 产品 |
| TBD-12 | Admin 配置项编辑 UI（内联编辑 vs 独立编辑页） | `admin.md §七.2` | 产品/设计 |
| TBD-13 | Admin 工单管理后续回复/评论功能（v1.0 不含，后续版本待定） | `admin.md §六` | 产品 |

### 技术实现阶段确认

| 编号 | 待定项 | 影响文档 | 决策方 |
|---|---|---|---|
| TBD-14 | condition / finish 枚举合法值（取决于第三方厂商） | `api-spec.md §3.2.2`、`third-party.md §4` | 研发（接入厂商后确认） |
| TBD-15 | 各代理接口最终 TTL（取决于厂商限速策略） | `api-spec.md §4.1–§4.7`、`third-party.md §5` | 研发（接入厂商后确认） |
| TBD-16 | Workers KV / Cache API TTL 最终值 | `architecture.md §4.3` | 研发 |
| TBD-17 | TS→Dart 类型共享工具选型（JSON Schema / OpenAPI 代码生成） | `monorepo.md §六` | 研发 |
| TBD-18 | 账号删除后资产数据隐私合规留存/清除策略 | `api-spec.md §2.12`、`profile.md §十三` | 研发/法务 |
| TBD-19 | Sets 搜索接口是否由厂商原生支持（影响 Sets Tab 实现方式） | `api-spec.md §4.3`、`search.md §十二` | 研发（接入厂商后确认） |

---

## 溯源说明

本目录文档由以下 9 份原始 PRD 整理产出，原文保留于 `docs/tcg_cord_docs/`：

1. `注册登录.md` → `auth.md`
2. `个人中心.md` → `profile.md`
3. `首页.md` → `home.md`
4. `Collection.md` → `collection.md`
5. `搜索.md` → `search.md`
6. `卡牌详情.md` → `card-detail.md`
7. `扫描.md` → `scan.md`
8. `全局用其他补充事项.md` → `global-rules.md`、`overview.md`
9. `后台管理.md` → `admin.md`

已知 PRD 内冲突按 `docs/superpowers/specs/2026-06-30-tcg-card-preparation-design.md §7` 裁决规则统一，裁决记录在各模块文档内标注。
