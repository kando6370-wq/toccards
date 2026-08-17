CREATE TABLE "user" (
  id text PRIMARY KEY,
  email text NOT NULL,
  password_hash text,
  display_name text,
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  status text NOT NULL DEFAULT 'active',
  CONSTRAINT ck_user_status CHECK (status IN ('active', 'deleted', 'disabled'))
);

CREATE UNIQUE INDEX uq_user_non_deleted_email
  ON "user" (email) WHERE status <> 'deleted';

CREATE TABLE anonymous_account (
  id text PRIMARY KEY,
  device_id text NOT NULL,
  created_at text NOT NULL,
  upgraded_user_id text
);

CREATE INDEX idx_anonymous_account_device_live
  ON anonymous_account (device_id, upgraded_user_id, created_at);

CREATE TABLE account_uid (
  uid integer PRIMARY KEY,
  created_at text NOT NULL,
  CONSTRAINT ck_account_uid_minimum CHECK (uid >= 100000)
);

CREATE TABLE app_installation (
  installation_id text PRIMARY KEY,
  platform text NOT NULL,
  country_code text,
  first_seen_at text NOT NULL,
  last_seen_at text NOT NULL,
  uid text
);

CREATE TABLE auth_identity (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES "user" (id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_uid text NOT NULL,
  created_at text NOT NULL,
  CONSTRAINT uq_auth_identity_provider UNIQUE (provider, provider_uid)
);

CREATE INDEX idx_auth_identity_user ON auth_identity (user_id);

CREATE TABLE session (
  id text PRIMARY KEY,
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  refresh_token text NOT NULL UNIQUE,
  expires_at text NOT NULL,
  created_at text NOT NULL,
  revoked_at text,
  login_method text,
  CONSTRAINT ck_session_login_method
    CHECK (login_method IS NULL OR login_method IN ('email', 'google', 'apple'))
);

CREATE INDEX idx_session_owner ON session (owner_type, owner_id);

CREATE TABLE verification_code (
  id text PRIMARY KEY,
  email text NOT NULL,
  code text NOT NULL,
  purpose text NOT NULL,
  expires_at text NOT NULL,
  used_at text,
  created_at text NOT NULL
);

CREATE INDEX idx_verification_code_email
  ON verification_code (email, purpose, created_at);

CREATE TABLE cards_all (
  product_id text PRIMARY KEY,
  game_id integer NOT NULL,
  game text,
  set_name text,
  set_code text,
  set_id text,
  name text,
  rarity text,
  description text,
  product_type_name text,
  foil_only integer DEFAULT 0,
  normal_only integer DEFAULT 0,
  created_at text DEFAULT (to_char(CURRENT_TIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS')),
  updated_at text DEFAULT (to_char(CURRENT_TIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS')),
  card_type text,
  full_type text,
  color text,
  converted_cost text,
  flavor_text text,
  power text,
  power_number text,
  toughness text,
  has_image integer NOT NULL DEFAULT 2,
  number text
);

CREATE INDEX idx_cards_all_game_id ON cards_all (game_id);
CREATE INDEX idx_cards_all_game_product ON cards_all (game_id, product_id);
CREATE INDEX idx_cards_all_updated_product ON cards_all (updated_at DESC, product_id ASC);
CREATE INDEX idx_cards_all_game_updated_product
  ON cards_all (lower(game), updated_at DESC, product_id ASC);
CREATE INDEX idx_cards_all_game_set_updated_product
  ON cards_all (lower(game), lower(set_code), updated_at DESC, product_id ASC);

CREATE TABLE games (
  game_id integer,
  tcgcsv_id double precision,
  name varchar(50),
  total_cards integer,
  image_source varchar(50),
  images_enabled integer,
  created_at text,
  load integer,
  search_sort integer NOT NULL DEFAULT 1000
);

CREATE UNIQUE INDEX uq_games_game_id ON games (game_id);
CREATE INDEX idx_games_load_sort ON games (load, search_sort, game_id);

CREATE TABLE sets (
  set_id text PRIMARY KEY,
  game text NOT NULL,
  name text NOT NULL,
  set_code text,
  total_cards integer DEFAULT 0,
  set_image_id text,
  CONSTRAINT uq_sets_game_name UNIQUE (game, name)
);

CREATE INDEX idx_sets_game_name_search ON sets (lower(game), name);

CREATE TABLE portfolio_folder (
  id text PRIMARY KEY,
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  name text NOT NULL,
  is_default integer NOT NULL DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  created_at text NOT NULL,
  updated_at text NOT NULL,
  CONSTRAINT uq_portfolio_folder_name UNIQUE (owner_type, owner_id, name),
  CONSTRAINT ck_portfolio_folder_is_default CHECK (is_default IN (0, 1))
);

CREATE INDEX idx_portfolio_folder_owner
  ON portfolio_folder (owner_type, owner_id, sort_order);

CREATE TABLE collection_item (
  id text PRIMARY KEY,
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  folder_id text NOT NULL REFERENCES portfolio_folder (id) ON DELETE CASCADE,
  card_ref text NOT NULL,
  object_type text NOT NULL,
  grader text NOT NULL,
  condition text,
  grade double precision,
  language text,
  finish text,
  quantity integer NOT NULL DEFAULT 1,
  purchase_price double precision,
  purchase_currency text,
  notes text,
  created_at text NOT NULL,
  updated_at text NOT NULL,
  folder_joined_at text,
  performance_start_at text,
  purchase_price_effective_at text,
  performance_history_available_from text,
  CONSTRAINT ck_collection_item_quantity CHECK (quantity >= 1)
);

CREATE INDEX idx_collection_item_owner
  ON collection_item (owner_type, owner_id, card_ref);
CREATE INDEX idx_collection_item_folder ON collection_item (folder_id);
CREATE INDEX idx_collection_item_card ON collection_item (card_ref);
CREATE UNIQUE INDEX uq_collection_item_folder_card_finish_language
  ON collection_item (
    owner_type, owner_id, folder_id, card_ref,
    COALESCE(finish, ''), COALESCE(language, '')
  );

CREATE TABLE collection_item_event (
  id text PRIMARY KEY,
  item_id text NOT NULL,
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  folder_id text NOT NULL,
  card_ref text NOT NULL,
  object_type text NOT NULL,
  grader text NOT NULL,
  condition text,
  grade double precision,
  language text,
  finish text,
  quantity integer NOT NULL,
  event_type text NOT NULL,
  effective_at text NOT NULL,
  purchase_price double precision,
  purchase_currency text,
  performance_history_available_from text,
  CONSTRAINT ck_collection_item_event_quantity CHECK (quantity >= 1),
  CONSTRAINT ck_collection_item_event_type CHECK (event_type IN ('upsert', 'delete'))
);

CREATE INDEX idx_collection_item_event_owner_time
  ON collection_item_event (owner_type, owner_id, effective_at);
CREATE INDEX idx_collection_item_event_folder_time
  ON collection_item_event (folder_id, effective_at);
CREATE INDEX idx_collection_item_event_item_time
  ON collection_item_event (item_id, effective_at);
CREATE INDEX idx_collection_item_event_performance_history
  ON collection_item_event (owner_type, owner_id, performance_history_available_from);

CREATE TABLE wishlist_item (
  id text PRIMARY KEY,
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  card_ref text NOT NULL,
  created_at text NOT NULL,
  CONSTRAINT uq_wishlist_item_card UNIQUE (owner_type, owner_id, card_ref)
);

CREATE INDEX idx_wishlist_item_owner ON wishlist_item (owner_type, owner_id);

CREATE TABLE user_preference (
  id text PRIMARY KEY,
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  currency text NOT NULL DEFAULT 'USD',
  amount_hidden integer NOT NULL DEFAULT 0,
  last_selected_folder_id text,
  created_at text NOT NULL,
  updated_at text NOT NULL,
  CONSTRAINT uq_user_preference_owner UNIQUE (owner_type, owner_id),
  CONSTRAINT ck_user_preference_amount_hidden CHECK (amount_hidden IN (0, 1))
);

CREATE TABLE scan_record (
  id text PRIMARY KEY,
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  image_url text,
  filename text NOT NULL,
  platform text NOT NULL,
  app_version text NOT NULL,
  device_model text,
  os_version text,
  recognition_status text NOT NULL,
  user_confirmation_status text NOT NULL,
  modified_result integer NOT NULL DEFAULT 0,
  system_result text NOT NULL,
  user_result text NOT NULL,
  candidates text NOT NULL,
  raw_response text NOT NULL,
  created_at text NOT NULL,
  CONSTRAINT ck_scan_record_modified_result CHECK (modified_result IN (0, 1))
);

CREATE INDEX idx_scan_record_created_at ON scan_record (created_at);
CREATE INDEX idx_scan_record_owner ON scan_record (owner_type, owner_id, created_at);

CREATE TABLE scan_quota_request (
  request_id text PRIMARY KEY,
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  session_id text NOT NULL REFERENCES session (id),
  access_mode text NOT NULL,
  status text NOT NULL,
  scan_id text,
  processing_expires_at text,
  attempts integer NOT NULL DEFAULT 1,
  response_json text,
  http_status integer,
  created_at text NOT NULL,
  settled_at text,
  updated_at text NOT NULL,
  CONSTRAINT ck_scan_quota_request_access_mode CHECK (access_mode IN ('free', 'premium')),
  CONSTRAINT ck_scan_quota_request_status CHECK (status IN ('reserved', 'consumed', 'released'))
);

CREATE INDEX idx_scan_quota_request_owner_status
  ON scan_quota_request (owner_type, owner_id, status, created_at);

CREATE TABLE billing_product (
  id text PRIMARY KEY,
  store text NOT NULL,
  product_id text NOT NULL,
  plan_id text NOT NULL,
  entitlement_id text NOT NULL,
  product_type text NOT NULL,
  active integer NOT NULL DEFAULT 1,
  created_at text NOT NULL,
  updated_at text NOT NULL,
  CONSTRAINT uq_billing_product_store_product UNIQUE (store, product_id),
  CONSTRAINT uq_billing_product_store_plan UNIQUE (store, plan_id),
  CONSTRAINT ck_billing_product_active CHECK (active IN (0, 1))
);

CREATE TABLE billing_purchase_chain (
  id text PRIMARY KEY,
  store text NOT NULL,
  environment text NOT NULL,
  original_transaction_id text NOT NULL,
  product_id text NOT NULL,
  entitlement_id text NOT NULL,
  original_owner_type text NOT NULL,
  original_owner_id text NOT NULL,
  app_account_token text,
  status text NOT NULL,
  auto_renew integer NOT NULL DEFAULT 0,
  expires_at text,
  grace_period_expires_at text,
  revoked_at text,
  created_at text NOT NULL,
  updated_at text NOT NULL,
  state_effective_at text,
  next_product_id text,
  lifecycle_signed_at text,
  lifecycle_notification_uuid text,
  correction_status text,
  auto_renew_signed_at text,
  plan_signed_at text,
  CONSTRAINT uq_billing_chain_store_environment_original
    UNIQUE (store, environment, original_transaction_id),
  CONSTRAINT ck_billing_chain_auto_renew CHECK (auto_renew IN (0, 1))
);

CREATE INDEX idx_billing_chain_owner
  ON billing_purchase_chain (original_owner_type, original_owner_id);
CREATE INDEX idx_billing_chain_status_expiry
  ON billing_purchase_chain (status, expires_at);

CREATE TABLE billing_transaction (
  id text PRIMARY KEY,
  purchase_chain_id text NOT NULL REFERENCES billing_purchase_chain (id),
  store text NOT NULL,
  environment text NOT NULL,
  transaction_id text NOT NULL,
  product_id text NOT NULL,
  transaction_reason text NOT NULL,
  status text NOT NULL,
  storefront_country_code text,
  amount_micros bigint,
  currency text,
  amount_usd_micros bigint,
  purchase_at text NOT NULL,
  expires_at text,
  revoked_at text,
  signed_transaction text,
  created_at text NOT NULL,
  updated_at text NOT NULL,
  refund_completed_at text,
  business_status text,
  charge_count integer,
  source_notification_uuid text,
  usd_exchange_rate text,
  usd_exchange_rate_base text,
  usd_exchange_rate_quote text,
  usd_exchange_rate_source text,
  usd_exchange_rate_effective_at text,
  usd_exchange_rate_fetched_at text,
  usd_exchange_rate_stale integer,
  usd_conversion_version text,
  usd_rounding_mode text,
  auto_renew_snapshot integer,
  CONSTRAINT ck_billing_transaction_auto_renew_snapshot
    CHECK (auto_renew_snapshot IS NULL OR auto_renew_snapshot IN (0, 1)),
  CONSTRAINT uq_billing_transaction_store_environment_transaction
    UNIQUE (store, environment, transaction_id)
);

CREATE INDEX idx_billing_transaction_chain_time
  ON billing_transaction (purchase_chain_id, purchase_at);
CREATE INDEX idx_billing_transaction_status_time
  ON billing_transaction (status, purchase_at);
CREATE INDEX idx_billing_transaction_product_time
  ON billing_transaction (product_id, purchase_at);
CREATE INDEX idx_billing_transaction_business_status_time
  ON billing_transaction (business_status, purchase_at);
CREATE INDEX idx_billing_transaction_charge_count
  ON billing_transaction (charge_count, purchase_at);

CREATE TABLE billing_entitlement_grant (
  id text PRIMARY KEY,
  purchase_chain_id text NOT NULL REFERENCES billing_purchase_chain (id),
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  source text NOT NULL,
  status text NOT NULL,
  granted_at text NOT NULL,
  revoked_at text,
  updated_at text NOT NULL,
  CONSTRAINT uq_billing_grant_chain_owner
    UNIQUE (purchase_chain_id, owner_type, owner_id)
);

CREATE INDEX idx_billing_grant_owner_status
  ON billing_entitlement_grant (owner_type, owner_id, status);

CREATE TABLE billing_session_entitlement_grant (
  id text PRIMARY KEY,
  session_id text NOT NULL REFERENCES session (id),
  purchase_chain_id text NOT NULL REFERENCES billing_purchase_chain (id),
  entitlement_id text NOT NULL,
  source text NOT NULL,
  status text NOT NULL,
  granted_at text NOT NULL,
  expires_at text,
  last_verified_at text NOT NULL,
  revoked_at text,
  updated_at text NOT NULL,
  CONSTRAINT uq_billing_session_grant_session_chain_entitlement
    UNIQUE (session_id, purchase_chain_id, entitlement_id),
  CONSTRAINT ck_billing_session_grant_status
    CHECK (status IN ('active', 'revoked', 'expired'))
);

CREATE INDEX idx_billing_session_grant_session_status_expiry
  ON billing_session_entitlement_grant (session_id, entitlement_id, status, expires_at);
CREATE INDEX idx_billing_session_grant_chain_status
  ON billing_session_entitlement_grant (purchase_chain_id, status);

CREATE TABLE billing_apple_purchase_challenge (
  token text PRIMARY KEY,
  session_id text NOT NULL REFERENCES session (id),
  product_id text NOT NULL,
  expires_at text NOT NULL,
  consumed_at text,
  consumed_transaction_id text,
  created_at text NOT NULL
);

CREATE INDEX idx_billing_apple_challenge_session_expiry
  ON billing_apple_purchase_challenge (session_id, expires_at);

CREATE TABLE billing_apple_verification_attempt (
  id text PRIMARY KEY,
  session_id text NOT NULL REFERENCES session (id),
  request_id text NOT NULL,
  evidence_type text NOT NULL,
  evidence_sha256 text NOT NULL,
  result_code text NOT NULL,
  transaction_id text,
  response_json text NOT NULL,
  http_status integer NOT NULL,
  processing_expires_at text,
  created_at text NOT NULL,
  CONSTRAINT uq_billing_apple_attempt_session_request UNIQUE (session_id, request_id)
);

CREATE INDEX idx_billing_apple_attempt_evidence
  ON billing_apple_verification_attempt (evidence_sha256, created_at);

CREATE TABLE billing_apple_app_attest_challenge (
  token text PRIMARY KEY,
  session_id text NOT NULL REFERENCES session (id),
  purpose text NOT NULL,
  request_id text NOT NULL,
  key_id text,
  evidence_sha256 text,
  client_data text NOT NULL,
  expires_at text NOT NULL,
  consumed_at text,
  consumption_id text,
  result_code text,
  response_json text,
  http_status integer,
  created_at text NOT NULL,
  CONSTRAINT uq_billing_app_attest_challenge_request UNIQUE (session_id, request_id),
  CONSTRAINT ck_billing_app_attest_challenge_purpose
    CHECK (purpose IN ('register', 'restore'))
);

CREATE INDEX idx_billing_app_attest_challenge_expiry
  ON billing_apple_app_attest_challenge (session_id, expires_at);

CREATE TABLE billing_apple_app_attest_key (
  key_id text PRIMARY KEY,
  public_key_pem text NOT NULL,
  receipt_base64 text NOT NULL,
  sign_count integer NOT NULL DEFAULT 0,
  environment text NOT NULL,
  registered_session_id text NOT NULL REFERENCES session (id),
  status text NOT NULL DEFAULT 'active',
  created_at text NOT NULL,
  updated_at text NOT NULL,
  CONSTRAINT ck_billing_app_attest_key_environment
    CHECK (environment IN ('development', 'production')),
  CONSTRAINT ck_billing_app_attest_key_status
    CHECK (status IN ('active', 'revoked'))
);

CREATE INDEX idx_billing_app_attest_key_status
  ON billing_apple_app_attest_key (status, updated_at);

CREATE TABLE apple_notification_inbox (
  id text PRIMARY KEY,
  payload_sha256 text NOT NULL UNIQUE,
  request_json text NOT NULL,
  signed_payload text NOT NULL,
  processing_status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  processing_expires_at text,
  notification_uuid text,
  last_error text,
  received_at text NOT NULL,
  processed_at text,
  CONSTRAINT ck_apple_notification_inbox_status CHECK (
    processing_status IN (
      'pending', 'processing', 'processed', 'verification_failed', 'parse_failed',
      'correction_required', 'processing_failed'
    )
  )
);

CREATE INDEX idx_apple_notification_inbox_processing
  ON apple_notification_inbox (processing_status, processing_expires_at, received_at);

CREATE TABLE apple_server_notification (
  id text PRIMARY KEY,
  notification_uuid text NOT NULL UNIQUE,
  notification_type text NOT NULL,
  subtype text,
  environment text NOT NULL,
  original_transaction_id text,
  transaction_id text,
  product_id text,
  signed_payload text NOT NULL,
  decoded_payload text,
  processing_status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  signed_at text,
  received_at text NOT NULL,
  processed_at text,
  inbox_id text REFERENCES apple_notification_inbox (id),
  CONSTRAINT uq_apple_notification_inbox_id UNIQUE (inbox_id)
);

CREATE INDEX idx_apple_notification_received
  ON apple_server_notification (received_at);
CREATE INDEX idx_apple_notification_type_received
  ON apple_server_notification (notification_type, received_at);
CREATE INDEX idx_apple_notification_transaction
  ON apple_server_notification (original_transaction_id);
CREATE INDEX idx_apple_notification_processing
  ON apple_server_notification (processing_status, received_at);

CREATE TABLE admin_user (
  id text PRIMARY KEY,
  email text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  role text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at text NOT NULL
);

CREATE TABLE card_override (
  id text PRIMARY KEY,
  card_ref text NOT NULL UNIQUE,
  override_fields text,
  image_url text,
  is_missing_card integer NOT NULL DEFAULT 0,
  updated_by text,
  updated_at text NOT NULL,
  CONSTRAINT ck_card_override_is_missing CHECK (is_missing_card IN (0, 1))
);

CREATE TABLE trending_pin (
  id text PRIMARY KEY,
  card_ref text NOT NULL UNIQUE,
  rank integer NOT NULL,
  active integer NOT NULL DEFAULT 1,
  updated_by text,
  updated_at text NOT NULL,
  CONSTRAINT ck_trending_pin_active CHECK (active IN (0, 1))
);

CREATE INDEX idx_trending_pin_rank ON trending_pin (active, rank);

CREATE TABLE app_config (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_by text,
  updated_at text NOT NULL
);

CREATE TABLE feedback_ticket (
  id text PRIMARY KEY,
  email text NOT NULL,
  types text NOT NULL,
  functions text NOT NULL,
  message text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  created_at text NOT NULL,
  updated_at text NOT NULL,
  uid text
);

CREATE INDEX idx_feedback_ticket_status ON feedback_ticket (status, created_at);
