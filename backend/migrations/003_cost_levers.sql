-- 003_cost_levers.sql — support the three cost-reduction levers:
--   1) delivery mode (two transfers vs. relayer contract with one-time activation)
--   2) energy source (own staked TRX vs. rented Energy)
--   3) GasFree route (recorded as a delivery mode; fees set by the provider)
BEGIN;

ALTER TABLE fee_schedules
    ADD COLUMN stake_energy_cost_sun INTEGER NOT NULL DEFAULT 5
        CHECK (stake_energy_cost_sun BETWEEN 0 AND 1000);
ALTER TABLE fee_schedules
    ADD CONSTRAINT fee_schedules_stake_le_rent CHECK (stake_energy_cost_sun <= energy_price_sun);

ALTER TABLE fee_quotes
    ADD COLUMN delivery_mode TEXT NOT NULL DEFAULT 'two_transfers'
        CHECK (delivery_mode IN ('two_transfers', 'relayer', 'gasfree')),
    ADD COLUMN energy_source TEXT NOT NULL DEFAULT 'rented'
        CHECK (energy_source IN ('staked', 'rented', 'provider')),
    ADD COLUMN activation_included BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE sponsored_transfers
    ADD COLUMN delivery_mode TEXT NOT NULL DEFAULT 'two_transfers'
        CHECK (delivery_mode IN ('two_transfers', 'relayer', 'gasfree')),
    ADD COLUMN energy_source TEXT NOT NULL DEFAULT 'rented'
        CHECK (energy_source IN ('staked', 'rented', 'provider'));

-- Market-based starting prices (mid-November 2026 research):
--   rented Energy ~36-46 sun (burn price is 100 sun); TRX ~0.33 USDT.
-- Re-check before testing; update with `admin_cli set-fees`.
INSERT INTO fee_schedules (
    created_by, note, service_fee_bps, min_service_fee_micro, max_service_fee_micro,
    energy_price_sun, bandwidth_price_sun, trx_price_micro, resource_margin_bps,
    min_send_micro, max_send_micro, stake_energy_cost_sun
) VALUES (
    'migration', 'market prices Nov 2026; staked energy priced at 5 sun',
    50, 100000, 10000000,
    45,            -- rented Energy (conservative vs. 36-46 market)
    0,
    330000,        -- 1 TRX = 0.33 USDT
    1000,          -- +10 % margin
    5000000, 10000000000,
    5              -- internal cost of own staked Energy
);

INSERT INTO audit_log (actor, action, details)
VALUES ('migration', 'fee_schedule.created',
        '{"note": "003_cost_levers market prices", "energy_price_sun": 45, "stake_energy_cost_sun": 5}');
COMMIT;
