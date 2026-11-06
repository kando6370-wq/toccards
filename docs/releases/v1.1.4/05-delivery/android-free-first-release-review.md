# Android 免费首版与双端隔离评估（2026-11-05）

本文保留实施前的源码评估基线及随后确认的扫描规则。用户已授权后续代码开发，当前实现与验证状态见[双端平台账号实现合同](../03-data-api/platform-accounts.md)；下文“尚无”“未实现”等描述不代表修改后的源码现状。

## 0. 评估说明

- 评估日期：2026-11-05，Asia/Shanghai。
- 源码基线：`codex/dev-andriod@b7a5eba37d2bdc3b4eeedc145b4983ea608fd750`；评估开始时工作区干净。
- 分析模式：围绕 Android 免费首发的跨模块评估，覆盖 Flutter、共享 API、PostgreSQL 归属模型、Admin、官网及 Android 发布配置；不是全项目重构或完整安全审计。
- 用户提供的事实：目前只有 iOS 正式用户。本轮未连接生产数据库确认历史 Android 测试数据或凭证，相关检查仍是条件项。
- 本轮只归档文档、阅读源码和已有测试、核对官方资料；没有修改业务代码、Schema、配置或原始输入，没有运行测试、构建、迁移、部署或商店提交。
- 结论标记：**代码明确体现**表示有直接实现证据；**根据代码推断**表示影响由多个实现点推导；**待确认**表示缺少产品细节、正式产物或外部环境证据。
- 下文“阻塞”表示交付本次 PRD 前必须解决，不表示现有 iOS 生产系统已经发生故障。

### 0.1 归档输入及优先级

| 输入 | 归档位置 | 使用方式 |
|---|---|---|
| 2026-11-03 技术方案原件 | [Android-iOS双端数据隔离方案.md](../00-product/Android-iOS双端数据隔离方案.md) | 历史技术建议；不代表已批准的数据模型或已实现能力 |
| 2026-11-05 产品 PRD v0.3 | [Card_AI_Android_Free_First_Release_Incremental_PRD-3.md](../00-product/Card_AI_Android_Free_First_Release_Incremental_PRD-3.md) | 本次产品需求依据；优先于旧方案，扫描规则按下述用户最新澄清执行 |
| 本文 | 当前文件 | 当前源码差距、待补规则和实施建议；不替代产品原件 |

两份文件从 `D:/Downloads/` 原样复制，原文件保留。归档后与原文件 SHA-256 分别一致：

```text
Android-iOS双端数据隔离方案.md
37b55cc74492361ac08f51dbad82ca16ba1f442eaf076453ddb96e30fa395ed8

Card_AI_Android_Free_First_Release_Incremental_PRD-3.md
b8b12c121c15d4bafd42baa7b48b2cbb71e3fe96053ee2e546172d609ad1b6ff
```

附带文档是本轮评估对象，其中的实施步骤、生产操作和验收要求没有被当作执行授权。

### 0.2 扫描规则澄清（2026-11-05）

用户在评估后明确：Android 的扫描业务逻辑与当前 iOS 一致，只取消订阅用户校验。结合已确定的 Android 免费要求，执行口径为：

- 识别、活动扫描队列、收藏、删除、失败重试、处理后补扫及页面退出行为沿用当前 iOS；同时最多 10 张活动卡牌的既有限制保留。
- Android 不等待或校验 Apple 订阅权益，不应用 iOS 累计免费扫描 10 次额度；不伪造 Premium，不新增日／周／月额度。
- 不增加“整批全部收藏或删除后才能继续”的限制，不新增批次实体、批次持久化、跨设备扫描恢复或服务端批次状态机。
- 双端数据空间、扫描记录归属、游客迁移、账号切换缓存隔离和既有幂等／防重复边界仍然有效。

本澄清优先于 PRD 2.2 第 3 项及 A03／A04 中会被理解为新增整批约束的描述。原 PRD 保持归档字节不变；此前评估将现有滚动队列列为差距的 B06 已撤回，相关实现和验收建议同步修正。扫描生命周期不再是需要产品补充的新规则。

## 1. 业务总览与结论

产品方向可以实施，但需要一次贯穿账号、数据归属、权益与删号的共享后端改造。当前 Android 工程能编译，并不意味着已经满足免费首发；隐藏 Apple 按钮和订阅页也不足以满足这份 PRD。

