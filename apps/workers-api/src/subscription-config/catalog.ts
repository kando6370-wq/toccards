import type { Env } from "../env";
import {
  configuredIds, isRecord, SubscriptionConfigError,
  type DisplayConfig, type FieldIssue, type ProductType,
} from "./model";

export type IntroductoryOffer = {
  territory: string;
  mode: string;
  duration: string;
  periods: number;
  start_date: string | null;
  end_date: string | null;
};
export type CatalogProduct = {
  product_id: string;
  reference_name: string;
  product_type: ProductType;
  subscription_group_id: string | null;
  period: string | null;
  group_level: number | null;
  state: string;
  has_free_trial: boolean;
  introductory_offers: IntroductoryOffer[];
};
export type ProductCatalog = {
  app_id: string;
  bundle_id: string;
  subscription_group_id: string | null;
  products: CatalogProduct[];
};
export type CatalogLoader = (env: Env, types: ReadonlySet<ProductType>) => Promise<ProductCatalog>;

type AppleResource = {
  id: string;
  type: string;
  attributes: Record<string, unknown>;
  relationships?: Record<string, unknown>;
};
const APPLE_ORIGIN = "https://api.appstoreconnect.apple.com";
const CATALOG_DEADLINE_MS = 10_000;
const WEEKLY_PERIODS = new Set(["ONE_WEEK", "ONE_MONTH", "THREE_MONTHS", "ONE_YEAR"]);

