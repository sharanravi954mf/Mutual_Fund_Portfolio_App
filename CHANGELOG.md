# Changelog

All notable completed releases of Sharan Fincorp are documented here. This changelog follows the spirit of [Keep a Changelog](https://keepachangelog.com/).

Detailed release notes and boundaries are maintained inside the [docs/changelog/](docs/changelog/README.md) directory.

---

## [v1.1.0-alpha] — 2026-07-19

### Summary
Release v1.1.0 introduces significant upgrades to the Admin Dashboard (Invoice Signer tab, in-memory batch ZIP processing), Client Dashboard features (Autocomplete search, factsheets, live wallpapers, time-of-day greetings), and registrar statement ingestion (decryption & auto-linking).

### Major Additions & Changes
- **Invoice Signer upgrades**: Standalone tab inside the Admin Dashboard supporting single PDFs and zipped archives. In-memory batch decryption, signing, and re-zipping.
- **Material 3 Dusty Rose Gold migration**: Migrated design seed color to `Color(0xFFC9B4BC)` across sidebar navigation drawer, metrics, cards, and tables.
- **Client Search & Factsheets**: Autocomplete mutual fund search on dashboard with modal factsheets.
- **Ingestion Pipeline Upgrades**: Deno engine parses password-protected ZIPs containing dBASE III `.dbf` statements. Standalone CAMs staging table imports, unregistered client ingestion, and auto-linking triggers.
- **Live Money Wallpaper**: Animated falling rupee symbols (`₹`) and golden wealth curves under Display settings.
- **Deduplicated greetings**: Unified time-of-day greetings on the main header appbar.

### Detailed Release Logs
- [v1.1.0 In-Memory ZIP Ingestion Spec](docs/changelog/v1.1.0_invoice_signer.md)
- [CAMS Signer Boundary Notes](docs/changelog/cams_invoice_signer_boundary.md)
- [Material 3 Theme Redesign Notes](docs/changelog/theme-redesign.md)

---

## [v0.7.0-alpha] — 2026-07-22

### Summary
Sprint 5.2 – Secure PAN Verification for client account linking.

### Major Additions & Changes
- **PAN Verification Workflow**: Masked PAN lookups and Vault-backed encryption at rest.
- **Opaque Candidate-Tokens**: Token-bound approval mechanisms preventing UUID leak.
- **Immutable Request Evidence**: Safe conflict categorizations and audit records.

---

## [v0.6.1-alpha] — 2026-07-22

### Summary
Sprint 4 – Onboarding and Identity Foundations.

### Major Additions & Changes
- **Separated Identities**: Isolated Supabase Auth credentials from business profile records.
- **Advisor verification queues**: Verification assignment structures.
- **Row Level Security (RLS)**: Enforced client select filters based on active investor links.
