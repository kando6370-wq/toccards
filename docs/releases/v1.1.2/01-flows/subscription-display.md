# App 1.0.6 订阅展示配置消费

需求输入：[PRD 1.14](../00-product/admin-subscription-config-prd.md)；接口：[第一阶段 V1 合同](../03-data-api/subscription-display-config.md)。本文件描述第三阶段本地源码；本轮已完成 Page／Modal 的本地三卡兜底和 test／production 商品映射，`850e339` 已完成目标 iOS CI 的无签名 production Release 编译。发布仍依赖签名制品、真实 StoreKit／真机验收及独立环境发布，不代表线上功能已启用。

## 页面与加载

iOS 的 Page、Modal 各自创建配置快照与选择状态。配置接口按 type 查询，未知响应字段可忽略；版本、页面类型、展示 SKU 数量（1–3 个）、默认项、去重或文案不合法时拒绝整份配置。配置最多 3 秒，配置、商品读取、远端全部失败后的兜底及最多 3 次自动重试共用 15 秒预算。部分成功保留后台顺序，默认项缺失时首次选择第一个可用商品。商品事实加载完成后立即结束 Loading；当前版本不再等待或调用 Apple 账号级试用资格查询。

2026-10-15 补充的数量限制按展示位置计数，关联试用目标不额外占名额，独立展示的试用商品计入数量。远端超过 3 个时沿用初次配置无效的整份兜底，不截取前三个、不改变有效配置的顺序或默认项，也不缩小长期购买／Restore 商品集合。Android 的既有行为不变。

当前页面只确定一次配置快照；重试和回到前台仅刷新商品，不重新读取配置或接受迟到远端响应。远端商品一旦成功展示，后续刷新全部失败也不能切成另一组兜底商品，只保留该快照并显示加载失败。用户主动重试开始新商品加载周期，但不重置关闭延迟。旧加载、页面卸载后的响应均隔离。关闭页面不销毁长期购买监听。

关闭延迟从页面实例建立计算。iOS 订阅弹窗禁用原生无条件拖动，改由顶部手柄按同一关闭条件处理；Android 继续原拖动行为。购买和 Restore 进行时沿用关闭保护与来源返回。

## 计费与试用事实

购买继续使用现有 StoreKit SDK 商品对象。新增只读 iOS channel 返回真实类型、Decimal 正常价格、本地化金额、币种、周期、组、等级和介绍性免费优惠期限。两次读取的 ID／币种／显示金额不同则不接受该商品；金额比较只容纳 Decimal 转 double 与十进制字符串解析造成的最多 1 ULP 表示差异，超过 1 ULP 的差异仍拒绝，零价必须两路均为零。价格不从格式化字符串反算，新 iOS 展示路径不使用固定美元占位价。

正常周期完整金额和真实计费周期始终来自 StoreKit；购买按钮上方说明按下文的说明方式显示。后台配置的周均折算口径为周 P、月 P×12÷52、季度 P×4÷52、年 P÷52；使用原生 Decimal，最终一次四舍五入并按 StoreKit 币种格式固定显示两位小数。一次性或未支持周期不显示周均值。本地兜底的月卡右侧展示单独按月价 P÷4 计算，同样固定两位小数，且不改变后台配置的参考价口径。

2026-10-21 展示增量：后台配置可对页面展示 SKU 和关联试用 SKU 分别选择“实际周期价格”“实际周期价格 + 周均参考价”“只展示周均价”或“不展示”。实际价加周均参考价时，右侧主价为 StoreKit 实际周期价格，正下方固定显示本地化周均金额 `per week`，不加 `Approx.`；只展示周均价时，右侧主价改为周均金额，正下方仅显示 `per week`，真实免费试用商品的主价保留 `Then` 前缀。两项均不改变真实扣费价格、周期与购买目标。不展示时仅隐藏该商品卡片右侧金额和价格说明；商品名称、角标和选择状态仍展示，购买区说明按当前 SKU 的说明方式决定。试用卡优先使用自身可选设置；旧配置未提供试用价格字段时，继续继承源 SKU 的对应模式，显式 `weekly_only: false` 可关闭所继承的“只展示周均价”；隐藏价格优先于其他显示方式。此规则覆盖原 PRD 的“主价始终展示／试用复用源模式”卡片展示描述；本地三卡兜底与 Android 路径不受后台价格配置影响。V1 的 `price_mode` 仍为 actual／weekly，新选项由可选 `weekly_only` 表达，旧版 App 会忽略它并显示原周均参考模式。

