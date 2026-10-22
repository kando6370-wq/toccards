import { emptyCopy, newEditor } from "../src/subscription-config/model.ts";

export const CONFIG_ID = "00000000000000000000000001";
export const REQUEST_ID = "11111111-1111-4111-8111-111111111111";
export function editorFixture() {
  const editor = newEditor("weekly-card");
  editor.body.name = "订阅页标准配置";
  editor.body.page_type = "page";
  editor.body.trial_enabled = true;
  editor.body.trial_toggle_text = "Enable Free Trial";
  editor.body.skus[0] = { ...editor.body.skus[0], ...emptyCopy("Weekly"), product_id: "paid.week", is_default: true,
    trial: { ...emptyCopy("Weekly Trial"), product_id: "trial.week", cta: "START FREE TRIAL" } };
  editor.body.skus.push({ ...editor.body.skus[0], ...emptyCopy("Lifetime"), key: "lifetime-card", product_id: "lifetime",
    product_type: "non_consumable", is_default: false, trial: null });
  return editor;
}
export function catalogFixture() {
  const product = (id, trial = false, level = 1, period = "ONE_WEEK") => ({
    product_id: id, reference_name: id, product_type: "subscription", subscription_group_id: "group", period, group_level: level,
    has_free_trial: trial, state: "APPROVED", admission: { admitted: true, reasons: [] },
  });
  return {
    subscription: { status: "loaded", products: [product("paid.week"), product("trial.week", true), product("paid.year", false, 1, "ONE_YEAR"), product("trial.year", true, 1, "ONE_YEAR"), product("trial.other", true, 2), product("independent.trial", true)] },
    non_consumable: { status: "loaded", products: [{ ...product("lifetime"), product_type: "non_consumable", subscription_group_id: null, period: null, group_level: null }] },
  };
}
export function operationFixture() {
  const editor = editorFixture();
  return { version: 1, kind: "create", path: "/subscription-configs", method: "POST",
    body: { request_id: REQUEST_ID, config: structuredClone(editor.body) }, editor, baseline: JSON.stringify(editor.body) };
}
export function memoryStorage() {
  const values = new Map();
  return { values, getItem: (key) => values.get(key) ?? null, setItem: (key, value) => values.set(key, value), removeItem: (key) => values.delete(key) };
}
