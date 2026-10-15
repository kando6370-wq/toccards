import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { createAppleCatalogLoader, createCatalogToken } from "./catalog";

const NOW = new Date("2026-10-14T04:00:00.000Z");
const resource = (type: string, id: string, attributes: Record<string, unknown> = {}) => ({ type, id, attributes });
const subscription = (id: string, productId: string) => resource("subscriptions", id, { productId, name: "Reference name", subscriptionPeriod: "ONE_WEEK", groupLevel: 1, state: "READY_TO_SUBMIT" });
const offer = (id: string, start: string | null, end: string | null, mode = "FREE_TRIAL") => ({
  ...resource("subscriptionIntroductoryOffers", id, { offerMode: mode, duration: "ONE_MONTH", numberOfPeriods: 1, startDate: start, endDate: end }),
  relationships: { territory: { data: { type: "territories", id: "USA" } } },
});

let env: Env;
let publicKey: CryptoKey;
let pages: Map<string, unknown>;
const requested: string[] = [];
const fetcher = vi.fn<typeof fetch>();
const loader = createAppleCatalogLoader({ fetch: fetcher, now: () => NOW });

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  if (!("privateKey" in pair)) throw new Error("Expected an asymmetric test key pair.");
  publicKey = pair.publicKey;
  const exported = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  if (!(exported instanceof ArrayBuffer)) throw new Error("Expected a PKCS8 test key.");
  const bytes = new Uint8Array(exported);
  env = { APP_STORE_CONNECT_APP_ID: "456", APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID: "123",
    APPLE_IAP_BUNDLE_ID: "example.app", APP_STORE_CONNECT_KEY_ID: "test-key", APP_STORE_CONNECT_ISSUER_ID: "test-issuer",
    APP_STORE_CONNECT_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\n" + btoa(String.fromCharCode(...bytes)) + "\n-----END PRIVATE KEY-----",
    SUBSCRIPTION_LIFETIME_PRODUCT_IDS: "lifetime" } as Env;
});

