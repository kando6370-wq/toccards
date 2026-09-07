ALTER TABLE `collection_item` ADD `performance_start_at` text;
--> statement-breakpoint
ALTER TABLE `collection_item` ADD `purchase_price_effective_at` text;
--> statement-breakpoint
ALTER TABLE `collection_item` ADD `performance_history_available_from` text;
--> statement-breakpoint
UPDATE `collection_item`
SET `performance_start_at` = `created_at`,
    `purchase_price_effective_at` = `created_at`,
    `performance_history_available_from` = strftime('%Y-%m-%dT%H:%M:%fZ', 'now');
--> statement-breakpoint
ALTER TABLE `collection_item_event` ADD `purchase_price` real;
--> statement-breakpoint
ALTER TABLE `collection_item_event` ADD `purchase_currency` text;
--> statement-breakpoint
ALTER TABLE `collection_item_event` ADD `performance_history_available_from` text;
--> statement-breakpoint
UPDATE `collection_item_event`
SET `purchase_price` = (
      SELECT `collection_item`.`purchase_price`
      FROM `collection_item`
      WHERE `collection_item`.`id` = `collection_item_event`.`item_id`
    ),
    `purchase_currency` = (
      SELECT `collection_item`.`purchase_currency`
      FROM `collection_item`
      WHERE `collection_item`.`id` = `collection_item_event`.`item_id`
    ),
    `performance_history_available_from` = (
      SELECT `collection_item`.`performance_history_available_from`
      FROM `collection_item`
      WHERE `collection_item`.`id` = `collection_item_event`.`item_id`
    )
WHERE EXISTS (
  SELECT 1 FROM `collection_item`
  WHERE `collection_item`.`id` = `collection_item_event`.`item_id`
);
--> statement-breakpoint
CREATE INDEX `idx_collection_item_event_performance_history`
ON `collection_item_event` (`owner_type`, `owner_id`, `performance_history_available_from`);
