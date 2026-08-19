// tcg-card D1 Schema —— 对齐 docs/releases/v1.0.0/03-data-api/data-model.md 与 v1.1.0 增量契约。
// 约定：账号主键为至少 6 位的全局数字 UID，其他业务主键为 ULID TEXT；时间戳 ISO8601 UTC TEXT；布尔 INTEGER(0/1)；资产金额 REAL，账单金额 INTEGER micros；枚举 TEXT（Workers 层校验）；多值 JSON 字符串 TEXT；软删 deleted_at；owner 多态 owner_type+owner_id；软引用不设 DB 级 FK。
import { sql } from "drizzle-orm";
import {
  check,
  index,
  integer,
  real,
  sqliteTable,
  text,
  unique,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";

// ── 卡牌基础数据源层 ──────────────────────────────────────────

export const cardsAll = sqliteTable(
  "cards_all",
  {
    productId: text("product_id").primaryKey(),
    gameId: integer("game_id").notNull(),
    game: text("game"),
    setName: text("set_name"),
    setCode: text("set_code"),
    setId: text("set_id"),
    number: text("number"),
    name: text("name"),
    rarity: text("rarity"),
    description: text("description"),
    productTypeName: text("product_type_name"),
    foilOnly: integer("foil_only").default(0),
    normalOnly: integer("normal_only").default(0),
    createdAt: text("created_at").default(sql`CURRENT_TIMESTAMP`),
    updatedAt: text("updated_at").default(sql`CURRENT_TIMESTAMP`),
    cardType: text("card_type"),
    fullType: text("full_type"),
    color: text("color"),
    convertedCost: text("converted_cost"),
    flavorText: text("flavor_text"),
    power: text("power"),
    powerNumber: text("power_number"),
    toughness: text("toughness"),
  },
  (t) => [
    index("idx_cards_all_game_id").on(t.gameId),
    index("idx_cards_all_game_product").on(t.gameId, t.productId),
    index("idx_cards_all_updated_product").on(
      sql`${t.updatedAt} DESC`,
      sql`${t.productId} ASC`,
    ),
    index("idx_cards_all_game_updated_product").on(
      sql`lower(${t.game})`,
      sql`${t.updatedAt} DESC`,
      sql`${t.productId} ASC`,
    ),
    index("idx_cards_all_game_set_updated_product").on(
      sql`lower(${t.game})`,
      sql`lower(${t.setCode})`,
      sql`${t.updatedAt} DESC`,
      sql`${t.productId} ASC`,
    ),
  ],
);

export const games = sqliteTable(
  "games",
  {
    id: integer("id"),
    gameId: real("game_id"),
    name: text("name"),
    totalCards: integer("total_cards"),
    imageSource: text("image_source"),
    imagesEnabled: integer("images_enabled"),
    createdAt: text("created_at"),
    load: integer("load"),
    searchSort: integer("search_sort").notNull().default(1000),
  },
  (t) => [index("idx_games_load_sort").on(t.load, t.searchSort, t.gameId)],
);

export const sets = sqliteTable(
  "sets",
  {
    game: text("game").notNull(),
    name: text("name").notNull(),
    setCode: text("set_code"),
    setId: text("set_id").primaryKey(),
    setImageId: text("set_image_id"),
    totalCards: integer("total_cards").default(0),
  },
  (t) => [
    unique("uq_sets_game_name").on(t.game, t.name),
    index("idx_sets_game_name_search").on(sql`lower(${t.game})`, t.name),
  ],
);

export const tcgPrice = sqliteTable(
  "tcg_price",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    skuId: integer("sku_id"),
    pricechartingId: text("pricecharting_id"),
    productId: text("product_id").notNull(),
    skuKey: text("sku_key").notNull(),
    conditionCode: text("condition_code"),
    conditionName: text("condition_name"),
    languageCode: text("language_code"),
    languageName: text("language_name"),
    variantCode: text("variant_code"),
    variantName: text("variant_name"),
    priceUngraded: text("price_Ungraded").notNull().default("[]"),
    priceGrade7: text("price_Grade_7").notNull().default("[]"),
    priceGrade8: text("price_Grade_8").notNull().default("[]"),
    priceGrade9: text("price_Grade_9").notNull().default("[]"),
    priceGrade95: text("price_Grade_9_5").notNull().default("[]"),
    pricePsa10: text("price_PSA_10").notNull().default("[]"),
    priceBgs10: text("price_BGS_10").notNull().default("[]"),
    priceCgc10: text("price_CGC_10").notNull().default("[]"),
    priceSgc10: text("price_SGC_10").notNull().default("[]"),
    increaseUngraded: real("increase_Ungraded").notNull().default(0),
    increaseGrade7: real("increase_Grade_7").notNull().default(0),
    increaseGrade8: real("increase_Grade_8").notNull().default(0),
    increaseGrade9: real("increase_Grade_9").notNull().default(0),
    increaseGrade95: real("increase_Grade_9_5").notNull().default(0),
    increasePsa10: real("increase_PSA_10").notNull().default(0),
    increaseBgs10: real("increase_BGS_10").notNull().default(0),
    increaseCgc10: real("increase_CGC_10").notNull().default(0),
    increaseSgc10: real("increase_SGC_10").notNull().default(0),
  },
  (t) => [
    uniqueIndex("idx_tcg_price_sku_id").on(t.skuId),
    uniqueIndex("idx_tcg_price_natural_key").on(
      t.productId,
      sql`coalesce(${t.conditionName}, '')`,
      sql`coalesce(${t.languageName}, '')`,
      sql`coalesce(${t.variantName}, '')`,
    ),
    index("idx_tcg_price_pricecharting_lookup").on(t.pricechartingId),
    index("idx_tcg_price_product_id").on(t.productId),
    index("idx_tcg_price_lookup").on(
      t.productId,
      t.languageCode,
      t.variantCode,
      t.conditionCode,
    ),
    index("idx_tcg_price_increase_ungraded").on(t.increaseUngraded),
  ],
);

