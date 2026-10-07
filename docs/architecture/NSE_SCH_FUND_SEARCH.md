# NSE SCH-backed Fund Search

## Decision

MoneyBowl Fund Search uses the official NSE Invest consolidated scheme master (`SCH`)
instead of the former third-party mutual-fund search feed. The provider route is the
existing member-scoped `POST /nsemfdesk/api/v2/reports/MASTER_DOWNLOAD` contract with
body `{"file_type":"SCH"}`. The bulk file is captured, validated and stored once;
browser searches query a bounded local projection and never call NSE per keystroke.

Factsheets remain a separate feature. SCH is catalogue/reference data and therefore
belongs to Fund Search; it is not a replacement for factsheet PDFs, fund-manager or
portfolio-holdings content.

## 2026-10-07 UAT transport evidence

A DEV UAT SCH request using the commissioned NSE member binding returned HTTP 200,
`text/plain`, identity encoding, and **no Content-Length**. The original B06 transport
therefore classified it `UNVERIFIABLE` before reading the body. That attempt is
retained as terminal evidence and is not reused.

The additive transport change permits a missing Content-Length only when all of the
following remain true:

- identity encoding is used;
- the response reaches EOF;
- the existing 16 MiB maximum is enforced while streaming;
- every persisted chunk retains its exact SHA-256;
- the complete body digest is independently verified by SQL;
- malformed Content-Length and compressed responses remain rejected;
- a supplied Content-Length must still exactly equal the captured bytes.

This is a narrow compatibility change based on observed NSE UAT framing. It does not
relax provider-response parsing or the existing evidence/ownership boundaries.

## Search projection

`public.search_nse_schemes(text, integer)` is the only browser-facing SCH reader. Raw
`nse_reference` tables remain private. It selects the latest validated
`SCH_OBSERVED_44_V1` UAT snapshot from the single commissioned runtime binding and
returns at most 50 rows.

The projected fields are:

- NSE scheme code and scheme name;
- AMC code;
- RTA agent code;
- RTA scheme code;
- AMC scheme code;
- ISIN;
- scheme type and plan type;
- AMC active flag.

No workspace ID, connection ID, credentials, raw provider body, investor data, or
other private evidence is exposed. The projection is reference-only: code/name
equality does not establish transaction eligibility, registrar crosswalk approval,
NAV authority, or an eKYC RTA-AMC mapping.

## eKYC investigation boundary

NSE v1.9.7 calls `EKYCREG.amcCode` an **RTA AMC CODE**. SCH has distinct `AMC CODE`
and `RTA AGENT CODE` columns, so MoneyBowl does not equate either field to the eKYC
code by name. The Fund Search details view intentionally displays the retained SCH
source values so DEV can compare a known provider eKYC mapping (for example a code
confirmed by NSE documentation) against actual SCH rows. Any automated eKYC selector
mapping requires separate evidence and review.

## Third-party source retirement

The old browser proxy for the former third-party mutual-fund API is removed. Both
Explorer Fund Search and the legacy client/admin search paths use the local NSE SCH
projection. The old daily-NAV updater is also fail-closed rather than continuing to
use that source. NSE `NAV` MASTER_DOWNLOAD already has a separate evidence model, but
NAV publication remains blocked until its crosswalk/source policy is commissioned;
no NAV value is fabricated from SCH.

## Refresh model

A validated SCH snapshot is immutable. A new explicit master-download job creates a
new snapshot/version. Fund Search resolves the latest validated UAT SCH snapshot on
each query, so a later commissioned refresh can become visible without rewriting old
reference evidence. Scheduling cadence is a separate operational decision and is not
introduced by this slice.

## 2026-10-07 SCH terminal-EOF compatibility

A second real DEV UAT SCH capture completed with HTTP 200 `text/plain`, identity
encoding, EOF and 4,084,985 captured bytes. The exact retained file used the pinned
44-column header and 15,352 non-empty records, with consistent CRLF separators, but
NSE did **not** emit a CRLF after the final record. The existing
`SCH_OBSERVED_44_V1` validator therefore rejected the snapshot solely because V1
required one terminal newline. Read-only characterization of the retained evidence
confirmed the header matches after CRLF normalization, every row has 44 columns,
the existing core field/length checks pass, and scheme/serial identities are unique.

`SCH_OBSERVED_44_V2` changes only that framing rule: after consistent LF/CRLF
normalization it accepts either one terminal LF or immediate EOF after the final
record. Double terminal newlines, blank records, mixed/bare line endings, controls,
quotes, embedded BOM, schema changes, malformed rows and duplicate identities remain
rejected exactly as before. Historical V1 validation receipts are untouched; the
private validator registry is advanced atomically to V2 for future SCH snapshots and
then remains immutable. Browser Fund Search can read validated V1 or V2 snapshots.
