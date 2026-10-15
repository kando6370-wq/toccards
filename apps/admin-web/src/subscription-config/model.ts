export type PageType = "page" | "modal";
export type ProductType = "subscription" | "non_consumable";
export type CopyFields = {
  name: string; subtitle: string; badge: string; price_note: string;
  cta: string; billing_note_mode: "custom" | "auto"; billing_note: string;
};
export type TrialOverride = CopyFields & { product_id: string };
export type DisplaySku = CopyFields & {
  product_id: string; product_type: ProductType; price_mode: "actual" | "weekly";
  is_default: boolean; trial: TrialOverride | null;
};
export type DisplayConfig = {
  schema_version: 1; name: string; page_type: PageType; trial_enabled: boolean;
  trial_toggle_text: string; cta: string; close_delay_seconds: number; skus: DisplaySku[];
};
export type ConfigRecord = {
  id: string; page_type: PageType; revision: number; body: DisplayConfig;
  enabled: boolean; updated_by: string; updated_at: string;
};
export type ActiveSelection = { page_type: PageType; config_id: string | null; active_revision: number };
export type ConfigList = { items: ConfigRecord[]; active: ActiveSelection[] };
export type CatalogProduct = {
  product_id: string; reference_name: string; product_type: ProductType;
  subscription_group_id: string | null; period: string | null; group_level: number | null;
  has_free_trial: boolean; state: string;
  admission: { admitted: boolean; reasons: string[] };
};
export type Catalog = { products: CatalogProduct[]; subscription_group_id: string | null };
export type CatalogState = { status: "idle" | "loading" | "loaded" | "error"; products: CatalogProduct[]; error?: string };
export type Catalogs = Record<ProductType, CatalogState>;
export type FieldIssue = { path: string; message: string };
export type EditorSku = DisplaySku & { key: string; needs_trial_repair: boolean };
export type EditorConfig = Omit<DisplayConfig, "page_type" | "close_delay_seconds" | "skus"> & {
  page_type: PageType | ""; close_delay_seconds: number | null; skus: EditorSku[];
};
export type Editor = { id: string | null; revision: number; enabled: boolean; body: EditorConfig };
export type SubscriptionRequest = <T>(path: string, init?: { method?: string; body?: unknown; signal?: AbortSignal }) => Promise<T>;

export const MAX_DISPLAY_SKUS = 3;
export const PAGE_LABELS: Record<PageType, string> = { page: "订阅页", modal: "订阅大弹窗" };
export const emptyCopy = (name = ""): CopyFields => ({ name, subtitle: "", badge: "", price_note: "", cta: "", billing_note_mode: "custom", billing_note: "" });
export const blankSku = (key: string): EditorSku => ({ ...emptyCopy(), key, needs_trial_repair: false,
  product_id: "", product_type: "subscription", price_mode: "actual", is_default: false, trial: null });
