# v1.1.0 发布与验证记录

本页维护版本管理、向量识别、Singular 收入及 dev 合并发布的验证证据。代码与本地验证、服务端部署、客户端发布和真机验收分别记录，不能互相替代；下文每次测试与发布结果只对应其注明的提交、日期和环境。

## Card Detail Price 时间按钮点击方框（2026-09-18，本地修改）

用户截图显示无价格数据时切换 `1D/7D/15D` 等时间范围，选中标识外出现浅色方框。源码中 Price 按钮的 `InkWell` 未设置点击反馈，40×40 热区使用 Flutter 默认 splash/overlay，而选中渐变仅为 40×24；相邻 Performance 范围控件已关闭默认反馈。修复只对 Price 范围按钮关闭 splash/overlay，保留选中渐变、点击热区、范围切换及 1Y PRO 门禁。影响通用与具体 Item 详情的 Price 页，iOS/Android 共用 Flutter 实现；不改 Performance、价格数据、API 或权益逻辑。现有 UI 设计规范已禁止默认 Material 视觉，业务/接口文档契约未变化，故无需另改流程文档（N/A）。

Windows / Flutter 本地验证：新增无价格数据的 widget 回归在修复前失败（默认 `splashFactory=null`）；修复后定向测试 1/1、完整 `test/widget/card_detail_page_test.dart` 61/61 通过；`flutter analyze --no-pub` 无问题；两份改动 Dart 文件的只读格式检查退出 0。初次定向复跑因测试窗口中按钮不在可见区域而未命中，调整测试先滚动至按钮后通过，未修改业务逻辑。Code Review 自审核对通用/具体 Item 两处调用、六个范围和 1Y PRO 入口、选中渐变与默认点击反馈的边界，未发现本轮变更问题。本地检查不等于用户截图所用设备上的视觉验收；未运行 iOS/Android 真机、设备包构建、其他模块或全仓测试，需客户端测试人员在两端后续测试包中复核按压和切换画面。本轮未手动部署。

## 旧 Cloudflare dev 业务退役（2026-09-17）

用户确认 Linux 客户端业务路径已测试无问题，并要求保留旧测试数据和旧包，退役旧业务 Worker、域名入口和 cron；本次没有独立重跑真机路径。退役前只读核对 kd201：`current` 为 watcher 发布的 `dev@4d5d66fdf60c2703604d9c72fc0ed204635c2279`，manifest、`last-deployed-sha` 和远端 dev 一致；API/Web/DB 容器运行，API/DB healthy，API bundle 与 release 的 SHA-256 相同，Admin 首页文件也与 release 一致。PostgreSQL 为 18.6，migration ledger 为 13 项。该 release 的发布前备份为 1,120,771,233 字节，容器内 `pg_restore --list` 退出 0；未执行整库恢复。回调网关和重定向 systemd 服务均为 active/enabled，实际 nftables 表存在，网关文件与本地源码摘要一致。

Cloudflare 退役前回读：`toccards-api-dev` 的自定义域名仅有 `api-dev.tcgcard.fun`，cron 仅有 `*/5 * * * *`，workers.dev 和 preview URLs 均关闭。首次清空 cron 的对象格式请求被 Cloudflare 以 10026 拒绝，没有修改线上状态；按 Wrangler 所用的数组格式 `[]` 重试后，独立 GET 确认 schedules 为 0。仅对已核对域名、服务和 ID 的旧绑定执行 DELETE；该接口返回空响应，但独立 GET 确认旧绑定为 0。随后 `wrangler delete toccards-api-dev` 成功退出 0，未使用 `--force`。脚本清单不再包含旧 Worker；Cloudflare 权威 DNS 对旧域名返回不存在，本机缓存期间的旧 HTTPS 请求返回 530，未再提供旧 API。

退役后 `api.tcgcard.fun/api/v1/health`、Linux 内网 health、`recognize-vec.tcgcard.fun/health` 均返回 200；独立 `dev-callback.tcgcard.fun` 对通知路径 GET 返回预期 405。Cloudflare 清单仍包含 prod API、向量 Worker 和独立 Apple 回调，prod 与回调自定义域名保持原归属；只读清单确认旧 dev KV namespace 与 R2 bucket 均仍存在，未读取内容。没有删除或写入共享 PostgreSQL、旧 dev KV/R2、Linux 数据卷、旧包或 prod；旧 Worker 自身的 Secret 和版本历史随脚本删除，若要恢复需重新配置，不能将数据保留等同于 Worker 可无密钥回滚。本次未发送新的 Apple TEST、未执行旧包兼容访问或完整客户端复验，用户确认的客户端验收与上述只读服务检查分别记录。源码移除旧 `wrangler.toml` dev 环境以防误部署；本次本地文档和配置变更未提交、推送或触发 Linux watcher。

本地验证：`pnpm lint` 退出 0；`pnpm type-check` 7/7（其中 6 项命中缓存，Workers API 实际执行）；`pnpm --filter @kando/workers-api exec vitest run src/entitlements/node-fetch-worker-shim.test.ts --maxWorkers=1` 为 5/5；prod `deploy:dry-run:prod` 与 Linux `deploy:dry-run:dev` 均退出 0，后者的完整 API bundle 启动/Apple SDK 回归 2/2，均未发布。反向检查 `wrangler deploy --env dev --dry-run` 退出 1，明确提示配置没有 dev 环境，属于预期拒绝。文档路径/新增退役锚点和 `git diff --check` 通过；Code Review 核对了唯一旧 Worker/域名/cron、prod/回调/识别资源保留、配置删除范围与实际远端回读，未发现阻断项。未运行全仓 Workers/Flutter 测试、真机、真实购买或备份恢复演练，本次未改业务运行逻辑。
## 引导页 1 视频顶部位置与等比尺寸（2026-09-17，本地修改）

按用户文字要求而非图片中的 390×510 cover 备注调整页面 1：视频源 780×960，最大显示宽度 390 pt、按比例高度 480 pt，距屏幕顶部 56 pt；窄屏等比缩小，宽屏居中。首帧占位图与视频共用原媒体容器，不另行裁剪；页面 2、3 保持原来的顶部安全区布局，播放/循环/降低动态效果及按钮交互未变。`01-flows/business-context.md` 已同步当前行为，冻结 v1.0.0 文档未修改。修改前页 1 顶部布局回归测试失败（实际顶部为 0），页 2 保持原布局测试通过。

本地验证：macOS / Flutter，`flutter test --no-pub --dart-define-from-file=config/test.json test/widget/onboarding_page_test.dart test/onboarding_gate_test.dart --reporter expanded`：20/20 通过、退出 0，覆盖 390×844 顶部 56 与 390×480 等比尺寸、320×700 窄屏比例和静态回退、430×932 居中，以及页 2 原安全区布局、三个引导页跳转和启动门禁。`flutter analyze --no-pub`：无问题、退出 0；`dart format`：仅格式化本轮测试文件；`git diff --check`：退出 0。Code Review 自审核对页 1 媒体尺寸和顶距仅作用于索引 0、首帧图与视频共用尺寸容器，页 2、3 原媒体尺寸分支及播放、文案、底部控制未修改；未发现本轮变更问题。尚未重新打包或在 iOS/Android 真机验收，Widget 布局测试不能代替真机视频解码与尺寸检查，需后续测试包补验。

## 注册 Welcome 留在注册页及登录提示恢复 1 秒（2026-09-17，本地修改）

现象：注册成功后先退出邮箱注册页，再由外层显示 `Welcome`，首次引导会在提示背后露出引导页 3；此前的统一时长调整把邮箱登录 `Welcome back` 改为 2 秒，与用户要求恢复的 1 秒不符。根因：注册 `_completeSignIn` 先关闭邮箱路由，`_openEmailAuthPage` 才在根 Navigator 上展示 Welcome；修改前首次引导/Profile 的注册页保留断言失败。影响范围仅邮箱注册成功的提示位置/流转顺序及邮箱登录提示时长，不改认证请求、会话持久化或权益判定。

修复：全屏注册页直接显示并等待 1 秒 Welcome，然后才关闭自己的路由；外层在同一帧移除登录选项，首次引导/Profile 沿用既有权益刷新分流。登录 Welcome back 计时恢复 1 秒；其他无按钮欢迎弹窗默认 2 秒、带按钮需确认的行为不变。当前流程文档已同步到 `01-flows/business-context.md`；v1.0.0 冻结文档未改。

验证：macOS / Flutter，修复前首次引导和 Profile 的注册页保留断言均失败；修复后 `flutter test --no-pub --dart-define-from-file=config/test.json test/widget/auth_profile_test.dart --name 'email registration keeps its entry flow|successful register passes current anonymous id|onboarding email welcome auto closes after one second|email welcome keeps password page|email login saves onboarding only once|email welcome does not close a newer route|email welcome timer is safe|onboarding Email login follows|Profile Email login checks|welcome without an action|welcome with an action|welcome timer only|early welcome dismissal' --reporter expanded`：29/29 通过、退出 0，覆盖 iOS/Android 登录、首次引导/Profile 注册的 Free/Premium/Unknown 分流及计时边界。`flutter analyze --no-pub`：无问题、退出 0；`git diff --check`：退出 0。全量 `auth_profile_test.dart`：125 项通过、4 项订阅页 Golden 图像对比失败、退出 1；失败项仍是 responsive Profile banner、subscription success 300ms motion、v1.1 bottom sheet 和 success page，与欢迎提示路径无关，未更改 Golden 基线，不把全量测试记为通过。

Code Review 自审：核对注册提示在原注册路由上显示、提示结束后才退出该路由、外层只移除自己的登录选项，以及两处入口和三种权益状态的后续分流；登录提示 1 秒及共享弹窗默认 2 秒的其他行为未改。未运行 iOS/Android 真机首次安装及注册、IPA/Android 构建或真实权益接口联调；Widget 测试不能代替设备视觉/转场验收，需客户端测试人员在后续测试包补验。

## 认证欢迎提示自动关闭（2026-09-17，本地修改）

现象：邮箱注册成功的无按钮 `Welcome` 没有定时关闭路径，只能点击遮罩；登录的 `Welcome back` 固定 1 秒，与本次统一 2 秒的要求不符。根因证据：注册路径调用 `showKandoWelcomeModal`，该共享弹窗原先只等待手动 `showDialog` 结束；修改前注册流转和共享弹窗的计时边界测试失败。影响范围限认证页的欢迎提示及其后的原有引导/Profile 权益检查；认证接口、会话、订阅判定、顶部 toast、支付提示和需确认的弹窗均未修改。

修复：无按钮共享欢迎弹窗默认 2 秒自动关闭，注册显式指定 1 秒；登录 `Welcome back` 改为 2 秒。计时器销毁时取消，仅关闭提示自身路由；保留点击遮罩提前关闭和带按钮弹窗等待用户确认。`01-flows/business-context.md` 已同步当前行为；v1.0.0 冻结文档不变。

本地验证：macOS / Flutter，修改前针对注册流转和无按钮欢迎弹窗的回归测试失败；修改后 `flutter test --no-pub --dart-define-from-file=config/test.json test/widget/auth_profile_test.dart --name 'welcome without an action|welcome with an action|welcome timer only|early welcome dismissal|email registration keeps its entry flow|onboarding email welcome auto closes after two seconds|email welcome keeps password page|email login saves onboarding only once|email welcome does not close a newer route|email welcome timer is safe|onboarding Email login follows|Profile Email login checks' --reporter expanded`：24/24 通过、退出 0，覆盖 iOS/Android 登录及引导/Profile 注册分流。`flutter analyze --no-pub`：无问题、退出 0；`dart format` 仅格式化改动测试文件；`git diff --check`：退出 0。全量 `auth_profile_test.dart`：121 项通过、4 项订阅页 Golden 图像对比失败、退出 1；失败项为 responsive Profile banner、subscription success 300ms motion、v1.1 bottom sheet 和 success page，与本次欢迎弹窗路径无关，未更新 Golden 基线，不把该测试记为通过。

Code Review 自审：核对了无按钮默认/注册特例、带按钮不定时、点击遮罩提前关闭、销毁取消计时、后来打开的页面不被错误关闭，以及引导/Profile 权益分流；未发现本次变更的问题。未运行 iOS/Android 真机首次安装与注册、IPA/Android 构建或订阅接口联调；本地 Widget 测试不能替代真机对提示时长及后续页面流转的验收，需客户端测试人员在后续测试包补验。
## Linux dev 公网回源服务器隔离（2026-09-17）

原公网 `111.10.170.43:8089` NAT 到 `192.168.50.201:8080`，可绕过 CF Worker 直接得到 Admin HTML 与 `/api/v1/health` 200；CF Worker 的路径限制无法保护这条直连。kd201 仅在 8080 发布 Docker Web，`ens160` 抓包确认公网请求保留公网源地址，内网客户端从私网到达。为不改 NAT、App/Admin 内网地址或现有 Compose，在主机启动独立 Node 22 回调网关（8081），再通过专属 nftables `ip toccards_callback` 表以 prerouting priority -101（Docker DNAT 为 -100）仅将公网 IPv4 到 `201:8080` 的流量转到该网关；RFC1918 内网源地址仍直达 8080。两项 systemd 服务已启用并运行，代码和策略存放在 `deploy/linux/security/` 与宿主机对应私有安装位置，原 API/Web/DB 容器及 watcher release `dev@7a8300b` 均未更换。

网关仅允许精确的 `POST /api/v1/apple/notifications/v2/sandbox`，200,000 字节上限、固定回环上游、8 秒超时、拒绝重定向，不转发客户端 Cookie/Authorization；JWS 验签仍由原 API 负责。Windows 与 kd201 的 Node 定向测试均为 2/2；服务器 `nft -c`、systemd unit 校验和服务状态通过。公网源站 `/`、`/api/v1/health`、Admin API 均为 404；通过原始 SOCKS 连接固定公网目的地后，伪造内网 Host 仍为 404，抓包确认为公网源地址。局域网 HTTP 代理伪造 Host 曾返回 200，原因是代理将连接改走私网，并非公网转发绕过；该私网代理需由其自身访问控制保护。公网回调 GET 为 405、空 JSON POST 经 CF 与直连源站均为 Linux 400；私网 Admin 200、health 200、未登录 Admin API 401。使用既有已处理 Apple TEST 的原始 JWS 经 CF 网关仅重放一次返回 200，inbox 仍为 16 条，未请求 Apple 发送新 TEST。PostgreSQL migration 仍为 13，其他项目/CF prod/识别 Worker 未改。

安全策略上线后，用户再授权发送**一条**新的 Apple Sandbox 官方 TEST。Apple Server API 于 `2026-09-17T06:48:33.381Z` 接受请求，状态回读为 `SUCCESS`，官方 SDK 验签得到 UUID `4c121de4-fa5d-4767-8bb2-3c87c148b9e5` 和 SHA-256 `e03f90e205eb95966f5d69851ab75f93d164729264a2dc6a4dfb9bf1d885aea1`。Linux inbox 于 `06:48:34.688Z` 新增该 UUID，摘要一致、Sandbox/beta、`processed`、attempts=1、`last_error=null`，结构化 `TEST` 与 decoded payload 均存在；inbox 16→17，Sandbox 交易数仍为 14、购买链仍为 1，迁移账本 13 项。公网空 JSON POST 继续返回 Linux 400，临时 Apple token 和诊断脚本已清理。此次真实 TEST 补齐了新网关上线后 Apple 投递回执与 Linux 验签闭环，但仍不代表其余订阅生命周期、Restore 或收入后台验收完成。

残余边界：CF→origin 仍为 HTTP；规则依赖当前 `ens160`、目标 IP 和公网源地址保留，路由器若将 WAN 源地址 SNAT 为私网或未来启用公网 IPv6，必须重新设计/复验。宿主机服务和规则独立于 Git watcher，仓库代码未推送，后续更新需显式同步。若网关故障保持重定向可让公网失败关闭；直接停用重定向会恢复此前整站公网暴露，不可当作无风险回滚。

## Apple Sandbox 公网回源复验（2026-09-17）

