-- 006_own_trx.sql — the sender may pay the network fee with their own TRX
-- (no Energy lent by the platform; no operator wallet needed on the server).
BEGIN;
ALTER TABLE fee_quotes DROP CONSTRAINT IF EXISTS fee_quotes_energy_source_check;
ALTER TABLE fee_quotes ADD CONSTRAINT fee_quotes_energy_source_check
    CHECK (energy_source IN ('staked', 'rented', 'provider', 'own_trx'));
ALTER TABLE fee_quotes ADD COLUMN network_fee_sun BIGINT NOT NULL DEFAULT 0
    CHECK (network_fee_sun >= 0);
COMMIT;
