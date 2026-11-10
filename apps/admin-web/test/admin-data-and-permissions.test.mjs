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
  const effects = [];
  let stateIndex = 0;
  let effectIndex = 0;
  return {
    reset() { stateIndex = 0; effectIndex = 0; },
    useState(initial) {
      const index = stateIndex++;
      if (!(index in state)) state[index] = typeof initial === "function" ? initial() : initial;
      return [state[index], (next) => { state[index] = typeof next === "function" ? next(state[index]) : next; }];
    },
    useEffect(effect, deps) {
      const index = effectIndex++;
      const previous = effects[index];
      if (!previous || deps.some((value, i) => value !== previous.deps[i])) {
        previous?.cleanup?.();
        effects[index] = { deps, cleanup: effect() };
      }
    },
    useMemo: (make) => make(),
  };
}

const flush = () => new Promise((resolve) => setImmediate(resolve));

test("version management labels Google as Android without changing its PATCH platform", () => {
  const appVersionPlatformLabel = new Function(
    `${compileFunction("appVersionPlatformLabel")} return appVersionPlatformLabel;`,
  )();
  assert.equal(appVersionPlatformLabel("Google"), "Android（Google Play）");
  assert.equal(appVersionPlatformLabel("iOS"), "iOS");
  assert.match(source, /`\/app-versions\/\$\{editing\.platform\}`/);
  assert.match(source, /`\/app-versions\/\$\{row\.platform\}`/);
  assert.doesNotMatch(source, /\/app-versions\/Android/);
});

test("a failed filter change cannot show rows from the previous Admin query", async () => {
  const hooks = createHooks();
  const pending = new Map();
  const dependencies = {
    ...hooks,
    adminRequest(path, init) {
      return new Promise((resolve, reject) => pending.set(path, { resolve, reject, init }));
    },
    errorMessage: (error) => error.message,
  };
  const useAdminData = new Function(...Object.keys(dependencies), `${compileFunction("useAdminData")} return useAdminData;`)(...Object.values(dependencies));
  const session = { accessToken: "test-token" };
  const render = (path) => { hooks.reset(); return useAdminData(path, session); };

  render("/permissions?page=1");
  pending.get("/permissions?page=1").resolve({ items: [{ id: "old" }] });
  await flush();
  assert.deepEqual(render("/permissions?page=1").data.items.map((row) => row.id), ["old"]);

  render("/permissions?page=2");
  assert.equal(render("/permissions?page=2").data, null);
  assert.equal(pending.get("/permissions?page=1").init.signal?.aborted, true);
  pending.get("/permissions?page=2").reject(new Error("network failed"));
  await flush();
  const failed = render("/permissions?page=2");
  assert.equal(failed.data, null);
  assert.equal(failed.error, "network failed");

  render("/permissions?page=1");
  pending.get("/permissions?page=1").resolve({ items: [{ id: "fresh" }] });
  await flush();
  const current = render("/permissions?page=1");
  assert.deepEqual(current.data.items.map((row) => row.id), ["fresh"]);
  current.reload();
  render("/permissions?page=1");
  assert.deepEqual(render("/permissions?page=1").data.items.map((row) => row.id), ["fresh"]);
  const oldSignal = pending.get("/permissions?page=1").init.signal;
  session.accessToken = "next-token";
  assert.equal(render("/permissions?page=1").data, null);
  assert.equal(oldSignal.aborted, true);
});

test("permissions use server pagination, filters, and the existing role/status editor", async () => {
  const hooks = createHooks();
  const requested = [];
  const mutations = [];
  const component = (name) => name;
  const form = { submit() {}, resetFields() {}, setFieldsValue() {} };
  const Form = () => {};
  Form.useForm = () => [form];
  Form.Item = component("FormItem");
  const jsx = { jsx: (type, props) => ({ type, props }), jsxs: (type, props) => ({ type, props }) };
  const dependencies = {
    ...hooks,
    Form,
    useAdminData(path) {
      requested.push(path);
      return { data: { items: [{ id: "admin-101", email: "last@example.com", role: "operator", permission_status: "active" }], total: 101, page_size: 8 }, loading: false, error: null, reload() {} };
    },
    mutate(_session, path, init) { mutations.push({ path, init }); return Promise.resolve(); },
    PagePanel: component("PagePanel"), FilterBar: component("FilterBar"), DataPanel: component("DataPanel"),
    Title: component("Title"), Text: component("Text"), Input: component("Input"), Select: component("Select"),
    Button: component("Button"), Space: component("Space"), Table: component("Table"), Modal: component("Modal"),
    permissionStatusOptions: [{ value: "active", label: "启用" }, { value: "disabled", label: "停用" }],
    renderPermissionStatus: (value) => value, formatDate: (value) => value,
  };
  const PermissionsPage = new Function("require", "exports", ...Object.keys(dependencies), `${compileFunction("PermissionsPage")} return PermissionsPage;`)(
    (id) => { if (id === "react/jsx-runtime") return jsx; throw new Error(id); }, {}, ...Object.values(dependencies),
  );
  const render = (role = "super_admin") => { hooks.reset(); return PermissionsPage({ session: { accessToken: "test-token", role } }); };
  const find = (tree, type, predicate = () => true) => {
    if (Array.isArray(tree)) return tree.map((item) => find(item, type, predicate)).find(Boolean);
    if (!tree || typeof tree !== "object") return undefined;
    if (tree.type === type && predicate(tree.props)) return tree;
    return find(tree.props?.children, type, predicate);
  };
  let view = render();
  find(view, "Table").props.pagination.onChange(13);
  view = render();
  assert.equal(new URL(requested.at(-1), "http://localhost").searchParams.get("page"), "13");
  find(view, "Input", (props) => props.placeholder === "邮箱账号").props.onChange({ target: { value: "last" } });
  view = render();
  find(view, "Select", (props) => props.placeholder === "权限状态").props.onChange("disabled");
  view = render();
  find(view, "Button", (props) => props.children === "查询").props.onClick();
  view = render();
  const query = new URL(requested.at(-1), "http://localhost").searchParams;
  assert.equal(query.get("q"), "last");
  assert.equal(query.get("status"), "disabled");
  assert.equal(query.get("page"), "1");
  const actions = find(view, "Table").props.columns.at(-1).render(null, { id: "admin-101", email: "last@example.com", role: "operator", permission_status: "active" }).props.children;
  assert.equal(actions[0].props.disabled, false);
  actions[0].props.onClick();
  view = render();
  const editModal = find(view, "Modal", (props) => props.title === "编辑授权账号");
  assert.equal(editModal.props.open, true);
  await find(editModal, Form).props.onFinish({ role: "super_admin", status: "disabled" });
  assert.deepEqual(mutations, [{ path: "/permissions/admin-101", init: { method: "PATCH", body: { role: "super_admin", status: "disabled" } } }]);
  view = render();
  find(view, "Button", (props) => props.children === "重置").props.onClick();
  render();
  const resetQuery = new URL(requested.at(-1), "http://localhost").searchParams;
  assert.equal(resetQuery.has("q"), false);
  assert.equal(resetQuery.has("status"), false);
  const operatorView = render("operator");
  assert.equal(find(operatorView, "Button", (props) => props.children === "新增授权账号").props.disabled, true);
  const operatorActions = find(operatorView, "Table").props.columns.at(-1).render(null, { id: "admin-101", permission_status: "active" }).props.children;
  assert.equal(operatorActions[0].props.disabled, true);
  assert.equal(operatorActions[1].props.disabled, true);
});
