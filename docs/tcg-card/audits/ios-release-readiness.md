# iOS 上架就绪审计

## 0. 审计结论

- 审计日期：2026-07-16。
- 目标：Card AI 1.0.0 首次 iPhone 上架，不包含 Android 和订阅。
- 结论：`NO-GO`。应用代码已经具备无签名 iOS Release 构建条件，但 App Store Connect 记录、签名、原生截图和 TestFlight 真机验收尚未完成。
- 完成口径：仅以代码、真实生产接口、CI、平台回执或真机结果为证据，不采信进度文档中的完成标记。

## 1. 代码与生产已验证

| 项目 | 当前结果 | 证据 |
|---|---|---|
| 名称与版本 | `Card AI`，`1.0.0+1` | `Info.plist`、`pubspec.yaml` |
| Bundle ID | `com.kando.kandoApp` | Xcode Debug/Profile/Release 配置 |
| 首发设备 | 仅 iPhone，竖屏，iOS 13.0+ | `TARGETED_DEVICE_FAMILY=1`、`Info.plist` |
| 相机与相册权限 | 已提供用途说明 | `NSCameraUsageDescription`、`NSPhotoLibraryUsageDescription` |
| Apple 登录 | entitlement、Xcode capability、Workers 受众均为真实配置 | `Runner.entitlements`、`project.pbxproj`、`APPLE_CLIENT_ID` |
| Google 登录 | iOS Client ID、反向 URL Scheme 与 Workers 受众一致；接口使用 `id_token` | `Info.plist`、`oauth_authorizer.dart`、`POST /auth/oauth/google/callback` |
| 出口合规 | 声明不使用非豁免加密 | `ITSAppUsesNonExemptEncryption=false` |
| App Icon | 19 个声明槽位完整；实际尺寸匹配；1024 图标为 RGB 且无透明通道 | 像素检查、`Contents.json` |
| Launch Screen | storyboard 与 1x/2x/3x 启动图片齐全 | `LaunchScreen.storyboard`、`LaunchImage.imageset` |
| 隐私清单 | Flutter 引擎声明 Required Reason API；当前 iOS 插件自带隐私清单；App 未直接调用对应原生 API | Flutter 3.35.5 与已解析插件包 |
| Ruby / CocoaPods | `Gemfile.lock` 与 `Podfile.lock` 已由 macOS CI 生成并固定；Bundler 4.0.15、CocoaPods 1.17.0；Debug/Release/Profile 均显式包含 Pods 配置 | GitHub Actions run `29507734068` |
| App Review 材料 | 已准备无需 Demo 账号的审核说明；主分类 `Reference`、次分类 `Utilities`；旧截图自动上传已禁用 | `fastlane/metadata/review_information/notes.txt`、`Fastfile` |
| 法律与支持页 | Terms、Privacy、Support 均为公开生产页面 | `https://api.tcgcard.fun/api/v1/legal/*` |
| 扫描图片生命周期 | 私有 R2 卡图最多保留 30 天；每日 Cron 自动删除，到期 D1 指针清空 | Worker `d5710560-...`、Cron `17 3 * * *` |
| iOS 无签名构建 | Xcode 16.4 下 Ruby 依赖安装、`pod install`、两份 lockfile 无漂移检查与 `flutter build ios --release --no-codesign` 全部成功 | GitHub Actions run `29507734068` |

当前生产 `/app-config`：

```json
{
  "upgrade_prompt": null,
  "app_store_url": null,
  "terms_url": "https://api.tcgcard.fun/api/v1/legal/terms",
  "privacy_url": "https://api.tcgcard.fun/api/v1/legal/privacy"
}
```

`app_store_url=null` 是真实上线阻断：Profile 分享必然失败，评分回退页与后续升级跳转不可用。

## 2. 已修复的上线风险

| 风险 | 处理结果 |
|---|---|
| Google ID Token 被伪装成授权码和无效 redirect URI | Flutter 与 Workers 已统一为 `id_token` 真实契约 |
| iOS Client ID 同时被当作 Server Client ID | iOS SDK 只配置 iOS Client ID；Workers 验证同一受众 |
| R2 扫描图片无明确保留期 | 固定为 30 天并部署每日清理任务；隐私政策同步 |
| Runner 自定义 xcconfig 未包含 CocoaPods 配置 | Debug/Release/Profile 分别包含对应 Pods 配置；CI 对警告和 lockfile 漂移设为失败 |
| 商店描述声称只在设备端处理图片 | 已说明裁剪卡图上传、用途和 30 天上限 |
| Fastlane 会上传业务整改前的旧截图 | `metadata` lane 已设置 `skip_screenshots: true` |

## 3. 仓库内仍需 Mac 完成

