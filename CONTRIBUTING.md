# Contributing to Sharan Fincorp

Welcome! This guide outlines the development lifecycle, branch rules, AI coding assistance protocols, and code review criteria required to contribute to the Sharan Fincorp (Moneyball) repository.

---

## 1. Repository Philosophy
Sharan Fincorp is a standards-driven engineering platform. We prioritize security, data masking, and complete test verification before any code merges to production tracks.

---

## 2. Developer Lifecycle

```text
Draft Proposal / Issue → Write Plan (high-risk) → Code in Sandbox → Run Tests → PR Code Review → Staging Validation → Squash & Merge
```

- **Branching Strategy**: Branch from `main` using `feature/` (e.g. `feature/analytics`), `hotfix/`, or `release/` prefixes.
- **Commit Messages**: Enforce Conventional Commits (e.g. `feat(analytics): add xirr curves`, `fix(signer): resolve coordinates`).
- **PR approvals**: Pull requests require passing static analysis (`flutter analyze`), unit tests, database resets, and a peer developer review before merging.

---

## 3. AI-Assisted Development Workflow
All AI coding agents must:
1. Read the rules engine guidelines in **[AGENTS.md](AGENTS.md)**.
2. Formulate an `implementation_plan.md` in the active workspace and wait for human Chief Architect sign-off before applying code modifications.
3. Track progress inside `task.md` and append verification run logs (deno tests, local builds) to `walkthrough.md`.

---

## 4. Documentation Libraries

Before writing code, review the specific standards in our documentation libraries:
- 🎯 **[Product vision & Persona Guides](docs/product/README.md)**: Target user stories, domain models, and business capability specifications.
- ⚙️ **[Target Architecture Contract](docs/architecture.md)**: Data schemas, RLS rules, deployment models, and security boundaries.
- 💻 **[Engineering Handbook](docs/engineering/README.md)**: Coding conventions, API formats, and Definition of Done checks.
- ⚖️ **[Governance Framework](docs/governance/README.md)**: Living decision registers, change risk assessments, and risk registers.
