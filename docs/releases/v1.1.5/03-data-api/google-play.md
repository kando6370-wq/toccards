# Android Google Play 订阅与对账

安装证明使用 Play Integrity 已核实的包名、签名、构建号和时间。首次游客会话写入 PostgreSQL，邮箱注册、登录和 Google 登录从当前安装的可信会话承接证明。已有会话可在 `POST /api/v1/entitlements/google/installation` 提交绑定当前会话的新证明。旧版请求仍使用原认证格式。Linux dev 的安装证明豁免仅用于认证，计费构建身份需要真实 Play 证明。

`0019_google_play_subscriptions.sql` 为业务环境和 Google package 创建独立的配置、存量资格、购买、订单、通知和审计存储。先在相应环境迁移，再发布调用这些表的服务。回退应用版本时保留表和已入账事实。`GOOGLE_PLAY_PACKAGE_NAME` 与 `APP_ENVIRONMENT` 共同确定 scope。批准存量截止时间和首个计费构建后，通过参数化的 `google_play_prepare_rollout(scope, cutoff, first_build)` 一次性快照该环境的 Android 空间。`metering_enabled` 控制新版额度，`sales_enabled` 控制新售，默认均关闭。新额度只统计预留时记录了本批次的免费扫描。测试交易要求空间已登记在对应 scope 的 `google_play_test_space`。

服务端使用独立的 `GOOGLE_PLAY_PUBLISHER_EMAIL` 和 `GOOGLE_PLAY_PUBLISHER_PRIVATE_KEY` 请求 Publisher API。`GOOGLE_PLAY_TOKEN_HASH_KEY` 使用 32 字节随机密钥的无填充 base64url，作为稳定索引密钥保存。`GOOGLE_PLAY_ENCRYPTION_KEYS` 以逗号分隔 `keyId:base64url`，首项用于写入，旧项用于回查历史密文。轮换加密密钥时保留旧项，索引密钥变更需先迁移历史映射。应用和后台均通过服务端访问商店。

## 环境与商店通知

Linux kd201 的 `development` 使用独立 PostgreSQL。Cloudflare 的 `production` 使用生产 PostgreSQL。各自在发布 API 前依次执行 `0019`、`0020` 和 `0021`。`0019` 提供计费、通知和账务表，`0020` 为 Google 订单增加商店服务周期和首笔扣款归因，`0021` 为 Google 通知增加可空的脱敏 JSON 字段。旧服务仍可写入收件箱，回退时保留该字段和已有快照。Billing 制品、Play 发布轨道、业务环境、Google 标记的测试交易是不同维度。每个环境按实际安装包配置 package 和自己的密钥。

Pub/Sub 推送到 `POST /api/v1/google-play/notifications`。每个环境配置 `GOOGLE_PLAY_PUSH_AUDIENCE`、`GOOGLE_PLAY_PUSH_EMAIL`、`GOOGLE_PLAY_PUSH_SUBSCRIPTION` 和 `GOOGLE_PLAY_TOPIC`。服务端验证 Google 签名、受众、服务账号、订阅名和 package，以 topic 和消息 ID 去重。测试消息只验通道，退款审核消息单独隔离。已支持的订阅事件和订阅商品的作废事件触发商店回查。作废回扫按页保存进度，完成时间窗后保留一天重叠范围。已绑定的过期 token 可以凭真实订单号补账。生产回查、测试下单和价格配置需使用对应环境的授权账号。

### 后台查询通知

在「数据统计 → Google Play 通知消息」按 Android UID、消息 ID、脱敏购买链、订单号、SKU、购买类型、主通知类型、子通知类型、处理状态和 UTC 接收日期查询。订单号可匹配通知自带的订单，也可匹配同一购买凭证经商店核实的关联订单。抽屉分别显示通知携带的订单号和该购买最近的订单号。业务环境和包名由当前 API 决定，筛选选项、分页、详情和重试均限定在该范围。

页面按类别解释类型值，覆盖 19 个订阅事件、2 个一次性商品事件、2 种退款类型、退款审核和通道测试。通知事件和处理结果分别展示。一次性商品通知和待审核退款只记录供排查，已核实的交易继续由原账务流程入账。通道测试独立于测试购买。历史作废消息和主动回扫若缺少退款类型，显示「未记录退款类型」。

运营可在详情查看并复制新收到的脱敏 JSON。购买与退款令牌、账号标识和推送认证信息均从快照排除。历史记录及主动回扫显示现有字段和快照缺失原因。只有超级管理员可说明原因后重新处理失败消息。

2026-11-26 本地核对了 25 条通知映射。Admin 99 项测试和服务端 4 个文件的 79 项专项测试通过，覆盖 Google 签名投递、幂等、脱敏、环境隔离、受控重试，以及 Apple 通知和订单汇总。dev 与 prod 的 Admin 构建通过。本机浏览器使用模拟通知验证了查询、重置、刷新和退款详情，真实 Play 推送仍待联调。