目标闭环是：用户在 Android 游客使用或验证共享身份 → 开通有效 Android 平台账号及空数据空间 → 免费访问当前端功能 → 按现有 iOS 流程扫描、处理结果并形成本端资产 → 同端重登恢复 → 本端删号撤销本端全部凭证并处理关联数据 → 再次使用需重新注册新平台账号。iOS 原数据和 Apple 购买流程在整个过程中继续有效。

### 1.1 已确定事项，不再重复要求产品决策

- 共享基础登录身份，平台账号状态、业务数据、权益分别管理；不拆物理数据库。
- Android 首次开通从空业务空间开始；公共卡库和公共价格可共用。
- Android 首版免费，不伪造 Premium，不新增日／周／月扫描额度，不新增 Google Billing 或广告。
- Android 扫描沿用当前 iOS 业务流程，只取消订阅校验及对应的累计免费扫描额度限制，不新增批次机制。
- Android 移除 Apple 登录、购买、Restore 和试用入口；iOS 保留原规则。
- Delete Account 删除当前平台账号及关联数据；另一端保留；删后重新注册，不是直接登录空账号。
- 不新增全账号删除按钮、数据导出、AI Grade 或跨端迁移。
- Google Play 是组织账号；不把面向特定新个人账号的测试要求直接套用到本项目。

### 1.2 旧方案与新版 PRD 的冲突处理

| 旧方案内容 | 本次采用的规则 | 原因 |
|---|---|---|
| 账号 active/disabled/deleted 可作为共享状态 | 平台账号有效／已删除状态分别管理；全局安全封禁另行明确 | PRD 3.1、3.4 已明确两端账号生命周期独立 |
| 建议“删除当前平台数据”和“删除整个账号”两个动作 | 保留 Delete Account，仅删除当前平台账号，不增加第二按钮 | PRD 3.4 明确覆盖旧建议 |
| 建议新增当前平台／全账号导出 | 本期不新增导出 | PRD 已排除新业务能力 |
| 历史正式数据统一归 iOS | 正式 iOS 数据保留；先核对是否存在有证据的 Android 测试混入 | PRD 3.6 加入了条件核查，不能依据最近扫描平台猜测拆分 |
| iOS 数据空间 ID 可沿用 user.id | 只保留为待验证的技术选项，不能成为永久回退规则 | 删后重注册要求新平台关系及新空间，不能复活原 owner 历史 |
| Play Integrity 推荐项 | 可信平台会话必须实现，具体应用证明机制由研发设计 | PRD 不指定必须新增某一 SDK |

原件中上述旧建议和旧文档入口保持不改；后续实现以用户最新澄清、新版 PRD 和批准的技术合同为准。

## 2. 用户角色、权限与数据范围

| 身份／角色 | 目标范围 | 当前差距 |
|---|---|---|
| Android 游客 | Android 匿名空间、免费功能和当前扫描队列 | 匿名 owner 当前按 device_id 复用；平台没有绑定为鉴权边界 |
| Android 注册用户 | 共享身份下的有效 Android 平台账号及对应空间 | 正式 session 当前直接指向 user，没有平台账号层 |
| iOS 游客／注册用户 | 原 iOS 空间及原免费／Apple 权益规则 | 迁移需保留原 owner、旧客户端响应和购买归属 |
| 客服／Admin | 查看明确平台，按授权操作对应平台账号和数据 | 目前平台取最近扫描上报值，禁用操作作用于共享 user |
| 外部删号申请处理人员 | 核验身份和申请平台，执行与 App 相同的本端删除 | 尚无完整公开入口及平台删除操作闭环 |

共享身份不意味着共享所有管理动作。密码重置修改共享凭据，两端登录密码随之变化；本端删号不能把共享身份置为 deleted。全局安全封禁是否同时撤销两端会话，需要与平台停用明确区分，避免把普通客服操作做成跨端失效。

## 3. 核心业务流程与异常路径

### 3.1 登录、首次开通及重新注册

当前邮箱登录和 OAuth 最终创建 user owner 的 session，无法表达“身份验证成功，但当前平台尚未开通／已经删除”。需要补齐以下状态转换，而不是把所有情况都返回成功 session：

