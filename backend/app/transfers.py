"""Sending USDT (Phase 3).

Flow
1. prepare  — from an unexpired quote, the server BUILDS two unsigned TRC20
              transfers (recipient, and fee -> treasury). The phone decodes and
              checks every byte before signing (see mobile/lib/core/tron_tx.dart).
2. submit   — the phone sends the two signatures. The server checks they were
              made by the sender over exactly those transactions, re-checks the
              balance, and claims the transfer exactly once (idempotency key).
3. process  — (background) activate the account if new, lend Energy/Bandwidth,
              broadcast fee then recipient transfer, wait for confirmation,
              take the Energy back. The user never needs TRX.

If the fee transfer fails nothing is sent. If the fee succeeds but the
recipient transfer fails, the transfer is marked `refund_needed` for the
operator (the fee wallet's key is not on the server, by design).
"""
from __future__ import annotations

import logging
import time
from datetime import datetime, timedelta, timezone

from . import crypto, tron_tx
from .chain import ChainError
from .config import Settings
from .operator import Operator

log = logging.getLogger("wallet.transfers")

FEE_LIMIT_SUN = 40_000_000          # max TRX a tx may burn (user has none anyway)
TX_LIFETIME_MS = 10 * 60 * 1000     # signed transactions are valid for 10 minutes
BANDWIDTH_TO_LEND = 800             # two TRC20 transfers ≈ 690 bytes
ENERGY_MARGIN = 1.10


class TransferError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def public_view(t: dict, explorer: str) -> dict:
    return {
        "transfer_id": str(t["id"]),
        "status": t["status"],
        "step": t["step"],
        "failure_reason": t["failure_reason"],
        "from_address": t["from_address"],
        "to_address": t["to_address"],
        "recipient_micro": t["recipient_micro"],
        "fee_micro": t["fee_micro"],
        "main_txid": t["main_txid"],
        "fee_txid": t["fee_txid"],
        "main_explorer_url": explorer + t["main_txid"],
        "fee_explorer_url": explorer + t["fee_txid"],
        "expires_at": t["expires_at"].isoformat(),
    }


