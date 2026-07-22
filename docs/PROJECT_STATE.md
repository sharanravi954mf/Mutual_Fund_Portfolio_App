# Project State

This living document records the current delivery position. Update it at the
end of every sprint or whenever a material validation boundary changes.

## Current Sprint

Sprint 5.6A — Advisor Folio Authorization Layer.

## Current Branch

`feature/sprint5.3-folio-verification`

## Current Milestone

Sprint 5.6A is complete and validated. The next approved scope is Sprint 5.6B
Advisor Folio Verification Workflow presentation.

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
- Principal engineering architecture review passed.
- Security review passed.
- SQL runtime validation and persistent SQL regression suite passed.
- Flutter analyzer introduced zero new Sprint 5.6A findings; existing project
  warnings remain separately tracked.
- Browser login was validated using explicit Supabase Dart defines.

## Pending Work

- Sprint 5.6B Advisor folio review presentation is not started.
- Supervisor assignment/reassignment workflow is deferred; it is required
  before enabling a second Advisor account.

## Known Blockers

No Sprint 5.6A blocker remains. The project retains one unrelated dashboard
test issue listed under Open Bugs.

## Known Technical Debt

- Existing `flutter analyze` warnings in legacy dashboard, web interop, theme,
  and utility files.
- Client Dashboard test animation/layout behavior needs isolated remediation.
- Multi-Advisor routing and supervised reassignment are deliberately deferred.
- Folio request/grant review remains an alpha workflow pending broader UAT.

## Open Bugs

- Dashboard shell test RenderFlex overflow described above.

## Current Database Version

Current working-tree migration head:
`20260729000002_qualify_folio_lifecycle_updates.sql`.

The preceding assignment migration is:
`20260729000000_advisor_folio_authorization.sql`.

Sprint 5.6A SQL runtime validation and persistent regression execution passed.

## Next Sprint

Sprint 5.6B — Advisor Folio Verification Workflow presentation, only after
Sprint 5.6A’s validated authorization boundary is preserved.

## Files Most Likely To Change Next

- Future Sprint 5.6B presentation files under
  `lib/features/investor_verification/presentation/`.
- `lib/features/investor_verification/data/` and `application/` only if the
  approved Advisor presentation requires an already-missing safe contract.
- `test/portfolio/client_dashboard_test.dart` when the known overflow is
  separately authorized for remediation.

## Last Updated

2026-07-23 — Sprint 5.6A final validation recorded.
