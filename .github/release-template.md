## Release Template

### Release Summary
*Provide a high-level overview of the capabilities introduced in this release.*

### New Features
*List all new capabilities (link to feature tickets or PRs).*

### Bug Fixes
*List all resolved bugs.*

### Breaking Changes
*Detail any backward-incompatible API changes or schema shifts.*

### Migration Notes
*List the SQL migration scripts applied to production databases during release.*
```bash
# Example migration commands executed
supabase db deploy --project-ref <project-id>
```

### Known Issues & Technical Debt
*Describe any outstanding warnings or known bugs deferred to future sprints.*

### Rollback Plan
*Provide step-by-step instructions to revert web hosting and function deployments if failures occur.*
1. Revert web routing on CDN to release tag `vX.Y.Z-previous`.
2. Apply hotfix migration if schema updates need backward-compatible adjustments.
