# Security Review Template

## Review Information
- **Target Changes**: *e.g. Database migrations, Stored procedures*
- **Review Date**: *YYYY-MM-DD*
- **Reviewer**: *Security Lead*

## Threat Vector Audits
1. **PII Isolation**: *Are PAN or other sensitive variables encrypted using Vault secrets?*
2. **HMAC Indexes**: *Are searches executed on hashes rather than plaintext lookups?*
3. **Log Scrubbing**: *Do Edge Functions filter out sensitive inputs before printing logs?*
4. **Security Definer search_path**: *Do database functions declare explicit public search_paths?*

## Assessment & Sign-Off
- **Status**: *Approved | Action Required | Blocked*
- **Required Action Items**: *List any outstanding security issues.*
