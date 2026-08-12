# tcg-card - App Store Connect 订阅配置手册

> **定位**：指导运营与研发在 App Store Connect 中配置 Performance Pro 的 iOS 商品、测试账号、服务端通知与审核资料。
> **日期**：2026-08-10
> **适用应用**：Bundle ID `com.cardai.tcg`
> **权益 ID**：`performance_pro`
> **当前状态**：商品配置可开始；正式购买仍被服务端票据验证能力阻塞，详见「七、当前阻塞项」。

---

## 一、先明确商品模型

iOS 中的数字内容订阅必须使用 **Apple In-App Purchase（StoreKit）**，不能使用 Apple Pay。

| 套餐 | App Store 商品类型 | 建议 Product ID | 归属 |
|---|---|---|---|
| Weekly | Auto-Renewable Subscription | `com.cardai.tcg.pro.weekly` | `Performance Pro` 订阅组 |
| Yearly | Auto-Renewable Subscription | `com.cardai.tcg.pro.yearly` | `Performance Pro` 订阅组 |
| Lifetime | Non-Consumable | `com.cardai.tcg.pro.lifetime` | 独立内购商品，不属于订阅组 |

关键约束：

- Weekly 和 Yearly 必须放在同一个订阅组，用户同一时间只能持有该组内一个订阅。
- Lifetime 是一次性永久购买，不能放入自动续订订阅组。
- Product ID 创建后不能修改，也不能在删除后复用；创建前须确认命名。
- App Store 返回的本地化价格是展示与扣款的权威来源。当前代码中的 `$4.99`、`$49.99`、`$79.99` 仅为商店价格暂时不可用时的 fallback，不代表 App Store Connect 已配置价格。

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
| Product ID | `com.cardai.tcg.pro.weekly` |
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
| Product ID | `com.cardai.tcg.pro.yearly` |
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
| Product ID | `com.cardai.tcg.pro.lifetime` |
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

PowerShell 构建示例：

```powershell
flutter build ipa --release `
  --dart-define=SUBSCRIPTION_APP_STORE_WEEKLY_ID=com.cardai.tcg.pro.weekly `
  --dart-define=SUBSCRIPTION_APP_STORE_YEARLY_ID=com.cardai.tcg.pro.yearly `
  --dart-define=SUBSCRIPTION_APP_STORE_LIFETIME_ID=com.cardai.tcg.pro.lifetime
```

当前客户端要求三个 iOS Product ID 全部非空才会初始化商店。漏配任意一个时，整个订阅购买入口都会处于未配置状态。

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

- Sandbox Server URL：开发或测试环境通知地址。
- Production Server URL：生产环境通知地址。
- Version：选择 Version 2。

具体 URL 需在后端通知接口完成后确定。接口必须验证 Apple 签名，并保证重复通知可幂等处理。

### 6.3 后端职责

- [ ] 使用 App Store Server API 查询交易与订阅状态。
- [ ] 验证 Apple 签名的 JWS 交易数据，不能仅信任客户端结果。
- [ ] 处理续订、退款、撤销、过期、Billing Retry 与 Grace Period。
- [ ] 将 StoreKit 交易映射到用户和 `performance_pro` 权益。
- [ ] Lifetime 验证成功后授予无到期时间的永久权益。
- [ ] 提供恢复购买后的权益重建能力。
- [ ] 保存通知处理记录，确保幂等并支持审计。

---

## 七、当前阻塞项

仅完成 App Store Connect 配置，**当前代码仍无法完成正式购买授权**。

客户端仍注入 `_MissingSubscriptionReceiptVerifier`：

```text
apps/flutter-app/lib/features/subscription/subscription_controller.dart:286
```

购买验证时会抛出：

```text
A receipt verifier must be configured by the app.
```

上线前必须完成服务端验证接口，并在 App 中替换该占位 verifier。未完成前只能验证商品查询和发起购买等局部流程，不能宣称订阅支付已经端到端可用。

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
