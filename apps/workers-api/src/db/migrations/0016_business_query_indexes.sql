CREATE INDEX `idx_cards_all_updated_product` ON `cards_all` (`updated_at` DESC, `product_id` ASC);
--> statement-breakpoint
CREATE INDEX `idx_cards_all_game_updated_product` ON `cards_all` (lower(`game`), `updated_at` DESC, `product_id` ASC);
--> statement-breakpoint
CREATE INDEX `idx_cards_all_game_set_updated_product` ON `cards_all` (lower(`game`), lower(`set_code`), `updated_at` DESC, `product_id` ASC);
--> statement-breakpoint
CREATE INDEX `idx_games_load_sort` ON `games` (`load`, `search_sort`, `game_id`);
--> statement-breakpoint
CREATE INDEX `idx_sets_game_name_search` ON `sets` (lower(`game`), `name`);
--> statement-breakpoint
CREATE INDEX `idx_anonymous_account_device_live` ON `anonymous_account` (`device_id`, `upgraded_user_id`, `created_at`);
--> statement-breakpoint
CREATE INDEX `idx_auth_identity_user` ON `auth_identity` (`user_id`);
--> statement-breakpoint
DROP INDEX `idx_verification_code_email`;
--> statement-breakpoint
CREATE INDEX `idx_verification_code_email` ON `verification_code` (`email`, `purpose`, `created_at`);
--> statement-breakpoint
DROP INDEX `idx_portfolio_folder_owner`;
--> statement-breakpoint
CREATE INDEX `idx_portfolio_folder_owner` ON `portfolio_folder` (`owner_type`, `owner_id`, `sort_order`);
--> statement-breakpoint
DROP INDEX `idx_collection_item_owner`;
--> statement-breakpoint
CREATE INDEX `idx_collection_item_owner` ON `collection_item` (`owner_type`, `owner_id`, `card_ref`);
--> statement-breakpoint
DROP INDEX `idx_scan_record_owner`;
--> statement-breakpoint
CREATE INDEX `idx_scan_record_owner` ON `scan_record` (`owner_type`, `owner_id`, `created_at`);
