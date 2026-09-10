# v1.1.0 发布与验证记录

本页维护版本管理、向量识别、Singular 收入及 dev 合并发布的验证证据。代码与本地验证、服务端部署、客户端发布和真机验收分别记录，不能互相替代；下文每次测试与发布结果只对应其注明的提交、日期和环境。

## 扫描结果遮挡取景框修复（2026-09-10，本地未发布）

用户报告 iPhone 12 相机识别完成后，底部结果卡片遮挡黄色取景框，并要求兼容其他机型。用户图片未提供已安装 App 的版本或 iOS 版本；本地复现基于 `dev@075db55`、App `1.0.2+132`、Windows、Flutter 3.44.7 / Dart 3.12.2，以相机测试替身完成拍照与匹配，不依赖真实模型或网络。

根因是 `_scanViewfinderGeometry` 仅为底部 22 像素边距及 88 像素拍照控件预留空间，遗漏定位在安全区上方 126 像素处的结果区（16 像素统计行、8 像素间距、82 像素卡片列表）。iPhone 12 的 390×844 逻辑视口、顶部 47 / 底部 34 安全区下，原取景框底边为 613，结果区顶部为 578，稳定重叠 35 个逻辑像素；免费与 Premium 均可复现。

先失败证据：在修改生产代码前，于 `apps/flutter-app` 执行 `flutter test --no-pub test/widget/scan_page_test.dart --plain-name 'result rail never covers' --reporter expanded`，12 项中 4 通过、8 失败，退出 1；iPhone 12、iPhone 8、360×640 与 320×568 Android 的两种权益状态均未能为结果区留足间距，430×932 iPhone 与 412×915 Android 的对照用例通过。

修复将结果区实际使用的底部位置、统计行、间距及列表高度与取景框预留共用常量。结果出现前即预留完整区域，空间不足时等比例缩小取景框；布局不依赖具体机型或结果状态。影响范围为扫描页取景框、扫描线与识别遮罩的共享几何及对应回归基准；相机输入、模型推理、额度、队列、Review、确认入库、API、Schema 和部署配置变更为 N/A。

修改后验证（命令除注明外均在 `apps/flutter-app` 执行）：

- `flutter test --no-pub test/widget/scan_page_test.dart --plain-name 'result rail never covers' --reporter expanded`：12/12 通过，退出 0。覆盖上述六个竖屏尺寸、两平台及免费/Premium；首张匹配、第二张拍照期间、两张匹配及删空结果均保持取景框位置和比例，结果区与取景框/拍照按钮均留有间距。320×568 用例使用无市场报价的匹配卡，其余使用 0.13 单价，分别覆盖无总价和有总价；测试默认 Ahem 字体下的长总价横向排版不是本次修复范围。
- `flutter test --no-pub test/widget/scan_page_test.dart --reporter expanded`：最终 115 通过、3 个既有 Golden 失败，退出 1，不能记为全量通过。原有相机完整照片输入、扫描线/遮罩一致性、权限、队列、额度、Review 和保存用例通过。失败仍是 `Figma scan scanning`、`Figma recognition`、`Figma scan reveal` 的 390×844 截图比较；修改前已存在顶部额度文字差异。仅更新本次四张受影响视觉基准的取景框/遮罩布局，保留原有文字差异；逐像素回读确认三个剩余差异均与修改前完全相同，各 676 像素，位于 `(143,93)` 至 `(248,106)` 区域，无新增视觉差异。
- `flutter analyze --no-pub`：无问题，退出 0。
- `dart format --output=none --set-exit-if-changed lib/features/scan/scan_page.dart test/widget/scan_page_test.dart`：2 文件无变化，退出 0；仓库根 `git diff --check` 通过。已目视核对更新后的待扫描、扫描中、识别中和结果反馈基准，取景框下沿与结果统计/卡片分离。

