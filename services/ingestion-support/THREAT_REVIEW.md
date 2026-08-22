# Ingestion support focused threat review

| Threat | Control | Residual limitation |
| :--- | :--- | :--- |
| Bearer theft or boundary collapse | Three distinct 32+ character tokens, constant-time comparison, no token logging, `Cache-Control: no-store` | Host must provide HTTPS and secret rotation |
| SSRF and redirect abuse | Gmail origins are startup configuration restricted to HTTPS/localhost; request data cannot choose a URL; redirects are never followed | New providers require the same origin validation |
| Path traversal and command injection | No request path is opened; filenames are metadata-only, control-character bounded, and never passed to a shell | Provider filenames remain untrusted display metadata |
| Host-header poisoning | Explicit `ALLOWED_HOSTS`; no URL generation from Host | Deployment must add its exact hostname |
| Slow or oversized requests | Content-Length precheck, streaming byte counters, upload timeouts, strict MIME/method checks | Reverse proxy should also enforce matching limits/timeouts |
| Provider response amplification | Bounded streamed JSON, message/attachment/part counts, field and identifier limits; Gmail defaults to at most 4 pages, 100 inspected candidates, and 25 returned messages | Gmail poll performs bounded per-message metadata calls |
| Gmail page-one starvation | PDF/DBF attachment query, bounded `nextPageToken` traversal, repeated-token rejection, and page-fair output selection across inspected pages | Messages beyond the configured page/candidate window remain for a later design; Edge still owns sender allowlist validation |
| Provider redirect/data exfiltration | `follow_redirects=False`; fixed trusted provider roots; provider errors are generic | OAuth client remains a high-value host secret |
| OAuth credential leakage | Tokens never logged or persisted by this service; bounded TTL/LRU cache scoped to connector/mailbox/registrar identity | Restart, expiry, eviction, or cache miss fails closed and requires a new poll; current Edge fetch contract requires a single API replica |
| PDF parser exploitation | Pinned parser, magic/trailer/page/text/row/result bounds, strict known layouts, no OCR, memory only | New parser/library releases need fixture and adversarial regression |
| PDF mis-normalization | Synthetic characterization marker plus required alias headers; unknown/encrypted layouts fail closed; actual Edge parser contracts are tested | No live registrar CAS PDF layout is enabled; each requires a sanitized non-production fixture and deterministic tests |
| ClamAV evasion or outage | Raw bytes sent with `INSTREAM`, no path scanning, digest checked first, unavailable is distinct from infected, readiness requires `PONG` | Signature freshness/alerts are host operational duties |
| Archive/decompression bombs | Support service does not unpack archives; PDF page/text/result sizes bounded; ClamAV owns its internal archive limits | Edge DBF/archive behavior remains outside this service |
| Temp-file leakage | Read-only API filesystem, small tmpfs, statement bytes kept in memory, no persistence | Process memory protection depends on host isolation |
| Sensitive logs | Uvicorn access logs disabled; application emits no body/header/provider payload logs; errors use fixed codes | Host/reverse-proxy logs must also exclude headers and bodies |
| Cross-mailbox attachment fetch | Fetch requires a fresh token cached for the exact connector/mailbox/registrar identity tuple; concurrent mailboxes and registrar values remain isolated | Cache state is intentionally process-local and disappears on restart |
| Response cache leakage | `no-store`, minimal malware/health schemas, no content in errors | Reverse proxy must respect no-store and avoid body logging |

ClamAV TCP is unauthenticated by design and is therefore isolated on an
unpublished Docker network. Only the API may reach it. Hosted HTTP is forbidden;
TLS terminates at a reviewed reverse proxy or container platform ingress.
