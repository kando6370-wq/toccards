CREATE INDEX IF NOT EXISTS idx_cards_all_visible_created_numeric_product
  ON cards_all (
    created_at DESC NULLS LAST,
    (CASE WHEN product_id ~ '^[0-9]+$' THEN product_id::numeric ELSE NULL END) DESC NULLS LAST,
    product_id DESC
  ) WHERE has_image = 2;

CREATE INDEX IF NOT EXISTS idx_cards_all_visible_game_created_numeric_product
  ON cards_all (
    lower(game),
    created_at DESC NULLS LAST,
    (CASE WHEN product_id ~ '^[0-9]+$' THEN product_id::numeric ELSE NULL END) DESC NULLS LAST,
    product_id DESC
  ) WHERE has_image = 2;

CREATE INDEX IF NOT EXISTS idx_cards_all_visible_game_set_created_numeric_product
  ON cards_all (
    lower(game),
    set_id,
    created_at DESC NULLS LAST,
    (CASE WHEN product_id ~ '^[0-9]+$' THEN product_id::numeric ELSE NULL END) DESC NULLS LAST,
    product_id DESC
  ) WHERE has_image = 2;
