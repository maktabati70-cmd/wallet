"""secp256k1 / Keccak-256 / BIP39-BIP32 primitives in pure Python.

Used by the server only for the platform's OWN operator wallet (Energy
delegation, account activation) and by tests. User keys never reach the
server. Signatures are deterministic (RFC 6979) with low-s normalisation, the
format TRON expects: r (32) || s (32) || v (1, 27 + recovery id).
"""
from __future__ import annotations

import hashlib
import hmac

from .tron_address import encode_address

# ----------------------------------------------------------------- Keccak-256
_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
        [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
_M64 = (1 << 64) - 1


def _rol(x: int, n: int) -> int:
    return ((x << n) | (x >> (64 - n))) & _M64 if n else x


def _keccak_f(a):
    for rc in _RC:
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
        a = [[a[x][y] ^ d[x] for y in range(5)] for x in range(5)]
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rol(a[x][y], _ROT[x][y])
        a = [[b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y]) for y in range(5)]
             for x in range(5)]
        a[0][0] ^= rc
    return a


def keccak256(data: bytes) -> bytes:
    rate = 136
    p = bytearray(data) + b"\x01"
    while len(p) % rate:
        p += b"\x00"
    p[-1] |= 0x80
    a = [[0] * 5 for _ in range(5)]
    for i in range(0, len(p), rate):
        block = p[i:i + rate]
        for j in range(rate // 8):
            a[j % 5][j // 5] ^= int.from_bytes(block[8 * j:8 * j + 8], "little")
        a = _keccak_f(a)
    return b"".join(a[j % 5][j // 5].to_bytes(8, "little") for j in range(4))


# ----------------------------------------------------------------- secp256k1
P = 2**256 - 2**32 - 977
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)


def _add(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if a[0] == b[0] and (a[1] + b[1]) % P == 0:
        return None
    if a == b:
        lam = 3 * a[0] * a[0] * pow(2 * a[1], -1, P) % P
    else:
        lam = (b[1] - a[1]) * pow(b[0] - a[0], -1, P) % P
    x = (lam * lam - a[0] - b[0]) % P
    return x, (lam * (a[0] - x) - a[1]) % P


def _mul(k: int, point=G):
    result = None
    while k:
        if k & 1:
            result = _add(result, point)
        point = _add(point, point)
        k >>= 1
    return result


def public_key(priv: bytes) -> tuple[int, int]:
    d = int.from_bytes(priv, "big")
    if not 0 < d < N:
        raise ValueError("invalid private key")
    return _mul(d)


def address_from_public(pub: tuple[int, int]) -> str:
    raw = pub[0].to_bytes(32, "big") + pub[1].to_bytes(32, "big")
    return encode_address(b"\x41" + keccak256(raw)[-20:])


def address_from_private(priv: bytes) -> str:
    return address_from_public(public_key(priv))


def _rfc6979_k(d: int, h: bytes) -> int:
    x = d.to_bytes(32, "big")
    h1 = (int.from_bytes(h, "big") % N).to_bytes(32, "big")
    v, k = b"\x01" * 32, b"\x00" * 32
    k = hmac.new(k, v + b"\x00" + x + h1, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    k = hmac.new(k, v + b"\x01" + x + h1, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    while True:
        v = hmac.new(k, v, hashlib.sha256).digest()
        cand = int.from_bytes(v, "big")
        if 1 <= cand < N:
            return cand
        k = hmac.new(k, v + b"\x00", hashlib.sha256).digest()
        v = hmac.new(k, v, hashlib.sha256).digest()


def _lift_x(x: int, odd: int):
    y2 = (pow(x, 3, P) + 7) % P
    y = pow(y2, (P + 1) // 4, P)
    if y * y % P != y2:
        return None
    if y & 1 != odd:
        y = P - y
    return x, y


def recover_public(digest: bytes, r: int, s: int, rec_id: int):
    if not (0 < r < N and 0 < s < N) or rec_id not in (0, 1):
        return None
    big_r = _lift_x(r, rec_id)
    if big_r is None:
        return None
    e = int.from_bytes(digest, "big") % N
    r_inv = pow(r, -1, N)
    sr = _mul(s, big_r)
    eg = _mul((-e) % N)
    return _mul(r_inv, _add(sr, eg))


def sign_digest(priv: bytes, digest: bytes) -> bytes:
    """65-byte TRON signature of a 32-byte digest (e.g. a transaction id)."""
    if len(digest) != 32:
        raise ValueError("digest must be 32 bytes")
    d = int.from_bytes(priv, "big")
    pub = public_key(priv)
    k = _rfc6979_k(d, digest)
    big_r = _mul(k)
    r = big_r[0] % N
    s = pow(k, -1, N) * (int.from_bytes(digest, "big") + r * d) % N
    if s > N // 2:
        s = N - s
    for rec_id in (0, 1):
        if recover_public(digest, r, s, rec_id) == pub:
            return r.to_bytes(32, "big") + s.to_bytes(32, "big") + bytes([27 + rec_id])
    raise RuntimeError("could not compute recovery id")


def signer_address(digest: bytes, signature: bytes) -> str | None:
    """Address that produced `signature` over `digest`, or None if invalid."""
    if len(signature) != 65:
        return None
    r = int.from_bytes(signature[:32], "big")
    s = int.from_bytes(signature[32:64], "big")
    v = signature[64]
    rec_id = v - 27 if v >= 27 else v
    if s > N // 2:  # enforce low-s (non-malleable)
        return None
    pub = recover_public(digest, r, s, rec_id)
    return address_from_public(pub) if pub else None


# ----------------------------------------------------------------- BIP39/BIP32
TRON_PATH = (44 + 2**31, 195 + 2**31, 2**31, 0)


def _ser_compressed(pt) -> bytes:
    return bytes([2 + (pt[1] & 1)]) + pt[0].to_bytes(32, "big")


def private_key_from_mnemonic(mnemonic: str, index: int = 0) -> bytes:
    """BIP39 seed (no passphrase) -> BIP32 m/44'/195'/0'/0/index."""
    words = " ".join(mnemonic.strip().lower().split())
    seed = hashlib.pbkdf2_hmac("sha512", words.encode(), b"mnemonic", 2048)
    i = hmac.new(b"Bitcoin seed", seed, hashlib.sha512).digest()
    k, chain = int.from_bytes(i[:32], "big"), i[32:]
    for idx in (*TRON_PATH, index):
        if idx >= 2**31:
            data = b"\x00" + k.to_bytes(32, "big") + idx.to_bytes(4, "big")
        else:
            data = _ser_compressed(_mul(k)) + idx.to_bytes(4, "big")
        i = hmac.new(chain, data, hashlib.sha512).digest()
        k, chain = (int.from_bytes(i[:32], "big") + k) % N, i[32:]
    return k.to_bytes(32, "big")