beforeEach(() => {
  requested.length = 0;
  pages = new Map([
    ["/v1/apps/456", { data: resource("apps", "456", { bundleId: "example.app" }) }],
    ["/v1/apps/456/subscriptionGroups", { data: [resource("subscriptionGroups", "123")] }],
    ["/v1/subscriptionGroups/123/subscriptions", { data: [subscription("s1", "paid.week"), subscription("s2", "trial.week")] }],
    ["/v1/subscriptions/s1/introductoryOffers", { data: [] }],
    ["/v1/subscriptions/s2/introductoryOffers", { data: [offer("o1", null, null)] }],
    ["/v1/apps/456/inAppPurchasesV2", { data: [
      resource("inAppPurchases", "life", { productId: "lifetime", name: "Lifetime", inAppPurchaseType: "NON_CONSUMABLE", state: "APPROVED" }),
      resource("inAppPurchases", "other", { productId: "other.nonconsumable", inAppPurchaseType: "NON_CONSUMABLE", state: "APPROVED" }),
    ] }],
  ]);
  fetcher.mockReset();
  fetcher.mockImplementation(async (input, init) => {
    const url = new URL(String(input));
    requested.push(url.href);
    expect(init?.method).toBe("GET");
    expect(init?.redirect).toBe("manual");
    expect(new Headers(init?.headers).get("Authorization")).toMatch(/^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    const data = pages.get(url.pathname + (url.searchParams.has("cursor") ? "?cursor=" + url.searchParams.get("cursor") : ""));
    if (data === undefined) return new Response("unexpected request", { status: 500 });
    return Response.json(data);
  });
});

describe("App Store Connect read-only catalog", () => {
  it("signs a five-minute ES256 team token for the catalog audience", async () => {
    const token = await createCatalogToken(env, NOW);
    const [header, payload, signature] = token.split(".");
    const decode = (v: string) => Uint8Array.from(atob(v.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
    expect(JSON.parse(new TextDecoder().decode(decode(header)))).toEqual({ alg: "ES256", kid: "test-key", typ: "JWT" });
    const claims = JSON.parse(new TextDecoder().decode(decode(payload)));
    expect(claims.aud).toBe("appstoreconnect-v1");
    expect(claims.iss).toBe("test-issuer");
    expect(claims.exp - claims.iat).toBe(300);
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, decode(signature), new TextEncoder().encode(header + "." + payload))).toBe(true);
  });

  it("reads only the configured App/group and explicit Lifetime products, preserving real offer units", async () => {
    const catalog = await loader(env, new Set(["subscription", "non_consumable"]));
    expect(catalog.products.map((p) => p.product_id)).toEqual(["paid.week", "trial.week", "lifetime"]);
    expect(catalog.products[1].introductory_offers[0]).toMatchObject({ territory: "USA", duration: "ONE_MONTH", periods: 1 });
    expect(catalog.products[0].has_free_trial).toBe(false);
    expect(catalog.products[1].has_free_trial).toBe(true);
    expect(catalog.products[2].subscription_group_id).toBeNull();
  });

  it("follows pagination for groups, subscriptions and offers without returning partial lists", async () => {
    pages.set("/v1/apps/456/subscriptionGroups", { data: [], links: { next: "/v1/apps/456/subscriptionGroups?cursor=next" } });
    pages.set("/v1/apps/456/subscriptionGroups?cursor=next", { data: [resource("subscriptionGroups", "123")] });
    pages.set("/v1/subscriptionGroups/123/subscriptions", { data: [subscription("s1", "paid.week")], links: { next: "https://api.appstoreconnect.apple.com/v1/subscriptionGroups/123/subscriptions?cursor=next" } });
    pages.set("/v1/subscriptionGroups/123/subscriptions?cursor=next", { data: [subscription("s2", "trial.week")] });
    pages.set("/v1/subscriptions/s2/introductoryOffers", { data: [], links: { next: "?cursor=next" } });
    pages.set("/v1/subscriptions/s2/introductoryOffers?cursor=next", { data: [offer("o2", null, null)] });
    expect((await loader(env, new Set(["subscription"]))).products).toHaveLength(2);
    expect(requested.filter((url) => url.includes("cursor=next"))).toHaveLength(3);
  });

  it.each([
    "https://other.example/v1/subscriptionGroups/123/subscriptions?cursor=next",
    "https://api.appstoreconnect.apple.com/v1/apps/999?cursor=next",
    "http://api.appstoreconnect.apple.com/v1/subscriptionGroups/123/subscriptions",
    "/v1/subscriptionGroups/123/subscriptions?limit=200",
  ])("rejects unsafe or looping pagination: %s", async (next) => {
    pages.set("/v1/subscriptionGroups/123/subscriptions", { data: [], links: { next } });
    await expect(loader(env, new Set(["subscription"]))).rejects.toMatchObject({ code: "CATALOG_INVALID_RESPONSE" });
    expect(requested).toHaveLength(3);
  });

  it("distinguishes a truly empty catalog from upstream failure and malformed payload", async () => {
    pages.set("/v1/subscriptionGroups/123/subscriptions", { data: [] });
    expect((await loader(env, new Set(["subscription"]))).products).toEqual([]);
    pages.set("/v1/subscriptionGroups/123/subscriptions", { errors: [{ detail: "private upstream error" }] });
    await expect(loader(env, new Set(["subscription"]))).rejects.toMatchObject({ code: "CATALOG_INVALID_RESPONSE" });
    pages.set("/v1/subscriptionGroups/123/subscriptions", { data: null });
    await expect(loader(env, new Set(["subscription"]))).rejects.toMatchObject({ code: "CATALOG_INVALID_RESPONSE" });
  });

  it("does not disclose Apple errors or follow redirects on authentication failure", async () => {
    for (const status of [302, 401, 403, 429, 500]) {
      fetcher.mockResolvedValueOnce(new Response("secret upstream payload", { status, headers: { Location: "https://elsewhere.example" } }));
      await expect(loader(env, new Set(["subscription"]))).rejects.toMatchObject({ code: "CATALOG_UNAVAILABLE", message: "Apple catalog could not be read." });
    }
  });

  it("fails closed when team credentials or App scope are missing, without a demo fallback", async () => {
    await expect(loader({ ...env, APP_STORE_CONNECT_PRIVATE_KEY: undefined }, new Set(["subscription"]))).rejects.toMatchObject({ code: "CATALOG_NOT_CONFIGURED" });
    await expect(loader({ ...env, APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID: undefined }, new Set(["subscription"]))).rejects.toMatchObject({ code: "CATALOG_NOT_CONFIGURED" });
    expect(requested).toEqual([]);
  });

  it("rejects a mismatched Bundle ID or a group from another App", async () => {
    pages.set("/v1/apps/456", { data: resource("apps", "456", { bundleId: "other.app" }) });
    await expect(loader(env, new Set(["subscription"]))).rejects.toMatchObject({ code: "CATALOG_SCOPE_MISMATCH" });
    pages.set("/v1/apps/456", { data: resource("apps", "456", { bundleId: "example.app" }) });
    pages.set("/v1/apps/456/subscriptionGroups", { data: [resource("subscriptionGroups", "other")] });
    await expect(loader(env, new Set(["subscription"]))).rejects.toMatchObject({ code: "CATALOG_SCOPE_MISMATCH" });
  });

  it("retains scheduled offers as facts but never treats expired, future or paid offers as a current free trial", async () => {
    pages.set("/v1/subscriptions/s2/introductoryOffers", { data: [
      offer("expired", "2026-09-01", "2026-10-13"),
      offer("future", "2026-10-15", null),
      offer("paid", null, null, "PAY_AS_YOU_GO"),
    ] });
    const catalog = await loader(env, new Set(["subscription"]));
    expect(catalog.products[1].introductory_offers).toHaveLength(3);
    expect(catalog.products[1].has_free_trial).toBe(false);
  });

  it("does not convert missing offer territory or period into a valid trial", async () => {
    const missing = offer("incomplete", null, null);
    delete (missing as Partial<typeof missing>).relationships;
    pages.set("/v1/subscriptions/s2/introductoryOffers", { data: [missing] });
    await expect(loader(env, new Set(["subscription"]))).rejects.toMatchObject({ code: "CATALOG_INVALID_RESPONSE" });
  });

  it("keeps one-time reading independent of subscription-group configuration", async () => {
    const catalog = await loader({ ...env, APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID: undefined }, new Set(["non_consumable"]));
    expect(catalog.products.map((p) => p.product_id)).toEqual(["lifetime"]);
    expect(requested.some((url) => url.includes("subscriptionGroups"))).toBe(false);
    pages.set("/v1/apps/456/inAppPurchasesV2", { data: [resource("inAppPurchases", "life", { productId: "lifetime", inAppPurchaseType: "CONSUMABLE", state: "APPROVED" })] });
    await expect(loader(env, new Set(["non_consumable"]))).rejects.toMatchObject({ code: "CATALOG_INVALID_RESPONSE" });
  });
});
