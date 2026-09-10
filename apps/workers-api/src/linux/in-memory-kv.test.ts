import { afterEach, describe, expect, it, vi } from "vitest";

import { createInMemoryKv } from "./in-memory-kv";

describe("Linux in-memory KV", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns cached strings and expires TTL entries", async () => {
    vi.useFakeTimers();
    const kv = createInMemoryKv();

    await kv.put("rates", "cached", { expirationTtl: 30 });
    expect(await kv.get("rates")).toBe("cached");

    vi.advanceTimersByTime(30_000);
    expect(await kv.get("rates")).toBeNull();
  });

  it("supports the JSON reads used by Cloudflare-compatible callers", async () => {
    const kv = createInMemoryKv();
    await kv.put("payload", JSON.stringify({ status: "ok" }));

    await expect(kv.get<{ status: string }>("payload", "json")).resolves.toEqual({
      status: "ok",
    });
  });
});
