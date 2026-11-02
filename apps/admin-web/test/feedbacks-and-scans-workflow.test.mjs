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
const compile = (source) => ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
}).outputText;
const jsx = { jsx: (type, props) => ({ type, props }), jsxs: (type, props) => ({ type, props }) };
const component = (name) => name;

function mount(name, dependencies) {
  const state = [];
  const refs = [];
  const effects = [];
  let index = 0;
  let refIndex = 0;
  const deps = {
    useState(initial) {
      const position = index++;
      if (!(position in state)) state[position] = initial;
      return [state[position], (next) => { state[position] = typeof next === "function" ? next(state[position]) : next; }];
    },
    useRef(initial) {
      const position = refIndex++;
      if (!(position in refs)) refs[position] = { current: initial };
      return refs[position];
    },
    useMemo: (make) => make(),
    useEffect: (effect) => { effects.push(effect); },
    ...dependencies,
  };
  const page = new Function("require", "exports", "deps", `const { ${Object.keys(deps).join(", ")} } = deps;\n${compile(functionSource(name))}\nreturn ${name};`)(
    (id) => { if (id === "react/jsx-runtime") return jsx; throw new Error(`Unexpected dependency: ${id}`); }, {}, deps);
  return { render() {
    index = 0;
    refIndex = 0;
    effects.length = 0;
    const view = page({ session: { accessToken: "test-only" } });
    effects.forEach((effect) => effect());
    return view;
  } };
}

function find(tree, type, predicate = () => true) {
  if (Array.isArray(tree)) return tree.map((item) => find(item, type, predicate)).find(Boolean);
  if (!tree || typeof tree !== "object") return undefined;
  if (tree.type === type && predicate(tree.props)) return tree;
  return find(tree.props?.children, type, predicate);
}

test("feedback search and pagination keep every matching ticket reachable", () => {
  let path = "";
  let total = 12;
  const datePicker = { RangePicker: component("RangePicker") };
  const harness = mount("FeedbackPage", {
    useAdminData(nextPath) {
      path = nextPath;
      return { data: { items: Array.from({ length: 5 }, (_, i) => ({ id: String(i) })), total, page: 1, page_size: 5 }, loading: false, error: null, reload() {} };
    },
    platformOptions: [], feedbackTypeOptions: [{ value: "Bug Report", label: "Bug Report" }], feedbackStatusOptions: [],
    PagePanel: component("PagePanel"), FilterBar: component("FilterBar"), DatePicker: datePicker,
    Select: component("Select"), Input: component("Input"), Button: component("Button"), Alert: component("Alert"),
    Space: component("Space"), FeedbackStatusTag: component("FeedbackStatusTag"), Tag: component("Tag"), Text: component("Text"),
    Pagination: component("Pagination"), formatTime: (value) => value, rangeSummary: () => "", rangeSummaryPage: () => "",
  });
  let view = harness.render();
  const uid = find(view, "Input", (props) => props.placeholder === "UID 搜索");
  uid.props.onChange({ target: { value: "user-1" } });
  view = harness.render();
  find(view, "Select", (props) => props.placeholder === "问题类型").props.onChange("Bug Report");
  find(view, "Select", (props) => props.placeholder === "处理状态").props.onChange("pending");
  find(view, datePicker, (props) => props.placeholder === "开始时间").props.onChange(null, "2026-10-28");
  find(view, datePicker, (props) => props.placeholder === "结束时间").props.onChange(null, "2026-10-29");
  assert.equal(new URL(path, "http://localhost").searchParams.has("uid"), false, "Draft filters wait for Query");
  view = harness.render();
  find(view, "Button", (props) => props.children === "查询").props.onClick();
  view = harness.render();
  const query = new URL(path, "http://localhost").searchParams;
  for (const [key, value] of Object.entries({ uid: "user-1", issue_type: "Bug Report", status: "pending", date_from: "2026-10-28", date_to: "2026-10-29" })) {
    assert.equal(query.get(key), value);
  }
  find(view, "Pagination").props.onChange(2);
  view = harness.render();
  assert.equal(new URL(path, "http://localhost").searchParams.get("page"), "2");
  total = 2;
  harness.render();
  view = harness.render();
  assert.equal(new URL(path, "http://localhost").searchParams.get("page"), "1", "Out-of-range page returns to the last valid page");
  find(view, "Button", (props) => props.children === "重置").props.onClick();
  harness.render();
  assert.equal(new URL(path, "http://localhost").searchParams.get("page"), "1");
  assert.equal(new URL(path, "http://localhost").searchParams.has("uid"), false);
  assert.equal(find(view, "Select", (props) => props.placeholder === "平台未知").props.disabled, true);
});

test("scan detail keeps the last selected record when requests finish out of order", async () => {
  const pending = new Map();
  const harness = mount("ScansPage", {
    scanCardTypeOptions: [], scanPlatformOptions: [], environmentOptions: [], recognitionOptions: [], confirmationOptions: [],
    useAdminData: () => ({ data: { items: [], total: 0, page_size: 10 }, loading: false, error: null, reload() {} }),
    adminRequest: (path) => new Promise((resolve, reject) => { pending.set(path, { resolve, reject }); }),
    AuthenticatedScanImage: component("AuthenticatedScanImage"), ScanDetailDrawer: component("ScanDetailDrawer"),
    ScanFilterField: component("ScanFilterField"), Alert: component("Alert"), Button: component("Button"),
    DatePicker: { RangePicker: component("RangePicker") }, Input: component("Input"), Pagination: component("Pagination"),
    Select: component("Select"), Table: component("Table"), Text: component("Text"),
    rangeSummaryPage: () => "", formatTime: (value) => value, renderRecognitionStatus: (value) => value,
    errorMessage: (error) => error.message,
  });
  let view = harness.render();
  const action = find(view, "Table").props.columns.at(-1).render;
  action(null, { scan_id: "A" }).props.onClick();
  action(null, { scan_id: "B" }).props.onClick();
  pending.get("/scans/B").resolve({ scan_id: "B" });
  await Promise.resolve();
  pending.get("/scans/A").resolve({ scan_id: "A" });
  await Promise.resolve();
  view = harness.render();
  assert.equal(find(view, "ScanDetailDrawer").props.scan?.scan_id, "B");
  find(view, "ScanDetailDrawer").props.onClose();
  view = harness.render();
  assert.equal(find(view, "ScanDetailDrawer").props.scan, null);
  assert.equal(find(view, "ScanDetailDrawer").props.open, false);

  action(null, { scan_id: "C" }).props.onClick();
  pending.get("/scans/C").reject(new Error("详情读取失败"));
  await Promise.resolve();
  view = harness.render();
  assert.equal(find(view, "ScanDetailDrawer").props.error, "详情读取失败");
  assert.equal(find(view, "ScanDetailDrawer").props.open, true);
  find(view, "ScanDetailDrawer").props.onRetry();
  pending.get("/scans/C").resolve({ scan_id: "C" });
  await Promise.resolve();
  view = harness.render();
  assert.equal(find(view, "ScanDetailDrawer").props.scan?.scan_id, "C");

  action(null, { scan_id: "D" }).props.onClick();
  view = harness.render();
  find(view, "ScanDetailDrawer").props.onClose();
  pending.get("/scans/D").resolve({ scan_id: "D" });
  await Promise.resolve();
  view = harness.render();
  assert.equal(find(view, "ScanDetailDrawer").props.open, false);
  assert.equal(find(view, "ScanDetailDrawer").props.scan, null);
});
