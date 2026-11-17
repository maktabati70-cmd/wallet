"""Read-only TRON access through the TronGrid HTTP API.

Phase 1 only *reads* the chain (balances, USDT history, whether a recipient
already holds USDT). Nothing here signs or broadcasts transactions.

Every TRC20 record is checked against the configured USDT contract and its
6 decimals, so look-alike "USDT" tokens are never shown as real USDT.
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Protocol

from .tron_address import address_to_abi_param, is_valid_address


@dataclass(frozen=True)
class AccountInfo:
    address: str
    activated: bool
    trx_sun: int
    usdt_micro: int


@dataclass(frozen=True)
class UsdtTransfer:
    txid: str
    timestamp_ms: int
    from_address: str
    to_address: str
    amount_micro: int
    direction: str          # "in" | "out" | "self"
    confirmed: bool


class ChainError(RuntimeError):
    pass


def parse_balance_of(payload: dict) -> int:
    """Result of a constant balanceOf(address) call -> micro-USDT."""
    if not (payload.get("result") or {}).get("result"):
        raise ChainError("balanceOf call failed")
    values = payload.get("constant_result") or []
    if not values or not values[0]:
        raise ChainError("balanceOf returned no data")
    return int(values[0], 16)


def parse_free_energy(payload: dict) -> int:
    """Unused Energy of an account from /wallet/getaccountresource."""
    limit = int(payload.get("EnergyLimit", 0))
    used = int(payload.get("EnergyUsed", 0))
    return max(0, limit - used)


class ChainReader(Protocol):
    async def get_account(self, address: str) -> AccountInfo: ...
    async def free_energy(self, address: str) -> int: ...
    async def usdt_history(self, address: str, limit: int, fingerprint: str | None
                           ) -> tuple[list[UsdtTransfer], str | None]: ...


class _TTLCache:
    def __init__(self, ttl: float, max_items: int = 5000):
        self.ttl, self.max_items = ttl, max_items
        self._data: dict[Any, tuple[float, Any]] = {}

    def get(self, key):
        hit = self._data.get(key)
        if hit and hit[0] > time.monotonic():
            return hit[1]
        self._data.pop(key, None)
        return None

    def set(self, key, value):
        if len(self._data) >= self.max_items:
            self._data.clear()
        self._data[key] = (time.monotonic() + self.ttl, value)


def parse_account(address: str, payload: dict, usdt_contract: str) -> AccountInfo:
    data = payload.get("data") or []
    if not data:
        return AccountInfo(address, activated=False, trx_sun=0, usdt_micro=0)
    acct = data[0]
    usdt = 0
    for entry in acct.get("trc20") or []:
        if usdt_contract in entry:
            usdt = int(entry[usdt_contract])
    return AccountInfo(address, activated=True, trx_sun=int(acct.get("balance", 0)), usdt_micro=usdt)


def parse_history(address: str, payload: dict, usdt_contract: str) -> tuple[list[UsdtTransfer], str | None]:
    out: list[UsdtTransfer] = []
    for item in payload.get("data") or []:
        token = item.get("token_info") or {}
        if token.get("address") != usdt_contract or int(token.get("decimals", -1)) != 6:
            continue  # ignore fake / look-alike tokens
        if item.get("type") != "Transfer":
            continue
        frm, to = item.get("from", ""), item.get("to", "")
        if not (is_valid_address(frm) and is_valid_address(to)):
            continue
        direction = "self" if frm == to == address else ("out" if frm == address else "in")
        out.append(UsdtTransfer(
            txid=str(item.get("transaction_id", "")),
            timestamp_ms=int(item.get("block_timestamp", 0)),
            from_address=frm,
            to_address=to,
            amount_micro=int(item.get("value", "0")),
            direction=direction,
            confirmed=True,  # requested with only_confirmed=true
        ))
    fingerprint = (payload.get("meta") or {}).get("fingerprint")
    return out, fingerprint


class TronGridReader:
    def __init__(self, base_url: str, usdt_contract: str, api_key: str = "", timeout: float = 8.0):
        import httpx  # imported lazily so pure modules stay importable without it

        headers = {"Accept": "application/json"}
        if api_key:
            headers["TRON-PRO-API-KEY"] = api_key
        self.usdt = usdt_contract
        self.client = httpx.AsyncClient(base_url=base_url.rstrip("/"), headers=headers, timeout=timeout)
        self.cache = _TTLCache(ttl=10)

    async def _get(self, path: str, params: dict) -> dict:
        try:
            resp = await self.client.get(path, params=params)
        except Exception as exc:  # network errors
            raise ChainError("TRON node is unreachable") from exc
        if resp.status_code == 429:
            raise ChainError("TRON node rate limit reached")
        if resp.status_code >= 400:
            raise ChainError(f"TRON node error {resp.status_code}")
        body = resp.json()
        if body.get("success") is False:
            raise ChainError("TRON node returned an error")
        return body

    async def get_account(self, address: str) -> AccountInfo:
        key = ("acct", address)
        if (hit := self.cache.get(key)) is not None:
            return hit
        body = await self._get(f"/v1/accounts/{address}", {"only_confirmed": "true"})
        info = parse_account(address, body, self.usdt)
        # A TRC20 transfer does NOT activate a TRON account, so the account
        # record can be empty while the address holds USDT. Read the balance
        # from the USDT contract itself — correct for any address.
        usdt = await self.usdt_balance(address)
        info = AccountInfo(info.address, info.activated, info.trx_sun, usdt)
        self.cache.set(key, info)
        return info

    async def usdt_balance(self, address: str) -> int:
        try:
            resp = await self.client.post("/wallet/triggerconstantcontract", json={
                # owner = the contract itself: always exists, unlike a fresh user address
                "owner_address": self.usdt,
                "contract_address": self.usdt,
                "function_selector": "balanceOf(address)",
                "parameter": address_to_abi_param(address),
                "visible": True,
            })
        except Exception as exc:
            raise ChainError("TRON node is unreachable") from exc
        if resp.status_code >= 400:
            raise ChainError(f"TRON node error {resp.status_code}")
        return parse_balance_of(resp.json())

    async def free_energy(self, address: str) -> int:
        """Energy currently available from the platform's own staked TRX."""
        key = ("energy", address)
        if (hit := self.cache.get(key)) is not None:
            return hit
        try:
            resp = await self.client.post("/wallet/getaccountresource",
                                          json={"address": address, "visible": True})
        except Exception as exc:
            raise ChainError("TRON node is unreachable") from exc
        if resp.status_code >= 400:
            raise ChainError(f"TRON node error {resp.status_code}")
        value = parse_free_energy(resp.json())
        self.cache.set(key, value)
        return value

    async def usdt_history(self, address, limit=20, fingerprint=None):
        params = {"limit": str(max(1, min(limit, 50))), "contract_address": self.usdt,
                  "only_confirmed": "true"}
        if fingerprint:
            params["fingerprint"] = fingerprint
        key = ("hist", address, params["limit"], fingerprint)
        if (hit := self.cache.get(key)) is not None:
            return hit
        body = await self._get(f"/v1/accounts/{address}/transactions/trc20", params)
        result = parse_history(address, body, self.usdt)
        self.cache.set(key, result)
        return result

    # ------------------------------------------------------------ write side
    async def _post(self, path: str, body: dict) -> dict:
        try:
            resp = await self.client.post(path, json=body)
        except Exception as exc:
            raise ChainError("TRON node is unreachable") from exc
        if resp.status_code == 429:
            raise ChainError("TRON node rate limit reached")
        if resp.status_code >= 400:
            raise ChainError(f"TRON node error {resp.status_code}")
        return resp.json()

    async def now_block(self):
        from .tron_tx import RefBlock
        b = await self._post("/wallet/getnowblock", {})
        raw = b["block_header"]["raw_data"]
        return RefBlock(number=int(raw["number"]), block_id=b["blockID"],
                        timestamp_ms=int(raw["timestamp"]))

    async def broadcast_hex(self, tx_hex: str) -> str:
        r = await self._post("/wallet/broadcasthex", {"transaction": tx_hex})
        if not r.get("result"):
            msg = r.get("message", "")
            try:
                msg = bytes.fromhex(msg).decode("utf-8", "replace")
            except ValueError:
                pass
            raise ChainError(f"broadcast rejected: {r.get('code', '')} {msg}".strip())
        return r.get("txid", "")

    async def chain_params(self) -> tuple[int, int]:
        """(energy burn price, bandwidth burn price) in sun; cached for an hour."""
        hit = self.cache.get(("params",))
        if hit is not None:
            return hit
        r = await self._post("/wallet/getchainparameters", {})
        params = {p.get("key"): int(p.get("value", 0)) for p in r.get("chainParameter", [])}
        value = (params.get("getEnergyFee") or 100, params.get("getTransactionFee") or 1000)
        self.cache._data[("params",)] = (time.monotonic() + 3600, value)
        return value

    async def tx_info(self, txid: str) -> dict:
        """{} until the transaction is in a block."""
        return await self._post("/wallet/gettransactioninfobyid", {"value": txid})

    async def account_resource(self, address: str) -> dict:
        return await self._post("/wallet/getaccountresource", {"address": address, "visible": True})

    async def can_delegate_max(self, address: str, resource: int) -> int:
        r = await self._post("/wallet/getcandelegatedmaxsize",
                             {"owner_address": address, "type": resource, "visible": True})
        return int(r.get("max_size", 0))

    async def account_raw(self, address: str) -> dict:
        """Account record (balance, frozenV2...) — {} if not activated."""
        body = await self._get(f"/v1/accounts/{address}", {"only_confirmed": "true"})
        data = body.get("data") or []
        return data[0] if data else {}

    def forget(self, address: str) -> None:
        """Drop cached account data (after a transfer changed it)."""
        self.cache._data.pop(("acct", address), None)
        self.cache._data.pop(("energy", address), None)

    async def aclose(self) -> None:
        await self.client.aclose()
