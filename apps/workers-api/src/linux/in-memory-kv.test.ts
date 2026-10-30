import { afterEach, describe, expect, it, vi } from "vitest";

import { createInMemoryKv } from "./in-memory-kv";

describe("Linux in-memory KV", () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("returns cached strings and expires TTL entries", async () => {
    vi.useFakeTimers();
    const kv = createInMemoryKv();

    await kv.put("rates", "cached", { expirationTtl: 30 });
    expect(await kv.get("rates")).toBe("cached");

    vi.advanceTimersByTime(30_000);
    expect(await kv.get("rates")).toBeNull();
  });

  it("releases expired one-off search entries without another read", async () => {
    vi.useFakeTimers();
    const kv = createInMemoryKv();

    await kv.put("one-off-search", "cached", { expirationTtl: 30 });
    expect(vi.getTimerCount()).toBe(1);
    vi.advanceTimersByTime(60_000);

    expect(vi.getTimerCount()).toBe(0);
    expect(await kv.get("one-off-search")).toBeNull();
  });

  it("keeps sweeping while another TTL entry remains valid", async () => {
    vi.useFakeTimers();
    const kv = createInMemoryKv();

    await kv.put("early", "first", { expirationTtl: 30 });
    await kv.put("late", "second", { expirationTtl: 90 });
    vi.advanceTimersByTime(60_000);

    expect(vi.getTimerCount()).toBe(1);
    expect(await kv.get("early")).toBeNull();
    expect(await kv.get("late")).toBe("second");

    vi.advanceTimersByTime(60_000);
    expect(vi.getTimerCount()).toBe(0);
    expect(await kv.get("late")).toBeNull();
  });

  it("does not keep cleanup running for non-expiring, replaced, or deleted entries", async () => {
    vi.useFakeTimers();
    const kv = createInMemoryKv();

    expect(vi.getTimerCount()).toBe(0);
    await kv.put("rates", "fallback");
    expect(vi.getTimerCount()).toBe(0);

    await kv.put("search", "first", { expirationTtl: 30 });
    expect(vi.getTimerCount()).toBe(1);
    await kv.put("search", "replacement");
    expect(vi.getTimerCount()).toBe(0);

    await kv.put("other-search", "cached", { expirationTtl: 30 });
    expect(vi.getTimerCount()).toBe(1);
    await kv.delete("other-search");
    expect(vi.getTimerCount()).toBe(0);

    vi.advanceTimersByTime(60_000);
    expect(await kv.get("rates")).toBe("fallback");
    expect(await kv.get("search")).toBe("replacement");
  });

  it("unrefs cleanup so an idle Linux process can exit", async () => {
    const timeoutSpy = vi.spyOn(globalThis, "setTimeout");
    const kv = createInMemoryKv();

    await kv.put("search", "cached", { expirationTtl: 30 });
    const timer = timeoutSpy.mock.results.at(-1)?.value as NodeJS.Timeout | undefined;
    expect(timer?.hasRef()).toBe(false);
    if (timer) clearTimeout(timer);
  });

  it("bounds expiring search entries while preserving the exchange-rate fallback", async () => {
    vi.useFakeTimers();
    const kv = createInMemoryKv();
    await kv.put("rates", "fallback");

    for (let index = 0; index <= 10_000; index += 1) {
      await kv.put(`search-${index}`, "cached", { expirationTtl: 3600 });
    }

    expect(await kv.get("search-0")).toBeNull();
    expect(await kv.get("search-10000")).toBe("cached");
    expect(await kv.get("rates")).toBe("fallback");
  });

  it("bounds retained payload bytes and never serves the previous value after an oversized overwrite", async () => {
    vi.useFakeTimers();
    const kv = createInMemoryKv();
    const payload = "x".repeat(9 * 1024 * 1024);

    await kv.put("first", payload, { expirationTtl: 3600 });
    await kv.put("second", payload, { expirationTtl: 3600 });
    expect(await kv.get("first")).toBeNull();
    expect((await kv.get("second"))?.length).toBe(payload.length);

    await kv.put("second", "x".repeat(17 * 1024 * 1024), { expirationTtl: 3600 });
    expect(await kv.get("second")).toBeNull();
  });

  it("supports the JSON reads used by Cloudflare-compatible callers", async () => {
    const kv = createInMemoryKv();
    await kv.put("payload", JSON.stringify({ status: "ok" }));

    await expect(kv.get<{ status: string }>("payload", "json")).resolves.toEqual({
      status: "ok",
    });
  });
});
