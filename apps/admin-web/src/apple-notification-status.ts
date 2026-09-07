const STATUS_NAMES: Readonly<Record<string, Readonly<Record<string, string>>>> = {
  CONSUMPTION_REQUEST: { "": "消费数据请求" },
  DID_CHANGE_RENEWAL_PREF: {
    UPGRADE: "订阅方案变更：升级",
    DOWNGRADE: "订阅方案变更：降级",
    "": "取消订阅方案变更",
  },
  DID_CHANGE_RENEWAL_STATUS: {
    AUTO_RENEW_ENABLED: "自动续订已开启",
    AUTO_RENEW_DISABLED: "自动续订已关闭",
  },
  DID_FAIL_TO_RENEW: {
    GRACE_PERIOD: "续订失败：进入宽限期",
    "": "续订失败：进入重试期",
  },
  DID_RENEW: {
    BILLING_RECOVERY: "重试期内扣款成功",
    "": "自动续订成功",
  },
  EXPIRED: {
    VOLUNTARY: "订阅过期：用户主动取消",
    BILLING_RETRY: "订阅过期：重试扣款失败",
    PRICE_INCREASE: "订阅过期：未同意涨价",
    PRODUCT_NOT_FOR_SALE: "订阅过期：商品已下架",
    "": "订阅过期：其他原因",
  },
  EXTERNAL_PURCHASE_TOKEN: {
    CREATED: "外部购买令牌已创建",
    ACTIVE_TOKEN_REMINDER: "外部购买令牌仍有效",
    UNREPORTED: "外部购买令牌未上报",
  },
  GRACE_PERIOD_EXPIRED: { "": "账单宽限期结束" },
  METADATA_UPDATE: { "": "订阅元数据已更新" },
  MIGRATION: { "": "订阅已迁移" },
  OFFER_REDEEMED: {
    UPGRADE: "优惠兑换：升级订阅",
    DOWNGRADE: "优惠兑换：降级订阅",
    "": "优惠兑换：当前订阅",
  },
  ONE_TIME_CHARGE: { "": "一次性购买交易" },
  PRICE_CHANGE: { "": "订阅价格已变更" },
  PRICE_INCREASE: {
    PENDING: "订阅涨价：等待用户同意",
    ACCEPTED: "订阅涨价：已确认",
  },
  REFUND: { "": "退款成功" },
  REFUND_DECLINED: { "": "退款申请被拒绝" },
  REFUND_REVERSED: { "": "退款已撤销" },
  RENEWAL_EXTENDED: { "": "单个订阅续订日期延长成功" },
  RENEWAL_EXTENSION: {
    SUMMARY: "批量延期处理完成",
    FAILURE: "单个订阅延期失败",
  },
  RESCIND_CONSENT: { "": "监护人撤回同意" },
  REVOKE: { "": "家庭共享权益被撤销" },
  SUBSCRIBED: {
    INITIAL_BUY: "首次订阅",
    RESUBSCRIBE: "重新订阅",
  },
  TEST: { "": "测试通知" },
};

export function appleNotificationStatusName(
  notificationType: string | null,
  subtype: string | null,
): string | null {
  if (!notificationType) return null;
  return STATUS_NAMES[notificationType]?.[subtype ?? ""] ?? null;
}
