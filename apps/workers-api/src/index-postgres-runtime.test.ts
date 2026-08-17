import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createPostgresDatabase: vi.fn(),
  runWithDatabaseLifecycle: vi.fn(),
}));

vi.mock("./db/postgres-database", () => mocks);

import worker from "./index";

describe("Worker PostgreSQL runtime selection", () => {
  beforeEach(() => {
    mocks.createPostgresDatabase.mockReset();
    mocks.runWithDatabaseLifecycle.mockReset();
  });

  it("prefers Hyperdrive when a stale D1 binding is also present because cutover must not read the retired database", async () => {
    const postgres = { close: vi.fn() };
    mocks.createPostgresDatabase.mockReturnValue(postgres);
    mocks.runWithDatabaseLifecycle.mockImplementation(
      async (_database, context, handler) => handler(context),
    );
    const context = executionContext();

    const response = await worker.fetch(
      new Request("https://worker.test/api/v1/health"),
      {
        DB: { prepare: vi.fn(() => { throw new Error("legacy D1 must not be used"); }) },
        HYPERDRIVE: { connectionString: "postgres://hyperdrive" },
        CACHE_KV: {} as KVNamespace,
        JWT_SECRET: "test-secret",
      } as never,
      context,
    );

    expect(response.status).toBe(200);
    expect(mocks.createPostgresDatabase).toHaveBeenCalledWith("postgres://hyperdrive");
    expect(mocks.runWithDatabaseLifecycle).toHaveBeenCalledWith(
      postgres,
      context,
      expect.any(Function),
    );
  });
});

function executionContext(): ExecutionContext {
  return {
    waitUntil: vi.fn(),
    passThroughOnException: vi.fn(),
    props: {},
  } as unknown as ExecutionContext;
}
