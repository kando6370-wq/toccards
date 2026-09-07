import { describe, expect, it, vi } from "vitest";
import { divideAndRoundMicros, loadBillingUsdSnapshot } from "./billing-currency";

describe("billing USD snapshots", () => {
  it("divides by the USD-to-local rate with integer half-away rounding because order money must be deterministic", () => {
    expect(divideAndRoundMicros(8_768_100, "0.87681")).toBe(10_000_000);
    expect(divideAndRoundMicros(1, "2")).toBe(1);
  });

  it("freezes USD identity without an upstream request because USD orders already are the reporting amount", async () => {
    const kv = { get: vi.fn(), put: vi.fn() } as unknown as KVNamespace;
    const now = new Date("2026-08-12T12:00:00.000Z");
    const loadRates = vi.fn();
    await expect(loadBillingUsdSnapshot(kv, 49_990_000, "USD", now, loadRates)).resolves.toMatchObject({
      amountUsdMicros: 49_990_000, rate: "1", source: "identity",
      conversionVersion: "usd_divide_rate_v1", roundingMode: "half_away_from_zero",
    });
    expect(loadRates).not.toHaveBeenCalled();
  });

  it("freezes the provider rate and divides local micros because the source is quoted as local units per USD", async () => {
    const kv = {} as KVNamespace;
    const loadRates = vi.fn().mockResolvedValue({
      base: "USD", rates: { EUR: 0.87681 }, updatedAt: "2026-08-11T00:00:00.000Z",
      fetchedAt: "2026-08-12T12:00:00.000Z", stale: false,
    });
    await expect(loadBillingUsdSnapshot(kv, 8_768_100, "EUR", new Date(), loadRates)).resolves.toMatchObject({
      amountUsdMicros: 10_000_000, rate: "0.87681", quote: "EUR", source: "frankfurter.dev",
      effectiveAt: "2026-08-11T00:00:00.000Z", fetchedAt: "2026-08-12T12:00:00.000Z", stale: 0,
    });
  });

  it("keeps the snapshot empty when no rate can be proved because order ingestion must not invent financial facts", async () => {
    await expect(loadBillingUsdSnapshot(
      {} as KVNamespace, 1_000_000, "CHF", new Date(),
      vi.fn().mockRejectedValue(new Error("rates unavailable")),
    )).resolves.toBeNull();
  });
});
