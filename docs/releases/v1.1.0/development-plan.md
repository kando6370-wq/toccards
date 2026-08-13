# v1.1.0 开发计划

## 1. 依据与优先级

本计划以三份 v1.1 PRD 定义业务目标和验收行为，以 2026-08-12 `dev` 代码、迁移和运行配置证明当前完成度，并吸收《TCG v1.1 PRD 综合评审》的 P0/P1 结论。App 业务不得因为当前代码尚未实现而缩减、改写或降级 PRD；发现不一致时必须记录为待实现差距并按 PRD 收口。

发生冲突时按以下顺序裁决：

1. App 页面、交互、异常和验收行为以 [`TCG Card App v1.1 PRD`](00-product/TCG_Card_App_v1.1_PRD.md) 为主。
2. Apple ownership、可信证据、生命周期和跨设备规则以 [`Apple Subscription & Premium 权益统一方案`](00-product/Apple_Subscription_Premium_%E6%9D%83%E7%9B%8A%E7%BB%9F%E4%B8%80%E6%96%B9%E6%A1%88.md) 为上位规则。
3. 订单、通知和 Admin 目标行为以 [`Admin PRD`](00-product/TCG_Admin_%E8%AE%A2%E5%8D%95%E7%BB%9F%E8%AE%A1%E4%B8%8E%E8%8B%B9%E6%9E%9C%E9%80%9A%E7%9F%A5%E6%B6%88%E6%81%AF_PRD_V1.1_%E8%AE%A2%E9%98%85%E7%9C%9F%E5%80%BC%E6%94%B6%E5%8F%A3%E7%89%88.md) 为主。
4. 当前代码只证明已实现状态。代码与 PRD 不一致时列为开发差距，不以现状削减 PRD。

原始 PRD 保持只读。实现契约、迁移、验收结果和发布边界维护在本目录。每个业务增量必须在同一开发检查点同步记录实现状态、契约或迁移影响、验证结果和未完成边界；文档未同步或必要验证未执行时，该项不得标记为完成。

PRD 条款、实现文件、数据库迁移、自动化测试及外部验收边界统一维护在 [`traceability-matrix.md`](traceability-matrix.md)。

## 2. 当前基线

| 范围 | 当前代码事实 | v1.1 差距 |
|---|---|---|
| App 订阅体验 | 已有 Subscription Page、Paywall、Success、StoreKit 2 Fresh Purchase verifier、Secure Storage 补偿队列、本机 Restore 结果分流、App Attest 原生桥接，以及 Performance/1Y/Folder/Scan Waiting 的来源动作恢复；Home/Search/Collection/Profile 顶部入口和 Profile Banner 已按 PRD 接入完整 Subscription Page；商品局部缺失、15 秒重载、Purchase 状态、首次/冷启动 Premium 三态分流、ATT/Singular 启动顺序及 v1.1 PRD 视觉 Golden 已实现 | 前后台完整矩阵、Singular 正式 Key 及 iOS 真机验收不完整 |
| Premium 真值 | 鉴权保留可信 `session_id`；Fresh Purchase 与 Restore 均已有独立 Apple 证据、session proof 和 session grant 写链；App 使用 Unknown/Free/Premium 三态及已验证缓存；Scan、Folder、Performance、Home 与 Card Detail 普通历史 1Y 已接入统一授权 | 三态仍缺 iOS 真机前后台与过期续订矩阵验收 |
| Billing 数据 | `0025` 至 `0033` 已覆盖购买链、交易、session grant、原始通知 inbox、生命周期、订单业务事实及 USD 汇率快照；`0000` 至 `0033` 已通过隔离空库顺序执行和自动化完整迁移链测试；`0025` 至 `0033` 也已在远程 dev 只读导出的本地副本连续执行并通过完整性与行数不变量检查 | Wrangler 只读核对确认远程 dev/prod 均待执行 `0025` 至 `0033`；缺 Sandbox/TestFlight 实单验收 |
| Scan | 服务端已有终身 10 次真源、request ID 原子预占、逐张结算/返还、60 秒租约、响应重放和多设备并发保护；Flutter 已使用服务端 quota 真值，完成 Waiting、Quota=0 Paywall、Done 公式、服务端确认 Unlimited 后自动递补、Scan Pro 完整订阅来源返回及 Processing 删除后的后台结算 | Sandbox/TestFlight 与真实并发、超时规模验收尚未完成 |
| Folder | 已有 Folder CRUD；Free 总数最多 2 个（含默认 Folder），服务端按当前 session grant 判断，并以单条条件 INSERT 防止并发越限；购买或恢复成功后在原 Folder Sheet 仍有效时打开 Create Folder Modal；服务端并发上限拒绝会先刷新 Folder List 再进入 Paywall，普通失败或权益同步中保留名称输入 | `0030`/相关授权迁移未执行；仍缺 Sandbox/TestFlight 多设备人工验收 |
| Performance | 已有 Home 与 Card Detail 独立服务端接口、六档自然范围、Purchase/Quantity/Folder Move 历史、迁移 baseline、Premium session grant 校验及 App 完整状态渲染；`0031` 已在 dev 真实历史数据的本地副本验证不伪造历史 | dev 最大 owner 仅 24 条 Event、12 个现存 Item，只能证明当前小样本；仍缺重度收藏用户规模、Cloudflare 端到端、Sandbox/TestFlight 验收 |
| Admin | 订单 13 列、11 项组合筛选、动态国家/SKU、10,000 行以内 XLSX 全量导出及 inbox 通知排障视图已实现；完整 Decoded Payload 仅授权用户打开详情时加载，默认不返回 `signedPayload`，复制由用户主动触发 | dev 订单表为空，无法证明有数据及 10,000 行导出时的 3 秒普通查询目标；Sandbox/TestFlight 人工验收尚未完成 |
| 归因与收入 | 已有 Firebase/Mixpanel 基础设施；首次安装仅在 ATT `notDetermined` 时请求，随后按最终状态初始化 Singular；冷启动不重复请求，回前台只读同步；Key 缺失或 SDK 失败不阻断。Apple verified 新 Purchase 使用 JWS `price/currency` 上报 Firebase 标准 Purchase，并按 `transaction_id` 持久化去重、失败保留重试 | 缺 Singular 正式 Key、iOS 真机归因及 Sandbox/TestFlight Revenue 验收 |

