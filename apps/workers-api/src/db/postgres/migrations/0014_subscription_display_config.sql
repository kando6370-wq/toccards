-- Display configuration is independent from billing_product and purchase history.
CREATE TABLE subscription_display_config (
  id text PRIMARY KEY,
  scope text NOT NULL,
  page_type text NOT NULL CHECK (page_type IN ('page', 'modal')),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  body jsonb NOT NULL,
  updated_by text NOT NULL,
  updated_at text NOT NULL,
  UNIQUE (scope, page_type, id),
  CHECK (jsonb_typeof(body) = 'object'),
  CHECK (body->>'page_type' = page_type AND body->>'schema_version' = '1')
);

CREATE TABLE subscription_display_active (
  scope text NOT NULL,
  page_type text NOT NULL CHECK (page_type IN ('page', 'modal')),
  config_id text,
  revision integer NOT NULL DEFAULT 0 CHECK (revision >= 0),
  PRIMARY KEY (scope, page_type),
  FOREIGN KEY (scope, page_type, config_id)
    REFERENCES subscription_display_config (scope, page_type, id)
);

CREATE TABLE subscription_display_mutation (
  scope text NOT NULL,
  request_id text NOT NULL,
  admin_id text NOT NULL,
  payload_hash text NOT NULL,
  operation text NOT NULL,
  run_id text NOT NULL,
  http_status integer,
  response jsonb,
  created_at text NOT NULL,
  PRIMARY KEY (scope, request_id),
  CHECK ((http_status IS NULL) = (response IS NULL)),
  CHECK (http_status IS NULL OR http_status BETWEEN 200 AND 599)
);

CREATE INDEX idx_subscription_display_config_scope
  ON subscription_display_config (scope, updated_at DESC, id);
