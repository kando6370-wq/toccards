import { afterEach, describe, expect, it, vi } from "vitest";

import { createExtensionRateLimiter } from "./extension-rate-limiter";

const first = { key: "192.0.2.1" };
const second = { key: "192.0.2.2" };

describe("Linux plugin burst protection", () => {
  afterEach(() => { vi.useRealTimers(); });

  it("allows normal anonymous use but refuses the 61st request from the same IP in a minute", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(0);
    const limiter = createExtensionRateLimiter();
    const results = await Promise.all(Array.from({ length: 61 }, () => limiter.limit(first)));
    expect(results.filter((result) => result.success)).toHaveLength(60);
    expect(results.at(-1)).toEqual({ success: false });
  });

  it("does not lock everyone out because one public plugin client has exhausted its IP window", async () => {
    const limiter = createExtensionRateLimiter(1);
    expect(await limiter.limit(first)).toEqual({ success: true });
    expect(await limiter.limit(first)).toEqual({ success: false });
    expect(await limiter.limit(second)).toEqual({ success: true });
  });

  it("resets after the minute boundary instead of implementing a daily scan allowance", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(0);
    const limiter = createExtensionRateLimiter(1);
    await limiter.limit(first);
    vi.setSystemTime(59_999);
    expect(await limiter.limit(first)).toEqual({ success: false });
    vi.setSystemTime(60_000);
    expect(await limiter.limit(first)).toEqual({ success: true });
  });

  it("bounds anonymous source memory without evicting existing counters and reopening throttled IPs", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(0);
    const limiter = createExtensionRateLimiter(1);
    for (let index = 0; index < 10_000; index += 1) {
      expect(await limiter.limit({ key: String(index) })).toEqual({ success: true });
    }
    expect(await limiter.limit({ key: "new-source" })).toEqual({ success: false });
    expect(await limiter.limit({ key: "0" })).toEqual({ success: false });
    vi.setSystemTime(60_000);
    expect(await limiter.limit({ key: "new-source" })).toEqual({ success: true });
  });
});
