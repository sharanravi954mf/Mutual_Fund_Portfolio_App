# ADR-007 — Advisor Assignment for Folio Review

## Status

Accepted

## Date

2026-07-23

## Context

Folio grants control investor portfolio access. A broad `is_admin()` check is
adequate for the current single-Advisor installation but cannot prevent one
Advisor from reviewing another Advisor's investor request in a multi-Advisor
deployment.

## Decision

Each folio verification request has at most one active assignment in
`verification_request_assignments`. Advisor-safe queue, detail, and lifecycle
operations require both Advisor account state and an active assignment.

Generic verification RPCs are permanently non-folio contracts. They either
exclude folio rows or return a stable database error directing callers to the
dedicated folio lifecycle. This prevents legacy queue, candidate, and decision
paths from bypassing assignment authorization.

Single-Advisor installations receive automatic assignment during migration and
submission. Deployments with multiple Advisors require a future supervisor
assignment workflow; automatic selection among multiple Advisors is forbidden.

## Consequences

Folio review authorization is server-enforced and cannot depend on Flutter
filtering. Existing generic PAN review remains compatible. Assignment changes
and routing require an explicit future operational workflow rather than an
implicit privilege escalation.

Folio decision operations lock the request row before the active assignment
row. Any future reassignment mechanism must use the same lock ordering to avoid
deadlocks and serialize an assignment change with a decision.

## Benefits

- Enforces least-privilege Advisor review.
- Supports a controlled move from one Advisor to multiple Advisors.
- Preserves immutable evidence, versioned lifecycle decisions, and event audit
  history.

## Trade-offs

- Multi-Advisor deployments need assignment operations before they can process
  new folio requests.
- The current schema has no supervisor role, so reassignment is deferred.

## Alternatives Considered

| Alternative | Reason not selected |
|---|---|
| Retain global `is_admin()` review access | Cannot isolate unrelated Advisors. |
| Assign a random active Advisor | Creates nondeterministic ownership and weak auditability. |
| Expose all requests and filter in Flutter | Does not enforce authorization. |

## References

- [Sprint 5.6A](../sprints/Sprint-5.6A.md)
- [ADR-006 — Folio-Scoped Portfolio Access Authorization](ADR-006-Folio-Access-Authorization.md)
