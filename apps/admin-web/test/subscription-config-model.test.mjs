import assert from "node:assert/strict";
import test from "node:test";
import { availableProducts, changePriceDisplayMode, changeProduct, changeTrialPriceDisplayMode, changeTrialProduct, editorFromRecord, moveSku, newEditor, priceDisplayMode, productMap, removeSku, toDisplayConfig, unlinkTrial, validateEditor } from "../src/subscription-config/model.ts";
import { catalogFixture, CONFIG_ID, editorFixture } from "./subscription-fixtures.mjs";

test("new configurations start empty and cannot accidentally be enabled or default a demo product", () => {
  const editor = newEditor("first");
  assert.equal(editor.enabled, false);
  assert.equal(editor.body.page_type, "");
  assert.equal(editor.body.skus[0].product_id, "");
  assert.equal(editor.body.skus[0].is_default, false);
  const issues = validateEditor(editor.body, catalogFixture());
  assert.ok(issues.some((i) => i.path === "page_type"));
  assert.ok(issues.some((i) => i.path === "skus"));
});

test("page and modal allow three display SKUs plus linked trials but reject a fourth independent trial", () => {
  for (const pageType of ["page", "modal"]) for (const enabled of [false, true]) {
    const body = editorFixture().body;
    body.page_type = pageType;
    body.skus.push({ ...body.skus[0], key: "yearly-card", product_id: "paid.year", is_default: false,
      trial: { ...body.skus[0].trial, product_id: "trial.year" } });
    assert.deepEqual(validateEditor(body, catalogFixture(), enabled), []);
    body.skus.push({ ...body.skus[0], key: "independent-card", product_id: "independent.trial", is_default: false, trial: null });
    assert.deepEqual(validateEditor(body, catalogFixture(), enabled), [{ path: "skus", message: "页面展示 SKU 最多只能配置 3 个" }]);
    const repaired = removeSku(body, "yearly-card");
    assert.deepEqual(validateEditor(repaired, catalogFixture(), enabled), []);
    assert.deepEqual(repaired.skus.map((sku) => sku.product_id), ["paid.week", "lifetime", "independent.trial"]);
    assert.equal(repaired.skus[0].is_default, true);
  }
});

test("source and trial targets occupy one configuration even when switching is disabled", () => {
  const body = editorFixture().body;
  body.trial_enabled = false;
  body.skus[1].product_type = "subscription";
  const catalog = catalogFixture();
  const available = availableProducts(body, 1, catalog.subscription.products);
  assert.ok(!available.some((p) => p.product_id === "paid.week"));
  assert.ok(!available.some((p) => p.product_id === "trial.week"));
  const released = unlinkTrial(body, body.skus[0].key);
  assert.ok(availableProducts(released, 1, catalog.subscription.products).some((p) => p.product_id === "trial.week"));
  assert.equal(released.skus[0].trial.cta, "START FREE TRIAL");
});

test("trial choices enforce group, period, level, free offer and configuration occupancy", () => {
  const body = editorFixture().body;
  const catalog = catalogFixture();
  const otherGroup = { ...catalog.subscription.products.at(-1), product_id: "foreign", subscription_group_id: "other" };
  const available = availableProducts(body, 0, [...catalog.subscription.products, otherGroup], true);
  assert.deepEqual(available.map((p) => p.product_id), ["trial.week", "independent.trial"]);
  body.skus[1].product_id = "independent.trial";
  assert.deepEqual(availableProducts(body, 0, catalog.subscription.products, true).map((p) => p.product_id), ["trial.week"]);
});

test("changing a product clears an invalid trial target but preserves marketing text and requires an explicit repair", () => {
  const body = editorFixture().body;
  body.skus[0].cta = "BUY";
  body.skus[0].billing_note = "Billed at {price}";
  const changed = changeProduct(body.skus[0], "paid.year", productMap(catalogFixture()));
  assert.equal(changed.trial.product_id, "");
  assert.equal(changed.trial.cta, "START FREE TRIAL");
  assert.equal(changed.cta, "BUY");
  assert.equal(changed.billing_note, "Billed at {price}");
  assert.equal(changed.needs_trial_repair, true);
  body.skus[0] = changed;
  assert.ok(validateEditor(body, catalogFixture()).some((i) => i.path === "skus.0.trial.product_id"));
  assert.equal(unlinkTrial(body, changed.key).trial_enabled, false);
});

