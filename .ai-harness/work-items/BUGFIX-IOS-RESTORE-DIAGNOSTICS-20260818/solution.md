# iOS Restore 诊断日志修复方案

## 根因

- iOS `AppStore.sync()` 异常被转换为 `apple_restore_failed` 时，`FlutterError.details` 为 `nil`，Apple 错误域和数值错误码丢失。
- Flutter `SubscriptionController.restore()` 捕获所有异常时未记录异常或堆栈，只更新为既有 `restoreFailed` 事件。

## 修改

- Swift 将捕获的 `Error` 桥接为 `NSError`，仅传递 `domain` 与数值 `code`；不记录描述、账号、Product ID、交易 JWS 或其他用户数据。
- Dart 在 Restore catch 中通过 `debugPrint` 记录异常对象与堆栈。`PlatformException` 的 code/message/details 由其字符串表示保留，`TimeoutException` 也可直接区分。
- 保持 Restore 成功、Not Found、Failed、15 秒 Deadline、UI 文案和状态更新顺序不变。

## 跨端能力矩阵

| 平台 | Restore 业务语义 | 本次变化 | 验证 |
| --- | --- | --- | --- |
| iOS 15+ | 用户主动 `AppStore.sync()` 后读取 verified entitlement | 原生错误增加非敏感 domain/code，Flutter 输出异常与堆栈 | Dart 定向测试、静态分析、iOS 构建、真机复现 |
| Android | 当前配置不启用 Apple Restore | 无业务变化；共享 catch 不会从 Android Restore 入口触发 | 静态分析与现有订阅测试 |

## 文档影响

更新 `docs/releases/v1.1.0/05-delivery/development-plan.md` 的 Restore 实现状态，记录诊断日志能力和真机错误码仍需重新复现确认。
