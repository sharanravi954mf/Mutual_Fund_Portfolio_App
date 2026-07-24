# 01 — AI Operating Model

## Purpose
This document establishes the fundamental philosophy, goals, and guiding principles of AI collaboration on the Moneyball platform.

## Objectives
- Standardize AI agent behaviors to match repository engineering patterns.
- Secure operations using human approval gates.
- Maximize developer velocity without compromising code quality.

---

## Detailed Guidelines

### Guiding Principles
1. **AI Assists, Humans Approve**: AI agents possess research, drafting, and testing capabilities, but lack direct production merge or write authorization.
2. **Grounding Over Hallucination**: Every agent response or proposal must be grounded in the active codebase files. Unverified assumptions are rejected.
3. **Traceability**: All agent runs, test executions, and command outputs must be appended to audit files (e.g. `walkthrough.md`).

### Human-in-the-Loop Philosophy
We treat the human Chief Architect as the final system authority. Any modification to security policies, database schemas, or business APIs must obtain explicit human confirmation before merging.

### AI-First Engineering Philosophy
We structure files, tasks, and documentation to be easily parsed and edited by LLM agents. Features are mapped to discrete tasks, and directories follow strict clean architecture layers.

---

## References
- [Project Principles](../../governance/project-principles.md)
- [Repository Governance](../../governance/repository-governance.md)
