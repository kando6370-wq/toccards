CREATE TABLE `billing_apple_app_attest_challenge` (
  `token` text PRIMARY KEY NOT NULL,
  `session_id` text NOT NULL REFERENCES `session`(`id`),
  `purpose` text NOT NULL CHECK (`purpose` IN ('register', 'restore')),
  `request_id` text NOT NULL,
  `key_id` text,
  `evidence_sha256` text,
  `client_data` text NOT NULL,
  `expires_at` text NOT NULL,
  `consumed_at` text,
  `consumption_id` text,
  `result_code` text,
  `response_json` text,
  `http_status` integer,
  `created_at` text NOT NULL,
  CONSTRAINT `uq_billing_app_attest_challenge_request` UNIQUE(`session_id`, `request_id`)
);
--> statement-breakpoint
CREATE INDEX `idx_billing_app_attest_challenge_expiry` ON `billing_apple_app_attest_challenge` (`session_id`, `expires_at`);
--> statement-breakpoint
CREATE TABLE `billing_apple_app_attest_key` (
  `key_id` text PRIMARY KEY NOT NULL,
  `public_key_pem` text NOT NULL,
  `receipt_base64` text NOT NULL,
  `sign_count` integer NOT NULL DEFAULT 0,
  `environment` text NOT NULL CHECK (`environment` IN ('development', 'production')),
  `registered_session_id` text NOT NULL REFERENCES `session`(`id`),
  `status` text NOT NULL DEFAULT 'active' CHECK (`status` IN ('active', 'revoked')),
  `created_at` text NOT NULL,
  `updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_billing_app_attest_key_status` ON `billing_apple_app_attest_key` (`status`, `updated_at`);
