import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { AuthenticatedOwner } from "../owner-auth";
import { PGliteDatabase } from "../test-support/pglite-database";
import { reserveScanQuota } from "./quota";

const owner: AuthenticatedOwner = {
  owner_type: "user",
  owner_id: "android-space",
  session_id: "android-session",
  platform: "android",
  user_id: "base-user",
  data_space_id: "android-space",
};

describe("Android free-launch scan quota", () => {
  let db: PGliteDatabase;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(`
      CREATE TABLE mutation_lock (lock_key text PRIMARY KEY);
      CREATE TABLE scan_quota_request (
        request_id text PRIMARY KEY,
        owner_type text NOT NULL,
        owner_id text NOT NULL,
        session_id text NOT NULL,
        access_mode text NOT NULL CHECK (access_mode IN ('free', 'premium')),
        status text NOT NULL,
        scan_id text,
        processing_expires_at text,
        attempts integer NOT NULL DEFAULT 0,
        response_json text,
        http_status integer,
        created_at text NOT NULL,
        settled_at text,
        updated_at text NOT NULL
      );
    `);
  });

  afterEach(async () => db.close());

  it("bypasses the cumulative limit while persisting the launch access as free", async () => {
    for (let index = 0; index < 11; index += 1) {
      const reservation = await reserveScanQuota(
        db,
        owner,
        `android-request-${index}`,
        "free",
        new Date("2026-11-05T00:00:00.000Z"),
        { startProcessing: false, unlimited: true },
      );
      expect(reservation.status).toBe("reserved");
    }

    const rows = await db.prepare(`
      SELECT DISTINCT access_mode FROM scan_quota_request
      WHERE owner_type = ? AND owner_id = ?
    `).bind(owner.owner_type, owner.owner_id).all<{ access_mode: string }>();
    expect(rows.results).toEqual([{ access_mode: "free" }]);

    const limited = await reserveScanQuota(
      db,
      owner,
      "ios-style-request",
      "free",
      new Date("2026-11-05T00:00:00.000Z"),
      { startProcessing: false },
    );
    expect(limited.status).toBe("exhausted");
  });
});
