# v1.1.0 Premium 权益契约

## 1. 权威边界

- 本机 StoreKit verified 可即时解锁客户端 UI。
- Scan、Folder、Performance 等服务端能力只接受 Workers 独立验证 Apple 证据后签发的当前 session grant。
- UID、owner grant、订单、Admin 查询结果、客户端 `isPremium` 和裸交易 ID 均不得授权。
- `session_id` 来自已验签 JWT 并再次匹配共享 PostgreSQL 中的有效 session；客户端不得自行指定授权 session，也不得从 D1 查询或恢复 session。

## 2. 会话生命周期

| 场景 | 处理 |
|---|---|
| Access Token Refresh | session 不变，grant 继续按有效期使用 |
| Logout/session 撤销 | 权限查询因 session 非 live 立即拒绝；不取消 Apple entitlement |
| 账号切换/新登录 | 新 session 不继承旧 grant；用本机 StoreKit/Restore 证据重新验证 |
| 同 UID 另一设备 | 不共享 grant |
| 游客注册 | 新 session 重新验证；UID 关联只用于统计 |
| 重装/新设备 | 通过 StoreKit current entitlements 或 Restore 建立新 session grant |

### 2.1 Session proof 技术方案

Fresh Purchase 与 Restore 使用不同但等价的当前设备证明，不能仅提交可复制的交易 JWS：

- Fresh Purchase：购买前由 Workers 为当前 session 签发一次性 UUID；客户端通过现有 `PurchaseParam.applicationUserName` 传给 StoreKit 2，Apple 将其作为签名交易中的 `appAccountToken` 返回。Workers 只在 JWS 验签成功、token 属于当前 session、未过期且未被其他交易消费时建立 grant。
- Restore/既有交易：历史交易的 `appAccountToken` 不能改写，不能要求它等于新 session。客户端使用 App Attest 对“Workers 一次性 nonce + 当前交易 JWS 摘要 + 当前 session 上下文”生成 assertion；Workers 验证 assertion 后才为新 session 建立 grant。
- 同 UID、订单查询、裸 installation/device ID、客户端生成 nonce 和只做 JWS 请求幂等均不能替代上述 proof。

iOS 最低版本为 15.5，满足 App Attest 平台前提。模拟器或设备 proof 暂不可用时，客户端本机 StoreKit verified UI 仍按 PRD即时生效，但服务端受限操作返回 `ENTITLEMENT_SYNC_REQUIRED`，不得降级产生业务副作用。

## 3. Apple 证据同步

Fresh Purchase 在调起 StoreKit 前先申请一次性 challenge：

```http
POST /api/v1/entitlements/apple/purchase-challenge
Authorization: Bearer <access-token>
Content-Type: application/json

{"product_id":"<configured-product-id>"}
```

响应中的 `application_account_token` 有效期 10 分钟，只能用于当前 session、请求中的 Product ID 和一笔 Apple 交易。正式 Product ID 白名单、active `billing_product` → `performance_pro` 映射或 Apple verifier 配置缺失时返回 `VERIFICATION_UNAVAILABLE`。按 App PRD 第 6.3 节，challenge/业务接口失败不得阻止 Apple 购买；客户端仍可调起 StoreKit 并在本机 verified 后即时 Premium，但服务端 grant 未同步前受限操作返回 `ENTITLEMENT_SYNC_REQUIRED`。

```http
POST /api/v1/entitlements/apple/verify
Authorization: Bearer <access-token>
Idempotency-Key: <request-id>
```

```json
{
  "schema_version": 1,
  "evidence_type": "storekit2_signed_transaction",
  "signed_transaction_info": "<Apple JWS>",
  "environment_hint": "Sandbox",
  "request_id": "<UUID>"
}
```

`environment_hint` 不可信。Workers 必须从验签 Payload 确认 environment，并校验 Apple 证书链、Bundle ID `com.cardai.tcg`、Product ID 白名单、交易有效期和撤销状态。若 Flutter 最终只能取得 receipt/serverVerificationData，必须新增独立 `evidence_type` 和验证器，不能复用 JWS 解析器。

当前 `in_app_purchase_storekit 0.4.11` 的实际代码已确认：StoreKit 2 的 `serverVerificationData` 是交易 JWS；StoreKit 1 的同名字段是 Base64 App Receipt。因此客户端必须按 `SK2PurchaseDetails` 运行时类型标注 `storekit2_signed_transaction`，不得根据字符串外观猜测。客户端只有在已解析 JWS 的 `transactionReason=PURCHASE` 时才将证据加入 Fresh Purchase 队列；`RENEWAL` 不得提交到 `/entitlements/apple/verify`，已有购买链的续期由 Notifications V2/Apple Server API 归约。v1.1 首发可信同步以 StoreKit 2 JWS 为主；StoreKit 1 Receipt 验证器未完成时显式返回不支持，不能当 JWS 处理。

