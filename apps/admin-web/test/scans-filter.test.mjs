import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import ts from "typescript";

const source = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const file = ts.createSourceFile("App.tsx", source, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TSX);
const page = file.statements.find((node) => ts.isFunctionDeclaration(node) && node.name?.text === "ScansPage");
const optionNames = ["scanCardTypeOptions", "scanPlatformOptions", "environmentOptions", "recognitionOptions", "confirmationOptions"];
const options = optionNames.map((name) => file.statements.find((node) =>
  ts.isVariableStatement(node) && node.declarationList.declarations.some((decl) => decl.name.getText(file) === name)));
assert.ok(page && options.every(Boolean), "Scan page and filter choices must exist");

const compiled = ts.transpileModule(`${options.map((node) => node.getText(file)).join("\n")}\n${page.getText(file)}`, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
}).outputText;

function scanPageHarness() {
  const state = [];
  let stateIndex = 0;
  let requestedPath = "";
  const component = (name) => name;
  const deps = {
    useState(initial) {
      const index = stateIndex++;
      if (!(index in state)) state[index] = initial;
      return [state[index], (next) => { state[index] = typeof next === "function" ? next(state[index]) : next; }];
    },
    useMemo: (make) => make(),
    useAdminData(path) {
      requestedPath = path;
      return { data: { items: [], total: 31, page_size: 10 }, loading: false, error: null, reload: () => {} };
    },
    adminRequest: () => { throw new Error("Detail should not load during filter test"); },
    rangeSummaryPage: () => "",
    formatTime: (value) => value,
    renderRecognitionStatus: (value) => value,
    AuthenticatedScanImage: component("AuthenticatedScanImage"),
    ScanDetailDrawer: component("ScanDetailDrawer"),
    ScanFilterField: component("ScanFilterField"),
    Alert: component("Alert"), Button: component("Button"), DatePicker: { RangePicker: component("RangePicker") },
    Input: component("Input"), Pagination: component("Pagination"), Select: component("Select"),
    Table: component("Table"), Text: component("Text"),
  };
  const ScansPage = new Function("require", "exports", "deps", `const { ${Object.keys(deps).join(", ")} } = deps;\n${compiled}\nreturn ScansPage;`)(
    (id) => { if (id === "react/jsx-runtime") return requireJsxRuntime(); throw new Error(`Unexpected dependency: ${id}`); }, {}, deps);
  return {
    render() { stateIndex = 0; return ScansPage({ session: { accessToken: "test-only" } }); },
    get path() { return new URL(requestedPath, "http://localhost"); },
  };
}

function requireJsxRuntime() {
  return { jsx: (type, props) => ({ type, props }), jsxs: (type, props) => ({ type, props }) };
}

function find(tree, type, predicate = () => true) {
  if (Array.isArray(tree)) return tree.map((item) => find(item, type, predicate)).find(Boolean);
  if (!tree || typeof tree !== "object") return undefined;
  if (tree.type === type && predicate(tree.props)) return tree;
  return find(tree.props?.children, type, predicate);
}

test("scan card type search preserves draft, pagination, other filters and reset", () => {
  const harness = scanPageHarness();
  let view = harness.render();
  const typeField = () => find(view, "ScanFilterField", (props) => props.label === "卡牌类型");
  const typeSelect = () => find(typeField(), "Select");
  const button = (label) => find(view, "Button", (props) => props.children === label);
  const uid = () => find(view, "Input", (props) => props.placeholder === "输入用户 ID");

  assert.deepEqual(typeSelect().props.options, [
    { value: "0", label: "TCG" }, { value: "1", label: "SPORTS" },
  ]);
  assert.equal(harness.path.searchParams.has("card_type"), false);

  typeSelect().props.onChange("0");
  uid().props.onChange({ target: { value: "user-17" } });
  view = harness.render();
  assert.equal(harness.path.searchParams.has("card_type"), false, "Draft must wait for Query");
  button("查询").props.onClick();
  view = harness.render();
  assert.equal(harness.path.searchParams.get("card_type"), "0", "TCG must survive query encoding");
  assert.equal(harness.path.searchParams.get("uid"), "user-17");
  assert.equal(harness.path.searchParams.get("page"), "1");

  find(view, "Pagination").props.onChange(3);
  view = harness.render();
  assert.equal(harness.path.searchParams.get("page"), "3");
  assert.equal(harness.path.searchParams.get("card_type"), "0");

  typeSelect().props.onChange("1");
  view = harness.render();
  button("查询").props.onClick();
  view = harness.render();
  assert.equal(harness.path.searchParams.get("card_type"), "1");
  assert.equal(harness.path.searchParams.get("uid"), "user-17");
  assert.equal(harness.path.searchParams.get("page"), "1", "New search must reset pagination");

  typeSelect().props.onChange(undefined);
  view = harness.render();
  button("查询").props.onClick();
  view = harness.render();
  assert.equal(harness.path.searchParams.has("card_type"), false);
  assert.equal(harness.path.searchParams.get("uid"), "user-17");

  typeSelect().props.onChange("1");
  view = harness.render();
  button("查询").props.onClick();
  view = harness.render();
  find(view, "Pagination").props.onChange(3);
  view = harness.render();
  assert.equal(harness.path.searchParams.get("card_type"), "1");
  assert.equal(harness.path.searchParams.get("page"), "3");

  button("重置").props.onClick();
  harness.render();
  assert.equal(harness.path.searchParams.has("card_type"), false);
  assert.equal(harness.path.searchParams.has("uid"), false);
  assert.equal(harness.path.searchParams.get("page"), "1");
});
