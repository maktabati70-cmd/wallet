# Security

## Implemented in Phase 1

**Mobile app**
- Keys generated on-device (BIP39, secure RNG); the server never receives the
  phrase or private key. Key bytes are zeroed after address derivation.
- Recovery phrase stored with `flutter_secure_storage` (Android Keystore-backed
  encryption). `allowBackup=false` and data-extraction rules exclude all app data
  from cloud backup and device transfer.
- 6-digit PIN: PBKDF2-HMAC-SHA256, 100,000 iterations, random 16-byte salt,
  constant-time comparison, trivial PINs rejected, lockout after 5 failures with
  growing delays (30 s → 1 h).
- Optional biometric unlock; PIN re-entry required to view the phrase, change
  the PIN, enable biometrics, or remove the wallet.
- Auto-lock when the app returns from background (immediately / 1 / 5 min).
- `FLAG_SECURE`: no screenshots, screen recording or recent-apps preview.
- Phrase is never copied to the clipboard; import uses an incognito keyboard.
- Full Base58Check address validation; warnings for own address, the USDT
  contract address, never-used recipients, and **address-poisoning look-alikes**
  (same first/last characters as an address in your history).
- HTTPS only (cleartext allowed only for the emulator host in development).
- Minimal permissions: `INTERNET`, `USE_BIOMETRIC`.

**Backend**
- No secrets in code; settings from environment. Mainnet refuses to start unless
  `ALLOW_MAINNET=true`; `SENDING_ENABLED=true` is rejected in Phase 1.
- Strict request validation (unknown fields rejected, decimal-string amounts,
  checksum-validated addresses), 8 KB body limit.
- Per-IP rate limiting (stricter for quotes); `X-Forwarded-For` trusted only
  behind a configured proxy.
- Security headers, HSTS in production, API docs disabled in production.
- Look-alike tokens filtered: only the configured USDT contract with 6 decimals counts.
- Integer micro-USDT math everywhere; no floats.
- Append-only, hash-chained audit log; append-only fee history; least-privilege DB role.
- No public admin panel — pricing is changed via a server-side CLI.

## Remaining (before any real funds)

1. **Phase 3 signing design review**: transaction built and verified on the
   device (recipient, amount, contract, fee transfer) before signing; never sign
   server-provided bytes blindly.
2. Idempotent submission (one quote → one transfer), replay protection,
   Energy delegation limits per address/day, abuse controls for free Energy.
3. Play Integrity API / app attestation to reduce bot abuse of sponsored Energy.
4. Certificate pinning for the API domain.
5. Root/emulator detection (warning, not blocking).
6. Consider an additional PIN-derived encryption layer for the phrase.
7. Sanctions screening of recipient addresses (e.g. a blocklist provider).
8. Independent security audit and penetration test; dependency scanning.
9. Production ops: TLS termination, WAF, Redis-backed rate limits, backups,
   monitoring/alerting, incident response plan, secret manager.
