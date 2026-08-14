# tcg-card - App Store Connect 订阅配置手册

> **定位**：指导运营与研发在 App Store Connect 中配置 Performance Pro 的 iOS 商品、测试账号、服务端通知与审核资料。
> **日期**：2026-08-10
> **适用应用**：Bundle ID `com.cardai.tcg`
> **权益 ID**：`performance_pro`
> **当前状态**：dev/test 商品 Product ID 已确认，dev D1 商品映射和 Worker 白名单已部署；prod 商品尚未创建或通过审核，prod Product ID 保持未配置。服务端 Apple JWS 验证链已实现，购买闭环仍被 Apple Secret 和 Sandbox/TestFlight 端到端验收阻塞，详见「七、当前阻塞项」。

---

## 一、先明确商品模型

iOS 中的数字内容订阅必须使用 **Apple In-App Purchase（StoreKit）**，不能使用 Apple Pay。

| 套餐 | App Store 商品类型 | dev/test Product ID | 归属 |
|---|---|---|---|
| Weekly | Auto-Renewable Subscription | `cardx.week` | `Performance Pro` 订阅组 |
| Yearly | Auto-Renewable Subscription | `cardx.year` | `Performance Pro` 订阅组 |
| Lifetime | Non-Consumable | `cardx.lifetime` | 独立内购商品，不属于订阅组 |

| 套餐 | dev/test Product ID | prod Product ID |
|---|---|---|
| Weekly | `cardx.week` | 待 App Store 审核通过后填写 |
| Yearly | `cardx.year` | 待 App Store 审核通过后填写 |
| Lifetime | `cardx.lifetime` | 待 App Store 审核通过后填写 |

dev/test Product ID 不得默认复用到 prod。prod 值确认后，必须独立更新 production 构建配置、Workers prod 白名单、prod D1 `billing_product` 映射及本手册。

关键约束：

- Weekly 和 Yearly 必须放在同一个订阅组，用户同一时间只能持有该组内一个订阅。
- Lifetime 是一次性永久购买，不能放入自动续订订阅组。
- Product ID 创建后不能修改，也不能在删除后复用；创建前须确认命名。
- App Store 返回的本地化价格是展示与扣款的权威来源。当前 App 不使用固定美元价格兜底；商品未返回时显示 Loading 或 Unavailable，不得伪造价格。

---

## 二、配置前置条件

在创建和送审商品前，确认以下项目已经完成：

- [ ] Apple Developer Program 账号有效，且当前账号拥有 App Manager 或 Admin 等所需权限。
- [ ] App Store Connect 中已存在 Bundle ID 为 `com.cardai.tcg` 的 App。
- [ ] `Agreements, Tax, and Banking` 中 Paid Apps Agreement 已生效。
- [ ] 银行账户与税务资料已完成并通过 Apple 校验。
- [ ] Xcode 工程已启用 In-App Purchase capability。

协议、银行或税务状态不完整时，商品可能无法销售，即使客户端已经能够查询到商品。

---

## 三、创建 Weekly 和 Yearly 自动续订商品

### 3.1 创建订阅组

1. 登录 App Store Connect，进入 `My Apps`，选择 tcg-card。
2. 进入 `Monetization -> Subscriptions`。
3. 创建订阅组，Reference Name 建议填写 `Performance Pro`。
4. 为订阅组添加本地化名称。该名称可能出现在用户的订阅管理界面中，应使用正式面向用户的文案。

### 3.2 创建 Weekly

在 `Performance Pro` 订阅组内新增订阅并配置：

| 字段 | 配置值 |
|---|---|
| Reference Name | `Performance Pro Weekly` |
| Product ID | `cardx.week` |
| Subscription Duration | `1 Week` |
| Availability | 选择计划发布的国家或地区 |
| Subscription Price | 在 App Store Connect 中选择价格档位 |

随后补齐：

- [ ] App Store 本地化 Display Name 与 Description。
- [ ] Review Information 中的审核截图。
- [ ] Review Notes，说明入口、购买步骤以及测试方式。

### 3.3 创建 Yearly

仍在同一订阅组内新增订阅并配置：

| 字段 | 配置值 |
|---|---|
| Reference Name | `Performance Pro Yearly` |
| Product ID | `cardx.year` |
| Subscription Duration | `1 Year` |
| Availability | 与 Weekly 保持一致 |
| Subscription Price | 在 App Store Connect 中选择价格档位 |

同样补齐本地化、价格、可用地区、审核截图与 Review Notes。

### 3.4 配置订阅等级

Weekly 与 Yearly 提供相同的 `performance_pro` 权益，应配置在同一个 Subscription Level。它们是不同计费周期，不应被建模为高低权益等级。

---

## 四、创建 Lifetime 终身买断商品

1. 在应用中进入 `Monetization -> In-App Purchases`。
2. 新建商品，类型选择 `Non-Consumable`。
3. 配置以下字段：

