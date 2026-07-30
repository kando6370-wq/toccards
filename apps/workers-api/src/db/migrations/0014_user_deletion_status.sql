ALTER TABLE `user` ADD `status` text DEFAULT 'active' NOT NULL CHECK (`status` IN ('active', 'deleted', 'disabled'));
--> statement-breakpoint
UPDATE `user` SET `status` = 'deleted' WHERE `deleted_at` IS NOT NULL;
--> statement-breakpoint
DROP INDEX `user_email_unique`;
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_user_non_deleted_email` ON `user` (`email`) WHERE `status` <> 'deleted';
