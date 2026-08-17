export type MigrationTable = {
  name: string;
  cursor: string;
  cursorType: "number" | "text";
  columns: readonly string[];
  bigintColumns?: readonly string[];
};

export const MIGRATION_TABLES: readonly MigrationTable[] = [
  {
    name: "user",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "email", "password_hash", "display_name", "created_at", "updated_at",
      "deleted_at", "status",
    ],
  },
  {
    name: "anonymous_account",
    cursor: "id",
    cursorType: "text",
    columns: ["id", "device_id", "created_at", "upgraded_user_id"],
  },
  {
    name: "account_uid",
    cursor: "uid",
    cursorType: "number",
    columns: ["uid", "created_at"],
  },
  {
    name: "app_installation",
    cursor: "installation_id",
    cursorType: "text",
    columns: [
      "installation_id", "platform", "country_code", "first_seen_at", "last_seen_at", "uid",
    ],
  },
  {
    name: "auth_identity",
    cursor: "id",
    cursorType: "text",
    columns: ["id", "user_id", "provider", "provider_uid", "created_at"],
  },
  {
    name: "session",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "owner_type", "owner_id", "refresh_token", "expires_at", "created_at",
      "revoked_at", "login_method",
    ],
  },
  {
    name: "verification_code",
    cursor: "id",
    cursorType: "text",
    columns: ["id", "email", "code", "purpose", "expires_at", "used_at", "created_at"],
  },
  {
    name: "cards_all",
    cursor: "product_id",
    cursorType: "text",
    columns: [
      "product_id", "game_id", "game", "set_name", "set_code", "set_id", "name", "rarity",
      "description", "product_type_name", "foil_only", "normal_only", "created_at", "updated_at",
      "card_type", "full_type", "color", "converted_cost", "flavor_text", "power",
      "power_number", "toughness", "has_image", "number",
    ],
  },
  {
    name: "games",
    cursor: "game_id",
    cursorType: "number",
    columns: [
      "game_id", "tcgcsv_id", "name", "total_cards", "image_source", "images_enabled",
      "created_at", "load", "search_sort",
    ],
  },
  {
    name: "sets",
    cursor: "set_id",
    cursorType: "text",
    columns: ["set_id", "game", "name", "set_code", "total_cards", "set_image_id"],
  },
  {
    name: "portfolio_folder",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "owner_type", "owner_id", "name", "is_default", "sort_order", "created_at",
      "updated_at",
    ],
  },
  {
    name: "collection_item",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "owner_type", "owner_id", "folder_id", "card_ref", "object_type", "grader",
      "condition", "grade", "language", "finish", "quantity", "purchase_price",
      "purchase_currency", "notes", "created_at", "updated_at", "folder_joined_at",
      "performance_start_at", "purchase_price_effective_at", "performance_history_available_from",
    ],
  },
  {
    name: "collection_item_event",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "item_id", "owner_type", "owner_id", "folder_id", "card_ref", "object_type",
      "grader", "condition", "grade", "language", "finish", "quantity", "event_type",
      "effective_at", "purchase_price", "purchase_currency", "performance_history_available_from",
    ],
  },
  {
    name: "wishlist_item",
    cursor: "id",
    cursorType: "text",
    columns: ["id", "owner_type", "owner_id", "card_ref", "created_at"],
  },
  {
    name: "user_preference",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "owner_type", "owner_id", "currency", "amount_hidden", "last_selected_folder_id",
      "created_at", "updated_at",
    ],
  },
  {
    name: "scan_record",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "owner_type", "owner_id", "image_url", "filename", "platform", "app_version",
      "device_model", "os_version", "recognition_status", "user_confirmation_status",
      "modified_result", "system_result", "user_result", "candidates", "raw_response", "created_at",
    ],
  },
  {
    name: "scan_quota_request",
    cursor: "request_id",
    cursorType: "text",
    columns: [
      "request_id", "owner_type", "owner_id", "session_id", "access_mode", "status", "scan_id",
      "processing_expires_at", "attempts", "response_json", "http_status", "created_at",
      "settled_at", "updated_at",
    ],
  },
  {
    name: "billing_product",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "store", "product_id", "plan_id", "entitlement_id", "product_type", "active",
      "created_at", "updated_at",
    ],
  },
  {
    name: "billing_purchase_chain",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "store", "environment", "original_transaction_id", "product_id", "entitlement_id",
      "original_owner_type", "original_owner_id", "app_account_token", "status", "auto_renew",
      "expires_at", "grace_period_expires_at", "revoked_at", "created_at", "updated_at",
      "state_effective_at", "next_product_id", "lifecycle_signed_at",
      "lifecycle_notification_uuid", "correction_status", "auto_renew_signed_at", "plan_signed_at",
    ],
  },
  {
    name: "billing_transaction",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "purchase_chain_id", "store", "environment", "transaction_id", "product_id",
      "transaction_reason", "status", "storefront_country_code", "amount_micros", "currency",
      "amount_usd_micros", "purchase_at", "expires_at", "revoked_at", "signed_transaction",
      "created_at", "updated_at", "refund_completed_at", "business_status", "charge_count",
      "source_notification_uuid", "usd_exchange_rate", "usd_exchange_rate_base",
      "usd_exchange_rate_quote", "usd_exchange_rate_source", "usd_exchange_rate_effective_at",
      "usd_exchange_rate_fetched_at", "usd_exchange_rate_stale", "usd_conversion_version",
      "usd_rounding_mode", "auto_renew_snapshot",
    ],
    bigintColumns: ["amount_micros", "amount_usd_micros"],
  },
  {
    name: "billing_entitlement_grant",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "purchase_chain_id", "owner_type", "owner_id", "source", "status", "granted_at",
      "revoked_at", "updated_at",
    ],
  },
  {
    name: "billing_session_entitlement_grant",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "session_id", "purchase_chain_id", "entitlement_id", "source", "status", "granted_at",
      "expires_at", "last_verified_at", "revoked_at", "updated_at",
    ],
  },
  {
    name: "billing_apple_purchase_challenge",
    cursor: "token",
    cursorType: "text",
    columns: [
      "token", "session_id", "product_id", "expires_at", "consumed_at",
      "consumed_transaction_id", "created_at",
    ],
  },
  {
    name: "billing_apple_verification_attempt",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "session_id", "request_id", "evidence_type", "evidence_sha256", "result_code",
      "transaction_id", "response_json", "http_status", "processing_expires_at", "created_at",
    ],
  },
  {
    name: "billing_apple_app_attest_challenge",
    cursor: "token",
    cursorType: "text",
    columns: [
      "token", "session_id", "purpose", "request_id", "key_id", "evidence_sha256", "client_data",
      "expires_at", "consumed_at", "consumption_id", "result_code", "response_json", "http_status",
      "created_at",
    ],
  },
  {
    name: "billing_apple_app_attest_key",
    cursor: "key_id",
    cursorType: "text",
    columns: [
      "key_id", "public_key_pem", "receipt_base64", "sign_count", "environment",
      "registered_session_id", "status", "created_at", "updated_at",
    ],
  },
  {
    name: "apple_notification_inbox",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "payload_sha256", "request_json", "signed_payload", "processing_status", "attempts",
      "processing_expires_at", "notification_uuid", "last_error", "received_at", "processed_at",
    ],
  },
  {
    name: "apple_server_notification",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "notification_uuid", "notification_type", "subtype", "environment",
      "original_transaction_id", "transaction_id", "product_id", "signed_payload", "decoded_payload",
      "processing_status", "attempts", "last_error", "signed_at", "received_at", "processed_at",
      "inbox_id",
    ],
  },
  {
    name: "admin_user",
    cursor: "id",
    cursorType: "text",
    columns: ["id", "email", "password_hash", "role", "status", "created_at"],
  },
  {
    name: "card_override",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "card_ref", "override_fields", "image_url", "is_missing_card", "updated_by", "updated_at",
    ],
  },
  {
    name: "trending_pin",
    cursor: "id",
    cursorType: "text",
    columns: ["id", "card_ref", "rank", "active", "updated_by", "updated_at"],
  },
  {
    name: "app_config",
    cursor: "key",
    cursorType: "text",
    columns: ["key", "value", "updated_by", "updated_at"],
  },
  {
    name: "feedback_ticket",
    cursor: "id",
    cursorType: "text",
    columns: [
      "id", "email", "types", "functions", "message", "status", "created_at", "updated_at", "uid",
    ],
  },
] as const;

export const PRICE_TABLES = [
  "price_source",
  "price_series",
  "price_ingest_batch",
  "price_current_snapshot",
  "current_price_pointer",
  "price_history_month",
  "card_trending_snapshot",
] as const;

export const EXCLUDED_SOURCE_TABLES = [
  "_cf_KV",
  "d1_migrations",
  "cards_new",
  "price_sync_state",
  "tcg_price",
] as const;

export const EXPECTED_TARGET_TABLES = [
  "postgres_migration",
  ...MIGRATION_TABLES.map((table) => table.name),
  ...PRICE_TABLES,
] as const;

export function findMigrationTable(name: unknown): MigrationTable | undefined {
  return typeof name === "string"
    ? MIGRATION_TABLES.find((table) => table.name === name)
    : undefined;
}
