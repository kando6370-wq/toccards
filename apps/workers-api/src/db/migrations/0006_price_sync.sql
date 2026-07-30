ALTER TABLE `tcgplayer_skus` ADD `source` text;
--> statement-breakpoint
ALTER TABLE `tcgplayer_skus` ADD `source_variant_id` text;
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_tcgplayer_skus_source_variant`
ON `tcgplayer_skus` (`source`, `source_variant_id`);
--> statement-breakpoint
CREATE TABLE `price_sync_state` (
  `source` text PRIMARY KEY NOT NULL,
  `status` text NOT NULL,
  `cursor_product_id` integer,
  `cycle_started_at` text,
  `last_attempt_at` text,
  `last_success_at` text,
  `last_completed_at` text,
  `next_run_at` text,
  `products_processed` integer DEFAULT 0 NOT NULL,
  `variants_written` integer DEFAULT 0 NOT NULL,
  `covered_products` integer DEFAULT 0 NOT NULL,
  `total_products` integer DEFAULT 0 NOT NULL,
  `last_error` text
);
