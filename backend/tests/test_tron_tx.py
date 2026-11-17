import pytest

from app import tron_tx
from app.tron_tx import RefBlock

OWNER = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"
TO = "TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC"
USDT = "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf"
REF = RefBlock(number=0x1234ABCD, block_id="00" * 8 + "11223344556677889900aabbccddeeff00112233445566ff",
               timestamp_ms=1_800_000_000_000)


def build():
    return tron_tx.build_trc20_transfer(OWNER, USDT, TO, 96_950_000, REF,
                                        REF.timestamp_ms + 600_000, 1_800_000_000_123, 40_000_000)


def test_roundtrip():
    t = tron_tx.parse_trc20_transfer(build())
    assert (t.owner, t.token, t.to, t.amount) == (OWNER, USDT, TO, 96_950_000)
    assert t.expiration_ms == REF.timestamp_ms + 600_000 and t.fee_limit == 40_000_000


def test_cross_platform_vector():
    """Same bytes are decoded in mobile/test/tron_tx_test.dart."""
    raw = build()
    assert tron_tx.txid(raw) == VECTOR_TXID
    assert raw.hex() == VECTOR_RAW


def test_ref_block_fields():
    assert REF.ref_bytes == bytes.fromhex("abcd")
    assert REF.ref_hash == bytes.fromhex("11223344556677889900aabbccddeeff00112233445566ff")[:8]


def test_rejects_other_contracts():
    trx = tron_tx.build_trx_transfer(OWNER, TO, 1, REF, REF.timestamp_ms + 1, 1)
    with pytest.raises(ValueError):
        tron_tx.parse_trc20_transfer(trx)
    approve = bytearray(build())
    i = approve.find(bytes.fromhex("a9059cbb"))
    approve[i:i + 4] = bytes.fromhex("095ea7b3")  # approve(address,uint256)
    with pytest.raises(ValueError):
        tron_tx.parse_trc20_transfer(bytes(approve))


def test_signed_transaction_wraps_raw_and_signature():
    raw, sig = build(), b"\x01" * 65
    fields = tron_tx.parse_fields(tron_tx.signed_transaction(raw, sig))
    assert fields == [(1, 2, raw), (2, 2, sig)]


VECTOR_RAW = ("0a02abcd2208112233445566778840c0ef95c3b1345aae01081f12a9010a31747970652e676f6f676c6561"
              "7069732e636f6d2f70726f746f636f6c2e54726967676572536d617274436f6e747261637412740a1541"
              "c8599111f29c1e1e061265b4af93ea1f274ad78a121541eca9bc828a3005b9a3b909f2cc5c2a54794de0"
              "5f2244a9059cbb0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf000000"
              "0000000000000000000000000000000000000000000000000005c756f070fba0f1c2b134900180b48913")
VECTOR_TXID = "fc5732905d0068d9d21c34451cd1c028bb286ae8919ffeb7602aee18f03a6655"
