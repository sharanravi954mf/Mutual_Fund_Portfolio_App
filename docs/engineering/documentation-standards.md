# Documentation Standards

## Purpose
This document defines file organizations, markdown conventions, cross-links, and version history standards for all repository documentation.

## Scope
Applies to roadmaps, changelogs, architecture designs, features, and engineering handbook guides.

---

## Detailed Guidelines

### 1. File Formatting & Markdown
- **Headers**: Maintain a clean heading hierarchy (single `#` for page title, `##` for primary sections, `###` for sub-sections).
- **Line Lengths**: Keep paragraphs concise to prevent excessive wrapping on desktop views.
- **Alert Blocks**: Use standard alert prefixes (e.g. `> [!IMPORTANT]`, `> [!NOTE]`) for critical highlights.

### 2. Navigation & Cross-Linking
- **Relative Linking**: Link files using absolute file URI links relative to the file:
  - Good: `[ADR-003](../decisions/ADR-003-PAN-Verification.md)`
  - Bad: `[ADR-003](/decisions/ADR-003-PAN-Verification.md)`
- **Symbol Referencing**: Provide clickable links pointing to specific source code symbols or file lines wherever possible.

### 3. Visuals & Mermaid Diagrams
- **Mermaid Usage**: Visualize flowcharts, state transitions, and class models. Quote node labels containing brackets or special characters to prevent parser breaks.

### 4. Version History (Changelog Updates)
- Every release or major sprint milestone must log a concise entry inside the root `CHANGELOG.md`. Detailed release specs are saved in sub-folders under `docs/changelog/`.

---

## References
- [Target Architecture Contract: Section 5](../architecture/ARCHITECTURE.md#5-documentation-guidelines)
