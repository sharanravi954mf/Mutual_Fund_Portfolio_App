-- Platform authority is an auth-account grant, never a business persona.
BEGIN;
CREATE SCHEMA platform_authority;
REVOKE ALL ON SCHEMA platform_authority FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE platform_authority.grants (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id),
 grant_key text NOT NULL CHECK(grant_key IN ('platform_admin','mfd_applications.review','platform.catalog.manage','platform.family_support','platform.investor_links.revoke')),
 granted_at timestamptz NOT NULL DEFAULT now(),
 granted_by text NOT NULL,
 evidence text NOT NULL CHECK(length(btrim(evidence)) BETWEEN 8 AND 2000),
 grant_request_id uuid NOT NULL UNIQUE,
 revoked_at timestamptz,
 revoked_by text,
 revocation_evidence text,
 revoke_request_id uuid UNIQUE,
 CHECK((revoked_at IS NULL AND revoked_by IS NULL AND revocation_evidence IS NULL AND revoke_request_id IS NULL)
   OR (revoked_at IS NOT NULL AND revoked_by IS NOT NULL AND length(btrim(revocation_evidence)) BETWEEN 8 AND 2000 AND revoke_request_id IS NOT NULL AND revoked_at>=granted_at))
);
CREATE UNIQUE INDEX platform_grants_active_unique ON platform_authority.grants(user_id,grant_key) WHERE revoked_at IS NULL;
CREATE TABLE platform_authority.events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 grant_id uuid REFERENCES platform_authority.grants(id),
 user_id uuid NOT NULL REFERENCES auth.users(id),
 action text NOT NULL CHECK(action IN ('granted','revoked','catalog.nav_updated')),
 occurred_at timestamptz NOT NULL DEFAULT now(),
 actor_principal text NOT NULL,
 actor_user_id uuid,
 details jsonb NOT NULL
);
CREATE INDEX platform_events_grant ON platform_authority.events(grant_id);
CREATE INDEX platform_events_user ON platform_authority.events(user_id,occurred_at);
ALTER TABLE platform_authority.grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_authority.events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA platform_authority FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION platform_authority.account_eligible(p_user uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p_user AND u.deleted_at IS NULL
  AND NOT coalesce(u.is_anonymous,false) AND u.email_confirmed_at IS NOT NULL
  AND (u.banned_until IS NULL OR u.banned_until<=now())
  AND NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.user_id=u.id AND p.account_status<>'active'))
