-- 001_init.sql — Phase 1 schema (non-custodial wallet backend)
--
-- The backend never stores private keys, seed phrases, passwords or balances.
-- It stores: pricing configuration, fee quotes, (Phase 3) sponsored transfer
-- records for accounting, and an append-only, hash-chained audit log.
--
-- All USDT amounts are BIGINT micro-USDT (6 decimals). No floating point.

BEGIN;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION forbid_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% on table % is not allowed (append-only)', TG_OP, TG_TABLE_NAME
        USING ERRCODE = 'insufficient_privilege';
END;
$$;

-- TRON base58 address shape (full checksum validation happens in the app)
CREATE DOMAIN tron_address AS TEXT
    CHECK (VALUE ~ '^T[1-9A-HJ-NP-Za-km-z]{33}$');

CREATE DOMAIN micro_usdt AS BIGINT CHECK (VALUE >= 0);

-- ---------------------------------------------------------------------------
-- Fee schedules — append-only; the newest row is the active schedule.
-- Changed only via the admin CLI on the server (no public admin endpoint).
-- ---------------------------------------------------------------------------
CREATE TABLE fee_schedules (
    id                     BIGSERIAL PRIMARY KEY,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by             TEXT        NOT NULL,
    note                   TEXT        NOT NULL DEFAULT '',
    service_fee_bps        INTEGER     NOT NULL CHECK (service_fee_bps BETWEEN 0 AND 500),
    min_service_fee_micro  micro_usdt  NOT NULL,
    max_service_fee_micro  micro_usdt  NOT NULL,
    energy_price_sun       INTEGER     NOT NULL CHECK (energy_price_sun BETWEEN 1 AND 1000),
    bandwidth_price_sun    INTEGER     NOT NULL CHECK (bandwidth_price_sun BETWEEN 0 AND 10000),
    trx_price_micro        BIGINT      NOT NULL CHECK (trx_price_micro > 0),
    resource_margin_bps    INTEGER     NOT NULL CHECK (resource_margin_bps BETWEEN 0 AND 5000),
    min_send_micro         micro_usdt  NOT NULL CHECK (min_send_micro > 0),
    max_send_micro         micro_usdt  NOT NULL,
    CHECK (min_service_fee_micro <= max_service_fee_micro),
    CHECK (min_send_micro <= max_send_micro)
);

CREATE TRIGGER fee_schedules_append_only
    BEFORE UPDATE OR DELETE ON fee_schedules
    FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
CREATE TRIGGER fee_schedules_no_truncate
    BEFORE TRUNCATE ON fee_schedules
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

-- Development defaults. PRICES ARE PLACEHOLDERS — update them with the admin
-- CLI from real Energy-rental and TRX market prices before testing quotes.
INSERT INTO fee_schedules (
    created_by, note, service_fee_bps, min_service_fee_micro, max_service_fee_micro,
    energy_price_sun, bandwidth_price_sun, trx_price_micro, resource_margin_bps,
    min_send_micro, max_send_micro
) VALUES (
    'migration', 'initial development defaults',
    50,            -- 0.50 % service fee
    100000,        -- min service fee 0.10 USDT
    10000000,      -- max service fee 10 USDT
    60,            -- Energy price paid by platform (sun per unit) — placeholder
    0,             -- Bandwidth covered by platform-staked TRX
    300000,        -- 1 TRX = 0.30 USDT — placeholder
    1000,          -- +10 % margin on resource cost
    5000000,       -- min send 5 USDT (smaller amounts are mostly eaten by resource cost)
    10000000000    -- max send 10,000 USDT per transfer (risk control)
);

-- ---------------------------------------------------------------------------
-- Audit log — append-only and hash-chained (tamper-evident).
-- ---------------------------------------------------------------------------
CREATE TABLE audit_log (
    id           BIGSERIAL   PRIMARY KEY,
    occurred_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor        TEXT        NOT NULL,
    action       TEXT        NOT NULL,
    details      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    prev_hash    TEXT,
    row_hash     TEXT        NOT NULL
);

