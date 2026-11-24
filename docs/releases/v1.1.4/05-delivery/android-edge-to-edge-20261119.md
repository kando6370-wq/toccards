# Android 无边框画面检查（2026-11-19）

## 结论

当前 Flutter App 已主动使用 `SystemUiMode.edgeToEdge`，Android 构建实际使用 `targetSdkVersion=36`、`compileSdkVersion=36`、`minSdkVersion=24`。Android 原生 `MainActivity` 不需要再重复加入 Kotlin `enableEdgeToEdge()`，否则会把同一窗口策略分散到两个层面。

现有 Home、Search、Collection、Profile、详情、订阅、认证和 Scan 页面已经使用 `SafeArea` 或 `MediaQuery` 安全区。Scan 的顶部控件、取景框和底部结果区已有安全区计算。引导页原来只保留固定 48dp 底部间距，未使用系统底部 inset，已补齐这一处边界。

## 实现变更

- `apps/flutter-app/lib/features/onboarding/onboarding_page.dart` 将引导控制面板从底部对齐改为 `Positioned`。当系统底部安全区超过现有 48dp 保留值时，整个面板向上移动超出部分，保持原有视觉间距和面板高度。
- `apps/flutter-app/test/widget/onboarding_page_test.dart` 增加 72dp 底部 inset 场景，确认“Skip and start now”按钮仍位于安全区域内。测试辅助支持注入底部 `MediaQuery.padding`。
- 未修改 iOS 原生方向配置、共享主题、Android `MainActivity` 或发布配置。

## 验证结果

| 检查 | 结果 | 范围 |
|---|---|---|
| `flutter analyze` | 通过 | Flutter App，Flutter 3.47.9 |
| 引导页 widget 测试 | 17/17 通过 | 原有 390×844、紧凑视口、动效与可访问性场景，加 72dp 底部 inset 场景 |
| Android debug APK 构建 | 通过 | JDK 21、Flutter 3.47.9 |
| APK manifest | 通过 | `targetSdkVersion=36`、`compileSdkVersion=36`、`minSdkVersion=24` |
| API 36 模拟器 | 通过 | 手势导航，应用启动、状态栏和底部系统区域未遮挡引导按钮，日志无崩溃或 inset 异常 |

修改前已完成的相关基线检查仍保留为独立证据。Scan 方向与安全区测试为 169/169，相关页面组合 widget 测试为 453/453。这两组没有在本次仅影响引导页的最终 diff 后重复执行。

## 未覆盖范围

本机没有 API 35 模拟器或 Android 15 实体设备，因此本记录的真实窗口检查使用 API 36 模拟器，不能写成 Android 15 实机验收。未执行 iOS 模拟器或实体设备运行检查，iOS 本次没有源码变更。Gradle 8.14.6、AGP 8.13.2 和 Kotlin 2.2.20 的升级提示与本次无边框修复分开处理。

本次已补充一台 Android 12 实体设备验证，但仍不代表 Android 15/API 35 实体设备、Google Play 生产包或 Play 安装包全量验收已经完成。

## 初始连接失败记录（错误地址，2026-11-19）

用户首次提供的地址为 `192.168.35.22:38991`。该地址从 `192.168.35.3` 返回 `DestinationHostUnreachable`，`adb connect` 返回 Windows 10060 超时，ARP 没有有效条目。随后用户更正为 `192.168.36.22:38991`，设备连接、安装和实体测试均已完成，详见下一节。

## 实体设备复测（2026-11-19 10:43–11:02，+08:00）

设备通过 `192.168.36.22:38991` 无线 ADB 接入。

| 项目 | 结果 | 证据 |
|---|---|---|
| 设备 | 已通过 | HONOR `YOK-AN10`，系统 Android 12，API 31，版本 `YOR-AN10 7.0.0.180(C00E163R10P3)` |
| 屏幕 | 已读取 | `1236×2676`，密度 520 |
| 测试包 | 已安装并启动 | `com.kando.kandoApp.beta`，version `1.0.7`，versionCode `213`，target SDK `36`，安装使用 `adb install -r -d`，保留原有数据 |
| Home | 通过 | 状态栏、主内容、底部导航和 Scan 入口均可见，无明显遮挡 |
| Search | 通过 | 搜索框、卡片网格和底部导航可见，无明显遮挡 |
| Collection | 通过 | Portfolio／Wishlist、卡片内容和底部导航可见，无明显遮挡 |
| Profile | 通过 | 账户、支持、法律条目和底部版本文本位于安全区域内 |
| 卡牌详情 | 通过 | 返回、分享、图片、标签、VIEW SOLD LISTINGS 和底部标签可操作 |
| Scan | 通过 | 相机预览、顶部控件、取景框、Gallery／拍摄／Done 控件可见，取景框与控件没有被状态栏或底部系统区域遮挡 |
| 相机权限 | 通过 | `android.permission.CAMERA` 已授权，Scan 可直接进入预览 |
| Android 方向 | 通过 | Scan 进入、模拟请求横屏、退出和系统返回后均为 `SCREEN_ORIENTATION_PORTRAIT`、`ROTATION_0` |
| 应用日志 | 通过 | 本轮未发现该应用的 `FATAL EXCEPTION`、`AndroidRuntime`、`E/flutter`、`FlutterError` 或未处理异常 |

