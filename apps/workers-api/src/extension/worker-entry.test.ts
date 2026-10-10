import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createPostgresDatabase: vi.fn(),
  runWithDatabaseLifecycle: vi.fn(),
}));
vi.mock("../db/postgres-database", () => mocks);

import type { RuntimeEnv } from "../env";
import worker from "../index";

describe("Cloudflare plugin entry point", () => {
  beforeEach(() => {
    vi.spyOn(console, "info").mockImplementation(() => {});
    mocks.createPostgresDatabase.mockReturnValue({});
    mocks.runWithDatabaseLifecycle.mockImplementation(async (_database, context, handler) => handler(context));
  });
  afterEach(() => { vi.restoreAllMocks(); });

  function setup() {
    const limiter = vi.fn().mockResolvedValue({ success: true });
    const recognition = vi.fn().mockResolvedValue(Response.json({ candidates: [] }));
    const env = {
      HYPERDRIVE: { connectionString: "postgres://entry-test" },
      EXTENSION_RECOGNITION_KEY: "entry-test-only",
      EXTENSION_RECOGNITION_RATE_LIMITER: { limit: limiter },
      VECTOR_RECOGNITION: { fetch: recognition },
      EXTENSION_CLIENT_IP: "stale-runtime-value",
    } as unknown as RuntimeEnv;
    const context = { waitUntil: vi.fn(), passThroughOnException: vi.fn(), props: {} } as unknown as ExecutionContext;
    const request = (headers: Record<string, string>) => worker.fetch(new Request("https://worker.test/api/v1/extension/recognize", {
      method: "POST",
      headers: { Authorization: "Bearer entry-test-only", "Content-Type": "application/json", ...headers },
      body: JSON.stringify({ vector: [1, ...Array(511).fill(0)], card_type: 0 }),
    }), env, context);
    return { limiter, recognition, request };
  }

  it("keys protection from the platform client address rather than X-Forwarded-For or mutable runtime state", async () => {
    const { limiter, request } = setup();
    const response = await request({ "CF-Connecting-IP": "192.0.2.1", "X-Forwarded-For": "192.0.2.99" });
    expect(response.status).toBe(200);
    expect(limiter).toHaveBeenCalledExactlyOnceWith({ key: "192.0.2.1" });
  });

  it("fails closed without a platform address instead of trusting a caller-supplied forwarding chain", async () => {
    const { limiter, recognition, request } = setup();
    expect((await request({ "X-Forwarded-For": "192.0.2.99" })).status).toBe(503);
    expect(limiter).not.toHaveBeenCalled();
    expect(recognition).not.toHaveBeenCalled();
  });
});
