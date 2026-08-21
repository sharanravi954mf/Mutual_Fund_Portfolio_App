-- Issue #105: restore the forward-only schema bridge that was previously
-- folded into the already-applied 20260801000000 migration.
--
-- This migration must work from the production schema recorded at
-- 20260801000000 and from a clean replay of the immutable migration chain.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

-- Fail closed when existing financial data cannot be migrated without an
-- explicit business decision. Production was verified to have no delegation
-- rows when this bridge was authored.
DO $preflight$
BEGIN
  IF to_regclass('public.order_requests') IS NULL
     OR to_regclass('public.family_delegations') IS NULL
     OR to_regclass('public.subscription_plans') IS NULL THEN
    RAISE EXCEPTION 'migration_preflight_missing_production_baseline';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = 'public.order_requests'::pg_catalog.regclass
      AND attribute.attname = 'investor_profile_id'
      AND NOT attribute.attisdropped
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = 'public.order_requests'::pg_catalog.regclass
      AND attribute.attname = 'investor_id'
      AND NOT attribute.attisdropped
  ) THEN
    RAISE EXCEPTION 'migration_preflight_unexpected_order_request_shape';
  END IF;

  IF EXISTS (SELECT 1 FROM public.family_delegations) THEN
    RAISE EXCEPTION 'migration_preflight_family_delegations_not_empty';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.portfolios AS portfolio
    WHERE 1 < (
      SELECT pg_catalog.count(DISTINCT membership.workspace_id)
      FROM public.workspace_memberships AS membership
      WHERE membership.profile_id = portfolio.client_id
        AND membership.status = 'active'
    )
  ) THEN
    RAISE EXCEPTION 'migration_preflight_ambiguous_portfolio_workspace';
  END IF;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.subscription_plans
    WHERE name IN ('Starter', 'Pro MFD', 'Enterprise Firm')
  ) <> 3 THEN
    RAISE EXCEPTION 'migration_preflight_missing_subscription_plans';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      VALUES
        ('public.plan_entitlements'),
        ('public.auto_approval_rules'),
        ('public.workspace_branding'),
        ('public.advisor_profiles'),
        ('public.advisor_euin_assignments'),
        ('public.crm_notes')
    ) AS expected(relation_name)
    WHERE pg_catalog.to_regclass(expected.relation_name) IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'migration_preflight_prerequisite_table_already_exists';
  END IF;
END
$preflight$;

-- Replace the deployed enum transactionally. The legacy
-- submitted_to_exchange value is retained because PostgreSQL enum values and
-- historical financial states must not be silently removed.
ALTER TYPE public.order_status RENAME TO order_status_legacy_20260801000001;

CREATE TYPE public.order_status AS ENUM (
  'draft',
  'pending_qualification',
  'pending_review',
  'auto_approved',
  'approved',
  'rejected',
  'cancelled',
  'submitted_to_exchange'
);

ALTER TABLE public.order_requests
  ALTER COLUMN status DROP DEFAULT,
  ALTER COLUMN status TYPE public.order_status
    USING status::pg_catalog.text::public.order_status,
  ALTER COLUMN status SET DEFAULT 'pending_qualification'::public.order_status;

DROP TYPE public.order_status_legacy_20260801000001;

ALTER TABLE public.profiles
  ADD COLUMN pan_hmac pg_catalog.text,
  ADD COLUMN normalised_phone_hmac pg_catalog.text,
  ADD COLUMN normalised_email_hmac pg_catalog.text,
  ADD COLUMN aadhaar_hmac pg_catalog.text,
  ADD COLUMN identity_match_status pg_catalog.text
    DEFAULT 'unresolved'
    CHECK (
      identity_match_status IN (
        'unresolved',
        'matched',
        'manual_verification_required'
      )
    );

ALTER TABLE public.portfolios
  ADD COLUMN workspace_id pg_catalog.uuid
    REFERENCES public.workspaces(id)
    ON DELETE CASCADE;

UPDATE public.portfolios AS portfolio
SET workspace_id = (
  SELECT membership.workspace_id
  FROM public.workspace_memberships AS membership
  WHERE membership.profile_id = portfolio.client_id
    AND membership.status = 'active'
  ORDER BY membership.created_at, membership.workspace_id
  LIMIT 1
)
WHERE portfolio.workspace_id IS NULL;

