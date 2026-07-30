CREATE TABLE `account_uid` (
  `uid` integer PRIMARY KEY NOT NULL,
  `created_at` text NOT NULL,
  CONSTRAINT `ck_account_uid_minimum` CHECK (`uid` >= 100000)
);
--> statement-breakpoint
ALTER TABLE `app_installation` ADD COLUMN `uid` text;
--> statement-breakpoint
ALTER TABLE `feedback_ticket` ADD COLUMN `uid` text;
