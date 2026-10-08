# MONEYBOWL-M1 — canonical runtime configuration and NSE credentials

Status: local configuration-foundation candidate, not deployed or independently
certified. Base: `c8014297c6e1c0b639e4b895ec51dd88b422f97b`, verified against a
fresh fetch and remote `refs/heads/develop` on 2026-10-08. Branch:
`feature/m1-runtime-config-20261008`. No live secrets were read or changed.

## Scope and promotion contract

One backend variable, `MONEYBOWL_ENV`, selects exactly `DEV`, `QA`, or `PROD`.
There is no implicit environment, hostname discovery, branch-derived authority,
DEV fallback, or default Production endpoint. `STAGING` means QA operationally;
it is not an accepted identifier. Branches are promotion conventions, not runtime
inputs. The shared resolver and transport work unchanged across projects.

| Setting or capability | DEV | QA | PROD |
| --- | --- | --- | --- |
| Promotion branch | `develop` | `qa` | `main` |
| Supabase | Existing DEV project | Independently owned private QA project | Existing Production project |
| NSE origin | `https://nseinvestuat.nseindia.com` | `https://www.nseinvest.com` | `https://www.nseinvest.com` |
| Provider | `edge-secrets` | `edge-secrets`, separately provisioned | `edge-secrets`, separately provisioned |
| Existing UAT workflows | Preserved | Denied before claims | Denied before claims |
| Stateless NAV certification probe | Existing behavior | Explicit `MASTER_DOWNLOAD` approval + private token | Explicit approval + own token |
| Investor mutations | Existing UAT authorization and invariants | Always denied | Not enabled by M1 |
| Permissions | Existing DEV paths | Explicit finite read list, initially `[]` | Explicit finite read list, initially `[]` |

The historical `nse-uat-smoke-test` route becomes the initial cross-environment
certification probe. It still posts only `{"file_type":"NAV"}` to MASTER_DOWNLOAD;
request bodies cannot select an endpoint, method or investor. Its dedicated
`X-NSE-Smoke-Token` is required even if JWT verification is disabled. It has always
been stateless and does not create integration evidence. Outside DEV, response
preview is empty and content type is a fixed generic value, so it returns only
status and byte-count diagnostics. This is a bounded initial QA certification
surface, **not activation of investor workflows or Production operations**.

Full persisted QA/PROD business workflows remain blocked by existing UAT database
contracts. Promoting M1 code requires no API URL source edits and permits the
approved stateless probe. It does **not** make the existing evidence schema ready
for Production investor reads or writes. The separate schema commissioning work
below must be reviewed before those workflows can be activated. No runtime flag
bypasses these fences.

## Runtime implementation

- `nse_runtime.ts`: environment types, project binding, strict origin validation,
  immutable endpoint policy, finite certification read catalog, and UAT workflow
  guard.
- `nse_credentials.ts`: asynchronous backend provider interface and initial Edge
  Secrets implementation; validates the four existing credential fields.
- `nse_config.ts`: composes an immutable config from runtime settings and exactly
  one selected provider. Existing authentication field names remain unchanged.
- `nse_client.ts`: checks environment/origin and method/path approval before auth
  generation or fetch. Redirects fail closed centrally, including the smoke
  probe. The streaming MASTER_DOWNLOAD transport is separately origin/DEV-bound
  before REQUEST evidence creation and retains its redirect prohibition.

Origins must be canonical HTTPS origins, optionally with one trailing slash.
User info, explicit ports (including `:443`), paths, dot segments, queries,
fragments (including empty delimiters), backslashes, normalized host aliases and
non-allowlisted hosts fail. Request paths cannot introduce alternate origins,
URL encoding, dot segments or queries. No request can follow a redirect to a
second endpoint. A config with a manually substituted cross-environment origin
is also rejected at the transport boundary.

`MONEYBOWL_SUPABASE_URL` is a project-local expected public origin and must match
the platform-injected `SUPABASE_URL`. This catches mismatched provisioning. It
cannot prove credential provenance or defend against an administrator who
intentionally relabels both values. The deployment owner must bind each project
to its actual environment independently; no repository project IDs or central
secret lookup tables are used. `supabase/config.toml` has a tracked CLI project
identifier and per-function JWT settings; neither selects the hosted environment.
Do not use that identifier as a promotion target.

