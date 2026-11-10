import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword, signAccessToken } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";

vi.mock("./oauth-provider", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./oauth-provider")>();
  const identity = (token: string | null, prefix: string, provider: "google" | "apple") => {
    if (!token?.startsWith(`${prefix}:`)) return null;
    const [, providerUid, email] = token.split(":");
    if (!providerUid || /[^A-Za-z0-9._-]/.test(providerUid) || !email?.includes("@")) return null;
    return { provider, providerUid, email: email.toLowerCase() };
  };
  return {
    ...actual,
    resolveGoogleIdentity: async (input: { idToken: string | null }) =>
      identity(input.idToken, "mock-google", "google"),
    resolveAppleIdentity: async (input: { idToken: string | null }) =>
      identity(input.idToken, "mock-apple", "apple"),
  };
});

import { authRoutes } from "./anonymous";

const JWT_SECRET = "oauth-legacy-postgres";
const NOW = "2026-11-05T00:00:00.000Z";

describe("legacy OAuth business contracts on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    const migrations = new URL("../db/postgres/migrations/", import.meta.url);
    for (const name of ["0000_business_schema.sql", "0006_mutation_lock.sql", "0018_platform_account_isolation.sql"]) {
      await db.exec(readFileSync(new URL(name, migrations), "utf8"));
    }
    env = {
      DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET,
      GOOGLE_CLIENT_ID: "google-client", APPLE_CLIENT_ID: "apple-client",
      APP_ENVIRONMENT: "development",
    };
  });

  afterEach(async () => { vi.restoreAllMocks(); await db.close(); });

  it("google oauth creates an OAuth-only user because a new provider identity starts durable auth", async () => {
    const response = await google("mock-google:google-1:google.new@example.com");
    expect(response.status).toBe(200);
    const data = await success(response);
    expect(data).toMatchObject({ email: "google.new@example.com", login_method: "google", is_new_user: true, migrated: false });
    await expect(identity("google", "google-1")).resolves.toBe(data.user_id);
    await expect(platforms(data.user_id)).resolves.toEqual(["ios"]);
  });

  it("google oauth signs in an existing identity because provider_uid is the stable login key", async () => {
    await seedUser("existing", "original@example.com"); await seedPlatform("existing", "existing");
    await seedIdentity("existing", "google", "google-existing");
    const guest = await seedGuest("guest-existing");
    const response = await google("mock-google:google-existing:new-email@example.com", guest);
    expect(await success(response)).toMatchObject({ user_id: "existing", is_new_user: false, migrated: false });
    await expect(guestOwner("guest-existing")).resolves.toBe("anonymous");
  });

  it("google oauth binds an existing live email because user.email is unique across auth methods", async () => {
    await seedUser("email-user", "shared@example.com", "password"); await seedPlatform("email-user", "email-user");
    const guest = await seedGuest("guest-email");
    const response = await google("mock-google:google-shared:shared@example.com", guest);
    expect(await success(response)).toMatchObject({ user_id: "email-user", is_new_user: false, migrated: false });
    await expect(identity("google", "google-shared")).resolves.toBe("email-user");
    await expect(guestOwner("guest-email")).resolves.toBe("anonymous");
  });

  it("google oauth migrates a live guest only for a new user because registration transfers guest assets", async () => {
    const guest = await seedGuest("guest-google-migrate", true);
    const response = await google("mock-google:google-migrate:google.migrate@example.com", guest);
    const data = await success(response);
    expect(data).toMatchObject({ user_id: "guest-google-migrate", is_new_user: true, migrated: true });
    await expect(guestOwner("guest-google-migrate")).resolves.toBe("user");
  });

  it("google oauth does not half-create a migrated user when the guest is concurrently upgraded because guarded writes must depend on claimed ownership", async () => {
    const guest = await seedGuest("guest-google-race", true);
    const batch = db.batch.bind(db);
    vi.spyOn(db, "batch").mockImplementationOnce(async (statements) => {
      await db.prepare("UPDATE anonymous_account SET upgraded_user_id = 'existing-user' WHERE id = 'guest-google-race'").run();
      return batch(statements);
    });
    const response = await google("mock-google:google-race:google.race@example.com", guest);
    expect(response.status).not.toBe(200);
    await expect(userByEmail("google.race@example.com")).resolves.toBeNull();
    await expect(guestOwner("guest-google-race")).resolves.toBe("anonymous");
  });

  it("google oauth rejects a stale identity because a soft-deleted linked user must not create replacement accounts", async () => {
    await seedDeletedUser("deleted-identity", "deleted@example.com");
    await seedIdentity("deleted-identity", "google", "google-deleted");
    expect((await google("mock-google:google-deleted:deleted@example.com")).status).toBe(422);
    await expect(userCount()).resolves.toBe(1);
  });

  it("google oauth creates a new user for a deleted provider email because inactive accounts do not reserve the address", async () => {
    await seedDeletedUser("deleted-email", "reused@example.com");
    const response = await google("mock-google:google-new:reused@example.com");
    expect(response.status).toBe(200);
    await expect(userByEmail("reused@example.com")).resolves.not.toBeNull();
  });

  it("google oauth rejects malformed mock authorization because failed provider proof must not create accounts", async () => {
    expect((await google("bad-code")).status).toBe(422); await expect(userCount()).resolves.toBe(0);
  });

  it("google oauth rejects malformed provider UID because durable login keys must be constrained", async () => {
    expect((await google("mock-google:bad uid:baduid@example.com")).status).toBe(422); await expect(userCount()).resolves.toBe(0);
  });

  it("apple oauth creates an OAuth-only user because id_token proves a new provider identity", async () => {
    const response = await apple("mock-apple:apple-1:apple.new@example.com");
    expect(await success(response)).toMatchObject({ email: "apple.new@example.com", login_method: "apple", is_new_user: true });
    await expect(identity("apple", "apple-1")).resolves.toEqual(expect.any(String));
  });

  it("apple oauth signs in an existing identity because provider_uid is stable across sessions", async () => {
    await seedUser("apple-existing", "original@example.com"); await seedPlatform("apple-existing", "apple-existing");
    await seedIdentity("apple-existing", "apple", "apple-existing");
    const guest = await seedGuest("guest-apple-existing");
    expect(await success(await apple("mock-apple:apple-existing:new@example.com", guest)))
      .toMatchObject({ user_id: "apple-existing", is_new_user: false, migrated: false });
    await expect(guestOwner("guest-apple-existing")).resolves.toBe("anonymous");
  });

  it("apple oauth binds an existing live email because one email maps to one user", async () => {
    await seedUser("apple-email", "shared@example.com", "password"); await seedPlatform("apple-email", "apple-email");
    const guest = await seedGuest("guest-apple-email");
    expect(await success(await apple("mock-apple:apple-shared:shared@example.com", guest)))
      .toMatchObject({ user_id: "apple-email", is_new_user: false, migrated: false });
    await expect(identity("apple", "apple-shared")).resolves.toBe("apple-email");
  });

  it("apple oauth migrates a live guest only for a new user because existing-user login must not merge assets", async () => {
    const guest = await seedGuest("guest-apple-migrate", true);
    expect(await success(await apple("mock-apple:apple-migrate:apple.migrate@example.com", guest)))
      .toMatchObject({ user_id: "guest-apple-migrate", is_new_user: true, migrated: true });
    await expect(guestOwner("guest-apple-migrate")).resolves.toBe("user");
  });

  it("apple oauth rejects missing id_token because provider identity cannot be proven", async () => {
    expect((await apple(null)).status).toBe(422); await expect(userCount()).resolves.toBe(0);
  });

  it("apple oauth rejects malformed mock authorization because failed provider proof must not create accounts", async () => {
    expect((await apple("bad-code")).status).toBe(422); await expect(userCount()).resolves.toBe(0);
  });

  it("apple oauth rejects malformed provider UID because durable login keys must be constrained", async () => {
    expect((await apple("mock-apple:bad uid:user@example.com")).status).toBe(422); await expect(userCount()).resolves.toBe(0);
  });

  it("apple oauth rejects malformed email because provider identity email must be usable for account lookup", async () => {
    expect((await apple("mock-apple:valid-uid:not-an-email")).status).toBe(422); await expect(userCount()).resolves.toBe(0);
  });

  async function google(token: string, guest?: { id: string; access: string }): Promise<Response> {
    return oauth("google", token, guest);
  }
  async function apple(token: string | null, guest?: { id: string; access: string }): Promise<Response> {
    return oauth("apple", token, guest);
  }
  async function oauth(provider: "google" | "apple", token: string | null, guest?: { id: string; access: string }) {
    return await authRoutes.request(`/oauth/${provider}/callback`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(guest ? { Authorization: `Bearer ${guest.access}` } : {}) },
      body: JSON.stringify({ id_token: token, code: `${provider}-code`, platform: "ios", ...(guest ? { anonymous_id: guest.id } : {}) }),
    }, env);
  }
  async function success(response: Response): Promise<Record<string, any>> {
    expect(response.status).toBe(200); return ((await response.json()) as { data: Record<string, any> }).data;
  }
  async function seedUser(id: string, email: string, password?: string) {
    await db.prepare(`INSERT INTO "user" (id,email,password_hash,created_at,updated_at,status)
      VALUES (?,?,?,'${NOW}','${NOW}','active')`).bind(id, email, password ? await hashPassword(password) : null).run();
  }
  async function seedDeletedUser(id: string, email: string) {
    await db.prepare(`INSERT INTO "user" (id,email,created_at,updated_at,status,deleted_at)
      VALUES (?,?,'${NOW}','${NOW}','deleted','${NOW}')`).bind(id, email).run();
  }
  async function seedPlatform(id: string, userId: string) {
    await db.prepare(`INSERT INTO platform_account (id,user_id,platform,status,created_at,updated_at)
      VALUES (?,?,'ios','active','${NOW}','${NOW}')`).bind(id, userId).run();
  }
  async function seedIdentity(userId: string, provider: string, uid: string) {
    await db.prepare(`INSERT INTO auth_identity (id,user_id,provider,provider_uid,created_at)
      VALUES (?,?,?,?,?)`).bind(crypto.randomUUID(), userId, provider, uid, NOW).run();
  }
  async function seedGuest(id: string, assets = false): Promise<{ id: string; access: string }> {
    await db.prepare(`INSERT INTO anonymous_account (id,device_id,created_at,platform,status)
      VALUES (?,?,?,'ios','active')`).bind(id, `device-${id}`, NOW).run();
    const session = `${id}-session`;
    await db.prepare(`INSERT INTO session (id,owner_type,owner_id,refresh_token,expires_at,created_at,platform,user_id)
      VALUES (?,'anonymous',?,'refresh','2099-01-01',?,'ios',NULL)`).bind(session, id, NOW).run();
    if (assets) {
      await db.prepare(`INSERT INTO portfolio_folder
        (id,owner_type,owner_id,name,is_default,sort_order,created_at,updated_at)
        VALUES (?,'anonymous',?,'Main',1,0,?,?)`).bind(`${id}-folder`, id, NOW, NOW).run();
      await db.prepare(`INSERT INTO wishlist_item (id,owner_type,owner_id,card_ref,created_at)
        VALUES (?,'anonymous',?,'card-1',?)`).bind(`${id}-wish`, id, NOW).run();
    }
    return { id, access: await signAccessToken({ owner_type: "anonymous", owner_id: id, session_id: session }, JWT_SECRET) };
  }
  async function identity(provider: string, uid: string) {
    return await db.prepare("SELECT user_id FROM auth_identity WHERE provider=? AND provider_uid=?").bind(provider, uid).first("user_id");
  }
  async function platforms(userId: string) {
    return (await db.prepare("SELECT platform FROM platform_account WHERE user_id=? ORDER BY platform").bind(userId).all<{ platform: string }>()).results.map((r) => r.platform);
  }
  async function guestOwner(id: string) {
    const folder = await db.prepare("SELECT owner_type FROM portfolio_folder WHERE id=?").bind(`${id}-folder`).first("owner_type");
    return folder ?? "anonymous";
  }
  async function userByEmail(email: string) { return await db.prepare("SELECT id FROM \"user\" WHERE email=? AND status='active'").bind(email).first(); }
  async function userCount() { return Number(await db.prepare("SELECT COUNT(*) AS total FROM \"user\"").first("total") ?? 0); }
});
