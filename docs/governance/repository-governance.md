# Repository Governance

## Purpose
This document defines ownership roles, approval authorities, code checkout limits, and contribution boundaries across all platform domains.

## Scope
Applies to code folders, documentation directories, deployment setups, and release managers.

---

## Detailed Guidelines

### 1. Ownership & Roles

We enforce a strict division of ownership domains:

- **Repository Owner (Distributor)**: Retains ultimate governance authority over database secrets, project access lists, and billing tiers.
- **Chief Technical Architect**: Owns the system layout, schema migrations, and Row Level Security (RLS) configurations. Changes to `supabase/migrations/` require their explicit sign-off.
- **Product Architect**: Owns features catalog, customer personas, user journeys, and glossary definitions.
- **Software Engineering Lead**: Owns code implementations, folders conventions, lints checks, and test strategies.
- **AI Coding Agents**: Operate as **contributors** under sandboxed tool permissions. Agents possess zero direct merge authority on main branches.

### 2. Approval Authorities Matrix

| Activity | Proposer | Reviewer | Approver |
| :--- | :--- | :--- | :--- |
| **Database Migrations** | Developer / Agent | Lead Developer | Technical Architect |
| **API / Routing Updates** | Developer / Agent | Lead Developer | Technical Architect |
| **Product Capability Shifts**| Product Manager | Product Architect | Project Owner |
| **Code Commits (PR Merge)** | Developer / Agent | Lead Developer | Release Manager |

---

## References
- [Git Workflow](../engineering/git-workflow.md)
- [Review Checklists](../engineering/review-checklists.md)
