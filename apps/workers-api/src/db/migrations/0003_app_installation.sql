CREATE TABLE `app_installation` (
  `installation_id` text PRIMARY KEY NOT NULL,
  `platform` text NOT NULL,
  `country_code` text,
  `first_seen_at` text NOT NULL,
  `last_seen_at` text NOT NULL
);
--> statement-breakpoint
INSERT OR IGNORE INTO `app_installation`
  (`installation_id`, `platform`, `country_code`, `first_seen_at`, `last_seen_at`)
SELECT `device_id`, 'iOS', NULL, MIN(`created_at`), MAX(`created_at`)
FROM `anonymous_account`
GROUP BY `device_id`;
