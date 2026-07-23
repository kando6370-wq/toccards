import type {
  CardSearchOptions,
  DataSourceAdapter,
} from "./adapter";

export type DataSourceKvNamespace = {
  get(key: string): Promise<string | null>;
  put(
    key: string,
    value: string,
    options?: { expirationTtl?: number },
  ): Promise<void>;
};

const SEARCH_CARDS_TTL_SECONDS = 60 * 60;
const TRENDING_LAST_GOOD_TTL_SECONDS = 24 * 60 * 60;
const CARD_RESPONSE_CACHE_VERSION = "v3";
const TRENDING_RESPONSE_CACHE_VERSION = "v5";
const TRENDING_LEGACY_CACHE_KEY = "v4:getTrending";
const DEFAULT_SEARCH_PAGE = 1;
const DEFAULT_SEARCH_PAGE_SIZE = 20;

export function createKvCachedDataSourceAdapter(
  source: DataSourceAdapter,
  kv: DataSourceKvNamespace,
): DataSourceAdapter {
  return {
    async searchCards(query, options) {
      return readThroughKv(
        kv,
        searchCardsCacheKey(query, options),
        SEARCH_CARDS_TTL_SECONDS,
        () => source.searchCards(query, options),
      );
    },

    searchSets(query, options) {
      return source.searchSets(query, options);
    },

    getCard(card_ref) {
      return source.getCard(card_ref);
    },

    getPriceSeries(card_ref, grader, grade, condition, days) {
      return source.getPriceSeries(card_ref, grader, grade, condition, days);
    },

    getMarketPrices(card_ref) {
      return source.getMarketPrices(card_ref);
    },

    async getTrending() {
      const key = `${TRENDING_RESPONSE_CACHE_VERSION}:getTrending`;
      const lastGoodKey = `${key}:last-known-good`;
      var lastGood = await readCachedValue<
        Awaited<ReturnType<typeof source.getTrending>>
      >(kv, lastGoodKey);
      if (lastGood === null) {
        lastGood = await readCachedValue<
          Awaited<ReturnType<typeof source.getTrending>>
        >(kv, TRENDING_LEGACY_CACHE_KEY);
        if (lastGood !== null && lastGood.length > 0) {
          await writeCachedValue(
            kv,
            lastGoodKey,
            lastGood,
            TRENDING_LAST_GOOD_TTL_SECONDS,
          );
        }
      }
      try {
        const fresh = await source.getTrending();
        if (fresh.length === 0) return lastGood ?? fresh;

        if (JSON.stringify(fresh) != JSON.stringify(lastGood)) {
          await writeCachedValue(
            kv,
            lastGoodKey,
            fresh,
            TRENDING_LAST_GOOD_TTL_SECONDS,
          );
        }
        return fresh;
      } catch (error) {
        if (lastGood !== null) return lastGood;
        throw error;
      }
    },

    getSoldListings(card_ref) {
      return source.getSoldListings(card_ref);
    },
  };
}

async function readThroughKv<T>(
  kv: DataSourceKvNamespace,
  key: string,
  ttlSeconds: number,
  loadFresh: () => Promise<T>,
): Promise<T> {
  const cached = await readCachedValue<T>(kv, key);

  if (cached !== null) {
    return cached;
  }

  const fresh = await loadFresh();
  await writeCachedValue(kv, key, fresh, ttlSeconds);

  return fresh;
}

async function readCachedValue<T>(
  kv: DataSourceKvNamespace,
  key: string,
): Promise<T | null> {
  try {
    const rawValue = await kv.get(key);

    return rawValue === null ? null : (JSON.parse(rawValue) as T);
  } catch {
    return null;
  }
}

async function writeCachedValue<T>(
  kv: DataSourceKvNamespace,
  key: string,
  value: T,
  ttlSeconds: number,
): Promise<void> {
  try {
    await kv.put(key, JSON.stringify(value), { expirationTtl: ttlSeconds });
  } catch {
    // Cache backfill must not turn a successful adapter response into a 500.
  }
}

function searchCardsCacheKey(
  query: string,
  options: CardSearchOptions | undefined,
): string {
  const page = positiveIntegerOrDefault(options?.page, DEFAULT_SEARCH_PAGE);
  const pageSize = positiveIntegerOrDefault(
    options?.page_size,
    DEFAULT_SEARCH_PAGE_SIZE,
  );
  const objectType = options?.object_type ?? "all";
  const game = options?.game ?? "all";
  const setCode = options?.set_code ?? "all";

  return [
    CARD_RESPONSE_CACHE_VERSION,
    "searchCards",
    cacheKeyPart(query),
    cacheKeyPart(objectType),
    cacheKeyPart(game),
    cacheKeyPart(setCode),
    String(page),
    String(pageSize),
  ].join(":");
}

function cacheKeyPart(value: string): string {
  return encodeURIComponent(value.trim().toLowerCase());
}

function positiveIntegerOrDefault(
  value: number | undefined,
  fallback: number,
): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : fallback;
}
