CREATE TABLE platform_account (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES "user" (id),
  platform text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  CONSTRAINT ck_platform_account_platform CHECK (platform IN ('ios', 'android')),
  CONSTRAINT ck_platform_account_status CHECK (status IN ('active', 'disabled', 'deleting', 'deleted'))
);

CREATE UNIQUE INDEX uq_platform_account_live_user_platform
  ON platform_account (user_id, platform)
  WHERE status <> 'deleted';

CREATE INDEX idx_platform_account_user
  ON platform_account (user_id, platform, status);

INSERT INTO platform_account
  (id, user_id, platform, status, created_at, updated_at, deleted_at)
SELECT id, id, 'ios',
       CASE WHEN status = 'active' THEN 'active' ELSE 'disabled' END,
       created_at, updated_at, NULL
FROM "user"
WHERE status <> 'deleted';

DELETE FROM verification_code
WHERE EXISTS (
  SELECT 1 FROM "user" deleted_user
  WHERE deleted_user.status = 'deleted' AND deleted_user.email = verification_code.email
)
AND NOT EXISTS (
  SELECT 1 FROM "user" live_user
  WHERE live_user.status <> 'deleted' AND live_user.email = verification_code.email
);

DELETE FROM auth_identity
WHERE user_id IN (SELECT id FROM "user" WHERE status = 'deleted');

UPDATE "user"
SET email = 'deleted+' || id || '@invalid.cardai.local',
    password_hash = NULL,
    display_name = NULL
WHERE status = 'deleted';

ALTER TABLE anonymous_account
  ADD COLUMN platform text DEFAULT 'ios',
  ADD COLUMN status text NOT NULL DEFAULT 'active',
  ADD COLUMN deleted_at text;

UPDATE anonymous_account
SET platform = 'ios'
WHERE platform IS NULL;

ALTER TABLE anonymous_account
  ALTER COLUMN platform SET NOT NULL;

ALTER TABLE anonymous_account
  ADD CONSTRAINT ck_anonymous_account_platform
  CHECK (platform IN ('ios', 'android'));

ALTER TABLE anonymous_account
  ADD CONSTRAINT ck_anonymous_account_status
  CHECK (status IN ('active', 'deleting', 'deleted'));

CREATE INDEX idx_anonymous_account_live_device_platform
  ON anonymous_account (device_id, platform, created_at, id)
  WHERE upgraded_user_id IS NULL AND status = 'active';

ALTER TABLE session
  ADD COLUMN platform text DEFAULT 'ios',
  ADD COLUMN user_id text;

UPDATE session
SET platform = 'ios',
    user_id = CASE WHEN owner_type = 'user' THEN owner_id ELSE NULL END
WHERE owner_type IN ('user', 'anonymous');

ALTER TABLE session
  ADD CONSTRAINT ck_session_platform
  CHECK (platform IS NULL OR platform IN ('ios', 'android'));

CREATE INDEX idx_session_user_platform
  ON session (user_id, platform, revoked_at);

CREATE OR REPLACE FUNCTION enforce_active_business_owner()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.owner_type = 'user' THEN
    PERFORM 1 FROM platform_account
    WHERE id = NEW.owner_id AND status = 'active'
    FOR SHARE;
  ELSIF NEW.owner_type = 'anonymous' THEN
    PERFORM 1 FROM anonymous_account
    WHERE id = NEW.owner_id AND status = 'active'
    FOR SHARE;
  ELSE
    RAISE EXCEPTION 'unsupported business owner type';
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'business owner is not active';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'portfolio_folder', 'collection_item', 'collection_item_event',
    'wishlist_item', 'user_preference', 'scan_record', 'scan_quota_request'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %I '
      'FOR EACH ROW EXECUTE FUNCTION enforce_active_business_owner()',
      'trg_' || table_name || '_active_owner', table_name
    );
  END LOOP;
END;
$$;
