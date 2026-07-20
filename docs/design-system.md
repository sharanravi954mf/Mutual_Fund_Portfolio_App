# Sharan Fincorp Design System

Welcome to the **Sharan Fincorp** Design System documentation. This system outlines the visual language, design tokens, component standards, and accessibility guidelines engineered for a premium fintech experience (drawing inspiration from Zerodha Console, Groww, CRED, Stripe Dashboard, Linear, and Mercury Bank).

---

## 1. Design Language & Principles

- **Trust & Professionalism**: Clean, high-contrast layouts engineered for financial data clarity.
- **Visual Hierarchy**: Warm off-white background (`#F8F6F2`) paired with crisp pure white card surfaces (`#FFFFFF`) to ensure cards pop effortlessly with subtle soft shadows.
- **8px Grid Layout**: Strict adherence to an 8px spacing system for consistent rhythm.
- **Restrained Elevation**: Soft, multi-layered ambient drop shadows rather than heavy black overlays.

---

## 2. Color Tokens (`AppColors`)

### Light Mode Palette
| Token | Hex Value | Purpose / Usage |
| :--- | :--- | :--- |
| **App Background** | `#F8F6F2` | Warm off-white canvas |
| **Surface / Card** | `#FFFFFF` | Crisp white elevation container |
| **Sidebar** | `#F2EEE7` | Distinct soft warm beige navigation panel |
| **Primary Brand** | `#2563EB` | Royal Blue primary action buttons, active tabs, highlights |
| **Primary Hover** | `#1D4ED8` | Hover state for primary buttons |
| **Secondary** | `#64748B` | Slate Grey secondary text & outlined borders |
| **Success / Positive**| `#22C55E` | Positive growth, verified state badges |
| **Profit** | `#16A34A` | Financial gains & positive XIRR text |
| **Warning** | `#F59E0B` | Pending operations, caution alerts |
| **Error / Loss** | `#DC2626` | Negative returns, critical alerts |
| **Info** | `#0EA5E9` | Informational callouts |
| **Divider** | `#E5E7EB` | Subtle structural dividers |
| **Primary Text** | `#1F2937` | High contrast dark charcoal headings & body text |
| **Secondary Text** | `#6B7280` | Cool grey subtitles, metadata, timestamps |
| **Disabled** | `#9CA3AF` | Inactive buttons, disabled field backgrounds |

---

## 3. Typography & Hierarchy (`AppTextStyles`)

| Style Name | Font Family | Size / Weight | Color (Light Mode) | Usage |
| :--- | :--- | :--- | :--- | :--- |
| `h1` | Outfit | 28px / Bold | `#1F2937` | Page titles, primary numbers |
| `h2` | Outfit | 22px / Bold | `#1F2937` | Section headers, card titles |
| `h3` | Outfit | 18px / SemiBold | `#1F2937` | Subheaders, metric titles |
| `bodyLarge` | Inter | 16px / Regular | `#1F2937` | Primary body, dialog text |
| `bodyMedium` | Inter | 14px / Regular | `#1F2937` | Standard input text, table cells |
| `bodySecondary` | Inter | 13px / Regular | `#6B7280` | Subtext, secondary table metadata |
| `labelMedium` | Inter | 13px / Medium | `#6B7280` | Input field labels, table headers |
| `labelBold` | Inter | 13px / SemiBold | `#1F2937` | Active navigation links, bold tags |
| `caption` | Inter | 11px / Regular | `#6B7280` | Footers, timestamps, scheme codes |

---

## 4. Spacing, Radius & Elevation Tokens

### Spacing Grid (`AppSpacing`)
- `xxs`: 2px | `xs`: 4px | `sm`: 8px | `md`: 16px | `lg`: 24px | `xl`: 32px | `xxl`: 40px

### Border Radius (`AppRadius`)
- **Cards & Container Panels**: `12px` (`AppRadius.card`)
- **Buttons**: `10px` (`AppRadius.button`)
- **Input Fields**: `8px` (`AppRadius.input`)
- **Badges & Tags**: `6px` (`AppRadius.sm`)

### Soft Elevation Shadows (`AppShadows`)
- **Cards**: `[BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 2))]`
- **Dropdowns / Menus**: `[BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, 8))]`

---

## 5. Component Guidelines

### Sidebar Navigation
- **Background**: `#F2EEE7`
- **Active State**: `#2563EB` icon, `#2563EB` text (`FontWeight.w600`), and subtle `#2563EB` background overlay (`alpha: 0.12`).
- **Collapsible Mode**: Toggles between 260px expanded width and 72px icon-only shrunken mode with interactive hover tooltips.

### Financial Metric Cards
- Surface background `#FFFFFF` with `#E5E7EB` border and 12px radius.
- Positive gains display in `#16A34A` profit green with high-contrast text.

### Tables & Data Grids
- **Header Row**: `#F8F6F2` background with `#6B7280` medium-weight headers.
- **Alternating Rows**: Primary `#FFFFFF` and subtle `#FAF9F6` row striping for readability.
- **Dividers**: Clean 1px `#E5E7EB` borders.

---

## 6. Accessibility & WCAG Compliance

- **Contrast Ratios**: All primary text (`#1F2937`) against `#FFFFFF` surface achieves **7.4:1 contrast ratio**, exceeding the WCAG AA requirement of 4.5:1.
- **No Low-Contrast Grey Text**: Secondary text is fixed at `#6B7280` (4.6:1 contrast ratio on `#FFFFFF`), eliminating unreadable light grey labels on light backgrounds.
- **Interactive Focus States**: Form fields highlight with a distinct `#2563EB` border (1.5px) when focused.
