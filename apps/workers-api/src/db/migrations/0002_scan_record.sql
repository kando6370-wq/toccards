CREATE TABLE `scan_record` (
  `id` text PRIMARY KEY NOT NULL,
  `owner_type` text NOT NULL,
  `owner_id` text NOT NULL,
  `image_url` text,
  `filename` text NOT NULL,
  `platform` text NOT NULL,
  `app_version` text NOT NULL,
  `device_model` text,
  `os_version` text,
  `recognition_status` text NOT NULL,
  `user_confirmation_status` text NOT NULL,
  `modified_result` integer DEFAULT 0 NOT NULL,
  `system_result` text NOT NULL,
  `user_result` text NOT NULL,
  `candidates` text NOT NULL,
  `raw_response` text NOT NULL,
  `created_at` text NOT NULL,
  CONSTRAINT `ck_scan_record_modified_result` CHECK(`modified_result` IN (0, 1))
);
--> statement-breakpoint
CREATE INDEX `idx_scan_record_owner` ON `scan_record` (`owner_type`,`owner_id`);--> statement-breakpoint
CREATE INDEX `idx_scan_record_created_at` ON `scan_record` (`created_at`);
