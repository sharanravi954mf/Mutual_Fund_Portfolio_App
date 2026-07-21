# CAMS Invoice Signer Processing Boundary

The Invoice Signer now has shared job-controller, ZIP, PDF, and signature
wrappers plus a CAMS-only registrar processor. Existing dashboard UI, Supabase
Edge Functions, payloads, output filenames, and processing order are retained.

No KFintech/Karvy implementation, registrar selector, detection logic, or ZIP
optimization was added.

The web CAMS tracker updater now preserves `.xls` as a BIFF8 workbook and
`.xlsx` as an Open XML workbook. No matching or PDF-processing behavior changed.