class TransferService:
    def __init__(self, settings: Settings, repo, chain, operator: Operator | None):
        self.settings, self.repo, self.chain, self.op = settings, repo, chain, operator

    def _require_enabled(self) -> None:
        if not self.settings.sending_enabled or self.op is None or not self.settings.treasury_address:
            raise TransferError(503, "Sending is not enabled on this server yet.")

    # ------------------------------------------------------------- prepare
    async def prepare(self, quote_id: str) -> dict:
        self._require_enabled()
        existing = self.repo.transfer_for_quote(quote_id)
        if existing:
            if existing["status"] != "prepared":
                raise TransferError(409, "This quote was already used.")
            return self._prepared_view(existing)

        q = self.repo.get_quote(quote_id)
        if not q or q["network"] != self.settings.tron_network:
            raise TransferError(404, "Quote not found.")
        if q["status"] != "quoted" or q["expires_at"] <= datetime.now(timezone.utc):
            raise TransferError(410, "This quote has expired. Please review the transfer again.")

        fee = q["service_fee_micro"] + q["resource_fee_micro"]
        ref = await self.chain.now_block()
        exp = ref.timestamp_ms + TX_LIFETIME_MS
        ts = int(time.time() * 1000)
        usdt = self.settings.usdt_contract
        main_raw = tron_tx.build_trc20_transfer(q["from_address"], usdt, q["to_address"],
                                                q["recipient_micro"], ref, exp, ts, FEE_LIMIT_SUN)
        fee_raw = tron_tx.build_trc20_transfer(q["from_address"], usdt, self.settings.treasury_address,
                                               fee, ref, exp, ts + 1, FEE_LIMIT_SUN)
        t = self.repo.create_transfer(
            quote_id=quote_id, network=self.settings.tron_network,
            from_address=q["from_address"], to_address=q["to_address"],
            treasury_address=self.settings.treasury_address,
            recipient_micro=q["recipient_micro"], fee_micro=fee,
            main_raw_hex=main_raw.hex(), main_txid=tron_tx.txid(main_raw),
            fee_raw_hex=fee_raw.hex(), fee_txid=tron_tx.txid(fee_raw),
            expires_at=datetime.fromtimestamp(exp / 1000, timezone.utc) - timedelta(seconds=60),
        )
        return self._prepared_view(t)

    def _prepared_view(self, t: dict) -> dict:
        return {
            "transfer_id": str(t["id"]),
            "expires_at": t["expires_at"].isoformat(),
            "usdt_contract": self.settings.usdt_contract,
            "treasury_address": t["treasury_address"],
            "transactions": [
                {"purpose": "recipient", "raw_data_hex": t["main_raw_hex"], "txid": t["main_txid"],
                 "to": t["to_address"], "amount_micro": t["recipient_micro"]},
                {"purpose": "fee", "raw_data_hex": t["fee_raw_hex"], "txid": t["fee_txid"],
                 "to": t["treasury_address"], "amount_micro": t["fee_micro"]},
            ],
        }

    # ------------------------------------------------------------- submit
    async def submit(self, transfer_id: str, idempotency_key: str,
                     main_sig_hex: str, fee_sig_hex: str) -> tuple[dict, bool]:
        """Returns (view, should_process)."""
        self._require_enabled()
        t = self.repo.get_transfer(transfer_id)
        if not t:
            raise TransferError(404, "Transfer not found.")
        if t["idempotency_key"] == idempotency_key:
            return public_view(t, self.settings.explorer_tx_url), False  # safe retry
        if t["status"] != "prepared":
            raise TransferError(409, "This transfer was already submitted.")
        if t["expires_at"] <= datetime.now(timezone.utc):
            self.repo.update_transfer(transfer_id, status="expired", step="expired")
            raise TransferError(410, "The signed transaction expired. Please start again.")

        try:
            main_sig, fee_sig = bytes.fromhex(main_sig_hex), bytes.fromhex(fee_sig_hex)
        except ValueError:
            raise TransferError(422, "Invalid signature format.")
        for raw_hex, tid, sig in ((t["main_raw_hex"], t["main_txid"], main_sig),
                                  (t["fee_raw_hex"], t["fee_txid"], fee_sig)):
            raw = bytes.fromhex(raw_hex)
            if tron_tx.txid(raw) != tid or tron_tx.parse_trc20_transfer(raw).owner != t["from_address"]:
                raise TransferError(500, "Stored transaction is inconsistent.")
            if crypto.signer_address(bytes.fromhex(tid), sig) != t["from_address"]:
                raise TransferError(422, "Signature does not match the sending wallet.")

        self.chain.forget(t["from_address"])
        balance = await self.chain.usdt_balance(t["from_address"])
        if balance < t["recipient_micro"] + t["fee_micro"]:
            raise TransferError(422, "Insufficient USDT balance.")

        if not self.repo.claim_transfer(transfer_id, idempotency_key, main_sig_hex, fee_sig_hex):
            raise TransferError(409, "This transfer was already submitted or expired.")
        self.repo.add_audit("api", "transfer.submitted", {
            "transfer_id": transfer_id, "from": t["from_address"], "to": t["to_address"],
            "recipient_micro": t["recipient_micro"], "fee_micro": t["fee_micro"]})
        return public_view(self.repo.get_transfer(transfer_id), self.settings.explorer_tx_url), True

    # ------------------------------------------------------------- process
    async def process(self, transfer_id: str) -> None:
        t = self.repo.get_transfer(transfer_id)
        if not t or t["status"] != "processing":
            return
        sender, upd = t["from_address"], (lambda **f: self.repo.update_transfer(transfer_id, **f))
        q = self.repo.get_quote(str(t["quote_id"]))
        energy_sun = bw_sun = 0
        try:
            upd(step="activating")
            if await self.op.ensure_activated(sender):
                upd(activation_sent=True)

            upd(step="providing_energy")
            energy_sun = await self.op.delegate(sender, tron_tx.ENERGY,
                                                int(q["energy_units"] * ENERGY_MARGIN))
            bw_sun = await self.op.delegate(sender, tron_tx.BANDWIDTH, BANDWIDTH_TO_LEND)
            upd(energy_delegated_sun=energy_sun, bandwidth_delegated_sun=bw_sun)

            upd(step="sending_fee")
            fee_tx = tron_tx.signed_transaction(bytes.fromhex(t["fee_raw_hex"]),
                                                bytes.fromhex(t["fee_signature"]))
            await self.chain.broadcast_hex(fee_tx.hex())
            fee_info = await self.op.wait(t["fee_txid"])
        except ChainError as exc:
            log.warning("transfer %s failed before sending: %s", transfer_id, exc)
            upd(status="failed", step="failed", failure_reason=str(exc)[:300])
            self.repo.add_audit("api", "transfer.failed", {"transfer_id": transfer_id, "reason": str(exc)[:300]})
            await self._reclaim(transfer_id, sender, energy_sun, bw_sun)
            return

        try:
            upd(step="sending")
            main_tx = tron_tx.signed_transaction(bytes.fromhex(t["main_raw_hex"]),
                                                 bytes.fromhex(t["main_signature"]))
            await self.chain.broadcast_hex(main_tx.hex())
            main_info = await self.op.wait(t["main_txid"])
            used = sum(int((i.get("receipt") or {}).get("energy_usage_total", 0))
                       for i in (fee_info, main_info))
            upd(status="confirmed", step="done", energy_used=used)
            self.repo.add_audit("api", "transfer.confirmed", {"transfer_id": transfer_id, "energy_used": used})
        except ChainError as exc:
            log.error("transfer %s: fee taken but recipient transfer failed: %s", transfer_id, exc)
            upd(status="refund_needed", step="failed", failure_reason=str(exc)[:300])
            self.repo.add_audit("api", "transfer.refund_needed", {"transfer_id": transfer_id, "reason": str(exc)[:300]})
        finally:
            self.chain.forget(sender)
            self.chain.forget(t["to_address"])
        await self._reclaim(transfer_id, sender, energy_sun, bw_sun)

    async def _reclaim(self, transfer_id: str, sender: str, energy_sun: int, bw_sun: int) -> None:
        try:
            await self.op.undelegate(sender, tron_tx.ENERGY, energy_sun)
            await self.op.undelegate(sender, tron_tx.BANDWIDTH, bw_sun)
            self.repo.update_transfer(transfer_id, resources_reclaimed=True)
        except ChainError as exc:  # retried later by the operator CLI
            log.warning("reclaim for %s failed: %s", transfer_id, exc)
