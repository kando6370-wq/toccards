-- Historical inbox entries and Voided Purchases API reconciliation rows have no RTDN snapshot.
ALTER TABLE google_play_inbox ADD COLUMN redacted_payload jsonb;
