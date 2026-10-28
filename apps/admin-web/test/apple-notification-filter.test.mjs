import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import ts from "typescript";

const source = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const file = ts.createSourceFile("App.tsx", source, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TSX);
const functionSource = (name) => {
  const node = file.statements.find((statement) => ts.isFunctionDeclaration(statement) && statement.name?.text === name);
  assert.ok(node, `${name} must exist`);
  return node.getText(file);
};
const compiled = ts.transpileModule(`${functionSource("queryPath")}\n${functionSource("AppleNotificationsPage")}`, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
}).outputText;

function notificationPageHarness() {
  const state = [];
  let stateIndex = 0;
  let listPath = "";
  let optionPath = "";
  let optionError = null;
  const reloads = { list: 0, options: 0 };
  const component = (name) => name;
  const deps = {
    DEFAULT_BILLING_ENVIRONMENT: "Sandbox",
    billingEnvironmentOptions: [{ value: "Production", label: "正式" }, { value: "Sandbox", label: "测试" }],
    useState(initial) {
      const index = stateIndex++;
      if (!(index in state)) state[index] = initial;
      return [state[index], (next) => { state[index] = typeof next === "function" ? next(state[index]) : next; }];
    },
    useRef: (initial) => ({ current: initial }),
    useMemo: (make) => make(),
    useEffect: () => {},
    useAdminData(path) {
      if (path === "/apple-notifications/options") {
        optionPath = path;
        return {
          data: { items: [{ notification_type: "DID_RENEW", subtype: null }], skus: ["CardAi.monthly", "CardAi.yearly"] },
          loading: false, error: optionError, reload: () => { reloads.options += 1; },
        };
      }
      listPath = path;
      return {
        data: { items: [{ id: "1", sku: "CardAi.yearly" }], total: 41, page_size: 20 },
        loading: false, error: null, reload: () => { reloads.list += 1; },
      };
    },
    rangeSummaryPage: () => "",
    appleNotificationStatusName: () => "",
    billingEnvironmentLabel: (value) => value,
    billingEnvironmentDetailLabel: (value) => value,
    formatUtcTime: (value) => value,
    notificationFailureLabel: () => "",
    prettyJson: (value) => value,
    adminRequest: () => { throw new Error("Notification detail should not load during filter test"); },
    message: { success() {}, error() {} },
    PagePanel: component("PagePanel"), ScanFilterField: component("ScanFilterField"),
    Alert: component("Alert"), Button: component("Button"), DatePicker: { RangePicker: component("RangePicker") },
    Drawer: component("Drawer"), DetailSection: component("DetailSection"), InfoGrid: component("InfoGrid"),
    Input: component("Input"), Pagination: component("Pagination"), Select: component("Select"),
    Space: component("Space"), Spin: component("Spin"), Table: component("Table"),
    Tag: component("Tag"), Text: component("Text"), Title: component("Title"),
  };
  const AppleNotificationsPage = new Function("require", "exports", "deps", `const { ${Object.keys(deps).join(", ")} } = deps;\n${compiled}\nreturn AppleNotificationsPage;`)(
    (id) => {
      if (id === "react/jsx-runtime") return { Fragment: "Fragment", jsx: (type, props) => ({ type, props }), jsxs: (type, props) => ({ type, props }) };
      throw new Error(`Unexpected dependency: ${id}`);
    }, {}, deps);
  return {
    render() { stateIndex = 0; return AppleNotificationsPage({ session: { accessToken: "test-only" } }); },
    get path() { return new URL(listPath, "http://localhost"); },
    get optionPath() { return optionPath; },
    get reloads() { return { ...reloads }; },
    setOptionError(error) { optionError = error; },
  };
}

function find(tree, type, predicate = () => true) {
  if (Array.isArray(tree)) return tree.map((item) => find(item, type, predicate)).find(Boolean);
  if (!tree || typeof tree !== "object") return undefined;
  if (tree.type === type && predicate(tree.props)) return tree;
  return find(tree.props?.children, type, predicate);
}

test("Apple notification SKU choices can filter records outside the current page without losing other filters", () => {
  const harness = notificationPageHarness();
  let view = harness.render();
  const field = (label) => find(view, "ScanFilterField", (props) => props.label === label);
  const sku = () => find(field("SKU"), "Select");
  const uid = () => find(field("UID"), "Input");
  const button = (label) => find(view, "Button", (props) => props.children === label);

  assert.equal(harness.optionPath, "/apple-notifications/options", "SKU choices must be fetched separately from the paged list");
  assert.deepEqual(sku().props.options, [
    { value: "CardAi.monthly", label: "CardAi.monthly" },
    { value: "CardAi.yearly", label: "CardAi.yearly" },
  ]);
  assert.equal(harness.path.searchParams.has("sku"), false);

  sku().props.onChange("CardAi.monthly");
  view = harness.render();
  uid().props.onChange({ target: { value: " user-17 " } });
  view = harness.render();
  assert.equal(harness.path.searchParams.has("sku"), false, "Selecting a draft SKU must wait for Query");
  button("查询").props.onClick();
  view = harness.render();
  assert.equal(harness.path.searchParams.get("sku"), "CardAi.monthly");
  assert.equal(harness.path.searchParams.get("uid"), "user-17");
  assert.equal(harness.path.searchParams.get("page"), "1");
  assert.deepEqual(sku().props.options.map((option) => option.value), ["CardAi.monthly", "CardAi.yearly"], "Choices must remain available when SKU is filtered");

  find(view, "Pagination").props.onChange(2);
  view = harness.render();
  assert.equal(harness.path.searchParams.get("page"), "2");
  assert.equal(harness.path.searchParams.get("sku"), "CardAi.monthly");
  button("刷新").props.onClick();
  view = harness.render();
  assert.deepEqual(harness.reloads, { list: 1, options: 1 });
  assert.equal(harness.path.searchParams.get("sku"), "CardAi.monthly");
  assert.equal(harness.path.searchParams.get("page"), "2");

  sku().props.onChange(undefined);
  view = harness.render();
  button("查询").props.onClick();
  view = harness.render();
  assert.equal(harness.path.searchParams.has("sku"), false);
  assert.equal(harness.path.searchParams.get("uid"), "user-17");
  assert.equal(harness.path.searchParams.get("page"), "1");

  sku().props.onChange("CardAi.yearly");
  view = harness.render();
  button("查询").props.onClick();
  view = harness.render();
  button("重置").props.onClick();
  view = harness.render();
  assert.equal(harness.path.searchParams.has("sku"), false);
  assert.equal(harness.path.searchParams.has("uid"), false);
  assert.equal(harness.path.searchParams.get("environment"), "Sandbox");
  assert.equal(sku().props.value, undefined);

  harness.setOptionError("network failure");
  view = harness.render();
  assert.equal(view.props.error, "筛选选项加载失败，请点击刷新重试");
  button("刷新").props.onClick();
  assert.deepEqual(harness.reloads, { list: 2, options: 2 });
});
