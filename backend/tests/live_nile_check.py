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
    finally:
        await reader.aclose()


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"))
