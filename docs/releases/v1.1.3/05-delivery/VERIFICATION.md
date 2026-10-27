# v1.1.3 实际验证记录

启用日期：2026-10-26（Asia/Shanghai）。

本文件只记录 v1.1.3 启用后的代码、配置、数据、构建、部署和业务验收结果。创建版本目录本身没有修改业务代码、数据库、远程配置或运行环境，也不构成新的验证通过。

当前运行基线见 [v1.1.2 生产收尾记录](../../v1.1.2/05-delivery/VERIFICATION.md#prod-app-1-0-6-monthly-admission-20261026)。以下记录只代表 v1.1.3 本地增量及实际执行的验证，不改变远端运行状态。

## iOS 测试环境内部安装包 1.0.6 (186)（2026-10-27）

- 构建输入：从构建前干净且与实时同名远端一致的 `codex/dev-1.0.7scan@83836efd003723d4715bc66d4e9a43f7a418adf0` 原样重打；该提交只归档 185 的版本号和验证记录，185 后没有业务源码或依赖变化。本分支不是 `origin/dev` 最新状态，本包只代表当前 `codex/dev-1.0.7scan`。脚本从 `1.0.6+185` 显式选择 `1.0.6 (186)`，dev health 返回 `{"status":"ok"}`；成功后仅将 `pubspec.yaml` 同步为 `1.0.6+186`。
- 工具链与依赖：使用 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1。构建前 `flutter pub get --enforce-lockfile`、脚本内依赖解析及完整 `flutter analyze` 均退出 0；根 `pubspec.lock` 与 iOS `Podfile.lock` SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有依赖锁更新。Swift Package Manager 与 ML Kit Apple Silicon iOS 26+ 模拟器提示同 185，本轮 CocoaPods、真机 Release Archive 和 IPA 导出成功，不把未来／模拟器兼容提示记为已解决。
- 环境与签名：最终内部 IPA 为 `com.kando.kandoApp.beta`、`1.0.6 (186)`、MinimumOSVersion 16.0；测试 API `http://192.168.50.201:8080/api/v1` 存在且生产 API 不存在。`GoogleService-Info.plist` 与仓库 test 文件逐字节一致，Firebase project 为 `card-ai---test`，生产 Firebase project／app ID／storage bucket 均不存在；生产 Google OAuth audience 仍是既有 Workers 验签合同例外，本轮未做真机 Google 登录。Runner 与 42 个 Framework 共 43 个 Mach-O 均通过严格签名校验，全部为 Apple Development `kancloud cq (578WZAD3DU)`、Team `B95U3272HR`；最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`。profile UUID `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。
- 符号：IPA 的 43 个唯一 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，missing／extra 均为 0；45 条 DWARF 中两组为 `cupertino_http` 与 `objective_c` 的重复 UUID 副本。逐 bundle `dwarfdump --verify` 为 44／45 通过；只有 `App.framework.dSYM` 退出 1，包含 169 次 Flutter AOT address range 错误及两条汇总。排除临时路径后，其输出与保存的 185 对应文件逐字节一致，确认不是 186 新增；UUID 覆盖完整，但仍不能写成全部 dSYM 深检通过。
- 制品与边界：`Card AI Test.ipa` 为 42,974,357 字节，SHA-256 `87f9fcd9dd32669eee58cfdda7bb0c218eda5779cdb2eb0f03b61c7773a57aca`；`dSYMs.zip` 为 63,896,975 字节，SHA-256 `b714c900b19f67c5d034dbd0d37b3a06082cb9523db7cd042d2853d398eb0c5e`。两份 ZIP 完整性通过，保存 IPA 与构建输出逐字节一致；独立展开比对确认 IPA 的 384 个文件及 dSYM 的 134 个文件均与当前 xcarchive 一致。制品位于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-186/`；完整保存后最旧的 183 已移入废纸篓，当前保留 184、185、186。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push；未重跑全量 Flutter 测试、扫描 Golden 或真机 OCR／pHash。

## iOS 测试环境内部安装包 1.0.6 (185)（2026-10-27）

- 构建输入：构建前本地与实时远端均为干净的 `codex/dev-1.0.7scan@32afefb521177b316f7280018e0083afbe866116`，包含年试用 SKU 及重新对齐的扫描页 Figma 样式。脚本从工程 `1.0.6+184` 显式选择 `1.0.6 (185)`；dev health 返回 `{"status":"ok"}`。成功构建后只将 `pubspec.yaml` 同步为 `1.0.6+185`。
- 工具链与失败处理：首次调用误用本机已升级的 Flutter 3.47.8／Dart 3.13.7，`pub get` 因 SDK 约束将 6 个传递依赖改为新版并由新迁移器改写两份 `analysis_options.yaml`，随后 `flutter analyze` 以 `unawaited_return_in_try_block` 退出 1；该轮没有生成 IPA，也没有更新版本。确认仓库 iOS 基线后，恢复全部工具生成变更及临时源码验证，使用独立的 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1 重跑。`flutter pub get --enforce-lockfile`、图片组件定向测试 3／3、独立全量 `flutter analyze --no-pub` 及发布脚本内的全量 analyze 均退出 0。脚本更新版本后回查又发现根锁文件呈现同一组 3.47.8 自动重解结果，已再次精确恢复；最终根 `pubspec.lock` 与 iOS `Podfile.lock` SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有项目依赖锁更新。
- 环境：最终内部 IPA 为 `com.kando.kandoApp.beta`，版本 `1.0.6 (185)`；测试 API `http://192.168.50.201:8080/api/v1` 存在，生产 API 不存在。内置 `GoogleService-Info.plist` 与仓库 test 文件逐字节一致，Firebase project 为 `card-ai---test`，生产 Firebase project／app ID／storage bucket 均不存在。Google OAuth audience 按既有 Workers 验签合同继续固定使用生产 Client ID，183／184／185 均相同，属于已知例外，不代表 Firebase SDK 串到生产；本轮未做真机 Google 登录验收。
- 构建提示：`google_mlkit_commons`、`google_mlkit_text_recognition`、`sign_in_with_apple` 仍未支持 iOS Swift Package Manager；ML Kit 相关 Pod 仍提示 Apple Silicon iOS 26+ 模拟器 arm64 兼容性。本轮目标为真机 Release Archive，CocoaPods、Xcode Archive 和 IPA 导出均成功，不把上述未来／模拟器提示记为已解决。
- 签名与符号：Runner 与 42 个 Framework 共 43 个 Mach-O 均通过严格签名校验，全部为 Apple Development `kancloud cq (578WZAD3DU)`、Team `B95U3272HR`；最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`，application identifier 为 `B95U3272HR.com.kando.kandoApp.beta`。profile UUID `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。IPA 的 43 个唯一 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，missing／extra 均为 0；45 条 DWARF 中两条为重复 UUID 副本。独立 `dwarfdump --verify` 深检有 44／45 个 bundle 通过，`App.framework.dSYM` 退出 1，并报告 169 次 Flutter AOT `DIE address ranges are not contained by parent ranges` 及两条汇总错误；保存的 184 对应文件同样为 171 条错误，确认不是 185 新增。UUID 覆盖完整，但不能写成全部 dSYM 深检通过。
- 制品与边界：`Card AI Test.ipa` 为 42,974,353 字节，SHA-256 `3381891e492fbb3b03fd7d8ecbdb70c6e0ba11176a77bc3775e60319e7d14281`；`dSYMs.zip` 为 63,897,837 字节，SHA-256 `5e494bf4fecdef02e2970c31f4a961555a43cf5001b7be10c7d2e2c5ae887ebf`。两份 ZIP 完整性通过，保存 IPA 与构建输出逐字节一致；制品位于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-185/`。新版本完整保存后，最旧的 181 已移入废纸篓，当前保留 183、184、185。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push；未重跑全量 Flutter 测试、扫描 Golden 或真机 OCR／pHash。

## 订阅兜底页与年试用 SKU（2026-10-27）

- 来源与范围：开始时基线为 `codex/dev-1.0.7scan@013a234f17ecf4a13ea507607b8ec4aa5dcac268` 加本地未提交修改；保留并行扫描页工作。按 Figma `3512:10546`／`3512:10763` 将本地 Page／Modal 兜底改为普通周、独立年试用、终身三卡，默认年试用；正式注册 `CardAi.yearly.trial`，测试注册 `cardx.year.trial`。原长期商品集合保留。具体价格、选中态文案和原型周期冲突取舍见[订阅本地兜底页](../01-flows/subscription-display.md)。没有修改服务端 V1、数据库、远端展示配置或 Android 购买分支。
- 购买保护：代码路径审查发现离线 `TRY FOR FREE` 点击后，`prepareFallbackPurchase` 原先只核对真实商品 ID／类型；若免费优惠已消失，后续两次商品事实一致仍可能继续付费。现在先显示已加载商品的中性文案并停止此次购买，用户须再次确认。按先开发及文档、再测试的约定，未在修改前运行失败测试；完成后在隔离临时副本中仅移除新增保护，同一回归用例按预期失败（应返回 null，实际返回 SubscriptionProduct），真实源码用例通过。临时 Dart 文件已清理，未改工作区真实源码做反证。
- 定向验证：`flutter test --no-pub --concurrency=1 --no-track-widget-creation test/subscription_display_test.dart test/subscription_restore_ui_test.dart test/release_config_test.dart test/subscription_product_registry_test.dart` 退出 0，122／122 通过。覆盖 390×844 下真实商品与离线 Page／Modal 三档、试用／非试用文案、完整年价与年周期、终身无周期、按精确年试用 SKU 重查、优惠消失阻止首次付费、原远端关联试用及长期注册／恢复边界。测试中的商店与注册表为受控替身，不代表真实 StoreKit 或服务端准入通过。
- 静态与视觉检查：订阅模块及上述四个测试文件的 `flutter analyze --no-pub` 无问题。另通过两项临时渲染用例生成完整页／弹窗三种选择的六张 390×844 预览并检查试用、终身状态；输出位于忽略的 `apps/flutter-app/build/subscription-fallback-preview/`。预览使用 Windows 本机字体代替部分系统字体，完整页原生视频未播放，不能作为 iOS 像素级或真机视频验收。独立 Code Review 发现的优惠消失保护和周期归一化作用域问题均已修复并复核关闭；`git diff --check` 通过。
- 工具与未验边界：首次沙箱内 Dart 格式化已写入文件，但写 SDK 外 telemetry session 失败而退出 1，不记为通过；后续受控 Flutter 检查通过。未运行全仓 Flutter／Workers 测试、APK／IPA 构建、CI、iOS／Android 真机或真实商店购买／Restore；未执行 Git commit／push、dev/prod 部署、后台商品审批、Apple 写操作、数据库迁移或业务写入。新年试用的 Apple 可售状态、实际三天免费优惠、各环境准入与 Singular 事件映射仍需在对应平台验证。

## iOS 测试环境内部安装包 1.0.6 (184)（2026-10-27）

- 构建输入：从构建前干净且与实时远端一致的 `codex/dev-1.0.7scan@76068ec82cb9674f4250e4a2bfe599e29561d033` 构建，包含扫描卡牌类型顶部提示样式提交。脚本按工程 `1.0.6+183` 显式选择 `1.0.6 (184)`，完整保存后仅将 `pubspec.yaml` 同步为 `1.0.6+184`；分支名不会自动改变营销版本。构建前 dev health 返回 `{"status":"ok"}`。
- 环境与构建：最终内部 IPA 为 `com.kando.kandoApp.beta`，只包含测试 API `http://192.168.50.201:8080/api/v1`，Firebase plist 与仓库 test 文件逐字节一致，项目为 `card-ai---test`；生产 API、生产 Firebase project/app ID 不存在。Google OAuth audience 按既有 Workers 验签合同继续固定使用生产 Client ID，属于已知例外，不代表混入生产 Firebase。Flutter 3.44.5／Dart 3.12.2／Xcode 27.1 下，发布脚本完成配置校验、依赖解析、`flutter analyze`、`flutter clean`、test flavor Release Archive、基础 IPA 和内部 IPA 校验；analyze 无问题。根 `pubspec.lock` 与 iOS `Podfile.lock` 的 SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有依赖锁漂移。
- 构建提示：`google_mlkit_commons`、`google_mlkit_text_recognition`、`sign_in_with_apple` 尚未支持 iOS Swift Package Manager；ML Kit 相关 Pod 另提示缺少 Apple Silicon iOS 26+ 模拟器 arm64 支持。本轮目标是真机 Release Archive，CocoaPods 和 Xcode 构建成功；这些未来／模拟器兼容提示未解决，也不扩展为真机 OCR 已验收。
- 签名与符号：Runner 与 42 个 Framework 共 43 个组件逐个通过严格签名校验，均为 `Apple Development: kancloud cq (578WZAD3DU)`、Team `B95U3272HR`。最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`；profile UUID `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。IPA 的 43 个唯一 arm64 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，缺失／额外均为 0；45 个 DWARF 条目中两个为同 UUID 副本，45/45 均与当前 Archive 字节一致。
- 测试：在 macOS 使用提交记录中的单并发、关闭 widget creation tracking 参数运行完整 `scan_page_test.dart`，130 项通过、5 个 390x844 Golden 像素比较失败，差异为 0.63%～3.85%；没有修改或重录 Golden。明确排除这 5 个 Golden 后，其余 130/130 项通过。该结果不能写成完整集合全通过；未执行真机相机、OCR／pHash、真实识别服务或人工视觉验收。
- 制品与边界：`Card AI Test.ipa` 为 42,974,836 字节，SHA-256 `d89708a5e579f43d433d002034587a11d155e24d36f3faeb6c6e2601b2863cec`；`dSYMs.zip` 为 63,896,828 字节，SHA-256 `50d398a1cd73a0fbf533ca8ea110d7a8fe38b5a50be3009302dc8c1b3155e269`。两份 ZIP 完整性通过，保存 IPA 与构建输出逐字节一致；制品位于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-184/`。新版本完整保存后才将 180 移入废纸篓，当前保留 181、183、184。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push。

## 扫描卡牌类型顶部提示样式（2026-10-27）

- 设计与范围：按 Figma 完整扫描页 `3305:21640` 重做 Flutter 扫描页样式，并以类型胶囊 `3305:21722`、取景框 `3305:21737`、额度提示 `3305:22294`、结果区 `3305:22304`、底部快门区 `3305:22349` 的属性为准。390×844 基线下，类型胶囊为 209×42px；取景框为 `x=68, y=154, 254×363px`、11px 圆角、0.91px 渐变边框及品牌色阴影；额度提示为 `x=16, y=573, 358×42px` 单行文案；结果轨道从 `y=618` 开始，卡片可见面板约 202×76px；底部控制区增加 8px 水平内边距。顶部仍保留 20px 背景模糊和 0.5px 底部分隔，控制项按设计只显示关闭、卡牌类型和闪光灯。
- 业务边界：继续复用 `_selectedCardType`、`ScanCardType.tcg/sports`、PopupMenu、`onCardTypeChanged` 及既有拍照／相册／重试／额度升级／结果操作调用链；没有修改 `card_type=0/1`、扫描接口、OCR／pHash、额度计算、订阅、候选、确认入库、Analytics、权限或路由。Figma 顶部没有搜索图标，因此仅移除该视觉快捷入口；既有 `/search` 路由及 No Match 卡片的 `Search Manually` 入口保持并由原测试继续覆盖。
- 布局兼容：扫描计数、额度提示和结果轨道使用固定 162px 下部状态槽，Free／Premium、扫描前／结果出现后均不移动取景框；底部安全区由快门区吸收，不再重复压缩取景框。iPhone 8、iPhone 12、大小屏 iOS 与 compact／small／large Android 的 Free／Premium 变体继续断言取景框、结果轨道和快门互不覆盖；取景框比例按设计精确使用 `254/363`。
- 本地验证：更新四张受扫描页样式影响的 390×844 Golden 后，`flutter test --no-pub --concurrency=1 --no-track-widget-creation test/widget/scan_page_test.dart` 在不更新 Golden 的复跑中 135/135 通过；四张图已逐张原样回读，未重录 Review Golden。显式使用当前 Flutter SDK 运行全量 `analyze --no-pub` 返回 `No issues found`。首次默认 `flutter analyze --no-pub` 约三分钟无任何输出后被主动终止，不计为通过；随后显式入口验证成功。
- 未执行：未制作 APK／IPA、未运行 iOS／Android 原生编译、模拟器或真机视觉验收，未执行 Git commit／push、dev/prod 部署、数据库或远程配置操作。本地 Golden 证明当前测试字体和 390×844 渲染输出，不证明真实相机画面、设备字体或所有系统安全区已由人工验收。

## iOS 测试环境内部安装包 1.0.6 (183)（2026-10-26）

- 构建输入：从构建前干净且与实时远端一致的 `codex/dev-1.0.7scan@fc7073fd747c97391cab8556d02df7f99a961ed5` 构建。分支名不会自动改变 App 营销版本；脚本按 `pubspec.yaml` 的 `1.0.6+182` 选择 `1.0.6 (183)`，完整保存后仅将工程版本同步为 `1.0.6+183`。dev health 在构建前返回 `{"status":"ok"}`。
- 环境与构建：最终内部 IPA 为 `com.kando.kandoApp.beta`，只包含测试 API `http://192.168.50.201:8080/api/v1` 与 Firebase `card-ai---test`，生产 API／Firebase 字符串不存在。Flutter 3.44.5／Dart 3.12.2／Xcode 27.1 下，发布脚本完成配置校验、锁定依赖解析、`flutter analyze`、`flutter clean`、test flavor Release Archive、App Store 基础 IPA 与内部 IPA 校验；analyze 无问题。根 `pubspec.lock` 与 iOS `Podfile.lock` 的 SHA-256 保持 `612f006776860e3a61f083bf27283a73ec1c22b95dd8d318b06533d8fed46183`、`14216d83bfc80fdb98860bf1d624e528f35878242513a14ac6a41b3bf61ff685`，没有依赖锁漂移。构建仅提示 `google_mlkit_commons`、`google_mlkit_text_recognition`、`sign_in_with_apple` 尚不支持 iOS Swift Package Manager；本轮 CocoaPods 安装和 Xcode 构建成功，未把未来兼容提示写成已解决。
- 签名与符号：IPA 的 Runner 与 42 个 Framework 共 43 个组件逐个严格签名校验通过，均为 `Apple Development: kancloud cq (578WZAD3DU)`；最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`。profile UUID 为 `b38a6512-5b51-4f36-ab2d-757de0582e7b`，有效至 2027-09-07，包含 6 台设备。IPA 的 43 个唯一 arm64 Mach-O UUID 与 dSYM 的 43 个唯一 UUID 精确一致，缺失／额外均为 0；45 个 DWARF 条目中两个是同 UUID 副本，不影响覆盖。
- 测试：首次运行扫描相关单元／组件完整集合时，179 项通过、5 个 390x844 Golden 像素比较失败；失败项均为 macOS 与现有图像基线差异，未修改或重录 Golden。明确排除这 5 个 Golden 后，以相同测试文件和 test 配置重跑其余 179/179 项通过。该结果不能写成完整集合全通过，真机 OCR／pHash 与真实识别服务仍未验收。
- 制品与边界：`Card AI Test.ipa` 为 42,972,634 字节，SHA-256 `056f20185ba55731e9f48bc937243114c83fae691cebd8336b48f67294dde156`；`dSYMs.zip` 为 63,896,903 字节，SHA-256 `c0e988e6bccf8d4ede7ca01f42aebf3b8798bfa6f26611db687cb6e0ef2127f2`，两份 ZIP 完整性通过。制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.6-183/`；完整保存后才将 179 移入废纸篓，当前保留 180、181、183。本次未安装真机、上传蒲公英／TestFlight／App Store Connect／Firebase，也未执行远程部署、数据库写入、Git commit 或 push。

## 扫描记录 OCR 文本展示（2026-10-26）

基线为 `codex/dev-1.0.7scan@8f4763a4567b30d0f9964bfb3b1054e4cd420b9f` 加本地未提交增量。pHash/OCR 扫描把经过请求校验的文本写入既有 `scan_record.system_result.ocr_text`：有文本保存字符串，OCR 成功但无文本保存空字符串，OCR 缺失及旧向量请求保存 `null`。没有新增数据库字段或 migration；既有 Admin 扫描详情 API 原样解析 `system_result`，旧记录缺少该键时仍可读取。

Admin “扫描详情 → 系统识别结果”在现有候选数量右侧增加“OCR 文本”。字符串原样展示；`null`、字段缺失及空字符串均展示为空白，不使用通用的 `-` 占位，也不改变列表、筛选、候选卡牌或其他 Admin 模块。

实际本地验证：

- Workers `src/scan/routes.test.ts` 与 `src/admin/routes.test.ts` 共 2 文件／76 项通过，覆盖 pHash 文本规范化后持久化、OCR 缺失／空字符串、旧向量 `null`、Admin 详情回传。
- Admin 全量 Node 测试 78 项通过，其中新增意图测试约束 OCR 字段位置与空白展示；Admin TypeScript 检查通过。
- Workers 首次 TypeScript 检查因 `buildSystemResult` 参数未显式包含运行时已排除的 `null` 类型而退出 2；仅修正参数类型为 `string | null | undefined` 后，同一类型检查退出 0，并重跑上述 76 项通过。
- Admin development 构建通过：Vite 转换 1,526 个模块并生成静态产物。本轮未启动远端环境、未执行 migration／数据库写入、Git commit／push 或 dev/prod 部署；未以真实 Admin 登录态和现有扫描记录进行浏览器交互验收。

## 扫描 pHash／OCR 选择性集成（2026-10-26）

本地基线为 `codex/dev-1.0.7scan@8d8d2bb03e31af63b01e7f3e519fd3e6970e009b` 加未提交增量，来源为 `dev-xiangyang@2c56e9f12901c33d22684c869ac29d42f3ee77c3`。本轮未执行整分支 merge，只移植扫描识别、直接平台桥、依赖、双识别服务配置／预检及对应文档；版本号、订阅、Admin、历史归档回写和其他无关业务未引入。

当前 App 使用 RTMDet 矫正卡面，并行计算 RGB pHash 与 ML Kit Latin OCR，OCR 经规则化后作为可选 `ocr_text`；体育卡发送 `card_type=1`。当前 App 与线上低版本 App 均调用 `POST /api/v1/scan/recognize`：服务端只收到 `r/g/b` 字段组时转发到 `PHASH_RECOGNITION_BASE_URL`，只收到 512 维 `vector` 时继续使用 `VECTOR_RECOGNITION`，两组同时出现或均缺失时返回 422。当前 Flutter 源码不再构建旧向量识别；插件向量入口、额度、R2、目录补全、扫描审计和 confirm 契约保持。PE-Core 转换产物保留在 source-only 模型目录，但已从 Android/iOS bundle 与原生运行入口移除。

实际本地验证：

- Flutter 扫描相关测试：`flutter test --no-pub ...` 退出 0，共 173 项；覆盖 pHash 位序／Pillow 对照、OCR 规则化、OCR 失败降级、RTMDet 裁剪、API multipart、Sports `card_type=1`、额度／重试及 Scan 页面共享流程。
- 模型 bundle 清理后重跑核心 Flutter 测试，退出 0，共 23 项；针对性 `flutter analyze --no-pub` 退出 0。首次 analyze 因 `scan_text_recognizer_native.dart` 的冗余 `dart:typed_data` import 退出 1，删除该 import 后以相同范围重跑通过。
- Workers 定向测试：`src/scan/routes.test.ts`、`src/legal/routes.test.ts`、`src/linux/config.test.ts` 共 3 文件／70 项通过；覆盖同一路径的旧向量与当前 pHash 分流、双字段歧义拒绝、OCR 缺失／空字符串、非法哈希、Sports 类型、配置缺失释放额度、目录／审计及隐私披露。
- 按“当前源码只构建新协议、服务端兼容生产旧包”的边界将新旧请求收敛到原 `/scan/recognize` 后，重跑 Flutter API／编排 25 项、Workers 上述 70 项及 Workers TypeScript 检查，均退出 0；未新增第二条识别路由。
- Workers TypeScript 检查通过；Linux bundle 与 preflight 的 Node 测试 11 项通过。随后 `deploy:dry-run:dev` 再运行 bundle 3 项并完成 Linux 打包，明确未连接 SSH、未执行 migration 或部署。
- `pnpm test:app-compatibility` 退出 0：当前 PostgreSQL API 合同 8/8、固定 App 1.0.4+161 与 1.0.5+163 各 24/24。该编排不覆盖扫描；旧向量扫描兼容证据来自本轮 Workers 路由测试，不能把固定合同结果扩展为旧包真机扫描通过。
- `pnpm lint` 通过。生产 Worker dry-run 通过，保留 `VECTOR_RECOGNITION` Service Binding，并加入 `PHASH_RECOGNITION_BASE_URL=https://recognize.tcgcard.fun`；没有上传、切流或修改远端配置。
- Android test Debug APK 在接口收敛后重新构建通过：`apps/flutter-app/build/app/outputs/flutter-apk/app-debug.apk`，256,916,611 字节，SHA-256 `23f4448a1904e6758a6bd403eb17a082e896fddde36d4470db4c23c269ff8c8e`。包内断言确认 PE-Core 资源不存在、RTMDet 与 ML Kit OCR 资源存在。构建仅出现仓库既有 Gradle 8.12、AGP 8.9.1、Kotlin 2.1.0 的未来弃用警告，未在本任务升级工具链。

未验证与边界：

- Windows 无法执行 Xcode／CocoaPods／iOS 模拟器或真机构建；`Podfile.lock` 与 Xcode PE-Core 引用已按依赖和 bundle 变更更新，但 iOS 编译、签名、ML Kit Latin OCR、App Attest entitlement 和 IPA 解包仍待 macOS 补验。
- 未向 `recognize.tcgcard.fun` 发送真实或合成识别请求，也未实时回读其公开 health；preflight 使用受控测试服务验证 768/euclidean/Top 5/`cards_phash` 合同。真实图片准确率、OCR 命中率、弱网／超时、真机性能和外部服务当前状态未验。
- 未运行完整 Workers 默认测试、全仓 Flutter 测试、iOS 构建或真实旧 App 安装包扫描；未执行数据库 migration／业务写入、Git commit／push、dev/prod 部署或商店发布。

后续记录按时间倒序追加，并明确以下信息：

- 来源提交、工作区是否干净、目标环境与授权范围；
- 实际执行的检查、结果、失败、重试和未运行项；
- 本地、CI、dev、prod、商店与真机证据边界；
- 回退点、数据影响、外部平台影响及用户反馈是否由 Agent 独立复验。
