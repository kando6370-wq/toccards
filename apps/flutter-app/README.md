# Kando App

## Environments

`APP_ENV` selects the API and Mixpanel projects together. The supported values
are `test` and `production`; these map to the current business environments
`dev` (Linux) and `prod` (Cloudflare), respectively. The default is
`test` so an unconfigured local build uses the test API and isolated Android
identity. Test builds must explicitly load `config/test.json`; the retired
Cloudflare dev API is not a build target.

既有 `test` 环境现默认请求内网 Linux `http://192.168.50.201:8080/api/v1`，
`production` 继续请求 `https://api.tcgcard.fun/api/v1`。登录、目录、收藏、扫描、
汇率和版本配置共用该环境入口。测试设备需要能访问此局域网；构建成功不代表
Linux 新后端已部署或手机链路已验收。

测试分享固定使用 `http://192.168.50.201:8080/share/cards`，避免复制来的数据库
分享配置把测试用户带到生产环境；生产分享继续优先采用服务端配置。
目录卡牌图片仍使用 `https://image.tcgcard.fun`，不属于本次 API 入口迁移。

## Network transport

移动端 API、运行时配置、分享缩略图和目录图片共用一个应用级原生连接池。
正式 `test` / `production` 配置均固定 `APP_HTTP_TRANSPORT=native`：iOS 使用
`URLSession`，可协商 HTTP/2，并在 HTTPS 服务通过 `Alt-Svc` 宣告支持时使用
HTTP/3；Android 使用 embedded Cronet，并显式启用 HTTP/2 和 QUIC。协议由客户端、
系统和服务端共同协商，不保证每个请求固定使用 HTTP/3，协商失败会正常降级。

Android 仅在 Cronet provider 明确不可用时按进程回退到 Dart IO transport；连接、
TLS、超时和响应错误不会触发换协议自动重试，避免重复提交扫描、收藏或购买同步。
诊断或紧急回退构建可将 `APP_HTTP_TRANSPORT` 设为 `io`；正式配置校验拒绝该值。
扫描继续使用已有 25 秒整体 Deadline 和 `CancelToken`，Native transport 下不再叠加
Adapter 级 10 秒响应头超时。test API 是内网明文 HTTP，只能验证功能兼容，不能
用于验收 HTTP/2 或 HTTP/3；协议验收必须使用支持对应协议的 HTTPS 服务和真机。

From the repository root, run the web app with:

```bash
pnpm app:chrome:dev
pnpm app:chrome:prod
```

Build a TestFlight package against test services with:

```bash
flutter build ipa --release --flavor=test --dart-define-from-file=config/test.json
```

Build an App Store package against production services with:

```bash
flutter build ipa --release --dart-define-from-file=config/production.json
```

Run these `flutter build` commands from `apps/flutter-app`.

The iOS test flavor uses Bundle ID `com.kando.kandoApp.beta` and the Firebase
configuration in `ios/Runner/Firebase/test`. Pgyer and device-installation
packages for that Bundle ID must use App Attest `development`. Both values are
validated against the final Development-signed internal IPA rather than
inferred from Xcode project settings. Other Bundle IDs do not currently have a
fixed App Attest rule. Production keeps `com.cardai.tcg` and its separate
Firebase configuration.

测试 flavor 的 Debug/Profile/Release 三个配置使用 `ios/Runner/Info-test.plist`，
只为 `192.168.50.201` 设置 HTTP ATS 例外并声明局域网用途；其余 plist 内容
与生产 `Info.plist` 保持一致。iOS 17+ 使用 IP exception，iOS 16 按系统对 IP
直连的规则处理。首次访问局域网时需允许系统权限；iOS 签名包仍需在 macOS 构建
后核验，不能仅凭源码或 Windows 测试认定权限和 App Attest 已生效。

