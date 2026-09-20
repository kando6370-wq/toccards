import { signAccessToken } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { PGliteDatabase } from "./test-support/pglite-database";
import { authenticateOwner, type OwnerType } from "./owner-auth";

const JWT_SECRET = "test-secret";

describe("authenticateOwner PostgreSQL owner boundary", () => {
  let db: PGliteDatabase;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(`
      CREATE TABLE anonymous_account (
        id text PRIMARY KEY,
        upgraded_user_id text
      );
      CREATE TABLE "user" (
        id text PRIMARY KEY,
        status text NOT NULL
      );
      CREATE TABLE session (
        id text PRIMARY KEY,
        owner_type text NOT NULL,
        owner_id text NOT NULL,
        expires_at text NOT NULL,
        revoked_at text
      );
    `);
  });

  afterEach(async () => db.close());

  it.each([
    ["anonymous", "100000"],
    ["user", "100001"],
  ] as const)(
    "authenticates a live %s owner because the combined lookup must preserve valid sessions",
    async (ownerType, ownerId) => {
      if (ownerType === "anonymous") {
        await db.prepare("INSERT INTO anonymous_account (id, upgraded_user_id) VALUES (?, NULL)")
          .bind(ownerId)
          .run();
      } else {
        await db.prepare("INSERT INTO \"user\" (id, status) VALUES (?, 'active')")
          .bind(ownerId)
          .run();
      }
      const token = await insertSession(ownerType, ownerId);

      await expect(authenticateOwner(
        { DB: db, JWT_SECRET },
        `Bearer ${token}`,
      )).resolves.toEqual({
        status: "ok",
        owner: {
          owner_type: ownerType,
          owner_id: ownerId,
          session_id: `session-${ownerId}`,
        },
      });
    },
  );

  it("rejects upgraded guests and inactive users because query consolidation must not weaken owner validity", async () => {
    await db.exec(`
      INSERT INTO anonymous_account (id, upgraded_user_id) VALUES ('100000', '100001');
      INSERT INTO "user" (id, status) VALUES ('100001', 'disabled');
    `);
    const anonymousToken = await insertSession("anonymous", "100000");
    const userToken = await insertSession("user", "100001");

    await expect(authenticateOwner(
      { DB: db, JWT_SECRET },
      `Bearer ${anonymousToken}`,
    )).resolves.toEqual({ status: "unauthorized" });
    await expect(authenticateOwner(
      { DB: db, JWT_SECRET },
      `Bearer ${userToken}`,
    )).resolves.toEqual({ status: "unauthorized" });
  });

  async function insertSession(ownerType: OwnerType, ownerId: string): Promise<string> {
    const sessionId = `session-${ownerId}`;
    await db.prepare(`
      INSERT INTO session (id, owner_type, owner_id, expires_at, revoked_at)
      VALUES (?, ?, ?, '2099-01-01T00:00:00.000Z', NULL)
    `).bind(sessionId, ownerType, ownerId).run();
    return signAccessToken(
      { owner_type: ownerType, owner_id: ownerId, session_id: sessionId },
      JWT_SECRET,
    );
  }
});
