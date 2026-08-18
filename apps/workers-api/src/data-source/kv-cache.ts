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
const CARD_RESPONSE_CACHE_VERSION = "v11";
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

    getPriceSeries(card_ref, grader, grade, condition, days, finish) {
      return source.getPriceSeries(card_ref, grader, grade, condition, days, finish);
    },

    async getPriceSeriesBatch(card_ref, requests) {
      if (source.getPriceSeriesBatch) {
        return source.getPriceSeriesBatch(card_ref, requests);
      }
      const results = [];
      for (const request of requests) {
        results.push(await source.getPriceSeries(
          card_ref,
          request.grader,
          request.grade,
          request.condition,
          request.days,
          request.finish,
        ));
      }
      return results;
    },

    getMarketPrices(card_ref, finish, language) {
      return source.getMarketPrices(card_ref, finish, language);
    },

    getTrending(options) {
      return source.getTrending(options);
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
  const setId = options?.set_id ?? "all";
  const setCode = options?.set_code ?? "all";

  return [
    CARD_RESPONSE_CACHE_VERSION,
    "searchCards",
    cacheKeyPart(query),
    cacheKeyPart(objectType),
    cacheKeyPart(game),
    cacheKeyPart(setId),
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