代码中只有 Scan 使用时触发的相机/相册权限，没有 PRD 所述“首次安装网络授权流程”。本实现选择遵守同一 PRD 的“不得新增无业务需要权限”：不伪造网络授权弹窗，ATT 排在现有 Splash/启动预加载之后、Onboarding 之前。ATT/Singular SDK、用途说明、首次安装请求、冷启动不重复请求、回前台只同步及非阻断降级均已完成；正式 Key 通过构建参数注入，仍待产品账号配置和 iOS 真机验证。

产品待决项：评审 P1-B 要求冻结 Lifetime 在 StoreKit 与服务端均不可用时的最长本地兜底时间。最新 App PRD 仅定义“可临时保持 Premium”，没有给出可测试期限；当前代码按该 PRD 持续使用已验证 Lifetime 缓存。该期限会改变离线用户权益，开发不得自行设定，需产品确认后再实现超时转 Unknown 及对应验收矩阵。

## 3. 阶段与验收门槛

### 当前开发检查点（2026-08-13）

- 已实现：鉴权保留 live `session_id`、session grant 表与统一查询、Fresh Purchase challenge、StoreKit 2 JWS 官方验签写链、可恢复处理租约、请求幂等/证据摘要审计和新旧生命周期竞态保护；Flutter Fresh Purchase 已尽力申请 challenge、透传 `applicationUserName`，并在返回本机即时 Premium 前尽力将 JWS 持久化到 session 隔离的 Secure Storage 补偿队列，再于后台同步。安全存储故障会显式记录诊断，但不把 Apple 本机 verified 交易改判为购买失败。
- App 本机 Restore 已实现：iOS 调用 `AppStore.sync()` 后只读取 Apple verified `Transaction.currentEntitlements`，按配置 SKU 区分 Success/Not Found，配置 SKU 出现 unverified 时进入 Failed；Subscription Page/Paywall/Profile 使用独立 Restore 结果事件，15 秒 Timeout 与 Failed 共用失败 Alert，Success 不进入 Purchase Success，Restore 期间阻断当前容器且拒绝并发操作。
- PRD 验收 110 的重启边界已有直接回归保护：Secure Storage entitlement cache 只序列化 Apple 已验证权益事实，不保存 Paywall、Restore Loading/Failed、Subscription Success、Purchase Pending 或 `blocked_action` 等瞬态 UI/业务恢复状态。字段类型或日期损坏的合法 JSON 会被整体丢弃并进入 Apple 重新验证，不因强制类型转换中断启动、不误判 Free，也不从损坏数据授予 Premium。该定向测试 8 项及实现/测试文件静态分析通过。
- App Premium 已收口为 `Unknown/Free/Premium` 三态：启动先读取本机已验证缓存，再以不触发 Apple 登录提示的 `Transaction.currentEntitlements` 静默刷新；只有用户主动 Restore 才调用 `AppStore.sync()`。自动续订缓存必须存在未过期 `expiresAt` 才可临时判为 Premium，Lifetime 缓存可持续判为 Premium，过期缓存刷新失败保持 Unknown。Home、Card Detail、Folder 和 Scan 的受限动作遇 Unknown 会先主动刷新；仅明确 Free 才进入 Paywall，刷新失败不提交受限请求、不创建 Folder、不切 1Y，也不伪装成 Free。Profile 同样只在明确 Free 时展示升级入口。该逻辑已有缓存、Reader 及 Scan 三分支意图测试，仍待 iOS 真机前后台与续订过期矩阵验证。
- App 根生命周期已在回前台时通过 `Transaction.currentEntitlements` 静默刷新权益，并读取当前 session 已证明购买链的服务端 lifecycle 校正；不调用用户主动 Restore 的 `AppStore.sync()`，也不导航或自动弹 Subscription Page/Paywall。只有同链且不旧于本机 JWS 的 `BILLING_RETRY/EXPIRED/REVOKED` 才剔除对应 entitlement，再用剩余全部 Apple entitlement 重算；服务端 active 不能单独授予，接口不可用不直接降级。确认 Premium 变 Free 后由当前页面监听状态原地锁定，刷新失败保持现有兜底状态。Flutter 校正/API 定向 14 项、Workers 当前 session/环境隔离真实 D1 测试及类型检查已通过；仍待 iOS 真机订阅过期、退款和多 entitlement 矩阵验证。
- StoreKit 静默刷新会遍历全部 verified current entitlements：单条损坏证据不遮蔽其他有效权益，Lifetime 优先于可续订商品；没有 Lifetime 时缓存到期最晚的有效订阅。该选择规则已有纯业务测试，仍待 Sandbox 多 entitlement 实单顺序验收。
- 首次完成 Onboarding 后和后续完整冷启动已接入一次性启动门禁：权益刷新最长 15 秒，明确 Free 展示完整 Subscription Page，并分别保留 `source=onboarding` 或 `source=cold_start`；Premium 与 Unknown 进入 Home，Unknown 不伪装成 Free。门禁只存在于根启动流程，App 后台回前台或使用中变 Free 不会自动弹 Subscription Page。ATT/Singular 已排在 Splash/启动预加载结束与 Onboarding 之间；仓库不存在产品所述“现有网络授权”，因此按 PRD 禁止新增无业务需要权限的规则不伪造该步骤。
- Subscription Page 与 Subscription Success 的固定内容已按 App PRD 收口：标题分别为 `Choose Your Plan` 和 `You're Premium!`，两页仅展示四项 Premium Benefits，Wishlist 不作为 Premium；Success 主按钮为 `Start Exploring`，不再增加 `Manage subscription` 第二出口。
- Home/Search/Collection/Profile 顶部订阅入口已按 App PRD 补齐：仅明确 Free 时显示 42px Premium 图标，Unknown/Premium 隐藏；Scan 和二级页面不挂载。四个入口均打开完整 Subscription Page，并携带各自 `source` 与 `entry_source=top_subscription_entry`；Profile Banner 使用 `source=profile&entry_source=profile_banner`。Purchase Success 经 Success Page 的 `Start Exploring` 逐层返回原一级页面实例，Restore Success/外部解锁直接关闭订阅页，因此可保留输入、Tab、Range、滚动位置和已加载数据；`onboarding/cold_start` 仍按启动门禁进入 Home，Scan 保留原实例返回链。
- 当前入口相关验证：共享三态/URL 契约 3 项、Subscription 商品/Restore/来源返回及法律外链上下文 12 项、Collection 24 项、Profile 相关 3 项和 `flutter analyze` 已通过。Terms/Privacy 使用系统外部应用模式；Full Subscription Page 与 Functional Paywall 的直接 Widget 验收已证明打开外链后原订阅容器、非默认 Plan 选择及来源页面状态均保持。StoreKit Product Loading 已实现首次请求加最多 3 次后台重试，默认间隔 1/3/8 秒并共享 15 秒总 Deadline；同一时刻复用单个请求周期，Deadline 或页面销毁后以周期标识拒绝迟到 StoreKit 结果写回。任一可用 SKU 返回后立即开放真实商品，其余 SKU 保持不可用且不显示 Selected，不伪造价格。全部失败、购买无法启动及普通交易失败分别使用 App PRD 固定文案，自动重试仅限商品读取，不自动重试 Purchase。Search 既有回归已按当前代码与 PRD 收口，23 项全部通过。2026-08-13 最新全量回归为 App 667 项通过、10 项跳过、1 项失败，`subscription_core` 9 项通过；唯一失败仍是既有 App Shell Golden。该基线最初在测试显式加载 `Geist-Regular.ttf` 时生成，历史提交 `369cd7a` 后字体资源与加载逻辑被删除但 Golden 未同步，Flutter 3.44.7 因此以测试占位字体渲染并产生差异。v1.1 App PRD 未变更底部导航，该问题不作为本期业务需求差距；但在产品/视觉确认恢复 Geist 资产或批准新基线前不得覆盖 Golden，Flutter 全量测试仍不得标记为通过。
- Profile Restore Blocking Loading 已有直接 Widget 验收：Restore 期间全页业务点击由 `AbsorbPointer` 吸收，系统返回由 `PopScope` 拦截，并持续显示全屏 Loading 遮罩；点击 Customer Support 不会导航，符合 App PRD 第 99 条。
- Restore proof 代码已实现：iOS `DCAppAttestService` 注册安装级 key，对 Workers 返回且绑定 live session、一次性 nonce、request ID、key ID 和 StoreKit JWS 摘要的 canonical client data 签名；Workers 使用 WebCrypto 验证 Apple 证书链、nonce、App ID、AAGUID、key ID、assertion 与递增 counter，原子消费 challenge 后只为当前 session 写 `source=restore` grant。同 UID 另一 session 盗用与重放已通过真实 Miniflare D1 集成测试拒绝。
- Fresh Purchase 补偿队列错误码已收口：有效 60 秒处理租约返回可重试的 `VERIFICATION_UNAVAILABLE`；证据/idempotency 冲突和较新 lifecycle 覆盖返回终态 `STATE_CONFLICT`。客户端仅保留临时失败，终态冲突移除并继续后续交易，避免永久阻塞队列。
- Notifications V2 已实现原始收件箱、官方 JWS 验签、结构化消费、通知/交易幂等、生命周期乱序保护、5 分钟失败补偿及 Apple Server API 当前状态校正，并通过真实 D1 集成测试。Scan/Folder/Performance 权限已接入；App 的功能卡点使用 typed Paywall success 和页面实例内的最小上下文恢复原动作，不持久化旧动作，Close/Cancelled/Pending/Failed/Restore Not Found 不执行，目标失效时不强制恢复。Subscription 商品只展示 StoreKit 本地化价格，单个 SKU 缺失不阻断其余商品，Yearly 缺失时选中首个可用商品；购买前商品重载共享 15 秒 Deadline，Pending 禁止重复购买和 Restore 但允许关闭，关闭后的迟到 verified 更新只刷新 Premium，不恢复旧成功流。App Attest 尚未在 macOS/Xcode/真机验证，Apple Server API Secret 未配置；`0026` 至 `0029` 已通过隔离空库顺序执行，但尚未应用到常用 local、远程 dev 或 prod。因此阶段 A/B 的代码已形成闭环但发布验收未完成，不能视为 P0 或 v1.1 完成。
- Folder 限制已接入统一授权：服务端仅认可当前 live session grant；Free 总数最多 2 个且包含默认 Folder；条件 INSERT 保证同 owner 多 session 并发不能创建第 3 个。本机 Premium 已验证但 grant 未同步时，客户端只发送状态提示，服务端返回 `ENTITLEMENT_SYNC_REQUIRED` 且不创建。App 在本地明确为 Free 且已有 2 个 Folder 时进入 Functional Paywall；购买或恢复成功且原 Folder Sheet 仍有效时自动打开 Create Folder Modal，非成功结果保持原状态。
- Folder 的服务端并发拒绝反馈已按 App PRD 收口：Create Folder 请求留在弹窗内执行，Saving 时锁定输入、返回和重复保存；成功才关闭。普通失败沿用现有错误反馈并保留名称，`ENTITLEMENT_SYNC_REQUIRED` 保留弹窗并提示 Premium 正在同步；另一设备抢占最后 Free 名额导致 `PREMIUM_REQUIRED` 时，Controller 先刷新 Dashboard/Folders，再关闭 Create Folder、打开 Functional Paywall。Paywall 成功后以原名称重新打开 Create Folder，未成功则不创建。Flutter Collection Controller/Widget 50 项及 Workers 真实 D1 Folder 集成 3 项已通过，仍待真实多设备人工验收。
- Collection Item Folder Move 复用现有单次原子 `PATCH` 保存目标 Folder 与编辑字段，保存中禁止重复提交，API 网络 Deadline 短于 PRD 的 15 秒上限；失败或 Timeout 不更新本地 Item。目标 Folder 已被另一设备删除并返回 `NOT_FOUND` 时，App 会刷新 Card Detail 可选 Folder 及全局 Collection/Home/Search 数据，Item 仍保持服务端 Source Folder；Item 仍存在时保留其他编辑输入并把 Folder 草稿恢复为真实归属，Item 也已失效时退出编辑态。Home Performance 已修正为按 Item 最新 Folder 归属全部可靠历史：Move 后 Source 当前及历史全部移除，Target 从可靠起点获得完整曲线，Quantity、价格映射和 Delete 时点仍按历史 Event 还原。Card Detail Controller 39 项、Controller/Widget 合计 77 项、Workers Item 路由 12 项及 Portfolio 10 文件 57 项已通过。
- Scan Quota 服务端闭环已落地 `0030`：`scan_quota_request` 是额度与幂等唯一真源；Free 识别在 R2/OCR 前以单条条件 INSERT 原子预占，Matched/No Match 消耗，技术失败释放，Premium 不写 Free 消费；60 秒租约支持 Worker 中断接管，完成响应可按相同 session/request ID 重放。Flutter 不再读取或写入本地 Scan Quota，进入页面后首帧拉取服务端 `remaining/unlimited`；Gallery 超额和 Failed Retry 可转 Waiting，单张 quota=0 不留 Item，Waiting 删除/Functional Paywall、Done 唯一公式及按 Queue 顺序自动递补已实现。只有 Waiting 来源的 Paywall typed success 会恢复仍存在的 Waiting；quota=0 且图片未入 Queue 时成功后只返回 Scan。Scan Pro Card 进入完整 Subscription Page，Purchase Success 经 Success Page 返回原 Scan 实例，Restore/外部解锁直接返回，并在有效 Queue 仍有 Waiting 时递补。Processing 删除立即从 UI 和 Processing Count 移除，但保留后台请求观察：最终响应结算 Quota，技术失败无 Quota 时主动刷新，均不重插已删除卡片，并可递补现存 Waiting。`ENTITLEMENT_SYNC_REQUIRED` 保留为独立同步等待状态，只有服务端确认 `unlimited=true` 后才自动提交。代码闭环已完成，Sandbox/TestFlight 与真实并发、超时规模验收仍待完成。
- App PRD 验收 125-128 已形成直接自动化证据：真实 Miniflare D1 测试证明两个 session 并发创建 Folder 只能一个成功且总数保持 2；ATT 测试证明后台恢复只读取状态并同步 Singular，不再次请求授权；Scan Widget 测试分别证明 quota=0 的 Capture 与 Gallery 在 typed Premium success 后只返回原 Scan 页面，`photo`/`library` 调用次数仍为 0，用户必须重新操作。复验结果为 Scan Widget 81 项、Folder D1 集成 3 项、ATT 5 项及 `flutter analyze` 全部通过；这不替代 iOS 真机 ATT、Sandbox/TestFlight 和真实多设备验收。
- App PRD 验收 129-132 已补齐生产规则和直接测试：只有 Waiting 来源的 typed Premium success 会刷新服务端 Quota，并在确认 `unlimited=true` 后按原图重提为 Processing；Restore Not Found 按最新 verified current entitlements 明确归约为 Free，Restore Failed/Timeout 不改变原 Premium 三态；Pending 同时由 Subscription Page 按钮禁用和 Controller 入口守卫阻止重复 Purchase。Scan Waiting 定向测试与 Subscription/Restore 13 项测试已通过；仍需 Sandbox/TestFlight 验证 Apple Pending 最终回调、真实 Restore Not Found/Timeout 及 Waiting 重提链。
- App PRD 验收 133-136 已完成代码核对和直接测试：Apple Pending 状态跨过 16 秒后仍保持 Pending，不套用商品读取/Restore 的 15 秒失败规则；Collection Item 的字段编辑和 Folder Move 由同一次 PATCH 及 D1 batch 原子保存，目标 Folder 不存在或越权时不执行 batch、Item 保持原 Folder 和原字段；Move 成功后 Card Detail 立即使用服务端返回的 Target Folder，并统一失效 Home、Collection、Search 及 Home Performance。核对时发现 Home Performance 原先未纳入资产变更失效范围，现已补齐，避免继续显示 Source/Target Folder 的旧缓存。Subscription Pending 定向测试、Card Detail Controller 40 项、Workers Item 路由 12 项已通过；真实弱网 Timeout、跨设备删除和远端 Performance 重载仍待人工验收。
- 全局 Deadline 复核发现 Scan Dio 原先使用 4 秒连接与 12 秒响应两个独立上限，最坏可超过 App PRD 的单次 15 秒总 Deadline。现已在 Scan API 调用边界从请求发起时统一计时，覆盖 Quota、识别和确认；到期主动取消客户端等待并归约为 `REQUEST_TIMEOUT`，晚到成功不能更新已过期操作。识别的 `request_id` / `Idempotency-Key` 与服务端预占、结算、响应重放保持不变。短 Deadline 自动化测试已补充；真实弱网下服务端最终结算与 Waiting 递补仍需 Sandbox/TestFlight 验收。
- Portfolio 公共 API 已同步收口 15 秒总 Deadline，覆盖 Folder、Collection Item、Wishlist、Dashboard 与估值历史读写；Timeout 后取消客户端等待并使用 PRD 通用文案，晚到写响应不能完成已过期 UI 操作。Create Folder、Quick Collect、完整 Collection Item Create 与 Add Wishlist 已补齐客户端与服务端幂等闭环：Timeout 后按稳定 owner 与完整操作语义复用 UUID Key（access token 刷新不影响），服务端同 Key/同语义重放原资源，同 Key/不同字段冲突，非法 Key 拒绝，成功后新操作生成新 Key；两个 Item 创建入口使用独立操作域。Folder Move 仍为单次原子 `PATCH`，现有 Controller 的请求代次判断继续隔离晚到读取结果。Workers Folder/Item/Quick Collect/Wishlist 4 文件 38 项、Flutter Portfolio 21 项、Workers type-check 与 Dart 定向静态分析已通过；真实弱网响应丢失仍需设备验收。
- Card Data 公共 API 已同步收口 15 秒总 Deadline，覆盖 Home 推荐、Search、Set/Card Detail、市场价和普通/批量 Price History；到期取消客户端等待并归约为 `REQUEST_TIMEOUT`。Search 与 Range 仍由现有 Controller 请求代次隔离旧响应，新增短 Deadline 测试证明迟到 Catalog 成功不会完成过期查询。真实快速连续搜索、切 Range 与弱网恢复仍需设备验收。
- Auth API 已收口 15 秒 Deadline，覆盖匿名会话、邮箱登录/注册、验证码、找回密码、OAuth 回调、Token 刷新、Logout 与删除账号；启动 `validateStoredSession` 的 `/auth/me → token refresh → /auth/me` 串行链从操作开始共享同一预算，每一步只使用剩余时间。Timeout 取消当前客户端等待并复用现有网络失败处理，迟到登录或 session 校验成功不会返回 session，OAuth 仍使用既有授权失败文案。单请求与三段校验链短 Deadline 测试已补充；系统浏览器中的 OAuth 交互本身仍按 PRD 例外。
- Currency Rate API 已收口 15 秒总 Deadline；并发选择继续复用单个 `/rates` 请求，Timeout 后保持旧货币、不缓存迟到结果并清理在途 Future，使下一次主动选择可以重新请求。自动化测试直接证明两次超时选择会发起两次独立请求；真实弱网货币切换仍需设备验收。
- Apple entitlement Workers HTTP 已收口 15 秒 Deadline，覆盖 purchase challenge、Fresh Purchase JWS 同步、App Attest challenge/register、Restore proof verify 与 lifecycle 校正；Timeout 归约为可重试 `REQUEST_TIMEOUT/408`，迟到 grant 响应不会完成过期请求，补偿队列继续保留证据。Apple Purchase Sheet、`AppStore.sync()` 与 App Attest 原生计算不套用该 HTTP Deadline，本机 StoreKit verified 即时 Premium 不等待 proof。定向 API 7 项已通过；真实弱网补偿、App Attest 真机和 Sandbox 仍待验收。
- App PRD 验收 137-140 已补齐直接 Widget 证据：Processing Item 删除后立即从可见 Queue 移除，`Done` 只按当前可见 Item 重算，在后台识别/Quota 请求尚未完成时即可恢复；后台最终成功仅更新服务端 Quota，不把已删除 Item 插回 UI，技术失败会刷新 Quota 并按 Queue 顺序递补现有 Waiting。Functional Paywall 关闭或其他未返回 typed Premium success 的结果不会 retry Waiting，也不会执行来源动作；各功能统一以非空 typed success 作为恢复门槛。Scan 定向测试已通过，真实 Worker 中断、租约接管和多设备时序仍待 Sandbox/TestFlight 验收。
- App PRD 验收 141-145 已完成代码与文档证据核对：各功能卡点统一引用 Functional Paywall 未成功规则，只有 typed Premium success 才恢复 `blocked_action`；PRD 前部的 `v1.1 核心规则速查` 明确仅汇总正文。服务端 Premium 授权只读取当前 `session_id` 的 Apple 购买链 grant，同 UID 另一 session 不继承；Notifications V2 与 Apple Server API 分别承担 Apple 生命周期维护和状态校正。客户端 StoreKit 2 verified Purchase/Restore 会立即把本机状态更新为 Premium，不等待通知、Admin 订单或服务端同步；Fresh Purchase 的持久同步失败直接测试仍返回 active entitlement。Flutter Subscription/Restore 14 项、`subscription-core` 9 项、Workers 权益/通知/校正/Restore 真实 D1 集成 17 项已通过；Apple 最终权威的端到端结论仍需 Sandbox/TestFlight、App Attest 真机、通知及 Server API 实网验收。
- App PRD 订阅验收 146-148 已完成代码和直接测试证据：Notifications V2 维护续订、Grace Period、Billing Retry、Billing Recovery、Expired、Refund/Revoked，Apple Server API 负责异常校正；所有授权仍绑定购买链与当前 session，UID 仅作为交易和业务关联字段。客户端读取本机 StoreKit verified entitlement，服务端或 StoreKit 暂时不可用时使用未过期 verified 缓存，缓存无法继续证明有效时进入 Unknown 而非直接降为 Free。新增真实 D1 通知测试直接覆盖 Billing Retry 失效、Billing Recovery 恢复、Expired 失效和 Refund 撤销并更新原订单，通知集成 9 项及 Workers type-check 已通过；仍需 Apple Sandbox 实际生命周期矩阵验证。原 PRD 随后对 Performance 验收再次从 146 编号，开发与测试记录分别使用“订阅 146-148”和“Performance 146-156”区分，不修改原始 PRD。
- App PRD Performance 验收 146-156 已补齐 migration 与 1Y Partial History 直接证据：`0031` 对 Existing Item 将 `performance_start_at`、`purchase_price_effective_at` 设为原 `created_at`，同时把 `performance_history_available_from` 设为 migration 时刻；既有事件保留原 `effective_at` 和原 Folder，只回填当前 Purchase Price/Currency 及可靠历史起点，因此不会把当前 Folder 或其他当前属性伪造成 v1.0 历史。1Y 仍按自然年范围返回，历史不足时从可靠起点展示真实片段并标记 `partial_history=true`，不降级、不补虚假点，也不误报 Network Error。已有数据 migration 与 Performance 计算测试 9 项、Flutter DTO/Controller 21 项及 Workers type-check 已通过；2026-08-13 又在远程 dev 只读导出的本地副本验证了 67 个 Item、145 条 Event 的迁移不变量。由于 dev 最大 owner 仅 24 条 Event、12 个现存 Item，1Y 重度用户规模和 Cloudflare 端到端性能仍需发布环境验收。
- Performance 已落地 `0031` 与独立接口：Home 按 Folder、Card Detail 严格按 `collection_item_id` 查询，统一 1D/7D/15D/1M/3M/1Y、默认 1M、15 秒超时和迟到响应隔离；服务端返回 `item_count`、`market_price_status` 与 purchase price 状态，App 可区分 Empty、No Data、Partial History 和 Missing Purchase Price。同卡多 Item 且无 Item 上下文时隐藏 Card Detail Performance，不猜测、不聚合。Home 点位已按 PRD 全精度公式分解 `market_change_usd`、`portfolio_change_usd` 与 `quantity_change`；Range 首点读取范围外紧邻可靠节点，只有全历史无前态时返回 `null`。Folder Move 使用最新 Folder 决定全部可靠历史归属，不再把 Move 前片段留在 Source。Tooltip 只展示 Date/Market/Portfolio/Qty，Partial Purchase Price 使用 Info Popover，并在点击图表、切 Range、切 Folder或离开 Performance 时执行互斥/清理。1D 单点可点击，金额隐藏只隐藏金额且保留 Qty。Workers Portfolio 10 文件 57 项、Flutter DTO/Controller/Home 定向测试及 `flutter analyze` 已通过。`0031` 已通过隔离空库及 dev 导出副本验证，但尚未应用到常用 local、远程 dev 或 prod；App Attest/iOS 与真实历史数据规模尚未验证。
- Card Detail Performance 已按 App PRD 第 12 章和 14.8 收口：正常曲线使用 Item Profit/Loss，缺 Purchase Price 时使用 Market Value；服务端点位提供全精度计算后舍入的 `market_value_change_usd` 与 `profit_loss_change_usd`，Range 首点读取范围外紧邻可靠节点。正常 Tooltip 字段固定为 Date/Daily Change/Market Value/Profit-Loss/Qty，缺购买价状态不泄露 Profit/Loss、Purchase Cost 或 Return；1D 单点可点击，切 Range 后旧 Tooltip 清空。页面指标文案同步为 Purchase Cost、Market Value、Profit/Loss、Return，正金额按 PRD 显示 `+`。Flutter Card/DTO/Controller 定向 58 项、Workers Performance 单元/授权集成 11 项及两侧静态检查通过。
- Admin 订单与通知已落地：`0032` 增加 `business_status`、`charge_count` 与来源通知 UUID；试用为 0，成功付费按 `environment + originalTransactionId`、`purchase_at + transactionId` 确定性编号，重复交易不增加次数，退款保留原序号。`DID_CHANGE_RENEWAL_PREF + UPGRADE/DOWNGRADE` 只记录下一 Product ID、不建单；`SUBSCRIBED + RESUBSCRIBE` 使用新链时为首次付款/次数 1，沿用旧链时即使 Apple 原因为 `PURCHASE` 也重算为续费/次数递增。已验签建单通知在没有 UID/既有 chain 时可按启用 SKU 建立 `unlinked` 链和订单，Admin 显示空 UID且精确 UID 筛选不误匹配；通知不创建 grant，未知 SKU 隔离，后续只有可信 Fresh Purchase/Restore session proof 可补 owner。订单页按 PRD 展示 13 列和 11 项筛选，国家/SKU 来自实际数据，导出当前筛选的全部结果为真实 XLSX；同步导出上限 10,000 行，超限显式失败。通知页以 inbox 为入口，验签/解析/业务失败记录可见，列表不加载完整 JSON，详情不返回 `signedPayload`，仅在授权用户主动打开详情后加载 Decoded Payload，并由用户主动复制后显示成功 Toast。最新 Admin PRD 未要求新增查看/复制审计；Entitlements 8 文件 55 项、Workers 全量 47 文件 376 项及 Workers type-check 已通过，真实 Apple 无 UID 通知、升级/降级、重订阅与后续补关联仍待 Sandbox 验收。
- 订单 USD 金额已按 Admin PRD 与评审 P1-E 补齐 `0033` 快照：现有服务返回 `1 USD = rate × 原币种`，服务端以整数 micros 执行除法换算并固化原始 rate、来源、有效/抓取时间、陈旧标记、版本和舍入模式；USD 使用恒等快照。汇率或币种不可证明时订单仍入库但 USD 保持空，历史订单不猜测回填。汇率/Fresh Purchase/Notifications 定向 28 项和 Workers type-check 已通过；`0033` 已通过隔离空库顺序执行，但尚未应用到常用 local、远程 dev 或 prod。
- Extended Price History 已按 App PRD 统一 Home Overview 与 Card Detail Price History 六档 Range、默认 1M；Free 点击 1Y 不切 Range、不请求数据，Functional Paywall 成功后返回来源图表并自动加载 1Y，Premium 变 Free 时自动回 3M。Home 1Y `/portfolio/valuation-history?days=365` 强制当前 session grant。Card Detail 公共 `market-prices` 最多返回 90 天 history，`price-series` 单条或 batch 只在 `days<=90` 时公开；1Y Raw/Graded 均要求 live session 的服务端 grant，不允许同 UID 其他 session 继承，也不回退公开请求。本机 verified 头只用于返回同步等待态。Flutter Card Data/Card Detail 53 项、Workers 数据源/Premium helper/迁移与真实 D1 权限 26 项及两侧类型/静态检查已通过；该闭环不新增迁移。
- 配置阻塞：正式 Product ID 仍按 App PRD 标记为 Pending Configuration；Apple Root CA、Production App Apple ID 等 secret/vars 尚未配置。
- iOS 正式发布入口已增加配置门禁：`tool/release_ios.sh` 可通过 `RELEASE_ENV_CONFIG` 读取仓库外受控 JSON，并在构建前结构化校验环境、三个不重复的 Product ID 和 Singular Key/Secret；当前仓库占位 JSON 会被明确拒绝，避免误发无订阅或无归因配置的 IPA。校验规则 3 项及 Flutter analyze 已通过；Windows 环境没有 Bash，脚本语法和完整 IPA 流程仍需 macOS CI/开发机执行。
- 2026-08-13 最新工程回归：Workers 48 个文件 385 项、Admin 13 项、根 TypeScript 7 个 package type-check、全仓 build、Dart/Flutter analyze、依赖方向检查、Workers dev/prod dry-run 均通过；Flutter 全量为 667 项通过、10 项跳过、1 项 App Shell Golden 失败，不能标记全绿。Workers 首轮全量曾因 Miniflare 临时端口命中 Undici `bad port` 导致 Folder 并发集成测试未执行完成；该文件单独 3 项及随后全量 385 项均通过，归类为一次性测试基础设施故障。Wrangler dry-run 因沙箱不能写用户目录日志打印 `EPERM`，但 prod/dev 打包、bindings 检查及命令退出均成功；dry-run 不证明 Apple Secret 已配置或远程环境已部署。
- iOS release 配置门禁已对仓库内 `config/test.json` 与 `config/production.json` 实际执行，两者均按预期显式失败：缺 Weekly/Yearly/Lifetime 三个正式 Product ID 和 Singular API Key/Secret。校验器只依赖 Dart 标准库，发布脚本已改为直接执行文件，避免 `dart run` 在校验配置前触发整个 workspace 的无关 native build hooks；对应门禁 4 项测试通过。仓库配置仍只保存无密钥的 `APP_ENV` 占位，正式发布必须通过 `RELEASE_ENV_CONFIG` 注入仓库外受控文件；本结果证明门禁有效，也证明当前配置尚未达到发布条件。
- 2026-08-13 远程只读发布审计：dev/prod Worker 均只有既有 JWT、Mixpanel、ZeptoMail Secret，缺 Apple Root CA 和 App Store Server API Issuer/Key/Private Key；`wrangler.toml` 也尚未配置正式 Product ID 白名单、IAP Bundle ID、Production App Apple ID。两环境 D1 均待执行 `0025` 至 `0033`。因此当前部署即使可打包，Fresh Purchase/通知验签/Server API 校正仍会显式不可用；本轮未写 Secret、未迁移、未部署。
- 2026-08-13 真实历史迁移预演：通过 Wrangler 只读导出远程 dev D1，在仓库外本地 SQLite 副本连续执行 `0025` 至 `0033`。迁移前后核心表行数一致，`quick_check=ok`、外键检查无错误；67/67 个既有 Item 的逻辑起点保持原 `created_at`，可靠历史起点统一为迁移时刻，145 条 Event 未删除或重排。单条迁移耗时 9-45 ms，`0031` 为 17 ms。当前 dev 最大 owner 只有 24 条 Event、12 个现存 Item，Performance 数据库查询本地 20 次中位数为 Event 6.71 ms、价格 7.72 ms；Admin 订单表为空，空列表/计数中位数分别为 6.52/6.41 ms。这些结果不包含 Cloudflare 网络与 Worker JS 计算，也不覆盖有订单或重度收藏用户，不能替代 App 15 秒和 Admin 普通查询 3 秒的发布环境验收。本轮未写远程 D1。

