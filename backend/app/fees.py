"""Fee quote engine (pure functions, integer math only).

Non-custodial "sponsored resources" model: the user signs, the platform
provides the Energy/Bandwidth, so the user never needs TRX.

Fees shown to the user:
* **Service fee** — the platform's charge (% with min/max).
* **Network resource fee** — recovers what the platform spends on Energy and
  Bandwidth, plus a margin. It is NOT a TRON protocol fee paid in USDT (TRON
  never accepts USDT as gas); the UI must say so.

Three cost-reduction levers (see docs/ARCHITECTURE.md):

1. **Delivery mode** — ``TWO_TRANSFERS`` (recipient transfer + fee transfer,
   no contract) or ``RELAYER`` (one call to the platform's audited relayer
   contract that moves both amounts; one-time ``approve`` = activation).
2. **Energy source** — Energy from the platform's own staked TRX is priced at
   ``stake_energy_cost_sun``; when the stake is exhausted, rented Energy is
   priced at ``energy_price_sun``. The quote uses whichever will actually be
   used, so each transfer always covers its real cost.
3. **GasFree** (third-party protocol) — handled as a separate route in Phase 3;
   its fees are set by the GasFree provider, not by this engine.

Saving: Energy depends on whether the recipient already holds USDT; the quote
checks this live so users are never charged for the expensive case needlessly.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from enum import Enum

from .money import ceil_div

# Measured typical Energy for a USDT TRC20 `transfer`.
ENERGY_TO_HOLDER = 64_285
ENERGY_TO_NEW_HOLDER = 130_285
BANDWIDTH_PER_TRC20_TRANSFER = 345

# RELAYER estimates (two transferFrom in one call). PLACEHOLDERS — must be
# measured on Nile after the contract is written; conservative on purpose.
RELAYER_ENERGY_TO_HOLDER = 100_000
RELAYER_ENERGY_TO_NEW_HOLDER = 166_000
RELAYER_BANDWIDTH = 420
ACTIVATION_ENERGY = 50_000          # one-time USDT approve() for the relayer
ACTIVATION_BANDWIDTH = 315

# Creating a brand-new TRON account (user received USDT but never TRX):
# 1 TRX network account-creation fee + 0.1 TRX we send + bandwidth.
ACCOUNT_CREATION_SUN = 1_200_000

SUN_PER_TRX = 1_000_000
BPS = 10_000
CENT_MICRO = 10_000  # fees are rounded UP to whole cents (0.01 USDT)


class DeliveryMode(str, Enum):
    TWO_TRANSFERS = "two_transfers"
    RELAYER = "relayer"


class EnergySource(str, Enum):
    STAKED = "staked"
    RENTED = "rented"
    OWN_TRX = "own_trx"   # the sender burns their own TRX; platform pays nothing


@dataclass(frozen=True)
class FeeSchedule:
    """Operator-controlled pricing. Stored append-only in PostgreSQL.
    Field order must match repository._SCHEDULE_COLUMNS."""

    service_fee_bps: int            # 50 = 0.50 %
    min_service_fee_micro: int      # floor on the service fee
    max_service_fee_micro: int      # cap on the service fee
    energy_price_sun: int           # RENTED Energy price per unit (market)
    bandwidth_price_sun: int        # per Bandwidth byte (0 if covered by staked TRX)
    trx_price_micro: int            # micro-USDT per 1 TRX (conversion rate)
    resource_margin_bps: int        # markup on resource cost, e.g. 1000 = 10 %
    min_send_micro: int
    max_send_micro: int
    stake_energy_cost_sun: int = 5  # internal cost of OWN staked Energy per unit

    def validate(self) -> None:
        checks = [
            (0 <= self.service_fee_bps <= 500, "service_fee_bps must be 0..500 (max 5%)"),
            (0 <= self.min_service_fee_micro <= self.max_service_fee_micro, "min/max service fee"),
            (0 < self.energy_price_sun <= 1_000, "energy_price_sun must be 1..1000"),
            (0 <= self.stake_energy_cost_sun <= self.energy_price_sun,
             "stake_energy_cost_sun must be 0..energy_price_sun"),
            (0 <= self.bandwidth_price_sun <= 10_000, "bandwidth_price_sun must be 0..10000"),
            (0 < self.trx_price_micro <= 100_000_000, "trx_price_micro out of range"),
            (0 <= self.resource_margin_bps <= 5_000, "resource_margin_bps must be 0..5000"),
            (0 < self.min_send_micro <= self.max_send_micro, "min/max send"),
        ]
        for ok, msg in checks:
            if not ok:
                raise ValueError(msg)


@dataclass(frozen=True)
class FeeQuote:
    amount_micro: int               # total deducted from the sender
    service_fee_micro: int
    resource_fee_micro: int
    total_fee_micro: int
    recipient_micro: int            # what the recipient receives
    energy_units: int
    bandwidth_units: int
    resource_cost_micro: int        # estimated platform cost (internal)
    est_profit_micro: int           # internal; never shown to users
    recipient_holds_usdt: bool
    mode: str
    energy_source: str
    activation_included: bool

    def public_dict(self) -> dict:
        d = asdict(self)
        d.pop("resource_cost_micro")
        d.pop("est_profit_micro")
        return d


class QuoteError(ValueError):
    pass


def round_up_cents(micro: int) -> int:
    return ceil_div(micro, CENT_MICRO) * CENT_MICRO


def service_fee(amount_micro: int, s: FeeSchedule) -> int:
    raw = round_up_cents(ceil_div(amount_micro * s.service_fee_bps, BPS))
    return min(max(raw, s.min_service_fee_micro), s.max_service_fee_micro)


def resource_cost(energy: int, bandwidth: int, s: FeeSchedule,
                  source: EnergySource = EnergySource.RENTED) -> int:
    """Platform's estimated cost in micro-USDT for the given resources."""
    energy_price = s.stake_energy_cost_sun if source == EnergySource.STAKED else s.energy_price_sun
    sun = energy * energy_price + bandwidth * s.bandwidth_price_sun
    return ceil_div(sun * s.trx_price_micro, SUN_PER_TRX)


