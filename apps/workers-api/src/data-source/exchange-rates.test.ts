import { describe, expect, it, vi } from "vitest";
import {
  ExchangeRateUnavailableError,
  loadUsdExchangeRates,
} from "./exchange-rates";

class FakeKv {
  values = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.values.get(key) ?? null;
  }

  async put(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }
}

const sourcePayload = {
  amount: 1,
  base: "USD",
  date: "2026-07-14",
  rates: {
    AUD: 1.4404,
    CAD: 1.4112,
    EUR: 0.87681,
    GBP: 0.74717,
    JPY: 162.22,
    NZD: 1.724,
    SGD: 1.2927,
  },
};

describe("loadUsdExchangeRates", () => {
  it("stores provider rates because currency conversion must use real market data", async () => {
    const kv = new FakeKv();
    const fetcher = vi.fn().mockResolvedValue(Response.json(sourcePayload));

    const result = await loadUsdExchangeRates(
      kv as unknown as KVNamespace,
      Date.parse("2026-07-15T00:00:00.000Z"),
      fetcher,
    );

    expect(result).toEqual({
      base: "USD",
      rates: { USD: 1, ...sourcePayload.rates },
      updatedAt: "2026-07-14T00:00:00.000Z",
      stale: false,
    });
    expect(fetcher).toHaveBeenCalledOnce();
    expect(kv.values.size).toBe(1);
  });

  it("uses a fresh snapshot without calling the provider because rates are shared infrastructure", async () => {
    const kv = new FakeKv();
    const now = Date.parse("2026-07-15T00:00:00.000Z");
    const firstFetch = vi.fn().mockResolvedValue(Response.json(sourcePayload));
    await loadUsdExchangeRates(kv as unknown as KVNamespace, now, firstFetch);
    const secondFetch = vi.fn();

    const result = await loadUsdExchangeRates(
      kv as unknown as KVNamespace,
      now + 60_000,
      secondFetch,
    );

    expect(result.stale).toBe(false);
    expect(secondFetch).not.toHaveBeenCalled();
  });

  it("returns the last successful snapshot as stale because an upstream outage must not invent rates", async () => {
    const kv = new FakeKv();
    const now = Date.parse("2026-07-15T00:00:00.000Z");
    await loadUsdExchangeRates(
      kv as unknown as KVNamespace,
      now,
      vi.fn().mockResolvedValue(Response.json(sourcePayload)),
    );

    const result = await loadUsdExchangeRates(
      kv as unknown as KVNamespace,
      now + 7 * 60 * 60 * 1000,
      vi.fn().mockRejectedValue(new Error("upstream unavailable")),
    );

    expect(result.stale).toBe(true);
    expect(result.rates.EUR).toBe(0.87681);
  });

  it("fails when neither provider nor cache can prove a rate", async () => {
    await expect(
      loadUsdExchangeRates(
        new FakeKv() as unknown as KVNamespace,
        Date.now(),
        vi.fn().mockRejectedValue(new Error("upstream unavailable")),
      ),
    ).rejects.toBeInstanceOf(ExchangeRateUnavailableError);
  });
});
