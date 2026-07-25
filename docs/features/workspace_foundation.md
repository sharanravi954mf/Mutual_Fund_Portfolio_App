# Workspace & User Management Foundation

## Overview
This document specifies the Workspace and User Management foundation for Sharan Fincorp (Moneyball). It establishes the multi-tenant architecture scoping user access, roles, and resource isolation.

## Database Tables & Schema

### `public.workspaces`
Represents the root tenant aggregate.
- `id` (uuid, primary key): Unique workspace identifier.
- `name` (text, not null): Display name (e.g. "Personal Workspace").
- `slug` (text, not null, unique): Human-readable url-friendly identifier.
- `owner_profile_id` (uuid, references `profiles(id)`): logical owner profile.
- `workspace_status` (text, check status in `active`, `suspended`, `archived`): Workspace state.

### `public.workspace_memberships`
Defines profile membership in workspaces.
- `id` (uuid, primary key): Membership link ID.
- `workspace_id` (uuid, references `workspaces(id)`): Target workspace.
- `profile_id` (uuid, references `profiles(id)`): Joined user profile.
- `role` (text, check in `investor`, `advisor`, `admin`, `operations`, `client`): local role.
- `status` (text, check in `active`, `inactive`, `suspended`): Membership status.
- `joined_at` (timestamptz): Join timestamp.
- `ended_at` (timestamptz, nullable): Expiration or termination timestamp.

### `public.advisor_investor_assignments`
Enforces and stores assignment histories between Advisors and Investors.
- `advisor_id` (uuid, references `profiles(id)`): Assigned Advisor.
- `investor_id` (uuid, references `profiles(id)`): Assigned Investor.
- `status` (text, check in `active`, `ended`): Assignment state.

### `public.workspace_invitations`
Handles email invitations to join a workspace.
- `token_hash` (text, unique): SHA-256 hash of the plaintext token.

### `public.workspace_audit_logs`
Immutable historical log of all tenant configuration events.
- Enforced immutable via trigger raising custom SQL exceptions on update or delete.

## RLS Security Architecture
Row Level Security policies enforce the following constraints:
1. **Platform Admin**: Global access to all records in `workspaces`, `workspace_memberships`, `profiles`, etc.
2. **Workspace Admin**: Full access to manage invitations, assignments, and memberships within their assigned workspaces.
3. **Workspace Members**: Read access to members, details, and assignments of their active workspaces only.

## Dart & Flutter Services
- **WorkspaceService**: Query and manage workspaces.
- **MembershipService**: Add members and change membership state.
- **InvitationService**: Issue and accept invitations with hashed validation.
- **AssignmentService**: Assign investors to advisors within shared workspaces.