// ── 用户 / 账号层 ──────────────────────────────────────────────

export const user = sqliteTable(
  "user",
  {
    id: text("id").primaryKey(),
    email: text("email").notNull(),
    passwordHash: text("password_hash"), // OAuth 唯一注册时可为 NULL
    displayName: text("display_name"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
    status: text("status").notNull().default("active"),
    deletedAt: text("deleted_at"),
  },
  (t) => [
    check(
      "ck_user_status",
      sql`${t.status} IN ('active', 'deleted', 'disabled')`,
    ),
    uniqueIndex("uq_user_non_deleted_email")
      .on(t.email)
      .where(sql`${t.status} <> 'deleted'`),
  ],
);

export const anonymousAccount = sqliteTable(
  "anonymous_account",
  {
    id: text("id").primaryKey(),
    deviceId: text("device_id").notNull(),
    createdAt: text("created_at").notNull(),
    upgradedUserId: text("upgraded_user_id"), // 升级后回填 user.id；NULL = 仍为游客
  },
  (t) => [
    index("idx_anonymous_account_device_live").on(
      t.deviceId,
      t.upgradedUserId,
      t.createdAt,
    ),
  ],
);

export const accountUid = sqliteTable(
  "account_uid",
  {
    uid: integer("uid").primaryKey(),
    createdAt: text("created_at").notNull(),
  },
  (t) => [check("ck_account_uid_minimum", sql`${t.uid} >= 100000`)],
);

export const mutationLock = sqliteTable("mutation_lock", {
  lockKey: text("lock_key").primaryKey(),
});

export const appInstallation = sqliteTable("app_installation", {
  installationId: text("installation_id").primaryKey(),
  uid: text("uid"),
  platform: text("platform").notNull(),
  countryCode: text("country_code"),
  firstSeenAt: text("first_seen_at").notNull(),
  lastSeenAt: text("last_seen_at").notNull(),
});

export const authIdentity = sqliteTable(
  "auth_identity",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    provider: text("provider").notNull(), // 'google' | 'apple'
    providerUid: text("provider_uid").notNull(),
    createdAt: text("created_at").notNull(),
  },
  (t) => [
    unique("uq_auth_identity_provider").on(t.provider, t.providerUid),
    index("idx_auth_identity_user").on(t.userId),
  ],
);

