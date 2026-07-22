# ADR-003 — Protect PAN as Encrypted Business Evidence

## Status

Accepted

## Date

2026-07-22

## Context

PAN is sensitive investor evidence needed for explicit portfolio verification.
It must support matching and duplicate review without becoming a login field or
being exposed to browsers, logs, or operational statement storage.

## Decision

Use encrypted `profile_pan_records` for business PAN provenance and immutable
`verification_pan_evidence` for submitted request evidence. Use a canonical
record reference on profiles. Encrypt PAN with Vault and use a separate HMAC
secret for deterministic lookup.

## Consequences

Advisor and investor projections show masked PAN only. Duplicate detection is
safe and server-side. Registrar source and historical evidence remain distinct
from a single verification request.

## Benefits

- No raw PAN in active operational tables or logs.
- Strong auditability and source precedence.
- Efficient matching without direct raw-PAN lookup.

## Trade-offs

- Requires Vault operations and protected data models.
- Key rotation requires a planned migration.

## Alternatives Considered

| Alternative | Why not selected |
|---|---|
| Store raw PAN on profiles | Exposes sensitive data and loses provenance. |
| One PAN table for all purposes | Mixes mutable business history with immutable request evidence. |

## References

- [ADR-001](ADR-001-Identity-Architecture.md)
- [Architecture contract](../architecture/ARCHITECTURE.md)
