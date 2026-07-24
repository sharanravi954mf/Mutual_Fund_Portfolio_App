# Review Checklists

## Purpose
This document provides specific code and release checklist templates customized for Developers, AI agents, Reviewers, Architects, and Release Managers.

## Scope
Applies to all pull requests, code reviews, architecture validations, and release sign-offs.

---

## Detailed Checklists

### 1. Developer Checklist (Human)
- [ ] Code complies with clean architecture layers (`models -> data -> application -> presentation`).
- [ ] Imports are relative; no absolute package imports are used for internal files.
- [ ] No raw PAN or unmasked folio details are output to console logs.
- [ ] Local tests (`flutter test`) pass cleanly.

### 2. AI Agent Checklist
- [ ] Read [AGENTS.md](../../AGENTS.md) first before editing.
- [ ] Draft an implementation plan and wait for human approval before modifying code.
- [ ] Update `task.md` checklists and document outputs in `walkthrough.md`.
- [ ] Ensure existing warnings or comments are not deleted during file updates.

### 3. Code Reviewer Checklist
- [ ] Verify RLS is enabled on new tables and check that select policies check link ownership.
- [ ] Verify that stored procedures updating sensitive fields implement `SECURITY DEFINER`.
- [ ] Inspect new feature files for proper error mappings and response codes.
- [ ] Check that unit test coverage is present for new helper logic.

### 4. Technical Architect Checklist
- [ ] Review proposed changes against target architecture contracts.
- [ ] Approve new database Vault key integrations and KMS backup strategies.
- [ ] Verify that lock orders (`FOR UPDATE`) on tables prevent deadlock risks.
- [ ] Approve modifications that impact authentication/onboarding lifecycles.

### 5. Release Manager Checklist
- [ ] Verify that database migrations deploy cleanly on staging sandboxes.
- [ ] Check that release tags match semantic conventions.
- [ ] Confirm that `CHANGELOG.md` reflects completed changes.
- [ ] Confirm rollback procedures are active on static CDN hosting.
