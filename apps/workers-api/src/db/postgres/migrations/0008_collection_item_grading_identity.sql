DROP INDEX uq_collection_item_folder_card_finish_language;

CREATE UNIQUE INDEX uq_collection_item_folder_card_variant
  ON collection_item (
    owner_type,
    owner_id,
    folder_id,
    card_ref,
    COALESCE(finish, ''),
    COALESCE(language, ''),
    grader,
    COALESCE(condition, ''),
    COALESCE(grade, '-1'::double precision)
  );