export function createAppleCatalogLoader(dependencies: { fetch?: typeof fetch; now?: () => Date } = {}): CatalogLoader {
  return async (env, types) => {
    const appId = env.APP_STORE_CONNECT_APP_ID?.trim();
    const bundleId = env.APPLE_IAP_BUNDLE_ID?.trim();
    const groupId = env.APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID?.trim();
    if (!appId || !/^\d+$/.test(appId) || !bundleId ||
        (types.has("subscription") && (!groupId || !/^\d+$/.test(groupId)))) {
      throw new SubscriptionConfigError("CATALOG_NOT_CONFIGURED", "Apple catalog scope is not configured.");
    }
    const now = dependencies.now?.() ?? new Date();
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), CATALOG_DEADLINE_MS);
    try {
      const token = await createCatalogToken(env, now);
      const read = async (url: URL): Promise<Record<string, unknown>> => {
        const response = await (dependencies.fetch ?? fetch)(url.toString(), {
          method: "GET", headers: { Authorization: "Bearer " + token, Accept: "application/json" },
          redirect: "manual", signal: abort.signal,
        });
        if (!response.ok) throw new SubscriptionConfigError("CATALOG_UNAVAILABLE", "Apple catalog could not be read.");
        const body: unknown = await response.json();
        if (!isRecord(body) || body.errors) throw new SubscriptionConfigError("CATALOG_INVALID_RESPONSE", "Apple catalog returned invalid data.");
        return body;
      };
      const list = async (path: string): Promise<AppleResource[]> => {
        let url: URL | null = new URL(path, APPLE_ORIGIN);
        const expectedPath = url.pathname;
        const seen = new Set<string>();
        const ids = new Set<string>();
        const items: AppleResource[] = [];
        while (url) {
          if (url.origin !== APPLE_ORIGIN || url.pathname !== expectedPath || url.username || url.password || url.hash || seen.has(url.href) || seen.size >= 100) {
            throw new SubscriptionConfigError("CATALOG_INVALID_RESPONSE", "Apple pagination is invalid.");
          }
          seen.add(url.href);
          const page = await read(url);
          if (!Array.isArray(page.data)) throw new SubscriptionConfigError("CATALOG_INVALID_RESPONSE", "Apple catalog list is invalid.");
          for (const item of page.data) {
            const resource = parseResource(item);
            const key = resource.type + ":" + resource.id;
            if (ids.has(key)) throw new SubscriptionConfigError("CATALOG_INVALID_RESPONSE", "Apple returned duplicate resources.");
            ids.add(key);
            items.push(resource);
          }
          const links = page.links;
          if (links !== undefined && links !== null && !isRecord(links)) throw new SubscriptionConfigError("CATALOG_INVALID_RESPONSE", "Apple pagination is invalid.");
          const next = isRecord(links) ? links.next : null;
          if (next !== null && next !== undefined && typeof next !== "string") throw new SubscriptionConfigError("CATALOG_INVALID_RESPONSE", "Apple pagination is invalid.");
          url = next ? new URL(next, url) : null;
        }
        return items;
      };
      const app = parseResource((await read(new URL("/v1/apps/" + appId + "?fields[apps]=bundleId", APPLE_ORIGIN))).data);
      if (app.type !== "apps" || app.id !== appId || app.attributes.bundleId !== bundleId) {
        throw new SubscriptionConfigError("CATALOG_SCOPE_MISMATCH", "Configured Apple App does not match this API.");
      }
      const products: CatalogProduct[] = [];
      if (types.has("subscription")) {
        const groups = await list("/v1/apps/" + appId + "/subscriptionGroups?limit=200");
        if (!groups.some((group) => group.type === "subscriptionGroups" && group.id === groupId)) {
          throw new SubscriptionConfigError("CATALOG_SCOPE_MISMATCH", "Subscription group does not belong to this App.");
        }
        const subscriptions = await list("/v1/subscriptionGroups/" + groupId + "/subscriptions?limit=200");
        for (const subscription of subscriptions) {
          if (subscription.type !== "subscriptions") invalidCatalog();
          const attributes = subscription.attributes;
          const period = requiredString(attributes.subscriptionPeriod);
          const level = attributes.groupLevel;
          if (!Number.isSafeInteger(level) || (level as number) < 1) invalidCatalog();
          const resources = await list("/v1/subscriptions/" + encodeURIComponent(subscription.id) + "/introductoryOffers?include=territory&limit=200");
          const offers = resources.map(parseOffer);
          // Catalog classification only. StoreKit must still confirm territory and user eligibility.
          const day = now.toISOString().slice(0, 10);
          products.push({
            product_id: requiredString(attributes.productId), reference_name: optionalString(attributes.name),
            product_type: "subscription", subscription_group_id: groupId!, period, group_level: level as number,
            state: requiredString(attributes.state), introductory_offers: offers,
            has_free_trial: offers.some((offer) => offer.mode === "FREE_TRIAL" &&
              (!offer.start_date || offer.start_date <= day) && (!offer.end_date || offer.end_date >= day)),
          });
        }
      }
      if (types.has("non_consumable")) {
        const lifetimeIds = configuredIds(env.SUBSCRIPTION_LIFETIME_PRODUCT_IDS);
        if (!env.SUBSCRIPTION_LIFETIME_PRODUCT_IDS?.trim()) {
          throw new SubscriptionConfigError("CATALOG_NOT_CONFIGURED", "Lifetime product scope is not configured.");
        }
        const purchases = await list("/v1/apps/" + appId + "/inAppPurchasesV2?filter[inAppPurchaseType]=NON_CONSUMABLE&limit=200");
        for (const purchase of purchases) {
          if (purchase.type !== "inAppPurchases") invalidCatalog();
          const id = requiredString(purchase.attributes.productId);
          if (!lifetimeIds.has(id)) continue;
          if (purchase.attributes.inAppPurchaseType !== "NON_CONSUMABLE") invalidCatalog();
          products.push({ product_id: id, reference_name: optionalString(purchase.attributes.name),
            product_type: "non_consumable", subscription_group_id: null, period: null, group_level: null,
            state: requiredString(purchase.attributes.state), has_free_trial: false, introductory_offers: [] });
        }
      }
      if (new Set(products.map((product) => product.product_id)).size !== products.length) invalidCatalog();
      return { app_id: appId, bundle_id: bundleId, subscription_group_id: groupId ?? null, products };
    } catch (error) {
      if (error instanceof SubscriptionConfigError) throw error;
      throw new SubscriptionConfigError("CATALOG_UNAVAILABLE", "Apple catalog could not be read.");
    } finally { clearTimeout(timer); }
  };
}

