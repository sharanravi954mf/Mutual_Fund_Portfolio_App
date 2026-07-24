# Risk Register

## Purpose
This document logs technical, security, operational, documentation, and AI-related risks, detailing impact levels and mitigation steps.

## Scope
Tracks active risks that could impact the platform's stability, security, or product roadmap.

---

## Detailed Guidelines

### Risk Matrix

| Risk ID | Category | Description | Impact | Mitigation Strategy |
| :--- | :--- | :--- | :---: | :--- |
| **RSK-001** | Security | Exposure of raw PAN records during imports or queries. | **Critical** | Database encrypts PAN at rest (AES-256) and exposes hashes only. Logs scrub PAN before writing. |
| **RSK-002** | Technical | Edge Function timeout (50ms limit) during large ZIP/PDF signing. | **High** | Functions run in-memory without database writes. Large tasks are offloaded to client interops. |
| **RSK-003** | Operational | Duplicate folio claims from separate investor accounts. | **Medium** | System enforces strict unique constraints and routes duplicate claims to advisor reviews. |
| **RSK-004** | AI | Hallucination of relative imports or deletion of code comments by agents. | **High** | Mandatory compiler checks (`flutter analyze`) and code audits against `AGENTS.md` rules. |
| **RSK-005** | Documentation| Outdated roadmap and changelog entries. | **Medium** | DoD rules mandate documentation update before pull requests can be merged. |

### Review Cadence
The Risk Register is reviewed by the Chief Enterprise Governance Architect every two weeks.

---

## References
- [Target Architecture Contract](../architecture/ARCHITECTURE.md)
- [Definition of Done](../engineering/definition-of-done.md)