test("type switching resets Product IDs and weekly pricing without erasing copy", () => {
  const sku = editorFixture().body.skus[0]; sku.price_mode = "weekly"; sku.weekly_only = true; sku.hide_price = true;
  const changed = changeProduct(sku, "", productMap(catalogFixture()), "non_consumable");
  assert.equal(changed.product_id, ""); assert.equal(changed.trial.product_id, "");
  assert.equal(changed.price_mode, "actual"); assert.equal(changed.name, "Weekly");
  assert.equal(changed.weekly_only, false);
  assert.equal(changed.hide_price, true);
  assert.equal(priceDisplayMode(changed), "hidden");
});

test("relinking a hidden trial resets unsupported weekly pricing but retains its hidden state", () => {
  const trial = editorFixture().body.skus[0].trial;
  trial.price_mode = "weekly"; trial.weekly_only = true; trial.hide_price = true;
  const catalogs = catalogFixture();
  const target = { ...catalogs.subscription.products.find((product) => product.product_id === "trial.week"), product_id: "trial.day", period: "ONE_DAY" };
  const products = productMap({ ...catalogs, subscription: { ...catalogs.subscription, products: [...catalogs.subscription.products, target] } });
  const changed = changeTrialProduct(trial, "trial.day", products);
  assert.equal(changed.product_id, "trial.day");
  assert.equal(changed.price_mode, "actual");
  assert.equal(changed.weekly_only, false);
  assert.equal(changed.hide_price, true);
  assert.equal(changed.name, "Weekly Trial");
});

test("switching to an unsupported period clears inherited weekly-only trial pricing", () => {
  const sku = editorFixture().body.skus[0];
  sku.price_mode = "weekly";
  sku.weekly_only = true;
  sku.trial.weekly_only = true;
  const catalogs = catalogFixture();
  catalogs.subscription.products.find((product) => product.product_id === "paid.week").period = "ONE_DAY";
  catalogs.subscription.products.find((product) => product.product_id === "trial.week").period = "ONE_DAY";
  const changed = changeProduct(sku, "paid.week", productMap(catalogs));
  assert.equal(changed.price_mode, "actual");
  assert.equal(changed.weekly_only, false);
  assert.equal(changed.trial.product_id, "trial.week");
  assert.equal(changed.trial.weekly_only, false);
});

test("reordering keeps the complete card and default, and removing the default requires reselection", () => {
  const body = editorFixture().body;
  const moved = moveSku(body, 0, 1);
  assert.deepEqual(moved.skus[1], body.skus[0]);
  assert.equal(moved.skus[1].is_default, true);
  assert.equal(removeSku(moved, "weekly-card").trial_enabled, false);
  assert.ok(validateEditor(removeSku(moved, "weekly-card"), catalogFixture()).some((i) => i.path === "skus"));
});

test("removing one of several trial relations does not turn off the remaining relation", () => {
  const body = editorFixture().body;
  body.skus.push({ ...body.skus[0], key: "yearly-card", product_id: "paid.year", is_default: false, trial: { ...body.skus[0].trial, product_id: "trial.year" } });
  const result = removeSku(body, "weekly-card");
  assert.equal(result.trial_enabled, true);
  assert.equal(result.skus.at(-1).trial.product_id, "trial.year");
});

test("catalog failure preserves saved references rather than classifying unknown products as deleted", () => {
  const body = editorFixture().body;
  const catalogs = catalogFixture();
  catalogs.subscription = { status: "error", products: [], error: "offline" };
  assert.ok(!validateEditor(body, catalogs).some((i) => i.path.endsWith("product_id")));
  catalogs.subscription.status = "loaded";
  assert.ok(validateEditor(body, catalogs).some((i) => i.path.endsWith("product_id")));
});

