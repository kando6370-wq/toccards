import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashRefreshToken, signAccessToken } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { authRoutes } from "./anonymous";
import { migrateGuestAssetsToUser } from "./guest-migration";

const JWT_SECRET = "guest-migration-contract";
const NOW = "2026-11-05T00:00:00.000Z";

describe("legacy guest migration business contracts on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    const migrations = new URL("../db/postgres/migrations/", import.meta.url);
    for (const name of ["0000_business_schema.sql", "0006_mutation_lock.sql", "0018_platform_account_isolation.sql"]) {
      await db.exec(readFileSync(new URL(name, migrations), "utf8"));
    }
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET, APP_ENVIRONMENT: "development" };
  });

  afterEach(async () => db.close());

  it("migrates only the requested live guest assets with an empty guard because standalone migration must not steal other anonymous work", async () => {
    await seedUser("target"); await seedGuest("source", true); await seedGuest("other", true);
    const counts = await migrateGuestAssetsToUser(db, "source", "target", NOW, {});
    expect(counts).toEqual({
      migrated_folders: 1,
      migrated_items: 1,
      migrated_wishlist: 1,
    });
    await expect(folderOwner("source-folder")).resolves.toEqual({ owner_type: "user", owner_id: "target" });
    await expect(folderOwner("other-folder")).resolves.toEqual({ owner_type: "anonymous", owner_id: "other" });
  });

  it("fails migration for an already upgraded guest because claimed guest assets must not move to another user", async () => {
    await seedUser("target"); await seedGuest("source", true, "existing-user");
    await expect(migrateGuestAssetsToUser(db, "source", "target", NOW, {}))
      .rejects.toThrow("Guest account is no longer available.");
    await expect(folderOwner("source-folder")).resolves.toEqual({ owner_type: "anonymous", owner_id: "source" });
  });

  it("rejects an incomplete guard because verification-gated migration must not silently downgrade to an unguarded path", async () => {
    await seedUser("target"); await seedGuest("source", true);
    await expect(migrateGuestAssetsToUser(
      db, "source", "target", NOW, { verificationCodeId: "code-only" },
    )).rejects.toThrow("Incomplete guest migration guard.");
  });

  it("migrate-assets transfers guest assets to the current user because registration migration can be retried", async () => {
    const user = await seedUser("target"); const guest = await seedGuest("source", true);
    const response = await migrate("source", user, guest.access);
    expect(response.status).toBe(200);
    await expect(folderOwner("source-folder")).resolves.toEqual({ owner_type: "user", owner_id: "target" });
  });

  it("migrate-assets merges guest defaults into an existing user because standalone retry must not collide with default assets", async () => {
    const user = await seedUser("target", true); const guest = await seedGuest("source", true);
    expect((await migrate("source", user, guest.access)).status).toBe(200);
    const folders = await db.query<{ id: string; name: string }>(
      "SELECT id,name FROM portfolio_folder WHERE owner_type='user' AND owner_id='target' ORDER BY id",
    );
    expect(folders.rows.filter((row) => row.name === "Main")).toHaveLength(1);
    await expect(wishlistOwner("source-wish")).resolves.toBe("target");
  });

  it("migrate-assets remaps migrated preference folder because deleted guest folders must not leave dangling selections", async () => {
    const user = await seedUser("target", true); const guest = await seedGuest("source", true);
    await db.prepare("UPDATE user_preference SET last_selected_folder_id='source-folder' WHERE owner_id='source'").run();
    expect((await migrate("source", user, guest.access)).status).toBe(200);
    const selected = await db.prepare("SELECT last_selected_folder_id FROM user_preference WHERE owner_type='user' AND owner_id='target'").first("last_selected_folder_id");
    expect(selected).toBe("target-folder");
  });

  it("migrate-assets rolls back when migration batch fails because partial guest claims must not leak through", async () => {
    const user = await seedUser("target", true); const guest = await seedGuest("source", true);
    await db.exec(`CREATE FUNCTION fail_guest_migration() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'migration failure'; END $$;
      CREATE TRIGGER fail_guest_migration BEFORE UPDATE ON wishlist_item
      FOR EACH ROW WHEN (OLD.owner_id = 'source') EXECUTE FUNCTION fail_guest_migration();`);
    expect((await migrate("source", user, guest.access)).status).toBe(500);
    await expect(guestUpgrade("source")).resolves.toBeNull();
    await expect(folderOwner("source-folder")).resolves.toEqual({ owner_type: "anonymous", owner_id: "source" });
  });

  it("migrate-assets returns 403 without anonymous proof because anonymous_id alone must not prove source ownership", async () => {
    const user = await seedUser("target"); await seedGuest("source", true);
    expect((await migrate("source", user)).status).toBe(403);
    await expect(guestUpgrade("source")).resolves.toBeNull();
  });

  it("migrate-assets returns 403 for mismatched anonymous proof because one guest token must not claim another guest", async () => {
    const user = await seedUser("target"); await seedGuest("source", true); const other = await seedGuest("other");
    expect((await migrate("source", user, other.access)).status).toBe(403);
    await expect(guestUpgrade("source")).resolves.toBeNull();
  });

  it("migrate-assets returns 403 for missing anonymous account without guest proof because source state must not be disclosed", async () => {
    const user = await seedUser("target");
    expect((await migrate("missing", user)).status).toBe(403);
  });

  it("migrate-assets returns 404 for a missing anonymous account with valid guest proof because there is no source owner", async () => {
    const user = await seedUser("target");
    await db.prepare(`INSERT INTO session
      (id,owner_type,owner_id,refresh_token,expires_at,created_at,platform,user_id)
      VALUES ('missing-session','anonymous','missing',?,'2099-01-01',?,'ios',NULL)`)
      .bind(await hashRefreshToken("missing-session-refresh"), NOW).run();
    const proof = await signAccessToken({ owner_type: "anonymous", owner_id: "missing", session_id: "missing-session" }, JWT_SECRET);
    expect((await migrate("missing", user, proof)).status).toBe(404);
  });

  it("migrate-assets returns 409 for an already upgraded anonymous account because assets must not be stolen", async () => {
    const user = await seedUser("target"); const guest = await seedGuest("source", true, "existing-user");
    expect((await migrate("source", user, guest.access)).status).toBe(409);
    await expect(folderOwner("source-folder")).resolves.toEqual({ owner_type: "anonymous", owner_id: "source" });
  });

  it("migrate-assets returns 403 for anonymous JWT because only durable users can claim guest assets", async () => {
    const guest = await seedGuest("source", true);
    expect((await migrate("source", guest.access, guest.access)).status).toBe(403);
    await expect(guestUpgrade("source")).resolves.toBeNull();
  });

  async function seedUser(id: string, defaults = false): Promise<string> {
    await db.prepare(`INSERT INTO "user" (id,email,created_at,updated_at,status)
      VALUES (?,?,'${NOW}','${NOW}','active')`).bind(id, `${id}@example.com`).run();
    await db.prepare(`INSERT INTO platform_account (id,user_id,platform,status,created_at,updated_at)
      VALUES (?,?,'ios','active','${NOW}','${NOW}')`).bind(id, id).run();
    const session = `${id}-session`;
    const refreshToken = await hashRefreshToken(`${session}-refresh`);
    await db.prepare(`INSERT INTO session (id,owner_type,owner_id,refresh_token,expires_at,created_at,platform,user_id)
      VALUES (?,'user',?,?,'2099-01-01','${NOW}','ios',?)`)
      .bind(session, id, refreshToken, id).run();
    if (defaults) {
      await db.prepare(`INSERT INTO portfolio_folder
        (id,owner_type,owner_id,name,is_default,sort_order,created_at,updated_at)
        VALUES (?,'user',?,'Main',1,0,'${NOW}','${NOW}')`).bind(`${id}-folder`, id).run();
      await db.prepare(`INSERT INTO user_preference
        (id,owner_type,owner_id,currency,amount_hidden,last_selected_folder_id,created_at,updated_at)
        VALUES (?,'user',?,'USD',0,?,'${NOW}','${NOW}')`).bind(`${id}-pref`, id, `${id}-folder`).run();
    }
    return await signAccessToken({ owner_type: "user", owner_id: id, session_id: session }, JWT_SECRET);
  }

  async function seedGuest(id: string, assets = false, upgraded: string | null = null) {
    await db.prepare(`INSERT INTO anonymous_account
      (id,device_id,created_at,upgraded_user_id,platform,status)
      VALUES (?,?,?,?,'ios','active')`).bind(id, `device-${id}`, NOW, upgraded).run();
    const session = `${id}-session`;
    const refreshToken = await hashRefreshToken(`${session}-refresh`);
    await db.prepare(`INSERT INTO session (id,owner_type,owner_id,refresh_token,expires_at,created_at,platform,user_id)
      VALUES (?,'anonymous',?,?,'2099-01-01',?,'ios',NULL)`)
      .bind(session, id, refreshToken, NOW).run();
    if (assets) {
      await db.prepare(`INSERT INTO portfolio_folder
        (id,owner_type,owner_id,name,is_default,sort_order,created_at,updated_at)
        VALUES (?,'anonymous',?,'Main',1,0,?,?)`).bind(`${id}-folder`, id, NOW, NOW).run();
      await db.prepare(`INSERT INTO wishlist_item (id,owner_type,owner_id,card_ref,created_at)
        VALUES (?,'anonymous',?,'card-1',?)`).bind(`${id}-wish`, id, NOW).run();
      await db.prepare(`INSERT INTO collection_item
        (id,owner_type,owner_id,folder_id,card_ref,object_type,grader,quantity,created_at,updated_at)
        VALUES (?,'anonymous',?,?,'card-1','tcg','Raw',1,?,?)`)
        .bind(`${id}-item`, id, `${id}-folder`, NOW, NOW).run();
      await db.prepare(`INSERT INTO user_preference
        (id,owner_type,owner_id,currency,amount_hidden,last_selected_folder_id,created_at,updated_at)
        VALUES (?,'anonymous',?,'USD',0,?,?,?)`).bind(`${id}-pref`, id, `${id}-folder`, NOW, NOW).run();
    }
    return { id, access: await signAccessToken({ owner_type: "anonymous", owner_id: id, session_id: session }, JWT_SECRET) };
  }

  async function migrate(id: string, userAccess: string, guestAccess?: string) {
    return await authRoutes.request("/migrate-assets", {
      method: "POST",
      headers: {
        "Content-Type": "application/json", Authorization: `Bearer ${userAccess}`,
        ...(guestAccess ? { "X-Anonymous-Authorization": `Bearer ${guestAccess}` } : {}),
      },
      body: JSON.stringify({ anonymous_id: id }),
    }, env);
  }
  async function folderOwner(id: string) { return await db.prepare("SELECT owner_type,owner_id FROM portfolio_folder WHERE id=?").bind(id).first(); }
  async function wishlistOwner(id: string) { return await db.prepare("SELECT owner_id FROM wishlist_item WHERE id=?").bind(id).first("owner_id"); }
  async function guestUpgrade(id: string) { return await db.prepare("SELECT upgraded_user_id FROM anonymous_account WHERE id=?").bind(id).first("upgraded_user_id"); }
});
