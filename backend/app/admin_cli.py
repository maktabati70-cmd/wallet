"""Operator CLI — run on the server only (needs the DB owner credentials).

There is intentionally no admin web panel exposed to the internet in Phase 1.
Every change is written to the append-only, hash-chained audit log.

Examples:
    python -m app.admin_cli show-fees
    python -m app.admin_cli set-fees --actor "Abu Abdullah" --note "new energy price" \
        --service-percent 0.5 --min-service 0.10 --max-service 10 \
        --energy-price-sun 60 --trx-price 0.30 --margin-percent 10 \
        --min-send 1 --max-send 10000
    python -m app.admin_cli simulate --amount 100
    python -m app.admin_cli audit-log --limit 20
    python -m app.admin_cli verify-audit
    python -m app.admin_cli purge-quotes
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import asdict, replace

from . import fees
from .config import load_settings
from .money import format_usdt, parse_usdt


def _percent_to_bps(text: str) -> int:
    # "0.5" -> 50 bps; parsed as a 6-decimal amount to avoid floats
    micro = parse_usdt(text)
    if micro % 10_000:
        raise argparse.ArgumentTypeError("use at most 2 decimals for percentages")
    return micro // 10_000


def _print_schedule(sid: int, s: fees.FeeSchedule) -> None:
    print(f"Active fee schedule #{sid}")
    print(f"  service fee        : {s.service_fee_bps / 100:.2f}%  "
          f"(min {format_usdt(s.min_service_fee_micro)}, max {format_usdt(s.max_service_fee_micro)} USDT)")
    print(f"  rented energy      : {s.energy_price_sun} sun/Energy")
    print(f"  own staked energy  : {s.stake_energy_cost_sun} sun/Energy (internal cost)")
    print(f"  bandwidth price    : {s.bandwidth_price_sun} sun/byte")
    print(f"  TRX price          : {format_usdt(s.trx_price_micro, 4)} USDT")
    print(f"  resource margin    : {s.resource_margin_bps / 100:.2f}%")
    print(f"  send limits        : {format_usdt(s.min_send_micro)} .. {format_usdt(s.max_send_micro)} USDT")


def _simulate(s: fees.FeeSchedule, amount_micro: int) -> None:
    print(f"\n  Sending {format_usdt(amount_micro)} USDT")
    print(f"  {'mode':<14}{'energy':<8}{'recipient':<10}{'service':>9}{'resource':>10}"
          f"{'gets':>12}{'our cost':>10}{'profit':>10}")
    for mode in fees.DeliveryMode:
        for source in fees.EnergySource:
            for holds in (True, False):
                q = fees.quote(amount_micro, holds, s, mode=mode, source=source)
                cents = lambda m: f"{m / 1_000_000:.2f}"  # noqa: E731 (display only)
                print(f"  {mode.value:<14}{source.value:<8}{'holder' if holds else 'new':<10}"
                      f"{format_usdt(q.service_fee_micro):>9}{format_usdt(q.resource_fee_micro):>10}"
                      f"{format_usdt(q.recipient_micro):>12}{cents(q.resource_cost_micro):>10}"
                      f"{cents(q.est_profit_micro):>10}")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="admin_cli")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("show-fees")

    sf = sub.add_parser("set-fees", help="create a new fee schedule (unspecified values are kept)")
    sf.add_argument("--actor", required=True)
    sf.add_argument("--note", required=True)
    sf.add_argument("--service-percent", type=_percent_to_bps)
    sf.add_argument("--min-service", type=parse_usdt)
    sf.add_argument("--max-service", type=parse_usdt)
    sf.add_argument("--energy-price-sun", type=int, help="rented Energy price")
    sf.add_argument("--stake-energy-cost-sun", type=int, help="internal cost of own staked Energy")
    sf.add_argument("--bandwidth-price-sun", type=int)
    sf.add_argument("--trx-price", type=parse_usdt, help="USDT per 1 TRX, e.g. 0.30")
    sf.add_argument("--margin-percent", type=_percent_to_bps)
    sf.add_argument("--min-send", type=parse_usdt)
    sf.add_argument("--max-send", type=parse_usdt)

    sm = sub.add_parser("simulate")
    sm.add_argument("--amount", type=parse_usdt, required=True)

    al = sub.add_parser("audit-log")
    al.add_argument("--limit", type=int, default=20)
    sub.add_parser("verify-audit")
    pq = sub.add_parser("purge-quotes")
    pq.add_argument("--older-than-hours", type=int, default=24)

    args = p.parse_args(argv)
    settings = load_settings()
    from .repository import PostgresRepository
    repo = PostgresRepository(settings.database_url)

    if args.cmd == "show-fees":
        _print_schedule(*repo.active_fee_schedule())
    elif args.cmd == "simulate":
        _, s = repo.active_fee_schedule()
        _simulate(s, args.amount)
    elif args.cmd == "set-fees":
        _, current = repo.active_fee_schedule()
        changes = {k: v for k, v in {
            "service_fee_bps": args.service_percent,
            "min_service_fee_micro": args.min_service,
            "max_service_fee_micro": args.max_service,
            "energy_price_sun": args.energy_price_sun,
            "stake_energy_cost_sun": args.stake_energy_cost_sun,
            "bandwidth_price_sun": args.bandwidth_price_sun,
            "trx_price_micro": args.trx_price,
            "resource_margin_bps": args.margin_percent,
            "min_send_micro": args.min_send,
            "max_send_micro": args.max_send,
        }.items() if v is not None}
        if not changes:
            print("Nothing to change.")
            return 1
        new = replace(current, **changes)
        new.validate()
        print("Changes:", {k: (asdict(current)[k], v) for k, v in changes.items()})
        if input("Type YES to apply: ").strip() != "YES":
            print("Cancelled.")
            return 1
        sid = repo.insert_fee_schedule(new, actor=args.actor, note=args.note)
        _print_schedule(sid, new)
    elif args.cmd == "audit-log":
        for row in repo.list_audit(args.limit):
            print(*row, sep=" | ")
    elif args.cmd == "verify-audit":
        bad = repo.verify_audit_chain()
        if bad:
            print("AUDIT CHAIN BROKEN at ids:", bad)
            return 2
        print("Audit chain OK")
    elif args.cmd == "purge-quotes":
        print("Deleted", repo.purge_stale_quotes(args.older_than_hours), "stale quotes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
