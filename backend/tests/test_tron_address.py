from app.tron_address import (address_to_abi_param, b58decode, b58encode, decode_address,
                              encode_address, is_valid_address)

# BIP44 m/44'/195'/0'/0/0 of "abandon ×11 about" (well-known TRON test vector)
VECTOR = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"
VECTOR_HEX = "41c8599111f29c1e1e061265b4af93ea1f274ad78a"
USDT_MAINNET = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"


def test_valid_addresses():
    for a in (VECTOR, USDT_MAINNET, "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf"):
        assert is_valid_address(a)


def test_decode_matches_hex():
    assert decode_address(VECTOR).hex() == VECTOR_HEX
    assert encode_address(bytes.fromhex(VECTOR_HEX)) == VECTOR


def test_rejects_bad_checksum_and_shapes():
    bad = [
        VECTOR[:-1] + ("I" if VECTOR[-1] != "I" else "J"),  # invalid char
        VECTOR[:-1] + ("e" if VECTOR[-1] != "e" else "f"),  # checksum
        VECTOR[1:],                                          # too short
        "0x" + VECTOR_HEX,                                   # hex form
        "1BoatSLRHtKNngkdXEeobR76b53LETtpyT",                # bitcoin address
        "",
    ]
    for a in bad:
        assert not is_valid_address(a), a


def test_b58_roundtrip_with_leading_zeros():
    data = b"\x00\x00\x01\x02"
    assert b58decode(b58encode(data)) == data


def test_abi_param():
    p = address_to_abi_param(VECTOR)
    assert len(p) == 64 and p.endswith(VECTOR_HEX[2:])
