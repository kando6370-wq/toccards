import { signAccessToken } from "@kando/auth-core";
import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { PGliteDatabase } from "./test-support/pglite-database";
import { authenticateOwner, type OwnerType } from "./owner-auth";

const JWT_SECRET = "owner-boundary-postgres-fixture";

describe("authenticateOwner PostgreSQL owner boundary", () => {
  let db: PGliteDatabase;
  beforeEach(async () => {
    db = await PGliteDatabase.create();
    for (const name of ["0000_business_schema.sql", "0018_platform_account_isolation.sql"]) {
      await db.exec(readFileSync(new URL(`./db/postgres/migrations/${name}`, import.meta.url), "utf8"));
    }
  });
  afterEach(async () => db.close());

  it.each([["anonymous", "100000"], ["user", "100001"]] as const)(
    "authenticates a live %s owner because the combined lookup must preserve valid sessions",
    async (ownerType, ownerId) => {
      await seedOwner(ownerType, ownerId);
      const token = await insertSession(ownerType, ownerId);
      expect(await authenticateOwner({ DB: db, JWT_SECRET }, `Bearer ${token}`)).toEqual({
        status: "ok",
        owner: {
          owner_type: ownerType, owner_id: ownerId, session_id: `session-${ownerId}`,
          platform: "ios", user_id: ownerType === "user" ? ownerId : null, data_space_id: ownerId,
        },
      });
    },
  );

  it("rejects upgraded guests and inactive users because query consolidation must not weaken owner validity", async () => {
    await seedOwner("anonymous", "100000");
    await seedOwner("user", "100001");
    await db.exec(`UPDATE anonymous_account SET upgraded_user_id = '100001';
      UPDATE "user" SET status = 'disabled'`);
    for (const [type, id] of [["anonymous", "100000"], ["user", "100001"]] as const) {
      const token = await insertSession(type, id);
      expect(await authenticateOwner({ DB: db, JWT_SECRET }, `Bearer ${token}`))
        .toEqual({ status: "unauthorized" });
    }
  });

  it.each(["platform", "user_id", "deleted"] as const)(
    "rejects a mismatched or removed platform relation (%s) even while the shared identity stays active",
    async (change) => {
      await seedOwner("user", "100001");
      const token = await insertSession("user", "100001");
      if (change === "platform") await db.exec("UPDATE session SET platform = 'android'");
      if (change === "user_id") await db.exec("UPDATE session SET user_id = 'another-identity'");
      if (change === "deleted") await db.exec("UPDATE platform_account SET status = 'deleted'");
      expect(await authenticateOwner({ DB: db, JWT_SECRET }, `Bearer ${token}`))
        .toEqual({ status: "unauthorized" });
    },
  );

  async function seedOwner(type: OwnerType, id: string): Promise<void> {
    if (type === "anonymous") {
      await db.prepare("INSERT INTO anonymous_account (id, device_id, created_at) VALUES (?, ?, '2026-11-05')")
        .bind(id, `fixture-${id}`).run();
    } else {
      await db.prepare('INSERT INTO "user" (id, email, created_at, updated_at) VALUES (?, ?, ?, ?)')
        .bind(id, `${id}@fixture.invalid`, "2026-11-05", "2026-11-05").run();
      await db.prepare(`INSERT INTO platform_account (id, user_id, platform, created_at, updated_at)
        VALUES (?, ?, 'ios', '2026-11-05', '2026-11-05')`).bind(id, id).run();
    }
  }

  async function insertSession(ownerType: OwnerType, ownerId: string): Promise<string> {
    const sessionId = `session-${ownerId}`;
    await db.prepare(`INSERT INTO session
      (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES (?, ?, ?, ?, '2099-01-01T00:00:00.000Z', '2026-11-05', 'ios', ?)`)
      .bind(sessionId, ownerType, ownerId, `fixture-${sessionId}`, ownerType === "user" ? ownerId : null).run();
    return signAccessToken({ owner_type: ownerType, owner_id: ownerId, session_id: sessionId }, JWT_SECRET);
  }
});