| 当前状态 | 目标行为 |
|---|---|
| 基础身份不存在 | 沿用经验证的新用户注册，建立当前平台账号及空空间 |
| 基础身份存在，当前平台从未开通 | 验证身份后开通当前端；不能复制另一端资产 |
| 当前平台账号有效 | 登录原平台空间 |
| 当前平台账号已删除 | 普通邮箱登录不得自动创建；明确进入重新注册；Google 合一入口按新用户流程完成注册 |
| 当前平台删除中／部分失败 | 不允许另一个请求继续写入待删空间；重试沿用同一目标，不能扩大到另一端 |

**尚需补充的交互细节**：首次跨端开通和删后重新注册分别经过哪些现有注册页面、如何提示“身份存在但本端账号已删除”；共享身份已有密码时重新注册是否沿用原密码。不能为开通 Android 而悄悄重设 iOS 共享密码。

### 3.2 游客注册与登录已有账号

当前已有游客资产迁移实现，但目标是 user owner，不是当前平台空间；新账号迁移、登录已有账号、手动 `/migrate-assets` 必须统一校验来源与目标平台。已有有效本端账号登录时，PRD 没有批准静默合并；游客收藏、未处理扫描的保留与告知仍须补齐。

### 3.3 扫描沿用当前 iOS 流程

**代码明确体现**：当前是页面内最多 10 项的滚动队列。收藏单项后移除该队列项并重新开相机，队列有空位即可按既有逻辑继续扫描；失败、重试、删除和页面退出使用现有流程。这些行为符合用户最新澄清，不作为待修复缺陷。

Android 保留上述队列与识别／确认逻辑，仅按免费策略取消订阅权益查询、付费拦截和累计免费扫描额度限制。服务端继续保证当前端 owner、请求幂等和确认写入，不因取消订阅校验而取消业务鉴权或防重复。

本期不新增批次生命周期设计、批次持久化、跨设备扫描恢复或批次关闭接口。平台隔离改造只改变扫描数据的可信归属，不借此重做扫描交互。

### 3.4 删除及再注册

删除目标需覆盖平台账号、业务数据、会话、刷新凭证及相关存储，并区分已完成、处理中和失败。删除与扫描上传／确认、登录刷新、游客迁移并发时，需要确保不会在删后重新写回旧空间。

iOS 旧版仍调用 V1 Delete Account。共享 user 保留后，服务端不能仅按 user.active 让已删 iOS 会话继续有效，也不能在重新注册时把旧凭证重新映射到新空间。合法购买／财务记录和现有 iOS 订阅处理按原合同保留，不等于保留已删除的用户资产；iOS 删后新注册账号能否及如何 Restore 旧购买，需要专项核对现有删号合同，不能由数据空间迁移自行改义。

## 4. 核心数据实体与迁移边界

| 对象 | 当前实现 | 本次需要表达的业务含义 |
|---|---|---|
| user / auth_identity | 邮箱、密码、OAuth identity、共享 user 状态 | 共用身份验证；与本端账号有效性分离 |
| 平台账号／数据空间 | 尚无对应完整边界 | user 与 platform 的账号生命周期、当前空间、删后新一代空间 |
| session / JWT | owner_type、owner_id、session_id | 服务端固化身份、平台账号与空间；刷新继承，不能接受业务请求改端 |
| Folder / Item / Wishlist / Preference | owner_type + owner_id | 所有读写删和唯一约束均以可信当前空间为归属 |
| collection_item_event | owner 资产历史 | Performance、估值与数量按本端历史计算 |
| scan_record / scan_quota_request | owner + 请求／session；platform 是上报元数据 | 本端扫描记录、Android 免费策略与既有幂等；iOS 原累计额度独立保留 |
| Apple purchase chain / entitlement / session grant | 原 owner、购买链、session grant | 仅 iOS 授权，保留原购买、通知、退款及 Restore 关系 |
| 扫描图片对象 | R2 key 和 metadata 含 owner 与 scanId | 与平台删除、必要保留及去关联规则一致 |

不建议为本需求拆两个物理数据库。数据空间设计要审计主键、唯一键、外键、锁键、缓存键、Admin join 和购买链引用，不能只给 SELECT 增加平台条件。

迁移采用 PostgreSQL 增量 migration，不恢复 D1、不改历史迁移。可评估初始 iOS 空间沿用历史 owner 以减少资产重写，但必须有明确映射和账号代际：删后新注册不得重新指向旧空间。历史会话的 iOS 映射应落库、可追溯，并验证已删除和已撤销状态，不能长期把任意“缺平台”请求当作有效 iOS 账号。

