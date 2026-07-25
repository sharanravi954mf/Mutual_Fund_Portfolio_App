# Documentation Quality Gates & Workflows

## Purpose
This document details the automated repository checks, validations, and local scripts used to enforce documentation quality, folder structures, and relative link integrity.

## Scope
Applies to all markdown documents (`.md` files) across the workspace and sub-directories.

---

## Detailed Guidelines

### 1. Automated Workflow
The repository executes a GitHub Actions workflow on every push or pull request to validation branches:
- **Location**: `.github/workflows/documentation-quality.yml`
- **Runner**: `ubuntu-latest`
- **Python Setup**: Configures Python 3.10 to run the custom validation suite.

---

### 2. Validation Rules

Our automated validator (`.github/scripts/validate_docs.py`) validates:
1. **Directory Integrity**: Confirms that all core folders (`docs/product/`, `docs/architecture/`, `docs/engineering/`, `docs/governance/`, `docs/ai/`, `docs/audit/`) exist.
2. **UTF-8 Encoding**: Checks that all markdown files can be read as valid UTF-8.
3. **Internal & Sibling Links**: Scans all `[text](link)` structures and verifies that target files exist locally relative to the file.
4. **Mermaid Closures**: Ensures all ` ```mermaid ` segments have corresponding closing ` ``` ` markers.

---

### 3. How to Run Locally

You must execute validation checks locally before submitting any pull request:
```bash
python3 .github/scripts/validate_docs.py
```

---

### 4. Common Failures & Troubleshooting
- **UnicodeDecodeError**:
  - *Cause*: A file contains characters that cannot be decoded as UTF-8 (e.g. legacy Windows encoding).
  - *Remediation*: Re-save the file using UTF-8 encoding in your editor.
- **Broken Link Error**:
  - *Cause*: An index path, cross-reference link, or file link has a typo or incorrect traversal sequences (`../../` instead of `../`).
  - *Remediation*: Check the relative path of the target file from the current file and fix the path.
- **Unclosed Mermaid block**:
  - *Cause*: A code block is missing the closing fence.
  - *Remediation*: Append ` ``` ` to close the block.

---

## References
- [Documentation Standards](../docs/engineering/documentation-standards.md)
- [Definition of Done](../docs/engineering/definition-of-done.md)
