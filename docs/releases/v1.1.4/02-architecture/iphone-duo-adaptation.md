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

这是同一 Flutter 客户端的布局增量。当前保留独立详情路由，不实施搜索／收藏的列表详情主从导航。首轮 Scan 保持全窗口预览；2026-11-18 按用户后续授权增加第 9.9 节的 6:4 局部预览双栏。平台商业策略、账号／数据、API、扫描识别协议及原生方向声明均保留。

### 9.1 右侧导航与正文

- iOS 当前窗口右安全区至少 84 逻辑像素，且扣除顶部安全区、底部／键盘避让后高度至少 520 时，显示 68×380 的竖向胶囊。顶部至少预留 140 逻辑像素给相机和系统状态，在余下区域垂直居中；84 宽的区域左右各留 8。该规则依据窗口安全区和空间，不按硬件型号切换。
- 顺序沿用 Home、Search、Scan、Collection、Profile；普通入口高 54，Scan 为 56 圆按钮，入口间隔 22、水平内边距 4、垂直内边距 10。根据用户反馈，将原预览的 80×312 胶囊收窄、拉长，并缩小 Scan，使入口间距和上下留白更均衡。复用现有图标、11px 导航字、品牌渐变、毛玻璃和选中动画。右栏不会挤压正文；正文仍尊重系统左右安全区。
- 右栏模式移除底部胶囊和它的预留空白；短窗口回到底部，底部导航宽度至多 480 并避让左右安全区，390×844 基线仍为 350×62。Android 保留底部导航。
- 正文最大宽度 1200；Profile 宽窗口正文最大 1040、单列最大 560，认证／订阅正文最大 560，路由 sheet 最大 640，Toast 尊重左右安全区。底部未完成收藏提示保持可点击与限宽。

### 9.2 页面重排与状态

- Search、Collection、Set Detail 按局部宽度计算网格列数：目标卡宽 170、间隔 10；局部净宽至少 320 时保留两列紧凑卡片，大字体按最多 1.5 倍提高宽度门槛并增加卡片高度。390 正常手机及 466×678／右安全区 84 的折叠外屏均保留两列；951×669／右安全区 84 的展开内屏显示四列，极窄或大字体可降一列。Set Detail 窄窗口保留原 350 内容宽度。
- Home Overview 在扣除页面横向边距后的局部宽度至少 800，且扣除顶栏、模块间距、上下留白后的面板高度至少 400（空收藏面板为 520，均随字体倍率提高门槛）时并排：顶部切换栏与货币控件、左侧资产／图表固定，右侧 Most Valuable 与 Trending Today 共同独立纵向滚动，Most Valuable 保留横向滚动。窄屏、短窗口、键盘或大字体占用后空间不足时回到最大 672 的可滚动单列。稳定页面内 Key 保持图表、卡片横向列表和主滚动 State；Performance 保留整页滚动。
- Card Detail 以正文局部约束判断布局：宽度至少 800、高度至少 480 时，左侧卡图／主操作和右侧价格／资产信息分别使用独立滚动容器。滑动右侧不会带动左侧；左侧内容过高时仍可单独滚动以访问按钮。窄屏、短窗口或键盘占用后高度不足时回到限宽 672 的整页单列滚动。两面板和主滚动容器通过页面内的稳定 Key 保持既有子树／滚动 State；内容构建放在尺寸布局计算之外，避免键盘动画重复重建编辑表单。沿用 controller、路由及原有下拉刷新。
- Scan 在安全区和页面边距内宽度至少 800、扣除顶部栏与上下留白后面板高度至少 440（两项门槛随字体倍率提高）时，按扣除 24 间距后的宽度 6:4 分为左侧相机预览和右侧控制／结果队列。取景框保持原卡牌比例并占预览高度至多 80%；显示、遮罩和拍照裁剪共用左侧局部 viewport／取景框。右侧结果纵向滚动，类型／闪光灯与底部操作固定；窄屏、短窗口和字体增大后空间不足时保留整窗预览与原底部横向结果条。capture orientation、拍照期间 metrics 变化时丢弃旧几何结果、活动队列和相机会话的原规则保持。

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

### 9.5 卡牌详情固定左栏（2026-11-18）

用户要求从 Search 进入卡牌详情后，右侧信息滚动时左侧图片区域保持固定。原实现将两栏放在同一个 SingleChildScrollView 内，右侧滚动会同时移动左侧；修改前在 951×669／right 84／bottom 34 下，iOS 和 Android 的针对性测试均复现：向上滑动 240 后，Hero 顶部从 20 变为 -220。

