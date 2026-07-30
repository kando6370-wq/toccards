INSERT INTO app_config (key, value, updated_by, updated_at)
VALUES (
  'card_share_base_url',
  'https://api-dev.tcgcard.fun/share/cards',
  NULL,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
)
ON CONFLICT(key) DO UPDATE SET
  value = excluded.value,
  updated_at = excluded.updated_at;

SELECT key, value, updated_at
FROM app_config
WHERE key = 'card_share_base_url';