def resources_needed(recipient_holds_usdt: bool, mode: DeliveryMode,
                     needs_activation: bool = False, collect_fees: bool = True) -> tuple[int, int]:
    """(energy, bandwidth) the platform must provide for one send."""
    if not collect_fees:  # personal mode: one plain transfer, no fee transfer
        main = ENERGY_TO_HOLDER if recipient_holds_usdt else ENERGY_TO_NEW_HOLDER
        return main, BANDWIDTH_PER_TRC20_TRANSFER
    if mode == DeliveryMode.TWO_TRANSFERS:
        main = ENERGY_TO_HOLDER if recipient_holds_usdt else ENERGY_TO_NEW_HOLDER
        return main + ENERGY_TO_HOLDER, 2 * BANDWIDTH_PER_TRC20_TRANSFER
    energy = RELAYER_ENERGY_TO_HOLDER if recipient_holds_usdt else RELAYER_ENERGY_TO_NEW_HOLDER
    bandwidth = RELAYER_BANDWIDTH
    if needs_activation:
        energy += ACTIVATION_ENERGY
        bandwidth += ACTIVATION_BANDWIDTH
    return energy, bandwidth


def quote(amount_micro: int, recipient_holds_usdt: bool, s: FeeSchedule, *,
          mode: DeliveryMode = DeliveryMode.TWO_TRANSFERS,
          source: EnergySource = EnergySource.RENTED,
          needs_activation: bool = False,
          sender_activated: bool = True,
          collect_fees: bool = True) -> FeeQuote:
    """``source`` must reflect where the Energy will really come from (the
    caller checks the platform's free staked Energy first), so the resource
    fee always covers the real cost of this transfer."""
    if amount_micro < s.min_send_micro:
        raise QuoteError("amount is below the minimum transfer amount")
    if amount_micro > s.max_send_micro:
        raise QuoteError("amount is above the maximum transfer amount")

    activation = needs_activation and mode == DeliveryMode.RELAYER and collect_fees
    energy, bandwidth = resources_needed(recipient_holds_usdt, mode, activation, collect_fees)

    if source == EnergySource.OWN_TRX:
        cost = 0
        sender_activated = True  # holding TRX means the account exists
    else:
        cost = resource_cost(energy, bandwidth, s, source)
    if not sender_activated:
        cost += ceil_div(ACCOUNT_CREATION_SUN * s.trx_price_micro, SUN_PER_TRX)
    if collect_fees:
        svc = service_fee(amount_micro, s)
        res = round_up_cents(ceil_div(cost * (BPS + s.resource_margin_bps), BPS)) if cost else 0
    else:  # personal mode: the operator absorbs the cost
        svc = res = 0
    total = svc + res
    recipient = amount_micro - total
    if recipient <= 0:
        raise QuoteError("amount is too small to cover the fees")

    return FeeQuote(
        amount_micro=amount_micro,
        service_fee_micro=svc,
        resource_fee_micro=res,
        total_fee_micro=total,
        recipient_micro=recipient,
        energy_units=energy,
        bandwidth_units=bandwidth,
        resource_cost_micro=cost,
        est_profit_micro=svc + (res - cost),
        recipient_holds_usdt=recipient_holds_usdt,
        mode=mode.value,
        energy_source=source.value,
        activation_included=collect_fees and (activation or not sender_activated),
    )


def network_fee_sun(energy: int, bandwidth: int, energy_fee_sun: int, bandwidth_fee_sun: int) -> int:
    """TRX (sun) the sender burns when paying the network fee themselves, +10 %."""
    return ceil_div((energy * energy_fee_sun + bandwidth * bandwidth_fee_sun) * 11, 10)
