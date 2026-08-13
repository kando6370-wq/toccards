# v1.1.0 版本增量

本目录只记录 v1.1.0 相对 [`v1.0.0`](../v1.0.0/) 的新增、变更和移除。未变化的产品与工程事实继续引用 v1.0.0 文档。

## 原始产品需求

以下文件为产品提供的 v1.1 原始 PRD，只读保留。App 页面、流程、文案、异常反馈和验收行为以最新 App PRD 为目标；Apple 可信证据与服务端授权同时受权益统一方案约束。当前代码、迁移和运行配置只用于证明实际完成状态，不能用来削减或改写 PRD 目标。

- [`Apple Subscription Premium 权益统一方案`](00-product/Apple_Subscription_Premium_%E6%9D%83%E7%9B%8A%E7%BB%9F%E4%B8%80%E6%96%B9%E6%A1%88.md)
- [`TCG Admin 订单统计与苹果通知消息 PRD V1.1 订阅真值收口版`](00-product/TCG_Admin_%E8%AE%A2%E5%8D%95%E7%BB%9F%E8%AE%A1%E4%B8%8E%E8%8B%B9%E6%9E%9C%E9%80%9A%E7%9F%A5%E6%B6%88%E6%81%AF_PRD_V1.1_%E8%AE%A2%E9%98%85%E7%9C%9F%E5%80%BC%E6%94%B6%E5%8F%A3%E7%89%88.md)
- [`TCG Card App v1.1 PRD`](00-product/TCG_Card_App_v1.1_PRD.md)

## 版本目标

除已记录的官网增量外，当前开发分支已实现 Fresh Purchase 的 Apple JWS 独立验证、session grant 和客户端补偿同步，完成本机 Restore 结果分流及 App Attest/JWS 服务端 proof 写链，并补齐 Notifications V2 原文留存、验签、幂等、确定性生命周期归约、失败补偿及 Apple Server API 校正。App Subscription 已按最新 PRD 支持 SKU 局部可用、StoreKit 本地化价格、商品重载 15 秒 Deadline、Purchase Pending/Cancelled/Failed/Unverified 分流、迟到 verified Transaction Update、Premium 三态、首次/冷启动及回前台静默刷新、全量 current entitlements 选择、Home/Search/Collection/Profile Free 顶部入口与来源页面实例返回，以及 Folder 并发上限拒绝后的列表刷新、输入保留和 Paywall 恢复；仅对已验证的新 Apple Purchase 使用 JWS 实际金额/币种异步上报 Firebase Revenue，并按 `transaction_id` 持久化去重和失败重试。首次安装 ATT 与 Singular 初始化顺序也已接入：仅 `notDetermined` 请求、冷启动不重复请求、回前台只同步状态，未配置 Key 或 SDK 失败不阻断业务。Admin 订单与通知业务功能已按最新 PRD 补齐，包含固化扣款次数、组合筛选、XLSX 和 inbox 失败排障视图；Decoded Payload 仅在授权用户主动打开详情后加载和复制，Admin API/UI 默认不返回原始 `signedPayload`。Singular 正式 Key、Apple Secret 配置、迁移执行和 iOS/Sandbox/TestFlight 验证尚未完成；既有 App Shell Golden 还存在历史字体资源被移除后无法稳定复现的问题。该 Golden 不是 v1.1 App 业务需求差距，但在基线明确处置前全量测试仍不通过，因此当前仍不构成可上线的订阅权益闭环。

订单美元金额的财务事实已新增 `0033_billing_exchange_rate_snapshot.sql`：新订单固化现有汇率服务的 rate、来源、时间、版本和舍入口径；汇率不可证明时保留空值，不阻断订单或伪造金额。升级/降级通知只更新下一 Product ID、不建单；重订阅以 Apple `originalTransactionId` 购买链判断首次付款或同链续费，不仅依赖 `transactionReason`。`0000` 至 `0033` 已在独立空白 local D1 完整执行并通过自动化迁移链测试；2026-08-13 Wrangler 只读核对确认远程 dev/prod 均待执行 `0025` 至 `0033`，尚未进行远程写入。

Portfolio 写请求已统一 15 秒 Deadline，并为 Create Folder、Quick Collect、完整 Add Collection Item 和 Add Wishlist 建立客户端超时重试与服务端结果重放闭环；该代码闭环不替代真实弱网与多设备发布验收。

## 当前订阅资料

- [`development-plan.md`](development-plan.md)：基于 PRD、评审结论与当前代码的分阶段开发计划及验收门槛。
- [`entitlement-contract.md`](entitlement-contract.md)：P0 Apple 证据、会话授权与服务端受限操作契约。
- [`contract-changes.md`](contract-changes.md)：订阅数据骨架、当前边界与上线缺口。
- [`migration.md`](migration.md)：v1.1 数据迁移、兼容性与回滚边界。
- [`app-store-connect-subscription-setup.md`](app-store-connect-subscription-setup.md)：App Store Connect 商品、测试与通知配置手册。

## 架构调研

- [`database-migration-research.md`](database-migration-research.md)：D1 全量迁移的 PostgreSQL 与云服务商选型、Cloudflare 适配、成本比较及采购建议。

## 按需创建

- `requirements.md`：增量需求和验收条件。
- `contract-changes.md`：流程、API、数据、权限或状态变化。
- `migration.md`：数据库、配置、兼容或数据迁移方案。
- `release-criteria.md`：发布前必须完成的验证。
- `release-notes.md`：最终发布说明。

没有实际变化时不创建空文件。实现落地后，在本版本目录中补充对应的当前实现文档；不得回写 v1.0.0 基线。

每个 v1.1 业务增量必须在同一开发检查点同步维护实现状态、契约或迁移影响、已通过验证及未完成边界。未同步文档或未执行必要验证时，不得将该项标记为完成。
