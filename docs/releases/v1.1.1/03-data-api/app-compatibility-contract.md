# App 1.0.4+ 服务端兼容契约（v1.1.1 设计）

状态：2026-09-28 用户确认兼容方向；本文件定义未来服务端发布的目标契约，**不是已通过的兼容验收**，不授权代码、数据库、版本门禁或远程环境变更。未变化的业务细节沿用 [v1.1.0 契约](../../v1.1.0/03-data-api/contract-changes.md)与[权益契约](../../v1.1.0/03-data-api/entitlement-contract.md)；验证门禁见[兼容验收矩阵](../05-delivery/app-compatibility-acceptance.md)。

## 1. 受支持范围

“向下兼容”指**每次新 App 或配套服务端发布后**，已经实际发布、仍处于支持范围内的旧 App（最早为 `1.0.4`）连接最新服务端，仍能完成该版本原本提供的业务；新版本独有功能不要求旧包获得。兼容同时包括旧请求/响应及错误语义、旧包对同账号共享数据的读取与原有操作、身份隔离、额度和购买权益真值；只返回 HTTP 200、仅能启动、只通过最新客户端测试或以强更替代兼容均不算成立。后续实际发布的客户端版本按平台和构建号登记并进入支持集合；未经产品明确决定及独立迁移/升级验收，不静默把最低受支持版本提高到 `1.0.4` 之上。

