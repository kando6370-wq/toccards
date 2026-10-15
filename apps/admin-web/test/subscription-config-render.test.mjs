import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import ts from "typescript";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const React = require("react");
const { renderToStaticMarkup } = require("react-dom/server");
const source = await readFile(new URL("../src/subscription-config/SubscriptionConfigPage.tsx", import.meta.url), "utf8");
const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
const module = { exports: {} };
const dependencies = {
  "../request-id": { createRequestId: () => "11111111-1111-4111-8111-111111111111" },
  "./model": { PAGE_LABELS: { page: "订阅页", modal: "订阅大弹窗" }, productMap: () => new Map(), admissionMessage: () => "", subscriptionErrorMessage: (e) => e?.message ?? "", validateEditor: () => [] },
  "./mutation": { SubscriptionMutation: class { constructor() { this.state = { phase: "idle", pending: null, result: null, warning: null }; this.blocked = false; } } },
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

test("the top-level menu uses real subscription APIs and guarded navigation, not an embedded prototype", () => {
  assert.match(app, /key: "subscription-configs", label: group\.title/);
  assert.match(app, /<SubscriptionConfigPage request=\{subscriptionRequest\}/);
  assert.match(app, /leaveGuard\.current\(\)/);
  assert.match(app, /response\.status, payload\.error\.fields/);
  assert.doesNotMatch(source, /<iframe|com\.tcg\.premium|prototype\.subscription/);
});
