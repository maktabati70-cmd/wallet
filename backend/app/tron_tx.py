"""Minimal TRON transaction encoding/decoding (protobuf, canonical field order).

Transactions are built locally (not by the node) so the exact bytes that
users sign are fully under our control and can be re-verified on the phone.
txID = sha256(raw_data). Fields are emitted in ascending field number and
default (zero) values are omitted, exactly as protobuf re-serialises them.

Message layouts (java-tron protocol):
  Transaction      { raw raw_data = 1; repeated bytes signature = 2; }
  Transaction.raw  { bytes ref_block_bytes = 1; bytes ref_block_hash = 4;
                     int64 expiration = 8; repeated Contract contract = 11;
                     int64 timestamp = 14; int64 fee_limit = 18; }
  Contract         { ContractType type = 1; google.protobuf.Any parameter = 2; }
  Any              { string type_url = 1; bytes value = 2; }
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass

from .tron_address import decode_address, encode_address

# ContractType values and type URLs
TRANSFER = 1
TRIGGER_SMART_CONTRACT = 31
FREEZE_BALANCE_V2 = 54
DELEGATE_RESOURCE = 57
UNDELEGATE_RESOURCE = 58
TYPE_URLS = {
    TRANSFER: "type.googleapis.com/protocol.TransferContract",
    TRIGGER_SMART_CONTRACT: "type.googleapis.com/protocol.TriggerSmartContract",
    FREEZE_BALANCE_V2: "type.googleapis.com/protocol.FreezeBalanceV2Contract",
    DELEGATE_RESOURCE: "type.googleapis.com/protocol.DelegateResourceContract",
    UNDELEGATE_RESOURCE: "type.googleapis.com/protocol.UnDelegateResourceContract",
}
BANDWIDTH, ENERGY = 0, 1
TRC20_TRANSFER_SELECTOR = bytes.fromhex("a9059cbb")  # transfer(address,uint256)


# ----------------------------------------------------------------- encoding
def _varint(n: int) -> bytes:
    if n < 0:
        n &= (1 << 64) - 1  # int64 two's complement
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def _key(field: int, wire: int) -> bytes:
    return _varint((field << 3) | wire)


def _int(field: int, value: int) -> bytes:
    return _key(field, 0) + _varint(value) if value else b""


def _bytes(field: int, value: bytes) -> bytes:
    return _key(field, 2) + _varint(len(value)) + value if value else b""


@dataclass(frozen=True)
class RefBlock:
    number: int
    block_id: str      # 64 hex chars
    timestamp_ms: int

    @property
    def ref_bytes(self) -> bytes:
        return self.number.to_bytes(8, "big")[6:8]

    @property
    def ref_hash(self) -> bytes:
        return bytes.fromhex(self.block_id)[8:16]


def _raw(contract_type: int, value: bytes, ref: RefBlock, expiration_ms: int,
         timestamp_ms: int, fee_limit: int = 0) -> bytes:
    any_msg = _bytes(1, TYPE_URLS[contract_type].encode()) + _bytes(2, value)
    contract = _int(1, contract_type) + _bytes(2, any_msg)
    return (_bytes(1, ref.ref_bytes) + _bytes(4, ref.ref_hash) + _int(8, expiration_ms)
            + _bytes(11, contract) + _int(14, timestamp_ms) + _int(18, fee_limit))


def trc20_transfer_data(to: str, amount: int) -> bytes:
    return (TRC20_TRANSFER_SELECTOR + decode_address(to)[1:].rjust(32, b"\x00")
            + amount.to_bytes(32, "big"))


def build_trc20_transfer(owner: str, token: str, to: str, amount: int, ref: RefBlock,
                         expiration_ms: int, timestamp_ms: int, fee_limit: int) -> bytes:
    value = (_bytes(1, decode_address(owner)) + _bytes(2, decode_address(token))
             + _bytes(4, trc20_transfer_data(to, amount)))
    return _raw(TRIGGER_SMART_CONTRACT, value, ref, expiration_ms, timestamp_ms, fee_limit)


def build_trx_transfer(owner: str, to: str, amount_sun: int, ref: RefBlock,
                       expiration_ms: int, timestamp_ms: int) -> bytes:
    value = _bytes(1, decode_address(owner)) + _bytes(2, decode_address(to)) + _int(3, amount_sun)
    return _raw(TRANSFER, value, ref, expiration_ms, timestamp_ms)


def build_freeze_v2(owner: str, amount_sun: int, resource: int, ref: RefBlock,
                    expiration_ms: int, timestamp_ms: int) -> bytes:
    value = _bytes(1, decode_address(owner)) + _int(2, amount_sun) + _int(3, resource)
    return _raw(FREEZE_BALANCE_V2, value, ref, expiration_ms, timestamp_ms)


def build_delegate(owner: str, receiver: str, resource: int, balance_sun: int, ref: RefBlock,
                   expiration_ms: int, timestamp_ms: int, undelegate: bool = False) -> bytes:
    value = (_bytes(1, decode_address(owner)) + _int(2, resource) + _int(3, balance_sun)
             + _bytes(4, decode_address(receiver)))
    ctype = UNDELEGATE_RESOURCE if undelegate else DELEGATE_RESOURCE
    return _raw(ctype, value, ref, expiration_ms, timestamp_ms)


def txid(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def signed_transaction(raw: bytes, signature: bytes) -> bytes:
    return _bytes(1, raw) + _bytes(2, signature)


# ----------------------------------------------------------------- decoding
def _read_varint(buf: bytes, i: int) -> tuple[int, int]:
    shift = result = 0
    while True:
        if i >= len(buf) or shift > 63:
            raise ValueError("bad varint")
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, i
        shift += 7


def parse_fields(buf: bytes) -> list[tuple[int, int, object]]:
    """[(field, wire_type, value)]; value is int (wire 0) or bytes (wire 2)."""
    out, i = [], 0
    while i < len(buf):
        key, i = _read_varint(buf, i)
        field, wire = key >> 3, key & 7
        if wire == 0:
            value, i = _read_varint(buf, i)
        elif wire == 2:
            length, i = _read_varint(buf, i)
            if i + length > len(buf):
                raise ValueError("truncated field")
            value, i = buf[i:i + length], i + length
        else:
            raise ValueError(f"unsupported wire type {wire}")
        out.append((field, wire, value))
    return out


@dataclass(frozen=True)
class Trc20Transfer:
    owner: str
    token: str
    to: str
    amount: int
    expiration_ms: int
    timestamp_ms: int
    fee_limit: int


def parse_trc20_transfer(raw: bytes) -> Trc20Transfer:
    """Strictly decode a raw transaction that must be a single TRC20 transfer()."""
    fields = parse_fields(raw)
    contracts = [v for f, w, v in fields if f == 11]
    if len(contracts) != 1:
        raise ValueError("expected exactly one contract")
    known = {1, 4, 8, 11, 14, 18}
    if any(f not in known for f, _, _ in fields):
        raise ValueError("unexpected transaction field")
    top = {f: v for f, _, v in fields}
    c = {f: v for f, _, v in parse_fields(contracts[0])}
    if c.get(1) != TRIGGER_SMART_CONTRACT or set(c) - {1, 2}:
        raise ValueError("not a smart-contract call")
    any_msg = {f: v for f, _, v in parse_fields(c[2])}
    if any_msg.get(1) != TYPE_URLS[TRIGGER_SMART_CONTRACT].encode():
        raise ValueError("wrong type url")
    t = {f: v for f, _, v in parse_fields(any_msg[2])}
    if set(t) - {1, 2, 4}:
        raise ValueError("call_value / token value not allowed")
    data = t.get(4, b"")
    if len(data) != 68 or data[:4] != TRC20_TRANSFER_SELECTOR or data[4:16] != b"\x00" * 12:
        raise ValueError("not a TRC20 transfer(address,uint256)")
    return Trc20Transfer(
        owner=encode_address(t[1]),
        token=encode_address(t[2]),
        to=encode_address(b"\x41" + data[16:36]),
        amount=int.from_bytes(data[36:68], "big"),
        expiration_ms=int(top.get(8, 0)),
        timestamp_ms=int(top.get(14, 0)),
        fee_limit=int(top.get(18, 0)),
    )