当前按第 9.2 节的局部尺寸规则拆分双栏滚动，左侧包含卡图、返回／收藏入口及主按钮。普通手机、短窗口和键盘占用后空间不足时继续整页单列滚动。保留同一页面、面板和主滚动 State，布局切换不丢失编辑文本；内容与约束计算分离，避免键盘动画重复构建表单。该布局由通用 CardDetailPage 承担，Search、收藏及 Scan 入口沿用各自既有业务语义，没有新增路由或修改平台策略。

- **测试：**新增 iOS／Android 回归覆盖右侧滚动时 Hero 与主按钮的矩形保持不变、窄屏整页滚动、主滚动 State 连续性、较短双栏下左侧按钮可达且不带动右侧、编辑草稿在宽窄／键盘切换时保持。`flutter test --no-pub test/widget/card_detail_page_test.dart test/widget/kando_responsive_test.dart test/widget/search_page_test.dart` 最终 145 项全部通过，退出 0，包含既有双端键盘动画和 Search 进出详情的回归。`flutter analyze --no-pub` 无问题；未更新 golden。
- **模拟器：**隔离 test／Debug-test 预览构建成功并安装到同一 Duo，版本仍为 1.0.7+213。产物来源为 `72b293fd` 加本轮未提交改动，不能标为纯提交构建；已安装 Flutter kernel 与构建产物 SHA-256 一致，记录见 `pinned-detail-installed-identity.json`。从 Search 点击用户截图中的 Fuecoco - 126/M-P，实际拖动右侧至 Market Prices／Shop 后，左侧卡图、返回和 VIEW SOLD LISTINGS 按钮位置保持不变。
- **证据：**本机 `/private/tmp/kd-iphone-duo-adapted/` 保留 `pinned-detail-before.log`、`pinned-detail-ime.log`、`pinned-detail-regression-final.log`、`analyze-pinned-detail-final.log`、`build-pinned-detail-final.log`、滑动前后的 `pinned-detail-before-scroll.png`／`pinned-detail-after-scroll.png` 和展示缩略图 `pinned-detail-preview.png`。
- **Code Review：**自审通过，检查了左右滚动隔离、窄屏与短高度回退、稳定 Key 的作用域、下拉刷新、主滚动容器及键盘编辑状态；修改仅涉及详情布局、对应测试和本方案文档。
- **边界：**本轮仅改 Flutter 布局，未修改 Android 原生／SDK／签名配置；完成双端 widget 回归，未重建本轮 Android APK 或进行 Android 设备运行。iOS 继续保留第 8 节 OCR 预览例外，本次结果只证明所述 UI 行为。未提交／推送 Git、发布商店制品或改动远端环境。

### 9.6 Profile 宽屏分区（2026-11-18）

用户要求重新整理 Duo 的 Profile 页面。原来整个 Profile 在共享壳层限宽 560，展开后仍是窄长列表，支持和法律入口落在首屏之外。本轮为布局迭代：页面自行管理阅读宽度，安全区内宽度至少 840、扣除上下安全区后高度至少 528 时使用最大 1040 的双栏；左侧从上到下为免费用户的既有会员卡片、Account 账户卡片、独立的 Subscribe／Restore 分组、退出或删除入口及版本号，右侧为支持和法律条款。两栏间距 32，常用入口使用最小 64 高的紧凑行，保留原有字号、图标、暗色卡片和品牌色；文字增大时由内容自然撑高，并可整页滚动。Duo 右栏导航模式下移除 Profile 的底部导航预留空白。

窄窗口及短高度仍采用最大 560 的单列及原始会员 banner、分组和行高。页面状态、下拉刷新、账号／恢复购买、客服、评分、分享、条款、退出／删除及版本入口沿用当前回调；Android 仍隐藏 Apple 订阅和恢复入口，保留竖屏／免费首版规则。账户和反馈详情页继续采用原 390 画布。

- **回归：**`flutter test --no-pub test/widget/auth_profile_test.dart test/widget/app_shell_test.dart test/widget/kando_responsive_test.dart` 为 154 项通过、5 项失败，退出 1。5 项均为既有 golden 差异；本轮实际截图与上一轮保存的未修改基线逐字节一致，包含 Profile banner、导航及订阅 sheet／成功页，没有更新或放宽 golden。新增 3 项专项用例全部通过，覆盖 iOS／Android 宽屏首屏入口可达、原生动作与分享定位调用、窄屏状态延续，以及 Premium、短高度和双倍文字场景。`flutter analyze --no-pub` 无问题，退出 0。
- **Code Review：**自审通过：只解除共享壳层对 Profile 的固定限宽，其他主 Tab 的 1200 上限不变；Profile 自行保证窄屏／短窗口最大 560，账户及反馈详情仍为 390。所有动作沿用原回调，恢复过程的遮挡与返回阻断保留。未修改 API、平台判断、原生方向或商业策略。
- **验证边界：**本轮为 Flutter 页面布局，Android 完成相关 widget 回归，未重建 APK 或运行 Android 设备；真实购买／恢复、OAuth、删除及分享发送没有操作。模拟器沿用第 8 节的 ML Kit 隔离 UI 预览工程，不能用于完整扫描／OCR 验收。未提交／推送 Git、部署远端或发布商店制品。

