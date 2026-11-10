# Android Google Play 正式配置交接清单

核对与控制台配置日期：2026-11-09（Asia/Shanghai）。

本文定义 `com.cardai.tcg` Android 免费首版正式打包、Google Play、Firebase、Google OAuth 与 Play Integrity 的最小配置真源及验收顺序。它不保存私钥、密码、Token、API Key、原始 Console 页面或可直接执行的占位配置，也不代表打包环境、生产服务或商店发布已经完成。

## 已确认的 Play 应用身份

| 字段 | 当前真值 | 使用边界 |
|---|---|---|
| Play 开发者 ID | `7335509243736440723` | 组织开发者账号标识 |
| Play 应用 ID | `4974515041695299034` | Play Console 内应用标识 |
| Android package name | `com.cardai.tcg` | Gradle `ANDROID_APPLICATION_ID`、Firebase Android App、Android OAuth client、Play Integrity 必须一致 |
| Play App Signing | 已启用 | Google 管理用户最终安装包的应用签名；不是本地上传密钥 |
| 当前应用签名证书 SHA-256 | `97:95:91:85:58:0E:3D:75:82:62:D5:28:4B:D9:FE:7A:D2:2F:5C:34:7B:28:5A:EF:25:67:23:9F:17:97:C4:3F` | Play 公开分发证书；用于核对 Play 安装包和服务端允许证书 |
| 当前应用签名证书 SHA-1 | `26:89:B7:E0:55:29:04:53:B4:46:CE:1B:97:4A:25:55:62:55:70:08` | 从 Play Console 当前应用签名页回读；用于 Firebase／Google Android OAuth 指纹登记 |
| 同一摘要的 base64url（无填充） | `l5WRhVgOPXWCYtUoS9n-etIvXDR7KFrvJWcjnxeXxD8` | 由常规代码从上述 32 字节摘要转换；拟用于 `ANDROID_PLAY_CERTIFICATE_SHA256_DIGESTS`，发布前仍须从 Console 复核 |
| 历史签名记录 | Console 存在 2026-11-02 记录 | 只作为追溯线索，不证明当前上传 keystore 的持有方或内容 |
| Upload certificate | 未核实 | 必须从 Console 读取 SHA-1／SHA-256，并与独立打包机实际 JKS 导出结果一致 |
| App bundle | 当前为引导空态，未见上传记录 | 不得写成已上传、已进入测试轨道或已通过审核 |

Play 应用签名证书与上传证书是两套身份。独立打包机只持有上传私钥；Google Play 使用应用签名证书重新签署分发包。不得把应用签名证书当作本地 JKS，也不得把上传证书摘要当作用户从 Play 安装后的最终签名摘要。

当前 Play 初始设置为 6／12。登录详情、目标受众、Data safety、交易者状态、应用类别与联系方式、商店详情仍需由运营依据最终包和正式业务事实完成。Play Integrity 已关联 `card ai`／project number `1030914046373`；当前关联表仅有这一个项目，因此解除操作不可用，需先增加另一关联项目才能解除。

## Google 与 Firebase 资源边界

用户已完成 MFA／两步验证并由本人处理 Firebase 条款，账号门禁已经解除。Firebase Android App、Play 分发 SHA-1、自动生成的 Android OAuth client、Android 原生配置交付物、Play Integrity project 关联、专用服务账号及本地私钥均已建立；Upload 签名、服务端 Play 分发 SHA-256 允许集合、打包机注入、服务账号调用权限与生产 Secret 注入仍待核实或配置。

