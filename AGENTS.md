# Sharan Fincorp - AI Operating Manual (AGENTS.md)

Welcome to the development manual for **Sharan Fincorp**, a premium, responsive Mutual Fund Portfolio Tracker designed for Web (Desktop) and Android (Mobile) platforms.

This file provides system instructions, coding standards, and guidelines for AI developers working on this codebase.

---

## 1. Project Overview & Tech Stack

### Project Overview
Sharan Fincorp allows clients to track their mutual fund portfolios, view transaction histories, analyze absolute and annualized returns (XIRR), and monitors advisor ingestion operations.

### Tech Stack
* **Framework**: Flutter (Channel stable, target SDK `^3.0.0`)
* **Language**: Dart (SDK `^3.0.0`)
* **State Management**: Provider (`^6.1.2`)
* **Database & Auth**: Supabase (`supabase_flutter ^2.6.0`)
* **Typography**: Google Fonts (`google_fonts ^6.2.1`)
* **Formatting**: Intl (`intl ^0.19.0`)
* **Backend Ingestion**: Supabase Edge Functions (Deno / TypeScript)

---

## 2. Folder Architecture & Ownership

```text
├── lib/
│   ├── main.dart            # Application root wrapper and router
│   ├── providers/           # ChangeNotifier states (auth, session)
│   ├── screens/             # UI Layouts & Dashboard Views
│   ├── services/            # Supabase API client connection bindings
│   └── utils/               # Analytics calculators (XIRR, Absolute Return)
├── supabase/
│   ├── migrations/          # PostgreSQL schemas, functions, and RLS policies
│   └── functions/           # Edge Functions for RTA Statement Ingestion
├── web/                     # Web assets (index.html, manifest.json)
└── docs/                    # Technical specifications and logs
```

---

## 3. Coding Standards & Best Practices

1. **Responsiveness First**: Every UI layout must scale dynamically between:
   - Mobile Viewports (Android): Compact vertical lists, 2x2 metric grids.
   - Widescreen Viewports (Web): Multi-column layouts, expanded Rows, persistent sidebars.
2. **Design System Consistency**: Use the custom dark theme color palette:
   - Primary: `Color(0xFFE94057)` (Crimson Red)
   - Secondary: `Color(0xFF8A2387)` (Indigo Purple)
   - Background: `Color(0xFF0F0C20)` (Deep Space Blue)
   - Surface: `Color(0xFF151030)` (Rich Violet)
   - Accents: `Color(0xFFF27121)` (Glowing Orange)
3. **No Unnecessary Dependencies**: Leverage native Flutter drawing tools (like `CustomPainter` or standard layout combinations) rather than importing heavy external rendering libraries.
4. **Clean Imports**: Use relative paths (`../utils/finance.dart`) for local files inside the package rather than absolute package paths.
5. **Documentation Integrity**: Retain all docstrings and structural comments during refactoring.

---

## 4. Git Workflow & Review Checklist

### Branching Model
- Build on standalone feature branches (e.g., `feature/analytics`) off the `main` branch.
- Avoid modifying code directly in `main`.

### Pre-Commit Checklist
Before submitting a pull request, you must run:
1. `flutter analyze` - code must compile cleanly with 0 errors.
2. `flutter test` - all tests must pass.
3. Update `walkthrough.md` with visual progress, descriptions, and verification logs.
4. Update appropriate files under `docs/` detailing the feature changes.

---

## 5. Documentation Guidelines

Every implemented feature must update the relevant document inside the `docs/` folder:
- **Architecture**: Update `docs/architecture/` if database schemas, API structures, or folder layouts change.
- **Features**: Update `docs/features/` with instructions, metrics, and functional specifications of the feature.
- **Decisions**: Log design choices and framework decisions in `docs/decisions/`.
- **Changelog**: Append concise records of the release changes to `docs/changelog/`.
