# CAMS characterization fixtures

This directory contains approved, redacted CAMS `.xls` characterization
fixtures. `cams_characterization_test.dart` requires:

- `BeforeCams.xls` — the source Excel 97-2003 tracker.
- `AfterCams.xls` — the approved expected tracker result.
- `UK_ARN-153316_UKM26-27E3.pdf` — a representative CAMS PDF invoice.

When an Open XML equivalent is approved, add it as a matched pair:

- `BeforeCams.xlsx`
- `AfterCams.xlsx`

The browser characterization suite must assert the same CAMS matching,
duplicate, unmatched-row, and `FILE NAME` outcomes for both pairs. An `.xls`
input must produce BIFF8 (`.xls`) output; it must not be relabelled `.xlsx`
content.

Do not commit unredacted client, tax, or banking data.