2026-10-19 按钮说明增量：有效后台配置选择“自定义文本”时，购买按钮上方只显示当前实际 SKU 的 `billing_note`，其中 `{price}` 展开为 StoreKit 完整周期价格；文本为空则不显示说明，不叠加自动计费摘要。选择“自动商品说明”时，只显示按当前商品自身试用事实生成的真实计费摘要。基础 SKU 与关联试用 SKU 各自使用自己的方式和文案，Page／Modal 共用规则。当前版本不读取账号级资格，因此 Apple 商品事实包含免费试用时立即展示试用文案；商品事实不含免费试用时使用标准价格说明。原 `TrialEligibility` 三态及资格查询方法仍保留，旧调用路径已注释，不参与当前展示或购买流程。本次用户要求覆盖 PRD 1.14 中“固定真实交易摘要始终展示”的旧规则；商品真实价格校验、购买前复核和权益判断不变，Android 仍走原购买页面。

关联切换要求两商品成功、同组／周期／等级、源不带免费试用、目标商品事实包含有效免费优惠。iOS 16.0–16.3 无法读取 groupLevel 时保留基础商品购买，隐藏无法确认等级的关系；16.4+ 使用该字段。这是待真机验收的能力边界。Apple 账号是否曾使用过试用不在 App 端准入条件内，由 StoreKit 在实际交易时处理。

开启开关时只替换当前选中的有效关联位置；当前位置无有效关系时选第一个有效关系。之后选择其他非试用商品只改变选中项，开关及开启瞬间形成的商品列表保持不变；再次选择原关联位置仍使用对应试用商品。只有用户主动关闭开关时，才保留当前位置并将关联位置恢复为基础商品。独立试用的身份来自已批准长期注册及商品自身的真实优惠事实，不按标题识别；优惠消失时仍保留 Product ID，显示 Premium／SUBSCRIBE，默认显示标准价格（卡片配置隐藏价格时除外），隐藏自由营销字段。账号级 unknown／ineligible 不再参与当前 App 展示判断。

购买前重新读取当前商品，确认等待不超过 15 秒。价格、周期或商品自身试用事实变化时中止本次购买，要求再次点击；当前选中关联试用商品失效时保留位置并禁止提交，必须主动关闭切换或改选。购买 challenge、点击上下文与最后交给 StoreKit 的对象使用同一 Product ID；共享包新增精确商品对象入口，迟到的旧 catalog 不能替换已确认对象。购买前不再重新查询 Apple 账号级试用资格。

## 长期商品支持与 Restore

原构建中的 weekly／yearly／lifetime ID 继续属于长期集合。新增可选 dart-define SUBSCRIPTION_APP_STORE_SUPPORTED_PRODUCTS，值为 JSON 数组，每项明确 plan_id、product_id、product_type（subscription／non_consumable）及 is_trial_product；plan_id 和 Product ID 不能与旧集合或彼此重复。该列表来自经批准的商品接入映射，不由展示配置自动扩充。

购买监听、启动权益读取、当前会话同步及 Restore 使用完整长期集合；页面只加载其中当前展示所需的商品。关闭配置、删除卡片不缩小权益支持集合。新非消耗型按明确注册类型判断永久权益，不解析 ID 名称。Restore 现有阶段与局部 25 秒超时保持，没有新增端到端 Restore deadline。

第三阶段最初未填写新真实 ID；本轮已按用户确认补齐 test／production 的本地商品映射。原有 weekly／yearly／lifetime 注册继续保留用于购买监听、权益和 Restore；Page／Modal 的本地兜底另按以下三张卡展示。production 的 `CardAi.yearly` 与原 `SUBSCRIPTION_APP_STORE_YEARLY_ID` 是同一个长期商品，因此不重复追加注册：

| 环境 | Product ID | plan_id | 类型 | is_trial_product | Singular 收入事件 |
| --- | --- | --- | --- | --- | --- |
| test | weekly.trial | weekly_trial | subscription | true | card_weekly_trialtest |
| test | yearly.pro | yearly_pro | subscription | false | yearly_cardtest |
| test | cardx.month | monthly | subscription | false | card_monthlytest |
| production | CardAi.weekly.trial | weekly_trial | subscription | true | card_weekly_trial |
| production | CardAi.yearly | yearly（原注册） | subscription | false | yearly_card |
| production | CardAi.monthly | monthly | subscription | false | card_monthly |

