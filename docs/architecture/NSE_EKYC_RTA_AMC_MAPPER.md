# NSE eKYC RTA-AMC mapper: evidence and unresolved source discrepancy

## Decision: Phase A complete; Phase B stopped

The official NSE FAQ independently proves the seven named relationships below.
However, the newer v1.9.7 manual uses an additional, unnamed `AXF` value in its
fresh-registration sample. The retained Postman request also uses the unlisted,
unnamed value `T`. No inspected source explains whether these examples are obsolete
or whether the FAQ list is incomplete for the current endpoint.

The task requires an unambiguous complete supported list and explicitly prohibits
seeding when official sources conflict or a code/name relationship is ambiguous.
Consequently **no seed, migration, runtime change or frontend change is included**.
The existing empty selector continues to block initiation. This is an evidence-only
candidate, not a completed or commissioned mapper.

The [frozen V2 contract](MFD_INVESTOR_ONBOARDING_V2_KYC_FIRST_FROZEN.md),
[V2-A implementation](MFD_INVESTOR_ONBOARDING_V2A_IMPLEMENTATION_VALIDATION.md),
[V1 identity/security](MFD_LED_INVESTOR_ONBOARDING_V1.md),
[SCH Fund Search](NSE_SCH_FUND_SEARCH.md) and
[SCH master contract](NSE_MASTER_DOWNLOAD_SCH.md) were read before this decision.
Frozen onboarding and existing EKYCREG request semantics were not changed.

## Fresh base and execution boundary

