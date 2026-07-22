# ADR-004 — Keep Data Access Behind Repositories

## Status

Accepted

## Date

2026-07-22

## Context

Direct Supabase calls in widgets mix presentation, authorization assumptions,
error handling, and infrastructure concerns. This makes protected workflows
harder to test and easier to bypass incorrectly.

## Decision

Flutter widgets depend on repository abstractions and application services.
Repositories invoke approved Supabase RPCs or safe data projections and map
them to domain models. Widgets own presentation state only.

## Consequences

Business logic and server interaction remain outside the UI. Tests can use fake
repositories without live Supabase access.

## Benefits

- Clear separation of concerns.
- Safer authorization boundaries.
- Better testability and maintainability.

## Trade-offs

- More interfaces and mapping code.
- Repository contracts must evolve deliberately.

## Alternatives Considered

| Alternative | Why not selected |
|---|---|
| Screen-level Supabase access | Couples UI to infrastructure and weakens reviewability. |

## References

- [Architecture contract](../architecture/ARCHITECTURE.md)
