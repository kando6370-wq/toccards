import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { PGliteDatabase } from "../../test-support/pglite-database";

const migrations = new URL("./migrations/", import.meta.url);

describe("PostgreSQL platform account isolation migration", () => {
  let db: PGliteDatabase;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
    await db.exec(`
      INSERT INTO "user" (id, email, created_at, updated_at, status)
      VALUES ('user-active', 'active@example.com', '2026-01-01', '2026-01-02', 'active'),
             ('user-disabled', 'disabled@example.com', '2026-01-01', '2026-01-02', 'disabled'),
             ('user-deleted', 'deleted@example.com', '2026-01-01', '2026-01-02', 'deleted'),
             ('user-deleted-reused', 'active@example.com', '2026-01-01', '2026-01-02', 'deleted');
      UPDATE "user" SET password_hash = 'legacy-password', display_name = 'Legacy User';
      INSERT INTO auth_identity (id, user_id, provider, provider_uid, created_at) VALUES
        ('identity-active', 'user-active', 'google', 'google-active', '2026-01-01'),
        ('identity-disabled', 'user-disabled', 'google', 'google-disabled', '2026-01-01'),
        ('identity-deleted', 'user-deleted', 'google', 'google-deleted', '2026-01-01'),
        ('identity-deleted-reused', 'user-deleted-reused', 'google', 'google-deleted-reused', '2026-01-01');
      INSERT INTO verification_code
        (id, email, code, purpose, expires_at, used_at, created_at)
      VALUES ('deleted-code', 'deleted@example.com', '123456', 'register', '2099-01-01', NULL, '2026-01-01'),
             ('reused-code', 'active@example.com', '654321', 'register', '2099-01-01', NULL, '2026-01-01');
      INSERT INTO anonymous_account (id, device_id, created_at, upgraded_user_id)
      VALUES ('anonymous-1', 'device-1', '2026-01-01', NULL);
      INSERT INTO session
        (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
      VALUES ('session-user', 'user', 'user-active', 'refresh-user', '2099-01-01', '2026-01-01', NULL),
             ('session-anonymous', 'anonymous', 'anonymous-1', 'refresh-anonymous', '2099-01-01', '2026-01-01', NULL);
    `);
    await db.exec(readFileSync(new URL("0018_platform_account_isolation.sql", migrations), "utf8"));
  });

  afterEach(async () => { await db.close(); });

  it("maps every live historical account and session to iOS without reviving deleted users", async () => {
    const accounts = await db.query<{
      id: string; user_id: string; platform: string; status: string;
    }>("SELECT id, user_id, platform, status FROM platform_account ORDER BY id");
    expect(accounts.rows).toEqual([
      { id: "user-active", user_id: "user-active", platform: "ios", status: "active" },
      { id: "user-disabled", user_id: "user-disabled", platform: "ios", status: "disabled" },
    ]);

    const sessions = await db.query<{
      id: string; platform: string; user_id: string | null;
    }>("SELECT id, platform, user_id FROM session ORDER BY id");
    expect(sessions.rows).toEqual([
      { id: "session-anonymous", platform: "ios", user_id: null },
      { id: "session-user", platform: "ios", user_id: "user-active" },
    ]);
    await expect(db.query<{ platform: string; status: string }>(
      "SELECT platform, status FROM anonymous_account WHERE id = 'anonymous-1'",
    ).then((result) => result.rows[0])).resolves.toEqual({ platform: "ios", status: "active" });
    const identities = await db.query<{ user_id: string }>(
      "SELECT user_id FROM auth_identity ORDER BY user_id",
    );
    expect(identities.rows).toEqual([
      { user_id: "user-active" }, { user_id: "user-disabled" },
    ]);
    const users = await db.query<{
      id: string; email: string; password_hash: string | null; display_name: string | null;
    }>(`SELECT id, email, password_hash, display_name FROM "user" ORDER BY id`);
    expect(users.rows).toEqual([
      { id: "user-active", email: "active@example.com", password_hash: "legacy-password", display_name: "Legacy User" },
      { id: "user-deleted", email: "deleted+user-deleted@invalid.cardai.local", password_hash: null, display_name: null },
      { id: "user-deleted-reused", email: "deleted+user-deleted-reused@invalid.cardai.local", password_hash: null, display_name: null },
      { id: "user-disabled", email: "disabled@example.com", password_hash: "legacy-password", display_name: "Legacy User" },
    ]);
    const deletedCodes = await db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM verification_code WHERE email = 'deleted@example.com'",
    );
    expect(deletedCodes.rows[0]?.total).toBe(0);
    const reusedCodes = await db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM verification_code WHERE email = 'active@example.com'",
    );
    expect(reusedCodes.rows[0]?.total).toBe(1);
  });

  it("allows a new generation after deletion but never two live accounts for one platform", async () => {
    await db.exec(`UPDATE platform_account SET status = 'deleted', deleted_at = '2026-11-05'
      WHERE id = 'user-active'`);
    await db.exec(`INSERT INTO platform_account
      (id, user_id, platform, status, created_at, updated_at)
      VALUES ('ios-generation-2', 'user-active', 'ios', 'active', '2026-11-05', '2026-11-05')`);
    await expect(db.exec(`INSERT INTO platform_account
      (id, user_id, platform, status, created_at, updated_at)
      VALUES ('ios-generation-3', 'user-active', 'ios', 'active', '2026-11-05', '2026-11-05')`))
      .rejects.toThrow();
  });

  it("separates platforms while preserving historical same-platform duplicate guests for deterministic reuse", async () => {
    await db.exec(`INSERT INTO anonymous_account
      (id, device_id, created_at, upgraded_user_id, platform, status)
      VALUES ('anonymous-android', 'device-1', '2026-11-05', NULL, 'android', 'active')`);
    await db.exec(`INSERT INTO anonymous_account
      (id, device_id, created_at, upgraded_user_id, platform, status)
      VALUES ('anonymous-android-2', 'device-1', '2026-11-05', NULL, 'android', 'active')`);
    const rows = await db.query<{ platform: string; total: number }>(`
      SELECT platform, COUNT(*)::int AS total FROM anonymous_account
      WHERE device_id = 'device-1' GROUP BY platform ORDER BY platform`);
    expect(rows.rows).toEqual([
      { platform: "android", total: 2 }, { platform: "ios", total: 1 },
    ]);
  });

  it("rejects writes after deletion starts because in-flight requests cannot recreate assets", async () => {
    await db.exec(`UPDATE platform_account SET status = 'deleting' WHERE id = 'user-active'`);
    await expect(db.exec(`INSERT INTO portfolio_folder
      (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('late-folder', 'user', 'user-active', 'Late', 0, 10, '2026-11-05', '2026-11-05')`))
      .rejects.toThrow(/business owner is not active/);
  });
});
