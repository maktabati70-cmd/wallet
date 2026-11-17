-- 004_transfers.sql — real sending (Phase 3).
-- One row per send: two user-signed TRC20 transfers (recipient + fee) that the
-- platform sponsors with Energy/Bandwidth from its operator account.
-- Replaces the unused placeholder table sponsored_transfers.
BEGIN;

DROP VIEW IF EXISTS daily_revenue;
DROP TABLE IF EXISTS sponsored_transfers;

CREATE TABLE transfers (
    id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    quote_id             UUID         NOT NULL UNIQUE REFERENCES fee_quotes(id),
    network              TEXT         NOT NULL,
    from_address         tron_address NOT NULL,
    to_address           tron_address NOT NULL,
    treasury_address     tron_address NOT NULL,
    recipient_micro      micro_usdt   NOT NULL CHECK (recipient_micro > 0),
    fee_micro            micro_usdt   NOT NULL CHECK (fee_micro > 0),
    main_raw_hex         TEXT         NOT NULL,
    main_txid            TEXT         NOT NULL UNIQUE CHECK (main_txid ~ '^[0-9a-f]{64}$'),
    fee_raw_hex          TEXT         NOT NULL,
    fee_txid             TEXT         NOT NULL UNIQUE CHECK (fee_txid ~ '^[0-9a-f]{64}$'),
    expires_at           TIMESTAMPTZ  NOT NULL,
    idempotency_key      TEXT         UNIQUE CHECK (idempotency_key IS NULL OR length(idempotency_key) BETWEEN 16 AND 100),
    main_signature       TEXT,
    fee_signature        TEXT,
    status               TEXT         NOT NULL DEFAULT 'prepared'
                         CHECK (status IN ('prepared', 'processing', 'confirmed', 'failed',
                                           'refund_needed', 'expired')),
    step                 TEXT         NOT NULL DEFAULT 'prepared',
    failure_reason       TEXT,
    activation_sent      BOOLEAN      NOT NULL DEFAULT false,
    energy_delegated_sun BIGINT       NOT NULL DEFAULT 0,
    bandwidth_delegated_sun BIGINT    NOT NULL DEFAULT 0,
    energy_used          BIGINT       NOT NULL DEFAULT 0,
    resources_reclaimed  BOOLEAN      NOT NULL DEFAULT false,
    CHECK (from_address <> to_address)
);
CREATE INDEX transfers_from_idx ON transfers (from_address, created_at DESC);
CREATE INDEX transfers_open_idx ON transfers (status) WHERE status IN ('prepared', 'processing');

CREATE VIEW daily_revenue AS
SELECT date_trunc('day', created_at)  AS day,
       count(*)                        AS transfers,
       sum(fee_micro)                  AS fees_collected_micro,
       sum(energy_used)                AS energy_used
FROM transfers
WHERE status IN ('confirmed', 'refund_needed')
GROUP BY 1
ORDER BY 1 DESC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'wallet_api') THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE ON transfers TO wallet_api';
        EXECUTE 'GRANT SELECT ON daily_revenue TO wallet_api';
    END IF;
END $$;

COMMIT;