| 对象 | 必须取得的真值 | 交接要求 |
|---|---|---|
| Firebase project | `card ai`；project ID `tcg-card-2072d`；project number `1030914046373` | 与仓库 iOS production plist 匹配；继续使用前仍须保持 Android 与 iOS App 配置独立 |
| Firebase iOS App | Apple iOS `cardAi`；Bundle ID `com.cardai.tcg`；App ID `1:1030914046373:ios:d7aa0de588060708f5504c` | 保持原配置，不复用为 Android App |
| Firebase Android App | `Card AI Android`；package `com.cardai.tcg`；App ID `1:1030914046373:android:ff2ff9194659fa63f5504c` | 已保存 Play 分发 SHA-1 `26:89:B7:E0:55:29:04:53:B4:46:CE:1B:97:4A:25:55:62:55:70:08`，Console 回读一致；未添加 SHA-256 或 Upload 证书指纹 |
| Android 原生配置 | 已核实 `google-services.json`，1613 字节，SHA-256 `33655d82c9e7be25b75612c4d2113ec8bda1bc763f896d760f5e3fdf309ab4f3` | 包含匹配的 Android client（`client_type=1`、package、SHA-1）及 Web client（`client_type=3`）；未将 JSON 或 API Key 写入仓库 |
| Android 配置交付物 | `D:/Downloads/CardAI-Android-Release-Config/com.cardai.tcg/20261109-sha1-33655d82/google-services.json` | 同目录保留 `config-verification.json` 与 `SHA256SUMS.txt`；仅为待交付产物，尚未注入本机测试或独立打包环境 |
| 旧下载文件 | 两个 1303 字节 JSON，SHA-256 均为 `b888fa6e9de96a1bdda5627fced8ce58b01c1b5ed9b0edae637073517e0eed86` | 只含 Web client，不得用于 Android production；原下载未删除或覆盖 |
| Android OAuth client | `1030914046373-k5qcg4ihftm7g4rbh4vr7j97mudj7aru.apps.googleusercontent.com` | 由 Google Service 自动创建；类型 Android、package `com.cardai.tcg`、SHA-1 与上述分发证书完全匹配，不代表手工修改 iOS／Web client |
| Web OAuth client | 现有 `1030914046373-ub1ap8io8trdoj2lu5musu2bmumduuak.apps.googleusercontent.com`（Google Service 自动创建） | 用户已确认保留当前分工，Android server audience 使用此值；API 本地 prod 变量已准备，尚未注入客户端或线上 API，也未真实验签。必须同时写入 `GOOGLE_SERVER_CLIENT_ID` 与 `GOOGLE_ANDROID_SERVER_CLIENT_ID` |
| iOS OAuth client | 已存在，保持现状 | 不复用为 Android client，不修改现有 iOS 配置 |
| Play Integrity Cloud project | 已关联 `card ai`／project number `1030914046373`，Play Integrity API 已启用 | `LICENSED`、`PLAY_RECOGNIZED`、`MEETS_DEVICE_INTEGRITY` 三个基础响应已自动启用；其余可选响应未启用。该 Console 状态不等同真实 Token 验证、解码调用或 Cloud API 独立回查 |
| 现有 Cloud 服务账号 | `firebase-adminsdk-fbsvc@tcg-card-2072d.iam.gserviceaccount.com` | 仅证明账号存在；未确认具备 Play Integrity 所需权限，不读取或复用其私钥 |
| Play Integrity 服务账号 | `cardai-play-integrity@tcg-card-2072d.iam.gserviceaccount.com`；唯一 ID `100866085555606469332`；状态已启用 | 本轮使用“创建并关闭”，未添加项目角色、直接访问或模拟授权。既有项目继承权限保留，包括 Firebase Admin SDK 服务账号继承的 Service Account Token Creator，以及用户继承的 Owner／Editor；本轮未审计或修改既有项目 IAM，不得表述为无人可模拟 |
| Play Integrity 本地私钥 | 唯一 JSON Key ID `c86debc3d56da8ad1072a6242169498c612ff442`；Active；创建于 2026-11-09 | 仅本地保管，尚未写入 Cloudflare Secret、候选版本或其他运行环境；真实 OAuth／解码权限未验证 |

仓库 iOS production plist 指向的 `tcg-card-2072d`、project number `1030914046373` 与 Console 核对一致；同一项目现已分别注册上述 iOS 与 Android App，并关联 Play Integrity。平台 App、原生配置和 OAuth client 仍各自独立，项目一致不能替代上传签名核对、服务端分发证书允许集合、真实 Google 登录或 Integrity 验证。Upload 证书的 Firebase 指纹仅在需要支持其签名的侧载登录时另行登记；Play 轨道登录使用已登记的 Play 分发 SHA-1。测试项目 `card-ai---test`、project number `490325688457` 只属于测试环境，不得作为 Android production 配置。

Android package 与 iOS Bundle ID 虽然都是 `com.cardai.tcg`，平台资源仍相互独立。不得复用 iOS `GoogleService-Info.plist`、iOS OAuth client、Apple 签名材料或服务端 `GOOGLE_CLIENT_ID`。现有 iOS 配置和发布流程不得因 Android 接入而改写。

## 独立打包机字段映射

正式打包机从批准且干净的源码提交构建 release AAB。仓库不会读取 `key.properties`、全机 Debug keystore 或本机既有正式签名。

