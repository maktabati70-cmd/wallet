"""USDT amount helpers.

All amounts are handled as integers in *micro-USDT* (USDT TRC20 has 6 decimals,
so 1 USDT == 1_000_000 micro). Floats are never used for money.
"""
from __future__ import annotations

import re

USDT_DECIMALS = 6
MICRO = 10**USDT_DECIMALS

_AMOUNT_RE = re.compile(r"^(0|[1-9]\d{0,11})(\.\d{1,6})?$")


def parse_usdt(text: str) -> int:
    """Parse a user-supplied decimal string ("12.5") into micro-USDT.

    Rejects signs, exponents, more than 6 decimals, leading zeros and
    absurdly large numbers. Raises ValueError on invalid input.
    """
    if not isinstance(text, str):
        raise ValueError("amount must be a string")
    text = text.strip()
    m = _AMOUNT_RE.fullmatch(text)
    if not m:
        raise ValueError("invalid amount format")
    whole = int(m.group(1))
    frac = (m.group(2) or ".")[1:].ljust(USDT_DECIMALS, "0")
    return whole * MICRO + int(frac or "0")


def format_usdt(micro: int, min_decimals: int = 2) -> str:
    """Format micro-USDT as a decimal string, trimming trailing zeros."""
    if micro < 0:
        return "-" + format_usdt(-micro, min_decimals)
    whole, frac = divmod(micro, MICRO)
    frac_s = f"{frac:06d}".rstrip("0")
    if len(frac_s) < min_decimals:
        frac_s = frac_s.ljust(min_decimals, "0")
    return f"{whole}.{frac_s}" if frac_s else str(whole)


def ceil_div(a: int, b: int) -> int:
    """Integer ceiling division for non-negative a and positive b."""
    if b <= 0:
        raise ValueError("divisor must be positive")
    return -(-a // b)
