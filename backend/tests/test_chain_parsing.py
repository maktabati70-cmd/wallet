import pytest

from app.chain import ChainError, parse_account, parse_balance_of, parse_free_energy, parse_history

USDT = "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf"
ME = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"
OTHER = "TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC"
FAKE = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"


def test_inactive_account():
    a = parse_account(ME, {"data": [], "success": True}, USDT)
    assert not a.activated and a.usdt_micro == 0


def test_account_balances():
    a = parse_account(ME, {"data": [{"balance": 5_000_000,
                                     "trc20": [{FAKE: "999"}, {USDT: "12500000"}]}]}, USDT)
    assert a.activated and a.trx_sun == 5_000_000 and a.usdt_micro == 12_500_000


def _tx(token, frm, to, value="1000000", decimals=6, typ="Transfer"):
    return {"transaction_id": "ab" * 32, "block_timestamp": 1, "from": frm, "to": to,
            "value": value, "type": typ, "token_info": {"address": token, "decimals": decimals}}


def test_history_filters_fake_tokens_and_sets_direction():
    payload = {"data": [
        _tx(USDT, OTHER, ME),
        _tx(USDT, ME, OTHER, "2500000"),
        _tx(FAKE, OTHER, ME),                 # look-alike token: dropped
        _tx(USDT, OTHER, ME, decimals=18),    # wrong decimals: dropped
        _tx(USDT, OTHER, ME, typ="Approval"), # not a transfer: dropped
    ], "meta": {"fingerprint": "next123"}}
    items, nxt = parse_history(ME, payload, USDT)
    assert [i.direction for i in items] == ["in", "out"]
    assert items[1].amount_micro == 2_500_000
    assert nxt == "next123"


def test_free_energy():
    assert parse_free_energy({"EnergyLimit": 200_000, "EnergyUsed": 50_000}) == 150_000
    assert parse_free_energy({}) == 0
    assert parse_free_energy({"EnergyLimit": 10, "EnergyUsed": 20}) == 0


def test_balance_of():
    ok = {"result": {"result": True},
          "constant_result": ["000000000000000000000000000000000000000000000000000000003b9aca00"]}
    assert parse_balance_of(ok) == 1_000_000_000  # 1000 USDT
    zero = {"result": {"result": True}, "constant_result": ["0" * 64]}
    assert parse_balance_of(zero) == 0
    for bad in ({}, {"result": {"result": False}}, {"result": {"result": True}, "constant_result": []}):
        with pytest.raises(ChainError):
            parse_balance_of(bad)
