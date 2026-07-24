## Pull Request Template

### Summary
*Provide a concise summary of the changes introduced in this PR.*

### Problem Statement
*Describe the issue, bug, or feature request this PR addresses.*

### Solution
*Explain the technical solution implemented.*

### Validation & Testing Completed
- [ ] Static checks completed: `flutter analyze` passes.
- [ ] Client tests completed: `flutter test` passes.
- [ ] Database tests completed: `supabase db reset` and `sh supabase/tests/run_all.sh` pass.
- [ ] Staging validation checked for affected roles (Advisor/Investor/Explorer).

### System Impact Analysis
- **Architecture**: *Are there any architecture contract changes? (If yes, link to ADR)*
- **Database**: *Are there any schema migrations?*
- **Security**: *Have RLS policies, Vault secrets, or input sanitizations been audited?*
- **PII / PAN**: *Confirm no raw PAN or unmasked PII is logged or exposed in client responses.*
- **Breaking Changes**: *Is this change backward-compatible?*

### Definition of Done Checklist
- [ ] Code compiles cleanly with zero warnings.
- [ ] Coding rules in `AGENTS.md` and `coding-standards.md` are followed.
- [ ] Unit/regression tests are added for new capabilities.
- [ ] Walkthrough logs (`walkthrough.md`) are updated with command logs.
- [ ] PR is squash-merged; git tags updated if applicable.