公网映射调整期间，Cloudflare `toccards-apple-callback-dev` 仍将精确的 Sandbox POST 路径转发到 `http://dev-callback-origin.tcgcard.fun:8089`，但空请求返回 `502 CALLBACK_UPSTREAM_UNAVAILABLE`，实时 Worker 日志为 10 秒 `TimeoutError`；Linux 内网同一路径返回 400，API 健康、数据库 inbox 基线为 14。按用户要求先发送一条 Apple 官方 TEST，官方签名可验证但投递为 `TIMED_OUT`；随后以至少 10 秒的请求间隔发起 116 条 TEST，其中 115 条已回读为 `TIMED_OUT`、最后一条未取得最终状态，下一次请求触发 Apple HTTP 429，发送进程已停止。这一阶段没有新通知入 Linux，不能把 Apple 接受发送请求写成投递成功；临时 token 与诊断脚本已清理。

网络侧恢复后，用户再次明确要求只发一条 TEST。Apple Server API 接受该请求并给出测试 token；随后的官方投递状态查询仍返回 429，**未取得 Apple 的 SUCCESS 回执**。但公网 HTTPS 回调的空 JSON POST 已恢复为 Linux `400 INVALID_REQUEST`，本地 inbox 于 `2026-09-17T06:10:48.682Z` 新增唯一 `TEST`，UUID `c0bcefe9-816a-4c58-98e6-e4a23cf4b748`，Sandbox、`com.kando.kandoApp.beta`、`processing_status=processed`、`attempts=1`、`last_error=null`，结构化记录及 decoded payload 均存在；HTTP 入口、入库及服务端验签链路已实测。随后 `06:11:42Z` 又收到真实 `DID_CHANGE_RENEWAL_STATUS / AUTO_RENEW_ENABLED`，同样处理为 `processed`、无错误。基线 14 条变为 16 条，迁移账本仍为 13；该生命周期通知不应被描述为本轮新购买或新交易。仅运行现有 Linux release `dev@7a8300b` 和独立 Cloudflare 回调 Worker，没有改业务代码、数据库结构、prod 或旧 CF dev 部署。此次验证不覆盖后续每种订阅通知、真机 Restore 或公网源站的访问面整改；后者由用户暂缓。

## Linux dev 统计 SDK 配置同步（2026-09-17）

原 Cloudflare `toccards-api-dev` 的 Secret 列表含 `MIXPANEL_PROJECT_TOKEN`、`MIXPANEL_API_SECRET`、`SINGULAR_API_KEY`、`SINGULAR_SECRET_KEY`；Secret 接口只返回名称，不能读取明文。旧 dev 公共 `/app-config` 在 iOS/Google 两种平台均下发前三项客户端需要的值（Mixpanel Project Token、Singular API Key/Secret Key）。Linux 原私有 `.env` 声明了四项但运行容器均为空。本次仅把三项公共 SDK 配置从旧 dev 同步到 Linux；`MIXPANEL_API_SECRET` 保持空值，当前代码仅声明此环境变量，没有使用它的服务端路径。

配置操作只替换服务器私有 `.env` 中对应三行；原文件备份到 `/home/user/apps/toccards-test/shared/.env.before-analytics-20260917-024633`，两者权限均为 600，其他内容按字节保留。目标仍为 `branch-dev-7a8300b502d5-20260917101244`，只通过原离线 Compose 重建 API，Web 与 PostgreSQL 容器 ID 未变，没有迁移、业务数据写入、Cloudflare/prod 配置变更或 Git 推送。更新前先验证源响应非空、待写文件格式、现有键为空且各只出现一次；更新后 Node 解析的配置、API 容器环境与来源摘要一致，iOS/Google 两种 `/api/v1/app-config` 均为 200，三项下发值逐项与旧 CF dev 相等，未输出值。API health 200、Admin 标题正常。未运行应用测试/构建（没有源码或依赖变更），也未执行 App 真机安装、Mixpanel/Singular 项目后台事件和收入收件验收；配置相等不等于事件已送达。

用户随后提供同一 Mixpanel 项目的 Project Token 与 API Secret。前者与旧 CF dev 和 Linux `/app-config` 均逐值匹配；仅将后者填入 Linux 原本为空的 `MIXPANEL_API_SECRET` 一行，不改前三项，备份为 `/home/user/apps/toccards-test/shared/.env.before-mixpanel-api-20260917-025354`。备份和新 `.env` 权限均为 600，原离线 Compose 仅重建 API；Web/数据库容器 ID 未变。暂存文件经 Node 解析、运行容器经摘要校验确认该 Secret 已注入；API health/Admin 正常，iOS/Google 的三项公开配置仍与原 dev 一致，`MIXPANEL_API_SECRET` 未进入 `/app-config`。没有向 Mixpanel API 发起凭据校验，也没有验证真机 SDK 初始化或后台事件/收入收件；该字段在当前源码中仍无使用路径。本次仅调整私有运行配置与文档，未执行应用构建/测试、远程 migration、CF/prod 变更或 Git 推送。

后续只读核验：从 Linux API 容器使用现有 `MIXPANEL_API_SECRET` 按 Mixpanel Project Secret 的 HTTPS Basic Auth 方式调用 Raw Data Export，返回 HTTP 200 和有效事件；没有输出原始事件/用户信息，也未向 Mixpanel 写入测试事件。首次当天读取 44 条事件，其事件时间都晚于本轮 Linux 配置同步；第二次当天读取 50 条，包含 `subscribe_view` 3、`splash_view` 2、`homePerformance_view` 1、`sub_click` 1、`sub_result` 1、`restore_result` 1。记录存在证明该 Mixpanel 项目可查询且有 App 类事件，但事件时间由客户端提供、未核对指定用户或交易 ID，不能归因到本次 Linux 测试订阅，也不能宣称 Mixpanel 收入或 `sub_success` 已收到。Singular 的 SDK API Key/Secret Key 已从 Linux `/app-config` 正常下发，但不提供后台报表查询权限；缺少 Singular 后台/Reporting API 访问条件，本轮未验证其安装、事件或收入收件。Mixpanel 官方已将 Project Secret 认证标记为弃用，后续新增服务端查询应改用 Service Account。
## 首次引导页 1 扫描演示素材（2026-09-17，已构建测试内部包 146）

应用户要求，将 `assets/onboarding/guide_scan.mp4` 替换为提供的 `Card_AI_Pikachu_Scan_3s-2.mp4`（3 秒、780×960、H.264），SHA-256 均为 `cc85b9e35e02fb66a439574ab030cf0b0f236771805fbbf1399c5719a876918e`。原 PNG 在视频解码前与减少动态效果时仍会显示旧喷火龙画面，因此同步以新视频真实首帧生成 `guide_scan_placeholder.png`，按相同比例缩放为 390×480，让图片和视频在现有 `BoxFit.cover` 下按相同方式裁切。两个资源路径不变；引导页布局、文字、播放/循环及页面 2、3 素材与业务流程均未修改。实际视觉内容同步到 `01-flows/business-context.md`，v1.0.0 冻结文档未改。

本地验证：macOS / Flutter 3.44.5，AVFoundation 能解码新视频首帧；图片已回读为 390×480，源文件与目标视频 SHA-256 一致。`flutter test --no-pub --dart-define-from-file=config/test.json test/widget/onboarding_page_test.dart test/onboarding_gate_test.dart --reporter expanded`：17/17，通过、退出 0；`flutter analyze --no-pub`：无问题、退出 0。Code Review 自审核对了媒体加载、首帧 fallback、自动循环、减少动态效果、资源打包声明与页面 2、3 引用，改动限定在页 1 的两份资源和当前版本文档。

签名构建：同日重新执行 `./tool/release_ios.sh --env test --pgy --build-number 146`，退出 0，内网 `http://192.168.50.201:8080/api/v1` 健康检查返回 HTTP 200、`status=ok`。脚本清理旧构建后静态分析通过，归档、导出及最终 IPA 校验通过；最终内部包使用 `com.kando.kandoApp.beta`、Apple Development 签名、App Attest `development`，测试 Firebase 与内网 API 校验通过，41 个 Mach-O UUID 均匹配 dSYM。保存的 IPA 再次回读确认仅 `192.168.50.201` 的 HTTP ATS 例外及本地网络用途说明。IPA 大小 56,482,862 字节，SHA-256 为 `86e61f355fd92c3dc647ba3c35c8c2ca62e296d0e76e16e24ef6510411da3094`；与 `dSYMs.zip` 保存至 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.2-146/`，副本摘要一致。现保留 144、145、146，旧 143 移入废纸篓，可恢复；归档另存至 `~/Library/Developer/Xcode/Archives/2026-09-17/Card AI Test 1.0.2 (146).xcarchive`。源码版本同步为 `1.0.2+146`；Dart/CocoaPods 锁文件未变化。构建前后视频文件摘要一致，为上述新素材。

未运行：iOS/Android 真机视频播放、首次安装登录、扫描与购买、Android 构建以及全 App/全仓测试；本轮为 iOS 内部包交付，Widget 测试与签名构建不能代替设备视频解码/流畅度及局域网权限验收。客户端测试人员需用 146 包在可访问内网的设备上验收。未安装、上传、推送或部署。
## 邮箱登录在密码页展示 Welcome back（2026-09-16，已构建测试内部包 145）

用户在首次安装引导的邮箱登录中观察到密码验证成功后先闪回引导页 3，再进入订阅页，要求在密码页展示原有 1 秒 Welcome back 后继续。基于 `dev@a97c5ed`、含已有 `1.0.2+144` 打包改动的工作区；本轮不修改版本或发布脚本。根因由代码路径和失败测试确认：`_completeSignIn` 先 pop 密码页，`_openEmailAuthPage` 再 pop 登录选项并于下一帧展示提示，因而提示背后已变为引导页，随后引导完成和权益检查再次切换画面。此前真机看到提示只能证明提示出现，不能证明背景页面和切换符合本次要求。

修复限于认证 UI 和引导调用方：邮箱验证成功后在密码页等待既有提示实际关闭，再由引导入口保存完成状态；保留密码页直到替代内容完成一帧构建，然后关闭邮箱页、无退场动画移除登录选项。Profile 共用同一密码页提示，但后续仍使用其原权益检查；注册和 Google/Apple 的流程不变。邮箱流程只完成自己的路由，避免等待期间误 pop 新页面；引导保存失败不重复提交保存。登录请求、密码验证、会话持久化、游客资产、订阅购买、权益判定及扫描扣次均未修改。当前行为同步到 `01-flows/business-context.md`，冻结 PRD 未改。

验证环境为 macOS / Flutter 3.44.5 / Dart 3.12.2，以下 Flutter 命令均在 `apps/flutter-app` 执行：

- 失败证据：`flutter test --no-pub --dart-define-from-file=config/test.json test/widget/auth_profile_test.dart --name 'onboarding email welcome auto|email welcome keeps password' --reporter expanded` 在修复前 8/8 失败、退出 1，均为密码页已不存在；覆盖 iOS/Android 三种权益与慢存储。修复后同一断言通过，另逐帧断言提示关闭和慢存储等待时不露出引导或登录选项。
- 定向回归：`flutter test --no-pub --dart-define-from-file=config/test.json test/widget/auth_profile_test.dart --name 'Profile .*login|Profile .*waits|Profile .*cancellation|onboarding .*login|onboarding .*cancellation|email registration keeps|onboarding email welcome auto|email welcome|email login saves' --reporter expanded` 最终 52/52、退出 0。覆盖 1 秒/999ms、手动关闭、销毁、新页面覆盖、慢存储/慢权益、保存失败、两入口三种登录与权益、取消和失败、注册。新增覆盖页测试在路由精确关闭修复前失败，修复后通过。旧时序 helper 的 `pumpAndSettle` 会因保留密码页的 Loading 动画推进到提示消失，已改为观测提示首帧和显式推进时间，保留原断言。
- 扩大回归：`flutter test --no-pub --dart-define-from-file=config/test.json test/widget/auth_profile_test.dart test/auth_controller_test.dart test/auth_repository_test.dart test/auth_session_interceptor_test.dart test/oauth_authorizer_test.dart test/auth_storage_test.dart test/startup_subscription_gate_test.dart test/onboarding_gate_test.dart test/onboarding_repository_test.dart test/widget/onboarding_page_test.dart --reporter expanded` 最终 199 通过、4 个 Golden 失败、退出 1，不能标记整组通过。差异分别为 Profile banner 1853px、订阅成功动效 117px、订阅 sheet 7816px、订阅成功页 5080px，与本页此前记录相同；未更新图片或放宽断言。初次扩大回归另发现防重复登录测试缺少登录后权益返回值，补充测试替身后该用例单独 1/1 通过且整组复验不再失败，原防重断言保留。
- `flutter analyze --no-pub`：无问题、退出 0。四个修改的 Dart 文件执行 `dart format --output=none --set-exit-if-changed`，以及根目录 `git diff --check`，均退出 0。

Code Review 自审通过：逐项核对提示生命周期、密码页和选项路由清理、异步回调 mounted 保护、引导保存单次执行、Profile 调用方、注册/三方入口及测试时序；无待处理审查项。仅页面承接顺序变化，未改变服务端或业务控制器。

签名构建：同日按用户要求重新构建连接 `http://192.168.50.201:8080/api/v1` 的内部包。构建前复跑上方 52 项定向回归，以及 `flutter test --no-pub --dart-define-from-file=config/test.json test/api_environment_test.dart test/release_config_test.dart test/card_detail_actions_test.dart --reporter expanded` 的 16 项环境/分享测试，均退出 0；服务器健康检查 HTTP 200、`status=ok`。执行 `./tool/release_ios.sh --env test --pgy --build-number 145`，首次在 `flutter build ipa` 隐式触发的依赖获取阶段等待包服务响应，长时间无进展后终止该次 `dart pub get`，脚本退出 241；未更改依赖或跳过检查，以相同命令重试后静态分析、清理、签名构建与产物验证全部通过，退出 0。

最终内部包 `1.0.2 (145)` 使用 `com.kando.kandoApp.beta`、Apple Development 签名、App Attest `development`，内网 API 和测试 Firebase 校验通过，41 个 Mach-O UUID 均匹配 dSYM。保存的 IPA 再次回读确认 `192.168.50.201` 的 HTTP ATS 例外和本地网络用途说明。IPA 为 56,689,687 字节，SHA-256 为 `fa8742ee4794b3a083df3c40e43261cf38fa082bf57d653e9573203f54112551`；与 `dSYMs.zip` 保存至 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.2-145/`，保存副本摘要一致。现保留 143、144、145，旧 142 已移入废纸篓，可恢复；归档另存至 `~/Library/Developer/Xcode/Archives/2026-09-16/Card AI Test 1.0.2 (145).xcarchive`。源码同步为 `1.0.2+145`，Dart/CocoaPods 锁文件、API 配置及本节三个运行文件构建前后摘要一致，包含本节最新调整。

未运行：iPhone 12 Pro Max 安装登录复验、Android 真机与构建、全 App/全仓测试及扩大 Golden 整组复跑（本轮为 iOS 内部包交付，使用定向回归、静态分析和签名产物验证；前述 4 项既有截图差异未处理）。客户端测试人员需用 145 包，在能访问内网并允许本地网络权限的设备验收首次引导邮箱登录的实际画面和 1 秒停留。保留已有改动，未安装、上传、push 或远程部署。

## Linux 内网 iOS 测试包校验同步（2026-09-16）

用户要求重新打包并连接 `192.168.50.201`。基线 `dev@a97c5ed`、源码 `1.0.2+143`；App test 与两端网络配置已使用 `http://192.168.50.201:8080/api/v1`，但 `release_ios.sh` 的 test IPA 检查仍要求旧 CF 测试域名，导致正确的内网包无法通过交付检查。新增脚本校验目标与当前编译环境 API 一致的回归，修改脚本前执行 `flutter test --no-pub --dart-define=APP_ENV=test test/api_environment_test.dart --plain-name 'iOS IPA validation expects' --reporter expanded`，退出 1，明确显示旧域名与内网地址不一致。

