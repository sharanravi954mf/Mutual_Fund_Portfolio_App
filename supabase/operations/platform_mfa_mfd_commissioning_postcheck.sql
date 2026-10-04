-- Manual inspection only. NOT a browser-session proof or a commissioning PASS.
-- psql -X -v ON_ERROR_STOP=1 -v project_ref=<attested DEV ref> \
--   -v operator_user_id=<UUID> -v applicant_user_id=<UUID> \
--   -v application_id=<application UUID> -f <this file>
-- Independently verify connection host/project in Dashboard first. Database name
-- is not project identity. LOCAL_DISPOSABLE is for the isolated test harness only.
-- Requires an already authorized inspection connection; never grant extra ACLs.
BEGIN TRANSACTION READ ONLY;
WITH raw AS (
 SELECT :'project_ref'::text project_ref, :'operator_user_id'::text operator_text,
        :'applicant_user_id'::text applicant_text, :'application_id'::text application_text
), p AS (
 SELECT project_ref, application_text,
 CASE WHEN operator_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN operator_text::uuid END operator_id,
 CASE WHEN applicant_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN applicant_text::uuid END applicant_id,
 CASE WHEN application_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN application_text::uuid END application_id
 FROM raw
), errors AS (
 SELECT array_remove(ARRAY[
 CASE WHEN project_ref NOT IN ('rskryngwzyuzmiwtriyy','LOCAL_DISPOSABLE') THEN 'dev_project_attestation_required' END,
 CASE WHEN operator_id IS NULL THEN 'invalid_operator_uuid' END,
 CASE WHEN applicant_id IS NULL THEN 'invalid_applicant_uuid' END,
 CASE WHEN application_id IS NULL THEN 'invalid_application_uuid' END,
 CASE WHEN operator_id=applicant_id THEN 'operator_and_applicant_must_differ' END,
 CASE WHEN operator_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p.operator_id) THEN 'operator_not_found' END,
 CASE WHEN applicant_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p.applicant_id) THEN 'applicant_not_found' END,
 CASE WHEN application_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.mfd_applications a WHERE a.id=p.application_id) THEN 'application_not_found' END,
 CASE WHEN EXISTS(SELECT 1 FROM public.mfd_applications a WHERE a.id=p.application_id AND a.applicant_user_id<>p.applicant_id) THEN 'application_applicant_mismatch' END
 ],NULL) validation_errors FROM p
), valid AS (
 SELECT p.operator_id,p.applicant_id,p.application_id FROM p,errors
 WHERE cardinality(errors.validation_errors)=0
), a AS (
 SELECT app.id,app.applicant_user_id,app.status,app.version,app.review_started_by,
        app.decided_by,app.profile_id,app.workspace_id,app.membership_id
 FROM public.mfd_applications app JOIN valid v ON app.id=v.application_id
), profiles AS (
 SELECT x.id,x.role,x.account_status FROM public.profiles x JOIN valid v ON x.user_id=v.applicant_id
), workspaces AS (
 SELECT w.id FROM public.workspaces w JOIN profiles p ON w.owner_profile_id=p.id
)
SELECT jsonb_build_object(
 'inspection','postcheck',
 'transaction_read_only',current_setting('transaction_read_only'),
 'validation_errors',(SELECT to_jsonb(validation_errors) FROM errors),
 'parameters_valid',(SELECT cardinality(validation_errors)=0 FROM errors),
 'operator_user_id',(SELECT operator_id FROM valid),
 'applicant_user_id',(SELECT applicant_id FROM valid),
 'application_id',(SELECT application_id FROM valid),
 'application_supplied',(SELECT application_text<>'' FROM p),
 'browser_session_confirmed',false,
 'operator_eligible',EXISTS(SELECT 1 FROM auth.users u JOIN valid v ON u.id=v.operator_id
    WHERE u.email_confirmed_at IS NOT NULL AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false)
      AND (u.banned_until IS NULL OR u.banned_until<=now())),
 'applicant_eligible_account',EXISTS(SELECT 1 FROM auth.users u JOIN valid v ON u.id=v.applicant_id
    WHERE u.email_confirmed_at IS NOT NULL AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false)
      AND (u.banned_until IS NULL OR u.banned_until<=now())),
 'applicant_account_state',(SELECT u.account_state FROM public.user_accounts u JOIN valid v ON u.user_id=v.applicant_id),
 'operator_grants',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'grant_key',g.grant_key,'revoked',g.revoked_at IS NOT NULL) ORDER BY g.id)
    FROM platform_authority.grants g JOIN valid v ON g.user_id=v.operator_id),'[]'::jsonb),
 'operator_factors',jsonb_build_object(
    'verified_totp',(SELECT count(*) FROM auth.mfa_factors f JOIN valid v ON f.user_id=v.operator_id WHERE f.factor_type='totp' AND f.status='verified'),
    'pending_totp',(SELECT count(*) FROM auth.mfa_factors f JOIN valid v ON f.user_id=v.operator_id WHERE f.factor_type='totp' AND f.status='unverified'),
    'unsupported',(SELECT count(*) FROM auth.mfa_factors f JOIN valid v ON f.user_id=v.operator_id WHERE f.factor_type<>'totp'),
    'corroborating_live_aal2_sessions',(SELECT count(*) FROM auth.sessions s JOIN valid v ON s.user_id=v.operator_id
       JOIN auth.mfa_factors f ON f.id=s.factor_id AND f.user_id=s.user_id
       WHERE s.aal='aal2' AND f.status='verified' AND (s.not_after IS NULL OR s.not_after>now()))),
 'target_counts',jsonb_build_object(
    'profiles',(SELECT count(*) FROM profiles),
    'investor_profiles',(SELECT count(*) FROM profiles WHERE role='investor'),
    'owned_workspaces',(SELECT count(*) FROM workspaces),
    'memberships',(SELECT count(*) FROM public.workspace_memberships m JOIN profiles p ON m.profile_id=p.id),
    'investor_links',(SELECT count(*) FROM public.investor_account_links l JOIN valid v ON l.user_id=v.applicant_id),
    'investor_assignments',(SELECT count(*) FROM public.advisor_investor_assignments x WHERE x.advisor_id IN(SELECT id FROM profiles) OR x.investor_id IN(SELECT id FROM profiles)),
    'advisor_profiles',(SELECT count(*) FROM public.advisor_profiles x JOIN profiles p ON x.profile_id=p.id),
    'euin_assignments',(SELECT count(*) FROM public.advisor_euin_assignments e JOIN public.advisor_profiles x ON e.advisor_profile_id=x.id JOIN profiles p ON x.profile_id=p.id),
    'integration_accounts',(SELECT count(*) FROM public.integration_accounts x WHERE x.workspace_id IN(SELECT id FROM workspaces) OR x.investor_profile_id IN(SELECT id FROM profiles)),
    'integration_operations',(SELECT count(*) FROM public.integration_operations x WHERE x.workspace_id IN(SELECT id FROM workspaces)),
    'nse_connections',(SELECT count(*) FROM nse_reference.connections x WHERE x.workspace_id IN(SELECT id FROM workspaces)),
    'platform_grants',(SELECT count(*) FROM platform_authority.grants g JOIN valid v ON g.user_id=v.applicant_id)),
 'global_baseline',CASE WHEN EXISTS(SELECT 1 FROM valid) THEN jsonb_build_object(
    'platform_grants',(SELECT count(*) FROM platform_authority.grants),
    'platform_events',(SELECT count(*) FROM platform_authority.events),
    'grants_integrity',(SELECT md5(coalesce(string_agg(g.id::text||g.user_id::text||g.grant_key||coalesce(g.revoked_at::text,''),'|' ORDER BY g.id),'')) FROM platform_authority.grants g),
    'investor_links',(SELECT count(*) FROM public.investor_account_links),
    'investor_assignments',(SELECT count(*) FROM public.advisor_investor_assignments),
    'euin_assignments',(SELECT count(*) FROM public.advisor_euin_assignments),
    'integration_accounts',(SELECT count(*) FROM public.integration_accounts),
    'integration_operations',(SELECT count(*) FROM public.integration_operations),
    'nse_connections',(SELECT count(*) FROM nse_reference.connections)) END,
 'application',(SELECT jsonb_build_object('id',a.id,'status',a.status,'version',a.version,
    'review_started_by',a.review_started_by,'decided_by',a.decided_by,
    'profile_id',a.profile_id,'workspace_id',a.workspace_id,'membership_id',a.membership_id) FROM a),
 'decision_integrity',(SELECT jsonb_build_object(
   'terminal',a.status IN('approved','rejected'),
   'expected_operator',a.decided_by=v.operator_id,
   'terminal_events',(SELECT count(*) FROM public.mfd_application_events e WHERE e.application_id=a.id AND e.event_type IN('approved','rejected')),
   'attributed_terminal_events',(SELECT count(*) FROM public.mfd_application_events e WHERE e.application_id=a.id AND e.event_type=a.status AND e.actor_user_id=v.operator_id AND e.applicant_user_id=v.applicant_id AND e.new_version=a.version),
   'decision_receipts',(SELECT count(*) FROM mfd_application_private.requests r WHERE r.application_id=a.id AND r.operation IN('approve','reject')),
   'receipt_event_binding',(SELECT count(*) FROM mfd_application_private.requests r JOIN public.mfd_application_events e ON e.request_id=r.request_id
       WHERE r.application_id=a.id AND e.application_id=a.id AND e.event_type=a.status
         AND r.actor_user_id=v.operator_id AND e.actor_user_id=v.operator_id
         AND r.operation=CASE a.status WHEN 'approved' THEN 'approve' WHEN 'rejected' THEN 'reject' END),
   'provisioning_audits',(SELECT count(*) FROM public.workspace_audit_logs l WHERE l.target_id=a.id AND l.action='mfd.application_provisioned'),
   'attributed_provisioning_audits',(SELECT count(*) FROM public.workspace_audit_logs l JOIN public.mfd_application_events e ON e.request_id=l.correlation_id
       WHERE l.target_id=a.id AND l.action='mfd.application_provisioned' AND l.actor_user_id=v.operator_id
         AND l.actor_type='platform_admin' AND l.workspace_id=a.workspace_id AND e.application_id=a.id AND e.event_type='approved'),
   'approval_binding',EXISTS(SELECT 1 FROM public.profiles p JOIN public.workspaces w ON w.owner_profile_id=p.id
       JOIN public.workspace_memberships m ON m.profile_id=p.id AND m.workspace_id=w.id
       WHERE a.status='approved' AND p.id=a.profile_id AND p.user_id=v.applicant_id AND p.role='advisor' AND p.account_status='active'
         AND w.id=a.workspace_id AND w.workspace_status='active' AND m.id=a.membership_id AND m.role='admin' AND m.status='active' AND m.ended_at IS NULL),
   'rejection_has_no_provisioning',a.status='rejected' AND a.profile_id IS NULL AND a.workspace_id IS NULL AND a.membership_id IS NULL
 ) FROM a JOIN valid v ON v.application_id=a.id)
) AS inspection;
COMMIT;