Android 尚未放行前可以验证兼容部署回退；Android 已写入独立资产后，回退到只认识共享 user 的旧后端会有串端风险。回退方案必须保留隔离，或暂停 Android 新入口并拒绝其凭证；不能仅凭“旧版本健康检查正常”恢复旧服务。

## 5. 问题清单与业务规则差距

| 编号／级别 | 当前证据及问题 | 建议与关闭条件 |
|---|---|---|
| B01 阻塞：平台会话与账号生命周期 | `owner-auth.ts` 仅区分 anonymous／user 两类 owner，没有平台账号或空间边界；正式登录无平台绑定，匿名 platform 只是 installation 元数据。同一正式身份会访问同一资产 | 先批准基础身份／平台账号／空间／session 合同，贯穿创建、登录、refresh、鉴权和所有 owner 查询；跨端资源 ID、伪造平台、旧凭证均不能越界。见 E01–E03 |
| B02 阻塞：本端删除和重新注册 | 正式删号将共享 user 置 deleted 并撤销全部 owner session，却不清理正式业务数据。OAuth identity 仍指向 deleted user；另一端身份保留时，现注册逻辑也会因邮箱已存在而拒绝 | 删除以平台账号为目标，补全关联数据及会话处理；注册区分基础身份和平台开通；Google 再注册建立新空间而非复活旧空间。覆盖仍有另一端账号和两端均已删除两种情况。见 E04–E06 |
| B03 阻塞：隐私与实际删除冲突 | API 隐私页明确扫描记录／图片无固定到期日且删号不删除；官网则写临时处理、按需要保留及删除／去标识化。两份政策也不是同一具体合同 | 列出真实存储、识别方、SDK、保留理由及期限、删除／去关联方式；统一 App 链接、官网、API 法律页及客服执行。不把停用或无限保留直接当作完成 PRD 删除。见 E07、E08 |
| B04 阻塞：Android 免费策略未贯穿前后端 | Flutter 启动门禁、前后台权益刷新、Profile、扫描及 Performance 仍走订阅路径；后端累计 10 次、超过 90 天历史、Performance、文件夹上限仍检查 Premium | 同一平台访问策略贯穿入口和服务端能力；Android 不等待 Apple、不扣 iOS 额度、不写 Apple Premium；iOS 原规则不变。不能只隐藏页面或把 Android 伪装为 premium session。见 E09、E10 |
| B05 阻塞：Apple 购买边界 | 购买／Restore 接口认证 owner 后进入 Apple 处理，缺少当前平台为 iOS 的门禁 | Android 会话不能绑定／授予 Apple 购买链或 session grant；通知、退款和 Restore 保留 iOS 归属，旧购买不可因 owner 改义丢失。见 E11 |
| B06 已撤回：新增批次机制 | 用户已明确扫描沿用当前 iOS；现有最多 10 项滚动队列、处理后补扫及页面退出行为不是本期缺陷 | 不新增批次机制；Android 移除订阅／累计额度校验的工作并入 B04，按现有 iOS 流程做回归。见 0.2、E12、E13 |
| B07 高：游客与本地偏好 | 游客迁移直接把 owner 改为 user；金额隐藏开关使用安装级键 `portfolio.amount_hidden`，并有本地 override | 迁移限定同平台目标，幂等且不重复；退出／换账号／删号时清理或隔离本地用户态，迟到响应不得覆盖新账号；偏好按平台账号／空间保存。见 E14、E15 |
| B08 高：Android 登录尚未闭环 | Google 初始化无平台分支，固定 iOS clientId、serverClientId 为空；后端只接受一个 GOOGLE_CLIENT_ID audience。Android Firebase 缺少配置／Gradle 接入证据，初始化失败仅 debugPrint 后禁用 | Android 包名、OAuth Web/Android client、实际签名指纹、服务端 audience 配套验收，保留 iOS 原 audience。分别用本地 release 和 Play 轨道安装验证登录。Firebase 是否启用以正式包实测为准，不断言 Google 登录已必然失败。见 E16、E17 |
| B09 高：照片权限及平台 UI | Manifest 声明广泛照片／旧存储权限，Gallery 前主动申请；Apple 登录 UI 仍显示，原生实现会对非 iOS/macOS 抛 unavailable | Android 走系统选图，按支持 API 和插件实际回退核对最终权限；移除 Apple UI 及失败回退入口，加入平台隔离说明。保留 iOS 路径，验证小屏、键盘、返回及权限取消。见 E18、E19 |
| B10 高：Admin 与外部删除申请 | Admin 用最近 scan_record.platform 推断用户平台，禁用共享 user；官网 footer 无 Account Setup，现 privacy 页面不构成 PRD 的完整申请流程 | 最小补齐平台账号展示和操作目标；邮件申请复用同一平台删除能力，核验身份、平台及处理结果。使用真实邮箱和期限，不新建 PRD 未要求的表单系统。见 E20、E08 |
| B11 高：正式发布证据不足 | 已有 Debug APK 编译证据，仓库未见 Android AAB 构建与验签发布流程；自定义 ONNX AAR 的 native .so 尚无最终 16 KB 验证 | 正式 AAB 核对签名、包名、versionCode、API 36、ABI／16 KB、最终权限、APP_ENV 与 URL；经 Play 测试轨道验证扫描／OCR／登录。仓库内本地签名文件被忽略且未跟踪，不能宣称密钥泄漏。见 E21、E22 |
| B12 上线前：功能范围及统计口径 | “iOS 已实现功能”未固定对应正式 App、源码提交或页面列表；扫描已明确沿用当前 iOS，其他功能需列清单。统计已有 OS 维度，但 Android Firebase、data space 与免费收入路径未验收 | 建立本次纳入功能矩阵；当前 iOS 已有的扫描操作沿用，包括其实际提供的 Add All，不借“批量收藏”字样另加新能力。平台统计沿用已有 OS 字段并补必要空间语义，Android 不产生试用／收入假事件。见 E12、E17、E23 |

