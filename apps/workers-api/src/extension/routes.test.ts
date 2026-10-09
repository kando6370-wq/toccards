import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { app } from "../app";
import type { Env } from "../env";
import type { CardSearchResult, DataSourceAdapter } from "../data-source/adapter";
import * as dataSourceRoutes from "../data-source/routes";

const endpoint = "/api/v1/extension/recognize";
const accessKey = "extension-test-only-key";
const input = { vector: [1, ...Array(511).fill(0)], card_type: 1 };
const output = { candidates: [{ product_id: "10738", confidence: 92.125 }] };

const card: CardSearchResult = {
  card_ref: "10738", name: "Test Charizard", game: "Pokemon",
  set_name: "Test Base Set", set_code: "BS", card_number: "4/102",
  finish: "Normal", language: "English", object_type: "tcg",
  image_url: null, rarity: "Rare", price_usd: 12.5,
  previous_7d_price_usd: 10, price_change_7d_percent: 25,
  price_as_of: "2026-10-09", available_finishes: ["Normal", "Holo"],
  available_languages: ["English", "Japanese"],
};

function setup() {
  const upstream = vi.fn().mockResolvedValue(Response.json(output));
  const limiter = vi.fn().mockResolvedValue({ success: true });
  const forbidden = new Proxy({}, { get() { throw new Error("Plugin recognition must not access quota or storage."); } });
  const getCard = vi.fn(async (cardRef: string): Promise<CardSearchResult | null> => cardRef === card.card_ref ? card : null);
  vi.spyOn(dataSourceRoutes, "createDefaultAdapter").mockReturnValue({ getCard } as unknown as DataSourceAdapter);
  const overrides = new Map<string, { card_ref: string; override_fields: string; image_url: string | null; is_missing_card: number }>();
  const readOverride = vi.fn((query: string) => {
    if (!query.trim().startsWith("SELECT") || !query.includes("FROM card_override")) {
      throw new Error("Unexpected plugin database access.");
    }
    return {
      bind: (cardRef: string) => ({ first: async () => overrides.get(cardRef) ?? null }),
    };
  });
  const env = {
    EXTENSION_RECOGNITION_KEY: accessKey,
    EXTENSION_RECOGNITION_RATE_LIMITER: { limit: limiter },
    EXTENSION_CLIENT_IP: "192.0.2.1",
    VECTOR_RECOGNITION: { fetch: upstream },
    DB: { prepare: readOverride },
    CACHE_KV: forbidden,
    SCAN_IMAGES: forbidden,
    JWT_SECRET: "not-a-plugin-key",
    APP_ENVIRONMENT: "development",
  } as unknown as Env;
  const request = (body: unknown = input, headers: Record<string, string> = {}) => app.request(endpoint, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessKey}`, "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  }, env);
  return { env, upstream, limiter, request, getCard, overrides, readOverride };
}

describe("anonymous plugin recognition", () => {
  beforeEach(() => {
    vi.spyOn(console, "info").mockImplementation(() => {});
    vi.spyOn(console, "error").mockImplementation(() => {});
  });
  afterEach(() => { vi.restoreAllMocks(); });

  it("resolves full public card details without login, quota, storage, or sending the plugin credential upstream", async () => {
    const { request, upstream, limiter } = setup();
    const response = await request();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ candidates: [{
      ...card, image_url: "https://image.tcgcard.fun/cards/10738.jpg", override_applied: false,
      product_id: "10738", confidence: 92.125,
    }] });
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(limiter).toHaveBeenCalledExactlyOnceWith({ key: "192.0.2.1" });
    expect(upstream).toHaveBeenCalledExactlyOnceWith("https://recognize-vec.internal/recognize", {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify(input),
      signal: expect.any(AbortSignal),
      redirect: "manual",
    });
  });

  it("preserves upstream ranking and confidence rather than sorting candidates by their card price", async () => {
    const { request, upstream, getCard } = setup();
    getCard.mockImplementation(async (cardRef) => ({ ...card, card_ref: cardRef, price_usd: cardRef === "200" ? 500 : 1 }));
    upstream.mockResolvedValue(Response.json({ candidates: [
      { product_id: "200", confidence: 80 }, { product_id: "10738", confidence: 92.125 },
    ] }));
    const response = await request();
    expect(await response.json()).toMatchObject({ candidates: [
      { product_id: "200", confidence: 80, price_usd: 500, image_url: "https://image.tcgcard.fun/cards/200.jpg" },
      { product_id: "10738", confidence: 92.125, price_usd: 1 },
    ] });
  });

  it("normalizes numeric product IDs and deduplicates before querying while keeping the first recognition confidence", async () => {
    const { request, upstream, getCard, readOverride } = setup();
    upstream.mockResolvedValue(Response.json({ candidates: [
      { product_id: 10738, confidence: 90 }, { product_id: "10738", confidence: 99 },
    ] }));
    const response = await request();
    expect(await response.json()).toMatchObject({ candidates: [{ product_id: "10738", confidence: 90 }] });
    expect(getCard).toHaveBeenCalledExactlyOnceWith("10738");
    expect(readOverride).toHaveBeenCalledTimes(1);
  });

  it("applies operations corrections exactly like existing card detail instead of returning stale catalog fields", async () => {
    const { request, overrides } = setup();
    overrides.set("10738", { card_ref: "10738", override_fields: JSON.stringify({ name: "Corrected name", rarity: "Promo" }), image_url: "https://custom.invalid/card.jpg", is_missing_card: 0 });
    expect(await (await request()).json()).toMatchObject({ candidates: [{
      name: "Corrected name", rarity: "Promo", price_usd: 12.5,
      image_url: "https://image.tcgcard.fun/cards/10738.jpg", override_applied: true,
    }] });
  });

  it("keeps operations-backfilled cards even without a provider record because detail lookup permits manual catalog repair", async () => {
    const { request, upstream, overrides, getCard } = setup();
    const productId = "admin:tcg:missing-promo";
    upstream.mockResolvedValue(Response.json({ candidates: [{ product_id: productId, confidence: 85 }] }));
    overrides.set(productId, { card_ref: productId, override_fields: JSON.stringify({ name: "Manual promo", set_name: "Promos", set_code: "PR", card_number: "001", object_type: "tcg" }), image_url: null, is_missing_card: 1 });
    const response = await request();
    expect(await response.json()).toMatchObject({ candidates: [{
      product_id: productId, name: "Manual promo", confidence: 85, override_applied: true,
      image_url: "https://image.tcgcard.fun/cards/admin%3Atcg%3Amissing-promo.jpg",
    }] });
    expect(getCard).not.toHaveBeenCalled();
  });

  it("omits unknown card IDs without hiding the remaining valid matches", async () => {
    const { request, upstream } = setup();
    upstream.mockResolvedValue(Response.json({ candidates: [{ product_id: "unknown", confidence: 95 }, ...output.candidates] }));
    expect(await (await request()).json()).toMatchObject({ candidates: [{ product_id: "10738", name: card.name }] });
  });

  it("returns an empty result when all cards are missing rather than inventing names or prices", async () => {
    const { request, upstream } = setup();
    upstream.mockResolvedValue(Response.json({ candidates: [{ product_id: "unknown", confidence: 95 }] }));
    expect(await (await request()).json()).toEqual({ candidates: [] });
  });

  it("does not query business data for a genuine empty recognition result", async () => {
    const { request, upstream, getCard, readOverride } = setup();
    upstream.mockResolvedValue(Response.json({ candidates: [] }));
    expect(await (await request()).json()).toEqual({ candidates: [] });
    expect(getCard).not.toHaveBeenCalled();
    expect(readOverride).not.toHaveBeenCalled();
  });

  it("preserves absent prices rather than advertising zero-value cards", async () => {
    const { request, getCard } = setup();
    const { price_usd, previous_7d_price_usd, price_change_7d_percent, price_as_of, ...unpriced } = card;
    getCard.mockResolvedValue(unpriced);
    const response = await request();
    const payload = await response.json() as { candidates: Record<string, unknown>[] };
    expect(payload.candidates[0]).toMatchObject({ name: card.name, image_url: "https://image.tcgcard.fun/cards/10738.jpg" });
    expect(payload.candidates[0]).not.toHaveProperty("price_usd");
  });

  it("fails loudly on a detail database error instead of treating an outage as a successful no-match or vector-service error", async () => {
    const { request, getCard } = setup();
    getCard.mockRejectedValue(new Error("detail database unavailable"));
    const response = await request();
    expect(response.status).toBe(500);
    expect(await response.json()).toMatchObject({ success: false, error: { code: "INTERNAL_ERROR" } });
  });

  it.each([
    {}, null, { candidates: null }, { candidates: [{}] },
    { candidates: [{ product_id: "10738", confidence: -1 }] },
    { candidates: [{ product_id: "10738", confidence: 101 }] },
    { candidates: [{ product_id: "10738", confidence: "92" }] },
    { candidates: [{ product_id: " 10738", confidence: 92 }] },
  ])("rejects malformed recognition candidates before querying card details: %j", async (payload) => {
    const { request, upstream, getCard, readOverride } = setup();
    upstream.mockResolvedValue(Response.json(payload));
    expect((await request()).status).toBe(502);
    expect(getCard).not.toHaveBeenCalled();
    expect(readOverride).not.toHaveBeenCalled();
  });

  it("does not trust price or card-name fields from retrieval output because business data must come from the public detail resolver", async () => {
    const { request, upstream } = setup();
    upstream.mockResolvedValue(Response.json({
      candidates: [{ product_id: "10738", confidence: 92.125, price_usd: 0, name: "Injected name" }],
      debug_trace: "internal retrieval diagnostics",
    }));
    const response = await request();
    expect(await response.json()).toEqual({ candidates: [{
      ...card, image_url: "https://image.tcgcard.fun/cards/10738.jpg", override_applied: false,
      product_id: "10738", confidence: 92.125,
    }] });
  });

  it("does not return partial success when a later candidate detail query fails", async () => {
    const { request, upstream, getCard } = setup();
    upstream.mockResolvedValue(Response.json({ candidates: [...output.candidates, { product_id: "200", confidence: 80 }] }));
    getCard.mockResolvedValueOnce(card).mockRejectedValueOnce(new Error("later detail failure"));
    const response = await request();
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ success: false, error: { code: "INTERNAL_ERROR", message: "Something went wrong. Please try again." } });
  });

  it("defaults card_type to TCG just like the existing scan protocol", async () => {
    const { request, upstream } = setup();
    expect((await request({ vector: input.vector })).status).toBe(200);
    expect(JSON.parse(upstream.mock.calls[0][1].body)).toEqual({ vector: input.vector, card_type: 0 });
  });

  it.each(["", "Bearer wrong", "Basic anything", "Bearer extension-test-only-key extra", "Bearer not-a-plugin-key"])(
    "rejects invalid credentials before spending recognition or limiter capacity: %s", async (authorization) => {
      const { request, upstream, limiter } = setup();
      const response = await request(input, { Authorization: authorization });
      expect(response.status).toBe(401);
      expect(await response.json()).toMatchObject({ error: { code: "UNAUTHORIZED" } });
      expect(upstream).not.toHaveBeenCalled();
      expect(limiter).not.toHaveBeenCalled();
    },
  );

  it("leaves the endpoint disabled when its independent key is not configured without disabling existing health", async () => {
    const { env, request, upstream } = setup();
    delete env.EXTENSION_RECOGNITION_KEY;
    expect((await request()).status).toBe(503);
    expect(upstream).not.toHaveBeenCalled();
    const health = await app.request("/api/v1/health", undefined, env);
    expect(await health.json()).toEqual({ status: "ok" });
  });

  it.each(["EXTENSION_RECOGNITION_RATE_LIMITER", "VECTOR_RECOGNITION", "EXTENSION_CLIENT_IP"] as const)(
    "fails closed rather than expose an unprotected route when %s is missing", async (binding) => {
      const { env, request, upstream } = setup();
      delete env[binding];
      const response = await request(input, { "CF-Connecting-IP": "192.0.2.99", "X-Forwarded-For": "192.0.2.98" });
      expect(response.status).toBe(503);
      expect(upstream).not.toHaveBeenCalled();
    },
  );

  it("refuses bursts without invoking the internal recognizer or spending App quota", async () => {
    const { request, upstream, limiter } = setup();
    limiter.mockResolvedValue({ success: false });
    const response = await request();
    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("60");
    expect(await response.json()).toMatchObject({ error: { code: "RATE_LIMITED" } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it("fails closed when the limiter is unavailable rather than silently bypassing protection", async () => {
    const { request, upstream, limiter } = setup();
    limiter.mockRejectedValue(new Error("limiter unavailable"));
    expect((await request()).status).toBe(503);
    expect(upstream).not.toHaveBeenCalled();
  });

  it.each([
    null, [], {}, { vector: [] }, { vector: Array(512).fill(0) },
    { vector: Array(511).fill(1) }, { vector: Array(513).fill(1) },
    { vector: ["1", ...Array(511).fill(0)] },
    { vector: [null, ...Array(511).fill(1)] },
    { ...input, card_type: 2 }, { ...input, card_type: "1" },
  ])("rejects invalid protocol input without sending it to the recognizer: %j", async (body) => {
    const { request, upstream } = setup();
    expect((await request(body)).status).toBe(422);
    expect(upstream).not.toHaveBeenCalled();
  });

  it.each(["1e309", "-1e309"])("rejects JSON numeric overflow %s because the vector service requires finite components", async (overflow) => {
    const { env, upstream } = setup();
    const body = JSON.stringify(input).replace('"vector":[1,', `"vector":[${overflow},`);
    const response = await app.request(endpoint, {
      method: "POST", headers: { Authorization: `Bearer ${accessKey}`, "Content-Type": "application/json" }, body,
    }, env);
    expect(response.status).toBe(422);
    expect(upstream).not.toHaveBeenCalled();
  });

  it("does not forward caller-selected destinations, extra payload, or authentication headers", async () => {
    const { request, upstream } = setup();
    expect((await request({ ...input, url: "https://other.invalid", image: "ignored" })).status).toBe(200);
    expect(JSON.parse(upstream.mock.calls[0][1].body)).toEqual(input);
  });

  it("rejects malformed JSON rather than inventing a default recognition input", async () => {
    const { env, upstream } = setup();
    const response = await app.request(endpoint, {
      method: "POST", headers: { Authorization: `Bearer ${accessKey}`, "Content-Type": "application/json" }, body: "{",
    }, env);
    expect(response.status).toBe(422);
    expect(upstream).not.toHaveBeenCalled();
  });

  it.each([
    ["ASCII", "x".repeat(33 * 1024)],
    ["multibyte UTF-8", "汉".repeat(11 * 1024)],
  ])("limits actual body bytes for %s even when a caller lies about Content-Length", async (_encoding, extra) => {
    const { request, upstream } = setup();
    const response = await request({ ...input, extra }, { "Content-Length": "1" });
    expect(response.status).toBe(413);
    expect(upstream).not.toHaveBeenCalled();
  });

  it.each(["text/plain", "multipart/form-data"])("only accepts the existing JSON vector transport, not %s", async (contentType) => {
    const { request, upstream } = setup();
    expect((await request(input, { "Content-Type": contentType })).status).toBe(422);
    expect(upstream).not.toHaveBeenCalled();
  });

  it.each([503, 307])("reports upstream HTTP %s as recognition failure without leaking its error body", async (status) => {
    const { request, upstream } = setup();
    upstream.mockResolvedValue(Response.json({ secret: "internal diagnostics" }, { status }));
    const response = await request();
    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({ error: { code: "VECTOR_RECOGNITION_UNAVAILABLE" } });
    expect(upstream).toHaveBeenCalledTimes(1);
  });

  it.each([null, JSON.stringify({ candidates: [] })])("rejects redirects without forwarding vectors because Workers require manual redirect handling: %j", async (body) => {
    const { request, upstream, getCard, readOverride } = setup();
    upstream.mockResolvedValue(new Response(body, {
      status: 307,
      headers: { Location: "https://untrusted.example/recognize", "Content-Type": "application/json" },
    }));
    const response = await request();
    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({ error: { code: "VECTOR_RECOGNITION_UNAVAILABLE" } });
    expect(upstream).toHaveBeenCalledExactlyOnceWith("https://recognize-vec.internal/recognize", expect.objectContaining({
      redirect: "manual",
      body: JSON.stringify(input),
    }));
    expect(getCard).not.toHaveBeenCalled();
    expect(readOverride).not.toHaveBeenCalled();
  });

  it("does not report malformed upstream JSON as a successful identification", async () => {
    const { request, upstream } = setup();
    upstream.mockResolvedValue(new Response("not-json"));
    expect((await request()).status).toBe(502);
  });

  it("reports network failure without retrying an expensive identification", async () => {
    const { request, upstream } = setup();
    upstream.mockRejectedValue(new Error("network unavailable"));
    expect((await request()).status).toBe(502);
    expect(upstream).toHaveBeenCalledTimes(1);
  });

  it("keeps the deadline through response-body reads so stalled results cannot hold the request indefinitely", async () => {
    const { request, upstream } = setup();
    const controller = new AbortController();
    const timeout = vi.spyOn(AbortSignal, "timeout").mockReturnValue(controller.signal);
    upstream.mockImplementation(async (_url, init) => new Response(new ReadableStream({
      start(stream) {
        init.signal.addEventListener("abort", () => stream.error(new DOMException("Timed out", "TimeoutError")), { once: true });
      },
      pull() { controller.abort(); },
    })));
    expect((await request()).status).toBe(504);
    expect(timeout).toHaveBeenCalledWith(10_000);
  });

  it("does not expose the extension credential as an App login credential", async () => {
    const { env } = setup();
    const response = await app.request("/api/v1/scan/quota", { headers: { Authorization: `Bearer ${accessKey}` } }, env);
    expect(response.status).toBe(401);
  });
});
