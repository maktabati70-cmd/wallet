# Architecture

## Why non-custodial

The original specification described a custodial wallet. The owner chose a
**non-custodial** design instead because:

- Google Play's *Cryptocurrency Exchanges and Software Wallets* policy requires
  jurisdiction-specific licences (e.g. FinCEN, FCA, MiCA) for **custodial**
  wallets; its help page states that non-custodial wallets are out of scope.
- The operator never holds customer funds, so a server breach cannot drain
  user balances, and there is no customer-funds ledger to reconcile.
- Much less infrastructure: no deposit addresses, sweeping, hot/cold wallets.

How the original requirements map to this design:

| Original (custodial) requirement | Non-custodial equivalent |
|---|---|
| Registration, email verification, login | Create / import wallet on the device; no server account |
| Secure password storage | 6-digit PIN, PBKDF2-SHA256 (100k iterations, random salt), lockout with growing delays |
| MFA | PIN + optional biometrics; PIN re-entry for sensitive actions |
| Account recovery | 12-word BIP39 recovery phrase (verified during setup) |
| Unique deposit address per user | The user's own address (BIP44 m/44'/195'/0'/0/0, TronLink-compatible) |
| Credit deposits after confirmations | Balance read directly from the chain (confirmed data only) |
| Double-entry ledger for balances | Not needed — the blockchain is the balance. The DB keeps fee quotes, sponsored-transfer accounting and an audit log |
| Private keys in KMS/HSM | Keys never leave the phone (Android Keystore-encrypted storage) |
| Account deletion | No account exists; "Remove wallet from this device" wipes all local data |

## Components

```
Flutter app (device)                         Backend (FastAPI)               TRON
────────────────────                         ─────────────────               ────
BIP39 phrase + key  ──(never sent)──X
PIN / biometric lock
Read balance/history  ── POST /v1/wallet/* ──►  TronGrid reader  ── HTTPS ──►  TronGrid
Fee quote             ── POST /v1/quotes ────►  fee engine + PostgreSQL
(Phase 3) sign tx locally ─► submit ───────►  delegate Energy, broadcast
```

Addresses are sent in POST bodies (not URLs) so they don't appear in access logs.

## Fee model (profit and cost control)

Each send in Phase 3 consists of two USDT transfers signed by the user:

1. `recipient_amount` → recipient
2. `service_fee + resource_fee` → platform treasury (one transfer)

The platform provides the Energy/Bandwidth for both, so the user needs no TRX.

- **Service fee** — `amount × service %`, rounded up to the cent, clamped to
  `[min, max]` (defaults 0.5 %, min 0.10, max 10 USDT).
- **Network resource fee** — `(Energy × energy price + Bandwidth × bandwidth price)`
  converted at the configured TRX price, plus margin (default 10 %), rounded up
  to the cent. **It is not a TRON fee paid in USDT**; the UI says so explicitly.
- **Live recipient check (saving):** a transfer to an address that already holds
  USDT needs ~64,285 Energy, to an empty one ~130,285. The quote checks this, so
  users are never overcharged.
- **Never lose money on a transfer:** resource fee ≥ estimated cost, always
  (unit-tested).
- **Quotes expire** (60 s) and are stored; Phase 3 will accept each quote once,
  preventing duplicate submissions.

## Cost levers (all three are built into the fee engine)

| Lever | What it does | Status |
|---|---|---|
| 1. Relayer contract (`DELIVERY_MODE=relayer`) | One contract call moves both the recipient amount and the fee (two `transferFrom`), instead of two separate transfers. One-time `approve` = activation, charged once. | Engine + DB ready. Contract to be written, measured on Nile and **audited** in Phase 3. Energy figures are conservative placeholders until measured. |
| 2. Own staked TRX (`ENERGY_ACCOUNT`) | If the platform's staked account has enough free Energy, the quote is priced at the internal staked cost (default 5 sun) instead of the rental price. Otherwise rented Energy is priced. Every quote still covers its real cost. | Implemented (reads free Energy via TronGrid). |
| 3. GasFree route | TRON's GasFree protocol: the user signs a TIP-712 permit and a GasFree service provider pays the gas, charging its fee in USDT. | Researched; Phase 3. Needs an API key + secret from the GasFree Developers Center. Each user gets a separate GasFree address (deposits must go there), and the fee goes to the provider, so it is a fallback route unless you become a provider or get a revenue share. |

Sending 100 USDT at market prices (rented Energy 45 sun, 1 TRX = 0.33 USDT, 10 % margin),
from `admin_cli simulate`:

| Mode | Energy | Recipient | Service | Resource | Total fees | Our profit |
|---|---|---|---|---|---|---|
| two transfers | rented | holder | 0.50 | 2.11 | 2.61 | 0.70 |
| relayer | rented | holder | 0.50 | 1.64 | 2.14 | 0.66 |
| two transfers | **staked** | holder | 0.50 | 0.24 | **0.74** | 0.53 |
| relayer | **staked** | holder | 0.50 | 0.19 | **0.69** | 0.53 |

GasFree-based wallets charge about 1–1.5 USDT per transfer. **Staked Energy is the lever
that makes the app cheaper than competitors; the relayer saves ~20 % more.**

Capital needed for staking (≈ 9.74 Energy per staked TRX per day, Nov 2026; varies with
total network stake): ~13,200 TRX per daily transfer with two transfers, ~10,300 TRX
with the relayer. Example: 10 transfers/day ≈ 103,000–132,000 TRX. Staked TRX is not
spent (14-day unstaking period) and keeps earning voting rewards; rented Energy covers peaks.

Suggested rollout: start with rented Energy (higher price, no capital), stake TRX as
volume grows, deploy the relayer after its audit, keep GasFree as a fallback route.

All prices are operator-configurable with `python -m app.admin_cli set-fees`
(append-only, audit-logged). Use `simulate` to compare all routes.

## Database (PostgreSQL)

- `fee_schedules` — append-only pricing history; newest row is active.
- `fee_quotes` — short-lived quotes; DB checks enforce
  `amount = recipient + service + resource`.
- `sponsored_transfers` — Phase 3 accounting (fees collected vs. resources spent,
  unique quote id / idempotency key / txids).
- `audit_log` — append-only and SHA-256 hash-chained; UPDATE/DELETE/TRUNCATE are
  rejected by triggers; `admin_cli verify-audit` re-checks the chain.
- `daily_revenue` view.
- `002_app_role.sql` — the API runs as `wallet_api`, which cannot change pricing
  or rewrite history.
