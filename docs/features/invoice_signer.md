# Feature Specification: Invoice PDF & ZIP Signer

## 1. Overview
The Invoice Signer allows administrators of Sharan Fincorp to manually upload distributor invoices (in PDF format or packaged inside a ZIP archive), apply transparent company stamp and signature overlays on the final page of each document, and download the signed output directly.

## 2. In-Memory Processing Workflow
* **ZIP Archive Handling**: If a ZIP file is uploaded:
  * The Supabase Edge Function decompresses the archive in-memory using `@zip.js/zip.js`.
  * PDF files are extracted and processed individually.
  * System metadata folders like `__MACOSX/` and resource forks starting with `._` are automatically bypassed.
* **Coordinate Anchoring**: Overlays are anchored using page point measurements (A4 space boundary: 595 x 842).
* **Compression & Download**: Signed PDFs are bundled back into a new ZIP archive and returned as a single download attachment `_SIGNED.zip` to minimize network overhead.

## 3. UI Layout
* Located on the Admin Dashboard under the **Invoice Signer** tab.
* Left Panel: Three big file selector cards (Invoice PDF/ZIP, Signature PNG, Stamp PNG).
* Right Panel: Fine-tuning sliders for coordinates and the action button with loading indicators.

## 4. CAMS Processor Boundary

The working CAMS workflow is now represented by a CAMS-only registrar boundary
in Flutter. ZIP decryption, signing, stamping, repackaging, output naming, and
download handling remain shared controller/services responsibilities. The CAMS
processor only extracts invoice metadata and delegates tracker updates to the
existing updater, preserving its current matching and `FILE NAME` behavior.

For CAMS ZIP jobs, PDF text is extracted once per document and retained for the
tracker update. The existing tracker matching receives the same ordered
filename/text inputs without a second PDF.js extraction pass.

KFintech parsing and tracker-update support are available behind the
registrar-processor boundary. Progressive internal detection now validates the
tracker headers, the archive structure, then one sample invoice before a
registrar is confirmed. The normal workflow routes confirmed CAMS and
KFintech uploads automatically and reports the source in business-friendly
language. It does not expose a registrar selector.

For readable ZIP uploads, signing uses the archive manifest to retain archive
hierarchy, entry order, and non-PDF companion files while replacing only PDFs
that sign successfully. Password-protected CAMS ZIPs retain the existing
decryption fallback. A tracker with zero matching invoices does not download an
unchanged workbook and instead reports that no matching invoices were found.

## 5. CAMS Tracker Formats

The dashboard accepts `.xls` and `.xlsx` CAMS trackers. On Flutter Web, the
existing SheetJS processor reads both formats and preserves the uploaded format
when writing the updated tracker: BIFF8 for `.xls` and Open XML for `.xlsx`.
Matching, duplicate selection, unmatched handling, and `FILE NAME` updates all
use the same CAMS processing loop.

The Dart `excel` fallback supports `.xlsx` only. The current Invoice Signer is
therefore fully format-preserving for its supported web workflow; a future
native implementation would need an additional legacy-Excel reader/writer for
identical `.xls` support outside the browser.

## 6. Characterization Fixtures

The real, redacted `.xls` fixture set is `BeforeCams.xls`, `AfterCams.xls`, and
`UK_ARN-153316_UKM26-27E3.pdf`. Equivalent `.xlsx` fixtures are optional until
they are approved, but must be added as `BeforeCams.xlsx` and `AfterCams.xlsx`
together. See `test/fixtures/cams/README.md`.