Code Review 自审通过：核对取景框计算的唯一调用方、顶部与底部安全区、等比例缩放及最大尺寸、结果区实际高度与位置共用常量、无结果到连续识别的几何稳定性，以及扫描线/遮罩继续复用同一几何；未增加机型判断或改动识别输入。保留原有小屏用例对安全区、比例、扫描线/遮罩稳定性的断言，仅调整本次布局变化对应的尺寸期望。修复前相同回归用例的 8 项失败证明恢复旧预留高度会再次暴露遮挡。业务说明同步至[扫描识别](../01-flows/scan-recognition.md#扫描页布局)。

未运行：全 App/全仓测试、签名包构建、iOS/Android 真机相机验收；本次为局部 Flutter 布局修改，Windows 无法执行 Xcode，未连接测试手机。以上 Widget 尺寸与平台变体不能代替真机验收，客户端开发/测试人员需用包含修复的新包在 iPhone 12 及其他 iOS/Android 大小屏手机复测连续扫描和结果删除。代码提交与推送不代表客户端已部署或发布。

## Home 版本静默复查与详情页 Loading 修复（2026-09-10，本地未发布）

用户在 iPhone 11 的 `1.0.2 (132)` 上报告：进入 Home 后返回桌面、不杀进程，再打开 App 出现全屏 Loading；卡牌详情也出现，引导和启动订阅页不出现。设备版本已只读确认，未抓取该包切换日志。代码根因是 9 月 9 日只延后了首次激活：`_homeEntered` 一旦置为 true，所有页面 resumed 都 invalidate 版本决策，且重新请求时把上一次通过的决策置为不可用，进而显示全局 Loading。

经用户明确授权，本次保留首次 Home 检查/失败重试，后续普通复查仅在当前 Home 返回前台或从其他路由返回 Home 时触发，保留上一次成功决策并静默检查，失败不遮盖现有页面。`AppUpgradeHomeEntry` 跟踪实际路由是否为当前页及组件移除，覆盖 push/pop 的底层 Home 与 go 替换销毁的 Home。可选提示仅在 Home 展示，Home 请求离开后才返回的新提示延后处理。已在 Home 确认的强更仍全局拦截，并允许其他页 resumed 重查；失败保留强更，成功确认解除才放行。正在检查时不重复发起请求。版本比较、服务端配置、订阅/扫描业务、Home 数据刷新及 UI 视觉不变；用户原有 `pubspec.yaml` 改动保留。

先失败证据：macOS、Flutter 3.44.5 / Dart 3.12.2，`flutter test --no-pub test/app_upgrade_resume_test.dart --reporter expanded` 在修改前 1/7 通过、6 项失败（退出 1）。iOS/Android 前台复查均发现不应出现的转圈；详情 resume 请求次数错误；迟到结果用例因旧全屏 Loading 导致 pumpAndSettle 超时。修改后同一复现路径全部通过，另补充初次等待期间切页/返回不重复请求，以及已显示可选提示离开 Home 后隐藏的回归。

验证命令在 `apps/flutter-app` 执行：

- `flutter test --no-pub test/app_upgrade_resume_test.dart test/widget/app_upgrade_gate_test.dart test/app_upgrade_integration_test.dart test/widget_test.dart test/app_upgrade_policy_test.dart test/app_upgrade_repository_test.dart test/startup_subscription_gate_test.dart test/onboarding_gate_test.dart --reporter expanded`：54/54，退出 0；覆盖原有引导/订阅入口、初次失败重试、商店失败/返回、两平台强更、版本规则及本次 9 项回归。
- `flutter test --no-pub --dart-define=APP_ENV=test test/app_upgrade_resume_test.dart test/app_upgrade_integration_test.dart test/widget_test.dart --reporter expanded`：16/16，退出 0。
- `flutter analyze --no-pub`：无问题，退出 0。
- `dart format --output=none --set-exit-if-changed apps/flutter-app/lib/features/app_upgrade/app_upgrade_gate.dart apps/flutter-app/test/app_upgrade_resume_test.dart apps/flutter-app/test/widget_test.dart`（仓库根）：3 文件无变化，退出 0；`git diff --check` 通过。

Code Review 自审通过：核对当前路由判定、帧后回调及 disposed 防护、Home 多实例的进入/移除、异步请求迟到、已知强更与普通决策分离、并发请求合并及原“稍后”去重。已有启动测试只调整了返回 Home 应再次检查的次数断言，仍验证同版本不重复提示。实现限于共用版本 Gate，使用 Flutter 跨平台能力；业务与 Admin 行为文档已同步，API/Schema 变更为 N/A。未执行全仓测试、签名包构建、新包安装或 iOS/Android 真机切换/商店往返：当前手机仍为旧安装包，需客户端测试人员使用含修复的新包补验；Widget 平台变体不代表真机已通过。未修改远程规则、部署或发布。

## iOS 原始分类分数修复（2026-09-09）

问题输入为 `227.PNG`（1206×1515、EXIF orientation=1、Display P3）。电脑端同源 ONNX 检测可输出约 0.535 的分类概率并完成四角拟合与 745×1043 卡面矫正，但 iOS 相册导入在端侧检测阶段直接失败，因此请求尚未提交 Workers，管理平台不会生成扫描记录。

根因是 iOS Core ML 模型导出原始 RTMDet 分类 head，输出值是 logit；`ScanModelRuntime.swift` 此前直接把 logit 当作概率返回，而 Dart 按 0.35 概率阈值过滤。该图片约 0.535 的概率对应约 0.140 的 logit，因而被错误过滤。修复在 iOS 候选后处理对分类 logit 执行 sigmoid，候选排序保持不变，返回值恢复为与 Android/ONNX 契约一致的 0–1 概率。

影响范围仅为 iOS RTMDet 检测置信度换算；不修改相机或相册页面、图片方向与色彩解码、mask/四角拟合、透视矫正、PE-Core-T16 向量化、Android 推理及 Workers 向量检索。用户明确要求不执行验证，本轮未运行 iOS 编译、模拟器/真机复现、Flutter 测试或完整构建；Windows 环境也无法执行 Xcode/Core ML 真机路径。Code Review 核对导出脚本、原生输出和 Dart 阈值契约后，确认改动针对根因且未发现额外阻断项；真实 iOS 设备仍需使用 `227.PNG` 补验。

## 升级提示延后到 Home（2026-09-09，本地未发布）

用户明确要求升级提示在进入 Home 后显示。原 `AppUpgradeGate` 挂在 `MaterialApp.router.builder` 中，一挂载即订阅版本决策，导致 Splash、Onboarding 和启动订阅页也被升级/版本检查失败界面遮住。本次是显示时机调整，取代下方 9 月 8 日历史记录中的“启动即全局版本检查”行为。

当前 `/` 内实际 Home 内容及 `/home` 使用 `AppUpgradeHomeEntry`，在 Home 所在路由成为当前页且首帧完成后激活版本门禁。Home 前不启动该门禁的版本请求，生命周期恢复也不提前激活；其他用途的 `/app-config` 请求不受影响。门禁仍挂在 Navigator 上方，激活后继续保留强更跨路由拦截、商店返回重查、请求失败重试和本次运行同版本可选更新的“稍后”去重。外层树结构保持不变，不因激活重建 Navigator 或重置启动流程。版本判断、API、平台/环境隔离、认证及订阅权益契约不变，界面视觉不变。

先失败证据：macOS、Flutter 3.44.5 / Dart 3.12.2，使用真实 `KandoApp`、Onboarding 和启动订阅路径并注入强更决策；修改前 `flutter test --no-pub test/widget_test.dart --plain-name 'upgrade checks wait for Home' --reporter expanded` 退出 1，尚未进入 Home 即发生版本检查（预期 0、实际 1）。修改后同一用例包含于以下运行并通过。

验证命令均在 `apps/flutter-app` 执行：

- `flutter test --no-pub test/widget_test.dart test/app_upgrade_integration_test.dart test/widget/app_upgrade_gate_test.dart test/app_upgrade_policy_test.dart test/app_upgrade_repository_test.dart test/startup_subscription_gate_test.dart test/onboarding_gate_test.dart --reporter expanded`：45/45 通过，退出 0。覆盖首次引导/订阅前不提示、Premium/未知权益冷启动直接进 Home、`/home` 首次提示、稍后后离开并返回不重复、非 Home 入口延后激活、iOS/Android 强更跨路由拦截，以及原有失败/重试/商店返回逻辑。
- `flutter test --no-pub --dart-define=APP_ENV=test test/widget_test.dart test/app_upgrade_integration_test.dart --reporter expanded`：7/7 通过，退出 0，包含修正测试文件后重新验证的启动路径。
- `flutter analyze --no-pub`：首次发现新增测试的一个未使用 import，退出 1；移除后重新运行无问题，退出 0。
- `dart format --output=none --set-exit-if-changed lib/features/app_upgrade/app_upgrade_gate.dart lib/app/router.dart test/widget_test.dart test/widget/app_upgrade_gate_test.dart test/app_upgrade_integration_test.dart`：5 文件无变化，退出 0；`git diff --check` 通过。

Code Review 自审通过：检查两个真实 Home 入口、启动组件挂载顺序、帧回调 mounted/current-route 防护、只激活一次、Navigator 状态保留、原强更和稍后状态延续，未发现本次范围剩余阻断项。行为文档同步至 `01-flows/business-context.md`；API/Schema/部署文档变更为 N/A，因为未改这些契约。未运行全仓测试、签名包构建或 iOS/Android 真机验收：本次仅交付本地代码及 Widget 平台变体验证，测试人员仍需在新包中补验启动至 Home 和商店往返。未部署、发布或修改远程版本配置。

## 当前运行边界（2026-09-09 回读）

本地 `dev@b0b54df` 与 `github/dev` 一致，包含向量合并 `f38ef98`；四个已清理分支 `dev-wxy`、`dev-xiangyang`、`dev-update-dio`、`dev-scan-page-update-ui` 在本地及远程均不存在。旧分支名仅保留历史来源含义，后续开发与 dev 发布使用当前 `dev`。

| 环境 | 当前 100% 流量 Worker version | 数据与识别边界 |
|---|---|---|
| dev | `f904daec-25e6-4a0a-8001-b2ea7166197e`，创建于 `2026-09-09T03:07:51Z` | 共享 Hyperdrive、dev KV/R2、VECTOR_RECOGNITION=recognize-vec；无 D1 或 OCR_SERVICE_BASE_URL |
| prod | `934506ae-d433-4a38-ae40-6d07b109d50e`，创建于 `2026-09-07T09:24:34Z` | 共享 Hyperdrive、production KV/R2、OCR_SERVICE_BASE_URL；无 D1，尚未切换当前 dev 的向量协议 |

以上分别执行 `wrangler deployments status --env dev`、`wrangler deployments status --env prod` 及对应环境的 `wrangler versions view` 回读，命令均退出 0。较早的 `3e5d4b2d` 是本页下方合并发布时的版本，已被后续部署接替；新版本没有原合并发布 tag，本轮只核对版本与绑定，不把旧版本的 bundle/资源哈希验证外推到新版本。

`2026-09-09T03:16:45Z` dev HTTP 回读：health 为 `200/status=ok`，games 为 `200/10` 条，iOS/Google 公共配置均为 `200/no-store`，iOS 最低/建议版本 `1.0.2`、`force_update=false`，Google 规则停用，未授权 Admin 版本接口为 401。prod `/app-config` 返回 200 且两项 Singular SDK 配置非空；旧接口没有 dev 新增的 `no-store`，本轮未输出配置值。

本次文档核对没有重新部署、运行数据库迁移、修改运营配置、发送 Apple 通知或进行真实购买。`0011` 的 development 初始化与 `0012` 未执行回填沿用下方既有证据，没有重查数据库 ledger。D1 已废弃、dev/test 与 prod 均已完成 PostgreSQL 迁移；后续仅维护 PostgreSQL 内的 schema 和业务数据变更，见[数据迁移](../03-data-api/migration.md)。下文的 Golden 失败、真机待验及 SDK 收件限制仍有效。

## 验收规则

| 场景 | 当前实现要求 |
|---|---|
| dev/prod 共用数据库 | 每环境、每平台独立配置；dev 编辑或停用不影响 prod |
| 强更开启，当前版本低于最低支持版本 | 显示强更界面，只能前往更新，不能继续操作 App |
| 当前版本达到最低值，但低于建议值 | 可选择稍后更新 |
| 当前版本达到建议值，或规则明确停用 | 允许继续使用 |
| 首次版本检查失败、响应无效 | 停留重试界面，检查成功前不允许操作业务页面 |
| 强更后打开商店但未更新，或商店打开失败 | 保持拦截；打开失败可重试 |
| 返回前台、页面跳转、系统返回 | 不绕过全局拦截；返回前台重新检查配置与安装版本 |
| `1.0.1+124` 与 `1.0.1+125` | 都按 `1.0.1` 比较，不按构建号强更 |

最低版本和建议版本均为三段数字；建议版本必须大于等于最低版本。启用规则必须填写可用 HTTP(S) 下载地址。服务端只能校验地址格式，发布前仍须人工确认地址属于对应平台、环境及 App，且商店已提供目标版本。

## 根因和修复

1. 后台和公共 API 使用同一 `admin.app_version.ios/google` 键，没有环境维度。现在改为 `admin.app_version.<development|production>.<ios|google>`，只使用 Worker 可信 `APP_ENVIRONMENT`；请求参数不能选择环境。通用配置 API 不再读写版本键，防止绕过隔离和版本校验。
2. 更新组件位于 `MaterialApp.router` 的 Navigator 上方，却使用自身 context 调用 `showDialog`。真实 KandoApp 测试在 iOS/Android 都得到 `Navigator operation requested with a context that does not include a Navigator`。现在在路由上方直接渲染项目更新组件，并阻止下方页面的触摸、焦点和辅助功能访问。
3. 请求失败原先返回空配置，且仅检查一次。现在失败显式进入重试状态，返回前台重新检查，已知强更要求在重新检查失败时继续保留。
4. 原先可保存最低版本大于建议版本、空下载地址等无效规则。现在前后端都校验，服务端遇到缺失或损坏的环境规则返回 `503 APP_VERSION_CONFIG_UNAVAILABLE`，不回退到另一环境或共用版本规则。

影响范围为 Admin 版本管理、公共 App Config、Flutter 全局版本拦截和共享更新弹窗。Profile 法律链接和卡牌分享继续保留原有公共链接兜底。认证、订阅权益、卡牌数据及资产归属不变。

## 迁移、发布与回滚

- PostgreSQL `0011_app_version_environment.sql` 只新增环境配置记录，不改变表结构。旧规则一次性复制为独立记录；已存在的独立记录不覆盖，旧记录不删除。
- 分阶段仅发布 dev 时，只初始化 `development` 两条键，不提前创建 production 快照，不登记完整 `0011` 完成；prod 发布前再运行完整迁移，保留已有 dev 独立规则。初始化与发布结果须以远程复核记录为准。
- 空库初始化为四条明确停用的规则。历史仅有共用 `upgrade_prompt` 时保留原有效升级策略；历史商店兜底只在迁移时复制，运行时不再依赖共用键。
- 应先暂停版本配置编辑，执行并核验迁移，再发布 dev/prod Worker，确认两环境 API 和后台读取各自配置后恢复编辑。部署期间旧 Worker 的版本写入仍使用旧键，因此不能在迁移与切换之间编辑版本。
- 回滚必须保留迁移数据并使用支持环境键的 PostgreSQL Worker，不能回滚为重新共用版本键的实现。
- 新客户端必须在服务端迁移与配置就绪后发布。已经安装的旧客户端不能通过后台修复其导航错误；旧用户首次进入修复版本仍需商店手动或系统自动更新。

## 验证记录

环境：Windows、Node 22.20.0、pnpm 11.9.0、Flutter 3.44.7 / Dart 3.12.2；数据库测试使用实际 PostgreSQL 引擎 PGlite，不新增 D1 测试基座。

修复前证据：环境隔离集成测试 13 项中 11 项失败，确认 dev 写入改变 prod 返回值；真实 KandoApp 两平台用例均失败；网络/响应错误和前台刷新用例共 7 项失败。

| 检查 | 命令 / 证据 | 结果 |
|---|---|---|
| 环境隔离、迁移、公共配置和 Admin 路由 | `pnpm --filter @kando/workers-api exec vitest run src/app-config src/db/postgres/app-version-environment.test.ts src/admin/routes.test.ts` | 36/36，退出 0 |
| Flutter 更新及直接影响面 | 在 `apps/flutter-app` 执行下方命令 | 121/121，退出 0 |
| Flutter 测试环境挂载 | `flutter test --no-pub --dart-define=APP_ENV=test test/app_upgrade_integration_test.dart test/api_environment_test.dart test/app_debug_overlay_environment_test.dart --reporter expanded` | 6/6，退出 0；补验测试构建中两平台强更挂载、dev API 选择和调试组件共存 |
| Flutter 静态分析 | `flutter analyze --no-pub` | 无问题，退出 0 |
| Admin 测试 | `pnpm --filter @kando/admin-web test` | 21/21，退出 0 |
| TypeScript 类型 | 两应用分别执行 `type-check`；根 `pnpm type-check` | 两应用实际检查通过；根 7/7 成功，其中未变更的 5 包复用缓存；退出 0 |
| 依赖方向 | `pnpm lint` | 通过，退出 0 |
| prod 构建预演 | `pnpm --filter @kando/workers-api run deploy:dry-run:prod` | Admin production 构建及 Worker 打包通过，退出 0 |
| dev 构建预演 | `pnpm --filter @kando/workers-api run deploy:dry-run:dev` | Admin development 构建及 Worker 打包通过，退出 0 |
| Workers 全量 | `pnpm --filter @kando/workers-api test` | 610/611，退出 1；存在下述独立并发用例失败，不能标记全量通过 |
| 并发失败单独复验 | `pnpm --filter @kando/workers-api exec vitest run src/portfolio/owner-card-concurrency.integration.test.ts` | 4/4，退出 0；不抹去全量运行中的失败事实 |
| 缓存配置只读检查 | `wrangler hyperdrive get` 当前共用 Hyperdrive，只保留缓存字段 | 2026-09-08 确认 `caching.disabled=true`；没有更改远程配置 |
| 格式、文档与冻结边界 | 对修改的 Dart 文件执行 `dart format --output=none --set-exit-if-changed`；`git diff --check`；文档相对链接检查 | 通过；v1.0.0 和 v1.1.0 原始产品输入无改动 |

Flutter 验证命令：

```powershell
flutter test --no-pub test/app_upgrade_integration_test.dart test/app_upgrade_repository_test.dart test/app_upgrade_policy_test.dart test/widget/app_upgrade_gate_test.dart test/widget_test.dart test/profile_actions_test.dart test/card_detail_actions_test.dart test/widget/auth_profile_test.dart test/kando_modal_test.dart --reporter expanded
```

验证覆盖：真实 `KandoApp`/GoRouter 在 iOS、Android 的强更挂载，遮罩、系统返回和路由跳转绕过；首次请求等待与失败重试；商店打开失败、商店返回后的配置失败、更新版本后解除；支持最低版本边界、数字版本排序、构建号忽略、错误规则拒绝；320×568 大字体与长文案下更新按钮可点击。原有版本路由测试迁至 PGlite；认证/启动测试明确提供“当前版本受支持”的配置，更新拦截另由真实 App 集成测试保护。

全量 Workers 唯一失败为原有 `owner-card-concurrency.integration.test.ts` 中 Wishlist 与 Quick Collect 并发用例：预期 Wishlist 返回 `201/409`，实际 `wishlistItemResponse` 读取空记录返回 `500`。该测试及其 Portfolio、Scan、锁和鉴权调用链未在本任务中修改；单独复跑通过，当前只能确认其不稳定，未确认本轮全量失败的具体调度条件。此项作为独立问题保留，没有跳过测试或维护其旧 D1 基座。

## Code Review 与发布边界

本轮执行 Code Review 自审。审查发现重新检查时旧错误状态可能使重试按钮仍可点击，已改为请求中显示 Loading，并增加等待重试响应的回归断言；返工后重跑上述 121 项 Flutter 检查及分析，复审未发现本次改动剩余的阻断项。审查确认版本环境只能由服务端选择，旧共用键不再参与运行时读取，迁移幂等且不覆盖独立修改，全局拦截覆盖导航与输入，配置异常不再放行。未将本轮自审表述为独立评审。

## dev 发布验证（2026-09-08）

用户已明确授权提交、推送 `dev` 并部署 dev 后台。功能提交 `24216dea20f3a8ea075236da66cc92bd00673f76` 已推送到 `github/dev`；执行标准 `pnpm --filter @kando/workers-api run deploy:dev`，命令退出 0。

- 发布前使用只绑定目标 Hyperdrive 的一次性 PostgreSQL preview，在受 advisory lock 保护的事务中仅初始化 `admin.app_version.development.ios` 和 `admin.app_version.development.google`，事务外复核两条规则均合法。旧共用规则摘要在事务前后均为 `39c597361448511daca665f904327fedd10cdc1d77be817babf29992b143a811`；未创建 production 独立键，未改写旧规则，未将完整 `0011` 记入 migration ledger。preview 已关闭。
- 本次采用的 dev-only SQL 在本地 PGlite 验证了：只新增 development 两条键，旧规则和 production 不受写入；以后执行完整 `0011` 时，已独立修改的 dev 规则不会被覆盖。
- 初始化时最新 iOS 配置为最低/建议版本 `1.0.1`、强更开启，商店地址为 Card AI 的 Apple ID `6793017224`；Google 规则停用，保留原有地址。没有提高运营当时已配置的最低版本。
- Cloudflare deployment `6fde4062-783f-42d1-b3c4-dc1225f1b765` 于 `2026-09-08T03:27:20Z` 将 Worker version `e1e232ac-5799-49f7-a003-75a47db2e2b0` 置于 100% dev 流量。
- `https://api-dev.tcgcard.fun/api/v1/health` 返回 `200` / `status=ok`；`/admin` 返回 `200`，HTML 与本地 dev 构建 SHA-256 一致。全部 10 个 JS/CSS 资源返回 `200`，逐文件 SHA-256 与本地构建一致。
- dev 公共 iOS/Google 版本接口均返回 `200` 和 `Cache-Control: no-store`；iOS 返回最低/建议版本 `1.0.1` 与 `force_update=true`，Google 返回 `upgrade_prompt=null`。未授权 `/api/v1/admin/app-versions` 返回 `401 UNAUTHORIZED`。
- 发布前后 prod deployment 均为 `7cc2f8aa-613e-4da6-9828-3b33015e701d`，version `934506ae-d433-4a38-ae40-6d07b109d50e` 保持 100% 流量；prod 版本接口仍读取旧配置，未部署 prod。

dev 服务端发布与上述线上检查已完成。新 dev 使用独立环境键，prod 旧 Worker 使用旧键，双方后续版本设置分别生效。尚未运行的验收项：

- production 独立键初始化、完整 `0011` migration 登记及 prod 新 Worker 发布：不在本次 dev 发布授权范围内，须在后续 prod 发布前完成。
- 登录态线上 Admin 分环境修改/停用人工验收：未改动线上运营规则做往返测试；已有真实 PostgreSQL 路由集成测试保护环境隔离，人工验收仍须补充。
- iOS/Android 签名包、真实商店跳转和覆盖升级：需要含修复的新客户端包、对应发布渠道与真机；须由客户端发布/测试人员补验，Widget 平台变体不等于真机通过。
- Flutter 全仓测试未运行；本次执行的是列出的更新、启动、鉴权/Profile、分享与共享弹窗影响面测试。

旧 1.0.0 安装包里的导航缺陷无法通过服务端下发配置修复；只有用户安装含本次修复的客户端后，后续版本策略才能使用新的可靠拦截链路。正式启用更高最低版本前，必须确认对应商店/测试渠道已提供可更新版本。Google 当前线上地址此前只读检查指向 YouTube，且更新规则停用；迁移不会猜测或替换运营地址，启用 Google 规则前必须由产品/发布人员填写正确下载渠道。

## 更新弹窗设计修正与文案字段移除（2026-09-08）

设计真源为 [Figma 736:13370](https://www.figma.com/design/DjacfTioobtRy59SnqH7SY?node-id=736-13370)。原实现使用手机下载图标、普通弹窗配色和服务端文案，与设计中的火箭、黄绿标题和固定提示语不符。本次按用户明确变更采用该节点：342 × 452.267、16px 圆角、33px 内边距，标题 `Update Now`，提示 `New update available! Tap to upgrade`，按钮 `INSTALL / LATER`。火箭素材从 `736:13372` 原样导出为 PNG（3 倍），保存在 App `assets/ui/update_rocket.png`；Baskerville 标题复用项目已注册的 Fraunces 字体别名，正文及按钮沿用平台字体。

命中强更时移除 `LATER` 及其 56px 布局空间，保留 `INSTALL` 和全局拦截。普通更新与强更均不显示后台自定义版本说明；商店打开失败仍显示可重试提示，更新失败、系统返回、路由跳转和商店返回均不解除既有强更要求。

Admin 表单、列表结构和版本保存移除“建议更新文案”“强制更新文案”。存量 JSON 兼容读取但不展示旧文案，下一次保存时不再写入；不执行远程数据清理，不改动 `0011`。公共 API 保留旧客户端需要的 `title/message/forced_message`，值固定为上述设计文案。环境隔离、版本比较及强更条件保持不变。

失败证据：修复前 UI 测试分别确认普通/强更尺寸与设计不符、旧文案仍被 App 展示；PostgreSQL 路由测试确认 Admin 仍返回被移除的文案字段。本节是本地后续修正，不代表前述 dev 部署已包含此 UI 与字段变更。

| 本轮检查 | 命令 / 证据 | 结果 |
|---|---|---|
| Flutter 更新与共享弹窗回归 | `flutter test --no-pub test/app_update_design_test.dart test/app_upgrade_integration_test.dart test/widget/app_upgrade_gate_test.dart test/kando_modal_test.dart test/app_upgrade_policy_test.dart test/app_upgrade_repository_test.dart test/widget/auth_profile_test.dart --reporter expanded` | 107/107，退出 0 |
| Workers 配置及 Admin 路由 | `pnpm --filter @kando/workers-api exec vitest run src/app-config src/admin/routes.test.ts` | 34/34，退出 0 |
| Admin 回归 | `pnpm --filter @kando/admin-web test` | 21/21，退出 0 |
| 静态/类型检查 | `flutter analyze --no-pub`、Workers/Admin 各自 `type-check` | 均通过，退出 0 |
| UI 对照 | 原始火箭 PNG 与本地 asset SHA-256 相同；已渲染普通和强更两种 390×844 预览并与设计对照 | 火箭、标题、固定提示、按钮与布局一致；强更无 LATER，小屏大字体时 INSTALL 保持可点击 |

Code Review 自审已完成：确认只影响更新弹窗的专用样式、固定提示和后台退役文案，通用确认弹窗既有交互不变；重跑共享弹窗与鉴权/Profile 回归通过。原有强更拦截、平台和环境隔离未改动；API 兼容字段保留，已执行迁移及冻结产品输入未修改。未发现剩余阻断项。

本轮未运行全仓测试、签名安装包或 iOS/Android 真机视觉/商店验收；已有 Widget 两平台验证不替代真机。Figma 的 SF Pro 正文在 iOS 使用平台字体，Android 使用其平台字体，跨平台字形不宣称逐像素相同。后台与 API 发布情况见下方；App 界面仍需通过新客户端包交付。

### dev 后台重新发布（2026-09-08）

按用户明确授权，从与 `github/dev` 同步且工作区干净的 `aaa044317aadc23d7f33b4bd2d09a6924e725a78` 执行 `pnpm --filter @kando/workers-api run deploy:dev`，Admin development 构建、Worker 上传与触发器发布均通过，命令退出 0。

- Cloudflare deployment `c90f1d72-d248-4a15-864e-fd6bcceb9496` 于 `2026-09-08T06:17:29Z` 将 Worker version `262f177d-09e5-462c-b827-c92ea1e3958b` 置于 100% dev 流量。
- `/api/v1/health` 返回 `200` / `status=ok`；`/admin` 返回 `200`，HTML SHA-256 与本地构建一致。全部 10 个 JS/CSS 返回 `200`，逐文件 SHA-256 一致；发布的前端中已不含“建议更新文案”和“强制更新文案”表单标签。
- iOS/Google 公共版本接口均返回 `200` 与 `Cache-Control: no-store`；iOS 固定标题/提示语已生效，当前运营规则为最低/建议版本 `1.0.2`、强更开启，Google 规则停用，均与发布前读取的规则一致。未授权 `/api/v1/admin/app-versions` 返回 `401`。
- 本次没有执行数据迁移或调整版本规则。prod deployment 仍为 `7cc2f8aa-613e-4da6-9828-3b33015e701d`，Worker version `934506ae-d433-4a38-ae40-6d07b109d50e` 保持 100% 流量。

本次发布复用上述已完成的测试与 Code Review，实际执行了完整 dev 构建和部署后验证。未执行登录态后台人工编辑、App 签名包发布或真机 UI 验收，不能把后台发布视作客户端 UI 已更新。

### 更新弹窗背景渐变修正（2026-09-08）

用户反馈背景与 Figma `736:13370` 不符。重新读取原始 fills 确认设计为不透明 `#222222` 底色，加 24% 不透明度的菱形渐变；旧 Flutter 使用两个不透明近似颜色的短线性渐变。基准尺寸下部分颜色已经接近，但线性渐变在强更缩短高度、小屏缩窄宽度时改变了光感分布。以 Figma 导出截图的 9 个无内容背景点建立像素对照：修复前 `app_update_design_test.dart` 为 3/5 通过，强更尺寸和窄屏尺寸两项失败（退出 1），不是版本判断或接口问题。

当前 `KandoModalFrame` 仅在 `update=true` 时使用 Flutter Canvas 按 Figma 原始归一化矩阵绘制四个渐变象限，保留原始两色、终止位置和 24% 透明度；同时使用 1px、10% 透明度的白色到橄榄色渐变内描边。背景按实际宽高缩放，原有圆角、阴影、插画、文本、按钮布局及升级逻辑保持不变。使用跨平台绘制能力，没有新增图片、依赖或平台分支。Figma 底层填充完全不透明，背景模糊不贡献可见底色，因此未增加额外的背景采样层。

影响范围：普通和强制更新弹窗，包括全局 Gate 和 `showKandoUpdateModal` 入口。危险确认、移除确认、欢迎及失败弹窗保留原有装饰；后台、公共配置接口、环境隔离、版本比较及商店跳转契约无变更。

本次本地验证环境为 macOS、Flutter 3.44.5 / Dart 3.12.2：

- `flutter test --no-pub test/app_update_design_test.dart --reporter expanded`：修复后 5/5 通过，退出 0；覆盖 342×452.267、342×396.267 和 272×396.267 的背景颜色，以及两种按钮布局。
- `flutter test --no-pub test/app_update_design_test.dart test/kando_modal_test.dart test/app_upgrade_integration_test.dart test/widget/app_upgrade_gate_test.dart /tmp/toccards-update-background.Wh2ckI/render_upgrade_test.dart --reporter expanded`：22 项仓库回归与 1 项临时预览渲染通过，退出 0。覆盖 iOS/Android Widget 平台变体、强更拦截、商店失败/返回、刷新和小屏大字体按钮可达性。
- `flutter analyze --no-pub`：无问题，退出 0。Dart 格式检查及 `git diff --check` 通过。
- 已查看 Figma 原图、完整普通更新和强更的 Flutter 渲染对照。背景抽样 RGB 通道差值为 0～2（8 位通道）；此结论限定于背景抽样，不宣称整张弹窗或真机逐像素相同。预览只保存在临时目录，未把截图加入 `docs/`。临时预览脚本补充真实字体、图片预解码及阴影后，曾因测试结束前未恢复绘制调试变量退出 1；修正临时脚本清理后独立重跑 1/1 通过，应用代码未因此改动。

Code Review 自审通过：核对原始矩阵、颜色叠加、象限连续性、圆角裁剪及描边，确认绘制不会改变尺寸和输入处理；新增像素回归在旧实现下已有失败证据，原有交互回归通过。文档影响限于本节视觉实现和验证说明，业务/API 文档变更为 N/A。未运行全仓测试、iOS/Android 真机截图或签名包构建；客户端测试人员仍需使用包含本次修改的包补验实际设备显示。本次未发布客户端或服务端。

## Singular 套餐收入事件（2026-09-09）

产品要求将现有 Singular 套餐成功事件改为收入事件。根因是 `SubscriptionController._handleEvent` 仅调用 `trackEvent`，最终通过 `Singular.event(eventName)` 发送名称，没有调用收入 API 或传入金额、币种。修改前在 SDK MethodChannel 回归中要求收入方法被调用，稳定得到实际 0 次、预期 1 次，退出 1；这属于本地代码路径复现，没有访问真实用户交易或 Singular 后台。

现六个 test/production 套餐事件改为 `Singular.customRevenueWithAttributes`，使用既有 Apple verified Revenue 提取规则得到交易金额、币种、交易 ID 和商品 ID。复用 Revenue 串行队列与持久化实现，仅增加可选存储命名空间，Firebase 默认键与调用流程保持原样。Singular 使用独立环境键，只为当前购买界面中的 Fresh Purchase 入队；Restore、外部恢复、失败及 Pending 不入队。零金额保留为 0，缺失/错配交易字段不猜测展示价格。启动重试只处理该队列以前已记录的交易，等待 ATT 后 SDK 初始化完成，不枚举旧交易补报。支付、订阅权益、服务端、Schema 与 Google Play 购买范围无变更。

本地环境：macOS、Flutter 3.44.5 / Dart 3.12.2。命令在 `apps/flutter-app` 运行：

```sh
flutter test --no-pub test/app_attribution_test.dart test/subscription_singular_revenue_test.dart test/subscription_singular_events_test.dart test/subscription_revenue_reporter_test.dart
flutter test --no-pub test/app_attribution_test.dart test/singular_bootstrap_test.dart test/subscription_singular_events_test.dart test/subscription_singular_revenue_test.dart test/subscription_revenue_reporter_test.dart test/subscription_analytics_test.dart test/subscription_receipt_verifier_test.dart test/subscription_server_entitlement_sync_test.dart test/subscription_entitlement_lifecycle_test.dart test/subscription_sync_queue_test.dart test/subscription_restore_ui_test.dart test/startup_subscription_gate_test.dart --reporter expanded
flutter analyze --no-pub
```

结果：第一组 36/36、第二组 100/100、静态分析无问题，均退出 0；修改 Dart 文件的格式检查和仓库 `git diff --check` 通过。覆盖六个事件名、真实币种与千分之一单位换算、零收入、无效字段排除、并发回调及重建 Reporter 去重、失败待重试、Firebase 存储隔离、初始化前不发事件、缺凭据不标记交付，以及订阅/恢复/启动相邻路径。

Code Review 自审通过：对照锁定的 Singular Flutter SDK 1.9.0 Dart 与 iOS/Android 桥接确认 `customRevenueWithAttributes` 参数和方法对应；没有另发同名普通事件；原 Fresh Purchase 门禁、异步调用位置、Firebase 默认存储键和权益状态机保持原口径。SDK 方法返回 `void` 且原生桥接无成功回执，本地记录表示已交给 SDK API；桥接异步错误只提供诊断，不能宣称后台收入已验收，也不保证清数据/卸载或交付与落盘之间异常退出时的全局一次性。

真机 Debug 启动验证：使用数据线连接的 iPhone 11（iOS 18.7.8，开发者模式已开启），执行 `flutter run --debug --no-pub --flavor test --dart-define-from-file=config/test.json -d <device-id>`。Xcode 构建完成（130.8 秒），安装启动完成（30.5 秒），Dart VM Service 已连接，调试进程保持运行。读取 `build/ios/iphoneos/Runner.app/Info.plist` 和 `codesign -d --entitlements :- build/ios/iphoneos/Runner.app` 确认 Bundle ID 为 `com.kando.kandoApp.beta`、最终签名 App Attest 为 `development`、`get-task-allow=true`；`codesign --verify --strict build/ios/iphoneos/Runner.app` 退出 0。本次为签名 `.app` 真机调试，没有生成或交付 IPA。

真机周订阅补报验证：首次启动日志出现网络离线错误及 `Singular attribution disabled: runtime credentials unavailable.`。用户随后完成购买，日志收到 `status=purchased, productId=cardx.week` 且无购买错误，收入首次尝试报 `Singular revenue unavailable: missing credentials`。本机只读检查 test `/app-config` 确认响应成功、两项 Singular 配置均非空（未输出配置值）；通过 Flutter 调试会话发送 `R` 热重启后，日志依次出现 `Singular attribution SDK initialized.` 和 `Singular revenue handed to SDK: weekly_cardtest`。这验证了该次缺配置失败的收入记录在重启后重试并交给 SDK API，无须再次购买；没有取得 Singular 后台收件回执或实际金额、币种的后台核验结果，不能据此宣称收入已到账。

未运行：Singular 后台收入确认、完整 Sandbox/TestFlight 商品与恢复购买验收矩阵、Release/IPA 构建、Android 真机原生 SDK 收入验收、Flutter 全仓测试。后续由客户端测试/归因负责人使用 Singular Testing Console 的当前安装 SDID，核对本次 `weekly_cardtest` 的收入事件类型、金额、币种及交易属性，并补验其他套餐和恢复购买不新增收入。旧普通事件不自动回填价值；未执行客户端/服务端发布、后台配置写入或远程数据库操作。完整字段与范围见 [收入契约](../03-data-api/contract-changes.md)。

### Singular 首次配置失败后在当前进程恢复（2026-09-09）

根因有两处：Gateway 将首次配置请求保存为不可替换的 Future，失败得到 `null` 后，回前台和收入交付都继续读取同一失败结果；Singular 收入队列仅在订阅 Controller 启动时 flush，没有初始化恢复后的唤醒。定位时，iPhone 13 的 test 包 `1.0.1 (127)` 本地存在一笔 `cardx.week`、3.99 USD 的 Singular pending，reported 数为 0；重启同一安装后，该交易出现在 reported 中。此次 iPhone 13 首次失败的底层网络原因没有日志，不能据此断言；此前 iPhone 11 已有配置缺失导致交付失败的日志。修复前用可控配置加载器模拟“首次离线、购买入队、恢复联网但不重启”，测试稳定在预期 SDK start 1 次、实际 0 次处失败（退出 1）。

修复只涉及 `app_attribution.dart` 的配置缓存、初始化重试与生命周期，以及 `subscription_controller.dart` 中 Singular Reporter Provider 的初始化完成回调。配置成功才缓存，请求进行中合并；既有 ATT 流程之后按 5/15/30/60 秒前台退避重试，之后保持 60 秒间隔，后台暂停，回前台及收入交付可再次尝试。初始化恢复会自动 flush 已落盘的 Singular 记录。原事件门禁、Apple 校验、金额提取、持久化键、串行去重、Firebase Reporter、支付/恢复购买、权益同步、服务端和 Schema 均未改动。文档影响为配置恢复与自动补报行为，已同步 [收入契约](../03-data-api/contract-changes.md) 和 [订阅测试说明](app-store-connect-subscription-setup.md)。

环境为 macOS、Flutter 3.44.5 / Dart 3.12.2。以下命令在 `apps/flutter-app` 执行：

```sh
flutter test --no-pub test/subscription_singular_revenue_test.dart --plain-name 'retries failed startup configuration' --reporter expanded
flutter test --no-pub test/app_attribution_test.dart test/singular_bootstrap_test.dart test/subscription_singular_revenue_test.dart --reporter expanded
flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_singular_revenue_test.dart --reporter expanded
flutter test --no-pub test/app_attribution_test.dart test/singular_bootstrap_test.dart test/subscription_singular_events_test.dart test/subscription_singular_revenue_test.dart test/subscription_revenue_reporter_test.dart test/subscription_analytics_test.dart test/subscription_receipt_verifier_test.dart test/subscription_server_entitlement_sync_test.dart test/subscription_entitlement_lifecycle_test.dart test/subscription_sync_queue_test.dart test/subscription_restore_ui_test.dart test/startup_subscription_gate_test.dart --reporter expanded
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib/shared/attribution/app_attribution.dart lib/features/subscription/subscription_controller.dart test/app_attribution_test.dart test/subscription_singular_revenue_test.dart
```

结果：原失败复现修复后 1/1；针对性测试 30/30；test 环境收入测试 13/13；扩展订阅回归 106/106，均退出 0。静态分析无问题，格式检查无差异；仓库 `git diff --check` 通过。覆盖不中断进程自动恢复、多笔离线购买分别持久化、真实 Flutter 前后台事件驱动补报、重复交付去重、重试退避和后台暂停、并发请求只启动一次 SDK、最新 ATT 状态且不重复弹窗、销毁后迟到响应无副作用，以及原订阅/权益/恢复路径。新增测试过程中曾因 import 插入位置和把 SDK 附带的 wrapper-version 调用误计为 start 而失败，均已修正测试代码；没有删除业务断言或修改支付代码。

Code Review 自审通过：逐段核对配置成功缓存与失败释放、并发异步返回顺序、前后台取消/恢复、销毁检查、初始化回调与原串行队列的先后关系；确认回调不等待自身 flush、不另建交易、不更换去重键、不影响 Firebase，且 SDK 初始化仍在原 ATT 流程之后。此为自审，不是独立评审。

未运行：包含本次修复的新包 iPhone 13 断网恢复与 Singular 后台收件验收、Android 真机重试验收、Release/IPA 构建和 Flutter 全仓测试。本地测试使用模拟配置响应与 SDK MethodChannel，不能替代原生 SDK 服务端回执；客户端测试/归因负责人仍需用新包补验“首次配置失败 → 购买已入队 → 同进程恢复联网 → 自动补报”，并在 Testing Console 核对当前安装的设备标识、金额和币种。本次没有修改后台测试设备登记、发布客户端/服务端或操作远程数据库。

补充“允许联网后及时重试”验证：现有 Observer 接收所有 `resumed`，不要求先进入后台，因此没有新增业务或原生代码。将生命周期集成回归扩展为 `paused → resumed` 与系统弹窗常见的 `inactive → resumed` 两种路径；后者在首次 5 秒定时器触发前模拟请求恢复，确认收到 resumed 后立即重新请求、补报两笔 pending，交易不重复且不再次请求 ATT。`flutter test --no-pub --dart-define-from-file=config/test.json test/app_attribution_test.dart test/subscription_singular_revenue_test.dart --reporter expanded` 28/28 通过，退出 0；代码自审确认只有测试和行为说明增量。该测试验证 Flutter 信号处理，不代表已经验证 iPhone 13 联网授权弹窗一定发出此信号；系统没有发出信号时仍依赖退避重试，原生授权场景仍由客户端测试人员使用新包补验。

## No content available 弹窗标题下划线（2026-09-09）

根因：启动配置请求失败时，`AppUpgradeGate` 在 Navigator/页面 Material 之外显示共享 `KandoFailureBlock`；标题未覆盖继承的文字装饰，最终 `RichText` 带有 Flutter 默认下划线。使用既有启动检查失败测试，读取渲染文本的有效 style，修复前稳定得到 `contains(TextDecoration.underline) == true`，与无下划线预期不符（退出 1）。本地输入是模拟配置请求失败，不要求实际网络授权弹窗即可复现同一渲染路径。

修复仅在共享失败卡片的 `No content available` 标题设置 `TextDecoration.none`，正常与紧凑布局、启动遮罩及所有复用该组件的页面/弹层一起生效。文案、颜色、字号、间距、刷新回调、加载和启动拦截逻辑均未改动；业务/API/配置文档影响为 N/A，因此仅在此记录 UI 修复。

macOS、Flutter 3.44.5 / Dart 3.12.2；在 `apps/flutter-app` 执行 `flutter test --no-pub test/widget/app_upgrade_gate_test.dart --plain-name 'failed startup checks must block interaction' --reporter expanded`，原失败路径修复后 1/1 通过；`flutter test --no-pub test/load_state_test.dart test/widget/app_upgrade_gate_test.dart --reporter expanded` 13/13 通过，刷新重试和版本拦截保持原断言；`flutter analyze --no-pub` 无问题，均退出 0。测试新增断言的首次格式检查提示换行差异，执行 formatter 后重新验证。Code Review 自审通过：生产代码只增加标题的装饰覆盖，不修改全局主题或其他组件；沿用现有设计 token，未改变尺寸和交互。未运行新包的 iOS/Android 真机截图或首次联网授权流程；客户端测试人员需在下次构建中补验实际设备显示，本次未打包发布。

## dev-wxy：仅移植扫描向量识别链路（2026-09-08）

范围：以 `745138292ed7a02f62dee3c3ea78747c0b737745` 为业务基线，从 `dev-xiangyang@ceef1af08ea949d184164ad661dc6228e1cf4773` 按代码段引入 RTMDet-Ins 检测、原生透视矫正、PE-Core-T16 512 维向量化和 Workers `VECTOR_RECOGNITION` 调用。用户明确同意 iOS 16+、Android、Web 扫描暂不支持。未整体合并源分支，也未修改 dev 分支。

核心验收：新识别输入不再使用 OpenCV/pHash；No Match 和目录不完整不扣次数，完整 Matched 才消费，缺少市场价格不影响成功；现有完整候选资料、Queue、批量结果缓存、显示额度、卡号消歧、Review、确认入库及权限保持基线。详细链路和接口变化见[扫描识别](../01-flows/scan-recognition.md)。

### 根因与移植边界证据

- 源分支落后于 dev-wxy 的近期业务修复，故只复制新增识别运行时/模型/许可证/模型工具，并将旧调用替换为 embedding。扫描页改动限于删除旧识别裁剪参数，不改布局和业务状态机。
- 当前 Workers 扫描测试原本使用 FakeD1。本轮先将同一组 26 个业务用例移至 PGlite PostgreSQL，在协议切换前确认 26/26 通过，再切换向量请求与 Service Binding；切换前选择的 4 个向量用例返回 503 并失败，切换后原业务断言继续通过。没有删除或放宽 No Match、详情完整性、评级、权限、幂等或额度断言。
- 补充了非法/零/错维向量拒绝和主 API 游戏过滤测试；模型编排测试保护 BGR/RGB 顺序、归一化、角点、矫正尺寸、JPEG 质量、向量维度与低置信度失败。
- 对照基线逐段比较，`/scan/:scan_id/confirm` 路由、额度结算代码、卡号消歧和完整目录判定保持原文一致。扫描额度控制器、额度账本、Review Repository、相机/权限层、订阅、鉴权、Portfolio、Admin 和版本更新模块没有代码改动。
- 六个 Android/iOS 模型及 runtime 核心制品的 Git blob 均与 `ceef1af` 一致。Code Review 的资源核对发现 Git 将 iOS 检测模型误判为旧 OpenCV 文件的 rename，最初新增文件筛选未包含它；现已补入并复核全部模型引用和内容。

### 本机验证

环境：Windows、Flutter 3.44.7 / Dart 3.12.2、Node 22.20.0、pnpm 11.9.0；未改动这些工具版本约束。

| 检查 | 命令 / 证据 | 结果 |
|---|---|---|
| Flutter 协议、结果、几何、原生图片桥与额度 | `flutter test --no-pub test/scan_api_client_test.dart test/scan_result_source_test.dart test/scan_mask_geometry_test.dart test/scan_native_image_processor_test.dart test/scan_quota_controller_test.dart --reporter expanded` | 30/30，退出 0 |
| 模型编排与完整扫描页 | `flutter test --no-pub test/scan_card_recognizer_test.dart test/widget/scan_page_test.dart --reporter expanded` | 106 通过、3 个 Golden 失败，退出 1；其中模型编排 3/3 通过 |
| Golden 原基线复验 | 独立 detached checkout `7451382`，同 Flutter 运行上述三个 Golden 用例 | 同为 3 项失败，每张差异 0.21% / 676 像素；移植前后输出 PNG 的 SHA-256 完全相同，故本次未引入这三处差异，也没有更新 Golden 掩盖问题 |
| Workers 扫描路由与图片输入 | `pnpm --filter @kando/workers-api exec vitest run src/scan/routes.test.ts src/scan/scan-image.test.ts` | 30/30，退出 0 |
| Workers 额度与识别隐私说明 | `pnpm --filter @kando/workers-api exec vitest run src/legal/routes.test.ts src/scan/quota.integration.test.ts` | 10/10，退出 0 |
| Flutter 分析 | `flutter analyze --no-pub` | 无问题，退出 0 |
| TypeScript/依赖 | Workers `type-check`、根 `pnpm type-check`、`pnpm lint` | 通过；根 7/7，其中 5 个未改动包复用缓存 |
| Android 实际构建 | `flutter build apk --debug --no-pub --dart-define-from-file=config/test.json` | 通过，退出 0；APK 实际包含两份 ORT 模型与原生 ONNX Runtime，不含 OpenCV/libdartcv |
| Worker 构建 | `deploy:dry-run:dev` 与 `deploy:dry-run:prod` | 均通过，退出 0；确认打包配置包含 `VECTOR_RECOGNITION=recognize-vec`，没有执行部署 |

Android debug APK 为 237,880,428 字节，SHA-256 为 `04fd423431a50019b705997c7f1e8e56126d5dd69ab8bf67a40d4cc1c0f1f59d`。这只是 debug 构建结果，不代表 release 体积、商店签名或真机模型运行已通过。Gradle/AGP/Kotlin 给出后续升级提醒，本次没有扩大范围升级工具链。

### Code Review 与未验证项

Code Review 自审已核对必要移植文件与原业务保护范围；模型资源遗漏已修正并重新完成六制品核对，未发现剩余的本次代码阻断项。3 个既有 Golden 失败保留为基线问题，不计作通过。未新增数据库 Schema、migration 或数据补全，也未改写冻结产品输入。

- Windows 无 Xcode，未执行 iOS 编译、签名或真机 Core ML/Core Image 验证；需在 macOS/iOS 设备补验。
- Android 已构建，但未做设备上的实际模型加载、方向/透视效果、推理耗时、内存及真实卡牌准确率验收。
- 未执行登录态新 App → 主 API → `recognize-vec` 完整扫描、弱网端到端及新旧 App 协议切换验收；需由客户端测试人员使用新包在真机补验。当前分支不兼容旧 pHash 请求。
- 本轮只运行列出的影响面验证，没有宣称全仓测试通过。dev 发布与内部向量服务契约烟测结果见下；prod 发布未执行。

### dev 发布与线上验证（2026-09-08）

用户明确授权将当前分支部署到共用 dev 环境。发布来源为已推送的 `dev-wxy@e18543afaee9d77616bd71686cb93f8268d7754c`，部署前工作区干净。执行 `pnpm --filter @kando/workers-api run deploy:dev`，完成 Admin dev 构建与 Workers 发布，退出 0；没有合并或推送 dev Git 分支。

- Cloudflare deployment `792ad7da-8219-4f34-a4bc-b057ef387399` 于 `2026-09-08T08:06:20Z` 将 Worker version `5e332a9b-27fb-4133-9103-2909b12a230e` 置于 100% dev 流量。发布后通过 `wrangler deployments list --env dev --json` 与 `wrangler versions view 5e332a9b-27fb-4133-9103-2909b12a230e --env dev --json` 复核，均退出 0。
- 实际远端版本包含 `VECTOR_RECOGNITION=recognize-vec`，`APP_ENVIRONMENT=development`，没有 `OCR_SERVICE_BASE_URL`。沿用 dev 的 KV/R2 与既有 Hyperdrive，未执行数据库 migration 或数据回填。
- 发布前通过只绑定 `recognize-vec` 的临时 remote preview，向内部 `/recognize` 提交 512 项 `1 / sqrt(512)` 合成向量；`2026-09-08T08:04:41Z` 返回 `200` 和 10 个候选，全部满足有效 `product_id`、有限且处于 0–100 的 `confidence` 契约。探测退出 0，preview 已关闭；未创建用户/扫描记录或消费额度。该结果只证明内部服务契约可用，不代表真实卡牌准确率或 App 完整扫描已通过。
- 本次复用的 `recognize-vec` version 为 `bbb962fa-c49a-40a2-8212-25ddb7a3bb2e`，deployment 为 `6065ceed-ff8d-48e5-8d2f-988f7aa0f0b6`；没有重新发布该内部服务。
- `2026-09-08T08:10:55Z` 的部署后 HTTP 校验退出 0：`https://api-dev.tcgcard.fun/api/v1/health` 返回 `200` / `status=ok`；`/admin` 返回 `200`，包含 `Kando Admin`，HTML SHA-256 与本地构建一致；全部 10 个 JS/CSS 资源返回 `200`，逐文件 SHA-256 一致。
- 未授权 `/api/v1/admin/app-versions` 与 `POST /api/v1/scan/recognize` 均返回 `401`，验证鉴权入口有效；该检查未覆盖登录后的识别和额度业务。
- iOS/Google `/api/v1/app-config` 均返回 `200` 与 `Cache-Control: no-store`。本次检查时 iOS 最低/建议版本均为 `1.0.2`，`force_update=false`；Google 返回 `upgrade_prompt=null`。强更状态与前文历史发布时的快照不同，此处记录实时响应；本次部署没有修改后台版本规则。
- 发布前后 prod deployment 均为 `7cc2f8aa-613e-4da6-9828-3b33015e701d`，version `934506ae-d433-4a38-ae40-6d07b109d50e` 保持 100% 流量，未部署 prod。

本次发布复用上文已完成的代码验证与 Code Review，执行了实际 dev 构建、内部服务契约烟测及部署后校验。iOS 编译/签名、两端真机模型运行及 App 完整扫描仍属未验证项；测试包必须包含本分支的模型和向量协议，并连接 dev API。

### 422 协议覆盖后的 dev 重新发布（2026-09-08）

用户反馈最新 dev-wxy iOS App 扫描返回 `422 VALIDATION_ERROR`。排查发现，共用 dev 在 `2026-09-08T08:38:45Z` 被另一轮 Wrangler 发布切换为 version `3b51584d-4089-4ae5-90be-04e65abaccc4`，deployment 为 `dc3584c6-175e-4e3d-bec4-16b3ad54d170`。从 Cloudflare 下载的该版本实际代码仍读取 `r/g/b`，缺少任一值即返回 422；其配置包含 `OCR_SERVICE_BASE_URL`，没有 `VECTOR_RECOGNITION`。用户提供的请求采用新 `vector` 协议，512 项数值有限且非零，因此新 App 与当前旧 API 的协议不一致足以触发该错误。

用户随后明确要求基于当前分支重新部署 dev。发布来源为干净且与远端一致的 `dev-wxy@20db6dc45752a4af8a0a85cd5c4ffd3372d102a2`；Workers、Admin 和共享包与已验证的 `e18543a` 无差异，复用上文测试和 Code Review。本轮未修改业务代码，执行 `pnpm --filter @kando/workers-api run deploy:dev`，Admin dev 构建与 Workers 发布均成功，退出 0。

- Cloudflare deployment `d7453012-1eb3-4ec5-a2ba-60e3548cf404` 于 `2026-09-08T09:14:02Z` 将 version `f351eae7-b0d5-4c19-ac51-930452efd5f4` 置于 100% dev 流量；发布后通过 deployment/version 查询复核。
- 实际远端配置恢复 `VECTOR_RECOGNITION=recognize-vec`，不含 `OCR_SERVICE_BASE_URL`。再次下载该部署版本的实际代码，确认 `/scan/recognize` 读取 `vector`，不读取 `r/g/b`；将用户提供的同一向量交给从已部署代码提取的 `readEmbeddingVector` 校验，返回合法 512 维向量，检查退出 0（`2026-09-08T09:16:12Z`）。这只验证协议与向量参数，不等于登录态完整扫描已通过。
- 部署后 HTTP 校验退出 0（`2026-09-08T09:16:03Z`）：`/api/v1/health` 返回 `200` / `status=ok`；`/admin` 及全部 10 个 JS/CSS 返回 `200`，逐文件 SHA-256 与本地 dev 构建一致；未授权 `/api/v1/admin/app-versions` 和 `POST /api/v1/scan/recognize` 均返回 `401`。
- 本次未执行数据库 migration、数据回填或版本规则调整。prod 发布前后仍为 deployment `7cc2f8aa-613e-4da6-9828-3b33015e701d`、version `934506ae-d433-4a38-ae40-6d07b109d50e`、100% 流量；没有发布 prod 或修改 dev Git 分支。

本轮未取得失败请求的图片文件和登录态，未在线重放该用户的完整扫描；需由用户使用现有 dev-wxy 新 App 重新扫描验收。共用 dev 的运行版本取决于最后一次发布，其他仍采用 pHash 的分支再次部署到同一 Worker 会重新覆盖向量协议。

## 向量识别合入 dev（2026-09-09）

按用户授权，将 `dev-wxy` 的向量识别链路合入已同步至 `github/dev@0e3e53b` 的 `dev`。来源同时包含向量功能提交 `e18543a`、本地发布记录 `b3b1025` 和远程 Podfile checksum 修正 `221c78c`。保留 dev 的 Scan confirm 购买价格事件修复、更新弹窗背景、Card Detail 离开 Collection Item 时取消草稿以及 Singular 收入上报；未把这些功能回退为源分支的较早实现。

冲突处理：`scan/routes.test.ts` 采用已在真实 PostgreSQL 引擎运行的 PGlite 测试基座，将 dev 的购买价格、币种与可靠历史起点断言迁入该用例，不恢复 FakeD1。验证文档保留双方记录，并将当前流程和架构说明更新为 dev 已合入的状态。扫描路由除保留 dev 的初始事件 SQL 外，其余内容与向量源分支相同；模型、原生桥接和资源与来源一致。平台范围沿用向量实现的 iOS 16+、Android minSdk 24，Web 扫描暂不支持。

本轮验证环境：Windows、Flutter 3.44.7 / Dart 3.12.2、Node 22.20.0、pnpm 11.9.0。

| 检查 | 实际命令 / 证据 | 结果 |
|---|---|---|
| 购买价格回归反证 | 临时将初始事件 SQL 恢复为 dev-wxy 的缺字段版本，执行 `pnpm --filter @kando/workers-api exec vitest run src/scan/routes.test.ts -t 'purchase price event'`，随后按原字节恢复合并代码 | 目标用例退出 1，实际购买价、币种及可靠起点均为 null；其余 27 项仅因目标过滤未运行 |
| Workers 影响面 | `pnpm --filter @kando/workers-api exec vitest run src/scan src/legal/routes.test.ts src/db/postgres/scan-confirm-purchase-price-event.test.ts src/portfolio/performance.test.ts src/app-config src/admin/routes.test.ts` | 9 文件、90/90，退出 0；包含还原后完整扫描路由回归 |
| Admin | `pnpm --filter @kando/admin-web test` | 21/21，退出 0 |
| TypeScript / 依赖 | `pnpm type-check`、`pnpm lint` | 通过，均退出 0；Turbo 7 项成功，其中 6 项复用缓存，Workers 类型检查实际执行 |
| Dart 依赖与分析 | `flutter pub get --enforce-lockfile`、`dart run melos run analyze` | 依赖按锁文件解析；两个工作区包无分析问题，均退出 0 |
| Flutter 影响面 | 下方命令 | 229 项通过、3 个既有图片基准失败，退出 1；不能标记整组通过 |
| 图片基准隔离复验 | 干净 detached checkout `dev-wxy@8046c85`，同版本 Flutter，仅运行上述三个失败用例 | 同为 3 项失败，每项 0.21% / 676 像素；三张实际渲染 PNG 的 SHA-256 逐一与合并后完全一致，未修改 Golden |
| Android | `flutter build apk --debug --no-pub --dart-define-from-file=config/test.json` | 退出 0；解包确认两份 ORT 模型与三个 ABI 的 ONNX Runtime 齐全，无 OpenCV/libdartcv |
| Worker / Admin 构建 | `pnpm --filter @kando/workers-api run deploy:dry-run:dev`、`pnpm --filter @kando/workers-api run deploy:dry-run:prod` | 均退出 0；两环境预演均含 VECTOR_RECOGNITION，不含 OCR_SERVICE_BASE_URL |
| 合并完整性 | 比较 dev 的 8 个既有修复文件、初始事件 SQL、源分支原生/模型文件、Podfile 与锁文件 checksum、冻结产品目录 | 均一致；Podfile SHA-1 为 `7bc2f1fa13fd5fe54f198913b6c69f4f1250cd4d` |

Flutter 影响面命令在 `apps/flutter-app` 执行：

```sh
flutter test --no-pub test/scan_api_client_test.dart test/scan_result_source_test.dart test/scan_mask_geometry_test.dart test/scan_native_image_processor_test.dart test/scan_quota_controller_test.dart test/scan_card_recognizer_test.dart test/widget/scan_page_test.dart test/app_update_design_test.dart test/widget/card_detail_page_test.dart test/subscription_singular_revenue_test.dart test/subscription_revenue_reporter_test.dart test/app_attribution_test.dart --reporter expanded
```

失败项为 `Figma scan scanning renders at the 390x844 baseline`、`Figma recognition renders at the 390x844 baseline`、`Figma scan reveal renders at the 390x844 baseline`。源分支隔离复验使用 `flutter test --no-pub test/widget/scan_page_test.dart --name 'Figma (recognition|scan scanning|scan reveal) renders at the 390x844 baseline' --reporter expanded`。图片只留在本地测试输出，没有加入文档目录。Android Debug APK SHA-256 为 `17b2e86abbe0d9ec78f5214fa2db9942651c5b7d741229b2187092373753d0b6`；构建提示既有 Gradle/AGP/Kotlin 版本后续升级和 SDK XML 版本差异，本轮没有修改工具链。

Code Review 自审通过：逐项核对双方提交和手工解冲突差异，确认向量输入、Service Binding、游戏过滤、模型资源和平台桥接完整；购买价格断言能在撤回修复时失败，dev 的更新弹窗、Card Detail 和 Singular 修复保持原文。没有引入旧协议回退或新的 D1 依赖，冻结产品输入未改动。三个图片基准问题保留为既有待清理项，不属于本次合并新增回归。

本轮未运行 Workers/Flutter 全仓测试、iOS 编译/签名及两端真机模型验收；Windows 无 Xcode，客户端测试人员仍需补验真实图片准确率、推理耗时、内存与登录态完整扫描。服务端部署不发布 App 安装包。PostgreSQL `0012` 文件保持原样，历史数据回填未执行；共享数据库迁移仍需单独授权。dev 发布结果与线上校验另按实际执行结果记录。

### 合并后的 dev 发布

合并提交为 `f38ef98ba254c31d5faa062d4ac6443f767514dd`，两个父提交为 `0e3e53b` 和 `8046c85`；发布前工作区干净，`dev-wxy` 本地与远程提交均为该合并提交的祖先。沿用本任务此前的 dev 部署授权，执行 `pnpm --filter @kando/workers-api run deploy:dev --tag dev-vector-f38ef98 --message "Merge dev-wxy vector recognition with current dev fixes (f38ef98)"`，退出 0。

- Cloudflare 于 `2026-09-09T03:00:50Z` 将 Worker version `3e5d4b2d-da0a-4f15-883e-538b9ee0210c` 置于 100% dev 流量，tag 为 `dev-vector-f38ef98`；deployment status 与 version view 回读均通过。
- 远程绑定为 `VECTOR_RECOGNITION=recognize-vec`、dev KV/R2、共享 Hyperdrive、`APP_ENVIRONMENT=development` 与 beta Apple 配置，不含 `OCR_SERVICE_BASE_URL` 或 D1；5 分钟 Cron 发布成功。
- `2026-09-09T03:02:23Z` 的 HTTP 校验退出 0：health 为 `200/status=ok`，games 为 `200/10` 条，Pokemon Search 第 3 页为 `200/40` 条；iOS/Google 公共配置均为 `200/no-store`，iOS 最低/建议版本均为 `1.0.2`、`force_update=false`，Google 规则停用。
- `/admin` 返回 200，HTML SHA-256 为 `30121eea22e331509e24030ad1d81dffa324fdc400f53c711f17082b20c54e1b`；HTML 与所引用全部 10 个 JS/CSS 均与本地 dev 构建逐字节一致。未授权 Admin 版本接口及扫描识别 POST 均为 `401 UNAUTHORIZED`，没有创建扫描记录或消费额度。
- 该次 dev 发布前后 prod 均为 `934506ae-d433-4a38-ae40-6d07b109d50e`、100% 流量，没有重新部署 prod，也未执行远程数据库迁移、历史回填或运营配置修改。随后按用户授权将合并与验证记录推送至 `github/dev@b0b54df`，并清理四个指定的本地/远程分支；当前 Git 与运行状态以上方回读为准。

dev 服务端部署及上述校验已完成；真实图片、登录态完整扫描与新 App 签名包验收仍按本节未验证项补充。后续应从含本次合并的 dev 提交发布，避免旧 pHash 分支再次覆盖同一开发环境。
