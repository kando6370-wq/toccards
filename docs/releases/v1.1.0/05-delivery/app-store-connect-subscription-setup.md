# tcg-card - App Store Connect 订阅配置手册

> **定位**：指导运营与研发在 App Store Connect 中配置 Performance Pro 的 iOS 商品、测试账号、服务端通知与审核资料。
> **日期**：2026-08-10
> **最近核验**：2026-08-18
> **适用应用**：dev/test Bundle ID `com.kando.kandoApp.beta`；production Bundle ID `com.cardai.tcg`
> **权益 ID**：`performance_pro`
> **状态快照（2026-08-18）**：当前 App Store Connect dev/test App 为 `Kando KP App`（Apple ID `6790245922`），订阅组 ID 为 `22251901`，Sandbox Server URL 已保存为 `https://api-dev.tcgcard.fun/api/v1/apple/notifications/v2`。dev 的 `APPLE_ROOT_CERTIFICATES_BASE64` 已用 Apple 官方 `Apple Root CA - G3` DER Base64 更新并立即生效；下载文件为 583 字节，SHA-256 为 `63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179`，更新后的 deployment 为 `623ef89f-f01b-48a4-912d-70586538e01d`、version 为 `6985637b-5e4e-480b-b804-19ce02ecef93`，`/api/v1/health` 返回 HTTP 200。Cloudflare 不回显 Secret 值，因此现有证据证明写入输入经过指纹核验且命令成功，真实 Apple Sandbox 通知验签、结构化入库和业务处理仍待验证。prod 只创建了包含相同 G3 证书的待部署 version `42f3934f-7cb4-41df-85b5-631b4e4b8954`，未部署、未分配流量；线上仍为 deployment `03235e84-694e-4800-854a-650173408412`、version `57213c10-d392-43a9-8d34-c6472fc3febc`。prod 商品与 Product ID 尚未配置；该 Apple 配置快照不证明 production 当前数据源，production deployment、Hyperdrive 和 PostgreSQL 运行状态必须在独立发布任务中重新核验，且不得查询或回退 D1。付费 App 协议、银行和税务资料尚未全部生效，完整购买闭环仍被 Sandbox/TestFlight 端到端验收阻塞，详见「七、当前阻塞项」。远程环境状态会变化，后续执行前必须重新查询。

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

dev/test Product ID 不得默认复用到 prod。prod 值确认后，必须独立更新 production 构建配置、Workers prod 白名单、共享 PostgreSQL 中按 production 环境隔离的 `billing_product` 映射及本手册；不得查询或写回 D1。

关键约束：

- Weekly 和 Yearly 必须放在同一个订阅组，用户同一时间只能持有该组内一个订阅。
- Lifetime 是一次性永久购买，不能放入自动续订订阅组。
- Product ID 创建后不能修改，也不能在删除后复用；创建前须确认命名。
- App Store 返回的本地化价格是展示与扣款的权威来源。当前 App 不使用固定美元价格兜底；商品未返回时显示 Loading 或 Unavailable，不得伪造价格。

---

## 二、配置前置条件

在创建和送审商品前，确认以下项目已经完成：

- [ ] Apple Developer Program 账号有效，且当前账号拥有 App Manager 或 Admin 等所需权限。
- [ ] App Store Connect 中已存在与目标构建匹配的 App：dev/test 使用 `com.kando.kandoApp.beta`，production 使用 `com.cardai.tcg`。
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

dev/test Product ID 已写入 `apps/flutter-app/config/test.json`，Workers dev 白名单已写入 `env.dev.vars.APPLE_IAP_PRODUCT_IDS`。2026-08-13 远程 dev D1 写入的三个 active `performance_pro` 商品映射已在 2026-08-17 迁入共享 PostgreSQL，正式 dev Worker/Admin version `73766f12-d888-4e94-ba2c-f990ef00ec43` 已部署。production/prod 仍未配置 Product ID 或白名单，不能使用本示例构建正式环境。当前客户端只请求非空 Product ID：未配置或 StoreKit 未返回的 SKU 显示 `Unavailable` 且不可购买。

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

截至 2026-08-18，dev 已完成 D1 非价格业务数据到共享 PostgreSQL 的迁移，并部署正式 Worker/Admin；34 条历史 inbox 均标记为 `Sandbox`，Sandbox URL 也已保存。dev Root CA Secret 已用指纹匹配的 Apple 官方 G3 DER Base64 更新并生效，但仍需新的 Apple 测试通知或真实 Sandbox 生命周期通知证明线上验签与业务处理恢复。prod 仅暂存 Root CA version `42f3934f-7cb4-41df-85b5-631b4e4b8954`，线上 deployment/version 未变化。

### 6.3 后端职责