- **模拟器实测：**Xcode test／Debug-test／arm64 构建成功，版本 1.0.7+213；已顺序安装并启动 Duo，关闭启动订阅页，进入 Profile，展开内屏后确认双栏及右侧导航完整显示，账户、支持、条款、删除入口与版本号在首屏可见。已安装 Flutter kernel 与本次产物一致，SHA-256 为 `f69b2286f4a9be30e964e2ceb6772f8502cc65fecfa704e2db708c4d96fea621`；来源为 `72b293fd` 加未提交的详情／Profile 改动。模拟器保留在此页供用户查看。
- **证据与清理：**本机 `/private/tmp/kd-iphone-duo-adapted/` 保留 `profile-layout-focused-final.log`、`profile-layout-regression.log`、`profile-layout-golden-comparison.json`、`analyze-profile-layout.log`、`build-profile-layout.log`、`profile-layout-installed-identity.json`、`profile-layout-inner.png` 和 `profile-layout-preview.png`。构建结束后清理本任务编译中间文件／模块缓存及测试诊断转储，保留最终安装包、隔离原生工程、旧预览和验证证据，不影响 Android 制品或共享缓存。

同日按用户反馈，将宽屏左侧的会员卡片与账户分组互换：会员卡片在上、账户／恢复购买在下，间距仍为 32；Android 和 Premium 无会员卡片时没有额外空白。仅调整现有排列及对应断言，`flutter test --no-pub test/widget/auth_profile_test.dart --plain-name 'wide Profile'` 3 项通过，`flutter analyze --no-pub` 无问题，均退出 0；未重复上一轮整套 golden。自审确认窄屏、平台策略及回调保持原样。重新构建并安装同一隔离预览包后，已实际核对 Duo 展开内屏的卡片顺序，模拟器停在 Profile。安装 kernel 与产物一致，SHA-256 为 `ef1957e59376d40f76eb42f6c314028897b631b04ce393787af2d87170c339d9`。本机证据使用 `profile-banner-top-*`、`analyze-profile-banner-top.log` 和 `build-profile-banner-top.log`；清理本次无活动依赖的编译中间文件／模块缓存，保留最终包及证据。Android 未重建或上机、ML Kit 预览例外及未提交／推送／发布边界沿用上段。

随后按用户要求，将 Restore 从 Account 卡片中拆出，恢复独立卡片及原有 `SUBSCRIBE` 标题，放在 Account 下方，分组间距 24；会员卡片继续置顶。复用同一 Restore 回调，Android 继续隐藏该分组。上述 3 项相关布局测试及 `flutter analyze --no-pub` 再次通过，退出 0，自审通过；未重复整套 golden 或重建 Android APK。隔离 UI 预览构建、安装和启动成功，已目视确认 Duo 内屏的会员卡片、Account、Subscribe／Restore 顺序及首屏可达，模拟器停留在此页。已安装 kernel 与产物一致，SHA-256 为 `a5aac13c15ca8b6cbf509ec94f5cb15cd3f30b7366c26ea70e19158b89178625`。本机证据使用 `profile-restore-section-*`、`analyze-profile-restore-section.log` 和 `build-profile-restore-section.log`，仅清理本次无活动依赖的编译中间文件／模块缓存，保留最终包与截图。其余验证和发布边界沿用上段。


### 9.7 折叠外屏恢复两列（2026-11-18）

用户截图中 Collection 外屏显示单列。实际 466 宽扣除右安全区 84 和页面左右各 20 后，网格净宽为 342；旧公式将卡宽 170 作为硬下限，连同列间距 10 要求至少 350 才能显示两列，导致 Search 和 Collection 外屏均降为一列。修复前在相同尺寸／安全区下，iOS 和 Android 共 4 项页面测试均失败，首两张卡纵向分开 388，证实根因。

共享网格保留宽屏原有列数计算，仅在局部净宽至少 320 时保证两列；宽度门槛继续随文字倍率提高，极窄或大字体可回到一列。Duo 外屏卡宽为 166，展开仍四列；卡片样式、行距、字号、图片比例和操作逻辑沿用原组件。Search、Collection 的 Portfolio／Wishlist 以及使用同一网格的 Set Detail 均在影响范围内；导航、方向、API、数据及双端商业策略不变。

