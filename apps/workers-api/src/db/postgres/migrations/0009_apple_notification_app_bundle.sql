ALTER TABLE apple_notification_inbox
  ADD COLUMN app_bundle_id text;

UPDATE apple_notification_inbox
SET app_bundle_id = CASE environment
  WHEN 'Sandbox' THEN 'com.kando.kandoApp.beta'
  WHEN 'Production' THEN 'com.cardai.tcg'
END;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM apple_notification_inbox
    WHERE app_bundle_id IS NULL OR app_bundle_id = ''
  ) THEN
    RAISE EXCEPTION
      'apple_notification_inbox contains rows without a trusted Bundle backfill';
  END IF;
END;
$$;

ALTER TABLE apple_notification_inbox
  ALTER COLUMN app_bundle_id SET NOT NULL;

CREATE FUNCTION set_legacy_apple_notification_app_bundle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.app_bundle_id IS NULL THEN
    NEW.app_bundle_id := CASE NEW.environment
      WHEN 'Sandbox' THEN 'com.kando.kandoApp.beta'
      WHEN 'Production' THEN 'com.cardai.tcg'
    END;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_legacy_apple_notification_app_bundle
  BEFORE INSERT ON apple_notification_inbox
  FOR EACH ROW
  EXECUTE FUNCTION set_legacy_apple_notification_app_bundle();

ALTER TABLE apple_notification_inbox
  DROP CONSTRAINT uq_apple_notification_inbox_environment_payload,
  ADD CONSTRAINT uq_apple_notification_inbox_app_environment_payload
    UNIQUE (app_bundle_id, environment, payload_sha256);

DROP INDEX idx_apple_notification_inbox_processing;

CREATE INDEX idx_apple_notification_inbox_processing
  ON apple_notification_inbox (
    app_bundle_id,
    environment,
    processing_status,
    processing_expires_at,
    received_at
  );
