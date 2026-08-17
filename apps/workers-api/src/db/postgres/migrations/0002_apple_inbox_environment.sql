ALTER TABLE apple_notification_inbox
  ADD COLUMN environment text;

UPDATE apple_notification_inbox AS inbox
SET environment = notification.environment
FROM apple_server_notification AS notification
WHERE notification.inbox_id = inbox.id;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM apple_notification_inbox
    WHERE environment IS NULL
  ) THEN
    RAISE EXCEPTION
      'apple_notification_inbox contains rows without a verified environment backfill';
  END IF;
END;
$$;

ALTER TABLE apple_notification_inbox
  ALTER COLUMN environment SET NOT NULL,
  ADD CONSTRAINT ck_apple_notification_inbox_environment
    CHECK (environment IN ('Production', 'Sandbox'));

ALTER TABLE apple_notification_inbox
  DROP CONSTRAINT IF EXISTS apple_notification_inbox_payload_sha256_key,
  ADD CONSTRAINT uq_apple_notification_inbox_environment_payload
    UNIQUE (environment, payload_sha256);

DROP INDEX idx_apple_notification_inbox_processing;

CREATE INDEX idx_apple_notification_inbox_processing
  ON apple_notification_inbox (
    environment,
    processing_status,
    processing_expires_at,
    received_at
  );
