# 12 — Security Architecture

## Purpose
This document defines the core security principles, authentication mechanisms, Row Level Security (RLS) rules, Vault setups, PII masking rules, threat models, and compliance policies for Sharan Fincorp.

## Scope
Covers database-level table protection, data-at-rest encryption pipelines, network transit parameters, API token verifications, and audit logging boundaries.

## Responsibilities
- **Security Lead**: Configures RLS policies, audits database roles, monitors security events, and manages Vault keys.
- **Developer**: Ensures code changes do not expose internal IDs or bypass RLS constraints.

## Architecture Overview

Sharan Fincorp implements a "Zero Trust" model at the database boundary. All client-facing read/write actions must satisfy strict RLS policies.

```mermaid
flowchart TD
  User["Authenticated User (Client)"] -- Request over TLS 1.3 --> Kong["Kong API Gateway"]
  Kong -- Validate Token --> Auth["Supabase Auth (JWT)"]
  Kong -- Forward Query --> Db[(Postgres Database)]
  
  subgraph Db[(Postgres Database)]
    RLS{Row Level Security} -- Restrict Row Access --> Tables[(Operational Tables)]
    Funcs["SECURITY DEFINER Functions"] -- Encrypt / Decrypt --> Vault[(pg_vault Store)]
  end
```

---

## Detailed Design

### Security Principles
1. **Least Privilege**: public browser endpoints have no direct read or write access to sensitive database tables (e.g. `profile_pan_records`, `verification_pan_evidence`).
2. **Defensive API Design**: Browser clients receive masked display projections. Internal database IDs (UUIDs) and raw PAN numbers are never exposed.

### Authentication & Token Verification
- **JWT Provider**: GoTrue service handles user verification and token issuance.
- **Client Session**: Clients present short-lived JWT tokens on every HTTP call. Postgres verifies the signature and decodes the payload parameters (`auth.uid()`).

### Row Level Security (RLS)
Operational tables have RLS enabled. Read policies assert owner/identity linkages:
- **Portfolios / Transactions**: A select policy validates that an active relationship exists in `investor_account_links` and an approved grant exists in `folio_grants` for the specific folio.
- **Direct Update Prevention**: Client roles cannot perform updates on state parameters, roles, or links.

### Vault Cryptography & PAN Protection
PAN verification isolates encrypted business files from request evidence records:
- **Vault Secrets**: `pan_encryption_key` (AES-256) encrypts PAN values at rest. `pan_lookup_hmac_key` (SHA-256) compiles hash tokens to perform query matches.
- **Lookup Process**: The database matches PAN inputs by hashing the request value and comparing it with the pre-compiled lookup HMAC index. Decryption is never performed for standard searches.

### Threat Model & Trust Boundaries
- **Untrusted Zone**: Browser runtimes, mobile viewports, and public CDN distributions.
- **Trusted Zone**: Supabase container runtimes, database engines, and secure Vault extension buffers.
- **Bypass Protections**: Opaque candidate tokens expire in 5 minutes to prevent replay attacks during advisor folio claim verifications.

---

## Dependencies
- **Postgres pgcrypto / pg_vault**: Crypto extensions.
- **Supabase Auth JWT signatures**: Authentication provider.

## Design Decisions
- **No Raw PAN in Logs**: Verification modules catch and scrub PAN values from log streams before writing console records.
- **No Client-Side Authorization**: Flutter UI roles customize user views for layout convenience, but the database RLS holds the ultimate authorization authority.

## Future Evolution
- **SOC 2 Type II Compliance Readiness**: Configuring automated log aggregators and vulnerability scanners to verify codebases on regular schedules.

## References
- [Target Architecture Contract](README.md)
- [ADR-003 — Protect PAN as Encrypted Business Evidence](../decisions/ADR-003-PAN-Verification.md)
- [ADR-006 — Folio-Scoped Portfolio Access Authorization](../decisions/ADR-006-Folio-Access-Authorization.md)
