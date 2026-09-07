ALTER TABLE `billing_transaction` ADD `auto_renew_snapshot` integer
  CHECK (`auto_renew_snapshot` IS NULL OR `auto_renew_snapshot` IN (0, 1));
