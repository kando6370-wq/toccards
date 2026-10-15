import type { Env } from "../env";

export type PageType = "page" | "modal";
export type ProductType = "subscription" | "non_consumable";
export type MarketingCopy = {
  name: string;
  subtitle: string;
  badge: string;
  price_note: string;
  cta: string;
  billing_note_mode: "custom" | "auto";
  billing_note: string;
};
export type TrialOverride = MarketingCopy & { product_id: string };
export type DisplaySku = MarketingCopy & {
  product_id: string;
  product_type: ProductType;
  price_mode: "actual" | "weekly";
  is_default: boolean;
  trial: TrialOverride | null;
};
export type DisplayConfig = {
  schema_version: 1;
  name: string;
  page_type: PageType;
  trial_enabled: boolean;
  trial_toggle_text: string;
  cta: string;
  close_delay_seconds: number;
  skus: DisplaySku[];
};
export type FieldIssue = { path: string; message: string };
export type ErrorBody = {
  success: false;
  error: { code: string; message: string; fields?: FieldIssue[] };
};
export type Outcome = { status: number; body: Record<string, unknown> | ErrorBody };

export class SubscriptionConfigError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status = 503,
  ) { super(message); }
}

export function errorOutcome(code: string, message: string, status: number, fields?: FieldIssue[]): Outcome {
  return { status, body: { success: false, error: { code, message, ...(fields ? { fields } : {}) } } };
}

export function subscriptionScope(env: Env): string {
  const bundle = env.APPLE_IAP_BUNDLE_ID?.trim();
  if (!bundle || !["production", "development"].includes(env.APP_ENVIRONMENT ?? "")) {
    throw new SubscriptionConfigError("SUBSCRIPTION_CONFIG_UNAVAILABLE", "Subscription scope is not configured.");
  }
  return env.APP_ENVIRONMENT + ":" + bundle;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function isPageType(value: unknown): value is PageType {
  return value === "page" || value === "modal";
}

export function configuredIds(value: string | undefined): Set<string> {
  return new Set((value ?? "").split(",").map((id) => id.trim()).filter(Boolean));
}

export function referencedProducts(config: DisplayConfig, includeRetained = true): Array<{ product_id: string; product_type: ProductType }> {
  return config.skus.flatMap((sku) => [
    { product_id: sku.product_id, product_type: sku.product_type },
    ...(sku.trial?.product_id && (includeRetained || config.trial_enabled)
      ? [{ product_id: sku.trial.product_id, product_type: "subscription" as const }]
      : []),
  ]);
}

// Stable key order for idempotency; array order remains meaningful SKU order.
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonicalJson).join(",") + "]";
  if (isRecord(value)) return "{" + Object.keys(value).sort()
    .map((key) => JSON.stringify(key) + ":" + canonicalJson(value[key])).join(",") + "}";
  return JSON.stringify(value);
}

