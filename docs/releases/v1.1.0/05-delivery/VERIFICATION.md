# 版本管理环境隔离与强制更新验收

本说明对应 2026-09-08 的版本管理修复。代码与本地验证、服务端部署、客户端发布和真机验收分别记录，不能互相替代。

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
- `recognize-vec` 实网联调、两环境发布、弱网端到端及新旧 App 协议切换未执行；当前分支不兼容旧 pHash 请求，发布必须协调 App 和 API。
- 本轮只运行列出的影响面验证，没有宣称全仓测试通过。本节随识别链路提交到 dev-wxy，尚未部署。
