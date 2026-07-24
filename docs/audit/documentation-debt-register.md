# Documentation Debt Register

## Purpose
This document logs all genuine documentation debt, path errors, and naming inconsistencies identified during audits, along with their resolution status.

## Scope
Includes all documentation folders, file indices, and root README links.

---

## Detailed Guidelines

| ID | Issue Description | Severity | Category | Location | Recommendation | Owner | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **DEBT-001** | AIOS files referenced sibling directories using `../../` instead of `../`. | Low | Path Error | `docs/ai/*.md` | Update references to use single parent folder traverse. | Technical Lead | **Resolved** |
| **DEBT-002** | Root index in `docs/README.md` used `../../` for `.github/` folder links instead of `../`. | Low | Path Error | `docs/README.md` | Re-align traverse steps. | Technical Lead | **Resolved** |

*All identified documentation debt has been resolved as part of the certification process.*

---

## References
- [Documentation Certification Report](documentation-certification-report.md)
