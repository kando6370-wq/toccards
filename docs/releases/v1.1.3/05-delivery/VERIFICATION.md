# v1.1.3 实际验证记录

启用日期：2026-10-26（Asia/Shanghai）。

本文件只记录 v1.1.3 启用后的代码、配置、数据、构建、部署和业务验收结果。创建版本目录本身没有修改业务代码、数据库、远程配置或运行环境，也不构成新的验证通过。

当前运行基线见 [v1.1.2 生产收尾记录](../../v1.1.2/05-delivery/VERIFICATION.md#prod-app-1-0-6-monthly-admission-20261026)。以下记录只代表 v1.1.3 本地增量及实际执行的验证，不改变远端运行状态。

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

- 设计与范围：按 Figma `卡牌app` 节点 `3305:21640`／顶部控制栏 `3305:21718` 调整 Flutter 扫描页。关闭按钮、卡牌类型选择器、搜索入口和闪光灯现在位于同一条 42px 顶部控制栏；类型胶囊在 390px 基线宽 204px，使用品牌强调色文字和下拉箭头。顶部区域增加 20px 背景模糊、半透明暗面及 0.5px 底部分隔，关闭和闪光灯触控区统一为 42px。搜索入口因“只改样式、不改业务”要求保留在右侧。
- 业务边界：继续复用原 `_selectedCardType`、`ScanCardType.tcg/sports`、PopupMenu、`onCardTypeChanged` 及相机／相册／重试调用链；没有修改 `card_type=0/1`、扫描接口、识别、额度、订阅、候选、确认入库、Analytics、路由或权限。文字缩放较大或屏幕较窄时仅对类型标签与箭头做 `scaleDown`，不改变选择值。
- 布局兼容：顶部栏较旧布局减少 12px 垂直占用，自适应取景框按既有安全区公式获得更多空间；iPhone 8 与 compact Android 的精确布局预期同步更新，仍分别断言取景框位于额度提示下方 16px、快门上方 16px。结果栏不覆盖取景框的全部既有 iOS／Android 变体继续通过。
- 本地验证：`flutter test --no-pub --concurrency=1 --no-track-widget-creation test/widget/scan_page_test.dart` 最终 135 项通过；四张受顶部栏影响的 390x844 Golden 已更新并原样回读通过。`flutter analyze --no-pub` 无问题，`git diff --check` 通过。早期定向测试曾依次暴露测试缺少 `KandoColors` 导入、放大字体下 `Sports Card` 溢出及两个旧坐标预期；修正后均以原测试范围重跑通过。两次默认 Windows JIT 测试因内存耗尽崩溃，改用单并发并关闭 widget creation tracking 后完成上述验证，不将 OOM 轮次记为通过。
- 未执行：未制作 APK／IPA、未运行 iOS 原生编译或真机视觉验收，未执行 Git commit／push、dev/prod 部署、数据库或远程配置操作。本地 Golden 证明布局输出，不证明真实相机画面、设备字体或系统安全区在所有机型上已由人工验收。

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
