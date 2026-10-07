# DEV onboarding preview V1

## Purpose and contract

This local candidate adds a synthetic presentation of the stages after KYC in the [frozen V2 KYC-first journey](MFD_INVESTOR_ONBOARDING_V2_KYC_FIRST_FROZEN.md). It responds to the CAMS UAT email OTP blocker without changing the investor's real `EKYC_IN_PROGRESS` case. The [V2-A implementation](MFD_INVESTOR_ONBOARDING_V2A_IMPLEMENTATION_VALIDATION.md) and [V1 identity foundation](MFD_LED_INVESTOR_ONBOARDING_V1.md) retain all authority over real onboarding. Positive `CLIENT_KYC_REPORT` status characterization is a separate provider integration task; it has not been commissioned by this preview.

**This preview is not an alternative KYC verification mechanism.**

## Isolation and entry

The KYC screen shows **Preview remaining onboarding (DEV)** only while it displays a server-authorized `EKYC_IN_PROGRESS` case. The existing `get_onboarding_kyc`/MFD workspace authority remains responsible for that projection. The button pushes a separate route without passing the case ID, PAN, investor contact, provider link, KYC controller, repository or any other real-case data. Popping the route returns to the unchanged KYC screen.

The preview route also fails closed unless all three build-time conditions hold:

1. `MONEYBOWL_DEV_ONBOARDING_PREVIEW=true` (explicit; defaults to false);
2. `MONEYBOWL_ENV=dev`;
3. `SUPABASE_URL=https://rskryngwzyuzmiwtriyy.supabase.co` (exact DEV project URL).

The gate reads Dart compile-time defines. There is no URL-query, browser-storage, remote setting or app-setting switch. A Production build using the Production project URL remains disabled even if the flag is accidentally supplied. The preview has no backend privilege: Flutter feature detection is not used to relax RLS or a business RPC. The application has no direct named route to this preview; direct construction of its guarded route in a disabled build shows only an unavailable screen. Only the authorized MFD KYC view offers the entry in the normal app navigation.

## Synthetic-data boundary

The preview owns a local `DevOnboardingPreviewController` that has no repository, network client, persistence, analytics or case identifier. Its only initial values are `Demo Investor` and `demo@example.test`. Editable fields explicitly request fictional values and live only in the route's memory. Route disposal clears its state; re-entry starts a new sample. The interface never asks for PAN, Aadhaar/OTP, a genuine account number, IFSC or provider secrets. Bank name is fixed to `Example Test Bank`; account type is only a local UI choice. There is no bank verification, consent record, UCC or readiness state.

Neither the preview controller nor its page can call `save_investor_onboarding`, `resolve_investor_onboarding`, `request_onboarding_kyc`, `prepare_onboarded_investor_ucc`, any NSE worker, bank verification, order or mandate operation. No Supabase or NSE client is imported into the preview. The real `kyc_cases`, onboarding cases, registration profiles, PAN records, integration accounts and encrypted provider evidence are never touched by preview navigation. The existing real KYC transition and post-KYC guard are unchanged.

## Screens and limitations

The visible **DEV SIMULATION — NOT KYC VERIFIED** banner persists on every stage, including compact/mobile layouts. The flow covers remaining personal details, address, explicit nominee Yes/No (with conditional fictional details), FATCA tax-residency choice, bank presentation, review/consent preview and a final end screen. Required fields and empty/invalid input have local validation. Back/forward navigation retains only the current route's state; exit discards it.

The nominee, FATCA, bank and review/consent screens are **preview-only presentation**. They do not claim an authoritative provider schema, nominee provider support, tax declaration, bank verification or investor consent. The final screen states: “Preview complete. No real investor was verified, registered or made ready to transact.” The existing V1 form and real KYC screen remain as they were; the preview shares only ordinary Flutter presentation patterns and field concepts because the live controller can mutate onboarding data.

## Safe DEV activation and disablement

This work is a local commit only. A separate reviewed DEV frontend deployment may build with the trusted DEV Supabase URL and public key plus:

```text
--dart-define=MONEYBOWL_ENV=dev
--dart-define=MONEYBOWL_DEV_ONBOARDING_PREVIEW=true
--dart-define=SUPABASE_URL=https://rskryngwzyuzmiwtriyy.supabase.co
```

After deployment, an authorized MFD can open an existing `EKYC_IN_PROGRESS` case from Clients, use the preview button, exit, and confirm the original KYC state remains pending. No database migration, feature-table change, hosted case patch or provider call is required. Disable by omitting the preview flag or setting it to false in the next DEV frontend build. Production build definitions must use their own project URL and omit the preview flag. Any hosted build/deployment still needs separate authorization.

## Validation and remaining production work

Focused widget tests cover the gate, production-disabled direct route, synthetic sample, form validation, navigation, conditional nominee/FATCA fields, bank/consent wording, final state, route disposal, KYC-entry isolation and 320px/desktop large-text layout. The KYC-entry test uses a synthetic repository and confirms preview navigation adds no KYC/eKYC request and leaves `EKYC_IN_PROGRESS` unchanged. No real investor or provider fixture is used.

Local validation against fresh develop `22b0de39e57bd2b8101134db86f6c9ab2a122140`:

| Check | Result |
| --- | --- |
| `flutter test --no-pub test/investor_onboarding/dev_onboarding_preview_test.dart` | 9 passed, default-off route blocked. |
| Same focused test with `MONEYBOWL_ENV=dev`, `MONEYBOWL_DEV_ONBOARDING_PREVIEW=true`, exact DEV `SUPABASE_URL` | 9 passed, authorized synthetic KYC entry opened. |
| Same focused test with `MONEYBOWL_ENV=production`, preview flag true, Production `SUPABASE_URL` | 9 passed, direct route blocked. |
| `flutter test --no-pub test/investor_onboarding test/authentication test/investor_identity_models_test.dart test/user_management_workspace_models_test.dart` | 99 passed. |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` on base and candidate | Both exit 0 with the same 91 existing diagnostics; zero new diagnostics. |
| `flutter build web --release --no-pub --dart-define=MONEYBOWL_ENV=dev --dart-define=MONEYBOWL_DEV_ONBOARDING_PREVIEW=true --dart-define=SUPABASE_URL=https://rskryngwzyuzmiwtriyy.supabase.co --dart-define=SUPABASE_ANON_KEY=synthetic-local-public-key` | Passed twice; `build/web` generated locally. Existing `dart:js` Wasm dry-run notices; the cold build also reported an existing Cupertino font notice. |
| `python3 .github/scripts/validate_docs.py` | Passed, 61 Markdown files. |
| `python3 .github/scripts/validate_migration_history.py` | Passed, frozen history unchanged. |
| `python3 -m unittest discover -s .github/scripts -p test_validate_commits.py` | 5 passed. |
| `python3 .github/scripts/validate_commits.py 'feat(onboarding): add DEV-only post-KYC preview'` | Passed. |
| `git diff --check` | Passed. |

SQL and Deno suites are omitted because no backend, migration or Edge Function file changed. This preview has no server operation to exercise.

Real post-KYC work still requires authoritative positive KYC-status semantics and UAT characterization, progressive production field collection, provider-supported nominee and FATCA contracts, encrypted bank capture and verification, auditable investor consent, UCC registration and post-registration readiness checks. None are implemented or bypassed here. No real EKYCREG, KYC report or other NSE request was sent during this task.
