UPDATE `collection_item_event`
SET `owner_type` = 'user',
    `owner_id` = (
      SELECT `upgraded_user_id`
      FROM `anonymous_account`
      WHERE `anonymous_account`.`id` = `collection_item_event`.`owner_id`
    )
WHERE `owner_type` = 'anonymous'
  AND EXISTS (
    SELECT 1
    FROM `anonymous_account`
    WHERE `anonymous_account`.`id` = `collection_item_event`.`owner_id`
      AND `anonymous_account`.`upgraded_user_id` IS NOT NULL
  );
