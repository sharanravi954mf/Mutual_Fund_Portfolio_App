# Sharan Fincorp Product Roadmap

**Current release:** `v0.7.0-alpha`  
**Current maturity:** Alpha

## Project Vision

Sharan Fincorp is being built as a secure, Advisor-managed Mutual Fund
Portfolio Management platform. Its long-term direction is to give Advisors a
trusted operating system for investor identity, portfolio ownership,
reconciliation, reporting, and operational automation—while giving Investors a
safe, clear view of their own verified investments.

The platform will grow through deliberate security and operational foundations,
not by adding features ahead of the controls needed to support them.

## Current Status

`v0.7.0-alpha` establishes the core foundations required for secure investor
access and Advisor review.

- ✓ Secure authentication and session foundations
- ✓ Separation of authentication identity and business identity
- ✓ Controlled investor-account ownership links
- ✓ Advisor verification workflow
- ✓ Opaque candidate-token approval flow
- ✓ Vault-backed secret management
- ✓ PAN verification with masked business evidence
- ✓ Immutable verification audit history
- ✓ Repository-based Flutter architecture
- ✓ Row Level Security and server-side authorization
- ✓ Local validation, security review, and pre-release workflow

## Release History

| Version | Status | Major Features | Notes |
|---|---|---|---|
| `v0.6.1-alpha` | Released | Identity, onboarding, ownership, and verification foundations | Established secure portfolio-linking direction. |
| `v0.7.0-alpha` | Released | PAN verification, Vault protection, candidate tokens, audit controls | Current alpha baseline. |
| `v0.8.0-alpha` | Planned | Verification and reconciliation improvements | Scope to be approved before implementation. |
| `v0.9.0-beta` | Planned | Broader portfolio and operational maturity | Beta entry target. |
| `v1.0.0-rc1` | Planned | Release-candidate stabilization | No unapproved feature expansion. |
| `v1.0.0` | Planned | Production launch | Subject to readiness criteria. |

## Planned Roadmap

### Phase 1 — Sprint 5.3

Primary objectives:

- Folio verification
- PAN correction workflow
- Approval reversal
- Imported PAN reconciliation

The exact Sprint 5.3 scope will be finalized and architected before work
begins.

### Phase 2 — Verification Improvements

Focus: stronger verification operations and Advisor productivity.

- Document verification
- Operational reconciliation
- Verification tooling
- Advisor productivity improvements

### Phase 3 — Portfolio Management Enhancements

Focus: richer portfolio insight and scalable Advisor operations.

- Portfolio analytics
- Client dashboards
- Reporting
- Statement generation
- Search improvements
- Bulk operations

### Phase 4 — Operational Maturity

Focus: reliability, governance, and sustainable operations.

- Monitoring and alerting
- Performance improvement
- Security hardening
- Backup strategy
- Disaster recovery
- Audit improvements

### Phase 5 — Production Readiness

Focus: validated delivery to real users.

- Beta release
- User acceptance testing
- Independent security review
- Load testing
- Release candidate
- Production launch

## Versioning Strategy

| Stage | Meaning |
|---|---|
| Alpha | Core architecture and workflows are being validated. Controlled breaking changes remain possible. |
| Beta | Feature-complete candidate tested with representative users and operational rehearsal. |
| Release candidate | Stabilization, security, performance, and release verification only. |
| Stable | Production release supported by operating, recovery, and support processes. |

Current version: **`v0.7.0-alpha`**.

## Development Process

Every sprint follows the same delivery discipline:

```text
Architecture
    ↓
Implementation
    ↓
Local validation
    ↓
Security review
    ↓
Fixes
    ↓
Validation
    ↓
Merge
    ↓
GitHub Release
```

This process ensures that product progress does not outpace security,
authorization, auditability, or operational readiness.

## Out of Scope

The following are ideas rather than committed roadmap items:

- Native mobile applications
- Multi-tenant scaling
- AI investment recommendations
- External integrations beyond approved registrar and operational scope
- Unapproved automated investor ownership decisions

## Success Criteria

The platform is production ready when it demonstrates:

- Secure and complete investor ownership verification
- A complete, efficient Advisor workflow
- Strong immutable audit history
- Zero raw PAN exposure in application data and logs
- Comprehensive automated and local validation
- A stable, repeatable release process
- Complete architecture, operational, and product documentation
