CREATE TABLE price_source (
  source_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_code text NOT NULL,
  display_name text NOT NULL,
  source_kind text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_price_source_code UNIQUE (source_code),
  CONSTRAINT ck_price_source_code
    CHECK (source_code ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  CONSTRAINT ck_price_source_display_name CHECK (btrim(display_name) <> ''),
  CONSTRAINT ck_price_source_kind CHECK (source_kind IN ('external', 'derived'))
);

CREATE TABLE price_series (
  series_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_id bigint NOT NULL,
  source_record_id text NOT NULL,
  metric_code text NOT NULL,
  card_ref text NOT NULL,
  currency_code text NOT NULL,
  condition_code text,
  condition_name text,
  language_code text,
  language_name text,
  finish_code text,
  finish_name text,
  grader_code text NOT NULL,
  grade_min_x10 smallint,
  grade_max_x10 smallint,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deactivated_at timestamptz,
  CONSTRAINT fk_price_series_source
    FOREIGN KEY (source_id) REFERENCES price_source (source_id) ON DELETE RESTRICT,
  CONSTRAINT fk_price_series_card
    FOREIGN KEY (card_ref) REFERENCES cards_all (product_id) ON DELETE RESTRICT,
  CONSTRAINT uq_price_series_external_metric
    UNIQUE (source_id, source_record_id, metric_code),
  CONSTRAINT ck_price_series_source_record_id CHECK (btrim(source_record_id) <> ''),
  CONSTRAINT ck_price_series_metric_code
    CHECK (metric_code ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  CONSTRAINT ck_price_series_currency CHECK (currency_code ~ '^[A-Z]{3}$'),
  CONSTRAINT ck_price_series_grader_code CHECK (btrim(grader_code) <> ''),
  CONSTRAINT ck_price_series_grade_pair CHECK (
    (grade_min_x10 IS NULL AND grade_max_x10 IS NULL)
    OR (
      grade_min_x10 BETWEEN 0 AND 100
      AND grade_max_x10 BETWEEN grade_min_x10 AND 100
    )
  ),
  CONSTRAINT ck_price_series_deactivation CHECK (
    (is_active AND deactivated_at IS NULL)
    OR (NOT is_active AND deactivated_at IS NOT NULL)
  )
);

CREATE INDEX idx_price_series_card_qualifiers
  ON price_series (
    card_ref,
    grader_code,
    grade_min_x10,
    grade_max_x10,
    condition_code,
    language_code,
    finish_code
  )
  INCLUDE (series_id, source_id, metric_code, currency_code)
  WHERE is_active;

CREATE INDEX idx_price_series_source_active
  ON price_series (source_id, is_active, series_id);

CREATE TABLE price_ingest_batch (
  batch_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  scope_code text NOT NULL,
  source_id bigint NOT NULL,
  business_date date NOT NULL,
  idempotency_key text NOT NULL,
  input_object_key text NOT NULL,
  input_checksum_sha256 text NOT NULL,
  content_checksum_sha256 text,
  expected_series_count bigint,
  loaded_series_count bigint NOT NULL DEFAULT 0,
  distinct_series_count bigint NOT NULL DEFAULT 0,
  rejected_record_count bigint NOT NULL DEFAULT 0,
  min_observed_on date,
  max_observed_on date,
  status text NOT NULL DEFAULT 'loading',
  started_at timestamptz NOT NULL DEFAULT now(),
  validated_at timestamptz,
  published_at timestamptz,
  failed_at timestamptz,
  failure_reason text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fk_price_ingest_batch_source
    FOREIGN KEY (source_id) REFERENCES price_source (source_id) ON DELETE RESTRICT,
  CONSTRAINT uq_price_ingest_batch_idempotency UNIQUE (scope_code, idempotency_key),
  CONSTRAINT uq_price_ingest_batch_scope_id UNIQUE (scope_code, batch_id),
  CONSTRAINT ck_price_ingest_batch_scope
    CHECK (scope_code ~ '^[a-z0-9][a-z0-9:_-]{0,126}$'),
  CONSTRAINT ck_price_ingest_batch_idempotency CHECK (btrim(idempotency_key) <> ''),
  CONSTRAINT ck_price_ingest_batch_object_key CHECK (btrim(input_object_key) <> ''),
  CONSTRAINT ck_price_ingest_batch_input_checksum
    CHECK (input_checksum_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT ck_price_ingest_batch_content_checksum CHECK (
    content_checksum_sha256 IS NULL
    OR content_checksum_sha256 ~ '^[0-9a-f]{64}$'
  ),
  CONSTRAINT ck_price_ingest_batch_counts CHECK (
    (expected_series_count IS NULL OR expected_series_count >= 0)
    AND loaded_series_count >= 0
    AND distinct_series_count >= 0
    AND rejected_record_count >= 0
    AND distinct_series_count <= loaded_series_count
  ),
  CONSTRAINT ck_price_ingest_batch_date_range CHECK (
    (min_observed_on IS NULL AND max_observed_on IS NULL)
    OR (
      min_observed_on IS NOT NULL
      AND max_observed_on IS NOT NULL
      AND min_observed_on <= max_observed_on
    )
  ),
  CONSTRAINT ck_price_ingest_batch_status
    CHECK (status IN ('loading', 'validated', 'published', 'superseded', 'failed')),
  CONSTRAINT ck_price_ingest_batch_complete CHECK (
    status NOT IN ('validated', 'published', 'superseded')
    OR (
      expected_series_count IS NOT NULL
      AND expected_series_count = loaded_series_count
      AND loaded_series_count = distinct_series_count
      AND rejected_record_count = 0
      AND content_checksum_sha256 IS NOT NULL
      AND validated_at IS NOT NULL
    )
  ),
  CONSTRAINT ck_price_ingest_batch_published CHECK (
    status NOT IN ('published', 'superseded') OR published_at IS NOT NULL
  ),
  CONSTRAINT ck_price_ingest_batch_failed CHECK (
    status <> 'failed'
    OR (
      failed_at IS NOT NULL
      AND failure_reason IS NOT NULL
      AND btrim(failure_reason) <> ''
    )
  )
);

CREATE INDEX idx_price_ingest_batch_source_date
  ON price_ingest_batch (source_id, business_date DESC, batch_id DESC);

CREATE INDEX idx_price_ingest_batch_unfinished
  ON price_ingest_batch (status, started_at)
  WHERE status IN ('loading', 'validated');

CREATE TABLE price_current_snapshot (
  batch_id bigint NOT NULL,
  series_id bigint NOT NULL,
  observed_on date NOT NULL,
  amount_micros bigint NOT NULL,
  baseline_1d_on date,
  baseline_1d_amount_micros bigint,
  baseline_7d_on date,
  baseline_7d_amount_micros bigint,
  baseline_30d_on date,
  baseline_30d_amount_micros bigint,
  change_1d_percent numeric(30, 6) GENERATED ALWAYS AS (
    CASE WHEN baseline_1d_amount_micros > 0 THEN
      round(
        (amount_micros - baseline_1d_amount_micros)::numeric
        * 100 / baseline_1d_amount_micros,
        6
      )
    END
  ) STORED,
  change_7d_percent numeric(30, 6) GENERATED ALWAYS AS (
    CASE WHEN baseline_7d_amount_micros > 0 THEN
      round(
        (amount_micros - baseline_7d_amount_micros)::numeric
        * 100 / baseline_7d_amount_micros,
        6
      )
    END
  ) STORED,
  change_30d_percent numeric(30, 6) GENERATED ALWAYS AS (
    CASE WHEN baseline_30d_amount_micros > 0 THEN
      round(
        (amount_micros - baseline_30d_amount_micros)::numeric
        * 100 / baseline_30d_amount_micros,
        6
      )
    END
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_price_current_snapshot PRIMARY KEY (batch_id, series_id),
  CONSTRAINT fk_price_current_snapshot_batch
    FOREIGN KEY (batch_id) REFERENCES price_ingest_batch (batch_id) ON DELETE RESTRICT,
  CONSTRAINT fk_price_current_snapshot_series
    FOREIGN KEY (series_id) REFERENCES price_series (series_id) ON DELETE RESTRICT,
  CONSTRAINT ck_price_current_snapshot_amount CHECK (amount_micros >= 0),
  CONSTRAINT ck_price_current_snapshot_1d CHECK (
    (baseline_1d_on IS NULL) = (baseline_1d_amount_micros IS NULL)
    AND (baseline_1d_on IS NULL OR baseline_1d_on <= observed_on)
    AND (baseline_1d_amount_micros IS NULL OR baseline_1d_amount_micros >= 0)
  ),
  CONSTRAINT ck_price_current_snapshot_7d CHECK (
    (baseline_7d_on IS NULL) = (baseline_7d_amount_micros IS NULL)
    AND (baseline_7d_on IS NULL OR baseline_7d_on <= observed_on)
    AND (baseline_7d_amount_micros IS NULL OR baseline_7d_amount_micros >= 0)
  ),
  CONSTRAINT ck_price_current_snapshot_30d CHECK (
    (baseline_30d_on IS NULL) = (baseline_30d_amount_micros IS NULL)
    AND (baseline_30d_on IS NULL OR baseline_30d_on <= observed_on)
    AND (baseline_30d_amount_micros IS NULL OR baseline_30d_amount_micros >= 0)
  )
) PARTITION BY LIST (batch_id);

CREATE INDEX idx_price_current_snapshot_series_date
  ON price_current_snapshot (series_id, observed_on DESC, batch_id);

CREATE TABLE current_price_pointer (
  scope_code text PRIMARY KEY,
  batch_id bigint NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by text NOT NULL,
  CONSTRAINT fk_current_price_pointer_batch_scope
    FOREIGN KEY (scope_code, batch_id)
    REFERENCES price_ingest_batch (scope_code, batch_id)
    ON DELETE RESTRICT,
  CONSTRAINT ck_current_price_pointer_scope
    CHECK (scope_code ~ '^[a-z0-9][a-z0-9:_-]{0,126}$'),
  CONSTRAINT ck_current_price_pointer_updated_by CHECK (btrim(updated_by) <> '')
);

CREATE FUNCTION assert_current_price_pointer_published()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM price_ingest_batch AS batch
    WHERE batch.batch_id = NEW.batch_id
      AND batch.scope_code = NEW.scope_code
      AND batch.status = 'published'
  ) THEN
    RAISE EXCEPTION
      'pointer scope % must reference a published batch, got %',
      NEW.scope_code,
      NEW.batch_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_current_price_pointer_published
AFTER INSERT OR UPDATE OF scope_code, batch_id
ON current_price_pointer
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW
EXECUTE FUNCTION assert_current_price_pointer_published();

CREATE FUNCTION protect_pointed_price_batch()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status <> 'published'
     AND EXISTS (
       SELECT 1
       FROM current_price_pointer AS pointer
       WHERE pointer.batch_id = NEW.batch_id
     ) THEN
    RAISE EXCEPTION
      'batch % is still referenced by current_price_pointer',
      NEW.batch_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_price_ingest_batch_protect_pointer
BEFORE UPDATE OF status
ON price_ingest_batch
FOR EACH ROW
EXECUTE FUNCTION protect_pointed_price_batch();

CREATE TABLE price_history_month (
  series_id bigint NOT NULL,
  month_start date NOT NULL,
  points jsonb NOT NULL,
  point_count integer NOT NULL,
  first_observed_on date,
  last_observed_on date,
  content_checksum_sha256 text NOT NULL,
  last_batch_id bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_price_history_month PRIMARY KEY (series_id, month_start),
  CONSTRAINT fk_price_history_month_series
    FOREIGN KEY (series_id) REFERENCES price_series (series_id) ON DELETE RESTRICT,
  CONSTRAINT fk_price_history_month_batch
    FOREIGN KEY (last_batch_id) REFERENCES price_ingest_batch (batch_id) ON DELETE RESTRICT,
  CONSTRAINT ck_price_history_month_start CHECK (extract(day FROM month_start) = 1),
  CONSTRAINT ck_price_history_month_points CHECK (
    CASE
      WHEN jsonb_typeof(points) = 'array'
      THEN jsonb_array_length(points) = point_count
      ELSE false
    END
  ),
  CONSTRAINT ck_price_history_month_count CHECK (point_count >= 0),
  CONSTRAINT ck_price_history_month_dates CHECK (
    (
      point_count = 0
      AND first_observed_on IS NULL
      AND last_observed_on IS NULL
    )
    OR (
      point_count > 0
      AND first_observed_on IS NOT NULL
      AND last_observed_on IS NOT NULL
      AND first_observed_on BETWEEN month_start
        AND (month_start + interval '1 month - 1 day')::date
      AND last_observed_on BETWEEN first_observed_on
        AND (month_start + interval '1 month - 1 day')::date
    )
  ),
  CONSTRAINT ck_price_history_month_checksum
    CHECK (content_checksum_sha256 ~ '^[0-9a-f]{64}$')
) PARTITION BY RANGE (month_start);

CREATE TABLE card_trending_snapshot (
  batch_id bigint NOT NULL,
  rank integer NOT NULL,
  card_ref text NOT NULL,
  winning_series_id bigint NOT NULL,
  observed_on date NOT NULL,
  amount_micros bigint NOT NULL,
  baseline_1d_on date NOT NULL,
  baseline_1d_amount_micros bigint NOT NULL,
  change_1d_percent numeric(30, 6) GENERATED ALWAYS AS (
    round(
      (amount_micros - baseline_1d_amount_micros)::numeric
      * 100 / baseline_1d_amount_micros,
      6
    )
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_card_trending_snapshot PRIMARY KEY (batch_id, rank),
  CONSTRAINT uq_card_trending_snapshot_card UNIQUE (batch_id, card_ref),
  CONSTRAINT fk_card_trending_snapshot_batch
    FOREIGN KEY (batch_id) REFERENCES price_ingest_batch (batch_id) ON DELETE RESTRICT,
  CONSTRAINT fk_card_trending_snapshot_card
    FOREIGN KEY (card_ref) REFERENCES cards_all (product_id) ON DELETE RESTRICT,
  CONSTRAINT fk_card_trending_snapshot_series
    FOREIGN KEY (winning_series_id) REFERENCES price_series (series_id) ON DELETE RESTRICT,
  CONSTRAINT ck_card_trending_snapshot_rank CHECK (rank >= 1),
  CONSTRAINT ck_card_trending_snapshot_amount CHECK (
    amount_micros >= 0
    AND baseline_1d_amount_micros > 0
  ),
  CONSTRAINT ck_card_trending_snapshot_dates CHECK (baseline_1d_on <= observed_on),
  CONSTRAINT ck_card_trending_snapshot_change CHECK (change_1d_percent > 0)
);

ALTER TABLE collection_item ADD COLUMN price_series_id bigint;
ALTER TABLE collection_item_event ADD COLUMN price_series_id bigint;

ALTER TABLE collection_item
  ADD CONSTRAINT fk_collection_item_price_series
  FOREIGN KEY (price_series_id) REFERENCES price_series (series_id) ON DELETE RESTRICT;

ALTER TABLE collection_item_event
  ADD CONSTRAINT fk_collection_item_event_price_series
  FOREIGN KEY (price_series_id) REFERENCES price_series (series_id) ON DELETE RESTRICT;

CREATE INDEX idx_collection_item_price_series
  ON collection_item (price_series_id)
  WHERE price_series_id IS NOT NULL;

CREATE INDEX idx_collection_item_event_price_series_time
  ON collection_item_event (price_series_id, effective_at)
  WHERE price_series_id IS NOT NULL;
