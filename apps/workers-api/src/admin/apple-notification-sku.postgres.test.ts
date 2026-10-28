import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword } from "@kando/auth-core";
import { Hono } from "hono";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { adminRoutes } from "./routes";

const NOW = "2026-10-28T04:00:00.000Z";

type NotificationResponse = {
  data: {
    items: Array<{ detail_id: string; sku: string | null; processing_status: string }>;
    total: number;
    page: number;
    page_size: number;
  };
};

describe("Admin Apple notification SKU filter on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;
  let token: string;
  const app = new Hono<{ Bindings: Env }>().route("/admin", adminRoutes);

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    const migrations = new URL("../db/postgres/migrations/", import.meta.url);
    for (const name of [
      "0000_business_schema.sql",
      "0002_apple_inbox_environment.sql",
      "0009_apple_notification_app_bundle.sql",
    ]) {
      await db.exec(readFileSync(new URL(name, migrations), "utf8"));
    }
    await db.prepare(
      "INSERT INTO admin_user (id, email, password_hash, role, status, created_at) VALUES ('notification-admin', 'notification@example.com', ?, 'operator', 'active', ?)",
    ).bind(await hashPassword("notification-test-password"), NOW).run();
    await db.exec(`
      INSERT INTO apple_notification_inbox
        (id, payload_sha256, request_json, signed_payload, processing_status, attempts,
         notification_uuid, received_at, processed_at, environment, app_bundle_id)
      VALUES
        ('inbox-processed', 'hash-processed', '{}', 'signed.processed', 'processed', 1,
         'notification-processed', '${NOW}', '${NOW}', 'Sandbox', 'com.kando.kandoApp.beta'),
        ('inbox-failed', 'hash-failed', '{}', 'signed.failed', 'verification_failed', 1,
         NULL, '${NOW}', NULL, 'Sandbox', 'com.kando.kandoApp.beta');
      INSERT INTO apple_server_notification
        (id, notification_uuid, notification_type, environment, original_transaction_id,
         transaction_id, product_id, signed_payload, decoded_payload, processing_status,
         attempts, received_at, processed_at, inbox_id)
      VALUES
        ('notification-row', 'notification-processed', 'DID_RENEW', 'Sandbox', 'original-1',
         'transaction-1', 'CardAi.yearly', 'signed.processed', '{}', 'processed', 1,
         '${NOW}', '${NOW}', 'inbox-processed');
    `);
    env = {
      DB: db,
      CACHE_KV: {} as KVNamespace,
      JWT_SECRET: "notification-filter-test",
      APP_ENVIRONMENT: "development",
      APPLE_IAP_BUNDLE_ID: "com.kando.kandoApp.beta",
    };
    const login = await app.request("/admin/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "notification@example.com",
        password: "notification-test-password",
      }),
    }, env);
    expect(login.status).toBe(200);
    token = ((await login.json()) as { data: { access_token: string } }).data.access_token;
  }, 30000);

  afterAll(async () => { await db?.close(); });

  async function get(query = ""): Promise<NotificationResponse["data"]> {
    const response = await app.request(`/admin/apple-notifications?${query}`, {
      headers: { Authorization: `Bearer ${token}` },
    }, env);
    expect(response.status).toBe(200);
    return ((await response.json()) as NotificationResponse).data;
  }

  it("matches the complete SKU and keeps list rows aligned with the total", async () => {
    const matched = await get("sku=CardAi.yearly");
    expect(matched).toMatchObject({ total: 1, page: 1, page_size: 20 });
    expect(matched.items).toEqual([expect.objectContaining({
      detail_id: "notification-processed",
      sku: "CardAi.yearly",
      processing_status: "processed",
    })]);

    const missing = await get("sku=CardAi.year");
    expect(missing.total).toBe(0);
    expect(missing.items).toEqual([]);

    const differentCase = await get("sku=cardai.yearly");
    expect(differentCase.total).toBe(0);
    expect(differentCase.items).toEqual([]);
  });

  it("keeps failed inbox records visible when the optional SKU filter is absent", async () => {
    const unfiltered = await get();
    expect(unfiltered.total).toBe(2);
    expect(unfiltered.items.map((item) => item.processing_status)).toContain("verification_failed");
  });
});
