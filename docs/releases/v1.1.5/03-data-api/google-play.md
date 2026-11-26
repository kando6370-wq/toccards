# Android Google Play 订阅与对账

安装证明使用 Play Integrity 已核实的包名、签名、构建号和时间。首次游客会话写入 PostgreSQL，邮箱注册、登录和 Google 登录从当前安装的可信会话承接证明。已有会话可在 `POST /api/v1/entitlements/google/installation` 提交绑定当前会话的新证明。旧版请求仍使用原认证格式。Linux dev 的安装证明豁免仅用于认证，计费构建身份需要真实 Play 证明。

`0019_google_play_subscriptions.sql` 为业务环境和 Google package 创建独立的配置、存量资格、购买、订单、通知和审计存储。先在相应环境迁移，再发布调用这些表的服务。回退应用版本时保留表和已入账事实。`GOOGLE_PLAY_PACKAGE_NAME` 与 `APP_ENVIRONMENT` 共同确定 scope。批准存量截止时间和首个计费构建后，通过参数化的 `google_play_prepare_rollout(scope, cutoff, first_build)` 一次性快照该环境的 Android 空间。`metering_enabled` 控制新版额度，`sales_enabled` 控制新售，默认均关闭。新额度只统计预留时记录了本批次的免费扫描。测试交易要求空间已登记在对应 scope 的 `google_play_test_space`。

服务端使用独立的 `GOOGLE_PLAY_PUBLISHER_EMAIL` 和 `GOOGLE_PLAY_PUBLISHER_PRIVATE_KEY` 请求 Publisher API。`GOOGLE_PLAY_TOKEN_HASH_KEY` 使用 32 字节随机密钥的无填充 base64url，作为稳定索引密钥保存。`GOOGLE_PLAY_ENCRYPTION_KEYS` 以逗号分隔 `keyId:base64url`，首项用于写入，旧项用于回查历史密文。轮换加密密钥时保留旧项，索引密钥变更需先迁移历史映射。应用和后台均通过服务端访问商店。

## 环境与商店通知

Linux kd201 的 `development` 使用独立 PostgreSQL。Cloudflare 的 `production` 使用生产 PostgreSQL。各自在发布 API 前依次执行 `0019` 和 `0020`。前者提供计费、通知和账务表，后者为 Google 订单增加商店服务周期，并保存首笔扣款归因。两条迁移均保留已有的 Apple 订单和权益。Billing 制品、Play 发布轨道、业务环境、Google 标记的测试交易是不同维度。每个环境按实际安装包配置 package 和自己的密钥。

Pub/Sub 推送到 `POST /api/v1/google-play/notifications`。每个环境配置 `GOOGLE_PLAY_PUSH_AUDIENCE`、`GOOGLE_PLAY_PUSH_EMAIL`、`GOOGLE_PLAY_PUSH_SUBSCRIPTION` 和 `GOOGLE_PLAY_TOPIC`。服务端验证 Google 签名、受众、服务账号、订阅名和 package，以 topic 和消息 ID 去重。测试消息只验通道，退款审核消息单独隔离。订阅和作废通知均回查商店事实。作废回扫按页保存进度，完成时间窗后保留一天重叠范围。已绑定的过期 token 可以凭真实订单号补账。生产回查、测试下单和价格配置需使用对应环境的授权账号。

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