- **回归：**修复前失败的 4 项 Duo 页面测试在相同尺寸／安全区下全部通过；Search 搜索词及页面 State、Collection 的 Portfolio／Wishlist 和页面 State 在折叠／展开后保持。完整受影响命令 `flutter test --no-pub test/widget/search_page_test.dart test/widget/collection_page_test.dart test/widget/set_detail_page_test.dart test/widget/kando_responsive_test.dart` 共 115 项全部通过，退出 0；包含 320 净宽两列、300 净宽单列、大字体单列及操作／价格区域不越界，普通手机和 Set Detail 原有尺寸回归通过。`flutter analyze --no-pub` 无问题，退出 0。
- **Code Review：**自审通过。两列下限只影响原公式会产生一列且满足紧凑宽度门槛的场景，三列及以上的计算保持原样；文字缩放和卡片高度规则保留。共享修复覆盖三个直接调用方，不增加设备型号判断、不修改卡片或页面业务。双端完成 widget 回归；本轮未重建 Android APK 或运行 Android 设备。

- **模拟器实测：**同一隔离 test／Debug-test／arm64 预览包构建成功并安装启动，版本 1.0.7+213，来源为 `72b293fd` 加未提交改动；已安装 kernel 与产物一致，SHA-256 为 `30b77d14122fdf160bb1b8203812f010c52cbfed2dccd5616d512182e1882dcf`。实际查看 Search 和 Collection，外屏均为两列、展开均为四列；重新折叠后 Collection 仍保持两列及原 Main 文件夹／7 张卡，未操作收藏写入。最终停留在折叠 Collection。部分卡图显示既有占位图，本轮只验收网格布局。
- **证据与边界：**本机 `/private/tmp/kd-iphone-duo-adapted/` 保留 `folded-grid-before.log`、`folded-grid-focused.log`、`folded-grid-regression.log`、`analyze-folded-grid.log`、`build-folded-grid.log`、`folded-grid-installed-identity.json`、`folded-grid-search.png`／`folded-grid-collection.png`、两页 `*-open.png` 与并排预览 `folded-grid-preview.png`。保留第 8 节 ML Kit 隔离 UI 预览例外；未进行完整扫描／OCR、真机或 Android 上机验证，未提交／推送 Git 或发布远端。
- **清理：**确认无活动 xcodebuild 后，仅删除本任务 DerivedData 的编译中间文件、模块缓存和索引，释放约 1.23 GB；最终 Runner.app、隔离工程、日志截图、旧验收证据与 Android 制品均保留，删除结果记录在 `folded-grid-cleanup.json`。最终 `git diff --check` 通过。


### 9.8 Overview 固定顶栏与左侧资产区（2026-11-18）

用户要求展开内屏 Home 的 Overview 仅右侧 Most Valuable／Trending Today 区域上下滚动。原实现把顶栏、左右两栏放入同一 SingleChildScrollView；在 951×669／右安全区 84／底安全区 34 下，iOS 和 Android 的修改前测试均复现：右侧上滑 180 后，Overview 顶部从 8 移到 -172。当前仅在满足第 9.2 节空间条件的 Overview 双栏中，将右侧列表作为主滚动区；顶栏和左侧资产／图表处于滚动容器之外，左右模块位置、间距、字号和样式保留。下拉刷新仍通过该主滚动区使用原回调；Performance、窄屏和空间不足时继续整页滚动。平台方向、免费／订阅策略、API 和数据未改。

- **专项回归：**7 项全部通过，包含 iOS／Android 右侧上滑时顶栏、货币、文件夹和图表矩形不变、左侧手势不移动页面、右侧下拉触发原刷新、短窗口／外屏／1.2 倍字体回到整页滚动、空收藏两个主动作可达，以及折叠前后页面、主滚动和横向卡片 Scrollable State 与横向位置保持。初始空态测试的 iOS 默认测试字体引起虚假换行，改用既有生产字体加载辅助后通过；没有修改生产字体／卡片样式。
- **额外压力检查边界：**曾测试 1.5 倍文字；旧源码的同尺寸重放同样复现顶栏标签、固定高度卡片的溢出，证据保留在 `home-pinned-large-text-baseline.log`。本轮未扩大修改这些既有固定字号／高度组件，不能把 1.2 倍专项通过扩展为任意大字体已验收。
- **底部空间修正：**初版模拟器检查发现右侧仍有底栏留白。LayoutBuilder 内的局部 context 已被 SafeArea 清除右安全区，导致侧栏判断误用底部 132 预留；改为使用页面原始 context，侧栏模式按底部安全区保留 34。新增滚动区底边断言在修复前 iOS 为 537、预期 635，Android 保持 537；修复后两端均通过，同组 7 项专项再次全部通过。失败证据为 `home-pinned-padding-before.log`。

