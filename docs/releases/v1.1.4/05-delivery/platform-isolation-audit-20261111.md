# 双端平台数据隔离专项审计（2026-11-11）

本次审计针对同一基础账号同时使用 iOS 与 Android 时，除 Collection 外的业务是否可能串用 owner、会话、本地缓存或权益。结论按当前源码、现有测试和项目约定工具链记录；不把真实双端登录、正式制品或真机结果用源码测试替代。

## 结论

服务端核心业务读写目前都以认证 session 解析出的 `owner_type + owner_id` 为边界。Portfolio、Collection、Wishlist、扫描确认、扫描图片、反馈和安装关联没有发现把 Android owner 读写到 iOS owner 的明确路径。现有回归还验证了建立 Android 平台账号后，原 iOS session 仍能读取原 iOS collection。

本轮发现并修复了四个会造成跨平台或跨账号状态混用的问题：

1. Android 启动清理遗留 iOS 用户会话时，旧 iOS 游客曾残留在 `previousAnonymousSession`，Android 后续 Logout 可能恢复该游客 owner。现在清理旧平台会话时同步清理 previous slot，并在恢复 previous guest 前强制校验平台与 Android `data_space_id`。
2. iOS entitlement cache 原来使用单一 Secure Storage key。现在按 `owner_type + platform + data_space_id` 建立 scoped key；SubscriptionController 也随 auth scope 重建，并拒绝迟到的旧 session entitlement 结果覆盖当前账号。
3. ScanQuotaController 原来不监听 auth scope。账号、平台或 data space 变化后现在先重置 quota 状态，再由当前 session 刷新服务端额度。
4. `scan_record.platform` 原来直接接受客户端表单值。现在由服务端认证 session 的真实平台写入，客户端只能提供其他设备信息，不能污染后台平台统计。

## 已验证的安全边界

- `owner-auth.ts` 对 user session 关联 `platform_account.id/user_id/platform/status`，对 anonymous session 关联 `anonymous_account.id/platform/status`；Portfolio、Collection、Wishlist、Scan、Feedback 等路由复用该 owner。
- Flutter 的 selected folder、amount hidden、pending collection、Search/Home/Collection controller 已按 auth scope 重建或校验；公开卡图、汇率和价格缓存不包含用户资产，不需要按平台复制。
- Android 免费策略不读取 Apple entitlement；Apple 购买、Restore 和生命周期接口仍只允许 iOS 商业路径。
- Apple server correction 当前的 grant 更新仍按 purchase chain 处理；入口只接受 Apple/iOS 业务，已列为需要补齐“双平台同一基础 user”回归矩阵的证据缺口。

## 尚未由源码矩阵完全证明的范围

- 同一 user 同时拥有 iOS/Android 时的完整 Portfolio/Wishlist CRUD 矩阵，包括 folder rename/reorder/delete、collection item update/delete、card assets batch。
- Scan upload/confirm/delete、R2 图片清理和跨平台保留的完整双 owner 矩阵。
- 双平台订阅 chain、Apple Restore、删除一个平台后另一平台权益及通知 correction 的完整矩阵。
- Feedback、app installation、analytics pending queue 的双平台统计归属；这些主要是运营身份/统计隔离风险，不是当前已证实的收藏资产泄漏。
- Admin 的双平台读写权限与扫描平台报表矩阵。
- 真实 iOS/Android 测试包的登录、平台 session 返回值、Play Integrity、真机和正式 API/数据库连接。测试包若仍复现 Collection 问题，应优先记录 `/auth/me` 与 `/collection/items` 的状态码、`platform`、`data_space_id` 和 API 环境。

## 本轮验证

使用项目约定的 Flutter 3.47.9 / Dart 3.13.7：

- Flutter analyze：0 issues。
- Auth controller：36/36 通过。
- Scan quota：9/9 通过。
- Subscription entitlement/cache/server sync：13/13 通过。
- Android auth prompt 与相关布局测试通过；完整 Auth profile 文件仍有一个既有的 `Profile exposes Refresh after auth startup fails` 测试失败，与本轮 owner scope 改动无关。

Workers 类型检查和依赖方向检查通过。Scan 路由的单场景回归通过；完整 `scan/routes.test.ts` 在本机 Node 22.20.0 进程中异常退出，项目约定 Node 为 22.23.4，因此不能把该完整集合写成通过。正式审计仍需在 Node 22.23.4 下重跑完整 Workers 矩阵。