Resolution occurs in the Edge runtime, generally once per worker isolate before
serving/claiming work. The onboarding worker now resolves before claims as well;
it still creates a separate transport for each operation. Configuration and
credentials are snapshots for an isolate, not a build-time substitution or a
promise of per-request secret refresh. Config failures produce only
`nse_configuration_invalid`, a static message, and known missing variable names.
Unknown provider exceptions are discarded, with no attached cause. Credential
properties remain available to authentication but are non-enumerable for normal
JSON and console inspection. This is defense in depth, not permission to log
config objects, authorization headers, credentials or raw provider payloads.

## Variable inventory

All backend settings below resolve at Edge runtime. Hosting injects its own
`SUPABASE_*` values; custom Edge secrets may not use that reserved prefix.

| Variable | Classification | Requirement / behavior |
| --- | --- | --- |
| `MONEYBOWL_ENV` | Non-secret | Required; `DEV`, `QA`, `PROD` only |
| `MONEYBOWL_SUPABASE_URL` | Non-secret | Required expected project HTTPS origin |
| `SUPABASE_URL` | Public, platform supplied | Required actual project origin; exact binding check |
| `NSE_URL` | Non-secret | Required; exact environment allowlist |
| `NSE_CREDENTIAL_PROVIDER` | Non-secret | Required; only `edge-secrets` implemented; `vault` rejected |
| `NSE_ALLOWED_READ_APIS` | Non-secret authorization policy | Required JSON array in QA/PROD; `[]` denies all; optional DEV |
| `NSE_LOGIN_USER_ID` | Backend credential | Required, nonblank |
| `NSE_API_KEY_MEMBER` | Backend secret | Required, nonblank |
| `NSE_API_SECRET_USER` | Backend secret | Required, nonblank |
| `NSE_MEMBER_CODE` | Backend credential/account identity | Required, nonblank |
| `NSE_USER_AGENT` | Non-secret | Optional; retains existing browser UA; printable bounded value |
| `SUPABASE_SERVICE_ROLE_KEY` | Backend secret, platform supplied | Existing persisted worker DB client; never frontend |
| `NSE_WORKER_TOKEN` | Backend secret | Existing worker bearer authorization; independent per project |
| `NSE_SMOKE_TEST_TOKEN` | Backend secret | Dedicated stateless probe authorization; independent per project |
| `NSE_UCC_WORKER_TOKEN` | Backend secret, legacy | Existing fallback only for UCC registration |
| `NSE_UCC_RECONCILIATION_WORKER_TOKEN` | Backend secret, legacy | Existing fallback only for reconciliation |
| `NSE_ORDER_STATUS_WORKER_TOKEN` | Backend secret, legacy | Existing fallback only for order status |

The shared worker token takes precedence over legacy tokens exactly as before;
this is a worker-auth compatibility contract, not a second NSE credential source.
All four NSE credential values are supplied together by the selected provider.
Blank values and control characters fail; no dummy values exist in production
code. Values and provider errors never appear in configuration diagnostics.

The finite non-DEV catalog is `MASTER_DOWNLOAD`, `ORDER_STATUS`,
`CLIENT_KYC_REPORT`, `CLIENT_MASTER_REPORT`, each mapped to its exact existing
POST report path. Unknown names, duplicate names, wildcards, malformed arrays,
EKYCREG and registration identifiers fail configuration. In M1 only the stateless
NAV probe has a non-DEV deployed entrypoint; enabling another read name cannot
unlock its UAT-only persisted worker. No generic request forwarding API exists.
Production mutation approval is deliberately not represented by a coarse boolean;
future operation-specific enablement needs its evidence and authorization contract.

See the [synthetic manifest](../examples/moneybowl-runtime.env.example). Never
provision placeholders; never commit a completed copy.

## Discovery and preserved contracts

Every NSE consumer was inspected. The 13 persisted workers are:
`nse-ucc-registration-worker`, `nse-ucc-reconciliation-worker`,
`nse-order-status-worker`, `nse-prov-orders-worker`, `nse-client-readiness-worker`,
`nse-order-funding-worker`, `nse-settlement-redemption-worker`,
`nse-sip-xsip-reports-worker`, `nse-stp-swp-reports-worker`,
`nse-master-download-worker`, `nse-mandate-status-worker`,
`nse-bank-mandate-worker`, and `nse-onboarding-kyc-worker`.
They all await `loadNseUatWorkflowConfig` before serving work. The stateless probe
uses `loadNseConfig`. Business payloads, response parsers and retry algorithms
were not rewritten.

