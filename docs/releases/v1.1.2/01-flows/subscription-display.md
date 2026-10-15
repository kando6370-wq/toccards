# App 1.0.6 订阅展示配置消费

需求输入：[PRD 1.14](../00-product/admin-subscription-config-prd.md)；接口：[第一阶段 V1 合同](../03-data-api/subscription-display-config.md)。本文件描述第三阶段本地源码；`850e339` 已完成目标 iOS CI 的无签名 production Release 编译，发布仍依赖独立兜底定稿、真实商品映射、签名制品与真机验收，不代表线上功能已启用。

## 页面与加载

iOS 的 Page、Modal 各自创建配置快照与选择状态。配置接口按 type 查询，未知响应字段可忽略；版本、页面类型、展示 SKU 数量（1–3 个）、默认项、去重或文案不合法时拒绝整份配置。配置最多 3 秒，配置、商品读取、远端全部失败后的兜底及最多 3 次自动重试共用 15 秒预算。部分成功保留后台顺序，默认项缺失时首次选择第一个可用商品。资格查询仅使用剩余预算，不延长普通商品的 Loading。

2026-10-15 补充的数量限制按展示位置计数，关联试用目标不额外占名额，独立展示的试用商品计入数量。远端超过 3 个时沿用初次配置无效的整份兜底，不截取前三个、不改变有效配置的顺序或默认项，也不缩小长期购买／Restore 商品集合。Android 的既有行为不变。

当前页面只确定一次配置快照；重试和回到前台仅刷新商品，不重新读取配置或接受迟到远端响应。远端商品一旦成功展示，后续刷新全部失败也不能切成另一组兜底商品，只保留该快照并显示加载失败。用户主动重试开始新商品加载周期，但不重置关闭延迟。旧加载、页面卸载后的响应均隔离。关闭页面不销毁长期购买监听。

关闭延迟从页面实例建立计算。iOS 订阅弹窗禁用原生无条件拖动，改由顶部手柄按同一关闭条件处理；Android 继续原拖动行为。购买和 Restore 进行时沿用关闭保护与来源返回。

## 计费与资格

购买继续使用现有 StoreKit SDK 商品对象。新增只读 iOS channel 返回真实类型、Decimal 正常价格、本地化金额、币种、周期、组、等级和介绍性免费优惠期限。两次读取的 ID／金额／币种／显示金额不同则不接受该商品。价格不从格式化字符串反算，新 iOS 展示路径不使用固定美元占位价。

主价格始终是正常周期完整金额，固定真实扣费摘要不能被营销说明替代。周均价只是辅助：周 P、月 P×12÷52、季度 P×4÷52、年 P÷52；使用原生 Decimal，最终一次四舍五入两位并采用 StoreKit 货币格式。一次性或未支持周期不显示周均值。

关联切换要求两商品成功、同组／周期／等级、源不带免费试用、目标真实优惠有效且资格 eligible。unknown／ineligible 不开启关联。iOS 16.0–16.3 无法读取 groupLevel 时保留基础商品购买，隐藏无法确认等级的关系；16.4+ 使用该字段。这是待真机验收的能力边界。

开关只替换当前选中位置；当前位置无有效关系时选第一个有效关系。点击同一位置不改变试用状态，选择其他位置关闭开关；主动关闭开关保留位置并恢复基础商品。独立试用的身份来自已批准长期注册及真实优惠，不按标题识别；优惠消失／资格未知／无资格时仍保留 Product ID，显示 Premium／SUBSCRIBE、标准价格，隐藏自由营销字段。unknown 明确由 App Store 确认优惠，不当作 ineligible。

购买前重新读取当前商品和资格，确认等待不超过 15 秒。价格、周期或试用条件变化时中止本次购买，要求再次点击；关联目标失效则保留位置并禁止提交，必须主动关闭切换或改选。购买 challenge、点击上下文与最后交给 StoreKit 的对象使用同一 Product ID；共享包新增精确商品对象入口，迟到的旧 catalog 不能替换已确认对象。

## 长期商品支持与 Restore

原构建中的 weekly／yearly／lifetime ID 继续属于长期集合。新增可选 dart-define SUBSCRIPTION_APP_STORE_SUPPORTED_PRODUCTS，值为 JSON 数组，每项明确 plan_id、product_id、product_type（subscription／non_consumable）及 is_trial_product；plan_id 和 Product ID 不能与旧集合或彼此重复。该列表来自经批准的商品接入映射，不由展示配置自动扩充。

购买监听、启动权益读取、当前会话同步及 Restore 使用完整长期集合；页面只加载其中当前展示所需的商品。关闭配置、删除卡片不缩小权益支持集合。新非消耗型按明确注册类型判断永久权益，不解析 ID 名称。Restore 现有阶段与局部 25 秒超时保持，没有新增端到端 Restore deadline。

本轮没有填写任何新真实 ID、改写 test／production 构建参数或扩展 Singular 映射。新商品需补齐 Apple、服务端准入、客户端长期注册、收入命名和旧包支持口径后再发布。既有验证交易、权益和收入处理仍复用，Restore 不计新收入。

## 兜底与平台边界

Page／Modal 的正式 1.0.6 兜底尚未定稿。代码为两类页面分别创建对象，暂保留当前客户端已有商品、顺序、Yearly 默认项与文案，仅展示真实加载成功的商品；这不是将旧三档或 HTML 示例批准为正式新设计。最终组合与文案需依各自设计定稿替换。

页面复用既有颜色、卡片、顶部提示、成功页及来源返回。Apple 配置及商品 channel 仅在 iOS 调用；Android 维持既有行为，不加载或售卖 Apple SKU，不宣称接入 Google Play。目标 Flutter 3.44.7／Xcode 16.4 已完成 Swift 无签名 Release 编译；该结果不能证明签名 entitlement、真实地区优惠或真机购买恢复已验收。

## 实现与验证入口

- [配置模型](../../../../apps/flutter-app/lib/features/subscription/subscription_display_config.dart)、[页面状态机](../../../../apps/flutter-app/lib/features/subscription/subscription_display_controller.dart)、[接口适配](../../../../apps/flutter-app/lib/features/subscription/subscription_display_providers.dart)。
- [购买与权益控制器](../../../../apps/flutter-app/lib/features/subscription/subscription_controller.dart)、[页面](../../../../apps/flutter-app/lib/features/subscription/subscription_page.dart)、[iOS 商品读取](../../../../apps/flutter-app/ios/Runner/AppDelegate.swift)。
- [Flutter 消费验证](../05-delivery/VERIFICATION.md#subscription-config-flutter)、[iOS 原生编译补验](../05-delivery/VERIFICATION.md#subscription-config-ios-compile)。

Apple 字段已核对官方 Product.SubscriptionInfo、groupLevel、Product.priceFormatStyle 文档；groupLevel 从 iOS 16.4 可用。资格调用锁定的 in_app_purchase_storekit 0.4.11 SDK，未升级依赖。
