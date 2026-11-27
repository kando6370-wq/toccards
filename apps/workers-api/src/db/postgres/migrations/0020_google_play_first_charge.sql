-- Periods are accounting evidence from Play, independent of the current entitlement expiry.
ALTER TABLE google_play_purchase ADD COLUMN started_at text;
ALTER TABLE google_play_order ADD COLUMN period_start text, ADD COLUMN period_end text,
  ADD COLUMN free_trial boolean, ADD COLUMN period_offer_id text;

CREATE TABLE google_play_first_charge (
  scope text NOT NULL, chain_id text NOT NULL, order_id text NOT NULL, owner_id text NOT NULL,
  product_id text NOT NULL, event_name text NOT NULL, currency text NOT NULL,
  amount_micros bigint NOT NULL CHECK (amount_micros > 0), charged_at text NOT NULL,
  install_hash text, sdk_handoff_at text,
  PRIMARY KEY (scope, chain_id), UNIQUE (scope, order_id)
);
CREATE INDEX idx_google_play_first_charge_pending ON google_play_first_charge(scope, owner_id, charged_at)
  WHERE sdk_handoff_at IS NULL;