| 注入字段 | 来源与要求 |
|---|---|
| `ANDROID_APPLICATION_ID` | 固定为 `com.cardai.tcg` |
| `ANDROID_KEYSTORE_PATH` | 已在 Play 登记的 Upload 私钥 JKS 私有路径 |
| `ANDROID_KEY_ALIAS` | 与该 JKS 实际 alias 一致 |
| `ANDROID_KEY_PASSWORD` | 打包机 Secret |
| `ANDROID_STORE_PASSWORD` | 打包机 Secret |
| `ANDROID_UPLOAD_CERTIFICATE_SHA256` | 从 Play Console 核实的 Upload 证书摘要，供 Android 发布脚本比对最终签名；当前 Upload 证书仍未核实，不得填写 App Signing 分发证书代替 |
| `ANDROID_FIREBASE_CONFIG_PATH` | 独立打包机接收并复核上述 SHA-256 后使用的私有路径；当前交付物尚未注入任何打包环境 |
| `GOOGLE_SERVER_CLIENT_ID` | 正式 Web OAuth client ID，属于公开标识，以 dart-define 构建参数注入 |
| `ANDROID_PLAY_CLOUD_PROJECT_NUMBER` | 已关联 Play Integrity 的 Cloud project number，以 dart-define 注入 |

构建仍加载仓库 `config/production.json` 选择生产 API 与原 iOS 订阅合同，但该文件不包含上述 Android Google 值。缺少 application ID、正式签名、Firebase 文件或两个 Android dart-define 时，Gradle 必须显式失败；不得回退到测试包名、测试签名或测试 Firebase 项目。打包环境需固定项目要求的 Flutter 3.47.9、Dart 3.13.7 与 JDK 21.0.13+9，并记录源码提交、工具链和输入文件哈希。

## API 与 Play Integrity 字段映射

| API 配置 | 正式值来源 |
|---|---|
| `GOOGLE_ANDROID_SERVER_CLIENT_ID` | 与客户端 `GOOGLE_SERVER_CLIENT_ID` 相同的 Web OAuth client ID |
| `ANDROID_PLAY_PACKAGE_NAME` | `com.cardai.tcg` |
| `ANDROID_PLAY_CERTIFICATE_SHA256_DIGESTS` | Play App Signing 分发证书 SHA-256 的无填充 base64url；证书轮换时按 Console 实际允许集合维护 |
| `ANDROID_PLAY_SERVICE_ACCOUNT_EMAIL` | `cardai-play-integrity@tcg-card-2072d.iam.gserviceaccount.com`；账号已创建并启用，真实 Play Integrity 解码权限尚未验证 |
| `ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY` | 已生成的唯一 Active JSON key 中未加密 PKCS#8 RSA 2048 `private_key`；接收目标为生产 Worker `toccards-api-prod` 的 Secret，通过未部署候选版本注入。当前尚未提取为单独 Secret 中转文件或写入 Cloudflare，候选上传与切流均未执行 |
| `ANDROID_INTEGRITY_ALLOW_DEVELOPMENT` | production 不得启用 |

服务端会验证 requestHash、包名、证书、时间、`PLAY_RECOGNIZED`、`LICENSED` 与设备完整性。本次发布验收要求从 Play 测试轨道安装正式签名包；侧载 APK、Debug 包或仅上传 AAB 均不能替代，正式 Play 分发包的后续运行证据另行记录。

## API Secret 接收与候选版本方案

生产接收目标确定为现有 Cloudflare Worker `toccards-api-prod`，不是 Firebase、Flutter 打包机或 Linux dev。仅 `ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY` 使用 Secret；Android Web audience、包名、分发证书摘要及服务账号邮箱是公开配置，已补入 `apps/workers-api/wrangler.toml` 的 `[env.prod.vars]`。原 `GOOGLE_CLIENT_ID` 和其他既有生产配置保持原值；这些改动目前仅在本地，尚未写入 Cloudflare。

专用服务账号 JSON key 已由用户授权生成并仅在本地接收，保存于 `C:/Users/jhon/AppData/Local/CardAI/Secrets/PlayIntegrity/tcg-card-2072d-20261109-4d841d1a/tcg-card-2072d-c86debc3d56d.json`。目录、私钥文件与 `verification.json` 的 DACL 均仅允许当前用户与 `SYSTEM`，目录中只有这两个预期文件；原 `D:/Downloads` 下载文件已不存在，凭据未复制入仓。普通代码核对 `type=service_account`、`project_id=tcg-card-2072d`、`client_email`、`client_id`、Key ID 与 `token_uri` 均匹配，并确认未加密 PKCS#8 RSA 2048 私钥可完成本地随机挑战 SHA-256 签名回验；`verification.json` 仅保存公开元数据与验证结果。