- [x] 代码已使用 App Store Server API 查询交易与订阅状态；dev Secret 配置项已存在，仍待确认内容有效并完成 Sandbox 验收，production 需独立配置。
- [x] 代码已使用 Apple 官方库验证 StoreKit 2 JWS，校验 Bundle、环境、Product ID、有效期与撤销状态；dev Root CA Secret 已用 Apple 官方 G3 更新并生效，仍待真实 Sandbox 验签；production 仅暂存相同证书版本，尚未部署。
- [x] 代码已处理续订、退款、撤销、过期、Billing Retry、Grace Period、乱序保护与 Apple Server API 校正；仍待真实通知矩阵。
- [x] 交易映射到 Apple purchase chain 与当前 session grant，不把 UID 当作 Premium owner。
- [x] Lifetime 通过已验证交易建立无到期时间权益；仍待 Sandbox 实单验收。
- [x] Restore 已使用 StoreKit current entitlements 与 App Attest proof 为当前 session 重建 grant；仍待 iOS 真机验收。
- [x] 通知原文、处理状态、幂等、重试和 Admin 排障视图已实现；dev 迁移和部署已完成，真实 Apple Sandbox 通知验收尚未完成。
- [x] 代码已将 Apple JWS 验签异常限制为受控的 `VerificationStatus` 错误码，不保存底层 message/cause；`RETRYABLE_VERIFICATION_FAILURE` 保持为 `processing_failed` 并由现有 5 分钟任务重试，其他验签失败保持终态。dev 仍待在不夹带其他未交付改动的前提下部署，并用新 Sandbox 通知确认具体状态。

---

## 七、当前阻塞项

当前已实现 Fresh Purchase challenge、StoreKit 2 JWS 上传和 Workers session grant 写链，但**仍无法宣称正式购买授权端到端完成**。上线阻塞包括：

- dev/test Product ID 已确认；三个 active `performance_pro` 映射已从 dev D1 迁入共享 PostgreSQL，Workers dev 白名单已随 PostgreSQL version `73766f12-d888-4e94-ba2c-f990ef00ec43` 部署，健康接口返回 HTTP 200。
- 2026-08-17 只读核验显示：付费 App 协议为“等待用户信息”，银行账户为“正在处理”，美国税务表为“缺少税务信息”。Sandbox Tester 可以先创建，但这些商务前置条件未完成时，不能据此认定付费商品可查询或可购买。
- `cardx.week` 已配置价格、本地化和 174 个销售地区，并已添加以供审核；它仍受上述付费协议、银行和税务状态共同阻塞。
- `cardx.year` 已配置价格和本地化，但尚未设置销售范围，也尚未添加以供审核；它同时受商品配置缺口和上述商务状态阻塞。
- prod Product ID 尚未创建或通过审核；production 客户端配置和 Workers prod 白名单必须保持空。共享 PostgreSQL 当前只包含 dev/test 商品映射，待正式值确认后再独立增加 production 映射与授权。
- dev Root CA 的官方 G3 下载指纹、DER Base64 写入命令和生效版本已确认，但平台不回显 Secret 值，仍需通过真实 Sandbox 通知证明线上验签恢复；App Store Server API Secret 仍需真实调用验证。production Root CA 仅存在于未部署 version，App Apple ID、Product ID 与 Server API Secret 仍需独立完成；上文记录的 `6790245922` 是当前 dev/test App 记录，不能代替 production 配置。
- StoreKit 2 服务端同步失败后的 Secure Storage 持久化补偿队列已实现；仍待真机断网与恢复验收。
- Restore 的 App Attest proof、App Store Server API 和 Notifications V2 生命周期代码已实现；dev Root CA 已按官方 G3 更新，Apple Server API Secret 配置项与 Sandbox 通知 URL 已就绪，但真实 Server API 调用和真机/Sandbox 端到端验收尚未完成。
- Scan、Folder、Performance 和 1Y Price History 已统一接入当前 live session grant；对应结构与 dev 数据已迁入共享 PostgreSQL 并由 dev 正式版本运行。production Worker、Hyperdrive 和 PostgreSQL 实时状态需在独立发布任务中重新核验，且不得以 D1 作为回退；Sandbox/TestFlight 多设备验收仍待完成。

challenge 或业务 API 失败不得阻止 Apple 购买；本机 StoreKit 2 verified 仍按 App PRD即时解锁，但服务端受限操作在 grant 未同步时必须返回 `ENTITLEMENT_SYNC_REQUIRED`。

---

## 八、Sandbox 与 TestFlight 验收

### 8.1 账号入口与权限

Sandbox Apple Account 不在 `developer.apple.com/account` 申请，也不需要单独审核。使用 App Store Connect 中具有以下任一角色的账号直接创建：

- Account Holder
- Admin
- App Manager
- Developer

创建入口为 `App Store Connect -> Users and Access -> Sandbox`。部分界面会在 Sandbox 下继续显示 `Testers`。

### 8.2 创建 Sandbox Tester

