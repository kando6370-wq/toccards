# Kando App

## Environments

`APP_ENV` selects the API and Mixpanel projects together. The supported values
are `test` and `production`; the default is `production` so an unconfigured
build stays aligned with the default production app identity. Test builds must
explicitly load `config/test.json`.

既有 `test` 环境现默认请求内网 Linux `http://192.168.50.201:8080/api/v1`，
`production` 继续请求 `https://api.tcgcard.fun/api/v1`。登录、目录、收藏、扫描、
汇率和版本配置共用该环境入口。测试设备需要能访问此局域网；构建成功不代表
Linux 新后端已部署或手机链路已验收。

测试分享固定使用 `http://192.168.50.201:8080/share/cards`，避免复制来的数据库
分享配置把测试用户带到生产环境；生产分享继续优先采用服务端配置。
目录卡牌图片仍使用 `https://image.tcgcard.fun`，不属于本次 API 入口迁移。

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
production 和未配置环境均使用禁止明文的默认策略。可分别构建验证：

```bash
flutter build apk --debug --no-pub --dart-define-from-file=config/test.json
flutter build apk --debug --no-pub --dart-define-from-file=config/production.json
```

## 扫描平台与协议

当前试验分支的扫描链路支持 iOS 16+ 和 Android API 24+。端侧 RTMDet-Ins 检测并矫正卡面，对矫正后的 RGB 分通道计算 pHash，向业务 API 提交 `r/g/b` 和 JPEG；业务 API 通过 `VECTOR_RECOGNITION` 适配器请求 `recognize.tcgcard.fun`。PE-Core-T16 不参与此试验的推理，模型资源尚未移除；Flutter Web 暂不支持扫描。实现与资源说明见[扫描识别链路](../../docs/releases/v1.1.0/01-flows/scan-recognition.md)。

## iOS simulator

Google ML Kit's iOS binaries do not support arm64 simulators. Run the test
environment with the simulator wrapper so local card-number OCR is disabled.
Scanning still requires on-device card detection and sends RGB pHashes to the API;
this wrapper does not provide an image-only recognition fallback:

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
