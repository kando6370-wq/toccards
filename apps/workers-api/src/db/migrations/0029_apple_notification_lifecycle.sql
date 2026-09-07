CREATE TABLE `apple_notification_inbox` (
  `id` text PRIMARY KEY NOT NULL,
  `payload_sha256` text NOT NULL UNIQUE,
  `request_json` text NOT NULL,
  `signed_payload` text NOT NULL,
  `processing_status` text NOT NULL DEFAULT 'pending',
  `attempts` integer NOT NULL DEFAULT 0,
  `processing_expires_at` text,
  `notification_uuid` text,
  `last_error` text,
  `received_at` text NOT NULL,
  `processed_at` text,
  CONSTRAINT `ck_apple_notification_inbox_status` CHECK (`processing_status` IN (
    'pending', 'processing', 'processed', 'verification_failed', 'parse_failed',
    'correction_required', 'processing_failed'
  ))
);
--> statement-breakpoint
CREATE INDEX `idx_apple_notification_inbox_processing`
ON `apple_notification_inbox` (`processing_status`, `processing_expires_at`, `received_at`);
--> statement-breakpoint
ALTER TABLE `apple_server_notification` ADD `inbox_id` text REFERENCES `apple_notification_inbox`(`id`);
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_apple_notification_inbox_id` ON `apple_server_notification` (`inbox_id`);
--> statement-breakpoint
ALTER TABLE `billing_purchase_chain` ADD `next_product_id` text;
--> statement-breakpoint
ALTER TABLE `billing_purchase_chain` ADD `lifecycle_signed_at` text;
--> statement-breakpoint
ALTER TABLE `billing_purchase_chain` ADD `lifecycle_notification_uuid` text;
--> statement-breakpoint
ALTER TABLE `billing_purchase_chain` ADD `correction_status` text;
--> statement-breakpoint
ALTER TABLE `billing_purchase_chain` ADD `auto_renew_signed_at` text;
--> statement-breakpoint
ALTER TABLE `billing_purchase_chain` ADD `plan_signed_at` text;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `refund_completed_at` text;
