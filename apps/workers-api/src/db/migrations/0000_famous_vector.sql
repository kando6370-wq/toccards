CREATE TABLE `admin_user` (
	`id` text PRIMARY KEY NOT NULL,
	`email` text NOT NULL,
	`password_hash` text NOT NULL,
	`role` text NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `admin_user_email_unique` ON `admin_user` (`email`);--> statement-breakpoint
CREATE TABLE `anonymous_account` (
	`id` text PRIMARY KEY NOT NULL,
	`device_id` text NOT NULL,
	`created_at` text NOT NULL,
	`upgraded_user_id` text
);
--> statement-breakpoint
CREATE TABLE `app_config` (
	`key` text PRIMARY KEY NOT NULL,
	`value` text NOT NULL,
	`updated_by` text,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `auth_identity` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`provider` text NOT NULL,
	`provider_uid` text NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_auth_identity_provider` ON `auth_identity` (`provider`,`provider_uid`);--> statement-breakpoint
CREATE TABLE `card_override` (
	`id` text PRIMARY KEY NOT NULL,
	`card_ref` text NOT NULL,
	`override_fields` text,
	`image_url` text,
	`is_missing_card` integer DEFAULT 0 NOT NULL,
	`updated_by` text,
	`updated_at` text NOT NULL,
	CONSTRAINT "ck_card_override_is_missing" CHECK("card_override"."is_missing_card" IN (0, 1))
);
--> statement-breakpoint
CREATE UNIQUE INDEX `card_override_card_ref_unique` ON `card_override` (`card_ref`);--> statement-breakpoint
CREATE TABLE `collection_item` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_type` text NOT NULL,
	`owner_id` text NOT NULL,
	`folder_id` text NOT NULL,
	`card_ref` text NOT NULL,
	`object_type` text NOT NULL,
	`grader` text NOT NULL,
	`condition` text,
	`grade` real,
	`language` text,
	`finish` text,
	`quantity` integer DEFAULT 1 NOT NULL,
	`purchase_price` real,
	`purchase_currency` text,
	`notes` text,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`folder_id`) REFERENCES `portfolio_folder`(`id`) ON UPDATE no action ON DELETE cascade,
	CONSTRAINT "ck_collection_item_quantity" CHECK("collection_item"."quantity" >= 1)
);
--> statement-breakpoint
CREATE INDEX `idx_collection_item_owner` ON `collection_item` (`owner_type`,`owner_id`);--> statement-breakpoint
CREATE INDEX `idx_collection_item_folder` ON `collection_item` (`folder_id`);--> statement-breakpoint
CREATE INDEX `idx_collection_item_card` ON `collection_item` (`card_ref`);--> statement-breakpoint
CREATE TABLE `feedback_ticket` (
	`id` text PRIMARY KEY NOT NULL,
	`email` text NOT NULL,
	`types` text NOT NULL,
	`functions` text NOT NULL,
	`message` text NOT NULL,
	`status` text DEFAULT 'open' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_feedback_ticket_status` ON `feedback_ticket` (`status`,`created_at`);--> statement-breakpoint
CREATE TABLE `portfolio_folder` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_type` text NOT NULL,
	`owner_id` text NOT NULL,
	`name` text NOT NULL,
	`is_default` integer DEFAULT 0 NOT NULL,
	`sort_order` integer DEFAULT 0 NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	CONSTRAINT "ck_portfolio_folder_is_default" CHECK("portfolio_folder"."is_default" IN (0, 1))
);
--> statement-breakpoint
CREATE INDEX `idx_portfolio_folder_owner` ON `portfolio_folder` (`owner_type`,`owner_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `uq_portfolio_folder_name` ON `portfolio_folder` (`owner_type`,`owner_id`,`name`);--> statement-breakpoint
CREATE TABLE `session` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_type` text NOT NULL,
	`owner_id` text NOT NULL,
	`refresh_token` text NOT NULL,
	`expires_at` text NOT NULL,
	`created_at` text NOT NULL,
	`revoked_at` text
);
--> statement-breakpoint
CREATE UNIQUE INDEX `session_refresh_token_unique` ON `session` (`refresh_token`);--> statement-breakpoint
CREATE INDEX `idx_session_owner` ON `session` (`owner_type`,`owner_id`);--> statement-breakpoint
CREATE TABLE `trending_pin` (
	`id` text PRIMARY KEY NOT NULL,
	`card_ref` text NOT NULL,
	`rank` integer NOT NULL,
	`active` integer DEFAULT 1 NOT NULL,
	`updated_by` text,
	`updated_at` text NOT NULL,
	CONSTRAINT "ck_trending_pin_active" CHECK("trending_pin"."active" IN (0, 1))
);
--> statement-breakpoint
CREATE UNIQUE INDEX `trending_pin_card_ref_unique` ON `trending_pin` (`card_ref`);--> statement-breakpoint
CREATE INDEX `idx_trending_pin_rank` ON `trending_pin` (`active`,`rank`);--> statement-breakpoint
CREATE TABLE `user` (
	`id` text PRIMARY KEY NOT NULL,
	`email` text NOT NULL,
	`password_hash` text,
	`display_name` text,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text
);
--> statement-breakpoint
CREATE UNIQUE INDEX `user_email_unique` ON `user` (`email`);--> statement-breakpoint
CREATE TABLE `user_preference` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_type` text NOT NULL,
	`owner_id` text NOT NULL,
	`currency` text DEFAULT 'USD' NOT NULL,
	`amount_hidden` integer DEFAULT 0 NOT NULL,
	`last_selected_folder_id` text,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_user_preference_owner` ON `user_preference` (`owner_type`,`owner_id`);--> statement-breakpoint
CREATE TABLE `verification_code` (
	`id` text PRIMARY KEY NOT NULL,
	`email` text NOT NULL,
	`code` text NOT NULL,
	`purpose` text NOT NULL,
	`expires_at` text NOT NULL,
	`used_at` text,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_verification_code_email` ON `verification_code` (`email`,`purpose`);--> statement-breakpoint
CREATE TABLE `wishlist_item` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_type` text NOT NULL,
	`owner_id` text NOT NULL,
	`card_ref` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_wishlist_item_owner` ON `wishlist_item` (`owner_type`,`owner_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `uq_wishlist_item_card` ON `wishlist_item` (`owner_type`,`owner_id`,`card_ref`);