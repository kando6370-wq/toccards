WITH confirmed_scan_items AS (
  SELECT DISTINCT
    owner_type,
    owner_id,
    user_result::jsonb ->> 'collection_item_id' AS item_id
  FROM scan_record
  WHERE user_confirmation_status = 'confirmed'
    AND user_result::jsonb ->> 'added_to_inventory' = 'true'
)
UPDATE collection_item_event AS event
SET
  purchase_price = item.purchase_price,
  purchase_currency = item.purchase_currency,
  performance_history_available_from = COALESCE(
    event.performance_history_available_from,
    item.performance_history_available_from,
    item.created_at
  )
FROM collection_item AS item
JOIN confirmed_scan_items AS scan
  ON scan.item_id = item.id
  AND scan.owner_type = item.owner_type
  AND scan.owner_id = item.owner_id
WHERE event.item_id = item.id
  AND event.owner_type = item.owner_type
  AND event.owner_id = item.owner_id
  AND event.event_type = 'upsert'
  AND event.effective_at = item.created_at
  AND event.id = (
    SELECT initial_event.id
    FROM collection_item_event AS initial_event
    WHERE initial_event.item_id = event.item_id
      AND initial_event.owner_type = event.owner_type
      AND initial_event.owner_id = event.owner_id
    ORDER BY initial_event.effective_at ASC, initial_event.id ASC
    LIMIT 1
  )
  AND event.purchase_price IS NULL
  AND event.purchase_currency IS NULL
  AND item.purchase_price IS NOT NULL
  AND item.purchase_currency IS NOT NULL;
