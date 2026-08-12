# Apple Subscription & Premium 权益统一方案

> 文档类型：跨端统一规则 / 开发评审基线  
> 适用范围：TCG Card App v1.1、TCG Admin、Apple 订阅后端能力  
> 状态：待评审确认  
> 日期：2026-08-11  
> 目的：统一 App、服务端、Admin 对 Apple Purchase、Premium、订单、订阅生命周期的口径，解决当前 App PRD 与 Admin PRD 的真值定义冲突。

---

# 1. 背景与当前冲突

当前 App PRD 与 Admin PRD 分别从客户端和后台角度定义了订阅能力，但存在两个必须在开发评审前统一的 P0 问题：

1. **App PRD 默认“现有 Apple 后端能力继续使用”，但当前工程实际不存在完整的 App Store Server Notifications V2 接收、JWS 验签、通知落库及订阅状态维护能力。**
2. **App PRD 将 Premium 定义为每台设备基于本机 StoreKit verified entitlement 独立判断；Admin PRD 又要求服务端根据续订、宽限期、Billing Retry、过期、退款等 Apple 生命周期事件更新订阅状态并重新计算 entitlement。**

如果不统一，会出现同一用户在 App、服务端和 Admin 中得到不同 Premium 状态的问题。

---

# 2. 最终统一结论

v1.1 采用以下统一原则：

> **Premium 不属于 App UID。Premium 的购买身份基础是 Apple transaction / originalTransactionId 所代表的 Apple 购买链路。**

> **Apple 是最终权威数据源；客户端 StoreKit 与服务端 Apple 验证能力是两个不同的 Apple 状态获取通道。**

> **客户端 StoreKit verified transaction 用于 Purchase / Restore 后即时解锁；服务端负责 App Store Server Notifications、Apple Server API 校正、订单和订阅生命周期维护。**

> **服务端维护 Premium 生命周期状态，不等于 Premium 归属于 App UID。UID 只用于业务账号数据及订单/通知关联。**

因此不得实现：

```text
UID A = Premium Owner
```

也不得实现：

```text
只要 UID A 在其他设备购买过 Premium
→ 当前设备即使没有当前 Apple 购买上下文的有效 entitlement
→ 也直接获得 Premium
```

---

# 3. 数据与职责归属

| 数据 / 能力 | 归属 | 说明 |
|---|---|---|
| Portfolio / Wishlist / Folder / 用户资料 | App UID | 账号用户可跨设备同步 |
| Free Scan Quota | App UID / 游客身份 | 按现有 App PRD 规则 |
| Apple Purchase | Apple transaction | 不属于 App UID |
| Premium 购买链路 | `environment + originalTransactionId` | 用于订阅生命周期维护 |
| 单笔交易 | `environment + transactionId` | 用于订单、幂等、收入 |
| UID | App 业务身份 | 可关联交易，但不是 Premium Owner |
| 客户端即时权益 | StoreKit verified transaction / current entitlement | Purchase / Restore 后即时生效 |
| 服务端订阅状态 | Apple Notification / Server API 验证结果 | 维护续订、Grace、Retry、Expired、Refund、Revoked 等生命周期 |
| Admin | 服务端数据的只读查询层 | 不提供人工开启/关闭 Premium |

---

# 4. Premium 判断模型

客户端内部仍保留：

```text
Unknown
Free
Premium
```

但不再把“本机 StoreKit 是唯一真值”作为产品定义。

统一定义为：

```text
Apple-verified entitlement state
├─ 客户端 StoreKit verified result
└─ 服务端 Apple verified lifecycle state
```

## 4.1 Purchase / Restore 即时场景

用户主动 Purchase 或 Restore 后：

```text
StoreKit 返回 verified transaction
→ 客户端立即更新 Premium
→ 更新本地 entitlement cache
→ UI 立即解锁
→ 不等待 Server Notification
→ 异步将交易信息同步服务端
→ 服务端完成交易验证 / 入库 / 生命周期维护
```

服务端暂时失败不得让已经 verified 的 Apple Purchase 在前端显示为购买失败。

## 4.2 后续生命周期场景

以下状态主要由服务端通过 Apple Server Notification / Apple Server API 持续维护：