export function newEditor(key: string): Editor {
  return { id: null, revision: 0, enabled: false, body: { schema_version: 1, name: "", page_type: "",
    trial_enabled: false, trial_toggle_text: "", cta: "", close_delay_seconds: 0, skus: [blankSku(key)] } };
}
export function editorFromRecord(record: ConfigRecord, key: () => string): Editor {
  if (!record?.id || record.body?.schema_version !== 1 || !Array.isArray(record.body.skus)) throw new Error("配置详情格式异常，请重新加载。");
  const body = structuredClone(record.body);
  return { id: record.id, revision: record.revision, enabled: record.enabled, body: { ...body,
    cta: typeof body.cta === "string" ? body.cta : "",
    skus: body.skus.map((sku) => ({ ...emptyCopy(), ...sku, cta: typeof sku.cta === "string" ? sku.cta : "",
      trial: sku.trial ? { ...emptyCopy(), ...sku.trial } : null, key: key(), needs_trial_repair: false })),
  } };
}
export function toDisplayConfig(body: EditorConfig): DisplayConfig {
  return { ...body, page_type: body.page_type as PageType, close_delay_seconds: body.close_delay_seconds as number,
    skus: body.skus.map(({ key: _key, needs_trial_repair: _repair, ...sku }) => sku) };
}
export function productMap(catalogs: Catalogs): Map<string, CatalogProduct> {
  return new Map(Object.values(catalogs).flatMap((catalog) => catalog.products).map((product) => [product.product_id, product]));
}
export function productLabel(product: CatalogProduct): string {
  return product.product_id + (product.reference_name ? " · " + product.reference_name : "") + (product.has_free_trial ? " · 带免费试用" : "");
}
export function trialPairValid(source: CatalogProduct | undefined, target: CatalogProduct | undefined): boolean {
  return !!source && !!target && source.product_id !== target.product_id && source.product_type === "subscription" &&
    !source.has_free_trial && target.product_type === "subscription" && target.has_free_trial && !!source.subscription_group_id &&
    source.subscription_group_id === target.subscription_group_id && !!source.period && source.period === target.period &&
    !!source.group_level && source.group_level === target.group_level;
}
export function availableProducts(body: EditorConfig, index: number, products: CatalogProduct[], trial = false): CatalogProduct[] {
  const sku = body.skus[index];
  const occupied = new Set(body.skus.flatMap((item, i) => [
    ...(!trial && i === index ? [] : [item.product_id]),
    ...(trial && i === index ? [] : [item.trial?.product_id ?? ""]),
  ]).filter(Boolean));
  const source = products.find((product) => product.product_id === sku.product_id);
  return products.filter((product) => !occupied.has(product.product_id) &&
    (trial ? trialPairValid(source, product) : product.product_type === sku.product_type));
}
export function changeProduct(sku: EditorSku, productId: string, products: Map<string, CatalogProduct>, type = sku.product_type): EditorSku {
  const changedType = type !== sku.product_type;
  const product = products.get(productId);
  const invalidTrial = changedType || (!!sku.trial?.product_id && !trialPairValid(product, products.get(sku.trial.product_id)));
  return { ...sku, product_type: type, product_id: changedType ? "" : productId,
    price_mode: type === "non_consumable" || (product && !["ONE_WEEK", "ONE_MONTH", "THREE_MONTHS", "ONE_YEAR"].includes(product.period ?? "")) ? "actual" : sku.price_mode,
    trial: invalidTrial && sku.trial ? { ...sku.trial, product_id: "" } : sku.trial,
    needs_trial_repair: sku.needs_trial_repair || (!!sku.trial?.product_id && invalidTrial) };
}
export function unlinkTrial(body: EditorConfig, key: string): EditorConfig {
  const removed = body.skus.find((sku) => sku.key === key);
  const skus = body.skus.map((sku) => sku.key === key ? { ...sku, needs_trial_repair: false,
    trial: sku.trial ? { ...sku.trial, product_id: "" } : null } : sku);
  return { ...body, skus, trial_enabled: (removed?.trial?.product_id || removed?.needs_trial_repair) && !skus.some((sku) => sku.trial?.product_id) ? false : body.trial_enabled };
}
export function removeSku(body: EditorConfig, key: string): EditorConfig {
  const withoutRelation = unlinkTrial(body, key);
  return { ...withoutRelation, skus: withoutRelation.skus.filter((sku) => sku.key !== key) };
}
export function moveSku(body: EditorConfig, index: number, delta: -1 | 1): EditorConfig {
  const target = index + delta;
  if (target < 0 || target >= body.skus.length) return body;
  const skus = [...body.skus]; [skus[index], skus[target]] = [skus[target], skus[index]];
  return { ...body, skus };
}

