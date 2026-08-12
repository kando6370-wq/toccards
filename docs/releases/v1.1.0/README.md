# v1.1.0 版本增量

本目录只记录 v1.1.0 相对 [`v1.0.0`](../v1.0.0/) 的新增、变更和移除。未变化的产品与工程事实继续引用 v1.0.0 文档。

## 原始产品需求

以下文件为产品提供的 v1.1 原始 PRD，只读保留，不作为已实现状态的证明。评审和实现结论以当前代码、迁移、运行配置及本目录工程文档为准。

- [`Apple Subscription Premium 权益统一方案`](00-product/Apple_Subscription_Premium_%E6%9D%83%E7%9B%8A%E7%BB%9F%E4%B8%80%E6%96%B9%E6%A1%88.md)
- [`TCG Admin 订单统计与苹果通知消息 PRD V1.1 订阅真值收口版`](00-product/TCG_Admin_%E8%AE%A2%E5%8D%95%E7%BB%9F%E8%AE%A1%E4%B8%8E%E8%8B%B9%E6%9E%9C%E9%80%9A%E7%9F%A5%E6%B6%88%E6%81%AF_PRD_V1.1_%E8%AE%A2%E9%98%85%E7%9C%9F%E5%80%BC%E6%94%B6%E5%8F%A3%E7%89%88.md)
- [`TCG Card App v1.1 PRD`](00-product/TCG_Card_App_v1.1_PRD.md)

## 版本目标

除已记录的官网增量外，当前代码已合入 App 订阅体验原型、StoreKit 抽象层及 Admin/D1 数据骨架。该实现尚不包含可上线的服务端订阅可信验证与权益闭环。

## 当前订阅资料

- [`contract-changes.md`](contract-changes.md)：订阅数据骨架、当前边界与上线缺口。
- [`app-store-connect-subscription-setup.md`](app-store-connect-subscription-setup.md)：App Store Connect 商品、测试与通知配置手册。

## 按需创建

- `requirements.md`：增量需求和验收条件。
- `contract-changes.md`：流程、API、数据、权限或状态变化。
- `migration.md`：数据库、配置、兼容或数据迁移方案。
- `release-criteria.md`：发布前必须完成的验证。
- `release-notes.md`：最终发布说明。

没有实际变化时不创建空文件。实现落地后，在本版本目录中补充对应的当前实现文档；不得回写 v1.0.0 基线。
