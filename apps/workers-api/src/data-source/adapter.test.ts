import { describe, expect, it } from "vitest";
import { createMockDataSourceAdapter } from "./test-support/mock-data-source-adapter";

describe("DataSourceAdapter mock implementation", () => {
  it("returns paginated card search results because proxy routes need a stable provider-independent contract", async () => {
    const adapter = createMockDataSourceAdapter();

    const firstPage = await adapter.searchCards("charizard", {
      page: 1,
      page_size: 1,
    });
    const secondPage = await adapter.searchCards("charizard", {
      page: 2,
      page_size: 1,
    });

    expect(firstPage).toHaveLength(1);
    expect(secondPage).toHaveLength(1);
    expect(firstPage[0]?.card_ref).not.toBe(secondPage[0]?.card_ref);
    expect(firstPage[0]).toEqual(
      expect.objectContaining({
        card_ref: "mock:tcg:charizard-base-4",
        name: "Charizard",
        object_type: "tcg",
      }),
    );
  });

  it("filters search results by object_type because downstream pages should not mix card categories", async () => {
    const adapter = createMockDataSourceAdapter();

    const results = await adapter.searchCards("box", {
      object_type: "sealed",
    });

    expect(results).toEqual([
      expect.objectContaining({
        card_ref: "mock:sealed:booster-box",
        object_type: "sealed",
      }),
    ]);
  });

  it("returns empty fallback data for unknown cards because M2 must degrade without throwing", async () => {
    const adapter = createMockDataSourceAdapter();

    await expect(adapter.getCard("missing-card")).resolves.toBeNull();
    await expect(adapter.getMarketPrices("missing-card")).resolves.toEqual([]);
    await expect(
      adapter.getPriceSeries("missing-card", "Raw", null, "Near Mint", 30),
    ).resolves.toEqual([]);
    await expect(adapter.getSoldListings("missing-card")).resolves.toEqual([]);
  });
});
