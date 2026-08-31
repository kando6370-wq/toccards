ALTER TABLE scan_record
  ADD COLUMN environment text;

UPDATE scan_record
SET environment = 'development'
WHERE environment IS NULL;

ALTER TABLE scan_record
  ALTER COLUMN environment SET DEFAULT 'development',
  ALTER COLUMN environment SET NOT NULL,
  ADD CONSTRAINT ck_scan_record_environment
    CHECK (environment IN ('development', 'production'));

CREATE INDEX idx_scan_record_environment_created_at
  ON scan_record (environment, created_at DESC, id ASC);