- 自动续订成功
- Grace Period
- Billing Retry
- Billing Recovery
- Expired
- Refund
- Refund Reversed
- Revoked
- Lifetime 有效状态
- Auto Renew 状态变化

客户端在启动、回前台、进入 Premium 功能、Restore 等合适时机刷新状态，并最终与 Apple 最新有效状态收敛。

---

# 5. 客户端与服务端状态冲突规则

不能简单定义“客户端永远优先”或“服务端永远优先”，统一按以下规则处理。

## 5.1 StoreKit 已验证 Premium，服务端暂无记录

场景：

```text
Purchase Success
→ StoreKit verified
→ 服务端通知尚未到达 / 订单尚未同步
```

处理：

- 客户端保持 Premium。
- 不因为服务端“暂无记录”降级为 Free。
- 后台异步补齐交易与订阅链路。

“服务端暂无记录”不等于“Apple 已确认无权益”。

## 5.2 服务端有更晚的 Apple 明确失效状态

例如服务端已经可靠处理：

- Refund
- Revoked
- Expired
- Billing Retry 且当前无 Grace entitlement

并确认该状态属于同一 Apple 购买链路且事件时间晚于客户端缓存。

处理：

- 客户端刷新后收敛到服务端记录的 Apple 最新状态。
- 如无其他有效 entitlement，则变为 Free。
- 如还有其他有效 entitlement，则继续 Premium。

## 5.3 服务端不可用

服务端请求失败不能直接等于 Free。

客户端继续按：

1. 当前 StoreKit verified result；
2. 最近一次有效本地 entitlement cache；
3. App PRD 已定义的 Unknown / Timeout 兜底；

维持当前可解释状态。

## 5.4 服务端显示 Premium，但当前设备无法证明属于同一 Apple 购买上下文

不得仅凭当前登录 UID 获取其他设备或其他 Apple 购买环境中的 Premium。

只有当前设备通过 StoreKit / Restore 等方式获得对应 Apple 交易链路，或当前设备已有可靠的同链路本地验证上下文后，才可使用该服务端状态辅助校正。

核心原则：

> **服务端 entitlement 可以校正 Apple 购买链路状态，但不能把 UID 变成 Premium Owner。**

---

# 6. App UID 与 Apple Transaction 的关系

UID 与 Apple Transaction 可以建立“关联”，但该关联只表示：

```text
这笔交易发生时 / 后续补关联时
可对应到哪个 App 用户
```

用途包括：

- Admin 查询
- 订单统计
- 用户行为分析
- 客服排查
- 历史通知补关联

不用于定义：

```text
该 UID 永久拥有这份 Premium
```

因此继续保留：

- 游客可以直接购买 Premium。
- 游客购买后注册，不执行“Premium ownership 迁移”。
- Logout 不清除当前 Apple entitlement。
- 从账号 A 切换账号 B，不自动取消当前 Apple entitlement。
- 同一 App UID 在另一台设备登录，不得仅凭 UID 自动继承 Premium。

UID 的具体关联方案，如 `appAccountToken`、交易同步映射或其他方案，由开发确定，但不得改变以上产品结果。

---

# 7. 跨设备规则

## 场景 A：同一 Apple 购买环境可被设备 B 恢复

```text
设备 A Purchase
→ Premium

设备 B
→ 登录同一或不同 App UID
→ Restore
→ StoreKit 验证到有效 Apple entitlement
→ Premium
```

Premium 生效原因是设备 B 自己验证到了 Apple entitlement，不是因为 App UID 继承。

## 场景 B：同一 App UID，但设备 B 当前 Apple 购买环境无有效 entitlement

```text
设备 A：UID 100 + Premium
设备 B：UID 100 + 当前 Apple 上下文无有效 entitlement
```

设备 B 不得只凭 UID 100 自动获得 Premium。

---

# 8. v1.1 服务端必须新增的 Apple 能力

当前工程不存在完整能力时，以下内容明确列为 **v1.1 后端依赖**，不再写为“沿用现有能力”。

至少包括：