仅将脚本 test 分支的预期 URL 同步到现有 App 配置，保留实际 IPA 二进制检查；没有修改运行代码、正式环境地址、签名、服务端、共享包或依赖。修复后在 `apps/flutter-app` 分别以 `--dart-define=APP_ENV=test` 和 `--dart-define=APP_ENV=production` 执行 `flutter test --no-pub` 的 `test/api_environment_test.dart test/release_config_test.dart test/card_detail_actions_test.dart --reporter expanded`，两组均 16/16、退出 0；`bash -n tool/release_ios.sh`、目标测试文件的格式检查通过。Mac 对内网 `/api/v1/health` 的只读请求返回 HTTP 200、`status=ok`。

Code Review 自审通过：脚本预期地址与 Flutter test 一致，production 分支不变；原 IPA 签名、环境、Firebase、App Attest 和 dSYM 门禁全部保留，测试在旧脚本上失败、修复后通过。当前架构及 Flutter README 已正确描述内网入口，无需改写；本节记录遗漏校验的修复证据。

签名构建：macOS / Flutter 3.44.5 执行 `./tool/release_ios.sh --env test --pgy --build-number 144`，静态分析、清理构建、导出和最终 IPA 校验全部通过，退出 0。内部包为 `1.0.2 (144)`、`com.kando.kandoApp.beta`、Apple Development 签名，最终 App Attest 为 `development`；二进制包含内网 API，测试 Firebase 正确，41 个 Mach-O UUID 均匹配 dSYM。对保存 IPA 的 Info.plist 再次回读，确认仅 `192.168.50.201` 的 HTTP ATS 例外及局域网用途说明。IPA 为 56,688,941 字节，SHA-256 为 `7e52d99e2ac54e403386343ded9360634173a837845b1e32841b9cbe3cdb9df3`，保存副本摘要一致；与 `dSYMs.zip` 一同存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.2-144/`。当前保留 142、143、144，旧 141 按规则移入废纸篓，可恢复；Xcode 归档另存至 `~/Library/Developer/Xcode/Archives/2026-09-16/Card AI Test 1.0.2 (144).xcarchive`。源码同步为 `1.0.2+144`，Dart/CocoaPods 锁文件和 App API 配置摘要未变化。

未运行：真机局域网权限、登录、扫描、购买和 Android 构建（本次交付 iOS 内部包，未安装设备）；全 App/全仓测试（本次只同步 iOS 交付校验目标，已复验两环境配置、API 客户端和分享相关测试）。客户端测试人员需在可访问内网的设备允许本地网络权限后验收，服务器健康检查不能代替设备业务验收。未上传、安装、推送、部署或执行远程数据写入。
## Linux Apple SDK ESM 打包修复（2026-09-17）

用户保存回源 A 记录与 App Store Connect Sandbox URL 后，Cloudflare Public DNS 已解析 `dev-callback-origin.tcgcard.fun → 111.10.170.43`；公网 HTTPS 空 JSON POST 透传 Linux `400 INVALID_REQUEST`。只请求了一条 Apple 官方 TEST，Apple 报告投递 `SUCCESS`；Linux inbox `01M2PFJSQYF9866127S9TNCSJK` 保存的 JWS SHA-256 与 Apple 返回值完全一致，但异步处理为 `processing_failed / VERIFIER_NOT_CONFIGURED`，不能以 HTTP 200 认定通知处理完成。

根因已通过同一 Node 22.22.1 API 容器的 ESM/CJS 最小对比证实：实际 `loadLinuxRuntime` 保留 Apple 配置；ESM 打包的 Apple SDK 3.1.0 依赖 `node-fetch@2.7.0` 调用 `require("stream")`，报 `Dynamic require of "stream" is not supported`。既有 factory catch 将加载异常转为 null，因此通知验签、购买验签和 Server API 客户端都会不可用；相同配置的 CJS 诊断包可正常初始化，这也是先前凭据诊断未暴露正式 bundle 故障的原因。

最小修复在 Linux 共用构建选项加入 `createRequire(import.meta.url)` banner；共享业务路由、JWS 验证规则、数据契约、Cloudflare 构建与依赖版本不变。新增 `node --test apps/workers-api/scripts/test-linux-bundle.mjs`，Apple SDK 真实打包配置在修复前稳定因 verifier=null 失败；独立子进程不使用 Apple SDK mock、不连接 Apple 或数据库，并校验无效 JWS 仍被拒绝。首次发布预检和 PostgreSQL 备份完成后，新 API 未通过健康检查，发布脚本自动重建了旧版本；在旧容器隔离运行新包明确报 `SyntaxError: Identifier 'createRequire' has already been declared`。`fflate` 在完整 ESM bundle 内已有同名导入，故把 banner 的本地绑定改为 `__linuxCreateRequire`；新增完整 API bundle 的语法检查、独立启动和 health 回归，该测试在修复前复现相同语法错误，修复后与 Apple SDK 检查共 2/2 通过。两项已接入 `build:linux:api`，后续手工与 watcher 构建都会执行。

首次失败后的旧 API 回退健康检查为 200；备份保留于服务器 `backups/toccards-test-20260917-094038-before-manual-a97c5ed-apple-esm-dirty-20260917-0941.dump`，未执行恢复。第二次发布前重新运行 Workers 定向 8 文件 32/32、CF 代理 8/8、全仓 `pnpm lint` 与 `pnpm type-check`、Linux `deploy:dry-run:dev`，均退出 0；第一次部署失败不计为发布通过。

第二次手工发布从本地 `dev@a97c5ed` 的未提交工作区构建，API/Admin 的源码与依赖相对服务器原 `75c0ec4` 无差异；先通过 `deploy:dry-run:dev`，再用原 `deploy-release.sh` 执行 PostgreSQL 18/本地库/CF 识别预检、备份与离线 Compose 部署。该次验收的 release 为 `manual-a97c5ed-apple-esm-dirty-20260917-0949`，回退基线为 `branch-dev-75c0ec4f991d-20260916151043`。API/Admin/数据库健康、health 200、Admin 标题正常；容器内 API bundle 与 release 的 SHA-256 相同（`27ecc6039fcb00e5828ea78f235ca38ad747b4a826f5c6d2de92c44bd69e7e33`），私有 `.env` 哈希未变，ledger 保持 13 项、无待执行迁移。本次新备份 `backups/toccards-test-20260917-095015-before-manual-a97c5ed-apple-esm-dirty-20260917-0949.dump`，没有做整库恢复。首次失败发布的回退事实保留，不能算首次发布成功。

只使用原 Apple 官方 TEST 的 token 读取原 JWS，**没有再次请求 Apple 发送 TEST**；官方签名、`TEST` 类型、`Sandbox` 环境、beta Bundle、UUID 和 SHA-256 逐项匹配。仅把同一 signedPayload 经 `https://dev-callback.tcgcard.fun/api/v1/apple/notifications/v2/sandbox` 重放一次，公网返回 Linux 200。只读查原 inbox `01M2PFJSQYF9866127S9TNCSJK`：状态 `processed`、attempts=6、`last_error=null`、UUID 为 `e2003ab6-6389-4c9c-b5a3-fd878129da9e`、processed_at=`2026-09-17T01:54:10.187Z`；唯一结构化通知 `notification_type=TEST`、状态 `processed`、有 decoded_payload，payload SHA-256 为 `ed189602840ec2b134ddc8b9deb31827977dfa449c30252010d2a2b7c3832e70`。总 inbox 1、结构化通知 1、交易 0、购买链 0；原失败记录未删除或伪造。公网复核 Sandbox GET 为 405、空 POST 为 Linux 400、其他 API 为 404。Code Review 自审核对实际 ESM 绑定冲突、独立 Linux 构建选项、通知幂等和错误状态、回退与卷/配置边界，修正首次发布暴露的冲突后未发现阻断项。真实购买、Restore、续订和真机端到端未运行，不能由 TEST 推断通过；上述手工验收时修复尚未提交，后续远端 dev 的自动发布结果需单独核对。

## Cloudflare Apple Sandbox 回调代理（2026-09-16/17，初次部署检查点）

用户授权通过 CF 将公网 Apple 回调转入 Linux。新增 `deploy/cloudflare/apple-callback/` 独立 Worker、配置、测试与部署说明，仅处理 `POST /api/v1/apple/notifications/v2/sandbox`。请求正文按字节转发，限制 200,000 字节，不转发客户端 Authorization/Cookie、不重试、不缓存；3xx 显式拒绝，上游 HTTP 失败保留，连接/超时返回 502，截止时间覆盖上游响应正文。该 Worker 无数据库、KV、R2、Apple 私钥或邮件凭据绑定，Linux 继续负责通知入库和 JWS 验签。

运行时问题与修复：首版 Node 测试 7/7 和 dry-run 通过，但真实 CF 返回 502。tail 日志明确指出 Workers 不支持 `redirect: "error"`，请求未到达 origin。新增仅 HTTP 的 Workerd/Miniflare 运行时回归（没有数据库绑定或 D1 基座），原实现稳定失败 `502 !== 200`；改为 `redirect: "manual"` 并显式拒绝 3xx 后，完整 8/8 通过。运行时 fetch mock 的请求体是流，最初用字符串 body 匹配得到工具侧 500；取消不适用的 body matcher，原始字节传递仍由独立断言保护，未放宽 200 成功门槛。最终真实边缘请求已通过参数校验；裸 IP 回源返回 403/1003，因此配置改为专用回源域名。

最终 `node --test deploy/cloudflare/apple-callback/worker.test.mjs` 为 8/8、0 跳过，`node --check`、根 `pnpm lint` 和 Wrangler dry-run 通过。Code Review 自审核对路径/方法、固定 origin、正文大小、凭据与重定向边界、取消/超时、失败确认及无重试，未发现本轮代码级阻断项。未运行应用全仓或 Flutter 测试：本轮未改共享业务代码、依赖、数据库或客户端。

以下为用户补齐 DNS 之前的部署检查点，后续进展见本页首节：

- Worker：`toccards-apple-callback-dev`，最终 Version `1b7c6ba8-1a87-4774-832a-c23d21581655`，2026-09-17 发布；`LINUX_CALLBACK_ORIGIN=http://dev-callback-origin.tcgcard.fun:8089`。
- HTTPS 入口：`https://dev-callback.tcgcard.fun/api/v1/apple/notifications/v2/sandbox`，另保留 `https://toccards-apple-callback-dev.product-dce.workers.dev` 诊断入口，preview URLs 关闭。
- 自定义域名先通过 Worker domain changeset 确认无更新、移除或冲突，再通过 API 以 `override_existing_origin=false` 和 `override_existing_dns_record=false` 创建；后续再次核对所属 Worker 无变化。没有覆盖其他服务域名。
- 通过有效 TLS 校验访问固定域名：Admin scans 为 404，Sandbox 路径 GET 为 405，空 JSON POST 为 530/1016；DNS 查询确认 `dev-callback-origin.tcgcard.fun` 为 NXDOMAIN。当前尚未成功将请求转入 Linux，不能将 HTTPS 已部署写成 Apple 回调完成。
- 缺失记录为 `tcgcard.fun` 区域中的 A `dev-callback-origin → 111.10.170.43`，必须为 DNS-only（灰云）。现有 OAuth 可管理 Worker/自定义域名，但读取和创建该 A 记录均为 403/10000。用户已登录控制台，浏览器工具仍报 `unsupported Codex auth method: apikey`，Windows Computer Use 的 kernel assets 初始化在重置后仍失败，未据此执行任何 UI 写操作；需要用户手动添加记录或提供有 DNS Read/Edit 权限的 Token。

原 Linux API、Admin、数据库、CF dev/prod API、向量服务和既有旧识别 Tunnel 未修改；未更改路由器映射、App Store Connect URL，也未发送 Apple TEST 通知。CF 边缘至 origin 目前设计为 HTTP，边缘 HTTPS 不等于端到端 TLS；且代理自身只放行回调路径不改变用户整端口 NAT 的开放范围。待 DNS 生效后，应先验证 CF 空请求得到 Linux 400，再做 Apple TEST 通知、数据库入库及签名验证。本轮未 Git 提交或推送。

2026-09-17 用户后续提供截图，显示 App Store Connect 的“沙盒环境服务器 URL”为上述 `https://dev-callback.tcgcard.fun/api/v1/apple/notifications/v2/sandbox`；截图未展示 App 身份，不据此推断 beta App 的最终通知目标。复查 Cloudflare Public DNS 的回源 A 记录仍为 NXDOMAIN；附加 Google Public DNS 查询因代理连接中断未取得结果，未标记为通过。真实 CF POST 仍返回 530/1016，Linux 空请求仍为预期 400，通知 inbox/TEST 记录均为 0。因此没有提前触发 Apple TEST，仍等待 Cloudflare 回源 DNS 配置，而非再次要求填写 Apple URL。

## Apple Sandbox 公网入口核查（2026-09-16）

用户提供 `111.10.170.43:8089/api/v1/apple/notifications/v2/sandbox`，并确认目标为 `192.168.50.201:8080/api/v1/apple/notifications/v2/sandbox`。本轮只核查连通性与 HTTPS 条件；未修改服务器服务、网关映射、DNS、证书或 App Store Connect。

