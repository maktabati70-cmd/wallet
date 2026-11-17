-- 005_personal_mode.sql — allow transfers without a fee transaction
-- (COLLECT_FEES=false: personal use, no service/resource fee is charged).
BEGIN;
ALTER TABLE transfers ALTER COLUMN fee_raw_hex DROP NOT NULL;
ALTER TABLE transfers ALTER COLUMN fee_txid DROP NOT NULL;
ALTER TABLE transfers ALTER COLUMN treasury_address DROP NOT NULL;
ALTER TABLE transfers DROP CONSTRAINT IF EXISTS transfers_fee_micro_check;
ALTER TABLE transfers ADD CONSTRAINT transfers_fee_micro_nonneg CHECK (fee_micro >= 0);
ALTER TABLE transfers ADD CONSTRAINT transfers_fee_tx_iff_fee
    CHECK ((fee_micro = 0) = (fee_raw_hex IS NULL) AND (fee_raw_hex IS NULL) = (fee_txid IS NULL));
COMMIT;
