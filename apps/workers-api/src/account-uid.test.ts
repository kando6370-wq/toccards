import { Miniflare } from "miniflare";
import { describe, expect, it, vi } from "vitest";

import { reserveAccountUid } from "./account-uid";

describe("account UID reservation", () => {
  it("locks and allocates in one batch because concurrent accounts need distinct UIDs", async () => {
    const uidStatement = boundStatement();
    const lockStatement = boundStatement();
    const prepare = vi.fn()
      .mockReturnValueOnce(uidStatement)
      .mockReturnValueOnce(lockStatement);
    const batch = vi.fn().mockResolvedValue([
      result([], 1),
      result([{ uid: 100000 }], 1),
    ]);
    const db = { prepare, batch } as unknown as D1Database;

    await expect(reserveAccountUid(db, "2026-08-18T00:00:00.000Z"))
      .resolves.toBe("100000");

    expect(uidStatement.bind).toHaveBeenCalledWith("2026-08-18T00:00:00.000Z");
    expect(lockStatement.bind).toHaveBeenCalledWith("account-uid");
    expect(batch).toHaveBeenCalledWith([lockStatement, uidStatement]);
  });

  it("allocates distinct sequential UIDs for concurrent calls in the D1 transaction model", async () => {
    const mf = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      compatibilityDate: "2024-11-01",
      d1Databases: ["DB"],
    });
    try {
      const db = await mf.getD1Database("DB");
      await db.prepare("CREATE TABLE mutation_lock (lock_key TEXT PRIMARY KEY)").run();
      await db.prepare(
        "CREATE TABLE account_uid (uid INTEGER PRIMARY KEY, created_at TEXT NOT NULL)",
      ).run();

      const uids = await Promise.all([
        reserveAccountUid(db, "2026-08-18T00:00:00.000Z"),
        reserveAccountUid(db, "2026-08-18T00:00:00.000Z"),
      ]);

      expect(uids.sort()).toEqual(["100000", "100001"]);
    } finally {
      await mf.dispose();
    }
  });

  it.each([
    { rows: [] },
    { rows: [{ uid: 99999 }] },
    { rows: [{ uid: 100000.5 }] },
  ])("fails loudly for an invalid allocation result: $rows", async ({ rows }) => {
    const db = databaseWithResult(rows);

    await expect(reserveAccountUid(db, "2026-08-18T00:00:00.000Z"))
      .rejects.toThrow("Failed to reserve account UID.");
  });
});

function boundStatement(): D1PreparedStatement & { bind: ReturnType<typeof vi.fn> } {
  const statement = { bind: vi.fn() };
  statement.bind.mockReturnValue(statement);
  return statement as unknown as D1PreparedStatement & { bind: ReturnType<typeof vi.fn> };
}

function databaseWithResult(rows: unknown[]): D1Database {
  const uidStatement = boundStatement();
  const lockStatement = boundStatement();
  return {
    prepare: vi.fn()
      .mockReturnValueOnce(uidStatement)
      .mockReturnValueOnce(lockStatement),
    batch: vi.fn().mockResolvedValue([result([], 1), result(rows, 1)]),
  } as unknown as D1Database;
}

function result<T>(results: T[], changes: number): D1Result<T> {
  return {
    success: true,
    results,
    meta: { changes },
  } as D1Result<T>;
}
