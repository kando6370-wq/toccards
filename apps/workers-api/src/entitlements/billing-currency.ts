import {
  loadUsdExchangeRates,
  type ExchangeRateSnapshot,
} from "../data-source/exchange-rates";

type RateLoader = (kv: KVNamespace, now: number) => Promise<ExchangeRateSnapshot>;

export type BillingUsdSnapshot = {
  amountUsdMicros: number;
  rate: string;
  base: "USD";
  quote: string;
  source: "frankfurter.dev" | "identity";
  effectiveAt: string;
  fetchedAt: string;
  stale: 0 | 1;
  conversionVersion: "usd_divide_rate_v1";
  roundingMode: "half_away_from_zero";
};

export async function loadBillingUsdSnapshot(
  kv: KVNamespace,
  amountMicros: number | null,
  currency: string | null,
  now: Date,
  loadRates: RateLoader = loadUsdExchangeRates,
): Promise<BillingUsdSnapshot | null> {
  if (!Number.isSafeInteger(amountMicros) || amountMicros! < 0 || !currency) return null;
  const quote = currency.toUpperCase();
  if (quote === "USD") return snapshot(amountMicros!, "1", quote, "identity", now.toISOString(), now.toISOString(), 0);
  try {
    const rates = await loadRates(kv, now.getTime());
    const rate = rates.rates[quote];
    if (!Number.isFinite(rate) || rate <= 0) return null;
    const rateText = rate.toString();
    const converted = divideAndRoundMicros(amountMicros!, rateText);
    return converted === null ? null : snapshot(
      converted, rateText, quote, "frankfurter.dev", rates.updatedAt,
      rates.fetchedAt, rates.stale ? 1 : 0,
    );
  } catch {
    return null;
  }
}

export function divideAndRoundMicros(amountMicros: number, decimalRate: string): number | null {
  if (!Number.isSafeInteger(amountMicros) || amountMicros < 0) return null;
  const match = /^(\d+)(?:\.(\d+))?$/.exec(decimalRate);
  if (!match) return null;
  const scale = 10n ** BigInt(match[2]?.length ?? 0);
  const divisor = BigInt(`${match[1]}${match[2] ?? ""}`);
  if (divisor <= 0n) return null;
  const numerator = BigInt(amountMicros) * scale;
  const rounded = (numerator * 2n + divisor) / (divisor * 2n);
  const value = Number(rounded);
  return Number.isSafeInteger(value) ? value : null;
}

function snapshot(
  amountUsdMicros: number, rate: string, quote: string,
  source: BillingUsdSnapshot["source"], effectiveAt: string, fetchedAt: string,
  stale: 0 | 1,
): BillingUsdSnapshot {
  return {
    amountUsdMicros, rate, base: "USD", quote, source, effectiveAt, fetchedAt, stale,
    conversionVersion: "usd_divide_rate_v1", roundingMode: "half_away_from_zero",
  };
}