export function validateEditor(body: EditorConfig, catalogs: Catalogs, enabled = false): FieldIssue[] {
  const issues: FieldIssue[] = [];
  const issue = (path: string, message: string) => { issues.push({ path, message }); };
  const text = (value: string, path: string, label: string, max: number, required = false) => {
    if (required && !value.trim()) issue(path, label + "不能为空");
    if (value.length > max) issue(path, label + "不能超过 " + max + " 字符");
  };
  const cta = (value: string, path: string) => {
    text(value, path, "订阅按钮文案", 100);
    if (/[{}]/.test(value)) issue(path, "按钮仅支持纯文本，不允许变量或花括号");
  };
  const copy = (value: CopyFields, path: string) => {
    text(value.name, path + "name", "商品展示名称", 100, true);
    text(value.subtitle, path + "subtitle", "副文案", 300);
    text(value.badge, path + "badge", "角标", 100);
    text(value.price_note, path + "price_note", "价格说明", 200);
    cta(value.cta, path + "cta");
    if (value.billing_note_mode === "custom") text(value.billing_note, path + "billing_note", "自定义说明", 500);
    for (const key of ["subtitle", "badge", "price_note", ...(value.billing_note_mode === "custom" ? ["billing_note"] : [])] as const) {
      if ([...value[key as keyof CopyFields].matchAll(/\{([^}]+)\}/g)].some((m) => m[1] !== "price")) issue(path + key, "说明只支持 {price} 变量");
    }
  };
  text(body.name, "name", "配置名称", 100, true);
  if (!body.page_type) issue("page_type", "请选择页面类型");
  cta(body.cta, "cta");
  if (!Number.isSafeInteger(body.close_delay_seconds) || (body.close_delay_seconds ?? -1) < 0) issue("close_delay_seconds", "关闭延迟必须是非负安全整数");
  if (!body.skus.length) issue("skus", "至少保留一个页面展示 SKU");
  if (body.skus.length > MAX_DISPLAY_SKUS) issue("skus", `页面展示 SKU 最多只能配置 ${MAX_DISPLAY_SKUS} 个`);
  if (body.skus.filter((sku) => sku.is_default).length !== 1) issue("skus", "必须且只能指定一个默认 SKU");
  if (body.trial_enabled) {
    text(body.trial_toggle_text, "trial_toggle_text", "试用开关文案", 100, true);
    if (!body.skus.some((sku) => sku.trial?.product_id)) issue("trial_enabled", "启用切换时至少配置一组有效试用关系");
  }
  const products = productMap(catalogs);
  const occupied = new Set<string>();
  body.skus.forEach((sku, index) => {
    const path = "skus." + index + ".";
    copy(sku, path);
    for (const [field, id] of [["product_id", sku.product_id], ["trial.product_id", sku.trial?.product_id ?? ""]]) {
      if (!id) continue;
      if (occupied.has(id)) issue(path + field, "该 Product ID 已在本组卡片或试用关系中使用");
      occupied.add(id);
    }
    const catalog = catalogs[sku.product_type];
    const product = products.get(sku.product_id);
    if (!sku.product_id) issue(path + "product_id", "请选择 Product ID");
    else if (catalog.status === "loaded" && (!product || product.product_type !== sku.product_type)) issue(path + "product_id", "当前商品已不在可配置范围，请重新选择");
    if (sku.price_mode === "weekly" && (sku.product_type === "non_consumable" || (catalog.status === "loaded" && !["ONE_WEEK", "ONE_MONTH", "THREE_MONTHS", "ONE_YEAR"].includes(product?.period ?? "")))) issue(path + "price_mode", "该商品周期不支持折算周均参考价");
    if (enabled && catalog.status === "loaded" && product && !product.admission.admitted) issue(path + "product_id", "商品未完成系统准入，不能保存到生效配置");
    if (body.trial_enabled && sku.needs_trial_repair) issue(path + "trial.product_id", "商品已变化，请重新关联试用或明确解除原关系");
    if (sku.trial?.product_id) {
      const target = products.get(sku.trial.product_id);
      if (catalogs.subscription.status === "loaded" && !trialPairValid(product, target)) issue(path + "trial.product_id", "试用目标须同组、同周期、同等级，源不带试用且目标有免费试用");
      if (body.trial_enabled) {
        copy(sku.trial, path + "trial.");
        if (enabled && catalogs.subscription.status === "loaded" && target && !target.admission.admitted) issue(path + "trial.product_id", "试用目标未完成系统准入，不能保存到生效配置");
      }
    }
  });
  return issues;
}

export function admissionMessage(reasons: string[]): string {
  const labels: Record<string, string> = { DISPLAY_APPROVAL_REQUIRED: "展示接入尚未确认", NOT_IN_ENTITLEMENT_ALLOWLIST: "未加入权益白名单", ENTITLEMENT_MAPPING_UNAVAILABLE: "权益映射未就绪" };
  return reasons.map((reason) => labels[reason] ?? "系统准入未完成").join("、");
}
export function subscriptionErrorMessage(error: unknown): string {
  const code = error && typeof error === "object" && "code" in error ? String(error.code) : "";
  const labels: Record<string, string> = {
    CONFIG_CONFLICT: "配置或生效状态已被其他人修改。请重新读取后再操作，当前输入已保留。",
    ACTIVE_PAGE_TYPE_IMMUTABLE: "该配置已经生效，请先在列表关闭后再修改页面类型。",
    PRODUCT_NOT_ADMITTED: "商品尚未完成系统准入，不能启用或保存到生效配置。",
    CATALOG_NOT_CONFIGURED: "Apple 商品目录尚未配置，请联系接入负责人。",
    CATALOG_UNAVAILABLE: "Apple 商品读取失败，请稍后重试。",
    CATALOG_INVALID_RESPONSE: "Apple 商品信息不完整，暂时无法校验。",
    CATALOG_SCOPE_MISMATCH: "Apple App 或订阅组配置不匹配，请联系接入负责人。",
    SUBSCRIPTION_CONFIG_UNAVAILABLE: "订阅配置服务暂不可用，请稍后重试。",
    CONFIG_NOT_FOUND: "配置已不存在或不属于当前环境，请返回列表刷新。",
    IDEMPOTENCY_CONFLICT: "原请求与当前操作不一致，请先核对原操作结果。",
    FORBIDDEN: "当前账号无法核对或执行该操作，请使用原操作账号。",
    UNAUTHORIZED: "登录已失效，请重新登录后核对操作结果。",
    VALIDATION_ERROR: "配置校验未通过，请按字段提示修改。",
  };
  return labels[code] ?? (error instanceof Error ? error.message : "请求失败，请稍后重试。");
}