### 5.1 已有正向基础

- 仍使用 Flutter 共用实现，Android 包名为 `com.cardai.tcg`，minSdk 为 24；正式网络安全配置默认禁止明文，测试配置独立。
- 2026-11-05 安全升级记录显示 Flutter 3.47.9 默认 compile／target SDK 36，AGP、Gradle、NDK 已配套升级；本轮没有重新构建验证最终 release manifest。
- App 配置已有 `production.google` 独立商店 URL 及版本门禁，Android 请求用 `platform=google`；正式 Play 页面可用后应正确配置评分、分享及升级目标。
- 统计事件已有操作系统维度，系统分享已有跨平台实现，均应复用现有能力，不重建一套框架。
- 现有 Google／Apple 身份解析校验 provider token 和已验证邮箱。不能仅因不同 Provider 使用同邮箱，就声称当前代码只相信客户端邮箱文本；是否绑定共享身份仍沿用已验证的现有规则。

### 5.2 扫描限制及计算规则

| 规则 | Android 目标 | iOS 目标 |
|---|---|---|
| 累计免费扫描额度 | 不应用 iOS 累计 10 次，不新增日／周／月额度 | 保留原 FREE_SCAN_LIMIT 与预留／消费／补偿逻辑 |
| 活动扫描队列 | 与当前 iOS 一致，最多 10 项，收藏／删除后按既有逻辑补扫；失败和重试行为不变 | 本次不改变原队列／额度交互 |
| Performance、估值和数量 | 只依据当前 Android 空间资产及历史事件计算 | 原 iOS 空间资产和历史事件继续可读 |
| 免费访问权 | 来自 Android 服务端策略 | 来自原免费／Apple entitlement |

技术并发控制、幂等、失败重试及必要防刷与“免费”并不冲突，但不能把它们变成 PRD 未批准的新的累计次数或付费门禁。

## 6. 影响面、实施顺序与验收边界

### 6.1 建议顺序

1. **冻结合同**：补齐第 9 节细节，明确功能基线、身份与平台账号状态、Android 免费策略、删除与保留清单。扫描按 0.2 的已确认规则执行，不再重新设计生命周期。形成技术设计后再写 migration。
2. **服务端先建立边界**：增量 schema、历史 iOS 映射、session 固化、所有读写删及 Apple 授权；同时修改 Admin 与客服目标选择。Android 入口尚未放行。
3. **客户端接入**：登录／重新注册状态、Android 免费策略、复用现有扫描流程、缓存、Apple 入口、Photo Picker 与说明。共享代码逐平台验证。
4. **受控环境验证**：PostgreSQL 迁移回放、删除重试与并发、同身份双端、游客、跨端资源 ID，以及现有 iOS 正式制品和购买恢复。源码合同只能作为一类证据。
5. **发布准备**：正式 AAB、Play 轨道、隐私和 Account Setup、Data safety、真实 SDK 链路、商店 URL。组织账号验证、素材和提交流程独立管理。
6. **分阶段上线**：按既有流程备份、迁移、API／双 Admin 发布，验证旧 iOS 后再放行 Android。Android 有数据后回退仍必须维持隔离。

