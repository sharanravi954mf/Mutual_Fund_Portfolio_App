# Sharan Fincorp Material 3 Design System

Welcome to the **Sharan Fincorp** Material 3 Design System documentation (`useMaterial3: true`), powered by **`Color(0xFFC9B4BC)`** (Dusty Rose Gold / Soft Mauve) as the primary seed color.

---

## 1. Material 3 Design Architecture

- **Primary Seed Color**: `Color(0xFFC9B4BC)` (Soft Dusty Rose Gold)
- **Tonal Color Schemes**: Dynamically generated via `ColorScheme.fromSeed(seedColor: const Color(0xFFC9B4BC))` for Light and Dark modes.
- **Surface Elevation & Pop**: `#FBF8F9` canvas paired with `#FFFFFF` elevated surface containers and soft tonal highlights (`#F4EBEF`).
- **Defined Structure**: Every card, table, search input, and sidebar features 1px defined borders with Material 3 radii.

---

## 2. Color Tokens (`AppColors`)

### Material 3 Palette (`seedColor: Color(0xFFC9B4BC)`)
| Token | Hex / Value | Purpose / Usage |
| :--- | :--- | :--- |
| **Material 3 Seed** | `Color(0xFFC9B4BC)` | Primary seed color for M3 tonal generation |
| **Canvas Background** | `#FBF8F9` | M3 soft tint canvas background |
| **Card / Surface** | `#FFFFFF` | Pure white elevated surfaces |
| **Left Panel (Sidebar)** | `#3B2B32` | Deep Mauve Slate left panel |
| **Sidebar Sub-surface** | `#4C3A42` | M3 Dark Mauve sub-surface containers |
| **Active Navigation Fill** | `#C9B4BC` | M3 Dusty Rose Gold active pill fill |
| **Active Navigation Text** | `#3B2B32` | Dark Mauve high-contrast text on active pill |
| **Inactive Sidebar Text** | `#D4C5CB` | Soft Rose Grey text for inactive links |
| **Primary Accent** | `#7D5C69` | M3 Deep Mauve primary buttons & action controls |
| **Active Content Fill** | `#F4EBEF` | M3 tonal active fill for list items & badges |
| **Primary Text** | `#23181C` | M3 Dark Charcoal primary text (**WCAG AA Compliant**) |
| **Secondary Text** | `#514349` | M3 Medium Dark subtext & labels |
| **Placeholder Text** | `#8B7780` | M3 hint text |
| **Borders & Dividers** | `#E8DCE1` | Soft Mauve defined borders |
| **Profit / Success** | `#16A34A` | Positive returns & financial gain |
| **Warning** | `#D97706` | Warning badges |
| **Error / Loss** | `#DC2626` | Negative returns & critical alerts |

---

## 3. Component Guidelines

### Material 3 Navigation Drawer & Sidebar
- **Background**: `#3B2B32` with 1px `#4C3A42` right border.
- **Active Navigation Link**: `#C9B4BC` Dusty Rose Gold active pill fill with `#3B2B32` text (`FontWeight.w600`).
- **Brand Header Badge**: `#C9B4BC` rounded container with white shield icon & `#FFFFFF` title text.

### Material 3 Form Controls & Cards
- **Form Inputs**: `#FFFFFF` background, `#E8DCE1` border, `#23181C` typed text, `#8B7780` placeholder, and `#7D5C69` focus border.
- **Cards**: `#FFFFFF` fill with 12px radius, `#E8DCE1` border, and soft M3 elevation shadow.