### Linux dev 后台配置与查询（2026-11-27）

kd201 上的管理员打开 Google Play 通知或订阅配置时，通知列表、筛选选项、商品和展示配置接口均返回 `503 GOOGLE_PLAY_NOT_CONFIGURED`。运行容器缺少 `GOOGLE_PLAY_PACKAGE_NAME`，独立数据库的迁移已到 `0021`。在 `shared/.env` 补入 Android 测试包名 `com.kando.kandoApp.beta` 后，仅用当前镜像重建 API，health 返回 200。Linux 配置样例已补入相同包名。该设置决定后台读取的环境和包名，新售和计费仍由对应开关控制。

功能分支提交 `a2af9ab1` 将 Google 配置写入和订单补账改为调用后台已有的 `createRequestId()`，支持内网 HTTP。本地登录回归覆盖通知、筛选选项、商品、配置和订单五个入口，空数据均返回 200，显式刷新商店目录仍要求 `GOOGLE_PLAY_PUBLISHER_EMAIL` 和 `GOOGLE_PLAY_PUBLISHER_PRIVATE_KEY`。测试包的真实通知投递还需要配置该环境的 Pub/Sub。Admin 100 项和服务端专项 88 项通过，代码复核确认请求权限、幂等字段和 Apple 业务路径沿用原实现。

管理员重新登录 kd201 后，Google 通知列表、筛选选项、商品、展示配置和订单五个接口均返回 HTTP 200。通知页显示开发环境和测试包名，列表为空。订阅页和弹窗均显示「未启用 · 版本 0」。订单统计默认显示正式购买，订单数为 0。iOS 订阅配置、苹果通知及原订单统计的读取接口也返回 200。

复验时远端 `dev` 为 `c337da8a`，尚未包含 `a2af9ab1`。kd201 实际加载的 `index-CPmA0NRy.js` 在保存 Google 配置和订单补账时仍直接调用 `crypto.randomUUID()`，内网 HTTP 页面没有此方法。这两项需在修复发布至 dev 后复验。本次仅查询后台，未保存或启用配置、补账或发起商店交易。

### 从 Play 刷新目录

打开配置页时，后台从当前环境的数据库读取已审批商品和展示配置。点击「从 Play 刷新目录」后，服务端才加载实时目录。审批商品和启用展示配置时，服务端会再次核对在售状态。2026-11-27 在 kd201 的 API 容器和持久配置中分别核对变量是否有值，确认测试包名为 `com.kando.kandoApp.beta`，Publisher 邮箱和私钥均缺失。截图中的 `GOOGLE_PLAY_UNAVAILABLE` 发生在请求 Google 之前。

1. 由管理员在服务账号所属 Google Cloud 项目启用 Google Play Developer API，并在 Play Console「用户和权限」中给该账号授予目标测试应用的目录访问权限。Google 按包名列出订阅。此前发布的 Internal 221 属于 `com.cardai.tcg`，kd201 查询的是 `com.kando.kandoApp.beta`。[内部测试包记录](../05-delivery/google-play-internal-221.md)
2. 通过私有配置渠道将同一服务账号 JSON 的 `client_email` 和 `private_key` 分别写入 kd201 的 `~/apps/toccards-test/shared/.env` 中的 `GOOGLE_PLAY_PUBLISHER_EMAIL` 和 `GOOGLE_PLAY_PUBLISHER_PRIVATE_KEY`。重建当前 release 的 API 容器，使新配置生效。
3. 重新进入 Google Play 订阅配置，点击刷新。成功时显示可向新订阅者销售的自动续订方案。返回空目录时核对测试包下基础方案的激活状态和可售地区。缺少凭据时接口返回 `503 GOOGLE_PLAY_PUBLISHER_NOT_CONFIGURED`。Google 拒绝访问时返回 `GOOGLE_PLAY_PUBLISHER_PERMISSION`。后台在商品目录卡片中保留原因供排查和重试。

本地验证通过 Admin 101 项、Workers 6 个相关文件 82 项、Linux 预检 8 项、Admin/API 类型检查及 dev/prod Admin 构建。首次运行 Workers 专项时额外命中了 `.wrangler` 中历史源码副本的 2 个失败用例。上述 82 项为按仓库正式测试范围排除该目录后的结果。Linux dev 发布包 dry-run 通过，包含 3 项 bundle 测试。真实后台构建配合模拟商店响应，在浏览器验证了首次打开只读已审批商品、刷新失败后重试、成功空目录、返回在售方案及再次失败后禁用旧选项。代码复核覆盖目录调用方和 iOS 订阅配置错误处理。kd201 实际页面的本轮浏览器会话已回到登录页。真实测试包的刷新仍待 Publisher 授权和注入后用管理员会话复验。

