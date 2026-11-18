# iPhone Duo 适配方案

状态：2026-11-18（Asia/Shanghai）已按用户授权实施首轮 Flutter UI 适配与右侧竖向导航，将优化比例版安装到 Duo 模拟器，并补齐内屏首页的实际外观核对。本地验证结果及 OCR 预览限制见第 8、9 节；不能把本地预览等同于完整设备或发布验收。原生工程、CI 和服务端源码未修改。

基线：从干净的 `codex/fixbug-andriod@c8b8caae4070918904f737223d844017c94602e3` 创建并切换到 `codex/iphone-duo-adaptation`；创建时两分支指向同一提交。

## 1. 推荐方向

继续使用同一套 Flutter 客户端，按当前窗口和局部内容区域的实际空间重排。首先完成内外屏切换、系统分屏下的可用性和状态连续性，再增加宽屏卡牌详情与资产面板的并排展示。

首轮保留现有品牌色、字体、卡牌组件、五个导航入口及突出的 Scan 主操作。窄屏继续使用当前移动布局，宽屏增加信息密度。账号、数据空间、订阅、额度、识别协议与服务端接口沿用现有合同。

Android 继续全程 `portraitUp`，保留免费首版策略；iOS 继续使用现有方向规则和 Apple 订阅策略。Duo 仍属于 iOS 业务平台，不能因展开宽度或布局分类改变账号归属、权益或商业策略。

## 2. 官方资料与工具链前提

2026-11-17 已直接阅读 Apple 官方页面：