UPDATE public.subscription_plans
SET
  client_limit = CASE name
    WHEN 'Starter' THEN 25
    WHEN 'Pro MFD' THEN 999999
    WHEN 'Enterprise Firm' THEN 99999999
  END,
  monthly_price = CASE name
    WHEN 'Starter' THEN 0.00
    WHEN 'Pro MFD' THEN 1500.00
    WHEN 'Enterprise Firm' THEN 5000.00
  END
WHERE name IN ('Starter', 'Pro MFD', 'Enterprise Firm');

CREATE TABLE public.plan_entitlements (
  id pg_catalog.uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id pg_catalog.uuid NOT NULL
    REFERENCES public.subscription_plans(id)
    ON DELETE CASCADE,
  entitlement_key pg_catalog.text NOT NULL,
  entitlement_value pg_catalog.text NOT NULL,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT plan_entitlements_unique
    UNIQUE (plan_id, entitlement_key)
);

INSERT INTO public.plan_entitlements (
  plan_id,
  entitlement_key,
  entitlement_value
)
SELECT
  plan.id,
  entitlement.entitlement_key,
  entitlement.entitlement_value
FROM (
  VALUES
    ('Starter', 'max_active_investors', '25'),
    ('Starter', 'mailbag_ingestion_enabled', 'true'),
    ('Starter', 'auto_approval_enabled', 'false'),
    ('Starter', 'white_label_enabled', 'false'),
    ('Starter', 'crm_enabled', 'false'),
    ('Starter', 'multi_advisor_enabled', 'false'),
    ('Starter', 'family_hub_enabled', 'false'),
    ('Starter', 'capital_gain_projection_enabled', 'false'),
    ('Starter', 'priority_support_enabled', 'false'),
    ('Starter', 'advanced_analytics_enabled', 'false'),
    ('Starter', 'support_sla_policy_id', 'starter-sla'),
    ('Pro MFD', 'max_active_investors', '999999'),
    ('Pro MFD', 'mailbag_ingestion_enabled', 'true'),
    ('Pro MFD', 'auto_approval_enabled', 'true'),
    ('Pro MFD', 'white_label_enabled', 'false'),
    ('Pro MFD', 'crm_enabled', 'true'),
    ('Pro MFD', 'multi_advisor_enabled', 'false'),
    ('Pro MFD', 'family_hub_enabled', 'true'),
    ('Pro MFD', 'capital_gain_projection_enabled', 'true'),
    ('Pro MFD', 'priority_support_enabled', 'false'),
    ('Pro MFD', 'advanced_analytics_enabled', 'true'),
    ('Pro MFD', 'support_sla_policy_id', 'pro-sla'),
    ('Enterprise Firm', 'max_active_investors', '99999999'),
    ('Enterprise Firm', 'mailbag_ingestion_enabled', 'true'),
    ('Enterprise Firm', 'auto_approval_enabled', 'true'),
    ('Enterprise Firm', 'white_label_enabled', 'true'),
    ('Enterprise Firm', 'crm_enabled', 'true'),
    ('Enterprise Firm', 'multi_advisor_enabled', 'true'),
    ('Enterprise Firm', 'family_hub_enabled', 'true'),
    ('Enterprise Firm', 'capital_gain_projection_enabled', 'true'),
    ('Enterprise Firm', 'priority_support_enabled', 'true'),
    ('Enterprise Firm', 'advanced_analytics_enabled', 'true'),
    ('Enterprise Firm', 'support_sla_policy_id', 'enterprise-sla')
) AS entitlement(plan_name, entitlement_key, entitlement_value)
JOIN public.subscription_plans AS plan
  ON plan.name = entitlement.plan_name;

CREATE TABLE public.auto_approval_rules (
  id pg_catalog.uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL
    REFERENCES public.workspaces(id)
    ON DELETE CASCADE,
  transaction_type public.order_type NOT NULL,
  min_amount pg_catalog.numeric(15, 2) CHECK (min_amount >= 0),
  max_amount pg_catalog.numeric(15, 2) CHECK (max_amount > min_amount),
  trusted_client_only pg_catalog.bool NOT NULL DEFAULT false,
  category_restrictions pg_catalog.text[],
  effective_from pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  is_active pg_catalog.bool NOT NULL DEFAULT true,
  rule_version pg_catalog.int4 NOT NULL DEFAULT 1 CHECK (rule_version >= 1),
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now()
);

