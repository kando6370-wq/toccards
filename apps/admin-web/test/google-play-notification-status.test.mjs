import assert from "node:assert/strict";
import test from "node:test";
import { playEventOptions, playNotificationEvent, playProcessingStates } from "../src/google-play-notification-status.ts";

test("operators can filter all 25 RTDN events before they arrive, without conflating the same number in different families", () => {
  const all = playEventOptions(undefined, []);
  assert.equal(all.length, 25);
  assert.deepEqual(playEventOptions("subscription", []).map(option => option.value),
    [1,2,3,4,5,6,7,8,9,10,11,12,13,17,18,19,20,21,22].map(code => "subscription:" + code));
  assert.deepEqual(["subscription:2", "one_time:2", "voided:2"].map(kind => playNotificationEvent(kind).name),
    ["续期成功", "一次性商品购买取消或撤销", "按数量部分退款"]);
  assert.equal(playNotificationEvent("subscription:3").code, "SUBSCRIPTION_CANCELED");
  assert.equal(playNotificationEvent("subscription:13").name, "订阅过期");
  assert.equal(playNotificationEvent("refund_review").name, "待审核拒付退款");
  assert.equal(playNotificationEvent("test").name, "测试通知");
  assert.equal(playProcessingStates.quarantined, "已隔离");
});

test("unmapped codes and historical voids stay searchable without labelling them as full refunds", () => {
  const observed = ["voided:2", "voided", "voided:9", "subscription:999"];
  const options = playEventOptions("voided", observed);
  assert.deepEqual(options.map(({value}) => value), ["voided:1", "voided:2", "voided", "voided:9"]);
  assert.match(options.at(-1).label, /未知通知类型.*voided:9/);
  assert.match(playNotificationEvent("voided").name, /未记录退款类型/);
  assert.deepEqual(playNotificationEvent("subscription:999"), {family:"订阅", name:"未知通知类型", number:"999", code:"subscription:999"});
});