Existing NSE authentication is preserved: PBKDF2 SHA-1/1000, AES-CBC/128,
random IV/salt and secret/random-number payload, then the existing Basic header.
The deterministic CryptoJS vector still passes through resolved credentials.
Encrypted REQUEST/RESULT records, database authorization, UCC registration,
onboarding eKYC link handling, KYC interpretations, idempotency, outbox claims,
leases, retries and PROVEN_NOT_SENT/MAYBE_SENT behavior remain intact. The new
policy denies invalid requests before fetch; it does not reclassify ambiguous
network failures as safe retries. Default User-Agent, memberId and authentication
headers are retained. UAT transport fixtures now declare DEV and use the policy
origin; fetch remains mocked and test network access is denied.

`verify_jwt = false` on these backend routes remains paired with existing secret
bearer checks and service-role-only persistence RPCs, which retain their own
scope/claim checks. The smoke route retains its distinct token header. No grants,
RLS policies, worker tokens or dispatcher routing were changed.

### Existing UAT database and browser fences

Do not replace `'UAT'` globally or delete a check constraint. Important owners:

| Source | Existing fence and future obligation |
| --- | --- |
| `20260901152955_nse_ucc_vertical_slice.sql` and subsequent UCC retry/verification migrations | UAT-specific account selection, partial index, operation creation/claim/source checks and immutable evidence; future environment must come from a trusted connection and match across account, operation, REQUEST and RESULT |
| Order status, provisional orders, B01–B05 report migrations | UAT admission and evidence validation plus endpoint-specific diagnostic interpretation; Production report semantics require certification, not reuse of UAT-only success exceptions |
| `20261002134417_nse_b06_1_master_reference_foundation.sql`, B06 runtime/staging/variant migrations | Connection accepts an environment enum but runtime rejects Production; evidence and adapters are explicitly UAT-bound |
| `20261006105515_nse_b07_approved_write_intents.sql`, operator authority and bank/mandate migrations | UAT consent, immutable approved intent and operator authorization; not Production write authority |
| `20261007130243_mfd_onboarding_v2a_kyc_orchestration.sql` | `onboarding_operation_id` evidence constraint requires UAT; start inserts UAT; `moneybowl_onboarding.ekyc_link` accepts only exact UAT host/path and bounded opaque token |
| `lib/features/investor_onboarding/presentation/onboarding_kyc_controller.dart` | Browser independently rejects non-UAT eKYC links; leave disabled outside DEV until matching server policy and verified Production hand-off contract exist |
| Frontend integration / authorization containment / onboarding migrations | Gates and authorization refer to existing UAT operations; must remain aligned with the eventual project-bound DB environment |

A reproducible inventory command is
`rg -n "UAT|nseinvestuat" supabase/migrations supabase/functions lib`.
These findings explain the explicit persisted-worker guard. Allowing QA to call
Production while recording UAT evidence would be a security regression. M1 leaves
all applied migrations and browser eKYC fences unchanged.

## Credential provider and Vault decision

Edge Function Secrets remain the only active source. This preserves existing
runtime provisioning and avoids exposing a new database secret retrieval API.
The asynchronous `NseCredentialProvider.resolve(environment)` interface returns
the same four authentication fields. Business code knows only `NseConfig`.
`NSE_CREDENTIAL_PROVIDER` explicitly selects the implementation; missing,
unsupported or unavailable providers never fall through to another source.

Vault is already involved in **database encryption**, not NSE login resolution:
`integration_payload_encryption_key_v1`, `bank_account_encryption_key_v1`, and
`bank_account_lookup_hmac_key_v1` are retrieved by existing restricted functions.
Other historical verification integrations also use Vault. This does not imply
NSE credentials should be moved or that Edge workers may select decrypted secrets.
No Vault values were inspected, moved or copied and no permissions were changed.