1. App Store Server Notifications V2 接收入口。
2. Apple JWS 签名验证与 Payload 解码。
3. 原始 `signedPayload` 保存。
4. Decoded Payload 保存。
5. `transactionId` / `originalTransactionId` 提取与订阅链维护。
6. 通知幂等处理。
7. 通知重复投递防重复订单 / 防重复扣款次数。
8. 通知处理失败的重试或可恢复机制。
9. 订单数据入库。
10. 当前订阅生命周期状态维护。
11. Refund / Revoked / Expired / Grace / Billing Retry / Billing Recovery 等状态处理。
12. 必要时使用 Apple Server API 查询当前交易或订阅状态进行校正。
13. 通知乱序 / 晚到保护。
14. Production / Sandbox 隔离。
15. 服务端 Apple 状态与 App entitlement 同步所需接口或同步机制。

具体数据库表结构、Worker、Queue、重试框架和技术实现由开发确定。

---

# 9. 生命周期权限映射

保持当前已确认产品规则：

| Apple 生命周期状态 | Premium |
|---|---|
| ACTIVE | Premium |
| TRIAL | Premium |
| GRACE_PERIOD | Premium |
| BILLING_RETRY | Free |
| EXPIRED | Free |
| REFUNDED / REVOKED | 重新计算全部有效 entitlement |
| BILLING_RECOVERY 成功 | Premium |
| Lifetime 有效 | Premium |

`Auto Renew = No` 不代表立即 Free；在有效到期时间之前仍保持 Premium。

退款、Revoked 等事件发生后，必须重新计算全部当前有效 entitlement，不能因为某一笔交易失效就直接关闭 Premium。

---

# 10. Purchase 统一流程

```text
用户点击 Subscribe
→ StoreKit Purchase
→ Transaction verified
→ 客户端立即 Premium
→ 更新本地 cache
→ 完成 Subscription Success / Functional Paywall 成功流程
→ 异步同步 transaction 到服务端
→ 服务端验证并建立 transaction / originalTransactionId 链路
→ 后续由 Notification / Server API 持续维护生命周期
```

以下行为不得发生：

- 等服务端通知后才显示 Purchase Success。
- 因订单同步失败把已经 verified 的购买提示成 Failed。
- Analytics 失败影响 Premium。
- Admin 数据未出现就撤销客户端刚完成的 verified Purchase。

---

# 11. Restore 统一流程

```text
Restore Purchases
→ StoreKit Sync / Restore
→ 重新读取 verified current entitlements
```

### 有有效 entitlement

```text
→ Restore Success
→ 客户端立即 Premium
→ Premium restored
→ 异步同步服务端
```

### Apple 明确返回无有效 entitlement

```text
→ Restore Not Found
→ 客户端刷新为 Free
```

### Restore 技术失败 / Timeout

```text
→ 保持原权益
→ Restore Failed
```

服务端不可用不得把 Restore 技术失败错误解释为“没有订阅”。

---

# 12. Server Notification 统一处理

服务端收到 Apple Notification：

```text
接收 signedPayload
→ 原文保存
→ JWS 验签
→ 解码
→ 通知消息入库
→ environment + transactionId 幂等
→ 更新订单
→ 更新 originalTransactionId 生命周期状态
→ 必要时重新查询 Apple Server API 校正
→ 更新服务端 entitlement state
```

原始通知保存与业务处理必须分离：

- 原始消息保存成功后，即使业务订单处理失败也不得丢失通知。
- 重复通知不得重复创建订单。
- 晚到旧通知不得覆盖较新的 Apple 有效状态。

---

# 13. Admin 后台职责

Admin 继续保持：

> **查询型、只读型后台页面。**

Admin 可以展示：

- 订单
- transactionId
- originalTransactionId
- UID 关联
- 当前订阅状态
- 自动续订状态
- Refund
- Grace
- Billing Retry
- Expired
- Apple 原始通知
- Decoded Payload

Admin 不提供：

- 手工开启 Premium
- 手工关闭 Premium
- 修改 Apple entitlement
- 将某个 originalTransactionId 人工绑定为某个 UID 的 Premium ownership
- 手工模拟 Apple 生命周期

Admin 展示的是服务端对 Apple 数据处理后的业务状态，不是一个人工权益管理系统。

---

# 14. App PRD 需要同步修改

App PRD 后续修改时至少同步以下口径：

