import assert from "node:assert/strict";
import test from "node:test";
import { countryName } from "../src/country-name.ts";

test("Apple storefront and installation country codes render the same Chinese country name", () => {
  assert.equal(countryName("USA"), "美国");
  assert.equal(countryName("US"), "美国");
  assert.equal(countryName(" usa "), "美国");
});

test("unknown country codes remain explicit", () => {
  assert.equal(countryName("ZZ"), "未知");
  assert.equal(countryName("INVALID"), "未知");
});