ALTER TABLE public.order_requests
  RENAME COLUMN investor_id TO investor_profile_id;

ALTER TABLE public.order_requests
  ADD COLUMN triggered_rule_id pg_catalog.uuid
    REFERENCES public.auto_approval_rules(id)
    ON DELETE SET NULL,
  ADD COLUMN triggered_rule_version pg_catalog.int4
    CHECK (triggered_rule_version >= 1),
  ADD COLUMN reviewed_by pg_catalog.uuid
    REFERENCES public.profiles(id)
    ON DELETE SET NULL,
  ADD COLUMN reviewed_at pg_catalog.timestamptz,
  ADD COLUMN rejection_reason pg_catalog.text;

ALTER TABLE public.family_delegations
  RENAME COLUMN owner_investor_id TO owner_profile_id;

ALTER TABLE public.family_delegations
  RENAME COLUMN delegate_investor_id TO delegate_profile_id;

ALTER TABLE public.family_delegations
  DROP CONSTRAINT family_delegations_no_self,
  DROP CONSTRAINT family_delegations_unique,
  ADD COLUMN workspace_id pg_catalog.uuid
    REFERENCES public.workspaces(id)
    ON DELETE CASCADE,
  ADD COLUMN consent_status pg_catalog.text NOT NULL DEFAULT 'pending'
    CHECK (consent_status IN ('pending', 'accepted', 'rejected')),
  ADD COLUMN expires_at pg_catalog.timestamptz,
  ADD CONSTRAINT family_delegations_no_self
    CHECK (owner_profile_id <> delegate_profile_id);

ALTER TABLE public.family_delegations
  ALTER COLUMN workspace_id SET NOT NULL,
  ADD CONSTRAINT family_delegations_unique
    UNIQUE (workspace_id, owner_profile_id, delegate_profile_id);

