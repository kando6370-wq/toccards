CREATE TABLE `collection_item_event` (
	`id` text PRIMARY KEY NOT NULL,
	`item_id` text NOT NULL,
	`owner_type` text NOT NULL,
	`owner_id` text NOT NULL,
	`folder_id` text NOT NULL,
	`card_ref` text NOT NULL,
	`object_type` text NOT NULL,
	`grader` text NOT NULL,
	`condition` text,
	`grade` real,
	`language` text,
	`finish` text,
	`quantity` integer NOT NULL,
	`event_type` text NOT NULL,
	`effective_at` text NOT NULL,
	CONSTRAINT "ck_collection_item_event_quantity" CHECK("collection_item_event"."quantity" >= 1),
	CONSTRAINT "ck_collection_item_event_type" CHECK("collection_item_event"."event_type" IN ('upsert', 'delete'))
);
--> statement-breakpoint
CREATE INDEX `idx_collection_item_event_owner_time` ON `collection_item_event` (`owner_type`,`owner_id`,`effective_at`);
--> statement-breakpoint
CREATE INDEX `idx_collection_item_event_folder_time` ON `collection_item_event` (`folder_id`,`effective_at`);
--> statement-breakpoint
CREATE INDEX `idx_collection_item_event_item_time` ON `collection_item_event` (`item_id`,`effective_at`);
--> statement-breakpoint
INSERT INTO `collection_item_event`
  (`id`, `item_id`, `owner_type`, `owner_id`, `folder_id`, `card_ref`, `object_type`,
   `grader`, `condition`, `grade`, `language`, `finish`, `quantity`, `event_type`, `effective_at`)
SELECT 'initial:' || `id`, `id`, `owner_type`, `owner_id`, `folder_id`, `card_ref`, `object_type`,
  `grader`, `condition`, `grade`, `language`, `finish`, `quantity`, 'upsert', `created_at`
FROM `collection_item`;
