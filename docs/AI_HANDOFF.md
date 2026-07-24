# AI Engineering Handoff Spec

**Mandatory reading before any implementation, review, migration, or release work.** 

This document outlines the current system state, data flow, architecture rules, and handoff checklists for AI engineers. Coding standards and rules are maintained in [AGENTS.md](../AGENTS.md); this document references those guidelines and provides the surrounding technical context.

---

## 1. Current Repository State

- **Current Sprint**: Sprint 5.6A — Advisor Folio Authorization Layer (Completed).
- **Next Planned Scope**: Sprint 5.6B — Advisor Folio Verification UI & Presentation.
- **Current Branch**: `feature/sprint5.3-folio-verification`
- **Current Database Head Migration**: `20260729000002_qualify_folio_lifecycle_updates.sql`.
- **System Health**:
  - Build status: Passing.
  - SQL runtime validation: Passed.
  - Persistent SQL regression suite: Passed.
  - Flutter analysis: Passed (zero new findings).
  - Web browser smoke tests: Passed.

---

## 2. Technical Stack & Local Setup

The system integrates Flutter (Web & Android) with Supabase (Auth, Postgres, Storage, and Edge Functions).

### Local Flutter Launch
The app does **not** load `.env` at startup. You must pass configuration variables explicitly when launching Flutter:

```sh
# Load local env variables into the terminal shell
set -a
source .env
set +a

# Launch Flutter Web
flutter run -d chrome \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
```

---

## 3. Architecture & Data Flow

### Authentication vs. Business Identity
- **Supabase Auth User**: Authentication session provider.
- **Profiles (`profiles`)**: Business investor directory, which can exist *prior* to Auth registration.
- **Investor Account Links (`investor_account_links`)**: Transactional relationship mapping an Auth user to a business profile.
- **Folio Grants (`folio_grants`)**: Explicit folio-level authorization.

```text
Supabase Auth User -> user_accounts -> investor_account_links -> profiles -> portfolios / transactions
```

### Row Level Security (RLS) & RPCs
- Direct table reads/writes from the client are forbidden.
- Repositories call PostgreSQL `SECURITY DEFINER` RPCs to request masked projections.
- Investor RLS policies evaluate `active` link status and `approved` folio grant status at folio scope.

---

## 4. Coding Standards & Guidelines
Refer to [AGENTS.md](../AGENTS.md) for non-negotiable coding conventions, relative import guidelines, folder structures, and the dark theme color palette tokens (`Color(0xFFC9B4BC)` Dusty Rose Gold seed).

---

## 5. Required Validation Before Implementation

Before beginning any implementation task, you **MUST** run the following discovery steps and verify baseline correctness:

1. **Verify Local Database State**:
   Confirm that your local environment is clean and all migrations are applied.
   ```bash
   supabase db reset
   ```
2. **Execute Database Regression Tests**:
   Ensure that RLS policies, Vault cryptography, and RPC contracts are working as expected.
   ```bash
   sh supabase/tests/run_all.sh
   ```
3. **Verify App Code Completes Analysis**:
   Verify that the current codebase builds and analyzes with zero compiler errors.
   ```bash
   flutter analyze
   ```
4. **Execute App Unit & Widget Tests**:
   Ensure all local Flutter tests pass.
   ```bash
   flutter test
   ```

---

## 6. Handoff & Release Checklist

Before marking a task as complete and preparing to commit:

- [ ] **Static Analysis Check**: Run `flutter analyze` and resolve all new warnings or lint issues.
- [ ] **Regression Tests Check**: Verify that `flutter test` and database test suites pass without regressions.
- [ ] **No Code Duplication**: Ensure code changes do not duplicate existing registrar or utility behaviors.
- [ ] **Security Validation**: Confirm that no raw PAN, Vault keys, or canonical identifiers are logged or returned to the browser.
- [ ] **Document Changes**:
  - Update `docs/PROJECT_STATE.md` with milestone accomplishments.
  - Append release details to `docs/changelog/` (if completing a feature).
  - Update `walkthrough.md` with shell logs, test outputs, and validation steps.
- [ ] **Commit Scoping**: Keep commits discrete, atomic, and properly prefixed (e.g. `docs:`, `feat:`, `fix:`).
- [ ] **No Direct Merges**: Push changes to a feature branch (`feature/*`) and request user review; never commit directly to `main`.
