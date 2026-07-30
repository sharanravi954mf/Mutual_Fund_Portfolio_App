# Flutter Finance UI Skill

Guidelines for building premium, trustworthy, and accessible financial user interfaces for Money Bowl.

## Core Design Principles
- **Theme & Colors**: Always inspect and reuse the existing dusty-mauve Material 3 `AppTheme` and `AppColors` via `AppThemeColors`. Never hardcode arbitrary hex colors or create global rebrands.
- **Tone**: Maintain a calm, trustworthy, and precise financial aesthetic. Avoid neon accents, excessive gradients, or crypto-trading gamification patterns.
- **Layout Rhythm**: Use an 8-point spacing rhythm. Implement responsive designs supporting compact mobile screens (bottom sheets/modals), tablet, and desktop viewports (centered dialogs or side panels) without overflow at 320px.
- **Light/Dark Parity**: All layouts and text/icon colors must adapt correctly to both dark and light modes.
- **PII & Financial Safety**: Mask sensitive variables (PAN, Phone, Email, Folio numbers) by default. Revealing values is strictly supplementary and subject to server validation.

## Technical Standards
- **Architectural Isolation**: Keep business logic/repositories separate from widgets. Presenters (ChangerNotifier/OrderBloc) must handle all states. Widgets must not call Supabase directly.
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