Linux dev、Cloudflare prod API、两个生产 Admin 入口、Marketing 及移动端商店是不同发布目标。发布其中一个不代表其他目标已发布或验收。

### 6.2 对 A01–A23 的补充用例

以下是建议补充的验收条件，均尚未执行。A03／A04 按 0.2 澄清执行，不采用原件中的新增整批约束：

| 补充场景 | 必须证明的意图 |
|---|---|
| 活动队列达到 10 项，再收藏或删除 1 项 | 队列上限及提示沿用当前 iOS；腾出空位后可按既有逻辑补扫，不要求清空全部队列 |
| Android 游客和注册用户累计扫描超过 10 次 | 不触发订阅校验、付费页或累计免费额度拦截；同时最多 10 项的现有队列限制仍有效 |
| 收藏失败、识别失败重试、返回及重进扫描页 | 行为与当前 iOS 一致；本期不增加跨重启／设备恢复机制 |
| 一端删除后仍保留另一端，再用邮箱／Google 注册；两端均删除后再注册 | 共享身份唯一约束不阻塞，旧空间和旧 token 不复活，另一端不受影响 |
| 删号并发扫描上传、confirm、refresh、游客迁移；删除失败重试 | 不产生删后写回，不扩删另一端，不把不确定结果报成功 |
| 游客注册时共享基础身份已有另一端账号 | 游客只迁入本端新平台账号，密码与另一端资产不被覆盖 |
| 换账号后的迟到响应、缓存和金额隐藏状态 | 旧账号响应及本地 override 不污染新平台账号 |
| Android 伪造平台／直接调用 Apple 购买或 Restore | 服务端策略拒绝跨端切换和 Apple 授权，不能靠 UI 隐藏关闭 |
| 正式 Play 安装包及 16 KB 环境 | 最终签名、native 推理、OCR、Google 登录、网络及权限真实可用 |
| Android 已产生独立资产后回退服务端 | 不恢复共享 owner 访问、不丢 Android 资产或改变合法 Apple 购买事实 |

### 6.3 本轮验证记录

已完成：原件完整阅读及冲突比对；源码、直接调用方和相关测试静态检查；归档字节一致性校验；文档路径／链接和 diff 检查。

未运行：单元／集成／兼容测试、Flutter 分析、构建、AAB／IPA、真机、OAuth 实际登录、迁移回放、数据库查询、远程部署、生产验收或 Play Console 操作。原因：本轮授权为文档归档与实施前评估，尚未实施任何业务变更。

已有安全升级文档记录 App 全测 **1326 通过／9 失败**，这只是先前基线证据，不是本轮执行结果，也不能写成全量通过；后续实施要区分既有失败与新增失败。

## 7. 术语

| 术语 | 本文含义 |
|---|---|
| 基础身份 | 共用的邮箱／密码／已验证 OAuth 关联，不等同于每端均有有效账号 |
| 平台账号 | 身份在 iOS 或 Android 的独立开通、有效、删除生命周期 |
| 数据空间 | 平台账号当前拥有的业务资产边界；删后新注册不能指回旧空间 |
| owner | 现有业务查询归属，不应在改造后继续混用基础 user 与空间 ID |
| 活动扫描队列 | 当前 iOS 扫描页的最多 10 项队列；Android 沿用处理后补扫等既有行为，不新增批次实体 |
| App Signing／upload key | Play 分发签名与上传签名不同；OAuth 指纹必须按最终安装包核对 |

## 8. 证据索引与官方依据

下面路径相对仓库根目录。行号对应本轮源码基线，后续实现后应以符号及最新代码重新核对。

