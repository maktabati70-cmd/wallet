"""The platform's operator wallet: activates new user accounts and lends them
Energy/Bandwidth (Stake 2.0 delegation) so they can send USDT without TRX.

This is a HOT wallet — its key is in the server environment — so keep only a
small TRX balance there. It never holds user funds and cannot move them; the
fee wallet (treasury) is a different address whose key is NOT on the server.
"""
from __future__ import annotations

import asyncio
import logging
import time

from . import crypto, tron_tx
from .chain import ChainError, TronGridReader

log = logging.getLogger("wallet.operator")

ACTIVATION_SUN = 100_000           # 0.1 TRX sent to create a brand-new account
MIN_DELEGATE_SUN = 1_000_000       # protocol minimum delegation: 1 TRX
TX_LIFETIME_MS = 60_000
KEEP_LIQUID_SUN = 30_000_000       # keep 30 TRX unstaked for fees


class Operator:
    def __init__(self, chain: TronGridReader, private_key: bytes):
        self.chain = chain
        self._key = private_key
        self.address = crypto.address_from_private(private_key)

    @classmethod
    def from_settings(cls, chain: TronGridReader, key_hex: str, mnemonic: str) -> "Operator | None":
        if key_hex:
            return cls(chain, bytes.fromhex(key_hex.removeprefix("0x")))
        if mnemonic:
            return cls(chain, crypto.private_key_from_mnemonic(mnemonic))
        return None

    async def _send(self, build) -> str:
        ref = await self.chain.now_block()
        now = int(time.time() * 1000)
        raw = build(ref, ref.timestamp_ms + TX_LIFETIME_MS, now)
        tid = tron_tx.txid(raw)
        sig = crypto.sign_digest(self._key, bytes.fromhex(tid))
        await self.chain.broadcast_hex(tron_tx.signed_transaction(raw, sig).hex())
        return tid

    async def wait(self, txid: str, timeout: float = 45.0) -> dict:
        """Wait until the transaction is in a block; raise if it failed."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            info = await self.chain.tx_info(txid)
            if info.get("blockNumber"):
                if info.get("result") == "FAILED":
                    raise ChainError(f"transaction {txid} failed: {info.get('resMessage', '')}")
                receipt = (info.get("receipt") or {}).get("result")
                if receipt and receipt != "SUCCESS":
                    raise ChainError(f"transaction {txid} failed: {receipt}")
                return info
            await asyncio.sleep(1.5)
        raise ChainError(f"transaction {txid} not confirmed in time")

    async def ensure_activated(self, address: str) -> bool:
        """Create the account on-chain if needed. Returns True if we sent TRX."""
        if await self.chain.account_raw(address):
            return False
        tid = await self._send(lambda ref, exp, ts: tron_tx.build_trx_transfer(
            self.address, address, ACTIVATION_SUN, ref, exp, ts))
        await self.wait(tid)
        self.chain.forget(address)
        return True

    async def _sun_for(self, resource: int, units: int) -> int:
        """TRX (in sun) that must be delegated to give `units` Energy/Bandwidth."""
        r = await self.chain.account_resource(self.address)
        if resource == tron_tx.ENERGY:
            limit, weight = int(r.get("TotalEnergyLimit", 0)), int(r.get("TotalEnergyWeight", 0))
        else:
            limit, weight = int(r.get("TotalNetLimit", 0)), int(r.get("TotalNetWeight", 0))
        if not limit or not weight:
            raise ChainError("network resource totals unavailable")
        trx = -(-units * weight // limit) + 1           # ceil, +1 TRX margin
        return max(MIN_DELEGATE_SUN, trx * 1_000_000)

    async def delegate(self, receiver: str, resource: int, units: int) -> int:
        """Lend `units` of Energy/Bandwidth to receiver. Returns delegated sun."""
        sun = await self._sun_for(resource, units)
        available = await self.chain.can_delegate_max(self.address, resource)
        if available < sun:
            kind = "Energy" if resource == tron_tx.ENERGY else "Bandwidth"
            raise ChainError(f"platform {kind} exhausted (need {sun}, have {available})")
        tid = await self._send(lambda ref, exp, ts: tron_tx.build_delegate(
            self.address, receiver, resource, sun, ref, exp, ts))
        await self.wait(tid)
        return sun

    async def undelegate(self, receiver: str, resource: int, sun: int) -> None:
        if sun <= 0:
            return
        tid = await self._send(lambda ref, exp, ts: tron_tx.build_delegate(
            self.address, receiver, resource, sun, ref, exp, ts, undelegate=True))
        await self.wait(tid)

    async def auto_stake(self, energy_share: float = 0.85) -> str | None:
        """Testnet convenience: stake idle TRX (keeps 30 TRX liquid)."""
        acct = await self.chain.account_raw(self.address)
        idle = int(acct.get("balance", 0)) - KEEP_LIQUID_SUN
        if idle < 20_000_000:
            return None
        energy_sun = int(idle * energy_share) // 1_000_000 * 1_000_000
        bw_sun = (idle - energy_sun) // 1_000_000 * 1_000_000
        for resource, amount in ((tron_tx.ENERGY, energy_sun), (tron_tx.BANDWIDTH, bw_sun)):
            if amount >= 1_000_000:
                tid = await self._send(lambda ref, exp, ts, r=resource, a=amount:
                                       tron_tx.build_freeze_v2(self.address, a, r, ref, exp, ts))
                await self.wait(tid)
        log.info("operator staked %s sun for Energy and %s sun for Bandwidth", energy_sun, bw_sun)
        return f"energy={energy_sun} bandwidth={bw_sun}"
