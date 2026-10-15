import assert from "node:assert/strict";
import test from "node:test";
import { availableProducts, changeProduct, editorFromRecord, moveSku, newEditor, productMap, removeSku, toDisplayConfig, unlinkTrial, validateEditor } from "../src/subscription-config/model.ts";
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
  const sku = editorFixture().body.skus[0]; sku.price_mode = "weekly";
  const changed = changeProduct(sku, "", productMap(catalogFixture()), "non_consumable");
  assert.equal(changed.product_id, ""); assert.equal(changed.trial.product_id, "");
  assert.equal(changed.price_mode, "actual"); assert.equal(changed.name, "Weekly");
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
