# 06 — Prompt Engineering Standards

## Purpose
This document defines prompt composition guidelines, reusable prompt blocks, quality checklists, and template lifecycles.

## Scope
Applies to system prompts, user-facing instructions, and automated agent orchestration templates.

---

## Detailed Guidelines

### 1. Prompt Standards
Prompts used to invoke coding subagents must prioritize:
- **Role Grounding**: Explicitly state the agent's persona, constraints, and workspace location.
- **Task Isolation**: Keep task scopes narrow. Do not request multiple file edits across unrelated modules in a single step.
- **Formatting Constraints**: Instruct agents to output code changes using standard format structures (e.g. diff blocks or complete replacement scripts).

### 2. Reusable Prompt Template (Planning Phase)
When tasking an agent to compile an implementation plan, use the following structure:
```text
You are the Coder Agent for Sharan Fincorp.
Analyze the target workspace files: [files list].
Identify the modifications required to implement feature: [Feature name].
Write a detailed implementation plan. Do NOT apply changes. Wait for human feedback.
```

### 3. Prompt Quality Checklist
- [ ] Prompt contains the target workspace directory path.
- [ ] Prompt refers to the coding standards in `AGENTS.md`.
- [ ] Prompt explicitly bans raw PII/PAN exposures in logs and return values.
- [ ] Prompt sets narrow boundaries to prevent directory traversal escapes.

---

## References
- [AI Developer Manual (AGENTS.md)](../../AGENTS.md)
- [Review Checklists](../../engineering/review-checklists.md)
