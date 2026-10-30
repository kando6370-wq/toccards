import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { QueryClient, QueryObserver } from "@tanstack/react-query";
import ts from "typescript";

const source = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const file = ts.createSourceFile("App.tsx", source, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TSX);
const imageFunction = file.statements.find((node) =>
  ts.isFunctionDeclaration(node) && node.name?.text === "AuthenticatedScanImage"
);
assert.ok(imageFunction);
const compiled = ts.transpileModule(imageFunction.getText(file), {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
}).outputText;

function renderImage(sessionToken, path, onUnauthorized = () => {}) {
  let queryOptions;
  const deps = {
    useState: () => [null, () => {}],
    useEffect: () => {},
    useQuery: (options) => { queryOptions = options; return { data: undefined }; },
    API_BASE: "https://api.example.test",
    createAdminRequestHeaders: (headers) => new Headers(headers),
    dispatchSessionExpiredOnUnauthorized: onUnauthorized,
    Image: "Image",
  };
  const component = new Function("require", "exports", "deps", `
    const { ${Object.keys(deps).join(", ")} } = deps;
    ${compiled}
    return AuthenticatedScanImage;
  `)((id) => {
    if (id === "react/jsx-runtime") return { jsx: () => ({}), jsxs: () => ({}) };
    throw new Error(`Unexpected dependency: ${id}`);
  }, {}, deps);
  component({ path, session: { accessToken: sessionToken }, className: "scan-thumb" });
  return queryOptions;
}

test("list and detail share one authorized image request while mounted", async () => {
  const list = renderImage("token-a", "/scans/one/image");
  const detail = renderImage("token-a", "/scans/one/image");
  assert.ok(list && detail, "both image views must use the shared query");
  assert.deepEqual(list.queryKey, detail.queryKey);
  assert.notDeepEqual(list.queryKey, renderImage("token-b", "/scans/one/image").queryKey);
  assert.equal(list.gcTime, 0, "image blobs must leave memory when the last view unmounts");
  assert.equal(list.retryOnMount, false, "a failed image must not refetch when detail opens");

  const originalFetch = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init });
    return new Response(new Uint8Array([1, 2, 3]), { headers: { "content-type": "image/jpeg" } });
  };
  const client = new QueryClient();
  try {
    const [first, second] = await Promise.all([client.fetchQuery(list), client.fetchQuery(detail)]);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, "https://api.example.test/scans/one/image");
    assert.equal(calls[0].init.headers.get("Authorization"), "Bearer token-a");
    assert.deepEqual(new Uint8Array(await first.arrayBuffer()), new Uint8Array([1, 2, 3]));
    assert.equal(first, second);
  } finally {
    client.clear();
    globalThis.fetch = originalFetch;
  }
});

test("unmount cancels an in-flight private image request", async () => {
  const options = renderImage("token-a", "/scans/pending/image");
  assert.ok(options);
  const originalFetch = globalThis.fetch;
  let started;
  const requestStarted = new Promise((resolve) => { started = resolve; });
  let signal;
  globalThis.fetch = (_url, init) => {
    signal = init.signal;
    started();
    return new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true });
    });
  };
  const client = new QueryClient();
  try {
    const observer = new QueryObserver(client, options);
    const unsubscribe = observer.subscribe(() => {});
    await requestStarted;
    unsubscribe();
    assert.equal(signal.aborted, true);
  } finally {
    client.clear();
    globalThis.fetch = originalFetch;
  }
});

test("a private image 401 triggers the existing session-expiry path once", async () => {
  const expired = [];
  const options = renderImage("expired-token", "/scans/expired/image", (response, token) => {
    expired.push([response.status, token]);
  });
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    return new Response(null, { status: 401 });
  };
  const client = new QueryClient();
  try {
    await assert.rejects(client.fetchQuery(options), /Scan image unavailable/);
    assert.equal(calls, 1);
    assert.deepEqual(expired, [[401, "expired-token"]]);
  } finally {
    client.clear();
    globalThis.fetch = originalFetch;
  }
});
