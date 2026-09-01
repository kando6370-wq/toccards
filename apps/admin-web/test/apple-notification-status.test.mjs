import assert from "node:assert/strict";
import test from "node:test";
import { appleNotificationStatusName } from "../src/apple-notification-status.ts";

test("Apple notification status names follow the approved main-type and subtype combinations", () => {
  const expected = [
    ["CONSUMPTION_REQUEST", null, "消费数据请求"],
    ["DID_CHANGE_RENEWAL_PREF", "UPGRADE", "订阅方案变更：升级"],
    ["DID_CHANGE_RENEWAL_PREF", "DOWNGRADE", "订阅方案变更：降级"],
    ["DID_CHANGE_RENEWAL_PREF", null, "取消订阅方案变更"],
    ["DID_CHANGE_RENEWAL_STATUS", "AUTO_RENEW_ENABLED", "自动续订已开启"],
    ["DID_CHANGE_RENEWAL_STATUS", "AUTO_RENEW_DISABLED", "自动续订已关闭"],
    ["DID_FAIL_TO_RENEW", "GRACE_PERIOD", "续订失败：进入宽限期"],
    ["DID_FAIL_TO_RENEW", null, "续订失败：进入重试期"],
    ["DID_RENEW", "BILLING_RECOVERY", "重试期内扣款成功"],
    ["DID_RENEW", null, "自动续订成功"],
    ["EXPIRED", "VOLUNTARY", "订阅过期：用户主动取消"],
    ["EXPIRED", "BILLING_RETRY", "订阅过期：重试扣款失败"],
    ["EXPIRED", "PRICE_INCREASE", "订阅过期：未同意涨价"],
    ["EXPIRED", "PRODUCT_NOT_FOR_SALE", "订阅过期：商品已下架"],
    ["EXPIRED", null, "订阅过期：其他原因"],
    ["EXTERNAL_PURCHASE_TOKEN", "CREATED", "外部购买令牌已创建"],
    ["EXTERNAL_PURCHASE_TOKEN", "ACTIVE_TOKEN_REMINDER", "外部购买令牌仍有效"],
    ["EXTERNAL_PURCHASE_TOKEN", "UNREPORTED", "外部购买令牌未上报"],
    ["GRACE_PERIOD_EXPIRED", null, "账单宽限期结束"],
    ["METADATA_UPDATE", null, "订阅元数据已更新"],
    ["MIGRATION", null, "订阅已迁移"],
    ["OFFER_REDEEMED", "UPGRADE", "优惠兑换：升级订阅"],
    ["OFFER_REDEEMED", "DOWNGRADE", "优惠兑换：降级订阅"],
    ["OFFER_REDEEMED", null, "优惠兑换：当前订阅"],
    ["ONE_TIME_CHARGE", null, "一次性购买交易"],
    ["PRICE_CHANGE", null, "订阅价格已变更"],
    ["PRICE_INCREASE", "PENDING", "订阅涨价：等待用户同意"],
    ["PRICE_INCREASE", "ACCEPTED", "订阅涨价：已确认"],
    ["REFUND", null, "退款成功"],
    ["REFUND_DECLINED", null, "退款申请被拒绝"],
    ["REFUND_REVERSED", null, "退款已撤销"],
    ["RENEWAL_EXTENDED", null, "单个订阅续订日期延长成功"],
    ["RENEWAL_EXTENSION", "SUMMARY", "批量延期处理完成"],
    ["RENEWAL_EXTENSION", "FAILURE", "单个订阅延期失败"],
    ["RESCIND_CONSENT", null, "监护人撤回同意"],
    ["REVOKE", null, "家庭共享权益被撤销"],
    ["SUBSCRIBED", "INITIAL_BUY", "首次订阅"],
    ["SUBSCRIBED", "RESUBSCRIBE", "重新订阅"],
    ["TEST", null, "测试通知"],
  ];

  for (const [notificationType, subtype, statusName] of expected) {
    assert.equal(
      appleNotificationStatusName(notificationType, subtype),
      statusName,
      `${notificationType} + ${subtype ?? "empty"}`,
    );
  }
});

test("unknown or incomplete notification combinations remain explicit instead of being guessed", () => {
  assert.equal(appleNotificationStatusName(null, null), null);
  assert.equal(appleNotificationStatusName("FUTURE_NOTIFICATION", "FUTURE_SUBTYPE"), null);
  assert.equal(appleNotificationStatusName("DID_RENEW", "FUTURE_SUBTYPE"), null);
});
