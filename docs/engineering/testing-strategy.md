# Testing Strategy

## Purpose
This document outlines the testing methodologies, test types, automation frameworks, and verification gates required to assure software quality and security.

## Scope
Includes Dart unit/widget tests, local integration tests, pgTAP database tests, and manual staging checklists.

---

## Detailed Guidelines

### 1. Database-Level Testing (Supabase / pgTAP)
RLS policies, schema migrations, and SQL procedures are validated using the pgTAP testing suite.
- **Location**: `supabase/tests/`
- **Execution**: Run database reset and tests inside local Docker container runtimes.
  ```bash
  supabase db reset
  sh supabase/tests/run_all.sh
  ```
- **Mandate**: Every mutation, RLS policy modification, or Vault retrieval function must have matching test coverage verifying both success and unauthorized denial paths.

### 2. Client-Side Testing (Flutter & Dart)
- **Unit Tests**: Expose DTO mappings, models, and calculation utilities. Expose to `package:test` rules under the `test/` folder.
  ```bash
  flutter test test/utils/finance_test.dart
  ```
- **Widget Tests**: Target component rendering, layout constraints, and controller triggers using `WidgetTester`.
- **Integration Tests**: Automate UI interactions using `integration_test` packages. Runs browser/device automation.

### 3. Regression Testing & Manual QA
- **Walkthrough updates**: Verification steps, command logs, and test results must be appended to the root `walkthrough.md` file before PR merge.
- **Role-Based Smoke Tests**: Perform manual validation for each user persona (Advisor, Linked Investor, Link Pending, Explorer) in the staging environment.

---

## References
- [Target Architecture Contract: Section 20](../architecture/ARCHITECTURE.md#20-validation-plan)
- [AI Engineering Handoff: Section 5](../AI_HANDOFF.md#5-required-validation-before-implementation)