| 编号 | 位置 | 说明 |
|---|---|---|
| E01 | `apps/workers-api/src/owner-auth.ts:7,37,89`；`apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:52` | session／鉴权仅有现有 owner |
| E02 | `apps/workers-api/src/auth/login.ts:62,117`；`apps/workers-api/src/auth/account-flow.ts:243`；`apps/workers-api/src/auth/anonymous.ts:111,205` | 正式登录、匿名创建与 platform 元数据 |
| E03 | `apps/workers-api/src/portfolio/routes.ts:139`；`apps/workers-api/src/scan/routes.ts:156,163,214` | owner 作用于查询、文件夹、扫描确认写入 |
| E04 | `apps/workers-api/src/auth/account.ts:99,105,143` | 共享 user 删除及全部 owner session 撤销；数据清理范围 |
| E05 | `apps/workers-api/src/auth/register.ts:105,135`；`apps/workers-api/src/auth/account-flow.ts:175`；`apps/workers-api/src/db/postgres/migrations/0000_business_schema.sql:41` | 邮箱注册、已删除身份与 OAuth 唯一约束 |
| E06 | `apps/workers-api/src/auth/session.ts:96,201,226`；`apps/workers-api/src/auth/forgot-password.ts:161` | refresh owner 与共享密码修改 |
| E07 | `apps/workers-api/src/legal/routes.ts:119,123`；`apps/workers-api/src/scan/routes.ts:510,520` | 图片上传、owner metadata 及无固定期限保留声明 |
| E08 | `apps/marketing-web/public/privacy.html:199,399,424`；`apps/marketing-web/public/index.html:704` | 官网保留／删除声明、支持邮箱及缺少 Account Setup 的 footer |
| E09 | `apps/flutter-app/lib/app/router.dart:40`；`apps/flutter-app/lib/features/subscription/startup_subscription_gate.dart:34`；`apps/flutter-app/lib/features/subscription/subscription_entitlement_lifecycle.dart:37`；`apps/flutter-app/lib/features/profile/profile_page.dart:138,228,264` | 全平台启动和订阅入口 |
| E10 | `apps/workers-api/src/scan/quota.ts:4,45`；`apps/workers-api/src/scan/routes.ts:295,333`；`apps/workers-api/src/portfolio/routes.ts:621,659,688,1482` | 扫描累计额度、历史与 Performance／文件夹 Premium 检查 |
| E11 | `apps/workers-api/src/entitlements/routes.ts:101,202,375`；`apps/workers-api/src/entitlements/restore-routes.ts:213,239`；`apps/workers-api/src/entitlements/premium-access.ts:23` | Apple 购买、恢复及 session grant |
| E12 | `apps/flutter-app/lib/features/scan/scan_page.dart:431,439,509,1936,1961,2314` | 内存队列、补扫、已有 Add All 与离开页面 |
| E13 | `apps/workers-api/src/scan/routes.ts:321,637,753,895` | 既有逐次 reserve、pending 与 confirm；Android 免费分流仍需保留幂等及确认边界 |
| E14 | `apps/workers-api/src/auth/guest-migration.ts:52,172`；`apps/workers-api/src/auth/account.ts:230` | 游客 owner 改写及资产迁移入口 |
| E15 | `apps/flutter-app/lib/shared/portfolio/portfolio_providers.dart:58,90`；`apps/flutter-app/lib/features/home/home_controller.dart:731,854`；`apps/flutter-app/lib/features/auth/auth_controller.dart:137,358` | 安装级隐藏金额 override、删除后本地会话处理 |
| E16 | `apps/flutter-app/lib/features/auth/oauth_authorizer.dart:40,86`；`apps/workers-api/src/auth/oauth-provider.ts:26,42` | Apple 原生平台限制、固定 Google 初始化及 audience 校验 |
| E17 | `apps/flutter-app/lib/shared/firebase/app_firebase.dart:17`；`apps/flutter-app/android/app/build.gradle.kts:5` | Firebase 初始化及 Android Gradle 接入缺口 |
| E18 | `apps/flutter-app/android/app/src/main/AndroidManifest.xml:5`；`apps/flutter-app/lib/features/scan/scan_permissions.dart:24`；`apps/flutter-app/lib/features/scan/scan_result_source.dart:201` | 广泛照片权限、前置权限申请与 image_picker |
| E19 | `apps/flutter-app/lib/features/auth/ui/auth_sheet.dart:116,220,412,506`；`apps/flutter-app/test/widget/auth_profile_test.dart:263` | Apple 登录多个展示分支及现有测试 |
| E20 | `apps/workers-api/src/admin/routes.ts:278,366,950` | 扫描平台推断、用户统计及共享 user 管理 |
| E21 | `apps/flutter-app/android/app/build.gradle.kts:12,38,54,78`；`apps/flutter-app/android/.gitignore:13`；`apps/flutter-app/tool/onnxruntime/build_minimal_aar.ps1:33` | 签名条件、SDK、ONNX AAR、签名文件忽略规则 |
| E22 | [技术栈安全升级](../02-architecture/security-stack-upgrade.md) | API 36／NDK／Flutter 构建证据及 9 项原有失败、发布边界 |
| E23 | `apps/flutter-app/lib/shared/analytics/app_analytics.dart:222,283`；`apps/flutter-app/lib/shared/attribution/app_attribution.dart:264`；`apps/flutter-app/lib/features/app_upgrade/app_upgrade_repository.dart:37`；`apps/flutter-app/lib/features/profile/profile_actions.dart:72,99` | 统计 OS 字段、归因限制及商店 URL 使用 |

