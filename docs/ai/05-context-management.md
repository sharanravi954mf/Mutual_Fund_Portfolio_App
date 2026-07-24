# 05 — Context Management

## Purpose
This document defines context hierarchy guidelines, workspace file grounding rules, session tracking, and prompt histories.

## Scope
Applies to all LLM memory configurations, file context feeds, and agent state preservations.

---

## Detailed Guidelines

### 1. Context Hierarchy

Agents must prioritize context inputs in the following order:

```text
1. Active User Request (Primary objective)
   ↓
2. AGENTS.md (Root-level coding and style rules)
   ↓
3. docs/AI_HANDOFF.md (Sprint progress, branch name, and database head migration)
   ↓
4. Target Architecture & Engineering Handbook (docs/architecture/ and docs/engineering/)
   ↓
5. Workspace Source Code Files (Grounding context)
```

### 2. Session Continuity
- **Progress Tracking**: Agents must maintain `task.md` checklists to persist state across separate chat turns or model invocations.
- **Decision History**: ADR files and the living Decision Register (`decision-register.md`) must be consulted before suggesting layout or schema changes.

### 3. Knowledge Boundaries
Agents must respect security trust boundaries:
- **Sandbox limits**: Do not attempt network API requests outside sandboxed containers.
- **Vault protection**: Do not attempt to log, copy, or expose decrypted database keys or raw PII variables to session summaries.

---

## References
- [Target Architecture Contract: Section 7](../architecture/ARCHITECTURE.md#7-authentication-and-authorization-strategy)
- [AI Engineering Handoff Specs](../AI_HANDOFF.md)
