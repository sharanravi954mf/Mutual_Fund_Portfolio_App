# Definition of Done (DoD)

## Purpose
This document defines the strict quality check gates required to mark features, sprints, or releases as completed and deployment-ready.

## Scope
Applies to all pull requests, feature merges, and staging updates.

---

## Detailed Guidelines

A feature is considered **Done** only when it satisfies all of the following requirements:

### 1. Coding Complete
- Code compiles cleanly with zero compilation errors.
- Runs without introducing new static analysis warnings (`flutter analyze` output is clean).
- Follows the relative imports and M3 design token guidelines defined in [AGENTS.md](../../AGENTS.md).
- Code formats match standard rules (`dart format`).

### 2. Testing Complete
- All existing unit, widget, and database regression tests pass.
- New capability files have corresponding unit test coverage (verifying positive and negative paths).
- Staging role checks (Advisor, Linked Investor, Explorer) are verified and logged.

### 3. Documentation Complete
- Root `CHANGELOG.md` is updated with release entries.
- Active sprint state maps are updated in `docs/PROJECT_STATE.md`.
- Validation command logs and shell outputs are appended to `walkthrough.md`.

### 4. Code Review Complete
- At least one human code review is performed on the pull request.
- All feedback comments are resolved.

### 5. Deployment Ready
- Database migration DDL scripts compile cleanly during local resets.
- Edge Functions deploy successfully on staging servers without syntax or import errors.
