# MoneyBowl MFD Investor Onboarding V2 — KYC-First Frozen Contract

> **STATUS: FROZEN — BUSINESS OWNER APPROVED — 07 Oct 2026**
>
> This document is the canonical MoneyBowl investor-onboarding product and architecture contract for V2. Future onboarding implementation must conform to it. If code, older documentation, implementation assumptions, or third-party examples conflict with this contract, implementation must stop and the conflict must be resolved explicitly.
>
> Semantic changes require explicit business-owner approval and a new version or architecture decision record. UI wording, visual polish, accessibility, and internal implementation mechanics may evolve only when they preserve the frozen behavior below.

## 1. Relationship to V1

[MFD-led Investor Onboarding V1](MFD_LED_INVESTOR_ONBOARDING_V1.md) remains the implemented identity/security foundation. V2 does not replace its canonical investor model, Auth-account separation, PAN deduplication, MFD assignment, workspace containment, encrypted drafts, audit trail, idempotency, or Explorer/signup convergence.

V2 freezes the **product journey above that foundation**:

```text
V1 foundation
  Auth Account != Investor Business Identity
  canonical investor / PAN resolution
  MFD <-> investor authority
  verified account linkage
  encrypted resumable state
  audit + idempotency
          |
          v
V2 frozen journey
  Add Investor
    -> PAN
    -> resolve/fetch
    -> KYC Check
    -> provider eKYC hand-off when required
    -> only missing details
    -> nominee
    -> FATCA
    -> bank
    -> review/consent
    -> UCC registration
    -> post-registration requirements
    -> Ready to Transact
```

B07 bank/mandate policy is downstream of onboarding. It is not the primary V2 onboarding slice.

## 2. Product principle

The MFD onboards an **investor**, not a MoneyBowl account.

The MFD sees:

```text
Clients -> Add Investor
```

The MFD must not see or manage Explorer lookup, MoneyBowl-user lookup, Auth-account selection, account linking, or manual Explorer-to-Investor conversion. MoneyBowl resolves Auth-account linkage privately through the V1 verified-identity boundary.

The frozen interaction principle is:

> **Ask for PAN first. MoneyBowl determines what is already known and asks only for what is still needed.**

MoneyBowl must not expose NSE's complete data model as one giant form simply because those fields exist in a provider contract.

## 3. Frozen end-to-end journey

```text
MFD: Add Investor
        |
        v
      PAN
        |
        v
Resolve / Fetch Details
        |
        v
    Check KYC
      /   \
     /     \
KYC compliant   KYC unavailable / not compliant
     |                    |
     |              Proceed to eKYC
     |                    |
     |              NSE eKYC initiation
     |                    |
     |              CAMS / provider hand-off
     |                    |
     |              Investor completes KYC
     |                    |
     +---------- KYC compliant
                         |
                         v
              Ask only missing details
                         |
                         v
                       Address
                         |
                         v
                  Nominee: Yes / No
                         |
                         v
                       FATCA
                         |
                         v
                        Bank
                         |
                         v
                Review + declarations
                         |
                         v
                Create / register NSE UCC
                         |
                         v
               Post-registration actions
                 eLog / nominee / mandate
                         |
                         v
                 READY TO TRANSACT
```

The stages may be grouped differently on mobile or desktop, but their semantics and ordering constraints are frozen.

## 4. PAN-first identity resolution

PAN is the first substantive onboarding input. After a syntactically valid PAN is supplied, MoneyBowl must use the V1 canonical identity boundary to:

1. search for the canonical investor business identity;
2. detect duplicate/conflicting investor identities;
3. reuse a compatible existing investor rather than creating a duplicate;
4. determine what trusted/provider-derived information can be reused;
5. privately evaluate whether a verified MoneyBowl Auth account may already or later be linked.

PAN is a business-identity key. PAN alone is **not** authentication of a MoneyBowl Auth account. Ambiguity must fail closed into reconciliation rather than creating another investor.

## 5. KYC Check is early and explicit