- **完整受影响回归：**底部空间修正后重新运行 `flutter test --no-pub test/widget/home_page_test.dart test/widget/app_shell_test.dart test/widget/kando_responsive_test.dart`，最终为 104 通过、5 失败，退出 1；5 项均为既有 golden 差异，对应 6 张本次实际图片与先前保存的未修改源码基线再次逐字节一致，没有更新 golden。初次扩展回归中，新测试提前加载真实字体影响后续两个旧几何断言；将这组使用字体加载的新增测试放到既有测试之后，恢复测试隔离，两个断言重新通过。`flutter analyze --no-pub` 再次无问题，退出 0。失败图像已归档，按 Git 跟踪状态仅清理本轮生成的未跟踪诊断。
- **Code Review：**自审通过。确认五个既有分区的参数与回调除格式外一致，布局仅在 Overview 满足宽高条件时分离；顶栏及资产区不在右侧主滚动的祖先链中。检查了空收藏 410 高面板所需的额外空间、底部安全区／导航预留、文字倍率、下拉刷新通知和 State 在宽窄切换中的连续性。未修改共享壳层或其他页面源码；Android 方向、免费策略与 iOS 订阅策略保留。未重建 Android APK 或运行 Android 设备。
- **模拟器实测：**底部空间修正后的隔离 test／Debug-test／arm64 UI 预览构建成功，顺序安装并启动同一 Duo，版本 1.0.7+213；来源为 `72b293fd` 加未提交改动。安装 kernel 与批准产物 SHA-256 一致，为 `615cfb1d48f075e817796ac9eed6aec664d5bc78a391c5b7053186051bc78036`。展开 Overview 后，实际向上拖动右侧列表，Most Valuable 和 Trending Today 一起移动，顶栏、货币按钮和左侧资产／图表固定；右侧延伸至底部安全区。滑动前后截图对比，顶栏及左侧内容区域像素完全一致，右侧发生变化。最终停留在展开 Overview，没有操作购买或收藏写入。
- **证据与边界：**本机 `/private/tmp/kd-iphone-duo-adapted/` 保留 `home-pinned-focused-final.log`、`home-pinned-regression-final.log`、`home-pinned-golden-comparison.json`、`home-pinned-golden-evidence.zip`、`analyze-home-pinned-final.log`、`build-home-pinned-final.log`、`home-pinned-installed-identity.json`、`home-pinned-before-scroll.png`／`home-pinned-after-scroll.png`、`home-pinned-scroll-comparison.json` 和 `home-pinned-preview.png`。第 8 节 ML Kit 隔离 UI 预览例外继续适用，不代表完整扫描／OCR 或真机验证；Android 完成 widget 回归，未重建 APK 或上机。未提交／推送 Git、改动远端环境或发布商店制品。
- **清理：**确认构建／测试进程已结束后，删除本任务 DerivedData 的编译中间文件、模块缓存和索引，释放约 1.32 GB，四个目标目录均已不存在；保留最终 Runner.app、隔离工程、Android 制品及上述证据。清理结果见 `home-pinned-cleanup.json`；最终 `git diff --check` 通过。

### 9.9 Scan 6:4 取景与队列双栏（2026-11-18）

用户批准扫描页采用左侧取景、右侧操作与结果队列的方案，并指定取景占 60%、右侧占 40%。当前按安全区内宽度减去左右各 20 和栏间距 24 后分配 6:4；顶部关闭与 Scan cards 标题独立，左右面板顶部对齐，底部在系统安全区外额外留 8。扣除边距后的宽度至少 800、面板高度至少 440 时采用双栏，门槛随文字倍率提高；外屏、短窗口或字体放大导致空间不足时保留原单列布局。