Android 沿用 `--dart-define-from-file=config/test.json` 选择测试环境，无需新增
flavor。Gradle 从同一 `APP_ENV=test` 编译参数选择网络策略，只为该 IP 允许 HTTP；
未配置环境默认使用测试 API 和 application ID `com.kando.kandoApp.beta`。
该字符串与 iOS 测试 Bundle ID 相同，但 Android 的 Firebase App、OAuth client、
签名和安装数据仍是独立平台资源，不复用 iOS 配置。`config/test.json` 提供 Android
测试使用的 Web server client ID；Android OAuth client 另按该包名和测试签名登记。
原 `dev.kando.cardvault.sandbox.a1aa3e` 安装的登录态及本地数据不会自动迁移到新包。
可构建本机测试包：

```bash
flutter build apk --debug --no-pub --dart-define-from-file=config/test.json
```

Debug 首次构建会使用当前 JDK 的 `keytool` 在仓库忽略目录
`.dart_tool/android-test-signing/` 创建本项目专用测试证书；固定 `android`
密码仅用于 Debug。该流程不会读取或删除全机 Debug keystore、正式 JKS 或
`key.properties`。

Android production 构建必须在独立打包环境显式提供
`ANDROID_APPLICATION_ID`、`ANDROID_KEYSTORE_PATH`、`ANDROID_KEY_ALIAS`、
`ANDROID_KEY_PASSWORD`、`ANDROID_STORE_PASSWORD`，并通过 dart-define 提供
Google server client ID 和 Play cloud project number。Firebase 使用
`ANDROID_FIREBASE_CONFIG_PATH` 指向打包机外部的 `google-services.json`；
配置存在时才应用 Google Services 与 Crashlytics Gradle 插件。
缺少任一正式配置时构建或运行会显式失败；本机测试构建不会读取仓库旁的
`key.properties` 或既有 keystore，也不提交正式 `google-services.json`。

## 扫描平台与协议

当前扫描链路支持 iOS 16+ 和 Android API 24+。端侧 RTMDet-Ins 检测并矫正卡面，随后并行计算 RGB 分通道 pHash 与 ML Kit OCR；Latin 与 Japanese 识别器对同一卡面并行执行。Latin 文本沿用既有 Unicode 兼容规范化、去附加符号、大小写及空白／分隔符规则；Japanese 仅保留 Han／Hiragana／Katakana／`ー`，少于 3 个日文字符时置空，最终按 Latin 在前、Japanese 在后合并为单个 `ocr_text`。

当前 App 向原 `/api/v1/scan/recognize` 提交 JPEG、`r/g/b`、`card_type` 以及成功取得时的 `ocr_text`；OCR 失败时省略该字段并继续哈希检索，成功但无文本时保留空字符串。当前源码不再构建旧向量识别，服务端仍在同一路径接受线上 App 1.0.4+ 的 `vector` 请求。Flutter Web 暂不支持扫描。实现与兼容边界见[当前扫描识别链路](../../docs/releases/v1.1.3/01-flows/scan-recognition.md)。

## iOS simulator

Run the test environment with the simulator wrapper. Scanning still requires
on-device card detection and sends RGB pHashes to the API; OCR remains an
optional enhancement and this wrapper does not provide an image-only
recognition fallback:

```bash
./tool/run_ios_simulator.sh -d <simulator-udid>
```

This override only applies to that simulator process. iOS device, release, and
Android builds continue to include ML Kit. When the simulator process exits,
the wrapper restores the standard device Pods automatically.

## iOS release script

From `apps/flutter-app`, build and validate a clean production App Store IPA:

```bash
# 构建并验证正式环境的 App Store IPA（不安装、不上传）
./tool/release_ios.sh
```

The script increments the current build number automatically. Installation and
upload are opt-in. Production is the default environment; use `--env
test` to select the test API, Xcode scheme, and Firebase configuration:

Singular SDK credentials are loaded at runtime from the selected environment's
public `/app-config` endpoint. Release JSON files contain only non-sensitive
build configuration such as the environment and subscription product IDs.