After identity resolution, the MFD must have a prominent **Check KYC** action, or an equivalent automatic check with equally clear status.

Provider responses—not MFD assertions—determine verified KYC evidence. The UI should expose a bounded business status such as:

```text
Verified / Compliant
Not Available
In Progress
Action Required
Unable to Verify
```

Do not ask the MFD to manually manufacture a KYC type/status when MoneyBowl can obtain authoritative evidence. An MFD-reported status is not verified KYC evidence.

## 6. eKYC hand-off

If KYC Check establishes that fresh eKYC is required, MoneyBowl shows:

```text
[ Proceed to eKYC ]
```

MoneyBowl orchestrates the provider hand-off. It does **not** implement Aadhaar KYC, Offline Aadhaar XML processing, Video KYC, liveness, or regulated KYC adjudication itself.

Conceptually:

```text
MoneyBowl
  -> approved NSE fresh-eKYC initiation contract
  -> provider-issued workflow/link
  -> investor
  -> CAMS / authorised provider
  -> status/result
  -> MoneyBowl resumes onboarding
```

Provider-supported methods may include Aadhaar, Offline Aadhaar XML, or Video KYC, but those options are provider-owned and must not be hard-coded as a permanent MoneyBowl guarantee.

MoneyBowl must preserve the external operation/result evidence required for safe resume/reconciliation. No blind re-initiation after an ambiguous provider outcome.

## 7. Progressive disclosure after KYC

Once KYC is compliant, MoneyBowl asks only for information still required for the investor's applicable path. Trusted/provider-confirmed values should be prefilled or read-only where appropriate.

Missing downstream fields may include legal/contact details, address, tax/occupation data, holding information, FATCA, bank information, nomination, communication choices, declarations, and consent. No mandatory fact may be fabricated simply to progress the workflow.

## 8. Nomination UX

Nomination is a focused decision:

```text
Do you wish to add a nominee?
[ Yes ] [ No ]
```

`No` records explicit opt-out evidence required by the applicable business/provider process and skips nominee-detail UI. `Yes` progressively requests applicable nominee details.

A missing field must not silently become opt-out unless an authoritative provider contract and business-owner decision explicitly require that behavior.

## 9. FATCA UX

FATCA is its own step. Request only the applicable tax-residency facts and declarations. No tax residency, occupation, declaration, or provider code may be fabricated.

## 10. Bank UX and verification boundary

Bank capture is a focused step. Collect/derive applicable account number, account type, IFSC, MICR, account-holder information, and other provider-required fields. Sensitive values remain encrypted and masked under the V1 boundary.

**Bank capture is not bank verification.**

The UI must distinguish entered/submitted/verified states. A bank remains unverified until trusted verification/provider evidence exists.

## 11. Review, consent, and declarations

Before external registration, provide a clear review/consent step. Important consent must be auditable, not reduced to an unaudited boolean.

Where applicable preserve consent/declaration version, actor, timestamp, terms/version reference, workflow/request reference, and provider-operation reference. Missing required consent blocks the dependent mutation.

## 12. UCC registration is not the final state

A successful NSE client/UCC registration does not automatically mean the investor is ready to transact.

MoneyBowl must distinguish:

```text
NSE registration submitted
NSE registration successful
Post-registration action required
Ready to Transact
```

Applicable post-registration requirements may include eLog/investor authentication, nominee authentication, mandate authentication/registration when requested, bank/provider verification, or other NSE-mandated prerequisites.

Exact requirements come from authoritative provider contracts. MoneyBowl must show remaining actions rather than declaring success too early.

## 13. Ready-to-transact definition

`READY_TO_TRANSACT` is a **derived** business state. It may be shown only when all applicable identity, KYC, provider, consent, bank, and post-registration prerequisites for the supported transaction path are satisfied.

It must not be set merely because PAN exists, KYC was typed as complete, UCC write returned success, a bank was entered, or the MFD completed the form.

## 14. Auth-account / Explorer behavior stays behind the scenes

