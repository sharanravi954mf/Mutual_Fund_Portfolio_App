# Changelog

All notable completed releases of Sharan Fincorp are documented here. This
changelog follows the spirit of [Keep a Changelog](https://keepachangelog.com/)
and summarizes user-visible and architectural outcomes rather than internal
implementation details.

## [Unreleased]

### Added

### Changed

### Fixed

### Security

## [v0.7.0-alpha]

### Sprint 5.2 – Secure PAN Verification

### Added

- Secure PAN verification workflow for investor account linking
- Encrypted PAN storage and immutable verification evidence
- Canonical PAN reference architecture for business investor records
- Vault-backed PAN encryption and HMAC duplicate detection
- Advisor PAN review with masked PAN information
- Opaque candidate-token approval flow
- Investor PAN verification status experience
- Safe match and conflict categorization

### Changed

- Replaced `profiles.pan` with a canonical PAN reference
- Removed raw PAN from active registrar statement ingestion
- Updated CAMS/KFintech PAN matching to protected HMAC lookup
- Strengthened verification lifecycle handling and source provenance

### Fixed

- Duplicate PAN submission race condition
- PAN exposure risk in parser and operational logging
- Raw PAN persistence in active statement storage
- PAN approval status validation
- Expired candidate-token regression coverage

### Security

- Added dedicated Vault secrets for PAN encryption and lookup
- Prevented browser access to encrypted PAN and HMAC data
- Removed raw PAN from application logging
- Kept PAN masked throughout Flutter experiences
- Added SQL regression validation for token expiry and protected approval flow

## [v0.6.1-alpha]

### Sprint 4 – Identity and Advisor Verification Foundations

### Added

- Advisor verification queue and request-detail workflow
- Authentication and business-identity separation
- Controlled investor-account linking architecture
- Account-state aware onboarding and protected routing
- Opaque candidate tokens for Advisor candidate selection
- Repository-based verification presentation layer

### Changed

- Migrated portfolio ownership to active investor-account links
- Centralized authorization around account state and server-side boundaries
- Improved Advisor navigation for verification review

### Security

- Added secured verification lifecycle workflow
- Introduced optimistic locking and append-only verification history
- Hardened Supabase authorization, Row Level Security, and privileged actions
- Added local Supabase validation for verification workflows

# Versioning

| Stage | Meaning |
|---|---|
| Alpha | Core architecture and workflows are being actively validated. |
| Beta | Feature-complete candidate undergoing broader user and operational testing. |
| Release candidate | Stabilization and release verification only. |
| Stable | Production release supported by operational and recovery processes. |

Current version: **v0.7.0-alpha**.
