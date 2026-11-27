export const playNotificationFamilies: Record<string, string> = {
  subscription: "订阅", one_time: "一次性商品", voided: "购买作废", refund_review: "退款审核", test: "通道测试", unknown: "未知通知",
};

// RTDN numbers are unique within a notification family only.
const events: Record<string, [string, string]> = {
  "subscription:1": ["SUBSCRIPTION_RECOVERED", "订阅恢复"],
  "subscription:2": ["SUBSCRIPTION_RENEWED", "续期成功"],
  "subscription:3": ["SUBSCRIPTION_CANCELED", "订阅取消"],
  "subscription:4": ["SUBSCRIPTION_PURCHASED", "新订阅购买"],
  "subscription:5": ["SUBSCRIPTION_ON_HOLD", "进入账号保留期"],
  "subscription:6": ["SUBSCRIPTION_IN_GRACE_PERIOD", "进入宽限期"],
  "subscription:7": ["SUBSCRIPTION_RESTARTED", "重新开启订阅"],
  "subscription:8": ["SUBSCRIPTION_PRICE_CHANGE_CONFIRMED", "确认价格变更（已弃用）"],
  "subscription:9": ["SUBSCRIPTION_DEFERRED", "订阅延期"],
  "subscription:10": ["SUBSCRIPTION_PAUSED", "订阅暂停"],
  "subscription:11": ["SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED", "暂停计划变更"],
  "subscription:12": ["SUBSCRIPTION_REVOKED", "订阅权益撤销"],
  "subscription:13": ["SUBSCRIPTION_EXPIRED", "订阅过期"],
  "subscription:17": ["SUBSCRIPTION_ITEMS_CHANGED", "订阅组合商品变更"],
  "subscription:18": ["SUBSCRIPTION_CANCELLATION_SCHEDULED", "分期订阅计划取消"],
  "subscription:19": ["SUBSCRIPTION_PRICE_CHANGE_UPDATED", "订阅价格变更更新"],
  "subscription:20": ["SUBSCRIPTION_PENDING_PURCHASE_CANCELED", "待支付订阅取消"],
  "subscription:21": ["SUBSCRIPTION_PLAN_TRANSITION_UPDATED", "订阅方案转换更新"],
  "subscription:22": ["SUBSCRIPTION_PRICE_STEP_UP_CONSENT_UPDATED", "涨价授权状态更新"],
  "one_time:1": ["ONE_TIME_PRODUCT_PURCHASED", "一次性商品购买成功"],
  "one_time:2": ["ONE_TIME_PRODUCT_CANCELED", "一次性商品购买取消或撤销"],
  "voided:1": ["REFUND_TYPE_FULL_REFUND", "全额退款／作废"],
  "voided:2": ["REFUND_TYPE_QUANTITY_BASED_PARTIAL_REFUND", "按数量部分退款"],
  refund_review: ["PendingRefundReviewNotification", "待审核拒付退款"],
  test: ["TestNotification", "测试通知"],
};

export const playProcessingStates: Record<string, string> = {
  pending: "待处理", processing: "处理中", processed: "已处理", failed: "处理失败", received_test: "已收到测试通知", quarantined: "已隔离",
};
export const playStoreKinds: Record<string, string> = {live: "正式购买", test: "测试购买", probe: "通道测试", unknown: "未核实"};

export function playNotificationEvent(kind: string) {
  const [family, number] = kind.split(":");
  const [code, name] = events[kind] ?? [kind, family === "voided" && !number ? "购买作废（未记录退款类型）" : "未知通知类型"];
  return { family: playNotificationFamilies[family] ?? family, code, number, name };
}

export function playEventOptions(family: string | undefined, observed: string[]) {
  return [...new Set([...Object.keys(events), ...observed])].filter(kind => !family || kind.split(":")[0] === family).map(value => {
    const {code, name, number} = playNotificationEvent(value);
    return {value, label: [name, number, code].filter(Boolean).join(" · ")};
  });
}
