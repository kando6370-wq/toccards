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

本轮未运行全仓测试、签名安装包或 iOS/Android 真机视觉/商店验收；已有 Widget 两平台验证不替代真机。Figma 的 SF Pro 正文在 iOS 使用平台字体，Android 使用其平台字体，跨平台字形不宣称逐像素相同。本节随修复代码提交，尚未部署。
