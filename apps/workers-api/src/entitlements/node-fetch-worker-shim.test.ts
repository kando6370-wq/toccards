import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import workerFetch, { Headers } from "../compat/node-fetch-worker-shim";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const wranglerConfig = readFileSync(join(testDirectory, "../../wrangler.toml"), "utf8");
const verifierSource = readFileSync(join(testDirectory, "apple-signed-data.ts"), "utf8");

describe("Apple SDK node-fetch Worker compatibility", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  it("aliases only the SDK transport while retaining online certificate revocation checks", () => {
    expect(wranglerConfig).toContain('"node-fetch" = "./src/compat/node-fetch-worker-shim.ts"');
    expect(verifierSource).toContain("new SignedDataVerifier(roots, true,");
  });

  it("returns Buffer bytes because Apple online OCSP verification consumes response.buffer()", async () => {
    const nativeFetch = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(init).not.toHaveProperty("timeout");
      expect(init?.signal).toBeInstanceOf(AbortSignal);
      return new Response(new Uint8Array([1, 2, 3]), { status: 200 });
    });
    vi.stubGlobal("fetch", nativeFetch);

    const response = await workerFetch("https://ocsp.apple.com", {
      body: Buffer.from([4, 5, 6]),
      headers: new Headers({ "content-type": "application/ocsp-request" }),
      method: "POST",
      timeout: 30_000,
    });

    expect(response.ok).toBe(true);
    const body = await response.buffer();
    expect(Buffer.isBuffer(body)).toBe(true);
    expect([...body]).toEqual([1, 2, 3]);
  });

  it("keeps native Response methods because Apple Server API reads JSON responses", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({ status: "ok" })));

    const response = await workerFetch("https://api.storekit.itunes.apple.com/inApps/v1/status/test");

    await expect(response.json()).resolves.toEqual({ status: "ok" });
  });

  it("clears the timeout when Apple rejects a non-success OCSP response without reading its body", async () => {
    vi.useFakeTimers();
    const abortListener = vi.fn();
    vi.stubGlobal("fetch", vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      init?.signal?.addEventListener("abort", abortListener, { once: true });
      return new Response(null, { status: 503 });
    }));

    const response = await workerFetch("https://ocsp.apple.com", { timeout: 30_000 });

    expect(response.status).toBe(503);
    expect(vi.getTimerCount()).toBe(0);
    await vi.advanceTimersByTimeAsync(30_000);
    expect(abortListener).not.toHaveBeenCalled();
  });

  it("aborts a stalled OCSP request because the SDK passes a finite timeout", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("fetch", vi.fn((_input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>(
      (_resolve, reject) => init?.signal?.addEventListener("abort", () => reject(new Error("aborted")), { once: true }),
    )));

    const request = workerFetch("https://ocsp.apple.com", { timeout: 30_000 });
    const rejection = expect(request).rejects.toThrow("aborted");
    await vi.advanceTimersByTimeAsync(30_000);

    await rejection;
  });
});
