import { hashPassword } from "@kando/auth-core";
import { unzipSync, strFromU8 } from "fflate";
import { Hono } from "hono";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { adminRoutes } from "./routes";

const NOW = "2026-08-12T12:00:00.000Z";

describe("Admin billing order contract", () => {
  let mf: Miniflare;
  let db: D1Database;
  let env: Env;
  let token: string;
  const app = new Hono<{ Bindings: Env }>().route("/admin", adminRoutes);

  beforeEach(async () => {
    mf = new Miniflare({ modules: true, script: "export default { fetch() { return new Response('ok') } }", compatibilityDate: "2024-11-01", d1Databases: ["DB"] });
    db = await mf.getD1Database("DB");
    for (const statement of SCHEMA) await db.prepare(statement).run();
    await seed();
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "billing-admin-test", APP_ENVIRONMENT: "development" };
    const login = await app.request("/admin/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email: "admin@example.com", password: "password" }) }, env);
    token = ((await login.json()) as { data: { access_token: string } }).data.access_token;
  });

  afterEach(async () => { await mf.dispose(); });

  it("uses exact UID and order matching while returning PRD order facts", async () => {
    const response = await get("/admin/billing/transactions?uid=100001&order_id=transaction-1&charge_count=1&subscription_status=ACTIVE");
    expect(response.status).toBe(200);
    const body = await response.json() as { data: { items: Array<Record<string, unknown>>; total: number } };
    expect(body.data.total).toBe(1);
    expect(body.data.items[0]).toMatchObject({
      uid: "100001", order_id: "transaction-1", install_time: "2026-08-01T00:00:00.000Z",
      order_status: "initial_purchase", subscription_status: "ACTIVE", charge_count: 1,
    });
    expect((await get("/admin/billing/transactions?uid=10000")).status).toBe(200);
    expect(((await (await get("/admin/billing/transactions?uid=10000")).json()) as any).data.total).toBe(0);
  });

  it("lists an unlinked Apple order without inventing a UID", async () => {
    await db.batch([
      db.prepare("INSERT INTO billing_purchase_chain (id, environment, original_transaction_id, original_owner_id, status, auto_renew) VALUES ('chain-unlinked', 'Sandbox', 'original-unlinked', '', 'ACTIVE', 1)"),
      db.prepare("INSERT INTO billing_transaction (id, purchase_chain_id, environment, transaction_id, product_id, business_status, charge_count, storefront_country_code, amount_micros, currency, amount_usd_micros, purchase_at, created_at) VALUES ('order-unlinked', 'chain-unlinked', 'Sandbox', 'transaction-unlinked', 'com.cardai.tcg.pro.yearly', 'initial_purchase', 1, 'US', 49990000, 'USD', 49990000, ?, ?)").bind(NOW, NOW),
    ]);

    const body = await (await get("/admin/billing/transactions?order_id=transaction-unlinked")).json() as any;
    expect(body.data.total).toBe(1);
    expect(body.data.items[0]).toMatchObject({ uid: null, order_id: "transaction-unlinked" });
    expect(((await (await get("/admin/billing/transactions?uid=100001&order_id=transaction-unlinked")).json()) as any).data.total).toBe(0);
  });

  it("returns country and SKU options from actual orders", async () => {
    const body = await (await get("/admin/billing/transactions/options")).json() as any;
    expect(body.data).toEqual({ countries: ["US"], skus: ["com.cardai.tcg.pro.yearly"] });
  });

  it("exports all filtered rows as a real XLSX workbook", async () => {
    const response = await get("/admin/billing/transactions/export?uid=100001");
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("spreadsheetml.sheet");
    const bytes = new Uint8Array(await response.arrayBuffer());
    expect(strFromU8(bytes.slice(0, 2))).toBe("PK");
    const files = unzipSync(bytes);
    const sheet = strFromU8(files["xl/worksheets/sheet1.xml"]!);
    expect(sheet).toContain("原始交易 ID");
    expect(sheet).toContain("transaction-1");
    expect(sheet).toContain("100001");
  });

  it("lists failed inbox records and exposes decoded content without leaking signedPayload", async () => {
    const options = await (await get("/admin/apple-notifications/options")).json() as any;
    expect(options.data.items).toEqual([{ notification_type: "DID_RENEW", subtype: null }]);
    const list = await (await get("/admin/apple-notifications")).json() as any;
    expect(list.data.total).toBe(2);
    expect(list.data.items.map((item: any) => item.processing_status)).toEqual([
      "verification_failed", "processed",
    ]);

    const failed = await (await get("/admin/apple-notifications/inbox-failed")).json() as any;
    expect(failed.data).toMatchObject({
      processing_status: "verification_failed", last_error: "NOTIFICATION_JWS_INVALID",
      decoded_payload: null,
    });
    expect(JSON.stringify(failed)).not.toContain("signed.failure.jws");

    const success = await (await get("/admin/apple-notifications/inbox-success")).json() as any;
    expect(JSON.parse(success.data.decoded_payload)).toMatchObject({ notification: { notificationType: "DID_RENEW" } });
    expect(JSON.stringify(success)).not.toContain("signed.success.jws");
  });

  it("shows future Apple notification types and decoded fields without a product dictionary update", async () => {
    await db.batch([
      db.prepare(`INSERT INTO apple_notification_inbox VALUES
        ('inbox-future', 'hash-future', '{"signedPayload":"signed.future.jws","futureRequestField":"kept"}',
         'signed.future.jws', 'processed', 1, NULL, 'notification-future', NULL,
         '2026-08-12T11:45:00.000Z', '2026-08-12T11:45:01.000Z')`),
      db.prepare(`INSERT INTO apple_server_notification VALUES
        ('notification-row-future', 'inbox-future', 'notification-future', 'FUTURE_NOTIFICATION',
         'FUTURE_SUBTYPE', 'Sandbox', NULL, NULL, NULL,
         '{"notification":{"notificationType":"FUTURE_NOTIFICATION","futureEnvelopeField":{"version":3}}}',
         'processed', '2026-08-12T11:45:00.000Z', '2026-08-12T11:45:00.000Z')`),
    ]);

    const options = await (await get("/admin/apple-notifications/options")).json() as any;
    expect(options.data.items).toContainEqual({
      notification_type: "FUTURE_NOTIFICATION",
      subtype: "FUTURE_SUBTYPE",
    });

    const detail = await (await get("/admin/apple-notifications/notification-future")).json() as any;
    expect(JSON.parse(detail.data.decoded_payload)).toMatchObject({
      notification: { futureEnvelopeField: { version: 3 } },
    });
    expect(JSON.stringify(detail)).not.toContain("signed.future.jws");
  });

  async function get(path: string) {
    return app.request(path, { headers: { authorization: `Bearer ${token}` } }, env);
  }

  async function seed() {
    await db.batch([
      db.prepare("INSERT INTO admin_user VALUES ('admin-1', 'admin@example.com', ?, 'super_admin', 'active', ?)").bind(await hashPassword("password"), NOW),
      db.prepare("INSERT INTO billing_purchase_chain (id, environment, original_transaction_id, original_owner_id, status, auto_renew) VALUES ('chain-1', 'Sandbox', 'original-1', '100001', 'ACTIVE', 1)"),
      db.prepare("INSERT INTO billing_transaction (id, purchase_chain_id, environment, transaction_id, product_id, business_status, charge_count, storefront_country_code, amount_micros, currency, amount_usd_micros, purchase_at, created_at) VALUES ('order-1', 'chain-1', 'Sandbox', 'transaction-1', 'com.cardai.tcg.pro.yearly', 'initial_purchase', 1, 'US', 49990000, 'USD', 49990000, ?, ?)").bind(NOW, NOW),
      db.prepare("INSERT INTO app_installation VALUES ('install-1', '100001', 'iOS', 'US', '2026-08-01T00:00:00.000Z', ?)").bind(NOW),
      db.prepare("INSERT INTO session VALUES ('user-session', 'user', '100001', 'refresh-user', '2099-01-01T00:00:00.000Z', ?, NULL)").bind(NOW),
      db.prepare("INSERT INTO billing_session_entitlement_grant VALUES ('grant-1', 'user-session', 'chain-1')"),
      db.prepare("INSERT INTO apple_notification_inbox VALUES ('inbox-success', 'hash-success', '{}', 'signed.success.jws', 'processed', 1, NULL, 'notification-1', NULL, '2026-08-12T11:00:00.000Z', '2026-08-12T11:00:01.000Z')"),
      db.prepare("INSERT INTO apple_notification_inbox VALUES ('inbox-failed', 'hash-failed', '{}', 'signed.failure.jws', 'verification_failed', 1, NULL, NULL, 'NOTIFICATION_JWS_INVALID', '2026-08-12T11:30:00.000Z', '2026-08-12T11:30:01.000Z')"),
      db.prepare("INSERT INTO apple_server_notification VALUES ('notification-row-1', 'inbox-success', 'notification-1', 'DID_RENEW', NULL, 'Sandbox', 'original-1', 'transaction-1', 'com.cardai.tcg.pro.yearly', '{\"notification\":{\"notificationType\":\"DID_RENEW\"}}', 'processed', '2026-08-12T11:00:00.000Z', '2026-08-12T11:00:00.000Z')"),
    ]);
  }
});