## 订单与收入

后台的 **Google Play 订单统计** 默认查看正式购买，查询和 XLSX 使用相同筛选。Apple 沿用原报表、统计和导出。Google 收入按完整订单号、扣款及成功退款的 UTC 发生时间核算。汇率快照支持换算，可核实的零金额显示为零，未核实的金额单列待对账。当前有效订阅在匹配到的订单中按购买链去重。一笔订单的多条退款明细只对应一份订阅。

Android 的 Firebase 收入使用 Play 与 Analytics 的自动集成。Flutter 的 Apple 手动收入通道继续只处理 App Store 交易。若选择 **Singular SDK** 作为 Google 首次付费的上报方，财务先核对该应用的现有自动导入，再在对应环境设置 `GOOGLE_PLAY_SINGULAR_SDK_FROM` 为 UTC 切换时间，例如 `2026-12-01T00:00:00Z`。默认关闭。时间只用于划分上报责任，实际启用日由运营确定。

只有 Google 已验证的正式订单、已处理且大于零的金额，以及能由商店服务周期确定的首次付费，才会生成回执。已核实的免费试用转付费也可生成一次回执，即使两个订单倒序到达。商品准入提供事件名，事件键包含业务环境、商店、包名和完整订单号。当前 Android 账号下的一个安装负责交给 Singular，回执确认中断后由同一安装重试，另一台设备恢复购买不会重新发送。SDK 本地接收和供应商后台入账分别验收。续费及退款记录以服务端账本为准。

## 客户端兼容与本地验证

设备平台决定登录方式、账号空间及商店。登录完成后，Android 按本次安装的服务器策略展示免费能力和购买入口。首次启动可以先建立游客会话。切换账号时立即撤下上一个账号的权益，购买前重新检查方案、资格和全部价格阶段。Android 删号弹窗提示在 Google Play 取消续订。iOS 继续使用 StoreKit 购买、恢复和到期刷新。

Android 订阅页和弹窗独立启停。个人中心、顶部 PRO 和扫描额度卡按 `page` 展示购买入口。扫描次数用完、文件夹达到上限、Performance 和长周期价格等受限操作使用 `modal`。App 在跳转前按当前账号重新读取对应位置的配置，只有新售开启且该位置已发布时才展示。配置停用或读取失败时留在原操作页面，额度继续生效。计费账号仍可在个人中心恢复购买和管理订阅。商店价格和优惠资格在付款前重新核实。

2026-11-26 使用仓库工具链完成本地验证。

| 验证 | 结果 |
| --- | --- |
| Flutter 3.47.9 / Dart 3.13.7 | 两个包静态分析通过。App 1,486 项、subscription-core 15 项测试通过。覆盖变价、优惠失效、待付款、恢复、换账号和收入回执重试。 |
| 旧版 iOS 源码合同 | 固定 `1.0.4+161` 和 `1.0.5+163` 各通过 24 项。 |
| 服务端、后台、官网 | Workers 118 个文件、974 项，Admin 97 项，官网 234 项。PostgreSQL 用例覆盖签名与重放、替换链、历史退款、并发写回、试用转付费与测试交易隔离。根依赖方向和 TypeScript 类型检查通过。 |
| 本地构建 | Android debug APK 的包名为 `com.kando.kandoApp.beta`，`aapt` 回读到 `com.android.vending.BILLING` 及 Billing Library `9.1.0`。Cloudflare prod 与 Linux dev 的发布包完成 dry-run。 |

### Android 订阅入口回归（2026-11-26）

修复前，个人中心只根据新售总开关展示订阅页入口，扫描达到上限时直接打开弹窗。用 Flutter 实际路由和页面测试四种启停组合，修复前三种失败，仅两者同时启用通过。修复后四种组合全部通过，两个位置停用时仍可由个人中心提交已购凭据并取得测试权益。测试同时覆盖运营临时停用、下拉刷新、直接链接、网络异常后重试和换账号。代码复核确认付款前仍重新核对商店报价与本位置商品，iOS 入口继续进入原 StoreKit 页面。

本轮 `flutter analyze` 通过，Flutter App 全量 1,493 项、共享订阅包 15 项通过。旧版兼容回归的当前 API 8 项通过，固定 iOS `1.0.4+161` 与 `1.0.5+163` 各通过 24 项。Flutter 页面测试使用模拟的 Play 目录和购买记录。

商店联调仍需具备商品管理权限的账号、已配置的测试商品及真机。验收范围包括一笔 Play 购买、服务端确认、RTDN、后台导出和归因平台回读，以及 iOS 实机购买与恢复。存量截止时间、首个计费构建号、价格、市场及真实交易开放时间由产品和运营确定。
