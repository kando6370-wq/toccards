CREATE FUNCTION assert_price_history_month_staged()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM price_series AS series
    JOIN price_ingest_batch AS batch
      ON batch.batch_id = NEW.last_batch_id
     AND batch.source_id = series.source_id
    WHERE series.series_id = NEW.series_id
      AND batch.status = 'validated'
      AND batch.scope_code LIKE 'current:%'
  ) THEN
    RAISE EXCEPTION
      'history series % must be written by a validated current batch, got %',
      NEW.series_id,
      NEW.last_batch_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_price_history_month_staged
BEFORE INSERT OR UPDATE
ON price_history_month
FOR EACH ROW
EXECUTE FUNCTION assert_price_history_month_staged();

CREATE FUNCTION assert_price_history_month_published()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND ROW(
       NEW.points,
       NEW.point_count,
       NEW.first_observed_on,
       NEW.last_observed_on,
       NEW.content_checksum_sha256
     ) IS DISTINCT FROM ROW(
       OLD.points,
       OLD.point_count,
       OLD.first_observed_on,
       OLD.last_observed_on,
       OLD.content_checksum_sha256
     )
     AND NEW.last_batch_id = OLD.last_batch_id THEN
    RAISE EXCEPTION
      'history series % month % content changes require a new batch lineage',
      NEW.series_id,
      NEW.month_start;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM price_series AS series
    JOIN price_ingest_batch AS batch
      ON batch.batch_id = NEW.last_batch_id
     AND batch.source_id = series.source_id
    JOIN current_price_pointer AS pointer
      ON pointer.batch_id = batch.batch_id
     AND pointer.scope_code = batch.scope_code
    WHERE series.series_id = NEW.series_id
      AND batch.status = 'published'
      AND pointer.scope_code LIKE 'current:%'
  ) THEN
    RAISE EXCEPTION
      'history series % must reference a published same-source batch, got %',
      NEW.series_id,
      NEW.last_batch_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_price_history_month_published
AFTER INSERT OR UPDATE
ON price_history_month
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION assert_price_history_month_published();
