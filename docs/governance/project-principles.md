# Project Principles

## Purpose
This document defines the core product, engineering, and architectural principles that govern the Moneyball platform.

## Scope
Applies to all design decisions, feature proposals, coding standards, and developer/agent workflows.

---

## Detailed Guidelines

### Core Principles

1. **Documentation First**
   - System specifications, roadmaps, and plans must be documented *prior* to implementation. The repository is the single source of truth for the product.

2. **Architecture Before Code**
   - Architectural boundaries, database schemas, and API routes must be formally defined (via ADRs) and approved before writing production code.

3. **AI Assists, Humans Approve**
   - AI coding agents automate research, planning, writing, and validation tests. However, a human developer/architect holds the ultimate review and merge authority.

4. **Security by Default (Zero Trust)**
   - RLS is enabled on all tables. Public access is rejected. Security gates are enforced at the database layer, not just in UI code.

5. **No Direct Production Changes**
   - Code modifications must progress through staging and pre-release gates. Direct edits to database schemas or live files are forbidden.

6. **Evidence-Based Decisions**
   - System updates require verified test run outputs, pgTAP logs, or compile results documented in the walkthrough before deployment sign-off.

7. **Single Source of Truth**
   - Eliminate documentation duplication. If a standard is already described, link to it directly instead of copying the content.

---

## References
- [Target Architecture Contract](../architecture/ARCHITECTURE.md)
- [ADR-005 — Require Evidence-Driven Release Workflow](../decisions/ADR-005-Release-Workflow.md)
