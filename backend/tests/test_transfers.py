"""End-to-end send flow with in-memory fakes (no network, no database)."""
import asyncio
import hashlib
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app import crypto, tron_tx
from app.config import Settings
from app.operator import Operator
from app.transfers import TransferError, TransferService

USDT = "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf"
USER_KEY = hashlib.sha256(b"user").digest()
USER = crypto.address_from_private(USER_KEY)
OP_KEY = hashlib.sha256(b"operator").digest()
TREASURY = crypto.address_from_private(hashlib.sha256(b"treasury").digest())
TO = "TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC"


class Repo:
    def __init__(self):
        self.quotes, self.transfers, self.audit = {}, {}, []

    def add_quote(self, **over):
        qid = str(uuid.uuid4())
        self.quotes[qid] = {
            "id": qid, "network": "nile", "status": "quoted",
            "expires_at": datetime.now(timezone.utc) + timedelta(seconds=60),
            "from_address": USER, "to_address": TO, "recipient_micro": 96_000_000,
            "service_fee_micro": 500_000, "resource_fee_micro": 3_500_000,
            "energy_units": 128_570, **over}
        return qid

    def get_quote(self, qid):
        return self.quotes.get(qid)

    def transfer_for_quote(self, qid):
        return next((t for t in self.transfers.values() if t["quote_id"] == qid), None)

    def get_transfer(self, tid):
        return self.transfers.get(tid)

    def create_transfer(self, **f):
        tid = str(uuid.uuid4())
        self.transfers[tid] = {"id": tid, "status": "prepared", "step": "prepared",
                               "idempotency_key": None, "failure_reason": None,
                               "main_signature": None, "fee_signature": None, **f}
        return self.transfers[tid]

    def claim_transfer(self, tid, key, msig, fsig):
        t = self.transfers[tid]
        if t["status"] != "prepared":
            return False
        t.update(status="processing", idempotency_key=key, main_signature=msig, fee_signature=fsig)
        self.quotes[t["quote_id"]]["status"] = "used"
        return True

    def update_transfer(self, tid, **f):
        self.transfers[tid].update(f)

    def add_audit(self, *a):
        self.audit.append(a)


class Chain:
    def __init__(self, fail_main=False, activated=False):
        self.broadcasts, self.fail_main, self.activated = [], fail_main, activated
        self.balance = 200_000_000

    async def now_block(self):
        return tron_tx.RefBlock(1000, "00" * 32, int(datetime.now().timestamp() * 1000))

    async def usdt_balance(self, a):
        return self.balance

    def forget(self, a):
        pass

    async def account_raw(self, a):
        return {"balance": 1} if (self.activated or a != USER) else {}

    async def account_resource(self, a):
        return {"TotalEnergyLimit": 180_000_000_000, "TotalEnergyWeight": 18_000_000_000,
                "TotalNetLimit": 43_200_000_000, "TotalNetWeight": 26_000_000_000}

    async def can_delegate_max(self, a, r):
        return 10**15

    async def broadcast_hex(self, h):
        raw = tron_tx.parse_fields(bytes.fromhex(h))[0][2]
        self.broadcasts.append(raw)
        if self.activated is False and len(self.broadcasts) == 1:
            self.activated = True  # first broadcast was the activation
        return tron_tx.txid(raw)

    async def tx_info(self, txid):
        if self.fail_main and self.broadcasts and tron_tx.txid(self.broadcasts[-1]) == txid:
            try:
                t = tron_tx.parse_trc20_transfer(self.broadcasts[-1])
                if t.to == TO:
                    return {"blockNumber": 1, "receipt": {"result": "OUT_OF_ENERGY"}}
            except ValueError:
                pass
        return {"blockNumber": 1, "receipt": {"result": "SUCCESS", "energy_usage_total": 64_285}}


def setup(**chain_kw):
    settings = Settings(usdt_contract=USDT, sending_enabled=True, treasury_address=TREASURY,
                        operator_private_key=OP_KEY.hex())
    repo, chain = Repo(), Chain(**chain_kw)
    return TransferService(settings, repo, chain, Operator(chain, OP_KEY)), repo, chain


def sign(tx):
    return crypto.sign_digest(USER_KEY, bytes.fromhex(tx["txid"])).hex()


def run(coro):
    return asyncio.get_event_loop_policy().new_event_loop().run_until_complete(coro)


