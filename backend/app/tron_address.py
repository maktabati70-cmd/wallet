"""TRON address validation (Base58Check, 0x41 prefix).

A TRON mainnet/testnet address is Base58Check(0x41 || 20-byte account id),
always 34 characters starting with "T". This module performs a full checksum
validation, not just a shape check.
"""
from __future__ import annotations

import hashlib

_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
_INDEX = {c: i for i, c in enumerate(_ALPHABET)}
TRON_PREFIX = 0x41


def _sha256d(data: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def b58encode(data: bytes) -> str:
    n = int.from_bytes(data, "big")
    out = ""
    while n:
        n, r = divmod(n, 58)
        out = _ALPHABET[r] + out
    pad = len(data) - len(data.lstrip(b"\x00"))
    return "1" * pad + out


def b58decode(text: str) -> bytes:
    n = 0
    for ch in text:
        if ch not in _INDEX:
            raise ValueError("invalid base58 character")
        n = n * 58 + _INDEX[ch]
    body = n.to_bytes((n.bit_length() + 7) // 8, "big") if n else b""
    pad = len(text) - len(text.lstrip("1"))
    return b"\x00" * pad + body


def decode_address(address: str) -> bytes:
    """Return the 21-byte raw address (0x41 + 20 bytes) or raise ValueError."""
    if not isinstance(address, str) or len(address) != 34 or not address.startswith("T"):
        raise ValueError("TRON address must be 34 characters and start with T")
    raw = b58decode(address)
    if len(raw) != 25:
        raise ValueError("invalid TRON address length")
    payload, checksum = raw[:21], raw[21:]
    if payload[0] != TRON_PREFIX:
        raise ValueError("invalid TRON address prefix")
    if _sha256d(payload)[:4] != checksum:
        raise ValueError("invalid TRON address checksum")
    return payload


def is_valid_address(address: str) -> bool:
    try:
        decode_address(address)
        return True
    except ValueError:
        return False


def encode_address(payload21: bytes) -> str:
    if len(payload21) != 21 or payload21[0] != TRON_PREFIX:
        raise ValueError("payload must be 21 bytes starting with 0x41")
    return b58encode(payload21 + _sha256d(payload21)[:4])


def address_to_abi_param(address: str) -> str:
    """64-hex-char ABI encoding of an address (used for balanceOf calls)."""
    return decode_address(address)[1:].hex().rjust(64, "0")