实体设备截图与 UI 层级证据保存在 `test-artifacts/android-edge-to-edge-20261119/`。本次没有清除应用数据，没有触发拍摄、识别提交、收藏、心愿单、账户删除或购买操作。

## 实体设备边界

本设备为 Android 12/API 31，不能替代 Android 15/API 35 实体设备验收。引导页未在本机清除数据后重走，以保留设备上的现有测试数据，底部 inset 场景由 widget 测试和 API 36 模拟器覆盖。Android 免费首版在当前配置下会将 `/subscription` 重定向到 `/home`，本次没有购买流程可测。真实卡片识别、后端写入、账号登录和支付流程未执行。


## 小米实体设备连接记录（2026-11-19 11:32:04 +08:00）

用户提供地址 192.168.36.51:38817 后，设备曾短暂成功通过无线 ADB 接入，设备标识为 Xiaomi 23116PN5BC（shennong），Android 16/API 36，屏幕 1440×3200，密度 560。随后设备在安装前进入 offline 状态，adb install 未执行成功，测试包没有安装或覆盖，设备数据没有修改。

复测时 192.168.36.51 仍可 Ping，但 TCP 38817 返回拒绝连接，adb mdns services 没有发现新的无线调试端口，常用端口 5555 和 38817–38820 也不可连接。需要在手机的开发者选项中重新打开无线调试，并提供当前显示的连接端口后继续。

## 小米实体设备复测（2026-11-19 11:58–12:08，+08:00）

用户更新无线 ADB 端口为 `192.168.36.51:39677` 后重新接入同一台 Xiaomi `23116PN5BC`（ADB 标识 `shennong`）。设备运行 Android 16/API 36，物理屏幕为 `1440×3200`、密度 560。旧端口 `38817` 未继续使用。

| 项目 | 结果 | 证据 |
|---|---|---|
| 设备连接 | 已通过 | `192.168.36.51:39677`，无线 ADB 在线 |
| 测试包 | 已安装并启动 | `com.kando.kandoApp.beta`，version `1.0.7`，versionCode `213`，target SDK `36`，安装使用 `adb install -r -d`，保留应用数据 |
| 引导页 | 通过 | 第 1、2、3 页、`NEXT`、`LET’S START`、`Skip and start now` 均可操作，底部操作区没有被系统导航区域遮挡 |
| Home／Search／Collection／Profile | 通过 | 页面内容、底部导航和主要操作控件可见；Profile 滚动到底部后 `Version 1.0.7` 完整位于底部导航上方 |
| 更新提示 | 通过 | 已点击 `LATER` 关闭提示，没有触发更新安装 |
| Scan 预览 | 通过 | 相机权限已授权，顶部控件、取景框、`ALIGN CARD HERE`、Gallery、拍摄和 Done 控件均可见，截图见 `test-artifacts/android-edge-to-edge-20261119/xiaomi/scan-preview.png` |
| Scan 横屏请求 | 通过 | 通过 `wm user-rotation lock 1` 请求 `ROTATION_90` 时，应用仍为 `mCurrentAppOrientation=SCREEN_ORIENTATION_PORTRAIT`、`mRotation=0`；释放系统旋转锁定后仍保持竖屏 |
| 退出 Scan | 通过 | 点击 `Close Scan` 返回 Home，前台窗口为 `MainActivity`，退出后仍为 `mCurrentAppOrientation=SCREEN_ORIENTATION_PORTRAIT`、`mRotation=0`，截图见 `test-artifacts/android-edge-to-edge-20261119/xiaomi/scan-exit.png` |
| 应用日志 | 通过 | 按应用 PID 过滤 logcat，未发现 `FATAL EXCEPTION`、`AndroidRuntime`、`E/flutter`、`FlutterError`、`Unhandled Exception` 或 `PlatformException` |

小米相机预览期间出现过厂商相机 HAL 的 `FrameInsert`、`CameraUnavailable` 等警告，但预览正常显示，未发现应用自身崩溃或 Flutter 异常。UI 层级文件与截图均保存在 `test-artifacts/android-edge-to-edge-20261119/xiaomi/`。本次没有清除应用数据，没有触发拍摄、识别提交、收藏、心愿单、账户删除或购买操作。

## 小米设备验证边界

本次真实设备为 Android 16/API 36，可验证 Android 15 之后的无边框行为和当前 target SDK 36 的窗口处理，但不能替代 Android 15/API 35 实体设备专项验收。小米设备也没有执行真实卡片识别、后端写入、账号登录或支付流程。
