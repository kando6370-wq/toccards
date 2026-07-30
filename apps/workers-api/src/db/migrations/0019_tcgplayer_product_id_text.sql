CREATE TABLE `__new_tcgplayer_skus` (
  `sku_id` integer PRIMARY KEY NOT NULL,
  `product_id` text NOT NULL,
  `sku_key` text NOT NULL,
  `condition_code` text,
  `condition_name` text,
  `language_code` text,
  `language_name` text,
  `variant_code` text,
  `variant_name` text,
  `created_at` text DEFAULT CURRENT_TIMESTAMP,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP,
  `price_history` text DEFAULT '[]' NOT NULL,
  `increase_rate` real
);
--> statement-breakpoint
INSERT INTO `__new_tcgplayer_skus` (
  `sku_id`, `product_id`, `sku_key`, `condition_code`, `condition_name`,
  `language_code`, `language_name`, `variant_code`, `variant_name`,
  `created_at`, `updated_at`, `price_history`, `increase_rate`
)
SELECT
  `sku_id`, CAST(`product_id` AS TEXT), `sku_key`, `condition_code`, `condition_name`,
  `language_code`, `language_name`, `variant_code`, `variant_name`,
  `created_at`, `updated_at`, `price_history`, `increase_rate`
FROM `tcgplayer_skus`;
--> statement-breakpoint
DROP TABLE `tcgplayer_skus`;
--> statement-breakpoint
ALTER TABLE `__new_tcgplayer_skus` RENAME TO `tcgplayer_skus`;
--> statement-breakpoint
CREATE INDEX `idx_tcgplayer_skus_product_id`
ON `tcgplayer_skus` (`product_id`);
--> statement-breakpoint
CREATE INDEX `idx_tcgplayer_skus_lookup`
ON `tcgplayer_skus` (`product_id`, `language_code`, `variant_code`, `condition_code`);
--> statement-breakpoint
CREATE INDEX `idx_tcgplayer_skus_increase_rate`
ON `tcgplayer_skus` (`increase_rate`);
