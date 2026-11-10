import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import ts from "typescript";

const source = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const file = ts.createSourceFile("App.tsx", source, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TSX);

function compileFunction(name) {
  const node = file.statements.find((statement) => ts.isFunctionDeclaration(statement) && statement.name?.text === name);
  assert.ok(node, `${name} must exist`);
  return ts.transpileModule(node.getText(file), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
  }).outputText;
}

function createHooks() {
  const state = [];
  const refs = [];
  const effects = [];
  let stateIndex = 0;
  let refIndex = 0;
  let effectIndex = 0;
  return {
    reset() { stateIndex = 0; refIndex = 0; effectIndex = 0; },
    useState(initial) {
      const index = stateIndex++;
      if (!(index in state)) state[index] = typeof initial === "function" ? initial() : initial;
      return [state[index], (next) => { state[index] = typeof next === "function" ? next(state[index]) : next; }];
    },
    useRef(initial) {
      const index = refIndex++;
      if (!(index in refs)) refs[index] = { current: initial };
      return refs[index];
    },
    useEffect(effect, deps) {
      const index = effectIndex++;
      const previous = effects[index];
      if (!previous || deps.some((value, dependencyIndex) => value !== previous.deps[dependencyIndex])) {
        previous?.cleanup?.();
        effects[index] = { deps, cleanup: effect() };
      }
    },
  };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

const flush = () => new Promise((resolve) => setImmediate(resolve));

function find(tree, type, predicate = () => true) {
  if (Array.isArray(tree)) return tree.map((item) => find(item, type, predicate)).find(Boolean);
  if (!tree || typeof tree !== "object") return undefined;
  if (tree.type === type && predicate(tree.props)) return tree;
  return find(tree.props?.children, type, predicate);
}

function createHarness() {
  const hooks = createHooks();
  const component = (name) => name;
  const form = {
    values: null,
    submit() {},
    setFieldsValue(values) { this.values = { ...values }; },
  };
  const Form = () => {};
  Form.useForm = () => [form];
  Form.Item = component("FormItem");
  const messages = [];
  const requests = [];
  const pending = [];
  let data = {
    environment: "development",
    items: [
      {
        platform: "iOS", min_supported_version: "1.0.0", recommended_version: "1.0.1",
        force_update: false, store_url: "https://apps.apple.com/app/id1", status: "enabled", updated_at: "2026-11-10T01:00:00Z",
      },
      {
        platform: "Google", min_supported_version: "2.0.0", recommended_version: "2.0.1",
        force_update: false, store_url: "https://play.google.com/store/apps/details?id=test", status: "disabled", updated_at: "2026-11-10T02:00:00Z",
      },
    ],
  };
  const jsx = { jsx: (type, props) => ({ type, props }), jsxs: (type, props) => ({ type, props }) };
  const dependencies = {
    ...hooks,
    Form,
    useAdminData() {
      return {
        data, loading: false, error: null, reload() {},
        updateData(updater) { data = typeof updater === "function" ? updater(data) : updater; },
      };
    },
    adminRequest(path, init) {
      const request = deferred();
      requests.push({ path, init });
      pending.push(request);
      return request.promise;
    },
    mutate(session, path, init) {
      return dependencies.adminRequest(path, { ...init, token: session.accessToken });
    },
    message: {
      error(value) { messages.push({ type: "error", value }); },
      success(value) { messages.push({ type: "success", value }); },
    },
    errorMessage: (error) => error.message,
    PagePanel: component("PagePanel"), Alert: component("Alert"), Text: component("Text"),
    Button: component("Button"), Space: component("Space"), Table: component("Table"), Drawer: component("Drawer"),
    Input: component("Input"), Select: component("Select"), Switch: component("Switch"),
    appVersionPlatformLabel: (platform) => platform === "Google" ? "Android（Google Play）" : platform,
    renderAppVersionStatus: (value) => value,
    formatDate: (value) => value,
  };
  const AppVersionsPage = new Function("require", "exports", ...Object.keys(dependencies), `${compileFunction("AppVersionsPage")} return AppVersionsPage;`)(
    (id) => { if (id === "react/jsx-runtime") return jsx; throw new Error(id); }, {}, ...Object.values(dependencies),
  );
  const render = () => { hooks.reset(); return AppVersionsPage({ session: { accessToken: "test-token" } }); };
  return { render, form, Form, messages, requests, pending, getData: () => data };
}

function table(view) {
  return find(view, "Table");
}

function rowActions(view, row) {
  return table(view).props.columns.at(-1).render(null, row).props.children;
}

test("version management removes unrelated sales and order tabs", () => {
  const tabs = find(createHarness().render(), "div", (props) => props.className === "top-tabs");
  assert.deepEqual([tabs.props.children].flat().map((child) => child.props.children), ["版本管理"]);
});

test("saving each platform updates the returned row without replacing the other platform", async () => {
  const harness = createHarness();
  let view = harness.render();
  const initialGoogle = harness.getData().items[1];
  rowActions(view, harness.getData().items[0])[0].props.onClick();
  view = harness.render();
  const iosValues = { ...harness.form.values, min_supported_version: "1.1.0", recommended_version: "1.2.0" };
  harness.form.values = iosValues;
  const first = find(view, harness.Form).props.onFinish(iosValues);
  assert.deepEqual(harness.requests[0], { path: "/app-versions/iOS", init: { method: "PATCH", body: iosValues, token: "test-token" } });
  const savedIos = { ...iosValues, platform: "iOS", updated_at: "2026-11-10T03:00:00Z" };
  harness.pending[0].resolve(savedIos);
  await first;
  assert.deepEqual(harness.getData().items, [savedIos, initialGoogle]);
  view = harness.render();
  assert.equal(find(view, "Drawer").props.open, false);

  rowActions(view, harness.getData().items[1])[0].props.onClick();
  view = harness.render();
  const googleValues = { ...harness.form.values, recommended_version: "2.1.0" };
  harness.form.values = googleValues;
  const googleSave = find(view, harness.Form).props.onFinish(googleValues);
  const savedGoogle = { ...googleValues, platform: "Google", updated_at: "2026-11-10T04:00:00Z" };
  harness.pending[1].resolve(savedGoogle);
  await googleSave;
  assert.deepEqual(harness.getData().items, [savedIos, savedGoogle]);
  assert.equal(harness.requests[1].path, "/app-versions/Google");
});

test("double save submits only the first version mutation while it is pending", async () => {
  const harness = createHarness();
  let view = harness.render();
  rowActions(view, harness.getData().items[0])[0].props.onClick();
  view = harness.render();
  const values = { ...harness.form.values, recommended_version: "1.2.0" };
  const first = find(view, harness.Form).props.onFinish(values);
  const duplicate = find(view, harness.Form).props.onFinish({ ...values, recommended_version: "9.9.9" });
  assert.equal(harness.requests.length, 1);
  assert.equal(harness.requests[0].init.body.recommended_version, "1.2.0");
  harness.pending[0].resolve({ ...values, updated_at: "2026-11-10T04:30:00Z" });
  await Promise.all([first, duplicate]);
});

test("a failed save keeps the editor open, reports the error, and permits an exact retry", async () => {
  const harness = createHarness();
  let view = harness.render();
  rowActions(view, harness.getData().items[0])[0].props.onClick();
  view = harness.render();
  const values = { ...harness.form.values, recommended_version: "1.3.0" };
  harness.form.values = values;
  const failedSave = find(view, harness.Form).props.onFinish(values);
  harness.pending[0].reject(new Error("保存失败，请重试"));
  await failedSave;
  view = harness.render();
  assert.equal(find(view, "Drawer").props.open, true);
  assert.deepEqual(harness.form.values, values);
  assert.deepEqual(harness.messages, [{ type: "error", value: "保存失败，请重试" }]);

  const retry = find(view, harness.Form).props.onFinish(values);
  const saved = { ...values, platform: "iOS", updated_at: "2026-11-10T05:00:00Z" };
  harness.pending[1].resolve(saved);
  await retry;
  assert.equal(harness.requests.length, 2);
  assert.deepEqual(harness.requests[1], harness.requests[0]);
  assert.deepEqual(harness.getData().items[0], saved);
});

test("the editor cannot be replaced or closed while a version mutation is pending", async () => {
  const harness = createHarness();
  let view = harness.render();
  rowActions(view, harness.getData().items[0])[0].props.onClick();
  view = harness.render();
  const save = find(view, harness.Form).props.onFinish({ ...harness.form.values, recommended_version: "1.4.0" });
  view = harness.render();
  const drawer = find(view, "Drawer");
  const actions = rowActions(view, harness.getData().items[1]);
  assert.equal(find(view, harness.Form).props.disabled, true);
  assert.equal(find(view, "Button", (props) => props.children === "保存").props.loading, true);
  assert.equal(actions[0].props.disabled, true);
  assert.equal(actions[1].props.disabled, true);
  assert.equal(find(view, "Button", (props) => props.children === "取消").props.disabled, true);
  assert.equal(drawer.props.extra.props.disabled, true);
  drawer.props.onClose();
  view = harness.render();
  assert.equal(find(view, "Drawer").props.open, true);
  assert.equal(harness.form.values.platform, "iOS");

  harness.pending[0].resolve({ ...harness.form.values, recommended_version: "1.4.0", updated_at: "2026-11-10T06:00:00Z" });
  await save;
});

test("status toggles use the returned row, ignore double clicks, and keep the old row after failure", async () => {
  const harness = createHarness();
  let view = harness.render();
  const originalIos = harness.getData().items[0];
  const originalGoogle = harness.getData().items[1];
  const iosToggle = rowActions(view, originalIos)[1];
  iosToggle.props.onClick();
  iosToggle.props.onClick();
  assert.equal(harness.requests.length, 1);
  assert.deepEqual(harness.requests[0], {
    path: "/app-versions/iOS",
    init: {
      method: "PATCH",
      body: { ...originalIos, status: "disabled" },
      token: "test-token",
    },
  });
  const disabledIos = {
    ...originalIos,
    status: "disabled",
    recommended_version: "1.0.2",
    updated_at: "2026-11-10T07:00:00Z",
  };
  harness.pending[0].resolve(disabledIos);
  await flush();
  assert.deepEqual(harness.getData().items, [disabledIos, originalGoogle]);

  view = harness.render();
  rowActions(view, originalGoogle)[1].props.onClick();
  harness.pending[1].reject(new Error("启用失败"));
  await flush();
  assert.deepEqual(harness.getData().items, [disabledIos, originalGoogle]);
  assert.deepEqual(harness.messages.at(-1), { type: "error", value: "启用失败" });

  view = harness.render();
  rowActions(view, originalGoogle)[1].props.onClick();
  assert.equal(harness.requests.length, 3);
  const enabledGoogle = {
    ...originalGoogle,
    status: "enabled",
    store_url: "https://play.google.com/store/apps/details?id=cardai",
    updated_at: "2026-11-10T08:00:00Z",
  };
  harness.pending[2].resolve(enabledGoogle);
  await flush();
  assert.deepEqual(harness.getData().items, [disabledIos, enabledGoogle]);
});