### 阶段 A：P0 可信权益闭环

目标：关闭评审 P0-A/P0-B/P0-C，使服务端受限操作不信任 UID 或客户端布尔值。

- 鉴权上下文保留服务端验证过的 `session_id`。
- 新增 session → Apple purchase chain grant；不从 owner grant 回填。
- 新增版本化 Apple 证据同步接口，独立校验签名、Bundle、SKU、环境、有效期和撤销状态。
- Fresh Purchase 使用 session 一次性 `appAccountToken`；Restore 使用 App Attest challenge/assertion，解决合法跨设备恢复与复制 JWS 重放的冲突。
- 请求幂等、证据重放、Sandbox/Production 隔离和原始证据访问边界落库。
- Scan、Folder、Performance 与 Home Extended Price History 统一使用同一个服务端授权判断入口。
- 客户端处理 `VERIFIED_ACTIVE`、`VERIFIED_INACTIVE`、`EVIDENCE_INVALID`、`VERIFICATION_UNAVAILABLE`、`STATE_CONFLICT`、`REPLAY_REJECTED`。

验收：伪造/裸 ID 不可授权；同 UID 的另一 session 不继承；Logout 后旧 session grant 不可用；合法 Restore 可在新 session 建立独立 grant；同步失败不创建 Folder、不提交 Scan、不消耗 Free Quota。

