CREATE TABLE `billing_product` (
  `id` text PRIMARY KEY NOT NULL,
  `store` text NOT NULL,
  `product_id` text NOT NULL,
  `plan_id` text NOT NULL,
  `entitlement_id` text NOT NULL,
  `product_type` text NOT NULL,
  `active` integer DEFAULT 1 NOT NULL,
  `created_at` text NOT NULL,
  `updated_at` text NOT NULL,
  CONSTRAINT `uq_billing_product_store_product` UNIQUE(`store`, `product_id`),
  CONSTRAINT `uq_billing_product_store_plan` UNIQUE(`store`, `plan_id`),
  CONSTRAINT `ck_billing_product_active` CHECK (`active` IN (0, 1))
);
--> statement-breakpoint
CREATE TABLE `billing_purchase_chain` (
  `id` text PRIMARY KEY NOT NULL,
  `store` text NOT NULL,
  `environment` text NOT NULL,
  `original_transaction_id` text NOT NULL,
  `product_id` text NOT NULL,
  `entitlement_id` text NOT NULL,
  `original_owner_type` text NOT NULL,
  `original_owner_id` text NOT NULL,
  `app_account_token` text,
  `status` text NOT NULL,
  `auto_renew` integer DEFAULT 0 NOT NULL,
  `expires_at` text,
  `grace_period_expires_at` text,
  `revoked_at` text,
  `created_at` text NOT NULL,
  `updated_at` text NOT NULL,
  CONSTRAINT `uq_billing_chain_store_environment_original` UNIQUE(`store`, `environment`, `original_transaction_id`),
  CONSTRAINT `ck_billing_chain_auto_renew` CHECK (`auto_renew` IN (0, 1))
);
--> statement-breakpoint
CREATE INDEX `idx_billing_chain_owner` ON `billing_purchase_chain` (`original_owner_type`, `original_owner_id`);
CREATE INDEX `idx_billing_chain_status_expiry` ON `billing_purchase_chain` (`status`, `expires_at`);
CREATE TABLE `billing_transaction` (
  `id` text PRIMARY KEY NOT NULL,
  `purchase_chain_id` text NOT NULL REFERENCES `billing_purchase_chain`(`id`),
  `store` text NOT NULL,
  `environment` text NOT NULL,
  `transaction_id` text NOT NULL,
  `product_id` text NOT NULL,
  `transaction_reason` text NOT NULL,
  `status` text NOT NULL,
  `storefront_country_code` text,
  `amount_micros` integer,
  `currency` text,
  `amount_usd_micros` integer,
  `purchase_at` text NOT NULL,
  `expires_at` text,
  `revoked_at` text,
  `signed_transaction` text,
  `created_at` text NOT NULL,
  `updated_at` text NOT NULL,
  CONSTRAINT `uq_billing_transaction_store_environment_transaction` UNIQUE(`store`, `environment`, `transaction_id`)
);
--> statement-breakpoint
CREATE INDEX `idx_billing_transaction_chain_time` ON `billing_transaction` (`purchase_chain_id`, `purchase_at`);
CREATE INDEX `idx_billing_transaction_status_time` ON `billing_transaction` (`status`, `purchase_at`);
CREATE INDEX `idx_billing_transaction_product_time` ON `billing_transaction` (`product_id`, `purchase_at`);
CREATE TABLE `billing_entitlement_grant` (
  `id` text PRIMARY KEY NOT NULL,
  `purchase_chain_id` text NOT NULL REFERENCES `billing_purchase_chain`(`id`),
  `owner_type` text NOT NULL,
  `owner_id` text NOT NULL,
  `source` text NOT NULL,
  `status` text NOT NULL,
  `granted_at` text NOT NULL,
  `revoked_at` text,
  `updated_at` text NOT NULL,
  CONSTRAINT `uq_billing_grant_chain_owner` UNIQUE(`purchase_chain_id`, `owner_type`, `owner_id`)
);
--> statement-breakpoint
CREATE INDEX `idx_billing_grant_owner_status` ON `billing_entitlement_grant` (`owner_type`, `owner_id`, `status`);
CREATE TABLE `apple_server_notification` (
  `id` text PRIMARY KEY NOT NULL,
  `notification_uuid` text NOT NULL UNIQUE,
  `notification_type` text NOT NULL,
  `subtype` text,
  `environment` text NOT NULL,
  `original_transaction_id` text,
  `transaction_id` text,
  `product_id` text,
  `signed_payload` text NOT NULL,
  `decoded_payload` text,
  `processing_status` text DEFAULT 'pending' NOT NULL,
  `attempts` integer DEFAULT 0 NOT NULL,
  `last_error` text,
  `signed_at` text,
  `received_at` text NOT NULL,
  `processed_at` text
);
--> statement-breakpoint
CREATE INDEX `idx_apple_notification_received` ON `apple_server_notification` (`received_at`);
CREATE INDEX `idx_apple_notification_type_received` ON `apple_server_notification` (`notification_type`, `received_at`);
CREATE INDEX `idx_apple_notification_transaction` ON `apple_server_notification` (`original_transaction_id`);
CREATE INDEX `idx_apple_notification_processing` ON `apple_server_notification` (`processing_status`, `received_at`);
