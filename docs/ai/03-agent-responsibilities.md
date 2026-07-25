# 03 — Agent Responsibilities

## Purpose
This document maps business and engineering responsibilities to specific AI agent roles to ensure clear ownership and avoid task conflicts.

## Scope
Applies to task allocation, PR assignments, and test monitoring.

---

## Detailed Guidelines

### Ownership Matrix

We map core repository activities to specific agent roles:

- **Chief Architect Agent**: Reviews proposed designs against [Target Architecture Contract](../architecture/README.md) and approves ADR status changes.
- **Product Architect Agent**: Maintains user journeys, catalogs features, and tracks personas.
- **Engineering Architect Agent**: Enforces clean architecture guidelines and audits API REST rules.
- **Implementation Agent (Coder)**: Modifies code inside sandboxed workspaces.
- **Testing Agent (QA)**: Writes unit/widget tests and executes database pgTAP scripts.
- **Documentation Agent**: Updates specs, changelogs, and walkthoughs.
- **Reviewer Agent**: Audits pull requests for relative imports and lints compliance.
- **Release Agent**: Prepares build packages and creates draft release tags.

---

## References
- [Repository Governance](../governance/repository-governance.md)
- [Review Checklists](../engineering/review-checklists.md)
