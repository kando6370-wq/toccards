import { describe, expect, it } from "vitest";
import { canonicalJson, parseDisplayConfig } from "./model";
import { validateCatalogReferences } from "./catalog";
import { displayFixture, catalogFixture } from "./test-fixtures";

describe("subscription display contract", () => {
  it("preserves optional price visibility and independent trial mode without changing legacy payloads", () => {
    const legacy = displayFixture();
    expect(parseDisplayConfig(legacy)).toEqual({ config: legacy, issues: [] });
    expect(parseDisplayConfig(legacy).config?.skus[0]).not.toHaveProperty("hide_price");
    expect(parseDisplayConfig(legacy).config?.skus[0].trial).not.toHaveProperty("price_mode");

    const config = displayFixture();
    config.skus[0].price_mode = "weekly";
    config.skus[0].hide_price = true;
    config.skus[0].trial!.price_mode = "actual";
    config.skus[0].trial!.hide_price = false;
    expect(parseDisplayConfig(config)).toEqual({ config, issues: [] });

    config.trial_enabled = false;
    expect(parseDisplayConfig(config)).toEqual({ config, issues: [] });
  });

  it("preserves optional weekly-only flags and accepts a trial's explicit false override", () => {
    const config = displayFixture();
    config.skus[0].price_mode = "weekly";
    config.skus[0].weekly_only = true;
    config.skus[0].trial!.weekly_only = false;
    expect(parseDisplayConfig(config)).toEqual({ config, issues: [] });
    delete config.skus[0].trial!.weekly_only;
    expect(parseDisplayConfig(config).config?.skus[0].trial).not.toHaveProperty("weekly_only");
    delete config.skus[0].weekly_only;
    expect(parseDisplayConfig(config).config?.skus[0]).not.toHaveProperty("weekly_only");
  });

  it("rejects invalid optional visibility and trial price modes without admitting a new base enum", () => {
    for (const [field, value, path] of [
      ["hide_price", "false", "skus.0.hide_price"],
      ["price_mode", "none", "skus.0.price_mode"],
      ["price_mode", "weekly_only", "skus.0.price_mode"],
      ["weekly_only", "true", "skus.0.weekly_only"],
    ] as const) {
      const config = displayFixture();
      (config.skus[0] as unknown as Record<string, unknown>)[field] = value;
      expect(parseDisplayConfig(config).issues).toEqual(expect.arrayContaining([expect.objectContaining({ path })]));
    }
    for (const [field, value, path] of [
      ["hide_price", 0, "skus.0.trial.hide_price"],
      ["price_mode", "none", "skus.0.trial.price_mode"],
      ["price_mode", "weekly_only", "skus.0.trial.price_mode"],
      ["weekly_only", 1, "skus.0.trial.weekly_only"],
    ] as const) {
      const config = displayFixture();
      (config.skus[0].trial as unknown as Record<string, unknown>)[field] = value;
      expect(parseDisplayConfig(config).issues).toEqual(expect.arrayContaining([expect.objectContaining({ path })]));
    }
  });

  it("requires weekly price mode when the weekly-only flag is true", () => {
    const config = displayFixture();
    config.skus[0].weekly_only = true;
    expect(parseDisplayConfig(config).issues).toEqual(expect.arrayContaining([
      expect.objectContaining({ path: "skus.0.weekly_only" }),
    ]));
    config.skus[0].price_mode = "weekly";
    config.skus[0].trial!.weekly_only = true;
    expect(parseDisplayConfig(config).issues).toEqual([]);
    config.skus[0].trial!.price_mode = "actual";
    expect(parseDisplayConfig(config).issues).toEqual(expect.arrayContaining([
      expect.objectContaining({ path: "skus.0.trial.weekly_only" }),
    ]));
  });

  it.each(["page", "modal"] as const)("allows three %s display SKUs with linked trials and rejects a fourth without truncation", (pageType) => {
    const config = displayFixture(); config.page_type = pageType;
    config.skus.push({ ...config.skus[0], product_id: "paid.year", is_default: false, trial: null });
    expect(parseDisplayConfig(config)).toEqual({ config, issues: [] });
    config.skus.push({ ...config.skus[0], product_id: "independent.trial", is_default: false, trial: null });
    expect(parseDisplayConfig(config)).toEqual({ config: null,
      issues: [{ path: "skus", message: "At most 3 display SKUs are allowed." }] });
    expect(config.skus).toHaveLength(4);
    config.skus.splice(2, 1);
    expect(parseDisplayConfig(config)).toEqual({ config, issues: [] });
  });

  it("preserves optional CTA values and retained trial copy instead of copying group text", () => {
    const input = displayFixture();
    delete (input.skus[0] as Partial<typeof input.skus[0]>).cta;
    input.cta = "GROUP";
    input.trial_enabled = false;
    input.skus[0].trial!.cta = "old {price}";
    const parsed = parseDisplayConfig(input);
    expect(parsed.issues).toEqual([]);
    expect(parsed.config?.skus[0].cta).toBe("");
    expect(parsed.config?.skus[0].trial?.cta).toBe("old {price}");
    input.trial_enabled = true;
    expect(parseDisplayConfig(input).issues).toEqual(expect.arrayContaining([expect.objectContaining({ path: "skus.0.trial.cta" })]));
  });

  it.each(["group", "sku", "trial"])("%s CTA is plain text so the App cannot expose unexpanded variables", (location) => {
    for (const value of ["{price}", "{unknown}", "Buy {", "Try }"]) {
      const config = displayFixture();
      if (location === "group") config.cta = value;
      if (location === "sku") config.skus[0].cta = value;
      if (location === "trial") config.skus[0].trial!.cta = value;
      expect(parseDisplayConfig(config).config, value).toBeNull();
    }
  });

  it("accepts all empty CTA levels, but enforces length and keeps legitimate description prices", () => {
    const config = displayFixture();
    config.cta = " ";
    config.skus[0].cta = "";
    config.skus[0].trial!.cta = "";
    config.skus[0].billing_note = "Billed at {price}";
    expect(parseDisplayConfig(config).issues).toEqual([]);
    config.cta = "x".repeat(100);
    expect(parseDisplayConfig(config).issues).toEqual([]);
    config.cta += "x";
    expect(parseDisplayConfig(config).config).toBeNull();
    config.cta = "";
    config.skus[0].billing_note = "{days} free";
    expect(parseDisplayConfig(config).config).toBeNull();
  });

  it("requires one actual default and prevents hidden trial targets from occupying a second card", () => {
    const config = displayFixture();
    config.skus[0].is_default = false;
    expect(parseDisplayConfig(config).config).toBeNull();
    config.skus[0].is_default = true;
    config.trial_enabled = false;
    config.skus[1].product_id = config.skus[0].trial!.product_id;
    expect(parseDisplayConfig(config).issues.some((i) => i.message.includes("unique"))).toBe(true);
  });

  it("has no 30-second business cap but rejects unsafe, negative and fractional delays", () => {
    const config = displayFixture();
    config.close_delay_seconds = 3600;
    expect(parseDisplayConfig(config).config?.close_delay_seconds).toBe(3600);
    for (const delay of [-1, 1.1, Number.MAX_SAFE_INTEGER + 1]) {
      config.close_delay_seconds = delay;
      expect(parseDisplayConfig(config).config).toBeNull();
    }
  });

  it("does not accept client supplied catalog facts or a future configuration schema", () => {
    expect(parseDisplayConfig({ ...displayFixture(), approved: true }).config).toBeNull();
    expect(parseDisplayConfig({ ...displayFixture(), schema_version: 2 }).config).toBeNull();
  });

  it("validates same-group period and service level even when switching is disabled", () => {
    const config = displayFixture();
    const catalog = catalogFixture();
    expect(validateCatalogReferences(config, catalog)).toEqual([]);
    config.trial_enabled = false;
    catalog.products[1].group_level = 2;
    expect(validateCatalogReferences(config, catalog)).toHaveLength(1);
    catalog.products[1].group_level = 1;
    catalog.products[1].subscription_group_id = "other";
    expect(validateCatalogReferences(config, catalog)).toHaveLength(1);
    catalog.products[1].subscription_group_id = "123";
    catalog.products[1].period = "ONE_YEAR";
    expect(validateCatalogReferences(config, catalog)).toHaveLength(1);
    catalog.products[1].period = "ONE_WEEK";
    catalog.products[1].has_free_trial = false;
    expect(validateCatalogReferences(config, catalog)).toHaveLength(1);
  });

  it("accepts independent trial products and excludes Lifetime from trial or weekly substitution", () => {
    const config = displayFixture();
    config.trial_enabled = false;
    config.skus[0].product_id = "trial.week";
    config.skus[0].trial = null;
    expect(validateCatalogReferences(config, catalogFixture())).toEqual([]);
    config.skus[1].price_mode = "weekly";
    expect(parseDisplayConfig(config).config).toBeNull();
    expect(validateCatalogReferences(config, catalogFixture())).toHaveLength(1);
  });

  it("does not guess weekly formulas for unsupported Apple periods", () => {
    const config = displayFixture();
    config.skus[0].price_mode = "weekly";
    config.skus[0].trial = null;
    config.trial_enabled = false;
    const catalog = catalogFixture();
    catalog.products[0].period = "SIX_MONTHS";
    expect(validateCatalogReferences(config, catalog)[0].path).toBe("skus.0.price_mode");
    config.skus[0].price_mode = "actual";
    expect(validateCatalogReferences(config, catalog)).toEqual([]);
  });

  it("checks a trial's independent weekly reference against its Apple period", () => {
    const config = displayFixture();
    config.skus[0].trial!.price_mode = "weekly";
    const catalog = catalogFixture();
    expect(validateCatalogReferences(config, catalog)).toEqual([]);
    catalog.products[1].period = "SIX_MONTHS";
    expect(validateCatalogReferences(config, catalog)).toEqual(expect.arrayContaining([
      expect.objectContaining({ path: "skus.0.trial.price_mode" }),
    ]));
  });

  it("checks a trial's inherited weekly reference against its Apple period", () => {
    const config = displayFixture();
    config.skus[0].price_mode = "weekly";
    config.skus[0].weekly_only = true;
    const catalog = catalogFixture();
    catalog.products[0].period = "SIX_MONTHS";
    catalog.products[1].period = "SIX_MONTHS";
    expect(validateCatalogReferences(config, catalog)).toEqual(expect.arrayContaining([
      expect.objectContaining({ path: "skus.0.price_mode" }),
      expect.objectContaining({ path: "skus.0.trial.price_mode" }),
    ]));
  });

  it("idempotency normalizes key ordering but preserves meaningful SKU order and null", () => {
    expect(canonicalJson({ b: 2, a: [1, null] })).toBe(canonicalJson({ a: [1, null], b: 2 }));
    expect(canonicalJson({ a: [1, 2] })).not.toBe(canonicalJson({ a: [2, 1] }));
    expect(canonicalJson({ a: null })).not.toBe(canonicalJson({}));
  });
});