```bash
# 构建并验证测试环境的 App Store IPA 和蒲公英内部测试 IPA（不安装、不上传）
./tool/release_ios.sh --env test

# 显式构建蒲公英内部测试 IPA；仅支持测试 Bundle ID
./tool/release_ios.sh --env test --pgy

# 列出当前已配对且可用的 Apple 设备
./tool/release_ios.sh --list-devices

# 构建正式环境 IPA，并安装到指定设备
./tool/release_ios.sh --install ABBA554A-D3A7-5651-827D-3754EB085751

# 构建正式环境 IPA，并上传到 App Store Connect
./tool/release_ios.sh --upload

# 构建测试环境 IPA，并安装到指定设备
./tool/release_ios.sh --env test --install 00008101-00111DCE3668001E

# 构建正式环境 IPA，安装到指定设备，并上传到 App Store Connect
./tool/release_ios.sh --env production --install 00008101-00111DCE3668001E --upload
```

Use `--build-number N` to choose an explicit build number. The selected number
must be greater than the current value in `pubspec.yaml`. Test builds always
produce `build/ios/test-internal-development/Card AI Test.ipa` for Pgyer and
device installation. That IPA preserves the archived Apple Development
signature and must contain Bundle ID `com.kando.kandoApp.beta` with App Attest
`development`; the script fails if either value differs. Production device
installation continues to use a `release-testing` export signed with Apple
Distribution. The App Store IPA remains separately signed for App Store
Connect. No device model or UDID is hardcoded; pass any available selector
shown by `--list-devices` (quote device names that contain spaces).

### IPA 与符号文件保存

脚本在包校验通过后、安装或上传前，自动保存到 `~/Downloads/CardAI-Packages/`，
专用目录下使用 Bundle ID 作为文件夹名称：测试包为 `com.kando.kandoApp.beta/`，
正式包为 `com.cardai.tcg/`。每个 Bundle ID 目录内再按版本建目录，例如
`com.kando.kandoApp.beta/CardAI-Test-1.0.2-134/`，目录内保存内部安装 IPA
和 `dSYMs.zip`；正式包目录名为 `CardAI-Prod-<版本>-<构建号>/`，保存
App Store IPA 和 `dSYMs.zip`，指定真机安装时还保存 `Card AI Device.ipa`。

测试包保留最近成功保存的 **3 个版本**，正式包保留 **7 个版本**，各自按保存时间排序。
同一包新增版本保存并校验成功后，将超出数量的最早版本移入废纸篓，
可在清空废纸篓前恢复；另一环境的版本不受影响。
保存失败不会清理旧版本，同名版本拒绝覆盖；无关目录和符号链接不参与清理。
此规则仅管理上述专用目录内的 IPA/dSYM，不清理 Xcode Archives。
保存步骤使用 macOS 的 `ditto` 和 Python 3 标准库，不需要额外安装 Python 包。

## Android 版本与制品管理

Android 使用 Python 3 标准库发布入口，不改变现有 iOS 发布脚本：

脚本先执行 `flutter pub get --enforce-lockfile`，按锁文件恢复依赖并重新生成原生插件注册文件，再分析和构建，避免干净检出或清理生成物后打出缺少插件的 APK。

```powershell
# 先查看将使用的环境、包名、版本和历史最高构建号；不构建、不改版本文件
python tool/release_android.py --env test --dry-run

# 构建、验证并保存可安装的 dev Debug APK
python tool/release_android.py --env test

# 独立正式打包环境：外部注入身份、签名、Firebase 与 Google 配置后构建 AAB
python tool/release_android.py --env production --bundletool /private/tools/bundletool.jar
```

默认使用 PATH 中的 Flutter；可通过 `--flutter` 选择 Flutter 3.47.9／Dart 3.13.7
或更新的兼容 SDK，通过 `--jdk` 选择安全修补的 JDK 21.0.13+9。
显式 JDK 仅在该次流程中临时设置，成功或失败后都恢复原 Flutter 设置；
同时检查 Flutter 与 Gradle 实际选择的 JVM。Gradle 默认使用进程内的 2 GiB heap、
单 worker 设置，可通过已有 `GRADLE_OPTS` 调整，不改写 `gradle.properties`。

