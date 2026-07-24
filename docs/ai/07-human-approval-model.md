# 07 — Human Approval Model

## Purpose
This document defines the strict validation gates, human approval requirements, escalations, and risk management criteria.

## Scope
Applies to all pull requests, database migration deploys, and security changes.

---

## Detailed Guidelines

### 1. Risk-Based Approval Gates

Approval requirements scale dynamically based on the risk level of the proposed modifications:

| Change Risk | Description | Required Human Sign-Off |
| :--- | :--- | :--- |
| **Low Risk** | Styling edits, typo fixes, docs markdown updates. | Peer developer check. |
| **Medium Risk** | Presentation controllers, service modifications, new unit tests. | Lead Developer approval. |
| **High Risk** | Schema migrations, RLS changes, pg_vault integrations, API routes. | Technical Architect + Security Lead approvals. |

### 2. Go / No-Go Process
No release branch merges to `main` without a formal human-approved **Go/No-Go** check. A single architectural or security block overrides any product schedule.

### 3. Escalations
If conflicts occur between performance targets and security requirements (e.g. Vault encryption latency vs. fast render), the issue is escalated to the Architecture Board for final resolution.

---

## References
- [Change Management](../../governance/change-management.md)
- [Repository Governance](../../governance/repository-governance.md)
- [Release Governance](../../governance/release-governance.md)