test("unadmitted products may prepare disabled configurations but cannot update active ones", () => {
  const body = editorFixture().body;
  const catalogs = catalogFixture();
  catalogs.subscription.products[0].admission = { admitted: false, reasons: ["DISPLAY_APPROVAL_REQUIRED"] };
  assert.deepEqual(validateEditor(body, catalogs, false), []);
  assert.ok(validateEditor(body, catalogs, true).some((i) => i.path === "skus.0.product_id"));
});

test("CTA validation matches the server while hidden trial copy and unused custom text are retained", () => {
  for (const target of ["group", "base", "trial"]) {
    const body = editorFixture().body;
    if (target === "group") body.cta = "Buy {price}";
    if (target === "base") body.skus[0].cta = "Buy {";
    if (target === "trial") body.skus[0].trial.cta = "Try {unknown}";
    assert.ok(validateEditor(body, catalogFixture()).some((i) => i.path.endsWith("cta")));
  }
  const body = editorFixture().body;
  body.trial_enabled = false; body.skus[0].trial.cta = "Legacy {price}";
  body.skus[0].billing_note = "Unused {unknown}"; body.skus[0].billing_note_mode = "auto";
  assert.deepEqual(validateEditor(body, catalogFixture()), []);
});

test("optional button text stays empty on edit and UI-only state never reaches the API", () => {
  const body = toDisplayConfig(editorFixture().body); delete body.skus[0].cta;
  let key = 0;
  const editor = editorFromRecord({ id: CONFIG_ID, body, page_type: "page", revision: 2, enabled: true }, () => "key-" + key++);
  assert.equal(editor.body.skus[0].cta, "");
  assert.equal(editor.body.skus[0].trial.cta, "START FREE TRIAL");
  assert.equal(editor.enabled, true); assert.equal(editor.revision, 2);
  const serialized = toDisplayConfig(editor.body);
  assert.ok(!("key" in serialized.skus[0]));
  assert.ok(!("needs_trial_repair" in serialized.skus[0]));
});

test("legacy trial pricing inherits the base mode until explicitly configured", () => {
  const body = toDisplayConfig(editorFixture().body);
  body.skus[0].price_mode = "weekly";
  const editor = editorFromRecord({ id: CONFIG_ID, body, page_type: "page", revision: 2, enabled: false }, () => "key");
  const sku = editor.body.skus[0];
  assert.equal(priceDisplayMode(sku, sku.trial), "weekly");
  sku.hide_price = true;
  assert.equal(priceDisplayMode(sku, sku.trial), "hidden");
  assert.ok(!("price_mode" in toDisplayConfig(editor.body).skus[0].trial));
  assert.ok(!("hide_price" in toDisplayConfig(editor.body).skus[0].trial));
  sku.trial.price_mode = "weekly";
  assert.equal(priceDisplayMode(sku, sku.trial), "hidden");
  sku.trial.hide_price = false;
  assert.equal(priceDisplayMode(sku, sku.trial), "weekly");
  sku.trial.price_mode = "actual";
  assert.equal(priceDisplayMode(sku, sku.trial), "actual");
  sku.trial.hide_price = true;
  assert.equal(priceDisplayMode(sku, sku.trial), "hidden");
  const saved = toDisplayConfig(editor.body).skus[0];
  assert.equal(saved.hide_price, true);
  assert.equal(saved.trial.price_mode, "actual");
  assert.equal(saved.trial.hide_price, true);
});

test("weekly-only pricing inherits to trials, supports explicit false, and stays hidden when requested", () => {
  const body = editorFixture().body;
  const sku = body.skus[0];
  sku.price_mode = "weekly";
  sku.weekly_only = true;
  assert.equal(priceDisplayMode(sku), "weekly_only");
  assert.equal(priceDisplayMode(sku, sku.trial), "weekly_only");
  sku.trial.weekly_only = false;
  assert.equal(priceDisplayMode(sku, sku.trial), "weekly");
  sku.trial.price_mode = "actual";
  assert.equal(priceDisplayMode(sku, sku.trial), "actual");
  sku.trial.price_mode = "weekly";
  sku.trial.weekly_only = true;
  sku.hide_price = true;
  assert.equal(priceDisplayMode(sku, sku.trial), "hidden");
  sku.trial.hide_price = false;
  assert.equal(priceDisplayMode(sku, sku.trial), "weekly_only");
  assert.equal(toDisplayConfig(body).skus[0].trial.weekly_only, true);
});

