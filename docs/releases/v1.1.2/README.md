# v1.1.2 开发归档

归档日期：2026-10-26（Asia/Shanghai）。当前开发入口已切换到 [v1.1.3](../v1.1.3/README.md)。本目录原位保留历史产品、实现和交付证据；后续新增功能、变更和验证记录不得继续写入 v1.1.2。只有明确授权的事实错误修正可以修改本目录，并须从 v1.1.3 留下引用。

## 产品定位

- [Card AI 产品定位与内容边界](00-product/card-ai-product-positioning.md)：先确认用户任务、实体卡牌范围、交易市场数据口径和已验证能力，再决定功能或官网内容。

App 向后兼容规则只维护以下两份；涉及 App API、共享业务数据或客户端协议的开发前，必须阅读 AI 执行版及受影响业务契约。仅落实规则时执行文档检查，具体范围见两份正文。

| 读者 | 文档 | 内容 |
|---|---|---|
| 产品、开发与评审人员 | [阅读版：App 向后兼容开发规则](05-delivery/app-backward-compatibility-plan.md) | 目标、基础版本、V1／V2 边界、示例和按需开发流程。 |
| AI 开发与修改 | [AI 执行版：App 向后兼容开发规则](03-data-api/app-backward-compatibility-ai-guide.md) | 执行规则、代码入口、测试运行方式、覆盖缺口和必要证据摘要。 |

2026-10-13 按用户确认，将重复的测试说明和独立验证文档合入上述两份，不继续维护四份兼容文档。本 README 只提供导航，兼容原则统一在两份正文中维护。历史 CI 配置过程与重复日志从当前正文移除，详细过程可在 Git 历史追溯。

现有源码回归只覆盖部分场景，正式旧包／真机与完整兼容验收仍未完成；文档整理不等于业务整改、V2 实现或发布验收通过。开发与文档修改完成后，只运行受影响范围验证，实际结果集中补入 AI 执行版。

