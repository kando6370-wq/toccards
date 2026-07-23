import { describe, expect, it } from "vitest";
import type {
  CardSearchResult,
  DataSourceAdapter,
  MarketPrice,
  PricePoint,
  SoldListing,
} from "./adapter";
import { createKvCachedDataSourceAdapter } from "./kv-cache";

class FakeKvNamespace {
  values = new Map<string, string>();
  puts: Array<{
    key: string;
    value: string;
    options?: { expirationTtl?: number };
  }> = [];
  failNextPut = false;

  async get(key: string): Promise<string | null> {
    return this.values.get(key) ?? null;
  }

  async put(
    key: string,
    value: string,
    options?: { expirationTtl?: number },
  ): Promise<void> {
    if (this.failNextPut) {
      this.failNextPut = false;
      throw new Error("Injected KV put failure.");
    }

    this.values.set(key, value);
    this.puts.push({ key, value, options });
  }
}

class CountingDataSourceAdapter implements DataSourceAdapter {
  searchCalls = 0;
  trendingCalls = 0;

  constructor(
    private readonly cards: CardSearchResult[],
    private readonly trendingFails = false,
  ) {}

  async searchCards(): Promise<CardSearchResult[]> {
    this.searchCalls += 1;
    return this.cards;
  }

  async searchSets() {
    return [];
  }

  async getCard(): Promise<CardSearchResult | null> {
    return null;
  }

  async getPriceSeries(): Promise<PricePoint[]> {
    return [];
  }

  async getMarketPrices(): Promise<MarketPrice[]> {
    return [];
  }

  async getTrending(): Promise<CardSearchResult[]> {
    this.trendingCalls += 1;
    if (this.trendingFails) throw new Error("Injected Trending failure.");
    return this.cards;
  }

  async getSoldListings(): Promise<SoldListing[]> {
    return [];
  }
}

const card: CardSearchResult = {
  card_ref: "mock:tcg:charizard-base-4",
  name: "Charizard",
  set_name: "Base Set",
  set_code: "BS",
  card_number: "4/102",
  finish: "Holofoil",
  language: "English",
  object_type: "tcg",
  image_url: null,
  rarity: "Rare Holo",
};

describe("KV cached data source adapter", () => {
  it("serves repeated searchCards calls from KV because cache hits must avoid third-party requests", async () => {
    const kv = new FakeKvNamespace();
    const source = new CountingDataSourceAdapter([card]);
    const adapter = createKvCachedDataSourceAdapter(source, kv);

    const first = await adapter.searchCards(" Charizard GX ", {
      object_type: "tcg",
      page: 1,
      page_size: 20,
    });
    const second = await adapter.searchCards("charizard gx", {
      object_type: "tcg",
      page: 1,
      page_size: 20,
    });

    expect(first).toEqual([card]);
    expect(second).toEqual([card]);
    expect(source.searchCalls).toBe(1);
    expect(kv.puts).toEqual([
      {
        key: "v3:searchCards:charizard%20gx:tcg:all:all:1:20",
        value: JSON.stringify([card]),
        options: { expirationTtl: 3600 },
      },
    ]);
  });

  it("keeps set searches separate because opening one set must not reuse another set's cards", async () => {
    const kv = new FakeKvNamespace();
    const source = new CountingDataSourceAdapter([card]);
    const adapter = createKvCachedDataSourceAdapter(source, kv);

    await adapter.searchCards("", {
      game: "Magic: The Gathering",
      set_code: "FDN",
      page: 1,
      page_size: 40,
    });
    await adapter.searchCards("", {
      game: "Magic: The Gathering",
      set_code: "ECL",
      page: 1,
      page_size: 40,
    });

    expect(source.searchCalls).toBe(2);
    expect(kv.puts.map((put) => put.key)).toEqual([
      "v3:searchCards::all:magic%3A%20the%20gathering:fdn:1:40",
      "v3:searchCards::all:magic%3A%20the%20gathering:ecl:1:40",
    ]);
  });

  it("queries Trending on every request because View all must show the latest ranking", async () => {
    const kv = new FakeKvNamespace();
    const source = new CountingDataSourceAdapter([card]);
    const adapter = createKvCachedDataSourceAdapter(source, kv);

    await adapter.getTrending();
    await adapter.getTrending();

    expect(source.trendingCalls).toBe(2);
    expect(kv.puts).toEqual([
      {
        key: "v5:getTrending:last-known-good",
        value: JSON.stringify([card]),
        options: { expirationTtl: 86400 },
      },
    ]);
  });

  it("does not cache empty Trending because the external producer may populate increase rates at any time", async () => {
    const kv = new FakeKvNamespace();
    const source = new CountingDataSourceAdapter([]);
    const adapter = createKvCachedDataSourceAdapter(source, kv);

    await adapter.getTrending();
    await adapter.getTrending();

    expect(source.trendingCalls).toBe(2);
    expect(kv.puts).toEqual([]);
  });

  it("migrates the last successful Trending result during empty producer windows because deployment must not cold-start Home to no data", async () => {
    const kv = new FakeKvNamespace();
    kv.values.set("v4:getTrending", JSON.stringify([card]));
    const source = new CountingDataSourceAdapter([]);
    const adapter = createKvCachedDataSourceAdapter(source, kv);

    await expect(adapter.getTrending()).resolves.toEqual([card]);
    expect(source.trendingCalls).toBe(1);
    expect(kv.puts).toEqual([
      {
        key: "v5:getTrending:last-known-good",
        value: JSON.stringify([card]),
        options: { expirationTtl: 86400 },
      },
    ]);
  });

  it("serves the last successful Trending result during query failures because transient D1 errors are not empty rankings", async () => {
    const kv = new FakeKvNamespace();
    kv.values.set("v5:getTrending:last-known-good", JSON.stringify([card]));
    const source = new CountingDataSourceAdapter([], true);
    const adapter = createKvCachedDataSourceAdapter(source, kv);

    await expect(adapter.getTrending()).resolves.toEqual([card]);
    expect(source.trendingCalls).toBe(1);
  });

  it("returns fresh adapter data when KV write fails because cache backfill must not break responses", async () => {
    const kv = new FakeKvNamespace();
    kv.failNextPut = true;
    const source = new CountingDataSourceAdapter([card]);
    const adapter = createKvCachedDataSourceAdapter(source, kv);

    const result = await adapter.searchCards("charizard");

    expect(result).toEqual([card]);
    expect(source.searchCalls).toBe(1);
    expect(kv.puts).toEqual([]);
  });
});