export const session = sqliteTable(
  "session",
  {
    id: text("id").primaryKey(),
    ownerType: text("owner_type").notNull(), // 'user' | 'anonymous'
    ownerId: text("owner_id").notNull(),
    loginMethod: text("login_method"), // NULL for anonymous or legacy sessions
    refreshToken: text("refresh_token").notNull().unique(),
    expiresAt: text("expires_at").notNull(),
    createdAt: text("created_at").notNull(),
    revokedAt: text("revoked_at"), // NULL = 有效
  },
  (t) => [
    index("idx_session_owner").on(t.ownerType, t.ownerId),
    check(
      "ck_session_login_method",
      sql`${t.loginMethod} IS NULL OR ${t.loginMethod} IN ('email', 'google', 'apple')`,
    ),
  ],
);

export const verificationCode = sqliteTable(
  "verification_code",
  {
    id: text("id").primaryKey(),
    email: text("email").notNull(),
    code: text("code").notNull(),
    purpose: text("purpose").notNull(), // 'register' | 'reset_password'
    expiresAt: text("expires_at").notNull(),
    usedAt: text("used_at"), // NULL = 未使用
    createdAt: text("created_at").notNull(),
  },
  (t) => [
    index("idx_verification_code_email").on(t.email, t.purpose, t.createdAt),
  ],
);

// ── 资产层 ────────────────────────────────────────────────────

export const portfolioFolder = sqliteTable(
  "portfolio_folder",
  {
    id: text("id").primaryKey(),
    ownerType: text("owner_type").notNull(),
    ownerId: text("owner_id").notNull(),
    name: text("name").notNull(),
    isDefault: integer("is_default").notNull().default(0), // is_default = 1 唯一性由 Workers 层保证
    sortOrder: integer("sort_order").notNull().default(0),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    unique("uq_portfolio_folder_name").on(t.ownerType, t.ownerId, t.name),
    index("idx_portfolio_folder_owner").on(t.ownerType, t.ownerId, t.sortOrder),
    check("ck_portfolio_folder_is_default", sql`${t.isDefault} IN (0, 1)`),
  ],
);