The V1 arrival-order model remains frozen:

```text
User signs up first
  -> verified identity
  -> safe existing investor match?
       yes -> same Auth account -> Investor experience
       no  -> Explorer

MFD onboards first
  -> canonical investor may exist without login
  -> investor later signs up
  -> safe verified match
  -> same Auth account -> Investor experience

Existing Explorer later becomes investor
  -> MFD uses ordinary Add Investor
  -> MFD never selects Explorer
  -> MoneyBowl privately finds compatible verified Auth identity
  -> safe linkage when V1 evidence threshold is satisfied
```

No second login is created. MFD-entered email/mobile is not itself proof of Auth ownership. Conflicts remain reconciliation states.

## 15. Ownership matrix

| Stage | MFD | MoneyBowl | NSE / Exchange | CAMS/KRA/authorised provider | Investor |
| --- | --- | --- | --- | --- | --- |
| Add Investor | Enters genuine known facts | Validates/encrypts/resolves canonical investor | — | — | Supplies facts where applicable |
| PAN resolution | Starts flow | Deduplicates/resolves | May provide downstream lookup | May hold KYC evidence | Owns identity |
| KYC Check | Requests/views | Orchestrates and projects safe status | Exposes authorised report interface | Supplies underlying status/evidence | — |
| Fresh eKYC | Starts when required | Orchestrates hand-off/tracks result | Initiates/returns approved workflow | Performs regulated KYC | Completes KYC |
| Remaining details | Enters missing facts | Prefills trusted facts/validates | Defines registration requirements | — | Supplies/approves facts |
| Nomination | Records choice/details | Persists/validates evidence | Consumes compatible data | — | Makes choice |
| FATCA | Captures applicable facts | Persists/validates evidence | Consumes applicable data | Registrar may process | Makes declarations |
| Bank | Captures bank facts | Encrypts/masks/tracks verification | Consumes bank data/status | May participate in verification | Owns/authorises bank |
| Consent | Presents/assists | Records exact provenance | Consumes required declarations | — | Provides required consent/authentication |
| UCC registration | Starts/reviews | Uses existing evidence-safe operation lifecycle | Creates/processes UCC | — | May authenticate |
| Post-registration | Monitors/assists | Tracks pending actions | eLog/nominee/mandate/etc. | Provider-specific actions | Completes required authentication |
| Ready state | Sees readiness | Derives readiness | Provider state contributes | Provider state contributes | Uses eligible transaction flows |

This matrix is architectural. Exact API ownership and field requirements must be verified against current authoritative provider documentation before implementation.

## 16. Frozen lifecycle semantics

Implementations may use more granular internal states, but must preserve these externally meaningful distinctions:

```text
DRAFT
IDENTITY_RESOLVED
KYC_CHECK_REQUIRED
KYC_CHECKING
KYC_COMPLIANT
EKYC_REQUIRED
EKYC_INITIATION_PENDING
EKYC_IN_PROGRESS
PROFILE_DETAILS_REQUIRED
NOMINATION_REQUIRED
FATCA_REQUIRED
BANK_REQUIRED
CONSENT_REQUIRED
UCC_READY
UCC_REGISTRATION_PENDING
UCC_REGISTERED
POST_REGISTRATION_ACTION_REQUIRED
READY_TO_TRANSACT

IDENTITY_RECONCILIATION_REQUIRED
RELATIONSHIP_RECONCILIATION_REQUIRED
PROVIDER_RECONCILIATION_REQUIRED
BLOCKED
```

Not every investor visits every state. A KYC-compliant investor skips the eKYC states. Code names may differ only if semantics map unambiguously to this contract.

## 17. Frozen security/evidence invariants

The following are non-negotiable:

