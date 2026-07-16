import type { DataSourceAdapter } from "./adapter";

export type DataSourceCache = {
  match(request: Request): Promise<Response | undefined>;
  put(request: Request, response: Response): Promise<void>;
};

const CACHE_API_TTL_SECONDS = 30 * 60;
const CACHE_ORIGIN = "https://data-source-cache.invalid";

export function createCacheApiDataSourceAdapter(
  source: DataSourceAdapter,
  cache: DataSourceCache,
): DataSourceAdapter {
  return {
    searchCards(query, options) {
      return source.searchCards(query, options);
    },

    getCard(card_ref) {
      return source.getCard(card_ref);
    },

    getPriceSeries(card_ref, grader, grade, condition, days) {
      return readThroughCacheApi(
        cache,
        priceSeriesCacheKey(card_ref, grader, grade, condition, days),
        () => source.getPriceSeries(card_ref, grader, grade, condition, days),
      );
    },

    getMarketPrices(card_ref) {
      return readThroughCacheApi(cache, marketPricesCacheKey(card_ref), () =>
        source.getMarketPrices(card_ref),
      );
    },

    getTrending() {
      return source.getTrending();
    },

    getSoldListings(card_ref) {
      return readThroughCacheApi(cache, soldListingsCacheKey(card_ref), () =>
        source.getSoldListings(card_ref),
      );
    },
  };
}

async function readThroughCacheApi<T>(
  cache: DataSourceCache,
  key: string,
  loadFresh: () => Promise<T>,
): Promise<T> {
  const request = cacheRequest(key);
  const cached = await readCachedResponse<T>(cache, request);

  if (cached !== null) {
    return cached;
  }

  const fresh = await loadFresh();
  await writeCachedResponse(cache, request, fresh);

  return fresh;
}

async function readCachedResponse<T>(
  cache: DataSourceCache,
  request: Request,
): Promise<T | null> {
  try {
    const response = await cache.match(request);

    return response ? ((await response.clone().json()) as T) : null;
  } catch {
    return null;
  }
}

async function writeCachedResponse<T>(
  cache: DataSourceCache,
  request: Request,
  value: T,
): Promise<void> {
  try {
    const response = new Response(JSON.stringify(value), {
      headers: {
        "Cache-Control": `public, max-age=${CACHE_API_TTL_SECONDS}`,
        "Content-Type": "application/json",
      },
    });
    await cache.put(request, response);
  } catch {
    // Cache backfill must not turn a successful adapter response into a 500.
  }
}

function cacheRequest(key: string): Request {
  return new Request(`${CACHE_ORIGIN}/${key}`);
}

function marketPricesCacheKey(card_ref: string): string {
  return ["getMarketPrices", cacheKeyPart(card_ref)].join(":");
}

function priceSeriesCacheKey(
  card_ref: string,
  grader: string,
  grade: number | null,
  condition: string | null,
  days: number,
): string {
  return [
    "getPriceSeries",
    cacheKeyPart(card_ref),
    cacheKeyPart(grader),
    nullableCacheKeyPart(grade),
    nullableCacheKeyPart(condition),
    String(days),
  ].join(":");
}

function soldListingsCacheKey(card_ref: string): string {
  return ["getSoldListings", "v2", cacheKeyPart(card_ref)].join(":");
}

function nullableCacheKeyPart(value: string | number | null): string {
  return value === null ? "none" : cacheKeyPart(String(value));
}

function cacheKeyPart(value: string): string {
  return encodeURIComponent(value.trim().toLowerCase());
}
