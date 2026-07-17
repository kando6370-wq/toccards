// tcg-card D1 Schema —— 严格对齐 docs/tcg-card/03-data-api/data-model.md。
// 约定：ULID 主键 TEXT；时间戳 ISO8601 UTC TEXT；布尔 INTEGER(0/1)；金额 REAL；枚举 TEXT（Workers 层校验）；多值 JSON 字符串 TEXT；软删 deleted_at；owner 多态 owner_type+owner_id；软引用不设 DB 级 FK。
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
    name: text("name"),
    rarity: text("rarity"),
    description: text("description"),
    productTypeName: text("product_type_name"),
    foilOnly: integer("foil_only").default(0),
    normalOnly: integer("normal_only").default(0),
    imageUrl: text("image_url"),
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
  ],
);

export const games = sqliteTable("games", {
  id: integer("id"),
  gameId: real("game_id"),
  name: text("name"),
  totalCards: integer("total_cards"),
  imageSource: text("image_source"),
  imagesEnabled: integer("images_enabled"),
  createdAt: text("created_at"),
  load: integer("load"),
});

export const sets = sqliteTable(
  "sets",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    game: text("game").notNull(),
    name: text("name").notNull(),
    setName: text("set_name"),
    setCode: text("set_code"),
    setId: text("set_id"),
    productId: text("product_id"),
    series: text("series"),
    totalCards: integer("total_cards").default(0),
    releaseDate: text("release_date"),
    createdAt: text("created_at").default(sql`CURRENT_TIMESTAMP`),
  },
  (t) => [
    unique("uq_sets_game_name").on(t.game, t.name),
    index("idx_sets_set_id").on(t.setId),
  ],
);

export const tcgplayerSkus = sqliteTable(
  "tcgplayer_skus",
  {
    skuId: integer("sku_id").primaryKey(),
    productId: integer("product_id").notNull(),
    skuKey: text("sku_key").notNull(),
    conditionCode: text("condition_code"),
    conditionName: text("condition_name"),
    languageCode: text("language_code"),
    languageName: text("language_name"),
    variantCode: text("variant_code"),
    variantName: text("variant_name"),
    createdAt: text("created_at").default(sql`CURRENT_TIMESTAMP`),
    updatedAt: text("updated_at").default(sql`CURRENT_TIMESTAMP`),
    priceHistory: text("price_history").notNull().default("[]"),
    source: text("source"),
    sourceVariantId: text("source_variant_id"),
  },
  (t) => [
    index("idx_tcgplayer_skus_product_id").on(t.productId),
    index("idx_tcgplayer_skus_lookup").on(
      t.productId,
      t.languageCode,
      t.variantCode,
      t.conditionCode,
    ),
    uniqueIndex("uq_tcgplayer_skus_source_variant").on(
      t.source,
      t.sourceVariantId,
    ),
  ],
);

export const priceSyncState = sqliteTable("price_sync_state", {
  source: text("source").primaryKey(),
  status: text("status").notNull(),
  cursorProductId: integer("cursor_product_id"),
  cycleStartedAt: text("cycle_started_at"),
  lastAttemptAt: text("last_attempt_at"),
  lastSuccessAt: text("last_success_at"),
  lastCompletedAt: text("last_completed_at"),
  nextRunAt: text("next_run_at"),
  productsProcessed: integer("products_processed").notNull().default(0),
  variantsWritten: integer("variants_written").notNull().default(0),
  coveredProducts: integer("covered_products").notNull().default(0),
  totalProducts: integer("total_products").notNull().default(0),
  lastError: text("last_error"),
});

// ── 用户 / 账号层 ──────────────────────────────────────────────

export const user = sqliteTable("user", {
  id: text("id").primaryKey(),
  email: text("email").notNull().unique(),
  passwordHash: text("password_hash"), // OAuth 唯一注册时可为 NULL
  displayName: text("display_name"),
  createdAt: text("created_at").notNull(),
  updatedAt: text("updated_at").notNull(),
  deletedAt: text("deleted_at"), // 软删除；NULL = 正常账号
});

export const anonymousAccount = sqliteTable("anonymous_account", {
  id: text("id").primaryKey(),
  deviceId: text("device_id").notNull(),
  createdAt: text("created_at").notNull(),
  upgradedUserId: text("upgraded_user_id"), // 升级后回填 user.id；NULL = 仍为游客
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
  (t) => [unique("uq_auth_identity_provider").on(t.provider, t.providerUid)],
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
  (t) => [index("idx_verification_code_email").on(t.email, t.purpose)],
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
    index("idx_portfolio_folder_owner").on(t.ownerType, t.ownerId),
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
    notes: text("notes"), // 最多 500 字符（Workers 层校验）
    folderJoinedAt: text("folder_joined_at"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    index("idx_collection_item_owner").on(t.ownerType, t.ownerId),
    index("idx_collection_item_folder").on(t.folderId),
    index("idx_collection_item_card").on(t.cardRef),
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
    index("idx_scan_record_owner").on(t.ownerType, t.ownerId),
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

export const trendingPin = sqliteTable(
  "trending_pin",
  {
    id: text("id").primaryKey(),
    cardRef: text("card_ref").notNull().unique(),
    rank: integer("rank").notNull(),
    active: integer("active").notNull().default(1),
    updatedBy: text("updated_by"), // 软引用 admin_user.id，无 DB 级 FK
    updatedAt: text("updated_at").notNull(),
  },
  (t) => [
    index("idx_trending_pin_rank").on(t.active, t.rank),
    check("ck_trending_pin_active", sql`${t.active} IN (0, 1)`),
  ],
);

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