- **取景与交互：**左侧取景框居中，保持原 254:363 比例，最大占相机面板高度 80%；右侧顶部为卡牌类型和闪光灯，底部固定相册、快门和 Done，中间结果队列独立纵向滚动，保留结果状态、删除、重试、手动搜索、Review 和总额。空队列显示简短提示。
- **坐标与平台：**绘制、动画与拍照共用相机面板的局部 viewport／取景框坐标，经现有 BoxFit.cover 裁剪映射；保留窗口变化时丢弃过期拍照结果的保护。iOS 免费额度与升级入口保留，Android 按现有免费首版策略隐藏；两端方向、识别协议、权限、队列上限和业务回调不改。折叠重排保持 ScanPage State 和活动队列，不因窗口变化重开相机会话。
- **专项验证：**iOS／Android 共 6 项通过，覆盖 6:4 与安全区、类型／闪光灯、局部拍照参数、8 项队列独立滚动、折叠往返保持会话／队列、删除与 Review，以及窄屏／短窗口／1.2 倍文字回退。测试使用生产字体；相册测试按既有关闭再重开相机流程提供新会话，并允许纵向懒列表回收已滚出视口的首项。
- **受影响回归：**`flutter test --no-pub test/widget/scan_page_test.dart test/scan_native_image_processor_test.dart test/scan_orientation_test.dart test/scan_result_source_test.dart test/scan_mask_geometry_test.dart` 最终 196 通过、5 失败，退出 1。5 项均为原有 iOS golden 差异；本次扫描前、拍摄、识别、揭示和 Review 的实际图像与先前保存的未修改源码基线逐字节一致，不更新 golden。局部相机面板的原生归一化裁剪参数、旧异步扫描／失败重试／额度、双端方向与蒙版测试通过；`flutter analyze --no-pub` 无问题，退出 0。
- **Code Review：**自审通过。显示和拍照共用 `_scanCameraLayout`，窄屏继续调用原几何；相机与动画均限制在同一局部面板。宽窄布局复用同一结果过滤、排序、总额与动作回调，固定控件不在结果 ListView 的祖先链内；未修改相机会话生命周期或识别原生实现。检查了空队列、处理状态、列表惰性回收、删除及 Done 门禁、折叠时相机与队列连续性和文字／短窗口回退。普通屏幕的 5 张实际图像保持字节一致。
- **模拟器安装与实测：**隔离工程的 test／Debug-test／arm64 UI 预览构建成功，顺序安装并启动 Device Hub 的 iPhone Duo（iOS 27.1，`A9D96BD2-F97C-42A6-9047-FDC8F0781675`）；Bundle `com.kando.kandoApp.beta`，版本 1.0.7+213，来源为 `783283a3` 加本轮未提交改动。安装 kernel 与构建 SHA-256 一致，为 `220173611cb899bd731b0554aff415c6afb894e7f23e8babba0825b67449ba2e`。实际确认展开时左侧取景／右侧操作与空队列、折叠恢复原单列、再次展开恢复双栏，以及 TCG／Sports Card 菜单切换；最终停留在展开的 TCG 扫描页。未拍照识别、选相册上传、购买或写收藏。
- **证据与边界：**本机 `/private/tmp/kd-iphone-duo-adapted/` 保留 `scan-split-focused.log`、`scan-split-regression.log`、`scan-split-golden-comparison.json`、`scan-split-golden-evidence.zip`、`analyze-scan-split.log`、`build-scan-split.log`、`scan-split-installed-identity.json` 和展开／折叠／预览截图。第 8 节省略 ML Kit 的隔离 UI 预览例外继续适用，不能代表完整原生 OCR／真实相机裁剪／识别已验收；这部分需真机补验。Android 完成共享 widget／裁剪／方向回归，未重建 APK 或运行折叠设备；安卓实机效果仍待补验。未提交／推送 Git、发布远端环境或商店制品。
- **清理：**确认本任务构建／测试已结束，删除 DerivedData 的编译中间文件、模块缓存、SDK 统计缓存和索引，移除约 0.96 GB 文件，磁盘可用空间增加约 1.02 GB；四个目标目录均不存在。保留最终 Runner.app、隔离工程、Android 制品和验证证据，本轮生成的未跟踪 golden 诊断已先归档再清理，跟踪文件保留。清理结果见 `scan-split-cleanup.json`。

2026-11-18 按用户要求为右侧操作区和左侧能显示相机画面的完整预览面板添加临时红色边框，以观察真实布局边界：仅 Debug 双栏显示 2 逻辑像素红框，分别使用相同 sidebar／preview 矩形叠加 IgnorePointer，不占布局空间，也不拦截点击；原取景框四角保留，Release／窄屏不显示红框。两端共享相同调试行为，原安全区、6:4 比例、业务和方向策略保留。

红框增量已重新通过 iOS／Android 6 项 Duo Scan 专项及 `flutter analyze --no-pub`；自审确认两个标记使用原面板矩形，IgnorePointer 不截获操作，未更改布局约束。接到左侧补充要求后中断了仅右侧红框的构建，随后包含两侧红框的构建成功并安装同一模拟器，kernel SHA-256 与产物一致，为 `6bf2b8c478899a4ed2417b16a45737e7bf81ebe9a452bf2d105b113cd11e6e60`。Device Hub 实际已显示左侧完整相机面板和右侧操作区的红色外框，内部黄色取景四角保持，最终停留在展开扫描页。相关日志、身份、截图和清理证据为本机上述目录的 `scan-border-focused.log`、`analyze-scan-border.log`、`build-scan-borders-final.log`、`scan-borders-installed-identity.json`、`scan-borders-open.png`／`scan-borders-preview.png` 和 `scan-borders-cleanup.json`。确认本轮构建／测试结束后再次清理四个编译缓存目录，保留 Runner.app 和证据；未重建 Android APK／运行 Android 真机，完整扫描／OCR 预览例外继续适用。

2026-11-18 按用户标注收紧双栏下方留白：两侧面板底部额外间距从 24 减至 8，保留系统底部安全区／键盘避让；Duo 951×669、底部安全区 34 时，红框底边从 y=611 下移至 y=627，距屏幕底部由 58 减至 42。6:4 宽度、顶部位置和两侧临时红框保留；普通单列分支和平台方向／商业策略不改。