脚本从共享 `pubspec.yaml` 的三段版本号读取营销版本，并选择高于当前构建号和
该 Android 包所有已保存构建号的下一个值。旧的 `*-Android-*` 手工交付目录也纳入
查找，避免已有 Android 203 包时因 pubspec 仍是 194 而退回 195。
`--build-number N` 可显式指定更大的值；不自动改变营销版本，不并行运行同一工作区的
iOS／Android 发布。只有构建、签名／包名／版本／原生库校验及完整保存都成功后，
才更新共享 pubspec 的构建号；失败不提前消耗构建号，也不会覆盖其他流程已经修改的版本。

Test 默认构建 Debug APK；production 默认构建 Release AAB，也可指定 `--artifact apk`。
正式模式要求干净的批准源码、外部正式包名、上传签名和 Firebase 配置，以及
`GOOGLE_SERVER_CLIENT_ID`／`ANDROID_PLAY_CLOUD_PROJECT_NUMBER`。
同时要求从 Play Console 核实的 Upload 证书 SHA-256，使用
`ANDROID_UPLOAD_CERTIFICATE_SHA256` 或 `--expected-certificate-sha256` 提供，
并与最终制品签名比较。Test 默认核对已登记 OAuth 的本项目测试证书；更换测试签名后，
须先登记对应 Android OAuth，再通过 `ANDROID_TEST_CERTIFICATE_SHA256` 或同一参数
明确提供新的批准摘要，不能只因“存在签名”就视为配置匹配。
公开编译值可在对应配置文件或进程环境提供；`--config`／`RELEASE_ENV_CONFIG`
可选择独立打包环境的配置文件。AAB 校验另外要求 `--bundletool` 或 `BUNDLETOOL_JAR`。
没有正式配置时明确失败，不回退到测试包名或测试签名。APK 校验签名与 ZIP／64 位
ELF 的 16 KB 对齐；AAB 校验 bundletool、JAR 签名、manifest 和 64 位 ELF。
两种制品均核对 minSdk 24、targetSdk 至少 36，以及最终证书与批准摘要一致。
这些本地校验不能替代 Play 处理后的分发签名、真实安装或商店验收。

制品默认保存到系统 Downloads 的 `CardAI-Packages/<applicationId>/Android/`，
可通过 `--artifacts-root` 指定现有交付根目录；例如本机历史包位于
`D:/Downloads/CardAI-Packages`，应继续使用该根目录。每版目录包含 APK／AAB、
可用的 Release symbols／mapping、`build-info.json` 和 `SHA256SUMS.txt`。
Android Test 保留最近 3 版、Production 保留 7 版，完整保存后才将超额受管版本移至
`Android/.Recovery/`，可人工恢复，不永久删除。iOS 同包名 IPA、历史手工 Android
目录、其他环境与无关目录均不参与清理。同名目录拒绝覆盖，复制哈希不匹配则失败。
脚本不安装设备、不上传商店、不修改后台版本规则，也不提交或推送 Git。

应用内升级与构建号是两套机制：后台最低／建议版本只比较三段营销版本，忽略 `+build`；
需要对用户提示新版本时，应发布新的营销版本并单独配置 Android 更新规则。
跨端接口与实际验证见[双端版本管理](../../docs/releases/v1.1.4/03-data-api/app-version-management.md)。

## Chrome with production services

From the repository root, run:

```bash
pnpm app:chrome:prod
```

This starts Flutter Web at `http://localhost:3000` and configures every app API client to use:

```text
https://api.tcgcard.fun/api/v1
```

The browser does not connect directly to PostgreSQL or KV. Production data access remains behind the deployed Worker API, including its authentication and authorization checks.
