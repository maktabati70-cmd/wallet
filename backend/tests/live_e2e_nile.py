"""LIVE end-to-end send on TRON Nile testnet (run by CI; needs DATABASE_URL).

Needs a PRIVATE testnet phrase in the env var NILE_E2E_MNEMONIC (GitHub
secret) whose index 0 holds Nile test TRX and test USDT. (Public test phrases
cannot be used: their accounts get hijacked by permission changes.)
  index 0 = sender, 1 = operator, 2 = treasury, 3 = recipient (fresh account)
Skips (exit 0) when the secret is not set.

    PYTHONPATH=. python tests/live_e2e_nile.py
"""
from __future__ import annotations

import asyncio
import os
import sys
import time

from fastapi.testclient import TestClient

from app import crypto, tron_tx
from app.chain import TronGridReader
from app.config import NETWORKS, Settings
from app.main import create_app
from app.operator import Operator

PHRASE = os.environ.get("NILE_E2E_MNEMONIC", "").strip()
if not PHRASE:
    print("NILE_E2E_MNEMONIC not set — skipping live end-to-end test")
    sys.exit(0)
KEYS = [crypto.private_key_from_mnemonic(PHRASE, i) for i in range(4)]
SENDER, OPERATOR, TREASURY, RECIPIENT = (crypto.address_from_private(k) for k in KEYS)
NET = NETWORKS["nile"]


async def fund_operator() -> None:
    chain = TronGridReader(NET["rpc"], NET["usdt"])
    try:
        op_acct = await chain.account_raw(OPERATOR)
        staked = sum(int(f.get("amount", 0)) for f in op_acct.get("frozenV2", []))
        liquid = int(op_acct.get("balance", 0))
        print(f"operator {OPERATOR}: liquid={liquid / 1e6} TRX staked={staked / 1e6} TRX")
        if staked + liquid < 300_000_000:
            funder = Operator(chain, KEYS[0])
            tid = await funder._send(lambda ref, exp, ts: tron_tx.build_trx_transfer(
                SENDER, OPERATOR, 400_000_000, ref, exp, ts))
            await funder.wait(tid)
            print("funded operator with 400 TRX:", tid)
        result = await Operator(chain, KEYS[1]).auto_stake()
        print("auto-stake:", result)
    finally:
        await chain.aclose()


def main() -> int:
    asyncio.run(fund_operator())
    settings = Settings(
        database_url=os.environ["DATABASE_URL"], tron_network="nile",
        tron_rpc_url=NET["rpc"], usdt_contract=NET["usdt"],
        treasury_address=TREASURY, sending_enabled=True,
        operator_private_key=KEYS[1].hex(), auto_stake=False, rate_limit_per_minute=1000,
    )
    settings.validate()
    with TestClient(create_app(settings)) as c:
        print("health:", c.get("/health").json())
        q = c.post("/v1/quotes", json={"from_address": SENDER, "to_address": RECIPIENT, "amount": "5"})
        assert q.status_code == 200, q.text
        quote = q.json()
        print("quote:", {k: quote[k] for k in ("service_fee", "resource_fee", "recipient_receives",
                                                 "energy_source", "activation_fee_included")})
        p = c.post("/v1/transfers/prepare", json={"quote_id": quote["quote_id"]})
        assert p.status_code == 200, p.text
        prep = p.json()
        sigs = {}
        for tx in prep["transactions"]:
            parsed = tron_tx.parse_trc20_transfer(bytes.fromhex(tx["raw_data_hex"]))
            assert parsed.owner == SENDER and parsed.to == tx["to"] and parsed.amount == tx["amount_micro"]
            sigs[tx["purpose"]] = crypto.sign_digest(KEYS[0], bytes.fromhex(tx["txid"])).hex()
        start = time.time()
        s = c.post("/v1/transfers/submit", json={
            "transfer_id": prep["transfer_id"], "idempotency_key": f"ci-{int(start)}-e2e-test",
            "recipient_signature": sigs["recipient"], "fee_signature": sigs["fee"]})
        assert s.status_code == 202, s.text
        status = c.get(f"/v1/transfers/{prep['transfer_id']}").json()
        print(f"result after {time.time() - start:.0f}s:", status)
        if status["status"] != "confirmed":
            return 1
        print("recipient tx:", status["main_explorer_url"])
        print("fee tx:      ", status["fee_explorer_url"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
