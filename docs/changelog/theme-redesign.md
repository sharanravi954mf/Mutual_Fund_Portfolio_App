# Changelog: Material 3 Design Integration (`Color(0xFFC9B4BC)`)

## Version Release: Material 3 Seed Color Migration

### Summary of Changes
Migrated the entire design system to **Material 3 (`useMaterial3: true`)** using **`Color(0xFFC9B4BC)`** (Dusty Rose Gold / Soft Mauve) as the primary seed color for generating color schemes, M3 card containers, navigation drawers, form controls, and button themes.

### Changed
- **`lib/theme/app_colors.dart`**:
  - Defined `seedColor: Color(0xFFC9B4BC)`.
  - Configured M3 Dusty Rose Light & Dark palettes (`#FBF8F9` canvas, `#FFFFFF` surfaces, `#3B2B32` left panel, `#C9B4BC` active navigation fill, `#7D5C69` primary accent, `#23181C` primary text).
- **`lib/theme/app_theme.dart`**:
  - Enabled `useMaterial3: true`.
  - Configured `ColorScheme.fromSeed(seedColor: AppColors.seedColor)` for Light and Dark modes.
- **`lib/screens/client_dashboard.dart` & `lib/screens/admin_dashboard.dart`**:
  - Applied Material 3 Dusty Rose Gold theme to sidebars, drawers, metric cards, holdings panels, and transaction tables.