- Canonical repository: `/home/ubuntu/moneybowl`; clean `develop`.
- Fetched `origin/develop` and canonical HEAD both:
  `b74bab8c922aba17bd6ae0463d20b148c4ba6e94` (PR #201).
- Branch: `feat/nse-ekyc-rta-amc-mapper-20261008`.
- Worktree: `/home/ubuntu/moneybowl-worktrees/nse-ekyc-rta-amc-mapper-20261008`.
- Discovery date: 7 October 2026; the branch name follows the requested example.
- Hosted access consisted only of DEV metadata/reference-data SELECT queries.
  No investor payload, Auth contact, credential, or encrypted provider link was read.
- No EKYCREG mutation, other NSE API request, hosted database mutation, secret
  rotation, Production/main change, push, PR, merge or deployment was performed.
  Downloading the public official FAQ PDF was the only direct NSE HTTP retrieval.

## Contract and authoritative material

The retained `NSEMF_API_Details_V1.9.7.pdf`, June 2026, printed/PDF page 193,
section **KYC FRESH REGISTER API**, defines:

```text
POST /nsemfdesk/api/v1/EKYC/EKYCREG
Required JSON fields: amcCode, panNo, invEmail, mobileNo
amcCode: mandatory CHAR, described as RTA AMC CODE
panNo: mandatory CHAR, size 10
invEmail: mandatory CHAR
mobileNo: mandatory NUMBER, size 10
```

MoneyBowl's existing four-field request serialization is unchanged. The retained
Postman collection's **KYC FRESH REGISTER API** request uses the same endpoint and
four field names. Examples do not authorize additional fields or AMC mappings.

| Source | Provenance |
| --- | --- |
| NSE API manual v1.9.7 | `/home/ubuntu/nse-uat-contract/docs/NSEMF_API_Details_V1.9.7.pdf`; SHA-256 `5c3c819d788e40ba28f8d2eb3a6b2faabc3a39c5e9bc658fa034cf4c26cc576a`; cover June 2026; contract p193, sample p194, MASTER_DOWNLOAD p191 |
| Retained Postman collection | `/home/ubuntu/nse-uat-contract/NSEInvest API Realease_21-05-2025.postman_collection 2.json`; SHA-256 `9db36cfb4bfb67b4481c9d8b462b0c534286f417e98067cd769b04e6f224f6fd`; 69 recursively enumerated requests |
| Official FAQ | [NSE_INVEST_API_FAQ_310725.pdf](https://nseinvestuat.nseindia.com/nsemfdesk/resources/upload/apidetails/NSE_INVEST_API_FAQ_310725.pdf), title **FAQ on NSE MF Invest – API**, updated **31/Jul/25**, p5 of 9, Access Related question **1.18**; SHA-256 `55aabf44a13dfe6169dd3ff7228131703d6c6e176b8d67de8e5e484b18e1ca8d` |

The FAQ was absent from the retained contract directory. It was retrieved from the
official HTTPS `nseinvestuat.nseindia.com` host without credentials or redirects.
The downloaded PDF is 277,461 bytes, nine pages; PDF creation/modification metadata
both read 31 July 2025, consistent with the visible update date. The mapping was
checked both through the official web document and local `pdftotext -layout`.
The initial download timed out; a bounded retry with a standard browser user agent
succeeded. No provider API was invoked to validate the values.

Question 1.18 asks for the AMC-code values for KYC Fresh Register. Its answer states:

> The RTA AMC code for E-KYC is as under:

The FAQ spells the question's field `amc_code`; the current manual supplies the
actual wire spelling `amcCode`. Both explicitly identify the same RTA AMC concept.
The older spelling does not change MoneyBowl's request contract.

## Complete mapping table published in FAQ question 1.18

These are all seven rows, in NSE's order, with labels preserved exactly. Every row
has the same authority: the official FAQ, 31 July 2025, p5, question 1.18. They are
verified published relationships, **not seeded or certified as the complete current
supported set** while the discrepancy below remains unresolved.

| RTA AMC code | Exact NSE label | Published support evidence |
| --- | --- | --- |
| `B` | Aditya Birla | Listed for fresh eKYC in FAQ 1.18 |
| `K` | Kotak Mahindra | Listed for fresh eKYC in FAQ 1.18 |
| `H` | HDFC Mutual Fund | Listed for fresh eKYC in FAQ 1.18 |
| `G` | Bandhan Mutual Fund | Listed for fresh eKYC in FAQ 1.18 |
| `CR` | Canara Robeco Mutual Fund | Listed for fresh eKYC in FAQ 1.18 |
| `O` | HSBC Asset Management | Listed for fresh eKYC in FAQ 1.18 |
| `UK` | Union Asset Management | Listed for fresh eKYC in FAQ 1.18 |

NSE provides no per-entry active flag, expiry, or environment-specific availability
in that table. Listing is documentary support as of the FAQ's date; it does not
prove current provider availability, successful registration for each AMC, or KYC
completion. The FAQ's p1 disclaimer gives NSE circulars precedence over the FAQ.
No contradictory named pair was found, but completeness is unresolved.

### Discrepancy that prevents the seed

The newer manual's p194 sample contains the isolated fragment
`" amcCode": " AXF"`. It does not name an AMC for this value. After accounting for
the sample's known padding defect, `AXF` is still absent from the FAQ's seven rows.
The retained Postman request's `amcCode` sample is `T`, also absent from the list
and without an AMC label. Neither a corrected current list nor an official
correction withdrawing these sample values was found in retained materials or targeted official-domain
searches. Official older manuals also contain the example, which establishes its
history but does not prove that it is obsolete.

The repository's retained conflict C042 resolves **example whitespace versus formal
field names**, not the validity or AMC identity of `AXF`. Extending that resolution
to dismiss the value would be an unsupported assumption. Conversely, assigning
`AXF` to an AMC from its letters, SCH, another provider, or general knowledge would
violate this task. The seven named pairs are not disputed; the claim that they are
the complete current supported set cannot be made safely.

Exact question for NSE: **For v1.9.7 `POST /nsemfdesk/api/v1/EKYC/EKYCREG`, is FAQ
1.18 dated 31 July 2025 the complete currently supported RTA AMC-code list, and is
the `AXF` example on p194 obsolete/incorrect? If `AXF` or any other additional code
is supported (including the retained Postman's `T` example), provide the complete
exact code/name list and any UAT-specific or active/inactive restrictions.**
No message was sent to NSE during this task.

## Dynamic mapping discovery

The complete retained manual, Postman request inventory, supporting provider file
structure and relevant repository contract notes were searched for AMC Master,
RTA AMC, `AMC_MASTER`, `RTA_AMC_MASTER`, `EKYC_AMC_LIST`, `amcCode`, eKYC and fresh
registration. No documented endpoint returning this mapping was found.

Manual p191 enumerates exactly `SCH`, `SIP`, `STP`, `SWP`, `NAV`, `SET` for
`POST /nsemfdesk/api/v2/reports/MASTER_DOWNLOAD`. The collection supplies a SCH
request and no additional RTA-AMC selector. References to an AMC master on manual
pp118, 121 and 124 concern funding/redemption report filters; they do not define a
mapping endpoint or equate those fields with fresh-eKYC RTA AMC codes.

This is a bounded finding about inspected official/retained contracts, not a claim
that NSE could have no unpublished service. There is no supported dynamic mapping
contract MoneyBowl can implement from the available evidence.

## Read-only DEV SCH cross-check

The latest validated SCH snapshot was discovered by joining snapshots, validations,
enabled UAT connections and active workspaces, ordering by version and creation
time. No snapshot ID was supplied to the discovery query.

- Snapshot `d1e227cc-3ca8-4f38-bc86-3aedf8eaa397`, version 2, created
  `2026-10-07 18:19:56.887709+00`.
- `SCH_OBSERVED_44_V2`, `STAGED_VALIDATED`, 15,352 rows, zero rejected rows.
- HTTP 200, `TEXT` media classification, `COMPLETE`, 4,084,985 bytes.
  The prior commissioning record identifies the HTTP media type as `text/plain`.
- Exact response SHA-256:
  `87cd63a822b8ce99d7d47508fa896180d6ec93c0ab315f126bd56df00ea30e3a`.
- Validation is structural/identity validation, not semantic certification.

The [cross-check evidence](evidence/nse_ekyc_sch_crosscheck_20261007.json) retains
the SELECT query and **all distinct AMC scheme and RTA scheme values** collected
for the recognizable AMC groups. Additional ABSL/SIF name groups are retained
separately; their inclusion is a discovery aid, not an approved lineage or eKYC
eligibility crosswalk. No scheme data is used as a seed input.

All groups below had the literal SCH `AMC ACTIVE FLAG` value `Y` (native field 27).
That is a scheme-master observation, not an eKYC support flag.

| FAQ comparison code | SCH AMC CODE | Rows | RTA AGENT CODE | Distinct AMC SCHEME CODE | Distinct RTA SCHEME CODE | Rows whose AMC SCHEME CODE equals FAQ code |
| --- | --- | ---: | --- | ---: | ---: | ---: |
| B | ABSL_MF | 248 | KARVY | 111 | 101 | 0 |
| B | BIRLAMF_SIF | 6 | CAMS | 5 | 5 | 0 |
| B | BIRLASUNLIFEMUTUALFUND_MF | 591 | CAMS | 342 | 333 | 3 |
| K | KOTAKMAHINDRAMF | 807 | CAMS | 352 | 339 | 0 |
| K | KOTAKMF_SIF | 4 | CAMS | 3 | 3 | 0 |
| H | HDFCMUTUALFUND_MF | 651 | CAMS | 271 | 273 | 0 |
| G | BANDHANMUTUALFUND_MF | 1,002 | CAMS | 406 | 414 | 13 |
| G | BANDHANMF_SIF | 46 | CAMS | 32 | 32 | 0 |
| CR | CANARAROBECOMUTUALFUND_MF | 193 | KARVY | 85 | 66 | 0 |
| O | HSBCMUTUALFUND_MF | 478 | CAMS | 185 | 184 | 15 |
| O | HSBCMF_SIF | 7 | CAMS | 5 | 5 | 0 |
| UK | UNIONMUTUALFUND_MF | 236 | CAMS | 110 | 110 | 0 |
| UK | UNIONMF_SIF | 3 | CAMS | 3 | 3 | 0 |

No collected RTA SCHEME CODE equals its group's comparison FAQ code. In particular,
Bandhan has 1,002 regular-master rows, `BANDHANMUTUALFUND_MF`, `CAMS`, `Y`, and only
13 rows with AMC SCHEME CODE `G`. The authority for the named `G` relationship is
FAQ 1.18. Its incidental presence in some scheme-code fields proves nothing about
a universal mapping.

| Field | Meaning established by the inspected contract |
| --- | --- |
| EKYCREG RTA AMC CODE | Fresh-eKYC selector defined by the manual and named FAQ list |
| SCH AMC CODE | Source AMC identifier in the scheme catalogue |
| SCH RTA AGENT CODE | Source agent observation such as CAMS/KARVY; shared by many AMCs |
| SCH AMC SCHEME CODE | Source scheme-level identifier; varies within an AMC |
| SCH RTA SCHEME CODE | Separate scheme-level identifier retained as reference evidence |

**A: SCH cannot reliably derive the mapping from this evidence. B: no documented
dynamic mapping API was found. C: a reviewed, source-controlled official reference
list is the appropriate authority model once NSE resolves current completeness.**
No field-name similarity, substring/prefix rule, name match or coincidental value
is an approved automatic mapper.

## Existing selector boundary and conditional implementation

The inspected [V2-A migration](../../supabase/migrations/20261007130243_mfd_onboarding_v2a_kyc_orchestration.sql)
already defines `moneybowl_onboarding.ekyc_amcs`:

- `code text PRIMARY KEY`, constrained to `^[A-Z0-9_-]{1,20}$`.
- `label text NOT NULL`, length 1–150.
- `source_reference text NOT NULL`, nonempty.
- `active boolean NOT NULL DEFAULT true`.
- RLS enabled, no policies, and no schema/table access for `anon`, `authenticated`
  or `service_role`. Direct browser insert/update/delete is denied.

Read-only hosted DEV verification found **zero rows** and confirmed these constraints,
RLS, zero policies and denied role privileges. No incompatible pre-existing mapping
was found. The table safely represents an approved reference list; no duplicate
table or schema redesign is needed.

`public.get_onboarding_kyc` first authorizes the live case actor and relationship.
Only `KYC_NOT_AVAILABLE`/`EKYC_DETAILS_REQUIRED` project active code/label pairs,
ordered by label. `public.request_onboarding_kyc` requires an exact active catalog
match before constructing the encrypted four-field request. Unknown/inactive codes
are rejected with `ekyc_details_required`; SCH is not consulted. An exact retry
returns the original operation rather than creating a new registration.

The existing repository/controller/page already consume that RPC's `amcs` list,
render labels, submit the selected code, and block the action for an empty catalog.
No frontend rewrite is required. Provider evidence, link authorization, encryption,
mutation retry fences, V1 account linkage, KYC states and UCC behavior are unchanged.

Once the source question is resolved, the smallest implementation is an additive
seed migration in the existing table, with exact confirmed code/label/provenance,
explicit activation, and a preflight that rejects conflicting rows rather than
silently overwriting them. Identical reapplication should be harmless; a previously
inactive row must not be silently reactivated. There must be no SCH dependency.

## Maintenance and DEV commissioning after review

1. Retain NSE's official clarification/current list, date, section, exact code/name
   entries and document hash. Resolve `AXF` and `T` explicitly; do not infer labels.
2. Review the differences against this evidence. Add only officially supported
   entries; use a new reviewed migration for additions, renames or deactivations.
   Preserve historical operation request evidence. Do not rewrite prior migrations.
3. Implement the conditional seed and focused positive/negative tests: exact entire
   list, labels/provenance, uniqueness, unknown/inactive rejection, browser mutation
   denial, authorized dropdown projection, and no automatic SCH conversion.
4. Run local onboarding/NSE security/concurrency regressions and validators, then
   obtain separate review and explicit hosted DEV deployment authorization.
5. Before deployment, read-only compare the DEV table with the approved migration
   preflight. Stop on unexpected entries or changed provenance. Apply only through
   the normal reviewed migration process, never a manual hosted patch.
6. In DEV, verify the assigned MFD sees the approved choices only at the eKYC stage,
   with no default, no account-search UI and no link rendered as ordinary text.
   Checking selector display does not require sending EKYCREG.
7. Any later real registration requires separate explicit commissioning authorization
   and genuine investor inputs. Record encrypted evidence and reconcile ambiguous
   sends without retrying blindly. Per-AMC acceptance and positive completed KYC
   remain uncommissioned by this task.

No EKYCREG mutation was sent during this task. The earlier retained initiation
success does not validate every code or establish provider completion. The source
question above must be answered before the seed or any mapper commissioning.

## Validation

All commands below ran in the isolated candidate worktree. SQL harnesses used
their own pinned Supabase PostgreSQL 17.6 disposable containers with `--network
none`, applied the full migration chain, and removed only their own containers.
No hosted reset or migration was run.

| Command | Result |
| --- | --- |
| `bash scripts/test_investor_onboarding_sql.sh` | PASS, exit 0; 30 SQL files including V1/V2-A and B01–B07, onboarding PL/pgSQL lint, six concurrency scripts (including all five KYC races), and the MFA commissioning inspection program |
| `bash scripts/test_nse_order_status_sql.sh` | PASS, exit 0; UCC and dispatcher plus 16 SQL suites twice (34 SQL executions), reference/facade PL/pgSQL lint, four reference/master/NAV-SET/frontend concurrency scripts |
| `python3 .github/scripts/validate_docs.py` | PASS; 60 Markdown files, links/structure/anchors |
| `python3 .github/scripts/validate_migration_history.py` | PASS; 27 frozen migration files unchanged |
| `python3 -m unittest discover -s .github/scripts -p test_validate_commits.py` | PASS; five tests |
| `python3 -m json.tool docs/architecture/evidence/nse_ekyc_sch_crosscheck_20261007.json > /dev/null` | PASS; evidence JSON parses |
| `python3 .github/scripts/validate_commits.py 'docs(nse): record eKYC AMC mapping evidence and source discrepancy'` | PASS; candidate commit subject |
| `git diff --check` and `git diff --cached --check` | PASS |

An additional seven-assertion local evidence check verified the 13 groups, all
seven FAQ comparison codes, uniqueness of each retained distinct-value array,
literal active flags, Bandhan's 1,002/13 observation and the 15,352/0 receipt.
These are evidence consistency checks, not tests of a new mapper.

Local receipts: `/tmp/nse-ekyc-mapper-onboarding-sql.log` and
`/tmp/nse-ekyc-mapper-nse-sql.log`; both had zero ERROR/FAIL lines and successful
process exit codes. The unchanged onboarding harness printed existing synthetic
contact fixtures; those values and long numeric fixtures were redacted from the
retained local receipt. No real PAN/contact data was accessed or added. No provider
fixture, operational link or secret material is committed in this evidence report.

Because Phase B was stopped, no seed tests were added or claimed. Deno, Flutter,
analyzer and build checks were not run: no executable source, test, dependency,
migration, schema, grant or RLS policy changed. The existing suites above were run
as regression evidence; their success does not resolve the provider discrepancy.
