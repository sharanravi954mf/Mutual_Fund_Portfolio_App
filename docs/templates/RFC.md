# RFC Template: [Title]

## Context
*Provide the background context, business problems, or system inefficiencies this proposal aims to address.*

## Objective
*State the clear functional or technical goals of the change.*

## Proposed Design
*Detail the technical implementation plan, folder locations, API routes, or database schemas.*

### Database Schema / Migrations
```sql
-- Draft SQL tables, columns, triggers or indexes
```

### Flutter Component / Domain Layer
*Detail feature layers or Providers required.*

## Security & Compliance Impact
- **RLS Verification**: *Describe Row Level Security policies.*
- **Data Encryptions**: *Are PII or PAN fields encrypted?*
- **Audit Trails**: *Detail the verification events emitted.*

## Performance & Scalability
- *Explain Edge Function execution boundaries (limit 50ms CPU).*
- *Explain database lock ordering to prevent deadlocks.*

## Alternatives Considered
*Compare alternative designs and explain why they were not chosen.*

## Open Questions
*List any technical or product ambiguities requiring architecture board input.*
