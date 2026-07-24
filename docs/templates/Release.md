# Release Template: Release [Version]

## Release Schedule
- **Target Date**: *YYYY-MM-DD*
- **Staging Verification Date**: *YYYY-MM-DD*

## Pre-Release Check Gates
- [ ] Version tag complies with Semantic Versioning.
- [ ] CI pipeline passes with zero warnings.
- [ ] Staging verification smoke checks complete.
- [ ] Go/No-Go call approved.

## Deployment Tasks
1. Merge release branch to `main`.
2. Deploy database migrations.
3. Deploy Edge Functions.
4. Deploy compiled Web static files.

## Post-Release Retrospective
*Capture deployment logs, performance metrics, or issues resolved.*