export const collectionItem = sqliteTable(
  "collection_item",
  {
    id: text("id").primaryKey(),
    ownerType: text("owner_type").notNull(),
    ownerId: text("owner_id").notNull(),
    folderId: text("folder_id")
      .notNull()
      .references(() => portfolioFolder.id, { onDelete: "cascade" }),
    cardRef: text("card_ref").notNull(), // cards_all.product_id
    objectType: text("object_type").notNull(), // 'tcg' | 'sports' | 'sealed' | 'other'
    grader: text("grader").notNull(), // 'Raw' | 'PSA' | 'BGS' | 'CGC' | 'SGC' | 'TAG' | 'AGS'
    condition: text("condition"), // grader = 'Raw' 时使用
    grade: real("grade"), // grader ≠ 'Raw' 时使用
    language: text("language"),
    finish: text("finish"),
    quantity: integer("quantity").notNull().default(1),
    purchasePrice: real("purchase_price"),
    purchaseCurrency: text("purchase_currency"),
    performanceStartAt: text("performance_start_at"),
    purchasePriceEffectiveAt: text("purchase_price_effective_at"),
    performanceHistoryAvailableFrom: text("performance_history_available_from"),
    notes: text("notes"), // 最多 500 字符（Workers 层校验）
    folderJoinedAt: text("folder_joined_at"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    index("idx_collection_item_owner").on(t.ownerType, t.ownerId, t.cardRef),
    index("idx_collection_item_folder").on(t.folderId),
    index("idx_collection_item_card").on(t.cardRef),
    uniqueIndex("uq_collection_item_folder_card_finish_language").on(
      t.ownerType,
      t.ownerId,
      t.folderId,
      t.cardRef,
      sql`COALESCE(${t.finish}, '')`,
      sql`COALESCE(${t.language}, '')`,
    ),
    check("ck_collection_item_quantity", sql`${t.quantity} >= 1`),
  ],
);

export const collectionItemEvent = sqliteTable(
  "collection_item_event",
  {
    id: text("id").primaryKey(),
    itemId: text("item_id").notNull(),
    ownerType: text("owner_type").notNull(),
    ownerId: text("owner_id").notNull(),
    folderId: text("folder_id").notNull(),
    cardRef: text("card_ref").notNull(),
    objectType: text("object_type").notNull(),
    grader: text("grader").notNull(),
    condition: text("condition"),
    grade: real("grade"),
    language: text("language"),
    finish: text("finish"),
    quantity: integer("quantity").notNull(),
    purchasePrice: real("purchase_price"),
    purchaseCurrency: text("purchase_currency"),
    performanceHistoryAvailableFrom: text("performance_history_available_from"),
    eventType: text("event_type").notNull(),
    effectiveAt: text("effective_at").notNull(),
  },
  (t) => [
    index("idx_collection_item_event_owner_time").on(
      t.ownerType,
      t.ownerId,
      t.effectiveAt,
    ),
    index("idx_collection_item_event_folder_time").on(t.folderId, t.effectiveAt),
    index("idx_collection_item_event_item_time").on(t.itemId, t.effectiveAt),
    index("idx_collection_item_event_performance_history").on(
      t.ownerType,
      t.ownerId,
      t.performanceHistoryAvailableFrom,
    ),
    check("ck_collection_item_event_quantity", sql`${t.quantity} >= 1`),
    check(
      "ck_collection_item_event_type",
      sql`${t.eventType} IN ('upsert', 'delete')`,
    ),
  ],
);

export const wishlistItem = sqliteTable(
  "wishlist_item",
  {
    id: text("id").primaryKey(),
    ownerType: text("owner_type").notNull(),
    ownerId: text("owner_id").notNull(),
    cardRef: text("card_ref").notNull(),
    createdAt: text("created_at").notNull(),
  },
  (t) => [
    unique("uq_wishlist_item_card").on(t.ownerType, t.ownerId, t.cardRef),
    index("idx_wishlist_item_owner").on(t.ownerType, t.ownerId),
  ],
);

export const scanRecord = sqliteTable(
  "scan_record",
  {
    id: text("id").primaryKey(),
    ownerType: text("owner_type").notNull(),
    ownerId: text("owner_id").notNull(),
    imageUrl: text("image_url"),
    filename: text("filename").notNull(),
    platform: text("platform").notNull(),
    appVersion: text("app_version").notNull(),
    deviceModel: text("device_model"),
    osVersion: text("os_version"),
    recognitionStatus: text("recognition_status").notNull(),
    userConfirmationStatus: text("user_confirmation_status").notNull(),
    modifiedResult: integer("modified_result").notNull().default(0),
    systemResult: text("system_result").notNull(),
    userResult: text("user_result").notNull(),
    candidates: text("candidates").notNull(),
    rawResponse: text("raw_response").notNull(),
    createdAt: text("created_at").notNull(),
  },
  (t) => [
    index("idx_scan_record_owner").on(t.ownerType, t.ownerId, t.createdAt),
    index("idx_scan_record_created_at").on(t.createdAt),
    check("ck_scan_record_modified_result", sql`${t.modifiedResult} IN (0, 1)`),
  ],
);

export const userPreference = sqliteTable(
  "user_preference",
  {
    id: text("id").primaryKey(),
    ownerType: text("owner_type").notNull(),
    ownerId: text("owner_id").notNull(),
    currency: text("currency").notNull().default("USD"),
    amountHidden: integer("amount_hidden").notNull().default(0),
    lastSelectedFolderId: text("last_selected_folder_id"), // 软引用 portfolio_folder.id，无 DB 级 FK
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [unique("uq_user_preference_owner").on(t.ownerType, t.ownerId)],
);

// ── 订阅与内购层 ──────────────────────────────────────────────

export const billingProduct = sqliteTable(
  "billing_product",
  {
    id: text("id").primaryKey(),
    store: text("store").notNull(),
    productId: text("product_id").notNull(),
    planId: text("plan_id").notNull(),
    entitlementId: text("entitlement_id").notNull(),
    productType: text("product_type").notNull(),
    active: integer("active").notNull().default(1),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    unique("uq_billing_product_store_product").on(t.store, t.productId),
    unique("uq_billing_product_store_plan").on(t.store, t.planId),
    check("ck_billing_product_active", sql`${t.active} IN (0, 1)`),
  ],
);

export const billingPurchaseChain = sqliteTable(
  "billing_purchase_chain",
  {
    id: text("id").primaryKey(),
    store: text("store").notNull(),
    environment: text("environment").notNull(),
    originalTransactionId: text("original_transaction_id").notNull(),
    productId: text("product_id").notNull(),
    entitlementId: text("entitlement_id").notNull(),
    originalOwnerType: text("original_owner_type").notNull(),
    originalOwnerId: text("original_owner_id").notNull(),
    appAccountToken: text("app_account_token"),
    status: text("status").notNull(),
    autoRenew: integer("auto_renew").notNull().default(0),
    expiresAt: text("expires_at"),
    gracePeriodExpiresAt: text("grace_period_expires_at"),
    revokedAt: text("revoked_at"),
    stateEffectiveAt: text("state_effective_at"),
    nextProductId: text("next_product_id"),
    lifecycleSignedAt: text("lifecycle_signed_at"),
    lifecycleNotificationUuid: text("lifecycle_notification_uuid"),
    correctionStatus: text("correction_status"),
    autoRenewSignedAt: text("auto_renew_signed_at"),
    planSignedAt: text("plan_signed_at"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    unique("uq_billing_chain_store_environment_original").on(
      t.store,
      t.environment,
      t.originalTransactionId,
    ),
    index("idx_billing_chain_owner").on(t.originalOwnerType, t.originalOwnerId),
    index("idx_billing_chain_status_expiry").on(t.status, t.expiresAt),
    check("ck_billing_chain_auto_renew", sql`${t.autoRenew} IN (0, 1)`),
  ],
);

export const billingTransaction = sqliteTable(
  "billing_transaction",
  {
    id: text("id").primaryKey(),
    purchaseChainId: text("purchase_chain_id")
      .notNull()
      .references(() => billingPurchaseChain.id),
    store: text("store").notNull(),
    environment: text("environment").notNull(),
    transactionId: text("transaction_id").notNull(),
    productId: text("product_id").notNull(),
    transactionReason: text("transaction_reason").notNull(),
    status: text("status").notNull(),
    businessStatus: text("business_status"),
    businessStatusBeforeRefund: text("business_status_before_refund"),
    chargeCount: integer("charge_count"),
    sourceNotificationUuid: text("source_notification_uuid"),
    autoRenewSnapshot: integer("auto_renew_snapshot"),
    storefrontCountryCode: text("storefront_country_code"),
    amountMicros: integer("amount_micros"),
    currency: text("currency"),
    amountUsdMicros: integer("amount_usd_micros"),
    usdExchangeRate: text("usd_exchange_rate"),
    usdExchangeRateBase: text("usd_exchange_rate_base"),
    usdExchangeRateQuote: text("usd_exchange_rate_quote"),
    usdExchangeRateSource: text("usd_exchange_rate_source"),
    usdExchangeRateEffectiveAt: text("usd_exchange_rate_effective_at"),
    usdExchangeRateFetchedAt: text("usd_exchange_rate_fetched_at"),
    usdExchangeRateStale: integer("usd_exchange_rate_stale"),
    usdConversionVersion: text("usd_conversion_version"),
    usdRoundingMode: text("usd_rounding_mode"),
    purchaseAt: text("purchase_at").notNull(),
    expiresAt: text("expires_at"),
    revokedAt: text("revoked_at"),
    refundCompletedAt: text("refund_completed_at"),
    signedTransaction: text("signed_transaction"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    unique("uq_billing_transaction_store_environment_transaction").on(
      t.store,
      t.environment,
      t.transactionId,
    ),
    index("idx_billing_transaction_chain_time").on(t.purchaseChainId, t.purchaseAt),
    index("idx_billing_transaction_status_time").on(t.status, t.purchaseAt),
    index("idx_billing_transaction_product_time").on(t.productId, t.purchaseAt),
    index("idx_billing_transaction_business_status_time").on(t.businessStatus, t.purchaseAt),
    index("idx_billing_transaction_charge_count").on(t.chargeCount, t.purchaseAt),
    check(
      "ck_billing_transaction_auto_renew_snapshot",
      sql`${t.autoRenewSnapshot} IS NULL OR ${t.autoRenewSnapshot} IN (0, 1)`,
    ),
  ],
);

export const billingEntitlementGrant = sqliteTable(
  "billing_entitlement_grant",
  {
    id: text("id").primaryKey(),
    purchaseChainId: text("purchase_chain_id")
      .notNull()
      .references(() => billingPurchaseChain.id),
    ownerType: text("owner_type").notNull(),
    ownerId: text("owner_id").notNull(),
    source: text("source").notNull(),
    status: text("status").notNull(),
    grantedAt: text("granted_at").notNull(),
    revokedAt: text("revoked_at"),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    unique("uq_billing_grant_chain_owner").on(t.purchaseChainId, t.ownerType, t.ownerId),
    index("idx_billing_grant_owner_status").on(t.ownerType, t.ownerId, t.status),
  ],
);

export const scanQuotaRequest = sqliteTable(
  "scan_quota_request",
  {
    requestId: text("request_id").primaryKey(),
    ownerType: text("owner_type").notNull(),
    ownerId: text("owner_id").notNull(),
    sessionId: text("session_id").notNull(),
    accessMode: text("access_mode").notNull(),
    status: text("status").notNull(),
    scanId: text("scan_id"),
    processingExpiresAt: text("processing_expires_at"),
    attempts: integer("attempts").notNull().default(1),
    responseJson: text("response_json"),
    httpStatus: integer("http_status"),
    createdAt: text("created_at").notNull(),
    settledAt: text("settled_at"),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    index("idx_scan_quota_request_owner_status").on(
      t.ownerType,
      t.ownerId,
      t.status,
      t.createdAt,
    ),
    check(
      "ck_scan_quota_request_access_mode",
      sql`${t.accessMode} IN ('free', 'premium')`,
    ),
    check(
      "ck_scan_quota_request_status",
      sql`${t.status} IN ('reserved', 'consumed', 'released')`,
    ),
  ],
);

export const billingSessionEntitlementGrant = sqliteTable(
  "billing_session_entitlement_grant",
  {
    id: text("id").primaryKey(),
    sessionId: text("session_id")
      .notNull()
      .references(() => session.id),
    purchaseChainId: text("purchase_chain_id")
      .notNull()
      .references(() => billingPurchaseChain.id),
    entitlementId: text("entitlement_id").notNull(),
    source: text("source").notNull(),
    status: text("status").notNull(),
    grantedAt: text("granted_at").notNull(),
    expiresAt: text("expires_at"),
    lastVerifiedAt: text("last_verified_at").notNull(),
    revokedAt: text("revoked_at"),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    unique("uq_billing_session_grant_session_chain_entitlement").on(
      t.sessionId,
      t.purchaseChainId,
      t.entitlementId,
    ),
    index("idx_billing_session_grant_session_status_expiry").on(
      t.sessionId,
      t.entitlementId,
      t.status,
      t.expiresAt,
    ),
    index("idx_billing_session_grant_chain_status").on(t.purchaseChainId, t.status),
    check(
      "ck_billing_session_grant_status",
      sql`${t.status} IN ('active', 'revoked', 'expired')`,
    ),
  ],
);

export const billingApplePurchaseChallenge = sqliteTable(
  "billing_apple_purchase_challenge",
  {
    token: text("token").primaryKey(),
    sessionId: text("session_id")
      .notNull()
      .references(() => session.id),
    productId: text("product_id").notNull(),
    expiresAt: text("expires_at").notNull(),
    consumedAt: text("consumed_at"),
    consumedTransactionId: text("consumed_transaction_id"),
    createdAt: text("created_at").notNull(),
  },
  (t) => [
    index("idx_billing_apple_challenge_session_expiry").on(t.sessionId, t.expiresAt),
  ],
);

export const billingAppleVerificationAttempt = sqliteTable(
  "billing_apple_verification_attempt",
  {
    id: text("id").primaryKey(),
    sessionId: text("session_id")
      .notNull()
      .references(() => session.id),
    requestId: text("request_id").notNull(),
    evidenceType: text("evidence_type").notNull(),
    evidenceSha256: text("evidence_sha256").notNull(),
    resultCode: text("result_code").notNull(),
    transactionId: text("transaction_id"),
    responseJson: text("response_json").notNull(),
    httpStatus: integer("http_status").notNull(),
    processingExpiresAt: text("processing_expires_at"),
    createdAt: text("created_at").notNull(),
  },
  (t) => [
    unique("uq_billing_apple_attempt_session_request").on(t.sessionId, t.requestId),
    index("idx_billing_apple_attempt_evidence").on(t.evidenceSha256, t.createdAt),
  ],
);

export const billingAppleAppAttestChallenge = sqliteTable(
  "billing_apple_app_attest_challenge",
  {
    token: text("token").primaryKey(),
    sessionId: text("session_id")
      .notNull()
      .references(() => session.id),
    purpose: text("purpose").notNull(),
    requestId: text("request_id").notNull(),
    keyId: text("key_id"),
    evidenceSha256: text("evidence_sha256"),
    clientData: text("client_data").notNull(),
    expiresAt: text("expires_at").notNull(),
    consumedAt: text("consumed_at"),
    consumptionId: text("consumption_id"),
    resultCode: text("result_code"),
    responseJson: text("response_json"),
    httpStatus: integer("http_status"),
    createdAt: text("created_at").notNull(),
  },
  (t) => [
    unique("uq_billing_app_attest_challenge_request").on(t.sessionId, t.requestId),
    index("idx_billing_app_attest_challenge_expiry").on(t.sessionId, t.expiresAt),
    check(
      "ck_billing_app_attest_challenge_purpose",
      sql`${t.purpose} IN ('register', 'restore')`,
    ),
  ],
);

export const billingAppleAppAttestKey = sqliteTable(
  "billing_apple_app_attest_key",
  {
    keyId: text("key_id").primaryKey(),
    publicKeyPem: text("public_key_pem").notNull(),
    receiptBase64: text("receipt_base64").notNull(),
    signCount: integer("sign_count").notNull().default(0),
    environment: text("environment").notNull(),
    registeredSessionId: text("registered_session_id")
      .notNull()
      .references(() => session.id),
    status: text("status").notNull().default("active"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    index("idx_billing_app_attest_key_status").on(t.status, t.updatedAt),
    check(
      "ck_billing_app_attest_key_environment",
      sql`${t.environment} IN ('development', 'production')`,
    ),
    check(
      "ck_billing_app_attest_key_status",
      sql`${t.status} IN ('active', 'revoked')`,
    ),
  ],
);

export const appleNotificationInbox = sqliteTable(
  "apple_notification_inbox",
  {
    id: text("id").primaryKey(),
    payloadSha256: text("payload_sha256").notNull().unique(),
    requestJson: text("request_json").notNull(),
    signedPayload: text("signed_payload").notNull(),
    processingStatus: text("processing_status").notNull().default("pending"),
    attempts: integer("attempts").notNull().default(0),
    processingExpiresAt: text("processing_expires_at"),
    notificationUuid: text("notification_uuid"),
    lastError: text("last_error"),
    receivedAt: text("received_at").notNull(),
    processedAt: text("processed_at"),
  },
  (t) => [
    index("idx_apple_notification_inbox_processing").on(
      t.processingStatus,
      t.processingExpiresAt,
      t.receivedAt,
    ),
    check(
      "ck_apple_notification_inbox_status",
      sql`${t.processingStatus} IN ('pending', 'processing', 'processed', 'verification_failed', 'parse_failed', 'correction_required', 'processing_failed')`,
    ),
  ],
);

export const appleServerNotification = sqliteTable(
  "apple_server_notification",
  {
    id: text("id").primaryKey(),
    inboxId: text("inbox_id").references(() => appleNotificationInbox.id),
    notificationUuid: text("notification_uuid").notNull().unique(),
    notificationType: text("notification_type").notNull(),
    subtype: text("subtype"),
    environment: text("environment").notNull(),
    originalTransactionId: text("original_transaction_id"),
    transactionId: text("transaction_id"),
    productId: text("product_id"),
    signedPayload: text("signed_payload").notNull(),
    decodedPayload: text("decoded_payload"),
    processingStatus: text("processing_status").notNull().default("pending"),
    attempts: integer("attempts").notNull().default(0),
    lastError: text("last_error"),
    signedAt: text("signed_at"),
    receivedAt: text("received_at").notNull(),
    processedAt: text("processed_at"),
  },
  (t) => [
    unique("uq_apple_notification_inbox_id").on(t.inboxId),
    index("idx_apple_notification_received").on(t.receivedAt),
    index("idx_apple_notification_type_received").on(t.notificationType, t.receivedAt),
    index("idx_apple_notification_transaction").on(t.originalTransactionId),
    index("idx_apple_notification_processing").on(t.processingStatus, t.receivedAt),
  ],
);

// ── 管理员层 ──────────────────────────────────────────────────

export const adminUser = sqliteTable("admin_user", {
  id: text("id").primaryKey(),
  email: text("email").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  role: text("role").notNull(), // 'super_admin' | 'operator'
  status: text("status").notNull().default("active"), // 'active' | 'disabled'
  createdAt: text("created_at").notNull(),
});

// ── 覆盖层 + 运营 + 反馈 ──────────────────────────────────────

export const cardOverride = sqliteTable("card_override", {
  id: text("id").primaryKey(),
  cardRef: text("card_ref").notNull().unique(),
  overrideFields: text("override_fields"), // JSON：字段级覆盖
  imageUrl: text("image_url"),
  isMissingCard: integer("is_missing_card").notNull().default(0),
  updatedBy: text("updated_by"), // 软引用 admin_user.id，无 DB 级 FK
  updatedAt: text("updated_at").notNull(),
}, (t) => [check("ck_card_override_is_missing", sql`${t.isMissingCard} IN (0, 1)`)]);

export const appConfig = sqliteTable("app_config", {
  key: text("key").primaryKey(),
  value: text("value").notNull(),
  updatedBy: text("updated_by"), // 软引用 admin_user.id，无 DB 级 FK
  updatedAt: text("updated_at").notNull(),
});

export const feedbackTicket = sqliteTable(
  "feedback_ticket",
  {
    id: text("id").primaryKey(),
    uid: text("uid"),
    email: text("email").notNull(),
    types: text("types").notNull(), // JSON 数组
    functions: text("functions").notNull(), // JSON 数组
    message: text("message").notNull(), // 最多 1000 字符（Workers 层校验）
    status: text("status").notNull().default("open"), // 'open' | 'in_progress' | 'closed'
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [index("idx_feedback_ticket_status").on(t.status, t.createdAt)],
);
