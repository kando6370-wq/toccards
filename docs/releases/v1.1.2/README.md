# v1.1.2 开发文档

App 向后兼容规则只维护以下两份；涉及 App API、共享业务数据或客户端协议的开发前，必须阅读 AI 执行版及受影响业务契约。仅落实规则时执行文档检查，具体范围见两份正文。

| 读者 | 文档 | 内容 |
|---|---|---|
| 产品、开发与评审人员 | [阅读版：App 向后兼容开发规则](05-delivery/app-backward-compatibility-plan.md) | 目标、基础版本、V1／V2 边界、示例和按需开发流程。 |
| AI 开发与修改 | [AI 执行版：App 向后兼容开发规则](03-data-api/app-backward-compatibility-ai-guide.md) | 执行规则、代码入口、测试运行方式、覆盖缺口和必要证据摘要。 |

2026-10-13 按用户确认，将重复的测试说明和独立验证文档合入上述两份，不继续维护四份兼容文档。本 README 只提供导航，兼容原则统一在两份正文中维护。历史 CI 配置过程与重复日志从当前正文移除，详细过程可在 Git 历史追溯。

现有源码回归只覆盖部分场景，正式旧包／真机与完整兼容验收仍未完成；文档整理不等于业务整改、V2 实现或发布验收通过。开发与文档修改完成后，只运行受影响范围验证，实际结果集中补入 AI 执行版。

## App 1.0.6 订阅配置（服务端与 Admin 页面）

本次产品输入为 PRD 1.14；App 目标版本 1.0.6 与工程文档版本 v1.1.2 分别管理。需求、商品映射和实施草案保留在同一份输入文档中，避免维护重复规则。

| 材料 | 内容与边界 |
|---|---|
| [订阅配置 PRD 1.14](00-product/admin-subscription-config-prd.md) | 两类页面配置、商品与试用关系、纯文本按钮、真实计费说明、iOS 范围及验收规则；只读需求输入，实施状态以服务端合同和验证记录为准 |
| [商品映射与待核验数据](00-product/admin-subscription-config-prd.md#product-mapping) | 源码已有商品、历史测试组与真实接入缺项分别标明；不能将示例 ID 作为真实商品 |
| [最小实施方案](00-product/admin-subscription-config-prd.md#implementation-plan) | V1 增量接口、PostgreSQL 数据对象、原子启用、幂等及开发顺序；是设计草案，不是当前架构事实 |
| [离线 HTML 原型](../../../prototypes/admin-subscription-config-standalone.html) | 本地演示配置编辑与校验；商品、金额与保存均为离线演示，不包含 Apple 或后台真实接入 |

服务端第一阶段源码与接口合同见 [订阅展示配置与商品准入](03-data-api/subscription-display-config.md)，包括目录、配置 API、PostgreSQL 迁移及幂等；Admin 页面已接入第一阶段接口，见 [后台文档](04-admin/admin.md)；Flutter 消费已有本地源码，见 [客户端流程](01-flows/subscription-display.md)，`850e339` 的目标 iOS CI 无签名 production Release 编译已通过，独立兜底定稿、真实商品、签名制品与真机仍待验；尚未部署。服务端验证见 [验证记录](05-delivery/VERIFICATION.md#subscription-config-server)，编译证据见 [iOS 原生编译补验](05-delivery/VERIFICATION.md#subscription-config-ios-compile)。

原型的已有本地验证及未验边界见 [实际验证记录](05-delivery/VERIFICATION.md#subscription-config-prototype)。原始输入归档后不随实现回写；实现后的接口和行为按本版本业务分类维护，App 兼容实际补证仍合入现有 AI 执行版。

## 其他业务与交付证据

- [Admin 订单金额与退款汇总](04-admin/admin.md)：保留本版本后台功能契约与双 prod 入口的验收边界。
- [App 订阅接入](../../../apps/flutter-app/lib/features/subscription/subscription_controller.dart)与[共享包说明](../../../dart-packages/subscription-core/README.md)：当前 App 只启用 iOS StoreKit；本机 verified Premium 与服务端当前 session grant 分别验证，不把共享包的 Google Play 能力写成 App 已接入。
- [营销内容源](../../../apps/marketing-web/content)与[内容生成器](../../../apps/marketing-web/scripts/generate-content.mjs)：当前生成 18 个落地页、3 篇博客及博客索引，并维护首页链接、`llms.txt` 和正式 Sitemap。最小诊断 Sitemap 独立生成，只含首页、Pokemon 扫描页、卡牌估价页，不加入 robots 或正式 Sitemap；源码和静态文件存在不等于部署或 Google 收录通过。
- [其他业务验证记录](05-delivery/VERIFICATION.md)：保留营销站 Sitemap 隔离实验、Admin 订单汇总等实际结果；App 兼容证据仍集中在 AI 执行版。

## 版本边界

- [v1.1.1](../v1.1.1/README.md)是直接增量基线；[v1.1.0](../v1.1.0/README.md)与 [v1.0.0](../v1.0.0/README.md)按历史归档保留，冻结产品输入不回写。
- 文档版本 v1.1.2、App 营销／构建版本、API 主版本与环境运行提交分别管理。
- 本版本兼容相关待验项与历史结果见 AI 执行版；未变化的其他业务按需引用原版本文档。
- 根 AGENTS.md 保留操作与安全边界；Git push、部署、远程迁移和生产写入遵循相应授权，不因生成文档而授权。

## 维护方式

- 规则变化时同步更新阅读版与 AI 执行版，并核对核心原则、V1／V2 判断、支持范围、共享数据、测试时序和完成标准。
- 测试命令、覆盖范围与兼容证据只在 AI 执行版维护，阅读版保留简明说明和链接；不新增第三份兼容说明或验证文档。
- 必要结果摘要区分本地源码、正式制品／真机、dev 与 prod；记录日期、提交、范围和未验项，不把历史结果冒充当前复验。
- 不向正式 docs 写入执行日志、任务快照、截图或原始响应；使用既有忽略输出目录、受控 artifact 或提交／Issue 追踪。