- MFD authority is derived server-side from approved live workspace authority.
- PAN deduplicates investor business identity; it does not authenticate an Auth account.
- Auth linkage follows the V1 verified-identity boundary and remains invisible to the MFD.
- Cross-workspace MFD access fails closed.
- Existing investor relationships are never silently stolen or reassigned.
- Identity/contact conflicts enter reconciliation.
- MFD-reported KYC is not verified KYC.
- Bank capture is not bank verification.
- Provider-known values may be reused only with trustworthy provenance.
- Sensitive PAN/bank/contact/provider payloads remain encrypted/masked.
- No blind retry after an ambiguous external mutation.
- Exact external request/result evidence is preserved under the integration model.
- No fabricated DOB, KYC, CKYC, bank verification, FATCA, nomination, declaration, consent, or provider codes.

## 18. Frozen acceptance scenarios

| Scenario | Required result |
| --- | --- |
| New PAN, KYC compliant | Resolve/create canonical investor; skip eKYC; continue with missing details |
| New PAN, KYC unavailable | Show `Proceed to eKYC`; do not ask MFD to fake KYC |
| eKYC initiated | Preserve provider operation; show in-progress/action state |
| eKYC completes | Resume onboarding without restarting investor |
| Existing canonical investor | Reuse investor; no duplicate |
| Existing Explorer matches safely | Link privately; MFD never selects Explorer |
| Investor has no Auth account | Onboarding proceeds; account can link later |
| Investor signs up after MFD onboarding | Safe verified match routes directly to Investor experience |
| Signup has no investor match | Explorer fallback |
| Split email/mobile Auth candidates | Identity reconciliation; no guessing |
| Duplicate/conflicting PAN identities | Identity reconciliation; no duplicate investor |
| Unrelated MFD knows PAN/contact | No authority is gained |
| Provider knows name/DOB | Reuse trusted values where contract permits; ask only for missing fields |
| Nominee = No | Record explicit opt-out evidence; skip nominee details |
| Nominee = Yes | Request applicable nominee details |
| Bank entered | Remains unverified until trusted evidence |
| Missing FATCA/consent | Dependent registration blocked |
| UCC registration success | Do not automatically claim Ready to Transact |
| Post-registration action outstanding | Show exactly what remains |
| All applicable prerequisites complete | Derive `READY_TO_TRANSACT` |
| Ambiguous provider mutation/result | Reconcile original operation; do not blindly resend |

## 19. Not frozen as implementation detail

The following may evolve if the frozen semantics stay intact: styling, responsive grouping, progress UI, equivalent button wording, internal table/function/class names, worker decomposition, polling versus events, provider transport representation, provider URL/method list, and internal state granularity.

Provider contracts remain authoritative for endpoint paths, fields, requiredness, authentication, schemas, statuses, and regulated workflow details.

## 20. Change control

This document is frozen. Changing any of the following requires explicit business-owner approval and a new version/ADR:

- PAN-first onboarding;
- early KYC Check;
- provider eKYC hand-off instead of MoneyBowl performing regulated KYC;
- ask-only-missing/progressive disclosure;
- invisible Auth/Explorer resolution;
- nomination Yes/No semantics;
- bank capture separated from verification;
- explicit consent provenance;
- UCC registration not equaling Ready to Transact;
- post-registration readiness;
- security/evidence invariants above.

Implementation must not silently reinterpret these rules to fit an API, existing code, or a third-party application's behavior.

## 21. Next implementation priority

The next onboarding engineering slice is **KYC-first orchestration**, not further B07 expansion.

Before coding, statically revalidate the current authoritative NSE contract for PAN-based KYC reads, fresh eKYC initiation, fresh eKYC status, required AMC/provider selectors, provider-link semantics/expiry, and reconciliation rules.

Only after that characterization should MoneyBowl replace the V1 giant-form experience with this V2 progressive journey.

## 22. Provenance

Frozen by business-owner decision on **07 Oct 2026** after review of the MoneyBowl V1 onboarding foundation and user-provided reference screenshots from NSE/CAMS and a third-party MFD onboarding walkthrough.

Those references informed the desired UX. They are not the authoritative technical API contract; current official NSE/CAMS/provider documentation remains mandatory for implementation.
