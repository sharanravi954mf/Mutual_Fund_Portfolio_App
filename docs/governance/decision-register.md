# Decision Register

## Purpose
This document serves as the living registry of all significant architectural, product, and engineering decisions.

## Scope
Includes all decisions captured as formal Architecture Decision Records (ADRs) or product direction shifts.

---

## Detailed Guidelines

| Decision ID | Title | Category | Date | Owner | Status | Reason | Impact | Link to ADR / Reference |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **DEC-001** | Separate Auth Identity from Profile | Architecture | 2026-07-22 | Chief Architect | **Accepted** | Imported folios must exist before sign-up. | Separates login credentials from business data. | [ADR-001](../decisions/ADR-001-Identity-Architecture.md) |
| **DEC-002** | Opaque Candidate-Tokens | Security | 2026-07-22 | Security Lead | **Accepted** | Prevent UUID enumeration leaks in UI. | Secures advisor search. | [ADR-002](../decisions/ADR-002-Candidate-Tokens.md) |
| **DEC-003** | Vault-Backed PAN Encryption | Security | 2026-07-22 | Security Lead | **Accepted** | Protect PII (PAN) to meet compliance rules. | Encrypts PAN, lookup via HMAC. | [ADR-003](../decisions/ADR-003-PAN-Verification.md) |
| **DEC-004** | Repository Isolation | Engineering | 2026-07-22 | Lead Developer | **Accepted** | UI widgets should remain decoupled from database. | Decouples Flutter widgets. | [ADR-004](../decisions/ADR-004-Repository-Pattern.md) |
| **DEC-005** | Evidence-Driven Release | Release | 2026-07-22 | Release Manager | **Accepted** | Enforce security checks before merges. | Establishes test gates. | [ADR-005](../decisions/ADR-005-Release-Workflow.md) |
| **DEC-006** | Folio-Scoped RLS | Security | 2026-07-22 | Chief Architect | **Accepted** | Restrict reads to verified owners. | Secures portfolio reads. | [ADR-006](../decisions/ADR-006-Folio-Access-Authorization.md) |
| **DEC-007** | Advisor Request Assignment | Security | 2026-07-23 | Chief Architect | **Accepted** | Restrict queue actions to assigned advisor. | Secures advisor queue. | [ADR-007](../decisions/ADR-007-Advisor-Folio-Review-Assignment.md) |
| **DEC-008** | In-Memory ZIP Ingestion | Engineering | 2026-07-23 | Lead Developer | **Accepted** | Prevent container I/O and function timeouts. | Offloads server disk. | [ADR-008 / 0002](../decisions/0002_in_memory_zip_processing.md) |
| **DEC-009** | SheetJS Web Interop | Engineering | 2026-07-19 | Lead Developer | **Accepted** | Support legacy `.xls` format on Web. | Bypasses Dart Excel limits. | [Changelog Boundary Notes](../changelog/cams_invoice_signer_boundary.md) |

---

## References
- [Architecture Decision Records Index](../decisions/README.md)
