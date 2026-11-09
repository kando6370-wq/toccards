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
- [双端平台账号与免费首版实现合同](03-data-api/platform-accounts.md)：2026-11-05 起的账号、会话、删除、集中商业策略与测试／正式配置隔离实现；开发与验证状态按该文档记录，未执行远程迁移或发布。
- [Android Google Play 正式配置交接清单](05-delivery/android-play-release-configuration.md)：正式包名、Play 签名、Firebase／OAuth／Play Integrity 字段映射、独立打包机输入及验收顺序；未核实值保持待确认，不保存私钥或占位配置。

两份输入均按原始字节归档，不随实现修订。平台账号、删号与重新注册规则以新版 PRD 为准，原技术方案不代表当前已实施架构。

2026-11-05 用户补充明确：Android 扫描业务逻辑沿用当前 iOS，只取消订阅校验及对应的累计免费扫描额度限制，不新增整批处理、持久化或跨设备恢复机制。此澄清优先于 PRD 中相关整批约束，详见[评估报告 0.2](05-delivery/android-free-first-release-review.md#02-扫描规则澄清2026-11-05)。

## 文档路由

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
