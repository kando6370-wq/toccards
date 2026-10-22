import { approvedAppleProducts } from "../entitlements/apple-product-policy";
import { writeProductAdmission } from "./product-admission";
import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { AdminBindings } from "../admin/routes";
import type { Env } from "../env";
import { createAppleCatalogLoader, validateCatalogReferences, type CatalogLoader } from "./catalog";
import {
  errorOutcome, isPageType, isRecord, parseDisplayConfig, payloadHash, referencedProducts,
  subscriptionScope, SubscriptionConfigError, type DisplayConfig, type Outcome, type ProductType,
} from "./model";
import {
  productAdmission, readActiveConfig, readConfig, readConfigList, readMutation,
  replayOutcome, writeMutation, type MutationCommand,
} from "./store";

const REQUEST_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CONFIG_ID = /^[0-9A-HJKMNP-TV-Z]{26}$/;
const MAX_BODY_BYTES = 256 * 1024;

type Dependencies = { loadCatalog?: CatalogLoader };

export function createSubscriptionConfigAdminRoutes(dependencies: Dependencies = {}): Hono<AdminBindings> {
  const routes = new Hono<AdminBindings>();
  const loadCatalog = dependencies.loadCatalog ?? createAppleCatalogLoader();
  // Child wildcard middleware must not change unrelated /admin endpoints.
  for (const path of ["/subscription-products", "/subscription-products/*", "/subscription-configs", "/subscription-configs/*", "/subscription-config-mutations/*"]) {
    routes.use(path, async (c, next) => {
      c.header("Cache-Control", "no-store");
      if (!c.get("admin")) return send(c, errorOutcome("UNAUTHORIZED", "Unauthorized.", 401));
      await next();
    });
    routes.use(path, bodyLimit({ maxSize: MAX_BODY_BYTES, onError: (c) => send(c,
      errorOutcome("VALIDATION_ERROR", "Configuration request exceeds the transport size limit.", 413)) }));
  }
  routes.onError((error, c) => send(c, unavailable(error)));

  routes.get("/subscription-products", async (c) => {
    subscriptionScope(c.env);
    const type = c.req.query("type");
    if (type !== "subscription" && type !== "non_consumable") return send(c, errorOutcome("VALIDATION_ERROR", "Choose a product type.", 422));
    const catalog = await loadCatalog(c.env, new Set([type]));
    const admission = await productAdmission(c.env, catalog.products);
    return c.json({ success: true, data: { ...catalog, scope: subscriptionScope(c.env), environment: c.env.APP_ENVIRONMENT, can_approve: c.get("admin").role === "super_admin", products: catalog.products.map((product, i) => ({
      ...product, admission: { admitted: admission[i].admitted, reasons: admission[i].reasons, singular_event_name: admission[i].singular_event_name },
    })) } });
  });
  routes.post("/subscription-products/admit", async (c) => {
    if (c.get("admin").role !== "super_admin") return send(c, errorOutcome("FORBIDDEN", "Only a super administrator can admit products.", 403));
    const scope = subscriptionScope(c.env);
    let input: unknown;
    try { input = await c.req.json(); } catch { return send(c, errorOutcome("VALIDATION_ERROR", "Invalid JSON.", 422)); }
    if (!isRecord(input) || typeof input.request_id !== "string" || !REQUEST_ID.test(input.request_id)) {
      return send(c, errorOutcome("VALIDATION_ERROR", "A UUID v4 request_id is required.", 422));
    }
    const requestId = input.request_id.toLowerCase();
    const adminId = c.get("admin").admin_id;
    const hash = await payloadHash({ kind: "admit", input: { ...input, request_id: requestId } });
    const previous = await readMutation(c.env.DB, scope, requestId);
    if (previous) return send(c, replayOutcome(previous, adminId, hash));
    let failure: Outcome | null = null;
    let product = null;
    const type = input.product_type;
    const eventName = typeof input.singular_event_name === "string" ? input.singular_event_name : "";
    if (input.expected_scope !== scope) failure = errorOutcome("ADMISSION_SCOPE_CONFLICT", "The selected environment or App changed. Reload the catalog.", 409);
    else if (typeof input.product_id !== "string" || input.product_id.length > 200 ||
        !["subscription", "non_consumable"].includes(type as string) ||
        input.acknowledge_legacy_restore_limit !== true) {
      failure = errorOutcome("VALIDATION_ERROR", "Product, revenue mapping and explicit legacy restore acknowledgement are required.", 422);
    } else if (!/^[A-Za-z][A-Za-z0-9_]{0,31}$/.test(eventName)) {
      failure = errorOutcome("VALIDATION_ERROR", "Singular revenue event names must be 1-32 characters, start with an ASCII letter and contain only letters, digits or underscores.", 422);
    } else {
      try {
        const catalog = await loadCatalog(c.env, new Set([type as ProductType]));
        product = catalog.products.find((p) => p.product_id === input.product_id && p.product_type === type) ?? null;
        if (!product) failure = errorOutcome("VALIDATION_ERROR", "Product is not in this App's approved catalog scope.", 422);
      } catch (error) { failure = unavailable(error); }
    }
    return send(c, await writeProductAdmission(c.env, scope, adminId, requestId, hash, product, eventName, failure));
  });
  routes.get("/subscription-configs", async (c) => c.json({ success: true,
    data: await readConfigList(c.env.DB, subscriptionScope(c.env)) }));
  routes.get("/subscription-configs/:id", async (c) => {
    const row = await readConfig(c.env.DB, subscriptionScope(c.env), c.req.param("id"));
    if (!row) return send(c, errorOutcome("CONFIG_NOT_FOUND", "Configuration not found.", 404));
    const { scope: _scope, ...data } = row;
    return c.json({ success: true, data });
  });
  routes.get("/subscription-config-mutations/:request_id", async (c) => {
    const requestId = c.req.param("request_id");
    if (!REQUEST_ID.test(requestId)) return send(c, errorOutcome("VALIDATION_ERROR", "Invalid request ID.", 422));
    const row = await readMutation(c.env.DB, subscriptionScope(c.env), requestId.toLowerCase());
    if (!row) return c.json({ success: true, data: { request_id: requestId.toLowerCase(), status: "unknown" } });
    if (row.admin_id !== c.get("admin").admin_id) return send(c, errorOutcome("FORBIDDEN", "Operation belongs to another administrator.", 403));
    const outcome = replayOutcome(row, row.admin_id);
    return c.json({ success: true, data: { request_id: requestId.toLowerCase(),
      status: row.http_status === null ? "unknown" : outcome.status < 400 ? "succeeded" : "failed",
      http_status: row.http_status, response: row.response } });
  });

  const save = async (c: Context<AdminBindings>, kind: "create" | "save" | "activate") => {
    const scope = subscriptionScope(c.env);
    let input: unknown;
    try { input = await c.req.json(); } catch { return send(c, errorOutcome("VALIDATION_ERROR", "Invalid JSON.", 422)); }
    if (!isRecord(input) || typeof input.request_id !== "string" || !REQUEST_ID.test(input.request_id)) {
      return send(c, errorOutcome("VALIDATION_ERROR", "A UUID v4 request_id is required.", 422));
    }
    const requestId = input.request_id.toLowerCase();
    const adminId = c.get("admin").admin_id;
    const target = kind === "create" ? null : kind === "save" ? c.req.param("id") : c.req.param("page_type");
    const hash = await payloadHash({ kind, target, input: { ...input, request_id: requestId } });
    const previous = await readMutation(c.env.DB, scope, requestId);
    if (previous) return send(c, replayOutcome(previous, adminId, hash));

    let command: MutationCommand;
    let failure: Outcome | null = null;
    const invalid = () => errorOutcome("VALIDATION_ERROR", "Invalid mutation fields or expected revision.", 422);
    const allowedFields = kind === "create" ? ["request_id", "config"] : kind === "save"
      ? ["request_id", "expected_revision", "config"]
      : ["request_id", "config_id", "expected_active_revision", "expected_config_revision"];
    if (Object.keys(input).some((key) => !allowedFields.includes(key))) failure = invalid();
    if (kind === "activate") {
      if (!isPageType(target)) return send(c, invalid());
      const id = input.config_id;
      if ((id !== null && (typeof id !== "string" || !CONFIG_ID.test(id))) ||
          !safeRevision(input.expected_active_revision, 0) ||
          (id !== null && !safeRevision(input.expected_config_revision, 1)) ||
          (id === null && input.expected_config_revision !== undefined && input.expected_config_revision !== null)) failure = invalid();
      command = { kind, page_type: target, config_id: typeof id === "string" ? id : null,
        expected_active_revision: safeRevision(input.expected_active_revision, 0) ? input.expected_active_revision as number : 0,
        expected_config_revision: safeRevision(input.expected_config_revision, 1) ? input.expected_config_revision as number : null, config: null };
      if (!failure && command.config_id) {
        const row = await readConfig(c.env.DB, scope, command.config_id);
        if (!row || row.page_type !== target) failure = errorOutcome("CONFIG_NOT_FOUND", "Configuration not found for this page type.", 404);
        else if (row.revision !== command.expected_config_revision) failure = errorOutcome("CONFIG_CONFLICT", "Configuration changed. Reload it before activation.", 409);
        else {
          const parsed = parseDisplayConfig(row.body);
          if (!parsed.config) failure = errorOutcome("VALIDATION_ERROR", "Stored configuration is invalid.", 422, parsed.issues);
          command.config = parsed.config;
        }
      }
    } else {
      const parsed = parseDisplayConfig(input.config);
      if (!parsed.config) failure = errorOutcome("VALIDATION_ERROR", "Configuration validation failed.", 422, parsed.issues);
      if (kind === "save") {
        if (!target || !CONFIG_ID.test(target) || !safeRevision(input.expected_revision, 1)) failure = invalid();
        command = { kind, id: target ?? "", expected_revision: safeRevision(input.expected_revision, 1) ? input.expected_revision as number : 0, config: parsed.config };
      } else command = { kind, config: parsed.config };
    }
    if (!failure && command.config) {
      try {
        const types = new Set<ProductType>(referencedProducts(command.config).map((p) => p.product_type));
        const catalog = await loadCatalog(c.env, types);
        const issues = validateCatalogReferences(command.config, catalog);
        if (issues.length) failure = errorOutcome("VALIDATION_ERROR", "Apple product references are invalid.", 422, issues);
      } catch (error) { failure = unavailable(error); }
    }
    return send(c, await writeMutation(c.env, scope, adminId, requestId, hash, command, failure));
  };
  routes.post("/subscription-configs", (c) => save(c, "create"));
  routes.put("/subscription-configs/:id", (c) => save(c, "save"));
  routes.put("/subscription-configs/active/:page_type", (c) => save(c, "activate"));
  return routes;
}

