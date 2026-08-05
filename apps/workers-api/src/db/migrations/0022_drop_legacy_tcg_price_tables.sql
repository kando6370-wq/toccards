CREATE TABLE IF NOT EXISTS `__tcg_price_migration_guard` (
  `ready` integer NOT NULL CHECK (`ready` = 1)
);--> statement-breakpoint
DELETE FROM `__tcg_price_migration_guard`;--> statement-breakpoint
INSERT INTO `__tcg_price_migration_guard` (`ready`)
SELECT CASE WHEN
  (SELECT COUNT(*) FROM `tcgplayer_skus`) =
    (SELECT COUNT(`sku_id`) FROM `tcg_price`)
  AND (SELECT COUNT(*) FROM `tcgplayer_skus`) =
    (SELECT COUNT(DISTINCT `sku_id`) FROM `tcg_price`)
  AND (
    SELECT COUNT(*) FROM (
      SELECT 1 FROM `tcg_price_history`
      WHERE `product_id` IS NOT NULL AND `product_sub_type` IS NOT NULL
      GROUP BY `product_id`, `product_sub_type`
    )
  ) = (
    SELECT COUNT(DISTINCT `pricecharting_id`) FROM `tcg_price`
    WHERE `pricecharting_id` IS NOT NULL AND `pricecharting_id` <> ''
  )
THEN 1 ELSE 0 END;--> statement-breakpoint
DROP TABLE `tcgplayer_skus`;--> statement-breakpoint
DROP TABLE `tcg_price_history`;--> statement-breakpoint
DROP TABLE `__tcg_price_migration_guard`;