test("price selections write compatible weekly mode and clear invalid inherited trial flags", () => {
  const source = editorFixture().body.skus[0];
  const weeklyOnly = changePriceDisplayMode(source, "weekly_only");
  assert.equal(weeklyOnly.price_mode, "weekly");
  assert.equal(weeklyOnly.weekly_only, true);
  const regularTrial = changeTrialPriceDisplayMode(weeklyOnly.trial, "weekly");
  assert.equal(regularTrial.price_mode, "weekly");
  assert.equal(regularTrial.weekly_only, false);
  const actualTrial = changeTrialPriceDisplayMode(regularTrial, "actual");
  assert.equal(actualTrial.weekly_only, false);
  assert.equal(actualTrial.price_mode, "actual");
  const inheritedTrial = { ...weeklyOnly.trial, weekly_only: true, product_id: "" };
  const actualBase = changePriceDisplayMode({ ...weeklyOnly, trial: inheritedTrial }, "actual");
  assert.equal(actualBase.price_mode, "actual");
  assert.equal(actualBase.weekly_only, false);
  assert.equal(actualBase.trial.weekly_only, false);
  const hidden = changePriceDisplayMode(weeklyOnly, "hidden");
  assert.equal(hidden.weekly_only, true);
  assert.equal(priceDisplayMode(hidden), "hidden");
  assert.equal(changeTrialPriceDisplayMode(regularTrial, "hidden").weekly_only, false);
});

test("retained trial weekly pricing must use a supported Apple period", () => {
  const body = editorFixture().body;
  body.trial_enabled = false;
  body.skus[0].trial.price_mode = "weekly";
  const catalogs = catalogFixture();
  catalogs.subscription.products.find((product) => product.product_id === "paid.week").period = "ONE_DAY";
  catalogs.subscription.products.find((product) => product.product_id === "trial.week").period = "ONE_DAY";
  assert.ok(validateEditor(body, catalogs).some((issue) => issue.path === "skus.0.trial.price_mode"));
});

test("weekly-only pricing requires a weekly mode and supported period", () => {
  const body = editorFixture().body;
  body.skus[0].weekly_only = true;
  assert.ok(validateEditor(body, catalogFixture()).some((issue) => issue.path === "skus.0.price_mode"));
  body.skus[0].price_mode = "weekly";
  body.skus[0].trial.weekly_only = true;
  assert.deepEqual(validateEditor(body, catalogFixture()), []);
  body.skus[0].trial.price_mode = "actual";
  assert.ok(validateEditor(body, catalogFixture()).some((issue) => issue.path === "skus.0.trial.price_mode"));
  body.skus[0].trial.price_mode = "weekly";
  const catalogs = catalogFixture();
  catalogs.subscription.products.find((product) => product.product_id === "paid.week").period = "ONE_DAY";
  catalogs.subscription.products.find((product) => product.product_id === "trial.week").period = "ONE_DAY";
  assert.ok(validateEditor(body, catalogs).some((issue) => issue.path === "skus.0.price_mode"));
  assert.ok(validateEditor(body, catalogs).some((issue) => issue.path === "skus.0.trial.price_mode"));
});

test("price modes, default count and safe delays prevent invalid writes without a 30-second cap", () => {
  const body = editorFixture().body;
  body.close_delay_seconds = 3600;
  assert.deepEqual(validateEditor(body, catalogFixture()), []);
  body.skus[1].price_mode = "weekly";
  body.close_delay_seconds = 1.5;
  body.skus[1].is_default = true;
  const paths = validateEditor(body, catalogFixture()).map((i) => i.path);
  assert.ok(paths.includes("skus.1.price_mode")); assert.ok(paths.includes("close_delay_seconds")); assert.ok(paths.includes("skus"));
});
