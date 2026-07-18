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
