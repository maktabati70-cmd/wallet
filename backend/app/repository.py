"""PostgreSQL data access (psycopg 3). All SQL is parameterised."""
from __future__ import annotations

import json
from dataclasses import asdict
from datetime import datetime, timedelta, timezone
from typing import Any, Protocol

from .fees import FeeQuote, FeeSchedule

_SCHEDULE_COLUMNS = (
    "service_fee_bps, min_service_fee_micro, max_service_fee_micro, energy_price_sun, "
    "bandwidth_price_sun, trx_price_micro, resource_margin_bps, min_send_micro, max_send_micro, "
    "stake_energy_cost_sun"
)

AUDIT_VERIFY_SQL = """
SELECT id FROM (
  SELECT id,
    prev_hash IS NOT DISTINCT FROM lag(row_hash) OVER w
    AND row_hash = encode(sha256(convert_to(
      coalesce(lag(row_hash) OVER w, '') || '|' || id::text || '|' ||
      to_char(occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US') || '|' ||
      actor || '|' || action || '|' || details::text, 'UTF8')), 'hex') AS ok
  FROM audit_log WINDOW w AS (ORDER BY id)
) t WHERE NOT ok ORDER BY id
"""


class Repository(Protocol):
    def active_fee_schedule(self) -> tuple[int, FeeSchedule]: ...
    def save_quote(self, *, network: str, from_address: str, to_address: str,
                   q: FeeQuote, schedule_id: int, ttl_seconds: int) -> tuple[str, datetime]: ...
    def add_audit(self, actor: str, action: str, details: dict[str, Any]) -> None: ...
    def ping(self) -> bool: ...
    def get_quote(self, quote_id: str) -> dict | None: ...
    def get_transfer(self, transfer_id: str) -> dict | None: ...
    def transfer_for_quote(self, quote_id: str) -> dict | None: ...
    def create_transfer(self, **fields) -> dict: ...
    def claim_transfer(self, transfer_id: str, idempotency_key: str,
                       main_sig: str, fee_sig: str) -> bool: ...
    def update_transfer(self, transfer_id: str, **fields) -> None: ...