1. 删除“本机 StoreKit 是唯一 Premium 真值”的绝对表述。
2. 改为 Apple 为最终权威数据源；StoreKit 与服务端均为 Apple 状态验证通道。
3. 保留 StoreKit verified Purchase / Restore 即时解锁。
4. 增加服务端生命周期状态同步与最终收敛规则。
5. 修改“服务端 Receipt 验证 / entitlement 为 Out of Scope”的旧描述。
6. 明确 v1.1 新增 Apple 后端能力依赖。
7. 保留“Premium 不属于 App UID”。
8. 保留游客购买、账号切换、Logout 不迁移 Premium ownership。
9. 保留 Unknown / Cache / Timeout 规则，但增加服务端不可用不直接等于 Free。
10. Refund / Revoked / Expired / Billing Retry 等以 Apple 最新生命周期状态进行校正。

Subscription Page、Paywall、Subscription Success、Scan、Folder、Performance 的既有 UI 和权益卡点原则上不需要因此重做。

---

# 15. Admin PRD 需要同步修改

Admin PRD 后续至少补充：

1. 明确第 8 节列出的 Apple 后端能力属于 v1.1 必须实现，而不是假设已有。
2. 明确服务端维护的是 **Apple 购买链路生命周期状态**，不是 UID Premium ownership。
3. 将“重新计算用户 Premium entitlement”统一表述为：
   - 重新计算该 Apple 购买链路及当前可验证的全部有效 Apple entitlements；
   - UID 关联仅用于查询和统计。
4. 保留 Admin 只读，不增加手工权益修改。
5. 保留 UID 可后补关联，但补关联不改变 Premium ownership 和历史交易事实。
6. 保留 Apple 通知、订单、订阅状态三层数据分离。

---

# 16. 开发评审必须确认的实现项

以下不再作为产品方案选择题，开发只需确认技术实现方式：

- Notification V2 接收 URL 与部署环境。
- JWS 验签方式。
- Apple Server API 的调用封装。
- Notification / Order / Subscription State 的数据表设计。
- transactionId 幂等方案。
- originalTransactionId 生命周期聚合方案。
- 通知消费失败重试方案。
- App 与服务端 entitlement 同步接口。
- Production / Sandbox 隔离。
- UID 关联方案。
- 客户端与服务端状态版本 / 时间比较方式。

开发实现可以不同，但最终产品结果必须符合本文。

---

# 17. 最终验收原则

- [ ] Purchase verified 后无需等待 Server Notification 即时解锁 Premium。
- [ ] 服务端未同步完成不得把 verified Purchase 当失败。
- [ ] Server Notification V2 可以真实接收、验签、解码、保存并处理。
- [ ] 同一 transactionId 重复通知不会重复建单或重复计费。
- [ ] 服务端维护 originalTransactionId 对应订阅生命周期。
- [ ] Grace Period 有 Premium。
- [ ] Billing Retry 无 Premium。
- [ ] Expired 无 Premium。
- [ ] Refund / Revoked 后重新计算全部有效 entitlement。
- [ ] 服务端晚到旧通知不会回滚较新的有效状态。
- [ ] Premium 不属于 App UID。
- [ ] UID 切换不会转移或取消 Apple Premium ownership。
- [ ] 同一 App UID 在另一设备不会仅凭 UID 自动继承 Premium。
- [ ] Restore 成功后当前设备验证到有效 Apple entitlement 才恢复 Premium。
- [ ] 服务端不可用不会直接把 Premium 用户错误降级为 Free。
- [ ] Admin 只读，不提供人工修改 Premium。
- [ ] App、服务端、Admin 对同一 Apple 购买链路最终状态可以收敛一致。

---

# 18. 文档优先级

本方案确认后，涉及 Apple Subscription / Premium 真值、UID ownership、服务端生命周期、Purchase / Restore 即时解锁的规则，以本文为统一总口径。

后续：

```text
本方案
↓
App v1.1 PRD
↓
Admin 订单统计与苹果通知消息 PRD
↓
技术设计 / 数据库 / 接口实现
```

App PRD 与 Admin PRD 如与本文冲突，应分别修订，不允许两个文档继续维护不同的 Premium 真值定义。