$$;
CREATE FUNCTION platform_authority.active_grant(p_user uuid,p_key text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT platform_authority.account_eligible(p_user) AND EXISTS(
  SELECT 1 FROM platform_authority.grants g WHERE g.user_id=p_user AND g.grant_key=p_key AND g.revoked_at IS NULL)
$$;
CREATE FUNCTION platform_authority.capable(p_user uuid,p_key text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT p_key<>'platform_admin' AND platform_authority.active_grant(p_user,'platform_admin')
  AND platform_authority.active_grant(p_user,p_key)
$$;
CREATE OR REPLACE FUNCTION public.is_platform_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT platform_authority.active_grant(auth.uid(),'platform_admin')
$$;
CREATE FUNCTION public.has_platform_capability(p_capability text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce(platform_authority.capable(auth.uid(),p_capability),false)
$$;
CREATE FUNCTION platform_authority.session_verified(p_user uuid,p_session text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT platform_authority.account_eligible(p_user) AND EXISTS(
  SELECT 1 FROM auth.sessions s JOIN auth.mfa_factors f ON f.id=s.factor_id AND f.user_id=s.user_id
  WHERE s.id::text=p_session AND s.user_id=p_user AND s.aal='aal2' AND f.status='verified'
   AND (s.not_after IS NULL OR s.not_after>now()))
$$;
CREATE OR REPLACE FUNCTION public.platform_admin_step_up_verified() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT public.is_platform_admin() AND coalesce(auth.jwt()->>'aal','')='aal2'
  AND platform_authority.session_verified(auth.uid(),auth.jwt()->>'session_id')
$$;
CREATE FUNCTION public.can_perform_platform_mutation(p_capability text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT public.has_platform_capability(p_capability) AND public.platform_admin_step_up_verified()
$$;
-- Legacy global catalogue policies use this alias, never workspace admin.
CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT public.can_perform_platform_mutation('platform.catalog.manage')
$$;
CREATE FUNCTION public.get_my_platform_context() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 RETURN jsonb_build_object('is_platform_admin',public.is_platform_admin(),
  'capabilities',coalesce((SELECT jsonb_agg(g.grant_key ORDER BY g.grant_key) FROM platform_authority.grants g
   WHERE g.user_id=auth.uid() AND g.revoked_at IS NULL AND public.has_platform_capability(g.grant_key)),'[]'::jsonb),
  'step_up_verified',public.platform_admin_step_up_verified(),
  'mfa_enrolled',EXISTS(SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=auth.uid() AND f.status='verified'));
END $$;

-- Out-of-band commissioning: no Data API role (including service_role) can call
-- these functions. Session principal is authoritative; there is no actor input.
CREATE FUNCTION platform_authority.assert_operator() RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF session_user NOT IN ('postgres','supabase_admin') OR current_setting('role',true) NOT IN ('none','postgres','supabase_admin') THEN
  RAISE EXCEPTION 'database_operator_required' USING ERRCODE='42501';
 END IF;
END $$;
CREATE FUNCTION platform_authority.guard_grant() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'platform_grant_history_immutable'; END IF;
 IF TG_OP='UPDATE' AND ((NEW.id,NEW.user_id,NEW.grant_key,NEW.granted_at,NEW.granted_by,NEW.evidence,NEW.grant_request_id)
   IS DISTINCT FROM (OLD.id,OLD.user_id,OLD.grant_key,OLD.granted_at,OLD.granted_by,OLD.evidence,OLD.grant_request_id)
   OR OLD.revoked_at IS NOT NULL OR NEW.revoked_at IS NULL) THEN RAISE EXCEPTION 'platform_grant_provenance_immutable'; END IF;
 IF TG_OP='INSERT' AND NEW.revoked_at IS NOT NULL THEN RAISE EXCEPTION 'platform_grant_must_start_active'; END IF;
 RETURN NEW;
END $$;
CREATE FUNCTION platform_authority.audit_grant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 INSERT INTO platform_authority.events(grant_id,user_id,action,actor_principal,details)
 VALUES(NEW.id,NEW.user_id,CASE WHEN TG_OP='INSERT' THEN 'granted' ELSE 'revoked' END,session_user,
  jsonb_build_object('grant_key',NEW.grant_key,'request_id',CASE WHEN TG_OP='INSERT' THEN NEW.grant_request_id ELSE NEW.revoke_request_id END,
   'evidence',CASE WHEN TG_OP='INSERT' THEN NEW.evidence ELSE NEW.revocation_evidence END));
 RETURN NULL;
END $$;
CREATE FUNCTION platform_authority.immutable_event() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$ BEGIN RAISE EXCEPTION 'platform_audit_immutable'; END $$;
CREATE TRIGGER platform_grant_guard BEFORE INSERT OR UPDATE OR DELETE ON platform_authority.grants FOR EACH ROW EXECUTE FUNCTION platform_authority.guard_grant();
CREATE TRIGGER platform_grant_audit AFTER INSERT OR UPDATE ON platform_authority.grants FOR EACH ROW EXECUTE FUNCTION platform_authority.audit_grant();
CREATE TRIGGER platform_event_immutable BEFORE UPDATE OR DELETE ON platform_authority.events FOR EACH ROW EXECUTE FUNCTION platform_authority.immutable_event();

CREATE FUNCTION platform_authority.grant_authority(p_user uuid,p_grant text,p_request_id uuid,p_evidence text) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE g platform_authority.grants;
BEGIN
 PERFORM platform_authority.assert_operator();
 IF p_request_id IS NULL OR p_grant IS NULL OR p_grant NOT IN ('platform_admin','mfd_applications.review','platform.catalog.manage','platform.family_support','platform.investor_links.revoke')
  OR p_evidence IS NULL OR length(btrim(p_evidence)) NOT BETWEEN 8 AND 2000 THEN RAISE EXCEPTION 'invalid_platform_grant'; END IF;
 PERFORM 1 FROM auth.users WHERE id=p_user FOR UPDATE;
 IF NOT platform_authority.account_eligible(p_user) THEN RAISE EXCEPTION 'platform_account_unavailable'; END IF;
 SELECT * INTO g FROM platform_authority.grants WHERE grant_request_id=p_request_id;
 IF FOUND THEN
  IF (g.user_id,g.grant_key,g.evidence) IS DISTINCT FROM (p_user,p_grant,btrim(p_evidence)) THEN RAISE EXCEPTION 'platform_request_conflict'; END IF;
  IF g.revoked_at IS NOT NULL THEN RAISE EXCEPTION 'platform_grant_revoked'; END IF;
  RETURN g.id;
 END IF;
 IF p_grant<>'platform_admin' AND NOT platform_authority.active_grant(p_user,'platform_admin') THEN RAISE EXCEPTION 'platform_admin_grant_required'; END IF;
 INSERT INTO platform_authority.grants(user_id,grant_key,granted_by,evidence,grant_request_id)
 VALUES(p_user,p_grant,session_user,btrim(p_evidence),p_request_id) RETURNING * INTO g;
 RETURN g.id;
END $$;
CREATE FUNCTION platform_authority.revoke_authority(p_grant_id uuid,p_request_id uuid,p_evidence text) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE g platform_authority.grants;
BEGIN
 PERFORM platform_authority.assert_operator();
 IF p_request_id IS NULL OR p_evidence IS NULL OR length(btrim(p_evidence)) NOT BETWEEN 8 AND 2000 THEN RAISE EXCEPTION 'invalid_platform_revocation'; END IF;
 SELECT * INTO g FROM platform_authority.grants WHERE id=p_grant_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'platform_grant_unavailable'; END IF;
 PERFORM 1 FROM auth.users WHERE id=g.user_id FOR UPDATE;
 SELECT * INTO g FROM platform_authority.grants WHERE id=p_grant_id FOR UPDATE;
 IF g.revoked_at IS NOT NULL THEN
  IF (g.revoke_request_id,g.revocation_evidence) IS DISTINCT FROM (p_request_id,btrim(p_evidence)) THEN RAISE EXCEPTION 'platform_request_conflict'; END IF;
  RETURN;
 END IF;
 UPDATE platform_authority.grants SET revoked_at=now(),revoked_by=session_user,revocation_evidence=btrim(p_evidence),revoke_request_id=p_request_id WHERE id=g.id;
END $$;
CREATE FUNCTION platform_authority.bootstrap_first_admin(p_user uuid,p_admin_request uuid,p_review_request uuid,p_evidence text) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE g uuid;
BEGIN
 PERFORM platform_authority.assert_operator();
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('moneybowl.first_platform_admin',0));
 IF EXISTS(SELECT 1 FROM platform_authority.grants WHERE grant_key='platform_admin' AND (user_id,grant_request_id) IS DISTINCT FROM (p_user,p_admin_request)) THEN
  RAISE EXCEPTION 'platform_bootstrap_already_commissioned';
 END IF;
 g:=platform_authority.grant_authority(p_user,'platform_admin',p_admin_request,p_evidence);
 PERFORM platform_authority.grant_authority(p_user,'mfd_applications.review',p_review_request,p_evidence);
 RETURN g;
END $$;

-- Serialize sensitive work against revocation, account suspension and MFA removal.
CREATE FUNCTION platform_authority.require_mutation(p_capability text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM auth.users WHERE id=auth.uid() FOR SHARE;
 PERFORM 1 FROM public.profiles WHERE user_id=auth.uid() FOR SHARE;
 PERFORM 1 FROM platform_authority.grants WHERE user_id=auth.uid() AND grant_key IN ('platform_admin',p_capability) ORDER BY id FOR SHARE;
 PERFORM 1 FROM auth.sessions WHERE id::text=auth.jwt()->>'session_id' AND user_id=auth.uid() FOR SHARE;
 PERFORM 1 FROM auth.mfa_factors WHERE user_id=auth.uid() ORDER BY id FOR SHARE;
 IF NOT public.has_platform_capability(p_capability) THEN RAISE EXCEPTION 'platform_capability_required' USING ERRCODE='42501'; END IF;
 IF NOT public.platform_admin_step_up_verified() THEN RAISE EXCEPTION 'platform_admin_step_up_required' USING ERRCODE='42501'; END IF;
END $$;

-- NAV updates are an existing global catalogue operation. Expose no tenant rows
-- to its caller; reprice affected portfolios internally under the same audit.
CREATE FUNCTION public.platform_update_fund_nav(p_fund_id uuid,p_nav numeric,p_nav_date date) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE portfolio_id uuid;
BEGIN
 PERFORM platform_authority.require_mutation('platform.catalog.manage');
 IF p_nav IS NULL OR p_nav<=0 OR p_nav IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) OR p_nav_date IS NULL THEN RAISE EXCEPTION 'invalid_nav'; END IF;
 UPDATE public.mutual_funds SET current_nav=p_nav,nav_date=p_nav_date WHERE id=p_fund_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'fund_unavailable'; END IF;
 FOR portfolio_id IN SELECT DISTINCT t.portfolio_id FROM public.transactions t WHERE t.mutual_fund_id=p_fund_id LOOP
  PERFORM public.recalculate_portfolio_value(portfolio_id);
 END LOOP;
 INSERT INTO platform_authority.events(user_id,action,actor_principal,actor_user_id,details)
 VALUES(auth.uid(),'catalog.nav_updated','authenticated',auth.uid(),jsonb_build_object('fund_id',p_fund_id,'nav',p_nav,'nav_date',p_nav_date));
END $$;


CREATE OR REPLACE FUNCTION moneybowl_authz.member_role(p_workspace uuid, p_profile uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT m.role FROM public.workspace_memberships m
    JOIN public.workspaces w ON w.id=m.workspace_id
    JOIN public.profiles p ON p.id=m.profile_id
  WHERE m.workspace_id=p_workspace AND m.profile_id=p_profile
    AND m.status='active' AND m.ended_at IS NULL AND w.workspace_status='active'
    AND moneybowl_authz.profile_active(p.id) AND p.role <> 'platform_admin' AND NOT platform_authority.active_grant(p.user_id,'platform_admin')
$function$;


CREATE OR REPLACE FUNCTION moneybowl_authz.owns_investor(p_profile uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT NOT public.is_platform_admin() AND moneybowl_authz.account_active(auth.uid()) AND moneybowl_authz.profile_active(p_profile)
    AND EXISTS (SELECT 1 FROM public.investor_account_links l
      WHERE l.user_id=auth.uid() AND l.profile_id=p_profile AND l.link_status='active')
$function$;


CREATE OR REPLACE FUNCTION public.bootstrap_identity()
 RETURNS TABLE(account_state user_account_state, onboarding_completed boolean, resolution text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  u auth.users%rowtype;
  a public.user_accounts%rowtype;
  p public.profiles%rowtype;
  own_profile uuid;
  linked_profile uuid;
  candidates uuid[];
BEGIN
  SELECT * INTO u FROM auth.users WHERE id = auth.uid();
  IF u.id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF u.deleted_at IS NOT NULL OR coalesce(u.is_anonymous,false) OR u.banned_until>now() THEN RAISE EXCEPTION 'account_unavailable'; END IF;
  INSERT INTO public.user_accounts(user_id) VALUES (u.id) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO a FROM public.user_accounts WHERE user_id = u.id FOR UPDATE;

  -- Platform context is projected separately; no fake business identity/state.
  IF public.is_platform_admin() THEN
    UPDATE public.user_accounts SET account_state='explorer',onboarding_completed=true WHERE user_id=u.id;
    RETURN QUERY SELECT 'explorer'::public.user_account_state,true,'platform_context'::text;
    RETURN;
  END IF;

  -- Retain old invitation links, but only redeem after confirmed email ownership.
  IF u.email_confirmed_at IS NOT NULL AND nullif(u.raw_user_meta_data->>'invited_token', '') IS NOT NULL THEN
    BEGIN
      PERFORM public.accept_workspace_invitation(u.raw_user_meta_data->>'invited_token');
    EXCEPTION WHEN raise_exception OR unique_violation THEN
      NULL; -- Invalid/replayed invitation never changes public-facing identity results.
    END;
  END IF;

  SELECT p0.id INTO own_profile FROM public.profiles p0 WHERE p0.user_id = u.id;
  IF own_profile IS NOT NULL THEN
    SELECT * INTO p FROM public.profiles WHERE id = own_profile FOR UPDATE;
    IF p.account_status <> 'active' THEN RAISE EXCEPTION 'account_unavailable'; END IF;
    IF p.role IN ('advisor', 'admin', 'operations') OR EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.profile_id=p.id AND moneybowl_authz.member_role(m.workspace_id,p.id) IN ('admin','advisor','operations')) THEN
      UPDATE public.user_accounts SET account_state = 'advisor', onboarding_completed = true WHERE user_id = u.id;
      RETURN QUERY SELECT 'advisor'::public.user_account_state, true, 'advisor'::text;
      RETURN;
    END IF;
  END IF;

  SELECT l.profile_id INTO linked_profile FROM public.investor_account_links l
  WHERE l.user_id = u.id AND l.link_status = 'active';
  IF linked_profile IS NOT NULL THEN
    SELECT * INTO p FROM public.profiles WHERE id = linked_profile FOR UPDATE;
    IF p.id IS NULL OR p.account_status <> 'active' OR p.role NOT IN ('investor', 'client')
      OR (p.user_id IS NOT NULL AND p.user_id <> u.id)
      OR (own_profile IS NOT NULL AND own_profile <> p.id) THEN
      RAISE EXCEPTION 'account_unavailable';
    END IF;
    UPDATE public.profiles SET user_id = u.id WHERE id = p.id AND user_id IS NULL;
    UPDATE public.user_accounts SET account_state = 'linked_investor', onboarding_completed = true WHERE user_id = u.id;
    RETURN QUERY SELECT 'linked_investor'::public.user_account_state, true, 'existing_link'::text;
    RETURN;
  END IF;

  IF u.email_confirmed_at IS NULL OR nullif(u.email, '') IS NULL THEN
    RAISE EXCEPTION 'email_verification_required';
  END IF;

  -- Count all active trusted contact matches BEFORE ownership filtering. A
  -- conflicting match must not make an ambiguous email appear unique.
  SELECT array_agg(p0.id) INTO candidates FROM public.profiles p0
  WHERE p0.role IN ('investor', 'client') AND p0.account_status = 'active'
    AND lower(btrim(p0.verified_email)) = lower(btrim(u.email));
  IF cardinality(candidates) = 1 THEN
    SELECT * INTO p FROM public.profiles WHERE id = candidates[1] FOR UPDATE;
    IF p.account_status = 'active' AND p.role IN ('investor', 'client')
      AND lower(btrim(p.verified_email)) = lower(btrim(u.email))
      AND (p.user_id IS NULL OR p.user_id = u.id)
      AND (own_profile IS NULL OR own_profile = p.id)
      AND NOT EXISTS (SELECT 1 FROM public.investor_account_links l
        WHERE (l.profile_id = p.id AND l.link_status = 'active')
          OR (l.profile_id = p.id AND l.user_id = u.id)) THEN
      BEGIN
        INSERT INTO public.investor_account_links(user_id, profile_id, verification_method, verified_at)
        VALUES (u.id, p.id, 'verified_email', now());
        UPDATE public.profiles SET user_id = u.id WHERE id = p.id AND user_id IS NULL;
        UPDATE public.user_accounts SET account_state = 'linked_investor', onboarding_completed = true WHERE user_id = u.id;
        RETURN QUERY SELECT 'linked_investor'::public.user_account_state, true, 'automatic_link'::text;
        RETURN;
      EXCEPTION WHEN unique_violation THEN NULL;
      END;
    END IF;
  END IF;
  -- Preserve an explicit portfolio-linking choice. No-match and conflicts have
  -- identical results; neither reveals whether another investor exists.
  UPDATE public.user_accounts SET account_state = CASE
    WHEN a.account_state = 'link_pending' AND a.onboarding_completed THEN 'link_pending'::public.user_account_state
    ELSE 'explorer'::public.user_account_state END, onboarding_completed = true WHERE user_id = u.id
  RETURNING * INTO a;
  RETURN QUERY SELECT a.account_state, true,
    CASE WHEN a.account_state = 'link_pending' THEN 'verification_pending' ELSE 'no_match' END;
END;
$function$;


CREATE OR REPLACE FUNCTION public.accept_workspace_invitation(p_plaintext_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  u auth.users%rowtype;
  invitation public.workspace_invitations%rowtype;
  profile_id uuid;
begin
  if public.is_platform_admin() or not moneybowl_authz.account_active(auth.uid()) then raise exception 'account_unavailable'; end if;
  SELECT * INTO u FROM auth.users WHERE id = auth.uid();
  IF u.id IS NULL OR u.email_confirmed_at IS NULL OR nullif(u.email, '') IS NULL THEN
    RAISE EXCEPTION 'invitation_unavailable';
  END IF;
  PERFORM 1 FROM public.user_accounts WHERE user_id = u.id FOR UPDATE;
  SELECT i.* INTO invitation FROM public.workspace_invitations i
  JOIN public.workspaces w ON w.id = i.workspace_id AND w.workspace_status = 'active'
  WHERE i.token_hash = pg_catalog.encode(extensions.digest(p_plaintext_token, 'sha256'), 'hex')
    AND i.status = 'pending' AND i.expires_at > now()
    AND lower(btrim(i.email)) = lower(btrim(u.email))
    AND EXISTS (
      SELECT 1 FROM public.profiles inviter WHERE inviter.id = i.invited_by
      AND inviter.account_status = 'active'
      AND EXISTS (
        SELECT 1 FROM public.workspace_memberships m WHERE m.profile_id = inviter.id
        AND m.workspace_id = i.workspace_id AND m.role = 'admin'
        AND m.status = 'active' AND m.ended_at IS NULL))
  FOR UPDATE OF i;
  IF invitation.id IS NULL THEN RAISE EXCEPTION 'invitation_unavailable'; END IF;
  PERFORM moneybowl_authz.lock_scope(invitation.workspace_id);
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=invitation.invited_by
    AND moneybowl_authz.profile_active(p.id) AND moneybowl_authz.member_role(invitation.workspace_id,p.id)='admin')
    OR NOT EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id=invitation.workspace_id AND w.workspace_status='active') THEN
    RAISE EXCEPTION 'invitation_unavailable';
  END IF;
  SELECT p.id INTO profile_id FROM public.profiles p WHERE p.user_id = u.id FOR UPDATE;
  IF profile_id IS NULL THEN
    -- This is a deliberate business invitation, not public signup provisioning.
    INSERT INTO public.profiles(user_id, role, email, full_name, account_status)
    VALUES (u.id, invitation.role, u.email, '', 'active') RETURNING id INTO profile_id;
  ELSIF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = profile_id AND p.account_status = 'active') THEN
    RAISE EXCEPTION 'invitation_unavailable';
  END IF;
  -- An existing membership is never silently promoted or reactivated.
  INSERT INTO public.workspace_memberships(workspace_id, profile_id, role, status, invited_by)
  VALUES (invitation.workspace_id, profile_id, invitation.role, 'active', invitation.invited_by);
  UPDATE public.workspace_invitations SET status = 'accepted', updated_at = now() WHERE id = invitation.id;
  INSERT INTO public.workspace_audit_logs(workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (invitation.workspace_id, profile_id, 'invitation_accepted', 'profile', profile_id,
    jsonb_build_object('invitation_id', invitation.id));
  RETURN true;
END;
$function$;


CREATE OR REPLACE FUNCTION public.revoke_investor_link(p_link_id uuid, p_reason_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare link public.investor_account_links%rowtype;
begin
  perform platform_authority.require_mutation('platform.investor_links.revoke');
  if nullif(btrim(p_reason_code),'') is null then raise exception 'reason_required'; end if;
  select * into link from public.investor_account_links where id = p_link_id for update;
  if not found or link.link_status <> 'active' then raise exception 'Link cannot be revoked'; end if;
  update public.investor_account_links set link_status = 'revoked' where id = link.id;
  update public.user_accounts set account_state = 'link_pending', onboarding_completed = true
  where user_id = link.user_id;
  insert into public.verification_events (subject_user_id, actor_user_id, actor_type,
    event_type, reason_code) values (link.user_id, auth.uid(), 'platform_admin', 'revoked', p_reason_code);
end;
$function$;


ALTER TABLE public.workspace_audit_logs ADD COLUMN actor_user_id uuid REFERENCES auth.users(id);
CREATE INDEX workspace_audit_actor_user ON public.workspace_audit_logs(actor_user_id) WHERE actor_user_id IS NOT NULL;

ALTER TABLE public.workspace_audit_logs DROP CONSTRAINT workspace_audit_logs_override_contract_chk;
ALTER TABLE public.workspace_audit_logs ADD CONSTRAINT workspace_audit_logs_override_contract_chk CHECK (((event_type IS NULL) OR (event_type !~~ 'override.%'::text) OR (((actor_profile_id IS NOT NULL) OR (actor_user_id IS NOT NULL)) AND (actor_type = 'platform_admin'::text) AND (entity_type IS NOT NULL) AND (entity_id IS NOT NULL) AND (action = ANY (ARRAY['family_delegation.read'::text, 'family_delegation.restore_access'::text])) AND (reason IS NOT NULL) AND (btrim(reason) <> ''::text) AND (correlation_id IS NOT NULL) AND (occurred_at IS NOT NULL) AND (((event_type = 'override.attempted'::text) AND (outcome = 'attempted'::text) AND (error_code IS NULL)) OR ((event_type = 'override.succeeded'::text) AND (outcome = 'succeeded'::text) AND (error_code IS NULL)) OR ((event_type = 'override.denied'::text) AND (outcome = 'denied'::text) AND (error_code IS NOT NULL)) OR ((event_type = 'override.failed'::text) AND (outcome = 'failed'::text) AND (error_code IS NOT NULL))))));

CREATE OR REPLACE FUNCTION public.begin_platform_admin_override_attempt(p_workspace_id uuid, p_entity_type text, p_entity_id uuid, p_action text, p_reason text, p_correlation_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor_profile_id pg_catalog.uuid;
  v_existing public.workspace_audit_logs;
  v_audit_id pg_catalog.uuid;
BEGIN
  PERFORM platform_authority.require_mutation('platform.family_support');
  v_actor_profile_id := public.current_user_profile_id();

  IF p_workspace_id IS NULL THEN
    RAISE EXCEPTION 'workspace_id_required';
  END IF;

  IF p_entity_type IS NULL OR pg_catalog.btrim(p_entity_type) = '' THEN
    RAISE EXCEPTION 'entity_type_required';
  END IF;

  IF p_entity_id IS NULL THEN
    RAISE EXCEPTION 'entity_id_required';
  END IF;

  IF p_action NOT IN ('family_delegation.read', 'family_delegation.restore_access') THEN
    RAISE EXCEPTION 'unsupported_override_action';
  END IF;

  IF p_entity_type <> 'family_delegations' THEN
    RAISE EXCEPTION 'unsupported_entity_type';
  END IF;

  IF p_reason IS NULL OR pg_catalog.btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  IF p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_correlation_id::pg_catalog.text, 0)
  );

  SELECT *
  INTO v_existing
  FROM public.workspace_audit_logs AS audit
  WHERE audit.correlation_id = p_correlation_id
    AND audit.event_type = 'override.attempted';

  IF v_existing.id IS NOT NULL THEN
    IF v_existing.actor_user_id IS DISTINCT FROM auth.uid()
       OR v_existing.workspace_id IS DISTINCT FROM p_workspace_id
       OR v_existing.entity_type IS DISTINCT FROM p_entity_type
       OR v_existing.entity_id IS DISTINCT FROM p_entity_id
       OR v_existing.action IS DISTINCT FROM p_action
       OR v_existing.reason IS DISTINCT FROM pg_catalog.btrim(p_reason) THEN
      RAISE EXCEPTION 'correlation_id_conflict';
    END IF;

    RETURN v_existing.id;
  END IF;

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_user_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    reason,
    correlation_id,
    event_type,
    outcome,
    occurred_at,
    payload
  ) VALUES (
    p_workspace_id,
    v_actor_profile_id,
    v_actor_profile_id,
    auth.uid(),
    'platform_admin',
    p_action,
    p_entity_type,
    p_entity_type,
    p_entity_id,
    p_entity_id,
    pg_catalog.btrim(p_reason),
    p_correlation_id,
    'override.attempted',
    'attempted',
    pg_catalog.now(),
    pg_catalog.jsonb_build_object(
      'session_id', auth.jwt()->>'session_id',
      'action', p_action,
      'reason', pg_catalog.btrim(p_reason),
      'correlation_id', p_correlation_id,
      'entity_type', p_entity_type,
      'entity_id', p_entity_id
    )
  )
  RETURNING id INTO v_audit_id;

  RETURN v_audit_id;
END;
$function$;


CREATE FUNCTION platform_authority.assert_override_actor(p_attempt public.workspace_audit_logs) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM auth.users WHERE id=p_attempt.actor_user_id FOR SHARE;
 PERFORM 1 FROM public.profiles WHERE user_id=p_attempt.actor_user_id FOR SHARE;
 PERFORM 1 FROM platform_authority.grants WHERE user_id=p_attempt.actor_user_id ORDER BY id FOR SHARE;
 PERFORM 1 FROM auth.sessions WHERE user_id=p_attempt.actor_user_id AND id::text=p_attempt.payload->>'session_id' FOR SHARE;
 PERFORM 1 FROM auth.mfa_factors WHERE user_id=p_attempt.actor_user_id ORDER BY id FOR SHARE;
 IF NOT platform_authority.capable(p_attempt.actor_user_id,'platform.family_support') OR NOT platform_authority.session_verified(p_attempt.actor_user_id,p_attempt.payload->>'session_id') THEN
  RAISE EXCEPTION 'platform_support_authority_expired' USING ERRCODE='42501';
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.platform_admin_read_family_delegation_support_projection(p_correlation_id uuid, p_workspace_id uuid, p_delegation_id uuid, p_owner_profile_id uuid, p_delegate_profile_id uuid)
 RETURNS TABLE(delegation_id uuid, workspace_id uuid, owner_profile_id uuid, delegate_profile_id uuid, consent_status text, is_active boolean, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_attempt public.workspace_audit_logs;
  v_terminal public.workspace_audit_logs;
BEGIN
  IF p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_correlation_id::pg_catalog.text, 0)
  );

  SELECT *
  INTO v_attempt
  FROM public.workspace_audit_logs AS audit
  WHERE audit.correlation_id = p_correlation_id
    AND audit.event_type = 'override.attempted'
    AND audit.action = 'family_delegation.read'
    AND audit.entity_type = 'family_delegations'
    AND audit.entity_id = p_delegation_id
    AND audit.workspace_id = p_workspace_id;

  IF v_attempt.id IS NULL THEN
    RAISE EXCEPTION 'override_attempt_not_found';
  END IF;
  PERFORM platform_authority.assert_override_actor(v_attempt);

  SELECT *
  INTO v_terminal
  FROM public.workspace_audit_logs AS audit
  WHERE audit.correlation_id = p_correlation_id
    AND audit.event_type IN ('override.succeeded', 'override.denied', 'override.failed');

  IF v_terminal.id IS NOT NULL
     AND v_terminal.event_type <> 'override.succeeded' THEN
    RAISE EXCEPTION 'override_already_finalized';
  END IF;

  RETURN QUERY
  SELECT
    delegation.id,
    delegation.workspace_id,
    delegation.owner_profile_id,
    delegation.delegate_profile_id,
    delegation.consent_status,
    delegation.is_active,
    delegation.expires_at
  FROM public.family_delegations AS delegation
  WHERE delegation.id = p_delegation_id
    AND delegation.workspace_id = p_workspace_id
    AND delegation.owner_profile_id = p_owner_profile_id
    AND delegation.delegate_profile_id = p_delegate_profile_id;

  IF NOT FOUND THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.family_delegations AS delegation
      WHERE delegation.id = p_delegation_id
    ) THEN
      RAISE EXCEPTION 'delegation_not_found';
    END IF;

    RAISE EXCEPTION 'target_binding_mismatch';
  END IF;
END;
$function$;


CREATE OR REPLACE FUNCTION public.platform_admin_restore_family_delegation_access(p_correlation_id uuid, p_workspace_id uuid, p_delegation_id uuid, p_owner_profile_id uuid, p_delegate_profile_id uuid)
 RETURNS family_delegations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_attempt public.workspace_audit_logs;
  v_terminal public.workspace_audit_logs;
  v_delegation public.family_delegations;
BEGIN
  IF p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_correlation_id::pg_catalog.text, 0)
  );

  SELECT *
  INTO v_attempt
  FROM public.workspace_audit_logs AS audit
  WHERE audit.correlation_id = p_correlation_id
    AND audit.event_type = 'override.attempted'
    AND audit.action = 'family_delegation.restore_access'
    AND audit.entity_type = 'family_delegations'
    AND audit.entity_id = p_delegation_id
    AND audit.workspace_id = p_workspace_id;

  IF v_attempt.id IS NULL THEN
    RAISE EXCEPTION 'override_attempt_not_found';
  END IF;
  PERFORM platform_authority.assert_override_actor(v_attempt);

  SELECT *
  INTO v_terminal
  FROM public.workspace_audit_logs AS audit
  WHERE audit.correlation_id = p_correlation_id
    AND audit.event_type IN ('override.succeeded', 'override.denied', 'override.failed');

  IF v_terminal.id IS NOT NULL
     AND v_terminal.event_type <> 'override.succeeded' THEN
    RAISE EXCEPTION 'override_already_finalized';
  END IF;

  SELECT *
  INTO v_delegation
  FROM public.family_delegations AS delegation
  WHERE delegation.id = p_delegation_id
  FOR UPDATE;

  IF v_delegation.id IS NULL THEN
    RAISE EXCEPTION 'delegation_not_found';
  END IF;

  IF v_delegation.workspace_id IS DISTINCT FROM p_workspace_id
     OR v_delegation.owner_profile_id IS DISTINCT FROM p_owner_profile_id
     OR v_delegation.delegate_profile_id IS DISTINCT FROM p_delegate_profile_id THEN
    RAISE EXCEPTION 'target_binding_mismatch';
  END IF;

  IF v_terminal.id IS NOT NULL THEN
    RETURN v_delegation;
  END IF;

  IF v_delegation.consent_status <> 'accepted' THEN
    RAISE EXCEPTION 'owner_consent_not_recorded';
  END IF;

  IF v_delegation.expires_at IS NOT NULL AND v_delegation.expires_at <= pg_catalog.now() THEN
    RAISE EXCEPTION 'delegation_expired';
  END IF;

  IF v_delegation.is_active THEN
    RETURN v_delegation;
  END IF;

  UPDATE public.family_delegations
  SET is_active = true,
      updated_at = pg_catalog.now()
  WHERE id = p_delegation_id
  RETURNING * INTO v_delegation;

  RETURN v_delegation;
