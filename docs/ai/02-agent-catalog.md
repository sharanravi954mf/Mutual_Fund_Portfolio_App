# 02 — AI Agent Catalog

## Purpose
This document catalogs the active and future AI actors participating in development, detailing their strengths, limitations, inputs, outputs, and authority boundaries.

## Scope
Includes LLM generation runtimes, coder subagents, and automated review assistants.

---

## Detailed Guidelines

### 1. Antigravity Agent Engine (Parent Coordinator)
- **Purpose**: Oversees planning, task delegation, and execution loops.
- **Strengths**: Excels at context management, tool invocation, and multi-agent coordination.
- **Limitations**: Relies on specific model weights; context window limit bounds scope.
- **Authority**: High read authority, sandbox execute, plan creation. Denied direct merge to `main`.
- **Inputs**: Task constraints, user goals, workspace files.
- **Outputs**: Implementation plans, subagent invocations, validation results.
- **Success Criteria**: Passes Definition of Done without manual hotfixes.

### 2. ChatGPT / Codex (Coder Subagents)
- **Purpose**: Inline file adjustments, feature implementations, and test drafting.
- **Strengths**: Deep coding domain knowledge, syntax accuracy.
- **Limitations**: Prone to context leaks if directories are too large.
- **Authority**: Sandbox write permission on feature paths. Denied edits to system-level tables.
- **Inputs**: Targeted code blocks, ADR specifications.
- **Outputs**: Code edits, diff blocks.

### 3. BAI (Business Analytics & Ingestion Auditor)
- **Purpose**: Verification of registrar parser logic.
- **Strengths**: Math calculations, tabular structures.
- **Limitations**: No UI layout rendering.
- **Inputs**: CAMS/KFintech DBF schema, parser tests.
- **Outputs**: Ingestion logic reviews.

### 4. Future AI Agents
- **Reviewer Agent**: Automatically comments on PR code style violations.
- **Compliance Agent**: Performs real-time checks on database RLS and Vault configurations.

---

## References
- [Repository Governance](../governance/repository-governance.md)
