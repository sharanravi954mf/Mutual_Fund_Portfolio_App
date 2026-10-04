-- READ ONLY. Supply an independently verified auth UUID with psql:
--   -v target_user_id=UUID -f platform_admin_commissioning_preflight.sql
-- No email predicate grants authority. No secret/evidence ciphertext is selected.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT u.id,u.email,u.email_confirmed_at,u.banned_until,u.deleted_at,u.is_anonymous,
 a.account_state,p.id profile_id,p.role,p.account_status
FROM auth.users u LEFT JOIN public.user_accounts a ON a.user_id=u.id
LEFT JOIN public.profiles p ON p.user_id=u.id WHERE u.id=:'target_user_id'::uuid;
SELECT g.id,g.grant_key,g.granted_at,g.granted_by,g.revoked_at,g.revoked_by
FROM platform_authority.grants g WHERE g.user_id=:'target_user_id'::uuid;
SELECT m.id,m.workspace_id,w.name,w.workspace_status,m.role,m.status,m.joined_at,m.ended_at,
 w.owner_profile_id=p.id AS owns_workspace,
 (SELECT count(*) FROM public.portfolios f WHERE f.workspace_id=w.id) AS portfolios,
 (SELECT count(*) FROM public.order_requests o WHERE o.workspace_id=w.id) AS orders
FROM public.profiles p JOIN public.workspace_memberships m ON m.profile_id=p.id
JOIN public.workspaces w ON w.id=m.workspace_id WHERE p.user_id=:'target_user_id'::uuid;
SELECT w.id,w.name,w.workspace_status,w.owner_profile_id FROM public.workspaces w
JOIN public.profiles p ON p.id=w.owner_profile_id WHERE p.user_id=:'target_user_id'::uuid;
SELECT a.id,a.workspace_id,a.advisor_id,a.investor_id,a.status,a.assigned_at,a.ended_at
FROM public.advisor_investor_assignments a JOIN public.profiles p ON p.id=a.advisor_id
WHERE p.user_id=:'target_user_id'::uuid;
SELECT ap.id advisor_profile_id,ap.profile_id,ea.id euin_assignment_id,ea.status
FROM public.profiles p JOIN public.advisor_profiles ap ON ap.profile_id=p.id
LEFT JOIN public.advisor_euin_assignments ea ON ea.advisor_profile_id=ap.id WHERE p.user_id=:'target_user_id'::uuid;
SELECT l.id,l.profile_id,l.link_status,l.verification_method,l.verified_at
FROM public.investor_account_links l WHERE l.user_id=:'target_user_id'::uuid;
SELECT ra.id,ra.request_id,ra.active,r.workspace_id,r.status
FROM public.verification_request_assignments ra JOIN public.verification_requests r ON r.id=ra.request_id
WHERE ra.advisor_account_id=:'target_user_id'::uuid;
SELECT i.id,i.workspace_id,i.role,i.status,i.expires_at
FROM public.workspace_invitations i JOIN public.profiles p ON p.id=i.invited_by WHERE p.user_id=:'target_user_id'::uuid;
SELECT o.workspace_id,o.status,count(*) AS historical_order_references
FROM public.order_requests o JOIN public.profiles p ON p.id IN (o.initiated_by_profile_id,o.reviewed_by_profile_id)
WHERE p.user_id=:'target_user_id'::uuid GROUP BY o.workspace_id,o.status;
SELECT s.workspace_id,s.mailbox_connection_id,s.flow_kind,s.completed_at,s.failed_at
FROM public.mailbox_oauth_authorization_states s JOIN public.profiles p ON p.id=s.actor_profile_id
WHERE p.user_id=:'target_user_id'::uuid;
SELECT f.id,f.factor_type,f.status FROM auth.mfa_factors f WHERE f.user_id=:'target_user_id'::uuid;
ROLLBACK;
