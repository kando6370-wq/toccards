import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createPostgresDatabase: vi.fn(),
  runWithDatabaseLifecycle: vi.fn(),
  retryAppleNotificationInbox: vi.fn(),
  retryAppleServerApiCorrections: vi.fn(),
}));

vi.mock("./db/postgres-database", () => mocks);
vi.mock("./entitlements/apple-notification-routes", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./entitlements/apple-notification-routes")>()),
  retryAppleNotificationInbox: mocks.retryAppleNotificationInbox,
}));
vi.mock("./entitlements/apple-server-api-correction", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./entitlements/apple-server-api-correction")>()),
  retryAppleServerApiCorrections: mocks.retryAppleServerApiCorrections,
}));

import worker from "./index";

describe("Worker PostgreSQL runtime selection", () => {
  beforeEach(() => {
    mocks.createPostgresDatabase.mockReset();
    mocks.runWithDatabaseLifecycle.mockReset();
    mocks.retryAppleNotificationInbox.mockReset();
    mocks.retryAppleServerApiCorrections.mockReset();
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

  it("rejects a DB-only fetch because a retired D1 binding must never become the runtime data source", async () => {
    const legacyDb = { prepare: vi.fn() };

    await expect(worker.fetch(
      new Request("https://worker.test/api/v1/health"),
      {
        DB: legacyDb,
        CACHE_KV: {} as KVNamespace,
        JWT_SECRET: "test-secret",
      } as never,
      executionContext(),
    )).rejects.toThrow("HYPERDRIVE binding is required");

    expect(legacyDb.prepare).not.toHaveBeenCalled();
    expect(mocks.createPostgresDatabase).not.toHaveBeenCalled();
  });

  it("rejects DB-only scheduled execution because background jobs must use the same PostgreSQL boundary", () => {
    const context = executionContext();
    const legacyDb = { prepare: vi.fn() };

    expect(() => worker.scheduled(
      {} as ScheduledController,
      {
        DB: legacyDb,
        CACHE_KV: {} as KVNamespace,
        JWT_SECRET: "test-secret",
      } as never,
      context,
    )).toThrow("HYPERDRIVE binding is required");

    expect(context.waitUntil).not.toHaveBeenCalled();
    expect(legacyDb.prepare).not.toHaveBeenCalled();
    expect(mocks.retryAppleNotificationInbox).not.toHaveBeenCalled();
    expect(mocks.retryAppleServerApiCorrections).not.toHaveBeenCalled();
  });
});

function executionContext(): ExecutionContext {
  return {
    waitUntil: vi.fn(),
    passThroughOnException: vi.fn(),
    props: {},
  } as unknown as ExecutionContext;
}