export async function payloadHash(value: unknown): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonicalJson(value)));
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function parseDisplayConfig(input: unknown): { config: DisplayConfig | null; issues: FieldIssue[] } {
  const issues: FieldIssue[] = [];
  const issue = (path: string, message: string) => { issues.push({ path, message }); };
  const fields = (value: Record<string, unknown>, allowed: string[], path: string) => {
    for (const key of Object.keys(value)) if (!allowed.includes(key)) issue(path + key, "Unknown field.");
  };
  const text = (value: unknown, path: string, max: number, required = false, validate = true): string => {
    if (value === undefined) value = "";
    if (typeof value !== "string") { issue(path, "Must be text."); return ""; }
    if (validate && (value.length > max || (required && !value.trim()))) issue(path, required ? "Required text or length limit exceeded." : "Length limit exceeded.");
    return value;
  };
  const cta = (value: unknown, path: string, validate = true) => {
    const result = text(value, path, 100, false, validate);
    if (validate && /[{}]/.test(result)) issue(path, "Button text must be plain text without braces.");
    return result;
  };
  const copyKeys = ["name", "subtitle", "badge", "price_note", "cta", "billing_note_mode", "billing_note"];
  const copy = (value: Record<string, unknown>, path: string, validate = true): MarketingCopy => {
    const mode = value.billing_note_mode ?? "custom";
    if (mode !== "custom" && mode !== "auto") issue(path + "billing_note_mode", "Unknown description mode.");
    const result: MarketingCopy = {
      name: text(value.name, path + "name", 100, true, validate),
      subtitle: text(value.subtitle, path + "subtitle", 300, false, validate),
      badge: text(value.badge, path + "badge", 100, false, validate),
      price_note: text(value.price_note, path + "price_note", 200, false, validate),
      cta: cta(value.cta, path + "cta", validate),
      billing_note_mode: mode === "auto" ? "auto" : "custom",
      billing_note: text(value.billing_note, path + "billing_note", 500, false, validate && mode === "custom"),
    };
    if (validate) for (const key of ["subtitle", "badge", "price_note", ...(mode === "custom" ? ["billing_note"] : [])] as const) {
      const value = result[key as keyof MarketingCopy];
      if ([...value.matchAll(/\{([^}]+)\}/g)].some((match) => match[1] !== "price")) issue(path + key, "Only {price} is supported in descriptions.");
    }
    return result;
  };
  if (!isRecord(input)) return { config: null, issues: [{ path: "config", message: "Configuration must be an object." }] };
  fields(input, ["schema_version", "name", "page_type", "trial_enabled", "trial_toggle_text", "cta", "close_delay_seconds", "skus"], "");
  if (input.schema_version !== 1) issue("schema_version", "Unsupported schema version.");
  if (!isPageType(input.page_type)) issue("page_type", "Choose page or modal.");
  if (typeof input.trial_enabled !== "boolean") issue("trial_enabled", "Must be boolean.");
  if (!Number.isSafeInteger(input.close_delay_seconds) || (input.close_delay_seconds as number) < 0) issue("close_delay_seconds", "Must be a nonnegative safe integer.");
  const config: DisplayConfig = {
    schema_version: 1,
    name: text(input.name, "name", 100, true),
    page_type: input.page_type === "modal" ? "modal" : "page",
    trial_enabled: input.trial_enabled === true,
    trial_toggle_text: text(input.trial_toggle_text, "trial_toggle_text", 100, input.trial_enabled === true, input.trial_enabled === true),
    cta: cta(input.cta, "cta"),
    close_delay_seconds: input.close_delay_seconds as number,
    skus: [],
  };
  if (!Array.isArray(input.skus) || input.skus.length === 0) issue("skus", "At least one SKU is required.");
  if (Array.isArray(input.skus) && input.skus.length > 3) issue("skus", "At most 3 display SKUs are allowed.");
  for (const [index, value] of (Array.isArray(input.skus) ? input.skus : []).entries()) {
    const path = "skus." + index + ".";
    if (!isRecord(value)) { issue(path, "SKU must be an object."); continue; }
    fields(value, [...copyKeys, "product_id", "product_type", "price_mode", "is_default", "trial"], path);
    const productId = text(value.product_id, path + "product_id", 255, true);
    if (productId !== productId.trim()) issue(path + "product_id", "Product ID cannot contain surrounding whitespace.");
    if (!["subscription", "non_consumable"].includes(value.product_type as string)) issue(path + "product_type", "Unknown product type.");
    if (!["actual", "weekly"].includes(value.price_mode as string)) issue(path + "price_mode", "Unknown price mode.");
    if (value.product_type === "non_consumable" && value.price_mode !== "actual") issue(path + "price_mode", "One-time products require actual price.");
    if (typeof value.is_default !== "boolean") issue(path + "is_default", "Must be boolean.");
    let trial: TrialOverride | null = null;
    if (value.trial !== undefined && value.trial !== null) {
      if (!isRecord(value.trial)) issue(path + "trial", "Trial override must be an object or null.");
      else {
        fields(value.trial, [...copyKeys, "product_id"], path + "trial.");
        const target = text(value.trial.product_id, path + "trial.product_id", 255);
        if (target !== target.trim()) issue(path + "trial.product_id", "Invalid Product ID.");
        trial = { product_id: target, ...copy(value.trial, path + "trial.", config.trial_enabled && !!target) };
      }
    }
    config.skus.push({ ...copy(value, path), product_id: productId,
      product_type: value.product_type === "non_consumable" ? "non_consumable" : "subscription",
      price_mode: value.price_mode === "weekly" ? "weekly" : "actual", is_default: value.is_default === true, trial });
  }
  if (config.skus.filter((sku) => sku.is_default).length !== 1) issue("skus", "Exactly one default SKU is required.");
  const ids = new Set<string>();
  for (const [i, sku] of config.skus.entries()) for (const id of [sku.product_id, sku.trial?.product_id].filter(Boolean) as string[]) {
    if (ids.has(id)) issue("skus." + i + ".product_id", "Display and trial Product IDs must be unique in this configuration.");
    ids.add(id);
  }
  if (config.trial_enabled && !config.skus.some((sku) => sku.trial?.product_id)) issue("skus", "Trial switching requires a relationship.");
  return { config: issues.length ? null : config, issues };
}
