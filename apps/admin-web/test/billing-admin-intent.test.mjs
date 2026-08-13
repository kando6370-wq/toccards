import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const routes = await readFile(new URL("../../workers-api/src/admin/routes.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../../workers-api/src/db/migrations/0025_billing_admin.sql", import.meta.url), "utf8");
const orderFactsMigration = await readFile(new URL("../../workers-api/src/db/migrations/0032_billing_order_facts.sql", import.meta.url), "utf8");

test("billing admin follows the v1.1 order facts contract without making UID the Premium owner", () => {
  assert.match(app, /label: "订单统计"/);
  assert.match(app, /label: "苹果通知消息"/);
  assert.match(app, /title: "扣款次数"/);
  assert.match(app, /title: "当前订阅状态"/);
  assert.match(app, /\/billing\/transactions\/options/);
  assert.match(app, /\/billing\/transactions\/export/);
  assert.match(app, /const lastPage = Math\.max\(1, Math\.ceil\(data\.total \/ data\.page_size\)\)/);
  assert.match(app, /if \(page > lastPage\) setPage\(lastPage\)/);
  assert.match(routes, /adminRoutes\.get\("\/billing\/transactions"/);
  assert.match(routes, /adminRoutes\.get\("\/apple-notifications"/);
  assert.match(routes, /createXlsx/);
  assert.match(routes, /LOWER\(linked_uid\.owner_id\) = \?/);
  assert.match(migration, /CREATE TABLE `billing_purchase_chain`/);
  assert.match(migration, /CREATE TABLE `billing_transaction`/);
  assert.match(migration, /CREATE TABLE `billing_entitlement_grant`/);
  assert.match(migration, /UNIQUE\(`purchase_chain_id`, `owner_type`, `owner_id`\)/);
  assert.match(migration, /`amount_micros` integer/);
  assert.match(orderFactsMigration, /ADD `business_status` text/);
  assert.match(orderFactsMigration, /ADD `charge_count` integer/);
});

test("Apple notification inbox is idempotent and remains read-only until JWS verification exists", () => {
  assert.match(migration, /`notification_uuid` text NOT NULL UNIQUE/);
  assert.match(migration, /`signed_payload` text NOT NULL/);
  assert.doesNotMatch(routes, /adminRoutes\.post\("\/apple-notifications"/);
});

test("Apple notification payload stays out of list responses and is copied only from an opened detail", () => {
  assert.match(app, /async function openDetail\(id: string\).*\/apple-notifications\/\$\{id\}/s);
  assert.match(app, /onClick=\{\(\) => openDetail\(row\.detail_id\)\}>查看详情/);
  assert.match(app, /navigator\.clipboard\.writeText\(prettyJson\(detail\.decoded_payload\)\)/);
  assert.match(app, /message\.success\("已复制通知内容"\)/);
  assert.match(routes, /adminRoutes\.get\("\/apple-notifications\/:detailId"/);
  assert.doesNotMatch(routes, /SELECT[^;]*signed_payload[^;]*FROM apple_notification_inbox/s);
});
