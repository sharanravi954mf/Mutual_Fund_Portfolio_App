# ADR-005 — Require Evidence-Driven Release Workflow

## Status

Accepted

## Date

2026-07-22

## Context

Financial identity and ownership changes require reviewable evidence before
release. Implementation completion alone does not demonstrate secure behavior.

## Decision

Every sprint follows: Architecture → Implementation → Review → Security Review
→ Validation → Merge → GitHub Pre-release → CHANGELOG.

## Consequences

Local validation, security review, fixes, and final validation are release
gates. Release documentation records completed work only.

## Benefits

- Prevents unreviewed architecture and security decisions.
- Produces repeatable release evidence.
- Creates a clear history for users and future contributors.

## Trade-offs

- Requires deliberate planning and validation time.
- Releases cannot be treated as an automatic by-product of coding.

## Alternatives Considered

| Alternative | Why not selected |
|---|---|
| Merge after implementation tests only | Does not provide architectural or security review evidence. |

## References

- [Release changelog](../../CHANGELOG.md)
- [Product roadmap](../../ROADMAP.md)
