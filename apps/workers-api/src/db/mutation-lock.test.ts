import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Miniflare } from "miniflare";
import { describe, expect, it, vi } from "vitest";

import {
  mutationLockKey,
  ownerCardMutationLockKey,
  runWithMutationLock,
  runWithMutationLockStatements,
  runWithMutationLocks,
} from "./mutation-lock";

describe("mutation lock", () => {
  it("uses one ordered batch so a guarded write observes the prior lock statement", async () => {
    const lockStatement = { bind: vi.fn() };
    lockStatement.bind.mockReturnValue(lockStatement);
    const guardedStatement = {} as D1PreparedStatement;
    const guardedResult = result([{ id: "created" }], 1);
    const prepare = vi.fn().mockReturnValue(lockStatement);
    const batch = vi.fn().mockResolvedValue([result([], 1), guardedResult]);
    const db = { prepare, batch } as unknown as D1Database;

    await expect(runWithMutationLock(db, "account-uid", guardedStatement))
      .resolves.toBe(guardedResult);
    expect(lockStatement.bind).toHaveBeenCalledWith("account-uid");
    expect(batch).toHaveBeenCalledOnce();
    expect(batch).toHaveBeenCalledWith([lockStatement, guardedStatement]);
  });

  it("fails loudly when either statement does not complete", async () => {
    const bound = {} as D1PreparedStatement;
    const db = {
      prepare: () => ({ bind: () => bound }),
      batch: vi.fn().mockResolvedValue([result([], 1)]),
    } as unknown as D1Database;

    await expect(runWithMutationLock(db, "account-uid", bound))
      .rejects.toThrow("Mutation lock transaction did not complete");
  });

  it("keeps every guarded statement ordered after one lock because cross-table invariants share a transaction", async () => {
    const lockStatement = { bind: vi.fn() };
    lockStatement.bind.mockReturnValue(lockStatement);
    const first = {} as D1PreparedStatement;
    const second = {} as D1PreparedStatement;
    const firstResult = result([], 1);
    const secondResult = result([], 0);
    const db = {
      prepare: vi.fn().mockReturnValue(lockStatement),
      batch: vi.fn().mockResolvedValue([
        result([], 1),
        firstResult,
        secondResult,
      ]),
    } as unknown as D1Database;

    await expect(runWithMutationLockStatements(db, "owner-card", [first, second]))
      .resolves.toEqual([firstResult, secondResult]);
    expect(db.batch).toHaveBeenCalledWith([lockStatement, first, second]);
  });

  it("rejects an empty guarded batch because acquiring a durable lock alone is not a mutation", async () => {
    await expect(runWithMutationLockStatements({} as D1Database, "owner-card", []))
      .rejects.toThrow("Mutation lock requires at least one guarded statement");
  });

  it("deduplicates and sorts multiple locks because overlapping invariants must not deadlock", async () => {
    const statements = new Map<string, D1PreparedStatement>();
    const prepare = vi.fn(() => {
      const statement = { bind: vi.fn((key: string) => {
        const bound = { key } as unknown as D1PreparedStatement;
        statements.set(key, bound);
        return bound;
      }) };
      return statement;
    });
    const guarded = {} as D1PreparedStatement;
    const guardedResult = result([], 1);
    const batch = vi.fn().mockImplementation(async (batchStatements: D1PreparedStatement[]) => [
      ...batchStatements.slice(0, -1).map(() => result([], 1)),
      guardedResult,
    ]);
    const db = { prepare, batch } as unknown as D1Database;

    await expect(runWithMutationLocks(
      db,
      ["scan-confirm", "owner-card", "scan-confirm"],
      [guarded],
    )).resolves.toEqual([guardedResult]);
    expect(batch).toHaveBeenCalledWith([
      statements.get("owner-card"),
      statements.get("scan-confirm"),
      guarded,
    ]);
  });

  it("hashes dynamic identities so lock rows do not duplicate raw identifiers", async () => {
    const identity = "user:customer@example.com";
    const first = await mutationLockKey("verification-code-register", identity);
    const second = await mutationLockKey("verification-code-register", identity);

    expect(first).toBe(second);
    expect(first).toMatch(/^verification-code-register:[0-9a-f]{64}$/);
    expect(first).not.toContain(identity);
    await expect(mutationLockKey("account-uid")).resolves.toBe("account-uid");
    await expect(ownerCardMutationLockKey(
      { owner_type: "user", owner_id: "customer@example.com" },
      "card:secret",
    )).resolves.toMatch(/^owner-card:[0-9a-f]{64}$/);
  });

  it("rejects unscoped or raw lock identifiers before they can reach persistence", async () => {
    const db = {} as D1Database;
    const statement = {} as D1PreparedStatement;

    await expect(mutationLockKey("", "identity")).rejects.toThrow("Invalid mutation lock scope");
    await expect(mutationLockKey("Verification Code", "identity"))
      .rejects.toThrow("Invalid mutation lock scope");
    await expect(runWithMutationLock(db, "verification-code:user@example.com", statement))
      .rejects.toThrow("Invalid mutation lock key");
  });

  it("executes the lock SQL in Miniflare because D1 must preserve the guarded quota", async () => {
    const mf = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      compatibilityDate: "2024-11-01",
      d1Databases: ["DB"],
    });
    try {
      const db = await mf.getD1Database("DB");
      await db.prepare("CREATE TABLE mutation_lock (lock_key TEXT PRIMARY KEY)").run();
      await db.prepare("CREATE TABLE guarded_value (id TEXT PRIMARY KEY)").run();
      const guarded = (id: string) => db.prepare(`
        INSERT INTO guarded_value (id)
        SELECT ?
        WHERE (SELECT COUNT(*) FROM guarded_value) < 1
      `).bind(id);

      const results = await Promise.all([
        runWithMutationLock(db, "quota-test", guarded("first")),
        runWithMutationLock(db, "quota-test", guarded("second")),
      ]);

      expect(results.map((entry) => entry.meta.changes).sort()).toEqual([0, 1]);
      await expect(db.prepare("SELECT COUNT(*) AS count FROM guarded_value").first("count"))
        .resolves.toBe(1);
    } finally {
      await mf.dispose();
    }
  });

  it("keeps the PostgreSQL migration runner and target inventory on the appended migration", () => {
    const directory = dirname(fileURLToPath(import.meta.url));
    const source = readFileSync(
      join(directory, "../../scripts/d1-postgres-migration/worker.ts"),
      "utf8",
    );

    expect(source).toContain('name: "0006_mutation_lock"');
    expect(source).toContain("expectedTargetTables: EXPECTED_TARGET_TABLES");
  });
});

function result<T>(results: T[], changes: number): D1Result<T> {
  return {
    success: true,
    results,
    meta: { changes },
  } as D1Result<T>;
}