### 8.1 官方政策与配置资料

核对日期为 2026-11-05。政策、组织账号权限和最终包验收是不同证据，以下不代表 Google 已批准本应用：

| 官方资料 | 对本项目的约束／边界 |
|---|---|
| 账号删除：`https://support.google.com/googleplay/android-developer/answer/13327111?hl=en` | 需有 App 内与外部网页申请路径；邮件可作为申请渠道，但页面要清楚可访问、能实际请求删除账号及相关数据；必要保留需告知，停用／冻结不替代删除 |
| 照片／视频：`https://support.google.com/googleplay/android-developer/answer/16558241?hl=en` | 对选择性照片访问优先采用系统选择器；当前 PRD 也明确不为选图申请广泛相册权限 |
| target API：`https://support.google.com/googleplay/android-developer/answer/11926878?hl=en` | 当前新应用要求 API 36；仓库工具链已有对应基础，最终以正式 AAB／Console 验证 |
| 16 KB：`https://developer.android.com/guide/practices/page-sizes` | 需检查最终 native 库对齐并在 16 KB 环境运行；NDK 或 AGP 版本达标不自动证明已有第三方／自编 AAR 达标。期限按实际提交时官方页面与 Console 执行，不套用旧日期 |
| Google Sign-In Android：`https://pub.dev/packages/google_sign_in_android` | 按包名与签名证书配置；不依赖 google-services 配置时需正确提供 serverClientId，并与服务端 audience 匹配 |
| Firebase Flutter：`https://firebase.google.com/docs/flutter/setup` | Android 对应 Firebase 应用／初始化配置需真实接入，源码 catch 后返回 null 不证明已正常采集 |

共享基础身份被另一端保留时，页面必须说明 Android 平台账号确实被删除，以及哪些身份／财务记录为何保留。本轮无法代替 Google 对这种具体实现的审核结论；不能仅因产品规定“本端删除”就直接填写全部数据已删除。

## 9. 待补齐的问题

无需重新讨论已经确定的双端隔离、免费、删号范围或全账号删除按钮。建议在开始业务实现前补齐以下细节：

| 问题 | 需要的明确结果 | 负责方 |
|---|---|---|
| “iOS 已实现功能”的基线是什么 | 扫描已明确沿用当前 iOS；其他功能明确正式 App 版本／源码基线及页面清单，区分已开发未上架增量 | 产品、研发、测试 |
| 首次开通与删后重新注册怎样呈现 | 现有页面与提示、邮箱验证方式、共享密码沿用规则；Google 合一入口完成何种新用户步骤 | 产品、客户端、认证研发 |
| 游客进入已有有效本端账号 | 收藏与未处理扫描的保留／放弃方式及明确提示；不自动增加静默合并 | 产品、客户端 |
| 删除与保留的真实清单 | 业务表、R2、日志、备份、SDK 标识的删除／去关联和期限；另一端有效／全部删除时共享身份如何保留或清理；iOS 删后重新注册的 Restore 按原合同专项核对 | 后端、隐私负责人、运维 |
| 平台停用和全局安全封禁 | 哪些动作只限本端，哪些依法／依安全需要影响共享身份；Admin 文案和权限 | 产品、后台、运营 |
| Android 正式配置和人工删号准备 | Play 签名／OAuth／Firebase 组合，真实支持邮箱、处理时间、身份核验与操作负责人；应用证明失败策略由研发给出 | 发布、后端、运营 |

这些缺口可以形成小范围 PRD 补充和技术合同，不需要重写整套产品，也不构成本轮已经实施或可以直接上架的结论。