### 阶段 B：Apple 通知与生命周期真值

当前状态：代码闭环，发布验证待完成。Notifications V2 接收、先存原文、官方验签、幂等、确定性归约、乱序保护、补偿重试、Apple Server API `correction_required` 消费与退款撤销校正已落地；完整 Sandbox/TestFlight 通知矩阵和正式 Secret 配置仍待完成。

- Notifications V2 接口先保存原始请求，再验签、解码和消费。
- 以 notification UUID 和 environment+transactionId 分别保证通知、交易幂等。
- 固定 purchase chain 状态版本比较元组，覆盖续订、Grace、Retry、Expired、Refund、Revoke 和 Refund Reversed。
- 不可比较或冲突时调用 App Store Server API 校正；业务消费失败可重试并可观测。
- 订单只由真实新 transactionId 创建，升级/降级通知本身不建单。
- 交易时点 USD 汇率快照代码已落地 `0033`：保存 rate、base/quote、来源、生效/抓取时间、陈旧标记、版本和舍入模式；汇率缺失不阻断订单且不伪造 USD 金额。迁移已通过隔离空库顺序执行，但尚未应用到常用 local、远程 dev 或 prod。

验收：重复/乱序通知不重复建单或回滚新状态；验签失败仍保留原始记录且无业务副作用；校正只影响对应购买链，不按 UID 传播权益。

