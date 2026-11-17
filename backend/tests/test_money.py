import pytest

from app.money import ceil_div, format_usdt, parse_usdt


@pytest.mark.parametrize("text,micro", [
    ("0", 0), ("1", 1_000_000), ("100.5", 100_500_000), ("0.000001", 1),
    ("99.50", 99_500_000), (" 12.345678 ", 12_345_678),
])
def test_parse_valid(text, micro):
    assert parse_usdt(text) == micro


@pytest.mark.parametrize("text", [
    "", "-1", "+1", "1e5", "1.0000001", "01", ".5", "5.", "1,5", "abc",
    "NaN", "inf", "1 000", "9999999999999",
])
def test_parse_invalid(text):
    with pytest.raises(ValueError):
        parse_usdt(text)


def test_format():
    assert format_usdt(99_500_000) == "99.50"
    assert format_usdt(1) == "0.000001"
    assert format_usdt(100_000_000) == "100.00"
    assert format_usdt(2_314_260) == "2.31426"
    assert format_usdt(-500_000) == "-0.50"


def test_ceil_div():
    assert ceil_div(10, 3) == 4
    assert ceil_div(9, 3) == 3
    assert ceil_div(0, 7) == 0


def test_admin_percent_parsing():
    import argparse

    import pytest as _pytest

    from app.admin_cli import _percent_to_bps
    assert _percent_to_bps("0.5") == 50
    assert _percent_to_bps("10") == 1000
    with _pytest.raises(argparse.ArgumentTypeError):
        _percent_to_bps("0.123")