A future Vault provider must add explicit `vault` selection to the same resolver,
use a project-local restricted backend RPC with fixed allowed credential names,
revoke PUBLIC/anon/authenticated execution, set an empty search path and avoid
arbitrary name lookup or any new broad grant on `vault.decrypted_secrets`.
Authenticate the backend and bind retrieval to the commissioned environment.
Test permission denial as actual roles, missing/duplicate secrets, rotation and
sanitized failure independently. No partial merge of Vault and Edge credentials;
no Edge fallback on Vault failure. This is a design seam, not an implemented or
approved Vault retrieval path.

## Flutter is build-time, not runtime

`lib/main.dart` reads `SUPABASE_URL` and the legacy-named `SUPABASE_ANON_KEY` using
`String.fromEnvironment`. The latter is passed as the Supabase `publishableKey`.
They are public build inputs embedded in Flutter web output. Build once per target
using the same source revision; changing server environment variables cannot
retarget an already built frontend. Never serve a DEV-built bundle against QA.

Existing frontend DEV feature gates compare `MONEYBOWL_ENV` to lowercase `dev`.
Keep that compatibility spelling **in Flutter build definitions only**; backend
runtime canonical names remain uppercase. QA builds use `qa`, Production `prod`;
DEV-only previews and NSE console gates stay off there. No frontend runtime
configuration redesign or secret injection was introduced.

