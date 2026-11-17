"""Live smoke test against TRON Nile (run in CI): balanceOf via the same
request the server makes. Usage: python tests/live_nile_check.py [address]"""
import asyncio
import sys

from app.chain import TronGridReader
from app.config import NETWORKS


async def main(address: str) -> None:
    net = NETWORKS["nile"]
    reader = TronGridReader(net["rpc"], net["usdt"])
    try:
        usdt = await reader.usdt_balance(address)
        acct = await reader.get_account(address)
        print(f"{address}: usdt_micro={usdt} activated={acct.activated} trx_sun={acct.trx_sun}")
        r = await reader.account_resource(address)
        lim, w = int(r.get("TotalEnergyLimit", 0)), int(r.get("TotalEnergyWeight", 1))
        print(f"Nile: {lim / max(w, 1):.2f} Energy per staked TRX per day "
              f"(TotalEnergyLimit={lim}, TotalEnergyWeight={w})")
        for extra in sys.argv[2:]:
            raw = await reader.account_raw(extra)
            res = await reader.account_resource(extra)
            print(f"{extra}: balance={int(raw.get('balance', 0)) / 1e6} TRX "
                  f"frozenV2={raw.get('frozenV2')} EnergyLimit={res.get('EnergyLimit', 0)} "
                  f"EnergyUsed={res.get('EnergyUsed', 0)}")
    finally:
        await reader.aclose()


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"))
