"""API request models. Amounts travel as decimal strings, never floats."""
from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .money import parse_usdt
from .tron_address import is_valid_address


def _check_address(v: str) -> str:
    if not is_valid_address(v):
        raise ValueError("invalid TRON address")
    return v


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class AddressRequest(_Strict):
    address: str = Field(min_length=34, max_length=34)

    @field_validator("address")
    @classmethod
    def _valid_address(cls, v: str) -> str:
        return _check_address(v)


class HistoryRequest(AddressRequest):
    limit: int = Field(default=20, ge=1, le=50)
    fingerprint: str | None = Field(default=None, max_length=200)


class QuoteRequest(_Strict):
    from_address: str = Field(min_length=34, max_length=34)
    to_address: str = Field(min_length=34, max_length=34)
    amount: str = Field(min_length=1, max_length=20, description='Decimal string, e.g. "100.5"')

    @field_validator("from_address", "to_address")
    @classmethod
    def _valid_addresses(cls, v: str) -> str:
        return _check_address(v)

    @field_validator("amount")
    @classmethod
    def _valid_amount(cls, v: str) -> str:
        if parse_usdt(v) <= 0:
            raise ValueError("amount must be greater than zero")
        return v


class PrepareRequest(_Strict):
    quote_id: str = Field(pattern=r"^[0-9a-fA-F-]{36}$")


class SubmitRequest(_Strict):
    transfer_id: str = Field(pattern=r"^[0-9a-fA-F-]{36}$")
    idempotency_key: str = Field(min_length=16, max_length=100, pattern=r"^[A-Za-z0-9_-]+$")
    recipient_signature: str = Field(pattern=r"^[0-9a-fA-F]{130}$")
    fee_signature: str | None = Field(default=None, pattern=r"^[0-9a-fA-F]{130}$")
