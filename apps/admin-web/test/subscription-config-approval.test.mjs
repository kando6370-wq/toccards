import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import ts from "typescript";
import * as model from "../src/subscription-config/model.ts";
import { catalogFixture, editorFixture } from "./subscription-fixtures.mjs";

const require = createRequire(import.meta.url);
const React = require("react");
const source = await readFile(new URL("../src/subscription-config/SubscriptionConfigPage.tsx", import.meta.url), "utf8");
const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
const text = (node) => Array.isArray(node) ? node.map(text).join("") : React.isValidElement(node) ? text(node.props.children) : typeof node === "string" ? node : "";
function nodes(node) {
  if (Array.isArray(node)) return node.flatMap(nodes);
  return React.isValidElement(node) ? [node, ...nodes(node.props.children)] : [];
}

// Exercise the real page's handlers with controlled hooks; effects and AntD rendering are outside this component test.
function approvalPage(events = {}) {
  const catalogs = catalogFixture();
  for (const catalog of Object.values(catalogs)) {
    Object.assign(catalog, { scope: "development:beta.app", environment: "development", can_approve: true });
    for (const product of catalog.products) product.admission.singular_event_name = events[product.product_id] ?? null;
  }
  const states = [];
  const submissions = [];
  let cursor = 0;
  const Modal = Object.assign(() => null, { useModal: () => [{ confirm: () => {} }, null] });
  const controls = Object.fromEntries(["Alert", "Button", "Checkbox", "Input", "InputNumber", "Radio", "Select", "Space", "Spin", "Switch", "Table", "Tag", "Tooltip"].map((name) => [name, name]));
  const dependencies = {
    antd: { ...controls, Radio: { Group: "RadioGroup" }, Modal, Form: Object.assign(() => null, { Item: "FormItem" }), Typography: { Text: "Text", Title: "Title" }, message: {} },
    react: { ...React, useState: (initial) => {
      const index = cursor++;
      if (!(index in states)) states[index] = typeof initial === "function" ? initial() : initial;
      return [states[index], (next) => { states[index] = typeof next === "function" ? next(states[index]) : next; }];
    }, useMemo: (factory) => factory(), useCallback: (callback) => callback, useRef: (current) => ({ current }), useEffect: () => {} },
    "../request-id": { createRequestId: () => "11111111-1111-4111-8111-111111111111" },
    "./model": model,
    "./mutation": { SubscriptionMutation: class {
      constructor() { this.state = { phase: "idle", pending: { editor: editorFixture(), baseline: "" }, result: null, warning: null }; this.blocked = false; }
      async start(operation) { submissions.push(operation); }
    } },
  };
  const module = { exports: {} };
  new Function("require", "module", "exports", compiled)((id) => id.endsWith(".css") ? {} : dependencies[id] ?? require(id), module, module.exports);
  let tree;
  const render = () => {
    cursor = 0;
    tree = module.exports.default({ accountKey: "local-test", registerLeaveGuard: () => {}, request: async (path) => {
      assert.match(path, /^\/subscription-products\?type=/);
      return catalogs[path.split("=")[1]];
    } });
  };
  const find = (predicate, within = tree) => {
    const node = nodes(within).find(predicate);
    assert.ok(node, "Expected control in the real subscription page");
    return node;
  };
  const button = (label) => find((node) => node.type === "Button" && text(node) === label);
  const dialog = () => find((node) => node.type === Modal);
  const input = () => find((node) => node.type === "Input" && node.props["aria-label"] === "准入收入事件名");
  render();
  return { render, find, button, dialog, input, submissions,
    async loadCatalogs() {
      for (const type of ["subscription", "non_consumable"]) {
        find((node) => node.type.name === "CatalogFeedback" && node.props.type === type).props.reload();
        await Promise.resolve();
        render();
      }
    },
    acknowledge() { find((node) => node.type === "Checkbox", dialog()).props.onChange({ target: { checked: true } }); render(); },
  };
}

for (const [product, label, event] of [["paid.week", "审核商品准入", "weekly_cardtest"], ["trial.week", "审核试用商品准入", "card_weekly_trialtest"]]) {
  test(`reviewing ${product} recalls its saved revenue mapping and still requires acknowledgement`, async () => {
    const page = approvalPage({ [product]: event });
    await page.loadCatalogs();
    page.button(label).props.onClick(); page.render();
    assert.equal(page.input().props.value, event);
    assert.equal(page.dialog().props.okButtonProps.disabled, true);
    page.acknowledge();
    await page.dialog().props.onOk();
    assert.equal(page.submissions[0].body.singular_event_name, event);
  });
}

test("an unconfigured trial cannot inherit another product's saved or unsaved event", async () => {
  const page = approvalPage({ "paid.week": "weekly_cardtest" });
  await page.loadCatalogs();
  page.button("审核商品准入").props.onClick(); page.render();
  page.input().props.onChange({ target: { value: "unsaved_weekly" } }); page.render();
  page.acknowledge();
  page.dialog().props.onCancel(); page.render();
  page.button("审核试用商品准入").props.onClick(); page.render();
  assert.equal(page.input().props.value, "");
  assert.equal(page.dialog().props.okButtonProps.disabled, true);
});

test("Singular's 32-character boundary is enforced both on the input and the submit handler", async () => {
  const page = approvalPage();
  await page.loadCatalogs();
  page.button("审核商品准入").props.onClick(); page.render();
  assert.equal(page.input().props.maxLength, 32);
  assert.equal(page.input().props.showCount, true);
  page.acknowledge();
  for (const invalid of ["a".repeat(33), "事件", "1weekly", "weekly event", "weekly\n"]) {
    page.input().props.onChange({ target: { value: invalid } }); page.render();
    assert.equal(page.dialog().props.okButtonProps.disabled, true);
    await page.dialog().props.onOk();
    assert.equal(page.submissions.length, 0);
  }
  const valid = "a".repeat(32);
  page.input().props.onChange({ target: { value: valid } }); page.render();
  assert.equal(page.dialog().props.okButtonProps.disabled, false);
  await page.dialog().props.onOk();
  assert.equal(page.submissions[0].body.singular_event_name, valid);
});

test("legacy long mappings remain visible in full but require correction before reapproval", async () => {
  const legacy = "legacy_" + "x".repeat(40);
  const page = approvalPage({ "paid.week": legacy });
  await page.loadCatalogs();
  page.button("审核商品准入").props.onClick(); page.render();
  assert.equal(page.input().props.value, legacy);
  page.acknowledge();
  assert.equal(page.dialog().props.okButtonProps.disabled, true);
  await page.dialog().props.onOk();
  assert.equal(page.submissions.length, 0);
});
