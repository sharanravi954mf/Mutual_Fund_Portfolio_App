# MoneyBowl M4 DEV Flutter handoff acceptance

Status: **proposed documentation-only acceptance revision; not deployed or commissioned**.

This file provides a harmless new source revision for the first independently
reviewed DEV frontend-owner handoff. It deliberately changes **no application
code, dependencies, migration, Edge Function, Docker configuration, GitHub Actions
workflow, webhook implementation or financial behavior**.

It is separate from M4 architecture PR #207, which includes wider backend and
deployment changes and must not be merged solely to test the Flutter cutover.

## Acceptance conditions

1. Review and approve this PR independently, and complete its applicable required
   checks. Capture the exact final merge SHA and confirm it descends from the
   current DEV release. This file alone never authorizes a deployment.
2. As part of the separately authorized DEV maintenance transaction, pause only
   the existing Flutter reconciliation timer and GitHub webhook spool dispatch
   path **before** merging. Drain the old build/spool locks and retain the existing
   listener, signature validation, live frontend and running services.
3. Verify the protected Flutter 3.44.6/Dart 3.12.2 toolchain, dedicated
   `moneybowl-deploy` identity, build tests, immutable M4 controller, isolated Git
   mirror, private public-only build defines and recovery snapshot.
4. Install and activate only the reviewed existing-frontend handler and systemd
   owner handoff, with narrowly scoped release-parent ACLs and a start-only
   authorization. Do not install a second webhook consumer or timer.
5. Build the newly merged `develop` SHA through the dedicated owner, verify
   the served full SHA, environment/project, actual `index.html` and
   `main.dart.js` digests, M4 release metadata, and healthy HTTP response.
6. Restore the existing webhook dispatch path and reconciliation timer only
   after acceptance, then observe unattended reconciliation. Preserve the
   original release and rollback material; fail closed on discrepancies.

This **frontend-only** acceptance does not commission Supabase evidence, the
ingestion API deployment owner or full-environment PASS. It does not activate
Production, QA, NSE financial dispatch or Director/M3B.

Until a reviewer approves and the cutover is executed, the previous frontend
owner and active release remain authoritative.
