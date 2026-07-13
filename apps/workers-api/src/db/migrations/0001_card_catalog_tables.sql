CREATE TABLE `cards_all` (
	`product_id` text PRIMARY KEY NOT NULL,
	`game_id` integer NOT NULL,
	`game` text,
	`set_name` text,
	`set_code` text,
	`set_id` text,
	`name` text,
	`rarity` text,
	`description` text,
	`product_type_name` text,
	`foil_only` integer DEFAULT 0,
	`normal_only` integer DEFAULT 0,
	`image_url` text,
	`created_at` text DEFAULT CURRENT_TIMESTAMP,
	`updated_at` text DEFAULT CURRENT_TIMESTAMP,
	`card_type` text,
	`full_type` text,
	`color` text,
	`converted_cost` text,
	`flavor_text` text,
	`power` text,
	`power_number` text,
	`toughness` text
);
--> statement-breakpoint
CREATE INDEX `idx_cards_all_game_id` ON `cards_all` (`game_id`);--> statement-breakpoint
CREATE INDEX `idx_cards_all_game_product` ON `cards_all` (`game_id`,`product_id`);--> statement-breakpoint
CREATE TABLE `games` (
	`id` integer,
	`game_id` real,
	`name` text,
	`total_cards` integer,
	`image_source` text,
	`images_enabled` integer,
	`created_at` text,
	`load` integer
);
--> statement-breakpoint
CREATE TABLE `sets` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`game` text NOT NULL,
	`name` text NOT NULL,
	`set_name` text,
	`set_code` text,
	`set_id` text,
	`series` text,
	`total_cards` integer DEFAULT 0,
	`release_date` text,
	`created_at` text DEFAULT CURRENT_TIMESTAMP
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_sets_game_name` ON `sets` (`game`,`name`);--> statement-breakpoint
CREATE INDEX `idx_sets_set_id` ON `sets` (`set_id`);--> statement-breakpoint
CREATE TABLE `tcgplayer_skus` (
	`sku_id` integer PRIMARY KEY NOT NULL,
	`product_id` integer NOT NULL,
	`sku_key` text NOT NULL,
	`condition_code` text,
	`condition_name` text,
	`language_code` text,
	`language_name` text,
	`variant_code` text,
	`variant_name` text,
	`created_at` text DEFAULT CURRENT_TIMESTAMP,
	`updated_at` text DEFAULT CURRENT_TIMESTAMP,
	`price_history` text DEFAULT '[]' NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_tcgplayer_skus_product_id` ON `tcgplayer_skus` (`product_id`);--> statement-breakpoint
CREATE INDEX `idx_tcgplayer_skus_lookup` ON `tcgplayer_skus` (`product_id`,`language_code`,`variant_code`,`condition_code`);
