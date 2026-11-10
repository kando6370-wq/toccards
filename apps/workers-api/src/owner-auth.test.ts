import { signAccessToken } from "@kando/auth-core";
import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { PGliteDatabase } from "./test-support/pglite-database";
import { authenticateOwner } from "./owner-auth";

const secret = "owner-context-postgres-fixture";
let db: PGliteDatabase;

beforeEach(async () => {
  db = await PGliteDatabase.create();
  for (const name of ["0000_business_schema.sql", "0018_platform_account_isolation.sql"]) {
    await db.exec(readFileSync(new URL(`./db/postgres/migrations/${name}`, import.meta.url), "utf8"));
  }
});
afterEach(async () => { vi.restoreAllMocks(); await db.close(); });

describe("authenticateOwner session context", () => {
  it("returns the verified live session because Premium grants must not collapse to UID ownership", async () => {
    const token = await session(true);
    const prepared = vi.spyOn(db, "prepare");
    expect(await authenticateOwner({ DB: db, JWT_SECRET: secret }, `Bearer ${token}`)).toEqual({
      status: "ok",
      owner: {
        owner_type: "user", owner_id: "100000", session_id: "session-a",
        platform: "ios", user_id: "100000", data_space_id: "100000",
      },
    });
    expect(prepared).toHaveBeenCalledTimes(1);
    expect(prepared.mock.calls[0]?.[0]).toContain('JOIN "user"');
  });

  it("rejects a session whose owner was removed because one-round-trip authentication must preserve owner validation", async () => {
    const token = await session(false);
    expect(await authenticateOwner({ DB: db, JWT_SECRET: secret }, `Bearer ${token}`))
      .toEqual({ status: "unauthorized" });
  });

  it("rejects a revoked session because logout must invalidate its Premium proof", async () => {
    const token = await session(true);
    await db.exec("UPDATE session SET revoked_at = '2026-08-12T00:00:00.000Z'");
    expect(await authenticateOwner({ DB: db, JWT_SECRET: secret }, `Bearer ${token}`))
      .toEqual({ status: "unauthorized" });
  });
});

async function session(withOwner: boolean): Promise<string> {
  if (withOwner) await db.exec(`
    INSERT INTO "user" (id, email, created_at, updated_at)
    VALUES ('100000', 'owner@fixture.invalid', '2026-11-05', '2026-11-05');
    INSERT INTO platform_account (id, user_id, platform, created_at, updated_at)
    VALUES ('100000', '100000', 'ios', '2026-11-05', '2026-11-05');
  `);
  await db.exec(`INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
    VALUES ('session-a', 'user', '100000', 'fixture-refresh', '2099-01-01', '2026-11-05', 'ios', '100000')`);
  return signAccessToken({ owner_type: "user", owner_id: "100000", session_id: "session-a" }, secret);
}
