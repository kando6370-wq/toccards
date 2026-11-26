# Android Google Play 订阅与上架方案

**评审稿 · 2026-11-26 · 代码基线 `7badd485` · 范围为 Flutter App、共享 API、PostgreSQL、Admin 和商店交付。**

建议保留现有免费应用和包名，在 Android 新版内销售一个 Premium 权益，先做月付与年付。已在用的 Android 用户如何过渡，是本次产品决策的第一项。iOS 继续由 StoreKit 和 Apple 服务端决定权益。两端可以展示同名 Premium，同一登录身份在两端仍有各自的订单和数据空间。

两份 HTML 放在同一目录即可离线互跳，品牌图形与样式已内嵌。原型里的金额、用户、日期、商品和交易均为演示样本。[Android App 原型](../../../../prototypes/google-play-subscription/app.html) · [Admin 原型](../../../../prototypes/google-play-subscription/admin.html)

## 一、项目起点和容易改错的地方

| 现场证据 | 对本次设计的影响 |
|---|---|
| 用户确认免费版已上架。11 月 26 日读取美国区公开商品页得到 `CardScanFox: TCG Card Scanner`。方案基线 `pubspec.yaml` 为 `1.0.8+220`，11 月 24 日记录指明 `220` 属于 Internal。 | 沿用 `com.cardai.tcg` 做应用更新。实施前在 Console 回读各轨道最高 versionCode、公开国家和商品状态，按回读结果定新构建号。公开页面没有给出生产 versionCode。[公开页面][listing] · [发布档案][release] |
| Flutter 的 `AppCommercialPolicy` 同时控制免费能力、Apple 入口、登录和启动。后端 `usesAndroidFreeLaunch` 既放行 Android 扫描等能力，也用于拒绝 Android 调 Apple verify、Restore、lifecycle。 | 将“已认证平台”“本次免费策略”“支付渠道”分开。Apple 路由显式要求 `owner.platform == ios`，Google 路由要求 `android`。Android 进入付费策略后仍用现有 Android 登录、竖屏、扫描和返回流程。[E1](#e1) |
| iOS 采用 StoreKit 2、purchase challenge、Apple 签名交易、App Attest Restore、Apple 通知 V2、购买链和 session grant。App 同时有长期商品注册表、Page/Modal 和离线三卡兜底。 | 复用产品展示经验、顶部反馈、幂等和运营流程。Apple 区继续支持周、年、终身及已批准的动态商品。源码还注册了独立年试用，是否在售应按 Apple 目录确认。长期商品的恢复资格独立于是否在当前付费页展示。[E2](#e2) |
| 免费版基线的 Android Manifest 主动移除 `com.android.vending.BILLING`。`subscription-core` 的默认购买网关仅注册 StoreKit，App 的商品注册表请求固定为 `platform=ios`。`subscription_revenue_reporter` 仅接受 App Store 购买。 | 新增 Android 专属 Flutter 购买适配、商品读取、恢复与归因入口。把免费包的构建断言保留为历史制品验收，给首个计费包增加正向断言。仅添加 Gradle 依赖无法完成购买。[E1](#e1) |
| 公开 `subscription-supported-products?platform=google` 返回 `products: []`，`subscription-display-config?platform=google` 返回 `data: null`。Admin 目录加载器及准入是 Apple 专用。Apple scope 为 `APP_ENVIRONMENT:APPLE_IAP_BUNDLE_ID`，两端正式标识恰好同为 `com.cardai.tcg`。 | Google 采用带商店的独立命名空间。保留旧调用缺省 iOS 的合同和旧 `google` 占位响应，新版 Android 使用显式 Google 路由。没有可售配置时不产生扣款入口。[E3](#e3) |
| Admin 的「数据统计 → 订单统计」查询要求 Apple 准入范围和 `source_notification_uuid IS NOT NULL`，导出带 Apple 通知列。「苹果通知消息」直接查 Apple 表。`hasActivePremiumGrant` 按允许的 Apple 商品、环境和 session 授权。 | Apple 查询及统计口径保留。Google 订单单独取数、单独导出，避免合法续费订单因没有 Apple 通知而消失，也避免两端标识碰撞。新交易成熟前分别看两张报表。[E4](#e4) |
| PostgreSQL `0018` 和 `authenticateOwner` 将 session 绑定到平台和有效 owner。基础 user、同邮箱或 Google 登录可共享，但业务归属是本端数据空间。现有 Integrity 校验安装、证书及许可，只返回验证结果，未输出可信 versionCode。 | 用服务端认证后的 Android `data_space_id` 定归属。Play 商店账号、Google OAuth 身份和 App 平台账号是三件事。计费协议的可信构建识别和交易验证分别实施。[E5](#e5) |

## 二、谁可以使用什么

以下是**待评审的商业方案**，不表示已经启用。建议负责人在创建 Console 商品前书面确定截止时间 `T0`、时区和可售市场。

| 人群 | 扫描和资产 | 付费入口与恢复 |
|---|---|---|
| T0 前已存在且能由服务端确认的 Android 数据空间 | 建议保留该空间已有免费首版能力，升级后继续可用。历史收藏、文件夹、价格和扫描记录可读。 | 不向已经拥有相同能力的空间展示订阅。老游客按可核验的本端游客空间保留，在既有同端登录迁移中幂等承接资格。删号后重注或无法关联的重装游客按新空间处理，并提前说明。 |
| T0 后仍使用原免费制品的用户 | 保留该制品已发布的免费合同。进入新计费制品后按服务端确定的批次执行。 | 老包继续能识别、确认及收藏，无需理解新收费错误。首发建议保持旧包可用，后续停止支持须单独评审。 |
| 新版、新空间、未订阅 | 建议累计 10 次免费扫描，免费文件夹总数 2 个（含默认夹），可查基础 90 天历史。Portfolio / 单卡 Performance、扩展历史、继续建夹和超额扫描可触发订阅。已有资产照常读取、整理或删除。 | 在 Profile、已有 Premium 入口或受限动作展示 Page/Modal，可关闭继续免费使用。建议游客可体验免费功能，首次购买前登录或注册一个 Android 平台账号，避免丢单。 |
| 新版且 Google 权益有效 | 解锁无限扫描、更多文件夹、Performance 和扩展历史。扫描仍使用现有活动队列。 | Profile 可恢复、管理订阅、查看有效期与续订状态。到期仅对之后的受限动作执行免费策略，已有超额文件夹和卡片继续可访问。 |
| iOS 原有用户 | 现有 iOS 免费扫描、文件夹、历史范围和 Apple Premium 判断维持现行合同。 | 原 StoreKit 购买、试用、终身、Restore、启动门禁、动态配置与 Apple 账户管理全链回归。Android 购买或退款只改变 Android 权益。 |

**切换怎么落地。** 在 T0 前按当前 Android owner 生成可审计的资格快照，记录来源和时间。仅有 iOS 历史或基础 user 的注册时间不构成 Android 存量资格。按服务器签发的会话策略识别老包和新计费包。先在全量仍免费的阶段扩展现有 Android 安装证明处理，在原请求内从同一份已验 Google 响应读取 package、签名、versionCode 和请求绑定，按安装/session 记录可信制品能力。用真实免费制品验证原认证流程仍能取得已发布旧构建身份，同时读取新包的能力。切换前的旧会话按旧合同过渡至正常重验。新版启动或升级时重绑本安装会话，支持同一账号两台设备分别使用新旧制品。现有版本管理只配置最低/推荐营销版本，用于更新提示。计费能力基于受信的构建号另行判定。证明不足的会话保留最后已核实策略并申请重验。无法安全区分新旧制品时先保持该批次免费。客户端省略版本、修改 Header 或本地 Premium 标记均不能重置已核实策略或获得永久资格。同一空间并发登录使用同一条过渡资格。

**额度的历史陷阱。** 现有 Android 免费识别仍可写 `scan_quota_request.access_mode='free'`，但预留时有 `unlimited` 通道。若直接启用旧累计查询，用过免费版的人可能第一次就显示额度用尽。建议在预留时持久化本次 Android 计费策略与生效批次，只统计本空间、该策略生效后真正受限的 `reserved/consumed`。续用现有请求幂等、超时释放与成功消费，Premium、旧包与存量免费阶段不追扣。跨 T0 的一条扫描按预留时的策略完成。iOS 继续使用现行计数。[E1](#e1)

## 三、用户购买、恢复和订阅状态

**商品建议。** 一个自动续订商品（示例 `premium`）映射 `performance_pro`，下挂 `monthly`、`yearly` 两个基础方案。可选 `intro-7d` 作为月方案的合资格优惠，运营决定是否首发启用。周付、终身、预付、分期和 App 内主动换档留待另次产品决策。选定一个已生效计划后从 Profile 管理现有订阅，避免再买一份。发生 Play 侧替换或重新订阅时，服务端仍能处理新旧 Token。以下 `US$4.99/月`、`US$39.99/年`、7 天均为原型示例。正式金额、地区、续费周期与资格取自商店。[商品配置][console] · [基础方案和优惠][sub]

1. **进入付费页。** 服务端返回本端策略、已批准并启用的 Page 或 Modal。App 读取 Google `ProductDetails`，将 `(productId, basePlanId, offerId)` 与当前用户可购买的项目求交。展示本地货币、每期实扣金额、周期、自动续订、取消入口和适用的试用转正条款。点击前刷新选择，取该项的 `offerToken`。资格或价格有变时重新展示并让用户再次确认。目录/网络异常时提供重试和返回，避免用缓存报价启动付款。[接入说明][integrate] · [订阅展示政策][policy]
2. **购买。** 用户登录 Android 空间后，服务端给出不含邮箱或明文 UID 的稳定混淆账号标识（可采用带服务器密钥的 HMAC，最长 64 字符）。带入 Billing 流程并呼出 Google Play 系统确认页。用户取消返回原页面。`PENDING` 显示“等待付款”，`PURCHASED` 把 token 交给服务端验单。App 杀进程或支付后网络中断，重新进入前台查询现有购买并补交，显示“同步中”，避免重复扣款。[购买集成][integrate]
3. **验单与确认。** 服务端按配置里的 package 调 `purchases.subscriptionsv2.get`，核对准入方案、行项、支付状态、到期、测试属性及 `obfuscatedExternalAccountId` 与当前 Android owner。事务中幂等绑定购买链、发放本端权益、写确认待办。提交后仅由服务端调用 `purchases.subscriptions.acknowledge` 确认需确认的新购买，读取 `acknowledgementState` 处理超时重试。普通续费复用已确认购买。自动续订首次购买的三天期限从成功购买起算。测试交易窗口更短。App 不再抢先确认 Android 交易，iOS 的 `completePurchase` 流程照常。正式扣款金额走独立订单查询，取价失败不阻断已验证权益与确认。[订阅生命周期][life] · [购买资源][v2]
4. **恢复与归属。** Profile 提供“恢复购买”和“在 Google Play 管理”。登录同一 Android 账号、使用原 Play 账号，在重装/新机上查询当前持有的订阅，服务端重新验证。已有链只发给已绑 owner。无匹配结果提示检查两边账号。已绑定其他空间时阻断转移并提供支持。外部重新订阅、RTDN 先到或缺少混淆账号时，优先核对经 Google 返回的关联证据和既有绑定。端外到期后重新订阅应在确认前读取 `outOfAppPurchaseContext.expiredPurchaseToken` 和 `expiredExternalAccountIdentifiers`。临时缺证进入待认领队列并在确认时限前告警。若服务端最终判定本笔新购买无法履约，经核实确属该包和本笔交易后，按 Google 的拒绝履约规则立即全额退款并撤销，记录结果。第一个实现版本可将此动作交由具权限运营人员在 Play Console 处理，并由服务端重新查询、留痕。单个客户端提交他人 token 的冲突只能拒绝该客户端请求，原持有人已交付的购买继续有效。切换账号清空本地权益和购买队列的展示上下文。删号不能代用户取消商店续订，删除流程先给管理入口（对应 package 和 subscriptionId 的 Play 订阅管理深链，必要时回到订阅中心），允许继续删号，禁止旧 token 自动授权给新一代账号。[账号标识与生命周期][v2] · [管理订阅][sub]

| 商店事实 | Android 访问 | App 和后台分别显示什么 |
|---|---|---|
| 尚待付款 / 待付款交易取消 | 暂不发权，原有已核实权益按原链独立判断 | 显示等待或取消。Admin 不计成功扣款。关联替换中的旧 token 仍需单独回查。 |
| `ACTIVE`，有效行项未到期 | 开通至已核实期限 | 区分试用、首购、试用转付费及续费。试用阶段与真实金额分别记录。 |
| `IN_GRACE_PERIOD` / `ON_HOLD` | 宽限期继续服务。进入保留期暂停受限能力 | 显示修复付款方式和管理入口。支付恢复后按重新查询的有效期恢复。 |
| `CANCELED` 且有效期尚未结束 | 继续服务到期，展示准确日期 | 关闭自动续订本身不产生退款，后台分别展示到期日、自动续订及订单金额。 |
| 将来暂停 / `PAUSED` / `EXPIRED` | 已安排暂停在生效前按现行有效期服务。实际暂停或到期后回到免费层 | 已有资产可访问。重新激活或复订后重验链，再开通。 |
| 退款、拒付、撤销、换档 | 资金变动按具体订单登记。实际撤权以回查到的当前链和行项为准 | 单期退款、部分退款和订阅撤销分别记录。旧期或部分退款不应误关一个仍有效的新周期。`linkedPurchaseToken` 校验同一归属后结转替换关系，按生效时间停旧 grant。 |
| 上游不可用、字段未知、同步滞后 | 保留最后可信权益至已核实有效期，过期未能验证先显示待同步 | 前端给返回/重试/管理入口。通知入待处理并告警，不制造新收入或无限展期。 |

## 四、服务端、数据与消息

新路由名称为设计建议。所有 App 路由以 `/api/v1` 为前缀。iOS 原有路径、默认 `platform=ios`、状态枚举、缓存键、生产和 Sandbox 处理保持原契约。[兼容规则][compat]

| 建议接口或数据边界 | 输入、输出和归属 |
|---|---|
| `GET /google-play/catalog?placement=page\|modal` | 返回本环境的配置版本、展示候选和长期支持标识。客户端将商店返回值作为最终可购买集合。目录故障、未配置、策略不适用于本用户分别表达。下架展示与历史恢复独立。 |
| `GET /entitlements/google/play` | 认证 Android 会话返回 `access_policy`、可购买标志、当前权益、到期、续订和同步状态。已登录且可购买时给混淆账号标识。业务能力在服务端按相同可信 owner 和策略检查。 |
| `POST /entitlements/google/verify` | Android 会话、`Idempotency-Key`、购买 token。购买与恢复共用验证管线。返回已开通、待付款、待同步或归属冲突。相同请求重放给原结果，异 payload、跨账号、iOS session、错包与未准入方案明确拒绝。客户端提交的金额/UID 不入账。 |
| `POST /google-play/notifications` | Pub/Sub 包装消息，使用推送身份的 OIDC JWT，校验 Google 签名、颁发方、audience、有效期、配置的服务账号 email 与 `email_verified`，并核对 push subscription 和 package。数据入库才给成功响应。有效重复返回成功，临时写库失败可重投，未知业务类型持久化隔离以便排查。[推送身份][oidc] |
| Admin | 新增 `/admin/google-play/orders` 及 `options/export`，`/admin/google-play/notifications`（列表、脱敏详情、受控重试），`/admin/google-play/products`（读目录、审批）及 `/admin/google-play/configs`（草稿、保存、启停）。历史 Apple `/admin/billing/transactions`、`/admin/apple-notifications` 和订阅配置继续走原路径。 |

**PostgreSQL 增量建议。** 可共用现有 owner 鉴权、金额转换函数、Admin 分页与 XLSX 输出。新增 Google 专用关系，避免硬塞 Apple 专属字段或改写旧表。建表、索引和回退 SQL 在实施阶段评审。尽量用数据库唯一约束与事务实现以下契约。

| 记录 | 唯一范围和关键字段 | 用途 |
|---|---|---|
| Google 准入、展示配置、启用指针和操作审计 | `业务环境 + google_play + package + productId + basePlanId + offerId/无优惠`。每个独立 scope 的 `page`、`modal` 各最多一个生效版本。无优惠显式规范化以防 NULL 穿透唯一约束。 | 价格、国家与活动状态来自 Play 目录。存营销文案、权益映射、归因事件、revision、操作者和 request_id。历史映射下线展示后保留。 |
| 平台过渡资格、购买链与本端权益 | 存量资格按 Android 空间唯一。购买 token 的 keyed digest 在本环境/package 唯一，密文仅供服务端回查，关联稳定链 ID、前序 token、本端 owner、`testPurchase`、确认和行项状态 | 客户端、RTDN 和对账复用同一条处理管线。并发绑定由事务唯一约束裁定，多个有效 grant 取并集，绑定冲突不转移。密钥轮换须保留可检索性。 |
| Google 订单/退款事实 | `(业务环境, package, test/live, 完整 orderId)` 表示一次商店订单。一次 token 可有多笔续费，不能按 token 去重金额。保留交易币、整数金额、汇率快照、来源和发生时间。 | 分开保存订单原始扣款和成功退款明细。每次读取完整历史时在事务里替换该订单的退款快照或差额入账，重放不能再次加钱或退款。 |
| RTDN 收件箱与待办 | 按 `(topic, messageId)` 去重投递，记录事件类型、时间、关联链、尝试次数、错误分类、下次重试和最终结果。 | 已持久接收、验单、发权与商店 acknowledge 各有独立状态，管理员可看哪一步未完成。日志、详情、XLSX 均使用脱敏摘要，数据库密文按最短必要期限保存。 |

**消息与漏单处理。** Play 发布到 Cloud Pub/Sub，后端持久接收后应答。订阅通知触发回查 `subscriptionsv2.get`，作废通知带来的订单线索触发订单/权益分别回查。`testNotification` 只验通道，未知或退款审核类消息进入相应队列，退款申请不能直接变成成功退款。同一 token 串行或带版本条件写回。较早事件也取当前商店状态，禁止慢请求回写覆盖已确认的新状态。对 429、超时、5xx 退避，加上限和运营告警，权限/错包类错误单独处理。Google 定时任务独立捕获失败并设置执行预算，避免影响现有 Apple inbox 定时处理。[RTDN 事件][rtdn] · [现有 API 调度][scheduler]

**补账。** 定时回扫待确认、临近到期、失败与活跃链。订阅到期后，Google 提供最长 60 天的 token 查询窗口。到期前后及时保存必要订单事实，超出窗口后按已存订单号和财务报告核查。用 `lineItems[].latestSuccessfulOrderId` 找到当前行项最近成功订单，按完整 ID 调 `orders.get`。扣款归日取 `orderHistory.processedEvent.eventTime`，全额或部分退款分别核对 `refundEvent`、成功的 `partialRefundEvents[]` 及其 `refundDetails.total`。先部分后全退时按实际退款余额核对，累计退款上限为该订单实付。多期续费的空档从 Play 销售报告补齐缺失的 orderId，再逐笔回查。作废购买用 `purchases.voidedpurchases.list(type=1)` 分页、带重叠水位回查可查询窗口（最多近 30 天），更早以订单和财务报告复核。每日做已知交易差异清单，每月与财务结算报告核对手续费、税、退款、币种和到账期，差额保留原因与处理人。[订单][orders] · [订阅行项][v2] · [作废购买][void] · [官方财务报告][reports] · [订阅生命周期][life]

**环境与密钥。** 业务环境 `development / production`，Play 事实 `test / live`，发布轨道 `internal / closed / production` 是三个维度。`testPurchase` 由 Google 验单确定。尚未回查标作未知，只读收件箱可查，不能进入正式收入。即使同一正式包的 Internal 测试调用 prod API，也只能向获准测试账号发测试权益并独立报表。真实非许可测试员在测试轨道也有可能被扣款。kd201 是独立 PostgreSQL 的 Linux dev，若测试 package 在 Play 没有登记，那里只跑合同/模拟，并在正式 package 的 Internal 完成 Play 签名实测。为正式包配置一个明确的 Pub/Sub 入口，不把所有 prod 通知转发到 dev。Publisher API 服务账号与现有 Integrity、Apple 密钥隔离。密钥仅放 Worker Secret 或 Linux 私有环境。[测试说明][testing] · [E5](#e5)

## 五、Admin 怎样运营、查单和看数

沿用 TCG Admin 的菜单、筛选、分页和抽屉交互。订单统计与订阅配置各增加「Google Play」入口，现有入口默认展示 iOS。「Google Play 通知」放在「数据统计」下，与「苹果通知消息」并列。进入 Google 视图固定显示环境、package、测试/正式标签及数据时间。两个生产 Admin 域名都要验证。[E4](#e4)

| 操作人 / 页面 | 日常工作 | 约束 |
|---|---|---|
| 运营管理员 `operator`，订单统计 | 按本端 UID、完整 GPA 订单号、国家、基础方案、扣款/退款类型、当前权益、测试属性和 UTC 区间查询。查看详情的来源、商店订单、退款时间、汇率及关联消息。导出同一筛选。 | 不显示原始购买 token、JWT、用户邮箱或凭据。金额未知显示「待对账」。查询/汇总/导出共用同一过滤器，建议沿用现有 10,000 行导出上限。 |
| 运营管理员，Google Play 通知 | 按 `messageId`、事件类型、处理状态、订单或脱敏链标识查找。抽屉并排显示接收时间、商店事件时间、最近回查状态、确认结果、尝试次数和下次处理时间。 | `testNotification` 只做连通性检查。OIDC 异常进入接收告警，不能写成可重放的有效业务消息。运营可读脱敏结果。 |
| 运营管理员，订阅配置 | 从 Google API 读取目录，选已批准的 product / base plan / offer，编辑 Page 或 Modal 的顺序、默认项和文案。保存草稿、预览、启停。该权限沿用现有 iOS 配置的运营边界。 | 从 `monetization.subscriptions`、`basePlans.offers` 核对可用区域与计划状态。过期目录禁止启用。运行时以 Play 用户可购条件为准。隐藏的计划仍可续费、退款与恢复。 |
| 超级管理员 `super_admin` | 拥有上述能力，负责准入/重新审批商品、绑定 `performance_pro` 与收入事件、重试单条异常消息。 | 后端也校验角色、scope、`expected_revision` 与幂等 request_id，保存操作者、变更前后和原因。重复点击不新增订单。并发配置冲突要求刷新。Admin 不代用户退款、发权、改 Google 价格或更改 Apple 商品。 |

**订单与金额口径。** Google 页默认显示正式购买。`testPurchase`、未知来源和通知探针各自隔离。一个付费周期的完整 GPA 号是一笔订单。同笔可能同时有原扣款和一至多次退款。用 `orders.get` 的处理历史、`total`、`tax` 和成功退款明细作事实。当前基础方案的标价、RTDN 次数、试用转正提醒、`recurringPrice` 都不能充当实际扣款。`Money.units/nanos` 在后端以整数/十进制落实精度，保留原金额和税。若采用现有 micros 和 USD 换算，统一舍入一次并记录 `rate/base/quote/source/effective_at`。重复同步复用同一快照。退款抵减优先采用原扣款汇率并标版本，财务结算汇差另列。[订单资源][orders] · [现有换算][fx]

| 指标 | Google 筛选后的口径 |
|---|---|
| 成功扣款、退款、净额 | UTC 半开区间 `[from,to)` 内按实际扣款事件和成功退款事件分别归日。毛扣款包含之后被退款的成功扣款。退款列显示绝对值。净额 = 毛扣款 − 退款。退款日可没有当日扣款。这里反映买家支付金额，开发者实收另看结算报告。 |
| 缺价、跨币种 | 原币只在同币种内相加。USD 卡片仅累计有快照的事件，并列出缺扣款/缺退款笔数。若没有任何可算值则显示 `—`。明确的零金额才能写 `0`。 |
| 订单数、订阅数 | 期内有资金事实或已知零价订单的完整 orderId 去重，跨期退款可使该订单再次出现在相应区间。未产生有效订单号的 Pending 不凑数。有效订阅数按时点的有效购买链去重。发布运营可分别统计试用、首购、续费、恢复支付。 |
| 归因系统 | Firebase/Singular 的 Android 收入事件需与已有自动采集对齐，明确唯一上报方。建议首购以已验证、正式、已知实际扣款为门槛，事件键带 store/package/orderId。服务端负责续费和退款事实。Restore、补发通知、免费使用不重复上报。原 `logVerifiedApplePurchase`、历史映射和值域继续按 iOS 回归。 |

**示例对账。** 同一 UTC 区间内，订单 A 扣 US$4.99，订单 B 扣 US$39.99 并退 US$10.00，则毛扣款 US$44.98、成功退款 US$10.00、净额 US$34.98。若另有已知原币但缺 USD 快照的一单，保留上述已知小计并标注 1 笔待对账。若 A 的退款发生在下一个区间，它只进入下一区间的退款和净额。这套 Google 口径单独展示。Apple 原汇总有自己的 `refunded` 分类和日期定义，首版不合算两张总额。原型可逐笔查看这一示例。

## 六、Google Play 更新与发布顺序

| 顺序 / 责任 | 执行动作 | 留给评审和放量的证据 |
|---|---|---|
| 1 · 产品、运营 | 回读生产包名、各轨道 versionCode、可售国家、付款资料、商店文案。确定存量过渡日、免费能力、价格、本地化、试用资格、宽限/保留期与目标地区。用现有应用更新。 | 产品签字的权益表和地区价表。商店声明、Data safety、Terms/Privacy 与账号删除页要覆盖 Android 续订、管理和取消。现有共享 API 法律页和正式官网仍有“Android 免费”内容及 Apple 专属删号提示，应同步校对。[E6](#e6) |
| 2 · Android / Play 发布 | 在原应用 `com.cardai.tcg` 的发布记录中查找含 Google Play Billing Library 的版本。已有符合条件的已发布版本即可进入第 3 步。首次启用结算时，Android 构建须接入该库，并在合并 Manifest 中保留 `com.android.vending.BILLING`。用正式包名和新的 versionCode 构建签名 AAB，上传并发布到内部测试轨道（Internal testing）。 | 在 Play Console 核对包名、已发布轨道和 versionCode，并确认「创建订阅」入口可用。此时 App 的购买入口可继续关闭。[启用 Play 结算][ready] |
| 3 · Play 运营 | 在原应用的「借助 Play 变现 → 商品 → 订阅」创建订阅商品，添加自动续订基础方案，设置地区和价格，按需要添加优惠，再激活要销售的方案。 | 确认实际 productId、basePlanId、可选 offerId、本地化权益描述和生效地区，采用实际目录做 Admin 审批和 App 读取测试。[商品步骤][console] |
| 与第 3 步并行 · Play/Cloud 管理员 | 开启 Google Play Android Developer API。限制专用服务身份至对应应用，按官方 Billing 调用授予财务/订单查看和订单订阅管理等所需权限。Cloud 创建 topic，为 `google-play-developer-notifications@system.gserviceaccount.com` 授予该 topic 的 Publisher。建立独立带身份的 HTTPS push subscription，正确授权 Pub/Sub 服务代理生成推送令牌。在 Console 收款设置填全名 topic，发送测试消息。 | 目录只读调用、认证回推、持久入库、测试通知的 messageId 回读。以脱敏证据交付。Integrity 已可用不能替代对这些权限的验证。[接入准备][ready] · [服务账号][api-setup] · [推送认证][oidc] |
| 4 · 后端和 Admin | Linux dev 验证 PG 增量、定时任务、配置审计和回退。prod 建备份并验证可恢复性，先增量建表，再发双端兼容 API、两个生产 Admin 入口。Android 销售开关默认关闭。 | 回读 Worker 绑定、Apple 原配置/定时任务、迁移 ledger，检查 `api.tcgcard.fun` 和 `admin.tcgcard.fun` 的 HTML/资源以及真实登录后的 Apple 和 Google 菜单。缺少 Google 凭据时，Apple 的启动、订单和通知仍独立可用。 |
| 5 · 移动端 / QA | 用 `release_android.py` 的正式配置构建或复用包含完整购买与恢复流程的候选 AAB。2026-11-26 对新提交的更新，PBL 最低为 8，7 的延期已于 11 月 1 日结束。Flutter 官方 Android 插件已有 PBL 9 系列接入记录，可优先验证与项目 Flutter 3.47.9、Dart 3.13.7、现有 StoreKit 锁和 Android API 24 的相容性。按最终解析的依赖选择版本。 | 核对 Gradle `dependencyInsight` 和合并 Manifest 的 Billing 权限、`com.google.android.play.billingclient.version`、Play 认可的 SDK。记录 versionCode、AAB 哈希、上传/分发签名、生产 API、R8、16 KB 对齐、竖屏及 OCR。iOS 在 macOS 独立编译及运行回归。[PBL 期限][pbl] · [Flutter 插件变更][flutter-plugin] |
| 6 · Play Internal → Closed（如需扩大覆盖） | 从 Play 安装包。使用许可测试账号覆盖快速续费、延迟付款成功/失败、试用资格、取消、宽限、保留、恢复路径、退款与重装。用 Billing Lab 和 Play 测试工具控制状态。给审核人员准备可登录的测试账号、菜单路径和测试说明。 | 至少贯通一笔测试购买，从系统收银台、token 验证、ack、RTDN、Admin 到权益，逐项记录脱敏关联 ID。同时用不具备试用资格的账号复测价格、用旧免费安装和真实 iOS 包执行下表。同 package 的测试购买在正式收入里为零。[许可测试][testing] |
| 7 · 生产灰度 | 用 Console 审核后分阶段发布 AAB，销售开关按服务器获准人群启用。建议按 5% → 25% → 100% 评审。具体节奏由流量与留样决定。 | 首批核对一笔经授权的真实 Play 交易及后台对账，监控验单错误、ack 临期、最老积压、退款差异、跨平台拒绝、旧包错误、Apple 购买/Restore/通知成功率。发现串端、重复扣账、Apple 回归或已付款无法取权即暂停扩量。保留每次实际版本、地区、采样时间、负责人。[分阶段发布][rollout] |
| 8 · 回退与售后 | 暂停 Play 分阶段发布，关闭 Android 新售/新优惠。已下载的客户端继续可用。服务端保留 Google 验单、ack、RTDN、恢复、退款与有效期查询，保留 PG 数据、存量免费资格和 Apple 路由。必要时发布更高 versionCode 的修复包。 | 分别演练“配置撤销”和“客户端已更新”的情形。停卖后已付款用户能恢复，续费/退款仍能对账。后台停用 Page/Modal 只影响展示。若要停止后续续费，应另行执行明确的商店商品/订阅决策。 |

2026-11-26 已完成内部配置包发布。订阅配置入口及当前操作账号的权限状态见[内部测试 221 发布记录](../05-delivery/google-play-internal-221.md)。

## 七、iOS 放量条件和双端验收

实施时在同一候选后端上执行“改动前样本 → 关 Google 开关 → 测试开启 → 模拟 Google 故障 → 回退”的比较。对同一登录身份建立两套平台空间，并设 iOS 免费、iOS 已购、Android 存量、Android 新免费、Android 已购和测试订单等样本。审核证据用脱敏 ID、具体构建、环境、时间和预期结果关联。

| 负责人 / 必测链路 | 观察结果和证据 |
|---|---|
| iOS QA · 购买与恢复 | 实机 StoreKit Sandbox/TestFlight 验证原周/年、终身、已批准动态商品（含试用资格）、购买取消、断网补验/队列、App Attest 恢复和换机。核对 `performance_pro`、原 Page/Modal、无远端配置的原三卡兜底以及归因恰好一次。原包从未见过的 SKU 按该包本来支持的范围验收。 |
| 后端 / 运营 · Apple 通知与订单 | 在测试环境走 Apple 签名通知、重复、乱序、续费、关闭续订、退款/撤销、恢复同步。对同一组 Apple 稳定样本记录列表/全筛选合计/导出、通知详情和 grant。增删一笔 Google 同值 SKU/同名 package 的订单，Apple 结果逐项一致。生产留只读观测，涉及真实扣款/退款需授权。 |
| 双端 QA · 资产、额度和方向 | iOS 游客/注册、登录退出、收藏、默认及新增文件夹、Performance、历史价格、累计扫描第 10/11 次、成功/失败释放和原横竖屏策略。Android 仍正向竖屏，切出 Scan 不旋转。旧包超 10 次仍可按原合同使用。存量资格不收回，新版计费从策略切换点起算。 |
| 后端 / QA · 同身份双端 | 同邮箱分别登录。Android session 请求 Apple purchase / restore / lifecycle，iOS session 请求 Google verify，均拒绝。Google 续费、退款、删号、登录迁移、开关切换不改变 Apple grant 和业务数据。反向测试 Apple 退款仅改变 iOS。先保留两端前后快照和归属计数，再比较。 |
| Android QA · 异常与恢复 | 覆盖购买后杀进程、待付款后成功/取消、重复 RTDN 和 verify、通知先到、错包/错归属、Test/Live、拒付、部分退款、取消未到期、宽限/保留/暂停/恢复和替换 token。Google 超时期间 Apple 对照路径继续成功。至少一笔从购买到 Admin 导出逐字段核对。 |
| 发布负责人 · 旧制品合同与回退 | 跑 `pnpm test:app-compatibility` 的固定旧 iOS 源码合同，同时用实际在用的 iOS 制品、Android 免费制品和新计费包验服务端。旧 V1 默认返回、错误码和分页稳定。Google 窗口滚回关闭后复测权益和 Apple 原后台。任一 iOS 对照失败先恢复兼容再放量。 |

### 本次方案交付记录

2026-11-26 在方案基线上用仓库匹配的 Flutter 3.47.9 与 Node 22.23.4 运行现有定向测试。Flutter 6 个文件 **96/96**（Android 免费、Apple 验单/恢复、生命周期、Singular、扫描额度），Workers 6 个文件 **105/105**（平台策略、Apple Restore/通知、后台金额、订阅配置、Android 免费额度），Admin 5 个文件 **31/31**（订单、苹果通知、配置审批和写入）。随后执行 `pnpm test:app-compatibility`，当前 API 的 8 项用例通过，固定旧客户端 `1.0.4+161` 与 `1.0.5+163` 各通过 24 项。证据范围是当前依赖下的源码合同。两端实机交易、新制品的跨端回归、商店审核和生产观测在实施阶段按上表执行。

**原型点验。** 两份 HTML 在独立目录离线打开，通过浏览器完成月付/年付、试用、取消续订后访问至到期、支付待处理/补验、同端恢复和归属冲突。后台按当前筛选导出的 CSV 与页面相符。11 月示例的已知净额为 US$34.98，12 月退款日为 −US$4.99。已点验商品准入权限、配置草稿/启停、从 Admin 跳到 App 的预览和已购恢复。已验证 Page/Modal 的四种启停组合，两个入口均关闭时 Profile 仍能恢复已购权益。两端页面均在桌面和 320/390 像素宽度检查过。

## 八、评审时需要定下的事项

| 决策人 | 建议提案 | 会影响什么 |
|---|---|---|
| 产品 / 客服 | 对 T0 前可辨认的 Android 空间保留现有免费能力。确定 T0、生效提示、老游客归属、停服版本计划。 | 用户是否需要付费、过渡提示与服务端资格快照。存量用户若要限期过渡，先定义到期通知、超额资产处理和申诉路径。 |
| 运营 / 商务 | 首发月付、年付。确认市场、实际价格和是否启用试用、试用时长、资格、宽限与保留天数。 | Play 商品激活、后台准入以及用户看到的实际扣费条款。 |
| 产品 / 账号负责人 | Android 首次购买要求本端账号，同账号换机可恢复，跨 owner 冲突由客服核验。 | 游客到正式账号的迁移、默认入口及删号后的历史退款处理。 |
| 财务 / 数据 / 发布 | 确认 Google 收入事件名、自动采集去重、退款折算口径、订单报表权限和测试/正式分界。指定灰度观察人。 | 收入、对账、审计和放量决策。 |

## 证据与术语

- <a id="e1"></a>**E1 · 平台与功能。** [Flutter 商业策略](../../../../apps/flutter-app/lib/shared/platform/app_commercial_policy.dart)、[StoreKit 网关](../../../../dart-packages/subscription-core/lib/src/in_app_purchase_gateway.dart)、[Android Manifest](../../../../apps/flutter-app/android/app/src/main/AndroidManifest.xml)、[后端策略](../../../../apps/workers-api/src/entitlements/platform-commercial-access.ts)、[扫描路由](../../../../apps/workers-api/src/scan/routes.ts)、[累计额度](../../../../apps/workers-api/src/scan/quota.ts)、[文件夹/Performance](../../../../apps/workers-api/src/portfolio/routes.ts)、[卡价历史](../../../../apps/workers-api/src/data-source/routes.ts)。
- <a id="e2"></a>**E2 · iOS 原合同。** [正式包商品注册](../../../../apps/flutter-app/config/production.json)、[Apple 控制器](../../../../apps/flutter-app/lib/features/subscription/subscription_controller.dart)、[收入队列](../../../../apps/flutter-app/lib/features/subscription/subscription_revenue_reporter.dart)、[验单与生命周期](../../../../apps/workers-api/src/entitlements/routes.ts)、[Restore](../../../../apps/workers-api/src/entitlements/restore-routes.ts)、[Apple 通知](../../../../apps/workers-api/src/entitlements/apple-notification-routes.ts)、[有效权益查询](../../../../apps/workers-api/src/entitlements/premium-access.ts)、[iOS 三卡兜底](../../v1.1.3/01-flows/subscription-display.md)。
- <a id="e3"></a>**E3 · 运营配置。** [路由及 Google 空响应](../../../../apps/workers-api/src/subscription-config/routes.ts)、[现有 scope](../../../../apps/workers-api/src/subscription-config/model.ts)、[配置表与版本](../../../../apps/workers-api/src/db/postgres/migrations/0014_subscription_display_config.sql)、[Admin 编辑器](../../../../apps/admin-web/src/subscription-config/SubscriptionConfigPage.tsx)、[App 注册表缓存](../../../../apps/flutter-app/lib/features/subscription/subscription_product_registry.dart)。
- <a id="e4"></a>**E4 · 管理员、订单与消息。** [菜单和渲染](../../../../apps/admin-web/src/App.tsx)、[授权及 SQL](../../../../apps/workers-api/src/admin/routes.ts) 中的 `requireAdmin`、`appleBillingAdminScope`、`billingTransactionQuery`、[PostgreSQL 订单统计测试](../../../../apps/workers-api/src/admin/billing-summary.postgres.test.ts)、[订单/权益表](../../../../apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql)。
- <a id="e5"></a>**E5 · 平台边界。** [session/owner 读取](../../../../apps/workers-api/src/owner-auth.ts)、[平台账号迁移](../../../../apps/workers-api/src/db/postgres/migrations/0018_platform_account_isolation.sql)、[安装证明](../../../../apps/workers-api/src/auth/android-integrity.ts)、[Android 正式包/签名和历史轨道][release]、[隔离核查](../../v1.1.4/05-delivery/platform-isolation-audit-20261111.md)、[旧包兼容合同][compat]。
- <a id="e6"></a>**E6 · 发布与法律入口。** [App 法律页](../../../../apps/workers-api/src/legal/routes.ts)、[官网 Terms](../../../../apps/cardscanfox-web/content/legacy/terms.html)、[官网 Privacy](../../../../apps/cardscanfox-web/content/legacy/privacy.html)、[官网删号选择](../../../../apps/cardscanfox-web/src/render.mjs)、[Android 打包脚本](../../../../apps/flutter-app/tool/release_android.py)。

**术语。** `basePlanId` 表示计费周期和续费方式所属的基础方案。`offerId` 表示其下优惠，`offerToken` 是本次设备购买时交给 Billing 的值。`purchaseToken` 标识可复核的购买记录，`orderId` 标识一次订单。`acknowledge` 通知 Play 已交付新购买。Pub/Sub 的成功响应表示消息已持久接收。RTDN 是 Google 实时开发者通知。`scope` 指业务环境、商店和应用标识共同限定的数据范围。

[listing]: https://play.google.com/store/apps/details?id=com.cardai.tcg&hl=en&gl=US
[release]: ../../v1.1.4/05-delivery/android-play-release-configuration.md
[compat]: ../../v1.1.2/03-data-api/app-backward-compatibility-ai-guide.md
[fx]: ../../../../apps/workers-api/src/entitlements/billing-currency.ts
[scheduler]: ../../../../apps/workers-api/src/app.ts
[sub]: https://developer.android.com/google/play/billing/subscriptions
[integrate]: https://developer.android.com/google/play/billing/integrate
[life]: https://developer.android.com/google/play/billing/lifecycle/subscriptions
[v2]: https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2
[orders]: https://developers.google.com/android-publisher/api-ref/rest/v3/orders
[void]: https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.voidedpurchases/list
[reports]: https://support.google.com/googleplay/android-developer/answer/6135870
[rtdn]: https://developer.android.com/google/play/billing/rtdn-reference
[oidc]: https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions
[policy]: https://support.google.com/googleplay/android-developer/answer/9900533
[console]: https://support.google.com/googleplay/android-developer/answer/140504
[ready]: https://developer.android.com/google/play/billing/getting-ready
[api-setup]: https://developers.google.com/android-publisher/getting_started
[testing]: https://developer.android.com/google/play/billing/test
[pbl]: https://developer.android.com/google/play/billing/deprecation-faq
[flutter-plugin]: https://pub.dev/packages/in_app_purchase_android/changelog
[rollout]: https://support.google.com/googleplay/android-developer/answer/6346149
