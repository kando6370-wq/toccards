ALTER TABLE `games` ADD `search_sort` integer NOT NULL DEFAULT 1000;
--> statement-breakpoint
UPDATE `games`
SET `search_sort` = 0
WHERE lower(trim(coalesce(`name`, ''))) = 'pokemon';