const SCHEMA = [
  "CREATE TABLE admin_user (id TEXT PRIMARY KEY, email TEXT, password_hash TEXT, role TEXT, status TEXT, created_at TEXT)",
  "CREATE TABLE session (id TEXT PRIMARY KEY, owner_type TEXT, owner_id TEXT, refresh_token TEXT UNIQUE, expires_at TEXT, created_at TEXT, revoked_at TEXT)",
  "CREATE TABLE billing_purchase_chain (id TEXT PRIMARY KEY, environment TEXT, original_transaction_id TEXT, original_owner_id TEXT, status TEXT, auto_renew INTEGER)",
  "CREATE TABLE billing_transaction (id TEXT PRIMARY KEY, purchase_chain_id TEXT, environment TEXT, transaction_id TEXT, product_id TEXT, business_status TEXT, charge_count INTEGER, storefront_country_code TEXT, amount_micros INTEGER, currency TEXT, amount_usd_micros INTEGER, purchase_at TEXT, refund_completed_at TEXT, created_at TEXT)",
  "CREATE TABLE billing_session_entitlement_grant (id TEXT PRIMARY KEY, session_id TEXT, purchase_chain_id TEXT)",
  "CREATE TABLE app_installation (installation_id TEXT PRIMARY KEY, uid TEXT, platform TEXT, country_code TEXT, first_seen_at TEXT, last_seen_at TEXT)",
  "CREATE TABLE apple_notification_inbox (id TEXT PRIMARY KEY, payload_sha256 TEXT, request_json TEXT, signed_payload TEXT, processing_status TEXT, attempts INTEGER, processing_expires_at TEXT, notification_uuid TEXT, last_error TEXT, received_at TEXT, processed_at TEXT)",
  "CREATE TABLE apple_server_notification (id TEXT PRIMARY KEY, inbox_id TEXT, notification_uuid TEXT, notification_type TEXT, subtype TEXT, environment TEXT, original_transaction_id TEXT, transaction_id TEXT, product_id TEXT, decoded_payload TEXT, processing_status TEXT, signed_at TEXT, received_at TEXT)",
];
