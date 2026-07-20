# Sharan Fincorp Design System

Welcome to the **Sharan Fincorp** Design System documentation. This system outlines the Slate Grey visual language, design tokens, component standards, and accessibility guidelines engineered for a high-contrast fintech experience (drawing inspiration from Zerodha Console, Groww, CRED, Stripe Dashboard, Linear, and Mercury Bank).

---

## 1. Design Language & Principles

- **Trust & High Readability**: Slate Grey base color palette with deep dark slate `#0F172A` text for 100% crisp legibility across titles, client names ("Hariom Sharan"), and numbers.
- **Visual Hierarchy & Pop**: Slate-100 background (`#F1F5F9`) paired with pure white surfaces (`#FFFFFF`) to ensure cards stand out clearly.
- **Defined Structure**: Every card, table, search input, and sidebar features a distinct 1px border (`#CBD5E1`).
- **8px Grid Layout**: Strict adherence to an 8px spacing system for layout harmony.

---

## 2. Color Tokens (`AppColors`)

### Slate Grey Light Mode Palette
| Token | Hex Value | Purpose / Usage |
| :--- | :--- | :--- |
| **Main Canvas Background** | `#F1F5F9` | Slate Grey off-white canvas |
| **Card / Panel / Surface** | `#FFFFFF` | Pure white overlays for maximum pop |
| **Sidebar** | `#F8FAFC` | Slate-50 soft sidebar background |
| **Primary Text** | `#0F172A` | Deep Slate for max contrast (titles, client names, values) |
| **Secondary Text** | `#334155` | Medium Dark Slate (labels, metadata, subtext) |
| **Placeholder Text** | `#64748B` | Muted Slate (search field hints) |
| **Primary Accent** | `#475569` | Slate Grey primary action buttons & active navigation |
| **Active Fill Background** | `#E2E8F0` | Soft Slate active link background tint |
| **Borders & Dividers** | `#CBD5E1` | Defined 1px Slate border around all cards, inputs & tables |
| **Profit / Success** | `#16A34A` | Financial gains & positive return text |
| **Warning** | `#D97706` | Warning amber badges & alerts |
| **Error / Loss** | `#DC2626` | Negative returns & critical alerts |
| **Info** | `#0284C7` | Informational callouts |

---

## 3. Typography & Hierarchy (`AppTextStyles`)

| Style Name | Font Family | Size / Weight | Color (Light Mode) | Usage |
| :--- | :--- | :--- | :--- | :--- |
| `h1` | Outfit | 28px / Bold | `#0F172A` | Page titles, primary numbers |
| `h2` | Outfit | 22px / Bold | `#0F172A` | Section headers, card titles |
| `h3` | Outfit | 18px / SemiBold | `#0F172A` | Subheaders, metric titles |
| `bodyLarge` | Inter | 16px / Regular | `#0F172A` | Primary body, dialog text |
| `bodyMedium` | Inter | 14px / Regular | `#0F172A` | Standard input text, table cells |
| `bodySecondary` | Inter | 13px / Regular | `#334155` | Subtext, secondary table metadata |
| `labelMedium` | Inter | 13px / Medium | `#334155` | Input field labels, table headers |
| `labelBold` | Inter | 13px / SemiBold | `#0F172A` | Active navigation links, bold tags |
| `caption` | Inter | 11px / Regular | `#64748B` | Footers, timestamps, scheme codes |

---

## 4. Component Guidelines

### Sidebar Navigation
- **Background**: `#F8FAFC` with 1px `#CBD5E1` right border.
- **Active Link State**: `#E2E8F0` active fill background with `#475569` accent icon and `#0F172A` text (`FontWeight.w600`). No pink highlights.

### Client Directory Cards & Rows
- **Client Names ("Hariom Sharan") & IDs**: `#0F172A` Deep Slate text for 100% legibility. Zero faint grey/pink text.
- **Alternating Table Rows**: `#FFFFFF` and `#F8FAFC` row striping with `#CBD5E1` dividers.

### Form Inputs & Search Bars
- Background `#FFFFFF`, 1px `#CBD5E1` border, `#0F172A` typed text, `#64748B` hint placeholder, and `#475569` focus border.

---

## 5. Accessibility & WCAG Compliance

- **Contrast Ratios**: `#0F172A` text against `#FFFFFF` surface achieves a **15.8:1 contrast ratio**, far surpassing WCAG AA requirement of 4.5:1.
- **Secondary Text**: `#334155` text achieves **9.6:1 contrast ratio** on `#FFFFFF`.
- **Placeholder Ratios**: `#64748B` placeholder text achieves **4.6:1 contrast ratio** on `#FFFFFF`.
