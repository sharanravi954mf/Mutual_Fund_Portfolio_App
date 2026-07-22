# Architecture Decision Records

Architecture Decision Records (ADRs) preserve the context and rationale for
major architectural choices. They complement the high-level
[architecture contract](../architecture/ARCHITECTURE.md) by recording why a
specific enduring decision was adopted.

Create an ADR when a decision changes security boundaries, identity, data
ownership, authorization, durable data, cross-feature structure, or release
process. Use [ADR-TEMPLATE.md](ADR-TEMPLATE.md).

ADRs are immutable historical records. Do not delete or rewrite a decision
because it later changes. Create a new ADR that supersedes the old one and mark
the earlier ADR as Superseded.

| ADR | Status | Summary |
|---|---|---|
| [ADR-001](ADR-001-Identity-Architecture.md) | Accepted | Separate Auth identity from business investor identity. |
| [ADR-002](ADR-002-Candidate-Tokens.md) | Accepted | Use opaque, expiring Advisor-bound candidate tokens. |
| [ADR-003](ADR-003-PAN-Verification.md) | Accepted | Protect PAN as encrypted business evidence with immutable request evidence. |
| [ADR-004](ADR-004-Repository-Pattern.md) | Accepted | Keep Supabase access and business orchestration outside widgets. |
| [ADR-005](ADR-005-Release-Workflow.md) | Accepted | Require architecture, review, validation, and pre-release evidence. |
| [ADR-006](ADR-006-Folio-Access-Authorization.md) | Proposed | Scope investor portfolio access through active approved folio grants. |
| [ADR-007](ADR-007-Advisor-Folio-Review-Assignment.md) | Accepted | Require active Advisor assignment for folio review operations and prevent legacy generic-RPC bypasses. |
