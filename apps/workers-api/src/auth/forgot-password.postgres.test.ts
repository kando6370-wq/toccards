import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword, verifyPassword } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { authRoutes } from "./anonymous";

const migrations = new URL("../db/postgres/migrations/", import.meta.url);

describe("PostgreSQL forgot-password flow", () => {
  let db: PGliteDatabase;
  let env: Env;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0006_mutation_lock.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0018_platform_account_isolation.sql", migrations), "utf8"));
    env = {
      DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "forgot-password-secret",
      ZEPTOMAIL_TOKEN: "test-token", ZEPTOMAIL_API_URL: "https://mail.test/send",
      MAIL_FROM_ADDRESS: "support@example.com", MAIL_FROM_NAME: "Card AI",
    };
    vi.stubGlobal("fetch", vi.fn(async () => new Response(
      JSON.stringify({ request_id: "mail-request" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    )));
  });

  afterEach(async () => { vi.unstubAllGlobals(); await db.close(); });

  it("sends one normalized reset proof and rate limits an immediate resend", async () => {
    await user("owner", "owner@example.com", "password-1");
    expect((await send("  OWNER@EXAMPLE.COM ")).status).toBe(200);
    expect((await send("owner@example.com")).status).toBe(429);
    const rows = await db.query<{ email: string; purpose: string }>(
      "SELECT email, purpose FROM verification_code",
    );
    expect(rows.rows).toEqual([{ email: "owner@example.com", purpose: "reset_password" }]);
  });

  it("serializes concurrent reset-code requests at the persistence boundary", async () => {
    await user("owner", "owner@example.com", "password-1");
    const responses = await Promise.all([
      send("owner@example.com"), send("owner@example.com"),
    ]);
    expect(responses.map((response) => response.status).sort()).toEqual([200, 429]);
    const count = await db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM verification_code",
    );
    expect(count.rows[0]?.total).toBe(1);
  });

  it("rejects unknown, OAuth-only, deleted, and disabled identities", async () => {
    await user("oauth", "oauth@example.com", null);
    await user("deleted", "deleted@example.com", "password-1", "deleted");
    await user("disabled", "disabled@example.com", "password-1", "disabled");
    for (const email of [
      "unknown@example.com", "oauth@example.com", "deleted@example.com", "disabled@example.com",
    ]) expect((await send(email)).status).toBe(422);
  });

  it("mints a reset token from the latest code, changes the shared password once, and rejects replay", async () => {
    await user("owner", "owner@example.com", "password-1");
    await code("old", "owner@example.com", "111111", "2026-11-05T00:00:00Z");
    await code("new", "owner@example.com", "222222", new Date().toISOString());
    expect((await verify("owner@example.com", "111111")).status).toBe(422);
    const verified = await verify("owner@example.com", "222222");
    expect(verified.status).toBe(200);
    const resetToken = ((await verified.json()) as { data: { reset_token: string } }).data.reset_token;
    const reset = () => authRoutes.request("/forgot-password/reset", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email: "owner@example.com", new_password: "password-2", reset_token: resetToken,
      }),
    }, env);
    expect((await reset()).status).toBe(200);
    const consumed = await db.query<{ used_at: string | null }>(
      "SELECT used_at FROM verification_code WHERE id = 'new'",
    );
    expect(consumed.rows[0]?.used_at).not.toBeNull();
    expect((await reset()).status).toBe(422);
    const stored = await db.query<{ password_hash: string }>(
      `SELECT password_hash FROM "user" WHERE id = 'owner'`,
    );
    expect(await verifyPassword("password-2", stored.rows[0]!.password_hash)).toBe(true);
  });

  it("uses code id as a stable tie-breaker when migrated reset proofs share a timestamp", async () => {
    await user("owner", "owner@example.com", "password-1");
    const timestamp = new Date().toISOString();
    await code("a-code", "owner@example.com", "111111", timestamp);
    await code("b-code", "owner@example.com", "222222", timestamp);
    expect((await verify("owner@example.com", "222222")).status).toBe(422);
    expect((await verify("owner@example.com", "111111")).status).toBe(200);
  });

  it("rejects wrong and expired codes without minting reset authority", async () => {
    await user("owner", "owner@example.com", "password-1");
    await code("expired", "owner@example.com", "222222", "2026-11-05T00:00:00Z", "2000-01-01");
    expect((await verify("owner@example.com", "111111")).status).toBe(422);
    expect((await verify("owner@example.com", "222222")).status).toBe(422);
  });

  it("removes the persisted proof when mail delivery fails so a retry is not falsely throttled", async () => {
    await user("owner", "owner@example.com", "password-1");
    vi.stubGlobal("fetch", vi.fn(async () => new Response(
      JSON.stringify({}), { status: 503, headers: { "Content-Type": "application/json" } },
    )));
    expect((await send("owner@example.com")).status).toBe(500);
    const count = await db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM verification_code",
    );
    expect(count.rows[0]?.total).toBe(0);
  });

  async function user(
    id: string, email: string, password: string | null, status = "active",
  ): Promise<void> {
    const passwordHash = password ? await hashPassword(password) : null;
    await db.prepare(`INSERT INTO "user"
      (id, email, password_hash, created_at, updated_at, status)
      VALUES (?, ?, ?, '2026-11-05', '2026-11-05', ?)`)
      .bind(id, email, passwordHash, status).run();
  }

  async function code(
    id: string, email: string, value: string, createdAt: string, expiresAt = "2099-01-01",
  ): Promise<void> {
    await db.prepare(`INSERT INTO verification_code
      (id, email, code, purpose, expires_at, used_at, created_at)
      VALUES (?, ?, ?, 'reset_password', ?, NULL, ?)`)
      .bind(id, email, value, expiresAt, createdAt).run();
  }

  async function send(email: string): Promise<Response> {
    return await authRoutes.request("/forgot-password/send-code", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    }, env);
  }

  async function verify(email: string, value: string): Promise<Response> {
    return await authRoutes.request("/forgot-password/verify-code", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, code: value }),
    }, env);
  }
});
