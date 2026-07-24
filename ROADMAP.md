# Sharan Fincorp — Product Roadmap

**Current release:** `v1.1.0-alpha`  
**Current maturity:** Alpha  

---

## 1. Project Vision
Sharan Fincorp is a secure, Advisor-managed Mutual Fund Portfolio Management platform. Its long-term direction is to give Advisors a trusted operating system for investor identity, portfolio ownership, reconciliation, reporting, and operational automation—while giving Investors a safe, clear view of their own verified investments.

The platform grows through deliberate security and operational foundations, not by adding features ahead of the controls needed to support them.

---

## 2. Release History & Timeline

| Version | Status | Major Features | Notes |
|---|---|---|---|
| `v0.6.1-alpha` | Released | Onboarding & identity links foundation | Separated Supabase Auth from business profiles. |
| `v0.7.0-alpha` | Released | PAN verification, Vault encryption, opaque tokens | Initial security and authorization baseline. |
| `v1.0.0-alpha` | Released | Autocomplete search, factsheets, live wallpapers | Client-side visual and interaction upgrades. |
| `v1.1.0-alpha` | Released | Batch PDF/ZIP Invoice Signer, DBF parser, auto-linking | In-memory decompression, dBASE III reader, auto-onboard. |
| `v1.2.0-beta` | Planned | Advisor Folio Verification presentation & workflow | Sprint 5.6B target scope. |
| `v2.0.0` | Planned | Production Launch | Subject to full validation and security audits. |

---

## 3. Major Milestones

### Completed Milestones

#### ✓ In-Memory Batch ZIP Invoice Signer (Sprint 2 / v1.1.0)
- Standalone Invoice Signer tab on Admin Dashboard.
- Batch ZIP file extraction, signature and stamp overlays, and re-zipping handled fully in-memory inside the `sign-stamp-invoice` Edge Function.
- Format-preserving SheetJS interop: keeps `.xls` as BIFF8 and `.xlsx` as Open XML.

#### ✓ Onboarding & Identity Links Foundation (Sprint 3 / v0.6.1)
- Implemented `investor_account_links` to separate Auth identities from business profiles (`profiles`).
- Verified contact-matching triggers auto-link profiles on first login.

#### ✓ Secure PAN Verification & Vault Protection (Sprint 5.2 / v0.7.0)
- Encrypted PAN storage at rest using Supabase Vault-backed AES-256 keys.
- Unique lookup index using cryptographic HMAC lookup tokens.
- Opaque, expiring candidate-tokens bound to the Advisor request to prevent internal UUID leaks in the UI.

#### ✓ Folio Verification & Scoped RLS (Sprint 5.3)
- Folio claims, canonical server-side folio generation, and holder relationship mappings (`SOLE_HOLDER`, `JOINT_HOLDER`, `GUARDIAN_FOR_MINOR`).
- Row Level Security (RLS) enforcement restricting portfolio database access to approved folio grants only.

#### ✓ Advisor Folio Authorization Layer (Sprint 5.6A)
- Request-to-Advisor assignment layer (`verification_request_assignments`).
- Strict lock ordering (`FOR UPDATE`) for verification decisions to prevent deadlocks.
- Legacy generic RPC closure to prevent verification bypass.

---

## 4. Upcoming Work

### Phase 1 — Sprint 5.6B: Advisor Verification Presentation
Focus: Advisor-facing review presentation interface, queues, and detail cards.
- **Advisor queues**: Filters by status, age, assignee, and workload metrics.
- **Review UI**: Masked evidence, relationship checks, and decision command panels.

### Phase 2 — Supervisor Assignment & Routing
Focus: Multi-Advisor scaling and supervisor routing.
- **Supervisor Role**: Privilege level to allocate, reassign, or override request queues.
- **Auto-routing gates**: Multi-Advisor assignment logic.

### Phase 3 — Portfolio Analytics & Reporting
Focus: Deeper investor engagement and reporting tools.
- **Valuation history**: Portfolio value trackers, historical charts, XIRR calculations.
- **Statements**: PDF portfolio statement generator.

### Phase 4 — Operational Monitoring & Infrastructure
Focus: Reliability, performance, and monitoring.
- **Alerting & metrics**: Edge Function performance tracking and database latency checks.
- **Backup & recovery**: Scripted database and storage bucket recovery tools.

---

## 5. Versioning Strategy

| Stage | Meaning |
|---|---|
| **Alpha** | Core architecture and workflows are being validated. Controlled breaking changes remain possible. |
| **Beta** | Feature-complete candidate tested with representative users and operational rehearsal. |
| **Release candidate** | Stabilization, security, performance, and release verification only. |
| **Stable** | Production release supported by operating, recovery, and support processes. |

---

## 6. Out of Scope

The following are ideas rather than committed roadmap items:
- Native mobile applications (unless explicitly prioritized)
- Multi-tenant software-as-a-service scaling
- AI investment recommendations
- External integrations beyond approved registrar and operational scope
- Unapproved automated investor ownership decisions

---

## 7. Success Criteria

The platform is production-ready when it demonstrates:
- Secure and complete investor ownership verification
- A complete, efficient Advisor workflow
- Strong, immutable audit history
- Zero raw PAN exposure in application data and logs
- Comprehensive automated and local validation
- A stable, repeatable release process
- Complete architecture, operational, and product documentation