该底部间距增量已通过 iOS／Android 6 项 Duo Scan 专项（包含两侧底边 y=627、相机局部裁剪参数、滚动／折叠连续性与回退场景）及 `flutter analyze --no-pub`。自审确认只收紧双栏面板下方额外间距，画面和拍照仍共用同一几何；未改变单列底部控件、平台方向或额度规则。

底部留白版隔离 UI 预览构建成功，安装并启动同一 Duo／1.0.7+213；安装 kernel 与构建一致，SHA-256 为 `2298fd20b58386084e477e8c28628fa4a2f1d1c3265176d47bad9885537a6f7f`。Device Hub 交互中已目视确认展开扫描页两侧红框底边下移、底部空白缩小；Agent 未操作拍照、相册、购买或收藏写入。证据保留 `scan-bottom-gap-focused.log`、`analyze-scan-bottom-gap.log`、`build-scan-bottom-gap.log`、`scan-bottom-gap-installed-identity.json` 和 `scan-bottom-gap-cleanup.json`；后续捕获到其他页面的截图不作为本次布局证据，已清理。确认构建／测试结束后移除四个编译缓存目录，约 0.96 GB 文件，保留最终 Runner.app。未重建 Android APK／运行 Android 真机，隔离包完整扫描／OCR 未验收边界继续保留。

### 9.10 Scan Review 底部操作区宽度与调试边界（2026-11-18）

用户标注扫描结果小卡片进入的 Review 页面，底部操作区比上方内容少占右侧空间。定位到外层 SafeArea 已避让安全区，而 Footer 为读取键盘状态恢复完整 MediaQuery 后，再次通过内部 SafeArea 应用左右安全区；Duo 951×669、右安全区 84 时，iOS／Android 修改前回归均复现删除按钮右边缘为 773，预期与上方内容对齐为 857，重复避让正好 84。

首轮 Footer 依赖既有外层安全区，移除内部重复的左右和底部避让；内容当时保留原左右各 10、底部 8 的间距。键盘出现时隐藏操作栏、单张／批量添加删除、保存状态和平台业务规则保持。首轮按用户要求移除相机预览与队列面板的两侧红框，仅对 Review 整块底部操作区添加 Debug 前景描边，不参与布局、不截获点击；后续间距收紧及全部红框移除见本节末尾。

用户继续指出批量按钮下方留白偏大：修改前两端回归均确认最后一排操作按钮底边为 y=593，预期只应用一次底部安全区后为 y=627，重复量正好 34。现已移除 Footer 内重复 SafeArea，由外层统一避让；按钮距屏幕底部为系统安全区 34 加内容边距 8，共 42。单卡时批量按钮与 6 间距原本就不构建，不占高度；列表固定底部滚动预留 170 本轮保留，与操作区的安全区重复是独立设置。

- **验证与 Code Review：**最终 iOS／Android 8 项 Duo Scan／Review 专项全部通过，含单张与多张经结果小卡片进入 Review 后的左右对齐、最后一排按钮底边为 y=627。受影响完整回归 `flutter test --no-pub test/widget/scan_page_test.dart test/scan_orientation_test.dart` 为 174 通过、5 项 golden 失败，退出 1；四张扫描实际图像与未修改基线逐字节一致，Review 比基线多出 1,952 个差异像素，全部为本次要求的纯红调试描边，未修改 golden。`flutter analyze --no-pub` 无问题，退出 0。自审通过：外层统一安全区、Footer 原间距和动态高度、键盘隐藏判断、保存状态与全部业务回调保持；删除的内部 SafeArea 是重复避让的唯一根因，移除两侧取景红框不改变拍照几何。
- **本机 UI 交付：**为保留用户当前两张活动扫描结果，本轮通过 `flutter attach` 对现有 Duo Debug 会话热更新，未重装／重启 App，未执行扫描、相册上传、添加或删除收藏。系统 Bonjour 未自动发现调试会话，改用该本地 App 既有调试服务直连；热更新成功后在 Device Hub 目视确认 Footer 红框覆盖完整安全宽度，按钮下方仅余 8 内容边距。断开调试客户端后原 App 进程 36322 仍运行，队列保留。此状态为运行中热更新，重新启动仍加载先前已安装包；最新源码的隔离 UI 预览 Runner.app 已另行构建成功并保留，版本 1.0.7+213、kernel SHA-256 `84b1134b1cca2def0e72a3a44cff4e7c3cf8dc42c8b6685e3cab4c399cb67fdd`，尚未安装，以免清空本轮临时队列。不将热更新与重新安装身份核验混报。
- **证据与清理：**本机既有临时目录保留 `scan-review-width-before.log`、`scan-review-bottom-before.log`、`scan-review-width-focused.log`、`scan-review-width-regression.log`、`analyze-scan-review-width.log`、`scan-review-width-golden-comparison.json`／`scan-review-width-golden-evidence.zip`、`build-scan-review-width-final.log`、`scan-review-hot-reload.json`、`scan-review-width-final-open.png`／`scan-review-width-final-preview.png` 及 `scan-review-width-cleanup.json`。已先归档再移除本轮未跟踪 golden 诊断；删除临时调试连接发现信息和 PID 文件。确认调试客户端、构建／测试均已结束后，清理四个编译缓存目录，保留最终包和截图。Android 未重新构建 APK 或运行真机，隔离预览的完整扫描／OCR 未验收边界保留；未提交／推送或发布任何远端环境。

