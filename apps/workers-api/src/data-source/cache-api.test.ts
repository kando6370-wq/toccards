import { describe, expect, it } from "vitest";
import type {
  CardSearchResult,
  DataSourceAdapter,
  MarketPrice,
  PricePoint,
  SoldListing,
} from "./adapter";
import { createCacheApiDataSourceAdapter } from "./cache-api";

class FakeCache {
  values = new Map<string, Response>();
  puts: Array<{ requestUrl: string; response: Response }> = [];
  failNextPut = false;

  async match(request: Request): Promise<Response | undefined> {
    return this.values.get(request.url);
  }

  async put(request: Request, response: Response): Promise<void> {
    if (this.failNextPut) {
      this.failNextPut = false;
      throw new Error("Injected Cache API put failure.");
    }

    this.values.set(request.url, response.clone());
    this.puts.push({ requestUrl: request.url, response: response.clone() });
  }
}

class CountingDataSourceAdapter implements DataSourceAdapter {
  marketPriceCalls = 0;
  priceSeriesCalls = 0;
  soldListingCalls = 0;
  trendingOptions: Array<{ page?: number; page_size?: number } | undefined> = [];

  async searchCards(): Promise<CardSearchResult[]> {
    return [];
  }

  async searchSets() {
    return [];
  }

  async getCard(): Promise<CardSearchResult | null> {
    return null;
  }

  async getPriceSeries(
    _card_ref: string,
    grader: string,
    grade: number | null,
    condition: string | null,
    days: number,
  ): Promise<PricePoint[]> {
    this.priceSeriesCalls += 1;
    return [
      {
        date: "2026-06-30",
        price:
          condition === "Near Mint" && grader === "Raw" && grade === null
            ? days
            : 1,
      },
    ];
  }

  async getMarketPrices(card_ref: string): Promise<MarketPrice[]> {
    this.marketPriceCalls += 1;
    return [
      {
        grader: "Raw",
        grade: null,
        condition: "Near Mint",
        price: card_ref.length,
      },
    ];
  }

  async getTrending(options?: { page?: number; page_size?: number }): Promise<CardSearchResult[]> {
    this.trendingOptions.push(options);
    return [];
  }

  async getSoldListings(card_ref: string): Promise<SoldListing[]> {
    this.soldListingCalls += 1;
    return [
      {
        date: "2026-06-29",
        title: card_ref,
        price: 5000,
        platform: "mock-market",
        url: null,
      },
    ];
  }
}

describe("Cache API data source adapter", () => {
  it("forwards Trending pagination because the outer production cache must not reset every request to page one", async () => {
    const source = new CountingDataSourceAdapter();
    const adapter = createCacheApiDataSourceAdapter(source, new FakeCache());

    await adapter.getTrending({ page: 2, page_size: 40 });

    expect(source.trendingOptions).toEqual([{ page: 2, page_size: 40 }]);
  });

  it("serves repeated getMarketPrices calls from Cache API because current price requests should not hit providers repeatedly", async () => {
    const cache = new FakeCache();
    const source = new CountingDataSourceAdapter();
    const adapter = createCacheApiDataSourceAdapter(source, cache);

    const first = await adapter.getMarketPrices("Mock:TCG:Charizard");
    const second = await adapter.getMarketPrices("mock:tcg:charizard");

    expect(first).toEqual(second);
    expect(source.marketPriceCalls).toBe(1);
    expect(cache.puts[0]?.requestUrl).toBe(
      "https://data-source-cache.invalid/getMarketPrices:v2:mock%3Atcg%3Acharizard",
    );
    expect(cache.puts[0]?.response.headers.get("Cache-Control")).toBe(
      "public, max-age=1800",
    );
  });

  it("keys getPriceSeries by grader grade condition and days because price chart dimensions must not share cached payloads", async () => {
    const cache = new FakeCache();
    const source = new CountingDataSourceAdapter();
    const adapter = createCacheApiDataSourceAdapter(source, cache);

    await adapter.getPriceSeries(
      "mock:tcg:charizard",
      "Raw",
      null,
      "Near Mint",
      30,
    );
    await adapter.getPriceSeries(
      "mock:tcg:charizard",
      "Raw",
      null,
      "Near Mint",
      30,
    );
    await adapter.getPriceSeries(
      "mock:tcg:charizard",
      "Raw",
      null,
      "Lightly Played",
      30,
    );

    expect(source.priceSeriesCalls).toBe(2);
    expect(cache.puts.map((put) => put.requestUrl)).toEqual([
      "https://data-source-cache.invalid/getPriceSeries:v2:mock%3Atcg%3Acharizard:raw:none:near%20mint:30",
      "https://data-source-cache.invalid/getPriceSeries:v2:mock%3Atcg%3Acharizard:raw:none:lightly%20played:30",
    ]);
  });

  it("returns fresh sold listings when Cache API write fails because cache backfill must not break responses", async () => {
    const cache = new FakeCache();
    cache.failNextPut = true;
    const source = new CountingDataSourceAdapter();
    const adapter = createCacheApiDataSourceAdapter(source, cache);

    const result = await adapter.getSoldListings("mock:tcg:charizard");

    expect(result).toEqual([
      expect.objectContaining({
        title: "mock:tcg:charizard",
        platform: "mock-market",
      }),
    ]);
    expect(source.soldListingCalls).toBe(1);
    expect(cache.puts).toEqual([]);
  });

  it("versions sold listing keys because marketplace source changes must not reuse stale empty payloads", async () => {
    const cache = new FakeCache();
    const source = new CountingDataSourceAdapter();
    const adapter = createCacheApiDataSourceAdapter(source, cache);

    await adapter.getSoldListings("mock:tcg:charizard");

    expect(cache.puts[0]?.requestUrl).toBe(
      "https://data-source-cache.invalid/getSoldListings:v4:mock%3Atcg%3Acharizard",
    );
  });
});
