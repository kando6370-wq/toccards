WITH trial_products AS (
  SELECT DISTINCT product.value->>'product_id' AS product_id
  FROM app_config config
  CROSS JOIN LATERAL jsonb_each(config.value::jsonb) AS product(key, value)
  WHERE config.key LIKE 'billing.apple.admission:%'
    AND product.value->>'product_id' = product.key
    AND product.value->>'is_trial_product' = 'true'
), trial_conversion_candidates AS (
  SELECT current_transaction.id
  FROM billing_transaction current_transaction
  JOIN trial_products
    ON trial_products.product_id = current_transaction.product_id
  WHERE current_transaction.transaction_reason = 'RENEWAL'
    AND current_transaction.amount_micros > 0
    AND current_transaction.source_notification_uuid IS NOT NULL
    AND (
      current_transaction.business_status = 'renewal'
      OR (
        current_transaction.business_status = 'refunded'
        AND current_transaction.business_status_before_refund = 'renewal'
      )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM billing_transaction earlier_paid_transaction
      WHERE earlier_paid_transaction.purchase_chain_id = current_transaction.purchase_chain_id
        AND earlier_paid_transaction.environment = current_transaction.environment
        AND earlier_paid_transaction.business_status IS NOT NULL
        AND earlier_paid_transaction.business_status != 'trial'
        AND earlier_paid_transaction.amount_micros > 0
        AND earlier_paid_transaction.source_notification_uuid IS NOT NULL
        AND (
          earlier_paid_transaction.purchase_at < current_transaction.purchase_at
          OR (
            earlier_paid_transaction.purchase_at = current_transaction.purchase_at
            AND earlier_paid_transaction.transaction_id < current_transaction.transaction_id
          )
        )
    )
)
UPDATE billing_transaction transaction_to_update
SET business_status = CASE
      WHEN transaction_to_update.business_status = 'renewal' THEN 'trial_conversion'
      ELSE transaction_to_update.business_status
    END,
    business_status_before_refund = CASE
      WHEN transaction_to_update.business_status_before_refund = 'renewal' THEN 'trial_conversion'
      ELSE transaction_to_update.business_status_before_refund
    END
FROM trial_conversion_candidates candidate
WHERE transaction_to_update.id = candidate.id;
