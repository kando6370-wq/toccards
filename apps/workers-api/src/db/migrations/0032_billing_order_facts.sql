ALTER TABLE `billing_transaction` ADD `business_status` text;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `charge_count` integer;
--> statement-breakpoint
ALTER TABLE `billing_transaction` ADD `source_notification_uuid` text;
--> statement-breakpoint
UPDATE `billing_transaction`
SET `business_status` = CASE
  WHEN `status` = 'refunded' THEN 'refunded'
  WHEN `amount_micros` = 0 THEN 'trial'
  WHEN `transaction_reason` = 'PURCHASE' THEN 'initial_purchase'
  WHEN `transaction_reason` = 'RENEWAL' THEN 'renewal'
  ELSE NULL
END;
--> statement-breakpoint
UPDATE `billing_transaction` AS current_transaction
SET `business_status` = 'trial_conversion'
WHERE current_transaction.`business_status` = 'renewal'
  AND EXISTS (
    SELECT 1 FROM `billing_transaction` AS trial_transaction
    WHERE trial_transaction.`purchase_chain_id` = current_transaction.`purchase_chain_id`
      AND trial_transaction.`environment` = current_transaction.`environment`
      AND trial_transaction.`business_status` = 'trial'
      AND (
        trial_transaction.`purchase_at` < current_transaction.`purchase_at`
        OR (
          trial_transaction.`purchase_at` = current_transaction.`purchase_at`
          AND trial_transaction.`transaction_id` < current_transaction.`transaction_id`
        )
      )
  )
  AND NOT EXISTS (
    SELECT 1 FROM `billing_transaction` AS earlier_paid_transaction
    WHERE earlier_paid_transaction.`purchase_chain_id` = current_transaction.`purchase_chain_id`
      AND earlier_paid_transaction.`environment` = current_transaction.`environment`
      AND earlier_paid_transaction.`business_status` != 'trial'
      AND (
        earlier_paid_transaction.`purchase_at` < current_transaction.`purchase_at`
        OR (
          earlier_paid_transaction.`purchase_at` = current_transaction.`purchase_at`
          AND earlier_paid_transaction.`transaction_id` < current_transaction.`transaction_id`
        )
      )
  );
--> statement-breakpoint
UPDATE `billing_transaction` AS current_transaction
SET `charge_count` = CASE
  WHEN current_transaction.`amount_micros` = 0 THEN 0
  WHEN current_transaction.`amount_micros` > 0 THEN (
    SELECT COUNT(*)
    FROM `billing_transaction` AS earlier_transaction
    WHERE earlier_transaction.`purchase_chain_id` = current_transaction.`purchase_chain_id`
      AND earlier_transaction.`environment` = current_transaction.`environment`
      AND earlier_transaction.`amount_micros` > 0
      AND (
        earlier_transaction.`purchase_at` < current_transaction.`purchase_at`
        OR (
          earlier_transaction.`purchase_at` = current_transaction.`purchase_at`
          AND earlier_transaction.`transaction_id` <= current_transaction.`transaction_id`
        )
      )
  )
  ELSE NULL
END;
--> statement-breakpoint
CREATE INDEX `idx_billing_transaction_business_status_time`
ON `billing_transaction` (`business_status`, `purchase_at`);
--> statement-breakpoint
CREATE INDEX `idx_billing_transaction_charge_count`
ON `billing_transaction` (`charge_count`, `purchase_at`);
