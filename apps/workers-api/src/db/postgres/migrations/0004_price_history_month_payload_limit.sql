ALTER TABLE price_history_month
  ADD CONSTRAINT ck_price_history_month_payload_bytes
  CHECK (octet_length(points::text) <= 24576);