后续经独立授权创建候选时，只提取 JSON 的 `private_key` 作为 `ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY` Secret，不得把整个服务账号 JSON 当作 Secret 值。当前实现支持真实多行 PEM，以及使用“反斜杠加字母 n”表示换行的单行转义形式；不支持 PKCS#1、加密 PEM 或带外层引号的值。当前没有导出额外 Secret 中转文件；如候选上传工具需要 `--secrets-file`，须在该次授权内于仓库外受限目录临时生成并按批准流程处置。凭据内容不进入聊天、Git、命令参数或日志；发布记录只保留账号、Key ID、Secret 名称、候选版本及验证结果。

仓库锁定的 Wrangler `4.106.0` 支持 `versions upload --secrets-file`。后续从批准且干净的源码、同次构建的 Admin assets 创建候选，并通过仅含 `ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY` 一项的私有 JSON 注入密钥。使用 `--keep-vars` 保留远端额外普通变量，同时应用本地配置；该上传路径保留未修改的既有 Secret。命令形态如下，两个变量必须由发布负责人提供，当前不执行：

```powershell
pnpm --filter @kando/workers-api exec wrangler versions upload `
  --env prod `
  --keep-vars `
  --strict `
  --secrets-file $integritySecretFile `
  --tag $approvedReleaseTag `
  --message "Prepare Android Play Integrity production configuration"
```

候选创建后，核对代码／assets 哈希与批准构建一致，四项公开变量正确，原普通变量和既有 Secret 名称全集保留且仅新增上述私钥 Secret，Hyperdrive／KV／R2／Service Binding／限频／runtime／placement／cache 未变化，并确认当前活动 deployment 及流量分配未改变。2026-11-09 只读基线为活动 deployment `481eeda4-9d84-4818-a539-1cf2b6abb964`、version `a31cd853-63cb-482a-b4f5-d9f2bf276761`、100% 流量，Secret 名称 17 项且无 Android 新 Secret；执行前仍须重新回查，不能从名称保留推断已读取或逐字节比较 Secret 明文。

`versions upload` 不分配生产流量；生产平台账号 migration、新 API 与双 Admin 的配套验收及正式切流仍按发布授权单独执行。不得使用会立即部署的普通 `wrangler secret put`／`secret bulk` 来做准备；也不采用从“最新上传版本”克隆的 `versions secret bulk` 替代上述完整候选上传，避免遗漏本地公开配置或带入其他候选。私钥生成、候选上传、正式部署是三个独立动作，本轮已确定接收方案、准备本地配置，并经单独授权生成私钥且仅在本地保管；候选上传与正式部署未执行。

服务账号密钥格式校验只能证明私钥可解析；OAuth Token 获取成功也不能替代真实 Play Token 解码及安装门禁验证。回退目标若缺少新 Secret 或四项公开变量，Android 新安装验证会不可用；回退时须核对该目标的完整配置，不能关闭生产 Integrity 校验。iOS 继续使用原 audience 与 Apple 业务规则，不因新增 Android 配置改写。

