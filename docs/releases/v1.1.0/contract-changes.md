# v1.1.0 契约变化

## 订阅与内购数据骨架

当前实现新增以下 D1 表，迁移见 `apps/workers-api/src/db/migrations/0025_billing_admin.sql`：

| 表 | 当前用途 |
|---|---|
| `billing_product` | 保存商店商品、计划与权益的映射。 |
| `billing_purchase_chain` | 保存按商店、环境和原始交易 ID 唯一的购买链当前状态。 |
| `billing_transaction` | 追加保存交易记录，账单金额使用整数 micros。 |
| `billing_entitlement_grant` | 保存购买链与 owner 的权益关联。 |
| `apple_server_notification` | 保存 Apple 通知载荷及处理状态。 |

Admin 已提供订单与 Apple 通知的查询骨架；Flutter 已提供订阅页面、购买入口和 StoreKit 抽象层。

## 当前边界

上述能力定位为 **App 订阅体验原型 + StoreKit 抽象层 + Admin/D1 数据骨架**，不是生产可用的订阅闭环。当前至少存在以下上线阻塞：

- 客户端默认仍使用缺失的票据验证器，真实购买或恢复不能完成可信授权。
- Workers 尚无 Apple 签名交易验证、App Store Server API 集成及 Notifications V2 接收处理闭环。
- `billing_entitlement_grant` 当前按 owner 关联，尚未落实 v1.1 PRD 要求的会话级授权凭证。
- Scan Quota 与 Folder 限制尚未由服务端基于可信 grant 原子执行。
- Apple 通知表结构尚未满足先保存完全原始请求、再异步验签和解码的要求。

订阅权益上线前必须以最新 v1.1 PRD 评审结论补齐服务端可信证据、会话级 grant、通知状态归约、幂等和异常处理，并完成 Sandbox、TestFlight 及服务端集成验收。
