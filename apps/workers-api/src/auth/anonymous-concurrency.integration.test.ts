import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { PGliteDatabase } from "../test-support/pglite-database";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Env } from "../env";
import { mutationLockKey } from "../db/mutation-lock";
import { authRoutes } from "./anonymous";

const JWT_SECRET = "anonymous-concurrency-test-secret";

describe("anonymous account concurrency", () => {
  let db: PGliteDatabase;
  let env: Env;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    for (const name of ["0000_business_schema.sql", "0006_mutation_lock.sql", "0018_platform_account_isolation.sql"]) {
      await db.exec(readFileSync(new URL(`../db/postgres/migrations/${name}`, import.meta.url), "utf8"));
    }
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET };
  });

  afterEach(async () => {
    await db.close();
  });

  it("creates one live owner for overlapping device requests because device identity cannot fork guest assets", async () => {
    const responses = await Promise.all([
      createAnonymous("same-device"),
      createAnonymous("same-device"),
    ]);
    const bodies = await Promise.all(responses.map((response) => response.json())) as Array<{
      data: { anonymous_id: string };
    }>;

    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    expect(new Set(bodies.map((body) => body.data.anonymous_id)).size).toBe(1);
    await expect(count("anonymous_account")).resolves.toBe(1);
    await expect(count("portfolio_folder")).resolves.toBe(1);
    await expect(count("user_preference")).resolves.toBe(1);
    await expect(count("session")).resolves.toBe(2);
    await expect(count("account_uid")).resolves.toBe(2);
    const lockRows = await db.prepare(
      "SELECT lock_key FROM mutation_lock ORDER BY lock_key",
    ).all<{ lock_key: string }>();
    expect(lockRows.results.map((row) => row.lock_key)).toEqual([
      "account-uid",
      await mutationLockKey("anonymous-device", "same-device"),
    ]);
  });

  async function createAnonymous(deviceId: string): Promise<Response> {
    return authRoutes.request("/anonymous", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: deviceId, platform: "ios" }),
    }, env);
  }

  async function count(table: string): Promise<number> {
    return await db.prepare(`SELECT COUNT(*) AS total FROM ${table}`).first<number>("total") ?? 0;
  }
});
