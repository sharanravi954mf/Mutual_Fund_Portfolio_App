# Project State

This living document records the current delivery position. Update it at the
end of every sprint or whenever a material validation boundary changes.

## Current Sprint

Sprint 5.6A.1 — Close Legacy Folio Authorization Bypasses.

## Current Branch

`feature/sprint5.3-folio-verification`

## Current Milestone

Sprint 5.6A implementation is frozen for final acceptance review. The working
tree contains the Advisor folio assignment layer and legacy-RPC remediation.

## Completed Work

- Secure identity, onboarding, RBAC/RLS, and permanent investor ownership
  links.
- Secure PAN verification with Vault-backed encryption/HMAC, immutable
  evidence, masked projections, and opaque Advisor candidate tokens.
- Folio verification foundation: canonical registrar-aware folios, immutable
  evidence, grants, folio-scoped portfolio RLS, secured lifecycle RPCs, and SQL
  regression coverage.
- Folio repository, datasource, service, presentation controller/provider,
  safe presentation models, investor verification page, and shell integration.
- Advisor folio review assignment table, assignment-scoped queue/detail RPCs,
  and safe repository/service contracts.
- Legacy generic verification RPC closure for folio requests, including typed
  action-specific reason codes and dedicated folio history access.

## Pending Work

- Run Sprint 5.6A/5.6A.1 database validation locally.
- Resolve or explicitly waive the known unrelated Client Dashboard RenderFlex
  test failure before a clean full-suite release gate.
- Obtain approval, then commit the frozen Sprint 5.6A change set.
- Sprint 5.6B Advisor folio review presentation is not started.
- Supervisor assignment/reassignment workflow is deferred; it is required
  before enabling a second Advisor account.

## Known Blockers

1. Mandatory local database validation has not completed for the current
   uncommitted migrations:

   ```sh
   supabase db reset
   sh supabase/tests/run_all.sh
   ```

2. The full Flutter suite has one known unrelated failure in
   `test/portfolio/client_dashboard_test.dart`: a `RenderFlex` overflow at
   `lib/screens/client_dashboard.dart:682` during the injected-folio-feature
   shell test.

## Known Technical Debt

- Existing `flutter analyze` warnings in legacy dashboard, web interop, theme,
  and utility files.
- Client Dashboard test animation/layout behavior needs isolated remediation.
- Multi-Advisor routing and supervised reassignment are deliberately deferred.
- Folio request/grant review remains an alpha workflow pending full local SQL
  validation and UAT.

## Open Bugs

- Dashboard shell test RenderFlex overflow described above.
- No confirmed defect in the frozen Sprint 5.6A implementation; SQL runtime
  execution remains the required confirmation.

## Current Database Version

Target working-tree migration head:
`20260729000001_close_legacy_folio_authorization_bypasses.sql`.

The preceding assignment migration is:
`20260729000000_advisor_folio_authorization.sql`.

Both are uncommitted and require local reset plus persistent SQL regression
execution before acceptance.

## Next Sprint

Sprint 5.6B — Advisor Folio Verification Workflow presentation, only after
Sprint 5.6A is accepted, committed, and its SQL validation evidence is recorded.

## Files Most Likely To Change Next

- `supabase/tests/folio_verification_foundation.sql` — only if local validation
  exposes a real regression.
- `docs/sprints/Sprint-5.6A.md`
- `docs/decisions/ADR-007-Advisor-Folio-Review-Assignment.md`
- Future Sprint 5.6B presentation files under
  `lib/features/investor_verification/presentation/`.
- `test/portfolio/client_dashboard_test.dart` and potentially its test harness
  when the known overflow is separately authorized.

## Last Updated

2026-07-23 — Final acceptance review preparation for Sprint 5.6A.1.
