-- Issue #40 corrective bridge: make paid/trial Investor subscriptions and
-- time-bounded referral rewards feed one caller-bound feature authorizer.

BEGIN;

CREATE OR REPLACE FUNCTION public.has_investor_entitlement(
  p_entitlement_key pg_catalog.text
)
RETURNS pg_catalog.bool AS $$
DECLARE
  v_profile_id pg_catalog.uuid;
BEGIN
  IF p_entitlement_key IS NULL OR pg_catalog.btrim(p_entitlement_key) = '' THEN
    RETURN false;
  END IF;

  v_profile_id := public.current_user_profile_id();
  IF v_profile_id IS NULL THEN
    RETURN false;
  END IF;

  -- This is an Investor capability boundary. Workspace billing is
  -- intentionally absent: an Investor's MFD membership cannot grant B2C
  -- Premium access.
  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    WHERE profile.id = v_profile_id
      AND profile.role = 'investor'
      AND profile.account_status = 'active'
  ) THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.investor_subscriptions AS subscription
    JOIN public.plan_entitlements AS entitlement
      ON entitlement.plan_id = subscription.plan_id
    WHERE subscription.investor_profile_id = v_profile_id
      AND subscription.status IN ('trialing', 'active')
      AND entitlement.entitlement_key = pg_catalog.btrim(p_entitlement_key)
      AND pg_catalog.lower(entitlement.entitlement_value) = 'true'
  ) OR (
    pg_catalog.btrim(p_entitlement_key) IN (
      'multi_advisor_enabled',
      'family_hub_enabled',
      'capital_gain_projection_enabled',
      'priority_support_enabled',
      'advanced_analytics_enabled'
    )
    AND EXISTS (
      SELECT 1
      FROM public.referral_rewards AS reward
      WHERE reward.profile_id = v_profile_id
        AND reward.reward_type = 'subscription_extension'
        AND reward.status = 'active'
        AND reward.created_at <= pg_catalog.now()
        AND reward.created_at
          + pg_catalog.make_interval(days => reward.duration_days)
          > pg_catalog.now()
    )
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.has_investor_entitlement(pg_catalog.text) IS
  'Caller-bound Investor feature authorization. Paid/trial access follows plan_entitlements; referral Premium access is limited to the BRD Investor feature set and trusted database reward time.';

REVOKE ALL ON FUNCTION public.has_investor_entitlement(pg_catalog.text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_investor_entitlement(pg_catalog.text)
  TO authenticated;

COMMIT;
