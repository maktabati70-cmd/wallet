# TRON Wallet — non-custodial USDT (TRC20) wallet for Android

> **Status: Phase 1 (development, TRON Nile testnet).** Sending is disabled.
> Do not use with real funds. Mainnet is blocked by the backend configuration.

A simple self-custody wallet for USDT on TRON:

- **Flutter** Android app (English only, left-to-right).
- **Python FastAPI** backend + **PostgreSQL**.
- **Non-custodial:** keys are generated and stored only on the user's phone
  (Android Keystore). The server never receives a private key or recovery phrase.
- **Business model:** a service fee (default 0.5 %, min/max configurable) plus a
  network resource fee that recovers the Energy/Bandwidth the platform provides,
  so users never need to hold TRX.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and fee model,
[docs/SECURITY.md](docs/SECURITY.md) and
[docs/GOOGLE_PLAY_COMPLIANCE.md](docs/GOOGLE_PLAY_COMPLIANCE.md).

## Repository layout

```
backend/
  app/
    main.py          FastAPI app (config, balance, history, fee quotes)
    fees.py          fee quote engine (integer micro-USDT math)
    chain.py         read-only TronGrid client (filters fake USDT tokens)
    tron_address.py  Base58Check address validation
    repository.py    PostgreSQL access (psycopg 3)
    security.py      rate limiting, security headers
    admin_cli.py     operator CLI: fees, audit log (no public admin panel)
    migrate.py       applies SQL migrations
  migrations/        001_init.sql (schema), 002_app_role.sql (least-privilege role)
  tests/             pytest suite + independent key-derivation vector script
mobile/
  lib/core/          wallet crypto, secure storage, PIN, API client
  lib/screens/       all app screens
  lib/widgets/       shared widgets (PIN pad, address view, …)
  android/           manifest (minimal permissions, no backup, HTTPS only), MainActivity (FLAG_SECURE)
  test/              unit tests (address, key derivation vector, money, PBKDF2)
docs/
docker-compose.yml   local PostgreSQL for development
```

## Run the backend

Requirements: Python 3.11+, Docker (or a local PostgreSQL 14+).

```bash
docker compose up -d db                 # local PostgreSQL on 127.0.0.1:5432

cd backend
python -m venv .venv
source .venv/bin/activate               # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
cp .env.example .env                    # then edit DATABASE_URL:
# DATABASE_URL=postgresql://wallet_owner:dev_only_change_me@localhost:5432/tron_wallet

python -m app.migrate                   # creates tables + default fee schedule
python -m app.admin_cli show-fees
python -m app.admin_cli simulate --amount 100
# schedule daily on the server (cron): python -m app.admin_cli purge-quotes

uvicorn app.main:create_app --factory --reload --host 0.0.0.0 --port 8000
```

API docs (development only): http://127.0.0.1:8000/docs

Set real prices before testing quotes (the defaults are placeholders):

```bash
python -m app.admin_cli set-fees --actor "your name" --note "market prices" \
  --energy-price-sun 60 --trx-price 0.30
```

Tests:

```bash
cd backend && pytest -q
python tests/derive_vector.py           # independent check of the mobile test vector
```

## Run the Android app

Requirements: Flutter 3.27+ (Dart 3.6+), Android Studio / Android SDK.

```bash
cd mobile
# Generates the missing Android project files; existing files are kept.
flutter create . --platforms=android --org com.alshami --project-name tron_wallet
```

Then open `android/app/build.gradle(.kts)` and set `minSdk = 23`
(required by `flutter_secure_storage` and `local_auth`).

```bash
flutter pub get
flutter analyze
flutter test
# Emulator → backend on your PC (10.0.2.2 = host machine):
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
# Real phone on the same Wi-Fi: use https or add your PC's IP to
# android/app/src/main/res/xml/network_security_config.xml (dev only).
```

Get test USDT/TRX on Nile from the official Nile faucet (nileex.io).

## Phase plan

| Phase | Scope | Status |
|---|---|---|
| 1 | App + backend foundation, wallet create/import, PIN/biometric lock, balance, receive, history, fee quotes, DB schema | **this commit** |
| 2 | Testnet integration hardening: verified balances/history, pending tx tracking, monitoring | next |
| 3 | Sending: local signing, Energy/Bandwidth sponsorship, fee transfer, idempotent submission | |
| 4 | Security testing, penetration test, Play Integrity, reconciliation | |
| 5 | Google Play preparation (AAB, signing, Data safety, listing) | |

Do not proceed to Phase 2 until Phase 1 has been reviewed.
