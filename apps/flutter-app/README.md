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
configuration in `ios/Runner/Firebase/test`. Production keeps
`com.cardai.tcg` and its separate Firebase configuration.

## iOS simulator

Google ML Kit's iOS binaries do not support arm64 simulators. Run the test
environment with the simulator wrapper so local card-number OCR is disabled and
the scan request falls back to server recognition:

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
# 构建并验证测试环境的 IPA（不安装、不上传）
./tool/release_ios.sh --env test

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
must be greater than the current value in `pubspec.yaml`. Device installation
uses a `release-testing` export signed with Apple Distribution; the App Store
IPA remains separately signed for App Store Connect. No device model or UDID is
hardcoded; pass any available selector shown by `--list-devices` (quote device
names that contain spaces).

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
