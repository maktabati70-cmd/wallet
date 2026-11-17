"""API tests with in-memory fakes (no database or network needed)."""
from datetime import datetime, timedelta, timezone

import pytest

pytest.importorskip("fastapi")
pytest.importorskip("httpx")
from fastapi.testclient import TestClient  # noqa: E402

from app.chain import AccountInfo  # noqa: E402
from app.config import Settings  # noqa: E402
from app.main import create_app  # noqa: E402
from tests.test_fees import S  # noqa: E402

ME = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"
OTHER = "TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC"
USDT = "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf"


class FakeRepo:
    def __init__(self):
        self.quotes, self.audit = [], []

    def ping(self):
        return True

    def active_fee_schedule(self):
        return 1, S

    def save_quote(self, **kw):
        self.quotes.append(kw)
        return "00000000-0000-0000-0000-000000000001", datetime.now(timezone.utc) + timedelta(seconds=60)

    def add_audit(self, *a):
        self.audit.append(a)


class FakeChain:
    def __init__(self):
        self.accounts = {ME: AccountInfo(ME, True, 0, 500_000_000),
                         OTHER: AccountInfo(OTHER, True, 0, 1)}

    async def get_account(self, address):
        return self.accounts.get(address, AccountInfo(address, False, 0, 0))

    async def free_energy(self, address):
        return 10_000_000

    async def usdt_history(self, address, limit, fingerprint):
        return [], None


@pytest.fixture()
def client():
    settings = Settings(usdt_contract=USDT, rate_limit_per_minute=1000)
    repo = FakeRepo()
    app = create_app(settings, repo=repo, chain=FakeChain())
    with TestClient(app) as c:
        c.repo = repo
        yield c


def test_health_and_headers(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["sending_enabled"] is False
    assert r.headers["x-content-type-options"] == "nosniff"


def test_config(client):
    body = client.get("/v1/config").json()
    assert body["is_testnet"] and body["fees"]["service_fee_percent"] == "0.50"


def test_quote_happy_path(client):
    r = client.post("/v1/quotes", json={"from_address": ME, "to_address": OTHER, "amount": "100"})
    assert r.status_code == 200, r.text
    b = r.json()
    assert b["service_fee"] == "0.50" and b["sending_enabled"] is False
    assert len(client.repo.quotes) == 1


@pytest.mark.parametrize("payload,code", [
    ({"from_address": ME, "to_address": ME, "amount": "10"}, 422),
    ({"from_address": ME, "to_address": USDT, "amount": "10"}, 422),
    ({"from_address": ME, "to_address": OTHER, "amount": "100000"}, 422),
    ({"from_address": ME, "to_address": OTHER, "amount": "1e3"}, 422),
    ({"from_address": ME, "to_address": OTHER, "amount": "10", "x": 1}, 422),
])
def test_quote_rejections(client, payload, code):
    assert client.post("/v1/quotes", json=payload).status_code == code


def test_balance(client):
    r = client.post("/v1/wallet/balance", json={"address": ME})
    assert r.json()["usdt"] == "500.00"


def test_rate_limit():
    app = create_app(Settings(usdt_contract=USDT, rate_limit_per_minute=3),
                     repo=FakeRepo(), chain=FakeChain())
    with TestClient(app) as c:
        codes = [c.get("/health").status_code for _ in range(5)]
    assert codes[:3] == [200] * 3 and codes[-1] == 429


def test_quote_uses_staked_energy_when_available():
    settings = Settings(usdt_contract=USDT, rate_limit_per_minute=1000,
                        energy_account="TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC")
    app = create_app(settings, repo=FakeRepo(), chain=FakeChain())
    with TestClient(app) as c:
        body = c.post("/v1/quotes", json={"from_address": ME, "to_address": OTHER,
                                          "amount": "100"}).json()
    assert body["energy_source"] == "staked"
