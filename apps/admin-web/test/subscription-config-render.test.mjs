import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import ts from "typescript";
import { createRequire } from "node:module";
import * as model from "../src/subscription-config/model.ts";
import { editorFixture } from "./subscription-fixtures.mjs";

const require = createRequire(import.meta.url);
const React = require("react");
const { renderToStaticMarkup } = require("react-dom/server");
const source = await readFile(new URL("../src/subscription-config/SubscriptionConfigPage.tsx", import.meta.url), "utf8");
const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
const module = { exports: {} };
let initialEditor = null;
const dependencies = {
  "../request-id": { createRequestId: () => "11111111-1111-4111-8111-111111111111" },
  "./model": model,
  "./mutation": { SubscriptionMutation: class { constructor() { this.state = { phase: "idle", pending: initialEditor ? { editor: initialEditor, baseline: JSON.stringify(initialEditor.body) } : null, result: null, warning: null }; this.blocked = false; } } },
};
new Function("require", "module", "exports", compiled)((id) => id.endsWith(".css") ? {} : dependencies[id] ?? require(id), module, module.exports);

test("the real subscription component renders its list entry inside the existing Admin UI", () => {
  const html = renderToStaticMarkup(React.createElement(module.exports.default, {
    request: async () => { throw new Error("Server rendering must not call the API"); }, accountKey: "local-test", registerLeaveGuard: () => {},
  }));
  for (const text of ["订阅页配置", "新增配置", "配置名称", "页面类型", "商品信息", "试用配置", "生效状态", "更新时间"]) assert.ok(html.includes(text), text);
  assert.match(html, /subscription-config-page/);
  assert.doesNotMatch(html, /com\.tcg\.premium/);
});

test("the editor blocks adding at three cards and permits adding after removal without hiding retained cards", () => {
  const renderEditor = (editor) => {
    initialEditor = editor;
    try {
      return renderToStaticMarkup(React.createElement(module.exports.default, {
        request: async () => { throw new Error("Server rendering must not call the API"); }, accountKey: "local-test", registerLeaveGuard: () => {},
      }));
    } finally { initialEditor = null; }
  };
  const addButton = (html) => {
    const button = html.match(/<button\b[^>]*>[\s\S]*?<\/button>/g)?.find((value) => value.includes("增加 SKU"));
    assert.ok(button);
    return button;
  };
  for (const pageType of ["page", "modal"]) {
    const editor = editorFixture(); editor.body.page_type = pageType;
    assert.doesNotMatch(addButton(renderEditor(editor)), /disabled/);
    editor.body.skus.push({ ...editor.body.skus[0], key: "independent-card", product_id: "independent.trial", is_default: false, trial: null });
    const full = renderEditor(editor);
    assert.match(addButton(full), /disabled=""/);
    assert.match(full, /最多 3 个/);
    assert.match(full, /关联试用 SKU 不占名额/);
    editor.body = model.removeSku(editor.body, "independent-card");
    assert.doesNotMatch(addButton(renderEditor(editor)), /disabled/);
    editor.body.skus.push(...["third", "fourth"].map((id) => ({ ...editor.body.skus[1], key: id, product_id: id })));
    const legacy = renderEditor(editor);
    assert.match(addButton(legacy), /disabled=""/);
    assert.equal((legacy.match(/class="subscription-sku-card"/g) ?? []).length, 4);
  }
});

test("base and linked trial show the hidden-price choice, with trial pricing before its name", () => {
  const editor = editorFixture();
  editor.body.skus[0].hide_price = true;
  initialEditor = editor;
  let html;
  try {
    html = renderToStaticMarkup(React.createElement(module.exports.default, {
      request: async () => { throw new Error("Server rendering must not call the API"); }, accountKey: "local-test", registerLeaveGuard: () => {},
    }));
  } finally { initialEditor = null; }
  assert.match(html, /SKU 1 价格展示方式/);
  assert.match(html, /SKU 1 试用价格展示方式/);
  assert.ok(html.indexOf("SKU 1 试用价格展示方式") < html.indexOf("试用商品展示名称"));
  assert.ok((html.match(/不展示/g) ?? []).length >= 2);
});

test("base and linked trial show the weekly-only selection", () => {
  const editor = editorFixture();
  editor.body.skus[0].price_mode = "weekly";
  editor.body.skus[0].weekly_only = true;
  editor.body.skus[0].trial.price_mode = "weekly";
  editor.body.skus[0].trial.weekly_only = true;
  initialEditor = editor;
  let html;
  try {
    html = renderToStaticMarkup(React.createElement(module.exports.default, {
      request: async () => { throw new Error("Server rendering must not call the API"); }, accountKey: "local-test", registerLeaveGuard: () => {},
    }));
  } finally { initialEditor = null; }
  assert.ok((html.match(/只展示周均价/g) ?? []).length >= 2);
});

test("the top-level menu uses real subscription APIs and guarded navigation, not an embedded prototype", () => {
  assert.match(app, /key: "subscription-configs", label: group\.title/);
  assert.match(app, /<SubscriptionConfigPage request=\{subscriptionRequest\}/);
  assert.match(app, /leaveGuard\.current\(\)/);
  assert.match(app, /response\.status, payload\.error\.fields/);
  assert.doesNotMatch(source, /<iframe|com\.tcg\.premium|prototype\.subscription/);
});
