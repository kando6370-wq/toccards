# v1.1.0 版本文档

本目录记录 v1.1.0 相对 [v1.0.0](../v1.0.0/README.md) 的产品输入、当前实现、数据契约和交付边界。当前代码核对基线为 `dev@b0b54df`（2026-09-09），已包含向量识别合并 `f38ef98`、Scan 购买价格事件修复和 Singular 收入上报；历史检查点保留原日期，不能外推为当前验收结果。

## 当前结论

- 仓库内已形成 Apple 订阅与 session grant、Scan Quota、Folder 限制、Performance、Extended Price History、Admin 订单与 Apple Notifications V2 的实现和自动化证据。
- 扫描向量链路已合入并推送 `dev`，对应 Workers/Admin 已发布到 dev；App 扫描支持 iOS 16+、Android API 24+，Web 扫描暂不支持。源分支已清理，后续使用 `dev`，详见[扫描识别链路](01-flows/scan-recognition.md)。
- “代码已完成”不等于发布完成。Apple 生产配置、Sandbox/TestFlight、真机、多设备、重度数据和真实订单规模仍是独立验收门槛。
- D1 已废弃，dev/test 与 prod 均已完成 PostgreSQL 迁移；2026-09-09 用户确认与 Cloudflare 回读一致，两环境均绑定同一 PlanetScale PostgreSQL/Hyperdrive，均无 D1 binding。dev 已使用向量识别，prod 仍为较早的识别协议，不能将本地 prod 配置视为已部署。KV、R2、`APP_ENVIRONMENT`、Apple 配置、域名和 secrets 继续隔离，最新版本回读见[发布与验证](05-delivery/VERIFICATION.md)。
- 数据库执行状态按证据区分：`0000` 至 `0010` 的远程应用与校验记录截至 2026-09-07；2026-09-08 仅初始化 `0011` 的 development 两条版本键，完整 `0011` 未登记完成；`0012` 已有修复脚本及测试，新 Worker 已发布，历史数据回填尚未执行。本轮未重查数据库 ledger、价格指针或业务数据，详见[数据迁移](03-data-api/migration.md)。
- 六份产品输入保持字节不变；实现状态只在 `01-flows` 至 `05-delivery` 更新。

## 原始产品输入

- [Apple Subscription & Premium 权益统一方案](00-product/Apple_Subscription_Premium_%E6%9D%83%E7%9B%8A%E7%BB%9F%E4%B8%80%E6%96%B9%E6%A1%88.md)
- [TCG Admin 订单统计与苹果通知消息 PRD](00-product/TCG_Admin_%E8%AE%A2%E5%8D%95%E7%BB%9F%E8%AE%A1%E4%B8%8E%E8%8B%B9%E6%9E%9C%E9%80%9A%E7%9F%A5%E6%B6%88%E6%81%AF_PRD_V1.1_%E8%AE%A2%E9%98%85%E7%9C%9F%E5%80%BC%E6%94%B6%E5%8F%A3%E7%89%88.md)
- [TCG Card App v1.1 PRD](00-product/TCG_Card_App_v1.1_PRD.md)
- [订阅升级降级补充](00-product/修改-升级降级订阅.md)
- [订阅升级降级补充（二）](00-product/修改2-升级降级订阅.md)
- [收藏待编辑与通用卡牌详情改版 PRD](00-product/TCG_Card_App_v1.1_收藏待编辑与通用卡牌详情改版_PRD.md)

## 实现文档

### 业务流程

- [业务上下文](01-flows/business-context.md)：角色、主流程、状态、实体、规则、上下游和待确认项。
- [扫描向量识别链路](01-flows/scan-recognition.md)：已合入 dev 的端侧识别引擎、向量接口及保留的扫描业务契约。
- [官网增量需求](01-flows/requirements.md)：当前版本的营销站搜索发现与视觉增量。

### 架构

- [系统架构](02-architecture/architecture.md)
- [Monorepo 边界](02-architecture/monorepo.md)
- [技术栈](02-architecture/tech-stack.md)
- [架构决策索引](02-architecture/decisions/README.md)

### 数据与 API

- [契约变化](03-data-api/contract-changes.md)
- [Premium 权益契约](03-data-api/entitlement-contract.md)
- [数据迁移](03-data-api/migration.md)
- [Trending Today 数据采集与 PostgreSQL 写入指南](03-data-api/trending-collector-integration.md)
- [历史数据库迁移选型研究](03-data-api/research/database-migration-research.md)
- [价格历史容量与性能分析](03-data-api/research/price-history-database-capacity-analysis.md)
- [PostgreSQL 价格域详细 DDL 设计](03-data-api/research/price-domain-postgresql-ddl.md)

### Admin

- [Admin 实现与权限](04-admin/admin.md)

### 交付与验收

- [开发计划](05-delivery/development-plan.md)
- [需求可追踪矩阵](05-delivery/traceability-matrix.md)
- [发布与验证记录](05-delivery/VERIFICATION.md)：版本管理、向量识别、Singular 收入、合并验证与运行环境边界。
- [App Store Connect 订阅配置手册](05-delivery/app-store-connect-subscription-setup.md)

## 证据口径

| 表述 | 含义 |
|---|---|
| 代码已完成 | 当前仓库存在实现且有对应自动化证据 |
| 历史环境已验证 | 文档记录的指定日期、环境和部署/迁移已验证，不能自动外推到当前 |
| 外部验收待完成 | 依赖密钥、Apple、远程环境、真机、并发或目标规模，仓库内测试不能替代 |
| 产品待决 | PRD 未给出可测试口径，开发不得自行设定 |
| 技术建议 | 调研结论，尚未批准或实施 |

## 冻结与更新规则

- `00-product` 与 `docs/releases/v1.0.0` 不在本版本实现任务中修改。
- 当前代码与文档冲突时，以代码、Schema/迁移、配置和测试为实现事实，同时保留产品差距。
- 带日期的历史迁移、部署和性能数据保留原日期；没有重新连接环境时不得写成实时状态。
