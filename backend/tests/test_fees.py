import pytest

from app import fees
from app.fees import FeeSchedule, QuoteError, quote

S = FeeSchedule(
    service_fee_bps=50, min_service_fee_micro=100_000, max_service_fee_micro=10_000_000,
    energy_price_sun=60, bandwidth_price_sun=0, trx_price_micro=300_000,
    resource_margin_bps=1000, min_send_micro=1_000_000, max_send_micro=10_000_000_000,
    stake_energy_cost_sun=5,
)
MARKET = FeeSchedule(**{**S.__dict__, "energy_price_sun": 45, "trx_price_micro": 330_000})


def test_spec_example_service_fee():
    # Spec: 100 USDT at 0.5% -> service fee 0.50
    assert fees.service_fee(100_000_000, S) == 500_000


def test_min_and_max_service_fee():
    assert fees.service_fee(2_000_000, S) == 100_000          # 0.01 -> floor 0.10
    assert fees.service_fee(5_000_000_000, S) == 10_000_000   # 25 -> cap 10


def test_quote_sums_and_never_loses_money():
    for holds in (True, False):
        q = quote(100_000_000, holds, S)
        assert q.amount_micro == q.recipient_micro + q.service_fee_micro + q.resource_fee_micro
        assert q.resource_fee_micro >= q.resource_cost_micro
        assert q.est_profit_micro >= q.service_fee_micro


def test_recipient_without_usdt_costs_more_energy():
    cheap, dear = quote(100_000_000, True, S), quote(100_000_000, False, S)
    assert cheap.energy_units == fees.ENERGY_TO_HOLDER * 2
    assert dear.energy_units == fees.ENERGY_TO_NEW_HOLDER + fees.ENERGY_TO_HOLDER
    assert dear.resource_fee_micro > cheap.resource_fee_micro


def test_fees_are_whole_cents():
    q = quote(123_450_000, False, S)
    assert q.service_fee_micro % 10_000 == 0 and q.resource_fee_micro % 10_000 == 0
    assert q.service_fee_micro == 620_000  # 0.5% of 123.45 = 0.61725 -> 0.62


def test_resource_cost_math():
    # 128,570 Energy * 60 sun = 7,714,200 sun = 7.7142 TRX * 0.30 = 2.31426 USDT
    assert fees.resource_cost(128_570, 0, S) == 2_314_260


def test_limits_and_too_small():
    with pytest.raises(QuoteError):
        quote(999_999, True, S)
    with pytest.raises(QuoteError):
        quote(10_000_000_001, True, S)
    tiny = FeeSchedule(**{**S.__dict__, "min_send_micro": 1})
    with pytest.raises(QuoteError):
        quote(1_000, True, tiny)


def test_public_dict_hides_internal_numbers():
    d = quote(100_000_000, True, S).public_dict()
    assert "resource_cost_micro" not in d and "est_profit_micro" not in d


def test_schedule_validation():
    S.validate()
    with pytest.raises(ValueError):
        FeeSchedule(**{**S.__dict__, "service_fee_bps": 9999}).validate()
    with pytest.raises(ValueError):
        FeeSchedule(**{**S.__dict__, "min_service_fee_micro": 20_000_000}).validate()


def test_staked_energy_is_cheaper_and_still_profitable():
    rented = quote(100_000_000, True, MARKET, source=fees.EnergySource.RENTED)
    staked = quote(100_000_000, True, MARKET, source=fees.EnergySource.STAKED)
    assert staked.resource_fee_micro < rented.resource_fee_micro
    for q in (rented, staked):
        assert q.resource_fee_micro >= q.resource_cost_micro


def test_relayer_uses_less_energy_and_activation_charged_once():
    two = quote(100_000_000, True, MARKET, mode=fees.DeliveryMode.TWO_TRANSFERS)
    rel = quote(100_000_000, True, MARKET, mode=fees.DeliveryMode.RELAYER)
    first = quote(100_000_000, True, MARKET, mode=fees.DeliveryMode.RELAYER, needs_activation=True)
    assert rel.energy_units < two.energy_units
    assert first.activation_included and first.energy_units == rel.energy_units + fees.ACTIVATION_ENERGY
    # activation flag is ignored for the two-transfer mode
    assert not quote(100_000_000, True, MARKET, needs_activation=True).activation_included


def test_stake_cost_cannot_exceed_rent():
    with pytest.raises(ValueError):
        FeeSchedule(**{**S.__dict__, "stake_energy_cost_sun": 61}).validate()


def test_new_sender_account_pays_activation_once():
    normal = quote(100_000_000, True, MARKET)
    new = quote(100_000_000, True, MARKET, sender_activated=False)
    assert new.activation_included and not normal.activation_included
    assert new.resource_fee_micro > normal.resource_fee_micro
    assert new.resource_fee_micro >= new.resource_cost_micro


def test_personal_mode_charges_nothing_and_needs_half_the_energy():
    q = quote(100_000_000, True, MARKET, collect_fees=False)
    assert q.total_fee_micro == 0 and q.recipient_micro == 100_000_000
    assert q.energy_units == fees.ENERGY_TO_HOLDER
    assert not q.activation_included
