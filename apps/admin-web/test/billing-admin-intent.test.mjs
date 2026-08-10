import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const routes = await readFile(new URL("../../workers-api/src/admin/routes.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../../workers-api/src/db/migrations/0025_billing_admin.sql", import.meta.url), "utf8");

test("billing admin keeps purchase history separate from multi-device entitlement grants", () => {
  assert.match(app, /label: "订单统计"/);
  assert.match(app, /label: "苹果通知消息"/);
  assert.match(app, /title: "授权 UID 数"/);
  assert.match(routes, /adminRoutes\.get\("\/billing\/transactions"/);
  assert.match(routes, /adminRoutes\.get\("\/apple-notifications"/);
  assert.match(routes, /COUNT\(DISTINCT g\.owner_type \|\| ':' \|\| g\.owner_id\)/);
  assert.match(migration, /CREATE TABLE `billing_purchase_chain`/);
  assert.match(migration, /CREATE TABLE `billing_transaction`/);
  assert.match(migration, /CREATE TABLE `billing_entitlement_grant`/);
  assert.match(migration, /UNIQUE\(`purchase_chain_id`, `owner_type`, `owner_id`\)/);
  assert.match(migration, /`amount_micros` integer/);
});

test("Apple notification inbox is idempotent and remains read-only until JWS verification exists", () => {
  assert.match(migration, /`notification_uuid` text NOT NULL UNIQUE/);
  assert.match(migration, /`signed_payload` text NOT NULL/);
  assert.doesNotMatch(routes, /adminRoutes\.post\("\/apple-notifications"/);
});
