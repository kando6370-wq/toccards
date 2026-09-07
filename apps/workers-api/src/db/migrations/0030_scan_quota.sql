CREATE TABLE `scan_quota_request` (
  `request_id` text PRIMARY KEY NOT NULL,
  `owner_type` text NOT NULL,
  `owner_id` text NOT NULL,
  `session_id` text NOT NULL REFERENCES `session`(`id`),
  `access_mode` text NOT NULL,
  `status` text NOT NULL,
  `scan_id` text,
  `processing_expires_at` text,
  `attempts` integer NOT NULL DEFAULT 1,
  `response_json` text,
  `http_status` integer,
  `created_at` text NOT NULL,
  `settled_at` text,
  `updated_at` text NOT NULL,
  CONSTRAINT `ck_scan_quota_request_access_mode` CHECK (`access_mode` IN ('free', 'premium')),
  CONSTRAINT `ck_scan_quota_request_status` CHECK (`status` IN ('reserved', 'consumed', 'released'))
);
--> statement-breakpoint
CREATE INDEX `idx_scan_quota_request_owner_status`
ON `scan_quota_request` (`owner_type`, `owner_id`, `status`, `created_at`);