2026-10-21 本地修复收藏编辑重复项错误：`PATCH /api/v1/portfolio/items/:item_id` 在编辑结果与同一收藏夹内另一条完整收藏身份重复时，复用既有 `409 DUPLICATE_COLLECTION_ITEM`，并将 PostgreSQL 唯一约束并发冲突转换为同一响应；请求字段、成功响应和数据库结构不变。该修复后续已随 `main@557166b` 的生产 Worker 发布；本版本记录未独立使用真实账号重放该冲突，原本地验证边界见[收藏编辑重复项修复](05-delivery/VERIFICATION.md#collection-item-edit-duplicate)。

## App 1.0.6 订阅配置（服务端与 Admin 页面）

2026-10-26 生产收尾：App Store 已上架 `1.0.6`，生产 iOS 版本门禁为建议／最低 `1.0.6` 且强制更新；动态注册表现包含 Weekly／Yearly／Lifetime／Weekly Trial／Monthly 五项商品，其中 `CardAi.monthly` 使用 `card_monthly`。Page／Modal 仍未启用并返回 `data:null`。用户确认相关购买、权益、通知、收入及 Restore 已在实机测试且目前无问题；Agent 未独立重放原始交易或平台记录。此前迁移前手工备份已由用户确认删除，未独立回读，详见[生产收尾记录](05-delivery/VERIFICATION.md#prod-app-1-0-6-monthly-admission-20261026)。

2026-10-21 本地增量：动态准入中标记为试用商品的 SKU，其首笔 Apple 通知确认正金额续费生成 `trial_conversion`（试用转付费），后续续费仍为 `renewal`；PostgreSQL `0015_trial_conversion_status.sql` 回填同口径历史订单，不新增 schema。该检查点当时尚未执行远程 migration 或部署，见[服务端合同](03-data-api/subscription-display-config.md#trial-conversion-order-status)、[后台口径](04-admin/admin.md#trial-conversion-order-status)和[本地验证](05-delivery/VERIFICATION.md#trial-conversion-order-status)。

2026-10-16 本地增量：新增超级管理员逐商品审批，dev/prod 与 Bundle 隔离；运行期白名单与 Flutter 长期商品集合可接收已批准 SKU，无需逐商品改代码。复用 PostgreSQL 现有表，无新 migration。该检查点当时尚未发布此增量，具体行为见[动态准入合同](03-data-api/subscription-display-config.md)、[后台操作](04-admin/admin.md)和[客户端注册](01-flows/subscription-display.md)，验证见[记录](05-delivery/VERIFICATION.md#subscription-dynamic-admission)。

2026-10-19 本地增量：订阅商品卡片可独立配置隐藏价格，关联试用 SKU 的价格方式在展示名称上方编辑；新旧客户端的可见边界及本地测试结果见[价格展示验证](05-delivery/VERIFICATION.md#subscription-price-visibility)。该检查点当时尚未部署或做本轮真机复测。

## Chrome 扩展

- [官网扩展介绍页](../../../apps/marketing-web/content/landing/chrome-extension.mjs)与 [Chrome Web Store 文案草稿](../../../apps/marketing-web/content/chrome-web-store-listing.md)：说明扩展与移动 App 的能力边界，包含 Pokémon 关键词、扩展官网入口和 UTM 参数。

本次产品输入为 PRD 1.14；App 目标版本 1.0.6 与工程文档版本 v1.1.2 分别管理。需求、商品映射和实施草案保留在同一份输入文档中，避免维护重复规则。

| 材料 | 内容与边界 |
|---|---|
| [订阅配置 PRD 1.14](00-product/admin-subscription-config-prd.md) | 两类页面配置、商品与试用关系、纯文本按钮、真实计费说明、iOS 范围及验收规则；只读需求输入，实施状态以服务端合同和验证记录为准 |
| [商品映射与待核验数据](00-product/admin-subscription-config-prd.md#product-mapping) | 源码已有商品、历史测试组与真实接入缺项分别标明；不能将示例 ID 作为真实商品 |
| [最小实施方案](00-product/admin-subscription-config-prd.md#implementation-plan) | V1 增量接口、PostgreSQL 数据对象、原子启用、幂等及开发顺序；是设计草案，不是当前架构事实 |
| [离线 HTML 原型](../../../prototypes/admin-subscription-config-standalone.html) | 本地演示配置编辑与校验；商品、金额与保存均为离线演示，不包含 Apple 或后台真实接入 |

服务端第一阶段源码与接口合同见 [订阅展示配置与商品准入](03-data-api/subscription-display-config.md)，包括目录、配置 API、PostgreSQL 迁移及幂等；Admin 页面见 [后台文档](04-admin/admin.md)，Flutter 消费见 [客户端流程](01-flows/subscription-display.md)。2026-10-23 已发布生产服务端与双 Admin，2026-10-26 App 1.0.6 已上架且 Weekly Trial／Monthly 均完成生产动态准入；用户确认实机交易链路目前无问题，Agent 独立证据范围见[生产收尾记录](05-delivery/VERIFICATION.md#prod-app-1-0-6-monthly-admission-20261026)。Page／Modal 仍未启用，App 使用本地兜底；完整旧包／真机兼容矩阵仍按兼容文档保留边界。

以下为初次联调历史记录，后续 dev 发布及五项商品准入见[2026-10-15 补证](05-delivery/VERIFICATION.md#dev-subscription-product-onboarding)，本次动态准入增量仍未发布。

Linux dev 初次[服务器只读补验](05-delivery/VERIFICATION.md#subscription-config-dev-server)记录 0014 未执行、7 项新配置缺失；[扫描基线定位与候选整合](05-delivery/VERIFICATION.md#subscription-config-baseline-resolution)进一步确认运行包是 pHash／OCR，当前订阅候选是 512 维向量，两者各有正常响应的配套服务。候选已移植 dev 图片预览修复；用户已确认本次采用 512 维向量方案，pHash／OCR 是另一位同事的独立测试，见[方案确认](05-delivery/VERIFICATION.md#subscription-config-vector-decision)。本任务尚未切换服务器；原 APPLE_IAP 的 401 证据保留，新提供的[目录团队 Key 已通过真实读取](05-delivery/VERIFICATION.md#subscription-config-apple-catalog-live)，确认测试 App 6790245922／组 22251901 和指定范围内 6 个商品。用户调整后，[cardx.week → weekly.trial 同等级关联已只读复验通过](05-delivery/VERIFICATION.md#subscription-config-trial-level-recheck)。[dev 目录六项配置已落地并加载到运行容器](05-delivery/VERIFICATION.md#subscription-config-dev-catalog-env)，持久配置的真实目录读取通过；没有切换业务 release 或扫描方案，0014、商品展示准入、正式兜底与真机联调仍待完成。

原型的已有本地验证及未验边界见 [实际验证记录](05-delivery/VERIFICATION.md#subscription-config-prototype)。原始输入归档后不随实现回写；实现后的接口和行为按本版本业务分类维护，App 兼容实际补证仍合入现有 AI 执行版。

## 其他业务与交付证据

- [Admin 订单金额与退款汇总](04-admin/admin.md)：保留本版本后台功能契约与双 prod 入口的验收边界。
- [App 订阅接入](../../../apps/flutter-app/lib/features/subscription/subscription_controller.dart)与[共享包说明](../../../dart-packages/subscription-core/README.md)：当前 App 只启用 iOS StoreKit；本机 verified Premium 与服务端当前 session grant 分别验证，不把共享包的 Google Play 能力写成 App 已接入。
- [营销内容源](../../../apps/marketing-web/content)与[内容生成器](../../../apps/marketing-web/scripts/generate-content.mjs)：当前生成 21 个落地页、6 篇博客及博客索引，并维护首页链接、`llms.txt` 和正式 Sitemap。正式 Sitemap 使用显式维护的真实 `lastmod` 日期，不使用构建日期。最小诊断 Sitemap 独立生成，只含首页、Pokemon 扫描页、卡牌估价页，不加入 robots 或正式 Sitemap；源码和静态文件存在不等于部署或 Google 收录通过。
- [其他业务验证记录](05-delivery/VERIFICATION.md)：保留营销站 Sitemap 隔离实验、Admin 订单汇总等实际结果；App 兼容证据仍集中在 AI 执行版。

## 版本边界

- [v1.1.3](../v1.1.3/README.md)是当前开发入口；[v1.1.1](../v1.1.1/README.md)是本版本的直接增量基线，[v1.1.0](../v1.1.0/README.md)与 [v1.0.0](../v1.0.0/README.md)按历史归档保留，冻结产品输入不回写。
- 文档版本 v1.1.2、App 营销／构建版本、API 主版本与环境运行提交分别管理。
- 本版本兼容相关待验项与历史结果见 AI 执行版；未变化的其他业务按需引用原版本文档。
- 根 AGENTS.md 保留操作与安全边界；Git push、部署、远程迁移和生产写入遵循相应授权，不因生成文档而授权。

## 维护方式

- 本目录归档后不再承接新开发记录；规则变化、测试结果和新证据写入 v1.1.3，并引用本版本基线。
- v1.1.2 的阅读版与 AI 执行版保持归档时内容；只有事实错误修正才同步修改两者，不新增第三份兼容说明。
- 必要结果摘要区分本地源码、正式制品／真机、dev 与 prod；记录日期、提交、范围和未验项，不把历史结果冒充当前复验。
- 不向正式 docs 写入执行日志、任务快照、截图或原始响应；使用既有忽略输出目录、受控 artifact 或提交／Issue 追踪。
