# ADR-001 — Separate Authentication Identity from Business Identity

## Status

Accepted

## Date

2026-07-22

## Context

Registrar-imported investors and portfolios may exist before a person creates
an application login. Treating a profile as an Auth user would incorrectly tie
business data, authentication, and portfolio ownership together.

## Decision

Use Supabase Auth for authentication, `user_accounts` for application account
state, `profiles` for business investor identity, and
`investor_account_links` for the controlled ownership relationship.

PAN is business evidence, never authentication identity, a login credential,
or an automatic-linking mechanism.

## Consequences

Investor access requires an active approved link. Explorers and Link Pending
users can exist without a business profile link. Imported investors can exist
without Auth accounts.

## Benefits

- Preserves registrar data independently of sign-up.
- Prevents unsafe ownership claims.
- Supports explicit verification and future linking methods.

## Trade-offs

- Requires account-state resolution and controlled linking workflows.
- Adds a relationship model instead of relying on a single profile field.

## Alternatives Considered

| Alternative | Why not selected |
|---|---|
| Use `profiles` as the Auth account | Cannot represent imported investors safely. |
| Use PAN as login or link identity | Insecure and incompatible with business rules. |

## References

- [Architecture contract](../architecture/ARCHITECTURE.md)
