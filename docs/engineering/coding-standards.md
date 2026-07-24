# Coding Standards

## Purpose
This document defines Dart, Flutter, SQL, and database coding conventions, comment philosophies, and folder organizations for the Sharan Fincorp repository.

## Scope
Applies to all source code edits, database DDLs, edge functions, and project config updates.

---

## Detailed Guidelines

### 1. Code Style Reference
General coding guidelines (such as color tokens, relative import mappings, and comments preservation) are defined in **[AGENTS.md](../../AGENTS.md)**. All AI agents and developers must prioritize `AGENTS.md` rules.

### 2. Dart & Flutter Conventions
- **Clean Architecture Layers**: Feature code belongs under `lib/features/{domain}/` and must separate concerns: `models` -> `data` (repositories/datasources) -> `application` (services) -> `presentation` (widgets/controllers).
- **Import Rules**: Always use **relative paths** (`../utils/finance.dart`) for files inside the local package. Absolute package imports are forbidden for internal files.
- **Provider State Management**: Use `ChangeNotifierProvider` and consumer widgets. Avoid introducing global singletons or unrelated state packages (e.g. Bloc, Riverpod) without an approved ADR.
- **Constructors**: Prefer formal initializers. Classes exposed to JSON conversions must implement `fromJson` and `toJson` methods.

### 3. SQL & Supabase Conventions
- **Explicit Aliases**: Queries joining tables must use explicit column aliases to prevent name ambiguity.
- **Security Definer RPCs**: Database mutation functions must use `SECURITY DEFINER` and set explicit `search_path = public` to prevent search path hijacking.
- **RLS Enforcements**: Tables must have Row Level Security enabled. Select policies must validate caller ownership using `auth.uid()` and link states.

### 4. Naming Standards
- **Dart Files & Folders**: Lowercase with underscores (`client_dashboard.dart`).
- **Dart Classes**: PascalCase (`ClientDashboard`).
- **SQL Tables & Columns**: Lowercase with underscores (`verification_events`, `request_id`).
- **SQL Functions**: Lowercase with underscores. Private helper functions start with `_` (e.g. `_resolve_candidate`).

### 5. Comment Philosophy
- Preserve all existing docstrings, header blocks, and inline explanations during refactoring.
- Write comments explaining **why** code is written a certain way, not just *what* it does.