| 客户端/环境 | 基线证据与边界 |
|---|---|
| iOS production `1.0.4 (161)` | [既有交付记录](../../v1.1.0/05-delivery/VERIFICATION.md)记载签名 IPA SHA-256 为 `bf58e164f39d62caae4895603f2553219980eef2ebf5097c5043bb9625ad6d32`，2026-09-23 上传时返回 processing；2026-09-28 [美国区 App Store 页面](https://apps.apple.com/us/app/card-ai-tcg-card-scanner/id6793017224)列出 1.0.4。实际 1.0.4 安装包对当前 prod 的登录态完整业务矩阵尚未执行。历史产物摘要不等于本机现在能取到该 IPA。 |
| Android `1.0.4+161` 源码 | [pubspec](../../../../apps/flutter-app/pubspec.yaml)和[构建配置](../../../../apps/flutter-app/android/app/build.gradle.kts)提供源码与最低 API 24 边界；尚无与 iOS 同等级、可识别的正式已分发 Android 1.0.4 制品证据。获得签名包、版本/哈希及分发事实前，只能进行源码和测试构建兼容设计，不能宣称已安装 Android 1.0.4 用户通过验收。 |
| 后续发布版本 | 发布时按平台登记 Bundle/包名、营销版本+构建号、源码提交、分发渠道与制品摘要、API origin、最低系统版本及使用的协议差异，并冻结该版本的请求/响应与旧 DTO 解析样本；同名营销版本、不同构建号或两平台不自动视为等价。 |
| 范围外 | `<1.0.4` 的旧 pHash 请求、任意历史旧服务端回滚、iOS `<16.0`、Android API `<24`、Web 扫描。当前 [iOS Podfile](../../../../apps/flutter-app/ios/Podfile)和 App Store 1.0.4 均以 iOS 16.0 为下限；v1.1.0 [归档权益文档](../../v1.1.0/03-data-api/entitlement-contract.md)所写 15.5 是较早历史口径，不与当前版本混用。紧邻发布版本的滚动/回退数据兼容按实际部署方案单独验证，不等于承诺任意旧服务端可回滚。 |

生产 App 的 API origin 由构建配置决定；从 `v1.0.4` tag 源码生成的 `APP_ENV=test` 包可在 dev Linux 预验，但**不是**上述生产签名 IPA，不能代替 prod 安装包验收。`v1.0.4` tag 指向 `77d55c10`；标签只固定源码，不代替制品哈希、App Store 状态或实际设备回读。

## 2. 必须保持的 `/api/v1` 业务契约

| 边界 | 对 1.0.4 客户端的承诺 |
|---|---|
| 配置与版本门禁 | `GET /api/v1/app-config?platform=ios` 与 `?platform=google` 保持 `success/data`、`upgrade_prompt`、`app_store_url` 等 1.0.4 可解析字段及环境隔离；旧客户端所需 `title/message/forced_message` 保留。2026-09-28 prod 只读回读：iOS `latest/min=1.0.4, force_update=true`，Google `upgrade_prompt=null`，均为动态配置快照而非永恒默认值。不得仅为掩盖服务端破坏性变更而提高最低版本；Google 的空提示也不能当作 Android 老包已受强更保护。1.0.4 客户端升级比较忽略 `+161` 等构建号，不能靠同营销版本的构建号变化强制淘汰旧包。 |
| 身份与授权 | 匿名/注册登录、找回密码、Token Refresh、登出、账号删除与当前 session 授权的旧版行为保持；账号/owner 隔离与服务端 Premium grant 必须由可信服务端证据决定，不能因为兼容旧包而接受客户端自报 Premium、UID 或未验证交易。保留 1.0.4 识别的成功包络、401 及各接口既有的 403/404/业务错误语义。 |
| 目录与资产 | 游戏、Search、Set、卡牌详情、价格/历史、汇率及 Folder/Collection/Wishlist 的既有请求路径、分页、字符串 `card_ref`、缺价 `null` 与合法零价等语义不被新字段或新数据库实现改变；创建类操作的 `Idempotency-Key` 与重放/冲突契约继续有效。 |
| 跨版本共享数据 | 新版 App 写入同账号已有业务范围的数据后，旧包仍能读取、展示并执行它原本支持的操作；新字段、枚举、状态、分页和持久化格式不得让旧包解析失败或把服务失败误判为空数据。新版本独有数据可经明确的旧版视图/隔离策略处理，但不得污染旧列表、隐藏或破坏旧包原有资产。 |
| 估值与 Performance | `/rates`、`/portfolio/valuation-history`、`/portfolio/performance`、`/portfolio/items/:item_id/performance` 的旧版可解析字段、Free/Premium 边界及 No Data/错误区别保持；价格、币种和历史口径不因新版本写入或 schema 变化而暗改。 |
| 向量扫描与额度 | 继续接受 1.0.4 的 multipart JPEG + 512 维有限非零 `vector`、业务 `request_id`/`Idempotency-Key` 和 `card_type=0/1`；缺少 `card_type` 时仍按 TCG `0`，可选 `card_number` 不变。保留 reserve、recognize、confirm 的响应字段与 Free 终身 10 次、仅完整 Matched 消费、No Match/技术失败释放、Premium unlimited、超时后同业务 ID 幂等重放及按当前账本回读 Quota。Sports 仍仅影响召回，不擅自把 `object_type` 改为新资产类型。**不承诺恢复旧 pHash `r/g/b` 协议。** |
| 订阅与恢复 | iOS Fresh Purchase、Restore、服务端 verified proof、当前 live session grant、过期/撤销及 `ENTITLEMENT_SYNC_REQUIRED`、`PREMIUM_REQUIRED` 等既有响应保持；不能把仅有本机 UI Premium 视为服务端授权。Android Premium 销售/授权范围仍按 [v1.1.0 待决项](../../v1.1.0/05-delivery/traceability-matrix.md)处理，本契约不自行开启售卖。 |
| 媒体、关联与错误 | 既有分享缩略图、目录图片、受保护扫描图的 URL/鉴权及响应保持可用；`X-Request-ID` 可选，旧客户端不发时由服务端生成，不与业务幂等键混淆。保持客户端可识别的 HTTP/业务错误与超时后不确定提交语义，不为兼容而吞错、绕过鉴权或自动重复提交写请求。 |

未来改动优先只增加**可选**请求字段和客户端可忽略的响应字段，并保留旧字段的类型及语义；新增必填字段、改名、改变 ID 类型、状态码/错误码、额度扣次或权益依据均视为破坏性变更。新增写入格式或枚举状态同样须验证旧包实际读取；旧包不理解的新功能数据必须在服务端提供兼容视图或明确隔离，不能让旧版既有业务报错或丢失原资产。确需不同语义时提供版本化新接口，同时保留 1.0.4 使用的旧路径和授权边界，直至另经产品授权调整支持范围。数据库仅按 PostgreSQL 前向兼容的扩展/收缩方案设计；D1 不作为兼容或回滚路径。客户端报告的版本号可用于运营诊断，**不能**作为权限、安全或购买权益的可信依据。

## 3. 发布及尚未解决的前提

1. 每次候选服务端或新 App 发布前，按[验收矩阵](../05-delivery/app-compatibility-acceptance.md)执行受支持版本冻结合同及受影响模块回归；新 App 写入共享数据时还须执行“新版写入→旧版读取/原有操作”，未改变共享数据时仍须核对旧包原有关键路径。需配套变更时服务端先验后发布新 App。不能只测最新源码，也不以少数设备抽样声称所有历史包均已实测。
2. prod 只能在获得相应授权后执行账号写入、真实 Scan/购买或运营配置更改；只读健康检查与未授权 401 不证明登录态兼容。真实旧包对候选服务端的预发布验证须有可达的候选路径；生产正式包若只能访问固定 prod origin，则切流后烟测只能记为发布后证据，不能预填为切流前通过。任何未运行项目列为待验/阻断，不写作通过。
3. 尚需确定 Android 实际分发的基线制品、取得 iOS 1.0.4 生产安装包并跑登录态矩阵；iOS 15.5 旧设备的告知/处置属于独立产品决策。当前文档仅制定规则，没有改变这些运行事实。
