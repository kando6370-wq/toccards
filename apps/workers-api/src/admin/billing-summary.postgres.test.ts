import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword } from "@kando/auth-core";
import { Hono } from "hono";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { adminRoutes } from "./routes";

const NOW = "2026-10-13T12:00:00.000Z";
const EMPTY_SUMMARY = {
  amount_usd_micros: 0, refunded_amount_usd_micros: 0,
  missing_amount_count: 0, missing_refunded_amount_count: 0,
};
const ALL_SUMMARY = {
  amount_usd_micros: 128450000, refunded_amount_usd_micros: 30000000,
  missing_amount_count: 1, missing_refunded_amount_count: 1,
};
type OrderResponse = { data: {
  items: Array<{ order_id: string; order_status: string | null; amount_usd_micros: number | null }>;
  total: number; page: number; page_size: number;
  summary: { amount_usd_micros: number | null; refunded_amount_usd_micros: number | null;
    missing_amount_count: number; missing_refunded_amount_count: number };
} };

describe("Admin billing totals on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;
  let token: string;
  const app = new Hono<{ Bindings: Env }>().route("/admin", adminRoutes);

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("../db/postgres/migrations/0000_business_schema.sql", import.meta.url), "utf8"));
    await db.prepare("INSERT INTO admin_user (id, email, password_hash, role, status, created_at) VALUES ('summary-admin', 'summary@example.com', ?, 'operator', 'active', ?)")
      .bind(await hashPassword("summary-test-password"), NOW).run();
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "billing-summary-test",
      APP_ENVIRONMENT: "development", APPLE_IAP_PRODUCT_IDS: "summary.yearly,summary.monthly" };
    const login = await app.request("/admin/auth/login", { method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "summary@example.com", password: "summary-test-password" }) }, env);
    expect(login.status).toBe(200);
    token = ((await login.json()) as { data: { access_token: string } }).data.access_token;
  }, 30000);
  afterAll(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.exec("DELETE FROM billing_transaction; DELETE FROM billing_purchase_chain; DELETE FROM app_installation;");
    await db.prepare(
      "INSERT INTO billing_purchase_chain (id, store, environment, original_transaction_id, product_id, entitlement_id, original_owner_type, original_owner_id, status, created_at, updated_at) VALUES ('summary-chain', 'apple', 'Sandbox', 'original-1', 'summary.yearly', 'premium', 'anonymous', '100001', 'ACTIVE', ?, ?)",
    ).bind(NOW, NOW).run();
    await db.exec("INSERT INTO app_installation (installation_id, platform, first_seen_at, last_seen_at, uid) VALUES ('summary-install', 'iOS', '2026-10-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z', '100001')");
    for (const [id, status, amount, sku, country, currency, original] of [
      ["paid-a", "initial_purchase", 123450000, "summary.yearly", "CHN", "CNY", 900000000],
      ["paid-b", "renewal", 2000000, "summary.monthly", "USA", "USD", 2000000],
      ["refund", "refunded", 30000000, "summary.yearly", "USA", "USD", 30000000],
      ["missing", "renewal", null, "summary.monthly", "USA", "EUR", 5000000],
      ["missing-refund", "refunded", null, "summary.yearly", "USA", "EUR", 6000000],
      ["free", "trial", 0, "summary.monthly", "USA", "USD", 0],
      ["unknown", null, 3000000, "summary.monthly", "USA", "USD", 3000000],
      ["unconfirmed", "initial_purchase", 900000000, "summary.yearly", "USA", "USD", 900000000],
      ["other-product", "initial_purchase", 900000000, "other.product", "USA", "USD", 900000000],
      ["production", "initial_purchase", 900000000, "summary.yearly", "USA", "USD", 900000000],
    ]) {
      await db.prepare(
        "INSERT INTO billing_transaction (id, purchase_chain_id, store, environment, transaction_id, product_id, transaction_reason, status, business_status, source_notification_uuid, amount_usd_micros, amount_micros, currency, storefront_country_code, auto_renew_snapshot, charge_count, purchase_at, refund_completed_at, created_at, updated_at) VALUES (?, 'summary-chain', 'apple', ?, ?, ?, 'PURCHASE', 'active', ?, ?, ?, ?, ?, ?, 1, 1, ?, ?, ?, ?)",
      ).bind(id, id === "production" ? "Production" : "Sandbox", id, sku, status,
        id === "unconfirmed" ? null : "notification-" + id, amount, original, currency, country,
        id === "refund" ? "2026-10-10T12:00:00.000Z" : NOW, status === "refunded" ? NOW : null, NOW, NOW).run();
    }
  });

  async function get(query = "", environment = env): Promise<OrderResponse["data"]> {
    const response = await app.request("/admin/billing/transactions?" + query, { headers: { Authorization: "Bearer " + token } }, environment);
    expect(response.status).toBe(200);
    return ((await response.json()) as OrderResponse).data;
  }

  it("totals every matching order independently of page size while keeping refunds separate", async () => {
    for (const query of ["page_size=1&page=1", "page_size=1&page=2", "page_size=100", "page=100"]) {
      const data = await get(query);
      expect(data.total).toBe(7);
      expect(data.summary).toEqual(ALL_SUMMARY);
      expect(data.items.length).toBe(query === "page=100" ? 0 : query === "page_size=100" ? 7 : 1);
    }
  });

  it("applies the exact list filters to totals instead of reporting unrelated sales", async () => {
    const filters = new URLSearchParams({ uid: "100001", order_id: "paid-a", country: "CHN,USA",
      sku: "summary.yearly", status: "initial_purchase", subscription_status: "ACTIVE",
      install_from: "2026-10-01", install_to: "2026-10-01", purchase_from: "2026-10-13",
      purchase_to: "2026-10-13", auto_renew: "true", environment: "Sandbox", charge_count: "1" });
    const data = await get(filters.toString());
    expect(data.total).toBe(1);
    expect(data.summary).toEqual({ ...EMPTY_SUMMARY, amount_usd_micros: 123450000 });
    for (const [name, value] of Object.entries({ uid: "100002", order_id: "absent", country: "JPN",
      sku: "summary.monthly", status: "renewal", subscription_status: "EXPIRED", auto_renew: "false",
      environment: "Production", charge_count: "2", install_from: "2026-10-02", install_to: "2026-09-30",
      purchase_from: "2026-10-14", purchase_to: "2026-10-12" })) {
      const changed = new URLSearchParams(filters);
      changed.set(name, value);
      if (name.endsWith("_from")) changed.delete(name.replace("_from", "_to"));
      if (name.endsWith("_to")) changed.delete(name.replace("_to", "_from"));
      const excluded = await get(changed.toString());
      expect(excluded.total, name).toBe(0);
      expect(excluded.summary, name).toEqual(EMPTY_SUMMARY);
    }
  });

  it("retains refunded rows but never adds their amounts to the non-refunded total", async () => {
    const data = await get("status=refunded");
    expect(data.total).toBe(2);
    expect(data.items.find((row) => row.order_id === "refund")?.amount_usd_micros).toBe(30000000);
    expect(data.summary).toEqual({ ...EMPTY_SUMMARY, refunded_amount_usd_micros: 30000000, missing_refunded_amount_count: 1 });
    const refundDay = await get("order_id=refund&purchase_from=2026-10-13&purchase_to=2026-10-13");
    expect(refundDay.total).toBe(1);
    expect(refundDay.summary).toEqual({ ...EMPTY_SUMMARY, refunded_amount_usd_micros: 30000000 });
  });

  it("distinguishes missing USD snapshots from free orders and empty results", async () => {
    expect((await get("order_id=missing")).summary).toEqual({ ...EMPTY_SUMMARY, amount_usd_micros: null, missing_amount_count: 1 });
    expect((await get("order_id=missing-refund")).summary).toEqual({ ...EMPTY_SUMMARY, refunded_amount_usd_micros: null, missing_refunded_amount_count: 1 });
    expect((await get("status=trial")).summary).toEqual(EMPTY_SUMMARY);
    const empty = await get("order_id=absent");
    expect(empty.total).toBe(0);
    expect(empty.summary).toEqual(EMPTY_SUMMARY);
  });

  it("uses current order status after a refund reversal and preserves unknown-status amounts", async () => {
    await db.exec("UPDATE billing_transaction SET business_status = 'initial_purchase' WHERE id = 'refund'");
    expect((await get()).summary).toEqual({ ...ALL_SUMMARY, amount_usd_micros: 158450000, refunded_amount_usd_micros: null });
    expect((await get("order_id=unknown")).summary).toEqual({ ...EMPTY_SUMMARY, amount_usd_micros: 3000000 });
  });

  it("sums stored USD micros without mixing original currencies or rounding each row", async () => {
    await db.exec("UPDATE billing_transaction SET amount_usd_micros = 1004900 WHERE id IN ('paid-a', 'paid-b')");
    const data = await get("status=initial_purchase,renewal&country=CHN,USA");
    expect(data.total).toBe(3);
    expect(data.summary).toEqual({ ...EMPTY_SUMMARY, amount_usd_micros: 2009800, missing_amount_count: 1 });
  });

  it("keeps product, notification and deployment environment boundaries for both totals", async () => {
    expect((await get()).summary).toEqual(ALL_SUMMARY);
    expect((await get("environment=Production")).summary).toEqual(EMPTY_SUMMARY);
    const production = await get("environment=Production", { ...env, APP_ENVIRONMENT: "production" });
    expect(production.total).toBe(1);
    expect(production.summary).toEqual({ ...EMPTY_SUMMARY, amount_usd_micros: 900000000 });
    expect((await get("order_id=unconfirmed")).summary).toEqual(EMPTY_SUMMARY);
    expect((await get("sku=other.product")).summary).toEqual(EMPTY_SUMMARY);
  });

  it("does not expose aggregate order amounts without Admin authentication or valid filters", async () => {
    expect((await app.request("/admin/billing/transactions", {}, env)).status).toBe(401);
    for (const query of ["auto_renew=invalid", "purchase_from=invalid", "charge_count=-1"]) {
      const response = await app.request("/admin/billing/transactions?" + query, { headers: { Authorization: "Bearer " + token } }, env);
      expect(response.status).toBe(422);
    }
  });
});
