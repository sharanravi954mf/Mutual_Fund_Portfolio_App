# ADR-002 — Use Opaque Candidate Tokens for Advisor Approval

## Status

Accepted

## Date

2026-07-22

## Context

Advisors need to select an imported investor during verification without
exposing internal profile UUIDs or allowing arbitrary identifiers to be typed.

## Decision

Candidate search returns a short-lived opaque token encrypted with a dedicated
Vault secret. The server binds it to the Advisor, verification request,
candidate, and expiry. Approval resolves and validates the token server-side.

## Consequences

UUIDs remain internal. Expired, tampered, replayed, wrong-Advisor, and
wrong-request tokens are rejected before a link can be created.

## Benefits

- Removes internal identifiers from the UI.
- Preserves server-side authorization and validation.
- Provides a narrow, auditable approval capability.

## Trade-offs

- Requires Vault provisioning and expiry regression tests.
- Advisor selections must be refreshed when a token expires.

## Alternatives Considered

| Alternative | Why not selected |
|---|---|
| Send profile UUID to Flutter | Leaks an internal identifier and expands misuse risk. |
| Persist candidate selections | Adds state, cleanup, and lifecycle complexity. |

## References

- [ADR-001](ADR-001-Identity-Architecture.md)
