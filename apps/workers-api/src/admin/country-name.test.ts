import { describe, expect, it } from "vitest";
import { countryDisplayName } from "./country-name";

describe("Admin country display name", () => {
  it("renders Apple alpha-3 storefront and existing alpha-2 country codes consistently", () => {
    expect(countryDisplayName("USA")).toBe("美国");
    expect(countryDisplayName("US")).toBe("美国");
    expect(countryDisplayName(" usa ")).toBe("美国");
  });

  it("keeps missing and unknown country codes empty for XLSX cells", () => {
    expect(countryDisplayName(null)).toBe("");
    expect(countryDisplayName("ZZ")).toBe("");
    expect(countryDisplayName("INVALID")).toBe("");
  });
});
