# v1.1.0 版本增量

本目录只记录 v1.1.0 相对 [`v1.0.0`](../v1.0.0/) 的新增、变更和移除。未变化的产品与工程事实继续引用 v1.0.0 文档。

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
