# v1.1.0 版本文档

本目录记录 v1.1.0 相对 [v1.0.0](../v1.0.0/README.md) 的产品输入、当前实现、数据契约和交付边界。当前 prod 发布来源为 `main@759b072`（2026-09-11），已包含 Linux 测试环境合并、Singular 同进程初始化恢复、Home 版本复查、iOS 交付物保存及扫描取景框布局修复。客户端 `pubspec.yaml` 为 `1.0.2+135`，与本目录的产品迭代版本分别管理；历史检查点保留原日期，不能外推为当前验收结果。

## 当前结论

- 2026-09-11 已将 `main@759b072` 发布到 prod，Worker `4f543496-9d54-48c4-a16c-0e608dcc32f0` 承载 100% 流量，配套 Admin 及 10 个静态资源摘要验证通过；向量识别绑定、公共环境版本配置、域名及定时配置已验证，见[prod 发布记录](05-delivery/VERIFICATION.md#prod-向量协议与环境版本配置发布2026-09-11)。

- 仓库内已形成 Apple 订阅与 session grant、Scan Quota、Folder 限制、Performance、Extended Price History、Admin 订单与 Apple Notifications V2 的实现和自动化证据。
- main 的扫描代码与 Cloudflare dev/prod 配置均使用向量协议；App 扫描支持 iOS 16+、Android API 24+，Web 扫描暂不支持。远程协议只按对应日期的部署证据判断，详见[扫描识别链路](01-flows/scan-recognition.md)。
- main 已包含原由 `19a6ac4` 引入的 Linux 测试环境，包含共享 Hono/Node 入口、独立 PostgreSQL、内存 KV、本地图片卷和分支监听发布脚本。Linux 尚未提供 `VECTOR_RECOGNITION` 适配器，仅填写旧 OCR 地址不能启用扫描；服务器当前部署 SHA 未于本轮回读，见[Linux 兼容设计](02-architecture/linux-test-environment.md)。
- 升级门禁在实际 Home 首帧后启动，后续 Home 返回或回前台静默复查，已确认强更仍跨路由拦截。扫描取景框从首帧预留底部结果区，iOS 检测分数按 sigmoid 转为概率。iOS 发布脚本按 Bundle ID 保存 IPA/dSYM，测试保留 3 个版本、正式保留 7 个版本；当前实现和既有测试限制见[发布与验证](05-delivery/VERIFICATION.md#当前代码与交付边界)。
- main 已包含三项扫描 Golden 修复、Review 图片等待、页面测试归因隔离以及 Windows 下的 Linux 打包路径修复。2026-09-10 的代码基线 `6a96404` 已通过 App 1047/1047、订阅包 9/9；Workers 默认首轮失败与完整受 Git 跟踪测试降低并发后的 621/621 通过分别保留，详见[Golden 与全量复验](05-delivery/VERIFICATION.md#golden-基准与全量复验2026-09-10)。
- “代码已完成”不等于发布完成。Apple 生产配置、Sandbox/TestFlight、真机、多设备、重度数据和真实订单规模仍是独立验收门槛。
- D1 已废弃，Cloudflare dev/test 与 prod 均使用共享 PostgreSQL/Hyperdrive，KV、R2、Apple 配置、域名和 secrets 继续隔离。prod 于 2026-09-11 已切换向量协议与独立版本配置；此前较早协议只保留为历史记录，最新范围见[prod 发布与验证](05-delivery/VERIFICATION.md#prod-向量协议与环境版本配置发布2026-09-11)。
- 2026-09-11 已核对共享 PostgreSQL `0000` 至 `0011` 的 12 条 ledger checksum，全部匹配，未验证约束为 0。经单独授权执行完整 `0011`，仅新增 production 两条版本键、既有四条配置不变；本轮未执行 `0012`，ledger 也无该迁移登记，历史回填不标为完成，见[数据迁移](03-data-api/migration.md)。
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
- [扫描向量识别链路](01-flows/scan-recognition.md)：main 当前端侧识别引擎、向量接口及保留的扫描业务契约。
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
