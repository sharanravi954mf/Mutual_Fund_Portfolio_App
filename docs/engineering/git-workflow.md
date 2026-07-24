# Git Workflow

## Purpose
This document defines the branching topologies, pull request guidelines, commit standards, and release tags required to manage code history and branches.

## Scope
Applies to all code repositories, database migrations, and release tags.

---

## Detailed Guidelines

### 1. Branching Strategy
We enforce a structured branch topology:
- **`main`**: Reflects the current stable production environment. Direct commits are forbidden.
- **`feature/{name}`**: Standalone feature development branches (e.g. `feature/analytics`).
- **`release/{version}`**: Pre-release verification tracks used for staging smoke tests.
- **`hotfix/{name}`**: Fast-track branches to resolve critical production bugs.

### 2. Commit Message Standards (Conventional Commits)
Commit prefixes must describe the change type.
```text
<type>(<scope>): <short description>
```
- **`feat`**: Adding a new user capability.
- **`fix`**: Resolving a bug.
- **`docs`**: Documentation updates only (no code).
- **`test`**: Creating or modifying tests.
- **`refactor`**: Reorganizing code without behavioral adjustments.

### 3. Pull Request & Merge Strategy
- **PR Checklists**: Pull requests require passing static checks (`flutter analyze`) and unit tests before review.
- **Review Gate**: At least one human code review is required for features.
- **Merge Method**: Squash commits on merge to keep history flat and clean.

### 4. Version Tagging
Use Semantic Versioning (`vMAJOR.MINOR.PATCH-stage`):
- **Alpha**: `v1.1.0-alpha`
- **Beta**: `v1.2.0-beta`
- **Stable**: `v1.2.0`

---

## References
- [ADR-005 — Require Evidence-Driven Release Workflow](../decisions/ADR-005-Release-Workflow.md)
- [Target Architecture Contract: Section 7](../architecture/ARCHITECTURE.md#7-release-discipline)
