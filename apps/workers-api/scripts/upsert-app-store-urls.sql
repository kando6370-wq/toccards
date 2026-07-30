-- Replace both URL placeholders before running this script against D1.

INSERT INTO app_config (key, value, updated_by, updated_at)
VALUES (
  'admin.app_version.ios',
  json_object(
    'platform', 'iOS',
    'min_supported_version', '1.0.0',
    'recommended_version', '1.0.0',
    'force_update', json('false'),
    'store_url', '__IOS_APP_STORE_URL__',
    'recommended_update_message', '',
    'forced_update_message', '',
    'status', 'disabled',
    'updated_at', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
  ),
  NULL,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
)
ON CONFLICT(key) DO UPDATE SET
  value = CASE
    WHEN json_valid(app_config.value) THEN json_set(
      app_config.value,
      '$.store_url', json_extract(excluded.value, '$.store_url'),
      '$.updated_at', excluded.updated_at
    )
    ELSE excluded.value
  END,
  updated_at = excluded.updated_at;

INSERT INTO app_config (key, value, updated_by, updated_at)
VALUES (
  'admin.app_version.google',
  json_object(
    'platform', 'Google',
    'min_supported_version', '1.0.0',
    'recommended_version', '1.0.0',
    'force_update', json('false'),
    'store_url', '__GOOGLE_PLAY_URL__',
    'recommended_update_message', '',
    'forced_update_message', '',
    'status', 'disabled',
    'updated_at', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
  ),
  NULL,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
)
ON CONFLICT(key) DO UPDATE SET
  value = CASE
    WHEN json_valid(app_config.value) THEN json_set(
      app_config.value,
      '$.store_url', json_extract(excluded.value, '$.store_url'),
      '$.updated_at', excluded.updated_at
    )
    ELSE excluded.value
  END,
  updated_at = excluded.updated_at;

SELECT key, value, updated_at
FROM app_config
WHERE key IN ('admin.app_version.ios', 'admin.app_version.google')
ORDER BY key;