| 优先级 | 项目 | 验收证据 |
|---|---|---|
| P0 | 设置真实 `DEVELOPMENT_TEAM`，确认 Automatic Signing、证书、Provisioning Profile 和 Apple Sign In capability | Xcode Signing 页面无错误；Archive 签名成功 |
| P0 | 执行带签名 Archive 并上传 App Store Connect | Organizer 上传回执或 TestFlight build |
| P0 | 在 iOS Simulator/真机重拍商店截图 | 截图展示当前 HOME 真实历史曲线、当前 Collection/Profile/Scan，不含 Mock 或矛盾数值 |
| P0 | TestFlight 真机验收 Apple/Google 登录、相机、相册、分享、评分、协议页和账号删除 | 每条流程的通过记录 |
| P1 | 在 macOS 执行 `bundle exec fastlane ios metadata` 上传 | Fastlane 上传回执；当前缺少 App Store Connect 凭据 |

仓库现有 `fastlane/screenshots/en-US` 五张截图不能直接提交。它们生成于 HOME、Collection 最终真实接口整改之前；HOME 图中 `$9.67` 组合总值与 `$45212` 曲线浮层明显矛盾，而且没有当前 Scan 画面。

## 4. 需要平台权限完成

| 优先级 | 平台事项 | 当前阻断 |
|---|---|---|
| P0 | 在 Apple Developer 注册 `com.kando.kandoApp` 并启用 Sign in with Apple | 仓库无法证明开发者后台状态 |
| P0 | 在 App Store Connect 创建 Card AI 应用记录 | 尚无真实数字 App ID，因此不能生成 App Store URL |
| P0 | 将真实 `https://apps.apple.com/app/id<APP_ID>` 写入 D1 `app_config.app_store_url` | 当前生产值为 `null` |
| P0 | 完成 App Privacy、年龄分级、版权和审核联系人 | 分类与审核说明已准备；Fastlane 文件不能替代 App Store Connect 问卷 |
| P0 | 确认 Google Cloud iOS OAuth 客户端绑定 `com.kando.kandoApp` | 代码只能验证 ID 一致，不能读取 Google Cloud 控制台的客户端类型与 Bundle 绑定 |
| P1 | 配置 App Store Connect API Key 或受控 Apple ID/Team ID | `Appfile` 当前仅包含 Bundle ID |

## 5. App Privacy 申报草案

以下是根据真实代码与隐私政策得到的申报输入，提交前仍须由产品/法务在 App Store Connect 最终确认：

| 数据类别 | 是否关联身份 | 用途 |
|---|---|---|
| Email Address | 是 | 账号、登录、客服 |
| User ID / Device ID | 是 | 用户或游客所有权、会话和安全 |
| Photos or Videos | 是 | 卡牌识别、扫描记录、客服和识别质量审计；图片最多保留 30 天 |
| Other User Content | 是 | Portfolio、Wishlist、评级、购买值、备注和反馈 |
| Diagnostics / Other Data | 需最终确认 | 网络、安全事件与故障诊断 |

- 不用于第三方广告。
- 不出售个人信息。
- 当前实现不做跨 App/网站跟踪，Tracking 应为 No。
- 用户可在 App 内删除账号；删除流程同时删除其 R2 扫描图片。

## 6. 验证记录

2026-07-16 本轮验证：

- Flutter：332 项通过，1 项明确跳过；`flutter analyze` 无问题。
- Workers：238 项通过；TypeScript 类型检查与 Wrangler dry-run 通过。
- GitHub macOS iOS CI：run `29507734068` 在提交 `15d554d` 上成功，覆盖 Xcode 16.4、Bundler 4.0.15、CocoaPods 1.17.0、`Gemfile.lock`/`Podfile.lock` 无漂移检查与无签名 Release 构建。
- Cloudflare：Google 无效 `id_token` 返回 `422 VALIDATION_ERROR`；30 天前仍带图片指针的生产记录计数为 0。
- 图标：全部 PNG 尺寸匹配资产声明，1024 图标无 alpha。
- 未执行：Xcode Archive、签名、TestFlight、真机 OAuth/评分/分享/权限、Fastlane 上传。

## 7. 最短上架路径

1. 在 Apple Developer 与 App Store Connect 创建并绑定 `com.kando.kandoApp`，取得数字 App ID。
2. 立即写入并验证生产 `app_store_url`，再验证 Profile Score/Share。
3. 在 Mac 设置 Team 与签名，确认 `pod install` 不改写 lockfile，完成 Archive 上传。
4. 用目标 iPhone Simulator/真机基于当前生产数据重拍截图，并补齐 App Privacy、年龄分级、版权与审核联系人。
5. TestFlight 真机完整跑通登录、Scan、Collection、Profile 和删除账号后再提交审核。

在上述 P0 全部关闭前，不得宣称“iOS 已可上架”或“目标完成”。
