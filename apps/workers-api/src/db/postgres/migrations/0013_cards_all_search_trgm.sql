CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_cards_all_search_trgm
  ON cards_all USING gin ((lower(
    coalesce(name, '') || ' ' ||
    coalesce(number, '') || ' ' ||
    coalesce(set_name, '') || ' ' ||
    coalesce(set_code, '') || ' ' ||
    coalesce(rarity, '') || ' ' ||
    coalesce(game, '')
  )) gin_trgm_ops);
