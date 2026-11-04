CREATE INDEX IF NOT EXISTS idx_cards_all_created_product
  ON cards_all (created_at DESC NULLS LAST, product_id DESC);

CREATE INDEX IF NOT EXISTS idx_cards_all_game_created_product
  ON cards_all (lower(game), created_at DESC NULLS LAST, product_id DESC);

CREATE INDEX IF NOT EXISTS idx_cards_all_game_set_created_product
  ON cards_all (lower(game), lower(set_code), created_at DESC NULLS LAST, product_id DESC);

DROP INDEX IF EXISTS idx_cards_all_updated_product;
DROP INDEX IF EXISTS idx_cards_all_game_updated_product;
DROP INDEX IF EXISTS idx_cards_all_game_set_updated_product;