### 阶段 C：服务端配额与 Premium 功能

- Scan 实现服务端 Free Quota 查询、request-id 预占、逐张结算/返还、Waiting 自动递补和多设备并发。
- Folder 创建已由单条条件 INSERT 原子完成 Free 数量检查与插入，Free 最多 2 个（含默认 Folder）。
- Performance 和普通价格历史 1Y 在服务端校验 grant。

验收：客户端超时重试不重复扣额度或创建对象；Premium 同步未完成不降级消耗 Free 配额；并发请求不能突破限制。

### 阶段 D：App PRD 完整交互

- 按 PRD 实现统一 15 秒 deadline、迟到响应防覆盖和写操作幂等键。
- 已按页面实例保留最小 `blocked_action` 来源上下文；Functional Paywall 成功不进入 Success Page，非成功或目标失效不执行旧动作。
- 已实现商品局部缺失时其余 SKU 仍可购买、商品读取 1/3/8 秒自动重试共享 15 秒总 Deadline、同次 Subscribe 重新拉取，以及 Pending、Cancelled、Failed、Unverified、Purchase unavailable 和商品重载 Timeout；仍需完成前后台完整矩阵与真机验证。
- 已实现 Unknown 主动刷新、Premium 变 Free、Lifetime/自动续订缓存期限和 Home/Card Detail/Folder/Scan/Profile 页面收敛；仍需 iOS 真机前后台与续订过期矩阵验证。
- 首次安装 ATT 与 Singular 初始化代码已完成；仍需注入正式 Key 并完成 iOS 系统弹窗、归因回传及真实 Firebase/App Store 收入验收。