CREATE OR REPLACE FUNCTION audit_log_chain() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    last_hash TEXT;
BEGIN
    -- serialise writers so the chain can never fork
    PERFORM pg_advisory_xact_lock(7262201);
    SELECT row_hash INTO last_hash FROM audit_log ORDER BY id DESC LIMIT 1;
    NEW.prev_hash := last_hash;
    NEW.row_hash := encode(sha256(convert_to(
        coalesce(last_hash, '') || '|' || NEW.id::text || '|' ||
        to_char(NEW.occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US') || '|' ||
        NEW.actor || '|' || NEW.action || '|' || NEW.details::text, 'UTF8')), 'hex');
    RETURN NEW;
END;
$$;

CREATE TRIGGER audit_log_chain_before_insert
    BEFORE INSERT ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_chain();

CREATE TRIGGER audit_log_append_only
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
CREATE TRIGGER audit_log_no_truncate
    BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

-- ---------------------------------------------------------------------------
-- Fee quotes — short-lived; a Phase 3 transfer must reference an unexpired,
-- unused quote (one quote = one transfer → prevents duplicate submissions).
-- ---------------------------------------------------------------------------
CREATE TABLE fee_quotes (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at            TIMESTAMPTZ NOT NULL,
    network               TEXT        NOT NULL,
    from_address          tron_address NOT NULL,
    to_address            tron_address NOT NULL,
    amount_micro          micro_usdt  NOT NULL CHECK (amount_micro > 0),
    service_fee_micro     micro_usdt  NOT NULL,
    resource_fee_micro    micro_usdt  NOT NULL,
    recipient_micro       micro_usdt  NOT NULL CHECK (recipient_micro > 0),
    resource_cost_micro   micro_usdt  NOT NULL,
    energy_units          INTEGER     NOT NULL CHECK (energy_units > 0),
    recipient_holds_usdt  BOOLEAN     NOT NULL,
    fee_schedule_id       BIGINT      NOT NULL REFERENCES fee_schedules(id),
    status                TEXT        NOT NULL DEFAULT 'quoted'
                          CHECK (status IN ('quoted', 'used', 'expired')),
    CHECK (from_address <> to_address),
    CHECK (amount_micro = recipient_micro + service_fee_micro + resource_fee_micro),
    CHECK (expires_at > created_at)
);
CREATE INDEX fee_quotes_expires_idx ON fee_quotes (expires_at) WHERE status = 'quoted';

-- ---------------------------------------------------------------------------
-- Sponsored transfers (used from Phase 3). Accounting record of each send the
-- platform sponsored: revenue collected vs. resources actually spent.
-- ---------------------------------------------------------------------------
CREATE TABLE sponsored_transfers (
    id                  BIGSERIAL   PRIMARY KEY,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    quote_id            UUID        NOT NULL UNIQUE REFERENCES fee_quotes(id),
    idempotency_key     TEXT        NOT NULL UNIQUE CHECK (length(idempotency_key) BETWEEN 16 AND 100),
    from_address        tron_address NOT NULL,
    to_address          tron_address NOT NULL,
    recipient_micro     micro_usdt  NOT NULL,
    fee_collected_micro micro_usdt  NOT NULL,
    main_txid           TEXT        UNIQUE CHECK (main_txid ~ '^[0-9a-f]{64}$'),
    fee_txid            TEXT        UNIQUE CHECK (fee_txid ~ '^[0-9a-f]{64}$'),
    energy_delegated    INTEGER     NOT NULL DEFAULT 0,
    resource_spent_sun  BIGINT      NOT NULL DEFAULT 0 CHECK (resource_spent_sun >= 0),
    status              TEXT        NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'broadcast', 'confirmed', 'failed')),
    failure_reason      TEXT
);

-- Daily revenue / cost view for the operator
CREATE VIEW daily_revenue AS
SELECT date_trunc('day', created_at)        AS day,
       count(*)                              AS transfers,
       sum(fee_collected_micro)              AS fees_collected_micro,
       sum(resource_spent_sun)               AS resources_spent_sun
FROM sponsored_transfers
WHERE status = 'confirmed'
GROUP BY 1
ORDER BY 1 DESC;

COMMIT;
