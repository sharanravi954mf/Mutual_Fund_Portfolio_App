# Architecture Review Template

## Review Information
- **Feature Name**: *e.g. Folio Verification*
- **Review Date**: *YYYY-MM-DD*
- **Reviewer**: *Lead Architect*

## Compliance Audits
1. **Identities Separation**: *Does the implementation separate Auth from business profiles?*
2. **Opaque Tokens**: *Does candidate discovery utilize expiring tokens?*
3. **Database RLS**: *Are RLS policies enabled and verified on all new tables?*
4. **Lock Ordering**: *Do mutation procedures lock requests first and then assignments to prevent deadlocks?*

## Assessment & Sign-Off
- **Status**: *Approved | Action Required | Blocked*
- **Required Action Items**: *List any outstanding architectural gaps.*