1. 登录 [App Store Connect](https://appstoreconnect.apple.com/)，进入 `Users and Access`。
2. 打开顶部 `Sandbox`，点击添加按钮 `+`；首次创建时可能显示 `Create Test Accounts`。
3. 按下表填写测试账号：

| 字段 | 要求 |
|---|---|
| First Name / Last Name | 使用可识别的测试用途名称，不填写真实用户资料 |
| Email | 不得注册过 Apple Account，也不得用于其他 Sandbox Tester 或购买 App Store 内容 |
| Password | 使用符合 Apple 强度要求的独立密码，不得写入仓库、工单或测试日志 |
| Country or Region | 选择已包含在被测商品 Availability 中的 App Store 地区 |

4. 点击 `Create` 完成创建。

创建后，测试员的姓名、邮箱和密码不能编辑；国家或地区可以在 Sandbox Tester 详情中调整。邮箱服务支持 `+` 子地址时，可以使用专门的沙箱邮箱派生多个测试地址，但每个地址仍必须未绑定过 Apple Account。

### 8.3 真机开发包测试

1. 在 iPhone 上启用 `Settings -> Privacy & Security -> Developer Mode`。
2. 从 `apps/flutter-app` 安装明确使用 test flavor 和 test 配置的构建：

```powershell
flutter run --flavor test --dart-define-from-file=config/test.json -d <device-id>
```

也可以使用项目发布脚本生成并安装内部测试包：

```bash
./tool/release_ios.sh --env test --install <device-id>
```

3. 在较新 iOS 中进入 `Settings -> Developer -> Sandbox Apple Account` 登录测试账号；部分旧版本入口显示为 `Settings -> App Store -> Sandbox Account`。
4. 不要退出设备主 iCloud Apple Account，也不要把 Sandbox Tester 登录到设备主 Apple Account 入口。
5. 打开 App 发起购买，确认系统购买弹窗显示 Sandbox 测试环境且没有真实扣款。

若测试员所在国家或地区不在商品 Availability 内，即使 Product ID 正确，StoreKit 也可能不返回该商品。修改测试员地区后，需要在设备上重新登录 Sandbox Apple Account。

### 8.4 TestFlight 测试

- TestFlight 内购交易自动运行在 Sandbox 环境，不产生真实扣款。
- TestFlight 测试员不需要退出设备主 Apple Account，也不能把 TestFlight 结果当作正式商店扣款证据。
- TestFlight 能证明分发构建与 Apple Sandbox 的集成，但不能替代 production 商品、协议、税务、银行和正式审核状态。

### 8.5 订阅续订设置

在 `Users and Access -> Sandbox` 中打开测试员详情，可以调整 `Subscription Renewal Rate`、启用 interrupted purchases 或清理购买历史。清理购买历史是不可逆的测试数据操作，执行前应确认目标测试账号。

Apple 默认将一个月压缩为 5 分钟；在该默认速率下，1 周订阅约 3 分钟续订一次，1 年订阅约 1 小时续订一次。Sandbox 自动续订最多发生 12 次，第 13 次续订尝试时自动续订关闭。该加速规则只用于测试，不能外推为生产行为。

### 8.6 Weekly 与 Yearly 查询前置检查

当前客户端 test 配置必须与 App Store Connect dev/test App 完全一致：

| 检查项 | 期望值 |
|---|---|
| Bundle ID | `com.kando.kandoApp.beta` |
| Weekly Product ID | `cardx.week` |
| Yearly Product ID | `cardx.year` |
| 订阅组 | `Performance Pro`，Group ID `22251901` |

若 Weekly 或 Yearly 显示 `Unavailable`，按以下顺序排查：

1. 补齐税务信息，并等待银行账户和付费 App 协议变为有效。
2. 为 Yearly 设置与 Weekly 一致的销售范围，并添加以供审核。
3. 确认 Sandbox Tester 的国家或地区属于商品已启用地区。
4. 确认安装包使用 test flavor，且通过 `config/test.json` 注入 Product ID。
5. App Store Connect 配置更新后等待 Apple 服务传播，再重新安装或重启 App 查询。
6. 若仍失败，记录 StoreKit 查询的 `error` 和 `notFoundIDs`。当前 UI 会把 StoreKit 未返回的商品统一显示为 `Unavailable`，仅凭页面不能区分具体失败原因。

### 8.7 必测清单

- [ ] Weekly、Yearly、Lifetime 均能查询到 App Store 本地化价格。
- [ ] 三种商品均能发起购买并正确处理成功、取消和失败。
- [ ] Weekly 与 Yearly 能在同一订阅组内切换周期。
- [ ] Restore Purchases 能恢复订阅和 Lifetime。
- [ ] 订阅续订、过期、退款、撤销后，服务端权益状态正确更新。
- [ ] Billing Retry 与 Grace Period 符合产品策略。
- [ ] Lifetime 始终授予永久权益，不设置订阅到期时间。
- [ ] 重复通知、重复验证和重复恢复不会重复授予权益。
- [ ] 分别记录真机开发包和 TestFlight 的结果，不以模拟器结果代替真机验收。

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
- [Create a Sandbox Apple Account](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account/)
- [Overview of testing in sandbox](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox/)
- [Manage Sandbox Apple Account settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/)

App Store Connect 菜单名称可能随 Apple 后台更新发生轻微变化；配置原则、商品类型和 Product ID 映射以本文件为准，具体页面位置以 Apple 当前界面为准。
