# AI Engineering Handoff

**Mandatory reading before any implementation, review, migration, or release
work.** Read this document with the relevant ADRs and sprint documents before
making a change.

## Project Overview

Sharan Fincorp is an Advisor-managed mutual-fund portfolio platform. It helps
distributors operate client, registrar-ingestion, document, factsheet, and
verification workflows while giving investors a secure view of only the
portfolio data they have been authorized to access.

The two primary users are:

- **Advisor** — manages clients, verification, ingestion, factsheets, invoice
  signing, and business operations.
- **Investor** — views permitted personal portfolio data, factsheets, and
  account settings.

Registrar data may be imported before an investor has an application account.
The product therefore separates authentication identity from the distributor's
business investor identity.

## Technology Stack

- Flutter and Dart for the web and mobile application.
- Provider for application state and dependency wiring.
- Supabase Auth, PostgreSQL, Row Level Security (RLS), Storage, and Edge
  Functions.
- PostgreSQL `SECURITY DEFINER` RPCs for privileged lifecycle operations and
  safe read projections.
- Repository and datasource abstractions between Flutter and Supabase.
- Supabase Vault-backed encryption/HMAC for protected PAN data.

## Repository Structure

| Location | Responsibility |
|---|---|
| `lib/main.dart` | Application bootstrap and top-level route decisions. |
| `lib/providers/` | Shared app/session/theme/language state. |
| `lib/screens/` | Existing application-shell and dashboard presentation. |
| `lib/features/` | Feature-oriented models, data, application, and presentation layers. |
| `lib/features/investor_verification/` | Verification, PAN, and folio verification feature boundaries. |
| `lib/services/` | Shared integrations and Supabase bindings. |
| `lib/utils/` | Focused utilities such as calculations and file processing. |
| `supabase/migrations/` | Forward-only PostgreSQL schema, RLS, triggers, and RPC changes. |
| `supabase/functions/` | Secured Edge Functions, primarily registrar ingestion. |
| `supabase/tests/` | Persistent SQL security and lifecycle regression tests. |
| `test/` | Flutter unit, repository, service, provider, and widget tests. |
| `docs/architecture/` | High-level system architecture. |
| `docs/decisions/` | Immutable Architecture Decision Records (ADRs). |
| `docs/sprints/` | Approved sprint scopes, designs, and implementation notes. |

## Architecture

### Authentication and Identity

```text
Supabase Auth user
  -> user_accounts
  -> investor_account_links
  -> profiles
  -> portfolios / transactions
```

- `user_accounts` is the application account and account-state boundary.
- `profiles` is the distributor's business-investor record and can exist before
  signup.
- `investor_account_links` is the sole account-to-business-profile ownership
  relationship. Do not restore `profiles.user_id` as an ownership source.
- Account states are `explorer`, `link_pending`, `linked_investor`, and
  `advisor`.
- PAN is business evidence only: never a login credential, signup field, or
  automatic identity-match input.

### Authorization and Folio Assignment

Investor portfolio access requires both an active `investor_account_links`
record and an active approved folio grant for the relevant canonical folio.
Advisor folio review additionally requires an active
`verification_request_assignments` record for that request.

Folio requests are not generic verification requests in browser-facing
contracts. Use dedicated folio RPCs for submission, read projections, and
lifecycle transitions. Generic queues, candidate selection, details, history,
and decisions must exclude or reject folio requests.

### RPC Philosophy

- Widgets never call Supabase directly.
- Repositories call safe RPCs and map safe DTOs to domain entities.
- Application services orchestrate repository work, validation, typed failure
  mapping, and correlation IDs.
- Browser clients receive masked display projections only. They must never
  receive canonical folio IDs, profile IDs, raw PAN, encrypted evidence, or
  direct access to protected tables.
- Privileged mutations use `SECURITY DEFINER`, explicit `search_path`, expected
  version checks, atomic transactions, and append-only events.

### Database and Migration Philosophy

- Migrations are forward-only. Never edit, replace, or delete a historical
  migration.
- SQL must use explicit aliases where column/variable names could be ambiguous.
- Keep helper functions private: revoke browser execution. Grant execute only
  to intended safe RPCs.
- RLS is the backend authority. Flutter visibility is not authorization.
- Immutable evidence and append-only verification events must remain immutable.

### Testing Philosophy

- Use repository-native persistent SQL tests in `supabase/tests/` for RLS,
  grants, RPC privileges, lifecycle transitions, concurrency, and atomicity.
- Use Flutter tests for DTO mapping, repository invocation, service workflow,
  state, and widgets.
- Do not substitute a mocked UI test for SQL authorization coverage.
- Before acceptance, run database reset, all SQL tests, Flutter analysis, full
  Flutter tests, and `git diff --check`.

## Architectural Decisions

Read the complete ADRs in [decisions](decisions/README.md). The key decisions
are summarized here for orientation only.

