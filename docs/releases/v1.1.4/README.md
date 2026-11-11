# v1.1.4 开发文档

状态：当前开发版本。启用日期：2026-11-05（Asia/Shanghai）。创建基线为 `main@70bd7cf5`。

v1.1.3 已原位归档。本版本承接 v1.1.3 之后的新增、变更、移除和实际验证；未变化的产品、兼容、订阅、部署及历史验收继续引用 v1.1.3、v1.1.2 或更早版本，不复制整套历史文档。

## 当前基线

- [v1.1.3 开发归档](../v1.1.3/README.md)保留 2026-10-26 至 2026-11-04 的扫描、收藏、账号隔离、Admin、营销及生产 API／双 Admin 发布记录。
- v1.1.3 的生产发布记录不因版本切换重新记为新部署；生产源、Worker、Pages、PostgreSQL migration 和未验边界按原日期理解。
- App 向后兼容原则继续以 v1.1.2 的[人员阅读版](../v1.1.2/05-delivery/app-backward-compatibility-plan.md)和[AI 执行版](../v1.1.2/03-data-api/app-backward-compatibility-ai-guide.md)为规则真源；v1.1.4 的新增兼容证据写入本版本受影响业务文档或验证记录。
- Flutter UI 继续遵循 [v1.0.0 UI 设计系统](../v1.0.0/00-product/ui-design-system.md)及已经生效的增量合同。
- v1.1.3 的 API、Admin、Flutter、Marketing 和生产部署结果均为历史证据；后续开发、测试和发布不得只因进入 v1.1.4 就推断为已完成。
- 2026-11-05 的依赖、Node、Flutter/Dart、Gradle 和 Linux 镜像安全升级见 [技术栈安全升级](02-architecture/security-stack-upgrade.md)，源码、构建、dev/prod 与移动端发布分别记录。

## Android 免费首版与双端数据隔离

- [Android 免费首版增量 PRD v0.3 原件](00-product/Card_AI_Android_Free_First_Release_Incremental_PRD-3.md)：2026-11-05 产品输入，本次需求依据。
- [Android 与 iOS 双端数据隔离方案原件](00-product/Android-iOS双端数据隔离方案.md)：2026-11-03 历史技术建议；与新版 PRD 冲突的全局账号状态、全账号删除按钮及导出建议不作为本期需求。
- [结合当前项目的实施前评估](05-delivery/android-free-first-release-review.md)：2026-11-05 开始实现前的源码差距、待补规则、迁移与发布边界；其源码结论按评估基线理解，后续实现见下条合同。
- [双端平台账号与免费首版实现合同](03-data-api/platform-accounts.md)：账号、会话、删除、集中商业策略与配置隔离；2026-11-10 已完成生产 0018／API／双 Admin 发布，历史开发验证与本轮生产证据分别保留。
- [Android Google Play 正式配置交接清单](05-delivery/android-play-release-configuration.md)：正式签名、Firebase／OAuth／Play Integrity 配置、本机隔离构建与发布记录；207 无 Billing AAB 已由 Play 接收并发布至 6 人 Internal testing 轨道，当前为有效／尚未审核，真实安装、登录、Integrity、扫描与统计验收仍待完成。
- [Android 与 iOS 版本管理](03-data-api/app-version-management.md)：双端独立升级规则、Android 自动构建号及 APK／AAB 校验归档，沿用既有 iOS 规则与发布流程。

两份输入均按原始字节归档，不随实现修订。平台账号、删号与重新注册规则以新版 PRD 为准，原技术方案不代表当前已实施架构。

2026-11-05 用户补充明确：Android 扫描业务逻辑沿用当前 iOS，只取消订阅校验及对应的累计免费扫描额度限制，不新增整批处理、持久化或跨设备恢复机制。此澄清优先于 PRD 中相关整批约束，详见[评估报告 0.2](05-delivery/android-free-first-release-review.md#02-扫描规则澄清2026-11-05)。

## 文档路由

- [官网账号删除申请方案与页面设计](00-product/cardscanfox-account-deletion-design.md)：保留现有正式 URL；2026-11-11 已实现并正式发布官网邮件草稿、复制回退与人工协助入口，页面／资源及 Help 入口已验收，后台受控执行与客服运营仍按文档落实。

- [CardScanFox 正式官网发布](05-delivery/cardscanfox-production-cutover.md)：正式 Worker 与 Route、手工构建身份、自动发布边界及 2026-11-11 重发的回退点和验收记录。

- [官网改版规格](00-product/cardscanfox-website-redesign-spec.md)与[独立只读服务规格](02-architecture/cardscanfox-website-service-spec.md)：官网设计、内容真源及服务边界，实际实现和发布按各文档的状态与日期理解。

- [官网路由与搜索意图](05-delivery/cardscanfox-website-route-seo-spec.md)及[单卡目录与规模化索引](05-delivery/cardscanfox-catalog-indexing.md)：URL、元数据、目录和 sitemap 的设计与实现边界。

- [官网卡牌术语内容补充](05-delivery/cardscanfox-card-term-content-20261108.md)：2026-11-08 内容增量及对应验证记录。

- [官网首页真实卡牌展示](05-delivery/cardscanfox-home-featured-20261108.md)：2026-11-08 首页卡牌与详情链接的实现及验收记录。

- [IndexNow 调试记录](05-delivery/indexnow-debug-20261108.md)和[新版官网通知记录](05-delivery/indexnow-full-redesign-20261108.md)：按原日期保留通知范围、接口回执与收录边界，不作为当前部署或搜索收录状态。

- [PokeScope 自然搜索词与独立官网覆盖](05-delivery/website-competitor-keyword-coverage.md)：2026-11-08 竞品估算口径、四篇角色/卡况指南、既有页面归属和索引发现。

- [官网关键词、可筛选卡表与印次指南](05-delivery/marketing-keyword-content.md)：2026-11-05 竞品关键词估算补证、三套英文官方编号表、全球竞品样本的角色/印次参考页、价格快照与本地验收边界。

| 目录 | 记录范围 |
|---|---|
| `00-product/` | v1.1.4 新产品输入和明确批准的需求补充；不复制旧 PRD |
| `01-flows/` | 新增或变化的用户流程、状态和跨端行为 |
| `02-architecture/` | 新架构决策、部署拓扑和运行边界 |
| `03-data-api/` | 新数据模型、迁移、接口和兼容增量 |
| `04-admin/` | Admin 新功能和操作合同 |
| `05-delivery/` | 测试、构建、部署、回退和验收证据 |

没有对应增量时不创建占位文档。新增文档必须从本 README 提供入口；已有合同未变化时直接引用 v1.1.3、v1.1.2 或更早版本。

## 记录规则

- 后续开发资料默认写入 `docs/releases/v1.1.4/`，不得继续向 v1.1.3 或更早归档版本追加新功能或新日期检查点。
- 本地验证、CI、dev、prod、商店发布、用户反馈和 Agent 独立验收必须分别标记，未执行项不得写成通过。
- 不在正式 docs 中保存执行日志、任务快照、截图、Secret、Token、私钥或原始生产响应。
- 文档版本、App 版本、API 版本、Git 提交和环境运行版本分别管理；创建 v1.1.4 不代表代码、数据库或环境发生变化。

- [CardScanFox 独立预览与自动部署](02-architecture/cardscanfox-auto-deployment.md)：新版独立应用、保护旧 URL、静态预览与只读 Worker 的发布边界。

- [CardScanFox 页面搜索意图与页面任务](05-delivery/cardscanfox-page-intents.md)：固定页面归属、动态卡牌元数据、平台下载与价格榜单口径。
