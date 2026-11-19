# Android R8 与资源缩减优化检查（2026-11-19）

## 结论

本次处理覆盖 Google Play 提示的两项 Android 发布优化问题。

- Release 构建已启用 R8 代码压缩和资源缩减。
- Android Gradle Plugin 已升级到 9.0.1，满足 9.0 或更高版本要求。
- Gradle Wrapper 已配套升级到 9.1.0，Kotlin Gradle Plugin 已升级到 2.3.20。
- Release AAB 已在本地成功构建，R8 mapping、资源使用和资源缩减报告均已生成。

## 变更范围

| 项目 | 修改前 | 修改后 |
|---|---|---|
| Android Gradle Plugin | 8.13.2 | 9.0.1 |
| Gradle Wrapper | 8.14.6 | 9.1.0 |
| Kotlin Gradle Plugin | 2.2.20 | 2.3.20 |
| Release 代码压缩 | 未启用 | `isMinifyEnabled = true` |
| Release 资源缩减 | 未启用 | `isShrinkResources = true` |

涉及文件如下。

- `apps/flutter-app/android/app/build.gradle.kts`
- `apps/flutter-app/android/settings.gradle.kts`
- `apps/flutter-app/android/gradle/wrapper/gradle-wrapper.properties`
- `apps/flutter-app/android/gradle.properties`

Release 构建继续使用 `proguard-android-optimize.txt` 和项目已有的 `proguard-rules.pro`。AGP 9 在 `isShrinkResources = true` 时使用优化型资源缩减，因此没有额外添加实验性或重复的 R8 配置项。

## AGP 9 兼容边界

本次保留 Flutter 迁移器已经加入的以下兼容配置。

- `android.newDsl=false`
- `android.builtInKotlin=false`
- `android.uniquePackageNames=false`

当前 Flutter 插件仍有主动应用 Kotlin Gradle Plugin 的依赖，暂未切换到 AGP 9 的内置 Kotlin 模式。Cronet 依赖中的 `cronet-api` 和 `cronet-shared` 仍使用相同的 `org.chromium.net` namespace，因此暂时关闭 AGP 9 的唯一包名检查。两项迁移均属于后续 Flutter 插件和依赖完成兼容后的清理工作，不影响本次 Release AAB 构建。

## 本地构建验证

执行目录为 `apps/flutter-app/android`。构建命令如下。

```powershell
.\gradlew.bat bundleRelease `
  --project-prop=kotlin.incremental=false `
  --no-daemon `
  --max-workers=2 `
  "-Dorg.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError"
```

验证结果如下。

| 检查 | 结果 |
|---|---|
| Gradle Release 构建 | `BUILD SUCCESSFUL` |
| Gradle 任务 | 925 actionable tasks，511 executed，414 up-to-date |
| R8 任务 | `:app:minifyReleaseWithR8` 已执行 |
| AAB 签名打包任务 | `:app:signReleaseBundle`、`:app:bundleRelease` 已执行 |
| AAB | `apps/flutter-app/build/app/outputs/bundle/release/app-release.aab` |
| AAB 大小 | 108,576,020 bytes |
| AAB SHA-256 | `D84592F6CF58BE5FFF598FAA908DE92AFD72508E1FAE6A8A8AA3088D05C43181` |

R8 输出目录为 `apps/flutter-app/build/app/outputs/mapping/release/`，已生成 `configuration.txt`、`mapping.prt`、`mapping.txt`、`resources.txt`、`seeds.txt` 和 `usage.txt`。AAB 结构检查包含 `base/resources.pb`、Android Manifest、1 个 DEX、27 个 native library 和 135 个 assets。

构建期间仅为解决本机 Kotlin 增量缓存跨盘路径问题临时传入 `kotlin.incremental=false`，并临时降低 Gradle worker 数和 JVM 内存参数。上述参数没有写入仓库配置。

## 发布边界

本次验证使用本地 test 环境的 Release 构建配置，没有读取或修改正式签名，没有上传 Google Play，也没有使用该 AAB 执行 Play 安装或真机回归。Android 业务代码、iOS 源码和 iOS 构建配置均未修改。

AGP 9 构建仍会报告 Flutter 插件、旧 DSL、非内置 Kotlin 和 Jetifier 相关过渡警告。它们没有阻止当前 AAB 构建成功，后续应在 Flutter 插件支持内置 Kotlin、Cronet 依赖完成 namespace 迁移后再清理对应兼容配置。

## 真机复测

测试时间为 2026-11-19 15:37–15:46（Asia/Shanghai）。

- `192.168.36.51:39677` 返回 Windows 10061，设备端拒绝连接。
- 已使用在线设备 `192.168.36.22:38991` 完成测试。设备为 HONOR YOK-AN10，Android 12，API 31，屏幕 1236×2676，密度 520。
- Release APK 使用项目专用测试签名 `.dart_tool/android-test-signing/cardvault-debug.keystore` 临时签名后安装。正式签名、正式密钥和 Play 发布配置未使用。
- 已安装包为 `com.kando.kandoApp.beta`，versionName `1.0.7`，versionCode `213`，target SDK `36`，APK 签名版本为 v3。
- 首页、Search、Collection、Profile 和 Scan 均可进入。Scan 的相机预览、TCG 选择、闪光灯、固定取景框、Gallery、拍摄和 Done 控件均可见，取景框没有被系统状态区域或底部导航区域遮挡。
- 退出 Scan 后返回主界面。应用的 requested orientation 为 `SCREEN_ORIENTATION_PORTRAIT`，显示服务回读的应用旋转为 `ROTATION_0`。
- 清空本轮 logcat 后回读，没有发现 `FATAL EXCEPTION`、`AndroidRuntime`、`E/flutter`、`FlutterError` 或未处理异常。

本轮未执行拍摄、识别提交、真实登录、收藏写入、购买、Play 安装或 Android 15/API 35 实体设备验收。API 31 真机结果用于确认当前 Release 代码的启动和基础页面行为，不能替代 Play 生产包及 Android 15 实体设备验收。
