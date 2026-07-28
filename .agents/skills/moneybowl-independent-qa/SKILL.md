---
name: moneybowl-independent-qa
description: Independently validate a ChatGPT-reviewed Money Bowl pull request at an exact commit SHA, run relevant regression and security tests, manage Review to Testing, and merge to develop only after all required checks pass. Use for Antigravity or YAI QA handoffs.
---

# Money Bowl Independent QA

## Required inputs

- GitHub issue number
- Pull request number
- ChatGPT-reviewed commit SHA

## Goal

Independently test the exact reviewed commit. Do not trust the
implementation agent's reported test results without rerunning them.

## Start

1. Confirm no other agent is editing the repository.
2. Fetch origin and switch to the PR branch.
3. Require a clean working tree.
4. Confirm `HEAD` exactly equals the reviewed SHA.
5. Stop when the SHA differs.
6. Move the existing Project card:
   - Review → Testing
   If the primary GitHub connector cannot update Issues or Project fields,
   use an already-authenticated GitHub CLI or connected MCP fallback where
   supported. Do not skip the update silently. If no authorised write path
   is available, report the limitation and do not claim that the board was
   updated.
7. Verify changed-file scope and acceptance criteria.
8. Run documentation and commit validators.
9. Run all relevant database, Flutter, service and integration tests.
10. For database work, apply `moneybowl-supabase-security`.
11. Verify GitHub checks.
12. Do not edit implementation during the initial validation pass.

## Failure workflow

- Do not merge.
- Add exact reproduction evidence to the PR.
- Include command, expected result and actual result.
- Move Testing → In Progress.
- Return Implementation Owner to `CDX — Codex`.
- Keep the same PR and branch.
- Keep the issue open.
- Require ChatGPT re-review after the fix commit.

## Success workflow

- Merge only into `develop`.
- Use the repository's established merge method.
- Confirm the merge commit exists remotely.
- Close the issue as Completed if GitHub does not close it.
- Move Testing → Done.
- Keep Sprint 6.1 itself in progress.
- Do not mark another issue complete.
- Add durable validation evidence to the PR or issue.
- Do not automatically start the next issue.

## Restrictions

- Do not commit `task.md`, `walkthrough.md`, or private planning files.
- Do not apply migrations to production or shared remote environments
  without Ravi's approval.
- Distinguish pre-existing warnings from new PR-specific failures.
- Do not merge when the reviewed SHA has changed.