验收：逐条映射 App PRD 第 21 章，不用 Widget 可见性代替服务端权限验收。

### 阶段 E：Performance 数据模型

当前状态：代码闭环，迁移与发布验证待完成。

- API 使用 PRD 固定的 `1D/7D/15D/1M/3M/1Y`，默认 `1M`，月/年按业务时区自然范围。
- 新增 `performance_start_at`、`performance_history_available_from` 和 v1.0 不可恢复历史 baseline。
- 保存 Purchase Price/Currency、Quantity、价格映射属性及 Folder Move 历史。
- 实现 Home/Card Detail 计算、缺失购买价分支、货币换算和精度规则。
- Home Performance 已实现 Market/Portfolio 变化分解、Tooltip 字段白名单、Qty 差值、金额隐藏、Partial Info Popover 互斥及 Range/Folder/Tab 清理；仍需真实历史数据规模与多设备远端删除人工验收。

验收：计算样例覆盖 PRD 第 10-14 章；迁移可重复且不伪造 v1.0 历史；1Y 查询达到性能门槛。

### 阶段 F：Admin、安全与发布

当前状态：订单/通知业务功能代码已完成，发布验收待完成；经最新 Admin PRD 核对，本期不新增 Payload 查看/复制审计范围。

- 已补齐订单和通知字段、查询、正确扣款次数、安装时间、当前订阅状态和 XLSX 全量导出。
- 已实现 Payload 默认安全边界：原始 `signedPayload` 长期保存但 Admin API/UI 不返回；XLSX 使用 inline string 防公式执行并限制同步导出最多 10,000 行。
- 最新 Admin PRD 未要求新增 Payload 查看/复制审计表或审计查询页面；本版本按授权详情加载、默认隐藏 `signedPayload`、用户主动复制的已确认安全契约实施，不猜测增加审计范围。
- 完成 Sandbox、TestFlight、通知失败恢复、跨设备、切号、退款撤销和服务端不可用测试。
- 补齐 Product ID、Apple 密钥/根证书策略、通知 URL、Singular Key 等环境配置。

验收：Admin PRD 第 20 章、App PRD 第 21 章和权益方案第 17 章全部有测试或人工验收证据；全量 CI 通过后才可进入发布。

## 4. 数据库与部署策略

- 已存在的 `0025_billing_admin.sql` 不修改；后续均使用递增迁移。
- owner grant 仅保留兼容旧骨架，授权路径禁止读取；不自动迁移到 session grant。
- 新表/列先向后兼容上线，再切换读写，最后在独立版本清理旧结构。
- 本地、dev、prod 环境严格分离。远程迁移和部署必须单独授权。
- Apple 官方服务端库依赖 Workers `nodejs_compat`；dev/prod dry-run build 必须保持通过。
- 每个迁移在对应文档中记录兼容性、回滚方式和数据回填规则。

## 5. 完成定义

“v1.1 开发完成”必须同时满足：三份 PRD 的验收条款均有可追踪证据；评审 P0/P1 全部关闭；客户端与服务端端到端可用；Sandbox/TestFlight 通过；全量测试和构建通过；所有外部配置齐备。单独完成 UI、StoreKit 抽象或 D1 表不能宣称完成。
