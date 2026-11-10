import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { PGliteDatabase } from "../test-support/pglite-database";
import type { Env } from "../env";

const verifyPasswordSpy = vi.hoisted(() => vi.fn());
vi.mock("@kando/auth-core", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@kando/auth-core")>();
  verifyPasswordSpy.mockImplementation(actual.verifyPassword);
  return { ...actual, verifyPassword: verifyPasswordSpy };
});

import { authRoutes } from "./anonymous";

const migrations = new URL("../db/postgres/migrations/", import.meta.url);

describe("PostgreSQL login account-enumeration resistance", () => {
  let db: PGliteDatabase;
  let env: Env;

  beforeEach(async () => {
    verifyPasswordSpy.mockClear();
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0006_mutation_lock.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0018_platform_account_isolation.sql", migrations), "utf8"));
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET: "login-cost-secret" };
  });

  afterEach(async () => { await db.close(); });

  it("runs password verification for an unknown email because failure cost must not expose account existence", async () => {
    const response = await authRoutes.request("/login", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email: "unknown@example.com", password: "password-1", platform: "ios",
      }),
    }, env);
    expect(response.status).toBe(422);
    expect(verifyPasswordSpy).toHaveBeenCalledTimes(1);
    expect(verifyPasswordSpy.mock.calls[0]?.[0]).toBe("password-1");
  });
});
