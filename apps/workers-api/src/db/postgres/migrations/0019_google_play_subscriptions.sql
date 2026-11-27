CREATE TABLE google_play_session_build (
  session_id text PRIMARY KEY REFERENCES session(id) ON DELETE CASCADE,
  package_name text NOT NULL,
  certificate_digest text NOT NULL,
  version_code integer NOT NULL CHECK (version_code BETWEEN 1 AND 2100000000),
  verified_at text NOT NULL
);

CREATE TABLE google_play_rollout (
  scope text PRIMARY KEY,
  cutoff_at timestamptz NOT NULL,
  minimum_build integer NOT NULL CHECK (minimum_build > 0),
  metering_enabled boolean NOT NULL DEFAULT false,
  sales_enabled boolean NOT NULL DEFAULT false
);
CREATE TABLE google_play_legacy_space (
  scope text NOT NULL REFERENCES google_play_rollout(scope),
  owner_type text NOT NULL CHECK (owner_type IN ('anonymous','user')),
  owner_id text NOT NULL,
  created_at text NOT NULL,
  PRIMARY KEY (scope, owner_type, owner_id)
);

-- Run once per approved environment/package, then enable sales separately.
CREATE FUNCTION google_play_prepare_rollout(target_scope text, cutoff timestamptz, first_build integer)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF cutoff > CURRENT_TIMESTAMP OR target_scope !~ '^(production|development):google_play:[A-Za-z0-9_.]+$' THEN
    RAISE EXCEPTION 'Invalid Play rollout cutoff or scope';
  END IF;
  LOCK TABLE anonymous_account, platform_account IN SHARE MODE;
  INSERT INTO google_play_rollout(scope, cutoff_at, minimum_build) VALUES(target_scope, cutoff, first_build);
  INSERT INTO google_play_legacy_space(scope, owner_type, owner_id, created_at)
    SELECT target_scope, 'anonymous', id, created_at FROM anonymous_account
    WHERE platform = 'android' AND status = 'active' AND created_at::timestamptz < cutoff
    UNION ALL
    SELECT target_scope, 'user', id, created_at FROM platform_account
    WHERE platform = 'android' AND status = 'active' AND created_at::timestamptz < cutoff;
END;
$$;

