# Change Management

## Purpose
This document defines change proposal workflows, risk evaluations, review gates, rollback parameters, and emergency hotfix policies.

## Scope
Applies to all pull requests, database migration updates, and configuration revisions.

---

## Detailed Guidelines

### 1. Proposal & Risk Assessment
Every code modification must be evaluated for risk:
- **Low Risk**: Layout fixes, documentation edits, or translation additions.
- **Medium Risk**: New presentation screens, API integrations, or unit test adjustments.
- **High Risk**: Schema updates, RLS policy changes, Edge Function deployment modifications, or encryption adjustments.

High-risk changes **require** an approved `implementation_plan.md` in the artifacts folder before code modifications begin.

### 2. PR Review Gates
- All merges to `main` require a successful CI run (analysis, test, migration resets).
- High-risk changes require explicit approval from the Chief Technical Architect.

### 3. Emergency Change Workflow (Hotfixes)
When a critical bug affects production operations:
1. **Declare Outage**: Create an emergency hotfix branch: `hotfix/outage-name`.
2. **Implement Fix**: Code the remediation directly on the hotfix branch.
3. **Emergency Review**: Request peer review from an active engineer (bypassing standard timelines, but maintaining validation tests).
4. **Deploy & Rollback Prep**: If the deployment fails or causes further errors, execute rollback immediately.

---

## References
- [Git Workflow](../engineering/git-workflow.md)
- [Definition of Done](../engineering/definition-of-done.md)
