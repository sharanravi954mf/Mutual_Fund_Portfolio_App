---
name: moneybowl-flutter-finance-ui
description: Build accessible, responsive and trustworthy Flutter financial interfaces using Money Bowl's existing architecture and theme.
---

# Flutter Finance UI Skill

Guidelines for building premium, trustworthy, and accessible financial user interfaces for Money Bowl.

## Core Design Principles
- **Theme & Colors**: Always inspect and reuse the existing dusty-mauve Material 3 `AppTheme` and `AppColors` via `AppThemeColors`. Never hardcode arbitrary hex colors or create global rebrands.
- **Tone**: Maintain a calm, trustworthy, and precise financial aesthetic. Avoid neon accents, excessive gradients, or crypto-trading gamification patterns.
- **Layout Rhythm**: Use an 8-point spacing rhythm. Implement responsive designs supporting compact mobile screens (bottom sheets/modals), tablet, and desktop viewports (centered dialogs or side panels) without overflow at 320px.
- **Light/Dark Parity**: All layouts and text/icon colors must adapt correctly to both dark and light modes.
- **PII & Financial Safety**: Mask sensitive variables (PAN, Phone, Email, Folio numbers) by default. Revealing values is strictly supplementary and subject to server validation.

## Technical Standards
- **Architectural Isolation**: Keep business logic/repositories separate from widgets. Presenters (ChangeNotifier/OrderBloc) must handle all states. Widgets must not call Supabase directly.
- **Formatting**:
  - Format monetary values using Indian rupee notation (`en_IN` locale, symbol `₹`, group by thousands/lakhs/crores).
  - Render financial numbers and values using tabular figures (e.g. `fontFeatures: [FontFeature.tabularFigures()]`) where practical to avoid alignments shifting.
- **Loading & State Parity**: Explicitly implement polished visual states for:
  - Reference data loading/lookups.
  - Empty lists (e.g. no folios, no assigned clients).
  - Validation failures (use clear helper texts, not just colors).
  - Submitting, Success, and Recovery Failure screens.
- **Accessibility**: Support large text scales (no clipped text), ensure minimum tap targets of 44x44, provide clear screen-reader/semantics annotations, and support full keyboard navigation.
- **Verification**: Write focused widget tests verifying compact/desktop widths, text scales, loading/success states, and error handling. Validate against clean web build.

## Detailed Finance Component Rules

### 1. Server-Authorised Data Sources
* All data loaded by the forms/modals must come strictly from server-authorised queries.
* Query active workspace memberships using `workspace_memberships` table, filtering by active roles and active statuses.
* Do not rely on local client role assertions or mock tables unless schema-verified.

### 2. Fail-Closed PII Rendering
* All sensitive user properties (PAN, emails, phones, folio numbers) must pass through a strict, fail-closed masking engine.
* If a string is malformed or shorter than expected, it must return a fully masked placeholder rather than letting raw characters bypass.

### 3. Financial-Intent Preservation
* Never drop or omit user inputs. In Buy, Sell, and Switch, all choices (source, destination, folio, amount or units, workspace, initiator) must be preserved in the `OrderState`.
* If a database table column is missing in the database contract (such as folio references and switch destination schemes on `order_requests`), the transaction must be blocked from submission with a clear explanation, rather than submitted as a lossy or incomplete order.

### 4. Source Holdings versus Scheme Universe
* For **Sell** and **Switch** transactions, source schemes must be filtered to show only schemes currently held in the client's folio (computed dynamically via unit ledgers).
* For **Buy** transactions and the destination scheme of **Switch** transactions, schemes may be selected from the entire eligible scheme universe. Use a debounced, searchable selector to avoid loading massive tables at once.

### 5. Typed Loading, Empty, and Error States
* Business state presenters must use a strongly typed enum state machine (such as `OrderPhase`) to distinguish between `loading`, `ready`, `emptyInvestors`, `emptyFolios`, `emptyHoldings`, `accessDenied`, `offline`, and `failure`.
* Present a polished, contextual view for each phase to make the application feel alive and responsive.

### 6. Evidence and Quality Controls
* Validate components against a wide range of test cases.
* Ensure code passes formatting (`dart format`) and static analysis (`flutter analyze`) with zero new issues.
* Verify responsiveness and alignment at both 320px and desktop resolutions, as well as text scale variations. Provide screenshots or widget tests as proof of compliance.
