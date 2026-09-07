ALTER TABLE `billing_transaction` ADD `usd_exchange_rate` text;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `usd_exchange_rate_base` text;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `usd_exchange_rate_quote` text;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `usd_exchange_rate_source` text;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `usd_exchange_rate_effective_at` text;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `usd_exchange_rate_fetched_at` text;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `usd_exchange_rate_stale` integer;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `usd_conversion_version` text;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `usd_rounding_mode` text;
