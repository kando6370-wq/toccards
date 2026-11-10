# Android 与 iOS 版本管理

本节区分应用内升级规则和打包构建号。Android 复用现有版本门禁及数据结构，iOS 的
规则、接口、商店地址、版本比较和发布脚本保持原有行为；不新增数据库表或 migration。

## 应用内升级规则

后台“版本管理”分别管理 iOS 与 Android（Google Play）的最低支持版本、建议版本、
强制更新、下载地址及启停状态。界面将原 `Google` 显示为 Android（Google Play）；
保存和启停仍使用原 `Google` wire 值，不迁移旧配置。

现有 V1 协议和存储键保持兼容：

| 项目 | iOS | Android |
|---|---|---|
| Flutter 公共配置查询 | `platform=ios` | `platform=google` |
| 新增兼容查询别名 | — | `platform=android`，与 `google` 返回同一规则 |
| Admin 平台值 | `iOS` | `Google` |
| PostgreSQL app_config key | `admin.app_version.<environment>.ios` | `admin.app_version.<environment>.google` |

environment 由可信服务端的 `APP_ENVIRONMENT` 决定，分为 `development` 和 `production`，
不能通过请求参数切换。省略或未知 platform 继续保留 iOS 的既有缺省行为。
保存 Android 规则不会更新 iOS，也不会将 dev 规则复制到 prod。

两端继续执行同一版本策略：

- 只比较 `major.minor.patch`；Android versionCode、iOS build number 和 `+build` 不参与。
- 当前版本达到建议版本时不弹窗。
- `force_update=true` 且当前版本低于最低支持版本时必须更新。
- 达到最低支持版本但低于建议版本时允许稍后更新；推荐提示按版本在当前进程内去重。
- 首次进入 Home 的配置失败仍显示重试，不伪装成无需更新；已确认的强更保留阻断，
  回到前台和再次进入 Home 会重新核对。
- Android 的 INSTALL 打开所选 Android 规则中的地址，iOS 保留原 App Store 地址。
  打开下载地址失败时保留提示并允许重试，不让强更绕过门禁。

各环境需要由运营保存明确规则。停用规则可以保留空下载地址；启用前必须填写真实可达的
HTTP(S) 下载页／商店地址，且建议版本不低于最低版本。缺失或损坏的已选规则仍返回 503，
不回退到另一平台或环境。仅打包新制品不会自动提高最低版本、开启强更或发布后台规则。

2026-11-09 的 dev 只读检查显示 Android 更新提示处于停用状态，保存的地址仍为
YouTube 占位链接，不能直接作为 Card AI 更新入口。本轮不自动修改该运行配置。
实际启用前应确认目标版本、兼容下限、强更开关和真实下载地址；正式商店版本尚不可下载时
不得用强更将用户导向不可用页面。

## Android 自动打包与保存

入口、参数和环境注入见 [Flutter Android 发布说明](../../../../apps/flutter-app/README.md#android-版本与制品管理)。
`tool/release_android.py` 使用 Python 标准库，Test 构建 APK，Production 默认构建 AAB。
正式配置仍由独立打包环境注入，不读取本机既有正式签名或将凭据写入源码。

版本选择以共享 `pubspec.yaml` 和同 applicationId 已保存的 Android 制品为依据，
包括旧手工 Android 交付目录；下一个构建号必须高于两者，且不超过 Android 的
`2100000000` 上限。营销版本由发布计划决定，脚本不会自动递增 patch。

成功顺序为：验证环境与工具链 → 构建 → 核对身份、版本、签名及原生库 →
复制并校验制品哈希 → 完整归档 → 写回 pubspec 构建号。
制品必须满足 minSdk 24、targetSdk 至少 36，最终签名摘要与批准证书一致。
Test 默认使用已登记 OAuth 的项目测试证书；Production 必须显式提供经 Console
核实的 Upload SHA-256，不以“签名存在”替代正确上传身份，也不将 Upload 证书
混同 Google Play 最终分发证书。
构建、校验或保存失败不提前修改版本号；其他流程修改了 pubspec 时明确失败并保留其值。
共享版本文件仍服务两端；不在同一工作区同时运行 iOS 和 Android 发布流程。

Android 制品使用 `<applicationId>/Android/` 子目录，与同名 iOS Bundle 的 IPA 隔离。
Test 保留 3 版、Production 保留 7 版，超额受管版本移至该目录的 `.Recovery`，不永久删除。
只处理受管 Android 目录，不移动 iOS 制品、其他环境、历史手工目录或符号链接。
构建信息保留 Git SHA、dirty 状态、SDK、校验结果和文件哈希；不含签名密码、私钥或 Token。
正式 AAB 的独立打包、Play 分发签名、真机更新及安装仍需分别验收，不能由本地 APK 推定。

官方工具与约束依据：[Flutter Android 发布](https://docs.flutter.dev/deployment/android)、
[Android 版本号](https://developer.android.com/studio/publish/versioning)、
[bundletool](https://developer.android.com/tools/bundletool)。

## 验证边界

2026-11-09 已用来源 `ff35c80ac5030220d1fdba55e405469f40cabf03` 加本轮未提交修改、
锁定 Flutter `3.47.9`、Dart `3.13.7`、JDK `21.0.13+9` 实际执行
`python tool/release_android.py --env test`。脚本扫描到 `com.kando.kandoApp.beta`
历史最高 Android 构建号为 203，在共享 `pubspec.yaml` 的 194 基础上选择 204，
构建成功并在校验后写回 `1.0.7+204`。交付目录为
`D:/Downloads/CardAI-Packages/com.kando.kandoApp.beta/Android/CardAI-Test-1.0.7-204/`，
APK 252,665,220 字节，SHA-256 `5b8ad76110963a271e7d0da61f7591357a56152402e695ae196f2fb5f780dd6e`。
APK 包名、versionCode 204、Debug 测试证书、minSdk 24、targetSdk 36、28 个原生库、
19 个 64 位库、ELF／ZIP 16 KB 对齐和已批准测试证书摘要均通过；复制哈希一致。
Python 制品管理测试 23 项通过；版本规则与 Admin／Workers／Flutter 定向回归在同一任务中
通过。该包未安装到设备，Android 真实升级弹窗和 Play 登录仍待真机验收。

本地实际通过不代表已启用 dev/prod Google 规则。2026-11-09 dev 的 Google 更新规则仍停用，
保存的旧地址为占位地址；在产品确认真实版本、最低版本、强更开关和 Play 下载页前，
不执行远端规则写入或把占位地址提供给用户。

未执行 API／Admin 远程部署、后台规则启用、Google Play 上传或 iOS 构建时不得写成通过。