稳定业务状态为：`VERIFIED_ACTIVE`、`VERIFIED_INACTIVE`、`EVIDENCE_INVALID`、`VERIFICATION_UNAVAILABLE`、`STATE_CONFLICT`、`REPLAY_REJECTED`。

服务端已覆盖 Fresh Purchase 和 Restore 的 `VERIFIED_ACTIVE` 写链。App 通过 iOS 原生桥接完成 `AppStore.sync()` + verified `Transaction.currentEntitlements` 的本机 Restore：配置 SKU 命中即即时 Premium、同步成功后的空结果为 Not Found、配置 SKU unverified/15 秒读取超时为 Failed。`AppStore.sync()` 取消、账号验证失败或其他同步错误均停止本次 Restore，不得继续读取设备残留 entitlement 并误报 Success。本机 Success 后后台执行 App Attest 注册/assertion 与 JWS 同步；同步失败不撤销本机 Premium，但不创建 session grant。Notifications V2 与 Apple Server API 校正已覆盖生命周期失效：Billing Retry/Expired 将同链 grant 标记 expired，Refund/Revoke 标记 revoked，Grace 保持 active；该失效归约是服务端链路状态，不复用客户端 Fresh Purchase/Restore 接口的 `VERIFIED_INACTIVE` 响应。

`GET /api/v1/entitlements/apple/lifecycle` 只返回当前 live session 已通过 Fresh Purchase/Restore proof 建立 grant、且属于当前 App Store 环境的购买链状态。App 静默刷新先读取全部 Apple verified `Transaction.currentEntitlements`，再以 `originalTransactionId` 和时间版本应用服务端校正：只有 `BILLING_RETRY/EXPIRED/REVOKED` 且 `state_effective_at` 不早于本机 JWS `signedDate` 时剔除对应 entitlement，并用剩余全部 entitlement 重算 Premium。服务端 `ACTIVE` 不能在本机无 Apple entitlement 时单独授予；接口不可用、链未知或校正较旧时保留 Apple 本机/有效缓存结果，不直接降为 Free。同 UID 其他 session 的链不会出现在响应中。

App 以前台已验证订阅的 `expiresAt` 安排一次性静默复核，续期证据会重排下一次复核，Free/Lifetime 不保留到期计时；该路径不调用 `AppStore.sync()`，不触发账号交互。

App Store Server Notifications V2 已通过 `POST /api/v1/apple/notifications/v2` 接收 Production，通过 `POST /api/v1/apple/notifications/v2/sandbox` 接收 production Bundle 的 TestFlight Sandbox 通知：先以可信 Worker Bundle、真实 environment 与 `signedPayload` SHA-256 幂等保存原始请求，再用 Apple 官方库验签外层通知及嵌套 transaction/renewal JWS。Grace 保持同链 session grant 至 `gracePeriodExpiresDate`，Billing Retry/Expired 使其失效，Refund/Revoke 撤销；旧 `signedDate` 不得回滚新状态。无法确定最终状态时标记 `correction_required`，由 5 分钟补偿任务按 inbox Bundle 和真实 environment 调用对应 Apple Server API 并再次验签当前 transaction/renewal JWS；只更新对应 purchase chain 与该链已有 grant，不按 UID 或订单创建权益。

