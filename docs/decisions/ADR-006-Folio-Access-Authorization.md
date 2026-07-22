# ADR-006 — Folio-Scoped Portfolio Access Authorization

## Status

Proposed

## Date

2026-07-22

## Context

An active `investor_account_links` record connects an authenticated account to a business investor profile. A profile can be associated with multiple folios and holder relationships. Account linking alone cannot prove the account may view every folio-derived portfolio record.

## Decision

Use active approved folio grants as the investor portfolio-access authority. Investor access requires both an active `investor_account_links` relationship and an active approved grant for the relevant canonical folio. The account link answers which account belongs to which business profile; the grant answers which folio-derived data that linked account may access.

Sprint 5.3 supports `SOLE_HOLDER`, `JOINT_HOLDER`, and `GUARDIAN_FOR_MINOR`. Joint and guardian grants require Advisor review and registrar evidence. Nominee, family, beneficiary, power-of-attorney, informal authorization, and deceased-holder succession do not grant direct access.

Revoking an account link removes all investor portfolio access. Revoking one grant removes access only to that folio. PAN correction and imported reconciliation do not silently alter grants; future explicit workflows may suspend or review them with immutable audit history.

## Consequences

RLS, portfolio repositories, and authorization must use an active-link-plus-active-grant predicate at canonical-folio scope. Existing linked investors require controlled migration and compare-mode rollout so access is neither silently broadened nor unexpectedly removed. Existing verification requests, events, secured RPCs, optimistic locking, and repository boundaries are reused.

## Benefits

- Enforces least privilege for investor portfolio access.
- Makes folio ownership reviewable, revocable, and auditable.
- Supports evidenced joint-holder and guardian access without treating family or nominee status as ownership.
- Preserves separation of authentication, business identity, PAN evidence, and authorization.

## Trade-offs

- Adds grant lifecycle, canonical identity, RLS, and migration complexity.
- Requires trusted registrar evidence and Advisor review capacity.
- Needs careful rollout for existing account-level access.

## Alternatives Considered

| Alternative | Why not selected |
|---|---|
| Blanket profile access from account linking | Cannot restrict access to folios proven to belong to the linked investor. |
| PAN approval as portfolio authority | PAN is supporting business evidence, not folio-level ownership authorization. |
| Client-side portfolio filtering | Cannot enforce security and would expose unauthorized data. |
| Treat all associated people as owners | Would grant unsupported access to nominees and family members. |

## Security Consequences

Investor RLS must require both active identity link and matching active grant. Browser clients must not directly create or modify grants, decisions, or immutable evidence. Secured RPCs enforce relationship policy, optimistic locking, idempotency, append-only events, and immediate loss of authorization when links or grants become inactive.

## References

- [Sprint 5.3 Design](../sprints/Sprint-5.3-Design.md)
- [ADR-001 — Identity Architecture](ADR-001-Identity-Architecture.md)
- [ADR-003 — PAN Verification](ADR-003-PAN-Verification.md)
