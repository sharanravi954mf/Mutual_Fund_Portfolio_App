# Changelog: Light Mode Theme Redesign

## Version Release: Premium Light Mode Design System

### Summary of Changes
Refactored the Light Mode Theme across Sharan Fincorp to introduce a modern, high-contrast visual language inspired by Zerodha, Groww, CRED, Stripe Dashboard, and Mercury Bank.

### Added
- **Design Token System (`lib/theme/`)**:
  - `app_colors.dart`: Standardized Light Palette (`#F8F6F2` canvas, `#FFFFFF` cards, `#F2EEE7` sidebar, `#2563EB` Royal Blue primary, `#1F2937` primary text, `#6B7280` secondary text, `#E5E7EB` dividers, `#22C55E` success, `#16A34A` profit).
  - `app_spacing.dart`: 8px spacing grid tokens (`xs` through `xxl`).
  - `app_radius.dart`: Strict border radius system (`card: 12px`, `button: 10px`, `input: 8px`).
  - `app_shadows.dart`: Soft ambient elevation shadows replacing heavy dark overlays.
  - `app_text_styles.dart`: High-contrast Outfit/Inter typography hierarchy.
  - `app_theme.dart`: ThemeData builders for Light & Dark modes.
- **Documentation**:
  - Created `docs/design-system.md` detailing design tokens, component rules, and WCAG AA accessibility decisions.

### Changed
- **`lib/providers/theme_provider.dart`**:
  - Bound `AppThemeColors` to the new `AppColors` token system.
- **`lib/main.dart`**:
  - Applied `AppTheme.lightTheme` and `AppTheme.darkTheme` to `MaterialApp`.
- **`lib/screens/login_screen.dart`**:
  - Refactored authentication form container to 12px radius with soft elevation, `#FFFFFF` card background, 8px input radius with `#2563EB` focus outline, and 10px Royal Blue primary button.
- **`lib/screens/client_dashboard.dart` & `lib/screens/admin_dashboard.dart`**:
  - Updated sidebar navigation background to `#F2EEE7` with active `#2563EB` blue highlights.
  - Applied 12px card radius and soft elevation to metric cards and holdings panels.
  - Added alternating row striping to transaction history and client management tables.
