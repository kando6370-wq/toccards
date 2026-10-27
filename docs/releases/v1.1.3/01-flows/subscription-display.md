# 订阅本地兜底页增量

沿用 [v1.1.2 订阅展示合同](../../v1.1.2/01-flows/subscription-display.md) 的远端 Page/Modal 配置、购买复核与 Restore 边界；本次只调整 iOS 远端配置缺失、无效或商品全量不可用时的本地三卡兜底。设计依据为 Figma `卡牌app` 节点 `3512:10546`、`3512:10763`；本次通过浏览器截图与属性核对，当前会话无法调用 Figma MCP `get_design_context`。

三卡顺序为 `Unlimited Weekly`（普通周订阅）、`3-Day Free`（独立年试用）、`Lifetime Access`（一次性终身），默认选中年试用。测试环境年试用 Product ID 为 `cardx.year.trial`，正式环境为 `CardAi.yearly.trial`；两者均以独立 `yearly_trial` plan_id 注册为试用订阅。原有普通周、普通年、终身及其他已注册商品继续留在长期购买／Restore 集合，不因兜底页换卡而移除。

固定离线参考价分别为 `US$4.99 per week`、`Then US$49.99 per year`、`US$79.99`；年卡角标为 `SAVE 81%`，终身卡角标为 `Best Offer`。第二张原型的年卡右侧写有 `per week`，与第一张原型的 `per year` 及年订阅 SKU 冲突；本次按第一张及商品周期采用 `per year`，终身卡不显示周期。固定 USD 数字仅用于 StoreKit 商品全量不可用时的界面预览，不代表当前地区真实价格或试用资格。

选中年试用时按钮为 `TRY FOR FREE`，协议下方为 `NO PAYMENT NOW`；选中普通周或终身时分别为 `SUBSCRIBE`、`CANCEL ANYTIME`。离线预览的年试用价格也显示 `Then`。读取到商品后使用 StoreKit 校验过的本地化完整价格、真实周期和商品自身免费优惠事实；年试用 SKU 没有有效免费优惠时改用现有中性文案，不承诺免费试用。点击离线卡仍须实时读取并校验选中的真实商品，失败时留在页面，不凭参考价发起交易。若此次读取发现免费优惠已经消失，先中止购买并显示中性商品卡及重新确认提示，用户再次点击后才允许按真实条件购买。

远端后台配置与 Android 原分支不随本次兜底改动。新增 SKU 的构建注册不等于服务端准入或 Apple 可售；测试／正式环境须各自完成当前 Bundle 的超级管理员动态审批、确认 Singular 收入事件名及旧包 Restore 限制后，才能作为真实购买链路验收。本次本地修改不代表已审批、已发布或已完成真机交易验收。