Restore proof API 分为 `POST /entitlements/apple/app-attest/challenge`、`POST /entitlements/apple/app-attest/register` 和 `POST /entitlements/apple/restore`。注册与 Restore challenge 均绑定当前 live session、request ID 与 key ID；Restore 还绑定 StoreKit JWS SHA-256。challenge 10 分钟有效且以随机 `consumption_id` 原子单次消费；assertion counter 使用旧值条件更新，counter 或消费条件失败时 purchase chain 与 grant 均不写入。相同 session/request/key/JWS 的重试返回已保存终态，不重复验签或写入；任一绑定字段不同则返回冲突。若 Notifications V2 或 Apple Server API 已写入比 Restore JWS `signedDate` 更新的购买链状态，Restore 不得用旧 JWS 回滚链：较新链仍为 `ACTIVE/TRIAL/GRACE_PERIOD/LIFETIME`、未撤销、未过期且 Product/Entitlement 仍在当前配置内时，以该权威链为当前 session 创建或刷新 grant 并返回 `VERIFIED_ACTIVE`；较新链为 `BILLING_RETRY/EXPIRED/REVOKED` 或已过期时保存并返回终态 `STATE_CONFLICT`，不得恢复 grant。两条分支均原子消费 assertion counter 和 challenge，并保存可幂等重放的终态。App Attest key 属于安装实例，登录/登出不清理；仅全新安装清除 Secure Storage 中的陈旧 key ID并重新注册。Performance 在本机 Premium 但服务端返回 `ENTITLEMENT_SYNC_REQUIRED` 时，可读取已经由 `Transaction.currentEntitlements` 验证的当前证据，最多执行一次 App Attest Restore proof；同步成功后原 Performance 请求最多重试一次，同步或重试失败后保留失败状态并等待显式刷新，不循环请求，也不重新调用 `AppStore.sync()`。

受保护请求在本机 Premium 时收到精确 `409 ENTITLEMENT_SYNC_REQUIRED`，必须先共享同一个 StoreKit/lifecycle 对账任务：确认当前 entitlement 有效才执行现有 session grant 同步，成功后原请求最多重试一次；确认 StoreKit 已空或存在不早于本机证据的 `BILLING_RETRY/EXPIRED/REVOKED` 时立即把全局状态和缓存降为 Free，当前页面原地重新上锁且不重试 Premium 请求；StoreKit、lifecycle 或本地缓存读取不可用时不误降为 Free、不重试原请求，并保留现有失败状态等待前台或显式刷新。该流程不循环请求，也不重新调用 `AppStore.sync()`。

客户端将待同步 StoreKit 2 JWS、原始 `request_id` 和 JWT `session_id` 保存在 Secure Storage，启动及 session 刷新后按原幂等键顺序重试。队列最多 20 条；切换 session 或全新安装时清除不匹配证据。`VERIFICATION_UNAVAILABLE`、网络错误、超时、429/5xx 保留重试；`EVIDENCE_INVALID`、`REPLAY_REJECTED` 和 `STATE_CONFLICT` 等终态错误移除，不阻塞后续交易。服务端对仍处于 60 秒处理租约的同一证据返回 `VERIFICATION_UNAVAILABLE`，不复用终态 `STATE_CONFLICT`。客户端在返回本机 active entitlement 前尽力完成队列持久化，但不等待后台网络同步；若 Secure Storage 自身失败，则记录诊断并仍按 App PRD 将本机 StoreKit verified 交易即时解锁，服务端受限操作继续按无 session grant 处理。

Workers 的验证请求使用 60 秒处理租约。相同 session、`request_id` 和证据摘要只能在租约过期或此前结果为 `VERIFICATION_UNAVAILABLE` 时接管重试；终态结果保持幂等返回。

Workers 配置契约：`APPLE_IAP_PRODUCT_IDS`（逗号分隔白名单）、`APPLE_IAP_BUNDLE_ID`、`APPLE_ROOT_CERTIFICATES_BASE64`（逗号分隔 DER Base64）、`APPLE_APP_ATTEST_APP_ID`；Production 还必须提供 `APPLE_IAP_APP_ID`。dev 只创建 beta Bundle 的 Sandbox verifier；prod 为同一 production Bundle 同时创建 Production 与 Sandbox verifier，Fresh Purchase、Restore、session grant、生命周期、通知重试和 Server API 校正都必须同时命中当前 Worker 的 Product ID 白名单。dev 的 `APPLE_APP_ATTEST_DEVELOPMENT=true` 只接受 development AAGUID，prod 为 `false` 只接受 production AAGUID。根证书与密钥不得提交仓库。

## 4. 服务端动作结果矩阵

| 客户端/服务端状态 | Folder Create | Scan Reserve/Submit | Performance Query |
|---|---|---|---|
| 有效 session grant | Premium 规则 | 不消耗 Free Quota | 返回 Premium 数据 |
| 本机 verified，grant 同步中或验证暂不可用 | 返回 `ENTITLEMENT_SYNC_REQUIRED`，不创建 | 返回 `ENTITLEMENT_SYNC_REQUIRED`，不预占、不提交 | 返回 `ENTITLEMENT_SYNC_REQUIRED`，保留当前页面 |
| 服务端明确无有效 entitlement | 第 3 个起返回 `PREMIUM_REQUIRED` | 使用 Free Quota | 返回 `PREMIUM_REQUIRED` |
| 服务端有更晚失效状态 | 撤销同链 grant 后按 Free | 撤销同链 grant 后按 Free | 返回 `PREMIUM_REQUIRED` |
| 同 UID 但当前 session 无 proof | 不放权 | 不放权 | 不放权 |
| 权益 Unknown | 先刷新，15 秒后仍 Unknown 则返回 `ENTITLEMENT_SYNC_REQUIRED` | 不得消费 Free Quota | 不得伪装 No Data |