CREATE TABLE public.workspace_branding (
  id pg_catalog.uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL
    REFERENCES public.workspaces(id)
    ON DELETE CASCADE
    UNIQUE,
  logo_url pg_catalog.text,
  primary_color pg_catalog.text,
  secondary_color pg_catalog.text,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE public.advisor_profiles (
  id pg_catalog.uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id pg_catalog.uuid NOT NULL
    REFERENCES public.profiles(id)
    ON DELETE CASCADE
    UNIQUE,
  arn_number pg_catalog.text NOT NULL,
  euin pg_catalog.text,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE public.advisor_euin_assignments (
  id pg_catalog.uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  advisor_profile_id pg_catalog.uuid NOT NULL
    REFERENCES public.advisor_profiles(id)
    ON DELETE CASCADE,
  euin pg_catalog.text NOT NULL,
  status pg_catalog.text DEFAULT 'active'
    CHECK (status IN ('active', 'inactive')),
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE public.crm_notes (
  id pg_catalog.uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL
    REFERENCES public.workspaces(id)
    ON DELETE CASCADE,
  client_profile_id pg_catalog.uuid NOT NULL
    REFERENCES public.profiles(id)
    ON DELETE CASCADE,
  advisor_profile_id pg_catalog.uuid NOT NULL
    REFERENCES public.profiles(id)
    ON DELETE CASCADE,
  note_text pg_catalog.text NOT NULL,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE OR REPLACE FUNCTION public.has_active_workspace_membership(
  p_workspace_id pg_catalog.uuid
)
RETURNS pg_catalog.bool
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS membership
    WHERE membership.workspace_id = p_workspace_id
      AND membership.profile_id = public.current_user_profile_id()
      AND membership.status = 'active'
  );
$function$;

CREATE OR REPLACE FUNCTION public.has_advisor_membership(
  p_workspace_id pg_catalog.uuid
)
RETURNS pg_catalog.bool
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS membership
    WHERE membership.workspace_id = p_workspace_id
      AND membership.profile_id = public.current_user_profile_id()
      AND membership.role IN ('advisor', 'admin', 'operations')
      AND membership.status = 'active'
  );
$function$;

CREATE OR REPLACE FUNCTION public.has_investor_membership(
  p_workspace_id pg_catalog.uuid
)
RETURNS pg_catalog.bool
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS membership
    WHERE membership.workspace_id = p_workspace_id
      AND membership.profile_id = public.current_user_profile_id()
      AND membership.role = 'investor'
      AND membership.status = 'active'
  );
$function$;

REVOKE ALL ON FUNCTION public.has_active_workspace_membership(pg_catalog.uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_advisor_membership(pg_catalog.uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_investor_membership(pg_catalog.uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_active_workspace_membership(pg_catalog.uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_advisor_membership(pg_catalog.uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_investor_membership(pg_catalog.uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.trigger_order_outbox_event()
RETURNS pg_catalog.trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.event_outbox (event_type, payload, status)
  VALUES (
    'order.created',
    pg_catalog.jsonb_build_object(
      'order_id', NEW.id,
      'workspace_id', NEW.workspace_id,
      'investor_profile_id', NEW.investor_profile_id,
      'scheme_code', NEW.scheme_code,
      'type', NEW.type,
      'amount', NEW.amount,
      'units', NEW.units,
      'status', NEW.status
    ),
    'pending'
  );
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trigger_order_outbox_event() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.log_family_delegation_audit()
RETURNS pg_catalog.trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor_id pg_catalog.uuid := public.current_user_profile_id();
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.workspace_audit_logs (
      workspace_id,
      actor_id,
      action,
      target_type,
      target_id,
      payload
    )
    VALUES (
      NEW.workspace_id,
      v_actor_id,
      'family_delegation.created',
      'family_delegations',
      NEW.id,
      pg_catalog.jsonb_build_object(
        'owner_profile_id', NEW.owner_profile_id,
        'delegate_profile_id', NEW.delegate_profile_id,
        'consent_status', NEW.consent_status,
        'expires_at', NEW.expires_at
      )
    );
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.consent_status IS DISTINCT FROM NEW.consent_status THEN
      INSERT INTO public.workspace_audit_logs (
        workspace_id,
        actor_id,
        action,
        target_type,
        target_id,
        payload
      )
      VALUES (
        NEW.workspace_id,
        v_actor_id,
        'family_delegation.consent_updated',
        'family_delegations',
        NEW.id,
        pg_catalog.jsonb_build_object(
          'owner_profile_id', NEW.owner_profile_id,
          'delegate_profile_id', NEW.delegate_profile_id,
          'consent_status', NEW.consent_status
        )
      );
    END IF;

    IF OLD.is_active AND NOT NEW.is_active THEN
      INSERT INTO public.workspace_audit_logs (
        workspace_id,
        actor_id,
        action,
        target_type,
        target_id,
        payload
      )
      VALUES (
        NEW.workspace_id,
        v_actor_id,
        'family_delegation.revoked',
        'family_delegations',
        NEW.id,
        pg_catalog.jsonb_build_object(
          'owner_profile_id', NEW.owner_profile_id,
          'delegate_profile_id', NEW.delegate_profile_id
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.log_family_delegation_audit()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER log_family_delegation_audit_trg
  AFTER INSERT OR UPDATE ON public.family_delegations
  FOR EACH ROW
  EXECUTE FUNCTION public.log_family_delegation_audit();

ALTER TABLE public.plan_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auto_approval_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_branding ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advisor_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advisor_euin_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS order_requests_investor_select
  ON public.order_requests;
DROP POLICY IF EXISTS order_requests_advisor_select
  ON public.order_requests;
DROP POLICY IF EXISTS order_requests_admin_select
  ON public.order_requests;
DROP POLICY IF EXISTS order_requests_investor_insert
  ON public.order_requests;
DROP POLICY IF EXISTS order_requests_advisor_update
  ON public.order_requests;
DROP POLICY IF EXISTS order_requests_admin_update
  ON public.order_requests;

CREATE POLICY order_requests_investor_select
  ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (
    investor_profile_id = public.current_user_profile_id()
    AND public.has_active_workspace_membership(workspace_id)
  );

CREATE POLICY order_requests_advisor_select
  ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (public.has_advisor_membership(workspace_id));

CREATE POLICY order_requests_admin_select
  ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (public.is_platform_admin());

CREATE POLICY order_requests_investor_insert
  ON public.order_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    investor_profile_id = public.current_user_profile_id()
    AND public.has_investor_membership(workspace_id)
    AND status = 'pending_qualification'::public.order_status
    AND NOT EXISTS (
      SELECT 1
      FROM public.family_delegations AS delegation
      WHERE delegation.delegate_profile_id = public.current_user_profile_id()
        AND delegation.owner_profile_id = investor_profile_id
        AND delegation.workspace_id = workspace_id
        AND delegation.consent_status = 'accepted'
        AND delegation.is_active
    )
  );

CREATE POLICY order_requests_admin_update
  ON public.order_requests
  FOR UPDATE
  TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

REVOKE UPDATE, DELETE ON TABLE public.order_requests FROM authenticated;

DROP POLICY IF EXISTS family_delegations_owner_all
  ON public.family_delegations;
DROP POLICY IF EXISTS family_delegations_delegate_select
  ON public.family_delegations;

CREATE POLICY family_delegations_owner_all
  ON public.family_delegations
  FOR ALL
  TO authenticated
  USING (owner_profile_id = public.current_user_profile_id())
  WITH CHECK (owner_profile_id = public.current_user_profile_id());

CREATE POLICY family_delegations_delegate_select
  ON public.family_delegations
  FOR SELECT
  TO authenticated
  USING (delegate_profile_id = public.current_user_profile_id());

DROP POLICY IF EXISTS family_delegate_read_policy ON public.portfolios;

CREATE POLICY family_delegate_read_policy
  ON public.portfolios
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.family_delegations AS delegation
      WHERE delegation.owner_profile_id = portfolios.client_id
        AND delegation.delegate_profile_id = public.current_user_profile_id()
        AND delegation.workspace_id = portfolios.workspace_id
        AND delegation.consent_status = 'accepted'
        AND delegation.is_active
        AND (
          delegation.expires_at IS NULL
          OR delegation.expires_at > pg_catalog.now()
        )
    )
  );

CREATE POLICY auto_approval_rules_select
  ON public.auto_approval_rules
  FOR SELECT
  TO authenticated
  USING (public.has_active_workspace_membership(workspace_id));

CREATE POLICY auto_approval_rules_admin_all
  ON public.auto_approval_rules
  FOR ALL
  TO authenticated
  USING (
    public.has_advisor_membership(workspace_id)
    OR public.is_platform_admin()
  )
  WITH CHECK (
    public.has_advisor_membership(workspace_id)
    OR public.is_platform_admin()
  );

CREATE POLICY plan_entitlements_select
  ON public.plan_entitlements
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS workspace_billing_select ON public.workspace_billing;
DROP POLICY IF EXISTS workspace_billing_admin_all ON public.workspace_billing;

CREATE POLICY workspace_billing_select
  ON public.workspace_billing
  FOR SELECT
  TO authenticated
  USING (
    public.has_active_workspace_membership(workspace_id)
    OR public.is_platform_admin()
  );

CREATE POLICY workspace_billing_admin_all
  ON public.workspace_billing
  FOR ALL
  TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS payment_events_select ON public.payment_events;

CREATE POLICY payment_events_select
  ON public.payment_events
  FOR SELECT
  TO authenticated
  USING (
    public.has_active_workspace_membership(workspace_id)
    OR public.is_platform_admin()
  );

CREATE POLICY workspace_branding_select
  ON public.workspace_branding
  FOR SELECT
  TO authenticated
  USING (public.has_active_workspace_membership(workspace_id));

CREATE POLICY workspace_branding_advisor_all
  ON public.workspace_branding
  FOR ALL
  TO authenticated
  USING (public.has_advisor_membership(workspace_id))
  WITH CHECK (public.has_advisor_membership(workspace_id));

CREATE POLICY advisor_profiles_read
  ON public.advisor_profiles
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY advisor_profiles_advisor_all
  ON public.advisor_profiles
  FOR ALL
  TO authenticated
  USING (
    profile_id = public.current_user_profile_id()
    OR public.is_platform_admin()
  )
  WITH CHECK (
    profile_id = public.current_user_profile_id()
    OR public.is_platform_admin()
  );

CREATE POLICY advisor_euin_select
  ON public.advisor_euin_assignments
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY crm_notes_select
  ON public.crm_notes
  FOR SELECT
  TO authenticated
  USING (
    public.has_advisor_membership(workspace_id)
    OR client_profile_id = public.current_user_profile_id()
  );

CREATE POLICY crm_notes_insert
  ON public.crm_notes
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.has_advisor_membership(workspace_id)
    AND advisor_profile_id = public.current_user_profile_id()
  );

DROP POLICY IF EXISTS event_outbox_all ON public.event_outbox;

CREATE POLICY event_outbox_all
  ON public.event_outbox
  FOR ALL
  TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

COMMIT;
