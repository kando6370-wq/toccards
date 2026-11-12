import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword, hashRefreshToken, signAccessToken } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { createPortfolioRoutes } from "../portfolio/routes";
import { PGliteDatabase } from "../test-support/pglite-database";
import { authRoutes } from "./anonymous";
import { completeOAuthAccountFlow } from "./account-flow";

const JWT_SECRET = "platform-account-flow-postgres-secret";
const migrations = new URL("../db/postgres/migrations/", import.meta.url);

describe("platform account authentication and deletion", () => {
  let db: PGliteDatabase;
  let env: Env;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0001_price_domain.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0006_mutation_lock.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0008_collection_item_grading_identity.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0018_platform_account_isolation.sql", migrations), "utf8"));
    env = {
      DB: db,
      CACHE_KV: {} as KVNamespace,
      JWT_SECRET,
      SCAN_IMAGES: { delete: async () => undefined } as unknown as R2Bucket,
    };
  });

  afterEach(async () => { await db.close(); });

  it("opens an empty Android space for an existing iOS identity and keeps both owners separate", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("shared", "shared", "ios", "active");
    await db.exec(`
      INSERT INTO portfolio_folder
        (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('ios-folder', 'user', 'shared', 'Main', 1, 0, '2026-11-05', '2026-11-05');
      INSERT INTO user_preference
        (id, owner_type, owner_id, currency, amount_hidden, created_at, updated_at)
      VALUES ('ios-preference', 'user', 'shared', 'USD', 0, '2026-11-05', '2026-11-05');
      INSERT INTO collection_item
        (id, owner_type, owner_id, folder_id, card_ref, object_type, grader, quantity, created_at, updated_at)
      VALUES ('ios-item', 'user', 'shared', 'ios-folder', 'ios-card', 'tcg', 'Raw', 1,
        '2026-11-05', '2026-11-05');
    `);
    const ios = await seedUserSession("shared", "shared", "ios", "ios-session");
    const anonymousToken = await seedAnonymousAndroidSession("android-guest", "android-session");

    const response = await authRoutes.request("/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${anonymousToken}`,
      },
      body: JSON.stringify({
        email: "shared@example.com", password: "password-1", platform: "android",
      }),
    }, env);
    expect(response.status).toBe(200);
    const body = await response.json() as { data: {
      user_id: string; data_space_id: string; platform: string; access_token: string;
    } };
    expect(body.data).toMatchObject({ user_id: "shared", platform: "android" });
    expect(body.data.data_space_id).not.toBe("shared");
    const me = await authRoutes.request("/me", {
      headers: { Authorization: `Bearer ${body.data.access_token}` },
    }, env);
    expect(me.status).toBe(200);
    await expect(me.json()).resolves.toMatchObject({ data: {
      user_id: "shared", platform: "android", data_space_id: body.data.data_space_id,
    } });
    const accounts = await db.query<{ id: string; platform: string }>(
      "SELECT id, platform FROM platform_account WHERE user_id = 'shared' ORDER BY platform",
    );
    expect(accounts.rows).toEqual([
      { id: body.data.data_space_id, platform: "android" },
      { id: "shared", platform: "ios" },
    ]);

    const iosCollection = await createPortfolioRoutes().request(
      "/collection/items?tab=portfolio",
      { headers: { Authorization: `Bearer ${ios.access}` } },
      env,
    );
    expect(iosCollection.status).toBe(200);
    await expect(iosCollection.json()).resolves.toMatchObject({
      data: { items: [expect.objectContaining({ id: "ios-item", card_ref: "ios-card" })] },
    });
  });

  it("deletes only the current platform, revokes refresh, and anonymizes identity after the last platform", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("shared", "shared", "ios", "active");
    await seedPlatform("android-space", "shared", "android", "active");
    await db.exec(`INSERT INTO verification_code
      (id, email, code, purpose, expires_at, used_at, created_at)
      VALUES ('shared-reset', 'shared@example.com', '123456', 'reset_password', '2099-01-01', NULL, '2026-11-05')`);
    await db.exec(`
      INSERT INTO auth_identity (id, user_id, provider, provider_uid, created_at)
      VALUES ('google-id', 'shared', 'google', 'google-shared', '2026-11-05');
      INSERT INTO portfolio_folder
        (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('android-folder', 'user', 'android-space', 'Main', 1, 0, '2026-11-05', '2026-11-05');
    `);
    const android = await seedUserSession("android-space", "shared", "android", "android-session");
    const androidSecond = await seedUserSession(
      "android-space", "shared", "android", "android-session-2",
    );
    const iosBeforeDelete = await seedUserSession("shared", "shared", "ios", "ios-session-before");
    const iosSecondBeforeDelete = await seedUserSession(
      "shared", "shared", "ios", "ios-session-before-2",
    );
    const deletedAndroid = await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${android.access}` },
    }, env);
    expect(deletedAndroid.status).toBe(200);
    await expect(platformStatus("android-space")).resolves.toBe("deleted");
    await expect(platformStatus("shared")).resolves.toBe("active");
    await expect(userStatus("shared")).resolves.toEqual({
      email: "shared@example.com", status: "active", password_hash_present: true,
    });
    await expect(db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM verification_code WHERE email = 'shared@example.com'",
    ).then((result) => result.rows[0]?.total)).resolves.toBe(1);
    const refresh = await authRoutes.request("/token/refresh", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: android.refresh }),
    }, env);
    expect(refresh.status).toBe(401);
    expect((await authRoutes.request("/token/refresh", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: androidSecond.refresh }),
    }, env)).status).toBe(401);
    expect((await authRoutes.request("/token/refresh", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: iosBeforeDelete.refresh }),
    }, env)).status).toBe(200);
    expect((await authRoutes.request("/token/refresh", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: iosSecondBeforeDelete.refresh }),
    }, env)).status).toBe(200);
    const revokedByPlatform = await db.query<{ platform: string; live: number }>(`
      SELECT platform, COUNT(*) FILTER (WHERE revoked_at IS NULL)::int AS live
      FROM session WHERE user_id = 'shared' GROUP BY platform ORDER BY platform`);
    expect(revokedByPlatform.rows).toEqual([
      { platform: "android", live: 0 }, { platform: "ios", live: 2 },
    ]);

    const ios = await seedUserSession("shared", "shared", "ios", "ios-session");
    const deletedIos = await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${ios.access}` },
    }, env);
    expect(deletedIos.status).toBe(200);
    await expect(userStatus("shared")).resolves.toEqual({
      email: "deleted+shared@invalid.cardai.local", status: "deleted", password_hash_present: false,
    });
    await expect(db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM verification_code WHERE email = 'shared@example.com'",
    ).then((result) => result.rows[0]?.total)).resolves.toBe(0);
    await expect(db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM auth_identity WHERE user_id = 'shared'",
    ).then((result) => result.rows[0]?.total)).resolves.toBe(0);
  });

  it("Google registration after platform deletion creates a new owner instead of reviving the tombstone", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("old-android", "shared", "android", "deleted");
    await db.exec(`INSERT INTO auth_identity (id, user_id, provider, provider_uid, created_at)
      VALUES ('google-id', 'shared', 'google', 'google-shared', '2026-11-05')`);

    const result = await completeOAuthAccountFlow(
      db,
      { provider: "google", providerUid: "google-shared", email: "shared@example.com" },
      JWT_SECRET,
      null,
      undefined,
      new Date("2026-11-05T00:00:00Z"),
      "android",
    );
    expect(result.isNewUser).toBe(true);
    expect(result.session.dataSpaceId).not.toBe("old-android");
    await expect(platformStatus("old-android")).resolves.toBe("deleted");
    await expect(platformStatus(result.session.dataSpaceId)).resolves.toBe("active");
  });

  it("keeps a failed deletion retryable while ordinary access and refresh remain revoked", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("android-space", "shared", "android", "active");
    const session = await seedUserSession("android-space", "shared", "android", "android-session");
    await db.exec(`INSERT INTO scan_record
      (id, owner_type, owner_id, image_url, filename, platform, app_version,
       recognition_status, user_confirmation_status, system_result, user_result,
       candidates, raw_response, created_at)
      VALUES ('scan-1', 'user', 'android-space', 'scan-key', 'scan.jpg', 'android', '1.0',
       'success', 'pending', '{}', '{}', '[]', '{}', '2026-11-05')`);
    let deleteAttempts = 0;
    env.SCAN_IMAGES = {
      delete: async () => {
        deleteAttempts += 1;
        if (deleteAttempts === 1) throw new Error("temporary R2 failure");
      },
    } as unknown as R2Bucket;

    const first = await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${session.access}` },
    }, env);
    expect(first.status).toBe(500);
    await expect(platformStatus("android-space")).resolves.toBe("deleting");
    expect((await authRoutes.request("/me", {
      headers: { Authorization: `Bearer ${session.access}` },
    }, env)).status).toBe(401);
    expect((await authRoutes.request("/token/refresh", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: session.refresh }),
    }, env)).status).toBe(401);

    const retry = await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${session.access}` },
    }, env);
    expect(retry.status).toBe(200);
    expect(deleteAttempts).toBe(2);
    await expect(platformStatus("android-space")).resolves.toBe("deleted");
    await expect(db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM scan_record WHERE owner_id = 'android-space'",
    ).then((result) => result.rows[0]?.total)).resolves.toBe(0);
  });

  it("rolls back final database cleanup when a real constraint failure interrupts deletion", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("android-space", "shared", "android", "active");
    const session = await seedUserSession("android-space", "shared", "android", "android-session");
    await db.exec(`
      INSERT INTO portfolio_folder
        (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('android-folder', 'user', 'android-space', 'Main', 1, 0, '2026-11-05', '2026-11-05');
      CREATE FUNCTION reject_deleted_platform() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN IF NEW.status = 'deleted' THEN RAISE EXCEPTION 'injected finalization failure'; END IF; RETURN NEW; END $$;
      CREATE TRIGGER reject_deleted_platform BEFORE UPDATE ON platform_account
        FOR EACH ROW EXECUTE FUNCTION reject_deleted_platform();
    `);
    const response = await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${session.access}` },
    }, env);
    expect(response.status).toBe(500);
    await expect(platformStatus("android-space")).resolves.toBe("deleting");
    const folder = await db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM portfolio_folder WHERE id = 'android-folder'",
    );
    expect(folder.rows[0]?.total).toBe(1);
  });

  it("retries guest migration only when durable and anonymous proofs share the same platform", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("shared", "shared", "ios", "active");
    await seedPlatform("android-space", "shared", "android", "active");
    const user = await seedUserSession("shared", "shared", "ios", "user-session");
    const guest = await seedAnonymousSession("guest-ios", "ios", "guest-session");
    await db.exec(`INSERT INTO portfolio_folder
      (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('guest-folder', 'anonymous', 'guest-ios', 'Guest', 1, 0, '2026-11-05', '2026-11-05')`);
    await db.exec(`
      INSERT INTO feedback_ticket
        (id, email, types, functions, message, status, created_at, updated_at, uid)
      VALUES ('guest-feedback', 'guest@example.com', '[]', '[]', 'Guest feedback', 'open', '2026-11-05', '2026-11-05', 'guest-ios');
      INSERT INTO app_installation
        (installation_id, platform, first_seen_at, last_seen_at, uid)
      VALUES ('guest-install', 'iOS', '2026-11-05', '2026-11-05', 'guest-ios');
    `);
    const migrated = await authRoutes.request("/migrate-assets", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${user.access}`,
        "X-Anonymous-Authorization": `Bearer ${guest}`,
      },
      body: JSON.stringify({ anonymous_id: "guest-ios" }),
    }, env);
    expect(migrated.status).toBe(200);
    await expect(db.query<{ owner_type: string; owner_id: string }>(
      "SELECT owner_type, owner_id FROM portfolio_folder WHERE id = 'guest-folder'",
    ).then((result) => result.rows[0])).resolves.toEqual({ owner_type: "user", owner_id: "shared" });

    const androidGuest = await seedAnonymousSession("guest-android", "android", "android-guest-session");
    const mismatched = await authRoutes.request("/migrate-assets", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${user.access}`,
        "X-Anonymous-Authorization": `Bearer ${androidGuest}`,
      },
      body: JSON.stringify({ anonymous_id: "guest-android" }),
    }, env);
    expect(mismatched.status).toBe(403);

    const deleted = await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${user.access}` },
    }, env);
    expect(deleted.status).toBe(200);
    await expect(platformStatus("shared")).resolves.toBe("deleted");
    await expect(platformStatus("android-space")).resolves.toBe("active");
    const related = await db.query<{
      status: string; device_id: string; feedback: number; installations: number;
    }>(`SELECT a.status, a.device_id,
        (SELECT COUNT(*) FROM feedback_ticket WHERE uid = 'guest-ios')::int AS feedback,
        (SELECT COUNT(*) FROM app_installation WHERE uid = 'guest-ios')::int AS installations
      FROM anonymous_account a WHERE a.id = 'guest-ios'`);
    expect(related.rows[0]).toEqual({
      status: "deleted", device_id: "deleted:guest-ios", feedback: 0, installations: 0,
    });
  });

  it("binds a verified OAuth identity to an existing email without merging guest assets into an active platform", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("shared", "shared", "ios", "active");
    const guestAccess = await seedAnonymousSession("guest-ios", "ios", "guest-session");
    await db.exec(`INSERT INTO portfolio_folder
      (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('guest-folder', 'anonymous', 'guest-ios', 'Guest', 1, 0, '2026-11-05', '2026-11-05')`);
    const result = await completeOAuthAccountFlow(
      db,
      { provider: "google", providerUid: "google-shared", email: "shared@example.com" },
      JWT_SECRET,
      "guest-ios",
      `Bearer ${guestAccess}`,
      new Date(),
      "ios",
    );
    expect(result).toMatchObject({ userId: "shared", isNewUser: false, migrated: false });
    const guestFolder = await db.query<{ owner_type: string; owner_id: string }>(
      "SELECT owner_type, owner_id FROM portfolio_folder WHERE id = 'guest-folder'",
    );
    expect(guestFolder.rows[0]).toEqual({ owner_type: "anonymous", owner_id: "guest-ios" });
    await expect(db.query<{ user_id: string }>(
      "SELECT user_id FROM auth_identity WHERE provider_uid = 'google-shared'",
    ).then((query) => query.rows[0])).resolves.toEqual({ user_id: "shared" });
  });

  it("rejects an OAuth identity linked to a globally deleted user", async () => {
    await db.exec(`
      INSERT INTO "user" (id, email, created_at, updated_at, status)
      VALUES ('deleted', 'deleted@example.com', '2026-11-05', '2026-11-05', 'deleted');
      INSERT INTO auth_identity (id, user_id, provider, provider_uid, created_at)
      VALUES ('identity', 'deleted', 'google', 'google-deleted', '2026-11-05');
    `);
    await expect(completeOAuthAccountFlow(
      db,
      { provider: "google", providerUid: "google-deleted", email: "deleted@example.com" },
      JWT_SECRET,
      null,
      undefined,
      new Date(),
      "ios",
    )).rejects.toThrow("OAuth authorization failed.");
  });

  it("creates a new identity and space after historical deleted login data was normalized", async () => {
    await db.exec(`INSERT INTO "user"
      (id, email, created_at, updated_at, deleted_at, status)
      VALUES ('old-deleted', 'deleted+old-deleted@invalid.cardai.local',
        '2026-01-01', '2026-11-05', '2026-11-05', 'deleted')`);
    const result = await completeOAuthAccountFlow(
      db,
      { provider: "google", providerUid: "google-returning", email: "returning@example.com" },
      JWT_SECRET,
      null,
      undefined,
      new Date(),
      "android",
    );
    expect(result.userId).not.toBe("old-deleted");
    expect(result.session.dataSpaceId).not.toBe("old-deleted");
    await expect(platformStatus(result.session.dataSpaceId)).resolves.toBe("active");
    const old = await db.query<{ status: string; platforms: number }>(`
      SELECT u.status, (SELECT COUNT(*) FROM platform_account WHERE user_id = u.id)::int AS platforms
      FROM "user" u WHERE u.id = 'old-deleted'`);
    expect(old.rows[0]).toEqual({ status: "deleted", platforms: 0 });
  });

  it("does not return OAuth credentials when the guarded session insert writes zero rows", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await db.exec(`
      INSERT INTO auth_identity (id, user_id, provider, provider_uid, created_at)
      VALUES ('identity', 'shared', 'google', 'google-shared', '2026-11-05');
      CREATE FUNCTION suppress_user_session() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN IF NEW.owner_type = 'user' THEN RETURN NULL; END IF; RETURN NEW; END $$;
      CREATE TRIGGER suppress_user_session BEFORE INSERT ON session
        FOR EACH ROW EXECUTE FUNCTION suppress_user_session();
    `);
    await expect(completeOAuthAccountFlow(
      db,
      { provider: "google", providerUid: "google-shared", email: "shared@example.com" },
      JWT_SECRET,
      null,
      undefined,
      new Date(),
      "android",
    )).rejects.toThrow("Failed to create platform account.");
    const sessions = await db.query<{ total: number }>(
      "SELECT COUNT(*)::int AS total FROM session WHERE user_id = 'shared'",
    );
    expect(sessions.rows[0]?.total).toBe(0);
  });

  it("converges concurrent OAuth user creation on one email identity instead of returning 500", async () => {
    const identity = {
      provider: "google" as const,
      providerUid: "google-email-race",
      email: "race@example.com",
    };
    const results = await Promise.all([
      completeOAuthAccountFlow(db, identity, JWT_SECRET, null, undefined, new Date(), "ios"),
      completeOAuthAccountFlow(db, identity, JWT_SECRET, null, undefined, new Date(), "ios"),
    ]);
    expect(new Set(results.map((result) => result.userId)).size).toBe(1);
    const state = await db.query<{ users: number; identities: number; sessions: number }>(`
      SELECT (SELECT COUNT(*) FROM "user" WHERE email = 'race@example.com')::int AS users,
        (SELECT COUNT(*) FROM auth_identity WHERE provider_uid = 'google-email-race')::int AS identities,
        (SELECT COUNT(*) FROM session WHERE login_method = 'google')::int AS sessions`);
    expect(state.rows[0]).toEqual({ users: 1, identities: 1, sessions: 2 });
  });

  it("converges concurrent OAuth identity binding on the stable provider key", async () => {
    await seedUser("shared", "bind@example.com", "password-1");
    await seedPlatform("shared", "shared", "ios", "active");
    const identity = {
      provider: "google" as const,
      providerUid: "google-bind-race",
      email: "bind@example.com",
    };
    const results = await Promise.all([
      completeOAuthAccountFlow(db, identity, JWT_SECRET, null, undefined, new Date(), "ios"),
      completeOAuthAccountFlow(db, identity, JWT_SECRET, null, undefined, new Date(), "ios"),
    ]);
    expect(results.map((result) => result.userId)).toEqual(["shared", "shared"]);
    const state = await db.query<{ identities: number; sessions: number }>(`
      SELECT (SELECT COUNT(*) FROM auth_identity WHERE provider_uid = 'google-bind-race')::int AS identities,
        (SELECT COUNT(*) FROM session WHERE user_id = 'shared' AND login_method = 'google')::int AS sessions`);
    expect(state.rows[0]).toEqual({ identities: 1, sessions: 2 });
  });

  it("requires a live matching bearer before destructive deletion", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("shared", "shared", "ios", "active");
    const session = await seedUserSession("shared", "shared", "ios", "user-session");
    expect((await authRoutes.request("/account", { method: "DELETE" }, env)).status).toBe(401);
    await db.prepare("UPDATE session SET expires_at = '2000-01-01' WHERE id = 'user-session'").run();
    expect((await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${session.access}` },
    }, env)).status).toBe(401);

    const live = await seedUserSession("shared", "shared", "ios", "revoked-session");
    await db.prepare("UPDATE session SET revoked_at = '2026-11-05' WHERE id = 'revoked-session'").run();
    expect((await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${live.access}` },
    }, env)).status).toBe(401);
    await seedUserSession("shared", "shared", "ios", "mismatch-session");
    const mismatch = await signAccessToken(
      { owner_type: "user", owner_id: "another-owner", session_id: "mismatch-session" },
      JWT_SECRET,
      new Date(),
    );
    expect((await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${mismatch}` },
    }, env)).status).toBe(401);
  });

  it("irreversibly deletes an anonymous platform space and all of its sessions", async () => {
    const access = await seedAnonymousSession("guest-ios", "ios", "guest-session");
    await db.exec(`
      INSERT INTO portfolio_folder
        (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('guest-folder', 'anonymous', 'guest-ios', 'Main', 1, 0, '2026-11-05', '2026-11-05');
      INSERT INTO user_preference
        (id, owner_type, owner_id, currency, amount_hidden, created_at, updated_at)
      VALUES ('guest-preference', 'anonymous', 'guest-ios', 'USD', 0, '2026-11-05', '2026-11-05');
    `);
    const response = await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${access}` },
    }, env);
    expect(response.status).toBe(200);
    const account = await db.query<{ status: string; device_id: string }>(
      "SELECT status, device_id FROM anonymous_account WHERE id = 'guest-ios'",
    );
    expect(account.rows[0]).toEqual({ status: "deleted", device_id: "deleted:guest-ios" });
    const assets = await db.query<{ total: number }>(`
      SELECT (SELECT COUNT(*) FROM portfolio_folder WHERE owner_id = 'guest-ios')::int +
             (SELECT COUNT(*) FROM user_preference WHERE owner_id = 'guest-ios')::int AS total`);
    expect(assets.rows[0]?.total).toBe(0);
    const session = await db.query<{ revoked_at: string | null }>(
      "SELECT revoked_at FROM session WHERE id = 'guest-session'",
    );
    expect(session.rows[0]?.revoked_at).not.toBeNull();
  });

  it("never downgrades a valid or stale Android bearer into legacy iOS identity authentication", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("shared", "shared", "ios", "active");
    const androidAccess = await seedAnonymousSession(
      "guest-android", "android", "android-session",
    );
    const request = (platform: string, access: string) => authRoutes.request("/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json", Authorization: `Bearer ${access}`,
      },
      body: JSON.stringify({
        email: "shared@example.com", password: "password-1", platform,
      }),
    }, env);
    expect((await request("ios", androidAccess)).status).toBe(401);
    await db.prepare("UPDATE session SET expires_at = '2000-01-01' WHERE id = 'android-session'").run();
    expect((await request("android", androidAccess)).status).toBe(401);
    expect((await request("unknown", androidAccess)).status).toBe(401);
  });

  it("deletes every current-platform business table while preserving the other platform space", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("ios-space", "shared", "ios", "active");
    await seedPlatform("android-space", "shared", "android", "active");
    const ios = await seedUserSession("ios-space", "shared", "ios", "ios-session");
    const android = await seedUserSession("android-space", "shared", "android", "android-session");
    await seedBusinessSpace("ios", "ios-space", "ios-session");
    await seedBusinessSpace("android", "android-space", "android-session");

    expect((await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${android.access}` },
    }, env)).status).toBe(200);
    await expect(businessCounts("android-space")).resolves.toEqual({
      folders: 0, items: 0, events: 0, wishlist: 0, preferences: 0, scans: 0, quota: 0,
    });
    await expect(businessCounts("ios-space")).resolves.toEqual({
      folders: 1, items: 1, events: 1, wishlist: 1, preferences: 1, scans: 1, quota: 1,
    });
    expect((await authRoutes.request("/me", {
      headers: { Authorization: `Bearer ${ios.access}` },
    }, env)).status).toBe(200);
  });

  it("deletes more than 1000 unique scan images in bounded R2 batches without touching the other platform", async () => {
    await seedUser("shared", "shared@example.com", "password-1");
    await seedPlatform("ios-space", "shared", "ios", "active");
    await seedPlatform("android-space", "shared", "android", "active");
    const android = await seedUserSession("android-space", "shared", "android", "android-session");
    await db.exec(`INSERT INTO scan_record
      (id, owner_type, owner_id, image_url, filename, platform, app_version,
       recognition_status, user_confirmation_status, system_result, user_result,
       candidates, raw_response, created_at)
      SELECT 'bulk-' || n, 'user', 'android-space',
        CASE WHEN n = 1002 THEN 'bulk-key-1' ELSE 'bulk-key-' || n END,
        'scan.jpg', 'android', '1.0', 'success', 'pending', '{}', '{}', '[]', '{}', '2026-11-05'
      FROM generate_series(1, 1002) AS series(n);
      INSERT INTO scan_record
        (id, owner_type, owner_id, image_url, filename, platform, app_version,
         recognition_status, user_confirmation_status, system_result, user_result,
         candidates, raw_response, created_at)
      VALUES ('ios-scan', 'user', 'ios-space', 'ios-key', 'scan.jpg', 'ios', '1.0',
        'success', 'pending', '{}', '{}', '[]', '{}', '2026-11-05');`);
    const keys = new Set([
      ...Array.from({ length: 1001 }, (_, index) => `bulk-key-${index + 1}`),
      "ios-key",
    ]);
    const batches: string[][] = [];
    env.SCAN_IMAGES = {
      delete: async (input: string | string[]) => {
        const batch = Array.isArray(input) ? input : [input];
        if (batch.length > 1000) throw new Error("R2 batch limit exceeded");
        batches.push(batch);
        for (const key of batch) keys.delete(key);
      },
    } as unknown as R2Bucket;

    expect((await authRoutes.request("/account", {
      method: "DELETE", headers: { Authorization: `Bearer ${android.access}` },
    }, env)).status).toBe(200);
    expect(batches.map((batch) => batch.length)).toEqual([1000, 1]);
    expect(keys).toEqual(new Set(["ios-key"]));
    const scans = await db.query<{ owner_id: string; total: number }>(
      "SELECT owner_id, COUNT(*)::int AS total FROM scan_record GROUP BY owner_id ORDER BY owner_id",
    );
    expect(scans.rows).toEqual([{ owner_id: "ios-space", total: 1 }]);
  });

  async function seedUser(id: string, email: string, password: string): Promise<void> {
    const passwordHash = await hashPassword(password);
    await db.prepare(`INSERT INTO "user"
      (id, email, password_hash, created_at, updated_at, status)
      VALUES (?, ?, ?, '2026-11-05', '2026-11-05', 'active')`)
      .bind(id, email, passwordHash).run();
  }

  async function seedPlatform(
    id: string, userId: string, platform: "ios" | "android", status: string,
  ): Promise<void> {
    await db.prepare(`INSERT INTO platform_account
      (id, user_id, platform, status, created_at, updated_at, deleted_at)
      VALUES (?, ?, ?, ?, '2026-11-05', '2026-11-05',
        CASE WHEN ? = 'deleted' THEN '2026-11-05' ELSE NULL END)`)
      .bind(id, userId, platform, status, status).run();
  }

  async function seedAnonymousAndroidSession(ownerId: string, sessionId: string): Promise<string> {
    return seedAnonymousSession(ownerId, "android", sessionId);
  }

  async function seedAnonymousSession(
    ownerId: string, platform: "ios" | "android", sessionId: string,
  ): Promise<string> {
    await db.prepare(`INSERT INTO anonymous_account
      (id, device_id, created_at, upgraded_user_id, platform, status)
      VALUES (?, ?, '2026-11-05', NULL, ?, 'active')`)
      .bind(ownerId, `device-${ownerId}`, platform).run();
    await db.prepare(`INSERT INTO session
      (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES (?, 'anonymous', ?, ?, '2099-01-01', '2026-11-05', ?, NULL)`)
      .bind(sessionId, ownerId, `refresh-${sessionId}`, platform).run();
    return signAccessToken(
      { owner_type: "anonymous", owner_id: ownerId, session_id: sessionId }, JWT_SECRET,
      new Date(),
    );
  }

  async function seedUserSession(
    ownerId: string, userId: string, platform: "ios" | "android", sessionId: string,
  ): Promise<{ access: string; refresh: string }> {
    const refresh = `refresh-${sessionId}`;
    const storedRefresh = await hashRefreshToken(refresh);
    await db.prepare(`INSERT INTO session
      (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES (?, 'user', ?, ?, '2099-01-01', '2026-11-05', ?, ?)`)
      .bind(sessionId, ownerId, storedRefresh, platform, userId).run();
    return {
      refresh,
      access: await signAccessToken(
        { owner_type: "user", owner_id: ownerId, session_id: sessionId }, JWT_SECRET,
        new Date(),
      ),
    };
  }

  function platformStatus(id: string): Promise<string | undefined> {
    return db.query<{ status: string }>(
      "SELECT status FROM platform_account WHERE id = $1", [id],
    ).then((result) => result.rows[0]?.status);
  }

  function userStatus(id: string): Promise<{
    email: string; status: string; password_hash_present: boolean;
  } | undefined> {
    return db.query<{ email: string; status: string; password_hash_present: boolean }>(
      `SELECT email, status, (password_hash IS NOT NULL) AS password_hash_present
       FROM "user" WHERE id = $1`, [id],
    ).then((result) => result.rows[0]);
  }

  async function seedBusinessSpace(
    prefix: string, ownerId: string, sessionId: string,
  ): Promise<void> {
    await db.prepare(`INSERT INTO portfolio_folder
      (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES (?, 'user', ?, 'Main', 1, 0, '2026-11-05', '2026-11-05')`)
      .bind(`${prefix}-folder`, ownerId).run();
    await db.prepare(`INSERT INTO collection_item
      (id, owner_type, owner_id, folder_id, card_ref, object_type, grader, quantity, created_at, updated_at)
      VALUES (?, 'user', ?, ?, ?, 'tcg', 'RAW', 1, '2026-11-05', '2026-11-05')`)
      .bind(`${prefix}-item`, ownerId, `${prefix}-folder`, `${prefix}-card`).run();
    await db.prepare(`INSERT INTO collection_item_event
      (id, item_id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
       quantity, event_type, effective_at)
      VALUES (?, ?, 'user', ?, ?, ?, 'tcg', 'RAW', 1, 'upsert', '2026-11-05')`)
      .bind(`${prefix}-event`, `${prefix}-item`, ownerId, `${prefix}-folder`, `${prefix}-card`).run();
    await db.prepare(`INSERT INTO wishlist_item (id, owner_type, owner_id, card_ref, created_at)
      VALUES (?, 'user', ?, ?, '2026-11-05')`)
      .bind(`${prefix}-wishlist`, ownerId, `${prefix}-wishlist-card`).run();
    await db.prepare(`INSERT INTO user_preference
      (id, owner_type, owner_id, currency, amount_hidden, created_at, updated_at)
      VALUES (?, 'user', ?, 'USD', 0, '2026-11-05', '2026-11-05')`)
      .bind(`${prefix}-preference`, ownerId).run();
    await db.prepare(`INSERT INTO scan_record
      (id, owner_type, owner_id, filename, platform, app_version, recognition_status,
       user_confirmation_status, system_result, user_result, candidates, raw_response, created_at)
      VALUES (?, 'user', ?, 'scan.jpg', ?, '1.0', 'success', 'pending', '{}', '{}', '[]', '{}', '2026-11-05')`)
      .bind(`${prefix}-scan`, ownerId, prefix).run();
    await db.prepare(`INSERT INTO scan_quota_request
      (request_id, owner_type, owner_id, session_id, access_mode, status, attempts, created_at, updated_at)
      VALUES (?, 'user', ?, ?, 'free', 'consumed', 1, '2026-11-05', '2026-11-05')`)
      .bind(`${prefix}-quota`, ownerId, sessionId).run();
  }

  function businessCounts(ownerId: string): Promise<{
    folders: number; items: number; events: number; wishlist: number;
    preferences: number; scans: number; quota: number;
  } | undefined> {
    return db.query<{
      folders: number; items: number; events: number; wishlist: number;
      preferences: number; scans: number; quota: number;
    }>(`SELECT
      (SELECT COUNT(*) FROM portfolio_folder WHERE owner_id = $1)::int AS folders,
      (SELECT COUNT(*) FROM collection_item WHERE owner_id = $1)::int AS items,
      (SELECT COUNT(*) FROM collection_item_event WHERE owner_id = $1)::int AS events,
      (SELECT COUNT(*) FROM wishlist_item WHERE owner_id = $1)::int AS wishlist,
      (SELECT COUNT(*) FROM user_preference WHERE owner_id = $1)::int AS preferences,
      (SELECT COUNT(*) FROM scan_record WHERE owner_id = $1)::int AS scans,
      (SELECT COUNT(*) FROM scan_quota_request WHERE owner_id = $1)::int AS quota`, [ownerId])
      .then((result) => result.rows[0]);
  }
});
