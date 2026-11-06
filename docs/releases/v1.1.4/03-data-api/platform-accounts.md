# 双端平台账号、Android 免费首版与发布配置

状态：2026-11-05 起的源码实现合同；本地验证及 2026-11-06 Linux dev 发布结果见本文末尾。源码、迁移文件、本地测试、远端迁移和商店发布分别记录。

产品依据为 [Android 免费首版 PRD](../00-product/Card_AI_Android_Free_First_Release_Incremental_PRD-3.md)及[扫描规则澄清](../05-delivery/android-free-first-release-review.md#02-扫描规则澄清2026-11-05)。原始输入保持字节不变；实施前评估的旧源码差距不作为修改后的实现事实。

## 已确认的规则

- 共享基础登录身份，iOS 与 Android 各有独立平台账号、数据空间和账号状态。当前正式历史数据属于 iOS；Android 首次开通不复制历史资产。
- 两端共用密码，本端重新注册不重置另一端密码；修改共享密码影响两端。
- 游客登录已有本端账号前提示：原游客数据保留，不自动合并。注册新的本端平台账号时，只迁入同平台游客资产。
- Delete Account 删除本端账号、关联业务数据、扫描记录和图片，并撤销本端全部会话；另一端继续有效。最后一个平台账号删除时清除共享登录身份中的邮箱、密码与 OAuth 关联，必要财务／审计事实另行保留。
- Android 首版所有本期已有功能免费；iOS 保持原订阅规则。Android 扫描沿用当前 iOS 的活动队列、收藏、删除、重试和补扫，不新增批次机制。
- Android 以后会接入订阅，现阶段以集中商业策略留扩展点；不新增 Google Billing、未来额度、远程付费开关或首版用户迁移规则。

## PostgreSQL 与 owner 边界

增量迁移文件为 `apps/workers-api/src/db/postgres/migrations/0018_platform_account_isolation.sql`，用于受控本地回放及经授权的环境发布，不修改历史 migration，不引入 D1。2026-11-06 已执行 Linux dev 迁移，结果见末节；prod 不在本次发布范围。

| 对象 | 归属／状态 |
|---|---|
| `user`、`auth_identity` | 共享基础身份与全局安全状态；普通平台删除不影响仍在使用的另一端 |
| `platform_account` | `id` 是用户业务 owner；`user_id` 指向基础身份，`platform` 为 ios／android；状态区分 active、disabled、deleting、deleted |
| `anonymous_account` | 新增持久化平台和删除状态；同一 device_id 在两端不复用 owner |
| `session` | 服务端记录 platform、user_id 和实际 owner_id；刷新只能继承，业务请求不能改端 |
| 业务表 | 继续使用 owner_type + owner_id，但 user owner 指当前平台空间，而非一概使用基础 user_id |

迁移将历史未删除的正式 user 建为 iOS 平台账号，平台账号 ID 沿用旧 user.id，避免重写资产和 Apple 购买归属；历史匿名 owner 与 session 同样回填为 iOS。历史已删除身份不自动复活。Android 新空间和删后重新注册的新空间使用新 ID，旧 owner 不复用。

历史 `user.status=deleted` 不建立平台账号；迁移清除其 OAuth 关联、密码、显示名和原邮箱，并将邮箱替换为基于旧 user ID 的不可登录占位。对应邮箱的认证码仅在该邮箱没有被 active／disabled 身份复用时清理。旧 user ID、业务资产 tombstone 及必要财务／审计记录保留，不迁入新账号。active／disabled 身份、登录信息和平台归属不受这项历史归一影响。

生产迁移需要冻结注册、登录及 OAuth 等认证写入，执行 0018、切换新 API 并只读核对映射后再解冻。旧服务端不能创建新平台账号，不能将这次迁移描述为无需写入冻结的在线变更；Android 放行必须晚于上述步骤。开发验证阶段未执行远程迁移，后续 Linux dev 发布单独记录在末节。

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

- 本机 Android 测试默认使用 `APP_ENV=test` 和独立 applicationId `dev.kando.cardvault.sandbox.a1aa3e`。Debug 签名在本项目忽略目录 `.dart_tool/android-test-signing/` 首次生成，不复用全机 Debug keystore 或已有正式 JKS。
- Android 正式 applicationId、上传签名路径／密码、Firebase 配置和其他正式 SDK 值由独立打包环境注入；不自动读取本机已有 key.properties 或签名库。
- production 必须提供 `ANDROID_APPLICATION_ID`、`ANDROID_KEYSTORE_PATH`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`、`ANDROID_STORE_PASSWORD`、有效的 `ANDROID_FIREBASE_CONFIG_PATH`，以及 Google server client ID／Play cloud project number 编译参数。缺失时构建显式失败，不回退到测试签名；production 禁止 Debug 构建。
- 开发未提供 Firebase 外部配置时不应用 Google Services／Crashlytics 插件，Firebase 在运行时明确不可用，不将其写成已接通。打包机提供正式文件后仍需实发日志／分析事件验收。
- 现有 iOS 正式 Bundle ID 和 Apple 配置关系保持兼容。改变默认开发环境时，既有 iOS 发布调用必须显式使用 production 配置，防止正式包误连 dev。
- 不通过随机重命名业务方法／资源、删除 Git 历史或混用开发者账号来替代发布与来源管理；本轮不更改 IDE 全局设置、网络、账号或删除本机私有文件。

本次是在同一 Flutter 项目增加 Android 发布，继续复用本仓的跨端实现，不引入其他项目源码。向独立打包机交付时应导出已批准提交的源码并记录提交与构建来源，忽略的本地测试签名、缓存及私有配置不随源码交付；无需删除正在开发的工作区 Git 历史。

## 实现说明

- 邮箱注册和 OAuth 首次建号可能并发命中 PostgreSQL 唯一约束。实现以邮箱验证码锁、共享 user 平台锁和唯一约束重试共同收敛到一个基础身份／Provider identity；驱动返回的 PostgreSQL 错误字段同时兼容 `constraint`／`constraint_name` 与 `column`／`column_name`，不能把真实唯一冲突误报为 500。
- 删号先将平台 owner 标记为 deleting，并由 PostgreSQL owner 写触发器阻止在途请求回写；R2 或数据库失败保留 deleting 供同一 owner 重试。关联到当前空间的已升级游客安装、反馈、会话和 device_id 同步清理或匿名化，另一平台不扩大删除。
- 扫描图片 key 去重后使用 R2 批量删除，每批最多 1000 个 key。超过 1000 张图片的账户分批执行，任一批失败即停止数据库最终清理并保留可重试状态，避免逐对象子请求耗尽 Workers 限额。
- Flutter 认证面板按商业策略渲染：Android 不创建 Apple 入口；iOS 在 Google／Apple OAuth 请求 loading 期间保留 Apple 按钮的原位置并置为 disabled，避免按钮消失造成布局位移或让用户误以为 Apple 登录已移除。Android 隔离说明增加了内容高度，面板高度受当前 viewport 约束，内容区可滚动，320×568 的普通态和 OAuth 失败态仍可触达关闭、Google 和邮箱操作。
- 历史 iOS 的本地 `portfolio.amount_hidden` 只允许当前旧 iOS owner 一次性迁入该 owner 的 scoped key。scope 优先使用 `data_space_id`；历史 iOS 的 owner ID 与迁移后的数据空间 ID 相同，因此旧 session 恢复新 scope 时不改变 key。已有 scoped 值优先，Android 和其他账号不继承旧 global。迁移由 controller 队列串行，并用持久 `migration_owner` claim 防止快速切换账号或进程重启时把同一 global 值复制到多个 scope；scoped 写入或 global 删除失败时保留 claim，由同一 scope 后续重试，其他 scope 只读取自己的值。异步读取继续使用 generation、当前 scope 和 mounted 检查阻止迟到结果覆盖新账号选择。

### 本轮修复的两个 Flutter 回归

1. Android 认证面板最初直接采用扩展后的固定高度，在 320×568 viewport 的 OAuth 失败态发生底部 14 px `RenderFlex` overflow，等价失败证据见 `.dart_tool/android-first-release/auth-profile-after-fixtures.jsonl` 的 `Android auth keeps normal and OAuth failure actions reachable at 320x568`。根因是新增平台隔离说明和操作按钮超过固定面板可用高度。修复为按 viewport 截断外框高度并让内容区滚动；同一用例同时检查操作可见、关闭按钮不与操作重叠及无 Flutter exception。独立复核确认该修改只处理布局，不改变认证路由或平台判断。
2. 移除 `main.dart` 对旧全局 amount visibility 的预读后，历史 iOS 升级用户会丢失原本地隐藏金额选择；直接恢复全局预读又会让 Android 或另一账号继承该值。修复采用上述当前 owner 一次迁移、持久 claim 和串行队列。迁移与用户选择共用 `_writeTail`，避免迟到迁移覆盖用户最新的持久化选择。9 项存储测试覆盖数据空间隔离、历史 owner scope 恢复、Android 不继承、已有 scoped 优先、A→B 快速切换、迟到读取、同 scope 保留、文件夹 scope 重置及迁移与选择顺序；Storage、Home、Collection 相关回归合计 77／77 通过。独立复核确认 claim 在 remove 失败时阻止跨 scope 复制并允许原 scope 后续清理，未发现死锁或新增跨账号副作用。

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