Synthetic build examples (replace only with the target project's public values):

```sh
flutter build web --release --dart-define=MONEYBOWL_ENV=dev --dart-define=SUPABASE_URL=https://synthetic-dev-project.supabase.co --dart-define=SUPABASE_ANON_KEY=SYNTHETIC_PUBLIC_PUBLISHABLE_KEY
flutter build web --release --dart-define=MONEYBOWL_ENV=qa --dart-define=SUPABASE_URL=https://synthetic-private-qa-project.supabase.co --dart-define=SUPABASE_ANON_KEY=SYNTHETIC_PUBLIC_PUBLISHABLE_KEY
```

Use target-specific public `AUTH_EMAIL_REDIRECT_URL` / `MONEYBOWL_PUBLIC_APP_URL`
where those flows are enabled. Never include service-role keys, passwords, NSE
credentials, worker/probe tokens or Vault credentials. Do not pass the backend
manifest to `--dart-define-from-file`. Existing placeholder defaults are not a
valid deployment; the build process must supply and verify the public pair.

## DEV rollout, failure handling and rollback (instructions only)

1. Before merging or deploying M1, the owner provisions `MONEYBOWL_ENV=DEV`,
   `MONEYBOWL_SUPABASE_URL` matching the actual DEV runtime, and
   `NSE_CREDENTIAL_PROVIDER=edge-secrets` in existing DEV Edge settings. Retain
   the existing correct UAT `NSE_URL`, credentials and authorization tokens.
   Current deployed code ignores the new names, so this additive phase does not
   interrupt working DEV. Do not deploy M1 first and hope for a fallback.
2. Validate presence, expected environment/origins and complete credentials using
   backend-only checks that report names/status, never values. Validate the
   synthetic tests and independent review first. Existing values were not inspected
   by this task; their correctness is an owner commissioning prerequisite.
3. Deploy only under a separate authorization. Check the authenticated DEV probe
   and approved DEV regression workflows; preserve encrypted evidence and outbox
   recovery rules. M1 performs no deployment or live probe.
4. Invalid configuration fails worker startup before claims or NSE transport.
   An empty probe token denies access; empty QA/PROD permissions deny transport.
   Alert on static error codes and failed startup, never dump the environment.
5. Roll back code to the previously deployed DEV revision if commissioning fails.
   Additive variables can remain because old DEV code ignores them. No database
   rollback or credential migration is needed. Do not reset outbox states or
   retry MAYBE_SENT writes as part of rollback.
6. Never roll QA/PROD back to pre-M1 unrestricted transport code with Production
   credentials. Disable access/probe approval and use a known-safe M1 revision.
   Treat in-flight calls as potentially sent; configuration changes cannot undo
   a request already dispatched.

There is no compatibility fallback with an expiry to forget. Compatibility is a
provision-before-deploy sequence, preserving working DEV until cutover. A running
old deployment remains untouched by this local candidate.

### Safe rotation

The owner rotates each project's credentials independently through its selected
provider. Preserve a coherent set of login, member key, user secret and member
code. Do not log values, send them to CI, or copy DEV credentials to QA. Plan a
controlled cutover of warm isolates since configs are resolved at isolate startup;
do not assume an already-created client refreshes on every request. Validate using
an approved read after the new set is active, then revoke the old credentials.
During mixed-version/credential windows fail closed; do not enable a second
provider as a fallback. Worker token rotation is separately coordinated with the
existing dispatcher and is not performed by M1. Encryption-key rotation is also a
separate, evidence-retention-sensitive procedure, not NSE credential rotation.

## Future private QA commissioning

The owner creates/provisions private QA independently: project binding, own
Supabase public build pair, own service-role infrastructure, own NSE Production
credentials authorized by NSE, approved egress/IP allowlisting, and distinct
worker/probe tokens. DEV infrastructure receives no QA service-role key, token or
secret retrieval access. Set `MONEYBOWL_ENV=QA`, the verified Production origin,
`edge-secrets` and `NSE_ALLOWED_READ_APIS=[]`. After explicit certification approval,
select `["MASTER_DOWNLOAD"]` to permit only the fixed NAV probe. Do not infer
approval from this example. The code is identical to DEV; no API URLs are edited.

Before any **persisted** Production read or any investor mutation:

1. Prepare an additive, independently tested schema change that stores the
   project/connection's canonical environment in backend-only configuration and
   derives vendor environment (`UAT` / `PRODUCTION`) from it. Runtime and DB
   bindings must agree before claims; browser/caller input must not select it.
2. Update the selected read workflow's account, operation, claim, evidence and
   diagnostic contracts together. Preserve existing UAT rows and indices; never
   relabel history, and reject inconsistent pre-existing rows. QA and PROD both
   use vendor Production but still have separate project ownership/credentials.
3. Replace the corresponding UAT worker guard with a tested DB/runtime environment
   binding, only for commissioned operations. Merely setting an Edge variable
   must never activate an old UAT evidence path. M1 supplies no such bypass.
4. Keep mutations denied in QA. For eventual PROD writes, separately implement
   approved operation-specific authorization, consent/evidence and reconciliation
   gates. Production eKYC hand-off origins/paths need their own verified contract;
   the API origin alone is not evidence of the hosted eKYC URL contract.
5. Test all new schema constraints/RPCs locally under real roles, including
   cross-project/environment attempts, encrypted evidence, replay, ambiguous
   delivery and rollback. Apply nothing live without separate authorization.

These are required subsequent implementations, not migrations included or applied
by M1. Broad replacement of dozens of applied UAT contracts would exceed this
configuration-foundation change. Persisted Production workflows are explicitly
not deployment-ready; the bounded stateless certification probe is the initial
supported QA path.

## Dispatcher and automated promotion still outstanding

No Oracle process, outbox dispatcher, services or dispatch semantics changed.
Environment-specific dispatch ownership, queue routing, worker tokens, event-driven
transport and existing retry/lease commissioning remain separate work. Existing
DEV infrastructure must not receive QA secrets to dispatch private QA work.

Future automation may deploy `develop` to DEV, validate it, prepare a PR to `qa`,
wait for the user's approved merge, then deploy identical code to private QA and
build the matching public Flutter bundle. The pipeline must verify branch/project
binding, required names and approved API set without reading secrets into logs.
No workflow, branch protection, CI permission, PR or deployment was created here.

## Sources and validation

The official [NSE NNF v1.9.7 handbook](https://www.nseinvest.com/nsemfdesk/resources/upload/apidetails/NSEMF_API_Details_V1.9.7.pdf),
June 2026, p6, explicitly identifies the UAT and Production API origins used in
policy. No NSE Production API was contacted; only public documentation was read.
[Supabase Edge environment documentation](https://supabase.com/docs/guides/functions/secrets)
confirms runtime environment access and separate secret provisioning.
[Supabase Vault documentation](https://supabase.com/docs/guides/database/vault)
describes encrypted storage and decrypted-view access; that is why a future
provider must constrain retrieval. The current Supabase changelog was inspected;
no new Vault/database feature is introduced by this candidate.

Validation uses Deno 2.9.6 and synthetic credentials only. All network transports
are mocks; tests run with `--deny-net --deny-env --cached-only`. This prevents
accidental live API calls or reads of process credentials, including for fixtures
using real policy hostnames. The same NSE regression suite preserves authentication,
request bytes, worker auth, evidence ordering, eKYC, retry/idempotency and streaming
transport behavior. New tests cover all environments, missing/empty settings,
provider selection/failure, origins/project binding, URL parser tricks, non-DEV
read approvals/write denial, redaction, and the private-token QA NAV probe.


### Local validation record

Executed with `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno`:

| Check | Result |
| --- | --- |
| `deno test --cached-only --deny-net --deny-env supabase/functions/_shared/nse supabase/functions/nse*-worker supabase/functions/nse-uat-smoke-test` | 981 passed, 0 failed |
| `deno check --cached-only supabase/functions/nse*/index.ts` | All 14 entrypoints passed |
| `deno fmt --check supabase/functions/_shared/nse supabase/functions/nse*-worker supabase/functions/nse-uat-smoke-test` | 113 files passed |
| `python3 .github/scripts/validate_docs.py` | Passed |
| `python3 .github/scripts/validate_commits.py 'feat(config): bind NSE runtime settings to canonical environments'` | Passed |
| `git diff --check` | Passed |

No Flutter or database schema changed, so no Flutter build, database reset, live
SQL checks or migration execution were needed or performed. Local synthetic
transport/evidence regressions are not a substitute for independently authorized
DEV or QA commissioning. The candidate is ready for independent configuration
foundation review; it is not blanket approval to deploy or activate persisted
Production workflows.

### Changed-file inventory

- `docs/CHANGELOG.md`
- `docs/PROJECT_STATE.md`
- `docs/architecture/MONEYBOWL_M1_RUNTIME_CONFIGURATION.md`
- `docs/architecture/SYSTEM_ARCHITECTURE.md`
- `docs/examples/moneybowl-runtime.env.example`
- `supabase/functions/_shared/nse/nse_client.ts`
- `supabase/functions/_shared/nse/nse_client_test.ts`
- `supabase/functions/_shared/nse/nse_config.ts`
- `supabase/functions/_shared/nse/nse_config_test.ts`
- `supabase/functions/_shared/nse/nse_credentials.ts`
- `supabase/functions/_shared/nse/nse_master_download.ts`
- `supabase/functions/_shared/nse/nse_master_download_test.ts`
- `supabase/functions/_shared/nse/nse_runtime.ts`
- `supabase/functions/_shared/nse/nse_types.ts`
- `supabase/functions/nse-bank-mandate-worker/adapters.ts`
- `supabase/functions/nse-bank-mandate-worker/index.ts`
- `supabase/functions/nse-bank-mandate-worker/index_test.ts`
- `supabase/functions/nse-client-readiness-worker/index.ts`
- `supabase/functions/nse-client-readiness-worker/index_test.ts`
- `supabase/functions/nse-mandate-status-worker/index.ts`
- `supabase/functions/nse-mandate-status-worker/index_test.ts`
- `supabase/functions/nse-master-download-worker/index.ts`
- `supabase/functions/nse-master-download-worker/index_test.ts`
- `supabase/functions/nse-onboarding-kyc-worker/adapters.ts`
- `supabase/functions/nse-onboarding-kyc-worker/handler_test.ts`
- `supabase/functions/nse-onboarding-kyc-worker/index.ts`
- `supabase/functions/nse-order-funding-worker/index.ts`
- `supabase/functions/nse-order-funding-worker/index_test.ts`
- `supabase/functions/nse-order-status-worker/index.ts`
- `supabase/functions/nse-order-status-worker/index_test.ts`
- `supabase/functions/nse-prov-orders-worker/index.ts`
- `supabase/functions/nse-prov-orders-worker/index_test.ts`
- `supabase/functions/nse-settlement-redemption-worker/index.ts`
- `supabase/functions/nse-settlement-redemption-worker/index_test.ts`
- `supabase/functions/nse-sip-xsip-reports-worker/index.ts`
- `supabase/functions/nse-sip-xsip-reports-worker/index_test.ts`
- `supabase/functions/nse-stp-swp-reports-worker/index.ts`
- `supabase/functions/nse-stp-swp-reports-worker/index_test.ts`
- `supabase/functions/nse-uat-smoke-test/handler.ts`
- `supabase/functions/nse-uat-smoke-test/index.ts`
- `supabase/functions/nse-uat-smoke-test/index_test.ts`
- `supabase/functions/nse-ucc-reconciliation-worker/index.ts`
- `supabase/functions/nse-ucc-registration-worker/index.ts`
