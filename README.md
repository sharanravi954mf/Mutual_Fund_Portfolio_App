# Sharan Fincorp — Mutual Fund Portfolio Management Platform

Sharan Fincorp (internally codenamed **Moneyball**) is a premium, secure, and responsive Mutual Fund Portfolio Tracker designed for Web (Desktop) and Android (Mobile) viewports.

---

## 1. Project Vision & Overview
The platform gives mutual fund Advisors (distributors) a trusted operating system to manage client onboarding, automated registrar (RTA) statement ingestion, reconciliation, and compliance operations. Concurrently, it grants Investors a secure, real-time interface to monitor their verified assets without exposing sensitive identifiers or raw personal credentials.

---

## 2. Key Features

- 🔐 **Isolated Identity & Account Linking**: Separation of Supabase Auth login credentials from the distributor's business investor profiles (`profiles`).
- 🛡️ **Vault-Backed PAN Protection**: Encrypted PAN storage at rest (`AES-256`) and SHA-256 HMAC lookups for duplicate check. Raw PAN is never logged or exposed.
- 📋 **Folio-Scoped Portfolio RLS**: Row Level Security (RLS) restricts investor access to only the specific folios covered by active, approved folio grants.
- ✍️ **In-Memory Batch ZIP Invoice Signer**: Deno Edge Function coordinates batch unzipping, signing, and re-compression of PDF invoices.
- 📊 **CAMS/KFintech Ingestion Pipeline**: Ingestion of password-protected registrar ZIPs containing dBASE III (`.dbf`) ledger statements.
- 🔍 **Autocomplete Fund Search & Factsheets**: Instantly search scheme codes or names and launch interactive factsheets.
- 🌧️ **Live Money Wallpaper Engine**: Ambient floating rupee/gains and golden wealth curve backgrounds adapting dynamically to light/dark themes.

---

## 3. Technology Stack

- **Frontend**: Flutter (stable) & Dart (`^3.0.0`)
- **State Management**: Provider (`^6.1.2`)
- **Typography & Formatting**: Google Fonts (`google_fonts ^6.2.1`) & Intl (`intl ^0.19.0`)
- **Database & Backend**: Supabase (Auth, Storage, Edge Functions)
- **Database Engine**: PostgreSQL (Row Level Security, triggers, `SECURITY DEFINER` RPCs)
- **Ingestion Runtime**: Deno / TypeScript (Edge Functions)

---

## 4. Repository Structure

```text
├── lib/
│   ├── main.dart            # Application bootstrap, router, & top-level guards
│   ├── providers/           # Shared ChangeNotifier states (auth, session, theme, language)
│   ├── screens/             # Legacy dashboards and application layout shell
│   ├── services/            # Supabase API bindings and core integrations
│   ├── utils/               # File pickers, math, and calculations (XIRR, Absolute Return)
│   └── features/            # Feature modules (Domain Models -> Data -> Application -> Presentation)
├── supabase/
│   ├── migrations/          # Forward-only database schemas, RLS policies, and RPCs
│   ├── functions/           # Secured Edge Functions (ingestion, invoice signer)
│   └── tests/               # Persistent SQL security and RLS regression tests
├── web/                     # Web assets (index.html, manifest.json, SheetJS integrations)
└── docs/                    # Technical specs, design logs, and release history
```

---

## 5. Environment Variables & Setup

Create a `.env` file in the root directory. The application requires compile-time values for client-side configuration.

```ini
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
RTA_DECRYPTION_PASSWORD=your-cams-zip-password
```

### Local Development Setup

Sourcing environment variables and running the app:

```bash
# 1. Load variables into active shell
set -a
source .env
set +a

# 2. Run Flutter with explicit environment definitions
flutter run -d chrome \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
```

*Note: Passing `--dart-define=ENV=.env` does not work; the variables must be passed explicitly as defined above.*

---

## 6. Running Subsystems Locally

### Running Supabase Database & Migrations
Ensure the Supabase CLI is installed and running locally:

```bash
# Start local supabase services
supabase start

# Reset local database schema and seed data
supabase db reset

# Run SQL security and authorization tests
sh supabase/tests/run_all.sh
```

### Running Deno Edge Functions
Run edge functions locally using the Supabase CLI:

```bash
# Start edge functions server
supabase functions serve
```

---

## 7. Development & Release Workflow

We enforce an evidence-driven release pipeline (see `ADR-005`):

```text
Architecture Spec → Implementation → Local Validation → Security Review → Merge → GitHub Pre-Release
```

### Branch Strategy
- Branch from `main` using `feature/` prefixes (e.g. `feature/analytics`).
- All code modifications require passing static analysis (`flutter analyze`) and unit tests (`flutter test`) locally before a PR is opened.

---

## 8. AI Developer Manual
All AI coding assistants working on this repository must read and adhere to [AGENTS.md](AGENTS.md). The manual details coding standards (relative imports, folder architecture, dark theme token color sets, docstring preservation, and regression test rules).

---

## 9. Documentation Index

- [Product Documentation Directory](docs/product/README.md)
- [Target Architecture Contract](docs/architecture/ARCHITECTURE.md)
- [Executive Architecture Entrypoint](docs/architecture.md)
- [Architecture Decision Records (ADRs)](docs/decisions/README.md)
- [Sprint Progress & State Records](docs/PROJECT_STATE.md)
- [Material 3 Design System Guides](docs/design-system.md)
- [AI Engineering Handoff Specs](docs/AI_HANDOFF.md)
- [Verification Workflow Blueprint](docs/verification_workflow_design.md)
