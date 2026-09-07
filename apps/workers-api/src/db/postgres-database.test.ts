import { describe, expect, it, vi } from "vitest";

import {
  PostgresDatabase,
  convertQuestionMarkPlaceholders,
  normalizePostgresValue,
  runWithDatabaseLifecycle,
} from "./postgres-database";

describe("PostgresDatabase", () => {
  it("converts only placeholders outside SQL literals and comments", () => {
    const converted = convertQuestionMarkPlaceholders(`
      SELECT '?', "?", value
      FROM example
      WHERE id = ? AND note = 'it''s ?'
      -- ignored ?
      /* ignored ? */ AND status = ?
    `);

    expect(converted.count).toBe(2);
    expect(converted.sql).toContain("WHERE id = $1");
    expect(converted.sql).toContain("AND status = $2");
    expect(converted.sql).toContain("SELECT '?', \"?\"");
  });

  it("preserves D1-style query results and affected-row metadata", async () => {
    const unsafe = vi.fn()
      .mockResolvedValueOnce(queryResult([{ id: "row-1" }], "SELECT", 1))
      .mockResolvedValueOnce(queryResult([], "UPDATE", 1));
    const database = new PostgresDatabase(sqlClient({ unsafe }));

    await expect(database.prepare("SELECT id FROM example WHERE id = ?").bind("row-1").first())
      .resolves.toEqual({ id: "row-1" });
    const update = await database.prepare("UPDATE example SET active = ? WHERE id = ?")
      .bind(1, "row-1")
      .run();

    expect(unsafe.mock.calls[0]?.slice(0, 2)).toEqual([
      "SELECT id FROM example WHERE id = $1",
      ["row-1"],
    ]);
    expect(update.meta).toMatchObject({ changes: 1, rows_written: 1, changed_db: true });
  });

  it("executes a D1-style batch sequentially inside one PostgreSQL transaction", async () => {
    const order: string[] = [];
    const transactionUnsafe = vi.fn(async (query: string) => {
      order.push(query);
      return queryResult([], "UPDATE", 1);
    });
    const begin = vi.fn(async (callback: (transaction: unknown) => Promise<unknown>) =>
      callback({ unsafe: transactionUnsafe }));
    const database = new PostgresDatabase(sqlClient({ begin }));

    const results = await database.batch([
      database.prepare("UPDATE example SET value = ? WHERE id = ?").bind("a", "1"),
      database.prepare("UPDATE example SET value = ? WHERE id = ?").bind("b", "2"),
    ]);

    expect(begin).toHaveBeenCalledOnce();
    expect(order).toEqual([
      "UPDATE example SET value = $1 WHERE id = $2",
      "UPDATE example SET value = $1 WHERE id = $2",
    ]);
    expect(results.map((result) => result.meta.changes)).toEqual([1, 1]);
  });

  it("fails rather than losing precision for an oversized PostgreSQL bigint", () => {
    expect(() => normalizePostgresValue("9007199254740992", { type: 20 }))
      .toThrow("exceeds JavaScript safe integer range");
    expect(normalizePostgresValue("42", { type: 20 })).toBe(42);
  });

  it("rejects non-finite PostgreSQL numeric values instead of returning invalid JSON numbers", () => {
    expect(normalizePostgresValue("12.5", { type: 1700 })).toBe(12.5);
    for (const value of ["NaN", "Infinity", "-Infinity"]) {
      expect(() => normalizePostgresValue(value, { type: 1700 }))
        .toThrow("PostgreSQL numeric value is not finite");
    }
  });

  it.each([
    ["bigint", 20],
    ["numeric", 1700],
  ])("preserves SQL NULL for nullable PostgreSQL %s columns so missing values remain unknown", (_type, oid) => {
    expect(normalizePostgresValue(null, { type: oid })).toBeNull();
  });

  it("keeps PostgreSQL date and timestamptz response shapes distinct", () => {
    const value = new Date("2026-08-17T12:34:56.000Z");

    expect(normalizePostgresValue(value, { type: 1082 })).toBe("2026-08-17");
    expect(normalizePostgresValue(value, { type: 1184 })).toBe("2026-08-17T12:34:56.000Z");
    expect(normalizePostgresValue("2026-08-17", { type: 1082 })).toBe("2026-08-17");
  });

  it("keeps the request database open until waitUntil work settles", async () => {
    const background = deferred<void>();
    const close = vi.fn().mockResolvedValue(undefined);
    const pending: Promise<unknown>[] = [];
    const context = executionContext(pending);

    const response = await runWithDatabaseLifecycle({ close }, context, async (tracked) => {
      tracked.waitUntil(background.promise);
      return "response";
    });

    expect(response).toBe("response");
    expect(close).not.toHaveBeenCalled();

    background.resolve();
    await Promise.allSettled(pending);
    await Promise.allSettled(pending);
    expect(close).toHaveBeenCalledOnce();
  });

  it("does not leak an active task when waitUntil rejects registration", async () => {
    const close = vi.fn().mockResolvedValue(undefined);
    const pending: Promise<unknown>[] = [];
    let calls = 0;
    const context = {
      waitUntil(promise: Promise<unknown>) {
        calls += 1;
        if (calls === 1) throw new Error("waitUntil unavailable");
        pending.push(promise);
      },
      passThroughOnException() {},
    } as unknown as ExecutionContext;

    await runWithDatabaseLifecycle({ close }, context, async (tracked) => {
      expect(() => tracked.waitUntil(Promise.resolve())).toThrow("waitUntil unavailable");
      return "response";
    });

    await Promise.allSettled(pending);
    expect(close).toHaveBeenCalledOnce();
  });
});

function queryResult(
  rows: Record<string, unknown>[],
  command: string,
  count: number,
): unknown {
  return Object.assign(rows, {
    command,
    count,
    columns: Object.keys(rows[0] ?? {}).map((name) => ({ name })),
  });
}

function sqlClient(overrides: Record<string, unknown>): never {
  return {
    unsafe: vi.fn(),
    begin: vi.fn(),
    end: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  } as never;
}

function executionContext(pending: Promise<unknown>[]): ExecutionContext {
  return {
    waitUntil(promise: Promise<unknown>) {
      pending.push(promise);
    },
    passThroughOnException() {},
  } as unknown as ExecutionContext;
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}
