CREATE UNIQUE INDEX IF NOT EXISTS `idx_tcg_price_natural_key`
ON `tcg_price` (
  `product_id`,
  COALESCE(`condition_name`, ''),
  COALESCE(`language_name`, ''),
  COALESCE(`variant_name`, '')
);
