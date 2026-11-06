import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword, signAccessToken, verifyPassword } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { authRoutes } from "./anonymous";

const migrations = new URL("../db/postgres/migrations/", import.meta.url);
const JWT_SECRET = "email-auth-postgres-secret";

describe("PostgreSQL email authentication", () => {
  let db: PGliteDatabase;
  let env: Env;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0006_mutation_lock.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0018_platform_account_isolation.sql", migrations), "utf8"));
    env = {
      DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET,
      ZEPTOMAIL_TOKEN: "test-token", ZEPTOMAIL_API_URL: "https://mail.test/send",
      MAIL_FROM_ADDRESS: "support@example.com", MAIL_FROM_NAME: "Card AI",
    };
    vi.stubGlobal("fetch", vi.fn(async () => new Response(
      JSON.stringify({ request_id: "mail-request" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    )));
  });
  afterEach(async () => { vi.unstubAllGlobals(); await db.close(); });

  it("normalizes and persists one register proof while active platform duplicates stay 409", async () => {
    const sent = await sendCode("  NEW@EXAMPLE.COM ");
    expect(sent.status).toBe(200);
    const codes = await db.query<{ email: string; purpose: string }>(
      "SELECT email, purpose FROM verification_code",
    );
    expect(codes.rows).toEqual([{ email: "new@example.com", purpose: "register" }]);
    await seedUser("active", "active@example.com", "password-1");
    await platform("active", "active", "ios", "active");
    expect((await sendCode("active@example.com")).status).toBe(409);
  });

  it.each([
    [{}, "Please enter your email."],
    [{ email: "   " }, "Please enter your email."],
    [{ email: 42 }, "Please enter your email."],
    [{ email: "not-an-email" }, "Please enter a valid email address."],
    [{ email: `${"a".repeat(244)}@example.com` }, "Please enter a valid email address."],
  ])("rejects unusable register inbox input %# without persisting a code", async (body, message) => {
    const response = await authRoutes.request("/register/send-code", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...body, platform: "ios" }),
    }, env);
    expect(response.status).toBe(422);
    await expect(response.json()).resolves.toMatchObject({ error: { message } });
    const count = await db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM verification_code",
    );
    expect(count.rows[0]?.total).toBe(0);
  });

  it("allows a deleted platform to request a new code and keeps newest-code ordering deterministic", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await platform("old-ios", "shared", "ios", "deleted");
    await db.exec(`INSERT INTO verification_code
      (id, email, code, purpose, expires_at, used_at, created_at)
      VALUES ('older', 'shared@example.com', '111111', 'register', '2099-01-01', NULL, '2000-01-01')`);
    expect((await sendCode("shared@example.com")).status).toBe(200);
    const latest = await db.query<{ id: string }>(
      "SELECT id FROM verification_code WHERE email = 'shared@example.com' ORDER BY created_at DESC, id ASC LIMIT 1",
    );
    expect(latest.rows[0]?.id).not.toBe("older");
    expect((await register("shared@example.com", "111111", "password-1")).status).toBe(422);
    const newest = await db.query<{ code: string }>(
      "SELECT code FROM verification_code WHERE email = 'shared@example.com' ORDER BY created_at DESC, id ASC LIMIT 1",
    );
    expect((await register("shared@example.com", newest.rows[0]!.code, "password-1")).status).toBe(200);
  });

  it("allows a globally deleted email to create a new base identity without reviving the tombstone", async () => {
    await seedUser("deleted", "reuse@example.com", "password-1", "deleted");
    expect((await sendCode("reuse@example.com")).status).toBe(200);
    const latest = await db.query<{ id: string; code: string }>(
      "SELECT id, code FROM verification_code WHERE email = 'reuse@example.com' ORDER BY created_at DESC, id ASC LIMIT 1",
    );
    const response = await register("reuse@example.com", latest.rows[0]!.code, "password-2");
    expect(response.status).toBe(200);
    const users = await db.query<{ id: string; status: string }>(
      `SELECT id, status FROM "user" WHERE email = 'reuse@example.com' OR id = 'deleted' ORDER BY id`,
    );
    expect(users.rows).toHaveLength(2);
    expect(users.rows.find((row) => row.id === "deleted")?.status).toBe("deleted");
  });

  it("uses code id as the deterministic tie-breaker and consumes a code only once under concurrency", async () => {
    const timestamp = new Date().toISOString();
    await db.exec(`INSERT INTO verification_code
      (id, email, code, purpose, expires_at, used_at, created_at) VALUES
      ('a-code', 'tie@example.com', '111111', 'register', '2099-01-01', NULL, '${timestamp}'),
      ('b-code', 'tie@example.com', '222222', 'register', '2099-01-01', NULL, '${timestamp}')`);
    expect((await register("tie@example.com", "222222", "password-1")).status).toBe(422);
    const results = await Promise.all([
      register("tie@example.com", "111111", "password-1"),
      register("tie@example.com", "111111", "password-1"),
    ]);
    const statuses = results.map((response) => response.status);
    const payloads = await Promise.all(results.map((response) => response.clone().json()));
    expect(statuses.filter((status) => status === 200), JSON.stringify({ statuses, payloads })).toHaveLength(1);
    expect(statuses.filter((status) => status === 422 || status === 409)).toHaveLength(1);
    const count = await db.query<{ total: number }>(
      `SELECT COUNT(*)::int AS total FROM "user" WHERE email = 'tie@example.com'`,
    );
    expect(count.rows[0]?.total).toBe(1);
  });

  it("keeps register lookup and persistence failures loud and retryable", async () => {
    await db.exec(`DROP TABLE "user" CASCADE`);
    expect((await sendCode("lookup@example.com")).status).toBe(500);
  });

  it("returns a retryable error when register-code persistence is unavailable", async () => {
    await db.exec("DROP TABLE verification_code");
    expect((await sendCode("persist@example.com")).status).toBe(500);
  });

  it("creates a new iOS user and platform account only after consuming the newest email proof", async () => {
    await verification("new@example.com", "123456");
    const response = await register("new@example.com", "123456", "password-1");
    expect(response.status).toBe(200);
    const body = await response.json() as { data: {
      user_id: string; data_space_id: string; platform: string; access_token: string;
    } };
    expect(body.data).toMatchObject({ platform: "ios" });
    expect(body.data.data_space_id).toBe(body.data.user_id);
    const current = await me(body.data.access_token);
    expect(current.status).toBe(200);
    await expect(current.json()).resolves.toMatchObject({ data: {
      owner_type: "user", user_id: body.data.user_id, anonymous_id: null,
      platform: "ios", data_space_id: body.data.data_space_id,
    } });
    expect((await register("new@example.com", "123456", "password-1")).status).toBe(422);
  });

  it("re-registers a deleted platform with the shared password and a new owner generation", async () => {
    const passwordHash = await seedUser("shared", "shared@example.com", "password-1");
    await platform("old-ios", "shared", "ios", "deleted");
    await verification("shared@example.com", "123456");
    expect((await register("shared@example.com", "123456", "wrong-password")).status).toBe(422);
    const response = await register("shared@example.com", "123456", "password-1");
    expect(response.status).toBe(200);
    const body = await response.json() as { data: { user_id: string; data_space_id: string } };
    expect(body.data.user_id).toBe("shared");
    expect(body.data.data_space_id).not.toBe("old-ios");
    const user = await db.query<{ password_hash: string }>(
      `SELECT password_hash FROM "user" WHERE id = 'shared'`,
    );
    expect(user.rows[0]?.password_hash).toBe(passwordHash);
  });

  it("rejects expired, reused, and short-password registration proofs without creating credentials", async () => {
    await verification("expired@example.com", "123456", "2000-01-01T00:00:00Z");
    expect((await register("expired@example.com", "123456", "password-1")).status).toBe(422);
    await verification("short@example.com", "123456");
    expect((await register("short@example.com", "123456", "short")).status).toBe(422);
    await verification("used@example.com", "123456", "2099-01-01T00:00:00Z", "2026-11-05");
    expect((await register("used@example.com", "123456", "password-1")).status).toBe(422);
    const count = await db.query<{ total: number }>(`SELECT COUNT(*)::int AS total FROM "user"`);
    expect(count.rows[0]?.total).toBe(0);
  });

  it("normalizes email and returns one password error for unknown, wrong, deleted, and OAuth-only users", async () => {
    await seedUser("active", "active@example.com", "password-1");
    await platform("active", "active", "ios", "active");
    const normalized = await login("  ACTIVE@EXAMPLE.COM ", "password-1");
    expect(normalized.status).toBe(200);
    const normalizedBody = await normalized.json() as { data: {
      user_id: string; platform: string; data_space_id: string;
      access_token: string; refresh_token: string;
    } };
    expect(normalizedBody.data).toMatchObject({
      user_id: "active", platform: "ios", data_space_id: "active",
    });
    expect(normalizedBody.data.access_token).toBeTruthy();
    expect(normalizedBody.data.refresh_token).toBeTruthy();
    const loginSession = await db.query<{ owner_id: string; user_id: string; platform: string }>(
      "SELECT owner_id, user_id, platform FROM session WHERE user_id = 'active' ORDER BY created_at DESC LIMIT 1",
    );
    expect(loginSession.rows[0]).toEqual({ owner_id: "active", user_id: "active", platform: "ios" });

    await seedUser("deleted", "deleted@example.com", "password-1", "deleted");
    await db.exec(`INSERT INTO "user" (id, email, password_hash, created_at, updated_at, status)
      VALUES ('oauth-only', 'oauth@example.com', NULL, '2026-11-05', '2026-11-05', 'active')`);
    for (const [email, password] of [
      ["unknown@example.com", "password-1"],
      ["active@example.com", "wrong-password"],
      ["deleted@example.com", "password-1"],
      ["oauth@example.com", "password-1"],
    ]) {
      const before = await db.query<{ total: number }>("SELECT COUNT(*)::int AS total FROM session");
      const response = await login(email, password);
      expect(response.status).toBe(422);
      await expect(response.json()).resolves.toMatchObject({
        error: { code: "VALIDATION_ERROR", message: "Incorrect password. Please try again." },
      });
      const after = await db.query<{ total: number }>("SELECT COUNT(*)::int AS total FROM session");
      expect(after.rows[0]?.total).toBe(before.rows[0]?.total);
    }
  });

  it.each([
    ["", "password-1"],
    ["invalid", "password-1"],
    [`${"a".repeat(250)}@x.com`, "password-1"],
    ["active@example.com", ""],
  ])("rejects malformed login input without creating a session %#", async (email, password) => {
    const response = await login(email, password);
    expect(response.status).toBe(422);
    const count = await db.query<{ total: number }>("SELECT COUNT(*)::int AS total FROM session");
    expect(count.rows[0]?.total).toBe(0);
  });

  it("fails loudly when signing or session persistence is unavailable", async () => {
    await seedUser("active", "active@example.com", "password-1");
    await platform("active", "active", "ios", "active");
    const secret = env.JWT_SECRET;
    env.JWT_SECRET = "";
    expect((await login("active@example.com", "password-1")).status).toBe(500);
    env.JWT_SECRET = secret;
    await db.exec("DROP TABLE session CASCADE");
    expect((await login("active@example.com", "password-1")).status).toBe(500);
  });

  it("does not consume registration proof when JWT signing is unavailable", async () => {
    await verification("config@example.com", "123456");
    env.JWT_SECRET = "";
    expect((await register("config@example.com", "123456", "password-1")).status).toBe(500);
    const code = await db.query<{ used_at: string | null }>(
      "SELECT used_at FROM verification_code WHERE email = 'config@example.com'",
    );
    expect(code.rows[0]?.used_at).toBeNull();
  });

  it("rolls back code, user, and platform creation when a real database constraint aborts registration", async () => {
    await verification("rollback@example.com", "123456");
    await db.exec(`CREATE FUNCTION reject_default_folder() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'injected folder failure'; END $$;
      CREATE TRIGGER reject_default_folder BEFORE INSERT ON portfolio_folder
      FOR EACH ROW EXECUTE FUNCTION reject_default_folder();`);
    expect((await register("rollback@example.com", "123456", "password-1")).status).toBe(500);
    const state = await db.query<{ users: number; accounts: number; used: number }>(`
      SELECT (SELECT COUNT(*) FROM "user" WHERE email = 'rollback@example.com')::int AS users,
        (SELECT COUNT(*) FROM platform_account)::int AS accounts,
        (SELECT COUNT(*) FROM verification_code WHERE email = 'rollback@example.com' AND used_at IS NOT NULL)::int AS used`);
    expect(state.rows[0]).toEqual({ users: 0, accounts: 0, used: 0 });
  });

  it("returns stale guest without consuming proof when the guest is claimed during registration", async () => {
    await db.exec(`
      INSERT INTO anonymous_account
        (id, device_id, created_at, upgraded_user_id, platform, status)
      VALUES ('racing-guest', 'racing-device', '2026-11-05', NULL, 'ios', 'active');
      INSERT INTO session
        (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES ('racing-session', 'anonymous', 'racing-guest', 'racing-refresh', '2099-01-01', '2026-11-05', 'ios', NULL);
      CREATE FUNCTION claim_guest_on_code_use() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN UPDATE anonymous_account SET upgraded_user_id = 'concurrent-owner'
          WHERE id = 'racing-guest'; RETURN NEW; END $$;
      CREATE TRIGGER claim_guest_on_code_use BEFORE UPDATE ON verification_code
        FOR EACH ROW EXECUTE FUNCTION claim_guest_on_code_use();
    `);
    const access = await signAccessToken({
      owner_type: "anonymous", owner_id: "racing-guest", session_id: "racing-session",
    }, JWT_SECRET, new Date());
    await verification("race@example.com", "123456");
    const response = await register(
      "race@example.com", "123456", "password-1", "racing-guest", access,
    );
    expect(response.status).toBe(422);
    const state = await db.query<{ upgraded_user_id: string | null; used_at: string | null }>(`
      SELECT a.upgraded_user_id, v.used_at FROM anonymous_account a
      CROSS JOIN verification_code v WHERE a.id = 'racing-guest' AND v.email = 'race@example.com'`);
    expect(state.rows[0]).toEqual({ upgraded_user_id: null, used_at: null });
  });

  it("returns 500 when login user lookup fails before issuing credentials", async () => {
    await db.exec(`DROP TABLE "user" CASCADE`);
    expect((await login("lookup@example.com", "password-1")).status).toBe(500);
  });

  it("does not issue a session for an active platform duplicate or a globally disabled identity", async () => {
    await seedUser("active", "active@example.com", "password-1");
    await platform("active", "active", "ios", "active");
    await verification("active@example.com", "123456");
    expect((await register("active@example.com", "123456", "password-1")).status).toBe(409);
    await seedUser("disabled", "disabled@example.com", "password-1", "disabled");
    await verification("disabled@example.com", "123456");
    expect((await register("disabled@example.com", "123456", "password-1")).status).toBe(409);
  });

  it("moves only a proven same-platform guest into a newly registered platform account", async () => {
    await db.exec(`
      INSERT INTO anonymous_account
        (id, device_id, created_at, upgraded_user_id, platform, status)
      VALUES ('guest-ios', 'device-ios', '2026-11-05', NULL, 'ios', 'active');
      INSERT INTO portfolio_folder
        (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('guest-folder', 'anonymous', 'guest-ios', 'Guest', 1, 0, '2026-11-05', '2026-11-05');
      INSERT INTO session
        (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES ('guest-session', 'anonymous', 'guest-ios', 'guest-refresh', '2099-01-01', '2026-11-05', 'ios', NULL);
    `);
    const access = await signAccessToken(
      { owner_type: "anonymous", owner_id: "guest-ios", session_id: "guest-session" },
      JWT_SECRET,
      new Date(),
    );
    await verification("guest@example.com", "123456");
    const response = await register(
      "guest@example.com", "123456", "password-1", "guest-ios", access,
    );
    expect(response.status).toBe(200);
    const body = await response.json() as { data: { data_space_id: string; migrated: boolean } };
    expect(body.data).toMatchObject({ data_space_id: "guest-ios", migrated: true });
    const folder = await db.query<{ owner_type: string; owner_id: string }>(
      "SELECT owner_type, owner_id FROM portfolio_folder WHERE id = 'guest-folder'",
    );
    expect(folder.rows[0]).toEqual({ owner_type: "user", owner_id: "guest-ios" });
  });

  it("does not migrate a guest from an id alone, a mismatched token, or a stale session", async () => {
    for (const mode of ["missing", "mismatch", "revoked", "expired"] as const) {
      const guestId = `guest-${mode}`;
      const sessionId = `session-${mode}`;
      await db.prepare(`INSERT INTO anonymous_account
        (id, device_id, created_at, upgraded_user_id, platform, status)
        VALUES (?, ?, '2026-11-05', NULL, 'ios', 'active')`)
        .bind(guestId, `device-${mode}`).run();
      await db.prepare(`INSERT INTO session
        (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at, platform, user_id)
        VALUES (?, 'anonymous', ?, ?, ?, '2026-11-05', ?, 'ios', NULL)`)
        .bind(
          sessionId,
          guestId,
          `refresh-${mode}`,
          mode === "expired" ? "2000-01-01" : "2099-01-01",
          mode === "revoked" ? "2026-11-05" : null,
        ).run();
      let accessToken: string | undefined;
      if (mode !== "missing") {
        accessToken = await signAccessToken({
          owner_type: "anonymous",
          owner_id: mode === "mismatch" ? "another-owner" : guestId,
          session_id: sessionId,
        }, JWT_SECRET, new Date());
      }
      const email = `${mode}@example.com`;
      await verification(email, "123456");
      const response = await register(email, "123456", "password-1", guestId, accessToken);
      expect(response.status).toBe(200);
      const body = await response.json() as { data: { data_space_id: string; migrated: boolean } };
      expect(body.data.migrated).toBe(false);
      expect(body.data.data_space_id).not.toBe(guestId);
      const guest = await db.query<{ upgraded_user_id: string | null }>(
        "SELECT upgraded_user_id FROM anonymous_account WHERE id = $1", [guestId],
      );
      expect(guest.rows[0]?.upgraded_user_id).toBeNull();
    }
  });

  it("lets legacy iOS authenticate with a stale guest token without migrating that guest", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await platform("shared", "shared", "ios", "active");
    await db.exec(`
      INSERT INTO anonymous_account
        (id, device_id, created_at, upgraded_user_id, platform, status)
      VALUES ('stale-guest', 'stale-device', '2026-11-05', NULL, 'ios', 'active');
      INSERT INTO session
        (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES ('stale-session', 'anonymous', 'stale-guest', 'stale-refresh', '2000-01-01', '2026-11-05', 'ios', NULL);
    `);
    const staleAccess = await signAccessToken({
      owner_type: "anonymous", owner_id: "stale-guest", session_id: "stale-session",
    }, JWT_SECRET, new Date());
    const response = await authRoutes.request("/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json", Authorization: `Bearer ${staleAccess}`,
      },
      body: JSON.stringify({
        email: "shared@example.com", password: "password-1", platform: "ios",
      }),
    }, env);
    expect(response.status).toBe(200);
    const guest = await db.query<{ upgraded_user_id: string | null }>(
      "SELECT upgraded_user_id FROM anonymous_account WHERE id = 'stale-guest'",
    );
    expect(guest.rows[0]?.upgraded_user_id).toBeNull();
  });

  it("lets an Android OAuth-only identity set the shared password once without changing iOS identity or data", async () => {
    await db.exec(`
      INSERT INTO "user" (id, email, password_hash, created_at, updated_at, status)
      VALUES ('oauth-user', 'oauth@example.com', NULL, '2026-11-05', '2026-11-05', 'active');
      INSERT INTO platform_account (id, user_id, platform, status, created_at, updated_at)
      VALUES ('ios-space', 'oauth-user', 'ios', 'active', '2026-11-05', '2026-11-05');
      INSERT INTO auth_identity (id, user_id, provider, provider_uid, created_at)
      VALUES ('apple-identity', 'oauth-user', 'apple', 'apple-oauth-user', '2026-11-05');
      INSERT INTO portfolio_folder
        (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('ios-folder', 'user', 'ios-space', 'Main', 1, 0, '2026-11-05', '2026-11-05');
    `);
    const android = await seedAnonymousAuth("oauth-android", "oauth-android-session");
    await verification("oauth@example.com", "123456");
    const response = await register(
      "oauth@example.com", "123456", "shared-password", "oauth-android", android,
      "android",
    );
    expect(response.status).toBe(200);
    const user = await db.query<{ password_hash: string; identities: number; ios_folders: number }>(`
      SELECT u.password_hash,
        (SELECT COUNT(*) FROM auth_identity WHERE user_id = u.id)::int AS identities,
        (SELECT COUNT(*) FROM portfolio_folder WHERE owner_id = 'ios-space')::int AS ios_folders
      FROM "user" u WHERE u.id = 'oauth-user'`);
    expect(await verifyPassword("shared-password", user.rows[0]!.password_hash)).toBe(true);
    expect(user.rows[0]).toMatchObject({ identities: 1, ios_folders: 1 });
  });

  it("never overwrites an existing shared password when Android opens its first platform space", async () => {
    const originalHash = await seedUser("shared", "shared-first@example.com", "original-password");
    await platform("ios-space", "shared", "ios", "active");
    const android = await seedAnonymousAuth("shared-android", "shared-android-session");
    await verification("shared-first@example.com", "123456");
    expect((await register(
      "shared-first@example.com", "123456", "original-password",
      "shared-android", android, "android",
    )).status).toBe(200);
    const user = await db.query<{ password_hash: string }>(
      `SELECT password_hash FROM "user" WHERE id = 'shared'`,
    );
    expect(user.rows[0]?.password_hash).toBe(originalHash);
  });

  it("rolls back first shared-password setup when Android platform creation fails", async () => {
    await db.exec(`INSERT INTO "user"
      (id, email, password_hash, created_at, updated_at, status)
      VALUES ('oauth-user', 'oauth-fail@example.com', NULL, '2026-11-05', '2026-11-05', 'active');
      CREATE FUNCTION reject_android_platform() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN RAISE EXCEPTION 'android platform failure'; END $$;
      CREATE TRIGGER reject_android_platform BEFORE INSERT ON platform_account
        FOR EACH ROW EXECUTE FUNCTION reject_android_platform();`);
    const android = await seedAnonymousAuth("fail-android", "fail-android-session");
    await verification("oauth-fail@example.com", "123456");
    expect((await register(
      "oauth-fail@example.com", "123456", "shared-password",
      "fail-android", android, "android",
    )).status).toBe(500);
    const state = await db.query<{
      password_hash: string | null; used_at: string | null; platforms: number;
    }>(`SELECT u.password_hash, v.used_at,
        (SELECT COUNT(*) FROM platform_account WHERE user_id = u.id)::int AS platforms
      FROM "user" u JOIN verification_code v ON v.email = u.email
      WHERE u.id = 'oauth-user'`);
    expect(state.rows[0]).toEqual({ password_hash: null, used_at: null, platforms: 0 });
  });

  it("serializes concurrent Android first-password setup so only one registration succeeds", async () => {
    await db.exec(`INSERT INTO "user"
      (id, email, password_hash, created_at, updated_at, status)
      VALUES ('oauth-user', 'oauth-race@example.com', NULL, '2026-11-05', '2026-11-05', 'active')`);
    const first = await seedAnonymousAuth("race-android-1", "race-android-session-1");
    const second = await seedAnonymousAuth("race-android-2", "race-android-session-2");
    await verification("oauth-race@example.com", "123456");
    const responses = await Promise.all([
      register("oauth-race@example.com", "123456", "shared-password", "race-android-1", first, "android"),
      register("oauth-race@example.com", "123456", "shared-password", "race-android-2", second, "android"),
    ]);
    const statuses = responses.map((response) => response.status);
    expect(statuses.filter((status) => status === 200)).toHaveLength(1);
    expect(statuses.filter((status) => status !== 200)).toHaveLength(1);
    const user = await db.query<{ password_hash: string; platforms: number }>(`
      SELECT u.password_hash,
        (SELECT COUNT(*) FROM platform_account WHERE user_id = u.id AND platform = 'android')::int AS platforms
      FROM "user" u WHERE u.id = 'oauth-user'`);
    expect(await verifyPassword("shared-password", user.rows[0]!.password_hash)).toBe(true);
    expect(user.rows[0]?.platforms).toBe(1);
  });

  async function register(
    email: string,
    code: string,
    password: string,
    anonymousId?: string,
    accessToken?: string,
    requestedPlatform = "ios",
  ): Promise<Response> {
    return await authRoutes.request("/register/verify", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
      },
      body: JSON.stringify({
        email, code, password, platform: requestedPlatform, anonymous_id: anonymousId,
      }),
    }, env);
  }

  async function sendCode(email: string): Promise<Response> {
    return await authRoutes.request("/register/send-code", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, platform: "ios" }),
    }, env);
  }

  async function login(email: string, password: string): Promise<Response> {
    return await authRoutes.request("/login", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, platform: "ios" }),
    }, env);
  }

  async function me(accessToken: string): Promise<Response> {
    return await authRoutes.request("/me", {
      headers: { Authorization: `Bearer ${accessToken}` },
    }, env);
  }

  async function verification(
    email: string, code: string, expiresAt = "2099-01-01T00:00:00Z", usedAt: string | null = null,
  ): Promise<void> {
    await db.prepare(`INSERT INTO verification_code
      (id, email, code, purpose, expires_at, used_at, created_at)
      VALUES (?, ?, ?, 'register', ?, ?, '2026-11-05')`)
      .bind(`code-${email}`, email, code, expiresAt, usedAt).run();
  }

  async function seedUser(
    id: string, email: string, password: string, status = "active",
  ): Promise<string> {
    const passwordHash = await hashPassword(password);
    await db.prepare(`INSERT INTO "user"
      (id, email, password_hash, created_at, updated_at, status)
      VALUES (?, ?, ?, '2026-11-05', '2026-11-05', ?)`)
      .bind(id, email, passwordHash, status).run();
    return passwordHash;
  }

  async function platform(id: string, userId: string, value: string, status: string): Promise<void> {
    await db.prepare(`INSERT INTO platform_account
      (id, user_id, platform, status, created_at, updated_at, deleted_at)
      VALUES (?, ?, ?, ?, '2026-11-05', '2026-11-05',
        CASE WHEN ? = 'deleted' THEN '2026-11-05' ELSE NULL END)`)
      .bind(id, userId, value, status, status).run();
  }

  async function seedAnonymousAuth(ownerId: string, sessionId: string): Promise<string> {
    await db.prepare(`INSERT INTO anonymous_account
      (id, device_id, created_at, upgraded_user_id, platform, status)
      VALUES (?, ?, '2026-11-05', NULL, 'android', 'active')`)
      .bind(ownerId, `device-${ownerId}`).run();
    await db.prepare(`INSERT INTO session
      (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES (?, 'anonymous', ?, ?, '2099-01-01', '2026-11-05', 'android', NULL)`)
      .bind(sessionId, ownerId, `refresh-${sessionId}`).run();
    await db.prepare(`INSERT INTO portfolio_folder
      (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES (?, 'anonymous', ?, 'Main', 1, 0, '2026-11-05', '2026-11-05')`)
      .bind(`folder-${ownerId}`, ownerId).run();
    await db.prepare(`INSERT INTO user_preference
      (id, owner_type, owner_id, currency, amount_hidden, created_at, updated_at)
      VALUES (?, 'anonymous', ?, 'USD', 0, '2026-11-05', '2026-11-05')`)
      .bind(`preference-${ownerId}`, ownerId).run();
    return signAccessToken(
      { owner_type: "anonymous", owner_id: ownerId, session_id: sessionId },
      JWT_SECRET,
      new Date(),
    );
  }
});