| 字段 | 配置值 |
|---|---|
| Reference Name | `Performance Pro Lifetime` |
| Product ID | `cardx.lifetime` |
| Type | `Non-Consumable` |
| Availability | 选择计划发布的国家或地区 |
| Price | 在 App Store Connect 中选择价格档位 |

4. 补齐本地化 Display Name、Description、审核截图和 Review Notes。

Lifetime 购买验证成功后，后端必须授予无到期时间的 `performance_pro` 永久权益，并支持恢复购买。

---

## 五、将 Product ID 注入 Flutter 构建

App Store Connect 中创建的 Product ID 必须与构建参数完全一致：

| 套餐 | Dart Define |
|---|---|
| Weekly | `SUBSCRIPTION_APP_STORE_WEEKLY_ID` |
| Yearly | `SUBSCRIPTION_APP_STORE_YEARLY_ID` |
| Lifetime | `SUBSCRIPTION_APP_STORE_LIFETIME_ID` |

PowerShell dev/test 构建示例：

```powershell
flutter build ipa --release `
  --dart-define=SUBSCRIPTION_APP_STORE_WEEKLY_ID=cardx.week `
  --dart-define=SUBSCRIPTION_APP_STORE_YEARLY_ID=cardx.year `
  --dart-define=SUBSCRIPTION_APP_STORE_LIFETIME_ID=cardx.lifetime
```

dev/test Product ID 已写入 `apps/flutter-app/config/test.json`，Workers dev 白名单已写入 `env.dev.vars.APPLE_IAP_PRODUCT_IDS`。远程 dev D1 已将三个 Product ID 映射为 active `performance_pro` 商品，dev Worker 已部署为 `7228b912-c57f-43a3-8f2c-2404f8dac7bc`。production/prod 保持不配置，不能使用本示例构建正式环境。当前客户端只请求非空 Product ID：未配置或 StoreKit 未返回的 SKU 显示 `Unavailable` 且不可购买。

Singular 使用同一份 `--dart-define-from-file` 环境配置注入，不在仓库写入正式密钥：

| 配置 | Dart Define |
|---|---|
| Singular API Key | `SINGULAR_API_KEY` |
| Singular Secret Key | `SINGULAR_SECRET_KEY` |

正式环境将两个字段与三个 Product ID 一并写入受控发布 JSON，正式值不得提交仓库。普通开发构建按业务规则降级；`tool/release_ios.sh` 的 test 内部测试包强制校验 `APP_ENV` 和三个不重复的 Product ID，但允许缺少 Singular Key 并保持归因关闭。production 发布额外强制校验 Singular API Key/Secret，缺项时显式终止，不能沿用 test 的放宽规则。

仓库内 `apps/flutter-app/config/test.json` 记录不敏感的 dev/test Product ID，可直接用于不启用 Singular 的内部测试包；`production.json` 仅保留 `APP_ENV`，prod Product ID 与 Singular 密钥均未配置。production 发布时通过 `RELEASE_ENV_CONFIG` 指向仓库外的受控文件：

```bash
RELEASE_ENV_CONFIG=/secure/path/production.json ./tool/release_ios.sh --env production
```

---

## 六、配置 App Store 服务端能力

### 6.1 创建 In-App Purchase API Key

在 `Users and Access -> Integrations -> In-App Purchase` 创建密钥，并安全保存：

- Issuer ID
- Key ID
- `.p8` 私钥文件

`.p8` 通常只能下载一次，禁止提交到 Git。应保存到后端密钥管理系统，并分别配置开发和生产环境。

### 6.2 配置 App Store Server Notifications V2

在应用的 App Store Server Notifications 配置中分别填写：

- Sandbox Server URL：`https://api-dev.tcgcard.fun/api/v1/apple/notifications/v2`。
- Production Server URL：`https://api.tcgcard.fun/api/v1/apple/notifications/v2`。
- Version：选择 Version 2。

上述 URL 来自当前 Worker 自定义域名和已挂载路由；填入 App Store Connect 前仍需先完成对应环境迁移、Apple 验签配置和部署，并用 Apple 测试通知验证可达性。接口已实现 Apple 签名验证和重复通知幂等处理。

### 6.3 后端职责

- [x] 代码已使用 App Store Server API 查询交易与订阅状态；待配置各环境 Secret 并完成 Sandbox 验收。
- [x] 代码已使用 Apple 官方库验证 StoreKit 2 JWS，校验 Bundle、环境、Product ID、有效期与撤销状态；仍待正式证书配置和 Sandbox 验收。
- [x] 代码已处理续订、退款、撤销、过期、Billing Retry、Grace Period、乱序保护与 Apple Server API 校正；仍待真实通知矩阵。
- [x] 交易映射到 Apple purchase chain 与当前 session grant，不把 UID 当作 Premium owner。
- [x] Lifetime 通过已验证交易建立无到期时间权益；仍待 Sandbox 实单验收。
- [x] Restore 已使用 StoreKit current entitlements 与 App Attest proof 为当前 session 重建 grant；仍待 iOS 真机验收。
- [x] 通知原文、处理状态、幂等、重试和 Admin 排障视图已实现；迁移和真实环境验收尚未完成。

