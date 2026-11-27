# Google Play 订阅配置内部包 1.0.8+221

2026-11-26 14:22（北京时间），Google Play 将 `com.cardai.tcg` 的 `1.0.8 (221) - Internal` 发布给内部测试人员。发布前应用包列表最高为 220，发布后刷新 Internal 轨道，最新版本为 221，状态为「有效」「已面向内部测试人员发布」。

## 订阅配置

发布前，「借助 Play 变现 → 商品 → 订阅」提示「上传新 APK」。发布后，同一应用显示「创建订阅内容」。当前操作账号看到「您需要权限」，按钮处于禁用状态。后续由具备此应用商品管理权限的账号配置商品、基础方案和价格。221 沿用 Android 的免费业务策略。

## 制品与验证

- 构建源为干净的 `0578228719650585f6bed8347258c340adba7eef`。签名 AAB 为 `CardAI-Prod-1.0.8-221.aab`，共 111,859,704 字节，SHA-256 为 `dced9f7dfd3ce9fa0e3e540306c0e3dede1c28b134fb28fab2b7af9052fb20a0`。成品、R8 mapping、三个架构的 Dart 符号和构建清单已归档到发布目录。
- AAB 的 Manifest 含 Google Play Billing Library `9.1.0` 版本标记，DEX 含结算组件。与 220 相比，权限清单仅增加 `com.android.vending.BILLING`。包名、Upload 证书、生产 API、minSdk 24、targetSdk 36、主界面竖屏和 64 位原生库 16 KB 对齐均已核对。
- Flutter 静态分析通过。Flutter 82 项定向回归覆盖 Android 免费策略、iOS StoreKit 验单与恢复及订阅展示，Android 打包与归档脚本 26 项通过。iOS 真机购买与恢复、Android 真实交易和商店正式审核留待对应发布阶段验收。