- [iPhone Duo 产品页](https://www.apple.com/iphone-duo/)：内外显示区域切换、不同摆放姿态、iOS 27 与 Split View 是本次适配需要考虑的场景。
- [Three steps to make your app shine on iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)：iOS 26 SDK 及更早构建采用兼容显示；iOS 27 SDK 支持动态调整，27.1+ SDK 才完整使用显示区域。官方要求按当前视图／窗口尺寸布局，持续响应尺寸变化，不以设备型号、方向或 phone／pad 身份代替可用空间判断；同时要求检查原生栏转为纵向后的内容布局。
- [Flutter 自适应布局方法](https://docs.flutter.dev/ui/adaptive-responsive/general)：全窗口使用 `MediaQuery.sizeOf`，局部组件使用 `LayoutBuilder` 的父约束，依据可用空间选择布局。当前网站注明面向 Flutter 3.50，项目仍以 3.47.9 和实际构建结果为准；本方案使用的这两种 API 已存在于当前源码，不据此默认升级依赖。

本机只读查询结果为 Xcode `27.2`（`27B52`）、iPhoneOS SDK `27.2`。这只证明工具链存在，不证明 Flutter 引擎、原生插件、签名包或 Duo 已通过运行验收。

当前 GitHub [iOS build](../../../../.github/workflows/ios-build.yml) 使用 `macos-15`，记录 Xcode 版本但没有显式选择 27.1+；[pubspec.yaml](../../../../apps/flutter-app/pubspec.yaml) 的 `device_info_plus` 注释仍描述 CI 使用 Xcode 16.4。注释不能证明当前远端运行版本。本机、CI 与正式打包必须分别回读，实施时统一到经验证的 27.1+ 工具链，并核对其他 Apple 构建入口。

`iOS 16+` 是部署下限，`iOS 27.1+ SDK` 是构建要求，两者不应混淆。先以仓库约定的 Flutter 3.47.9 验证 SDK／引擎及 camera、ML Kit、Core ML、StoreKit、OAuth 等插件；只有发现具体兼容阻塞，才评估最小工具链或依赖升级并同步 Android 回归。

## 3. 适配前源码基线

| 位置 | 已确认的当前行为 | 对适配的意义 |
|---|---|---|
| [app_shell.dart](../../../../apps/flutter-app/lib/shared/ui/app_shell.dart) | 自绘底部胶囊、五入口、居中突出的扫描按钮 | Flutter 自绘导航不会自动获得原生工具栏的 Duo 排列；宽窗口需要显式限宽、对齐，并核对左右安全区 |
| [router.dart](../../../../apps/flutter-app/lib/app/router.dart) | 卡牌详情是独立路由；收藏检查、订阅包含独立 sheet 路由 | 窗口变化不能通过重新导航切版，避免返回栈改变、重复埋点和状态丢失 |
| [search_page.dart](../../../../apps/flutter-app/lib/features/search/search_page.dart)、[collection_page.dart](../../../../apps/flutter-app/lib/features/collection/collection_page.dart) | 卡牌网格固定两列，`mainAxisExtent: 378` | 宽屏只加大卡片会浪费空间；需要按实际列宽和文字高度共同计算网格 |
| [card_detail_page.dart](../../../../apps/flutter-app/lib/features/card_detail/card_detail_page.dart) | 已有 `maxWidth: 672` 的居中单列详情及局部弹性布局 | 现有适配可以复用；并排卡图、价格和资产信息属于后续增量，不应把当前代码描述成完全固定布局 |
| [scan_page.dart](../../../../apps/flutter-app/lib/features/scan/scan_page.dart) | 取景框已有大小屏计算；布局与拍照从整页 `MediaQuery` 获取 viewport；活动扫描队列和编辑草稿在页面 State 内 | 需要保留同一 State；将预览放进局部面板后，必须同时调整显示与拍照使用的坐标 |
| [scan_camera.dart](../../../../apps/flutter-app/lib/features/scan/scan_camera.dart)、[scan_native_image_processor.dart](../../../../apps/flutter-app/lib/shared/scan/scan_native_image_processor.dart) | 预览采用 `BoxFit.cover`；裁剪根据传入 viewport、previewSize 与取景框计算归一化位置 | 不能只改视觉布局；覆盖裁切、面板偏移、拍照期间尺寸切换都必须验证 |
| [scan_orientation.dart](../../../../apps/flutter-app/lib/features/scan/scan_orientation.dart) | Scan 请求 `portraitUp`；退出后 Android 继续竖屏，iOS 恢复应用策略 | 保留平台差异；不能用全局解除方向限制来处理 Duo |
| [Info.plist](../../../../apps/flutter-app/ios/Runner/Info.plist)、[Info-test.plist](../../../../apps/flutter-app/ios/Runner/Info-test.plist)、[project.pbxproj](../../../../apps/flutter-app/ios/Runner.xcodeproj/project.pbxproj) | iPhone 仅声明 Portrait、目标设备 family=1；已有 FlutterSceneDelegate，multiple scenes=false | 不能把现状说成 iPhone 已支持横屏或 iPad；系统 Split View 和同一 App 多窗口是不同需求，不需要为本次适配默认开启后者 |
| [subscription_page.dart](../../../../apps/flutter-app/lib/features/subscription/subscription_page.dart)、[kando_bottom_sheet_page.dart](../../../../apps/flutter-app/lib/shared/ui/kando_bottom_sheet_page.dart) | 存在基于整页高度的布局分支和按视口比例计算的 sheet | 短窗口、键盘、左右安全区及内外屏切换需要单独验证；保留购买与关闭语义 |

当前 UI 基线为 [390px 设计系统](../../v1.0.0/00-product/ui-design-system.md)，它明确禁止把字号随屏宽整体缩放。Duo 的多栏布局属于当前版本的设计增量；不得回写冻结规范，也不能套用默认 Material 导航视觉。

## 4. 页面布局建议

断点按 Flutter 逻辑像素计算。以下 `600`／`840` 仅为初始调试值，必须用官方 Duo 模拟器实际窗口、系统分屏、大字体和内容最小宽度校准，不能当成硬件规格。内屏也可能处于窄窗口。

| 当前可用空间 | 建议行为 |
|---|---|
| 宽度小于 600 | 单列页面；现有底部胶囊；列表保留正常手机两列，极窄窗口或大字体时可降一列 |
| 宽度 600–839 | 网格按适合卡牌阅读的列宽增加列数；详情仍可使用现有居中限宽布局；表单和导航限宽居中 |
| 宽度至少 840 且两面板均满足最小宽高 | 启用适合该页面的双栏；空间不足立即回到单栏；不能仅因设备展开就强制双栏 |
| 高度不足、键盘弹出或系统分屏 | 优先保证输入、主按钮、关闭和返回可达；正文可滚动，必要时收起并排面板 |

用户后续明确要求将五入口移至 Duo 右侧状态区域下方，首版已按第 9 节规格实现竖向品牌胶囊；普通手机及高度不足的窗口继续使用限宽底部胶囊。上表为最初建议区间，首版代码采用实际局部宽度至少 800 的双栏阈值。

| 页面 | 首轮兼容 | 后续宽屏增量 |
|---|---|---|
| Home | 资产值、筛选、趋势等模块不溢出；图表按所在面板尺寸绘制 | 资产概览／表现与高价值卡牌、趋势并排；金额隐私开关和筛选保持同步 |
| Search／Collection／Set Detail | 卡牌网格动态列数、卡图保持比例；空态、加载、分页状态同步适配 | 左侧结果、右侧选中卡牌详情；折回窄窗口时保留选中项、筛选、滚动和返回语义 |
| Card Detail | 复用现有限宽结构，确保长标题、价格表、编辑区与操作按钮可达 | 左侧卡图与身份信息，右侧价格／资产／编辑；复用现有 controller，不创建两份资产状态 |
| Scan | 竖向取景框、控件和队列在实际窗口内可用；尺寸变化不清空队列和草稿 | 空间允许时左侧独立预览面板、右侧当前活动队列／候选操作；不新增整批处理或跨设备恢复 |
| Subscription／Auth／Profile | 正文和表单限宽；短高度可滚动；购买、恢复、登录回跳保留状态 | 可增加说明与表单并排，仍复用现有商品、交易与身份状态 |
| Sheet／Modal／顶部 Toast | 窄屏原有形态；宽屏内容限宽；适应四边安全区和键盘 | sheet 是否改为居中面板按具体场景设计；危险操作、订阅及强更的阻断语义保持原样 |

## 5. 扫描的专项处理

扫描是最高风险环节，应在普通宽屏 UI 开发前完成最小技术验证。

1. 继续保留竖向扫描和 capture orientation 规则。用 27.1+ SDK 在 Duo 模拟器核对当前 Portrait 声明下的内外屏、左右安全区与系统分屏；确认系统实际窗口行为后再定局部预览尺寸。不能声称调用 `setPreferredOrientations` 就能阻止窗口调整。
2. 预览面板通过局部约束计算 viewport；取景框、遮罩和裁剪复用同一份局部几何参数。面板有偏移或留边时，不能把整页尺寸直接传给裁剪。
3. 统一 `BoxFit.cover` 的缩放、偏移和原生图像方向处理。使用带边界标记的真实卡面核对四角，避免画面看起来正确而上传裁剪错位。
4. 拍照发起时记录同一帧使用的 viewport、取景框和几何版本。切换发生在拍照期间时，保证几何与图像匹配；匹配无法保证时明确中止该次拍照并允许重试，不提交错位图像或误计额度。
5. 尺寸变化只重排现有页面，不重建 `_ScanPageState`、camera session 或识别任务。仅当相机因实际系统生命周期／设备变化失效时，复用既有会话恢复逻辑；不得追加第二条识别流水线或重复确认收藏。
6. 半折叠姿态首轮按系统提供的当前可用窗口处理，不假设铰链必然位于中点，也不假设 Flutter 的 `displayFeatures` 在 iOS 必然提供姿态信息。若后续需要专门的桌面半折叠扫描，先确认 Apple 官方 API 与 Flutter 的实际支持，再决定是否需要最小原生桥接。

现有普通 iPhone 仅支持竖屏。若完整 Duo 验收发现必须改变支持方向声明，应先提出独立的 Duo 方向增量方案并确认影响；不能顺带让所有 iPhone 或 Android 开放横屏。该项目前是技术待验证条件，不是已授权的规则变更。

## 6. 实施顺序

1. **验证 SDK 与窗口行为。** 以测试配置构建并在 Duo 模拟器观察真实逻辑尺寸、安全区、方向及 camera／StoreKit／OAuth 兼容性；确认 CI 和正式打包可复现同一 SDK。遇到无法兼容双端的技术限制时停止相关实施并说明。
2. **完成基础适配。** 处理局部布局约束、导航限宽、动态网格、弹层与短高度；接入尺寸切换回归，保证状态与既有移动视觉。
3. **补扫描坐标与连续性。** 完成局部预览几何与拍照期间切换策略，保留两端识别流程、队列、平台额度和相机资源生命周期。
4. **增加有收益的双栏。** 优先卡牌详情、收藏／搜索结果与 Home；按页面最小尺寸启用。布局切换保留同一路由和数据状态，不以重建 router／ProviderScope 实现。
5. **双端验收与交付。** Duo 真机、普通 iPhone 与 Android 均通过后，再走既有构建归档和发布流程。构建、Git push、TestFlight／商店发布和环境部署分别取得对应授权；仅清理本任务确认无活动依赖的临时产物。

## 7. 验收条件与当前边界

实施后的验收必须覆盖：

- Duo 外屏、内屏、系统 Split View、短窗口和半折叠可用场景；连续切换时搜索词、文件夹、选中卡牌、滚动锚点、编辑草稿和返回栈保持正确。
- 动态尺寸穿越断点与大字体／键盘场景：无 RenderFlex overflow、关键卡图不裁掉、按钮和关闭入口可达；现有 390×844 视觉基线保持。
- 扫描在预览、拍照、识别、候选选择、编辑和保存期间切换：框内图像与实际裁剪一致，无队列丢失、重复请求、重复额度扣减或重复收藏；后台／前台切换后相机正常释放和恢复。
- iOS 16+ 受支持普通 iPhone：方向、登录、订阅、Premium、购买与恢复仍符合既有规则；Duo 不触发 Android 免费策略。
- Android API 24+：启动、进入／离开 Scan、键盘及前后台切换后始终正向竖屏；免费首版和独立账号数据空间不变。
- 受影响 Flutter 测试、`flutter analyze`、iOS／Android 测试配置构建；如实际修改共享依赖或 CI，再运行其对应的跨包／流水线检查。模拟器可验证窗口与 UI，真实扫描、相机方向、交易和性能仍需对应真机或平台证据。

方案阶段只验证了分支基线、源码／配置和官方资料，并查询本机 Xcode／SDK；当时尚未构建或运行 App。随后用户追加的模拟器预览记录见下节，不能据此关闭上述完整适配验收项。

## 8. 未适配模拟器预览（2026-11-17）

按用户要求，将当前基线安装到 Device Hub 已启动的 iPhone Duo（iOS 27.1，UDID `A9D96BD2-F97C-42A6-9047-FDC8F0781675`），未实施布局适配。

- **构建限制与文档冲突：**仓库 `tool/run_ios_simulator.sh` 首次运行报 `No Xcode build settings have been found`。原生 ML Kit 依赖排除 arm64 模拟器，而该 Duo runtime 仅支持 arm64；现有 ML Kit arm64 静态库对应 iOS 真机。README 描述的临时省略 OCR 方案没有在当前启动脚本中实现，不能把原始完整依赖构建记为通过。
- **预览例外：**在 `/private/tmp/kd-iphone-duo-baseline/native-preview/ios` 制作隔离原生工程，仅省略模拟器无法链接的 `google_mlkit_commons`、`google_mlkit_text_recognition` 及 Japanese OCR Pod／注册，调整该副本的模拟器架构设置。Flutter application path 仍指向仓库原 App，Dart／UI／业务源码保持原样；其余原生 Pod 版本与原 lockfile 对照无变化。该包只用于观察当前 UI，不能用于完整扫描验收。
- **实际安装包：**Xcode 27.2（27B52）／iPhoneSimulator 27.2 SDK，scheme `test`、`Debug-test`、arm64；版本 `1.0.7+210`，Bundle ID `com.kando.kandoApp.beta`，采用现有 `config/test.json` 测试环境。首次无签名包在安全存储初始化时报钥匙串 `-34018`；启用模拟器本地 ad-hoc 签名重新构建、安装后，已进入引导、关闭订阅页并进入可操作的访客首页，没有绕过安全存储或修改业务初始化。
- **已观察结果：**Device Hub 可显示原首页和底部五入口；铰链调至 180° 后，`simctl` 的 display 3 内屏截图可见横向展开的现有单列内容及铺满宽度的底部胶囊，尚无多栏重排。只记录本次可见结果，不推定方向、安全区、状态连续性或全页面均已适配。
- **证据位置：**本机 `/private/tmp/kd-iphone-duo-baseline/` 保留 `preview-pods.log`、`preview-build-signed.log`、`build-identity.json`、启动日志、`duo-inner-baseline.png`、`duo-outer-baseline.png` 与签名后的 `DerivedData/Build/Products/Debug-test-iphonesimulator/Runner.app`。外屏截图在内屏活动时为黑屏，不作为外屏 UI 验收证据。
- **未执行项：**本轮未实施代码，因此未新增测试、运行 Flutter analyze／全套测试或重建 Android；未验证 Duo 真机、真实相机／OCR、购买／恢复、登录账号、性能、完整折叠／分屏矩阵及远端 CI。未 Git commit／push、部署 API／官网或发布移动端制品。Android 源码和配置未改，双端业务验收仍保留。

构建结束后仅清理本任务已无活动依赖的临时编译中间文件和模块缓存，保留安装包、隔离工程、日志及截图，供继续查看和复查。

## 9. 首轮实施（2026-11-17）

这是同一 Flutter 客户端的布局增量。当前保留独立详情路由，不实施搜索／收藏的列表详情主从导航；Scan 保持全窗口预览，不实施局部预览双栏。平台商业策略、账号／数据、API、扫描识别协议及原生方向声明均保留。

### 9.1 右侧导航与正文

- iOS 当前窗口右安全区至少 84 逻辑像素，且扣除顶部安全区、底部／键盘避让后高度至少 520 时，显示 68×380 的竖向胶囊。顶部至少预留 140 逻辑像素给相机和系统状态，在余下区域垂直居中；84 宽的区域左右各留 8。该规则依据窗口安全区和空间，不按硬件型号切换。
- 顺序沿用 Home、Search、Scan、Collection、Profile；普通入口高 54，Scan 为 56 圆按钮，入口间隔 22、水平内边距 4、垂直内边距 10。根据用户反馈，将原预览的 80×312 胶囊收窄、拉长，并缩小 Scan，使入口间距和上下留白更均衡。复用现有图标、11px 导航字、品牌渐变、毛玻璃和选中动画。右栏不会挤压正文；正文仍尊重系统左右安全区。
- 右栏模式移除底部胶囊和它的预留空白；短窗口回到底部，底部导航宽度至多 480 并避让左右安全区，390×844 基线仍为 350×62。Android 保留底部导航。
- 正文最大宽度 1200，Profile／认证／订阅正文最大 560，路由 sheet 最大 640，Toast 尊重左右安全区。底部未完成收藏提示保持可点击与限宽。

### 9.2 页面重排与状态

- Search、Collection、Set Detail 按局部宽度计算网格列数：最小卡宽 170、间隔 10；大字体提高最小宽度及卡片高度。390 正常手机保留两列；951×669／右安全区 84 的预览场景可显示四列，极窄或大字体可降一列。Set Detail 窄窗口保留原 350 内容宽度。
- Home Overview 的资产面板与高价值卡牌／趋势，以及 Card Detail 的卡图／主操作与价格／资产详情，在局部宽度至少 800 且可用高度至少 480 时并排；键盘或短窗口回到可滚动单列。使用同一 Wrap 子树维持表单与页面 State，沿用 controller 和路由。
- Card Detail 采用单个 SingleChildScrollView 包含自适应内容，避免将整组双栏塞进懒加载单个列表项后破坏后代的滚动定位。
- Scan 保留整窗 viewport、既有取景框与 capture orientation，顶部／底部控件及结果条尊重左右安全区并限宽 560。拍照开始后若窗口 metrics 变化，丢弃该次结果并按既有失败卡片允许重试；不把旧几何对应的图片发送识别，活动队列和相机会话不因重排重建。

### 9.3 验证与边界

- **真实安全区与修复：**初版将右安全区门槛设为 96，测试使用虚构的 108，未触发真实 Duo 的右栏。通过 FlutterView 回读，内屏为 2853×2007 physical、DPR 3，即 951×669 logical；right padding／viewPadding 为 252 physical，即 84 logical。先将测试改为 84，确认返回错误的 480×62 底栏，再修复门槛并重建安装。已实际观察到右侧五入口胶囊、Search 可点击、展开四列卡牌；折叠外屏也显示竖栏。用户随后确认位置正确，并要求优化高度比例。
- **回归：**受影响的导航、布局、搜索、收藏、详情、Home、Scan、认证／订阅、Toast、方向和双端商业策略套件运行结果为 613 通过、14 失败，命令退出 1。14 项均为既有 golden 差异；独立未修改基线在同一环境也复现这 14 项，对应失败图像与本次原始字节一致，未更新 golden。基线另有 3 项测试字体路径缺失；本次临时提供当前 Flutter SDK 字体路径后，这 3 项通过。不能将该套件写成全绿。
- **最终比例专项：**68×380 版针对 Duo 内外屏尺寸切换、五入口点击及选中背景中心对齐、短窗口回退、普通 390×844 导航和表单 State 连续性的 4 项测试全部通过；最新 `flutter analyze --no-pub` 无问题。自审检查了导航触发／避让、动态网格、State 连续性、拍照期间 metrics 变化处理及双端规则；移除了无关格式变更。
- **iOS 预览：**最新比例版由 Xcode 27.2／Simulator SDK 27.2、test scheme、Debug-test、arm64 构建成功，版本 1.0.7+213、Bundle ID `com.kando.kandoApp.beta`。已顺序完成安装及启动，并回读已安装包的版本与 Flutter kernel SHA-256，和本次产物一致。沿用隔离工程的 ML Kit 例外，不能记为完整原生依赖构建通过。2026-11-17 最终比例的画面核对曾受 Device Hub 无响应影响，自动查看连续超时；当时外屏截图只确认 App 到达订阅页，不能作为新版竖栏外观验收。2026-11-18 用户恢复窗口后，已补齐下节的内屏首页目视检查。
- **Android：**已使用官方 Temurin 21.0.13+9，并分别核对 Flutter 实际 Java 与 Gradle JVM。第一次构建在 `sign_in_with_apple` 的 Kotlin compiler JAR instrumentation 阶段失败，原 JAR ZIP 校验及 SHA-1 正常；随后同一依赖的 Gradle 配置任务及完整 debug APK 重试成功，未升级插件、AGP 或 Kotlin。最终 APK 为 `com.kando.kandoApp.beta`／1.0.7+213、minSdk 24、targetSdk 36，Activity manifest 为 portrait；签名验证为独立 `CN=Android Debug, O=CardVault Test`，未使用正式签名。产物 178,913,792 字节，SHA-256 `3563db52342a89a7c66da52914e9558d722dcb752b5907fc2b1ed4bdfdcd1aa3`。仅完成构建与静态身份／签名核验，未在 Android 设备运行本次 APK。

验证日志和截图保留于本机 `/private/tmp/kd-iphone-duo-adapted/`，包含 `final-tests.log`、`golden-comparison.json`／`golden-evidence.zip`、`nav-proportions-test.log`、`analyze-proportions.log`、`build-proportions.log`、`installed-proportions-identity.json` 与 Android 构建／身份日志；未适配对照日志、包和截图位于 `/private/tmp/kd-iphone-duo-baseline/`。

本次验证后已清理确认无活动依赖的 iOS 适配构建中间文件／模块缓存、可从 Git 重建的基线测试副本、重复 JDK／Gradle 下载及临时测试字体链接；失败图像先归档，再仅删除本次未跟踪材料，保留仓库原有 8 张已跟踪图片。Android 构建结束后仅停止本任务两个 Java daemon，清理临时 JDK、App 编译中间文件及字节相同的重复 APK，保留 `build/app/outputs/flutter-apk/app-debug.apk`。iOS 安装包、隔离原生工程和验证证据继续保留，供用户查看及后续迭代。Flutter 临时 JDK 配置已恢复，未清理共享 Gradle 工具缓存或其他任务资源。

Duo 真机、普通 iPhone／Android 真机、系统完整分屏矩阵、真实相机裁剪／OCR、购买／恢复、OAuth 及性能需要对应设备与平台补验。模拟器包仍仅为 UI 预览，保留第 8 节 arm64 ML Kit 例外。未提交／推送 Git、修改远端环境或发布商店制品。

### 9.4 优化比例版外观补验（2026-11-18）

用户恢复 Device Hub 后，通过原生窗口截图实际观察到展开内屏的 Home 双栏及右侧完整五入口。68×380 胶囊呈修长比例，Scan 按钮位于中间，入口间距均匀；时间和信号显示在上方独立区域，未见导航遮挡系统状态或正文。该结果补齐最新比例版内屏首页的目视检查，不扩展为全页面、外屏或完整折叠矩阵验收。

随后用户自行进入 Scan，较晚取得的 `simctl` 截图已是扫描页面，保留为 `/private/tmp/kd-iphone-duo-adapted/duo-scan-inspection-20261118.png` 及对应原图，不将它标作导航截图。为保留用户正在操作的扫描状态，本轮未切换页面。仅补充运行画面观察与记录，没有修改 App 源码、重建安装包或重复运行上一轮已完成的测试。
