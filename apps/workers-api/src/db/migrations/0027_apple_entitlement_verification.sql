ALTER TABLE `billing_purchase_chain` ADD `state_effective_at` text;
--> statement-breakpoint
CREATE TABLE `billing_apple_purchase_challenge` (
  `token` text PRIMARY KEY NOT NULL,
  `session_id` text NOT NULL REFERENCES `session`(`id`),
  `product_id` text NOT NULL,
  `expires_at` text NOT NULL,
  `consumed_at` text,
  `consumed_transaction_id` text,
  `created_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_billing_apple_challenge_session_expiry` ON `billing_apple_purchase_challenge` (`session_id`, `expires_at`);
--> statement-breakpoint
CREATE TABLE `billing_apple_verification_attempt` (
  `id` text PRIMARY KEY NOT NULL,
  `session_id` text NOT NULL REFERENCES `session`(`id`),
  `request_id` text NOT NULL,
  `evidence_type` text NOT NULL,
  `evidence_sha256` text NOT NULL,
  `result_code` text NOT NULL,
  `transaction_id` text,
  `response_json` text NOT NULL,
  `http_status` integer NOT NULL,
  `processing_expires_at` text,
  `created_at` text NOT NULL,
  CONSTRAINT `uq_billing_apple_attempt_session_request` UNIQUE(`session_id`, `request_id`)
);
--> statement-breakpoint
CREATE INDEX `idx_billing_apple_attempt_evidence` ON `billing_apple_verification_attempt` (`evidence_sha256`, `created_at`);
