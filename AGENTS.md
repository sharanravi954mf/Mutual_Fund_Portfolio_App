# Money Bowl Agent Routing

## Canonical documents

- `docs/PROJECT_STATE.md`
- `docs/CHANGELOG.md`
- `docs/business/BRD.md`
- `docs/architecture/SYSTEM_ARCHITECTURE.md`
- `docs/sprints/Sprint-6.1.md`

Read only the sections relevant to the current GitHub issue. Do not
repeatedly load every canonical document in full.

## Available project skills

- `moneybowl-implementation`
  - Implementation workflow for one GitHub issue.
  - Primarily used by Codex.
- `moneybowl-independent-qa`
  - Independent testing and merge workflow for a ChatGPT-reviewed PR.
  - Primarily used by Antigravity/YAI.
- `moneybowl-supabase-security`
  - Database, migration, RPC, RLS, authorisation and audit requirements.
  - Used by either agent whenever Supabase/PostgreSQL security is involved.

## Roles

- Codex is the implementation agent.
- Codex creates code, tests, commits and PRs.
- Codex never merges a product PR or closes its issue.
- ChatGPT performs architecture and security review.
- Antigravity/YAI independently validates the reviewed commit.
- YAI merges only after ChatGPT PASS and independent QA success.
- Ravi is the business owner and final escalation authority.

## Repository safety

- Only one agent may edit or run Git commands in the shared repository
  directory at a time.
- Work on exactly one GitHub issue at a time.
- Branch from the latest `origin/develop`.
- Never commit product changes directly to `develop` or `main`.
- Never rewrite an existing applied migration.
- Never silently delete or modify financial records.
- Never weaken CI merely to make a check pass.
- Do not create duplicate GitHub Project cards.
- Local planning files such as `task.md` and `walkthrough.md` must not
  be committed.
- Detailed procedures live in project skills and should not be copied
  into every prompt.
