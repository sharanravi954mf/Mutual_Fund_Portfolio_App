# Release Governance

## Purpose
This document defines release readiness criteria, go/no-go processes, post-release validation checks, and release engineer responsibilities.

## Scope
Applies to all production deployments, tag generations, and version distribution actions.

---

## Detailed Guidelines

### 1. Release Readiness Criteria

To declare a version ready for deployment, it must meet three validation gates:

#### Engineering Readiness
- Passes all `flutter analyze` and `flutter test` checks.
- All database pgTAP tests pass on local sandbox database setups.
- Static asset sizes and runtime memory metrics meet non-functional requirements (NFRs).

#### Documentation Readiness
- Root `CHANGELOG.md` updated with release entries.
- Implementation plans are closed out and matching `walkthrough.md` logs are appended.

#### Architectural Approval
- The Chief Architect validates that new endpoints conform to security matrices and do not bypass RLS checks.

### 2. Go / No-Go Process
Prior to production deployment:
1. **Validation Review**: The release manager audits readiness criteria.
2. **Go/No-Go Call**: Stakeholders verify staging test results. A single "No-Go" vote from security or architecture blocks the release.
3. **Trigger Deployment**: Merge release branch to `main`.

### 3. Post-Release Validation & Review
- Within 15 minutes of deploy, verify that active metrics (connection pool, latency, error spikes) remain stable.
- Complete a post-release retrospective to document deployment issues.

---

## References
- [CI/CD Pipeline Architecture](../architecture/11-cicd-architecture.md)
- [Definition of Done](../engineering/definition-of-done.md)
