PRAGMA defer_foreign_keys = on;
--> statement-breakpoint
CREATE TABLE `__new_sets` (
	`game` text NOT NULL,
	`name` text NOT NULL,
	`set_code` text,
	`set_id` text PRIMARY KEY NOT NULL,
	`product_id` text,
	`total_cards` integer DEFAULT 0
);
--> statement-breakpoint
INSERT INTO `__new_sets` (`game`, `name`, `set_code`, `set_id`, `product_id`, `total_cards`)
SELECT `game`, `name`, `set_code`, `set_id`, `product_id`, `total_cards`
FROM `sets`;
--> statement-breakpoint
DROP TABLE `sets`;
--> statement-breakpoint
ALTER TABLE `__new_sets` RENAME TO `sets`;
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_sets_game_name` ON `sets` (`game`, `name`);