官方命令语义参见 [Workers Secrets](https://developers.cloudflare.com/workers/configuration/secrets/) 与 [Wrangler commands](https://developers.cloudflare.com/workers/wrangler/commands/)。本轮同时核对已安装的 `4.106.0` 实现，未将新版在线文档视为本地 CLI 已具备全部新增能力。

本地验证（2026-11-09）：最终使用隔离 Node `22.23.4`，部署配置与 Integrity 定向测试 2 文件／20 项通过，API 类型检查、auth-core／Admin production 构建及 Worker prod dry-run 通过；配置差异检查确认只新增上述四项公开变量，原 iOS 与其他生产配置保持。首次测试命令误扫历史 `.wrangler` 副本而失败；第二次参数透传错误意外启动 Workers 全量测试并出现内存不足，已中止；两次均不计为通过。最终定向命令显式排除历史副本并限制单 worker；Workers 全量测试未完成。私钥身份与本地签名格式验证通过，但没有发起真实 OAuth 网络请求；真实 IAM／OAuth／解码／Cloudflare Secret 传输及双端实机仍未验收。本轮未修改业务逻辑，未上传候选或部署服务。

## 配置与验收顺序

1. 在 Play Console 复核应用身份、App Signing 证书、Upload certificate 及应用访问权限；确定 Upload keystore 的实际持有方和备份责任人。
2. 在独立打包机由工具导出 JKS 证书 SHA-1／SHA-256，与 Console 的 Upload certificate 逐字节匹配。不得在仓库或普通终端输出密码和私钥。
3. 独立打包机接收上述 Android 配置交付物并复核 SHA-256；继续按实际用途核实 Upload 证书，必要时登记其 SHA-1／创建对应侧载 OAuth client。当前自动生成的 Android client 只覆盖已登记的 Play 分发 SHA-1。
4. 复核已关联的 Play Integrity project、三个基础响应和已启用 API；核实专用服务账号所需最小权限，并按上节接收方案准备候选 Secret。私钥已获授权在本地生成，但上传候选、Cloudflare Secret 写入和真实 OAuth／解码仍须分别授权或验证。不得未经权限审查直接复用现有 Firebase Admin SDK 服务账号、其 Token Creator 能力或其密钥。
5. 将客户端公开标识、打包 Secret 和 API Secret 分别注入对应环境；先完成配置检查和生产 API 候选验证。Android 放行仍须晚于生产平台账号 migration 与新 API 发布。
6. 构建 release AAB，核对来源、版本、package、Upload 签名、production API、Firebase project、最终权限、ABI、原生库和 16 KB 对齐；保存 AAB SHA-256 和构建清单。
7. 上传 Internal testing。Play 处理完成后，核对生成安装包使用 App Signing 证书，再从 Play 安装并验证 Play Integrity、Google 登录、Firebase Analytics／Crashlytics及 Android 免费业务闭环。
8. 同轮回归 iOS 登录、Apple 购买／Restore 和原数据空间；根据最终 AAB、SDK 与真实数据处理填写 Data safety、隐私、账号删除、商店详情及其余初始设置。

完成上述步骤前，不得将源码实现、Debug APK、Firebase App／SHA-1／OAuth 注册、Integrity project 关联、服务账号或本地私钥创建、配置文件下载或历史证书记录描述为 Android production 已完整配置、已上传或已通过商店验收。Android OAuth client 由 Google Service 自动创建，未手工修改原 iOS／Web client；Firebase SHA-1 登记也不等于服务端所需 Play 分发 SHA-256 已注入。专用 Integrity 服务账号与唯一私钥已创建并仅在本地受限保管，但本轮未添加直接 IAM 授权、未审计或修改既有项目继承 IAM，未写入 Cloudflare Secret、上传候选或完成真实 OAuth／解码；API／打包机正式配置未注入，Upload key 与打包机仍未核实，也没有真实 Google 登录／Integrity E2E、App／API 部署、数据库迁移、移动端发布或 Git 提交／推送。

## 本机正式构建准备（2026-11-10，进行中）

用户允许在当前 Windows 机器建立隔离的正式打包环境，覆盖此前物理独立打包机的要求；仍不复用本机既有正式签名。发布源已合并为 `main@a91ceb65`，共享版本为 `1.0.7+205`。Play Console 实时回读确认组织账号、正式 package、Google 托管分发证书及三个 Integrity 基础响应保持；内部测试尚无发布版本，现已建立首个未命名草稿。签名页未显示既有 Upload 证书，不能因此宣称已核对了既有 Upload JKS。

在仓库外受限目录新建尚未登记的专用 Upload JKS，alias 为 `cardai-upload-20261110`，RSA 4096；公开 SHA-256 为 `43:38:30:F5:02:98:FA:A5:E6:5E:B4:68:19:E1:59:52:11:8D:E3:31:19:F9:F5:7A:33:49:6E:7B:E5:33:84:28`，SHA-1 为 `6D:61:50:B7:A8:B6:C4:EA:41:FF:AB:D6:CE:8E:6C:AF:B0:47:DC:A7`。密码随机生成并由当前用户的 Windows DPAPI 加密保存，目录只允许当前用户与 SYSTEM；凭据未入仓。此签名仅是首包候选上传身份，尚未经 Play 接受或登记，不更换 Google 托管分发证书。

隔离 Flutter 3.47.9／Dart 3.13.7／JDK 21.0.13+9 可用。Google 官方 bundletool 1.18.3 的 SHA-256 与官方 asset digest 一致。项目所需 API 36、Build Tools 36、NDK 28.2 和 Platform Tools 均使用已接受的 Android SDK license；doctor 的剩余许可警告仅指未使用的 microXR 预览镜像，本轮没有接受新条款。

首次 release AAB 构建失败于 `processReleaseGoogleServices`：Google Services 4.4.4 后注册的 variant 任务覆盖了通用 `configureEach` 中设置的外部文件输入。最小修复在插件完成各 variant 的任务注册后，通过后注册的 `androidComponents.onVariants` 回调设置命名任务输入，不复制配置进源码。实际独立执行该 release Gradle 任务成功，生成资源中的 project ID、Android App ID 与 Web audience 均与批准配置一致，外部 JSON SHA-256 未变，源码目录中没有 `google-services.json`。完整 AAB 仍待重试，不能把此任务通过写成制品完成。

专用 Play Integrity 服务账号的真实 OAuth Token 请求返回 HTTP 200；固定无效 Token 的解码探测返回 HTTP 400／`INVALID_ARGUMENT`。Token 仅在进程内使用，不输出或落盘。这证明凭据和接口可达，不等于真实 Play 安装证明通过；未新增 IAM 权限，真实 Token 解码仍待 Play 安装包验收。生产 Secret、API 配套迁移／发布及内部测试 AAB 上传尚未执行。

第二次完整构建已通过外部 Firebase 任务，随后失败于 R8：Flutter ML Kit 插件将 Chinese／Devanagari／Korean 识别器声明为可选 `compileOnly`，但在脚本分流中直接引用其类型。当前 App 只创建 Latin 与 Japanese 识别器，Japanese 依赖已提供。最小处理仅加入 R8 自动建议的上述三种未使用脚本共六个具体类型的 `dontwarn`，不关闭 R8、不扩大到整个 ML Kit 包，也不引入未使用模型；修复后的完整 release 构建与两种实际 OCR 运行仍需分别验证。Android `.kotlin` 编译缓存加入忽略，保留既有缓存内容，避免构建输出使正式源码门禁误报。

### 10:04 正式 AAB 与 0% API 候选检查点

第三次完整构建成功，来源为干净的 `main@1e31a65f4bacf9af62b96d13893c92578a66af4c`，产物为 `com.cardai.tcg`／`1.0.7+206` release AAB。外部 Firebase、R8、正式 Upload 签名及 bundletool 校验通过，30 个原生库中 20 个 64 位库满足 ELF 16 KB 对齐。制品路径为 `D:/Downloads/CardAI-Packages/com.cardai.tcg/Android/CardAI-Prod-1.0.7-206/CardAI-Prod-1.0.7-206.aab`，112,346,826 字节，SHA-256 `15c1c6e3f49c16f427049c9199f1b764a86b9b7e6abc24f0d4c220e729584e89`；同目录保留三份 Dart 原生符号、R8 mapping、build-info 与逐文件 SHA-256。发布脚本成功归档后才将共享 `pubspec.yaml` 从 `1.0.7+205` 写为 `1.0.7+206`。此为本地正式制品验收，尚未从 Play 安装，也未完成真实 OCR／Google 登录／Integrity／统计崩溃验收。

同一源码冻结 API／Admin 后创建未部署的 API 候选 `c02380d5-32b2-4e63-b8ef-68cbdf909ebe`，Worker 2,240,417 字节、SHA-256 `de9930f552657743acbf0723efe5009617dd72366bca5bbb64fedbc93ae89a55`，Admin 为同次构建的 11 个静态文件。独立回读确认旧 34 个 binding 描述符及原 17 个 Secret 名称保留，仅新增四项 Android 公开变量和一个 `ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY` Secret；runtime／placement 保持，未读取或比较原 Secret 明文。私钥只提取为仓库外受限临时文件传入候选，上传后中转文件已移除。当前活动 deployment 仍为 `481eeda4-9d84-4818-a539-1cf2b6abb964`／`a31cd853-63cb-482a-b4f5-d9f2bf276761`／100%，没有切流。历史 33 个 binding 的数量不覆盖本轮实时回读的 34 项真值。

生产只读事务确认 PostgreSQL 18.6、ledger 精确为 `0000–0017` 的 18 项且 checksum 全部匹配，`0018` 与新增平台表／列／owner trigger 均不存在。迁移前手工备份 `7mb5sy3bszvh` 已创建，名称 `prod-main-a91ceb65-pre-0018-20261110`，默认到期日 2026-12-10；本检查点尚在生成，不能写成可恢复备份完成。Play 内部测试名单 `Card AI Internal 20261110` 已按用户提供邮箱保存并回读为 6 人，首个版本草稿仍未上传 AAB 或发布。现有管理员页面会话已到期，本轮不读取或输出登录凭据。

### Android 免费首版移除 Google Billing SDK（2026-11-10）

正式 AAB 独立检查发现共享 `in_app_purchase` umbrella 依赖即使未调用购买，也会把 Android BillingClient、查询 intent 与原生活动打入制品。用户明确选择首版从 Android 制品移除 Google Billing SDK，同时完整保留 iOS StoreKit 订阅。最小源码调整由订阅共享包直接依赖 StoreKit 实现与平台接口，App Store gateway 首次使用时只注册一次 StoreKit；Google Play store 未注册实现时显式失败，不引入占位实现、Manifest 隐藏或未来 Billing 代码。该调整不改变 `SubscriptionStoreGateway`、`SubscriptionClient`、iOS 产品／购买／Restore／完成交易或 StoreKit 2 验签合同。

依赖与 Dart 测试通过后仍须重新构建正式 AAB，确认 Android 插件注册表、Manifest、DEX 与 bundle 元数据不再包含 BillingClient／ProxyBillingActivity／`billing.properties`／Billing 查询；同时重新构建 iOS 制品并执行真实 Sandbox 购买、purchase stream、Restore 和未完成交易回归。本地源码测试不替代双端正式制品与真机验收。

本地定向验证：subscription-core **15／15** 通过，覆盖 App Store 产品及购买参数、StoreKit 2 证据、Restore、完成交易和未注册 Google Play 的显式失败；两个 Dart 包分析均为 0 issues。锁文件已移除 umbrella 与 Android 原生购买插件，生成的插件注册表中 Android 无 `in_app_purchase_android`、iOS 仍有 StoreKit。首次完整 App 测试为 **1404 通过／3 失败**，三项均因新 worktree 缺少既有测试直接读取的 Flutter Material 字体缓存而在读取字体时失败；从已批准 SDK 按原字节补齐被引用的两个字体文件后，原 Card Detail 整文件 **70／70** 通过，未修改页面实现、测试断言或 Golden。完整 App 正在按原配置重跑，正式无 Billing AAB 尚待重建；本记录不将首轮失败写成通过。

### 无 Billing 的 207 正式制品检查点

完整 App 按原配置重跑为 **1407／1407、0 失败、0 跳过**；订阅核心 **15／15**，两包分析 0 issues。正式 AAB 从干净 `main@8701ff9b576e42582c047e71581ffb942fce1be5` 构建并归档为 `1.0.7+207`，111,933,187 字节，SHA-256 `1d6123f06f21b5d15cc00104d9c163aef657812a4c7ded028cb978fb6f4c8a11`。路径为 `D:/Downloads/CardAI-Packages/com.cardai.tcg/Android/CardAI-Prod-1.0.7-207/CardAI-Prod-1.0.7-207.aab`，同目录保留符号、R8 mapping 与逐文件校验；归档成功后共享构建号才从 206 前进到 207。

独立回读确认正式包名／版本／minSdk 24／targetSdk 36、Upload 证书、批准 Firebase 三项公开身份与三种 libapp 的 production API 均正确；30 个原生库中 20 个 64 位 ELF 全部 16 KB 对齐，BundleConfig 为 `PAGE_ALIGNMENT_16K`，Latin／Japanese OCR 均保留。最终 Manifest、DEX、bundle properties 和插件表均无 Android Billing SDK／原生购买插件，iOS StoreKit 插件保留。767 个 payload 的 manifest 摘要逐项一致且 JAR 随机访问签名验证通过；签名记录仍位于 ZIP 末尾，流式验证警告保留，以 Play 实际接收结果作为最终签名兼容证据。206 含被动 Billing SDK 的制品只保留历史记录，不用于本次上传。

配套预发布检查：Workers 第二轮完整 **116 文件／943 项**、Admin **88 项**、旧 App 1.0.4／1.0.5 源码合同各 **24 项**和当前 API **8 项**通过。Workers 第一轮一项 PGlite hook 超时及首次兼容运行缺 package config 的失败日志保留，没有提高超时或排除用例。生产备份 `7mb5sy3bszvh` 已完成，界面报告 5.54 GB／未压缩 22.25 GB、提供恢复入口，到期日 2026-12-10；没有恢复演练。

仅将 `admin.app_version.production.google` 的 `store_url` 从 YouTube 改为正式 Card AI 地址，公开接口独立回读一致；仍为 disabled／force=false，原 min `1.0.0` 和 recommended `1.9.0` 未改，不得在校准这些值前直接启用。临时写入执行器已停止。API 和官网候选已在旧版 100%／候选 0% 下验收，尚未执行 `0018` 或普通流量切换；Cloudflare 只支持一个 deployment 中最多两个版本，因此维护候选逐个以 0% 验收，不同时登记三个 0% 版本。Worker 内容校验使用指定版本的 immutable modules 接口；Wrangler dry-run 上传表单先解析真实 JS 模块，再逐字节核对，未用随机 multipart boundary 的整体摘要替代脚本摘要。

本检查点尚未上传 Play AAB 或发布测试轨道。iOS 线上制品未重发；共享购买源码与 StoreKit 2 合同通过不等于已完成新的签名 IPA、真实购买／Restore 或双端实机验收。

## 生产配套发布与 Play 上传阻塞（2026-11-10 12:05）

经用户要求执行前述建议，生产配套已完成；Google Play 尚未上传或发布。以下状态覆盖前文较早检查点中的“未迁移／未切流”，不改写当时的历史事实。

- 认证写维护于 11:50:58 观察生效，11:59:41 回读解除，约 8 分 43 秒。期间旧 API 维护版本随后切为新 API 维护版本，注册／登录／刷新及用户管理写入保持 503，既有读取由对应业务代码继续处理；双 Admin 和 plain API 候选验收后才解除冻结。
- `0018_platform_account_isolation` 于 11:53:42 提交，ledger 为 19 项，checksum `8b90965117b90d4aabd24edae3a92021f4d378ab9588f209f69c7951175302d6`。449 个既有 active iOS 空间均保留原 owner ID，独立后验无缺失或错配，7 个指定触发器均为 origin enabled；14 个已删除 user 登录字段、2 条认证身份及精确候选的 3 条验证码已清理，完成前没有 Android 数据空间。
- 执行器第一次因事务选项语法、第二次因 JSON 参数类型失败，均在迁移 SQL 提交前回滚；分别独立确认目标表与 ledger 不存在后修正执行器。SQL 原文及其批准 checksum 未变。成功提交后的首次只读触发器探针另遇数组参数适配问题，修正为独立标量绑定后再次完成后验；没有把这些失败计为通过或重复执行已提交迁移。
- API 从干净 `main@1e31a65f` 的冻结构建发布，最终 version `c02380d5-32b2-4e63-b8ef-68cbdf909ebe`，deployment `2ac37542-a212-41b1-a7b4-b96b29f6cf09`，100%。原 34 个 binding 描述符及原 17 个 Secret 名称保留，仅增四项 Android 公开变量与一个 Integrity 私钥 Secret，最终 39 bindings／18 Secrets；runtime 与原版一致。只比较 Secret 名称与描述符，未读取原 Secret 明文。
- Pages deployment `727e70d3-385b-4f0f-9287-217248f75c27` 为 production／success，来源同一 `1e31a65f`。`api.tcgcard.fun` 与 `admin.tcgcard.fun` 共 22 个 HTML／JS／CSS 与同一批准构建原始字节一致。候选及迁移后的 17 项基础烟测和资产核验通过；解除维护后，空匿名请求返回正常 422，非法 Android 安装证明返回 401，而非建立业务账号。这些负向请求不等于真实 Google／Play Token 验收。
- 当前 `tcgcard.fun` 使用新 `cardscanfox-web`，没有部署退役营销站。官网 version `fc46ad44-9e93-4da2-97c3-d0bbe760e6ae`／deployment `89055b06-95c4-48de-abd5-84e9b05f461f` 为 100%，来源 `bff82de7`，release ID `d80e3cd4d1d87c2d4e5ed275c8c96e10b0c8941b8787571e5cc324d560e5594a`。原 8 bindings／runtime／`SITE_DATA` 保留；新增删号页与隐私文本已上线，删号页 200／noindex，首页、动态目录与 release manifest 回读正常，无既有路由丢失。动态 `/cards` 不接受测试自加的未知查询参数，最终按正常 URL 验收，未把非法参数请求的 400 当作上线故障。
- 最终只读回查 cron 仍为 `*/5 * * * *`，API 自定义域名 enabled，未执行 triggers deploy。数据库写执行器、只读探针和商店 URL 修复器均已停止。备份仍保留至 2026-12-10，没有恢复演练；没有重发 iOS App、Linux dev、Apple 配置或订阅商品。

用户随后明确确认上传 `207` AAB 并登记新 Upload 公钥。Play 草稿已保存为 `1.0.7 (207) - Internal`，名单为 6 人；上传在本地选文件阶段失败，因为 Chrome 扩展未允许文件网址访问。系统文件选择器的替代操作又因窗口最小化及工具无法可靠核实当前 Chrome 网址而被工具停止。当前没有 AAB 上传成功、Upload 公钥登记或 Internal testing 发布的证据，不得写成已上架；授权保留，待恢复浏览器操作条件后继续同一制品，不上传已退役的 206 包。

待完成：Play 接收与分发签名核验、内部测试发布、从 Play 安装后的真实安装证明／Google 登录／扫描与统计崩溃、iOS 真实购买／Restore，以及客服邮箱处理能力和正式运营资料验收。上述实机、交易和商店验收均未因源码测试、生产迁移或基础烟测自动关闭。
