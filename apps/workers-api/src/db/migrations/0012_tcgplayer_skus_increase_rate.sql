ALTER TABLE `tcgplayer_skus` ADD `increase_rate` real;
--> statement-breakpoint
CREATE INDEX `idx_tcgplayer_skus_increase_rate`
ON `tcgplayer_skus` (`increase_rate`);
