-- Authorization containment. Global persona labels are not tenant capabilities.
BEGIN;

CREATE SCHEMA moneybowl_authz;
REVOKE ALL ON SCHEMA moneybowl_authz FROM PUBLIC, anon, authenticated;

CREATE FUNCTION moneybowl_authz.account_active(p_user uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM auth.users u JOIN public.user_accounts a ON a.user_id=u.id
    WHERE u.id=p_user AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false)
      AND (u.banned_until IS NULL OR u.banned_until <= now())
      AND NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.user_id=u.id AND p.account_status<>'active'))
$$;

CREATE FUNCTION moneybowl_authz.profile_active(p_profile uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=p_profile AND p.account_status='active'
    AND (p.user_id IS NULL OR moneybowl_authz.account_active(p.user_id)))
$$;

CREATE FUNCTION moneybowl_authz.actor() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p.id FROM public.profiles p WHERE p.id=public.current_user_profile_id()
    AND p.user_id=auth.uid() AND moneybowl_authz.account_active(auth.uid())
    AND moneybowl_authz.profile_active(p.id)
$$;

CREATE FUNCTION moneybowl_authz.member_role(p_workspace uuid,p_profile uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT m.role FROM public.workspace_memberships m
    JOIN public.workspaces w ON w.id=m.workspace_id
    JOIN public.profiles p ON p.id=m.profile_id
  WHERE m.workspace_id=p_workspace AND m.profile_id=p_profile
    AND m.status='active' AND m.ended_at IS NULL AND w.workspace_status='active'
    AND moneybowl_authz.profile_active(p.id) AND p.role <> 'platform_admin'
$$;

CREATE FUNCTION moneybowl_authz.owns_investor(p_profile uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT moneybowl_authz.account_active(auth.uid()) AND moneybowl_authz.profile_active(p_profile)
    AND EXISTS (SELECT 1 FROM public.investor_account_links l
      WHERE l.user_id=auth.uid() AND l.profile_id=p_profile AND l.link_status='active')
$$;

CREATE OR REPLACE FUNCTION public.is_platform_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles p
    WHERE p.id=moneybowl_authz.actor() AND p.role='platform_admin')
$$;

-- Compatibility helper for global catalogue administration ONLY. Tenant review
-- callers below use a request/workspace predicate instead.
CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.is_platform_admin()
$$;

CREATE OR REPLACE FUNCTION public.current_user_workspace_ids() RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT m.workspace_id FROM public.workspace_memberships m
  WHERE m.profile_id=moneybowl_authz.actor()
    AND moneybowl_authz.member_role(m.workspace_id,m.profile_id) IS NOT NULL
$$;
CREATE OR REPLACE FUNCTION public.is_workspace_admin(p_workspace_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(moneybowl_authz.member_role(p_workspace_id,moneybowl_authz.actor())='admin',false)
$$;
CREATE OR REPLACE FUNCTION public.is_workspace_admin_or_ops(p_workspace_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(moneybowl_authz.member_role(p_workspace_id,moneybowl_authz.actor()) IN ('admin','operations'),false)
$$;
CREATE OR REPLACE FUNCTION public.has_active_workspace_membership(p_workspace_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT moneybowl_authz.member_role(p_workspace_id,moneybowl_authz.actor()) IS NOT NULL
$$;
CREATE OR REPLACE FUNCTION public.has_advisor_membership(p_workspace_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(moneybowl_authz.member_role(p_workspace_id,moneybowl_authz.actor()) IN ('admin','advisor'),false)
$$;
CREATE OR REPLACE FUNCTION public.has_investor_membership(p_workspace_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(moneybowl_authz.member_role(p_workspace_id,moneybowl_authz.actor()) IN ('investor','client'),false)
$$;
CREATE OR REPLACE FUNCTION public.has_active_investor_link(target_profile_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT moneybowl_authz.owns_investor(target_profile_id)
$$;

CREATE FUNCTION public.can_access_investor(p_workspace_id uuid,p_investor_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(moneybowl_authz.member_role(p_workspace_id,moneybowl_authz.actor()) IN ('advisor','admin','operations')
    AND moneybowl_authz.member_role(p_workspace_id,p_investor_id) IN ('investor','client'),false)
$$;
-- Fail closed for legacy callers that cannot provide resource provenance.
CREATE OR REPLACE FUNCTION public.can_access_investor(p_investor_profile_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT false $$;

CREATE OR REPLACE FUNCTION public.can_access_profile(p_profile_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(p_profile_id=moneybowl_authz.actor(),false) OR moneybowl_authz.owns_investor(p_profile_id)
    OR EXISTS (SELECT 1 FROM public.workspace_memberships m
      WHERE m.profile_id=p_profile_id AND moneybowl_authz.member_role(m.workspace_id,m.profile_id) IS NOT NULL
        AND coalesce(moneybowl_authz.member_role(m.workspace_id,moneybowl_authz.actor()) IN ('admin','advisor','operations'),false))
$$;

ALTER TABLE public.advisor_investor_assignments ADD COLUMN workspace_id uuid REFERENCES public.workspaces(id);
DROP TRIGGER verify_assignment_integrity ON public.advisor_investor_assignments;
-- Only one contemporaneous common workspace is evidence. Do not use today's
-- active flag to hide a second historical workspace and invent ownership.
UPDATE public.advisor_investor_assignments a SET workspace_id=s.workspace_id
FROM (SELECT a0.id, (array_agg(DISTINCT am.workspace_id))[1] workspace_id
  FROM public.advisor_investor_assignments a0
  JOIN public.workspace_memberships am ON am.profile_id=a0.advisor_id
    AND am.role IN ('advisor','admin') AND am.joined_at<=a0.assigned_at
    AND (am.ended_at IS NULL OR am.ended_at>a0.assigned_at)
  JOIN public.workspace_memberships im ON im.workspace_id=am.workspace_id AND im.profile_id=a0.investor_id
    AND im.role IN ('investor','client') AND im.joined_at<=a0.assigned_at
    AND (im.ended_at IS NULL OR im.ended_at>a0.assigned_at)
  GROUP BY a0.id HAVING count(DISTINCT am.workspace_id)=1) s WHERE s.id=a.id;
DROP INDEX public.unique_active_advisor_investor_assignment;
CREATE UNIQUE INDEX unique_active_advisor_investor_assignment
  ON public.advisor_investor_assignments(workspace_id,advisor_id,investor_id) WHERE ended_at IS NULL;
CREATE INDEX advisor_assignment_scope ON public.advisor_investor_assignments(workspace_id,investor_id,advisor_id)
  WHERE status='active' AND ended_at IS NULL;

CREATE FUNCTION moneybowl_authz.assigned(p_workspace uuid,p_advisor uuid,p_investor uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(moneybowl_authz.member_role(p_workspace,p_advisor) IN ('advisor','admin')
    AND moneybowl_authz.member_role(p_workspace,p_investor) IN ('investor','client'),false)
    AND EXISTS (SELECT 1 FROM public.advisor_investor_assignments a
      WHERE a.workspace_id=p_workspace AND a.advisor_id=p_advisor AND a.investor_id=p_investor
        AND a.status='active' AND a.ended_at IS NULL)
$$;

CREATE OR REPLACE FUNCTION public.verify_advisor_investor_assignment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP='UPDATE' AND (NEW.workspace_id,NEW.advisor_id,NEW.investor_id,NEW.assigned_by,NEW.assigned_at)
      IS DISTINCT FROM (OLD.workspace_id,OLD.advisor_id,OLD.investor_id,OLD.assigned_by,OLD.assigned_at) THEN
    RAISE EXCEPTION 'assignment_provenance_immutable';
  END IF;
  IF NEW.status='active' AND NEW.ended_at IS NULL AND
      (NEW.workspace_id IS NULL OR
       coalesce(moneybowl_authz.member_role(NEW.workspace_id,NEW.advisor_id) IN ('advisor','admin'),false)=false OR
       coalesce(moneybowl_authz.member_role(NEW.workspace_id,NEW.investor_id) IN ('investor','client'),false)=false) THEN
    RAISE EXCEPTION 'assignment_scope_invalid';
  END IF;
  IF current_setting('role',true) IN ('authenticated','anon') THEN
    PERFORM moneybowl_authz.lock_scope(NEW.workspace_id);
    IF NOT public.is_workspace_admin(NEW.workspace_id) THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='42501'; END IF;
    IF TG_OP='INSERT' THEN NEW.assigned_by:=moneybowl_authz.actor(); NEW.assigned_at:=now();
    ELSE NEW.ended_by:=moneybowl_authz.actor();
      IF NEW.status='ended' THEN NEW.ended_at:=coalesce(OLD.ended_at,now()); END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER verify_assignment_integrity BEFORE INSERT OR UPDATE ON public.advisor_investor_assignments
FOR EACH ROW EXECUTE FUNCTION public.verify_advisor_investor_assignment();

ALTER TABLE public.verification_requests ADD COLUMN workspace_id uuid REFERENCES public.workspaces(id);
ALTER TABLE public.folio_submission_tokens ADD COLUMN workspace_id uuid REFERENCES public.workspaces(id);
ALTER TABLE public.folio_grants ADD COLUMN workspace_id uuid REFERENCES public.workspaces(id);

-- Folio scope can only be proved from a linked investor and persisted portfolio.
CREATE FUNCTION moneybowl_authz.folio_workspaces(p_user uuid,p_folio uuid) RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT DISTINCT p.workspace_id FROM public.investor_account_links l
    JOIN public.portfolios p ON p.client_id=l.profile_id
    JOIN public.portfolio_folio_references pf ON pf.portfolio_id=p.id
  WHERE l.user_id=p_user AND l.link_status='active' AND pf.folio_reference_id=p_folio
    AND moneybowl_authz.member_role(p.workspace_id,l.profile_id) IN ('investor','client')
$$;
-- Historical attribution uses all portfolios, not a filtered active subset.
UPDATE public.verification_requests r SET workspace_id=s.workspace_id
FROM (SELECT r0.id,(array_agg(DISTINCT p.workspace_id))[1] workspace_id
  FROM public.verification_requests r0
  JOIN public.verification_folio_evidence e ON e.request_id=r0.id
  JOIN public.investor_account_links l ON l.user_id=r0.user_id
  JOIN public.portfolios p ON p.client_id=l.profile_id
  JOIN public.portfolio_folio_references pf ON pf.portfolio_id=p.id AND pf.folio_reference_id=e.folio_reference_id
  GROUP BY r0.id HAVING count(DISTINCT p.workspace_id)=1 AND bool_and(p.workspace_id IS NOT NULL)) s WHERE s.id=r.id;
UPDATE public.folio_grants g SET workspace_id=r.workspace_id FROM public.verification_requests r
  WHERE r.id=g.request_id AND r.user_id=g.user_id AND r.workspace_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.profiles approver JOIN public.workspace_memberships m ON m.profile_id=approver.id
      WHERE approver.user_id=g.approved_by AND approver.role<>'platform_admin'
        AND m.workspace_id=r.workspace_id AND m.role IN ('advisor','admin')
        AND m.joined_at<=g.approved_at AND (m.ended_at IS NULL OR m.ended_at>g.approved_at));
-- Existing tokens carry no workspace evidence; leave them unscoped and unusable.
DROP INDEX public.idx_folio_grants_active_unique;
CREATE UNIQUE INDEX idx_folio_grants_active_unique ON public.folio_grants
  (workspace_id,user_id,profile_id,folio_reference_id,holder_relationship) WHERE status='active';

CREATE FUNCTION moneybowl_authz.can_review(p_request uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.verification_requests r
    WHERE r.id=p_request AND moneybowl_authz.account_active(r.user_id)
      AND r.user_id<>auth.uid() AND public.has_advisor_membership(r.workspace_id)
      AND (r.method_code<>'folio' OR (EXISTS (SELECT 1 FROM public.verification_request_assignments a
        WHERE a.request_id=r.id AND a.advisor_account_id=auth.uid() AND a.active)
        AND EXISTS (SELECT 1 FROM public.verification_folio_evidence e
          WHERE e.request_id=r.id AND r.workspace_id IN (SELECT moneybowl_authz.folio_workspaces(r.user_id,e.folio_reference_id))))))
$$;
CREATE FUNCTION public.can_review_verification(p_request_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT moneybowl_authz.can_review(p_request_id)
$$;

CREATE OR REPLACE FUNCTION public.has_active_folio_grant(p_profile_id uuid,p_portfolio_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT moneybowl_authz.owns_investor(p_profile_id) AND EXISTS (
    SELECT 1 FROM public.portfolios p JOIN public.portfolio_folio_references pf ON pf.portfolio_id=p.id
    JOIN public.folio_grants g ON g.folio_reference_id=pf.folio_reference_id
      AND g.workspace_id=p.workspace_id AND g.profile_id=p.client_id
    WHERE p.id=p_portfolio_id AND p.client_id=p_profile_id AND g.user_id=auth.uid() AND g.status='active'
      AND moneybowl_authz.member_role(p.workspace_id,p_profile_id) IN ('investor','client'))
$$;
CREATE FUNCTION public.can_read_portfolio(p_portfolio_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.portfolios p WHERE p.id=p_portfolio_id AND
    (public.can_access_investor(p.workspace_id,p.client_id)
      OR public.has_active_folio_grant(p.client_id,p.id)
      OR (moneybowl_authz.member_role(p.workspace_id,p.client_id) IN ('investor','client')
        AND moneybowl_authz.actor() IS NOT NULL AND NOT public.is_platform_admin()
        AND EXISTS (SELECT 1 FROM public.family_delegations d WHERE d.workspace_id=p.workspace_id
          AND d.owner_profile_id=p.client_id AND d.delegate_profile_id=moneybowl_authz.actor()
          AND d.consent_status='accepted' AND d.is_active AND (d.expires_at IS NULL OR d.expires_at>now())))))
$$;

CREATE OR REPLACE FUNCTION public.is_order_mfd_profile(p_workspace_id uuid,p_profile_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(moneybowl_authz.member_role(p_workspace_id,p_profile_id)='advisor'
    OR (moneybowl_authz.member_role(p_workspace_id,p_profile_id)='admin' AND EXISTS (
      SELECT 1 FROM public.workspaces w WHERE w.id=p_workspace_id AND w.owner_profile_id=p_profile_id)),false)
$$;
CREATE OR REPLACE FUNCTION public.can_select_order_request(p_workspace_id uuid,p_investor_profile_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT NOT public.is_platform_admin() AND coalesce(moneybowl_authz.member_role(p_workspace_id,p_investor_profile_id) IN ('investor','client')
    AND (moneybowl_authz.owns_investor(p_investor_profile_id)
      OR public.is_order_mfd_profile(p_workspace_id,moneybowl_authz.actor())),false)
$$;

-- Complete replacement of the affected policy sets; permissive policies OR.
DO $$ DECLARE p record; BEGIN
  FOR p IN SELECT schemaname,tablename,policyname FROM pg_catalog.pg_policies
    WHERE schemaname='public' AND tablename IN ('portfolios','transactions','user_accounts','investor_account_links',
      'verification_requests','verification_events','advisor_investor_assignments','crm_notes','ingestion_logs',
      'advisor_profiles','advisor_euin_assignments','workspace_memberships','cams_statements')
  LOOP EXECUTE format('DROP POLICY %I ON %I.%I',p.policyname,p.schemaname,p.tablename); END LOOP;
END $$;
CREATE POLICY portfolios_scoped_read ON public.portfolios FOR SELECT TO authenticated USING(public.can_read_portfolio(id));
CREATE POLICY transactions_scoped_read ON public.transactions FOR SELECT TO authenticated USING(EXISTS (
  SELECT 1 FROM public.portfolios p WHERE p.id=portfolio_id
    AND (public.can_access_investor(p.workspace_id,p.client_id) OR public.has_active_folio_grant(p.client_id,p.id))));
CREATE POLICY account_self_read ON public.user_accounts FOR SELECT TO authenticated USING(user_id=(select auth.uid()));
CREATE POLICY link_self_read ON public.investor_account_links FOR SELECT TO authenticated USING(user_id=(select auth.uid()));
CREATE POLICY request_scoped_read ON public.verification_requests FOR SELECT TO authenticated
  USING(user_id=(select auth.uid()) OR public.can_review_verification(id));
CREATE POLICY verification_event_scoped_read ON public.verification_events FOR SELECT TO authenticated
  USING(subject_user_id=(select auth.uid()) OR public.can_review_verification(request_id));
CREATE POLICY assignment_scoped_read ON public.advisor_investor_assignments FOR SELECT TO authenticated
  USING(public.has_active_workspace_membership(workspace_id)
    AND (advisor_id=public.current_user_profile_id() OR investor_id=public.current_user_profile_id()
      OR public.is_workspace_admin_or_ops(workspace_id)));
CREATE POLICY assignment_scoped_write ON public.advisor_investor_assignments FOR ALL TO authenticated
  USING(public.is_workspace_admin(workspace_id)) WITH CHECK(public.is_workspace_admin(workspace_id));
CREATE POLICY crm_scoped_read ON public.crm_notes FOR SELECT TO authenticated
  USING(public.can_access_investor(workspace_id,client_profile_id)
    OR (client_profile_id=public.current_user_profile_id() AND public.has_investor_membership(workspace_id)));
CREATE POLICY crm_scoped_insert ON public.crm_notes FOR INSERT TO authenticated
  WITH CHECK(public.has_advisor_membership(workspace_id) AND advisor_profile_id=public.current_user_profile_id()
    AND public.can_access_investor(workspace_id,client_profile_id));
CREATE POLICY ingestion_scoped_read ON public.ingestion_logs FOR SELECT TO authenticated USING(public.has_advisor_membership(workspace_id));
CREATE POLICY professional_scoped_read ON public.advisor_profiles FOR SELECT TO authenticated USING(public.can_access_profile(profile_id));
CREATE POLICY professional_self_insert ON public.advisor_profiles FOR INSERT TO authenticated WITH CHECK(profile_id=public.current_user_profile_id() AND public.can_access_profile(profile_id));
CREATE POLICY professional_self_update ON public.advisor_profiles FOR UPDATE TO authenticated USING(profile_id=public.current_user_profile_id() AND public.can_access_profile(profile_id)) WITH CHECK(profile_id=public.current_user_profile_id() AND public.can_access_profile(profile_id));
CREATE POLICY euin_scoped_read ON public.advisor_euin_assignments FOR SELECT TO authenticated
  USING(EXISTS(SELECT 1 FROM public.advisor_profiles a WHERE a.id=advisor_profile_id AND public.can_access_profile(a.profile_id)));
CREATE POLICY membership_scoped_read ON public.workspace_memberships FOR SELECT TO authenticated USING(public.has_active_workspace_membership(workspace_id));
-- Tenant admins cannot manufacture an investor relationship from a known UUID.
-- Invitations remain the verified-recipient admission path. Maintenance is trusted.
REVOKE INSERT,UPDATE,DELETE ON public.workspace_memberships FROM authenticated,anon;
REVOKE ALL ON public.cams_statements FROM authenticated,anon;
REVOKE INSERT,UPDATE,DELETE ON public.ingestion_logs FROM authenticated,anon;

CREATE FUNCTION moneybowl_authz.lock_scope(p_workspace uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM 1 FROM public.workspaces WHERE id=p_workspace FOR SHARE;
  PERFORM 1 FROM public.profiles WHERE id IN (SELECT profile_id FROM public.workspace_memberships WHERE workspace_id=p_workspace) ORDER BY id FOR SHARE;
  PERFORM 1 FROM auth.users WHERE id IN (SELECT p.user_id FROM public.profiles p JOIN public.workspace_memberships m ON m.profile_id=p.id WHERE m.workspace_id=p_workspace) ORDER BY id FOR SHARE;
  PERFORM 1 FROM public.workspace_memberships WHERE workspace_id=p_workspace ORDER BY id FOR SHARE;
END $$;

CREATE FUNCTION moneybowl_authz.assert_review(p_request uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE w uuid;
BEGIN
  SELECT workspace_id INTO w FROM public.verification_requests WHERE id=p_request FOR UPDATE;
  PERFORM moneybowl_authz.lock_scope(w);
  IF NOT moneybowl_authz.can_review(p_request) THEN RAISE EXCEPTION 'Advisor authorization is required'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public._assert_assigned_folio_advisor(p_request_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM moneybowl_authz.assert_review(p_request_id);
  PERFORM 1 FROM public.verification_request_assignments a JOIN public.verification_requests r ON r.id=a.request_id
    WHERE r.id=p_request_id AND r.method_code='folio' AND a.advisor_account_id=auth.uid() AND a.active FOR UPDATE OF a;
  IF NOT FOUND THEN RAISE EXCEPTION 'Folio review is unavailable'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.validate_folio_request_assignment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE w uuid; reviewer uuid;
BEGIN
  IF NOT NEW.active THEN RETURN NEW; END IF;
  SELECT workspace_id INTO w FROM public.verification_requests WHERE id=NEW.request_id AND method_code='folio';
  SELECT id INTO reviewer FROM public.profiles WHERE user_id=NEW.advisor_account_id;
  IF coalesce(moneybowl_authz.member_role(w,reviewer) IN ('advisor','admin'),false)=false THEN
    RAISE EXCEPTION 'folio_assignment_scope_invalid';
  END IF;
  IF NEW.assigned_by_account_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.profiles p
    WHERE p.user_id=NEW.assigned_by_account_id AND moneybowl_authz.member_role(w,p.id)='admin') THEN
    RAISE EXCEPTION 'folio_assignment_scope_invalid';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION moneybowl_authz.guard_folio_grant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP='UPDATE' THEN
    IF (NEW.workspace_id,NEW.request_id,NEW.user_id,NEW.profile_id,NEW.folio_reference_id,NEW.holder_relationship)
      IS DISTINCT FROM (OLD.workspace_id,OLD.request_id,OLD.user_id,OLD.profile_id,OLD.folio_reference_id,OLD.holder_relationship) THEN
      RAISE EXCEPTION 'folio_grant_provenance_immutable';
    END IF;
    IF NEW.status<>'active' THEN RETURN NEW; END IF;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.verification_requests r
    JOIN public.verification_folio_evidence e ON e.request_id=r.id
    JOIN public.investor_account_links l ON l.user_id=r.user_id AND l.link_status='active'
    WHERE r.id=NEW.request_id AND r.workspace_id=NEW.workspace_id AND r.user_id=NEW.user_id
      AND l.profile_id=NEW.profile_id AND e.folio_reference_id=NEW.folio_reference_id
      AND e.holder_relationship=NEW.holder_relationship
      AND NEW.workspace_id IN (SELECT moneybowl_authz.folio_workspaces(NEW.user_id,NEW.folio_reference_id))) THEN
    RAISE EXCEPTION 'folio_grant_scope_invalid';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER folio_grant_scope BEFORE INSERT OR UPDATE ON public.folio_grants
FOR EACH ROW EXECUTE FUNCTION moneybowl_authz.guard_folio_grant();

CREATE FUNCTION moneybowl_authz.single_folio_reviewer(p_workspace uuid,p_user uuid) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE candidates uuid[]; owner_user uuid;
BEGIN
  SELECT array_agg(DISTINCT p.user_id) INTO candidates FROM public.profiles p
    JOIN public.investor_account_links l ON l.user_id=p_user AND l.link_status='active'
    WHERE p.user_id IS NOT NULL AND p.user_id<>p_user
      AND moneybowl_authz.assigned(p_workspace,p.id,l.profile_id);
  IF cardinality(candidates)=1 THEN RETURN candidates[1]; END IF;
  SELECT p.user_id INTO owner_user FROM public.workspaces w JOIN public.profiles p ON p.id=w.owner_profile_id
    WHERE w.id=p_workspace AND p.user_id<>p_user AND moneybowl_authz.member_role(w.id,p.id)='admin';
  IF owner_user IS NOT NULL THEN RETURN owner_user; END IF;
  SELECT array_agg(p.user_id) INTO candidates FROM public.profiles p WHERE p.user_id IS NOT NULL AND p.user_id<>p_user
    AND moneybowl_authz.member_role(p_workspace,p.id) IN ('advisor','admin');
  IF cardinality(candidates)=1 THEN RETURN candidates[1]; END IF;
  RETURN NULL;
END
$$;
CREATE OR REPLACE FUNCTION public._single_active_advisor_account() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT NULL::uuid $$;

-- Caller selection is only a selector; the linked investor's persisted portfolio
-- proves workspace authority. The legacy two-argument API requires unique scope.
CREATE FUNCTION public.issue_folio_submission_token(p_registrar text,p_folio_number text,p_workspace_id uuid)
RETURNS TABLE(submission_token text,masked_folio_summary text,registrar_display_name text,expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE f public.folio_references; t public.folio_submission_tokens; w uuid; scopes uuid[];
BEGIN
  IF NOT moneybowl_authz.account_active(auth.uid()) THEN RAISE EXCEPTION 'Folio is unavailable'; END IF;
  SELECT * INTO f FROM public.folio_references WHERE registrar=upper(trim(p_registrar))
    AND normalized_folio_number=upper(regexp_replace(coalesce(p_folio_number,''),'[^A-Za-z0-9]','','g'));
  SELECT array_agg(s) INTO scopes FROM moneybowl_authz.folio_workspaces(auth.uid(),f.id) s;
  IF p_workspace_id IS NULL THEN
    IF cardinality(scopes) IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'Folio is unavailable'; END IF;
    w:=scopes[1];
  ELSE
    IF coalesce(p_workspace_id=ANY(scopes),false)=false THEN RAISE EXCEPTION 'Folio is unavailable'; END IF;
    w:=p_workspace_id;
  END IF;
  PERFORM moneybowl_authz.lock_scope(w);
  IF w NOT IN (SELECT moneybowl_authz.folio_workspaces(auth.uid(),f.id)) THEN RAISE EXCEPTION 'Folio is unavailable'; END IF;
  INSERT INTO public.folio_submission_tokens(user_id,folio_reference_id,workspace_id,expires_at)
    VALUES(auth.uid(),f.id,w,now()+interval '5 minutes') RETURNING * INTO t;
  RETURN QUERY SELECT encode(extensions.pgp_sym_encrypt(jsonb_build_object('token_id',t.token_id,'user_id',auth.uid())::text,
    public.verification_candidate_token_secret(),'cipher-algo=aes256, compress-algo=0'),'base64'),
    public.mask_folio_summary(f.registrar,f.source_folio_masked),CASE WHEN f.registrar='KFINTECH' THEN 'KFintech' ELSE 'CAMS' END,t.expires_at;
END $$;
CREATE OR REPLACE FUNCTION public.issue_folio_submission_token(p_registrar text,p_folio_number text)
RETURNS TABLE(submission_token text,masked_folio_summary text,registrar_display_name text,expires_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT * FROM public.issue_folio_submission_token(p_registrar,p_folio_number,NULL::uuid)
$$;

-- PAN evidence can resolve scope only when both identity and workspace are unique.
-- Unresolved/manual historical requests remain unscoped for controlled remediation.
CREATE FUNCTION moneybowl_authz.scope_pan_request() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE candidates uuid[]; scopes uuid[];
BEGIN
  SELECT array_agg(DISTINCT p.id) INTO candidates FROM public.profiles p JOIN public.profile_pan_records pr ON pr.profile_id=p.id
    WHERE pr.pan_lookup_hmac=NEW.pan_lookup_hmac AND pr.status IN ('OBSERVED','VERIFIED') AND p.role IN ('investor','client');
  IF NEW.match_result='SINGLE_MATCH' AND NEW.conflict_reason='NONE' AND cardinality(candidates)=1 THEN
    SELECT array_agg(DISTINCT workspace_id) INTO scopes FROM public.workspace_memberships
      WHERE profile_id=candidates[1] AND role IN ('investor','client');
    IF cardinality(scopes)=1 THEN
      UPDATE public.verification_requests SET workspace_id=scopes[1] WHERE id=NEW.request_id AND workspace_id IS NULL;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER scope_pan_request AFTER INSERT ON public.verification_pan_evidence
FOR EACH ROW EXECUTE FUNCTION moneybowl_authz.scope_pan_request();

CREATE OR REPLACE FUNCTION nse_app.actor() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE a uuid:=moneybowl_authz.actor();
BEGIN
  IF a IS NULL OR public.is_platform_admin() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN a;
END $$;
CREATE OR REPLACE FUNCTION nse_app.can_target(p_actor uuid,p_target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p_actor=moneybowl_authz.actor() AND EXISTS (SELECT 1 FROM public.workspace_memberships i
    JOIN public.workspaces w ON w.id=i.workspace_id
    WHERE i.id=p_target AND i.status='active' AND i.ended_at IS NULL
      AND moneybowl_authz.member_role(i.workspace_id,i.profile_id) IN ('investor','client')
      AND ((moneybowl_authz.member_role(i.workspace_id,p_actor)='admin' AND w.owner_profile_id=p_actor)
        OR (moneybowl_authz.member_role(i.workspace_id,p_actor)='advisor'
          AND moneybowl_authz.assigned(i.workspace_id,p_actor,i.profile_id))))
$$;
CREATE OR REPLACE FUNCTION public.authorize_cams_kfintech_workspace(p_workspace_id uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.has_advisor_membership(p_workspace_id) THEN RAISE EXCEPTION 'not_authorized'; END IF;
  RETURN true;
END $$;

-- User-supplied document utilities do not identify a stored investor resource.
-- Require an active professional workspace, without treating persona as authority.
CREATE FUNCTION public.authorize_workspace_tools() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS(SELECT 1 FROM public.current_user_workspace_ids() w WHERE public.has_advisor_membership(w))
$$;

-- Rebind existing workflow bodies without changing their public signatures.

CREATE OR REPLACE FUNCTION public.approve_verification_candidate(p_request_id uuid, p_candidate_token text, p_expected_version integer, p_reason_code text DEFAULT NULL::text) RETURNS public.verification_request_status
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare request_row public.verification_requests%rowtype; token_payload jsonb; v_candidate_profile_id uuid;
begin
  perform moneybowl_authz.assert_review(p_request_id);
  select * into request_row from public.verification_requests where id=p_request_id for update;
  if not found then raise exception 'Verification request cannot be approved'; end if;
  if request_row.method_code='folio' then raise exception using errcode='PFL01',message='Use the dedicated folio verification lifecycle'; end if;
  begin token_payload:=extensions.pgp_sym_decrypt(decode(p_candidate_token,'base64'),public.verification_candidate_token_secret())::jsonb; exception when others then raise exception 'Verification candidate is unavailable'; end;
  if token_payload->>'request_id' IS DISTINCT FROM p_request_id::text or token_payload->>'advisor_user_id' IS DISTINCT FROM auth.uid()::text or coalesce((token_payload->>'expires_at')::bigint,0)<extract(epoch from now())::bigint then raise exception 'Verification candidate is unavailable'; end if;
  if request_row.method_code='pan' then return public.approve_pan_verification_candidate(p_request_id,p_candidate_token,p_expected_version,p_reason_code); end if;
  v_candidate_profile_id:=(token_payload->>'profile_id')::uuid;
  if coalesce(moneybowl_authz.member_role(request_row.workspace_id,v_candidate_profile_id) in ('investor','client'),false)=false then raise exception 'Verification candidate is unavailable'; end if;
  if request_row.status <> 'pending_advisor_review' or request_row.version <> p_expected_version or not exists(select 1 from public.profiles where id=v_candidate_profile_id and role IN ('investor','client')) or exists(select 1 from public.investor_account_links where (user_id=request_row.user_id or profile_id=v_candidate_profile_id) and link_status='active') then raise exception 'Verification request cannot be approved'; end if;
  insert into public.investor_account_links(user_id,profile_id,verification_method,verified_at,linked_at,link_status) values(request_row.user_id,v_candidate_profile_id,request_row.method_code,now(),now(),'active') on conflict(user_id,profile_id) do update set verification_method=excluded.verification_method,verified_at=excluded.verified_at,linked_at=excluded.linked_at,link_status='active';
  update public.user_accounts set account_state='linked_investor',onboarding_completed=true where user_id=request_row.user_id;
  update public.verification_requests set status='approved',candidate_profile_id=v_candidate_profile_id,resolved_at=now(),version=version+1 where id=request_row.id and version=p_expected_version;
  insert into public.verification_events(request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(request_row.id,request_row.user_id,auth.uid(),'advisor','approved','pending_advisor_review','approved',p_reason_code);
  return 'approved'::public.verification_request_status;
end;
$$;

CREATE OR REPLACE FUNCTION public.approve_pan_verification_candidate(p_request_id uuid, p_candidate_token text, p_expected_version integer, p_reason_code text DEFAULT NULL::text) RETURNS public.verification_request_status
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_request public.verification_requests%rowtype;
  v_token_payload jsonb;
  v_profile_id uuid;
  v_evidence public.verification_pan_evidence%rowtype;
  v_matching_record_id uuid;
begin
  perform moneybowl_authz.assert_review(p_request_id);
  begin v_token_payload := extensions.pgp_sym_decrypt(decode(p_candidate_token, 'base64'), public.verification_candidate_token_secret())::jsonb;
  exception when others then raise exception 'Verification candidate is unavailable'; end;
  if v_token_payload ->> 'request_id' IS DISTINCT FROM p_request_id::text or v_token_payload ->> 'advisor_user_id' IS DISTINCT FROM auth.uid()::text or coalesce((v_token_payload ->> 'expires_at')::bigint, 0) < extract(epoch from now())::bigint then raise exception 'Verification candidate is unavailable'; end if;
  v_profile_id := (v_token_payload ->> 'profile_id')::uuid;
  select request_row.* into v_request from public.verification_requests as request_row where request_row.id = p_request_id for update;
  if not found or v_request.method_code <> 'pan' or v_request.status <> 'pending_advisor_review' or v_request.version <> p_expected_version then raise exception 'Verification request cannot be approved'; end if;
  if coalesce(moneybowl_authz.member_role(v_request.workspace_id,v_profile_id) in ('investor','client'),false)=false then raise exception 'Verification candidate is unavailable'; end if;
  select evidence.* into v_evidence from public.verification_pan_evidence as evidence where evidence.request_id = v_request.id;
  if not found or v_evidence.match_result <> 'SINGLE_MATCH' or v_evidence.conflict_reason <> 'NONE' then raise exception 'PAN verification requires manual resolution'; end if;
  select pan_record.id into v_matching_record_id from public.profile_pan_records as pan_record
  join public.profiles as candidate_profile on candidate_profile.id = pan_record.profile_id and candidate_profile.role IN ('investor','client')
  where pan_record.profile_id = v_profile_id and pan_record.pan_lookup_hmac = v_evidence.pan_lookup_hmac
    and pan_record.status in ('OBSERVED', 'VERIFIED')
  order by pan_record.created_at asc limit 1;
  if v_matching_record_id is null then raise exception 'PAN verification requires manual resolution'; end if;
  if exists (select 1 from public.investor_account_links as active_link where (active_link.user_id = v_request.user_id or active_link.profile_id = v_profile_id) and active_link.link_status = 'active') then raise exception 'Verification request cannot be approved'; end if;
  insert into public.investor_account_links (user_id, profile_id, verification_method, verified_at, linked_at, link_status)
  values (v_request.user_id, v_profile_id, 'pan', now(), now(), 'active') on conflict (user_id, profile_id) do update set verification_method = excluded.verification_method, verified_at = excluded.verified_at, linked_at = excluded.linked_at, link_status = 'active';
  update public.profile_pan_records as pan_record set status = 'VERIFIED', verified_at = now() where pan_record.id = v_matching_record_id;
  update public.profiles as profile set canonical_pan_record_id = v_matching_record_id where profile.id = v_profile_id;
  update public.user_accounts as account set account_state = 'linked_investor', onboarding_completed = true where account.user_id = v_request.user_id;
  update public.verification_requests as request_row set status = 'approved', candidate_profile_id = v_profile_id, resolved_at = now(), version = request_row.version + 1 where request_row.id = v_request.id and request_row.version = p_expected_version;
  if not found then raise exception 'Verification request changed; refresh and retry'; end if;
  insert into public.verification_events (request_id, subject_user_id, actor_user_id, actor_type, event_type, previous_status, new_status, reason_code)
  values (v_request.id, v_request.user_id, auth.uid(), 'advisor', 'approved', 'pending_advisor_review', 'approved', p_reason_code);
  return 'approved'::public.verification_request_status;
end;
$$;

CREATE OR REPLACE FUNCTION public.approve_verification_request(p_request_id uuid, p_profile_id uuid, p_expected_version integer, p_reason_code text DEFAULT NULL::text) RETURNS public.verification_request_status
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform moneybowl_authz.assert_review(p_request_id);
  raise exception 'verification_candidate_token_required';
end;
$$;

CREATE OR REPLACE FUNCTION public.reject_verification_request(p_request_id uuid, p_expected_version integer, p_reason_code text DEFAULT NULL::text) RETURNS public.verification_request_status
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare request_row public.verification_requests%rowtype;
begin
  perform moneybowl_authz.assert_review(p_request_id);
  select * into request_row from public.verification_requests where id=p_request_id for update;
  if not found then raise exception 'Verification request cannot be rejected'; end if;
  if request_row.method_code='folio' then raise exception using errcode='PFL01',message='Use the dedicated folio verification lifecycle'; end if;
  if request_row.status <> 'pending_advisor_review' or request_row.version <> p_expected_version then raise exception 'Verification request cannot be rejected'; end if;
  update public.verification_requests set status='rejected',resolved_at=now(),version=version+1 where id=request_row.id and version=p_expected_version;
  insert into public.verification_events (request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(request_row.id,request_row.user_id,auth.uid(),'advisor','rejected','pending_advisor_review','rejected',p_reason_code);
  return 'rejected'::public.verification_request_status;
end;
$$;

CREATE OR REPLACE FUNCTION public.request_more_verification_information(p_request_id uuid, p_expected_version integer, p_reason_code text) RETURNS public.verification_request_status
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare request_row public.verification_requests%rowtype;
begin
  perform moneybowl_authz.assert_review(p_request_id);
  select * into request_row from public.verification_requests where id=p_request_id for update;
  if not found then raise exception 'Verification request cannot be updated'; end if;
  if request_row.method_code='folio' then raise exception using errcode='PFL01',message='Use the dedicated folio verification lifecycle'; end if;
  if nullif(trim(p_reason_code),'') is null or request_row.status <> 'pending_advisor_review' or request_row.version <> p_expected_version then raise exception 'Verification request cannot be updated'; end if;
  update public.verification_requests set status='more_information_required',version=version+1 where id=request_row.id and version=p_expected_version;
  insert into public.verification_events (request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(request_row.id,request_row.user_id,auth.uid(),'advisor','more_information_requested','pending_advisor_review','more_information_required',trim(p_reason_code));
  return 'more_information_required'::public.verification_request_status;
end;
$$;

CREATE OR REPLACE FUNCTION public.get_verification_review(p_request_id uuid) RETURNS TABLE(id uuid, method_code text, status public.verification_request_status, created_at timestamp with time zone, submitted_at timestamp with time zone, resolved_at timestamp with time zone, expires_at timestamp with time zone, version integer, retry_of_request_id uuid, requester_masked_email text, requester_masked_mobile text, masked_pan text, pan_match_result text, pan_conflict_reason text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform moneybowl_authz.assert_review(p_request_id);
  perform public._reject_generic_folio_request(p_request_id);
  return query select request_row.id,request_row.method_code,request_row.status,request_row.created_at,request_row.submitted_at,request_row.resolved_at,request_row.expires_at,request_row.version,request_row.retry_of_request_id,public.mask_verification_email(auth_user.email),public.mask_verification_mobile(auth_user.phone),evidence.masked_pan,evidence.match_result::text,evidence.conflict_reason::text
  from public.verification_requests request_row left join auth.users auth_user on auth_user.id = request_row.user_id
  left join public.verification_pan_evidence evidence on evidence.request_id = request_row.id
  where request_row.id = p_request_id and request_row.method_code <> 'folio';
end;
$$;

CREATE OR REPLACE FUNCTION public.search_verification_candidates(p_request_id uuid, p_query text) RETURNS TABLE(candidate_token text, candidate_name text, masked_email text, masked_mobile text, profile_summary text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare normalized_query text := trim(p_query);
begin
  perform moneybowl_authz.assert_review(p_request_id);
  perform public._reject_generic_folio_request(p_request_id);
  if normalized_query is null or length(normalized_query)<2 then raise exception 'Enter at least two characters to search'; end if;
  if not exists(select 1 from public.verification_requests where id=p_request_id and method_code<>'folio' and status in ('pending_advisor_review','more_information_required')) then raise exception 'Verification request is unavailable'; end if;
  return query select public.issue_verification_candidate_token(p_request_id,profile.id,auth.uid()),coalesce(nullif(profile.full_name,''),'Imported investor'),public.mask_verification_email(profile.verified_email),public.mask_verification_mobile(profile.verified_mobile),case when exists(select 1 from public.portfolios where client_id=profile.id and workspace_id=(select workspace_id from public.verification_requests where id=p_request_id)) then 'Portfolio record available' else 'Imported investor record' end
  from public.profiles profile where profile.role IN ('investor','client') and moneybowl_authz.member_role((select workspace_id from public.verification_requests where id=p_request_id),profile.id) IN ('investor','client') and (profile.full_name ilike '%'||normalized_query||'%' or profile.verified_email ilike '%'||normalized_query||'%' or profile.verified_mobile ilike '%'||normalized_query||'%') order by profile.full_name nulls last limit 20;
end;
$$;

CREATE OR REPLACE FUNCTION public.list_verification_review_queue() RETURNS TABLE(id uuid, user_id uuid, method_code text, status public.verification_request_status, submitted_at timestamp with time zone, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.authorize_workspace_tools() then raise exception 'Advisor authorization is required'; end if;
  return query select request_row.id,request_row.user_id,request_row.method_code,request_row.status,request_row.submitted_at,request_row.created_at
  from public.verification_requests request_row
  where public.can_review_verification(request_row.id) and request_row.status = 'pending_advisor_review' and request_row.method_code <> 'folio'
  order by request_row.submitted_at asc;
end;
$$;

CREATE OR REPLACE FUNCTION public.list_verification_review_queue_filtered(p_request_id_query text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_method_code text DEFAULT NULL::text) RETURNS TABLE(id uuid, method_code text, status public.verification_request_status, submitted_at timestamp with time zone, created_at timestamp with time zone, version integer, masked_pan text, pan_match_result text, pan_conflict_reason text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.authorize_workspace_tools() then raise exception 'Advisor authorization is required'; end if;
  return query select request_row.id,request_row.method_code,request_row.status,request_row.submitted_at,request_row.created_at,request_row.version,evidence.masked_pan,evidence.match_result::text,evidence.conflict_reason::text
  from public.verification_requests request_row
  left join public.verification_pan_evidence evidence on evidence.request_id = request_row.id
  where public.can_review_verification(request_row.id) and request_row.method_code <> 'folio'
    and (nullif(trim(p_request_id_query),'') is null or request_row.id::text ilike '%' || trim(p_request_id_query) || '%')
    and (nullif(trim(p_status),'') is null or request_row.status::text = trim(p_status))
    and (nullif(trim(p_method_code),'') is null or request_row.method_code = trim(p_method_code))
  order by request_row.submitted_at asc nulls last,request_row.created_at asc;
end;
$$;

CREATE OR REPLACE FUNCTION public.get_my_advisor_folio_requests(p_page integer DEFAULT 0, p_page_size integer DEFAULT 25, p_status public.verification_request_status DEFAULT NULL::public.verification_request_status) RETURNS TABLE(request_id uuid, version integer, investor_display_label text, registrar_display text, masked_folio text, holder_relationship public.folio_holder_relationship, status public.verification_request_status, submitted_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if auth.uid() is null or not public.authorize_workspace_tools() then
    raise exception 'Advisor authorization is required';
  end if;
  if p_page < 0 or p_page_size < 1 or p_page_size > 100 then
    raise exception 'Invalid pagination';
  end if;
  return query
  select request_row.id,request_row.version,
    'Investor request'::text,
    case when folio.registrar = 'KFINTECH' then 'KFintech' else 'CAMS' end,
    public.mask_canonical_folio(folio.normalized_folio_number),
    evidence.holder_relationship,request_row.status,request_row.submitted_at,
    request_row.updated_at
  from public.verification_request_assignments assignment
  join public.verification_requests request_row on request_row.id = assignment.request_id
  join public.verification_folio_evidence evidence on evidence.request_id = request_row.id
  join public.folio_references folio on folio.id = evidence.folio_reference_id
  where public.can_review_verification(request_row.id) and assignment.advisor_account_id = auth.uid() and assignment.active
    and request_row.method_code = 'folio'
    and (p_status is null or request_row.status = p_status)
  order by request_row.submitted_at asc nulls last, request_row.created_at asc, request_row.id asc
  limit p_page_size offset p_page * p_page_size;
end;
$$;

CREATE OR REPLACE FUNCTION public.get_verification_events(p_request_id uuid) RETURNS TABLE(id uuid, event_type text, previous_status public.verification_request_status, new_status public.verification_request_status, reason_code text, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'Authentication is required'; end if;
  perform public._reject_generic_folio_request(p_request_id);
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if not public.can_review_verification(p_request_id) and not exists (select 1 from public.verification_requests own_request where own_request.id = p_request_id and own_request.user_id = auth.uid()) then
    raise exception 'Verification history is not available';
  end if;
  return query select event_row.id,event_row.event_type,event_row.previous_status,event_row.new_status,event_row.reason_code,event_row.created_at
  from public.verification_events event_row where event_row.request_id = p_request_id order by event_row.created_at asc;
end;
$$;

CREATE OR REPLACE FUNCTION public.get_folio_request_detail(p_request_id uuid) RETURNS TABLE(masked_folio_summary text, status public.verification_request_status, submitted_at timestamp with time zone, resolved_at timestamp with time zone, expires_at timestamp with time zone, holder_relationship public.folio_holder_relationship, version integer, event_count bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'Authentication is required'; end if;
  if public.can_review_verification(p_request_id) then
    perform public._assert_assigned_folio_advisor(p_request_id);
  elsif not exists(select 1 from public.verification_requests own_request where own_request.id = p_request_id and own_request.user_id = auth.uid()) then
    raise exception 'Folio request is unavailable';
  end if;
  return query
  select public.mask_folio_summary(folio.registrar,folio.source_folio_masked),
    request_row.status,request_row.submitted_at,request_row.resolved_at,
    request_row.expires_at,evidence.holder_relationship,request_row.version,
    (select count(*) from public.verification_events event_row where event_row.request_id = request_row.id)
  from public.verification_requests request_row
  join public.verification_folio_evidence evidence on evidence.request_id = request_row.id
  join public.folio_references folio on folio.id = evidence.folio_reference_id
  where request_row.id = p_request_id and request_row.method_code = 'folio';
end;
$$;

CREATE OR REPLACE FUNCTION public.get_folio_grant_summary(p_request_id uuid) RETURNS TABLE(grant_status public.folio_grant_status, approved_at timestamp with time zone, revoked_at timestamp with time zone, masked_folio_summary text, holder_relationship public.folio_holder_relationship)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'Authentication is required'; end if;
  if public.can_review_verification(p_request_id) then
    perform public._assert_assigned_folio_advisor(p_request_id);
  elsif not exists(select 1 from public.verification_requests own_request where own_request.id = p_request_id and own_request.user_id = auth.uid()) then
    raise exception 'Folio grant is unavailable';
  end if;
  return query
  select grant_row.status,grant_row.approved_at,grant_row.revoked_at,
    public.mask_folio_summary(folio.registrar,folio.source_folio_masked),
    grant_row.holder_relationship
  from public.folio_grants grant_row
  join public.folio_references folio on folio.id = grant_row.folio_reference_id
  where grant_row.request_id = p_request_id;
end;
$$;

CREATE OR REPLACE FUNCTION public.get_folio_verification_events(p_request_id uuid) RETURNS TABLE(id uuid, event_type text, previous_status public.verification_request_status, new_status public.verification_request_status, reason_code text, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'Authentication is required'; end if;
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if public.can_review_verification(p_request_id) then
    perform public._assert_assigned_folio_advisor(p_request_id);
  elsif not exists (select 1 from public.verification_requests own_request where own_request.id = p_request_id and own_request.method_code = 'folio' and own_request.user_id = auth.uid()) then
    raise exception 'Folio verification history is not available';
  end if;
  return query select event_row.id,event_row.event_type,event_row.previous_status,event_row.new_status,event_row.reason_code,event_row.created_at
  from public.verification_events event_row where event_row.request_id = p_request_id order by event_row.created_at asc;
end;
$$;

CREATE OR REPLACE FUNCTION public._transition_folio_request(p_request_id uuid, p_expected_version integer, p_action text, p_reason text DEFAULT NULL::text) RETURNS TABLE(request_id uuid, status public.verification_request_status, version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  request_row public.verification_requests%rowtype;
  next_status public.verification_request_status;
  actor text;
  event_name text;
  normalized_reason text;
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'Authentication is required'; end if;
  select request_record.* into request_row
  from public.verification_requests as request_record
  where request_record.id = p_request_id
  for update;
  if not found
      or request_row.method_code <> 'folio'
      or request_row.version <> p_expected_version then
    raise exception 'Folio request changed or unavailable';
  end if;

  actor := case when p_action in ('cancel','resubmit') and request_row.user_id=auth.uid() then 'investor' else 'advisor' end;
  if actor = 'advisor' then
    -- The request is locked before the active assignment row.
    perform public._assert_assigned_folio_advisor(request_row.id);
  elsif request_row.user_id <> auth.uid() then
    raise exception 'Folio request unavailable';
  end if;

  if p_action = 'begin_review' and actor = 'advisor'
      and request_row.status = 'pending_advisor_review' then
    next_status := 'under_review';
    event_name := 'folio_review_started';
  elsif p_action = 'more_information' and actor = 'advisor'
      and request_row.status = 'under_review' then
    select public.validate_folio_review_reason_code('more_information', p_reason)
      into normalized_reason;
    next_status := 'more_information_required';
    event_name := 'folio_information_requested';
  elsif p_action = 'resubmit' and actor = 'investor'
      and request_row.status = 'more_information_required' then
    next_status := 'pending_advisor_review';
    event_name := 'folio_information_resubmitted';
  elsif p_action = 'reject' and actor = 'advisor'
      and request_row.status = 'under_review' then
    select public.validate_folio_review_reason_code('reject', p_reason)
      into normalized_reason;
    next_status := 'rejected';
    event_name := 'folio_rejected';
  elsif p_action = 'cancel' and actor = 'investor'
      and request_row.status in ('draft', 'pending_advisor_review', 'more_information_required') then
    next_status := 'cancelled';
    event_name := 'folio_cancelled';
  elsif p_action = 'expire' and actor = 'advisor'
      and request_row.status in ('pending_advisor_review', 'under_review', 'more_information_required')
      and request_row.expires_at <= now() then
    next_status := 'expired';
    event_name := 'folio_expired';
    normalized_reason := 'SYSTEM_EXPIRY';
  else
    raise exception 'Invalid folio lifecycle transition';
  end if;

  update public.verification_requests as request_record
  set status = next_status,
      resolved_at = case
        when next_status in ('rejected', 'cancelled', 'expired') then now()
        else null
      end,
      version = request_record.version + 1
  where request_record.id = request_row.id
    and request_record.version = p_expected_version;
  if not found then
    raise exception 'Folio request changed or unavailable';
  end if;

  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (
    request_row.id, request_row.user_id, auth.uid(), actor, event_name,
    request_row.status, next_status, normalized_reason
  );
  return query select request_row.id, next_status, p_expected_version + 1;
end;
$$;

CREATE OR REPLACE FUNCTION public.approve_folio_verification(p_request_id uuid, p_expected_version integer, p_reason text) RETURNS TABLE(request_id uuid, status public.verification_request_status, version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  request_row public.verification_requests%rowtype;
  evidence_row public.verification_folio_evidence%rowtype;
  linked_profile_id uuid;
  normalized_reason text;
begin
  if not public.can_review_verification(p_request_id) then
    raise exception 'Folio approval unavailable';
  end if;
  select request_record.* into request_row
  from public.verification_requests as request_record
  where request_record.id = p_request_id
  for update;
  if not found
      or request_row.method_code <> 'folio'
      or request_row.status <> 'under_review'
      or request_row.version <> p_expected_version then
    raise exception 'Folio request cannot be approved';
  end if;
  perform public._assert_assigned_folio_advisor(request_row.id);
  select evidence_record.* into evidence_row
  from public.verification_folio_evidence as evidence_record
  where evidence_record.request_id = request_row.id;
  select public.validate_folio_review_reason_code(
    'approve', p_reason, evidence_row.holder_relationship
  ) into normalized_reason;
  select link_record.profile_id into linked_profile_id
  from public.investor_account_links as link_record
  where link_record.user_id = request_row.user_id
    and link_record.link_status = 'active';
  if linked_profile_id is null then
    raise exception 'Folio request cannot be approved';
  end if;

  insert into public.folio_grants (
    workspace_id, request_id, user_id, profile_id, folio_reference_id,
    holder_relationship, approved_by
  ) values (
    request_row.workspace_id, request_row.id, request_row.user_id, linked_profile_id,
    evidence_row.folio_reference_id, evidence_row.holder_relationship, auth.uid()
  );
  update public.verification_requests as request_record
  set status = 'approved',
      resolved_at = now(),
      version = request_record.version + 1
  where request_record.id = request_row.id
    and request_record.version = p_expected_version;
  if not found then
    raise exception 'Folio request changed or unavailable';
  end if;
  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (
    request_row.id, request_row.user_id, auth.uid(), 'advisor',
    'folio_approved', 'under_review', 'approved', normalized_reason
  );
  return query select request_row.id,
    'approved'::public.verification_request_status,
    p_expected_version + 1;
end;
$$;

CREATE OR REPLACE FUNCTION public.revoke_folio_grant(p_grant_id uuid, p_expected_version integer, p_reason text) RETURNS public.folio_grant_status
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  grant_row public.folio_grants%rowtype;
  request_row public.verification_requests%rowtype;
begin
  if nullif(trim(p_reason), '') is null then
    raise exception 'Grant revocation unavailable';
  end if;
  select grant_record.* into grant_row
  from public.folio_grants as grant_record
  where grant_record.id = p_grant_id;
  if not found or grant_row.status <> 'active' then
    raise exception 'Grant cannot be revoked';
  end if;
  select request_record.* into request_row
  from public.verification_requests as request_record
  where request_record.id = grant_row.request_id
  for update;
  if not found or request_row.version <> p_expected_version then
    raise exception 'Folio request changed or unavailable';
  end if;
  perform public._assert_assigned_folio_advisor(request_row.id);
  select grant_record.* into grant_row
  from public.folio_grants as grant_record
  where grant_record.id = p_grant_id
  for update;
  update public.folio_grants as grant_record
  set status = 'revoked',
      revoked_at = now(),
      revoked_by = auth.uid(),
      revocation_reason = trim(p_reason)
  where grant_record.id = grant_row.id
    and grant_record.status = 'active';
  update public.verification_requests as request_record
  set status = 'revoked',
      version = request_record.version + 1
  where request_record.id = request_row.id
    and request_record.version = p_expected_version;
  if not found then
    raise exception 'Folio request changed or unavailable';
  end if;
  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (
    request_row.id, request_row.user_id, auth.uid(), 'advisor',
    'folio_grant_revoked', 'approved', 'revoked', trim(p_reason)
  );
  return 'revoked'::public.folio_grant_status;
end;
$$;

CREATE OR REPLACE FUNCTION public.submit_folio_verification(p_folio_token text, p_relationship public.folio_holder_relationship, p_idempotency_key uuid) RETURNS TABLE(request_id uuid, status public.verification_request_status, version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  request_row public.verification_requests%rowtype;
  payload jsonb;
  token_row public.folio_submission_tokens%rowtype;
  advisor_id uuid;
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'Folio verification unavailable'; end if;
  begin
    payload := extensions.pgp_sym_decrypt(decode(p_folio_token,'base64'),
      public.verification_candidate_token_secret())::jsonb;
  exception when others then raise exception 'Folio verification unavailable'; end;
  select * into token_row from public.folio_submission_tokens
  where token_id = (payload->>'token_id')::uuid for update;
  if not found or token_row.user_id <> auth.uid()
      or payload->>'user_id' <> auth.uid()::text
      or token_row.workspace_id is null or token_row.workspace_id not in (select moneybowl_authz.folio_workspaces(auth.uid(),token_row.folio_reference_id))
      or token_row.consumed_at is not null or token_row.expires_at <= now() then
    raise exception 'Folio verification unavailable';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_idempotency_key::text, 0));
  select r.* into request_row from public.verification_requests r
  where r.user_id = auth.uid() and r.method_code = 'folio'
    and r.status in ('pending_advisor_review','under_review','more_information_required')
  order by r.created_at desc limit 1;
  if found then
    if request_row.workspace_id is distinct from token_row.workspace_id or not exists(select 1 from public.verification_folio_evidence e where e.request_id=request_row.id and e.folio_reference_id=token_row.folio_reference_id and e.holder_relationship=p_relationship) then raise exception 'Folio request scope conflict'; end if;
    return query select request_row.id,request_row.status,request_row.version;
    return;
  end if;
  perform moneybowl_authz.lock_scope(token_row.workspace_id);
  advisor_id := moneybowl_authz.single_folio_reviewer(token_row.workspace_id,auth.uid());
  if advisor_id is null then raise exception 'Folio verification is unavailable'; end if;
  update public.folio_submission_tokens set consumed_at = now()
  where token_id = token_row.token_id and consumed_at is null;
  insert into public.verification_requests (workspace_id,user_id,method_code,status,submitted_at,expires_at)
  values (token_row.workspace_id,auth.uid(),'folio','pending_advisor_review',now(),now()+interval '30 days')
  returning * into request_row;
  insert into public.verification_folio_evidence (
    request_id,folio_reference_id,holder_relationship,evidence_source
  ) values (
    request_row.id,token_row.folio_reference_id,p_relationship,'INVESTOR_DECLARATION'
  );
  insert into public.verification_request_assignments (
    request_id,advisor_account_id,assigned_by_account_id
  ) values (request_row.id,advisor_id,null);
  insert into public.verification_events (
    request_id,subject_user_id,actor_user_id,actor_type,event_type,
    previous_status,new_status,reason_code
  ) values
    (request_row.id,auth.uid(),auth.uid(),'investor','folio_submitted',null,
      'pending_advisor_review',p_idempotency_key::text),
    (request_row.id,auth.uid(),null,'system','folio_review_assigned',
      'pending_advisor_review','pending_advisor_review','WORKSPACE_REVIEW_ASSIGNMENT');
  return query select request_row.id,request_row.status,request_row.version;
end;
$$;

CREATE OR REPLACE FUNCTION public.revoke_investor_link(p_link_id uuid, p_reason_code text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare link public.investor_account_links%rowtype;
begin
  if not public.is_platform_admin() or not public.platform_admin_step_up_verified() then raise exception 'Platform authorization is required'; end if;
  select * into link from public.investor_account_links where id = p_link_id for update;
  if not found or link.link_status <> 'active' then raise exception 'Link cannot be revoked'; end if;
  update public.investor_account_links set link_status = 'revoked' where id = link.id;
  update public.user_accounts set account_state = 'link_pending', onboarding_completed = true
  where user_id = link.user_id;
  insert into public.verification_events (subject_user_id, actor_user_id, actor_type,
    event_type, reason_code) values (link.user_id, auth.uid(), 'platform_admin', 'revoked', p_reason_code);
end;
$$;

CREATE OR REPLACE FUNCTION public.can_insert_order_request(p_workspace_id uuid, p_investor_profile_id uuid, p_initiated_by_profile_id uuid, p_initiated_by_role text, p_initiation_channel text, p_status public.order_status, p_reviewed_by uuid, p_reviewed_by_profile_id uuid, p_reviewed_at timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_profile_id pg_catalog.uuid;
begin
  if not public.can_select_order_request(p_workspace_id,p_investor_profile_id) then return false; end if;
  IF p_status <> 'pending_qualification'::public.order_status THEN
    RAISE EXCEPTION 'invalid_initial_order_status';
  END IF;

  IF p_reviewed_by IS NOT NULL
     OR p_reviewed_by_profile_id IS NOT NULL
     OR p_reviewed_at IS NOT NULL THEN
    RAISE EXCEPTION 'review_metadata_requires_qualification';
  END IF;

  v_profile_id := public.current_user_profile_id();

  IF v_profile_id IS NULL
     OR public.is_platform_admin()
     OR p_initiated_by_profile_id IS DISTINCT FROM v_profile_id THEN
    RETURN false;
  END IF;

  IF p_initiated_by_role = 'investor'
     AND p_initiation_channel = 'investor_portal' THEN
    RETURN p_investor_profile_id = v_profile_id
      AND EXISTS (
        SELECT 1
        FROM public.workspace_memberships AS investor_membership
        WHERE investor_membership.workspace_id = p_workspace_id
          AND investor_membership.profile_id = v_profile_id
          AND investor_membership.role = 'investor'
          AND investor_membership.status = 'active'
      );
  END IF;

  IF p_initiated_by_role = 'advisor'
     AND p_initiation_channel = 'advisor_portal' THEN
    RETURN public.is_order_mfd_profile(p_workspace_id, v_profile_id)
      AND EXISTS (
        SELECT 1
        FROM public.workspace_memberships AS beneficiary_membership
        WHERE beneficiary_membership.workspace_id = p_workspace_id
          AND beneficiary_membership.profile_id = p_investor_profile_id
          AND beneficiary_membership.role = 'investor'
          AND beneficiary_membership.status = 'active'
      );
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid, p_reason text DEFAULT NULL::text) RETURNS public.order_requests
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_workspace_id pg_catalog.uuid;
  v_investor_profile_id pg_catalog.uuid;
  v_current_status public.order_status;
  v_current_profile_id pg_catalog.uuid;
  v_cancellation_reason pg_catalog.text;
  v_order public.order_requests;
BEGIN
  SELECT
    o.workspace_id,
    o.investor_profile_id,
    o.status
  INTO
    v_workspace_id,
    v_investor_profile_id,
    v_current_status
  FROM public.order_requests AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_current_profile_id := public.current_user_profile_id();
  IF v_current_profile_id IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  IF public.is_platform_admin() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  perform moneybowl_authz.lock_scope(v_workspace_id);
  if not public.can_select_order_request(v_workspace_id,v_investor_profile_id) then raise exception 'not_authorized'; end if;

  IF v_current_status = 'cancelled' THEN
    RAISE EXCEPTION 'already_cancelled';
  END IF;

  IF v_current_status NOT IN ('pending_qualification', 'pending_review') THEN
    RAISE EXCEPTION 'invalid_cancellation_state';
  END IF;

  v_cancellation_reason := COALESCE(p_reason, 'Cancelled by user');

  UPDATE public.order_requests AS o
  SET status = 'cancelled',
      cancellation_reason = v_cancellation_reason,
      cancelled_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  WHERE o.id = p_order_id
  -- Return the actual table composite, whose physical column order differs
  -- from the historical hand-maintained projection.
  RETURNING o.* INTO v_order;

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    reason,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_workspace_id,
    v_current_profile_id,
    v_current_profile_id,
    CASE
      WHEN v_investor_profile_id = v_current_profile_id THEN 'investor'
      ELSE 'advisor'
    END,
    'order.cancelled',
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    v_cancellation_reason,
    v_current_status::pg_catalog.text,
    'cancelled',
    pg_catalog.jsonb_build_object(
      'reason', v_cancellation_reason,
      'previous_status', v_current_status,
      'new_status', 'cancelled',
      'investor_profile_id', v_investor_profile_id
    )
  );

  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.qualify_order(p_order_id uuid, p_decision public.order_status, p_rejection_reason text DEFAULT NULL::text) RETURNS public.order_requests
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_workspace_id pg_catalog.uuid;
  v_investor_profile_id pg_catalog.uuid;
  v_initiated_by_profile_id pg_catalog.uuid;
  v_current_status public.order_status;
  v_current_profile_id pg_catalog.uuid;
  v_order public.order_requests;
BEGIN
  SELECT
    o.workspace_id,
    o.investor_profile_id,
    o.initiated_by_profile_id,
    o.status
  INTO
    v_workspace_id,
    v_investor_profile_id,
    v_initiated_by_profile_id,
    v_current_status
  FROM public.order_requests AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_current_status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_qualification_state';
  END IF;

  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'invalid_qualification_decision';
  END IF;

  v_current_profile_id := public.current_user_profile_id();
  IF v_current_profile_id IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  perform moneybowl_authz.lock_scope(v_workspace_id);
  if not public.can_select_order_request(v_workspace_id,v_investor_profile_id) then raise exception 'not_authorized'; end if;
  IF public.is_platform_admin() OR NOT public.is_order_mfd_profile(v_workspace_id, v_current_profile_id) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  UPDATE public.order_requests AS o
  SET status = p_decision,
      reviewed_by = v_current_profile_id,
      reviewed_by_profile_id = v_current_profile_id,
      reviewed_at = pg_catalog.now(),
      rejection_reason = p_rejection_reason,
      updated_at = pg_catalog.now()
  WHERE o.id = p_order_id
  -- Match the physical table composite rather than a historical column list.
  RETURNING o.* INTO v_order;

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    event_type,
    target_type,
    entity_type,
    target_id,
    entity_id,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_workspace_id,
    v_current_profile_id,
    v_current_profile_id,
    'advisor',
    'order.qualified',
    'order.manual_qualification',
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    v_current_status::pg_catalog.text,
    p_decision::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'decision', p_decision,
      'rejection_reason', p_rejection_reason,
      'investor_profile_id', v_investor_profile_id,
      'initiated_by_profile_id', v_initiated_by_profile_id,
      'reviewed_by_profile_id', v_current_profile_id
    )
  );

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    event_type,
    target_type,
    entity_type,
    target_id,
    entity_id,
    reason,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_workspace_id,
    v_current_profile_id,
    v_current_profile_id,
    'advisor',
    CASE WHEN p_decision = 'approved' THEN 'order.approved' ELSE 'order.rejected' END,
    CASE WHEN p_decision = 'approved' THEN 'order.approved' ELSE 'order.rejected' END,
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    p_rejection_reason,
    v_current_status::pg_catalog.text,
    p_decision::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'decision', p_decision,
      'reason', p_rejection_reason,
      'investor_profile_id', v_investor_profile_id,
      'initiated_by_profile_id', v_initiated_by_profile_id,
      'reviewed_by_profile_id', v_current_profile_id
    )
  );

  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_order_request_canonical_contract() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_caller_user_id pg_catalog.uuid;
  v_caller_profile_id pg_catalog.uuid;
  v_is_service_role pg_catalog.bool;
  v_is_api_insert pg_catalog.bool;
  v_request_claims pg_catalog.text;
  v_request_role pg_catalog.text;
  v_validate_submission_intent pg_catalog.bool;
  v_source_fund_id pg_catalog.uuid;
  v_source_portfolio_id pg_catalog.uuid;
  v_source_portfolio_count pg_catalog.int8;
  v_available_units pg_catalog.numeric;
BEGIN
  v_request_claims := NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '');
  v_request_role := NULLIF(pg_catalog.current_setting('request.jwt.claim.role', true), '');

  IF v_request_role IS NULL AND v_request_claims IS NOT NULL THEN
    v_request_role := NULLIF((v_request_claims::pg_catalog.jsonb ->> 'role'), '');
  END IF;

  v_caller_user_id := auth.uid();
  v_is_service_role := COALESCE(auth.role(), v_request_role, '') = 'service_role';
  v_is_api_insert := TG_OP = 'INSERT'
    AND (
      v_caller_user_id IS NOT NULL
      OR v_request_role IN ('anon', 'authenticated', 'service_role')
      OR v_is_service_role
    );
  v_validate_submission_intent := TG_OP = 'INSERT'
    OR (
      TG_OP = 'UPDATE'
      AND (
        NEW.type IS DISTINCT FROM OLD.type
        OR NEW.scheme_code IS DISTINCT FROM OLD.scheme_code
        OR NEW.folio_reference_id IS DISTINCT FROM OLD.folio_reference_id
        OR NEW.destination_scheme_code IS DISTINCT FROM OLD.destination_scheme_code
      )
    );

  IF v_is_api_insert THEN
    IF NEW.status <> 'pending_qualification'::public.order_status THEN
      RAISE EXCEPTION 'invalid_initial_order_status';
    END IF;

    IF NEW.reviewed_by IS NOT NULL
       OR NEW.reviewed_by_profile_id IS NOT NULL
       OR NEW.reviewed_at IS NOT NULL THEN
      RAISE EXCEPTION 'review_metadata_requires_qualification';
    END IF;
  END IF;

  IF NEW.reviewed_by IS NOT NULL
     AND NEW.reviewed_by_profile_id IS NOT NULL
     AND NEW.reviewed_by <> NEW.reviewed_by_profile_id THEN
    IF TG_OP = 'INSERT' THEN
    if auth.uid() is not null then
      perform moneybowl_authz.lock_scope(NEW.workspace_id);
      if not public.can_select_order_request(NEW.workspace_id,NEW.investor_profile_id) then raise exception 'not_authorized'; end if;
    end if;
      RAISE EXCEPTION 'reviewer_profile_mismatch';
    ELSIF OLD.reviewed_by IS NULL
          AND OLD.reviewed_by_profile_id IS NULL
          AND OLD.reviewed_at IS NULL THEN
      RAISE EXCEPTION 'reviewer_profile_mismatch';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    if auth.uid() is not null then
      perform moneybowl_authz.lock_scope(NEW.workspace_id);
      if not public.can_select_order_request(NEW.workspace_id,NEW.investor_profile_id) then raise exception 'not_authorized'; end if;
    end if;
    IF NEW.status = 'draft'::public.order_status THEN
      RETURN NEW;
    END IF;

    IF v_caller_user_id IS NOT NULL THEN
      IF NEW.reviewed_by IS NOT NULL
         OR NEW.reviewed_by_profile_id IS NOT NULL
         OR NEW.reviewed_at IS NOT NULL THEN
        RAISE EXCEPTION 'review_metadata_requires_qualification';
      END IF;

      v_caller_profile_id := public.current_user_profile_id();

      IF v_caller_profile_id IS NULL THEN
        RAISE EXCEPTION 'profile_resolution_failed';
      END IF;

      IF NEW.initiated_by_profile_id IS NULL THEN
        NEW.initiated_by_profile_id := v_caller_profile_id;
      ELSIF NEW.initiated_by_profile_id <> v_caller_profile_id THEN
        RAISE EXCEPTION 'initiator_profile_mismatch';
      END IF;

      IF public.is_platform_admin() THEN
        RAISE EXCEPTION 'not_authorized';
      END IF;

      IF v_caller_profile_id = NEW.investor_profile_id THEN
        IF NEW.initiated_by_role IS NULL THEN
          NEW.initiated_by_role := 'investor';
        ELSIF NEW.initiated_by_role <> 'investor' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;

        IF NEW.initiation_channel IS NULL THEN
          NEW.initiation_channel := 'investor_portal';
        ELSIF NEW.initiation_channel <> 'investor_portal' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;
      ELSIF public.is_order_mfd_profile(NEW.workspace_id, v_caller_profile_id) THEN
        IF NEW.initiated_by_role IS NULL THEN
          NEW.initiated_by_role := 'advisor';
        ELSIF NEW.initiated_by_role <> 'advisor' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;

        IF NEW.initiation_channel IS NULL THEN
          NEW.initiation_channel := 'advisor_portal';
        ELSIF NEW.initiation_channel <> 'advisor_portal' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;
      ELSE
        RAISE EXCEPTION 'order_initiator_not_authorized';
      END IF;
    ELSIF v_is_service_role THEN
      IF NEW.initiated_by_profile_id IS NULL
         OR NEW.initiated_by_role IS NULL
         OR NEW.initiation_channel IS NULL THEN
        RAISE EXCEPTION 'order_request_canonical_metadata_missing';
      END IF;
    ELSIF COALESCE(pg_catalog.current_setting('role', true), '') NOT IN ('anon', 'authenticated', 'service_role') THEN
      IF NEW.initiated_by_profile_id IS NULL
         OR NEW.initiated_by_role IS NULL
         OR NEW.initiation_channel IS NULL THEN
        RAISE EXCEPTION 'order_request_canonical_metadata_missing';
      END IF;

      IF NEW.reviewed_by_profile_id IS NULL AND NEW.reviewed_by IS NOT NULL THEN
        NEW.reviewed_by_profile_id := NEW.reviewed_by;
      ELSIF NEW.reviewed_by IS NULL AND NEW.reviewed_by_profile_id IS NOT NULL THEN
        NEW.reviewed_by := NEW.reviewed_by_profile_id;
      END IF;

      IF NEW.reviewed_by_profile_id IS NOT NULL AND NEW.reviewed_at IS NULL THEN
        RAISE EXCEPTION 'reviewed_at_required';
      ELSIF NEW.reviewed_by_profile_id IS NULL AND NEW.reviewed_at IS NOT NULL THEN
        RAISE EXCEPTION 'reviewer_profile_required';
      END IF;
    ELSE
      RAISE EXCEPTION 'profile_resolution_failed';
    END IF;
  ELSE
    IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
       OR NEW.investor_profile_id IS DISTINCT FROM OLD.investor_profile_id
       OR NEW.initiated_by_profile_id IS DISTINCT FROM OLD.initiated_by_profile_id
       OR NEW.initiated_by_role IS DISTINCT FROM OLD.initiated_by_role
       OR NEW.initiation_channel IS DISTINCT FROM OLD.initiation_channel THEN
      RAISE EXCEPTION 'order_initiation_metadata_immutable';
    END IF;

    IF OLD.reviewed_by IS NOT NULL
       OR OLD.reviewed_by_profile_id IS NOT NULL
       OR OLD.reviewed_at IS NOT NULL THEN
      IF NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
         OR NEW.reviewed_by_profile_id IS DISTINCT FROM OLD.reviewed_by_profile_id
         OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at THEN
        RAISE EXCEPTION 'review_metadata_immutable';
      END IF;
    ELSIF NEW.reviewed_by IS NOT NULL
          OR NEW.reviewed_by_profile_id IS NOT NULL
          OR NEW.reviewed_at IS NOT NULL THEN
      IF NEW.reviewed_by IS NULL
         OR NEW.reviewed_by_profile_id IS NULL
         OR NEW.reviewed_at IS NULL THEN
        RAISE EXCEPTION 'review_metadata_incomplete';
      END IF;

      IF OLD.status <> 'pending_review'::public.order_status
         OR NEW.status NOT IN ('approved'::public.order_status, 'rejected'::public.order_status) THEN
        RAISE EXCEPTION 'review_metadata_requires_qualification';
      END IF;

      IF v_caller_user_id IS NOT NULL THEN
        v_caller_profile_id := public.current_user_profile_id();

        IF v_caller_profile_id IS NULL THEN
          RAISE EXCEPTION 'profile_resolution_failed';
        END IF;

        IF NEW.reviewed_by_profile_id <> v_caller_profile_id THEN
          RAISE EXCEPTION 'reviewer_profile_mismatch';
        END IF;

        IF public.is_platform_admin() OR NOT public.is_order_mfd_profile(NEW.workspace_id, v_caller_profile_id) THEN
          RAISE EXCEPTION 'not_authorized';
        END IF;
      ELSIF NOT v_is_service_role THEN
        RAISE EXCEPTION 'profile_resolution_failed';
      END IF;
    ELSIF OLD.status = 'pending_review'::public.order_status
          AND NEW.status IN ('approved'::public.order_status, 'rejected'::public.order_status) THEN
      RAISE EXCEPTION 'review_metadata_requires_qualification';
    END IF;
  END IF;

  IF NEW.workspace_id IS NULL
     OR NEW.investor_profile_id IS NULL
     OR NEW.initiated_by_profile_id IS NULL
     OR NEW.initiated_by_role IS NULL
     OR NEW.initiation_channel IS NULL THEN
    RAISE EXCEPTION 'order_request_canonical_metadata_missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS wm
    WHERE wm.workspace_id = NEW.workspace_id
      AND wm.profile_id = NEW.investor_profile_id
      AND wm.role = 'investor'
      AND wm.status = 'active'
  ) THEN
    RAISE EXCEPTION 'investor_workspace_relationship_required';
  END IF;

  IF NEW.initiated_by_role = 'investor' THEN
    IF NEW.initiation_channel <> 'investor_portal' THEN
      RAISE EXCEPTION 'invalid_order_initiation_metadata';
    END IF;

    IF NEW.initiated_by_profile_id <> NEW.investor_profile_id THEN
      RAISE EXCEPTION 'investor_initiator_mismatch';
    END IF;
  ELSIF NEW.initiated_by_role = 'advisor' THEN
    IF NEW.initiation_channel <> 'advisor_portal' THEN
      RAISE EXCEPTION 'invalid_order_initiation_metadata';
    END IF;

    IF TG_OP='INSERT' AND NOT public.is_order_mfd_profile(NEW.workspace_id, NEW.initiated_by_profile_id) THEN
      RAISE EXCEPTION 'advisor_workspace_relationship_required';
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_order_initiation_metadata';
  END IF;

  IF NEW.reviewed_by_profile_id IS NOT NULL THEN
    IF NEW.reviewed_at IS NULL THEN
      RAISE EXCEPTION 'reviewed_at_required';
    END IF;
    IF (TG_OP='INSERT' OR NEW.reviewed_by_profile_id IS DISTINCT FROM OLD.reviewed_by_profile_id) AND NOT public.is_order_mfd_profile(NEW.workspace_id, NEW.reviewed_by_profile_id) THEN
      RAISE EXCEPTION 'reviewer_workspace_relationship_required';
    END IF;
  ELSIF NEW.reviewed_at IS NOT NULL THEN
    RAISE EXCEPTION 'reviewer_profile_required';
  END IF;

  IF v_validate_submission_intent THEN
    IF NEW.type IN ('sell'::public.order_type, 'switch'::public.order_type) THEN
      IF NEW.folio_reference_id IS NULL THEN
        RAISE EXCEPTION 'folio_reference_required_for_sell_switch';
      END IF;

      SELECT
        pg_catalog.count(DISTINCT p.id),
        (pg_catalog.array_agg(DISTINCT p.id ORDER BY p.id))[1]
      INTO v_source_portfolio_count, v_source_portfolio_id
      FROM public.portfolio_folio_references AS pfr
      JOIN public.portfolios AS p
        ON p.id = pfr.portfolio_id
      WHERE pfr.folio_reference_id = NEW.folio_reference_id
        AND p.client_id = NEW.investor_profile_id
        AND p.workspace_id = NEW.workspace_id;

      IF v_source_portfolio_count = 0 THEN
        RAISE EXCEPTION 'folio_not_owned_by_investor_in_workspace';
      ELSIF v_source_portfolio_count > 1 THEN
        RAISE EXCEPTION 'folio_portfolio_workspace_ambiguous';
      END IF;

      SELECT mf.id
      INTO v_source_fund_id
      FROM public.mutual_funds AS mf
      WHERE mf.scheme_code = NEW.scheme_code
      LIMIT 1;

      IF v_source_fund_id IS NULL THEN
        RAISE EXCEPTION 'scheme_not_held_in_selected_folio';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM public.transactions AS t
        WHERE t.portfolio_id = v_source_portfolio_id
          AND t.folio_reference_id = NEW.folio_reference_id
          AND t.mutual_fund_id = v_source_fund_id
          AND t.transaction_type = 'SWITCH'
          AND t.source_folio_reference_id IS NOT NULL
          AND (
            t.transaction_direction IS NULL
            OR t.transaction_direction NOT IN ('INFLOW', 'OUTFLOW')
          )
      ) THEN
        RAISE EXCEPTION 'unsupported_transaction_direction';
      END IF;

      SELECT COALESCE(SUM(
        CASE
          WHEN t.transaction_type = 'BUY' THEN t.units
          WHEN t.transaction_type = 'SELL' THEN -t.units
          WHEN t.transaction_type = 'SWITCH' AND t.transaction_direction = 'INFLOW' THEN t.units
          WHEN t.transaction_type = 'SWITCH' AND t.transaction_direction = 'OUTFLOW' THEN -t.units
          ELSE 0
        END
      ), 0)
      INTO v_available_units
      FROM public.transactions AS t
      WHERE t.portfolio_id = v_source_portfolio_id
        AND t.folio_reference_id = NEW.folio_reference_id
        AND t.mutual_fund_id = v_source_fund_id;

      IF v_available_units <= 0 THEN
        RAISE EXCEPTION 'scheme_not_held_in_selected_folio';
      END IF;
    END IF;

    IF NEW.destination_scheme_code IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1
        FROM public.mutual_funds AS mf
        WHERE mf.scheme_code = NEW.destination_scheme_code
      ) THEN
        RAISE EXCEPTION 'destination_scheme_not_found';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_order_folios(p_investor_profile_id uuid, p_workspace_id uuid) RETURNS TABLE(folio_reference_id uuid, portfolio_id uuid, registrar text, masked_folio text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_caller_profile_id pg_catalog.uuid;
begin
  if not public.can_select_order_request(p_workspace_id,p_investor_profile_id) then return; end if;
  v_caller_profile_id := public.current_user_profile_id();

  IF auth.uid() IS NULL
     OR v_caller_profile_id IS NULL
     OR public.is_platform_admin() THEN
    RETURN;
  END IF;

  IF v_caller_profile_id <> p_investor_profile_id
     AND NOT public.is_order_mfd_profile(p_workspace_id, v_caller_profile_id) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT
    folio.id AS folio_reference_id,
    portfolio.id AS portfolio_id,
    folio.registrar,
    folio.source_folio_masked AS masked_folio
  FROM public.portfolios AS portfolio
  JOIN public.workspace_memberships AS investor_membership
    ON investor_membership.workspace_id = portfolio.workspace_id
   AND investor_membership.profile_id = portfolio.client_id
   AND investor_membership.role = 'investor'
   AND investor_membership.status = 'active'
   AND investor_membership.ended_at IS NULL
  JOIN public.profiles AS investor_profile
    ON investor_profile.id = portfolio.client_id
   AND investor_profile.account_status = 'active'
  JOIN public.portfolio_folio_references AS portfolio_folio
    ON portfolio_folio.portfolio_id = portfolio.id
  JOIN public.folio_grants AS folio_grant
    ON folio_grant.profile_id = portfolio.client_id
   AND folio_grant.folio_reference_id = portfolio_folio.folio_reference_id
   AND folio_grant.workspace_id = portfolio.workspace_id
   AND folio_grant.status = 'active'
  JOIN public.investor_account_links AS investor_link
    ON investor_link.user_id = folio_grant.user_id
   AND investor_link.profile_id = folio_grant.profile_id
   AND investor_link.link_status = 'active'
  JOIN public.user_accounts AS investor_account
    ON investor_account.user_id = investor_link.user_id
   AND investor_account.account_state = 'linked_investor'
  JOIN public.folio_references AS folio
    ON folio.id = portfolio_folio.folio_reference_id
  WHERE portfolio.client_id = p_investor_profile_id
    AND portfolio.workspace_id = p_workspace_id
    AND (
      v_caller_profile_id <> p_investor_profile_id
      OR investor_link.user_id = auth.uid()
    )
  ORDER BY folio.registrar, folio.source_folio_masked, folio.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_order_folio_portfolio(p_investor_profile_id uuid, p_workspace_id uuid, p_portfolio_id uuid, p_folio_reference_id uuid) RETURNS TABLE(portfolio_id uuid)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_caller_profile_id pg_catalog.uuid;
begin
  if not public.can_select_order_request(p_workspace_id,p_investor_profile_id) then return; end if;
  v_caller_profile_id := public.current_user_profile_id();

  IF auth.uid() IS NULL
     OR v_caller_profile_id IS NULL
     OR public.is_platform_admin() THEN
    RETURN;
  END IF;

  IF v_caller_profile_id <> p_investor_profile_id
     AND NOT public.is_order_mfd_profile(p_workspace_id, v_caller_profile_id) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT portfolio.id AS portfolio_id
  FROM public.portfolios AS portfolio
  JOIN public.workspace_memberships AS investor_membership
    ON investor_membership.workspace_id = portfolio.workspace_id
   AND investor_membership.profile_id = portfolio.client_id
   AND investor_membership.role = 'investor'
   AND investor_membership.status = 'active'
   AND investor_membership.ended_at IS NULL
  JOIN public.profiles AS investor_profile
    ON investor_profile.id = portfolio.client_id
   AND investor_profile.account_status = 'active'
  JOIN public.portfolio_folio_references AS portfolio_folio
    ON portfolio_folio.portfolio_id = portfolio.id
   AND portfolio_folio.folio_reference_id = p_folio_reference_id
  JOIN public.folio_grants AS folio_grant
    ON folio_grant.profile_id = portfolio.client_id
   AND folio_grant.folio_reference_id = portfolio_folio.folio_reference_id
   AND folio_grant.workspace_id = portfolio.workspace_id
   AND folio_grant.status = 'active'
  JOIN public.investor_account_links AS investor_link
    ON investor_link.user_id = folio_grant.user_id
   AND investor_link.profile_id = folio_grant.profile_id
   AND investor_link.link_status = 'active'
  JOIN public.user_accounts AS investor_account
    ON investor_account.user_id = investor_link.user_id
   AND investor_account.account_state = 'linked_investor'
  WHERE portfolio.client_id = p_investor_profile_id
    AND portfolio.workspace_id = p_workspace_id
    AND portfolio.id = p_portfolio_id
    AND (
      v_caller_profile_id <> p_investor_profile_id
      OR investor_link.user_id = auth.uid()
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.begin_mailbox_oauth_authorization(p_workspace_id uuid, p_mailbox_connection_id uuid, p_state_hash text, p_redirect_uri text, p_expires_at timestamp with time zone) RETURNS TABLE(authorization_id uuid, flow_kind text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
DECLARE
  v_actor_profile_id pg_catalog.uuid;
  v_authorization_id pg_catalog.uuid;
  v_flow_kind pg_catalog.text;
begin
  perform moneybowl_authz.lock_scope(p_workspace_id);
  perform public.authorize_cams_kfintech_workspace(p_workspace_id);
  v_actor_profile_id := public.current_user_profile_id();
  IF auth.uid() IS NULL OR v_actor_profile_id IS NULL THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  IF p_state_hash IS NULL OR p_state_hash !~ '^[0-9a-f]{64}$'
     OR p_redirect_uri IS NULL OR pg_catalog.length(p_redirect_uri) NOT BETWEEN 12 AND 2048
     OR p_redirect_uri ~ '[[:space:]]'
     OR p_expires_at <= pg_catalog.now()
     OR p_expires_at > pg_catalog.now() + pg_catalog.interval '10 minutes' THEN
    RAISE EXCEPTION 'oauth_request_invalid' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.workspaces AS workspace
    JOIN public.workspace_memberships AS membership
      ON membership.workspace_id = workspace.id
    WHERE workspace.id = p_workspace_id
      AND workspace.workspace_status = 'active'
      AND membership.profile_id = v_actor_profile_id
      AND membership.role IN ('advisor', 'admin')
      AND membership.status = 'active'
      AND membership.ended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.mailbox_connections AS mailbox
    WHERE mailbox.id = p_mailbox_connection_id
      AND mailbox.workspace_id = p_workspace_id
      AND pg_catalog.lower(mailbox.oauth_provider) = 'gmail'
      AND mailbox.status IN ('active', 'reauthorization_required')
  ) THEN
    RAISE EXCEPTION 'mailbox_connection_not_found' USING ERRCODE = 'P0001';
  END IF;

  v_flow_kind := CASE WHEN EXISTS (
    SELECT 1 FROM public.mailbox_oauth_credentials AS credentials
    WHERE credentials.workspace_id = p_workspace_id
      AND credentials.mailbox_connection_id = p_mailbox_connection_id
  ) THEN 'reauthorization' ELSE 'first_time' END;

  INSERT INTO public.mailbox_oauth_authorization_states (
    state_hash, workspace_id, mailbox_connection_id, actor_profile_id,
    redirect_uri, flow_kind, expires_at
  ) VALUES (
    p_state_hash, p_workspace_id, p_mailbox_connection_id, v_actor_profile_id,
    p_redirect_uri, v_flow_kind, p_expires_at
  ) RETURNING id INTO v_authorization_id;

  INSERT INTO public.workspace_audit_logs (
    workspace_id, actor_id, action, target_type, target_id, payload,
    actor_profile_id, actor_type, entity_type, entity_id, event_type,
    outcome, occurred_at
  ) VALUES (
    p_workspace_id, v_actor_profile_id, 'mailbox.oauth.authorization_started',
    'mailbox_connection', p_mailbox_connection_id,
    pg_catalog.jsonb_build_object('flow_kind', v_flow_kind),
    v_actor_profile_id, 'workspace_user', 'mailbox_connection',
    p_mailbox_connection_id, 'mailbox.oauth.authorization_started',
    'attempted', pg_catalog.now()
  );

  RETURN QUERY SELECT v_authorization_id, v_flow_kind;
END;
$_$;

CREATE OR REPLACE FUNCTION public.revoke_mailbox_oauth_credential(p_workspace_id uuid, p_mailbox_connection_id uuid, p_expected_credential_nonce text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_actor_profile_id pg_catalog.uuid;
begin
  perform moneybowl_authz.lock_scope(p_workspace_id);
  perform public.authorize_cams_kfintech_workspace(p_workspace_id);
  v_actor_profile_id := public.current_user_profile_id();
  IF auth.uid() IS NULL OR v_actor_profile_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.workspace_memberships AS membership
    WHERE membership.workspace_id = p_workspace_id
      AND membership.profile_id = v_actor_profile_id
      AND membership.role IN ('advisor', 'admin')
      AND membership.status = 'active'
      AND membership.ended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.mailbox_oauth_credentials AS credentials
  WHERE credentials.workspace_id = p_workspace_id
    AND credentials.mailbox_connection_id = p_mailbox_connection_id
    AND credentials.credential_nonce = p_expected_credential_nonce;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.mailbox_connections AS mailbox
  SET status = 'reauthorization_required', updated_at = pg_catalog.now()
  WHERE mailbox.id = p_mailbox_connection_id
    AND mailbox.workspace_id = p_workspace_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mailbox_connection_not_found' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.workspace_audit_logs (
    workspace_id, actor_id, action, target_type, target_id,
    actor_profile_id, actor_type, entity_type, entity_id, event_type,
    outcome, occurred_at
  ) VALUES (
    p_workspace_id, v_actor_profile_id, 'mailbox.oauth.revoked',
    'mailbox_connection', p_mailbox_connection_id,
    v_actor_profile_id, 'workspace_user', 'mailbox_connection',
    p_mailbox_connection_id, 'mailbox.oauth.revoked', 'succeeded',
    pg_catalog.now()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_nse_read_v1(p_target_ref uuid, p_request_id uuid, p_command jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE s jsonb; r nse_app.submission_receipts; c jsonb; op public.integration_operations; selection jsonb; new_id uuid; reason text;
BEGIN
 BEGIN s:=nse_app.scope(p_target_ref); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('NOT_AUTHORIZED'); END;
 IF p_request_id IS NULL OR p_command IS NULL OR pg_catalog.pg_column_size(p_command)>8192 THEN RETURN nse_app.failure('INVALID_COMMAND'); END IF;
 -- Actor lock also serializes request UUIDs reused across different workspaces.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nse-app-actor:'||(s->>'actor'),0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nse-app-workspace:'||(s->>'workspace'),0));
 -- Recheck after waiting for locks; hold the authority rows until acceptance.
 PERFORM 1 FROM public.workspaces WHERE id=(s->>'workspace')::uuid FOR SHARE;
 PERFORM 1 FROM public.profiles WHERE id IN ((s->>'actor')::uuid,(s->>'investor')::uuid) ORDER BY id FOR SHARE;
 PERFORM 1 FROM public.user_accounts WHERE user_id=auth.uid() FOR SHARE;
 PERFORM 1 FROM auth.users WHERE id=auth.uid() FOR SHARE;
 PERFORM 1 FROM public.workspace_memberships WHERE workspace_id=(s->>'workspace')::uuid
   AND profile_id IN ((s->>'actor')::uuid,(s->>'investor')::uuid) ORDER BY id FOR SHARE;
 PERFORM 1 FROM public.advisor_investor_assignments WHERE advisor_id=(s->>'actor')::uuid
   AND investor_id=(s->>'investor')::uuid AND workspace_id=(s->>'workspace')::uuid ORDER BY id FOR SHARE;
 BEGIN s:=nse_app.scope(p_target_ref); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('NOT_AUTHORIZED'); END;
 SELECT * INTO r FROM nse_app.submission_receipts WHERE actor_profile_id=(s->>'actor')::uuid AND request_id=p_request_id;
 IF r.operation_id IS NOT NULL THEN
   IF r.target_ref<>p_target_ref OR r.command IS DISTINCT FROM p_command THEN RETURN nse_app.failure('REQUEST_CONFLICT'); END IF;
   SELECT * INTO op FROM public.integration_operations WHERE id=r.operation_id;
   RETURN nse_app.reply(pg_catalog.jsonb_build_object('acceptance','REPLAYED','request_id',p_request_id,'operation_id',op.id,'state',op.state,'poll_after_ms',2000));
 END IF;
 BEGIN c:=nse_app.compile(p_command); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('INVALID_COMMAND'); END;
 PERFORM 1 FROM nse_app.dev_access WHERE workspace_id=(s->>'workspace')::uuid AND enabled FOR SHARE;
 IF NOT FOUND THEN RETURN nse_app.failure('FEATURE_DISABLED'); END IF;
 reason:=nse_app.prerequisite(s,c->>'family');
 IF c->>'api'='STP_INST_DUE_REPORT' THEN RETURN nse_app.failure('BLOCKED_PREREQUISITE'); END IF;
 IF c->>'api'='SIP_AMC_PAUSE_REPORT' AND (SELECT pg_catalog.length(external_account_id)>15 FROM public.integration_accounts WHERE id=(s->>'account')::uuid) THEN RETURN nse_app.failure('BLOCKED_PREREQUISITE'); END IF;
 IF reason IS NOT NULL THEN RETURN nse_app.failure('BLOCKED_PREREQUISITE'); END IF;
 -- Hold account while existing preparation performs its authoritative checks.
 PERFORM 1 FROM public.integration_accounts WHERE id=(s->>'account')::uuid FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.integration_operations WHERE integration_account_id=(s->>'account')::uuid AND api_key=c->>'api'
   AND (state IN ('PREPARED','QUEUED','SUBMITTING','RECONCILIATION_REQUIRED') OR (state='SUBMISSION_FAILED' AND retry_allowed))) THEN RETURN nse_app.failure('OPERATION_IN_PROGRESS'); END IF;
 IF (SELECT count(*) FROM nse_app.submission_receipts WHERE actor_profile_id=(s->>'actor')::uuid AND accepted_at>pg_catalog.now()-interval '1 minute')>=10
   OR (SELECT count(*) FROM nse_app.submission_receipts WHERE workspace_id=(s->>'workspace')::uuid AND accepted_at>pg_catalog.now()-interval '1 minute')>=60
   OR EXISTS(SELECT 1 FROM nse_app.submission_receipts WHERE integration_account_id=(s->>'account')::uuid AND command->>'kind'=p_command->>'kind'
     AND accepted_at>pg_catalog.now()-interval '10 seconds') THEN RETURN nse_app.failure('RATE_LIMITED'); END IF;
 new_id:=pg_catalog.gen_random_uuid();
 IF c->>'family'='SETTLEMENT_REDEMPTION' THEN
   BEGIN selection:=nse_app.settlement_selection(s,c->>'api',p_command->'options'); EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('BLOCKED_PREREQUISITE'); END;
 END IF;
 CASE c->>'family'
 WHEN 'ORDER_STATUS' THEN SELECT * INTO op FROM public.prepare_nse_order_status((s->>'workspace')::uuid,(s->>'account')::uuid,c->'filters',new_id);
 WHEN 'PROV_ORDERS' THEN SELECT * INTO op FROM public.prepare_nse_prov_orders((s->>'workspace')::uuid,(s->>'account')::uuid,c->'filters',new_id);
 WHEN 'CLIENT_READINESS' THEN SELECT * INTO op FROM public.prepare_nse_client_readiness((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id);
 WHEN 'ORDER_FUNDING' THEN SELECT * INTO op FROM public.prepare_nse_order_funding((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id);
 WHEN 'STP_SWP_REPORTS' THEN SELECT * INTO op FROM public.prepare_nse_stp_swp_reports((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id);
 WHEN 'SIP_XSIP_REPORTS' THEN SELECT * INTO op FROM public.prepare_nse_sip_xsip_reports((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id);
 WHEN 'SETTLEMENT_REDEMPTION' THEN SELECT * INTO op FROM public.prepare_nse_settlement_redemption((s->>'workspace')::uuid,(s->>'account')::uuid,c->>'api',c->'filters',new_id,selection);
 ELSE RAISE EXCEPTION 'INVALID_COMMAND'; END CASE;
 IF op.id IS DISTINCT FROM new_id OR op.safety_class<>'READ_ONLY' OR op.state<>'QUEUED' THEN RAISE EXCEPTION 'unexpected_preparation_result'; END IF;
 INSERT INTO nse_app.submission_receipts VALUES((s->>'actor')::uuid,p_request_id,p_target_ref,(s->>'workspace')::uuid,(s->>'account')::uuid,p_command,op.id,pg_catalog.now());
 INSERT INTO public.workspace_audit_logs(workspace_id,actor_id,actor_profile_id,actor_type,action,event_type,target_type,entity_type,target_id,entity_id,correlation_id,reason,new_state,payload)
 VALUES((s->>'workspace')::uuid,(s->>'actor')::uuid,(s->>'actor')::uuid,(SELECT role FROM public.profiles WHERE id=(s->>'actor')::uuid),'nse.read_accepted','nse.read_accepted',
   'integration_operation','integration_operation',op.id,op.id,p_request_id,'Authorized account read','QUEUED',pg_catalog.jsonb_build_object('kind',p_command->>'kind','channel','nse_console'));
 RETURN nse_app.reply(pg_catalog.jsonb_build_object('acceptance','ACCEPTED','request_id',p_request_id,'operation_id',op.id,'state',op.state,'poll_after_ms',2000));
 -- This exception block rolls back preparation, receipt AND audit together.
EXCEPTION WHEN OTHERS THEN RETURN nse_app.failure('TEMPORARILY_UNAVAILABLE');
END $$;

CREATE OR REPLACE FUNCTION public.request_nse_bank_mandate_review(p_workspace_id uuid, p_integration_account_id uuid, p_bank_account_id uuid, p_action text, p_request_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE a public.integration_accounts; b public.investor_bank_accounts; actor uuid;
 old_intent nse_bank_mandate.intents; snapshot jsonb; reason text;
begin
  perform moneybowl_authz.lock_scope(p_workspace_id);
  if not exists(select 1 from public.integration_accounts scoped_account where scoped_account.id=p_integration_account_id and scoped_account.workspace_id=p_workspace_id and public.can_select_order_request(scoped_account.workspace_id,scoped_account.investor_profile_id)) then raise exception 'not_authorized'; end if;
 actor:=public.current_user_profile_id();
 IF actor IS NULL THEN RAISE EXCEPTION 'bank_mandate_owner_required'; END IF;
 IF p_request_id IS NULL OR p_action IS NULL OR p_action NOT IN ('MANDATE','BANK_ADD','BANK_DEL') THEN RAISE EXCEPTION 'bank_mandate_intent_invalid'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text,7));
 SELECT * INTO a FROM public.integration_accounts WHERE id=p_integration_account_id AND workspace_id=p_workspace_id
   AND investor_profile_id=actor AND integration_key='NSE_INVEST' AND integration_environment='UAT' AND state='REGISTERED' FOR UPDATE;
 IF a.id IS NULL OR a.external_account_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.workspaces WHERE id=a.workspace_id AND workspace_status='active')
   OR NOT EXISTS(SELECT 1 FROM public.workspace_memberships WHERE workspace_id=a.workspace_id AND profile_id=actor AND role='investor' AND status='active' AND ended_at IS NULL)
   THEN RAISE EXCEPTION 'bank_mandate_owner_required'; END IF;
 SELECT * INTO b FROM public.investor_bank_accounts WHERE id=p_bank_account_id AND workspace_id=a.workspace_id AND investor_profile_id=actor FOR UPDATE;
 IF b.id IS NULL OR NOT b.is_active OR b.verification_status<>'verified' THEN RAISE EXCEPTION 'bank_mandate_verified_owned_bank_required'; END IF;
 SELECT * INTO old_intent FROM nse_bank_mandate.intents WHERE id=p_request_id;
 IF old_intent.id IS NOT NULL THEN
   IF old_intent.integration_account_id IS DISTINCT FROM a.id OR old_intent.bank_account_id IS DISTINCT FROM b.id OR old_intent.action IS DISTINCT FROM p_action THEN RAISE EXCEPTION 'bank_mandate_intent_conflict'; END IF;
   RETURN old_intent.id;
 END IF;
 IF p_action='BANK_DEL' AND b.is_default THEN RAISE EXCEPTION 'bank_delete_default_protected'; END IF;
 IF EXISTS(SELECT 1 FROM nse_bank_mandate.intents WHERE integration_account_id=a.id AND bank_account_id=b.id AND action=p_action) THEN RAISE EXCEPTION 'bank_mandate_duplicate_intent'; END IF;
 reason:=CASE p_action WHEN 'MANDATE' THEN 'mandate_contract_and_consent_unresolved' WHEN 'BANK_ADD' THEN 'bank_add_consent_and_provider_relationship_unproven' ELSE 'bank_delete_dependencies_unproven' END;
 snapshot:=pg_catalog.jsonb_build_object('client_code',a.external_account_id,'bank_account_id',b.id,'account_type',b.account_type,
  'account_no',extensions.pgp_sym_decrypt(b.account_number_ciphertext,public.bank_account_encryption_key(b.account_number_key_reference)),
  'ifsc_code',b.ifsc_code,'micr_code',b.micr_code,'is_default',b.is_default,'bank_updated_at',b.updated_at);
 INSERT INTO nse_bank_mandate.intents(id,workspace_id,integration_account_id,investor_profile_id,bank_account_id,actor_profile_id,action,member_mandate_no,block_reason,source_ciphertext,source_key_reference)
 VALUES(p_request_id,a.workspace_id,a.id,actor,b.id,actor,p_action,
 CASE WHEN p_action='MANDATE' THEN pg_catalog.left(pg_catalog.replace(pg_catalog.gen_random_uuid()::text,'-',''),20) ELSE NULL END,reason,
 extensions.pgp_sym_encrypt(snapshot::text,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'),'integration_payload_encryption_key_v1');
 INSERT INTO public.workspace_audit_logs(workspace_id,actor_id,action,event_type,target_type,entity_type,target_id,entity_id,actor_type,reason,payload)
 VALUES(a.workspace_id,actor,'nse.bank_mandate.review_requested','nse.bank_mandate.review_requested','nse_bank_mandate_intent','nse_bank_mandate_intent',p_request_id,p_request_id,
 'investor',reason,pg_catalog.jsonb_build_object('action',p_action,'previous_state',NULL,'new_state','BLOCKED'));
 RETURN p_request_id;
END $$;

CREATE OR REPLACE FUNCTION public.accept_workspace_invitation(p_plaintext_token text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  u auth.users%rowtype;
  invitation public.workspace_invitations%rowtype;
  profile_id uuid;
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'account_unavailable'; end if;
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
      AND (inviter.role = 'platform_admin' OR EXISTS (
        SELECT 1 FROM public.workspace_memberships m WHERE m.profile_id = inviter.id
        AND m.workspace_id = i.workspace_id AND m.role = 'admin'
        AND m.status = 'active' AND m.ended_at IS NULL)))
  FOR UPDATE OF i;
  IF invitation.id IS NULL THEN RAISE EXCEPTION 'invitation_unavailable'; END IF;
  PERFORM moneybowl_authz.lock_scope(invitation.workspace_id);
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=invitation.invited_by
    AND moneybowl_authz.profile_active(p.id) AND (p.role='platform_admin'
      OR moneybowl_authz.member_role(invitation.workspace_id,p.id)='admin'))
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
$$;

CREATE FUNCTION public.set_workspace_membership_status(p_membership_id uuid,p_status text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE m public.workspace_memberships;
BEGIN
  SELECT * INTO m FROM public.workspace_memberships WHERE id=p_membership_id;
  PERFORM moneybowl_authz.lock_scope(m.workspace_id);
  IF NOT public.is_workspace_admin(m.workspace_id) OR p_status NOT IN ('active','inactive','suspended') THEN RAISE EXCEPTION 'not_authorized'; END IF;
  SELECT * INTO m FROM public.workspace_memberships WHERE id=p_membership_id FOR UPDATE;
  IF m.ended_at IS NOT NULL THEN RAISE EXCEPTION 'membership_ended'; END IF;
  UPDATE public.workspace_memberships SET status=p_status,updated_at=now() WHERE id=m.id;
  INSERT INTO public.workspace_audit_logs(workspace_id,actor_id,action,target_type,target_id,payload)
    VALUES(m.workspace_id,moneybowl_authz.actor(),'membership_status_changed','membership',m.id,
      jsonb_build_object('previous_status',m.status,'status',p_status));
  RETURN true;
END $$;

CREATE FUNCTION moneybowl_authz.guard_invitation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP='INSERT' AND current_setting('role',true) IN ('authenticated','anon') THEN
    PERFORM moneybowl_authz.lock_scope(NEW.workspace_id);
    IF NOT public.is_workspace_admin(NEW.workspace_id) OR NEW.status<>'pending' THEN RAISE EXCEPTION 'not_authorized'; END IF;
    NEW.invited_by:=moneybowl_authz.actor();
  ELSIF TG_OP='UPDATE' AND (NEW.workspace_id,NEW.email,NEW.role,NEW.invited_by,NEW.token_hash,NEW.expires_at)
    IS DISTINCT FROM (OLD.workspace_id,OLD.email,OLD.role,OLD.invited_by,OLD.token_hash,OLD.expires_at) THEN
    RAISE EXCEPTION 'invitation_provenance_immutable';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER invitation_provenance BEFORE INSERT OR UPDATE ON public.workspace_invitations
FOR EACH ROW EXECUTE FUNCTION moneybowl_authz.guard_invitation();

CREATE FUNCTION moneybowl_authz.audit_assignment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE a public.advisor_investor_assignments;
BEGIN
  IF TG_OP='DELETE' THEN a:=OLD; ELSE a:=NEW; END IF;
  IF a.workspace_id IS NOT NULL THEN
    INSERT INTO public.workspace_audit_logs(workspace_id,actor_id,action,target_type,target_id,payload)
      VALUES(a.workspace_id,moneybowl_authz.actor(),'assignment_'||lower(TG_OP),'advisor_investor_assignment',a.id,
        jsonb_build_object('advisor_id',a.advisor_id,'investor_id',a.investor_id,'status',a.status,'ended_at',a.ended_at));
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER assignment_audit AFTER INSERT OR UPDATE OR DELETE ON public.advisor_investor_assignments
FOR EACH ROW EXECUTE FUNCTION moneybowl_authz.audit_assignment();

-- Scope is immutable once proven. A trusted operator may resolve NULL legacy
-- scope after evidence review; there is deliberately no browser provisioning API.
CREATE FUNCTION moneybowl_authz.guard_verification_scope() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF (OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS DISTINCT FROM OLD.workspace_id)
    OR (NEW.user_id,NEW.method_code) IS DISTINCT FROM (OLD.user_id,OLD.method_code) THEN
    RAISE EXCEPTION 'verification_provenance_immutable';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER verification_scope_immutable BEFORE UPDATE ON public.verification_requests
FOR EACH ROW EXECUTE FUNCTION moneybowl_authz.guard_verification_scope();

DROP POLICY payment_events_select ON public.payment_events;
CREATE POLICY payment_events_select ON public.payment_events FOR SELECT TO authenticated
  USING(public.can_access_investor(workspace_id,investor_profile_id)
    OR (public.has_active_investor_link(investor_profile_id) AND public.has_investor_membership(workspace_id)));

-- No scope can be reconstructed from this legacy signature.
CREATE OR REPLACE FUNCTION public.can_manage_assignment(p_advisor_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT false $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA moneybowl_authz FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.begin_folio_review(p_request_id uuid, p_expected_version integer) RETURNS TABLE(request_id uuid, status public.verification_request_status, version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'begin_review'); end; $$;

CREATE OR REPLACE FUNCTION public.request_folio_more_information(p_request_id uuid, p_expected_version integer, p_reason text) RETURNS TABLE(request_id uuid, status public.verification_request_status, version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'more_information',p_reason); end; $$;

CREATE OR REPLACE FUNCTION public.resubmit_folio_verification(p_request_id uuid, p_expected_version integer) RETURNS TABLE(request_id uuid, status public.verification_request_status, version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'resubmit'); end; $$;

CREATE OR REPLACE FUNCTION public.reject_folio_verification(p_request_id uuid, p_expected_version integer, p_reason text) RETURNS TABLE(request_id uuid, status public.verification_request_status, version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'reject',p_reason); end; $$;

CREATE OR REPLACE FUNCTION public.cancel_folio_verification(p_request_id uuid, p_expected_version integer) RETURNS TABLE(request_id uuid, status public.verification_request_status, version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'cancel'); end; $$;

CREATE OR REPLACE FUNCTION public.expire_folio_verification(p_request_id uuid, p_expected_version integer) RETURNS TABLE(request_id uuid, status public.verification_request_status, version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'expire','SYSTEM_EXPIRY'); end; $$;

CREATE OR REPLACE FUNCTION public.get_my_folio_requests(p_page integer DEFAULT 0, p_page_size integer DEFAULT 25) RETURNS TABLE(request_id uuid, version integer, registrar_display text, masked_folio text, status public.verification_request_status, submitted_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'Authentication is required'; end if;
  if p_page < 0 or p_page_size < 1 or p_page_size > 100 then raise exception 'Invalid pagination'; end if;
  return query
  select r.id,r.version,case when f.registrar='KFINTECH' then 'KFintech' else 'CAMS' end,
    public.mask_canonical_folio(f.normalized_folio_number),r.status,r.submitted_at
  from public.verification_requests r
  join public.verification_folio_evidence e on e.request_id=r.id
  join public.folio_references f on f.id=e.folio_reference_id
  where r.user_id=auth.uid() and r.method_code='folio'
  order by r.submitted_at desc nulls last,r.created_at desc,r.id desc
  limit p_page_size offset p_page*p_page_size;
end; $$;

CREATE OR REPLACE FUNCTION public.submit_pan_verification(p_pan text) RETURNS TABLE(request_id uuid, status public.verification_request_status, masked_pan text, match_result public.verification_match_result, conflict_reason public.verification_conflict_reason)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_account public.user_accounts%rowtype;
  v_request public.verification_requests%rowtype;
  v_normalized_pan text;
  v_pan_hmac bytea;
  v_profile_count integer;
  v_conflict public.verification_conflict_reason := 'NONE'::public.verification_conflict_reason;
  v_match public.verification_match_result := 'NO_MATCH'::public.verification_match_result;
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'Authentication is required'; end if;
  v_normalized_pan := public.normalize_pan(p_pan);
  if v_normalized_pan is null then raise exception 'PAN format is invalid'; end if;
  select * into v_account from public.user_accounts as account where account.user_id = auth.uid() for update;
  if not found or v_account.account_state <> 'link_pending' then raise exception 'PAN verification is not available for this account'; end if;
  if exists (select 1 from public.investor_account_links as link where link.user_id = auth.uid() and link.link_status = 'active') then raise exception 'PAN verification is not available for this account'; end if;
  if exists (select 1 from public.verification_requests as open_request where open_request.user_id = auth.uid() and open_request.status in ('draft', 'pending_advisor_review', 'more_information_required')) then raise exception 'A verification request is already in progress'; end if;
  v_pan_hmac := extensions.hmac(v_normalized_pan, public.pan_lookup_hmac_key(), 'sha256');
  -- A transaction-scoped keyed lock makes duplicate classification deterministic
  -- without exposing or persisting the PAN outside encrypted/HMAC storage.
  perform pg_advisory_xact_lock(hashtextextended(encode(v_pan_hmac, 'hex'), 0));
  select count(distinct pan_record.profile_id) into v_profile_count from public.profile_pan_records as pan_record
  where pan_record.pan_lookup_hmac = v_pan_hmac and pan_record.status in ('OBSERVED', 'VERIFIED');
  v_match := case when v_profile_count = 0 then 'NO_MATCH'::public.verification_match_result when v_profile_count = 1 then 'SINGLE_MATCH'::public.verification_match_result else 'MULTIPLE_MATCH'::public.verification_match_result end;
  if exists (select 1 from public.profile_pan_records as pan_record join public.investor_account_links as active_link on active_link.profile_id = pan_record.profile_id where pan_record.pan_lookup_hmac = v_pan_hmac and pan_record.status in ('OBSERVED', 'VERIFIED') and active_link.link_status = 'active') then
    v_conflict := 'ALREADY_VERIFIED';
  elsif exists (select 1 from public.verification_pan_evidence as evidence join public.verification_requests as pending_request on pending_request.id = evidence.request_id where evidence.pan_lookup_hmac = v_pan_hmac and pending_request.user_id <> auth.uid() and pending_request.status in ('pending_advisor_review', 'more_information_required')) then
    v_conflict := 'PENDING_DUPLICATE';
  end if;
  insert into public.verification_requests (user_id, method_code, status, submitted_at) values (auth.uid(), 'pan', 'pending_advisor_review', now()) returning * into v_request;
  insert into public.verification_pan_evidence (request_id, pan_ciphertext, pan_lookup_hmac, masked_pan, match_result, conflict_reason)
  values (v_request.id, extensions.pgp_sym_encrypt(v_normalized_pan, public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'), v_pan_hmac, public.mask_pan(v_normalized_pan), v_match, v_conflict);
  insert into public.verification_events (request_id, subject_user_id, actor_user_id, actor_type, event_type, previous_status, new_status)
  values (v_request.id, auth.uid(), auth.uid(), 'investor', 'created', null, 'draft'),
    (v_request.id, auth.uid(), auth.uid(), 'investor', 'pan_submitted', 'draft', 'pending_advisor_review'),
    (v_request.id, auth.uid(), null, 'system', 'pan_match_assessed', 'pending_advisor_review', 'pending_advisor_review');
  return query select v_request.id, v_request.status, public.mask_pan(v_normalized_pan), v_match, v_conflict;
end;
$$;

CREATE OR REPLACE FUNCTION public.create_non_pan_verification_request(p_method_code text) RETURNS TABLE(request_id uuid, status public.verification_request_status)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  account public.user_accounts%rowtype;
  created_request public.verification_requests%rowtype;
begin
  if not moneybowl_authz.account_active(auth.uid()) then raise exception 'Authentication is required'; end if;
  select * into account from public.user_accounts where user_id = auth.uid() for update;
  if not found or account.account_state <> 'link_pending' then
    raise exception 'Verification is not available for this account';
  end if;
  if exists (select 1 from public.investor_account_links where user_id = auth.uid() and link_status = 'active') then
    raise exception 'Verification is not available for this account';
  end if;
  if p_method_code not in ('verified_email', 'verified_mobile', 'folio', 'advisor_assisted', 'otp', 'document_upload') then
    raise exception 'Verification method is not available';
  end if;
  insert into public.verification_requests (user_id, method_code, status, submitted_at)
  values (auth.uid(), p_method_code, 'pending_advisor_review', now())
  returning * into created_request;
  insert into public.verification_events (request_id, subject_user_id, actor_user_id, actor_type, event_type, previous_status, new_status)
  values
    (created_request.id, auth.uid(), auth.uid(), 'investor', 'created', null, 'draft'),
    (created_request.id, auth.uid(), auth.uid(), 'investor', 'submitted', 'draft', 'pending_advisor_review');
  return query select created_request.id, created_request.status;
end;
$$;

ALTER TABLE public.verification_events DROP CONSTRAINT verification_events_actor_type_check;
ALTER TABLE public.verification_events ADD CONSTRAINT verification_events_actor_type_check CHECK(actor_type IN ('investor','advisor','system','service','platform_admin'));

CREATE OR REPLACE FUNCTION public.complete_mailbox_oauth_authorization(p_authorization_id uuid, p_credential_ciphertext text, p_credential_nonce text, p_key_version integer, p_expires_at timestamp with time zone) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_state public.mailbox_oauth_authorization_states;
BEGIN
  IF p_key_version <> 1 OR p_credential_ciphertext IS NULL
     OR p_credential_ciphertext = '' THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable' USING ERRCODE = 'P0001';
  END IF;
  BEGIN
    IF p_credential_nonce IS NULL
       OR pg_catalog.octet_length(pg_catalog.decode(p_credential_nonce, 'base64')) <> 12 THEN
      RAISE EXCEPTION 'oauth_credentials_unavailable';
    END IF;
    PERFORM pg_catalog.decode(p_credential_ciphertext, 'base64');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable' USING ERRCODE = 'P0001';
  END;

  SELECT * INTO v_state FROM public.mailbox_oauth_authorization_states AS state
  WHERE state.id = p_authorization_id FOR UPDATE;
  IF NOT FOUND OR v_state.consumed_at IS NULL OR v_state.completed_at IS NOT NULL
     OR v_state.failed_at IS NOT NULL
     OR pg_catalog.now() > v_state.expires_at + pg_catalog.interval '2 minutes' THEN
    RAISE EXCEPTION 'oauth_state_replayed' USING ERRCODE = 'P0001';
  END IF;

  PERFORM moneybowl_authz.lock_scope(v_state.workspace_id);
  IF coalesce(moneybowl_authz.member_role(v_state.workspace_id,v_state.actor_profile_id) IN ('advisor','admin'),false)=false THEN RAISE EXCEPTION 'not_authorized'; END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.workspaces AS workspace
    JOIN public.workspace_memberships AS membership
      ON membership.workspace_id = workspace.id
    JOIN public.mailbox_connections AS mailbox
      ON mailbox.workspace_id = workspace.id
    WHERE workspace.id = v_state.workspace_id
      AND workspace.workspace_status = 'active'
      AND membership.profile_id = v_state.actor_profile_id
      AND membership.role IN ('advisor', 'admin')
      AND membership.status = 'active'
      AND membership.ended_at IS NULL
      AND mailbox.id = v_state.mailbox_connection_id
      AND pg_catalog.lower(mailbox.oauth_provider) = 'gmail'
      AND mailbox.status IN ('active', 'reauthorization_required')
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.mailbox_oauth_credentials (
    mailbox_connection_id, workspace_id, credential_ciphertext,
    credential_nonce, key_version, expires_at, refreshed_at
  ) VALUES (
    v_state.mailbox_connection_id, v_state.workspace_id,
    p_credential_ciphertext, p_credential_nonce, p_key_version,
    p_expires_at, pg_catalog.now()
  ) ON CONFLICT (mailbox_connection_id) DO UPDATE
    SET credential_ciphertext = EXCLUDED.credential_ciphertext,
        credential_nonce = EXCLUDED.credential_nonce,
        key_version = EXCLUDED.key_version,
        expires_at = EXCLUDED.expires_at,
        refreshed_at = pg_catalog.now(),
        updated_at = pg_catalog.now()
    WHERE public.mailbox_oauth_credentials.workspace_id = v_state.workspace_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.mailbox_connections AS mailbox
  SET status = 'active', updated_at = pg_catalog.now()
  WHERE mailbox.id = v_state.mailbox_connection_id
    AND mailbox.workspace_id = v_state.workspace_id;

  UPDATE public.mailbox_oauth_authorization_states AS state
  SET completed_at = pg_catalog.now()
  WHERE state.id = v_state.id;

  INSERT INTO public.workspace_audit_logs (
    workspace_id, actor_id, action, target_type, target_id, payload,
    actor_profile_id, actor_type, entity_type, entity_id, event_type,
    outcome, occurred_at
  ) VALUES (
    v_state.workspace_id, v_state.actor_profile_id,
    'mailbox.oauth.authorization_completed', 'mailbox_connection',
    v_state.mailbox_connection_id,
    pg_catalog.jsonb_build_object('flow_kind', v_state.flow_kind),
    v_state.actor_profile_id, 'workspace_user', 'mailbox_connection',
    v_state.mailbox_connection_id, 'mailbox.oauth.authorization_completed',
    'succeeded', pg_catalog.now()
  );
  RETURN v_state.flow_kind;
END;
$$;

-- Workspace choices come only from established membership/link or a verified,
-- server-stored invitation. Selecting a workspace does not grant membership.
CREATE FUNCTION public.list_my_verification_workspaces() RETURNS TABLE(workspace_id uuid,workspace_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT w.id,w.name FROM public.workspaces w WHERE w.workspace_status='active'
    AND moneybowl_authz.account_active(auth.uid()) AND (
      EXISTS(SELECT 1 FROM public.workspace_memberships m WHERE m.workspace_id=w.id
        AND moneybowl_authz.member_role(w.id,m.profile_id) IS NOT NULL
        AND (m.profile_id=moneybowl_authz.actor() OR moneybowl_authz.owns_investor(m.profile_id)))
      OR EXISTS(SELECT 1 FROM public.workspace_invitations i JOIN auth.users u ON u.id=auth.uid()
        JOIN public.profiles inviter ON inviter.id=i.invited_by
        WHERE i.workspace_id=w.id AND i.status='pending' AND i.expires_at>now()
          AND u.email_confirmed_at IS NOT NULL AND lower(btrim(i.email))=lower(btrim(u.email))
          AND moneybowl_authz.profile_active(inviter.id)
          AND moneybowl_authz.member_role(w.id,inviter.id)='admin'))
  ORDER BY w.name,w.id
$$;
CREATE FUNCTION public.create_verification_request(p_method_code text,p_workspace_id uuid)
RETURNS TABLE(request_id uuid,status public.verification_request_status)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE r record;
BEGIN
  IF p_method_code='folio' THEN RAISE EXCEPTION USING ERRCODE='PFL01',message='Use dedicated folio verification submission'; END IF;
  PERFORM moneybowl_authz.lock_scope(p_workspace_id);
  IF p_workspace_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.list_my_verification_workspaces() w WHERE w.workspace_id=p_workspace_id) THEN
    RAISE EXCEPTION 'verification_workspace_required';
  END IF;
  SELECT * INTO r FROM public.create_non_pan_verification_request(p_method_code);
  UPDATE public.verification_requests SET workspace_id=p_workspace_id WHERE id=r.request_id;
  RETURN QUERY SELECT r.request_id,r.status;
END $$;
CREATE OR REPLACE FUNCTION public.create_verification_request(p_method_code text)
RETURNS TABLE(request_id uuid,status public.verification_request_status)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE choices uuid[];
BEGIN
  IF p_method_code='folio' THEN RAISE EXCEPTION USING ERRCODE='PFL01',message='Use dedicated folio verification submission'; END IF;
  SELECT array_agg(w.workspace_id) INTO choices FROM public.list_my_verification_workspaces() w;
  IF cardinality(choices) IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'verification_workspace_required'; END IF;
  RETURN QUERY SELECT * FROM public.create_verification_request(p_method_code,choices[1]);
END $$;

-- A verified identity approval may not take over an already-owned profile.
CREATE FUNCTION moneybowl_authz.guard_investor_link_owner() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE owner_id uuid;
BEGIN
  IF NEW.link_status='active' THEN
    SELECT user_id INTO owner_id FROM public.profiles WHERE id=NEW.profile_id FOR UPDATE;
    IF owner_id IS NOT NULL AND owner_id<>NEW.user_id THEN RAISE EXCEPTION 'investor_identity_owned'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER investor_link_owner BEFORE INSERT OR UPDATE ON public.investor_account_links
FOR EACH ROW EXECUTE FUNCTION moneybowl_authz.guard_investor_link_owner();
REVOKE ALL ON FUNCTION moneybowl_authz.guard_investor_link_owner() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_my_advisor_folio_request_detail(p_request_id uuid) RETURNS TABLE(request_id uuid, version integer, investor_display_label text, registrar_display text, masked_folio text, holder_relationship public.folio_holder_relationship, status public.verification_request_status, submitted_at timestamp with time zone, updated_at timestamp with time zone, expires_at timestamp with time zone, event_summary jsonb)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public._assert_assigned_folio_advisor(p_request_id);
  return query
  select request_row.id,request_row.version,
    'Investor request'::text,
    case when folio.registrar = 'KFINTECH' then 'KFintech' else 'CAMS' end,
    public.mask_canonical_folio(folio.normalized_folio_number),
    evidence.holder_relationship,request_row.status,request_row.submitted_at,
    request_row.updated_at,request_row.expires_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'event_type',event_row.event_type,
        'previous_status',event_row.previous_status,
        'new_status',event_row.new_status,
        'reason_code',event_row.reason_code,
        'created_at',event_row.created_at
      ) order by event_row.created_at asc)
      from public.verification_events event_row
      where event_row.request_id = request_row.id
    ), '[]'::jsonb)
  from public.verification_requests request_row
  join public.verification_folio_evidence evidence on evidence.request_id = request_row.id
  join public.folio_references folio on folio.id = evidence.folio_reference_id
  where request_row.id = p_request_id and request_row.method_code = 'folio';
end;
$$;

-- Explicit ACL contract for every affected public overload, including old ones.
DO $$ DECLARE p record; BEGIN
  FOR p IN SELECT oid::regprocedure signature,proname FROM pg_catalog.pg_proc WHERE pronamespace='public'::regnamespace AND proname IN ('get_my_advisor_folio_request_detail','create_verification_request','list_my_verification_workspaces','complete_mailbox_oauth_authorization','create_non_pan_verification_request','submit_pan_verification','get_my_folio_requests','expire_folio_verification','cancel_folio_verification','reject_folio_verification','resubmit_folio_verification','request_folio_more_information','begin_folio_review','_assert_assigned_folio_advisor','_single_active_advisor_account','_transition_folio_request','accept_workspace_invitation','approve_folio_verification','approve_pan_verification_candidate','approve_verification_candidate','approve_verification_request','authorize_cams_kfintech_workspace','authorize_workspace_tools','begin_mailbox_oauth_authorization','can_access_investor','can_access_profile','can_insert_order_request','can_manage_assignment','can_read_portfolio','can_review_verification','can_select_order_request','cancel_order','current_user_workspace_ids','get_folio_grant_summary','get_folio_request_detail','get_folio_verification_events','get_my_advisor_folio_requests','get_verification_events','get_verification_review','has_active_folio_grant','has_active_investor_link','has_active_workspace_membership','has_advisor_membership','has_investor_membership','is_admin','is_order_mfd_profile','is_platform_admin','is_workspace_admin','is_workspace_admin_or_ops','issue_folio_submission_token','list_order_folios','list_verification_review_queue','list_verification_review_queue_filtered','qualify_order','reject_verification_request','request_more_verification_information','request_nse_bank_mandate_review','resolve_order_folio_portfolio','revoke_folio_grant','revoke_investor_link','revoke_mailbox_oauth_credential','search_verification_candidates','set_workspace_membership_status','submit_folio_verification','validate_folio_request_assignment','validate_order_request_canonical_contract','verify_advisor_investor_assignment') LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',p.signature);
    IF p.proname NOT LIKE '\_%' AND p.proname NOT IN ('create_non_pan_verification_request','complete_mailbox_oauth_authorization','is_order_mfd_profile','verify_advisor_investor_assignment','validate_order_request_canonical_contract','validate_folio_request_assignment') AND p.signature::text<>'issue_folio_submission_token(uuid,uuid)' THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',p.signature);
    END IF;
  END LOOP;
END $$;

COMMIT;
