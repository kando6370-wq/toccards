-- Snapshot the existing effective version rules into independent environments.
-- Apply before deploying the scoped readers/writers. Existing scoped rows win;
-- legacy rows remain untouched for the deployment window, never as a fallback.
WITH platforms (platform_key, platform_name) AS (
  VALUES ('ios', 'iOS'), ('google', 'Google')
), sources AS (
  SELECT p.*,
    legacy.value::jsonb AS platform_rule,
    shared.value::jsonb AS shared_prompt,
    store.value AS shared_store_url,
    legacy.updated_by,
    COALESCE(legacy.updated_at, shared.updated_at,
      to_char(CURRENT_TIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')) AS updated_at
  FROM platforms p
  LEFT JOIN app_config legacy ON legacy.key = 'admin.app_version.' || p.platform_key
  LEFT JOIN app_config shared ON shared.key = 'upgrade_prompt'
  LEFT JOIN app_config store ON store.key = 'app_store_url'
), rules AS (
  SELECT platform_key, updated_by, updated_at,
    CASE WHEN platform_rule IS NOT NULL THEN platform_rule
    ELSE jsonb_build_object(
      'min_supported_version', COALESCE(shared_prompt->>'latest_version', shared_prompt->>'min_version', '1.0.0'),
      'recommended_version', COALESCE(shared_prompt->>'latest_version', shared_prompt->>'min_version', '1.0.0'),
      'force_update', COALESCE(shared_prompt->'force_update', 'false'::jsonb),
      'recommended_update_message', COALESCE(shared_prompt->>'message', ''),
      'forced_update_message', COALESCE(shared_prompt->>'message', 'Please update to continue.'),
      'status', CASE WHEN shared_prompt IS NULL THEN 'disabled' ELSE 'enabled' END
    ) END || jsonb_build_object(
      'platform', platform_name,
      'store_url', COALESCE(NULLIF(btrim(platform_rule->>'store_url'), ''),
        CASE WHEN platform_rule IS NULL THEN NULLIF(btrim(shared_prompt->>'store_url'), '') END,
        NULLIF(btrim(shared_store_url), ''), ''),
      'updated_at', updated_at
    ) AS value
  FROM sources
)
INSERT INTO app_config (key, value, updated_by, updated_at)
SELECT 'admin.app_version.' || e.environment || '.' || r.platform_key,
  r.value::text, r.updated_by, r.updated_at
FROM rules r CROSS JOIN (VALUES ('development'), ('production')) AS e(environment)
ON CONFLICT (key) DO NOTHING;
