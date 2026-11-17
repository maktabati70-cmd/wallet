# Google Play & legal checklist (draft — not legal advice)

Technical compliance does not guarantee approval. Re-check the official
policies right before submission; they change.

## Policy position

- Google Play's *Cryptocurrency Exchanges and Software Wallets* policy states
  that **non-custodial wallets are out of scope** of its licensing requirements.
  The app must therefore truly be non-custodial: keys only on the device, no
  ability for the operator to move user funds.
- Still complete the **Financial features declaration** in Play Console
  (App content) and describe the app accurately as a non-custodial wallet.
- Charging a fee for facilitating transfers may still be regulated in some
  countries. Get local legal advice for every country you publish in, and
  restrict distribution (Play Console → Countries) accordingly.

## Store listing

- [ ] App name: "TRON" is a third-party trademark. Use your own brand name
      (e.g. "<Brand> Wallet — USDT TRC20") unless you have permission.
- [ ] No TRON/Tether logos without authorization; original icon only.
- [ ] Describe it as a self-custody wallet; list fees; no promises of returns,
      no "guaranteed", "free" (fees exist), or "official" wording.
- [ ] Support email, website, privacy policy URL.

## Data safety (draft answers)

| Data | Collected? | Notes |
|---|---|---|
| Wallet address (financial info – other) | Yes, processed | Sent to our server to read balances/history and to quote fees. Stored in fee quotes (deleted after 24 h if unused) and, from Phase 3, in transfer accounting records. |
| Recovery phrase / private key | **No** | Never leaves the device. |
| Personal info (name, email, phone) | No | No accounts. |
| Device identifiers, location, contacts, SMS, photos | No | Not requested. |
| IP address | Processed transiently | Rate limiting; not stored by the app server. |

Data encrypted in transit: **yes** (HTTPS). Users can request deletion: no
server account exists; local data is deleted with "Remove wallet from this device".

## Account deletion

Google's account-deletion requirement applies to apps that let users create an
account. This app has no server accounts. Explain this in the listing / privacy
policy and keep the in-app "Remove wallet from this device" option.

## Technical

- [ ] Target API level: meet Play's current requirement at submission time.
- [ ] Release signing with Play App Signing; upload key kept outside the repo.
- [ ] Android App Bundle (AAB).
- [ ] Remove the emulator cleartext exception from `network_security_config.xml`.
- [ ] New personal developer accounts must run a closed test (currently 12
      testers for 14 days) before production access; an organization account is
      recommended for a financial app.
- [ ] Age rating questionnaire; not directed at children.

## Before enabling mainnet

- [ ] Legal review for each target country (fees, AML expectations, sanctions).
- [ ] Final privacy policy and terms published.
- [ ] Security audit completed; Phase 3 sending reviewed.
- [ ] Do not claim regulatory approval or licensing unless verified.
