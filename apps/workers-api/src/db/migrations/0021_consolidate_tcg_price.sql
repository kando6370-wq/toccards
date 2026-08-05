CREATE TABLE IF NOT EXISTS `tcg_price` (
  `id` integer PRIMARY KEY AUTOINCREMENT,
  `sku_id` integer,
  `pricecharting_id` text,
  `product_id` text NOT NULL,
  `sku_key` text NOT NULL,
  `condition_code` text,
  `condition_name` text,
  `language_code` text,
  `language_name` text,
  `variant_code` text,
  `variant_name` text,
  `price_Ungraded` text NOT NULL DEFAULT '[]',
  `price_Grade_7` text NOT NULL DEFAULT '[]',
  `price_Grade_8` text NOT NULL DEFAULT '[]',
  `price_Grade_9` text NOT NULL DEFAULT '[]',
  `price_Grade_9_5` text NOT NULL DEFAULT '[]',
  `price_PSA_10` text NOT NULL DEFAULT '[]',
  `price_BGS_10` text NOT NULL DEFAULT '[]',
  `price_CGC_10` text NOT NULL DEFAULT '[]',
  `price_SGC_10` text NOT NULL DEFAULT '[]',
  `increase_Ungraded` real NOT NULL DEFAULT 0,
  `increase_Grade_7` real NOT NULL DEFAULT 0,
  `increase_Grade_8` real NOT NULL DEFAULT 0,
  `increase_Grade_9` real NOT NULL DEFAULT 0,
  `increase_Grade_9_5` real NOT NULL DEFAULT 0,
  `increase_PSA_10` real NOT NULL DEFAULT 0,
  `increase_BGS_10` real NOT NULL DEFAULT 0,
  `increase_CGC_10` real NOT NULL DEFAULT 0,
  `increase_SGC_10` real NOT NULL DEFAULT 0
);--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `tcg_price_history` (
  `pricecharting_id` text PRIMARY KEY,
  `product_id` text,
  `product_name` text,
  `product_sub_type` text,
  `price_Ungraded` text NOT NULL DEFAULT '[]',
  `price_Grade_7` text NOT NULL DEFAULT '[]',
  `price_Grade_8` text NOT NULL DEFAULT '[]',
  `price_Grade_9` text NOT NULL DEFAULT '[]',
  `price_Grade_9_5` text NOT NULL DEFAULT '[]',
  `price_PSA_10` text NOT NULL DEFAULT '[]',
  `price_BGS_10` text NOT NULL DEFAULT '[]',
  `price_CGC_10` text NOT NULL DEFAULT '[]',
  `price_SGC_10` text NOT NULL DEFAULT '[]',
  `increase_Ungraded` real NOT NULL DEFAULT 0,
  `increase_Grade_7` real NOT NULL DEFAULT 0,
  `increase_Grade_8` real NOT NULL DEFAULT 0,
  `increase_Grade_9` real NOT NULL DEFAULT 0,
  `increase_Grade_9_5` real NOT NULL DEFAULT 0,
  `increase_PSA_10` real NOT NULL DEFAULT 0,
  `increase_BGS_10` real NOT NULL DEFAULT 0,
  `increase_CGC_10` real NOT NULL DEFAULT 0,
  `increase_SGC_10` real NOT NULL DEFAULT 0
);--> statement-breakpoint
DROP INDEX IF EXISTS `idx_tcg_price_pricecharting_id`;--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS `idx_tcg_price_sku_id`
ON `tcg_price` (`sku_id`);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `idx_tcg_price_pricecharting_lookup`
ON `tcg_price` (`pricecharting_id`);--> statement-breakpoint

INSERT INTO `tcg_price` (
  `sku_id`, `product_id`, `sku_key`, `condition_code`, `condition_name`,
  `language_code`, `language_name`, `variant_code`, `variant_name`,
  `price_Ungraded`, `increase_Ungraded`
)
SELECT old.`sku_id`, old.`product_id`, old.`sku_key`, old.`condition_code`,
  old.`condition_name`, old.`language_code`, old.`language_name`,
  old.`variant_code`, old.`variant_name`, old.`price_history`,
  coalesce(old.`increase_rate`, 0)
FROM `tcgplayer_skus` AS old
WHERE NOT EXISTS (
  SELECT 1 FROM `tcg_price` AS merged WHERE merged.`sku_id` = old.`sku_id`
);--> statement-breakpoint

INSERT INTO `tcg_price` (
  `pricecharting_id`, `product_id`, `sku_key`, `variant_name`,
  `price_Ungraded`, `price_Grade_7`, `price_Grade_8`, `price_Grade_9`,
  `price_Grade_9_5`, `price_PSA_10`, `price_BGS_10`, `price_CGC_10`,
  `price_SGC_10`, `increase_Ungraded`, `increase_Grade_7`,
  `increase_Grade_8`, `increase_Grade_9`, `increase_Grade_9_5`,
  `increase_PSA_10`, `increase_BGS_10`, `increase_CGC_10`, `increase_SGC_10`
)
SELECT selected.`pricecharting_id`, selected.`product_id`,
  'pricecharting:' || selected.`pricecharting_id`, selected.`product_sub_type`,
  selected.`price_Ungraded`, selected.`price_Grade_7`, selected.`price_Grade_8`,
  selected.`price_Grade_9`, selected.`price_Grade_9_5`, selected.`price_PSA_10`,
  selected.`price_BGS_10`, selected.`price_CGC_10`, selected.`price_SGC_10`,
  selected.`increase_Ungraded`, selected.`increase_Grade_7`,
  selected.`increase_Grade_8`, selected.`increase_Grade_9`,
  selected.`increase_Grade_9_5`, selected.`increase_PSA_10`,
  selected.`increase_BGS_10`, selected.`increase_CGC_10`,
  selected.`increase_SGC_10`
FROM (
  SELECT old.*,
    ROW_NUMBER() OVER (
      PARTITION BY old.`product_id`, old.`product_sub_type`
      ORDER BY CAST(old.`pricecharting_id` AS integer) DESC
    ) AS `selected_rank`
  FROM `tcg_price_history` AS old
  WHERE old.`product_id` IS NOT NULL AND old.`product_sub_type` IS NOT NULL
) AS selected
WHERE selected.`selected_rank` = 1
  AND NOT EXISTS (
    SELECT 1 FROM `tcg_price` AS merged
    WHERE merged.`pricecharting_id` = selected.`pricecharting_id`
  );--> statement-breakpoint

CREATE INDEX IF NOT EXISTS `idx_tcg_price_product_id`
ON `tcg_price` (`product_id`);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `idx_tcg_price_lookup`
ON `tcg_price` (`product_id`, `language_code`, `variant_code`, `condition_code`);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `idx_tcg_price_increase_ungraded`
ON `tcg_price` (`increase_Ungraded`);
