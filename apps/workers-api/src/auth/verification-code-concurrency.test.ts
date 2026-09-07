import { Hono } from "hono";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../mail/verification-email", () => ({
  sendVerificationEmail: vi.fn().mockResolvedValue("message-id"),
}));

import type { Env } from "../env";
import { sendVerificationEmail } from "../mail/verification-email";
import { registerForgotPasswordRoutes } from "./forgot-password";
import { registerEmailRegistrationRoutes } from "./register";

describe("verification code concurrency", () => {
  let mf: Miniflare;
  let db: D1Database;
  let app: Hono<{ Bindings: Env }>;
  let env: Env;

  beforeEach(async () => {
    vi.mocked(sendVerificationEmail).mockClear();
    mf = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      compatibilityDate: "2024-11-01",
      d1Databases: ["DB"],
    });
    db = await mf.getD1Database("DB");
    for (const statement of SCHEMA) await db.prepare(statement).run();
    app = new Hono<{ Bindings: Env }>();
    registerEmailRegistrationRoutes(app);
    registerForgotPasswordRoutes(app);
    env = {
      DB: db,
      CACHE_KV: {} as KVNamespace,
      JWT_SECRET: "verification-code-concurrency-test",
    };
  });

  afterEach(async () => mf.dispose());

  it("sends one registration email because normalized addresses share one resend window", async () => {
    const responses = await Promise.all([
      send("/register/send-code", "  Collector@Example.com "),
      send("/register/send-code", "collector@example.com"),
    ]);

    expect(responses.map((response) => response.status).sort()).toEqual([200, 429]);
    expect(sendVerificationEmail).toHaveBeenCalledTimes(1);
    const [, email, code, purpose] = vi.mocked(sendVerificationEmail).mock.calls[0]!;
    expect([email, code, purpose]).toEqual([
      "collector@example.com",
      expect.stringMatching(/^\d{6}$/),
      "register",
    ]);
    await expect(codeCount("register")).resolves.toBe(1);
    expect(await lockKeys()).toEqual([
      expect.stringMatching(/^verification-code-register:[0-9a-f]{64}$/),
    ]);
  });

  it("sends one reset email because concurrent requests must not bypass the resend window", async () => {
    await db.prepare(
      "INSERT INTO user (id, email, status, password_hash) VALUES ('100001', 'collector@example.com', 'active', 'hash')",
    ).run();

    const responses = await Promise.all([
      send("/forgot-password/send-code", "Collector@Example.com"),
      send("/forgot-password/send-code", " collector@example.com "),
    ]);

    expect(responses.map((response) => response.status).sort()).toEqual([200, 429]);
    expect(sendVerificationEmail).toHaveBeenCalledTimes(1);
    const [, email, code, purpose] = vi.mocked(sendVerificationEmail).mock.calls[0]!;
    expect([email, code, purpose]).toEqual([
      "collector@example.com",
      expect.stringMatching(/^\d{6}$/),
      "reset_password",
    ]);
    await expect(codeCount("reset_password")).resolves.toBe(1);
    expect(await lockKeys()).toEqual([
      expect.stringMatching(/^verification-code-reset-password:[0-9a-f]{64}$/),
    ]);
  });

  it("uses separate purpose locks because registration and reset have independent resend windows", async () => {
    const email = "purpose@example.com";
    expect((await send("/register/send-code", email)).status).toBe(200);
    await db.prepare(
      "INSERT INTO user (id, email, status, password_hash) VALUES ('100002', ?, 'active', 'hash')",
    ).bind(email).run();

    expect((await send("/forgot-password/send-code", email)).status).toBe(200);
    expect(await lockKeys()).toEqual([
      expect.stringMatching(/^verification-code-register:[0-9a-f]{64}$/),
      expect.stringMatching(/^verification-code-reset-password:[0-9a-f]{64}$/),
    ]);
    await expect(codeCount("register")).resolves.toBe(1);
    await expect(codeCount("reset_password")).resolves.toBe(1);
  });

  it.each([
    { path: "/register/send-code", purpose: "register", needsUser: false },
    { path: "/forgot-password/send-code", purpose: "reset_password", needsUser: true },
  ])("cleans a failed $purpose email so an immediate retry can succeed", async ({
    path,
    purpose,
    needsUser,
  }) => {
    const email = `${purpose}@example.com`;
    if (needsUser) {
      await db.prepare(
        "INSERT INTO user (id, email, status, password_hash) VALUES ('100003', ?, 'active', 'hash')",
      ).bind(email).run();
    }
    vi.mocked(sendVerificationEmail).mockRejectedValueOnce(new Error("mail failed"));
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);

    try {
      expect((await send(path, email)).status).toBe(500);
      await expect(codeCount(purpose)).resolves.toBe(0);
      expect((await send(path, email)).status).toBe(200);
      await expect(codeCount(purpose)).resolves.toBe(1);
      expect(sendVerificationEmail).toHaveBeenCalledTimes(2);
    } finally {
      errorSpy.mockRestore();
    }
  });

  it("does not send mail when lock persistence fails because rate limiting is server authoritative", async () => {
    await db.prepare("DROP TABLE mutation_lock").run();
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);

    try {
      const response = await send("/register/send-code", "lock-failure@example.com");

      expect(response.status).toBe(500);
      expect(sendVerificationEmail).not.toHaveBeenCalled();
      await expect(codeCount("register")).resolves.toBe(0);
    } finally {
      errorSpy.mockRestore();
    }
  });

  async function send(path: string, email: string): Promise<Response> {
    return app.request(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    }, env);
  }

  async function codeCount(purpose: string): Promise<number> {
    return await db.prepare(
      "SELECT COUNT(*) AS total FROM verification_code WHERE purpose = ?",
    ).bind(purpose).first<number>("total") ?? 0;
  }

  async function lockKeys(): Promise<string[]> {
    const result = await db.prepare(
      "SELECT lock_key FROM mutation_lock ORDER BY lock_key",
    ).all<{ lock_key: string }>();
    return result.results.map((row) => row.lock_key);
  }
});

const SCHEMA = [
  "CREATE TABLE mutation_lock (lock_key TEXT PRIMARY KEY)",
  "CREATE TABLE user (id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, status TEXT NOT NULL, password_hash TEXT)",
  "CREATE TABLE verification_code (id TEXT PRIMARY KEY, email TEXT NOT NULL, code TEXT NOT NULL, purpose TEXT NOT NULL, expires_at TEXT NOT NULL, used_at TEXT, created_at TEXT NOT NULL)",
];