export function createSubscriptionDisplayRoutes(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();
  routes.onError((error, c) => send(c, unavailable(error)));
  routes.get("/subscription-supported-products", async (c) => {
    c.header("Cache-Control", "no-store");
    const platform = c.req.query("platform") ?? "ios";
    if (!["ios", "google"].includes(platform)) return send(c, errorOutcome("VALIDATION_ERROR", "Invalid platform.", 422));
    if (platform === "google") return c.json({ success: true, data: { products: [] } });
    return c.json({ success: true, data: { scope: subscriptionScope(c.env), products: (await approvedAppleProducts(c.env))
      .map(({ approved_by: _by, approved_at: _at, ...p }) => p) } });
  });
  routes.get("/subscription-display-config", async (c) => {
    c.header("Cache-Control", "no-store");
    const type = c.req.query("type");
    const platform = c.req.query("platform") ?? "ios";
    if (!isPageType(type) || !["ios", "google"].includes(platform)) return send(c, errorOutcome("VALIDATION_ERROR", "Invalid page type or platform.", 422));
    if (platform === "google") return c.json({ success: true, data: null });
    const row = await readActiveConfig(c.env.DB, subscriptionScope(c.env), type);
    if (!row) return c.json({ success: true, data: null });
    const parsed = parseDisplayConfig(row.body);
    if (!parsed.config) return send(c, errorOutcome("SUBSCRIPTION_CONFIG_UNAVAILABLE", "Active configuration is invalid.", 503));
    const admission = await productAdmission(c.env, referencedProducts(parsed.config, false));
    if (admission.some((product) => !product.admitted)) return send(c, errorOutcome("SUBSCRIPTION_CONFIG_UNAVAILABLE", "Active products are no longer admitted.", 503));
    return c.json({ success: true, data: publicConfig(row.id, row.revision, parsed.config) });
  });
  return routes;
}

function publicConfig(id: string, revision: number, config: DisplayConfig) {
  const { name: _name, ...display } = config;
  return { ...display, config_id: id, revision,
    trial_toggle_text: config.trial_enabled ? config.trial_toggle_text : "",
    skus: config.skus.map((sku) => ({ ...sku, trial: config.trial_enabled && sku.trial?.product_id ? sku.trial : null })) };
}
function safeRevision(value: unknown, min: number): boolean { return Number.isSafeInteger(value) && (value as number) >= min; }
function unavailable(error: unknown): Outcome {
  if (error instanceof SubscriptionConfigError) return errorOutcome(error.code, error.message, error.status);
  console.error("subscription_config_unavailable");
  return errorOutcome("SUBSCRIPTION_CONFIG_UNAVAILABLE", "Subscription configuration is temporarily unavailable.", 503);
}
function send<E extends { Bindings: Env }>(c: Context<E>, outcome: Outcome) {
  return c.json(outcome.body, outcome.status as ContentfulStatusCode);
}
