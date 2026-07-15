export type ExchangeRateSnapshot = {
  base: "USD";
  rates: Record<string, number>;
  updatedAt: string;
  stale: boolean;
};

type CachedExchangeRateSnapshot = Omit<ExchangeRateSnapshot, "stale"> & {
  fetchedAt: number;
};

type Fetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

const CACHE_KEY = "exchange-rates:USD:v1";
const FRESH_FOR_MS = 6 * 60 * 60 * 1000;
const SOURCE_URL =
  "https://api.frankfurter.dev/v1/latest?from=USD&to=EUR,JPY,GBP,CAD,AUD,NZD,SGD";
const REQUIRED_TARGETS = ["EUR", "JPY", "GBP", "CAD", "AUD", "NZD", "SGD"];

export class ExchangeRateUnavailableError extends Error {
  constructor() {
    super("Exchange rates are unavailable.");
  }
}

export async function loadUsdExchangeRates(
  kv: KVNamespace,
  now: number = Date.now(),
  fetcher: Fetcher = fetch,
): Promise<ExchangeRateSnapshot> {
  const cached = await readCachedSnapshot(kv);
  if (cached && now - cached.fetchedAt < FRESH_FOR_MS) {
    return publicSnapshot(cached, false);
  }

  try {
    const response = await fetcher(SOURCE_URL, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new ExchangeRateUnavailableError();
    const snapshot = snapshotFromSource(await response.json(), now);
    await kv.put(CACHE_KEY, JSON.stringify(snapshot));
    return publicSnapshot(snapshot, false);
  } catch {
    if (cached) return publicSnapshot(cached, true);
    throw new ExchangeRateUnavailableError();
  }
}

async function readCachedSnapshot(
  kv: KVNamespace,
): Promise<CachedExchangeRateSnapshot | null> {
  try {
    const encoded = await kv.get(CACHE_KEY);
    if (!encoded) return null;
    return cachedSnapshotFromUnknown(JSON.parse(encoded));
  } catch {
    return null;
  }
}

function snapshotFromSource(
  value: unknown,
  fetchedAt: number,
): CachedExchangeRateSnapshot {
  if (!isRecord(value) || value.base !== "USD" || !isDate(value.date)) {
    throw new ExchangeRateUnavailableError();
  }
  const rates = ratesFromUnknown(value.rates);
  if (!rates) throw new ExchangeRateUnavailableError();
  return {
    base: "USD",
    rates: { USD: 1, ...rates },
    updatedAt: `${value.date}T00:00:00.000Z`,
    fetchedAt,
  };
}

function cachedSnapshotFromUnknown(
  value: unknown,
): CachedExchangeRateSnapshot | null {
  if (
    !isRecord(value) ||
    value.base !== "USD" ||
    typeof value.updatedAt !== "string" ||
    !Number.isFinite(value.fetchedAt)
  ) {
    return null;
  }
  const rates = ratesFromUnknown(value.rates, true);
  if (!rates) return null;
  return {
    base: "USD",
    rates,
    updatedAt: value.updatedAt,
    fetchedAt: value.fetchedAt as number,
  };
}

function ratesFromUnknown(
  value: unknown,
  includeUsd = false,
): Record<string, number> | null {
  if (!isRecord(value)) return null;
  const targets = includeUsd ? ["USD", ...REQUIRED_TARGETS] : REQUIRED_TARGETS;
  const rates: Record<string, number> = {};
  for (const target of targets) {
    const rate = value[target];
    if (typeof rate !== "number" || !Number.isFinite(rate) || rate <= 0) {
      return null;
    }
    rates[target] = rate;
  }
  return rates;
}

function publicSnapshot(
  snapshot: CachedExchangeRateSnapshot,
  stale: boolean,
): ExchangeRateSnapshot {
  return {
    base: snapshot.base,
    rates: snapshot.rates,
    updatedAt: snapshot.updatedAt,
    stale,
  };
}

function isDate(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
