# iOS Restore 认证超时修复设计

## 根因

`AppleSubscriptionRestorer.restore` 对 `reader.read(..., synchronize: true)` 的完整 Future 使用 15 秒 `timeout`。iOS 桥接在同一个 `syncCurrentEntitlements` 调用中先等待 `AppStore.sync()` 的系统账号/密码交互，再读取 `Transaction.currentEntitlements`，因此用户输入密码的时间被计入超时。

## 修复

- 为 `AppleCurrentEntitlementReader` 增加独立 `synchronize()` 操作。
- iOS MethodChannel 增加 `syncAppStore`，只执行 `AppStore.sync()`；该调用不设置客户端 Deadline。
- `AppleSubscriptionRestorer` 先等待 `synchronize()`，完成后再对 `readCurrentEntitlements` 使用现有 15 秒 Deadline。
- 保留原生 `syncCurrentEntitlements` 分支以兼容已运行的旧 Dart 客户端，但新代码不再调用它。

## 平台与错误语义

- iOS：系统认证等待不超时；认证取消或 StoreKit 错误仍通过现有 `FlutterError` 返回；后续权益读取超时仍映射为 `restoreFailed`。
- Android：当前没有 App Store Restore 实现，不经过该 Reader，行为不变。
- 不修改 Product ID、Bundle ID、权益匹配、缓存或服务端 Restore proof。

## 验证

- 单元测试证明同步阶段超过权益 Deadline 仍不会超时。
- 单元测试证明同步完成后的权益读取仍执行 Deadline。
- 验证 MethodChannel 调用顺序为 `syncAppStore` 后 `readCurrentEntitlements`。
- 运行定向 Flutter 测试、静态分析、iOS test flavor 无签名构建，并在 iPhone 8 上重新安装后人工输入密码超过 15 秒复验。