test 长期支持集合为原三商品加三项追加商品；production 为原三商品加两个追加商品，其中 `CardAi.yearly` 复用原年商品。页面仍按后台最多三张卡片展示；本地兜底顺序固定为周试用、年订阅、月订阅，周试用是默认项。Android 仍不消费 Apple 配置。

新增收入事件按确认成功交易的实际 Product ID 匹配，事件名随环境使用上表映射；原三档事件保持不变。商品金额仍来自已确认交易的 JWS，零元试用按 0 上报；重试队列保留原有交易去重、失败后重启重试与 Restore 不计新收入的规则。Firebase 沿用原事件与真实交易字段。

上述是客户端实现与接入契约，dev 环境落地、商品准入及实际验证见[本版本记录](../05-delivery/VERIFICATION.md#dev-subscription-product-onboarding)。旧包新增商品支持、签名测试包、真机购买／恢复及外部平台实际收到收入仍需独立验收。

## 兜底与平台边界

Page／Modal 在后台配置缺失、无效或展示商品加载失败时，使用同一份本地三卡兜底：`3-Day Free`、`Unlimited Yearly`、`Unlimited Monthly`，顺序为周试用、年订阅、月订阅；年卡标签为 `save 81%`，月卡标签为 `Most Popular`，周试用为默认项。右侧均显示 `per week`：1 周及 StoreKit 返回的 7 天周期都直接使用本地化正常周期价，年卡按年价÷52，月卡按月价÷4；折算值在原生 Decimal 最终四舍五入两位并本地化。只要 Apple 商品事实包含免费试用，周卡价格加 `Then` 并显示试用 CTA；商品事实不含免费试用时沿用 `Premium`／`SUBSCRIBE` 和正常周价。App 不以账号历史资格阻断试用展示。图稿的 `$3.24` 与 `$12.99÷4` 的四舍五入结果不一致，真实月价为 `$12.99` 时应显示 `$3.25`。Android 仍维持既有行为。

页面复用既有颜色、卡片、顶部提示、成功页及来源返回。Apple 配置及商品 channel 仅在 iOS 调用；Android 维持既有行为，不加载或售卖 Apple SKU，不宣称接入 Google Play。目标 Flutter 3.44.7／Xcode 16.4 已完成 Swift 无签名 Release 编译；该结果不能证明签名 entitlement、真实地区优惠或真机购买恢复已验收。

## 订阅页面视觉增量

2026-10-16 的本地 Flutter 布局按 Figma `3465:8694` 及同组两／三商品、试用开关状态还原：350 宽内容边距、四行 50 高权益项、上置的 62 高试用开关、74 高基础商品卡片、选中态描边与角标，以及贴底的账期摘要、44 高 CTA 和条款入口。选中卡片按本轮真机反馈移除背景填充和面阴影，保留描边与单选标记。完整页使用既有视频背景；iOS 弹窗复用同一商品内容，并保留弹窗手柄、背景和关闭延迟。Figma 的商品金额、节省比例、试用 CTA 为示例，实际页面继续使用已通过校验的 StoreKit 商品价格、后台文案、商品自身试用事实及购买前商品事实复核。周均价等附加内容使卡片增高时，商品区独立滚动，购买区固定在安全区上方。常规高度的标题固定在商品区上方，紧凑视口的标题随内容滚动；关闭和恢复入口始终固定。Android 保留原商品读取与购买分支。

价格说明明确区分配置来源：有效后台配置选择“实际周期价格”时，商品卡片在右侧价格下方只显示当前实际 SKU 的 `price_note`，空值时不显示；选择周均两项时，该位置改按上文显示 `per week` 或“本地化周均金额 per week”。客户端兜底卡片的右侧按上文周期规则显示本地化每周金额和 `per week`，商品自身免费试用事实有效时周卡在金额前显示 `Then`。年／月卡左侧副文案使用真实完整周期金额展开 `Only {price} per year/month`。所有折算所得金额固定两位小数；正常扣费价、StoreKit 商品事实校验和购买前复核不变。按钮上方说明以本节新增规则为准。

同次修正将试用开关到首张商品、相邻商品卡片的垂直间距统一为 20；浮动角标的价格列预留顶部空间，角标不得覆盖本卡价格或侵入上一张商品区域。后台配置商品的角标选中颜色随选择同帧切换，不执行中间色动画。商品名称下方没有副文案或行内角标时，名称在商品卡片中垂直居中；仅含空格的副文案视为空。有这些附加内容时继续从顶部排列，名称前的单选圆圈始终按整张卡片垂直居中，包括副文案换行时。兜底卡片的购买按钮按商品自身试用事实显示 `TRY FOR FREE` 或 `SUBSCRIBE`，Terms 下方分别显示 `NO PAYMENT NOW` 或 `CANCEL ANYTIME`。iOS 底部固定购买区的 Footer 底部留白统一为 16，购买按钮继续固定在 Terms 上方；商品列表仍独立滚动，不用压缩购买按钮或条款来容纳内容。

2026-10-21 按 Figma `3465:9667` 重新对齐 iOS Page／Modal 共用的固定购买区：在 390 宽画板中按钮宽 350、高 56，保持荧光黄绿胶囊和深色文字；按钮文字使用 SF Pro Text Semibold、16／24。按钮与协议行间隔 16；协议行高 18，链接文字为 SF Pro Text Regular、12／16、`#EEECD8`。有效后台配置存在计费说明时，说明位于按钮上方 16，使用 SF Pro Text Regular、12／16、`#EEECD8`；说明为空时不占位。正常后台配置不显示 `NO PAYMENT NOW` 或 `CANCEL ANYTIME`。两条 14／16 白色辅助提示仅由本地兜底按当前商品试用事实择一显示，位于协议行下方 4；这一来源判断和购买逻辑均未改变。Footer 底部间距仍为 16，Android 展示保持原状。

## 实现与验证入口

- [配置模型](../../../../apps/flutter-app/lib/features/subscription/subscription_display_config.dart)、[页面状态机](../../../../apps/flutter-app/lib/features/subscription/subscription_display_controller.dart)、[接口适配](../../../../apps/flutter-app/lib/features/subscription/subscription_display_providers.dart)。
- [购买与权益控制器](../../../../apps/flutter-app/lib/features/subscription/subscription_controller.dart)、[页面](../../../../apps/flutter-app/lib/features/subscription/subscription_page.dart)、[iOS 商品读取](../../../../apps/flutter-app/ios/Runner/AppDelegate.swift)。
- [Flutter 消费验证](../05-delivery/VERIFICATION.md#subscription-config-flutter)、[iOS 原生编译补验](../05-delivery/VERIFICATION.md#subscription-config-ios-compile)。

Apple 字段已核对官方 Product.SubscriptionInfo、groupLevel、Product.priceFormatStyle 文档；groupLevel 从 iOS 16.4 可用。商品事实读取锁定的 in_app_purchase_storekit 0.4.11 SDK，未升级依赖；历史账号资格调用仍保留在代码中但当前停用。


## 2026-10-16 动态商品注册增量（本地源码）

新增长期注册表接口由超级管理员逐个审批产生，iOS 在初始化、展示未知商品和 Restore 时读取。缓存键包含 API 地址、development／production 和实际 Bundle ID；响应 scope 不匹配或内容无效时拒绝，网络失败保留此前同 scope 的批准缓存及包内商品。已批准商品不会随页面删除而移出恢复集合。新版客户端已将本轮确认的 SKU 写入对应环境的本地注册；后续新增受支持的订阅 SKU 仍需审批并追加注册，不能由展示配置自动扩充。Page／Modal 继续使用本节定义的本地三卡兜底。

购买客户端采用追加注册，保留既有购买监听、历史计划和事件处理；同 Product ID 的包内计划标识保持稳定，冲突类型／重复计划拒绝整次更新。新 SKU 的 Singular 事件名由当前环境审批确认，并随收入交易记录持久化，离线／重启重试不重新猜测名称；金额、交易去重及 Restore 不计新增收入保持原规则。Firebase 保留原事件结构。Android 不读取 Apple 注册表，不新增 Google 售卖。

1.0.4／1.0.5 原商品继续使用原 V1；它们原生桥接会过滤包内未知 Product ID，因此新 SKU 回到旧包后的 Restore 无法通过服务端单独修复。该限制须由产品／超级管理员在启用新 SKU 前确认，源码测试不替代真实旧包和 StoreKit 验收。
