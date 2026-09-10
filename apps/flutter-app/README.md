# Kando App

## Environments

`APP_ENV` selects the API and Mixpanel projects together. The supported values
are `test` and `production`; the default is `production` so an unconfigured
build stays aligned with the default production app identity. Test builds must
explicitly load `config/test.json`.

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

## 扫描平台与协议

当前 App 的扫描链路支持 iOS 16+ 和 Android API 24+。端侧 RTMDet-Ins 检测与 PE-Core-T16 生成 512 维向量，向 Workers API 提交 `vector` 和矫正后的卡面图片；主 API 通过 `VECTOR_RECOGNITION` 调用内部检索服务。旧 `r/g/b` pHash 请求已退役，Flutter Web 暂不支持扫描。实现与资源说明见[扫描识别链路](../../docs/releases/v1.1.0/01-flows/scan-recognition.md)。

## iOS simulator

Google ML Kit's iOS binaries do not support arm64 simulators. Run the test
environment with the simulator wrapper so local card-number OCR is disabled.
Scanning still requires on-device Core ML models and sends a vector to the API;
this wrapper does not provide a pHash or image-only recognition fallback:

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