---

## 七、当前阻塞项

当前已实现 Fresh Purchase challenge、StoreKit 2 JWS 上传和 Workers session grant 写链，但**仍无法宣称正式购买授权端到端完成**。上线阻塞包括：

- dev/test Product ID 已确认；远程 dev D1 已写入三个 active `performance_pro` 映射，Workers dev 白名单已随版本 `7228b912-c57f-43a3-8f2c-2404f8dac7bc` 部署，健康接口返回 HTTP 200。
- prod Product ID 尚未创建或通过审核；production 客户端配置、Workers prod 白名单和 prod D1 映射必须保持空，待正式值确认后独立配置。
- Apple Root CA、Production App Apple ID 和 App Store Server API Secret 尚未配置。
- StoreKit 2 服务端同步失败后的 Secure Storage 持久化补偿队列已实现；仍待真机断网与恢复验收。
- Restore 的 App Attest proof、App Store Server API 和 Notifications V2 生命周期代码已实现，但 Apple Secret、通知 URL 和真机/Sandbox 端到端验收尚未完成。
- Scan、Folder、Performance 和 1Y Price History 已统一接入当前 live session grant；对应迁移已应用到远程 dev，尚未应用到常用 local 或 prod，仍待 Sandbox/TestFlight 多设备验收。

challenge 或业务 API 失败不得阻止 Apple 购买；本机 StoreKit 2 verified 仍按 App PRD即时解锁，但服务端受限操作在 grant 未同步时必须返回 `ENTITLEMENT_SYNC_REQUIRED`。

---

## 八、Sandbox 与 TestFlight 验收

### 8.1 创建 Sandbox 测试账号

进入 `Users and Access -> Sandbox -> Testers` 创建专用测试账号。不要使用真实 Apple ID 进行 Sandbox 扣款测试。

### 8.2 测试环境

- 真机开发包：使用 Sandbox Tester 测试。
- TestFlight：内购交易自动运行在 Sandbox 环境，不会产生真实扣款。
- 不以模拟器结果代替真机验收。

### 8.3 必测清单

- [ ] Weekly、Yearly、Lifetime 均能查询到 App Store 本地化价格。
- [ ] 三种商品均能发起购买并正确处理成功、取消和失败。
- [ ] Weekly 与 Yearly 能在同一订阅组内切换周期。
- [ ] Restore Purchases 能恢复订阅和 Lifetime。
- [ ] 订阅续订、过期、退款、撤销后，服务端权益状态正确更新。
- [ ] Billing Retry 与 Grace Period 符合产品策略。
- [ ] Lifetime 始终授予永久权益，不设置订阅到期时间。
- [ ] 重复通知、重复验证和重复恢复不会重复授予权益。

---

## 九、提交审核

每个商品送审前须确认：

- [ ] Product ID、商品类型和订阅时长正确。
- [ ] 所有目标地区均已启用并配置价格。
- [ ] 至少完成审核所需语言的名称和描述。
- [ ] 上传能清晰展示购买入口与商品信息的审核截图。
- [ ] Review Notes 写明进入订阅页的路径、测试步骤以及 Restore Purchases 入口。
- [ ] App 隐私政策、服务条款和订阅说明完整。
- [ ] App 内展示价格、周期、自动续订说明与 App Store 返回信息一致。

首次提交 In-App Purchase 通常需要随一个新的 App 版本一起送审：在该版本的 App Store 页面中，将商品添加到 `In-App Purchases and Subscriptions` 后一并提交。后续商品可按 App Store Connect 支持的流程单独送审。

---

## 十、完成标准

以下条件全部满足，才可认定 iOS 订阅支付已完成：

- [ ] App Store Connect 三个商品配置完整且状态允许测试或销售。
- [ ] 构建时三个 Dart Define 与 Product ID 完全一致。
- [ ] App 能加载 Apple 返回的本地化价格。
- [ ] 服务端验证、Server API 和 Notifications V2 已接通。
- [ ] Sandbox 与 TestFlight 必测清单全部通过。
- [ ] Weekly、Yearly 与 Lifetime 的权益规则通过后端集成测试。
- [ ] 商品与对应 App 版本审核通过。

---

## 官方文档

- [Offer auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/)
- [Create in-app purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-in-app-purchases/)

App Store Connect 菜单名称可能随 Apple 后台更新发生轻微变化；配置原则、商品类型和 Product ID 映射以本文件为准，具体页面位置以 Apple 当前界面为准。