END;
$function$;


CREATE OR REPLACE FUNCTION public.finish_platform_admin_override_attempt(p_correlation_id uuid, p_event_type text, p_error_code text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_attempt public.workspace_audit_logs;
  v_existing public.workspace_audit_logs;
  v_outcome pg_catalog.text;
  v_audit_id pg_catalog.uuid;
BEGIN
  IF p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_correlation_id::pg_catalog.text, 0)
  );

  IF p_event_type NOT IN ('override.succeeded', 'override.denied', 'override.failed') THEN
    RAISE EXCEPTION 'invalid_terminal_event_type';
  END IF;

  IF p_event_type = 'override.succeeded' THEN
    v_outcome := 'succeeded';
    IF p_error_code IS NOT NULL THEN
      RAISE EXCEPTION 'terminal_success_error_code_conflict';
    END IF;
  ELSIF p_event_type = 'override.denied' THEN
    v_outcome := 'denied';
    IF p_error_code IS NULL OR pg_catalog.btrim(p_error_code) = '' THEN
      RAISE EXCEPTION 'terminal_error_code_required';
    END IF;
  ELSE
    v_outcome := 'failed';
    IF p_error_code IS NULL OR pg_catalog.btrim(p_error_code) = '' THEN
      RAISE EXCEPTION 'terminal_error_code_required';
    END IF;
  END IF;

  SELECT *
  INTO v_attempt
  FROM public.workspace_audit_logs AS audit
  WHERE audit.correlation_id = p_correlation_id
    AND audit.event_type = 'override.attempted';

  IF v_attempt.id IS NULL THEN
    RAISE EXCEPTION 'override_attempt_not_found';
  END IF;

  SELECT *
  INTO v_existing
  FROM public.workspace_audit_logs AS audit
  WHERE audit.correlation_id = p_correlation_id
    AND audit.event_type IN ('override.succeeded', 'override.denied', 'override.failed');

  IF v_existing.id IS NOT NULL THEN
    IF v_existing.event_type = p_event_type
       AND v_existing.outcome = v_outcome
       AND v_existing.error_code IS NOT DISTINCT FROM NULLIF(pg_catalog.btrim(COALESCE(p_error_code, '')), '') THEN
      RETURN v_existing.id;
    END IF;

    RAISE EXCEPTION 'terminal_outcome_conflict';
  END IF;

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_user_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    reason,
    correlation_id,
    event_type,
    outcome,
    error_code,
    occurred_at,
    payload
  ) VALUES (
    v_attempt.workspace_id,
    v_attempt.actor_profile_id,
    v_attempt.actor_profile_id,
    v_attempt.actor_user_id,
    v_attempt.actor_type,
    v_attempt.action,
    v_attempt.entity_type,
    v_attempt.entity_type,
    v_attempt.entity_id,
    v_attempt.entity_id,
    v_attempt.reason,
    p_correlation_id,
    p_event_type,
    v_outcome,
    NULLIF(pg_catalog.btrim(COALESCE(p_error_code, '')), ''),
    pg_catalog.now(),
    pg_catalog.jsonb_build_object(
      'action', v_attempt.action,
      'correlation_id', p_correlation_id,
      'event_type', p_event_type,
      'outcome', v_outcome,
      'error_code', NULLIF(pg_catalog.btrim(COALESCE(p_error_code, '')), '')
    )
  )
  RETURNING id INTO v_audit_id;

  RETURN v_audit_id;
END;
$function$;


REVOKE ALL ON ALL FUNCTIONS IN SCHEMA platform_authority FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.has_platform_capability(text),public.get_my_platform_context(),public.can_perform_platform_mutation(text),public.platform_update_fund_nav(uuid,numeric,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.has_platform_capability(text),public.get_my_platform_context(),public.can_perform_platform_mutation(text),public.platform_update_fund_nav(uuid,numeric,date) TO authenticated;
REVOKE ALL ON FUNCTION public.is_platform_admin(),public.is_admin(),public.platform_admin_step_up_verified() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.is_platform_admin(),public.is_admin(),public.platform_admin_step_up_verified() TO authenticated;
COMMIT;