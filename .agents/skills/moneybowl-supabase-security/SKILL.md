---
name: moneybowl-supabase-security
description: Implement or validate Money Bowl Supabase and PostgreSQL migrations, SECURITY DEFINER RPCs, RLS, profile resolution, workspace isolation, immutable audit logging, concurrency controls, and financial-data migration safety. Use whenever database security or transaction correctness is involved.
---

# Money Bowl Supabase Security

## Migration rules

- Inspect the full migration sequence first.
- Never edit an applied migration.
- Use the next corrective migration.
- Prefer additive and backward-compatible changes.
- Add preflight checks for incompatible existing data.
- Never silently delete or transform financial records.
- Use stable machine-readable error messages.
- Run a clean local database reset.

## SECURITY DEFINER rules

- Use `SET search_path = ''`.
- Fully qualify tables, functions, types and sensitive built-ins.
- Revoke execution from `PUBLIC`.
- Grant execution only to required roles.
- Perform internal authorisation after granting role-level execution.
- Never accept caller identity as an RPC parameter.

## Identity and workspace rules

- Resolve `auth.uid()` to `public.profiles.id` through
  `public.current_user_profile_id()`.
- Do not directly compare profile foreign keys with `auth.uid()`.
- Fail closed when profile resolution is null or ambiguous.
- Load workspace, beneficiary and state values from database rows.
- Deny unrelated and cross-workspace actors.
- Explicitly test:
  - Platform Admin
  - Family Guest
  - inactive membership
  - operations membership
  - unrelated advisor
  - cross-workspace user

## RLS and privilege rules

- Inspect the complete existing policy and privilege surface before
  changing RLS.
- Query `pg_catalog.pg_policies` rather than assuming only known policy
  names exist.
- PostgreSQL permissive policies combine with `OR`; an unexpected
  surviving policy can broaden access.
- When an issue owns the complete RLS contract for a table, ensure the
  final policy set is exclusive:
  - remove or fail on unexpected policies
  - create only the intended policy names
  - assert exact commands and roles
  - assert the expected total policy count
- Use safely quoted catalog-driven dynamic SQL when replacing an
  exclusive policy set.
- Verify RLS enablement through PostgreSQL catalog metadata.
- Verify production grants using:
  - `pg_catalog.has_table_privilege`
  - `pg_catalog.has_function_privilege`
  - `pg_catalog.pg_proc`
  - ACL catalog inspection where PUBLIC/default privileges matter
- Test the actual API roles with `SET ROLE`; do not grant broad
  privileges inside focused tests merely to make test setup easier.
- Separate API-role behavior from database-owner migration maintenance
  and historical fixture setup.
- Treat JWT workspace claims only as request or UI context, never as the
  database authorization boundary.
- Verify RLS policies, triggers, table grants and SECURITY DEFINER RPCs
  do not create parallel unaudited mutation paths.
- For lifecycle-controlled financial tables, prefer restricted audited
  RPCs over direct client UPDATE or DELETE access.

## Transaction and audit rules

- Use `SELECT ... FOR UPDATE` when concurrent financial state changes
  can race.
- Perform state mutation and audit insertion in the same transaction.
- Build audits from database-loaded values.
- Record actor, workspace, entity, reason, previous state, new state and
  timestamp.
- Verify immutable audit rows cannot be updated or deleted.

## Required validation

Run where applicable:

```bash
supabase db reset --yes
sh supabase/tests/run_all.sh
supabase db lint --local
```

## Validation classification

Classify every warning or lint finding as:

- new and issue-specific
- pre-existing baseline
- unrelated environmental/tooling failure

Any new issue-specific error fails implementation or QA.

Record the exact command and relevant output for failures. Do not claim
a pass merely because unrelated baseline warnings already exist.

## Environment safety

- Use the local Supabase environment for migration development and
  destructive reset testing.
- Do not apply migrations to production, staging, linked, or shared
  remote environments without Ravi's explicit approval.
- Before adding a constraint that existing data may violate, run a
  read-only preflight and fail closed with a clear diagnostic.
- Never silently delete, rewrite, or auto-correct financial records to
  make a migration pass.
