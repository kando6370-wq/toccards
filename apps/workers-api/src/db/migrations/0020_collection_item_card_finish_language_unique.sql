CREATE UNIQUE INDEX `uq_collection_item_folder_card_finish_language`
ON `collection_item` (
  `owner_type`,
  `owner_id`,
  `folder_id`,
  `card_ref`,
  COALESCE(`finish`, ''),
  COALESCE(`language`, '')
);