class PostgresRepository:
    def __init__(self, database_url: str):
        from psycopg_pool import ConnectionPool  # imported lazily

        self.pool = ConnectionPool(database_url, min_size=1, max_size=10, open=True)

    def ping(self) -> bool:
        try:
            with self.pool.connection() as conn:
                conn.execute("SELECT 1")
            return True
        except Exception:
            return False

    def active_fee_schedule(self) -> tuple[int, FeeSchedule]:
        with self.pool.connection() as conn:
            row = conn.execute(
                f"SELECT id, {_SCHEDULE_COLUMNS} FROM fee_schedules ORDER BY id DESC LIMIT 1"
            ).fetchone()
        if row is None:
            raise RuntimeError("no fee schedule configured")
        return row[0], FeeSchedule(*row[1:])

    def save_quote(self, *, network, from_address, to_address, q, schedule_id, ttl_seconds):
        expires = datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)
        with self.pool.connection() as conn:
            row = conn.execute(
                """INSERT INTO fee_quotes (expires_at, network, from_address, to_address,
                       amount_micro, service_fee_micro, resource_fee_micro, recipient_micro,
                       resource_cost_micro, energy_units, recipient_holds_usdt, fee_schedule_id,
                       delivery_mode, energy_source, activation_included)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id, expires_at""",
                (expires, network, from_address, to_address, q.amount_micro,
                 q.service_fee_micro, q.resource_fee_micro, q.recipient_micro,
                 q.resource_cost_micro, q.energy_units, q.recipient_holds_usdt, schedule_id,
                 q.mode, q.energy_source, q.activation_included),
            ).fetchone()
        return str(row[0]), row[1]

    def add_audit(self, actor, action, details):
        with self.pool.connection() as conn:
            conn.execute(
                "INSERT INTO audit_log (actor, action, details) VALUES (%s, %s, %s::jsonb)",
                (actor, action, json.dumps(details, sort_keys=True)),
            )

    # ---- transfers (Phase 3) ----
    def _one(self, sql: str, params: tuple) -> dict | None:
        from psycopg.rows import dict_row
        with self.pool.connection() as conn:
            return conn.cursor(row_factory=dict_row).execute(sql, params).fetchone()

    def get_quote(self, quote_id: str) -> dict | None:
        return self._one("SELECT * FROM fee_quotes WHERE id = %s", (quote_id,))

    def get_transfer(self, transfer_id: str) -> dict | None:
        return self._one("SELECT * FROM transfers WHERE id = %s", (transfer_id,))

    def transfer_for_quote(self, quote_id: str) -> dict | None:
        return self._one("SELECT * FROM transfers WHERE quote_id = %s", (quote_id,))

    def create_transfer(self, **f) -> dict:
        cols = ", ".join(f)
        marks = ", ".join(["%s"] * len(f))
        return self._one(f"INSERT INTO transfers ({cols}) VALUES ({marks}) RETURNING *",
                         tuple(f.values()))

    def claim_transfer(self, transfer_id: str, idempotency_key: str,
                       main_sig: str, fee_sig: str) -> bool:
        """prepared -> processing exactly once; also burns the quote."""
        with self.pool.connection() as conn, conn.transaction():
            cur = conn.execute(
                """UPDATE transfers SET status = 'processing', step = 'queued',
                          idempotency_key = %s, main_signature = %s, fee_signature = %s,
                          updated_at = now()
                   WHERE id = %s AND status = 'prepared' AND expires_at > now()""",
                (idempotency_key, main_sig, fee_sig, transfer_id))
            if cur.rowcount != 1:
                return False
            conn.execute(
                "UPDATE fee_quotes SET status = 'used' WHERE id = "
                "(SELECT quote_id FROM transfers WHERE id = %s)", (transfer_id,))
            return True

    def update_transfer(self, transfer_id: str, **f) -> None:
        sets = ", ".join(f"{k} = %s" for k in f)
        with self.pool.connection() as conn:
            conn.execute(f"UPDATE transfers SET {sets}, updated_at = now() WHERE id = %s",
                         (*f.values(), transfer_id))

    # ---- admin-only operations (used by the CLI with the owner DB role) ----
    def insert_fee_schedule(self, s: FeeSchedule, actor: str, note: str) -> int:
        s.validate()
        values = asdict(s)
        with self.pool.connection() as conn, conn.transaction():
            row = conn.execute(
                f"""INSERT INTO fee_schedules (created_by, note, {_SCHEDULE_COLUMNS})
                    VALUES (%s, %s, {', '.join(['%s'] * len(values))}) RETURNING id""",
                (actor, note, *values.values()),
            ).fetchone()
            conn.execute(
                "INSERT INTO audit_log (actor, action, details) VALUES (%s, %s, %s::jsonb)",
                (actor, "fee_schedule.created",
                 json.dumps({"fee_schedule_id": row[0], "note": note, **values}, sort_keys=True)),
            )
        return row[0]

    def list_audit(self, limit: int = 20) -> list[tuple]:
        with self.pool.connection() as conn:
            return conn.execute(
                "SELECT id, occurred_at, actor, action, details FROM audit_log "
                "ORDER BY id DESC LIMIT %s", (limit,)
            ).fetchall()

    def verify_audit_chain(self) -> list[int]:
        """Return ids of audit rows whose hash chain does not verify (empty = OK)."""
        with self.pool.connection() as conn:
            return [r[0] for r in conn.execute(AUDIT_VERIFY_SQL).fetchall()]

    def purge_stale_quotes(self, older_than_hours: int = 24) -> int:
        with self.pool.connection() as conn:
            cur = conn.execute(
                """DELETE FROM fee_quotes q
                   WHERE q.status <> 'used'
                     AND q.expires_at < now() - make_interval(hours => %s)
                     AND NOT EXISTS (SELECT 1 FROM sponsored_transfers t WHERE t.quote_id = q.id)""",
                (older_than_hours,),
            )
            return cur.rowcount