## 5. Grant 数据规则

- 唯一关系：`session_id + purchase_chain_id + entitlement_id`。
- 只能由 Apple 验证服务创建或刷新。
- Fresh Purchase 必须消费当前 session 的一次性 `appAccountToken`；Restore 必须通过当前安装的 App Attest assertion。
- 有效性同时受 session live、grant status/expiry 和 purchase chain 更晚状态约束。
- Subscription grant 不晚于 Apple `expiresDate`；Lifetime 仍需服务端复核时限，具体最长缓存时限在 Apple 接入联调前冻结。
- `billing_entitlement_grant(owner_type, owner_id)` 是旧数据骨架，不参与任何授权判断，也不回填 session grant。

## 6. 错误副作用

`ENTITLEMENT_SYNC_REQUIRED`、`VERIFICATION_UNAVAILABLE` 和 `STATE_CONFLICT` 均不得创建 Folder、提交 Scan、预占/消耗 Free Quota或写入虚假 Performance 结果。`EVIDENCE_INVALID` 与 `REPLAY_REJECTED` 记录安全审计，但响应不得回显原始证据或购买链细节。

## 7. Folder 当前实现

- `POST /api/v1/portfolio/folders` 通过统一 Premium 查询读取当前 live session grant，不读取 UID 或旧 owner grant。
- Free Folder 总数上限为 2，默认 Folder 计入总数；服务端以单条条件 INSERT 同时检查数量并创建，避免多 session 并发突破上限。
- 客户端仅用 `X-Local-Premium-State: verified` 告知“本机已验证但服务端可能仍在同步”。该请求头不是授权证据；无 session grant 时服务端返回 `ENTITLEMENT_SYNC_REQUIRED`，且不写 Folder。
- 明确 Free 且达到上限时，App 按 PRD 进入 Functional Paywall。购买或恢复成功后，只有原 Folder Sheet 仍有效时才以保留名称重新打开 Create Folder Modal；非成功结果不创建 Folder。

## 8. Scan Quota 当前实现

- Free quota 归属为 `owner_type + owner_id`：账号用户多 session/多设备共享，游客身份独立；服务端为最终真源。
- `GET /scan/quota` 和 `/scan/recognize` 均先查询当前 session grant。本机 `verified` 但无 grant 时返回 `ENTITLEMENT_SYNC_REQUIRED`，不预占、不调用 R2/OCR、不消耗 Free quota。
- 每个识别请求使用 UUID `request_id`，并要求与 `Idempotency-Key` 一致。Free 在外部副作用前以单条条件 INSERT 原子预占；Premium 请求记录用于幂等，但不计入 Free quota。
- Matched 与 No Match 结算为 consumed；上传、OCR、解析或持久化技术失败结算为 released。完成响应持久化后可由同 session、同 request ID 原样重放。
- Quota 查询、识别成功及额度耗尽均返回完整 `{access, unlimited, limit, reserved, consumed, remaining}`；`access` 仅为 `free/premium`。Flutter 对字段缺失显式失败，不得把缺失 `unlimited` 当成 Free。
- Flutter 不再持久化或读取本地 Scan Quota，使用本机 Premium 或服务端 `unlimited=true` 的合并结果控制 Scan 展示和额度拦截；本机为 Free 时在页面生命周期内至少复核一次 StoreKit，服务端已确认 Unlimited 时请求继续携带同步保护。Gallery 超额与 Failed Retry 可保留原图转 Waiting；单张 Capture quota=0 不保留 Item；Waiting 删除不打开 Paywall，卡体打开 Paywall；Done 仅在存在 Matched 且无 Processing 时可用。Quota 返还按服务端 `remaining` 顺序递补，Purchase/Restore 后只有服务端确认 `unlimited=true` 才恢复全部 Waiting；`ENTITLEMENT_SYNC_REQUIRED` 保留现场且不转 Failed、不弹 Free Paywall。Processing 删除后继续在后台等待服务端结算但不重插 UI，Waiting Paywall 只在 typed success 且原 Queue 仍有效时恢复。
