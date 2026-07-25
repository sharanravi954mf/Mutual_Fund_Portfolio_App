# Commit Quality Gates & Formats

## Purpose
This document details the Conventional Commits specifications, PR title rules, and local verification git hooks used to enforce commit history quality across the platform.

## Scope
Applies to all git commits, pull request titles, and branch integrations.

---

## Detailed Guidelines

### 1. Accepted Commit Formats

All commit messages and Pull Request titles must follow the **Conventional Commits** specification:

```text
<type>(<scope>): <subject>
```

#### Allowed Types
- **`feat`**: A new user capability or feature.
- **`fix`**: A bug resolution or patch.
- **`docs`**: Documentation updates (no application code modified).
- **`refactor`**: Code changes that neither fix a bug nor add a feature.
- **`perf`**: A code change that improves execution speed or resources.
- **`style`**: Markup, styling, or formatting adjustments (no logic change).
- **`test`**: Creating or updating test suites.
- **`build`**: Modifications impacting build scripts or dependency versions.
- **`ci`**: Edits to GitHub Action files or validation scripts.
- **`chore`**: Maintenance tasks or housekeeping.
- **`revert`**: Reverting a previous commit.

---

### 2. Examples

- **Valid Feature Commit**: `feat(auth): separate login identity from investor profiles`
- **Valid Fix Commit**: `fix(signer): adjust coordinate padding on A4 templates`
- **Valid CI Commit**: `ci: add documentation quality validation workflow`
- **Invalid Format (Fails Check)**: `fixed the bug on screen` (missing type prefix and colon).
- **Invalid Type (Fails Check)**: `re-arrange(ui): move panels` (`re-arrange` is not an allowed type).

---

### 3. Local Validation Guidance

You must validate your commit messages locally before pushing changes. To test a specific message:
```bash
python3 .github/scripts/validate_commits.py "feat(auth): validate tokens"
```

To audit your last 5 commits:
```bash
python3 .github/scripts/validate_commits.py
```

#### Git Hook Integration
You can automate this check by adding a git `commit-msg` hook:
Create `.git/hooks/commit-msg`:
```bash
#!/bin/sh
python3 .github/scripts/validate_commits.py "$(cat "$1")"
```
Make the hook executable:
```bash
chmod +x .git/hooks/commit-msg
```

---

## References
- [Git Workflow](../docs/engineering/git-workflow.md)
- [Repository Contributor Guide](../CONTRIBUTING.md)