2026-11-18 后续收紧：用户在模拟器确认仍有空白，并明确只去掉红框内的底部留白、保留框外系统安全区。重新截图确认原 8 内容边距仍在，批量 OutlinedButton 还有 40 可见高度与 48 点击占位之间的下方 4 透明空间；本轮将 Footer 底部内容边距改为 0，两个批量按钮可见最小高度设为 48，使其可见边界填满既有点击占位。单卡主操作仍为 56 高；两端共享该布局，系统底部安全区 34 保留，最后一排按钮可见底边与红框底边均为 y=635。顶部和左右间距、回调、键盘隐藏与单张／多张业务规则保留。

修改前同一 iOS／Android Review 回归已复现 y=627 而期望 y=635，失败证据为 `review-footer-gap-before.log`；回归同时检查最后一排每个按钮的实际 Material 可见边界与 Footer 底边对齐，且可见高度至少 48，避免仅验证外层点击框而漏掉透明占位。

- **验证与 Code Review：**`flutter test --no-pub test/widget/scan_page_test.dart --plain-name 'Duo ' --reporter expanded` 的两端 8 项通过，退出 0；Review／批量操作相关回归（`--name '[Rr]eview|bulk actions'`）49 项通过、1 项旧 Review golden 失败（23,605 像素差异，未更新基线），退出 1，覆盖单张／多张、键盘、候选加载、关闭和失败保存。`flutter analyze --no-pub` 无问题、退出 0，`git diff --check` 通过。自审通过：0 底部内容边距只收紧 Footer；批量按钮可见高度从 40 补到既有 48 点击占位，没有缩小触控目标；单卡 56 高、左右 10、顶部 10、批量行间距 6 以及安全区与业务回调保持。此次未重跑其余页面和全量测试，未构建或上机验收 Android APK。
- **本机交付与清理：**同一 Duo／App 进程 36322 成功热更新 1 个库，截图确认批量按钮可见底边与红框底边贴合，框外 34 安全区保留、两张扫描结果仍在；没有重装／重启，也没有扫描或收藏写入。首次调试连接的默认 widget tracking 与隔离包的 false 不一致，触发调试字段查找异常；按隔离包实际配置重新连接并使用 `--no-track-widget-creation` 热更新后恢复，最终没有该异常。断开调试客户端后原 App 仍运行。此次未构建新包，重启后仍回到先前安装版本。证据为 `scan-review-user-gap-current.png`、`review-footer-gap-after.png`／`review-footer-gap-preview.png`、`review-footer-gap-focused.log`、`review-footer-gap-regression.log` 和 `analyze-review-footer-gap.log`；本轮 Review golden 诊断归档后移出仓库，临时编译输出在调试客户端结束后清理。其他任务的既有失败图与可复用缓存保留；未提交／推送或发布远端环境。

2026-11-18 用户确认间距后要求删除红框：移除 Review Footer 的临时 Debug DecoratedBox 描边，将区域 Key 保留在原 Material 上用于既有布局回归；最终 Scan 与 Review 均无临时红框。既有布局、间距、安全区和业务动作保持。

移除红框后，两端 8 项 Duo Scan／Review 专项和 `flutter analyze --no-pub` 均通过、退出 0，`git diff --check` 通过；未新增测试。自审确认只移除绘制层、保留 Material 与区域 Key，无尺寸或业务变化。当前 Duo 进程 36322 成功热更新 1 个库，未重装／重启；用户当前位于 Scan 且有 6 项活动扫描，未为截图切页或操作队列。运行截图仅显示 Scan，不作为 Review 外观验收证据；Review 几何由既有两端回归检查。证据保留 `review-footer-no-border-tests.log`、`analyze-review-footer-no-border.log`；调试客户端断开后确认 App 仍运行，删除两张无关运行截图与临时连接信息。未重新构建安装包、运行 Android 设备或重跑全量／golden；此前 golden 差异未在本轮关闭。未提交／推送或发布远端环境。
