-- Test Suite: Browser API privilege contract.
-- Verifies table ACLs separately from RLS policies.

BEGIN;

DO $$
DECLARE
  v_select_tables pg_catalog.text[] := ARRAY[
    'profiles',
    'user_accounts',
    'investor_account_links',
    'portfolios',
    'transactions',
    'mutual_funds'
  ];
  v_select_insert_tables pg_catalog.text[] := ARRAY[
    'workspaces',
    'workspace_invitations'
  ];
  v_select_insert_update_tables pg_catalog.text[] := ARRAY[
    'fund_factsheets',
    'workspace_memberships',
    'advisor_investor_assignments'
  ];
  v_protected_tables pg_catalog.text[] := ARRAY[
    'folio_references',
    'portfolio_folio_references',
    'verification_folio_evidence',
    'folio_grants',
    'verification_request_assignments',
    'folio_submission_tokens',
    'profile_pan_records'
  ];
  v_rls_tables pg_catalog.text[] := ARRAY[
    'profiles',
    'user_accounts',
    'investor_account_links',
    'portfolios',
    'transactions',
    'mutual_funds',
    'fund_factsheets',
    'workspaces',
    'workspace_memberships',
    'advisor_investor_assignments',
    'workspace_invitations',
    'order_requests'
  ];
  v_table pg_catalog.text;
  v_acl pg_catalog.text;
BEGIN
  FOREACH v_table IN ARRAY v_select_tables LOOP
    IF NOT pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'SELECT') THEN
      RAISE EXCEPTION 'browser_api_privilege_contract:authenticated_select_missing:%', v_table;
    END IF;
  END LOOP;

  FOREACH v_table IN ARRAY v_select_insert_tables LOOP
    FOREACH v_acl IN ARRAY ARRAY['SELECT', 'INSERT'] LOOP
      IF NOT pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, v_acl) THEN
        RAISE EXCEPTION 'browser_api_privilege_contract:authenticated_acl_missing:%:%', v_table, v_acl;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH v_table IN ARRAY v_select_insert_update_tables LOOP
    FOREACH v_acl IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE'] LOOP
      IF NOT pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, v_acl) THEN
        RAISE EXCEPTION 'browser_api_privilege_contract:authenticated_acl_missing:%:%', v_table, v_acl;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'SELECT')
     OR NOT pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'INSERT') THEN
    RAISE EXCEPTION 'browser_api_privilege_contract:order_requests_restricted_acl_missing';
  END IF;

  IF pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'DELETE')
     OR pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'TRUNCATE')
     OR pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'REFERENCES')
     OR pg_catalog.has_table_privilege('authenticated', 'public.order_requests', 'TRIGGER') THEN
    RAISE EXCEPTION 'browser_api_privilege_contract:order_requests_unexpected_authenticated_mutation_acl';
  END IF;

  IF pg_catalog.has_table_privilege('anon', 'public.order_requests', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'public.order_requests', 'INSERT')
     OR pg_catalog.has_table_privilege('anon', 'public.order_requests', 'UPDATE')
     OR pg_catalog.has_table_privilege('anon', 'public.order_requests', 'DELETE') THEN
    RAISE EXCEPTION 'browser_api_privilege_contract:order_requests_unexpected_anon_acl';
  END IF;

  FOREACH v_table IN ARRAY v_protected_tables LOOP
    IF pg_catalog.has_table_privilege('authenticated', 'public.' || v_table, 'SELECT') THEN
      RAISE EXCEPTION 'browser_api_privilege_contract:protected_table_authenticated_readable:%', v_table;
    END IF;
  END LOOP;

  FOREACH v_table IN ARRAY (v_select_tables || v_select_insert_tables || v_select_insert_update_tables) LOOP
    IF pg_catalog.has_table_privilege('anon', 'public.' || v_table, 'SELECT')
       OR pg_catalog.has_table_privilege('anon', 'public.' || v_table, 'INSERT')
       OR pg_catalog.has_table_privilege('anon', 'public.' || v_table, 'UPDATE')
       OR pg_catalog.has_table_privilege('anon', 'public.' || v_table, 'DELETE') THEN
      RAISE EXCEPTION 'browser_api_privilege_contract:anon_business_table_acl:%', v_table;
    END IF;
  END LOOP;

  FOREACH v_table IN ARRAY v_rls_tables LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS class
      JOIN pg_catalog.pg_namespace AS namespace
        ON namespace.oid = class.relnamespace
      WHERE namespace.nspname = 'public'
        AND class.relname = v_table
        AND class.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'browser_api_privilege_contract:rls_disabled:%', v_table;
    END IF;
  END LOOP;
END;
$$;

ROLLBACK;