def test_full_flow_fee_first_then_recipient():
    svc, repo, chain = setup()
    prep = run(svc.prepare(repo.add_quote()))
    main, fee = prep["transactions"]
    # transactions decode to exactly what the quote says
    m = tron_tx.parse_trc20_transfer(bytes.fromhex(main["raw_data_hex"]))
    f = tron_tx.parse_trc20_transfer(bytes.fromhex(fee["raw_data_hex"]))
    assert (m.owner, m.token, m.to, m.amount) == (USER, USDT, TO, 96_000_000)
    assert (f.to, f.amount) == (TREASURY, 4_000_000)

    view, start = run(svc.submit(prep["transfer_id"], "k" * 20, sign(main), sign(fee)))
    assert start and view["status"] == "processing"
    run(svc.process(prep["transfer_id"]))
    t = repo.transfers[prep["transfer_id"]]
    assert t["status"] == "confirmed" and t["activation_sent"] and t["resources_reclaimed"]

    user_txs = [r for r in chain.broadcasts if r in (bytes.fromhex(main["raw_data_hex"]),
                                                     bytes.fromhex(fee["raw_data_hex"]))]
    assert user_txs == [bytes.fromhex(fee["raw_data_hex"]), bytes.fromhex(main["raw_data_hex"])]


def test_wrong_signer_rejected():
    svc, repo, _ = setup()
    prep = run(svc.prepare(repo.add_quote()))
    main, fee = prep["transactions"]
    bad = crypto.sign_digest(OP_KEY, bytes.fromhex(main["txid"])).hex()
    with pytest.raises(TransferError) as e:
        run(svc.submit(prep["transfer_id"], "k" * 20, bad, sign(fee)))
    assert e.value.status == 422


def test_idempotent_retry_and_no_double_submit():
    svc, repo, _ = setup()
    prep = run(svc.prepare(repo.add_quote()))
    main, fee = prep["transactions"]
    _, start1 = run(svc.submit(prep["transfer_id"], "k" * 20, sign(main), sign(fee)))
    _, start2 = run(svc.submit(prep["transfer_id"], "k" * 20, sign(main), sign(fee)))
    assert start1 and not start2
    with pytest.raises(TransferError) as e:
        run(svc.submit(prep["transfer_id"], "z" * 20, sign(main), sign(fee)))
    assert e.value.status == 409


def test_expired_quote_and_used_quote():
    svc, repo, _ = setup()
    old = repo.add_quote(expires_at=datetime.now(timezone.utc) - timedelta(seconds=1))
    with pytest.raises(TransferError) as e:
        run(svc.prepare(old))
    assert e.value.status == 410


def test_insufficient_balance_at_submit():
    svc, repo, chain = setup()
    prep = run(svc.prepare(repo.add_quote()))
    main, fee = prep["transactions"]
    chain.balance = 1
    with pytest.raises(TransferError) as e:
        run(svc.submit(prep["transfer_id"], "k" * 20, sign(main), sign(fee)))
    assert e.value.status == 422


def test_recipient_failure_marks_refund_needed():
    svc, repo, _ = setup(fail_main=True, activated=True)
    prep = run(svc.prepare(repo.add_quote()))
    main, fee = prep["transactions"]
    run(svc.submit(prep["transfer_id"], "k" * 20, sign(main), sign(fee)))
    run(svc.process(prep["transfer_id"]))
    assert repo.transfers[prep["transfer_id"]]["status"] == "refund_needed"


def test_disabled_when_not_configured():
    svc = TransferService(Settings(usdt_contract=USDT), Repo(), Chain(), None)
    with pytest.raises(TransferError) as e:
        run(svc.prepare(str(uuid.uuid4())))
    assert e.value.status == 503


def test_personal_mode_single_transfer():
    settings = Settings(usdt_contract=USDT, sending_enabled=True, collect_fees=False,
                        operator_private_key=OP_KEY.hex())
    settings.validate()
    repo, chain = Repo(), Chain(activated=True)
    svc = TransferService(settings, repo, chain, Operator(chain, OP_KEY))
    qid = repo.add_quote(recipient_micro=100_000_000, service_fee_micro=0, resource_fee_micro=0,
                         energy_units=64_285)
    prep = run(svc.prepare(qid))
    assert [t["purpose"] for t in prep["transactions"]] == ["recipient"]
    main = prep["transactions"][0]
    with pytest.raises(TransferError):  # a fee signature is not expected
        run(svc.submit(prep["transfer_id"], "k" * 20, sign(main), sign(main)))
    _, start = run(svc.submit(prep["transfer_id"], "k" * 20, sign(main), None))
    assert start
    run(svc.process(prep["transfer_id"]))
    t = repo.transfers[prep["transfer_id"]]
    assert t["status"] == "confirmed" and t["bandwidth_delegated_sun"] == 0
    user_txs = [r for r in chain.broadcasts if r == bytes.fromhex(main["raw_data_hex"])]
    assert len(user_txs) == 1
