ALTER TABLE `collection_item` ADD `folder_joined_at` text;
--> statement-breakpoint
UPDATE `collection_item`
SET `folder_joined_at` = `created_at`
WHERE `folder_joined_at` IS NULL;