| ADR | Decision and rationale |
|---|---|
| ADR-001 | Separate Supabase authentication from business investor profiles so imported portfolios can exist before signup. PAN is not identity for login. |
| ADR-002 | Use opaque, expiring, request- and Advisor-bound candidate tokens instead of exposing UUIDs. |
| ADR-003 | Protect PAN through canonical encrypted records, immutable evidence, Vault keys, HMAC lookup, and masked browser projections. Raw PAN never belongs in operational tables or logs. |
| ADR-004 | Keep Supabase access outside widgets through repository/datasource boundaries for testability and enforceable separation of concerns. |
| ADR-005 | Require architecture, implementation, review, security validation, merge, and release evidence in sequence. |
| ADR-006 | Require both active identity link and active approved folio grant for investor portfolio access. This prevents blanket profile access. |
| ADR-007 | Scope Advisor folio review to one active assignment per request; generic verification contracts must not bypass it. |

Rejected alternatives include using PAN as authentication, exposing UUIDs in
Advisor flows, client-side authorization/filtering, blanket profile portfolio
access, random Advisor assignment, direct browser reads of evidence/grants, and
generic lifecycle endpoints for folio review.

## Sprint History

- **Sprint 2:** Registrar-agnostic Invoice Signer foundation, CAMS/KFintech
  processing boundaries, shared archive/PDF discovery, and safe output flows.
- **Sprint 3:** Identity foundation, secure onboarding, RBAC/RLS hardening, and
  migration from legacy profile ownership to identity links.
- **Sprint 4:** Investor dashboard foundation and verification workflow design.
- **Sprint 5.2:** Secure PAN verification: Vault-backed encryption, HMAC lookup,
  immutable evidence, opaque candidate tokens, and masked Advisor review.
- **Sprint 5.3:** Folio verification foundation: canonical registrar-aware
  folios, immutable evidence, grants, folio-scoped RLS, repositories, services,
  presentation contracts, and investor UI integration.
- **Sprint 5.6A (working tree):** Assignment-scoped Advisor folio
  authorization, safe Advisor projections, legacy generic-RPC closure, and
  action-specific reason codes. Acceptance still requires local SQL execution.

## Coding Standards

### Flutter

- Prefer feature layers: `models` → `data` → `application` → `presentation`.
- Use constructor injection. Avoid hidden singletons and direct production
  dependencies in test harnesses.
- Keep widgets limited to rendering and controller delegation.
- Preserve immutable models and typed failures.
- Use existing Provider patterns; do not introduce state-management frameworks
  without an approved ADR.

### SQL and RPCs

- Name public browser RPCs clearly; private helpers begin with `_` and have no
  browser execute grant.
- Every mutation validates caller, lifecycle state, expected version, and
  authorization before write effects.
- Emit an immutable event in the same transaction as a successful lifecycle
  change.
- Lock order for folio decisions: request row, then active assignment row.
- Return safe projections, never internal canonical IDs or sensitive evidence.

### Tests and Documentation

- Add regression tests with every security or lifecycle change.
- Test negative authorization paths as carefully as success paths.
- Update the applicable sprint document and ADR when an enduring architectural
  decision changes.
- Update `PROJECT_STATE.md` at the end of each sprint.

## Security Rules

1. Never bypass RPCs, repositories, or RLS.
2. Never weaken RLS or restore browser access to protected tables.
3. Never expose or log raw PAN, encrypted PAN, HMAC material, canonical folio
   identifiers, profile IDs, or security tokens in a browser projection.
4. Never edit historical migrations.
5. Never bypass active Advisor assignment for a folio operation.
6. Never replace explicit folio lifecycle RPCs with generic transitions.
7. Never remove optimistic locking, immutable evidence, or append-only events.
8. Never add random assignment or broad `is_admin()` folio access.
9. Never use a client-generated canonical identity.

## Deployment Checklist

### Before Commit

- Review `git status` and keep the change set scoped.
- Run `dart format` for changed Dart files.
- Run `flutter analyze`, focused tests, and `git diff --check`.
- For SQL changes, run `supabase db reset` and `sh supabase/tests/run_all.sh`.

### Before Merge

- Run the full Flutter suite and a debug web build.
- Review RLS, grants, `SECURITY DEFINER`, `search_path`, and direct table
  privileges.
- Confirm the affected safe projections do not leak sensitive fields.
- Record known failures and obtain explicit approval for any unrelated debt.

### Before Production

- Apply migrations in staging and run SQL regression tests.
- Configure required Vault secrets and verify service-role assumptions.
- Verify logs do not contain PAN or canonical folio values.
- Complete role-based smoke tests for Advisor, Linked Investor, Link Pending,
  and Explorer accounts.

## AI Working Agreement

Every AI engineer must:

1. Read this document first.
2. Read the relevant ADRs and approved sprint documents.
3. Inspect the current architecture and working tree before editing.
4. Preserve established boundaries and avoid unrelated refactors.
5. Explain authorization and migration changes before applying them.
6. Validate proportionately and report what was not executed.
7. Never commit, push, merge, or start the next sprint without explicit user
   authorization.
