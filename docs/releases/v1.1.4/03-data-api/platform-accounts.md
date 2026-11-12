# 双端平台账号、Android 免费首版与发布配置

状态：2026-11-05 起的源码实现合同；实现、构建与验证记录已更新至 2026-11-12，结果按日期分别记录。源码、迁移文件、本地测试、远端迁移和商店发布分别记录；历史段落中的“本轮未提交／未部署”只指对应阶段。

产品依据为 [Android 免费首版 PRD](../00-product/Card_AI_Android_Free_First_Release_Incremental_PRD-3.md)及[扫描规则澄清](../05-delivery/android-free-first-release-review.md#02-扫描规则澄清2026-11-05)。原始输入保持字节不变；实施前评估的旧源码差距不作为修改后的实现事实。

## 已确认的规则

- 共享基础登录身份，iOS 与 Android 各有独立平台账号、数据空间和账号状态。当前正式历史数据属于 iOS；Android 首次开通不复制历史资产。
- 两端共用密码，本端重新注册不重置另一端密码；修改共享密码影响两端。
- 游客登录已有本端账号前提示：原游客数据保留，不自动合并。注册新的本端平台账号时，只迁入同平台游客资产。
- Delete Account 删除本端账号、关联业务数据、扫描记录和图片，并撤销本端全部会话；另一端继续有效。最后一个平台账号删除时清除共享登录身份中的邮箱、密码与 OAuth 关联，必要财务／审计事实另行保留。
- Android 首版所有本期已有功能免费；iOS 保持原订阅规则。Android 扫描沿用当前 iOS 的活动队列、收藏、删除、重试和补扫，不新增批次机制。
- Android 以后会接入订阅，现阶段以集中商业策略留扩展点；不新增 Google Billing、未来额度、远程付费开关或首版用户迁移规则。

## PostgreSQL 与 owner 边界

增量迁移文件为 `apps/workers-api/src/db/postgres/migrations/0018_platform_account_isolation.sql`，已记录于 2026-11-06 在 Linux dev、2026-11-10 在 prod 执行，具体结果见本文各环境发布记录。不修改已应用 migration，不引入 D1；现有环境后续由 migration ledger 判断待执行项，不重复执行已登记迁移。

| 对象 | 归属／状态 |
|---|---|
| `user`、`auth_identity` | 共享基础身份与全局安全状态；普通平台删除不影响仍在使用的另一端 |
| `platform_account` | `id` 是用户业务 owner；`user_id` 指向基础身份，`platform` 为 ios／android；状态区分 active、disabled、deleting、deleted |
| `anonymous_account` | 新增持久化平台和删除状态；同一 device_id 在两端不复用 owner |
| `session` | 服务端记录 platform、user_id 和实际 owner_id；刷新只能继承，业务请求不能改端 |
| 业务表 | 继续使用 owner_type + owner_id，但 user owner 指当前平台空间，而非一概使用基础 user_id |

迁移将历史未删除的正式 user 建为 iOS 平台账号，平台账号 ID 沿用旧 user.id，避免重写资产和 Apple 购买归属；历史匿名 owner 与 session 同样回填为 iOS。历史已删除身份不自动复活。Android 新空间和删后重新注册的新空间使用新 ID，旧 owner 不复用。

历史 `user.status=deleted` 不建立平台账号；迁移清除其 OAuth 关联、密码、显示名和原邮箱，并将邮箱替换为基于旧 user ID 的不可登录占位。对应邮箱的认证码仅在该邮箱没有被 active／disabled 身份复用时清理。旧 user ID、业务资产 tombstone 及必要财务／审计记录保留，不迁入新账号。active／disabled 身份、登录信息和平台归属不受这项历史归一影响。

0018 的生产发布要求先冻结注册、登录及 OAuth 等认证写入，执行迁移、切换新 API 并只读核对映射后再解冻。2026-11-10 已按该流程完成，见[生产平台账号发布](#生产平台账号发布2026-11-10)。旧服务端不能创建新平台账号，不能将这次迁移描述为无需写入冻结的在线变更；Android 放行必须晚于上述步骤。

新平台空间开始写入后，不能直接回退到不识别平台 owner 的旧 API。回退版本必须保留本次平台鉴权与 owner 解析；若需要恢复发布前数据库备份，须另行核对发布后的新增数据及恢复范围。不得通过删除平台关系、把 Android owner 改写成 iOS owner 或复活旧空间来回退。

业务鉴权必须同时验证 session、平台账号／匿名账号状态及共享身份全局状态。接口不能仅凭客户端 platform、版本号或 device_id 授予 Android 免费资格。

## V1 认证合同

保持现有 `/api/v1/auth/*` 路径和原字段含义；新字段为兼容增量，不新增影响旧客户端解析的权益枚举。

| 场景 | 输入与结果 |
|---|---|
| 旧 iOS 请求 | 省略平台输入仍按 iOS 建立认证；旧 token 通过已迁移的数据库 session 绑定进入原空间 |
| 新 Android 匿名会话 | `device_id`、`platform:"android"`、`integrity_token`、`request_nonce`；生产验证应用与安装资格后创建 Android session |
| 邮箱登录、注册验证、Google OAuth | 提交平台，沿用当前匿名 Bearer；Android 从可信 session 继承平台，不能用自报字段把 iOS 改为 Android |
| 返回认证结果 | 保留 user_id 的基础身份含义，追加 platform、data_space_id；实际资产请求由服务器解析 owner |
| Refresh | 继承原平台和空间，不允许请求参数切换；已删平台的旧凭证不得刷新或映射到新注册空间 |
| 平台从未开通 | 身份验证后开通空的当前平台账号 |
| 平台已经删除 | 邮箱普通登录不自动复活，需重新注册；Google 合一流程按新用户建立新空间 |

Android Google audience 使用独立 `GOOGLE_ANDROID_SERVER_CLIENT_ID`，iOS 原 `GOOGLE_CLIENT_ID` 保留。不同 Provider 的关联继续以经过验证的身份为依据，不根据客户端邮箱文本合并资产。

已通过 Apple／Google 建立、尚无邮箱密码的共享基础身份，在 Android 通过邮箱验证码注册时允许首次设置 `password_hash`；该密码立即作为双端共享凭据，原 OAuth identity、iOS 平台账号及资产保持不变。只有 `password_hash IS NULL` 时可以设置一次；已有密码必须验证原值，Android 开端或删后重注册均不得覆盖。

兼容边界：已绑定 Android 的凭证不能通过改参数切到 iOS；Android 免费资格要求安装证明。旧 iOS 客户端尚无登录应用证明，原认证入口继续验证账号密码／OAuth，而不能仅从 HTTP 证明请求实际来自 iOS 物理设备。不得把该兼容路径宣称为双端物理设备证明均已完成；它不向 iOS 路径授予 Android 免费资格，也不允许既有 Android 会话切换空间。

## Android 应用证明与环境配置

Android Standard Play Integrity 的 requestHash 为：

```text
base64url_no_padding(SHA256(UTF8(device_id + "\nandroid\n" + request_nonce)))
```

服务端通过 Google 官方解码接口验证请求哈希、包名、证书 SHA-256、时间、PLAY_RECOGNIZED、LICENSED 和设备完整性。证明只用于建立安装／认证边界，不在每次业务操作前重复阻塞验证；后续业务从已绑定 session 读取平台。

| API 环境变量 | 用途 |
|---|---|
| `GOOGLE_ANDROID_SERVER_CLIENT_ID` | Android Google 登录所用服务端 OAuth audience |
| `ANDROID_PLAY_PACKAGE_NAME` | 当前环境允许的 Android 包名 |
| `ANDROID_PLAY_CERTIFICATE_SHA256_DIGESTS` | 逗号分隔、无填充 base64url SHA-256 证书摘要；按 Play 实际安装包签名设置 |
| `ANDROID_PLAY_SERVICE_ACCOUNT_EMAIL` | 有权调用 Play Integrity 的服务账号 |
| `ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY` | 服务账号私钥，仅 Secret／私有环境注入 |
| `ANDROID_INTEGRITY_ALLOW_DEVELOPMENT` | 只有 APP_ENVIRONMENT=development 且明确设为 true 时允许独立测试环境跳过外部证明 |

生产缺配置、证明无效或服务不可用时显式失败，不能回退为 iOS 或授予 Apple 权益。开发豁免默认关闭，不写入生产配置。Google access token 只做有界进程内缓存，不持久化服务账号私钥或用户证明日志。

客户端以 dart-define 提供 Google server client ID 和 Play cloud project number。Android Firebase 使用 `ANDROID_FIREBASE_CONFIG_PATH` 指向开发／打包环境的外部 `google-services.json`，由 Google Services 官方构建任务读取，不复制进源码；实际值按环境分别提供，不虚构配置。启用 Firebase 时按顺序应用 Google Services 与 Crashlytics 插件，仅配置 Dart options 不能替代 Android 原生构建接入。

## 免费首版与后续订阅扩展

客户端与 API 各保留一个集中的平台商业策略入口：当前 Android 为免费首版策略，iOS 复用已有 Apple entitlement。页面、扫描额度、Performance、历史和文件夹能力引用该策略，不通过创建订单、试用或 Premium grant 开放 Android。

以后接入 Android 订阅时，从商业策略及独立 Google 购买适配扩展，不重写扫描或资产归属。首版免费客户端不得被现有后台订阅页配置意外锁定；未来版本的免费范围、旧用户处理、商品和 Google Billing 合同另行定义。

## 删除与存储处理

删除只作用于当前会话固定的平台空间。标记 deleting 后停止普通业务访问，图片删除或数据库处理失败时保留可重试状态，不报告成功。最终清理业务表及本端会话／购买 session 授权，平台 owner 进入 deleted，不再复用。

扫描图片和扫描记录一起处理，不能沿用旧法律页中的无限期留存描述。订单／购买链等必要财务事实按原合同保留，但不向已删平台账号重新发放业务权限。两个平台均删除后，仅保留不可登录的必要审计关联，清除共享可登录身份信息及关联邮箱认证码；另一端仍有效时保留其共享认证信息，避免使另一端的密码验证失效。

App 内删除与官网邮件删除申请采用同一平台范围。官网公开页面应说明身份核验、目标平台、删后重新注册和必要保留；客服邮箱必须真实可用，处理期限和正式截图由运营提供，未确认前不虚构。人工申请处理不等于自动完成删除。

### 人工邮件申请的受控 Admin 操作

客服完成身份和目标平台核验后，由 `super_admin` 使用以下 API 执行与 App 内相同的平台空间删除能力：

```http
DELETE /api/v1/admin/users/:accountType/:id/account
Authorization: Bearer <admin access token>
Content-Type: application/json
X-Request-ID: <request id>

{
  "platform": "ios",
  "confirmation": "DELETE_PLATFORM_ACCOUNT"
}
```

合同约束：

- `accountType` 只允许 `user` 或 `anonymous`；`id` 必须是当前平台业务空间 ID。正式账号使用 `platform_account.id`，匿名账号使用 `anonymous_account.id`。接口不接受基础 `user.id` 作为跨平台批量删除目标；历史 iOS 空间 ID 即使与基础 user ID 字符串相同，也必须通过 `platform_account` 记录解析。
- `platform` 只允许 `ios` 或 `android`，并且必须与目标记录的真实平台一致；`confirmation` 必须逐字为 `DELETE_PLATFORM_ACCOUNT`。缺少确认、非法平台或平台不匹配返回 422，目标空间不存在返回 404。
- 只有 `super_admin` 可以调用；`operator` 返回 403。该 API 不由公开网页、邮件链接或 App 自动触发，邮件请求本身也不构成删除已完成。
- active 或 disabled 正式平台账号可以进入 deleting；删除会撤销该空间全部设备 session，并复用 `deletePlatformOwner` 清理业务数据、扫描记录／图片、反馈、安装关联、App Attest 和 session entitlement。另一平台账号、数据和会话不在目标范围内。
- R2 图片删除或数据库清理失败返回 500，目标保留 deleting 以便使用同一空间 ID 重试，不得向客服或用户反馈成功。目标已为 deleted 时幂等返回 200，不重复扩大删除范围。
- 成功响应只确认目标平台空间已经删除，返回 `account_type`、空间 `id`、`platform` 和 `status:"deleted"`；它不代表 Apple 订阅已取消，也不提供全账号导出或双端删除。

操作前后写入结构化审计事件 `admin_platform_account_delete`，字段限定为 `actor_admin_id`、`target_account_type`、`target_owner_id`、`platform`、`request_id` 和 `outcome`。`outcome` 为 `started`、`succeeded`、`failed` 或 `already_deleted`；审计不得记录用户邮箱、密码、Token、邮件正文或底层错误详情。

人工处理顺序为：收到邮件申请 → 核验登录身份及目标平台 → 在 Admin 读取对应平台空间 ID 和真实平台 → 使用独立 request ID 调用上述接口 → 以 API 结果和审计结果反馈。若平台不明确、身份不足或调用失败，只要求补充信息或安排重试，不转为基础 user 的全局封禁，也不删除另一端。

## 开发与正式打包隔离

- 本机 Android 测试默认使用 `APP_ENV=test` 和独立 applicationId `com.kando.kandoApp.beta`。Debug 签名在本项目忽略目录 `.dart_tool/android-test-signing/` 首次生成，不复用全机 Debug keystore 或已有正式 JKS。下述旧 APK 交付记录按各自构建日期保留原包名，不回写为当前合同。
- Android 正式 applicationId、上传签名路径／密码、Firebase 配置和其他正式 SDK 值由独立打包环境注入；不自动读取本机已有 key.properties 或签名库。
- 2026-11-10 用户已允许在当前 Windows 机器建立隔离的正式打包环境，覆盖此前物理独立打包机要求；测试与正式配置、签名和制品仍须隔离，详见[正式打包准备](../05-delivery/android-play-release-configuration.md#本机正式构建准备2026-11-10进行中)。
- production 必须提供 `ANDROID_APPLICATION_ID`、`ANDROID_KEYSTORE_PATH`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`、`ANDROID_STORE_PASSWORD`、有效的 `ANDROID_FIREBASE_CONFIG_PATH`，以及 Google server client ID／Play cloud project number 编译参数。缺失时构建显式失败，不回退到测试签名；production 禁止 Debug 构建。
- 开发未提供 Firebase 外部配置时不应用 Google Services／Crashlytics 插件，Firebase 在运行时明确不可用，不将其写成已接通。打包机提供正式文件后仍需实发日志／分析事件验收。
- 现有 iOS 正式 Bundle ID 和 Apple 配置关系保持兼容。改变默认开发环境时，既有 iOS 发布调用必须显式使用 production 配置，防止正式包误连 dev。
- 不通过随机重命名业务方法／资源、删除 Git 历史或混用开发者账号来替代发布与来源管理；本轮不更改 IDE 全局设置、网络、账号或删除本机私有文件。

本次是在同一 Flutter 项目增加 Android 发布，继续复用本仓的跨端实现，不引入其他项目源码。向独立打包机交付时应导出已批准提交的源码并记录提交与构建来源，忽略的本地测试签名、缓存及私有配置不随源码交付；无需删除正在开发的工作区 Git 历史。

### Android dev Google 登录配置（2026-11-09）

Android dev 与既有 iOS Google 登录共用 Google Cloud project `tcg-card-2072d`，但使用独立 OAuth client，不因同项目而混用平台身份：

- Android OAuth client 为 `1030914046373-72g2q8ornut5i7hs23ff2nhaec7ovknl.apps.googleusercontent.com`，package 为 `com.kando.kandoApp.beta`，Debug 证书 SHA-1 为 `D8:EC:55:E3:B9:C4:FF:7A:2E:54:F2:DE:DA:33:98:F6:E7:2C:B4:92`。
- Android dev 的 server audience 使用独立 Web OAuth client `1030914046373-60jceo6ofjtr3f58u6oa1ov3gjl51d81.apps.googleusercontent.com`。`config/test.json` 已将该值配置为客户端 `GOOGLE_SERVER_CLIENT_ID`；Linux dev 必须以同值配置 `GOOGLE_ANDROID_SERVER_CLIENT_ID`，否则 API 会因 ID Token audience 不匹配拒绝登录。
- 原 iOS client、既有 Web client 与 production Android OAuth 均未修改；iOS API 继续使用原 `GOOGLE_CLIENT_ID`。本配置不使用 Web client secret，不接入 Firebase Authentication，也不复用 production Play Integrity 服务账号或私钥。
- dev 的 `ANDROID_INTEGRITY_ALLOW_DEVELOPMENT=true` 只允许测试安装先建立 Android 游客会话；Google OAuth 回调仍校验真实 ID Token 的 audience、issuer、已验证邮箱和 `sub`，不会因开发豁免跳过。

2026-11-09 检查时，Linux dev 的 release 为 `branch-dev-9f17115ae738-20261109093204`，已在其共享私有环境中写入上述 Android Web audience；修改前私有环境备份为 `/home/user/apps/toccards-test/shared/.env.before-android-google-20261109T092000Z`。仅 `GOOGLE_ANDROID_SERVER_CLIENT_ID` 发生变化，其余 `.env` 原始字节保持；原 iOS audience `1030914046373-j0ihp89joii8c9k66v89l9dske6mp0mc.apps.googleusercontent.com`、`APP_ENVIRONMENT=development` 与 `ANDROID_INTEGRITY_ALLOW_DEVELOPMENT=true` 均保留。该 release 与下述容器状态是当天证据，不能代替 2026-11-12 Git 合并后的运行版本回读。

只使用同一 API image `sha256:8bd2fb1d816471ae40f927b8f0ab717cc3a6b4ea0cb7b35dbf09aa79f124f9d2` 重建 API 容器，新容器 ID 为 `1aab2fce3a1665d3d59c8a72a5f73239557dd746b02626c9f11cbbb7cf9973ff`，运行且 healthy，health HTTP 200。DB／Web／migrate 容器、watcher、`current` 与 release 状态均未改变，没有执行 migration。容器访问 Google `tokeninfo` 的无效 token 探测返回 HTTP 400 `invalid_token`，只证明出站网络和端点可达，不证明真实 Google 登录或 Token 验签成功。

客户端相关定向测试 13／13 通过，`flutter analyze` 为 0 issues。使用新 dev OAuth 配置构建 Android Debug APK 1.0.7+203，来源为 `6c53c9f21d702f5860db665a2ce715f4815649a3` 加本轮未提交修改，必须标记 dirty，不能描述为纯提交制品。交付文件为 `D:/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.7-203-Android-20261109-172557/CardAI-Test-1.0.7-203-dev-google-login.apk`，252,665,220 字节，SHA-256 `407ef92aae5097e7b7971bb580aa3c90b0ae008621449d2308531314b5d11027`；同目录保存公开构建与校验元数据。

静态核验确认 package `com.kando.kandoApp.beta`、versionCode 203、minSdk 24、targetSdk 36，Debug V2 签名 SHA-1 与上述 Android OAuth client 完全匹配。Compiled Kernel 包含选定 dev Web client ID，且与实际运行 Linux dev API 的 `GOOGLE_ANDROID_SERVER_CLIENT_ID` 逐字一致；未使用 Web client secret。APK 包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三种 ABI，28 个原生库中的 19 个 64 位库全部通过 ELF 16 KB 对齐，ZIP 16 KB 对齐通过；禁止的 Billing、录音和广泛照片／存储权限不存在，测试网络策略只为 `192.168.50.201` 放行 HTTP。复制后的制品哈希一致，537 个构建输入前后未变化；临时 Flutter JDK 设置已恢复。

该包没有接入 Firebase 或 production Play Integrity，测试安装仍使用 dev Integrity bypass。applicationId 从旧测试包名变为 `com.kando.kandoApp.beta`，本机旧安装数据不会自动迁移。当前 ADB 未发现连接的设备，本轮未执行模拟器或真机安装，也未使用真实 Google 账号登录；同一 Google 用户的共享基础身份、Android 独立数据空间及端到端登录仍待真机验证，不能由静态配置、API healthy 或无效 token 探测推断为已通过。

## 实现说明

- 邮箱注册和 OAuth 首次建号可能并发命中 PostgreSQL 唯一约束。实现以邮箱验证码锁、共享 user 平台锁和唯一约束重试共同收敛到一个基础身份／Provider identity；驱动返回的 PostgreSQL 错误字段同时兼容 `constraint`／`constraint_name` 与 `column`／`column_name`，不能把真实唯一冲突误报为 500。
- 删号先将平台 owner 标记为 deleting，并由 PostgreSQL owner 写触发器阻止在途请求回写；R2 或数据库失败保留 deleting 供同一 owner 重试。关联到当前空间的已升级游客安装、反馈、会话和 device_id 同步清理或匿名化，另一平台不扩大删除。
- 扫描图片 key 去重后使用 R2 批量删除，每批最多 1000 个 key。超过 1000 张图片的账户分批执行，任一批失败即停止数据库最终清理并保留可重试状态，避免逐对象子请求耗尽 Workers 限额。
- Flutter 认证面板按商业策略渲染：Android 不创建 Apple 入口；iOS 在 Google／Apple OAuth 请求 loading 期间保留 Apple 按钮的原位置并置为 disabled，避免按钮消失造成布局位移或让用户误以为 Apple 登录已移除。Android 隔离说明增加了内容高度，面板高度受当前 viewport 约束，内容区可滚动，320×568 的普通态和 OAuth 失败态仍可触达关闭、Google 和邮箱操作。
- 历史 iOS 的本地 `portfolio.amount_hidden` 只允许当前旧 iOS owner 一次性迁入该 owner 的 scoped key。scope 优先使用 `data_space_id`；历史 iOS 的 owner ID 与迁移后的数据空间 ID 相同，因此旧 session 恢复新 scope 时不改变 key。已有 scoped 值优先，Android 和其他账号不继承旧 global。迁移由 controller 队列串行，并用持久 `migration_owner` claim 防止快速切换账号或进程重启时把同一 global 值复制到多个 scope；scoped 写入或 global 删除失败时保留 claim，由同一 scope 后续重试，其他 scope 只读取自己的值。异步读取继续使用 generation、当前 scope 和 mounted 检查阻止迟到结果覆盖新账号选择。

### 本轮修复的两个 Flutter 回归

1. Android 认证面板最初直接采用扩展后的固定高度，在 320×568 viewport 的 OAuth 失败态发生底部 14 px `RenderFlex` overflow，等价失败证据见 `.dart_tool/android-first-release/auth-profile-after-fixtures.jsonl` 的 `Android auth keeps normal and OAuth failure actions reachable at 320x568`。根因是新增平台隔离说明和操作按钮超过固定面板可用高度。修复为按 viewport 截断外框高度并让内容区滚动；同一用例同时检查操作可见、关闭按钮不与操作重叠及无 Flutter exception。独立复核确认该修改只处理布局，不改变认证路由或平台判断。
2. 移除 `main.dart` 对旧全局 amount visibility 的预读后，历史 iOS 升级用户会丢失原本地隐藏金额选择；直接恢复全局预读又会让 Android 或另一账号继承该值。修复采用上述当前 owner 一次迁移、持久 claim 和串行队列。迁移与用户选择共用 `_writeTail`，避免迟到迁移覆盖用户最新的持久化选择。9 项存储测试覆盖数据空间隔离、历史 owner scope 恢复、Android 不继承、已有 scoped 优先、A→B 快速切换、迟到读取、同 scope 保留、文件夹 scope 重置及迁移与选择顺序；Storage、Home、Collection 相关回归合计 77／77 通过。独立复核确认 claim 在 remove 失败时阻止跨 scope 复制并允许原 scope 后续清理，未发现死锁或新增跨账号副作用。

### Android Home 布局修复（2026-11-06）

用户的 Android 真机截图显示 Overview／Performance 顶部 USD 被挤到下一行，空收藏卡片的操作区域出现 `BOTTOM OVERFLOWED BY 22 PIXELS`；用户明确要求保留原 iOS 页面样式。

- 顶部断行阈值原为 `200 + 8 + 32 + 98 = 338`，仍包含 Android 免费首版已经隐藏的 32px 订阅入口。仅当 `Theme.of(context).platform == TargetPlatform.android` 时改用实际控件总宽 306；360／393 宽度下 USD 与标签同行，320 极窄宽度仍保留可读的两行布局。iOS 原 338 阈值不变。
- Overview 与 Performance 共用的空收藏卡固定高 410，窄屏或放大字号增加正文行数后会挤压按钮。Android 改为最小高 410、按实际内容增高，页面仍由原滚动容器承载；iOS 继续固定高 410。内部字体、字号、颜色、padding、按钮高度、圆角和操作流程未改，也没有通过裁剪或隐藏文字规避溢出。
- 修前 5 个 Android 布局场景均失败；修后 Android 320／360／393 宽度、普通／1.2 倍文字及 iOS 360／390 原断点的 7 项矩阵全部通过。测试同时检查 Overview 和 Performance，校验 Scan／Search 按钮不重叠且完整位于空卡范围内，保留 iOS 的旧断点意图。
- 加入原 compact 场景与 Android 无 PRO／1Y 真实点击合同后，最窄回归 9／9 通过；完整 `home_page_test.dart` 为 87 项通过、2 项失败、0 跳过，退出码 1。失败仍为此前的 Home normal／partial failure 两项 Golden，未更新这些基线或放宽断言。生产文件及测试静态分析无问题，独立 Code Review 通过。本轮未以用户手机重放，不能把 widget 回归写成真机验收。

用户随后提供 Figma 文件 `Hzsq4itkIOHp9TRWkapvcU` 的 `1603:142`／`1603:148` 节点，并明确 Android 去掉 USD 旁圆形入口和图表 PRO 标识。已在现有 Chrome 会话只读核对这两个图片节点：Android 沿用免费商业策略隐藏对应入口和 PRO badge，USD、图表及 1Y 功能保留；不删除 iOS 共享订阅组件或改变其样式。本轮未修改 Figma 文件。

核对 1Y 时发现 Overview 点击处理仍直接使用 `premiumState=free`，与 Android 已隐藏 PRO、免费开放 1Y 的策略冲突。真实点击回归在修前稳定进入订阅路由，测试显示 `No GoRouter found in context`，图表仍为 1M 且 365 天 API 未触达。修复仅让 `hasFreePremiumFeatures` 跳过这段付费入口判断，后续仍调用原 controller／服务端接口，不制造 Premium 身份或发送 Apple 已验证 header；iOS 的 1Y 付费处理保持原逻辑。

修后真实点击 Overview 1Y，controller 切至 `oneYear` 并发出 `days=365, localPremiumVerified=false` 的估值请求；Performance 1Y 同样真实切换范围，最后一次请求的 `localPremiumVerified` 为 false。两页均断言顶部订阅入口和 Overview 的 1Y PRO badge 不存在，没有仅检查按钮的 onTap 非空来代替功能验证。

修复后执行 `flutter build apk --debug --no-pub --build-number=194 --dart-define-from-file=config/test.json`，构建成功，耗时 30.4 秒；版本为 1.0.7+194，源码为 `c3762ea4` 加本节未提交修复，未修改 `pubspec.yaml` 版本。新包保存至 `D:/Downloads/CardAI-Packages/dev.kando.cardvault.sandbox.a1aa3e/CardAI-Test-1.0.7-194-Android-20261106-105724/CardAI-Test-1.0.7-194-dev-home-fix.apk`，同目录含构建信息与校验文件。

制品为 251,361,196 字节，SHA-256 `27b80ea49ff8355f3698776693f58c05da3e5e6f732c67d74a8d0f7060066194`。独立测试包名及证书与 193 包一致，签名验证通过；没有 Billing／录音／广泛照片与存储权限，19 个 64 位原生库及 ZIP 16 KB 对齐检查通过。打包前后 Home 源码哈希相同，复制后制品哈希一致。Google／Firebase／真实 Play Integrity 的配置和未验边界沿用下述 dev 测试包说明；未执行提交、推送或服务端部署。

### Android 扫描退出确认（2026-11-06）

用户反馈扫描页点击 X 会直接退出，并提供 Figma `Hzsq4itkIOHp9TRWkapvcU` 的 `1620:200` 节点。已通过现有 Chrome 会话只读核对原型：主操作为 `NO, STAY HERE`，次操作为 `EXIT`；有未收藏结果时提示 `Exit scan result?` 和 `Your scanned card has not been collected yet.`。

原实现仅在 `_items` 非空时确认，空扫描页会直接跳转 Home。Android 现在在扫描页点击 X 或按系统返回时都先确认；空列表使用 `Exit scan?`／`Exit the scanner and return to Home?`，避免无结果时误称存在未收藏卡牌。有扫描、识别中或待处理结果时沿用原型的未收藏提示。

Android 弹窗复用 `KandoConfirmModal` 的普通品牌样式；主按钮返回 false，保留页面、扫描项、相机和在途识别，次按钮返回 true 后才返回 Home，并复用原 dispose 清理相机、计时器和动画、恢复方向。弹窗遮罩不能直接关闭；弹窗内系统返回视为留下，不执行退出。同步 `_exitDialogVisible` 防止重复点击叠加确认框，finally 不在已销毁页面调用 setState。

Review 打开／保存时的退出守卫、Review 返回扫描的折叠行为，以及 iOS 的空页直接返回和原有未收藏 AlertDialog 均保持。此次没有修改扫描队列、收藏／删除范围、订阅、识别协议、服务端或数据库。独立 Code Review 未发现阻塞项。

修前 Android 空页点击 X／连续触发会直接进入 Home，新退出提示断言失败。修后强化退出回归 5／5 通过：覆盖 320 宽度与 1.2 倍文字、X 与系统返回、防叠加、遮罩拦截、Stay 保留同一扫描项并在识别完成后继续展示，以及确认 EXIT 后迟到结果不回写页面。原 Review 折叠、iOS 空页／有结果退出与取消选图合同共 4 项通过。完整 Scan 文件曾运行 145 项通过、6 项既有失败、0 跳过，失败为原有 4 项 Golden 和 2 项额度／analytics 断言；之后仅强化新增测试并重跑 5 项，没有重复完整集合或更新既有 Golden，不记为全量通过。

生产文件与最终测试的 `flutter analyze --no-pub` 通过，最终 Code Review 通过。随后执行 `flutter build apk --debug --no-pub --build-number=195 --dart-define-from-file=config/test.json`，耗时 23.6 秒，产出 1.0.7+195；构建来自 `c3762ea4` 加本轮未提交的 Home／扫描修复，未修改 `pubspec.yaml` 版本或正式配置。

交付文件为 `D:/Downloads/CardAI-Packages/dev.kando.cardvault.sandbox.a1aa3e/CardAI-Test-1.0.7-195-Android-20261106-114034/CardAI-Test-1.0.7-195-dev-scan-exit-fix.apk`，251,362,944 字节，SHA-256 `d81266b82e13c755f2a049f021766befb6494604b7875a55a4f92b7a2bec20a3`。同目录有构建信息与校验文件，复制后哈希一致；构建前后 Home／Scan 源码哈希一致。包名、项目测试证书与 193／194 一致；签名、权限、19 个 64 位库及 ZIP 16 KB 对齐检查通过。仍连接 dev，Google／Firebase／真实 Play Integrity 的未配置边界不变；未执行真机安装、提交推送或服务端发布。

### Android 模拟器页面与键盘巡检（2026-11-06）

本轮使用本地既有 API 36 AVD 与独立 Android 测试包，连接 Linux dev；主要复现条件为逻辑宽度 320、系统字号 1.2、真实 Gboard 键盘，并补查 360／393 宽度。原始截图、UI 树、日志和执行矩阵保存在忽略目录 `.dart_tool/android-ui-audit-20261106/`，不把过渡动画截图或 Ahem 测试字体的尺寸差异直接记作产品缺陷。

实际巡检覆盖引导与登录选项、邮箱输入和校验、Home Overview／Performance 的空态及有资产状态、USD 搜索、文件夹新增／返回、Search Cards／Sets 与 Set Detail、Card Detail 新增／编辑收藏、Quick Review、Collection／Wishlist／筛选、Profile、反馈邮箱与多行留言、扫描权限／相册／退出确认和 Scan Review。邮箱验证码、设置密码、忘记密码的深层步骤用本地仓库替身补充控件可达性验证，没有发送真实验证码或反馈消息。

已确认并修复的 Android 布局问题：

- 邮箱首屏键盘弹起后溢出、Continue 遮挡：父级统一判断 IME，再传给表单，键盘可见时整页滚动；收起键盘恢复原底部按钮。验证码页可滚动，Android 切页即时交接焦点；iOS 保留原布局和 120ms 转场。
- Home 大字号 Performance 标签裁切、指标卡与 Top Performers 底部溢出：Android 标签宽度随缩放扩展，指标自然增高；最多五张排名卡使用横向滚动与自然统一高度，保留原图片、宽度、间距、点击与 View all。iOS 原固定尺寸不变。
- Sets 行、收藏状态按钮、已收藏详情摘要块的大字号溢出：Android 改为最小高度容纳内容；iOS 原固定高度保持。
- 收藏表单标题裁切：Android 标题与 Portfolio 操作上下排布，避免依赖某一字号的线性缩放假设；iOS 原 Row 保持。
- 标准新增表单的购买价格被底部操作区遮挡、Quick Review 的操作区被键盘覆盖：Android 依据实际滚动视口露出焦点，Quick Review 的按钮随键盘上移。iOS Quick Review 原 `24 + keyboardInset` 滚动底部空间保留，新增合同锁定该边界。
- Collection 摘要卡与固定 Sliver 高度不一致：仅 Android 大字号根据标题、Folder、金额行和边框计算同步高度；默认字号和 iOS 原尺寸保持。

模拟器使用仓库卡图完成了相册导入、识别、匹配详情与 Review 输入检查，证明该样本路径可达，不代表真实相机识别准确率。X／系统返回、Stay 保留结果及 EXIT 的 UI 已实际检查；iOS 通过源码合同和独立 Code Review 检查，本轮没有运行 iOS 真机。Google／Firebase／真实 Play Integrity、正式邮箱账号登录、真实支付和 Play 测试轨道仍不属于此次本地 UI 验收。

最终受影响六份 Widget 文件串行运行结果为 **531 项通过／9 项既有失败／0 跳过，退出码 1**。失败名称与已记录的原基线一致：Auth 的 1 个订阅 Golden、Home 的 2 个 Golden、Scan 的 4 个 Golden 和 2 个额度／analytics 断言。随后仅对巡检末尾补出的已收藏摘要块做最小修改，完整 Card Detail 文件重跑 **68／68** 通过；没有再次运行其余五份文件。最终源码／测试分析通过，没有更新 Golden、放宽断言或忽略布局异常；真实字体回归显式加载生产字体，独立 Code Review 发现的 iOS Quick Review padding 回归已关闭。

交付测试包为 **1.0.7+199**，构建命令为 `flutter build apk --debug --no-pub --build-number=199 --dart-define-from-file=config/test.json`，来源是 `c3762ea4` 加本轮未提交改动，构建耗时 38.8 秒。已安装到模拟器核对 `versionCode=199`，并完成最后已收藏摘要块的原路径复验；该会话 Flutter 日志没有 RenderFlex／RenderBox 布局错误。文件为 `D:/Downloads/CardAI-Packages/dev.kando.cardvault.sandbox.a1aa3e/CardAI-Test-1.0.7-199-Android-20261106-194948/CardAI-Test-1.0.7-199-dev-ui-adaptation.apk`，251,370,988 字节，SHA-256 `7b9449d1b9340626bdd3c86008e87ed25843f5a47e3c57076e996e4f093c3832`。独立测试包名和证书保持，签名、权限、19 个 64 位 ELF 库与 ZIP 16 KB 对齐检查通过；同目录保留构建信息、SHA256 校验和 UI 对照图。

测试创建的两张游客收藏、临时 pending 项和两次卡图扫描已通过 UI 清理，收藏数回读为 0；模拟器显示尺寸、密度、字号、硬件键盘 IME 设置及 Wi-Fi 已与开始时保存值核对恢复。未清除既有 AVD 数据或保存快照。此次未提交／推送 Git、未发布服务端或正式移动端制品。

### Android 正文字体 Inter（2026-11-09）

Android 的默认正文、按钮、标签和金额改为本地打包的 Inter 4.1，沿用原有字号、字重、行高和颜色；不依赖运行时网络下载。字体取自官方 `rsms/inter` 的 `v4.1` 发布包，接入当前使用的 400／500／600／700／800 正体和 400 斜体，SIL Open Font License 与版权声明随 App 资产一并分发。原始发布 ZIP 的 SHA-256 为 `9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e`。

平台选择集中在 `kandoBodyFontFamily`：仅 Android 返回 Inter，其他平台不覆盖原默认字体。iOS 继续使用原系统字体；显式 `Fraunces` 的标题、卡牌名继续加载原 Baskerville SemiBold 文件。冻结的 v1.0.0 设计规范仍记录 Geist，与当前未接入 Geist 的运行源码不同；本次按用户选择的 Android Inter 增量执行，不回写冻结规范或将 Inter 注册为 Geist 别名。

Home／Card Detail 的图表提示使用独立 TextPainter，登录加载提示显式指定过 Geist，协议链接使用裸 RichText，扫描权限提示另建 Material 主题；这些位置均在 Android 显式接入 Inter，iOS 原样式保留。Card Detail 的 Finish 标签仅在 Android 用与实际文字一致的继承样式测量宽度，避免换字体后错误选择固定行或横向滚动。扫描识别、账号、订阅、服务端和数据库行为不变。共享资产声明也会将 Inter 文件包含进 iOS 包，iOS 不选择该字体，不能据此声称 iOS 二进制体积不变。

本轮使用 Flutter 3.47.9／Dart 3.13.7。8 份受影响测试文件串行运行结果为 **561 项通过／14 项失败／0 跳过，退出码 1**；新增主题／字体合同 10／10 通过，Card Detail 文件 70／70 个测试通过。原 9 项失败保留；另有 5 项在真实 Inter 渲染后产生的 Golden 差异：Profile 未订阅 banner、订阅成功 300ms 动画帧、订阅成功页、锁定的 Performance 面板和 Scan Review。合计为 12 项截图差异及 2 项既有扫描额度／analytics 断言，未更新 Golden 或删除／放宽业务断言，不能记作全量通过。

真实字体在各文件 `setUpAll` 中提前加载，并以等长 `iiii` 比 `WWWW` 窄的前置检查拒绝 Ahem 替身；晚加载产生的等宽字形及其溢出诊断不作为产品布局证据。320 宽度／1.2 倍字号的 Home Performance、Scan Review 和新增收藏表单，以及已收藏摘要块回归通过；Finish 标签以实际渲染总宽两侧各 1px 验证固定行与滚动分支。两个旧 Auth 测试仅修正外层滚动容器定位和明确 390×844 的移动视口，原交互断言保留。完整 `flutter analyze --no-pub` 为 0 issues，独立 Code Review 通过。

本轮未完成最终制品的模拟器页面验收：早期旧包对照曾进入引导页，后续同一命名 AVD 已不可用，实际 `emulator -list-avds` 返回空，不能将旧包截图视作 Inter 验收。未运行 Android 真机或 iOS 构建／真机；Windows 本地字体选择合同不能代替两端实机视觉验收。原始本地诊断保存在忽略目录 `.dart_tool/android-inter-font-20261109/`。

随后使用隔离 JDK 21.0.13+9 执行 `flutter build apk --debug --no-pub --build-number=200 --dart-define-from-file=config/test.json`，构建成功，`assembleDebug` 耗时 70.2 秒。来源为 `cbff59879b7899db7bf0ce9a65ad37244308a737` 加本节未提交字体改动，必须标记 dirty；未修改 `pubspec.yaml` 的版本号。交付文件为 `D:/Downloads/CardAI-Packages/dev.kando.cardvault.sandbox.a1aa3e/CardAI-Test-1.0.7-200-Android-20261109-094220/CardAI-Test-1.0.7-200-dev-inter-font.apk`，252,664,736 字节，SHA-256 `2b0dd089453760d7abc84b00b724ae5cc6a88ca55667e826a40b8ba7c90b0699`，同目录包含构建信息、校验文件与字体资产验证结果。

包内六个 Inter 文件、许可证及原 Baskerville 共 8 项与源码逐字节一致，字体清单的字重和斜体映射完整；14 个构建输入在构建前后哈希一致。包名仍为 `dev.kando.cardvault.sandbox.a1aa3e`，项目测试证书与 199 包一致；签名、权限、19 个 64 位原生库及 ZIP 16 KB 对齐检查通过，可覆盖安装同一测试包并继续连接原 dev。Google／Firebase／真实 Play Integrity 等既有配置和未验边界不变；本轮未提交／推送 Git，未发布服务端、正式 Android 制品或 iOS 制品。

### Android 桌面图标比例修复（2026-11-09）

用户反馈 APK 安装后的卡牌图案被放大／裁切，并提供实际桌面截图。回查 200 包及源码确认：Android 五档 legacy／foreground PNG 与 iOS AppIcon 使用同一图案，APK 内 10 个 PNG 与源码字节一致；v26 adaptive XML 却把完整方形图直接作为 foreground。AOSP Android 8 的 `AdaptiveIconDrawable` 会把每个图层四边各扩展 25%，因此原画面以 1.5 倍进入最终可见区域，主体上／下边超出，不能归为打包漏图或直接替换另一张 Logo。

仅修改 `mipmap-anydpi-v26/ic_launcher.xml`，在 foreground 内使用四边各 `16.666667%` 的比例 inset，补偿 `1.5 × (1 − 1/6 − 1/6) = 1` 的缩放并保持居中。原 3D 卡牌图案、渐变背景、五档 Android PNG、iOS AppIcon 和启动页资源均不变；不强制 OEM 桌面采用 iOS 外框形状。Android API 24／25 继续使用原 legacy 图，API 26 起使用有补偿的 adaptive 图标；Android 8 AOSP 已核对支持 foreground 内嵌 drawable 及百分比 InsetDrawable。

回归以当前 iOS 1024 图的主体几何为参照，对全部五档 Android 图逐一检查 legacy 比例、adaptive 可见区域比例及圆形安全区。修前 legacy 通过、adaptive 失败，mdpi 主体左边距为 0.04167，明显偏离 iOS 的 0.19434；修后 2／2 通过。独立 Code Review 通过。上述回归按 AOSP 的图层变换建模，遮罩预览不是手机桌面截图，不能代替用户原手机安装后的视觉验收。

最终 `flutter analyze --no-pub` 为 0 issues；格式化后的图标回归再次 2／2 通过。使用同一隔离 Flutter 3.47.9／JDK 21.0.13+9 执行 `flutter build apk --debug --no-pub --build-number=201 --dart-define-from-file=config/test.json`，`assembleDebug` 24.4 秒成功。交付文件为 `D:/Downloads/CardAI-Packages/dev.kando.cardvault.sandbox.a1aa3e/CardAI-Test-1.0.7-201-Android-20261109-100451/CardAI-Test-1.0.7-201-dev-launcher-icon-fix.apk`，252,664,852 字节，SHA-256 `ceb209b1d08d6ab72b5e881a4b1d402f5247680f6b9fe9b0bb096ca690066588`；同目录含构建信息、SHA256、实际 APK 图标验证结果和明确标注为模拟的遮罩对照图。

从实际 APK 二进制 XML 回读四边 inset 均为 fraction `0.16666662693`，10 个 launcher PNG 和 8 个字体／许可证文件与源码字节一致；26 项原始 Android／iOS 图标资源与此前 14 个字体构建输入均保持，43 个构建输入的前后哈希一致。包名、项目测试证书、dev 配置沿用 200 包，签名、权限、19 个 64 位原生库和 ZIP 16 KB 对齐检查通过。新包包含上一节 Inter 改动，来源为 `cbff5987` 加字体与本节未提交修改，不能记为干净提交制品。

本次仅对 launcher 资源追加修复与验证，未重复运行上一节 8 份 Flutter 页面测试，其 14 项失败边界继续保留。用户原手机的更新后桌面图标、iOS 构建／真机均未验；未改启动页、正式配置、服务器、数据库或既有字体实现，未提交／推送 Git 或执行远程发布。

### iOS 视觉基线与 Android 免费测试边界（2026-11-09）

本轮只修订测试及过期截图，不修改 App 页面、字体、订阅、扫描或服务端业务实现。Profile 订阅入口、订阅页／成功页、付费 Performance 面板和原扫描视觉基线明确使用 `TargetPlatformVariant` 的 iOS 变体；Home 整页场景同时固定 iOS 商业策略，防止测试框架缺省 Android 使旧 iOS 用例误用 Inter 或免费功能。正常 Home 额外断言订阅入口及 1Y PRO，历史读取失败场景只断言仍应存在的订阅入口。Android 无 Apple／购买入口、免费 1Y 和无累计扫描额度限制的既有测试继续保留，真实 Inter 仍在原测试文件加载；未拆分、排除或跳过用例。

两项扫描回归原本断言只加载一次候选详情，落后于已记录的[逐候选渐进加载](../../v1.1.3/01-flows/scan-recognition.md#候选就绪相册导入与弱网重试2026-11-02-后续增量)。现在由仓库替身记录实际候选编号，精确验证三个不同候选各加载一次；iOS 展示额度 10→9、详情完成前不报告结果、空价格完成后只报告一次及晚到数据的原断言不变。

逐图核对后仅更新七张过期 iOS Golden：两张 Home 整页采用早已批准的[文字加下划线 Tab](../../v1.1.2/05-delivery/VERIFICATION.md#2026-10-19-home-顶部模式-tab-视觉调整)；一张订阅弹窗采用当前[三卡与文案合同](../../v1.1.3/01-flows/subscription-display.md)；四张相机阶段截图采用已记录的[顶部间距、提示文字和四角取景框](../../v1.1.3/05-delivery/VERIFICATION.md#扫描页顶部操作区间距收紧2026-10-27)。固定 Windows／Flutter 3.47.9 的输出同时包含现有边缘栅格化差异，经逐图核对未发现新增内容缺失、溢出或未批准的布局改动；不以 Android 免费页面覆盖原 iOS 订阅设计。比较器仍为逐像素精确比较，未增加容差；其余五张截图通过显式平台配置恢复原基线，未更新图片。

使用 Flutter 3.47.9／Dart 3.13.7，先在同一源码基线复现全部 14 项失败；修订后原 14 项定向复验 **14／14 通过、0 跳过**。随后在 `apps/flutter-app` 执行 `flutter test --no-pub --concurrency=1 --dart-define=APP_ENV=test --reporter=json`，完整 App 为 **1405／1405 通过、0 失败、0 跳过，退出码 0**；在 `dart-packages/subscription-core` 使用相同测试参数，**12／12 通过、0 跳过，退出码 0**。根目录 `dart run melos run analyze` 对两个包均为 **0 issues、退出码 0**，`git diff --check` 通过。独立 Code Review 确认原测试注册数量和名称保留、无生产改动、无跳过或比较器放宽，七张更新图均有既有设计增量依据，未发现阻断项。原失败用例及七张基线在定向与完整集合中均通过，测试收口未遗留失败项；前述历史失败记录仍按原日期保留，不回写为历史通过。

上述收口是本地自动化测试及图像审查，不等于 Android／iOS 真机、实际相机画面、正式签名包、真实登录／购买、生产发布或商店验收通过。本轮没有构建 APK／AAB／IPA、提交或推送 Git，也未执行远程迁移、部署或商店发布。

## 验证与发布边界

代码、测试和文档改动完成后，先验证 PostgreSQL 平台迁移／认证与免费能力，再运行受影响旧 iOS 源码合同、Admin 与 Flutter 双端回归。涉及 owner 的并发写入、删号重试、游客迁移和账号切换必须检查实际结果。

2026-11-05 至 2026-11-06（Asia/Shanghai）已确认的本地验证如下：

- Workers：116 个测试文件、943／943 项通过，0 skip；受影响旧认证与业务意图已迁入 PostgreSQL／PGlite 基座，没有新增或扩展 D1 测试解释器，也未通过排除用例缩小范围。
- Admin：87／87 项通过。Marketing：27／27 项通过，法律页和内容页由真源生成；Account Setup、平台删号说明及 sitemap 合同在该范围内通过。
- TypeScript：7 项 workspace 类型检查任务通过；依赖方向 `pnpm lint` 通过。
- 生产配置只执行 Workers prod dry-run；Linux dev 只执行发布包 dry-run，未 SSH、未迁移、未发布。
- 固定旧 App 源码兼容合同通过：v1.0.4 为 24／24、v1.0.5 为 24／24、当前 API 合同为 8／8；证据目录为 `.dart_tool/app-compatibility/run-Jgdb5L`。该结果是源码合同，不代表旧正式制品或真机验收。
- Flutter App 最近一次完整串行测试为 **1351 项通过／9 项失败／0 跳过，退出码 1**。9 个失败名称与本轮前次确认的既有基线集合一致：subscription bottom sheet 的 1 个 Golden、Home 的 2 个 Golden、Scan 的 4 个 Golden 和 2 个扫描额度／analytics 断言；既有基线详情见[技术栈升级验证](../02-architecture/security-stack-upgrade.md#验证与发布状态)。没有更新这些 Golden、放宽断言或排除用例。最后统一本地偏好写队列后，Storage／Home／Collection 相关 77 项回归通过；完整 App 集合未在这项局部修复后重复执行，不能写成全量通过。
- 根 `dart run melos run analyze` 通过，App 与 subscription-core 均为 0 issues；subscription-core 的 12 项测试通过。
- Android production 缺少外部 `ANDROID_APPLICATION_ID` 时，真实 Gradle 配置检查按预期失败，未回退到测试标识或测试签名。本轮没有构建正式 AAB 或 iOS IPA。

### Android Debug 制品核验（2026-11-06）

最终 Debug 构建使用 `APP_ENV=test`、Flutter 3.47.9 和隔离 Temurin JDK 21.0.13+9，`assembleDebug` 成功，耗时 47.7 秒。制品构建时来源为未提交工作区，不能写成纯提交制品或正式发布包。

| 项目 | 实际结果 |
|---|---|
| 文件 | `apps/flutter-app/build/app/outputs/flutter-apk/app-debug.apk` |
| 版本 | 1.0.7+193；minSdk 24，targetSdk 36 |
| applicationId | `dev.kando.cardvault.sandbox.a1aa3e` |
| 字节数 | 263,707,376 |
| SHA-256 | `68dd65f0cb57df7ebd795c87126a0b51502a26e6e6a5a8cbeb95dadaaa1444ea` |
| 测试证书 SHA-256 | `18ff20094a56b75f917ff8c3cbf182600de1884adb898ccea18ad12ca73248b8` |
| 最终权限 | 没有 Billing、录音、READ／WRITE_EXTERNAL_STORAGE 或 READ_MEDIA_IMAGES／VIDEO；归因 SDK 的 AD_ID／AD_SERVICES 权限保留，不能把无应用内广告写成无归因数据处理 |
| 原生对齐 | APK 中 25 个 `.so`；17 个 64 位库全部满足 16 KB ELF LOAD 对齐，`zipalign -c -P 16 4` 通过。32 位 ML Kit OCR 库为 4 KB，不将此项写成 64 位对齐失败 |

此 Debug 包未提供正式 Firebase／Google／Play 配置，未使用正式签名；构建与静态制品检查不代表登录、Play Integrity、统计归因、相机识别或商店轨道已通过真机验收。

以上为本地开发阶段的源码、测试、配置检查和 dry-run 范围。该阶段没有连接远端数据库，没有执行 dev／prod migration，没有部署 API、Admin Pages／Workers assets、Marketing 或移动端制品，没有提交 App Store／Google Play，也没有使用正式 Android 签名。后续 Linux dev 发布见下节。

正式发布前还需要独立打包设备上的签名 AAB／IPA、Play 测试轨道、真实 Google 登录与应用证明、iOS 购买／Restore、双端真机和正式制品的 16 KB 对齐复验。官网真实操作截图、处理期限及 SDK 数据披露也需按运营和最终包事实补齐。本地通过不能代替这些验收。

## Linux dev 发布与验收（2026-11-06）

本次经用户授权，将干净的 `codex/dev-andriod@c3762ea4` 合入 `dev@154c25fc910459c92a3e6025c8fd27e7b4adf3fc` 并推送。冲突仅涉及历史文档和营销测试；保留 dev／prod 各自的历史交付证据，营销测试采用更新后的谨慎内容合同并保留 HTML 标题渲染检查。合并后的 API、Admin、共享包和 Linux 部署代码与来源分支一致。

发布前在 Node 22.23.4／pnpm 11.28.10 下重新完成 frozen 安装、依赖方向检查、7 项 TypeScript 类型检查任务、Workers 116 文件／943 项、Admin 87 项、Marketing 27 项及部署检查 13 项；均退出 0，无测试跳过。Linux dry-run 的 3 项 bundle 检查及 API／Admin 构建通过，manifest 为 `working_tree_dirty=false`。旧 App 源码兼容重跑为当前 API 8／8、App 1.0.4 与 1.0.5 各 24／24，证据位于忽略目录 `.dart_tool/app-compatibility/run-Bc4JaD/`。本次未重跑 Flutter 全量测试，前述 9 项既有失败及移动端验收边界继续保留。

kd201 由既有 watcher 发布 `branch-dev-154c25fc9104-20261106092700`，服务器另外完成受影响 Workers 11 文件／125 项、部署检查 13 项及 bundle 检查 3 项，均通过且无跳过。更新 watcher 至同一来源版本并备份其脚本及私有配置，仅为本项目添加经 Node 官方 SHA-256 清单校验的独立 Node 22.23.4 路径，未改系统 Node 或其他应用。watcher 保持跟踪 dev，沿用原 cron、发布锁及失败处理。用户另行确认后，仅向 dev 私有环境追加 `ANDROID_INTEGRITY_ALLOW_DEVELOPMENT=true`；原文件已备份，逐字节确认除此追加外原内容完整保留。Android Google／Play 正式配置仍未提供，开发豁免不代表真实安装证明或 Google 登录已通过。

为阻止旧认证写入，发布期间先停止旧 API，再由标准流程预检、备份、迁移和启动。预检确认 PostgreSQL 18.6、两个识别服务合同可达，待执行项仅 `0018`。备份 `toccards-test-20261106-092703-before-branch-dev-154c25fc9104-20261106092700.dump` 为 1,137,225,348 字节，`pg_restore --list` 退出 0，339 项目录条目；未执行恢复演练。迁移实际回填 7 个 iOS 平台账号、清理 1 条旧验证码、匿名化 2 个已删除 user，并更新 119 条历史业务会话；ledger 为 19 项／最新 `0018_platform_account_isolation.sql`。只读回查确认 7 个历史平台账号均沿用原 user ID，无漏映射、错误旧会话绑定或残留已删除用户登录字段，7 个 owner 写触发器存在。迁移后、烟测前的收藏、文件夹、心愿单、扫描记录及原会话行数与迁移前一致。

独立运行验收确认 API／DB healthy、Web running、migration exited/0，API 实际 Node 为 22.23.4；current、manifest 和 last-deployed 均指向该发布提交，失败标记不存在，复检 pendingMigrations 为空。运行 API 与发布文件及同提交 Windows 构建 SHA-256 均为 `08223de5620c73e2baebb89a302f520030764283cc474df3b201b959d38f2381`。Admin 11 个运行文件及 HTTP 响应与 Linux release 原始字节一致；对 Windows 构建的 10 个 JS／CSS 原始字节一致，HTML 仅 CR 换行有差异，不能称跨平台 11／11 原始字节一致。部署记录属于文档后续提交时，watcher 仅推进 last-seen，不应将其写成重新发布业务代码。

运行烟测 30／30 通过：基础 health、未登录鉴权、App 配置、插件缺 Key 拒绝；旧 iOS 缺省匿名认证与有限 Free 配额；Android dev 认证、`free + unlimited=true`、配额预留幂等及免费文件夹创建；iOS 看不到且不能编辑 Android 文件夹；Android Apple 接口返回 403、既有 session 不能改端、refresh 保持原空间。两个本轮独立游客均按现有删号流程清理，旧 access／refresh 均被拒绝；保留必要 tombstone，不触及真实用户、卡牌、订单或扫描图片。

本次只发布 Linux dev API／Admin 及上述 PostgreSQL 迁移，未发布 prod、Marketing、APK／AAB／IPA 或商店版本。真实邮箱／Google 登录、Play Integrity、真机扫描、旧正式 iOS 包、购买／Restore、真实负载 P50/P95 和备份恢复仍待独立验收。0018 成功后的应用回退不会撤销数据库迁移；出现 Android 数据后不得直接回退到不识别平台空间的旧 API，恢复备份须另行核对新增数据和恢复范围。

### dev 测试 APK 交付（2026-11-06 10:03，Asia/Shanghai）

用户确认已部署 dev 后，从干净的 `codex/dev-andriod@c3762ea4714c92125f5004ca6146a10bfa65c4b3` 执行 `flutter build apk --debug --no-pub --dart-define-from-file=config/test.json`，构建成功，`assembleDebug` 耗时 76.5 秒。明确加载 test 配置及其 `cronetHttpNoPlay=true`，没有改动业务源码、版本号或正式配置。

- 安装包：`D:/Downloads/CardAI-Packages/dev.kando.cardvault.sandbox.a1aa3e/CardAI-Test-1.0.7-193-Android-20261106-100303/CardAI-Test-1.0.7-193-dev.apk`；同目录保存 `build-info.json` 与 `SHA256SUMS.txt`，复制后的 SHA-256 已复核一致。
- 版本仍为 1.0.7+193；独立测试 applicationId、minSdk 24／targetSdk 36、项目测试证书与上述合同一致。包为通用 APK，含 arm64-v8a、armeabi-v7a 和 x86_64。
- 字节数为 303,821,024；SHA-256 为 `d17d893a71e1c5ff7bdb8b520e1b0580232b1832b6fdf31b52c2c8749db07d0e`。显式测试配置与上一次仅传 APP_ENV 的构建参数不同，不沿用旧制品哈希和大小。
- 签名验证通过；最终权限没有 Billing、录音或广泛照片／存储权限。28 个原生库中 19 个 64 位库全部满足 16 KB ELF LOAD 对齐，ZIP 16 KB 对齐检查通过。
- APK 中的测试网络策略只为 `192.168.50.201` 放行 HTTP；API 为 `http://192.168.50.201:8080/api/v1`。本机只读 health 检查为 HTTP 200，手机仍需能访问该局域网地址。本轮没有独立回读服务器发布 SHA 或迁移 ledger，不把 health 当作这些验收的证据。
- 本包未提供 Android 专用 Google OAuth、Firebase 或 Play 配置；这些链路不在本次通过范围。首次 Android 游客会话要求 dev 服务端同时为 `APP_ENVIRONMENT=development` 和 `ANDROID_INTEGRITY_ALLOW_DEVELOPMENT=true`，否则不能用无 Integrity token 的测试安装建立会话。本轮没有修改服务器设置或执行登录／注册写请求。

本次只执行测试 APK 构建、静态制品核验和本地交付，没有安装到手机或执行真机扫描；iOS 源码及配置未改。README 中历史“默认 production”的描述已按当前 `AppConfig` 与 Android Gradle 的实际 test 缺省行为修正。

### iOS 测试环境内部包交付（2026-11-09）

从构建前干净的 `codex/dev-andriod@6c53c9f21d702f5860db665a2ce715f4815649a3` 执行 `./tool/release_ios.sh --env test`，使用 Flutter 3.47.9／Dart 3.13.7／Xcode 27.2 完成 clean Release 归档、App Store IPA 导出及 Development 内部 IPA 打包，脚本退出 0。构建参数指定 `1.0.7 (194)`，成功后 `pubspec.yaml` 从 `1.0.7+193` 同步为 `1.0.7+194`；`Podfile.lock` 仅更新本机新 Flutter SDK 的 spec checksum，Pod 版本及根 `pubspec.lock` 未变，未升级业务依赖。

- 交付内部包：`~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.7-194/Card AI Test.ipa`，45,666,531 字节，SHA-256 `c68dd98cf37bfa988070e2b98e8afa23f72398b2af65ed8a781fdbffca1454c2`；保存文件与构建输出逐字节一致。测试包只保留最近 3 版，新版完整保存后将最旧的 190 版移入废纸篓，191／192／194 保留。
- 最终内部 IPA 已解包并通过严格完整签名验证：Bundle ID=`com.kando.kandoApp.beta`、Apple Development 签名、`get-task-allow=true`、App Attest=`development`，描述文件含登记设备；Firebase 为测试项目 `card-ai---test` 且 plist 与测试源一致。AOT 含测试 API `http://192.168.50.201:8080/api/v1`，本机只读 health 为 HTTP 200；未回读服务端发布 SHA 或 migration ledger，不据 health 推定远端版本及迁移已验收。
- 符号：同目录 `dSYMs.zip` 为 64,414,160 字节，SHA-256 `8879f85407e60907f987faa399689cd04cd288a26a3304c45dec85266de3dd0d`。脚本校验两份 ZIP 完整性，内部包及 App Store 导出包均为 43／43 个唯一 Mach-O UUID 有匹配 dSYM；这是 UUID 覆盖证据，未执行全量 DWARF 深检或真实崩溃符号化验收。
- 本次 `flutter analyze` 通过；以显式 test 配置运行 `release_config_test.dart`、`api_environment_test.dart`、`app_commercial_policy_test.dart`、`subscription_android_free_policy_test.dart`，18／18 通过、退出 0，覆盖 Android 免费策略与 iOS 原 Apple 订阅策略的区分。没有修改两端业务实现或 Android 正式身份／签名；本次按用户范围只构建 iOS，未重新构建 Android、运行完整 Flutter workspace、安装真机、执行登录／扫描／购买、上传蒲公英／App Store Connect、提交／推送 Git 或部署／迁移远端环境。ML Kit 的 Swift Package Manager 及 Apple Silicon 模拟器架构支持提示仍保留，本次真机 arm64 构建成功不代表模拟器验收通过。

以上为本地源码、测试、配置检查和 dry-run 范围。本轮没有连接远端数据库，没有执行 dev／prod migration，没有部署 API、Admin Pages／Workers assets、Marketing 或移动端制品，没有提交 App Store／Google Play，也没有使用正式 Android 签名。

正式发布前还需要独立打包设备上的签名 AAB／IPA、Play 测试轨道、真实 Google 登录与应用证明、iOS 购买／Restore、双端真机和正式制品的 16 KB 对齐复验。官网真实操作截图、处理期限及 SDK 数据披露也需按运营和最终包事实补齐。本地通过不能代替这些验收。

### 生产平台账号发布（2026-11-10）

从干净 API 源 `main@1e31a65f` 完成生产 `0018` 及新 API／双 Admin 配套发布。迁移前备份 `7mb5sy3bszvh` 完成（5.54 GB，2026-12-10 到期，未恢复演练）；认证写维护约 11:50:58–11:59:41。11:53:42 迁移提交后 ledger 为 19 项且 checksum 精确匹配，449 个既有 active iOS 空间保留原 owner ID，无映射缺失，7 个指定 owner 触发器均启用。已删除账号的登录信息按合同匿名化，清理 2 条认证身份和精确候选的 3 条验证码；未扩删另一平台资产。

最终 API version `c02380d5-32b2-4e63-b8ef-68cbdf909ebe`／deployment `2ac37542-a212-41b1-a7b4-b96b29f6cf09` 为 100%。Pages `727e70d3-385b-4f0f-9287-217248f75c27` 为 production／success，双 Admin 22 个文件均与同一冻结构建字节一致。新增 Android 公开配置和 Integrity 私钥 Secret，原 34 bindings／17 Secret 名称保留；正式环境未启用 development 豁免。官网删号页与隐私说明亦已配套发布，Google 更新规则只修正商店 URL，仍停用提示且未启用强更。

迁移前执行器两次适配失败均回滚并独立确认未部分提交；首次迁移后只读探针的数组参数问题修正后再做独立后验。全部失败记录保留，未将其计为通过。解除维护后的基础 HTTP、非法安装证明拒绝与配置／资产核验通过。207 无 Billing 的正式 AAB 已由 Play 接收，新 Upload 证书与本地制品匹配，并于 2026-11-10 13:33 发布至 6 人 Internal testing 轨道；当前轨道有效、版本尚未审核，邀请页可打开但未代用户接受。真实账号登录、Play 安装证明、Android 扫描与统计、Play 分发 APK 独立验签及 iOS 购买／Restore 未独立重放；详见[本轮发布与上传记录](../05-delivery/android-play-release-configuration.md#google-play-内部测试发布2026-11-10-1333)。

### Android 扫描退出提示条件收紧（2026-11-11）

用户补充反馈：扫描结果中没有需要加入收藏或删除的卡牌时，Android 仍会弹出退出确认。根因是退出判断把扫描队列中任意 `_items` 都当成未收藏结果，包含识别中、失败和无匹配项目。

修复后 Android 仅在存在 `matched` 卡牌时显示 `Exit scan result?`；空队列、识别中、无匹配、失败、等待额度和权益同步项目直接返回 Home。iOS 仍按原有 `_items` 未保存结果规则处理，扫描队列、删除、重试、Review 和收藏接口均未改变。

本地使用仓库隔离 Flutter 3.47.9／Dart 3.13.7 执行 `scan_page_test.dart`，156／156 通过、0 失败、0 跳过；覆盖 Android 空队列、系统返回、识别中迟到结果、无匹配、失败及有匹配卡牌弹窗。`flutter analyze --no-pub` 为 0 issues。未执行真机安装、APK 构建、提交推送或 dev/prod 发布。

### Android dev 208 包启动停留 Logo 修复（2026-11-11）

用户安装 dev `1.0.7+208` 后一直停留原生 Logo。ADB 在荣耀 BKQ-AN10（API 37）安装同一制品后复现：进程存活，`firstWindowDrawn=false`，渲染帧数为 0；Flutter 报 `PlatformException(channel-error)`，无法连接 `dev.flutter.pigeon.shared_preferences_android.SharedPreferencesApi.getAll`。异常发生于 `runApp` 前的安装标记读取，不能归因为 dev API 网络加载。

Android SDK `apkanalyzer dex code` 确认交付 APK 缺少 `io.flutter.plugins.GeneratedPluginRegistrant`，工作区同名忽略生成文件也不存在。原发布脚本直接使用 `analyze --no-pub`／`build --no-pub`，已有 Dart 依赖配置不能保证原生插件注册文件仍存在，因而构建、签名和 16 KB 对齐通过也不能证明 App 可启动。

发布脚本现在先用选定 Flutter 执行 `pub get --enforce-lockfile`，恢复锁定依赖并生成插件注册文件，然后沿用原分析、构建、制品校验及成功后更新构建号的流程。依赖准备失败时立即中止，不保存制品或提前推进共享构建号；不绕过启动异常，不修改账号数据、业务页面、订阅或 iOS 发布脚本。

新增干净检出插件生成和依赖准备失败两项回归，修前均失败；在 `apps/flutter-app/tool` 执行 `python -m unittest test_release_android test_save_android_artifacts -v`，修后 Android 发布／保存脚本共 25／25 通过、0 跳过、退出 0；独立 Code Review 无阻塞项。真实 `pub get --enforce-lockfile` 成功，根锁文件和 iOS 跟踪文件均未变化；发布脚本的 `flutter analyze --no-pub` 为 0 issues，Debug 构建耗时 38.1 秒。

新 dev APK 为 `1.0.7+209`／`com.kando.kandoApp.beta`，来自 `598bac19` 加本节打包流程未提交修复，不能记为纯提交构建。保存路径为 `D:/Downloads/CardAI-Packages/com.kando.kandoApp.beta/Android/CardAI-Test-1.0.7-209/CardAI-Test-1.0.7-209.apk`；252,275,285 字节，SHA-256 `31ad95549975c16c8c8a954dfc3e5cddd7d1afc2ede71abc8e8f5abd8e82f941`。同目录保留构建元数据和校验文件，签名与批准测试证书一致，19 个 64 位原生库及 ZIP 16 KB 对齐通过；最终 APK DEX 已确认包含自动注册类及 SharedPreferences／Secure Storage 注册。

在同一荣耀 BKQ-AN10（API 37）覆盖安装 209 后进入 Home Overview；再次强停并冷启动成功，`am start -W` 首窗为 1,116ms，`firstWindowDrawn=true`，UI 树包含 Overview／Performance、Portfolio 和空收藏入口，当前进程无原通道异常。没有清除 App 数据，诊断临时日志标签已恢复，手机上的临时 UI 树文件已移除。未执行真实扫描、Google 登录、购买／Restore、iOS 构建或 dev/prod 服务端发布；此前 208 仅构建与静态校验通过，不能记为启动验收通过。

### Android 键盘弹出慢的代码排查（2026-11-11）

用户反馈新测试机的收藏／扫描 Review 数量、价格、备注输入每次弹键盘慢，并要求排查所有输入入口；随后明确暂时无法连接手机，先检查代码。本轮未操作正在运行的其他模拟器，未修改业务代码、输入法设置或重新打包，真机点击到 IME 显示的耗时尚未测量。

已检查 `lib` 中 21 处标准文本输入构造及其复用组件、焦点和窗口配置，范围包括扫描 Review、卡牌详情内联编辑、加入收藏／Quick Review、Search／Collection 搜索、文件夹命名、登录／注册／找回密码、反馈、Home 币种搜索和 API 日志访问码。

**已复现的代码问题**：Scan Review 的 `_KeyboardDismissOnPointerDown` 和 Card Detail 页面的 `_CardDetailKeyboardDismissOnPointerDown` 仅判断触点是否位于旧焦点输入框内，跨输入框点击时会先 `unfocus()`。使用 Flutter 3.47.9／Dart 3.13.7 和 Android 主题，模拟数量到价格的触点按下、跨帧等待 32ms 再抬起，实际记录到 `TextInput.clearClient → TextInput.hide → TextInput.setClient → TextInput.show`。两项“字段切换不应主动收起键盘”诊断断言均失败，证明存在额外的 hide/show；32ms 是模拟手指按压间隔，不是测得的键盘弹出耗时。

独立“加入收藏”弹层作为同条件对照通过：触点按下时旧输入框仍有焦点，切换期间没有 `TextInput.hide`。该弹层和 Quick Review 不处于上述 Card Detail 全页 Listener 下，不能把内联编辑的证据扩展到它们。Flutter 默认 `TextFieldTapRegion` 将标准输入框归到同组，字段自身的 `onTapOutside` 不是本次复现的原因。三个场景首次点击后均在首个 pump 发出 `TextInput.show`，但 Widget 测试不包含真实输入法或系统动画。

**修复前尚待真机测量的代价**：修复前 Scan 顶层和收藏弹层读取数值型 `viewInsets.bottom`，键盘高度变化会触发复杂表单重建；收藏 `_KeyboardAwareCollectionItemScroll` 每次高度增加还会安排立即检查与 200ms 延迟检查，并可能启动 180ms 滚动。200ms 发生在键盘 inset 已变化后，不能当作人为延迟显示键盘的证据。209 为 Debug 包且 test 环境启用 DebugOverlay，这些因素的实际耗时影响未在修复前完全隔离，不归因为系统输入法或直接认定为全部卡顿的根因。

其余入口及 Android `adjustResize`／MainActivity 未发现点击输入框后等待网络或刻意延迟焦点的路径；Search／Collection 的 300ms 防抖只用于文字变化后的查询。此结论仅为源码检查，不代表各页面真机性能已通过。临时诊断脚本与 Widget 输出已在读取后清理；执行两个临时 `*_probe_test.dart` 的 `Keyboard investigation` 场景，最终结果为 1 个对照通过、2 个暴露既有缺陷的失败、0 跳过；未放宽断言或将失败记为通过。

### Android 键盘延迟真机补证（2026-11-11）

设备为 Xiaomi `23116PN5BC`、Android API 36，安装 dev Debug `1.0.7+209`，使用 `com.sohu.inputmethod.sogou.xiaomi/.SogouIME`。系统窗口、转场与 animator 动画倍率回读均为 `1.0`，没有修改。设备允许 ADB 读取日志，但 `input tap` 被系统 `INJECT_EVENTS` 权限拒绝；没有绕过此限制，后续操作均由用户本人完成，使用 `ImeTracker` 同一 token 的 `onRequestShow → onShown` 计算耗时，不把 ADB 调度或人工等待时间算作点击延迟。

| 同机、同输入法场景 | 完整配对样本 | 请求显示至显示完成 | 中位数 |
| --- | --- | --- | --- |
| 原 Review 价格／备注操作 | 4 | 762–806ms | 777.5ms |
| 系统设置搜索框对照 | 5 | 452–537ms | 501ms |
| Review 开启 CPU 采样后再次操作 | 7 | 668–774ms | 735ms |

前两组均未开启 Dart CPU 采样，样本中位数相差约 277ms；用户也反馈系统设置明显更快。第三组用于分析运行开销，不是修复后数据。指标从 App 请求显示开始，尚无物理触点到首次请求的精确时间，不能将其称为完整点击耗时，也不据这些小样本宣称所有输入页面均有相同延迟。

真机同时证实了字段切换的额外收起：Review 中一条 App `HIDE_SOFT_INPUT` 请求发生后 81ms 又发出 `SHOW_SOFT_INPUT`；旧隐藏动画被取消，随后仍收到旧 token 的 `onHidden`，新 token 再 `onShown`。与上一节 Widget 诊断的 `unfocus → hide → focus → show` 路径一致，属于已证实的焦点交接缺陷。用户主动点击输入法收起的记录单独识别，不算作 App 的错误隐藏。

另一次短时 CPU／时间线采样取得 6,956 个 CPU 样本；环形缓冲区保留的 CPU 样本跨度约 19.944 秒。Flutter 调用栈主要热点包含 `Element.performRebuild`／`updateChildren`，采样时间线中可完整配对的 290 个 Flutter Frame 的 P95 为 25.33ms、最大 40.579ms，105 个超过 16.7ms。该片段包含键盘显示／隐藏和字段切换，不是全会话或正式包性能指标。它支持“复杂表单重建是需要优先验证的额外开销”这一判断，但尚未做隔离重建的 A/B 或 Profile／AOT 对照，不能把差值全部归因于该代码或 Debug JIT，也没有证据归咎于网络或输入法配置异常。

原 Review 保留在前台，未保存／删除扫描卡牌、清除 App 数据或切换输入法。临时日志标签及 Dart profiler 开关已恢复，VM 端口转发和手机临时 UI 树已移除；原始日志、CPU 采样和时间线已读取后清理，仅保留本节汇总。临时诊断未修改业务源码、重新构建、提交推送或部署；独立加入收藏弹层及其他页面本轮未做真机耗时对照，沿用上节各自的验证边界。

### 键盘焦点与避让修复（2026-11-11，源码）

随后按上述已复现路径做最小修复：Scan Review 和 Card Detail 内联编辑移除全页 `PointerDown` 强制 `unfocus()`，数量／价格／备注字段改由 Flutter 默认 `TextFieldTapRegion` 交接焦点，字段外点击继续通过输入框 `onTapOutside` 收起键盘。Scan Review 的页脚键盘可见性读取限制在局部 `MediaQuery` 子树，识别状态、候选和表单不再直接依赖键盘 inset；Card Detail 的键盘滚动补偿改为可取消的稳定计时器，键盘动画逐帧变化不会累积多个 200ms 检查。

相关键盘定向回归 **6／6 通过、0 失败、0 跳过**；Card Detail 全文件 **73／73 通过、0 失败、0 跳过**，覆盖 Android／iOS 字段切换、空白收起、选择控件、键盘避让、草稿保留、收藏编辑和保存路径。修复前暴露焦点 hide/show 的两个诊断断言已转为通过；`flutter analyze --no-pub` 为 0 issues。Scan 全文件最终集合在约第 152 项时因 Dart VM 在编译 Flutter `Element.updateChildren` 优化 JIT 阶段内存不足而中止，未将后续用例记为通过；此前已通过的 Scan 定向回归仍保留。未修改识别、收藏确认、删除、账号、订阅、API 或数据库业务。

修复后的 dev Debug APK `1.0.7+210` 已完成构建、签名、16 KB 对齐和制品校验，路径为 `D:/Downloads/CardAI-Packages/com.kando.kandoApp.beta/Android/CardAI-Test-1.0.7-210/CardAI-Test-1.0.7-210.apk`，252,275,629 字节，SHA-256 `0f7adbe0599049a369340a9e35e63ea88e7bd2b1f315cf1df958fff98b1059ad`。构建期间 USB 设备断开，未安装到真机，未完成修复后同机 A/B；因此真机 0.78 秒与系统 0.50 秒的原始差值不能写成修复后的性能结果。

2026-11-12 提交前独立 Code Review 未发现阻塞问题，复核了双端字段焦点交接、空白收起、选择控件、页脚布局及滚动 Timer 取消边界。该审查不替代上述真机及完整集合验证，工作区已有的普通确认弹窗高度和对应测试改动不纳入本次键盘修复提交。

### 键盘动画重复构建修复与荣耀实测（2026-11-12）

用户在小米和荣耀安装 210 后仍反馈键盘弹出卡顿，说明上一节焦点交接修复没有完成性能验收。本轮使用已连接的荣耀 YOK-AN10、Android API 31、百度荣耀输入法，在现有 Quick Review 价格输入页采样；该页是独立收藏 Review，不包含 `ScanPage`。保留待收藏项和草稿，自动操作仅点击现有输入框并收起键盘，不输入文字或触发保存、删除。

确认并修复三处额外工作：

- Scan Reveal 中 `MediaQuery.of(context).disableAnimations` 仍会让整个扫描页依赖完整窗口数据。改为 `MediaQuery.disableAnimationsOf(context)`，保留无障碍动画语义；新增断言验证 5 个 IME inset 帧不会重建 `ScanPage`。
- test 环境的隐藏 DebugOverlay 默认保留 Offstage 诊断页，窗口信息仍随键盘动画刷新。设置 `maintainState: false`，关闭时卸载诊断页；外部日志／HTTP bucket 保留，production 原本不挂载此面板。诊断面板自己的临时页签状态会在关闭后重置。
- 收藏新增／Quick Review 和已收藏卡牌编辑弹层在父 ConsumerWidget 读取键盘高度，导致每个 IME inset 帧重建完整表单。将读取下沉到局部 `Builder`，复用预先创建的表单、预览和底栏 Widget；业务 Provider 更新仍正常生成新内容。首轮性能隔离保留原 180ms 避让／底栏动画、滚动补偿及业务回调，后续底栏行为按下述用户补充要求修订。

修前 ScanPage 回归为 5 帧重建 5 次，隐藏诊断页回归失败；新增和编辑弹层的 Android 回归也分别为 5 帧重建 5 次。修后新增／编辑弹层 Android、iOS 共 4 项回归通过，同时断言草稿、焦点和输入法可见性保留。最终相关集合为 Scan／DebugOverlay **164／164**、Card Detail **77／77**，合计 **241／241 通过、0 失败、0 跳过**；隔离 Flutter 3.47.9 的 `flutter analyze --no-pub` 为 0 issues，`git diff --check` 通过。独立 Code Review 未发现阻塞问题，确认业务回调及双端原布局条件未改。首次测试命令 cwd 错误导致字体资产 setup 失败，另一次编辑弹层诊断因 Dart VM OOM 中止，均未计为通过；纠正入口、工作目录后，最终完整相关集合正常通过。

真机先仅加载前两处修复时仍有长帧，Flutter UI Frame P95 两次为 60.905ms、49.134ms，不能将其记为问题已解决。之后按 Widget／CPU 时间线定位到 `_AddCollectionItemSheet` 完整重建，保留片段中 11 次、单次含子树最高 38.88ms。热重载保留旧 Element 的继承依赖，单纯重新编译不足以验证新依赖图；本轮在保留 Provider 草稿的前提下重新挂载弹层，并恢复原始 item Key，未将临时 Key 写入最终实现。

在同一进程、同一价格输入框，预热后每组重复 3 次键盘开合。下表的 Flutter 指标是 UI isolate 上可配对的 Dart `Frame` 区间，不含完整屏幕呈现；Android 指标取原始 `gfxinfo` 顶部系统汇总，两者不能混为同一口径。

| 样本 | Flutter UI 帧数／P95／最大值 | UI 区间超过 16.7ms | Android 系统帧数／P95／janky |
| --- | --- | --- | --- |
| 原 210 基线 | 121／35.177ms／109.195ms | 35 | 97／36ms／23 |
| 完整隔离后第 1 组 | 122／38.879ms／111.818ms | 23 | 113／17ms／5 |
| 完整隔离后第 2 组 | 125／22.024ms／77.149ms | 15 | 114／11ms／3 |
| 完整隔离后第 3 组 | 125／21.412ms／63.013ms | 14 | 117／13ms／3 |

另一次只开启用户 Widget 构建跟踪的 3 轮采样中，完整 Add Sheet、Form、Add Form 和卡牌预览均为 **0 次构建**；局部键盘滚动包装器为 34 次，单次含子树最高 1.68ms。该跟踪采样不与上表未开启跟踪的性能数值合并。原始 `gfxinfo framestats` 脚本最初不兼容当前表头，返回的 0 帧不可用；修正表头后明细仍只保留 10 帧，不作为全窗口指标，表中仅引用系统完整汇总。固定 16.7ms 只是统一阈值，不等同系统 janky 判定。

用户随后在当前荣耀亲自操作并反馈“明显顺畅了”。该反馈与重复业务构建消除、系统长帧减少相符，但仍有离群长帧、Debug／JIT 和采样顺序偏差；不宣称完全无卡顿，不将 UI 帧指标当作点击至键盘显示耗时。小米本轮未连接，扫描 Review、iOS 真机、Profile／AOT 及其他输入页面未做本轮真机对照；双端业务回归不能替代这些验收。

首轮交付 dev Debug `1.0.7+211`／`com.kando.kandoApp.beta`，来源 `90ddf893132e29eeae073ff778d8609916825109` 加本节未提交修改，不能记为纯提交构建。Flutter 3.47.9／Dart 3.13.7／隔离 JDK 21.0.13+9 的实际 Gradle JVM 已核对，锁定依赖准备、分析及 `assembleDebug` 成功（56.9 秒），共享构建号仅在制品保存后推进。APK 为 `D:/Downloads/CardAI-Packages/com.kando.kandoApp.beta/Android/CardAI-Test-1.0.7-211/CardAI-Test-1.0.7-211.apk`，252,275,273 字节，SHA-256 `1c062d0a0dcc70e44e9644cfca830a43195408b9cb531e57af52a9925f3c8eb5`；测试证书匹配、19 个 64 位原生库及 ZIP 16 KB 对齐通过，最终 DEX 的 `classes18.dex` 确认定义插件自动注册类。

用户明确当前待收藏项可丢弃并授权直接安装后，荣耀覆盖安装返回 Success，回读 versionCode=211、新进程已显示 Search 和真实卡牌列表，无所检查的启动通道异常／未处理异常。初次诊断脚本只接受 Home，因实际恢复 Search 而断言失败；后续直接检查已渲染的 Search UI，不将错误的页面前提当作 App 启动故障，也不将该断言记为通过。未清除 App 数据、修改账号或写入收藏。

### Quick Review 的 Total Value 固定到底部（2026-11-12）

用户安装 211 后补充要求：键盘打开时 Total Value 不应浮到键盘上方，应固定在页面底部。首轮性能隔离保留了既有 Android Quick Review 的 `AnimatedContainer` 负向键盘高度位移，这与本次明确的布局要求冲突；现采用用户新要求，移除该底栏位移包装，直接复用稳定 `footerContent`。普通新增弹层原有的整体键盘避让、Quick Review 表单滚动补偿及 iOS 原有固定底栏行为保留，保存／删除／数量／价格计算不变。

新增几何回归在旧 Android 实现复现：TOTAL VALUE 顶部／底部从 734／758 变为 404／428，恰好随 330px 键盘高度上移。修复将底栏固定在原坐标，键盘覆盖底部时不把操作栏抬到键盘上方；同时验证键盘收起后的坐标、草稿和焦点。最终验证与后续制品见下述交付记录。

强化后的 Quick Review Android／iOS 两项回归通过，Card Detail 全文件仍为 **77／77、0 失败、0 跳过**；此前未改变的 Scan／DebugOverlay **164／164** 结果保留，合计相关回归 241 项。独立 Code Review 确认只删除底栏位移、普通 Add／Edit 的原避让和业务回调未变。

后续 dev Debug **1.0.7+212** 使用相同隔离工具链执行锁定依赖准备、0 issues 分析和 `assembleDebug`（45.1 秒），成功保存后共享构建号同步为 212。APK 为 `D:/Downloads/CardAI-Packages/com.kando.kandoApp.beta/Android/CardAI-Test-1.0.7-212/CardAI-Test-1.0.7-212.apk`，252,275,253 字节，SHA-256 `9e4e2639fb132f7986462876fff96356cd662d6a7677b14f05c8beec7e885f5f`；同样来自 `90ddf893` 加未提交修改，测试证书及 19 个 64 位库／ZIP 16 KB 对齐通过。上述性能时间线和“明显顺畅了”反馈属于 212 打包前的性能修复验证，不改写为 212 新进程的性能测量。

荣耀覆盖安装 212 返回 Success，实际回读 versionCode=212、新进程 27973。初次 UI 探针在 Review 尚未就绪时未找到待处理入口并停止，未新建或保存卡牌；待现有 Review 渲染后复验，价格输入能正常唤起键盘，TOTAL VALUE 的物理坐标在键盘展开前、展开中和收起后均为 `[52,2328][312,2387]`。实际截图确认底栏被键盘覆盖、没有浮到键盘上方，价格输入仍完整可见；检查的进程日志无通道异常、未处理异常或 fatal crash。完成后收起键盘并停留原 Review，未输入、保存或删除卡牌。该次几何／启动烟测不是 212 的完整性能采样，也不代表小米或 iOS 真机验收。

已断开诊断附加但保留 App 运行，恢复临时 profiler／Widget 跟踪设置，删除本轮手机 XML 和两个自建端口转发；私有 VM 连接文件、临时 Java／候选源码等 252,553 字节已移除。保留原始压缩时间线、回归／构建日志与本次截图用于此次问题复核；Android 交付目录按既有策略保留 210／211／212，209 移到可恢复区而非宣称释放其磁盘占用。未改动 iOS 制品或其他项目进程，未提交／推送 Git、发布服务端或操作生产环境。

### 小米安装同一 212 测试包（2026-11-12）

按用户要求，将上节同一 APK 覆盖安装到 Xiaomi `23116PN5BC`（ADB `dba62e86`）；安装前重新核对保存文件 SHA-256，原安装为 210，`adb install -r` 返回 Success，安装后回读版本为 `1.0.7+212`。冷启动 `am start -W` 返回 Status=ok、TotalTime=2028ms；后续回读 Card AI MainActivity 位于前台、进程 22648 存活，所检查日志无 fatal crash、通道异常或未处理异常。首次前台断言期间系统 PhotoPicker 位于前台而中止，随后已重新回读 App 前台状态，未将该断言记为通过。

本次未清除 App 数据、重新构建 APK、修改业务源码或操作荣耀手机；手机临时 UI XML 已移除。小米键盘流畅度及 Total Value 几何未在本次安装步骤中复测，不能将荣耀的结果外推为小米验收通过；未提交／推送 Git。

<a id="linux-dev-redeploy-20261112"></a>

## Linux dev API／Admin 重部署（2026-11-12）

按用户要求，通过服务器既有 watcher 强制重发干净的 `dev@87ba3b4b0929af3e37d770605653fb14559e4a45`。该提交已包含 `codex/fixbug-andriod@5fcd814c`，保留 dev 部署／环境实现及来源分支的业务代码。本机尚未提交的文档未参与服务器构建。发布前独立回读发现 watcher 已在 11:40 自动发布同一提交；确认两把锁空闲后才执行本次重发，没有并发启动第二轮部署。

新 release 为 `branch-dev-87ba3b4b0929-20261112140056`，14:05 独立回读确认 `current`、`shared/current-release`、manifest、watcher `last-seen-sha`／`last-deployed-sha` 及干净 source 检出全部一致；失败标记不存在，watcher／deploy 锁空闲。watcher 配置选中的 Node 和 API 实际运行 Node 均为 22.23.4，发布前补跑 Admin 96 项回归、Admin 类型检查和根依赖方向检查通过，标准 watcher 的锁定依赖安装、受影响 Workers／Node 检查、API／Admin 构建及 Linux bundle 检查正常完成。

- 发布前后预检均通过两套识别服务健康合同，`pendingMigrations=[]`。PostgreSQL 保持 18.6，ledger 精确匹配发布包中的 19 个文件、最新 `0018_platform_account_isolation.sql`，没有新增业务迁移。原 `toccards-linux-test_postgres-data` 卷保留，发布配置继续使用约定的 `/var/lib/postgresql/data` 路径。
- 发布前备份 `toccards-test-20261112-140058-before-branch-dev-87ba3b4b0929-20261112140056.dump` 为 1,232,817,600 字节，在 PostgreSQL 18 容器内执行 `pg_restore --list` 成功，374 项目录条目；未做恢复演练。
- API／DB healthy、Web running、migrate exited/0。运行 API bundle 与 release SHA-256 均为 `3dde06a44aedc35dd171c083d4787f69af6e46fbf0c6142bf77690d0d31422f6`；离线 Web 程序也逐字节匹配。Admin 11 个文件在 release、运行容器、服务器 HTTP 及开发机局域网 HTTP 四处原始字节全部一致，构建包含启动刷新会话逻辑。
- 服务器侧 8 项 HTTP 检查通过：health 200，App／Admin 未登录拒绝，缺失／无效 Admin refresh token 返回可解析的 JSON 401，iOS／Google／Android 公共配置均为 200。开发机另完成 15 项局域网检查（11 个 Admin 文件、health 和三端配置），Google／Android 配置相同。
- `shared/.env`、`watcher.env` 的发布前后完整哈希不变，未输出凭据或修改私有配置。备份、历史 release 和本地文档保留，没有清理用户数据。

本次仅重发 Linux dev API／Admin；没有执行 prod、官网、Flutter 制品或商店发布，没有进行数据库业务写入验收。真实管理员登录及浏览器闪现回归、Google 登录、真机扫描、购买／Restore、恢复演练和真实流量性能仍未验收，GitHub CI 结果未回查。机器可读验收证据位于忽略目录 `.dart_tool/dev-deploy-20261112/`；上述结果是本次发布回读，不替代后续环境状态核验。