export function validateCatalogReferences(config: DisplayConfig, catalog: ProductCatalog): FieldIssue[] {
  const products = new Map(catalog.products.map((product) => [product.product_id, product]));
  const issues: FieldIssue[] = [];
  for (const [index, sku] of config.skus.entries()) {
    const path = "skus." + index;
    const source = products.get(sku.product_id);
    if (!source || source.product_type !== sku.product_type ||
        (source.product_type === "subscription" && source.subscription_group_id !== catalog.subscription_group_id)) {
      issues.push({ path: path + ".product_id", message: "Product is not in the configured Apple scope or type." });
    }
    if (sku.price_mode === "weekly" && (!source?.period || !WEEKLY_PERIODS.has(source.period))) {
      issues.push({ path: path + ".price_mode", message: "Weekly reference price is not defined for this period." });
    }
    if (sku.trial?.product_id) {
      const target = products.get(sku.trial.product_id);
      if (!source || !target || source.product_type !== "subscription" || source.has_free_trial ||
          target.product_type !== "subscription" || !target.has_free_trial ||
          !source.period || source.period !== target.period || !source.group_level || source.group_level !== target.group_level ||
          source.subscription_group_id !== catalog.subscription_group_id || target.subscription_group_id !== source.subscription_group_id) {
        issues.push({ path: path + ".trial.product_id", message: "Trial requires a non-trial source and free-trial target in the same group, period and level." });
      }
    }
  }
  return issues;
}

export async function createCatalogToken(env: Env, now: Date): Promise<string> {
  const keyId = env.APP_STORE_CONNECT_KEY_ID?.trim();
  const issuer = env.APP_STORE_CONNECT_ISSUER_ID?.trim();
  const pem = env.APP_STORE_CONNECT_PRIVATE_KEY;
  if (!keyId || !issuer || !pem) throw new SubscriptionConfigError("CATALOG_NOT_CONFIGURED", "App Store Connect team credentials are not configured.");
  try {
    const raw = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
    const bytes = Uint8Array.from(atob(raw), (char) => char.charCodeAt(0));
    const key = await crypto.subtle.importKey("pkcs8", bytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
    const iat = Math.floor(now.getTime() / 1000);
    const data = base64Url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }))) + "." +
      base64Url(new TextEncoder().encode(JSON.stringify({ iss: issuer, iat, exp: iat + 300, aud: "appstoreconnect-v1" })));
    const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(data));
    return data + "." + base64Url(new Uint8Array(signature));
  } catch { throw new SubscriptionConfigError("CATALOG_NOT_CONFIGURED", "App Store Connect signing configuration is invalid."); }
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function parseResource(value: unknown): AppleResource {
  if (!isRecord(value) || typeof value.id !== "string" || !value.id || typeof value.type !== "string" || !isRecord(value.attributes)) invalidCatalog();
  return value as AppleResource;
}
function parseOffer(resource: AppleResource): IntroductoryOffer {
  if (resource.type !== "subscriptionIntroductoryOffers") invalidCatalog();
  const a = resource.attributes;
  const territory = resource.relationships?.territory;
  const data = isRecord(territory) ? territory.data : null;
  if (!isRecord(data) || data.type !== "territories" || typeof data.id !== "string" || !data.id) invalidCatalog();
  if (!Number.isSafeInteger(a.numberOfPeriods) || (a.numberOfPeriods as number) < 1) invalidCatalog();
  return { territory: data.id as string, mode: requiredString(a.offerMode), duration: requiredString(a.duration),
    periods: a.numberOfPeriods as number, start_date: dateOrNull(a.startDate), end_date: dateOrNull(a.endDate) };
}
function dateOrNull(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value) invalidCatalog();
  return value as string;
}
function requiredString(value: unknown): string {
  if (typeof value !== "string" || !value.trim() || value !== value.trim()) invalidCatalog();
  return value as string;
}
function optionalString(value: unknown): string { return typeof value === "string" ? value : ""; }
function invalidCatalog(): never { throw new SubscriptionConfigError("CATALOG_INVALID_RESPONSE", "Apple catalog data is incomplete or invalid."); }
