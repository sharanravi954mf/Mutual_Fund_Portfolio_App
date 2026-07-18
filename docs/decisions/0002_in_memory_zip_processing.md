# Architectural Decision Record: In-Memory ZIP Invoice Processing

## Context
Administrators require signing and stamping of dozens of AMC distributor invoices monthly. Uploading and downloading these files individually inside the app would create high administrative latency.

## Decision
To maximize efficiency, we support uploading a single ZIP archive containing multiple invoice PDFs. 

To keep the application scalable on free-tier CPU constraints (50ms limit on Edge Functions):
* All decompression and PDF overlays are handled **in-memory** in the Deno Edge Function using `pdf-lib` and `@zip.js/zip.js`.
* Discarded files (macOS metadata `._` files and `__MACOSX/` directories) are filtered before processing to conserve memory.
* Output is streamed back in a single compressed ZIP response stream.

## Consequences
* Reduces network requests from N to 1.
* Eliminates disk read/write requirements on the server, ensuring compliance security.
