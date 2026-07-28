---
name: moneybowl-implementation
description: Implement one Money Bowl GitHub issue from Sprint Backlog through a tested pull request to develop. Use for feature, fix, Flutter, Supabase, migration, CI, test, or documentation implementation assigned to Codex. This workflow never merges the PR or closes the issue.
---

# Money Bowl Implementation

## Required input

A GitHub issue number.

## Goal

Implement exactly one issue and produce a focused, tested PR targeting
`develop`.

## Workflow

1. Confirm repository path, branch and clean working tree.
2. Fetch origin and update local `develop` using fast-forward only.
3. Read the live GitHub issue and current acceptance criteria.
4. Read only relevant canonical-document sections.
5. Inspect current code, schemas and migrations before assuming an object
   is absent or must be created.
6. Claim the existing GitHub Project card:
   - Implementation Owner: `CDX — Codex`
   - Status: Sprint Backlog or Review → In Progress
   If the primary GitHub connector cannot update Issues or Project fields,
   use an already-authenticated GitHub CLI or connected MCP fallback where
   supported. Do not skip the update silently. If no authorised write path
   is available, report the limitation and do not claim that the board was
   updated.
7. Create or reuse:
   - `feature/issue-<number>-<short-name>`, or
   - `fix/issue-<number>-<short-name>`
8. Implement the smallest coherent change satisfying the issue.
9. Never rewrite applied migrations. Add the next corrective migration.
10. Add focused positive and negative tests.
11. Run tests relevant to every changed area.
12. Run documentation and commit validators.
13. Update only the current issue entry in `Sprint-6.1.md`.
14. Commit using Conventional Commits.
15. Push the branch and open one PR targeting `develop`.
16. Link the issue using `Closes #<number>` where appropriate.
17. Move the existing Project card to Review.
18. Keep the issue open.
19. Stop and report:
    - branch
    - commit SHA
    - PR number
    - changed files
    - tests run and results
    - baseline warnings
    - unresolved concerns

## Restrictions

- Do not merge.
- Do not close the issue.
- Do not move the card to Testing or Done.
- Do not begin another issue.
- Do not repeatedly analyse the entire repository.
- Do not change unrelated files merely to make CI green.
- Do not create local planning files inside the repository.