CREATE TABLE google_play_test_space (
  scope text NOT NULL, owner_id text NOT NULL REFERENCES platform_account(id), PRIMARY KEY(scope, owner_id)
);
CREATE TABLE google_play_product (
  scope text NOT NULL, product_id text NOT NULL, base_plan_id text NOT NULL, offer_id text NOT NULL DEFAULT '',
  revenue_event text NOT NULL, revision integer NOT NULL DEFAULT 1,
  PRIMARY KEY(scope, product_id, base_plan_id, offer_id)
);
CREATE TABLE google_play_display (
  scope text NOT NULL, placement text NOT NULL CHECK (placement IN ('page','modal')),
  draft jsonb NOT NULL, published jsonb, revision integer NOT NULL,
  PRIMARY KEY(scope,placement)
);
CREATE TABLE google_play_audit (
  scope text NOT NULL, request_id text NOT NULL, admin_id text NOT NULL, action text NOT NULL,
  payload_hash text NOT NULL, before_value jsonb, after_value jsonb, reason text NOT NULL, created_at text NOT NULL,
  PRIMARY KEY(scope, request_id)
);
CREATE TABLE google_play_account (
  scope text NOT NULL, owner_id text NOT NULL REFERENCES platform_account(id), account_ref text NOT NULL,
  PRIMARY KEY(scope, owner_id), UNIQUE(scope, account_ref)
);
CREATE TABLE google_play_purchase (
  scope text NOT NULL, token_hash text NOT NULL, token_encrypted text NOT NULL,
  owner_id text REFERENCES platform_account(id), chain_id text NOT NULL, previous_hash text,
  store_kind text CHECK (store_kind IN ('test','live')), state text NOT NULL DEFAULT 'UNKNOWN',
  product_id text, base_plan_id text, offer_id text, expires_at text, auto_renew boolean,
  superseded boolean NOT NULL DEFAULT false, granted boolean NOT NULL DEFAULT false, acknowledgement text, latest_order_id text, country text,
  lease_id text, lease_until text, next_check_at text, attempts integer NOT NULL DEFAULT 0, last_error text,
  checked_at text, PRIMARY KEY(scope,token_hash)
);
CREATE FUNCTION google_play_supersede_purchase(target_scope text, predecessor text, sealed text,
  expected_owner text, stable_chain text, purchase_kind text, due_at text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO google_play_purchase(scope,token_hash,token_encrypted,owner_id,chain_id,store_kind,superseded,next_check_at)
    VALUES(target_scope,predecessor,sealed,expected_owner,stable_chain,purchase_kind,true,due_at)
    ON CONFLICT(scope,token_hash) DO UPDATE SET superseded=true,granted=false,
      owner_id=excluded.owner_id,store_kind=excluded.store_kind,next_check_at=excluded.next_check_at
    WHERE (google_play_purchase.owner_id IS NULL OR google_play_purchase.owner_id=excluded.owner_id)
      AND (google_play_purchase.store_kind IS NULL OR google_play_purchase.store_kind=excluded.store_kind);
  IF NOT FOUND THEN RAISE EXCEPTION 'GOOGLE_PLAY_OWNER_CONFLICT'; END IF;
END;
$$;
CREATE INDEX idx_google_play_owner ON google_play_purchase(scope,owner_id,expires_at) WHERE granted;
CREATE INDEX idx_google_play_next_check ON google_play_purchase(scope,next_check_at);
CREATE TABLE google_play_verify_request (
  scope text NOT NULL, owner_id text NOT NULL, request_id text NOT NULL, token_hash text NOT NULL,
  result jsonb, status_code integer, created_at text NOT NULL, PRIMARY KEY(scope,owner_id,request_id)
);
CREATE TABLE google_play_inbox (
  scope text NOT NULL, topic text NOT NULL, message_id text NOT NULL, kind text NOT NULL,
  event_at text NOT NULL, received_at text NOT NULL, token_hash text, order_id text, token_encrypted text,
  state text NOT NULL, attempts integer NOT NULL DEFAULT 0, next_check_at text, last_error text,
  PRIMARY KEY(scope,topic,message_id)
);
CREATE INDEX idx_google_play_inbox_due ON google_play_inbox(scope,next_check_at);
CREATE TABLE google_play_order (
  scope text NOT NULL, store_kind text NOT NULL CHECK (store_kind IN ('test','live')), order_id text NOT NULL,
  token_hash text NOT NULL, owner_id text, product_id text, base_plan_id text, country text,
  currency text, total_micros bigint, tax_micros bigint, fx_snapshot jsonb, checked_at text, sync_revision text, next_check_at text,
  PRIMARY KEY(scope,store_kind,order_id)
);
CREATE TABLE google_play_order_event (
  scope text NOT NULL, store_kind text NOT NULL, order_id text NOT NULL, event_key text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('charge','refund')), event_at text NOT NULL,
  amount_micros bigint, usd_micros bigint,
  PRIMARY KEY(scope,store_kind,order_id,event_key),
  FOREIGN KEY(scope,store_kind,order_id) REFERENCES google_play_order(scope,store_kind,order_id)
);
CREATE INDEX idx_google_play_order_event_time ON google_play_order_event(scope,store_kind,event_at);
ALTER TABLE scan_quota_request ADD COLUMN google_play_cohort text;
CREATE INDEX idx_google_play_metered_scans ON scan_quota_request(owner_type,owner_id,google_play_cohort,status)
  WHERE google_play_cohort IS NOT NULL AND access_mode = 'free';
CREATE TABLE google_play_voided_cursor (
  scope text PRIMARY KEY, start_ms bigint NOT NULL, end_ms bigint NOT NULL,
  page_token text, scanned_through_ms bigint, revision integer NOT NULL DEFAULT 0
);
