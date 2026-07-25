# 08 — AI Quality Assurance

## Purpose
This document defines validation strategies, hallucination preventions, cross-agent review guidelines, and repository grounding checks.

## Scope
Applies to all code edits compiled by LLM runtimes, tests verifications, and automated PR review checks.

---

## Detailed Guidelines

### 1. Hallucination Prevention & Grounding
AI agents are prohibited from making unverified assumptions about files, functions, or database structures.
- **Rules**:
  - Always search the workspace paths (`grep_search` or `list_dir`) before referencing imports or symbols.
  - Every plan must provide clickable relative file path links matching actual codebase locations.

### 2. Validation & Testing Strategy
- **Compiler Validation**: Every change must compile with zero new compiler warnings or errors.
- **Database Test Isolation**: New database functions must run matching pgTAP scripts verifying target execution and RLS denial paths.

### 3. Cross-Agent Code Reviews
Future review workflows will utilize isolated subagents to audit PRs:
1. **Audit Agent**: Checks coding conventions against `AGENTS.md` guidelines.
2. **Security Agent**: Scans database schemas for RLS policy omissions or Vault access holes.

### 4. Conflict Resolution
If different coding agents suggest conflicting edits (e.g. nested brackets vs. clean file splits), the implementation falls back to the relative layer mapping guidelines defined in [AGENTS.md](../../AGENTS.md). The human Lead Developer resolves any remaining conflicts.

---

## References
- [Testing Strategy](../engineering/testing-strategy.md)
- [Review Checklists](../engineering/review-checklists.md)
