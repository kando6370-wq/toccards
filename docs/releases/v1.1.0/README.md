# v1.1.0 版本文档

本目录记录 v1.1.0 相对 [v1.0.0](../v1.0.0/README.md) 的产品输入、当前实现、数据契约和交付边界。当前功能代码核对基线为 `dev@7d9b0ca`（2026-09-21），已包含 Linux 测试环境、端侧向量扫描、订阅与归因、25 秒客户端总 Deadline、三页 Onboarding 更新、API 慢请求收敛和全业务 API 请求关联。客户端 `pubspec.yaml` 为 `1.0.3+155`。kd201 最近一次完整 SSH 基础设施回读为 `dev@baf0d7b`；推送 `7d9b0ca` 后的 HTTP 回读已确认请求 ID API 与对应 Admin 主资源对外生效，但本机缺少可用 SSH key，未重新读取服务器 manifest、状态文件、备份或 ledger。产品迭代版本、源码版本、安装包和商店发布状态分别管理；历史检查点保留原日期，不能外推为当前验收结果。

## 当前结论

- 当前业务环境只有 prod（维持原 Cloudflare 部署）与 dev（kd201 Linux）；旧 CF dev 仅为历史部署，不再发布。dev 仍通过独立 CF 服务调用向量识别和 Apple Sandbox 回调，详见[系统架构](02-architecture/architecture.md#6-环境与部署)。
- 仓库内已形成 Apple 订阅与 session grant、Scan Quota、Folder 限制、Performance、Extended Price History、Admin 订单与 Apple Notifications V2 的实现和自动化证据。
- 扫描向量链路已合入并推送 `dev`，对应 Workers/Admin 曾发布到旧 CF dev，现由 Linux 承接业务；App 扫描支持 iOS 16+、Android API 24+，Web 扫描暂不支持。源分支已清理，后续使用 `dev`，详见[扫描识别链路](01-flows/scan-recognition.md)。
- Linux 入口已通过 `19a6ac4` 合入 dev，包含共享 Hono/Node、独立 PostgreSQL、内存 KV、本地图片卷和分支监听发布脚本。App test/Admin development 默认使用 Linux 内网入口，扫描仅通过 CF HTTP 向量服务检索。2026-09-21 最近一次完整 SSH 回读为 `dev@baf0d7b`，API/DB healthy、Web running、ledger 为 14 项且最新为 `0013`；随后 `dev@7d9b0ca` 的请求 ID API 与 Admin 主资源已由 HTTP 回读确认对外生效，服务器状态文件未复读。旧 CF dev 业务 Worker、域名和 cron 已退役，测试数据与旧包保留；见[Linux 兼容设计](02-architecture/linux-test-environment.md)和[请求关联验证记录](05-delivery/VERIFICATION.md#全业务-api-请求关联-id2026-09-21已部署-dev)。
- 升级门禁在实际 Home 首帧后启动，后续 Home 返回或回前台静默复查，已确认强更仍跨路由拦截。扫描取景框从首帧预留底部结果区，iOS 检测分数按 sigmoid 转为概率。iOS 发布脚本按 Bundle ID 保存 IPA/dSYM，测试保留 3 个版本、正式保留 7 个版本；当前实现和既有测试限制见[发布与验证](05-delivery/VERIFICATION.md#当前代码与交付边界)。
- 2026-09-10 的 App 全量 1047/1047、订阅包 9/9 与 Workers 621/621 保留为对应历史检查点；2026-09-21 请求关联后的 Workers `src` 为 76 文件、650/650，并通过 type-check、依赖方向、dev dry-run 与 Code Review。Flutter 受影响 API 客户端为 117/117，Admin 为 23/23；这些定向和服务端全量结果仍不能替代未重跑的完整 App 测试或真机验收。
- “代码已完成”不等于发布完成。Apple 生产配置、Sandbox/TestFlight、真机、多设备、重度数据和真实订单规模仍是独立验收门槛。
- D1 已废弃，旧 Cloudflare dev/test 与 prod 均已完成 PostgreSQL 迁移；2026-09-09 两环境回读均绑定同一 PlanetScale PostgreSQL/Hyperdrive 且无 D1 binding。2026-09-17 旧 dev Worker 已退役，历史数据库/KV/R2 保留；prod 和共享向量识别仍运行，退役回读见[发布与验证](05-delivery/VERIFICATION.md#旧-cloudflare-dev-业务退役2026-09-17)。
- 数据库执行状态按环境和证据区分：共享 Cloudflare PostgreSQL 的 `0000` 至 `0010` 及 `0011/0012` 状态继续沿用各自历史记录，未因 Linux 发布外推；Linux 独立 PostgreSQL 已在 2026-09-20 回读为 14 项 ledger，最新为 `0013`、`0012`、`0011`。prod 尚未执行 `0013`，详见[数据迁移](03-data-api/migration.md)。
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
- [Linux 测试环境与 Cloudflare 正式环境兼容设计](02-architecture/linux-test-environment.md)
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
- [Linux 测试环境实施计划](05-delivery/linux-test-environment-implementation-plan.md)
- [Linux 测试环境部署手册](../../../deploy/linux/README.md)
- [Linux 测试环境自动部署手册](05-delivery/linux-test-auto-deployment.md)
- [需求可追踪矩阵](05-delivery/traceability-matrix.md)
- [发布与验证记录](05-delivery/VERIFICATION.md)：Home 版本复查、扫描布局、iOS 交付物、Singular 收入和历史发布边界。
- [iOS IPA 与符号文件保存](../../../apps/flutter-app/README.md#ipa-与符号文件保存)
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
