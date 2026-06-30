// tcg-card D1 Schema —— 严格对齐 docs/tcg-card/03-data-api/data-model.md（14 张表）。
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
} from "drizzle-orm/sqlite-core";

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
    refreshToken: text("refresh_token").notNull().unique(),
    expiresAt: text("expires_at").notNull(),
    createdAt: text("created_at").notNull(),
    revokedAt: text("revoked_at"), // NULL = 有效
  },
  (t) => [index("idx_session_owner").on(t.ownerType, t.ownerId)],
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
    cardRef: text("card_ref").notNull(), // 第三方卡牌标识（格式 TBD）
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
