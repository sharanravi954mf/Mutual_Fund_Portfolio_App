-- Issue #31: Platform Admin override and Family Access support boundary.

BEGIN;

-- Keep profile resolution canonical while removing SECURITY DEFINER search_path drift.
CREATE OR REPLACE FUNCTION public.current_user_profile_id()
RETURNS pg_catalog.uuid AS $$
DECLARE
  v_profile_id pg_catalog.uuid;
BEGIN
  SELECT profile.id
  INTO v_profile_id
  FROM public.profiles AS profile
  WHERE profile.user_id = auth.uid();

  RETURN v_profile_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS pg_catalog.bool AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    WHERE profile.user_id = auth.uid()
      AND profile.role = 'platform_admin'
      AND profile.account_status = 'active'
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.platform_admin_step_up_verified()
RETURNS pg_catalog.bool AS $$
DECLARE
  v_jwt jsonb;
BEGIN
  v_jwt := COALESCE(auth.jwt(), '{}'::jsonb);

  RETURN COALESCE(v_jwt -> 'amr', '[]'::jsonb) ? 'mfa'
    OR COALESCE(v_jwt ->> 'aal', '') IN ('aal2', 'aal3')
    OR COALESCE(v_jwt #>> '{app_metadata,aal}', '') IN ('aal2', 'aal3');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.current_user_profile_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_profile_id() FROM anon;
REVOKE ALL ON FUNCTION public.current_user_profile_id() FROM authenticated;
REVOKE ALL ON FUNCTION public.current_user_profile_id() FROM service_role;
GRANT EXECUTE ON FUNCTION public.current_user_profile_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_profile_id() TO service_role;

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_platform_admin() FROM anon;
REVOKE ALL ON FUNCTION public.is_platform_admin() FROM authenticated;
REVOKE ALL ON FUNCTION public.is_platform_admin() FROM service_role;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO service_role;

REVOKE ALL ON FUNCTION public.platform_admin_step_up_verified() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_admin_step_up_verified() FROM anon;
REVOKE ALL ON FUNCTION public.platform_admin_step_up_verified() FROM authenticated;
REVOKE ALL ON FUNCTION public.platform_admin_step_up_verified() FROM service_role;
GRANT EXECUTE ON FUNCTION public.platform_admin_step_up_verified() TO authenticated;

-- Remove direct, pre-Issue #31 override mutation entry points.
DROP FUNCTION IF EXISTS public.override_account_unlock(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid);
DROP FUNCTION IF EXISTS public.override_account_unlock(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.uuid);
DROP FUNCTION IF EXISTS public.override_access_reset(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid);
DROP FUNCTION IF EXISTS public.override_access_reset(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.uuid);

-- Removing Platform Admin from shared access helpers closes parallel broad policies.
CREATE OR REPLACE FUNCTION public.can_access_profile(p_profile_id pg_catalog.uuid)
RETURNS pg_catalog.bool AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS caller_membership
    JOIN public.workspace_memberships AS target_membership
      ON target_membership.workspace_id = caller_membership.workspace_id
    WHERE caller_membership.profile_id = public.current_user_profile_id()
      AND caller_membership.status = 'active'
      AND target_membership.profile_id = p_profile_id
      AND target_membership.status = 'active'
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.can_access_investor(p_investor_profile_id pg_catalog.uuid)
RETURNS pg_catalog.bool AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS caller_membership
    JOIN public.workspace_memberships AS investor_membership
      ON investor_membership.workspace_id = caller_membership.workspace_id
    WHERE caller_membership.profile_id = public.current_user_profile_id()
      AND caller_membership.status = 'active'
      AND caller_membership.role IN ('advisor', 'admin', 'operations')
      AND investor_membership.profile_id = p_investor_profile_id
      AND investor_membership.role = 'investor'
      AND investor_membership.status = 'active'
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

-- Catalog preflight before adding override-audit uniqueness constraints.
DO $$
DECLARE
  v_duplicate_count pg_catalog.int8;
BEGIN
  SELECT pg_catalog.count(*)
  INTO v_duplicate_count
  FROM (
    SELECT audit.correlation_id
    FROM public.workspace_audit_logs AS audit
    WHERE audit.event_type = 'override.attempted'
      AND audit.correlation_id IS NOT NULL
    GROUP BY audit.correlation_id
    HAVING pg_catalog.count(*) > 1
  ) AS duplicates;

  IF v_duplicate_count > 0 THEN
    RAISE EXCEPTION 'issue_31_preflight_duplicate_override_attempts';
  END IF;

  SELECT pg_catalog.count(*)
  INTO v_duplicate_count
  FROM (
    SELECT audit.correlation_id
    FROM public.workspace_audit_logs AS audit
    WHERE audit.event_type IN ('override.succeeded', 'override.denied', 'override.failed')
      AND audit.correlation_id IS NOT NULL
    GROUP BY audit.correlation_id
    HAVING pg_catalog.count(*) > 1
  ) AS duplicates;

  IF v_duplicate_count > 0 THEN
    RAISE EXCEPTION 'issue_31_preflight_duplicate_override_terminals';
  END IF;
END;
$$;

ALTER TABLE public.workspace_audit_logs
  DROP CONSTRAINT IF EXISTS workspace_audit_logs_override_contract_chk;

ALTER TABLE public.workspace_audit_logs
  ADD CONSTRAINT workspace_audit_logs_override_contract_chk
  CHECK (
    event_type IS NULL
    OR event_type NOT LIKE 'override.%'
    OR (
      actor_profile_id IS NOT NULL
      AND actor_type = 'platform_admin'
      AND entity_type IS NOT NULL
      AND entity_id IS NOT NULL
      AND action IN ('family_delegation.read', 'family_delegation.restore_access')
      AND reason IS NOT NULL
      AND pg_catalog.btrim(reason) <> ''
      AND correlation_id IS NOT NULL
      AND occurred_at IS NOT NULL
      AND (
        (event_type = 'override.attempted' AND outcome = 'attempted' AND error_code IS NULL)
        OR (event_type = 'override.succeeded' AND outcome = 'succeeded' AND error_code IS NULL)
        OR (event_type = 'override.denied' AND outcome = 'denied' AND error_code IS NOT NULL)
        OR (event_type = 'override.failed' AND outcome = 'failed' AND error_code IS NOT NULL)
      )
    )
  );

DROP INDEX IF EXISTS public.workspace_audit_logs_override_attempt_uidx;
DROP INDEX IF EXISTS public.workspace_audit_logs_override_terminal_uidx;
CREATE UNIQUE INDEX workspace_audit_logs_override_attempt_uidx
  ON public.workspace_audit_logs(correlation_id)
  WHERE event_type = 'override.attempted';

CREATE UNIQUE INDEX workspace_audit_logs_override_terminal_uidx
  ON public.workspace_audit_logs(correlation_id)
  WHERE event_type IN ('override.succeeded', 'override.denied', 'override.failed');

CREATE INDEX IF NOT EXISTS workspace_audit_logs_override_entity_idx
  ON public.workspace_audit_logs(workspace_id, entity_type, entity_id, action)
  WHERE event_type LIKE 'override.%';

CREATE OR REPLACE FUNCTION public.begin_platform_admin_override_attempt(
  p_workspace_id pg_catalog.uuid,
  p_entity_type pg_catalog.text,
  p_entity_id pg_catalog.uuid,
  p_action pg_catalog.text,
  p_reason pg_catalog.text,
  p_correlation_id pg_catalog.uuid
)
RETURNS pg_catalog.uuid AS $$
DECLARE
  v_actor_profile_id pg_catalog.uuid;
  v_existing public.workspace_audit_logs;
  v_audit_id pg_catalog.uuid;
BEGIN
  v_actor_profile_id := public.current_user_profile_id();
  IF v_actor_profile_id IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    WHERE profile.id = v_actor_profile_id
      AND profile.role = 'platform_admin'
      AND profile.account_status = 'active'
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF NOT public.platform_admin_step_up_verified() THEN
    RAISE EXCEPTION 'platform_admin_step_up_required';
  END IF;

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

  IF NOT EXISTS (
    SELECT 1
    FROM public.family_delegations AS delegation
    WHERE delegation.id = p_entity_id
      AND delegation.workspace_id = p_workspace_id
  ) THEN
    RAISE EXCEPTION 'target_workspace_mismatch';
  END IF;

  SELECT *
  INTO v_existing
  FROM public.workspace_audit_logs AS audit
  WHERE audit.correlation_id = p_correlation_id
    AND audit.event_type = 'override.attempted';

  IF v_existing.id IS NOT NULL THEN
    IF v_existing.actor_profile_id IS DISTINCT FROM v_actor_profile_id
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
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.finish_platform_admin_override_attempt(
  p_correlation_id pg_catalog.uuid,
  p_event_type pg_catalog.text,
  p_error_code pg_catalog.text DEFAULT NULL
)
RETURNS pg_catalog.uuid AS $$
DECLARE
  v_attempt public.workspace_audit_logs;
  v_existing public.workspace_audit_logs;
  v_outcome pg_catalog.text;
  v_audit_id pg_catalog.uuid;
BEGIN
  IF p_correlation_id IS NULL THEN
    RAISE EXCEPTION 'correlation_id_required';
  END IF;

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
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.platform_admin_read_family_delegation_support_projection(
  p_correlation_id pg_catalog.uuid,
  p_workspace_id pg_catalog.uuid,
  p_delegation_id pg_catalog.uuid,
  p_owner_profile_id pg_catalog.uuid,
  p_delegate_profile_id pg_catalog.uuid
)
RETURNS TABLE (
  delegation_id pg_catalog.uuid,
  workspace_id pg_catalog.uuid,
  owner_profile_id pg_catalog.uuid,
  delegate_profile_id pg_catalog.uuid,
  consent_status pg_catalog.text,
  is_active pg_catalog.bool,
  expires_at pg_catalog.timestamptz
) AS $$
DECLARE
  v_attempt public.workspace_audit_logs;
BEGIN
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
    RAISE EXCEPTION 'target_binding_mismatch';
  END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.platform_admin_restore_family_delegation_access(
  p_correlation_id pg_catalog.uuid,
  p_workspace_id pg_catalog.uuid,
  p_delegation_id pg_catalog.uuid,
  p_owner_profile_id pg_catalog.uuid,
  p_delegate_profile_id pg_catalog.uuid
)
RETURNS public.family_delegations AS $$
DECLARE
  v_attempt public.workspace_audit_logs;
  v_delegation public.family_delegations;
BEGIN
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
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.delegate_consent_revoke(
  p_delegation_id pg_catalog.uuid
)
RETURNS public.family_delegations AS $$
DECLARE
  v_delegation public.family_delegations;
  v_caller_profile pg_catalog.uuid;
BEGIN
  v_caller_profile := public.current_user_profile_id();
  IF v_caller_profile IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  IF public.is_platform_admin() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT *
  INTO v_delegation
  FROM public.family_delegations AS delegation
  WHERE delegation.id = p_delegation_id
  FOR UPDATE;

  IF v_delegation.id IS NULL THEN
    RAISE EXCEPTION 'delegation_not_found';
  END IF;

  IF v_delegation.owner_profile_id <> v_caller_profile
     AND v_delegation.delegate_profile_id <> v_caller_profile THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF NOT v_delegation.is_active THEN
    RAISE EXCEPTION 'already_inactive';
  END IF;

  UPDATE public.family_delegations
  SET is_active = false,
      consent_status = 'revoked',
      updated_at = pg_catalog.now()
  WHERE id = p_delegation_id
  RETURNING * INTO v_delegation;

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
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_delegation.workspace_id,
    v_caller_profile,
    v_caller_profile,
    'investor',
    'family_delegation.revoked',
    'family_delegations',
    'family_delegations',
    p_delegation_id,
    p_delegation_id,
    'active',
    'inactive',
    pg_catalog.jsonb_build_object(
      'previous_status', 'active',
      'new_status', 'revoked'
    )
  );

  RETURN v_delegation;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.delegate_consent_revoke(pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delegate_consent_revoke(pg_catalog.uuid) FROM anon;
REVOKE ALL ON FUNCTION public.delegate_consent_revoke(pg_catalog.uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.delegate_consent_revoke(pg_catalog.uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.delegate_consent_revoke(pg_catalog.uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.begin_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.begin_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.uuid) FROM anon;
REVOKE ALL ON FUNCTION public.begin_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.begin_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.begin_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.finish_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.finish_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.text) FROM anon;
REVOKE ALL ON FUNCTION public.finish_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.text) FROM authenticated;
REVOKE ALL ON FUNCTION public.finish_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.finish_platform_admin_override_attempt(pg_catalog.uuid, pg_catalog.text, pg_catalog.text) TO service_role;

REVOKE ALL ON FUNCTION public.platform_admin_read_family_delegation_support_projection(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_admin_read_family_delegation_support_projection(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM anon;
REVOKE ALL ON FUNCTION public.platform_admin_read_family_delegation_support_projection(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.platform_admin_read_family_delegation_support_projection(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.platform_admin_read_family_delegation_support_projection(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) TO service_role;

REVOKE ALL ON FUNCTION public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM anon;
REVOKE ALL ON FUNCTION public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.platform_admin_restore_family_delegation_access(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) TO service_role;

-- Remove direct Platform Admin table bypass policies. Issue #30 order_requests is intentionally untouched.
DROP POLICY IF EXISTS family_delegations_admin_select ON public.family_delegations;
DROP POLICY IF EXISTS "Platform admins manage workspaces" ON public.workspaces;
DROP POLICY IF EXISTS "Users can view workspaces they are members of" ON public.workspaces;
CREATE POLICY "Users can view workspaces they are members of"
  ON public.workspaces FOR SELECT TO authenticated
  USING (id IN (SELECT public.current_user_workspace_ids()));

DROP POLICY IF EXISTS "Admins can manage memberships in their workspaces" ON public.workspace_memberships;
DROP POLICY IF EXISTS "Users can view memberships in their workspaces" ON public.workspace_memberships;
CREATE POLICY "Users can view memberships in their workspaces"
  ON public.workspace_memberships FOR SELECT TO authenticated
  USING (workspace_id IN (SELECT public.current_user_workspace_ids()));
CREATE POLICY "Admins can manage memberships in their workspaces"
  ON public.workspace_memberships FOR ALL TO authenticated
  USING (public.is_workspace_admin(workspace_id))
  WITH CHECK (public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS "Admins can view audit logs in their workspaces" ON public.workspace_audit_logs;
CREATE POLICY "Admins can view audit logs in their workspaces"
  ON public.workspace_audit_logs FOR SELECT TO authenticated
  USING (public.is_workspace_admin_or_ops(workspace_id));

DROP POLICY IF EXISTS "Admins have full access to profiles" ON public.profiles;
CREATE POLICY profiles_workspace_select
  ON public.profiles FOR SELECT TO authenticated
  USING (public.can_access_profile(id));

DROP POLICY IF EXISTS "Admins have full access to portfolios" ON public.portfolios;
CREATE POLICY portfolios_workspace_select
  ON public.portfolios FOR SELECT TO authenticated
  USING (public.can_access_investor(client_id));

DROP POLICY IF EXISTS "Admins have full access to transactions" ON public.transactions;
CREATE POLICY transactions_workspace_select
  ON public.transactions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.portfolios AS portfolio
      WHERE portfolio.id = transactions.portfolio_id
        AND public.can_access_investor(portfolio.client_id)
    )
  );

DROP POLICY IF EXISTS "Users can view assignments in their workspaces" ON public.advisor_investor_assignments;
CREATE POLICY "Users can view assignments in their workspaces"
  ON public.advisor_investor_assignments FOR SELECT TO authenticated
  USING (
    advisor_id = public.current_user_profile_id()
    OR investor_id = public.current_user_profile_id()
    OR EXISTS (
      SELECT 1
      FROM public.workspace_memberships AS caller_membership
      JOIN public.workspace_memberships AS target_membership
        ON target_membership.workspace_id = caller_membership.workspace_id
      WHERE caller_membership.profile_id = public.current_user_profile_id()
        AND caller_membership.status = 'active'
        AND caller_membership.role IN ('admin', 'operations')
        AND target_membership.profile_id IN (advisor_id, investor_id)
        AND target_membership.status = 'active'
    )
  );

DROP POLICY IF EXISTS "Admins can manage assignments in their workspaces" ON public.advisor_investor_assignments;
CREATE POLICY "Admins can manage assignments in their workspaces"
  ON public.advisor_investor_assignments FOR ALL TO authenticated
  USING (public.can_manage_assignment(advisor_id))
  WITH CHECK (public.can_manage_assignment(advisor_id));

DROP POLICY IF EXISTS "Admins can view invitations in their workspaces" ON public.workspace_invitations;
CREATE POLICY "Admins can view invitations in their workspaces"
  ON public.workspace_invitations FOR SELECT TO authenticated
  USING (public.is_workspace_admin_or_ops(workspace_id));

DROP POLICY IF EXISTS "Admins can manage invitations in their workspaces" ON public.workspace_invitations;
CREATE POLICY "Admins can manage invitations in their workspaces"
  ON public.workspace_invitations FOR ALL TO authenticated
  USING (public.is_workspace_admin(workspace_id))
  WITH CHECK (public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS auto_approval_rules_admin_select ON public.auto_approval_rules;
DROP POLICY IF EXISTS event_outbox_select_admin ON public.event_outbox;
DROP POLICY IF EXISTS workspace_billing_admin_all ON public.workspace_billing;
DROP POLICY IF EXISTS workspace_billing_select ON public.workspace_billing;
CREATE POLICY workspace_billing_select
  ON public.workspace_billing FOR SELECT TO authenticated
  USING (public.has_active_workspace_membership(workspace_id));

DROP POLICY IF EXISTS payment_events_select ON public.payment_events;
CREATE POLICY payment_events_select
  ON public.payment_events FOR SELECT TO authenticated
  USING (
    public.has_active_workspace_membership(workspace_id)
    OR investor_profile_id = public.current_user_profile_id()
  );

DROP POLICY IF EXISTS advisor_profiles_select ON public.advisor_profiles;
CREATE POLICY advisor_profiles_select
  ON public.advisor_profiles FOR SELECT TO authenticated
  USING (profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS "Platform admins can manage mutual_funds" ON public.mutual_funds;

REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.family_delegations,
           public.workspace_audit_logs,
           public.profiles,
           public.workspaces,
           public.workspace_memberships,
           public.portfolios,
           public.transactions
  FROM anon, authenticated, service_role;

GRANT SELECT, INSERT ON TABLE public.family_delegations TO authenticated;
GRANT SELECT ON TABLE public.portfolios TO authenticated;

COMMIT;