- Linux 本地 `POST /api/v1/apple/notifications/v2/sandbox` 携带空 JSON 返回 `400 {"error":"INVALID_REQUEST"}`，与缺少 signedPayload 的既有契约一致，未产生通知入库。浏览器 GET 不是 Apple 通知的验收方法。
- 当前电脑直连公网 HTTP 约 5 秒被关闭，HTTPS TLS 握手收到 EOF；通过既有代理请求 HTTP 得到 502，HTTPS 同样未建立有效 TLS。服务器直连该公网 TCP 端口超时；这些来源都处于现有内网/代理环境，不能单独证明真正外网必然不可达，仍需外网复验或检查 NAT 回流。
- 实际 Web 容器为 `8080 → 80` 的 HTTP 服务，API 仅容器内 `3000`，没有监听 HTTPS 443/8443/8089。服务器 80 已由其他项目占用，本次未调整它。将公网 8089 直接转发到该 8080 不会自动提供 HTTPS。
- [Apple 官方通知接入要求](https://developer.apple.com/documentation/appstoreservernotifications/enabling-app-store-server-notifications)明确 HTTPS 与 TLS 1.2+；[App Store Connect 配置说明](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications)区分 Sandbox/Production URL。最终需提供可信 HTTPS 入口，仅代理既有 Sandbox 路径；纯端口 NAT 本身不限制 URL 路径，不能据此宣称 Admin 和其他 API 仍未暴露公网。

当前仍缺可用 HTTPS 域名/证书或相应 DNS 管理条件，未发起 Apple TEST 通知，未宣称公网回调已完成。后续按[集中处理清单](development-plan.md#linux-dev-集中处理清单2026-09-16)解决入口和配置权限，再使用有效 Apple 通知验证入库与验签。

## dev 整改合并、自动部署与扫描复验（2026-09-16）

用户明确接受提交验收文档、合并双方改动、推送 dev、验证现有 Linux 自动部署及扫描写库的执行顺序。先将 6 份凭据/部署验收文档提交为 `dev-inner@628cf25`；随后在最新 `dev@a419415` 合并 `dev-inner`，无冲突，得到 `75c0ec4f991d276a54caf3cde6c75858588e7ff1`。自审比对确认 dev 的 Admin 日期/环境筛选增量完整保留，Workers/Linux/Flutter 实现与已验证的整改分支一致，PostgreSQL migration SQL 及冻结目录无改动。

| 合并后检查 | 实际结果 |
|---|---|
| `pnpm lint`、`pnpm type-check --force` | 均退出 0，4 个共享包依赖方向通过，类型检查 7/7、0 缓存 |
| `pnpm --filter @kando/workers-api exec vitest run src/linux src/scan src/db/postgres-database.test.ts src/cors.test.ts src/index-postgres-runtime.test.ts src/admin --maxWorkers=2` | 15 文件、122/122，退出 0，无跳过 |
| `pnpm --filter @kando/admin-web test` | 22/22，退出 0；含保留的后台筛选与内网入口契约 |
| `node --test deploy/linux/preflight.test.mjs deploy/linux/offline/web-server.test.mjs` | 9/9，退出 0 |
| Flutter test 环境/发布配置/分享定向测试 | `flutter test --no-pub --dart-define=APP_ENV=test test/api_environment_test.dart test/release_config_test.dart test/card_detail_actions_test.dart --reporter expanded`，15/15，退出 0；`flutter analyze --no-pub` 无问题 |
| dev/prod 打包预演 | `pnpm --filter @kando/workers-api deploy:dry-run:prod` 与 `deploy:dry-run:dev` 均退出 0；prod 仅 dry-run，无发布 |
| GitHub iOS 编译 | 合并提交触发的 [iOS build 35066969713](https://github.com/kando6370-wq/toccards/actions/runs/35066969713) 已 completed/success；仅无签名 release 编译，不代表最终 IPA 或设备验收 |
| 合并检查 | 两个发布 shell 分别 `bash -n`、`git diff --cached --check` 通过；20 份合并涉及的 Markdown 共 214 个本地链接/锚点通过 |

服务器自动发布：

- 先在 watcher 锁内确认其专用 source checkout 无用户改动/私有 env，再备份并更新安装的 `watch-branch.sh`，使其覆盖新增运行时和发布预检测试。`watcher.env` 新增项目级 HTTP/HTTPS 代理、NO_PROXY、NODE_USE_ENV_PROXY，继续监控 dev；备份后缀 `before-20260916-150706`，脚本 SHA-256 为 `d81a8d15b5c3885e181c5092b8484ea2eb7aae1095b84306c81a317c6b9d66c7`。没有改变全局代理、其他项目或 crontab 周期。
- 推送后 `git ls-remote` 与本地 SHA 一致。既有 cron 在 15:08 自动发现 `75c0ec4`，完成锁定依赖安装、Workers 类型检查、运行时 9 文件 75/75 与 Node 发布检查 12/12、Linux/Admin 构建。没有手工调用发布脚本绕过该流程。
- 实际 preflight 返回本地 `toccards_test`、PostgreSQL 18、CF reachable、pending migrations 为空；随后备份 `/home/user/apps/toccards-test/backups/toccards-test-20260916-151045-before-branch-dev-75c0ec4f991d-20260916151043.dump`，1,120,645,783 字节、权限 600，`pg_restore --list` 可读取。没有整库恢复演练。
- current 为 `/home/user/apps/toccards-test/releases/branch-dev-75c0ec4f991d-20260916151043`；manifest 的 branch=dev、sha 为完整合并提交、built_at=`2026-09-16T07:10:43Z`、source=kd201-branch-watcher。`last-deployed-sha` 与目标提交一致；原 `a419415` release 保留供回退。
- API/数据库 healthy、Web 正常；原 `toccards-linux-test_postgres-data` 与 `toccards-linux-test_scan-images` 保留，ledger 仍为 13 项，无新迁移。API 容器 bundle 的 SHA-256 与 release 文件一致，实际 sourcemap 含 `createHttpVectorRecognition`，不再要求旧 OCR 字段。邮件、Apple 凭据、私钥格式及 API 代理均回读确认保留。

部署后烟测：health、games、卡牌 `100223`、iOS/Google app-config、Admin HTML 与 10 个资产、3 个 CORS origin 和分享 canonical 均通过，资产与服务器 release 逐字节比较一致；未登录 Admin scans 为 401。通过临时匿名账号、合成 745×1043 JPEG 和 512 维单位向量发起扫描，约 1.022 秒返回 5 个候选；Linux 数据库验证 development 扫描记录、consumed 额度及本地图片。免费额度由 10 变 9，同 request ID 重放后仍为 9、consumed=1；确认收藏返回 201，主记录与初始事件均保存 `12.5 USD` 及可靠历史起点。测试账号的业务记录和图片/metadata 已精确清理，保留已分配 UID 占位与基础设施锁。

Code Review 自审通过：合并未产生新业务改写，双方增量和测试均保留；监听器仍使用同一版本化发布脚本、原卷与私有配置，运行结果与合并 SHA 一致。未执行 Workers/Flutter 全仓测试、两端签名包或真机识别准确率/购买；本轮是定向合并验证及真实 Linux 服务端链路验收。公网 Apple 回调、统计配置、浏览器 Logout 服务端撤销和旧 CF dev 退役仍在集中清单中，本次未修改 CF dev/prod、DNS 或 App Store Connect。

发布后的 9 份说明文档已按运行事实更新，55 个本地链接/锚点及 diff 检查通过；该文档增量不改变应用或部署构建输入，按 watcher 路径规则仅推进观察基线，不触发重建。应用运行版本仍以上述 `75c0ec4` 为准。

## Linux Apple Server API 凭据与 Sandbox 鉴权（2026-09-16）

用户提供 Issuer ID，并明确 dev 对应本机 `SubscriptionKey_A2Q978K984.p8`。本轮仅配置 Linux 的 `APPLE_IAP_ISSUER_ID`、`APPLE_IAP_KEY_ID`、`APPLE_IAP_PRIVATE_KEY`；私钥文件内容未输出日志或写入仓库。执行时 current 仍为 `branch-dev-a4194156c572-20260916110050`，部署版本中的 Apple Server API factory 和 signed-data verifier 源码通过 sourcemap 与本地逐字节核对一致。配置前本地库的待处理通知、correction_required 及交易数均为 0。

临时诊断工具直接打包项目现有 `createAppleServerApiClient` 与 `createAppleNotificationVerifier`，使用锁定的 Apple 官方 SDK 3.1.0，未修改业务代码或依赖。先在既有 API 容器内通过标准输入传入候选凭据，只读查询最近 60 秒的 Sandbox 通知历史；HTTP 200 后才备份并更新服务器运行配置。API 重建后，第二次诊断完全读取新容器环境并复验同一路径。两个查询均为 `POST /inApps/v1/notifications/history`，这是带过滤条件的只读查询，没有调用 `requestTestNotification` 或购买/生产 API。

| 检查 | 实际结果 |
|---|---|
| 私钥与项目配置 | P-256 私钥解析、签名/验签通过；项目 Server API client 与 Sandbox notification verifier 均构造成功，Bundle 为 `com.kando.kandoApp.beta` |
| Apple Sandbox 鉴权 | 配置前候选凭据、配置后容器环境分别返回 HTTP 200；最近 60 秒 notification_count 均为 0、has_more=false，无重试 |
| PEM 换行 | `.env` 双引号转义换行经 Node 解析与原始 PEM 完全相同；Compose 注入后 API PID 1 环境可正确解析私钥 |
| 配置边界 | 备份 `/home/user/apps/toccards-test/shared/.env.before-apple-20260916-141728`；配置与备份权限均为 600；逐键比较只改 Apple 三项，邮件、代理、数据库及其他设置保持 |
| 运行状态 | 只执行原 Compose 的 `up -d --no-deps api`；API healthy，health/app-config 为 200，未登录 Admin scans 为 401，Web/数据库容器与 current 保留 |
| 数据与清理 | migration ledger 13 项、通知 inbox/校正待办/交易均为 0；临时私密 JSON 已删除，容器诊断文件已清理，原用户 `.p8` 文件保留 |

两个诊断进程出现依赖的 `punycode` 弃用警告，但均退出 0；没有为去除警告升级依赖。配置自审核对同组凭据、Sandbox 隔离、敏感输出、备份/回退、只读请求及仅重建 API，通过。未重跑应用全仓测试或业务构建（源码和依赖未变化），临时诊断 bundle 的实际运行结果如上。

Issuer ID/Key ID/私钥缺项已解除；本次没有真实交易，因此未验证 Fresh Purchase、Restore、App Attest 真机证据、Server API 交易校正或公网通知闭环，也未变更 App Store Connect、CF、watcher 或发布分支。此前发现的实际 dev 版本缺少向量整改仍须优先处理。本阶段文档未提交或推送。

## Linux ZeptoMail 配置与单封邮件验收（2026-09-16）

用户提供仓库外 Token 文件，并明确授权向指定 Gmail 地址发送一封测试邮件。文件含 `Zoho-enczapikey ` 前缀；代码 `sendZeptoMail` 会自行添加该前缀，因此读取时去掉前缀后仅写入原始 Token，未改用户原文件。Token 值未输出到日志或写入仓库。

执行前回读服务器确认 watcher 已将 current 更新为 `branch-dev-a4194156c572-20260916110050`，manifest 为 `dev@a4194156c5721b2c23255f44f1b64c2268a6382c`、`source=kd201-branch-watcher`，构建时间 `2026-09-16T03:00:50Z`。已比对实际部署 sourcemap 中 ZeptoMail、验证码邮件和注册路由三个文件与本地源代码一致，随后按该运行版本操作，没有覆盖为旧手工 release。

持有原 watcher/deploy 锁后，备份服务器配置到 `/home/user/apps/toccards-test/shared/.env.before-zeptomail-20260916-135420`，只修改 `ZEPTOMAIL_TOKEN`，再用原两份 Compose 文件执行 `up -d --no-deps api`。配置与备份均为 600，临时上传的私密 Token 文件已删除；API 进程回读确认 Token 已设置且不含授权前缀，其他配置逐键比较未变，API 健康检查通过。

2026-09-16 13:55:15（Asia/Shanghai）仅调用一次 Linux `/api/v1/auth/register/send-code`，使用已核对的现有注册验证码流程发送测试邮件。HTTP 200、`success=true`，耗时约 945 ms；该路由仅在 ZeptoMail 请求成功且返回 request_id 后报告成功。数据库只读复核本次产生 1 条未使用的 register 验证码，有效期 600 秒，未创建 App 用户。随后用户明确确认已收到邮件，完成 Linux → ZeptoMail → 实际邮箱的投递验收；没有重试或发送第二封邮件。

运行版本额外发现：fetch 后确认 `dev@a419415` 不包含整改提交 `b27ca90`、`a512dbd`、`a457f70`；容器中 API bundle 的 SHA-256 与 current 文件一致，其 sourcemap 中 Linux 配置仍要求旧 OCR 键且未构造 HTTP 向量适配。此前手工版本的扫描成功证据不适用于这个已被 watcher 替换的版本。该项已列入集中清单最高优先级，本次没有擅自合并分支、改变 watcher 或覆盖应用版本。

本轮邮件配置、单封发送及收件通过，缺失凭据清单已更新。配置自审核对 Token 前缀、受限文件权限、单键修改、仅重建 API、临时文件清理和单次发送约束，通过；6 份修改的 Markdown 中 33 个本地链接/锚点及 `git diff --check` 通过，修改文件中未发现该 Token 明文。未执行完整注册、验证码输入校验或找回密码，未修改业务代码、依赖或 migration SQL，也未运行与本次配置无关的应用构建/测试。仅 API 容器因配置重建，数据库与 Web 容器保留，ledger 仍为 13 项；本阶段文档未提交或推送。

## Linux Admin 既有管理员登录与只读验收（2026-09-16）

基线 `dev-inner@a457f70`。按用户提供的既有管理员凭据，在 `http://192.168.50.201:8080` 完成浏览器真实登录，显示“超级管理员”；扫描记录、订单统计、苹果通知页面均正常打开。密码与访问/刷新 token 仅在验证进程或登录流程中使用，没有写入仓库、文档或临时脚本。

独立接口验证通过 `POST /api/v1/admin/auth/login` 返回 200，并用参数中对应的会话 ID 在 Linux `toccards_test.session/admin_user` 只读核对：owner 为 admin、角色 super_admin、状态 active、会话未撤销。容器环境确认数据库主机为 `db`、库名 `toccards_test`、APP_ENVIRONMENT 为 development。

- 9 项授权只读接口全部 200：scans、billing/transactions、apple-notifications、analytics/installations、users、card-overrides、app-versions、billing/transactions/options、apple-notifications/options；另查公共目录卡牌 `100223` 返回 200。
- 扫描、订单、苹果通知总数均为 0，与直接查询 Linux 数据库一致；当前无数据不代表有记录详情、图片查看、导出或复杂筛选已验收。
- 独立接口会话的 refresh 返回 200；调用 logout 后旧 access token 请求 scans 返回 401，数据库 revoked_at 非空。浏览器点 Logout 后回到空登录表单并关闭验证标签页。
- 源码显示现有浏览器 Logout 仅清除本地会话、未调用后端 logout；本次没有修改这一既有行为，因此只能确认独立接口会话被服务端撤销，不能把页面返回登录表单视为同等撤销证据。该项记入集中清单后续处理。

本次只产生正常登录/刷新/退出会话操作，没有重置管理员、变更权限或修改业务数据，没有部署或数据库迁移。只更新当前版本 Admin 文档、验证记录和集中清单；未重跑应用构建/测试（业务代码未修改），未提交或推送。管理员凭据缺项已解除，其余邮件、Apple、统计和真机缺项继续保留。

## Linux dev 外部服务配置与代理（2026-09-15/16）

本阶段基于已提交并推送的 `dev-inner@a512dbd`，按用户“进行下一步”核对外部配置，随后按用户提供的 `192.168.48.10:7890` 代理配置现有 Linux API。用户最新要求先集中整理剩余缺项，再统一解决，因此凭据、公网入口与设备需求集中列入[开发计划](development-plan.md#linux-dev-集中处理清单2026-09-16)。代码改动仅限配置模板和文档，没有改业务逻辑、数据库 Schema 或 migration SQL。

2026-09-15：CF `toccards-api-dev/settings` 回读成功，公开变量与 `wrangler.toml` 的 `env.dev.vars` 一致；Secret 仅返回名称，不能据此获得明文。Wrangler `whoami` 因网络 fetch failed 退出 1，随后通过已授权账户的 CF REST API 完成只读核验。Linux 缺少的 `GOOGLE_CLIENT_ID`、`APPLE_APP_ATTEST_APP_ID`、`MAIL_FROM_ADDRESS`、`MAIL_FROM_NAME` 已按原 dev 配置补齐，JWT/数据库连接及其他私密配置保留。

从 [Apple 官方证书页面](https://www.apple.com/certificateauthority/)下载 Apple Root CA、G2、G3，将 DER 按现有逗号分隔 base64 契约写入 `APPLE_ROOT_CERTIFICATES_BASE64`。Node `X509Certificate` 校验三者 CA 属性、自签名和有效期通过；Python cryptography 的旧 Root CA 签名校验曾报 `Unsupported signature algorithm`，该检查没有记为通过，最终以 Node 验证结果为准。SHA-256 分别为 `b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024`、`c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050`、`63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179`。配置存在与证书有效不代表真实 Apple 购买或通知已经验收。

2026-09-16：Google 验证接口直连曾在宿主机和 API 容器稳定得到 `UND_ERR_CONNECT_TIMEOUT`（约 10.5 秒）。同一服务器通过用户提供的代理，`curl --proxy socks5h://192.168.48.10:7890` 与 `curl --proxy http://192.168.48.10:7890` 均在约 0.77 秒收到 Google HTTP 400，确认该端口同时支持 SOCKS5 和 HTTP CONNECT。服务器 Node 22.22.1 实际支持 [Node 22.21.0 起提供的环境代理](https://nodejs.org/docs/latest-v22.x/api/cli.html#node_use_env_proxy1)，无需引入代理包或修改 OAuth 路由。

服务器 `shared/.env` 已配置 `NODE_USE_ENV_PROXY=1`、HTTP/HTTPS 代理为 `http://192.168.48.10:7890`，`NO_PROXY=localhost,127.0.0.1,::1,db,api,192.168.50.201,192.168.48.10,recognize-vec.tcgcard.fun`。只在本项目 API 启动环境中生效，未设置宿主机全局代理或 Docker daemon 代理。配置前备份、持有 watcher/deploy 锁，使用原两份 Compose 文件执行 `up -d --no-deps api`；首次遇 watcher 正在拉取，锁拒绝时退出 20 且未修改配置，之后取得锁并正常执行。

| 检查 | 结果与边界 |
|---|---|
| 私有配置备份与 API 重建 | 公开配置备份 `/home/user/apps/toccards-test/shared/.env.before-services-20260915-171759`；代理备份 `.env.before-proxy-20260916-092027`；均权限 600。两个应用脚本最终退出 0，仅 API 容器重建 |
| 发布预检与根证书 | 实际 `current/deploy/linux/preflight.mjs` 返回 PostgreSQL 18、CF reachable、pending migrations 为空；3 张根证书均通过 Node 校验 |
| 实际 API 进程配置 | 从容器 `/proc/1/environ` 白名单回读确认代理和公开配置已生效、3 张根证书存在、`APP_ENVIRONMENT=development`、数据库主机为 `db`，TLS 校验未关闭 |
| Google 出站 | 在 API 容器仅依赖持久化环境执行原生 `fetch`，返回 `400 invalid_token`，约 817 ms；无真实用户令牌，因此只判定网络可达 |
| 代理路径反证 | 仅在单独 `docker exec` 进程将代理改为不可达的 `127.0.0.1:9`，Google 明确 `ECONNREFUSED`；同进程 API 回环健康与 CF 识别健康仍为 200，证明代理启用及 NO_PROXY 生效，未修改运行服务的环境 |
| 内网接口复验 | API health、Admin HTML、iOS/Google app-config 均 200；未登录 Admin scans 为 401；Google OAuth 使用唯一无效测试令牌返回 422，约 779 ms；Apple Sandbox 空请求返回 400，拒绝写库 |
| 数据与版本边界 | current 仍为 `manual-dev-inner-c9742fa-dirty-20260915-155717`，数据库 healthy、ledger 13 项、通知 inbox 0 条、active 管理员 1 个；未执行业务数据写入或 migration |
| 公网回调调研 | 当前 CF 凭据可读 Tunnel 配置，但 DNS 读取返回 403。既有 `smart-mtg-recognition` Tunnel 为 down，映射旧 `scanning.tcgcard.fun` 服务；未改该资源，未创建新 Tunnel/DNS 或修改 App Store Connect |

源码模板默认关闭代理，填写经核对的 dev 公开变量，并明确 HTTP(S) 协议与 Node 最低版本；没有添加模拟生产凭据或将实际密钥写入仓库。Code Review 自审核对配置来源、备份/回退、仅重建 API、NO_PROXY 和 TLS 边界，无配置级阻断发现。模板解析确认 10 项公开配置与 CF dev 回读一致、8 项私密值为空；5 份修改的 Markdown 中 33 个本地链接/锚点及 `git diff --check` 通过，冻结目录/业务源码/依赖锁文件无改动。本次没有重跑应用测试或构建，因为业务代码、依赖与打包未修改，验证采用实际容器配置和原接口路径。

剩余未验：管理员真实登录，Google/Apple 授权登录，邮件收件，真实 Apple Sandbox 购买/Restore/Server API 校正/公网通知，Mixpanel/Singular 收件，iOS/Android 真机与最终签名包。Apple Server API 三项、ZeptoMail Token、Mixpanel/Singular 四项私密配置仍缺失；Google 的代理缺项已解决。没有发送邮件或消息、没有扩大公网访问面、没有提交/推送本阶段改动或合并 dev。剩余集中处理顺序与需要材料以开发计划中的清单为准。

## dev 迁往 Linux：发布入口整改与既有实例升级（2026-09-15）

基线为已提交并推送的 `dev-inner@c9742fadad6783e83667e8204f2951de7bbd6b9b`，本阶段按用户授权整改发布流程并升级 `192.168.50.201` 已存在的项目。开发机为 Windows、Node 22.20.0、pnpm 11.9.0；服务器 `srs-node-test1` 使用 Node 22.22.1、Docker Compose 2.40.3 和 PostgreSQL 18.6。没有新建第二套 Compose 项目或数据卷。

根因、失败证据与修复：

- `deploy:dev` 原来仍调用 Wrangler，会继续向 CF 发布；Admin 环境意图测试修正预期后在旧脚本上得到 1 失败/2 通过。现在 `build:dev` 构建 Linux API 与 Admin development，`deploy:dry-run:dev` 生成发布包，`deploy:dev` 通过显式 SSH 目标调用原版本化发布脚本。prod 发布保持原 Wrangler 入口。
- 既有 `backup_database` 在缺少 `current` 链接时直接返回，即使数据库仍有数据。回归测试通过真实 Bash 函数复现：临时恢复旧函数后，备份文件数量断言为 `0 !== 1`；按原字节恢复修复后通过。现在任何已存在且运行的数据库均须备份。
- 标准 Compose 原默认 PostgreSQL 16，服务器实际离线数据库为 18.6。标准/离线配置统一 18，显式保留原 `PGDATA=/var/lib/postgresql/data`；新预检通过拟发布密码执行容器内 TCP 只读查询，核对库身份、18 大版本、migration ledger 和 CF 512 维/cosine/Top 5 健康契约。预检失败时，真实 release 脚本回归确认不会执行备份或容器操作。
- 发布后手工复核发现，通过 `current` 软链接运行预检会静默退出 0：Node 将 `import.meta.url` 解析为真实文件，但原入口比较只对 argv 使用 `path.resolve`。新增目录软链接回归，在修复前运行 `node --test --test-name-pattern='current release symlink' deploy/linux/preflight.test.mjs` 得到 1 失败/1 通过（另一项为同名匹配的备份测试）；现改为 `realpathSync` 比较。初次正式发布通过真实 artifact 路径调用，已实际执行预检；该缺陷影响手工通过软链接执行的入口。

| 检查 | 实际命令或证据 | 结果 |
|---|---|---|
| 发布与入口回归 | `node --test apps/admin-web/test/api-environment-intent.test.mjs deploy/linux/preflight.test.mjs deploy/linux/offline/web-server.test.mjs` | 最终 12/12，退出 0，无跳过；包含软链接回归修复后的全部用例 |
| 根检查 | `pnpm lint`、`pnpm type-check --force` | 均退出 0；类型检查 7/7、0 缓存 |
| Linux 发布包 | `pnpm --filter @kando/workers-api deploy:dry-run:dev` | 退出 0，40 个文件；39 个部署输入与工作区逐字节相同，另有 manifest；不含 `.env`、依赖目录或数据卷，shell 文件均为 LF |
| prod 兼容构建 | `pnpm --filter @kando/workers-api deploy:dry-run:prod` | 退出 0；仅打包，未发布 |
| Compose 与脚本 | 标准/离线 `docker compose config --format json`；两个 CI shell 文件分别 `bash -n`；两个新增 `.mjs` 的 `node --check` | 通过，保留原卷与 PGDATA；标准镜像未实际启动 |
| 服务器预检 | `node --env-file=shared/.env <artifact>/deploy/linux/preflight.mjs <artifact>`（由发布脚本执行） | 退出 0；`toccards_test`、PostgreSQL 18、CF 可达，仅待执行 0012 |
| 既有发布脚本 | 设置明确 release ID 后执行 `bash <artifact>/deploy/linux/ci/deploy-release.sh <artifact>` | 退出 0；备份、离线构建、迁移、API/Admin 健康检查及切换 current 完成 |
| 本地数据库迁移 | `docker logs toccards-linux-test-migrate-1` 与只读 psql 回读 | 0012 事务提交，`UPDATE 0`；ledger 从 12 增至 13，migration 容器退出 0 |
| 内网公开入口 | `/health`、`/games`、`/cards/100223`、iOS/Google `/app-config`、Admin HTML/10 个资产、分享页与 3 个允许 origin 的 CORS | 全部通过；卡牌为 Jace's Sanctum，资产 SHA-256 与发布包一致，分享 origin 为 `http://192.168.50.201:8080`；未登录 `/admin/scans` 为 401 |
| 受控服务端扫描 | 临时匿名账号、合成 745×1043 JPEG、512 维单位向量，经内网 `/scan/recognize` 与 `/scan/:id/confirm` | 200/201；CF 返回 5 个候选，首次约 1.664 秒；Linux 数据库实查账号、development 扫描记录、consumed 额度、收藏与初始事件 `12.5 USD`，Linux 图片卷文件存在；相同 request ID 重放结果相同、未再次扣次 |
| 最终软链接入口复验 | 在服务器通过 `current/deploy/linux/preflight.mjs` 执行真实预检，再以 `APP_ENVIRONMENT=production` 重试 | development 返回 CF reachable、pending migrations 为空，退出 0；production 明确拒绝并退出 1；最终 API/数据库 healthy、migrate 退出 0 |

发布与回滚事实：

- 先 fetch `feature/linux-test-environment`，其 Compose、离线 Compose、release 脚本和 Node runtime 准备脚本与服务器旧 release 按 LF 字节比较一致，确认复用该分支的既有部署。
- 原 release：`/home/user/apps/toccards-test/releases/branch-dev-6a9640443c81-20260910155650`，保留供应用回退。
- 当前 release：`/home/user/apps/toccards-test/releases/manual-dev-inner-c9742fa-dirty-20260915-155717`。manifest 为上述 `c9742fa` 基线、`dev-inner`、`working_tree_dirty=true`，构建时间 `2026-09-15T07:56:56.383Z`；不能描述为纯提交版本。前一版 `manual-dev-inner-c9742fa-dirty-20260915-153655` 已完成上述服务端烟测，最后一次发布仅修正预检软链接入口，API/Admin 产物逐字节相同。
- 最终上传包 `linux-release-J3Bhzj.tar.gz`，SHA-256 为 `72b047edbb38ed80962d13e265354d5de2954f1d17d80132f2b991d11d009828`，SFTP 上传后远端校验一致，再调用同一 release 脚本。此次使用用户提供的密码登录，没有配置 SSH authorized_keys；日常 `deploy:dev` 的非交互 SSH key/agent 路径未做真实发布验收。
- 数据库备份：`/home/user/apps/toccards-test/backups/toccards-test-20260915-153659-before-manual-dev-inner-c9742fa-dirty-20260915-153655.dump`，1,120,644,979 字节、权限 600，`pg_dump` 退出 0，`pg_restore --list` 可读取；没有执行整库恢复演练。
- 最终修正仍完整执行预检和备份：`/home/user/apps/toccards-test/backups/toccards-test-20260915-155720-before-manual-dev-inner-c9742fa-dirty-20260915-155717.dump`，1,120,645,398 字节、权限 600，目录可读取；无待执行 migration，ledger 保持 13 项。
- 配置备份：`/home/user/apps/toccards-test/shared/.env.before-manual-dev-inner-c9742fa-dirty-20260915-153655`。只更新识别 origin、CORS origin 和标准 PostgreSQL 镜像，其他键、密码及旧 OCR 回滚键保留；新版本不读取旧 OCR 键。
- 保留 `toccards-linux-test_postgres-data` 与 `toccards-linux-test_scan-images`；API 和数据库 healthy，Web 运行。0012 不改 Schema，当前匹配记录为 0；只在独立 Linux 库执行，未操作 CF 共享数据库，应用回退不会自动逆向 migration。
- 发布期间持有现有 `watcher/watch.lock` 并复用 `shared/deploy.lock`；完成后监听器恢复每两分钟检查。它仍监控 `dev@b941a3f`，未更改其安装文件、crontab 或状态。后续 dev 发布可能接替本次手工版本，需协调合并。
- 受控扫描的临时账号、安装记录、会话、额度、扫描、收藏/事件、默认 Folder、偏好和图片/metadata 均已精确清理；保留分配过的 UID 占位与基础设施锁，避免复用已发出的账号编号。

Code Review 自审通过：复核入口及调用方、SSH 目标/命令引用、发布包白名单、敏感配置边界、预检只读性、先预检后备份顺序、PG18/原卷兼容、错误回退和回归测试。软链接返工后重新运行 12 项影响面测试并复审 `realpathSync` 入口判定，未发现剩余代码级阻断项；没有改共享业务路由或 migration SQL。

未运行与限制：本阶段未重跑 Workers/Flutter 全仓测试（业务代码未变化，前两阶段验证保留在下文）；未生成两端签名包或执行真机模型/局域网权限/完整登录购买。没有可用管理员登录凭据，Admin 只验证静态资源和未登录鉴权；Google Client ID、Apple 验签根证书/Server API 私钥、邮件及统计测试配置当前缺失，不能宣称这些链路可用。尝试读取已知 CF Vectorize 向量时现有管理凭据返回 401，因此实际服务烟测使用合法合成向量，不把它当成真实图片识别准确率。Windows Docker daemon 未运行，本轮真实容器验证在 kd201 的离线模式完成。客户端与环境维护者需补齐相应配置和设备验收。

文档已同步发布入口、当前服务器和数据库事实，并保留早期检查点的原日期；15 份 Markdown 的 155 个本地链接/锚点与 `git diff --check` 通过，冻结目录和业务源码无改动。当前阶段没有 Git 提交/推送、合并 `dev`、CF dev/prod 发布或旧 CF dev 资源退役；不能据此标记整体环境整改已全部完成。

## dev 迁往 Linux：App/Admin 内网入口（2026-09-15）

基线为已提交并推送的 `dev-inner@b27ca90`，本阶段按用户授权整改现有 test/development 默认入口。环境为 Windows、Flutter `3.44.7` / Dart `3.12.2`、Node `22.20.0`、pnpm `11.9.0`；没有新建第三种业务环境，也没有部署服务器或修改数据库数据。

实现与影响面：

- Flutter 的 `AppConfig.apiOrigin` 在 test 下固定为 `http://192.168.50.201:8080`，由此派生 API 与分享地址；production/default 保持原生产 API。登录、目录、收藏、扫描及版本客户端共用该配置。测试分享固定使用内网，避免复制来的服务端 `card_share_base_url` 将测试用户带到生产环境；生产仍优先采用服务端分享配置，卡牌图片继续使用原 CDN。
- Admin development 改为同源 `/api/v1/admin`，本机 Vite 的 `/api` 代理到 Linux，production 配置不变。Linux `.env.example` 同步 dev 入口与 Flutter Web 3000 端口的 CORS origin；真实服务器 `.env` 尚未修改。
- Android 从已有 Flutter `dart-defines` 的 `APP_ENV` 选择网络资源，test 仅允许 `192.168.50.201` 明文 HTTP，其他主机及 production 禁止明文。主 manifest 显式包含 INTERNET 权限。iOS 三个既有 test flavor 使用 `Info-test.plist`，仅添加该 IP 的 ATS 例外和局域网用途；生产 plist、Bundle ID 与 App Attest 设置保持原样，测试比较其余 plist 内容以防配置漂移。
- 离线 Web 代理此前把 Host 改写为 `api:3000`，导致分享 canonical/og:url 指向内部地址。修改为保留请求 Host，仍使用固定 API_ORIGIN 连接上游；没有新增对客户端转发头的信任。新增真实回环 HTTP 代理回归测试，并纳入两个既有 Linux 发布检查入口。

先失败证据：修改业务代码前，test 环境的 API/分享用例 5 失败、1 通过，分别返回旧 CF dev 或生产分享地址；Admin 环境/代理用例 2 失败、1 通过。原代理 Host 改写逻辑的反证测试退出 1，明确显示上游 host/port 与外部请求不同；恢复修复代码后同一测试通过。首次 Flutter 测试因 C 盘已满未能完成编译，不算业务失败证据；中止该进程并将本任务 TEMP/TMP 改到 D 盘后，得到上述可重复失败和最终通过结果。

| 检查 | 实际命令 / 证据 | 结果 |
|---|---|---|
| Flutter test 最窄回归 | `flutter test --no-pub --dart-define=APP_ENV=test test/api_environment_test.dart test/card_detail_actions_test.dart test/release_config_test.dart --reporter expanded` | 15/15，退出 0 |
| Flutter production 隔离 | 同上三个文件，使用 `--dart-define=APP_ENV=production` | 15/15，退出 0；生产 API 与服务端分享配置行为保持 |
| Flutter 影响面 | 下方 12 个文件的完整命令 | 109/109，退出 0，无跳过 |
| Flutter 分析 | `flutter analyze` | 退出 0，No issues found；依赖锁文件无变更 |
| Admin | `pnpm --filter @kando/admin-web test`、`pnpm --filter @kando/admin-web type-check` | 22/22 与类型检查通过，均退出 0 |
| Admin 两种产物 | `pnpm --filter @kando/admin-web exec vite build --mode development --outDir D:/Temp/kando-dev-entry-check/admin-dev`；对应 production/admin-prod | 两种构建退出 0；检查实际 JS：dev 使用相对 API，无旧 dev/生产绝对 API；prod 保留生产 API |
| 本机 Vite → Linux | 启动当前 Vite 配置，待依赖扫描完成后请求本机 `/api/v1/health` | 代理目标 `http://192.168.50.201:8080`，HTTP 200、`status=ok`；只读请求，非登录或完整业务验收 |
| 离线代理 | `node --test deploy/linux/offline/web-server.test.mjs` | 修复后 1/1，退出 0；实际子进程代理保留外部 Host 与请求路径 |
| 根检查 | `pnpm lint`、`pnpm type-check --force` | 通过，类型检查 7 个任务、0 缓存 |
| Android test / production | 分别执行 `flutter build apk --debug --no-pub --dart-define-from-file=config/test.json` 和 production.json | 均退出 0；通过 aapt 解包验证实际 manifest 选择的策略与 INTERNET 权限，test 只对指定 IP 允许明文，prod 无该例外 |
| iOS 配置 | Python plistlib 解析两份 plist，Flutter 测试核对三组 test/production Xcode 配置 | 结构有效、三组 test 指向新文件、production 指向原文件；去掉两项网络字段后完全一致。不等于已构建 IPA |
| 脚本及文档 | Git Bash `-n deploy/linux/ci/watch-branch.sh`、`node --check deploy/linux/offline/web-server.mjs`、相对链接与 `git diff --check` | 通过；冻结产品文档、生产配置、Worker 业务代码和数据库 migrations 无修改 |

Flutter 影响面命令在 `apps/flutter-app` 执行：

```sh
flutter test --no-pub --dart-define=APP_ENV=test test/api_environment_test.dart test/card_detail_actions_test.dart test/release_config_test.dart test/app_debug_overlay_environment_test.dart test/auth_repository_test.dart test/auth_session_interceptor_test.dart test/card_data_api_client_test.dart test/portfolio_api_client_test.dart test/scan_api_client_test.dart test/app_upgrade_repository_test.dart test/currency_rate_api_test.dart test/subscription_entitlement_api_test.dart --reporter expanded
```

Android 解包确认的 test Debug APK SHA-256 为 `646ec6028ad93f87eb86e7641e2dc6f63d220311eb9debd4261b3ea93cea9d2b`；production 配置的 Debug APK 为 `c67fd140757982dbb02d3a656ef3022b492a2c713483ac61b90c8c056aa5be68`。曾因验证脚本使用错误相对路径及在产物重写时读取而无法解包，等待构建完成并改用绝对路径后已分别复核。构建提示的 Gradle/AGP/Kotlin 与 SDK XML 版本警告为既有工具链事项，本阶段没有绕过检查或升级依赖。

Vite 首次只读代理验证已获得 200，但关闭服务早于异步依赖扫描完成，输出了 dep-scan 关闭错误；随后等待扫描完成再执行相同健康请求并关闭，退出 0 且无该错误。这是验证脚本关闭时序问题，没有修改产品的依赖优化配置。

Code Review 自审通过：检查默认环境与四类业务客户端、test/production 分享分支、Admin 生产产物、Android 编译参数到 manifest 的实际选择、iOS plist 与原生产设置、代理上游与 Host 边界；没有发现阻断问题。配置与代理变化均有失败证据或反证，并在修改后按原路径复验。

未运行：iOS 编译/签名及最终 IPA App Attest 检查（Windows 无 Xcode）、Android Release 签名包、iOS/Android 真机局域网权限与完整登录/扫描/购买、Flutter Web 浏览器联调、kd201 新后端与代理部署、服务器 CORS 更新、dev 发布命令迁移和旧 CF dev 退役。客户端维护者需在两端测试包上补验，服务器维护者需准备配置并发布；本阶段仍为源码与本地验证，不能写成整体 dev 已完成迁移。未提交或推送本阶段改动，没有远程数据库迁移、数据写入或生产发布。

## dev 迁往 Linux：后端 HTTP 识别适配（2026-09-15）

范围为用户确认的整改第一步：现有 dev 业务部署后续由 Linux 接替，CF 只读向量识别继续复用，prod 保持原部署。本轮从干净 `dev-inner@601294f` 成功 fetch，并快进到 `github/dev@b941a3f81c1b48cb204e9ef23626cd052406dc15`，随后仅完成本地后端适配与验证。环境为 Windows、Node `22.20.0`、pnpm `11.9.0`、Vitest `4.1.9`。

根因与实现：Linux `loadLinuxRuntime` 原先必填旧 `OCR_SERVICE_BASE_URL`，却没有构造扫描路由所需的 `VECTOR_RECOGNITION`。新增 `src/linux/vector-recognition.ts`，将内部 Service Binding 地址映射到必填 `VECTOR_RECOGNITION_BASE_URL` origin 的 `/recognize`；10 秒超时覆盖响应正文，保留调用方取消，拒绝重定向，不新增重试。`Env` 与 Linux 运行时移除旧 OCR 字段，`.env.example` 使用现有 `https://recognize-vec.tcgcard.fun`。共享扫描业务代码、Cloudflare 入口和 PostgreSQL migrations 没有修改；资料补全、额度及扫描记录仍使用注入的本地 PostgreSQL。

先失败证据：新增配置测试在原实现上运行 `pnpm --filter @kando/workers-api exec vitest run src/linux/config.test.ts --maxWorkers=1`，退出 1，2 失败/1 通过。新向量配置因缺旧 OCR 键而无法启动，只有旧 OCR 的无向量配置反而被接受。实现后相同场景全部通过。另临时撤回 HTTP 地址映射、重新请求 `recognize-vec.internal`，执行 `pnpm --filter @kando/workers-api exec vitest run src/scan/routes.test.ts -t 'keeps Linux catalog reads' --maxWorkers=1`，目标测试因实际 URL 错误失败，退出 1；其余 33 项仅因定向过滤未运行。随后按原字节恢复源码并执行完整影响面复验。

| 检查 | 实际命令 / 证据 | 结果 |
|---|---|---|
| 配置与 HTTP 适配 | `pnpm --filter @kando/workers-api exec vitest run src/linux/config.test.ts src/linux/vector-recognition.test.ts --maxWorkers=2` | 2 文件、15/15，退出 0；含真实回环 HTTP 的请求超时、正文取消和重定向测试 |
| Linux / 扫描最窄集成 | `pnpm --filter @kando/workers-api exec vitest run src/linux src/scan/routes.test.ts --maxWorkers=2` | 6 文件、54/54，退出 0；PGlite 验证只发送向量、从本地目录补全、扫描记录及成功/失败/无匹配/超时额度结果 |
| 还原后的完整影响面 | `pnpm --filter @kando/workers-api exec vitest run src/linux src/scan src/db/postgres-database.test.ts src/cors.test.ts src/index-postgres-runtime.test.ts --maxWorkers=2` | 11 文件、84/84，退出 0，无跳过 |
| Workers 类型检查 | `pnpm --filter @kando/workers-api type-check` | 退出 0 |
| 根类型检查与依赖方向 | `pnpm type-check --force`、`pnpm lint` | 均退出 0；类型检查 7 个任务成功、0 缓存，4 个共享包依赖方向通过 |
| Admin 环境契约 | `node --test apps/admin-web/test/api-environment-intent.test.mjs` | 2/2，退出 0；本阶段未改 App/Admin 默认入口 |
| Linux 后端构建 | `pnpm --filter @kando/workers-api build:linux:api` | 退出 0，生成 Node API bundle 与 sourcemap |
| Cloudflare 兼容打包 | `pnpm --filter @kando/workers-api exec wrangler deploy --env prod --dry-run --outdir .wrangler/dev-linux-backend-check/prod`；对应 `--env dev --outdir .wrangler/dev-linux-backend-check/dev` | 两次均退出 0，保留原向量 Service Binding；仅打包预演，复用已有 Admin assets，未重新构建或发布 Admin |
| CI 检查入口 | Git Bash `--noprofile --norc -n deploy/linux/ci/watch-branch.sh`；解析 `.github/workflows/linux-test-deploy.yml` | 均通过；两个既有 Linux 检查入口现覆盖全部 `src/linux` 和 PostgreSQL 扫描路由测试 |
| 真实 CF 识别连通性 | 在 `apps/workers-api` 用 `node --experimental-strip-types --input-type=module -` 导入新增适配器，向量为 `[1, ...Array(511).fill(0)]`，经内部 URL 调用配置的现有 CF origin | 退出 0，HTTP 200、5 个 `product_id/confidence` 候选，约 1,242 ms；请求来自当前开发机，不代表 kd201 出站或真实图片识别已验收 |
| 文档与冻结边界 | 相对链接/残留引用检查、`git diff --check`；比较冻结目录、共享业务路由与 migrations | 通过；冻结产品输入、既有 API 路由与 migrations 保持原样，旧 OCR 名称仅保留历史记录、回滚说明或拒绝旧配置的测试 |

Code Review 自审通过：核对配置入口、唯一扫描调用方、URL 映射、超时覆盖正文、取消与重定向处理、PGlite 数据与额度断言及发布检查入口；没有发现阻断项，没有引入 D1 路径、数据库 schema 变更、旧 OCR 回退或自动重试。文档同步说明现有 dev 的整改目标、只读复用 CF 识别的授权边界和当前尚未部署的状态。

兼容与回滚：部署新代码前必须为服务器 `.env` 添加 `VECTOR_RECOGNITION_BASE_URL`，仅有旧 OCR 键会启动失败。新版本不读取旧键，过渡期可保留旧键供旧版本回滚，或备份并恢复对应版本配置；本次没有执行任何远程 migration（含 0012）。

未运行：Workers/Flutter 全仓测试、App/Admin 默认入口整改、移动端构建或真机扫描、kd201 部署/出站验证、真实购买与通知链路。前两类不属于本阶段后端适配的影响面或交付范围；设备和服务器验证分别需要客户端测试设备与 kd201 部署访问。没有 Git 提交/推送、服务器或 CF 发布、DNS/定时任务切换及业务库写入；不能把本阶段通过解释为原 CF dev 已退役或全部 dev 环境已迁移完成。
## 首次引导邮箱登录提示定时关闭（2026-09-16，已构建测试内部包 143）

用户确认场景为首次安装引导后的邮箱登录：`Welcome back` 应显示 1 秒后自动关闭，提示隐藏后再进入后续订阅流程。本轮基于含下节 Profile 登录订阅调整的 `1.0.2+142` 工作区，macOS / Flutter 3.44.5 / Dart 3.12.2；已保存的 142 IPA 不包含本节后续修改，新构建的 143 IPA 包含本节修改。

根因：`_showCenteredAuthSuccessToast` 原本没有关闭计时器；Onboarding 调用 `showAuthSheet` 未启用已存在的反馈完成等待，因此邮箱提示刚显示时引导已经完成并开始权益检查。先增加回归后、修改运行代码前，iOS/Android × 三种权益的六项测试均发现提示首帧时 `readCompleted()` 已为 true，提前完成引导；两项提前关闭/销毁对照通过（共 2 通过、6 失败，退出 1）。

修复：`Welcome back` 从首次构建起计时 1 秒，仅关闭自己的提示路由，手动关闭或组件销毁时取消计时；反馈 Future 等待提示路由实际移除。首次引导启用 `waitForSuccessFeedback`，之后才保存引导完成状态并进入既有 Gate。Free 进入订阅页，Premium/Unknown 进入 Home；Profile 复用提示自动关闭，后续仍保留下节现有权益检查和订阅来源规则。邮箱注册 `Welcome` 保留手动关闭方式，引导等待其关闭后继续。认证接口、会话持久化、三方授权、资产、扫描、购买与权益判定未改；未修改已有 Profile 源码、版本号或冻结 PRD，当前行为已同步到业务流程文档。

验证命令均在 `apps/flutter-app` 执行：

- `flutter test --no-pub test/widget/auth_profile_test.dart --name 'onboarding email welcome auto|email welcome timer' --reporter expanded`：修复前 2 通过/6 失败；修复后及最终复验 8/8，退出 0。断言提示首帧和 999ms 时引导未完成、权益检查未启动；1000ms 后提示消失再分流；提前手动关闭后计时器不误关订阅页，销毁页面无异常。
- `flutter test --no-pub test/widget/auth_profile_test.dart --name 'Profile .*login|Profile .*waits|Profile .*cancellation|onboarding .*login|onboarding .*cancellation|email registration keeps|onboarding email welcome auto|email welcome timer' --reporter expanded`：48/48，退出 0；含两入口三种登录、三种权益、等待/失败/取消、Profile 迟到结果保护、两入口注册及提示时序。
- `flutter test --no-pub --dart-define-from-file=config/test.json test/widget/auth_profile_test.dart test/auth_controller_test.dart test/auth_repository_test.dart test/auth_session_interceptor_test.dart test/oauth_authorizer_test.dart test/auth_storage_test.dart test/startup_subscription_gate_test.dart test/onboarding_gate_test.dart test/onboarding_repository_test.dart test/widget/onboarding_page_test.dart test/app_upgrade_resume_test.dart test/premium_top_entry_test.dart test/subscription_restore_ui_test.dart --reporter expanded`：250 通过、4 项既有 Golden 失败，退出 1，不能标记整组通过。四项差异仍为 1853px、117px、7816px、5080px；本轮实际渲染图片 SHA-256 与先前原代码对照结果逐项一致，没有更新 Golden 或放宽断言。
- `flutter analyze --no-pub`：初次发现新增测试 helper 缺少 if 花括号，补齐后无问题、退出 0；随后重跑上方 8 项定向用例通过。`dart format --output=none --set-exit-if-changed lib/features/auth/ui/auth_sheet.dart lib/features/onboarding/onboarding_page.dart test/widget/auth_profile_test.dart` 与 `git diff --check` 均退出 0。

Code Review 自审通过：复核两个反馈等待调用方、计时起点、提示路由移除时机、提前关闭及 dispose 的计时清理、账号状态先保存后显示提示、免费与未知权益分支、注册提示兼容性；无全局导航监听，无新增认证/订阅请求路径。原有提示文案和视觉保持不变。

签名构建：同日按用户要求执行 `./tool/release_ios.sh --env test --pgy --build-number 143`，退出 0；构建前上述 48 项定向回归再次全部通过，脚本静态分析通过，清理后构建 `1.0.2 (143)`。最终内部 IPA 的 `com.kando.kandoApp.beta`、测试 API/Firebase、Apple Development 签名及 App Attest `development` 解包检查通过，41 个 Mach-O UUID 均有匹配 dSYM。IPA 为 56,689,353 字节，SHA-256 为 `db7afd43a67f1f88c1a7e947d4aab68440a24f5f8f36dc79b6215a9627f637c3`；IPA 和 `dSYMs.zip` 保存至 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.2-143/`，回读 IPA 摘要一致，源码版本同步至 `1.0.2+143`。Dart/CocoaPods 锁文件及三个目标运行文件构建前后摘要一致。按保留规则现存 141、142、143，旧 140 已移入废纸篓，可恢复；归档另存至 `~/Library/Developer/Xcode/Archives/2026-09-16/Card AI Test 1.0.2 (143).xcarchive`。

未运行：iOS/Android 真机首次安装登录、真实邮箱/StoreKit/购买与 Restore（使用测试替身，客户端测试人员需用 143 新包补验）；Android 构建、全仓检查及前述扩展 Golden 整组复跑（本轮打包复验范围为 48 项定向回归、静态分析和 iOS 签名产物，4 项既有 Golden 差异仍未处理）。未上传、安装、推送或远程部署，保留工作区已有改动。

## Profile 登录后展示订阅页（2026-09-16，已构建测试内部包 142）

用户在测试内部包 `1.0.2 (141)` 的 Profile 使用 Apple 登录后没有看到订阅页。该包原规则仅在首次引导检查权益，Profile 成功出口只关闭认证弹层；用户随后明确确认新规则：首次引导与 Profile 的 Apple、Google、邮箱登录均需检查权益，Free 展示完整订阅页，Premium 不展示。本节替代下方 141 包历史记录中的 Profile 留页规则，Unknown 仍沿用不自动展示的策略。

实现仅涉及 Flutter 页面衔接：Profile 成功后调用既有 `refreshEntitlement(showFailure: false)`，使用返回状态而非直接读取登录前缓存；Free 推入 `source=profile`、`entry_source=login` 的既有完整订阅页，关闭回到原 Profile。以 15 秒超时约束等待，异常记录诊断并留页；返回时检查页面存活、入口路由与当前账号，避免用户离开页面或切换账号后追加订阅页。仅登录操作触发检查，不添加全局认证监听。首次引导保持既有 Gate。邮箱登录/注册成功提示增加可选的完成等待，Profile 在提示关闭后才进行后续检查，防止慢速权益返回将订阅页压到成功提示上方；首次引导默认行为保持不变。原生 OAuth、认证与订阅 Controller、可信权益判定、购买/Restore、API、模型、Schema 和依赖均未修改，兼容 iOS/Android。当前业务规则同步至 `01-flows/business-context.md`。

验证环境：macOS，Flutter 3.44.5 / Dart 3.12.2。以下命令在 `apps/flutter-app` 执行：

- 变更前 `flutter test --no-pub test/widget/auth_profile_test.dart --name 'Profile .* login checks|email registration keeps' --reporter expanded`：1 通过、10 失败，退出 1；9 个 Profile 登录权益组合没有触发新检查，Profile 邮箱注册未出现订阅页。实现后相同命令 11/11，退出 0。
- `flutter test --no-pub test/widget/auth_profile_test.dart --name 'Profile .*login|Profile .*waits|Profile .*cancellation|onboarding .*login|onboarding .*cancellation|email registration keeps' --reporter expanded`：40/40，退出 0。覆盖两个入口、三种登录、Free/Premium/Unknown、iOS/Android 延迟结果、邮箱成功提示关闭、超时/异常、离开页面、取消/失败及订阅关闭后留页。初次延迟测试发现邮箱提示层被新路由覆盖；补充可选反馈等待后原测试通过。平台测试最初手工覆盖 debug 变量导致 4 项测试清理错误，改用 Flutter 的 `TargetPlatformVariant` 后通过，未修改应用的平台逻辑。
- `flutter test --no-pub --dart-define-from-file=config/test.json test/widget/auth_profile_test.dart test/auth_controller_test.dart test/auth_repository_test.dart test/auth_session_interceptor_test.dart test/oauth_authorizer_test.dart test/auth_storage_test.dart test/startup_subscription_gate_test.dart test/onboarding_gate_test.dart test/onboarding_repository_test.dart test/widget/onboarding_page_test.dart test/app_upgrade_resume_test.dart test/premium_top_entry_test.dart test/subscription_restore_ui_test.dart --reporter expanded`：最终 242 通过、4 项既有 Golden 失败，退出 1，不能标记整组通过。四项视觉差异与构建 141 时一致：1853px、117px、7816px、5080px。首次扩展运行另有 4 个旧 OAuth 用例因新增权益调用缺少测试替身而留下 15 秒计时器；为这四项明确注入 Premium 返回值、保留原迁移和 Loading 断言后，定向 4/4 通过，完整命令复跑得到上述最终结果。
- `flutter analyze --no-pub`：无问题，退出 0；`dart format` 格式化目标文件，`git diff --check` 通过。

Code Review 自审通过：逐项检查两个 `showAuthSheet` 调用方、反馈 Future 在关闭/销毁路径的完成、Free 唯一触发条件、账号和路由迟到结果保护、重复点击防护、现有订阅关闭/购买/Restore 返回 Profile 的路由及首次引导行为；没有发现剩余代码阻断项。视觉组件及布局不变，未更新 Golden 或放宽断言。

签名构建：同日按用户要求执行 `./tool/release_ios.sh --env test --pgy --build-number 142`，退出 0；静态分析再次通过，清理后构建 `1.0.2 (142)`。最终内部 IPA 的 `com.kando.kandoApp.beta`、测试 API/Firebase、Apple Development 签名及 App Attest `development` 解包检查通过，41 个 Mach-O UUID 均有匹配 dSYM。IPA 和 `dSYMs.zip` 已由发布脚本保存，源码版本同步至 `1.0.2+142`；IPA SHA-256 为 `652f36d5442543b1804cb6c50c3aae94550433acb3458273abf6c6af1870aaee`。依赖锁文件未变化，构建前后两个目标运行文件摘要一致，包含本节修改；141 IPA 仍是旧行为。

未运行：新代码的 iOS/Android 真机登录、真实邮箱/StoreKit/购买与 Restore、新包上传分发及全 App/全仓测试。Widget 测试使用替身，客户端测试人员需使用 142 包验收真实服务；未改服务端或共享包，未进行远程部署。

## 登录后按入口流转修复（2026-09-16，141 包历史规则）

环境：macOS、Flutter 3.44.5 / Dart 3.12.2，App `1.0.2+140`。用户报告免费用户通过 Google、Apple、邮箱登录后直接进入 Home；预期按 v1.1 PRD §3.4 完成首次引导权益检查，Free 先展示订阅页，Profile 内登录按全局规则刷新当前页。

根因：认证弹层的 OAuth、邮箱成功出口均调用 `_goHomeAfterAuthSettles`，在下一帧无条件跳转 `/home`；此路由不含启动权益检查，从而绕过 `/` 中的 Onboarding / StartupSubscriptionGate。Profile 也复用同一出口，导致登录后离开当前页面。修改前先增加三种登录方式与权益状态的 15 项流程测试，执行下方定向命令，6 通过、9 失败（退出 1）：三项首次引导 Free 缺失 SubscriptionPage，六项 Profile 登录后的当前页被移除，与用户现象及代码路径一致。

修复仅调整 `auth_sheet.dart`：移除统一首页跳转及其 Home 预加载。认证成功仍保存会话并关闭登录页面，首次引导由既有 `_authenticate` 保存完成状态并进入原权益 Gate；Profile 通过原有 `authControllerProvider` 监听刷新。保留成功反馈、OAuth 等待遮罩、取消/失败、邮箱注册/找回密码和防重复提交行为。没有修改 AuthController、认证 Repository、原生 OAuth、Token/接口契约、资产迁移、扫描额度、购买/Restore、Premium 判定、Schema 或环境配置。当前流转同步到 `01-flows/business-context.md`；冻结 PRD 保持原样。

实际验证（命令在 `apps/flutter-app` 执行）：

| 检查 | 命令 | 结果 |
|---|---|---|
| 修复前失败证据 | `flutter test --no-pub test/widget/auth_profile_test.dart --name 'onboarding .* login follows\|Profile .* login stays' --reporter expanded` | 6 通过、9 失败，退出 1；上述直接跳 Home 行为稳定复现。 |
| 最终定向回归 | `flutter test --no-pub test/widget/auth_profile_test.dart --name 'onboarding .*login\|Profile .* login stays\|onboarding .*cancellation\|email registration keeps' --reporter expanded` | 22/22，退出 0。三种登录方式 × 三种引导权益、三种登录方式 × Free/Premium Profile、Google/Apple 取消及失败、等待权益时隐藏 Home、两个入口邮箱注册均通过；Free 关闭订阅页后进入 Home，Profile 保留同一页面实例并显示账号信息。 |
| 登录及关联影响面 | `flutter test --no-pub test/widget/auth_profile_test.dart test/auth_controller_test.dart test/auth_repository_test.dart test/auth_session_interceptor_test.dart test/oauth_authorizer_test.dart test/auth_storage_test.dart test/startup_subscription_gate_test.dart test/onboarding_gate_test.dart test/onboarding_repository_test.dart test/widget/onboarding_page_test.dart test/app_upgrade_resume_test.dart --reporter expanded` | 178 通过、4 个 Golden 失败，退出 1；认证、存储、刷新 Token、引导、Profile、启动订阅及 Home 升级检查行为用例通过，不能标记整组通过。 |
| Golden 原代码对照 | 临时将本次唯一运行代码文件恢复到 HEAD（`git diff --exit-code -- lib/features/auth/ui/auth_sheet.dart` 为 0），执行 `flutter test --no-pub test/widget/auth_profile_test.dart --name 'subscription success matches the Figma 300ms\|unsubscribed Profile banner matches\|v1.1 PRD subscription' --reporter expanded`，随后恢复本次修复并重跑最终 22 项回归 | 同样 4 项失败，退出 1；四份实际渲染图 SHA-256 与修复后完全相同，不由本次跳转修复引入。未更新 Golden、放宽断言或跳过测试。 |
| 静态分析 | `flutter analyze` | 无问题，退出 0。 |
| 格式/差异 | `dart format --output=none --set-exit-if-changed lib/features/auth/ui/auth_sheet.dart test/widget/auth_profile_test.dart`、`git diff --check` | 两文件无需格式变化，均退出 0。 |

四项既有视觉失败：Profile 升级 Banner 差异 1853px（3.48%）；订阅成功页 300ms 动画帧 117px（0.04%）；订阅底部弹层 7816px（2.37%）；订阅成功页静态基准 5080px（1.54%）。具体视觉根因不在本次范围内，保留待处理。

Code Review 自审通过：核对全部差异、两个调用入口及现有响应式刷新，确认没有新增全局导航监听或修改 `/home`，因此普通 Tab 切换、回前台、关闭订阅页不会额外触发订阅展示；邮箱成功反馈仍可关闭且不误关后续订阅页；注册仍传递原 anonymous ID；认证失败/取消不推进引导。修复前失败、修复后通过组成根因回归证据，原代码对照后已恢复最终实现并复验。

未运行：iOS/Android 真机三方登录、真实邮箱服务、真实 StoreKit 权益及购买/Restore（本轮使用测试替身，需客户端测试人员在新包补验两端登录与订阅流转）；移动端构建/签名、Flutter 全仓测试及服务端全仓检查（范围仅 Flutter 页面衔接，未改原生桥接、后端或共享包）。没有打包、推送或部署；本地测试不等于第三方平台和真机验收。
## Golden 基准与全量复验（2026-09-10）

用户要求修复 Golden 并全量复验。基线为 `dev@699ca48` 加本地文档更新，App `1.0.2+134`；环境为 Windows、Flutter `3.44.7` / Dart `3.12.2`、Node `22.20.0`、pnpm `11.9.0`。本次未修改 Flutter 业务代码、UI 设计、API 或数据库结构。

根因与修改：

- 三张扫描 Golden 仍记录提前扣减后的 `9 scans remaining`，而 `38c362c` 已把可见次数改为完整 Matched 展示后才扣减。Scanning、Recognizing 和 Revealing 阶段应保持 `10 scans remaining`；旧基准各有 676 个差异像素，均在 `(143,93)` 至 `(247,105)`。仅重新生成这三张对应基准，逐像素确认改动范围相同；取景框、遮罩和其他区域无差异。三个 Golden 用例补充业务原因明确的次数断言，保留原严格图片比较，不放宽容差。
- Review Golden 单独运行时，`KandoCardImage` 使用的 `assets/home/trend_placeholder.png` 尚未解码，导致 60,048 像素缺图；全文件运行会因之前用例预热缓存而通过。截图前通过 `tester.runAsync` 等待 `precacheImage` 完成并重新绘制，不修改 Review 基准，不用固定延时猜测加载完成。
- 首轮 Dart 全量另有三个页面测试遗留 Dio 的零时长 Timer：两项 Search 首帧用例和一项 Home 认证启动用例触发了订阅收入补发，从而创建真实 Singular Gateway 并预取配置。测试为该依赖注入返回空配置的既有 Gateway 构造参数，并登记 dispose；认证、页面和图片断言保持原样。归因初始化与收入行为仍由原专门测试覆盖。
- Linux 打包在 Windows 下因 `URL.pathname` 产生 `/D:/.../src/linux/server.ts` 而失败。`build-linux.mjs` 的入口和输出文件改用 Node `fileURLToPath`，同时保留 Linux 路径与 URL 转义处理；调用方、打包目标、数据库和运行适配器均不变。

先失败与同路径验证：初次筛选 5 个扫描 Golden 为 1 通过/4 失败，其中三项次数基准失败、一项 Review 缺图；增加 `APP_ENV=test` 后仍相同。先完成测试依赖修复、保留旧三张图片时，7 项定向用例为 4 通过/3 失败，失败仍严格指向旧次数基准；仅更新三张基准后同一组 7/7 通过。Linux `build:linux` 修改前明确报 `Could not resolve "/D:/.../src/linux/server.ts"`，修改后同一命令成功生成 Node API 与 Admin 产物。

验证结果（除 Flutter 定向命令外均在仓库根执行）：

| 检查 | 命令 | 结果 |
|---|---|---|
| 修复后最窄回归 | 在 `apps/flutter-app` 执行 `flutter test --no-pub --dart-define=APP_ENV=test test/widget/scan_page_test.dart test/widget/search_page_test.dart test/widget/home_page_test.dart --name '^Figma (scan scanning\|recognition\|scan reveal\|review) renders at the 390x844 baseline$\|^Search keeps static controls visible while catalog is pending$\|^Search renders backend card art\|^auth startup shows' --reporter expanded` | 7/7，退出 0；三项扫描基准、独立 Review 和三项页面依赖隔离均通过。 |
| Dart/Flutter 全量 | `dart run melos run test` | 修复前 App 1041 通过/6 失败、订阅包 9 通过；修复后 App 1047/1047、订阅包 9/9，退出 0。全部现有 Golden 随完整 App 测试通过。 |
| Dart/Flutter 分析 | `dart run melos run analyze` | App 与 subscription-core 均无问题，退出 0。 |
| Node 默认全量 | `pnpm -r --if-present test` | 首轮退出 1；Auth 34/34、Admin 21/21、Marketing 4/4 通过，Workers 620 通过/4 失败，详见下文。 |
| Workers 受 Git 跟踪的全部测试 | `pnpm --filter @kando/workers-api exec vitest run src scripts --maxWorkers=2` | 73 文件、621/621，退出 0；包含全部 `src` 与迁移脚本既有测试，未改超时、断言或测试内容。 |
| TypeScript 全仓类型检查 | `pnpm type-check --force` | 7 个任务全部成功、0 个缓存，退出 0。 |
| 依赖方向 | `pnpm lint` | 4 个共享包通过，退出 0。 |
| TypeScript 全仓构建 | `pnpm build --force` | 6 个任务全部成功、0 个缓存，含 Workers/Admin dev/prod dry-run，退出 0。 |
| Linux API/Admin 构建 | `pnpm --filter @kando/workers-api build:linux` | 路径修复后退出 0，生成 `dist/linux/server.mjs` 及对应 Admin。 |
| Marketing 打包 | `pnpm --filter @kando/marketing-web exec wrangler deploy --dry-run` | 读取 26 个 assets、dry-run 退出 0，无部署。 |
| 格式与脚本语法 | `dart format --output=none --set-exit-if-changed apps/flutter-app/test/widget/scan_page_test.dart apps/flutter-app/test/widget/search_page_test.dart apps/flutter-app/test/widget/home_page_test.dart`；`node --check apps/workers-api/scripts/build-linux.mjs` | 三个 Dart 文件无需格式变化，Node 语法检查退出 0。 |

默认 Workers 命令的失败必须保留：其一是旧 Miniflare/D1 基座的 Wishlist/Portfolio 并发用例返回 500，读取 Wishlist 响应时行已为空；另外三项来自 Git 忽略的 `.wrangler/diagnostics/installation-environment-20260909/installations-environment.test.ts`，复现共享库安装环境无法按来源过滤的问题。中间一次 `vitest run src` 为 606 通过/1 失败，扫描用例触发原 5 秒超时；最终限制两个 worker 的完整 `src scripts` 复验通过，不等于并发不稳定或安装环境业务缺口已修复。没有删除诊断文件、修改测试发现配置、放宽超时/断言或维护旧 D1 测试基座；后续由 API 维护者用 PostgreSQL 场景单独处理，默认命令首轮不能标为通过。

Code Review 自审通过：三张图片差异仅限已确认的次数文案；Review 等待真实图片解码且基准不变；三项页面测试只隔离无关归因 I/O，专门归因回归仍在全量中执行；`fileURLToPath` 同时处理入口和输出，未改变清理目标、打包选项或运行逻辑。首次失败、保留旧图时仍失败及最终严格比较通过组成回归证据；无新增业务行为、Schema 或远程配置变更，相关产品/API 文档影响为 N/A，Windows 构建方式已同步至 Linux 部署手册。

未运行：iOS 签名构建、IPA/dSYM 保存测试（Windows 无 Xcode/macOS `ditto`）；Android/iOS 真机及移动端打包（本次未改 Flutter 运行代码、未连接测试设备）；kd201 容器与真实扫描、Cloudflare dev/prod 和数据库实测（本次是本地修复与复验，无远程发布）。客户端测试人员负责后续新包真机验收，Linux 维护者负责运行 SHA、资源适配及扫描端到端；本地构建通过不代表 Linux 向量适配缺口已解决。

## 当前代码与交付边界

2026-09-10 文档核对基线为 `dev@699ca48`，Flutter `pubspec.yaml` 为 `1.0.2+134`。本节汇总已提交实现；下方原始测试和部署记录继续保留各自日期，不代表本轮重跑或新包已发布。

| 增量 | 当前实现 | 验证与交付边界 |
|---|---|---|
| Linux 测试环境（`19a6ac4`） | 共享 Hono 应用、Node 入口、独立 PostgreSQL/内存 KV/图片卷、Compose 与 dev 分支监听发布 | Linux 未提供 `VECTOR_RECOGNITION`；扫描不可用，旧 OCR 地址不能恢复。kd201 当前 release、SHA、ledger 和合入后自动发布结果未回读，见[Linux 手册](linux-test-auto-deployment.md)。 |
| Singular 同进程恢复（`c28e754`） | 仅缓存有效配置；ATT 顺序完成后按前台退避、resumed 和收入交付恢复初始化，成功后补发已有 pending | SDK API 调用不等于后台收件；原始回归记录见下文，同进程断网恢复的新包真机/后台验收仍待完成。 |
| 检测图片缩放（`1da3935`、`070f5b6`） | iOS/Android 检测输入使用确定性的半像素双线性缩放；iOS 保留 Core ML，Android 保留最小 ORT | 2026-09-11 用户确认 iOS 真机扫描成功；2026-09-14 合入本地 `dev` 后扫描回归、分析与 Android Debug 构建通过，Android 真机仍待验收，详见下文。 |
| Home 版本检查（`fc23c6f`、`075db55`） | 实际 Home 首帧激活；后续返回 Home/回前台静默复查，已确认强更继续全局拦截 | 2026-09-10 原回归为 54/54、test 配置 16/16，通过范围见下文；新包安装、商店往返和真机切页未验收。 |
| iOS 交付物（`deb1d3c`） | 校验 IPA/dSYM 后、安装或上传前按 Bundle ID 保存；测试 3 个版本、正式 7 个版本 | 保存规则按成功保存时间保留，新版本完整保存后才将最旧超额版本移入废纸篓；不清理 Xcode Archives。命令与产物说明见[Flutter README](../../../../apps/flutter-app/README.md#ipa-与符号文件保存)。 |
| 扫描取景框（`699ca48`） | 首帧预留底部统计行、结果列表和操作区，共用几何随视口/安全区等比缩放 | 2026-09-10 原尺寸回归 12/12；原完整 Scan Widget 的 3 个 Golden 失败已在本页 Golden 修复中收口，最新 App 全量 1047/1047 通过；真机仍待验收。 |

前一轮文档核对在 Windows 执行 `pnpm --filter @kando/workers-api type-check`，退出 0；该轮仅核对源码、配置和文档，未运行全量测试。后续 Golden 修复与全量复验结果见本页上方对应记录。iOS 保存脚本及其测试依赖 macOS `ditto`，截至本次仍未执行保存测试、签名构建或产物清理，也未连接 Cloudflare、kd201 或远程数据库执行发布。

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

## iOS 与 Android 检测图片缩放对齐（2026-09-10 修复，2026-09-14 合入本地 dev）

本轮基于 `origin/dev@b00e76e` 创建 `dev-xiangyang-new`。iOS 问题输入为 `227.PNG`：文件名虽为 PNG，内容实际是带 Display P3 ICC 的 JPEG，尺寸 1206×1515、EXIF Orientation 1，SHA-256 为 `12506B7158BBF0F1AAA5BCB8AACC67A24485AF1472D36D8C3CAEC2245E7716C0`。该图片在相邻 `real_time_recognition` 的 OpenCV 检测预处理中能识别卡牌，而旧 iOS UIKit 缩放会选中背景区域；请求在端侧失败时不会进入 Workers，因此管理平台没有对应扫描记录。

根因证据来自既有 GitHub Actions macOS run `34446393738`：固定 NCHW tensor 输入时 Core ML raw 输出与参考一致，Dart mask 几何也能从参考 mask 得到正确四角，但 UIKit 解码/缩放输入经过同一 Core ML 检测后稳定产生错误候选。受控对照中，sRGB 加 UIKit/Pillow 类双线性缩放使背景候选得分高于正确卡牌；同一 sRGB 图像改用 OpenCV `INTER_LINEAR` 后，正确卡牌成为最高分候选，得分约 0.535，mask bbox 约为 `(77,158)-(418,510)`。这把差异定位到检测前缩放采样，而不是模型格式、Core Image 透视裁正、Dart 四角拟合或向量检索。

修复仅替换最长边 640 的检测专用缩放：iOS 与 Android 都按半像素坐标映射、边界钳制和双线性插值输出 RGB，不重新引入 OpenCV。iOS 保留 `RTMDetInsTinyCardRawFP16.mlmodel`、Core ML raw 输出后处理和 Core Image；Android 保留 `onnxruntime-minimal-1.23.0.aar` 与现有 `.ort` 模型。裁正后的 384×384 embedding 图像预处理、PE-Core-T16 向量化、Flutter 页面、扫描状态机、API、`recognize-vec`、数据库及模型/运行时资源均未修改，因此本轮模型和推理库体积增量为 0；最终分支只增加少量生产缩放代码。

2026-09-11，用户使用云端 `dev-xiangyang-new@1da3935` 构建的苹果端包完成真机测试，并确认 Core ML 检测配合新缩放可以成功识别此前失败的输入。本结论验证 iOS 生产组合，不代表 Android 已验收。已验证回退点仍为 GitHub `dev-xiangyang@3d9f700`，其中 iOS 使用完整 ONNX/ORT 检测；当前分支无需改用该回退方案。

按用户为降低后续合入 `dev` 的差异范围所作的明确选择，本分支后续删除了专项 Android JVM 测试、iOS `227.PNG` RunnerTests、366,304 字节测试夹具、JUnit 测试依赖、Xcode 测试资源引用和 iOS CI 专项测试接线，并恢复仅为测试开放的 Swift 可见性。删除范围不包括既有 `dev` 测试，也不改变 iOS/Android 生产缩放代码；原根因证据和本次 iOS 真机结果保留在本文。由于专项自动化回归已移除，后续合并或修改该缩放实现时不能依赖仓库内用例自动发现采样行为回退。

本地静态验证在仓库根执行：`git diff --check` 退出 0；专项测试支持文件与 `origin/dev` 逐文件一致；最终分支差异不包含 `.github/workflows/ios-build.yml`、Android 测试依赖、RunnerTests、Xcode 测试资源或测试夹具。对 `origin/dev` 检查确认 iOS/Android 模型、最小 ORT AAR、Podfile/Podfile.lock、Flutter `lib`、Admin、Workers 和共享包无差异。首次残留引用检查因 `rg` 正则转义错误退出 2，改用逐项固定字符串检查后无残留、退出 0；该命令错误不记作产品验证通过。Windows 本机没有可用 Flutter/Android SDK/Xcode，因此删除测试后的 Android 构建、iOS 构建、Flutter 分析和 Android 真机测试未运行；iOS 真机成功结论来自用户实际验收。

Code Review 自审核对了解码后的方向尺寸、sRGB/RGB 与后续 BGR 通道转换、半像素坐标和边界钳制、源图/输出缓冲生命周期、检测与 embedding 预处理隔离、Core ML raw 输出后处理、Android 最小 ORT 保留，以及测试删除没有触及生产实现。生产差异限定为 iOS/Android 检测缩放。两端检测均会额外建立约 `source_width × source_height × 4` 字节的临时像素缓冲，常见 12MP 图片约 48 MB；Android 和超高分辨率图片的峰值内存、耗时及更多真实图片准确率尚未真机验证。文档影响已同步至[扫描识别](../01-flows/scan-recognition.md)；Schema、部署和运营操作影响为 N/A。

### 2026-09-14 合入 dev 的本地验证

用户授权将 `dev-xiangyang-new` 合入 `dev`，要求保持其他业务逻辑。刷新 `github` 后，合并前本地与远程 `dev` 均为 `b00e76e`，源分支为 `070f5b6`，提交关系为 `0/2`；扫描回归基线通过后执行 `git merge --ff-only github/dev-xiangyang-new`，本地 `dev` 快进至 `070f5b6`，无冲突。合入两个原提交，未改写生产修复；本轮未推送、部署、修改远程数据库或发布客户端。

范围核对：相对 `b00e76e`，仅 Android `MainActivity.kt`、新增 `OpenCvLinearRgbScaler.kt`、iOS `AppDelegate.swift` 和两份扫描文档有变化。完整文件列表检查与 `git diff --quiet` 均确认 Flutter `lib`、既有测试、模型/运行时资源、依赖与 CI、Admin、Workers、Marketing 和共享包无差异。原生文件逐段比较确认入口注册、生命周期、Android 解码辅助方法、两端卡牌裁正与 384×384 向量预处理以及 iOS 错误契约保持不变。

本轮环境为 Windows、Flutter 3.44.7 / Dart 3.12.2、JDK 21 与本地 Android SDK；与上方源分支阶段的工具可用性记录分开。以下 Flutter 命令均在 `apps/flutter-app` 执行：

- `flutter test --no-pub --dart-define=APP_ENV=test test/scan_native_image_processor_test.dart test/scan_card_recognizer_test.dart test/scan_card_number_reader_test.dart test/scan_mask_geometry_test.dart test/scan_api_client_test.dart test/scan_result_source_test.dart test/scan_review_repository_test.dart test/scan_quota_controller_test.dart test/widget/scan_page_test.dart --reporter expanded`：合并前、后均为 154/154，退出 0；覆盖检测/向量契约、OCR、四角几何、API、队列、额度、Review、保存和扫描页 Golden。原生通道使用测试替身，不代表模型真机识别通过。
- `flutter analyze --no-pub`：无问题，退出 0。
- `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`：退出 0，生成 `build/app/outputs/flutter-apk/app-debug.apk`。构建仍提示既有 Gradle 8.12、AGP 8.9.1、Kotlin 2.1.0 后续支持版本及 SDK XML 版本警告；未修改工具链或跳过依赖校验。
- 临时 Java 检查调用本次 Android 构建出的 `OpenCvLinearRgbScaler` Kotlin 类，复用 `1da3935` 原专项测试的参考像素、容差不超过 1 和原尺寸保持样例：2/2，编译与运行均退出 0。检查程序与日志仅保存在系统临时目录，未恢复仓库专项测试、测试依赖或 CI 接线；仓库内专项回归缺口仍然存在。
- 仓库根 `git diff --check b00e76e HEAD` 与文档补充后的 `git diff --check` 均通过；两份变更文档的本地相对链接目标存在。

Code Review 自审通过：复核半像素坐标、边界钳制、取整与 RGB 输出长度，确认新缩放只由检测入口调用；通道字段、阈值、模型、裁正与向量化隔离保持原契约。结合相同用例的合并前后结果，未发现本次合并对其他业务代码的额外修改或阻断项。

未运行：iOS 构建与签名验证（Windows 无 Xcode）、iOS/Android 真机原图识别及大图内存/耗时验证（本轮未使用测试手机）、全 App/全仓测试及远程 API/数据库实测（本轮按检测预处理和直接调用链验证，其余业务代码无差异）。iOS 2026-09-11 成功结论保留为既有用户验收，未在本轮重验；客户端测试人员仍需用合入后的新包完成两端设备复验。本地测试和 Android 构建不能替代这些验证。

### 2026-09-14 dev API/Admin 发布

用户随后授权提交、推送及部署 dev。发布源为本地与 `github/dev` 一致的 `42966a9bb766a58da1f0af8fba01d9301816f685`，包含扫描缩放合并与上方验收文档。部署前核对 Cloudflare 运行版本 `6a76360f-714f-4ec5-9819-f8c1c5031c5d` 的资源与仓库 dev 配置一致，并保留该版本作为本次发布前的回退点；本次未修改 Schema、执行 migration 或切换识别协议。

在仓库根执行 `pnpm --filter @kando/workers-api run deploy:dev --tag dev-42966a9 --message 'Deploy dev from 42966a9; scan resize merge verified'`，标准脚本重新构建 Auth Core 与 Admin development assets，随后发布 `toccards-api-dev`，退出 0。2026-09-14 14:54（北京时间）回读 deployment `77251695-34fd-4b48-b6e8-5bf69901f219`，version `ddeb0040-888b-4b33-bc50-c432c0a3793b`（number `358`、tag `dev-42966a9`）承载 100% dev 流量；发布输出确认 `api-dev.tcgcard.fun` 自定义域名与每 5 分钟 Cron 已同步。

发布后逐项比较 binding 类型、目标、变量值与 Secret 名称，均与发布前快照一致：`APP_ENVIRONMENT=development`、beta Apple Bundle 与 `cardx.*` SKU、dev KV/R2、既有共享 Hyperdrive 和 `VECTOR_RECOGNITION=recognize-vec` 保持原配置，没有 D1 binding。未改写 Secret，未修改 prod、Linux 或独立 Marketing 部署。

本次发布验证：

- `pnpm --filter @kando/workers-api exec vitest run src/index-postgres-runtime.test.ts src/app-config/routes.test.ts src/app-config/version-control.integration.test.ts src/scan/routes.test.ts src/scan/quota.integration.test.ts src/cors.test.ts src/admin/cors-preflight.test.ts --maxWorkers=2`：7 文件、62/62，退出 0。
- `pnpm --filter @kando/admin-web test`：21/21，跳过 0，退出 0；Workers 与 Admin 各自 `type-check` 均退出 0。
- `pnpm --filter @kando/workers-api run deploy:dry-run:dev`：Admin development 构建、Worker 打包与 dev bindings 检查通过，退出 0。
- 发布前后线上检查：`/api/v1/health` 为 200/`status=ok`；`/api/v1/games` 返回 10 个游戏；Pokemon Search 第 3 页、每页 40 条返回 200 与 40 条卡牌；iOS/Google `/api/v1/app-config` 均为 200 且 `Cache-Control: no-store`，版本规则与发布前一致。iOS 为推荐 `1.0.2`、最低 `1.0.0`、非强更；Google 升级提示关闭。
- Admin `/admin` 为 200，发布后本次回读的 HTML 与本地构建一致，引用的 10 个 JS/CSS 逐个返回 200 且 SHA-256 一致；未授权 `/api/v1/admin/scans` 与 `POST /api/v1/scan/recognize` 均保持 401。线上检查仅保存状态、版本规则和资源哈希，没有保存 `/app-config` 返回的 SDK 凭据。

首次发布前搜索烟测把游戏 ID 传给按游戏名称匹配的 `game` 参数，得到 200/空列表并因预期 40 条而退出 1；核对现有适配器后改用游戏名称，相同第 3 页检查在发布前后均通过，未修改产品代码。发布前 HTML 含 Cloudflare 注入的 beacon，原始 HTML 哈希不一致，但去除已确认的 beacon 并归一化标签间空白后与构建相同，10 个资源哈希原本就一致；没有将该页面转换差异记为应用故障。

本次仅发布 API/Admin。扫描缩放修复位于 iOS/Android App 原生代码，已安装的旧 App 不会因 Worker 发布而更新；仍需安装包含合并提交的新 App 包完成客户端验收。未执行已登录 Admin 操作、真实图片向量识别、购买/通知流程、全仓测试、iOS 签名构建或两端真机验证；线上基础检查不能替代这些业务验收。

## iOS 原始分类分数修复（2026-09-09，历史记录）

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

以下为 2026-09-09 历史回读。当时本地 `dev@b0b54df` 与 `github/dev` 一致，包含向量合并 `f38ef98`；四个已清理分支 `dev-wxy`、`dev-xiangyang`、`dev-update-dio`、`dev-scan-page-update-ui` 在本地及远程均不存在。旧分支名仅保留历史来源含义；该记录不证明当前 HEAD 或远程部署状态。

| 环境 | 该次回读的 100% 流量 Worker version | 数据与识别边界 |
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
