-- NSEInvest UCC vertical slice: canonical registration inputs, shared
-- integration current state, transactional outbox handoff, and immutable API
-- evidence. This uncommitted forward migration does not seed a fixture,
-- contact NSE, or alter a hosted project.

BEGIN;

CREATE TABLE public.investor_registration_profiles (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  investor_profile_id pg_catalog.uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  legal_name pg_catalog.text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(legal_name)) BETWEEN 1 AND 150),
  legal_first_name pg_catalog.text CHECK (legal_first_name IS NULL OR pg_catalog.length(pg_catalog.btrim(legal_first_name)) BETWEEN 1 AND 70),
  legal_middle_name pg_catalog.text CHECK (legal_middle_name IS NULL OR pg_catalog.length(pg_catalog.btrim(legal_middle_name)) BETWEEN 1 AND 70),
  legal_last_name pg_catalog.text CHECK (legal_last_name IS NULL OR pg_catalog.length(pg_catalog.btrim(legal_last_name)) BETWEEN 1 AND 70),
  investor_kind pg_catalog.text NOT NULL CHECK (investor_kind IN ('individual', 'non_individual')),
  date_of_birth pg_catalog.date,
  incorporation_date pg_catalog.date,
  gender pg_catalog.text CHECK (gender IS NULL OR gender IN ('male', 'female', 'other', 'transgender')),
  residency_status pg_catalog.text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(residency_status)) BETWEEN 1 AND 40),
  occupation pg_catalog.text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(occupation)) BETWEEN 1 AND 100),
  holding_mode pg_catalog.text NOT NULL DEFAULT 'single' CHECK (holding_mode IN ('single', 'joint', 'anyone_or_survivor')),
  pan_exempt pg_catalog.bool NOT NULL DEFAULT false,
  kyc_method pg_catalog.text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(kyc_method)) BETWEEN 1 AND 32),
  ckyc_number pg_catalog.text CHECK (ckyc_number IS NULL OR pg_catalog.length(pg_catalog.btrim(ckyc_number)) BETWEEN 1 AND 14),
  kyc_verified_at pg_catalog.timestamptz,
  communication_preference pg_catalog.text NOT NULL DEFAULT 'electronic' CHECK (communication_preference IN ('physical', 'electronic', 'mobile')),
  mobile_owner_relationship pg_catalog.text NOT NULL DEFAULT 'self' CHECK (pg_catalog.length(pg_catalog.btrim(mobile_owner_relationship)) BETWEEN 1 AND 40),
  email_owner_relationship pg_catalog.text NOT NULL DEFAULT 'self' CHECK (pg_catalog.length(pg_catalog.btrim(email_owner_relationship)) BETWEEN 1 AND 40),
  onboarding_mode pg_catalog.text NOT NULL DEFAULT 'paper' CHECK (onboarding_mode IN ('paper', 'paperless')),
  nomination_opted_in pg_catalog.bool NOT NULL DEFAULT false,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT investor_registration_profiles_scope_unique UNIQUE (workspace_id, investor_profile_id),
  CONSTRAINT investor_registration_profiles_entity_date_check CHECK (
    (investor_kind = 'individual' AND date_of_birth IS NOT NULL AND incorporation_date IS NULL)
    OR
    (investor_kind = 'non_individual' AND date_of_birth IS NULL AND incorporation_date IS NOT NULL)
  )
);

CREATE TABLE public.investor_addresses (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  investor_profile_id pg_catalog.uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  address_type pg_catalog.text NOT NULL DEFAULT 'domestic' CHECK (address_type IN ('domestic', 'foreign')),
  address_line_1 pg_catalog.text NOT NULL,
  address_line_2 pg_catalog.text,
  address_line_3 pg_catalog.text,
  city pg_catalog.text NOT NULL,
  region pg_catalog.text NOT NULL,
  postal_code pg_catalog.text NOT NULL,
  country pg_catalog.text NOT NULL,
  is_current pg_catalog.bool NOT NULL DEFAULT true,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT investor_addresses_nonblank CHECK (
    pg_catalog.btrim(address_line_1) <> '' AND pg_catalog.btrim(city) <> ''
    AND pg_catalog.btrim(region) <> '' AND pg_catalog.btrim(postal_code) <> ''
    AND pg_catalog.btrim(country) <> ''
  )
);

CREATE UNIQUE INDEX investor_addresses_one_current_type_idx
  ON public.investor_addresses (workspace_id, investor_profile_id, address_type)
  WHERE is_current;

CREATE OR REPLACE FUNCTION public.bank_account_encryption_key(p_key_reference pg_catalog.text)
RETURNS pg_catalog.text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_secret pg_catalog.text;
BEGIN
  IF p_key_reference <> 'bank_account_encryption_key_v1' THEN
    RAISE EXCEPTION 'bank_account_encryption_key_reference_unsupported';
  END IF;
  SELECT secret.decrypted_secret INTO v_secret FROM vault.decrypted_secrets AS secret
  WHERE secret.name = p_key_reference LIMIT 1;
  IF v_secret IS NULL OR pg_catalog.length(v_secret) < 32 THEN
    RAISE EXCEPTION 'bank_account_encryption_configuration_unavailable';
  END IF;
  RETURN v_secret;
END;
$$;

CREATE OR REPLACE FUNCTION public.bank_account_lookup_hmac_key(p_key_reference pg_catalog.text)
RETURNS pg_catalog.text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_secret pg_catalog.text;
BEGIN
  IF p_key_reference <> 'bank_account_lookup_hmac_key_v1' THEN
    RAISE EXCEPTION 'bank_account_lookup_key_reference_unsupported';
  END IF;
  SELECT secret.decrypted_secret INTO v_secret FROM vault.decrypted_secrets AS secret
  WHERE secret.name = p_key_reference LIMIT 1;
  IF v_secret IS NULL OR pg_catalog.length(v_secret) < 32 THEN
    RAISE EXCEPTION 'bank_account_lookup_configuration_unavailable';
  END IF;
  RETURN v_secret;
END;
$$;

CREATE TABLE public.investor_bank_accounts (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  investor_profile_id pg_catalog.uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  account_type pg_catalog.text NOT NULL CHECK (account_type IN ('savings', 'current', 'nre', 'nro')),
  account_number_ciphertext pg_catalog.bytea NOT NULL,
  account_number_key_reference pg_catalog.text NOT NULL,
  account_number_key_version pg_catalog.int4 NOT NULL CHECK (account_number_key_version > 0),
  account_number_lookup_hmac pg_catalog.bytea NOT NULL,
  lookup_hmac_key_reference pg_catalog.text NOT NULL,
  lookup_hmac_key_version pg_catalog.int4 NOT NULL CHECK (lookup_hmac_key_version > 0),
  masked_account_number pg_catalog.text NOT NULL,
  ifsc_code pg_catalog.text NOT NULL CHECK (ifsc_code ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  micr_code pg_catalog.text CHECK (micr_code IS NULL OR micr_code ~ '^[0-9]{9}$'),
  account_holder_name pg_catalog.text,
  verification_status pg_catalog.text NOT NULL DEFAULT 'unverified' CHECK (verification_status IN ('unverified', 'verified', 'rejected')),
  verified_at pg_catalog.timestamptz,
  is_default pg_catalog.bool NOT NULL DEFAULT false,
  is_active pg_catalog.bool NOT NULL DEFAULT true,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT investor_bank_accounts_scope_hmac_unique UNIQUE (
    workspace_id, investor_profile_id, lookup_hmac_key_reference, account_number_lookup_hmac
  ),
  CONSTRAINT investor_bank_accounts_verified_at_check CHECK ((verification_status = 'verified') = (verified_at IS NOT NULL))
);

CREATE UNIQUE INDEX investor_bank_accounts_one_default_idx
  ON public.investor_bank_accounts (workspace_id, investor_profile_id)
  WHERE is_default AND is_active;

CREATE TABLE public.integration_accounts (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  investor_profile_id pg_catalog.uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  integration_key pg_catalog.text NOT NULL CHECK (integration_key ~ '^[A-Z][A-Z0-9_]{1,31}$'),
  integration_environment pg_catalog.text NOT NULL CHECK (integration_environment IN ('UAT', 'PRODUCTION')),
  external_account_id pg_catalog.text,
  state pg_catalog.text NOT NULL DEFAULT 'NOT_REGISTERED' CHECK (state IN (
    'NOT_REGISTERED', 'REGISTRATION_PENDING', 'REGISTERED', 'VALIDATION_FAILED',
    'REGISTRATION_FAILED', 'RECONCILIATION_REQUIRED'
  )),
  current_registration_status pg_catalog.text,
  integration_metadata pg_catalog.jsonb NOT NULL DEFAULT '{}'::pg_catalog.jsonb CHECK (pg_catalog.jsonb_typeof(integration_metadata) = 'object'),
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT integration_accounts_scope_unique UNIQUE (
    workspace_id, investor_profile_id, integration_key, integration_environment
  )
);

CREATE UNIQUE INDEX integration_accounts_external_account_id_idx
  ON public.integration_accounts (workspace_id, integration_key, integration_environment, external_account_id)
  WHERE external_account_id IS NOT NULL;

CREATE UNIQUE INDEX integration_accounts_nse_uat_candidate_idx
  ON public.integration_accounts (
    workspace_id, integration_key, integration_environment,
    pg_catalog.upper(pg_catalog.btrim(integration_metadata->>'external_account_candidate'))
  )
  WHERE integration_key = 'NSE_INVEST'
    AND integration_environment = 'UAT'
    AND NULLIF(pg_catalog.btrim(integration_metadata->>'external_account_candidate'), '') IS NOT NULL;

CREATE TABLE public.integration_operations (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  integration_account_id pg_catalog.uuid NOT NULL REFERENCES public.integration_accounts(id) ON DELETE RESTRICT,
  integration_key pg_catalog.text NOT NULL CHECK (integration_key ~ '^[A-Z][A-Z0-9_]{1,31}$'),
  integration_environment pg_catalog.text NOT NULL CHECK (integration_environment IN ('UAT', 'PRODUCTION')),
  category pg_catalog.text NOT NULL CHECK (category IN (
    'REFERENCE_DATA', 'CLIENT', 'KYC_COMPLIANCE', 'AUTHORIZATION', 'TRANSACTION',
    'PAYMENT', 'MANDATE', 'SYSTEMATIC', 'RECONCILIATION', 'COMMUNICATION'
  )),
  safety_class pg_catalog.text NOT NULL CHECK (safety_class IN (
    'READ_ONLY', 'WRITE_CLIENT', 'WRITE_ORDER', 'WRITE_SYSTEMATIC',
    'WRITE_MANDATE', 'CANCEL', 'PAYMENT', 'COMMUNICATION',
    'SECURITY_CREDENTIAL_CHANGE', 'OTHER_MUTATING', 'UNKNOWN'
  )),
  operation_type pg_catalog.text NOT NULL,
  operation_purpose pg_catalog.text,
  api_key pg_catalog.text NOT NULL,
  contract_version pg_catalog.text NOT NULL,
  state pg_catalog.text NOT NULL CHECK (state IN (
    'PREPARED', 'QUEUED', 'SUBMITTING', 'SUCCESS', 'VALIDATION_FAILED',
    'BUSINESS_FAILED', 'HTTP_FAILED', 'SUBMISSION_FAILED', 'RECONCILIATION_REQUIRED'
  )),
  native_business_status pg_catalog.text,
  business_remark_category pg_catalog.text,
  correlation_id pg_catalog.uuid NOT NULL DEFAULT pg_catalog.gen_random_uuid(),
  attempt_count pg_catalog.int4 NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  retry_allowed pg_catalog.bool NOT NULL DEFAULT false,
  ambiguous_outcome pg_catalog.bool NOT NULL DEFAULT false,
  reconciliation_required pg_catalog.bool NOT NULL DEFAULT false,
  submitted_at pg_catalog.timestamptz,
  completed_at pg_catalog.timestamptz,
  reconciliation_target_operation_id pg_catalog.uuid REFERENCES public.integration_operations(id) ON DELETE RESTRICT,
  reconciliation_resolution_operation_id pg_catalog.uuid REFERENCES public.integration_operations(id) ON DELETE RESTRICT,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT integration_operations_correlation_unique UNIQUE (correlation_id),
  CONSTRAINT integration_operations_reconciliation_check CHECK (
    (state = 'RECONCILIATION_REQUIRED') = reconciliation_required
  ),
  CONSTRAINT integration_operations_ambiguous_check CHECK (
    NOT ambiguous_outcome OR reconciliation_required
  ),
  CONSTRAINT integration_operations_retry_check CHECK (
    NOT retry_allowed OR state = 'SUBMISSION_FAILED'
  )
);

CREATE UNIQUE INDEX integration_operations_one_active_ucc_idx
  ON public.integration_operations (integration_account_id, operation_type)
  WHERE operation_type = 'UCC_REGISTRATION'
    AND (
      state IN ('PREPARED', 'QUEUED', 'SUBMITTING', 'RECONCILIATION_REQUIRED')
      OR (state = 'SUBMISSION_FAILED' AND retry_allowed)
    );

CREATE UNIQUE INDEX integration_operations_one_active_ucc_verification_idx
  ON public.integration_operations (reconciliation_target_operation_id)
  WHERE operation_type = 'UCC_VERIFICATION'
    AND (
      state IN ('PREPARED', 'QUEUED', 'SUBMITTING')
      OR (state = 'SUBMISSION_FAILED' AND retry_allowed)
    );

CREATE OR REPLACE FUNCTION public.integration_payload_encryption_key(p_key_reference pg_catalog.text)
RETURNS pg_catalog.text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_secret pg_catalog.text;
BEGIN
  IF p_key_reference <> 'integration_payload_encryption_key_v1' THEN
    RAISE EXCEPTION 'integration_payload_key_reference_unsupported';
  END IF;
  SELECT secret.decrypted_secret INTO v_secret FROM vault.decrypted_secrets AS secret
  WHERE secret.name = p_key_reference LIMIT 1;
  IF v_secret IS NULL OR pg_catalog.length(v_secret) < 32 THEN
    RAISE EXCEPTION 'integration_payload_encryption_configuration_unavailable';
  END IF;
  RETURN v_secret;
END;
$$;

CREATE OR REPLACE FUNCTION public.integration_payload_has_forbidden_key(p_payload pg_catalog.jsonb)
RETURNS pg_catalog.bool LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE
  v_key pg_catalog.text;
  v_value pg_catalog.jsonb;
  v_normalized_key pg_catalog.text;
BEGIN
  IF p_payload IS NULL THEN RETURN false; END IF;
  IF pg_catalog.jsonb_typeof(p_payload) = 'object' THEN
    FOR v_key, v_value IN SELECT key, value FROM pg_catalog.jsonb_each(p_payload)
    LOOP
      v_normalized_key := pg_catalog.lower(pg_catalog.regexp_replace(v_key, '[^a-zA-Z0-9]', '', 'g'));
      IF v_normalized_key = ANY (ARRAY[
        'authorization', 'cookie', 'setcookie', 'apikey', 'apisecret',
        'apikeymember', 'apisecretuser', 'encryptedpassword', 'password',
        'clientsecret', 'accesstoken', 'refreshtoken', 'sessiontoken'
      ]::pg_catalog.text[]) THEN RETURN true; END IF;
      IF public.integration_payload_has_forbidden_key(v_value) THEN RETURN true; END IF;
    END LOOP;
  ELSIF pg_catalog.jsonb_typeof(p_payload) = 'array' THEN
    FOR v_value IN SELECT value FROM pg_catalog.jsonb_array_elements(p_payload)
    LOOP
      IF public.integration_payload_has_forbidden_key(v_value) THEN RETURN true; END IF;
    END LOOP;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.integration_header_metadata_is_safe(
  p_metadata pg_catalog.jsonb,
  p_phase pg_catalog.text
)
RETURNS pg_catalog.bool LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE
  v_key pg_catalog.text;
  v_value pg_catalog.jsonb;
  v_allowed pg_catalog.text[];
BEGIN
  IF p_metadata IS NULL OR pg_catalog.jsonb_typeof(p_metadata) <> 'object' THEN RETURN false; END IF;
  IF public.integration_payload_has_forbidden_key(p_metadata) THEN RETURN false; END IF;
  v_allowed := CASE p_phase
    WHEN 'REQUEST' THEN ARRAY['content_type', 'user_agent', 'accept']::pg_catalog.text[]
    WHEN 'RESULT' THEN ARRAY['content_type', 'x_request_id', 'x_correlation_id']::pg_catalog.text[]
    ELSE ARRAY[]::pg_catalog.text[]
  END;
  FOR v_key, v_value IN SELECT key, value FROM pg_catalog.jsonb_each(p_metadata)
  LOOP
    IF NOT (v_key = ANY(v_allowed))
       OR pg_catalog.jsonb_typeof(v_value) <> 'string'
       OR pg_catalog.length(v_value #>> '{}') > 512 THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN p_phase IN ('REQUEST', 'RESULT');
END;
$$;

CREATE TABLE public.integration_api_interactions (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  workspace_id pg_catalog.uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  integration_operation_id pg_catalog.uuid REFERENCES public.integration_operations(id) ON DELETE RESTRICT,
  integration_key pg_catalog.text NOT NULL,
  integration_environment pg_catalog.text NOT NULL,
  category pg_catalog.text NOT NULL,
  safety_class pg_catalog.text NOT NULL,
  operation_type pg_catalog.text NOT NULL,
  api_key pg_catalog.text NOT NULL,
  contract_version pg_catalog.text NOT NULL,
  endpoint_path pg_catalog.text NOT NULL CHECK (endpoint_path LIKE '/%'),
  http_method pg_catalog.text NOT NULL CHECK (http_method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE')),
  call_id pg_catalog.uuid NOT NULL,
  phase pg_catalog.text NOT NULL CHECK (phase IN ('REQUEST', 'RESULT')),
  attempt_number pg_catalog.int4 NOT NULL CHECK (attempt_number > 0),
  correlation_id pg_catalog.uuid NOT NULL,
  payload_encryption_key_reference pg_catalog.text NOT NULL,
  payload_encryption_key_version pg_catalog.int4 NOT NULL CHECK (payload_encryption_key_version > 0),
  request_payload_ciphertext pg_catalog.bytea,
  request_header_metadata pg_catalog.jsonb,
  request_content_type pg_catalog.text,
  request_bytes pg_catalog.int8,
  request_hash pg_catalog.bytea,
  started_at pg_catalog.timestamptz NOT NULL,
  response_payload_ciphertext pg_catalog.bytea,
  response_header_metadata pg_catalog.jsonb,
  response_content_type pg_catalog.text,
  response_bytes pg_catalog.int8,
  response_hash pg_catalog.bytea,
  response_identity_hash pg_catalog.bytea,
  http_status pg_catalog.int4 CHECK (http_status BETWEEN 100 AND 599),
  http_success pg_catalog.bool,
  completed_at pg_catalog.timestamptz,
  elapsed_ms pg_catalog.int8 CHECK (elapsed_ms IS NULL OR elapsed_ms >= 0),
  native_status_field pg_catalog.text,
  native_status_value pg_catalog.text,
  native_remark_field pg_catalog.text,
  native_remark_category pg_catalog.text,
  normalized_outcome pg_catalog.text NOT NULL CHECK (normalized_outcome IN (
    'REQUEST_RECORDED', 'SUCCESS', 'BUSINESS_FAILURE', 'HTTP_FAILURE',
    'PRE_TRANSMISSION_FAILURE', 'TRANSPORT_FAILURE', 'AMBIGUOUS'
  )),
  error_category pg_catalog.text,
  timeout_occurred pg_catalog.bool NOT NULL DEFAULT false,
  network_failure pg_catalog.bool NOT NULL DEFAULT false,
  ambiguous_outcome pg_catalog.bool NOT NULL DEFAULT false,
  reconciliation_required pg_catalog.bool NOT NULL DEFAULT false,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT integration_api_interactions_call_phase_unique UNIQUE (call_id, phase),
  CONSTRAINT integration_api_interactions_payload_phase_check CHECK (
    (
      phase = 'REQUEST'
      AND request_payload_ciphertext IS NOT NULL AND request_hash IS NOT NULL AND request_bytes IS NOT NULL
      AND request_header_metadata IS NOT NULL
      AND public.integration_header_metadata_is_safe(request_header_metadata, 'REQUEST')
      AND response_payload_ciphertext IS NULL AND response_header_metadata IS NULL
      AND completed_at IS NULL AND normalized_outcome = 'REQUEST_RECORDED'
    ) OR (
      phase = 'RESULT'
      AND request_payload_ciphertext IS NULL AND request_header_metadata IS NULL
      AND response_payload_ciphertext IS NOT NULL AND response_hash IS NOT NULL AND response_bytes IS NOT NULL
      AND response_header_metadata IS NOT NULL
      AND public.integration_header_metadata_is_safe(response_header_metadata, 'RESULT')
      AND completed_at IS NOT NULL AND normalized_outcome <> 'REQUEST_RECORDED'
    )
  ),
  CONSTRAINT integration_api_interactions_ambiguous_check CHECK (
    (NOT ambiguous_outcome OR reconciliation_required)
    AND (NOT ambiguous_outcome OR normalized_outcome = 'AMBIGUOUS')
  )
);

CREATE INDEX integration_api_interactions_operation_idx
  ON public.integration_api_interactions (integration_operation_id, created_at, id);
CREATE INDEX integration_api_interactions_correlation_idx
  ON public.integration_api_interactions (correlation_id, created_at, id);

ALTER TABLE public.integration_operations
  ADD COLUMN last_interaction_id pg_catalog.uuid REFERENCES public.integration_api_interactions(id) ON DELETE RESTRICT;
ALTER TABLE public.integration_accounts
  ADD COLUMN current_operation_id pg_catalog.uuid REFERENCES public.integration_operations(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.reject_integration_api_interaction_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  RAISE EXCEPTION 'integration_api_interactions_append_only';
END;
$$;

CREATE TRIGGER integration_api_interactions_append_only
  BEFORE UPDATE OR DELETE ON public.integration_api_interactions
  FOR EACH ROW EXECUTE FUNCTION public.reject_integration_api_interaction_mutation();

CREATE OR REPLACE FUNCTION public.validate_integration_operation_scope()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.integration_accounts account
    WHERE account.id = NEW.integration_account_id
      AND account.workspace_id = NEW.workspace_id
      AND account.integration_key = NEW.integration_key
      AND account.integration_environment = NEW.integration_environment
  ) THEN RAISE EXCEPTION 'integration_operation_scope_mismatch'; END IF;
  IF NEW.operation_type = 'UCC_VERIFICATION' THEN
    IF NEW.category <> 'RECONCILIATION' OR NEW.safety_class <> 'READ_ONLY'
       OR NEW.api_key <> 'CLIENT_MASTER_REPORT'
       OR NEW.operation_purpose NOT IN (
         'POST_REGISTRATION_VERIFICATION', 'AMBIGUOUS_WRITE_RECONCILIATION'
       )
       OR NEW.reconciliation_target_operation_id IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM public.integration_operations target
         WHERE target.id = NEW.reconciliation_target_operation_id
           AND target.workspace_id = NEW.workspace_id
           AND target.integration_account_id = NEW.integration_account_id
           AND target.integration_key = NEW.integration_key
           AND target.integration_environment = NEW.integration_environment
           AND target.operation_type = 'UCC_REGISTRATION'
           AND target.api_key = 'CLIENTCOMMON183'
       ) THEN RAISE EXCEPTION 'integration_reconciliation_target_mismatch'; END IF;
  ELSIF NEW.reconciliation_target_operation_id IS NOT NULL
        OR NEW.operation_purpose IS NOT NULL THEN
    RAISE EXCEPTION 'integration_reconciliation_target_unexpected';
  END IF;
  IF NEW.reconciliation_resolution_operation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.integration_operations resolution
    WHERE resolution.id = NEW.reconciliation_resolution_operation_id
      AND resolution.reconciliation_target_operation_id = NEW.id
      AND resolution.workspace_id = NEW.workspace_id
      AND resolution.integration_account_id = NEW.integration_account_id
      AND resolution.integration_key = NEW.integration_key
      AND resolution.integration_environment = NEW.integration_environment
      AND resolution.operation_type = 'UCC_VERIFICATION'
  ) THEN RAISE EXCEPTION 'integration_reconciliation_resolution_mismatch'; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER integration_operation_scope
  BEFORE INSERT OR UPDATE ON public.integration_operations
  FOR EACH ROW EXECUTE FUNCTION public.validate_integration_operation_scope();

CREATE OR REPLACE FUNCTION public.validate_integration_interaction_scope()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.integration_operation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.integration_operations operation
    WHERE operation.id = NEW.integration_operation_id
      AND operation.workspace_id = NEW.workspace_id
      AND operation.integration_key = NEW.integration_key
      AND operation.integration_environment = NEW.integration_environment
      AND operation.category = NEW.category
      AND operation.safety_class = NEW.safety_class
      AND operation.operation_type = NEW.operation_type
      AND operation.api_key = NEW.api_key
      AND operation.contract_version = NEW.contract_version
      AND operation.correlation_id = NEW.correlation_id
  ) THEN RAISE EXCEPTION 'integration_interaction_scope_mismatch'; END IF;
  IF NEW.phase = 'RESULT' AND NOT EXISTS (
    SELECT 1 FROM public.integration_api_interactions request
    WHERE request.call_id = NEW.call_id AND request.phase = 'REQUEST'
      AND request.integration_operation_id IS NOT DISTINCT FROM NEW.integration_operation_id
      AND request.workspace_id = NEW.workspace_id
      AND request.integration_key = NEW.integration_key
      AND request.integration_environment = NEW.integration_environment
      AND request.category = NEW.category AND request.safety_class = NEW.safety_class
      AND request.operation_type = NEW.operation_type AND request.api_key = NEW.api_key
      AND request.contract_version = NEW.contract_version
      AND request.endpoint_path = NEW.endpoint_path AND request.http_method = NEW.http_method
      AND request.attempt_number = NEW.attempt_number
      AND request.correlation_id = NEW.correlation_id
      AND request.started_at = NEW.started_at
  ) THEN RAISE EXCEPTION 'integration_interaction_request_result_mismatch'; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER integration_interaction_scope
  BEFORE INSERT ON public.integration_api_interactions
  FOR EACH ROW EXECUTE FUNCTION public.validate_integration_interaction_scope();

CREATE OR REPLACE FUNCTION public.validate_integration_account_current_operation()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.current_operation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.integration_operations operation
    WHERE operation.id = NEW.current_operation_id
      AND operation.integration_account_id = NEW.id
      AND operation.workspace_id = NEW.workspace_id
      AND operation.integration_key = NEW.integration_key
      AND operation.integration_environment = NEW.integration_environment
  ) THEN RAISE EXCEPTION 'integration_account_current_operation_mismatch'; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER integration_account_current_operation_scope
  BEFORE INSERT OR UPDATE ON public.integration_accounts
  FOR EACH ROW EXECUTE FUNCTION public.validate_integration_account_current_operation();

CREATE OR REPLACE FUNCTION public.enforce_integration_operation_transition()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
     OR NEW.integration_account_id IS DISTINCT FROM OLD.integration_account_id
     OR NEW.integration_key IS DISTINCT FROM OLD.integration_key
     OR NEW.integration_environment IS DISTINCT FROM OLD.integration_environment
     OR NEW.category IS DISTINCT FROM OLD.category
     OR NEW.safety_class IS DISTINCT FROM OLD.safety_class
     OR NEW.operation_type IS DISTINCT FROM OLD.operation_type
     OR NEW.operation_purpose IS DISTINCT FROM OLD.operation_purpose
     OR NEW.api_key IS DISTINCT FROM OLD.api_key
     OR NEW.contract_version IS DISTINCT FROM OLD.contract_version
     OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
     OR NEW.reconciliation_target_operation_id IS DISTINCT FROM OLD.reconciliation_target_operation_id
     OR (
       NEW.reconciliation_resolution_operation_id IS DISTINCT FROM OLD.reconciliation_resolution_operation_id
       AND NOT (
         OLD.reconciliation_resolution_operation_id IS NULL
         AND NEW.reconciliation_resolution_operation_id IS NOT NULL
         AND OLD.state = 'RECONCILIATION_REQUIRED'
         AND NEW.state = 'SUCCESS'
       )
     )
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'integration_operation_identity_immutable';
  END IF;
  IF NEW.last_interaction_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.integration_api_interactions interaction
    WHERE interaction.id = NEW.last_interaction_id
      AND interaction.integration_operation_id = NEW.id
  ) THEN RAISE EXCEPTION 'integration_operation_interaction_mismatch'; END IF;
  IF NEW.state IS DISTINCT FROM OLD.state AND NOT (
    (OLD.state = 'PREPARED' AND NEW.state = 'QUEUED')
    OR (OLD.state IN ('QUEUED', 'SUBMISSION_FAILED') AND NEW.state = 'SUBMITTING')
    OR (OLD.state IN ('QUEUED', 'SUBMISSION_FAILED') AND NEW.state IN ('VALIDATION_FAILED', 'SUBMISSION_FAILED'))
    OR (OLD.state = 'SUBMITTING' AND NEW.state IN (
      'SUCCESS', 'BUSINESS_FAILED', 'HTTP_FAILED', 'SUBMISSION_FAILED', 'RECONCILIATION_REQUIRED'
    ))
    OR (
      OLD.state = 'RECONCILIATION_REQUIRED' AND NEW.state = 'SUCCESS'
      AND NEW.reconciliation_resolution_operation_id IS NOT NULL
      AND public.nse_ucc_verification_evidence_matches(
        OLD.id, NEW.reconciliation_resolution_operation_id
      )
    )
  ) THEN RAISE EXCEPTION 'invalid_integration_operation_transition'; END IF;
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_integration_operation_transition
  BEFORE UPDATE ON public.integration_operations
  FOR EACH ROW EXECUTE FUNCTION public.enforce_integration_operation_transition();

CREATE OR REPLACE FUNCTION public.set_investor_bank_account(
  p_workspace_id pg_catalog.uuid,
  p_investor_profile_id pg_catalog.uuid,
  p_account_type pg_catalog.text,
  p_account_number pg_catalog.text,
  p_ifsc_code pg_catalog.text,
  p_micr_code pg_catalog.text DEFAULT NULL,
  p_account_holder_name pg_catalog.text DEFAULT NULL,
  p_verification_status pg_catalog.text DEFAULT 'unverified',
  p_is_default pg_catalog.bool DEFAULT true
)
RETURNS public.investor_bank_accounts
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_account pg_catalog.text := pg_catalog.upper(pg_catalog.regexp_replace(pg_catalog.btrim(COALESCE(p_account_number, '')), '[[:space:]-]', '', 'g'));
  v_ifsc pg_catalog.text := pg_catalog.upper(pg_catalog.btrim(COALESCE(p_ifsc_code, '')));
  v_micr pg_catalog.text := NULLIF(pg_catalog.btrim(COALESCE(p_micr_code, '')), '');
  v_encryption_key_reference pg_catalog.text := 'bank_account_encryption_key_v1';
  v_lookup_key_reference pg_catalog.text := 'bank_account_lookup_hmac_key_v1';
  v_lookup_hmac pg_catalog.bytea;
  v_row public.investor_bank_accounts;
BEGIN
  IF v_account !~ '^[A-Z0-9]{1,40}$' THEN RAISE EXCEPTION 'invalid_bank_account_number'; END IF;
  IF v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$' THEN RAISE EXCEPTION 'invalid_ifsc_code'; END IF;
  IF v_micr IS NOT NULL AND v_micr !~ '^[0-9]{9}$' THEN RAISE EXCEPTION 'invalid_micr_code'; END IF;
  IF p_account_type NOT IN ('savings', 'current', 'nre', 'nro') THEN RAISE EXCEPTION 'invalid_bank_account_type'; END IF;
  IF p_verification_status NOT IN ('unverified', 'verified', 'rejected') THEN RAISE EXCEPTION 'invalid_bank_verification_status'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_memberships membership
    WHERE membership.workspace_id = p_workspace_id
      AND membership.profile_id = p_investor_profile_id
      AND membership.status = 'active'
  ) THEN RAISE EXCEPTION 'investor_workspace_membership_required'; END IF;

  v_lookup_hmac := extensions.hmac(
    v_account,
    public.bank_account_lookup_hmac_key(v_lookup_key_reference),
    'sha256'
  );

  IF COALESCE(p_is_default, false) THEN
    UPDATE public.investor_bank_accounts
    SET is_default = false, updated_at = pg_catalog.now()
    WHERE workspace_id = p_workspace_id AND investor_profile_id = p_investor_profile_id
      AND is_default AND is_active;
  END IF;

  INSERT INTO public.investor_bank_accounts (
    workspace_id, investor_profile_id, account_type, account_number_ciphertext,
    account_number_key_reference, account_number_key_version,
    account_number_lookup_hmac, lookup_hmac_key_reference, lookup_hmac_key_version,
    masked_account_number, ifsc_code, micr_code, account_holder_name,
    verification_status, verified_at, is_default
  ) VALUES (
    p_workspace_id, p_investor_profile_id, p_account_type,
    extensions.pgp_sym_encrypt(
      v_account,
      public.bank_account_encryption_key(v_encryption_key_reference),
      'cipher-algo=aes256, compress-algo=0'
    ),
    v_encryption_key_reference, 1, v_lookup_hmac, v_lookup_key_reference, 1,
    '******' || pg_catalog.right(v_account, 4), v_ifsc, v_micr,
    NULLIF(pg_catalog.btrim(p_account_holder_name), ''), p_verification_status,
    CASE WHEN p_verification_status = 'verified' THEN pg_catalog.now() ELSE NULL END,
    COALESCE(p_is_default, false)
  )
  ON CONFLICT (workspace_id, investor_profile_id, lookup_hmac_key_reference, account_number_lookup_hmac)
  DO UPDATE SET
    account_type = EXCLUDED.account_type,
    account_number_ciphertext = EXCLUDED.account_number_ciphertext,
    account_number_key_reference = EXCLUDED.account_number_key_reference,
    account_number_key_version = EXCLUDED.account_number_key_version,
    masked_account_number = EXCLUDED.masked_account_number,
    ifsc_code = EXCLUDED.ifsc_code,
    micr_code = EXCLUDED.micr_code,
    account_holder_name = EXCLUDED.account_holder_name,
    verification_status = EXCLUDED.verification_status,
    verified_at = EXCLUDED.verified_at,
    is_default = EXCLUDED.is_default,
    is_active = true,
    updated_at = pg_catalog.now()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

CREATE UNIQUE INDEX event_outbox_one_ucc_registration_idx
  ON public.event_outbox (entity_type, entity_id, event_type)
  WHERE event_type = 'integration.nse.ucc_registration_requested'
    AND entity_type = 'integration_operation'
    AND status IN ('pending', 'processing', 'failed');

CREATE OR REPLACE FUNCTION public.prepare_nse_ucc_registration(
  p_workspace_id pg_catalog.uuid,
  p_investor_profile_id pg_catalog.uuid,
  p_integration_metadata pg_catalog.jsonb
)
RETURNS public.integration_operations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_account public.integration_accounts;
  v_operation public.integration_operations;
BEGIN
  IF p_integration_metadata IS NULL OR pg_catalog.jsonb_typeof(p_integration_metadata) <> 'object'
     OR public.integration_payload_has_forbidden_key(p_integration_metadata) THEN
    RAISE EXCEPTION 'invalid_integration_metadata';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.jsonb_object_keys(p_integration_metadata) AS metadata_key(key_name)
    WHERE metadata_key.key_name NOT IN ('external_account_candidate', 'ucc_mode', 'nse_codes')
  ) THEN RAISE EXCEPTION 'invalid_integration_metadata'; END IF;
  IF p_integration_metadata->>'ucc_mode' <> 'physical' THEN
    RAISE EXCEPTION 'first_slice_requires_physical';
  END IF;
  IF p_integration_metadata->'nse_codes' IS NULL
     OR pg_catalog.jsonb_typeof(p_integration_metadata->'nse_codes') <> 'object' THEN
    RAISE EXCEPTION 'invalid_integration_metadata';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.jsonb_object_keys(p_integration_metadata->'nse_codes') AS code_key(key_name)
    WHERE code_key.key_name NOT IN (
      'tax_status', 'occupation_code', 'state', 'country',
      'mobile_declaration_flag', 'email_declaration_flag', 'div_pay_mode'
    )
  ) THEN RAISE EXCEPTION 'invalid_integration_metadata'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.unnest(ARRAY[
      'tax_status', 'occupation_code', 'state', 'country',
      'mobile_declaration_flag', 'email_declaration_flag', 'div_pay_mode'
    ]::pg_catalog.text[]) AS required_code(key_name)
    WHERE NOT (p_integration_metadata->'nse_codes' ? required_code.key_name)
       OR pg_catalog.jsonb_typeof(p_integration_metadata->'nse_codes'->required_code.key_name) <> 'string'
       OR pg_catalog.btrim(p_integration_metadata->'nse_codes'->>required_code.key_name) = ''
  ) THEN RAISE EXCEPTION 'invalid_integration_metadata'; END IF;
  IF COALESCE(p_integration_metadata->>'external_account_candidate', '') !~ '^[A-Z0-9]{1,10}$' THEN
    RAISE EXCEPTION 'external_account_candidate_invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_memberships membership
    WHERE membership.workspace_id = p_workspace_id
      AND membership.profile_id = p_investor_profile_id
      AND membership.status = 'active'
  ) THEN RAISE EXCEPTION 'investor_workspace_membership_required'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.investor_registration_profiles registration
    WHERE registration.workspace_id = p_workspace_id
      AND registration.investor_profile_id = p_investor_profile_id
  ) THEN RAISE EXCEPTION 'investor_registration_profile_required'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.integration_accounts account
    WHERE account.workspace_id = p_workspace_id
      AND account.integration_key = 'NSE_INVEST'
      AND account.integration_environment = 'UAT'
      AND account.investor_profile_id <> p_investor_profile_id
      AND pg_catalog.upper(pg_catalog.btrim(account.integration_metadata->>'external_account_candidate')) =
          pg_catalog.upper(pg_catalog.btrim(p_integration_metadata->>'external_account_candidate'))
  ) THEN RAISE EXCEPTION 'nse_ucc_candidate_collision'; END IF;

  BEGIN
    INSERT INTO public.integration_accounts (
      workspace_id, investor_profile_id, integration_key, integration_environment,
      state, integration_metadata
    ) VALUES (
      p_workspace_id, p_investor_profile_id, 'NSE_INVEST', 'UAT',
      'NOT_REGISTERED', p_integration_metadata
    )
    ON CONFLICT (workspace_id, investor_profile_id, integration_key, integration_environment)
    DO UPDATE SET integration_metadata = EXCLUDED.integration_metadata, updated_at = pg_catalog.now()
    RETURNING * INTO v_account;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'nse_ucc_candidate_collision';
  END;

  IF v_account.state = 'REGISTERED' THEN RAISE EXCEPTION 'ucc_already_registered'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.integration_operations operation
    WHERE operation.integration_account_id = v_account.id
      AND operation.operation_type = 'UCC_REGISTRATION'
      AND (
        operation.state IN ('PREPARED', 'QUEUED', 'SUBMITTING', 'RECONCILIATION_REQUIRED')
        OR (operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed)
      )
  ) THEN RAISE EXCEPTION 'active_ucc_registration_exists'; END IF;

  INSERT INTO public.integration_operations (
    workspace_id, integration_account_id, integration_key, integration_environment,
    category, safety_class, operation_type, api_key, contract_version, state
  ) VALUES (
    p_workspace_id, v_account.id, 'NSE_INVEST', 'UAT',
    'CLIENT', 'WRITE_CLIENT', 'UCC_REGISTRATION', 'CLIENTCOMMON183', 'NNF_1.9.7', 'PREPARED'
  ) RETURNING * INTO v_operation;

  UPDATE public.integration_operations SET state = 'QUEUED'
  WHERE id = v_operation.id RETURNING * INTO v_operation;
  UPDATE public.integration_accounts SET
    state = 'REGISTRATION_PENDING', current_operation_id = v_operation.id,
    current_registration_status = NULL, updated_at = pg_catalog.now()
  WHERE id = v_account.id;

  INSERT INTO public.event_outbox (event_type, payload, status, entity_id, entity_type)
  VALUES (
    'integration.nse.ucc_registration_requested',
    pg_catalog.jsonb_build_object(
      'integration_operation_id', v_operation.id,
      'workspace_id', p_workspace_id,
      'investor_profile_id', p_investor_profile_id,
      'integration_account_id', v_account.id,
      'integration_key', 'NSE_INVEST'
    ),
    'pending', v_operation.id, 'integration_operation'
  );
  RETURN v_operation;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_nse_ucc_registration_source(p_integration_operation_id pg_catalog.uuid)
RETURNS pg_catalog.jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result pg_catalog.jsonb;
BEGIN
  SELECT pg_catalog.jsonb_build_object(
    'operation_id', operation.id,
    'workspace_id', operation.workspace_id,
    'integration_account_id', account.id,
    'correlation_id', operation.correlation_id,
    'external_account_candidate', account.integration_metadata->>'external_account_candidate',
    'registration_mode', account.integration_metadata->>'ucc_mode',
    'investor_kind', registration.investor_kind,
    'legal_first_name', COALESCE(registration.legal_first_name, ''),
    'legal_middle_name', COALESCE(registration.legal_middle_name, ''),
    'legal_last_name', COALESCE(registration.legal_last_name, ''),
    'date_of_birth', COALESCE(pg_catalog.to_char(registration.date_of_birth, 'DD/MM/YYYY'), ''),
    'gender', COALESCE(registration.gender, ''),
    'residency', registration.residency_status,
    'occupation', registration.occupation,
    'holding_mode', registration.holding_mode,
    'pan_exempt', registration.pan_exempt,
    'pan', CASE
      WHEN registration.pan_exempt OR pan.id IS NULL THEN ''
      ELSE extensions.pgp_sym_decrypt(pan.pan_ciphertext, public.pan_encryption_key())
    END,
    'kyc_method', registration.kyc_method,
    'kyc_verified', registration.kyc_verified_at IS NOT NULL,
    'ckyc_number', COALESCE(registration.ckyc_number, ''),
    'communication_preference', registration.communication_preference,
    'mobile_owner_relationship', registration.mobile_owner_relationship,
    'email_owner_relationship', registration.email_owner_relationship,
    'onboarding_mode', registration.onboarding_mode,
    'nomination_opted_in', registration.nomination_opted_in,
    'email', COALESCE(profile.email, ''),
    'mobile', COALESCE(profile.phone_number, ''),
    'address', pg_catalog.jsonb_build_object(
      'line_1', address.address_line_1, 'line_2', COALESCE(address.address_line_2, ''),
      'line_3', COALESCE(address.address_line_3, ''), 'city', address.city,
      'region', address.region, 'postal_code', address.postal_code, 'country', address.country
    ),
    'bank', pg_catalog.jsonb_build_object(
      'account_type', bank.account_type,
      'account_number', extensions.pgp_sym_decrypt(
        bank.account_number_ciphertext,
        public.bank_account_encryption_key(bank.account_number_key_reference)
      ),
      'ifsc_code', bank.ifsc_code, 'micr_code', COALESCE(bank.micr_code, ''),
      'account_holder_name', COALESCE(bank.account_holder_name, '')
    ),
    'nse_codes', account.integration_metadata->'nse_codes'
  ) INTO v_result
  FROM public.integration_operations operation
  JOIN public.integration_accounts account ON account.id = operation.integration_account_id
  JOIN public.investor_registration_profiles registration
    ON registration.workspace_id = operation.workspace_id
   AND registration.investor_profile_id = account.investor_profile_id
  JOIN public.profiles profile ON profile.id = account.investor_profile_id
  JOIN public.investor_addresses address
    ON address.workspace_id = operation.workspace_id
   AND address.investor_profile_id = account.investor_profile_id
   AND address.address_type = 'domestic' AND address.is_current
  JOIN public.investor_bank_accounts bank
    ON bank.workspace_id = operation.workspace_id
   AND bank.investor_profile_id = account.investor_profile_id
   AND bank.is_default AND bank.is_active AND bank.verification_status = 'verified'
  LEFT JOIN public.profile_pan_records pan
    ON pan.id = profile.canonical_pan_record_id AND pan.status = 'VERIFIED'
  WHERE operation.id = p_integration_operation_id
    AND operation.integration_key = 'NSE_INVEST'
    AND operation.integration_environment = 'UAT'
    AND operation.category = 'CLIENT'
    AND operation.safety_class = 'WRITE_CLIENT'
    AND operation.operation_type = 'UCC_REGISTRATION'
    AND operation.api_key = 'CLIENTCOMMON183'
    AND operation.contract_version = 'NNF_1.9.7';

  IF v_result IS NULL THEN RAISE EXCEPTION 'nse_ucc_source_incomplete'; END IF;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_nse_ucc_registration_event(
  p_event_outbox_id pg_catalog.uuid,
  p_max_attempts pg_catalog.int4 DEFAULT 2,
  p_lease_seconds pg_catalog.int4 DEFAULT 120
)
RETURNS TABLE (
  event_outbox_id pg_catalog.uuid,
  integration_operation_id pg_catalog.uuid,
  payload pg_catalog.jsonb,
  correlation_id pg_catalog.uuid,
  attempt pg_catalog.int4,
  claim_state pg_catalog.text,
  claim_token pg_catalog.uuid,
  claim_expires_at pg_catalog.timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event public.event_outbox;
  v_operation public.integration_operations;
BEGIN
  IF p_event_outbox_id IS NULL THEN RAISE EXCEPTION 'event_outbox_id_required'; END IF;
  IF p_max_attempts < 1 OR p_max_attempts > 2 THEN RAISE EXCEPTION 'invalid_max_attempts'; END IF;
  IF p_lease_seconds < 15 OR p_lease_seconds > 900 THEN RAISE EXCEPTION 'invalid_lease_seconds'; END IF;

  WITH candidate AS (
    SELECT event.id, pg_catalog.gen_random_uuid() AS token, operation.state AS operation_state,
      event.status AS previous_event_status
    FROM public.event_outbox event
    JOIN public.integration_operations operation ON operation.id = event.entity_id
    WHERE event.event_type = 'integration.nse.ucc_registration_requested'
      AND event.entity_type = 'integration_operation'
      AND event.retry_count < p_max_attempts
      AND event.id = p_event_outbox_id
      AND NOT operation.ambiguous_outcome
      AND NOT operation.reconciliation_required
      AND (
        (event.status = 'pending' AND operation.state = 'QUEUED')
        OR (event.status = 'failed' AND operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed)
        OR (
          event.status = 'processing'
          AND COALESCE(event.claim_expires_at, '-infinity'::pg_catalog.timestamptz) <= pg_catalog.now()
          AND operation.state = 'QUEUED'
          AND NOT EXISTS (
            SELECT 1 FROM public.integration_api_interactions interaction
            WHERE interaction.integration_operation_id = operation.id
              AND interaction.phase = 'REQUEST'
          )
        )
      )
    ORDER BY event.created_at, event.id
    FOR UPDATE OF event SKIP LOCKED
    LIMIT 1
  )
  UPDATE public.event_outbox event SET
    status = 'processing', retry_count = event.retry_count + 1,
    claimed_at = pg_catalog.now(), claimed_by = candidate.token,
    claim_token = candidate.token,
    claim_expires_at = pg_catalog.now() + (p_lease_seconds::pg_catalog.text || ' seconds')::pg_catalog.interval,
    error_message = NULL, updated_at = pg_catalog.now()
  FROM candidate WHERE event.id = candidate.id
  RETURNING event.* INTO v_event;

  IF v_event.id IS NULL THEN
    RETURN QUERY SELECT NULL::pg_catalog.uuid, NULL::pg_catalog.uuid, NULL::pg_catalog.jsonb,
      NULL::pg_catalog.uuid, 0::pg_catalog.int4, 'no_event'::pg_catalog.text,
      NULL::pg_catalog.uuid, NULL::pg_catalog.timestamptz;
    RETURN;
  END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id = v_event.entity_id;
  RETURN QUERY SELECT v_event.id, v_operation.id, v_event.payload, v_operation.correlation_id,
    v_event.retry_count,
    CASE
      WHEN v_event.retry_count = 1 THEN 'newly_claimed'
      WHEN v_operation.state = 'QUEUED' THEN 'pre_request_recovery_claimed'
      ELSE 'safe_retry_claimed'
    END,
    v_event.claim_token, v_event.claim_expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_nse_ucc_submission(
  p_event_outbox_id pg_catalog.uuid,
  p_claim_token pg_catalog.uuid,
  p_call_id pg_catalog.uuid,
  p_request_payload pg_catalog.text,
  p_request_content_type pg_catalog.text,
  p_request_header_metadata pg_catalog.jsonb,
  p_started_at pg_catalog.timestamptz
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event public.event_outbox;
  v_operation public.integration_operations;
  v_request_json pg_catalog.jsonb;
  v_interaction public.integration_api_interactions;
  v_request_bytes pg_catalog.int8;
  v_request_hash pg_catalog.bytea;
  v_key_reference pg_catalog.text := 'integration_payload_encryption_key_v1';
BEGIN
  IF p_call_id IS NULL OR p_started_at IS NULL OR NULLIF(p_request_payload, '') IS NULL THEN
    RAISE EXCEPTION 'submission_request_incomplete';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_call_id::pg_catalog.text, 0)
  );
  BEGIN
    v_request_json := p_request_payload::pg_catalog.jsonb;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'submission_request_invalid_json';
  END;
  IF public.integration_payload_has_forbidden_key(v_request_json) THEN
    RAISE EXCEPTION 'integration_payload_forbidden_key';
  END IF;
  IF pg_catalog.jsonb_typeof(v_request_json->'reg_details') <> 'array'
     OR pg_catalog.jsonb_array_length(v_request_json->'reg_details') <> 1
     OR pg_catalog.jsonb_typeof(v_request_json->'reg_details'->0) <> 'object' THEN
    RAISE EXCEPTION 'ucc_exactly_one_record_required';
  END IF;
  IF NOT public.integration_header_metadata_is_safe(p_request_header_metadata, 'REQUEST')
     OR NULLIF(pg_catalog.btrim(COALESCE(p_request_content_type, '')), '') IS NULL
     OR p_request_header_metadata->>'content_type' IS DISTINCT FROM p_request_content_type THEN
    RAISE EXCEPTION 'unsafe_request_header_metadata';
  END IF;
  v_request_bytes := pg_catalog.octet_length(pg_catalog.convert_to(p_request_payload, 'UTF8'));
  v_request_hash := extensions.digest(pg_catalog.convert_to(p_request_payload, 'UTF8'), 'sha256');

  SELECT * INTO v_event FROM public.event_outbox event
  WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
  IF v_event.event_type <> 'integration.nse.ucc_registration_requested'
     OR v_event.entity_type <> 'integration_operation' THEN RAISE EXCEPTION 'invalid_event'; END IF;
  IF v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token
     OR v_event.claim_expires_at <= pg_catalog.now() THEN RAISE EXCEPTION 'claim_not_owned'; END IF;

  SELECT * INTO v_operation FROM public.integration_operations operation
  WHERE operation.id = v_event.entity_id FOR UPDATE;
  IF v_operation.id IS NULL
     OR v_operation.integration_key <> 'NSE_INVEST'
     OR v_operation.integration_environment <> 'UAT'
     OR v_operation.category <> 'CLIENT'
     OR v_operation.safety_class <> 'WRITE_CLIENT'
     OR v_operation.operation_type <> 'UCC_REGISTRATION'
     OR v_operation.api_key <> 'CLIENTCOMMON183'
     OR v_operation.contract_version <> 'NNF_1.9.7' THEN
    RAISE EXCEPTION 'integration_operation_not_ucc';
  END IF;

  SELECT * INTO v_interaction FROM public.integration_api_interactions interaction
  WHERE interaction.call_id = p_call_id AND interaction.phase = 'REQUEST';
  IF v_interaction.id IS NOT NULL THEN
    IF v_interaction.integration_operation_id IS DISTINCT FROM v_operation.id
       OR v_interaction.attempt_number IS DISTINCT FROM v_event.retry_count
       OR v_interaction.correlation_id IS DISTINCT FROM v_operation.correlation_id
       OR v_interaction.request_content_type IS DISTINCT FROM p_request_content_type
       OR v_interaction.request_header_metadata IS DISTINCT FROM p_request_header_metadata
       OR v_interaction.request_bytes IS DISTINCT FROM v_request_bytes
       OR v_interaction.request_hash IS DISTINCT FROM v_request_hash
       OR v_interaction.started_at IS DISTINCT FROM p_started_at THEN
      RAISE EXCEPTION 'integration_request_idempotency_conflict';
    END IF;
    RETURN v_interaction;
  END IF;

  IF v_operation.state NOT IN ('QUEUED', 'SUBMISSION_FAILED')
     OR (v_operation.state = 'SUBMISSION_FAILED' AND NOT v_operation.retry_allowed)
     OR v_operation.reconciliation_required THEN
    RAISE EXCEPTION 'integration_operation_not_submittable';
  END IF;

  INSERT INTO public.integration_api_interactions (
    workspace_id, integration_operation_id, integration_key, integration_environment,
    category, safety_class, operation_type, api_key, contract_version,
    endpoint_path, http_method, call_id, phase, attempt_number, correlation_id,
    payload_encryption_key_reference, payload_encryption_key_version,
    request_payload_ciphertext, request_header_metadata, request_content_type,
    request_bytes, request_hash, started_at, normalized_outcome
  ) VALUES (
    v_operation.workspace_id, v_operation.id, v_operation.integration_key,
    v_operation.integration_environment, v_operation.category, v_operation.safety_class,
    v_operation.operation_type, v_operation.api_key, v_operation.contract_version,
    '/nsemfdesk/api/v2/registration/CLIENTCOMMON183', 'POST', p_call_id, 'REQUEST',
    v_event.retry_count, v_operation.correlation_id, v_key_reference, 1,
    extensions.pgp_sym_encrypt(
      p_request_payload,
      public.integration_payload_encryption_key(v_key_reference),
      'cipher-algo=aes256, compress-algo=0'
    ),
    p_request_header_metadata, p_request_content_type, v_request_bytes,
    v_request_hash, p_started_at, 'REQUEST_RECORDED'
  ) RETURNING * INTO v_interaction;

  UPDATE public.integration_operations SET
    state = 'SUBMITTING', attempt_count = v_event.retry_count,
    native_business_status = NULL, business_remark_category = NULL,
    retry_allowed = false, ambiguous_outcome = false,
    reconciliation_required = false, submitted_at = p_started_at,
    completed_at = NULL, last_interaction_id = v_interaction.id
  WHERE id = v_operation.id;
  UPDATE public.integration_accounts SET
    state = 'REGISTRATION_PENDING', current_registration_status = NULL,
    current_operation_id = v_operation.id, updated_at = pg_catalog.now()
  WHERE id = v_operation.integration_account_id;
  RETURN v_interaction;
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_nse_ucc_submission(
  p_event_outbox_id pg_catalog.uuid,
  p_claim_token pg_catalog.uuid,
  p_call_id pg_catalog.uuid,
  p_response_payload pg_catalog.text,
  p_response_content_type pg_catalog.text,
  p_response_header_metadata pg_catalog.jsonb,
  p_http_status pg_catalog.int4,
  p_completed_at pg_catalog.timestamptz,
  p_elapsed_ms pg_catalog.int8,
  p_native_status_value pg_catalog.text,
  p_native_remark_category pg_catalog.text,
  p_normalized_outcome pg_catalog.text,
  p_error_category pg_catalog.text DEFAULT NULL,
  p_timeout_occurred pg_catalog.bool DEFAULT false,
  p_network_failure pg_catalog.bool DEFAULT false,
  p_external_account_id pg_catalog.text DEFAULT NULL,
  p_registration_reference pg_catalog.text DEFAULT NULL,
  p_max_attempts pg_catalog.int4 DEFAULT 2
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event public.event_outbox;
  v_operation public.integration_operations;
  v_request public.integration_api_interactions;
  v_existing public.integration_api_interactions;
  v_interaction public.integration_api_interactions;
  v_request_json pg_catalog.jsonb;
  v_response_json pg_catalog.jsonb;
  v_response_text pg_catalog.text := COALESCE(p_response_payload, '');
  v_requested_account_id pg_catalog.text;
  v_response_bytes pg_catalog.int8;
  v_response_hash pg_catalog.bytea;
  v_identity_hash pg_catalog.bytea;
  v_effective_outcome pg_catalog.text := p_normalized_outcome;
  v_effective_error pg_catalog.text := NULLIF(p_error_category, '');
  v_state pg_catalog.text;
  v_account_state pg_catalog.text;
  v_retry_allowed pg_catalog.bool := false;
  v_ambiguous pg_catalog.bool := false;
  v_reconcile pg_catalog.bool := false;
  v_event_status pg_catalog.text := 'completed';
  v_key_reference pg_catalog.text := 'integration_payload_encryption_key_v1';
BEGIN
  IF p_completed_at IS NULL OR p_elapsed_ms IS NULL OR p_elapsed_ms < 0 THEN
    RAISE EXCEPTION 'submission_result_incomplete';
  END IF;
  IF p_max_attempts < 1 OR p_max_attempts > 2 THEN RAISE EXCEPTION 'invalid_max_attempts'; END IF;
  IF p_normalized_outcome NOT IN (
    'SUCCESS', 'BUSINESS_FAILURE', 'HTTP_FAILURE', 'PRE_TRANSMISSION_FAILURE', 'AMBIGUOUS'
  ) THEN RAISE EXCEPTION 'invalid_normalized_outcome'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_call_id::pg_catalog.text, 0)
  );
  IF NOT public.integration_header_metadata_is_safe(p_response_header_metadata, 'RESULT')
     OR p_response_header_metadata->>'content_type' IS DISTINCT FROM p_response_content_type THEN
    RAISE EXCEPTION 'unsafe_response_header_metadata';
  END IF;
  BEGIN
    v_response_json := v_response_text::pg_catalog.jsonb;
    IF public.integration_payload_has_forbidden_key(v_response_json) THEN
      RAISE EXCEPTION 'integration_payload_forbidden_key';
    END IF;
  EXCEPTION WHEN invalid_text_representation THEN
    v_response_json := NULL;
  END;

  SELECT * INTO v_request FROM public.integration_api_interactions interaction
  WHERE interaction.call_id = p_call_id AND interaction.phase = 'REQUEST';
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'request_interaction_not_found'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation
  WHERE operation.id = v_request.integration_operation_id;
  IF v_operation.id IS NULL OR v_operation.id IS DISTINCT FROM v_request.integration_operation_id THEN
    RAISE EXCEPTION 'integration_operation_not_found';
  END IF;
  BEGIN
    v_request_json := extensions.pgp_sym_decrypt(
      v_request.request_payload_ciphertext,
      public.integration_payload_encryption_key(v_request.payload_encryption_key_reference)
    )::pg_catalog.jsonb;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'integration_request_evidence_unreadable';
  END;
  v_requested_account_id := NULLIF(pg_catalog.btrim(COALESCE(
    v_request_json #>> '{reg_details,0,client_code}', ''
  )), '');
  IF v_requested_account_id IS NULL THEN RAISE EXCEPTION 'request_client_code_missing'; END IF;

  IF NULLIF(pg_catalog.btrim(COALESCE(p_native_status_value, '')), '') = 'REG_SUCCESS'
     AND NULLIF(pg_catalog.btrim(COALESCE(p_external_account_id, '')), '') IS DISTINCT FROM v_requested_account_id THEN
    v_effective_outcome := 'AMBIGUOUS';
    v_effective_error := 'nse_client_code_mismatch';
  END IF;

  IF v_effective_outcome = 'SUCCESS' THEN
    IF p_http_status NOT BETWEEN 200 AND 299
       OR p_native_status_value IS DISTINCT FROM 'REG_SUCCESS'
       OR NULLIF(pg_catalog.btrim(COALESCE(p_external_account_id, '')), '') IS NULL
       OR p_external_account_id IS DISTINCT FROM v_requested_account_id THEN
      RAISE EXCEPTION 'invalid_success_result';
    END IF;
  ELSIF v_effective_outcome = 'BUSINESS_FAILURE' THEN
    IF p_http_status NOT BETWEEN 200 AND 299
       OR NULLIF(pg_catalog.btrim(COALESCE(p_native_status_value, '')), '') IS NULL
       OR p_native_status_value = 'REG_SUCCESS' THEN
      RAISE EXCEPTION 'invalid_business_failure_result';
    END IF;
  ELSIF v_effective_outcome = 'HTTP_FAILURE' THEN
    IF p_http_status NOT IN (400, 403) THEN RAISE EXCEPTION 'http_failure_not_definitive'; END IF;
  ELSIF v_effective_outcome = 'PRE_TRANSMISSION_FAILURE' THEN
    IF p_http_status IS NOT NULL OR p_external_account_id IS NOT NULL
       OR p_registration_reference IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_pre_transmission_result';
    END IF;
  END IF;

  v_response_bytes := pg_catalog.octet_length(pg_catalog.convert_to(v_response_text, 'UTF8'));
  v_response_hash := extensions.digest(pg_catalog.convert_to(v_response_text, 'UTF8'), 'sha256');
  v_identity_hash := extensions.digest(
    pg_catalog.convert_to(pg_catalog.jsonb_build_object(
      'external_account_id', COALESCE(p_external_account_id, ''),
      'registration_reference', COALESCE(p_registration_reference, '')
    )::pg_catalog.text, 'UTF8'),
    'sha256'
  );

  SELECT * INTO v_existing FROM public.integration_api_interactions interaction
  WHERE interaction.call_id = p_call_id AND interaction.phase = 'RESULT';
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.integration_operation_id IS DISTINCT FROM v_operation.id
       OR v_existing.response_content_type IS DISTINCT FROM p_response_content_type
       OR v_existing.response_header_metadata IS DISTINCT FROM p_response_header_metadata
       OR v_existing.response_bytes IS DISTINCT FROM v_response_bytes
       OR v_existing.response_hash IS DISTINCT FROM v_response_hash
       OR v_existing.response_identity_hash IS DISTINCT FROM v_identity_hash
       OR v_existing.http_status IS DISTINCT FROM p_http_status
       OR v_existing.completed_at IS DISTINCT FROM p_completed_at
       OR v_existing.elapsed_ms IS DISTINCT FROM p_elapsed_ms
       OR v_existing.native_status_value IS DISTINCT FROM NULLIF(p_native_status_value, '')
       OR v_existing.native_remark_category IS DISTINCT FROM NULLIF(p_native_remark_category, '')
       OR v_existing.normalized_outcome IS DISTINCT FROM v_effective_outcome
       OR v_existing.error_category IS DISTINCT FROM v_effective_error
       OR v_existing.timeout_occurred IS DISTINCT FROM COALESCE(p_timeout_occurred, false)
       OR v_existing.network_failure IS DISTINCT FROM COALESCE(p_network_failure, false) THEN
      RAISE EXCEPTION 'integration_result_idempotency_conflict';
    END IF;
    RETURN v_existing;
  END IF;

  SELECT * INTO v_event FROM public.event_outbox event
  WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
  IF v_event.entity_id IS DISTINCT FROM v_operation.id
     OR v_event.status <> 'processing'
     OR v_event.claim_token IS DISTINCT FROM p_claim_token THEN
    RAISE EXCEPTION 'claim_not_owned';
  END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation
  WHERE operation.id = v_request.integration_operation_id FOR UPDATE;
  IF v_operation.state <> 'SUBMITTING' THEN RAISE EXCEPTION 'integration_operation_not_submitting'; END IF;

  IF v_effective_outcome = 'SUCCESS' THEN
    v_state := 'SUCCESS'; v_account_state := 'REGISTERED';
  ELSIF v_effective_outcome = 'BUSINESS_FAILURE' THEN
    v_state := 'BUSINESS_FAILED'; v_account_state := 'REGISTRATION_FAILED';
  ELSIF v_effective_outcome = 'HTTP_FAILURE' THEN
    v_state := 'HTTP_FAILED'; v_account_state := 'REGISTRATION_FAILED';
  ELSIF v_effective_outcome = 'PRE_TRANSMISSION_FAILURE' THEN
    v_state := 'SUBMISSION_FAILED';
    v_retry_allowed := v_event.retry_count < p_max_attempts;
    v_account_state := CASE WHEN v_retry_allowed THEN 'REGISTRATION_PENDING' ELSE 'REGISTRATION_FAILED' END;
    v_event_status := 'failed';
  ELSE
    v_state := 'RECONCILIATION_REQUIRED'; v_account_state := 'RECONCILIATION_REQUIRED';
    v_ambiguous := true; v_reconcile := true; v_retry_allowed := false;
  END IF;

  INSERT INTO public.integration_api_interactions (
    workspace_id, integration_operation_id, integration_key, integration_environment,
    category, safety_class, operation_type, api_key, contract_version,
    endpoint_path, http_method, call_id, phase, attempt_number, correlation_id,
    payload_encryption_key_reference, payload_encryption_key_version,
    started_at, response_payload_ciphertext, response_header_metadata,
    response_content_type, response_bytes, response_hash, response_identity_hash,
    http_status, http_success, completed_at, elapsed_ms,
    native_status_field, native_status_value, native_remark_field, native_remark_category,
    normalized_outcome, error_category, timeout_occurred, network_failure,
    ambiguous_outcome, reconciliation_required
  ) VALUES (
    v_request.workspace_id, v_request.integration_operation_id, v_request.integration_key,
    v_request.integration_environment, v_request.category, v_request.safety_class,
    v_request.operation_type, v_request.api_key, v_request.contract_version,
    v_request.endpoint_path, v_request.http_method, p_call_id, 'RESULT',
    v_request.attempt_number, v_request.correlation_id, v_key_reference, 1,
    v_request.started_at,
    extensions.pgp_sym_encrypt(
      v_response_text,
      public.integration_payload_encryption_key(v_key_reference),
      'cipher-algo=aes256, compress-algo=0'
    ),
    p_response_header_metadata, p_response_content_type, v_response_bytes,
    v_response_hash, v_identity_hash, p_http_status,
    CASE WHEN p_http_status IS NULL THEN NULL ELSE p_http_status BETWEEN 200 AND 299 END,
    p_completed_at, p_elapsed_ms,
    CASE WHEN NULLIF(p_native_status_value, '') IS NULL THEN NULL ELSE 'reg_status' END,
    NULLIF(p_native_status_value, ''),
    CASE WHEN NULLIF(p_native_remark_category, '') IS NULL THEN NULL ELSE 'reg_remark' END,
    NULLIF(p_native_remark_category, ''), v_effective_outcome, v_effective_error,
    COALESCE(p_timeout_occurred, false), COALESCE(p_network_failure, false),
    v_ambiguous, v_reconcile
  ) RETURNING * INTO v_interaction;

  UPDATE public.integration_operations SET
    state = v_state, native_business_status = NULLIF(p_native_status_value, ''),
    business_remark_category = NULLIF(p_native_remark_category, ''),
    retry_allowed = v_retry_allowed, ambiguous_outcome = v_ambiguous,
    reconciliation_required = v_reconcile,
    completed_at = CASE WHEN v_reconcile THEN NULL ELSE p_completed_at END,
    last_interaction_id = v_interaction.id
  WHERE id = v_operation.id;

  UPDATE public.integration_accounts SET
    state = v_account_state,
    external_account_id = CASE WHEN v_effective_outcome = 'SUCCESS' THEN p_external_account_id ELSE external_account_id END,
    current_registration_status = NULLIF(p_native_status_value, ''),
    integration_metadata = CASE WHEN v_effective_outcome = 'SUCCESS' THEN
      integration_metadata || pg_catalog.jsonb_build_object(
        'nse_registration', pg_catalog.jsonb_build_object(
          'registration_reference', NULLIF(p_registration_reference, ''),
          'registration_result_interaction_id', v_interaction.id
        )
      ) ELSE integration_metadata END,
    current_operation_id = v_operation.id, updated_at = pg_catalog.now()
  WHERE id = v_operation.integration_account_id;

  UPDATE public.event_outbox SET
    status = v_event_status,
    error_message = CASE WHEN v_event_status = 'failed' THEN
      pg_catalog.left(COALESCE(v_effective_error, 'pre_transmission_failure'), 1000)
      ELSE NULL END,
    claimed_by = NULL, claim_token = NULL, claim_expires_at = NULL,
    updated_at = pg_catalog.now()
  WHERE id = v_event.id;
  RETURN v_interaction;
END;
$$;

CREATE OR REPLACE FUNCTION public.recover_expired_nse_ucc_events(
  p_max_attempts pg_catalog.int4 DEFAULT 2
)
RETURNS pg_catalog.int4
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event public.event_outbox;
  v_operation public.integration_operations;
  v_request public.integration_api_interactions;
  v_result_id pg_catalog.uuid;
  v_count pg_catalog.int4 := 0;
  v_completed_at pg_catalog.timestamptz;
  v_retry_allowed pg_catalog.bool;
  v_key_reference pg_catalog.text := 'integration_payload_encryption_key_v1';
  v_empty_hash pg_catalog.bytea := extensions.digest(''::pg_catalog.bytea, 'sha256');
  v_identity_hash pg_catalog.bytea := extensions.digest(
    pg_catalog.convert_to(pg_catalog.jsonb_build_object(
      'external_account_id', '', 'registration_reference', ''
    )::pg_catalog.text, 'UTF8'), 'sha256'
  );
BEGIN
  IF p_max_attempts < 1 OR p_max_attempts > 2 THEN RAISE EXCEPTION 'invalid_max_attempts'; END IF;
  FOR v_event IN
    SELECT event.* FROM public.event_outbox event
    JOIN public.integration_operations operation ON operation.id = event.entity_id
    WHERE event.event_type = 'integration.nse.ucc_registration_requested'
      AND event.entity_type = 'integration_operation'
      AND event.status = 'processing'
      AND event.claim_expires_at <= pg_catalog.now()
      AND operation.state IN ('QUEUED', 'SUBMITTING')
    ORDER BY event.claim_expires_at, event.id
    FOR UPDATE OF event SKIP LOCKED
  LOOP
    SELECT * INTO v_operation FROM public.integration_operations
    WHERE id = v_event.entity_id FOR UPDATE;
    v_completed_at := pg_catalog.now();
    IF v_operation.state = 'QUEUED' THEN
      v_retry_allowed := v_event.retry_count < p_max_attempts;
      UPDATE public.integration_operations SET
        state = 'SUBMISSION_FAILED', attempt_count = GREATEST(attempt_count, v_event.retry_count),
        retry_allowed = v_retry_allowed, ambiguous_outcome = false,
        reconciliation_required = false,
        business_remark_category = 'pre_request_claim_expired',
        completed_at = v_completed_at
      WHERE id = v_operation.id;
      UPDATE public.integration_accounts SET
        state = CASE WHEN v_retry_allowed THEN 'REGISTRATION_PENDING' ELSE 'REGISTRATION_FAILED' END,
        current_registration_status = NULL, current_operation_id = v_operation.id,
        updated_at = pg_catalog.now()
      WHERE id = v_operation.integration_account_id;
      UPDATE public.event_outbox SET
        status = 'failed', error_message = 'pre_request_claim_expired',
        claimed_by = NULL, claim_token = NULL, claim_expires_at = NULL,
        updated_at = pg_catalog.now()
      WHERE id = v_event.id;
    ELSE
      SELECT * INTO v_request FROM public.integration_api_interactions interaction
      WHERE interaction.integration_operation_id = v_operation.id
        AND interaction.phase = 'REQUEST'
        AND NOT EXISTS (
          SELECT 1 FROM public.integration_api_interactions result
          WHERE result.call_id = interaction.call_id AND result.phase = 'RESULT'
        )
      ORDER BY interaction.created_at DESC LIMIT 1;
      IF v_request.id IS NOT NULL THEN
        INSERT INTO public.integration_api_interactions (
          workspace_id, integration_operation_id, integration_key, integration_environment,
          category, safety_class, operation_type, api_key, contract_version,
          endpoint_path, http_method, call_id, phase, attempt_number, correlation_id,
          payload_encryption_key_reference, payload_encryption_key_version,
          started_at, response_payload_ciphertext, response_header_metadata,
          response_content_type, response_bytes, response_hash, response_identity_hash,
          completed_at, elapsed_ms, normalized_outcome, error_category,
          ambiguous_outcome, reconciliation_required
        ) VALUES (
          v_request.workspace_id, v_request.integration_operation_id, v_request.integration_key,
          v_request.integration_environment, v_request.category, v_request.safety_class,
          v_request.operation_type, v_request.api_key, v_request.contract_version,
          v_request.endpoint_path, v_request.http_method, v_request.call_id, 'RESULT',
          v_request.attempt_number, v_request.correlation_id, v_key_reference, 1,
          v_request.started_at,
          extensions.pgp_sym_encrypt(
            '', public.integration_payload_encryption_key(v_key_reference),
            'cipher-algo=aes256, compress-algo=0'
          ),
          '{}'::pg_catalog.jsonb, NULL, 0, v_empty_hash, v_identity_hash,
          v_completed_at,
          GREATEST(0::pg_catalog.int8, (EXTRACT(EPOCH FROM (v_completed_at - v_request.started_at)) * 1000)::pg_catalog.int8),
          'AMBIGUOUS', 'post_request_claim_expired', true, true
        ) RETURNING id INTO v_result_id;
      ELSE
        v_result_id := NULL;
      END IF;
      UPDATE public.integration_operations SET
        state = 'RECONCILIATION_REQUIRED', retry_allowed = false,
        ambiguous_outcome = true, reconciliation_required = true,
        business_remark_category = 'post_request_claim_expired',
        completed_at = NULL, last_interaction_id = COALESCE(v_result_id, last_interaction_id)
      WHERE id = v_operation.id;
      UPDATE public.integration_accounts SET
        state = 'RECONCILIATION_REQUIRED', current_registration_status = NULL,
        current_operation_id = v_operation.id, updated_at = pg_catalog.now()
      WHERE id = v_operation.integration_account_id;
      UPDATE public.event_outbox SET
        status = 'completed', error_message = NULL,
        claimed_by = NULL, claim_token = NULL, claim_expires_at = NULL,
        updated_at = pg_catalog.now()
      WHERE id = v_event.id;
    END IF;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_nse_ucc_validation_failure(
  p_event_outbox_id pg_catalog.uuid,
  p_claim_token pg_catalog.uuid,
  p_error_code pg_catalog.text
)
RETURNS public.integration_operations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event public.event_outbox;
  v_operation public.integration_operations;
BEGIN
  IF NULLIF(pg_catalog.btrim(COALESCE(p_error_code, '')), '') IS NULL THEN
    RAISE EXCEPTION 'error_code_required';
  END IF;
  SELECT * INTO v_event FROM public.event_outbox event
  WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
  IF v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token THEN
    RAISE EXCEPTION 'claim_not_owned';
  END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation
  WHERE operation.id = v_event.entity_id FOR UPDATE;
  IF v_operation.state NOT IN ('QUEUED', 'SUBMISSION_FAILED') THEN
    RAISE EXCEPTION 'integration_operation_not_validating';
  END IF;
  UPDATE public.integration_operations SET
    state = 'VALIDATION_FAILED', retry_allowed = false,
    native_business_status = NULL,
    business_remark_category = pg_catalog.left(p_error_code, 100),
    completed_at = pg_catalog.now()
  WHERE id = v_operation.id RETURNING * INTO v_operation;
  UPDATE public.integration_accounts SET
    state = 'VALIDATION_FAILED', current_registration_status = NULL,
    current_operation_id = v_operation.id, updated_at = pg_catalog.now()
  WHERE id = v_operation.integration_account_id;
  UPDATE public.event_outbox SET
    status = 'completed', error_message = NULL,
    claimed_by = NULL, claim_token = NULL, claim_expires_at = NULL,
    updated_at = pg_catalog.now()
  WHERE id = v_event.id;
  RETURN v_operation;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_integration_account_state(p_integration_account_id pg_catalog.uuid)
RETURNS pg_catalog.jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT pg_catalog.jsonb_build_object(
    'integration_account_id', account.id,
    'workspace_id', account.workspace_id,
    'integration_key', account.integration_key,
    'integration_environment', account.integration_environment,
    'state', account.state,
    'current_registration_status', account.current_registration_status,
    'has_external_account_id', account.external_account_id IS NOT NULL,
    'current_operation_id', account.current_operation_id,
    'operation_state', operation.state,
    'category', operation.category,
    'safety_class', operation.safety_class,
    'api_key', operation.api_key,
    'contract_version', operation.contract_version,
    'native_business_status', operation.native_business_status,
    'business_remark_category', operation.business_remark_category,
    'attempt_count', operation.attempt_count,
    'retry_allowed', operation.retry_allowed,
    'ambiguous_outcome', operation.ambiguous_outcome,
    'reconciliation_required', operation.reconciliation_required,
    'interaction_count', (
      SELECT pg_catalog.count(*) FROM public.integration_api_interactions interaction
      WHERE interaction.integration_operation_id = operation.id
    )
  )
  FROM public.integration_accounts account
  LEFT JOIN public.integration_operations operation ON operation.id = account.current_operation_id
  WHERE account.id = p_integration_account_id;
$$;


CREATE OR REPLACE FUNCTION public.nse_ucc_verification_evidence_matches(
  p_target_operation_id pg_catalog.uuid,
  p_verification_operation_id pg_catalog.uuid
)
RETURNS pg_catalog.bool
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_target public.integration_operations;
  v_verification public.integration_operations;
  v_registration_request public.integration_api_interactions;
  v_verification_request public.integration_api_interactions;
  v_verification_result public.integration_api_interactions;
  v_registration_json pg_catalog.jsonb;
  v_request_json pg_catalog.jsonb;
  v_result_json pg_catalog.jsonb;
  v_client_code pg_catalog.text;
  v_pan pg_catalog.text;
BEGIN
  SELECT * INTO v_target FROM public.integration_operations WHERE id = p_target_operation_id;
  SELECT * INTO v_verification FROM public.integration_operations WHERE id = p_verification_operation_id;
  IF v_target.id IS NULL OR v_verification.id IS NULL
     OR v_target.operation_type <> 'UCC_REGISTRATION'
     OR v_target.api_key <> 'CLIENTCOMMON183'
     OR v_verification.operation_type <> 'UCC_VERIFICATION'
     OR v_verification.api_key <> 'CLIENT_MASTER_REPORT'
     OR v_verification.operation_purpose NOT IN (
       'POST_REGISTRATION_VERIFICATION', 'AMBIGUOUS_WRITE_RECONCILIATION'
     )
     OR v_verification.category <> 'RECONCILIATION'
     OR v_verification.safety_class <> 'READ_ONLY'
     OR v_verification.state <> 'SUCCESS'
     OR v_verification.reconciliation_target_operation_id IS DISTINCT FROM v_target.id
     OR v_verification.workspace_id IS DISTINCT FROM v_target.workspace_id
     OR v_verification.integration_account_id IS DISTINCT FROM v_target.integration_account_id
     OR v_verification.integration_key IS DISTINCT FROM v_target.integration_key
     OR v_verification.integration_environment IS DISTINCT FROM v_target.integration_environment THEN
    RETURN false;
  END IF;
  SELECT * INTO v_registration_request FROM public.integration_api_interactions interaction
  WHERE interaction.integration_operation_id = v_target.id AND interaction.phase = 'REQUEST'
  ORDER BY interaction.attempt_number DESC, interaction.created_at DESC LIMIT 1;
  SELECT request.* INTO v_verification_request FROM public.integration_api_interactions request
  JOIN public.integration_api_interactions result
    ON result.call_id = request.call_id AND result.phase = 'RESULT'
  WHERE request.integration_operation_id = v_verification.id AND request.phase = 'REQUEST'
    AND result.normalized_outcome = 'SUCCESS' AND result.http_success
  ORDER BY request.attempt_number DESC, request.created_at DESC LIMIT 1;
  SELECT * INTO v_verification_result FROM public.integration_api_interactions result
  WHERE result.call_id = v_verification_request.call_id AND result.phase = 'RESULT';
  IF v_registration_request.id IS NULL OR v_verification_request.id IS NULL OR v_verification_result.id IS NULL THEN RETURN false; END IF;
  v_registration_json := extensions.pgp_sym_decrypt(
    v_registration_request.request_payload_ciphertext,
    public.integration_payload_encryption_key(v_registration_request.payload_encryption_key_reference)
  )::pg_catalog.jsonb;
  v_request_json := extensions.pgp_sym_decrypt(
    v_verification_request.request_payload_ciphertext,
    public.integration_payload_encryption_key(v_verification_request.payload_encryption_key_reference)
  )::pg_catalog.jsonb;
  v_result_json := extensions.pgp_sym_decrypt(
    v_verification_result.response_payload_ciphertext,
    public.integration_payload_encryption_key(v_verification_result.payload_encryption_key_reference)
  )::pg_catalog.jsonb;
  v_client_code := pg_catalog.upper(pg_catalog.btrim(v_registration_json->'reg_details'->0->>'client_code'));
  v_pan := pg_catalog.upper(pg_catalog.btrim(v_registration_json->'reg_details'->0->>'primary_holder_pan'));
  IF v_client_code = '' OR v_pan = ''
     OR pg_catalog.upper(pg_catalog.btrim(v_request_json->>'client_code')) IS DISTINCT FROM v_client_code
     OR COALESCE(v_request_json->>'PAN', '') <> ''
     OR COALESCE(v_request_json->>'from_date', '') <> ''
     OR COALESCE(v_request_json->>'to_date', '') <> ''
     OR v_result_json->>'response_status' IS DISTINCT FROM 'S' THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM pg_catalog.jsonb_array_elements(COALESCE(v_result_json->'report_data', '[]'::pg_catalog.jsonb)) AS report(record)
    WHERE pg_catalog.upper(pg_catalog.btrim(report.record->>'client_code')) = v_client_code
      AND pg_catalog.upper(pg_catalog.btrim(COALESCE(
        report.record->>'primary_holder_pan', report.record->>'primary_pan'
      ))) = v_pan
  );
EXCEPTION WHEN OTHERS THEN RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.prepare_nse_ucc_verification(
  p_target_operation_id pg_catalog.uuid,
  p_verification_purpose pg_catalog.text
)
RETURNS public.integration_operations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_target public.integration_operations; v_verification public.integration_operations;
BEGIN
  IF p_verification_purpose NOT IN (
    'POST_REGISTRATION_VERIFICATION', 'AMBIGUOUS_WRITE_RECONCILIATION'
  ) THEN RAISE EXCEPTION 'ucc_verification_purpose_invalid'; END IF;
  SELECT * INTO v_target FROM public.integration_operations WHERE id = p_target_operation_id FOR UPDATE;
  IF v_target.id IS NULL OR v_target.integration_key <> 'NSE_INVEST'
     OR v_target.integration_environment <> 'UAT' OR v_target.operation_type <> 'UCC_REGISTRATION'
     OR v_target.api_key <> 'CLIENTCOMMON183' THEN RAISE EXCEPTION 'ucc_verification_target_invalid'; END IF;
  IF p_verification_purpose = 'POST_REGISTRATION_VERIFICATION'
     AND (v_target.state <> 'SUCCESS' OR v_target.reconciliation_required) THEN
    RAISE EXCEPTION 'ucc_post_registration_verification_target_invalid';
  END IF;
  IF p_verification_purpose = 'AMBIGUOUS_WRITE_RECONCILIATION'
     AND (v_target.state <> 'RECONCILIATION_REQUIRED' OR NOT v_target.reconciliation_required) THEN
    RAISE EXCEPTION 'ucc_reconciliation_target_invalid';
  END IF;
  INSERT INTO public.integration_operations (
    workspace_id, integration_account_id, integration_key, integration_environment,
    category, safety_class, operation_type, operation_purpose, api_key, contract_version,
    state, reconciliation_target_operation_id
  ) VALUES (
    v_target.workspace_id, v_target.integration_account_id, 'NSE_INVEST', 'UAT',
    'RECONCILIATION', 'READ_ONLY', 'UCC_VERIFICATION', p_verification_purpose,
    'CLIENT_MASTER_REPORT', 'NNF_1.9.7', 'PREPARED', v_target.id
  ) RETURNING * INTO v_verification;
  UPDATE public.integration_operations SET state = 'QUEUED'
  WHERE id = v_verification.id RETURNING * INTO v_verification;
  INSERT INTO public.event_outbox (event_type, payload, status, entity_id, entity_type)
  VALUES (
    'integration.nse.ucc_verification_requested',
    pg_catalog.jsonb_build_object(
      'integration_operation_id', v_verification.id,
      'reconciliation_target_operation_id', v_target.id,
      'verification_purpose', p_verification_purpose,
      'integration_account_id', v_target.integration_account_id,
      'integration_key', 'NSE_INVEST'
    ), 'pending', v_verification.id, 'integration_operation'
  );
  RETURN v_verification;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_nse_ucc_verification_source(
  p_integration_operation_id pg_catalog.uuid
)
RETURNS pg_catalog.jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_verification public.integration_operations; v_target_request public.integration_api_interactions;
  v_request pg_catalog.jsonb; v_result pg_catalog.jsonb;
BEGIN
  SELECT * INTO v_verification FROM public.integration_operations operation
  WHERE operation.id = p_integration_operation_id
    AND operation.integration_key = 'NSE_INVEST' AND operation.integration_environment = 'UAT'
    AND operation.category = 'RECONCILIATION' AND operation.safety_class = 'READ_ONLY'
    AND operation.operation_type = 'UCC_VERIFICATION' AND operation.api_key = 'CLIENT_MASTER_REPORT'
    AND (operation.state = 'QUEUED' OR (operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed));
  IF v_verification.id IS NULL THEN RAISE EXCEPTION 'nse_ucc_verification_source_unavailable'; END IF;
  SELECT * INTO v_target_request FROM public.integration_api_interactions interaction
  WHERE interaction.integration_operation_id = v_verification.reconciliation_target_operation_id
    AND interaction.phase = 'REQUEST'
  ORDER BY interaction.attempt_number DESC, interaction.created_at DESC LIMIT 1;
  IF v_target_request.id IS NULL THEN RAISE EXCEPTION 'nse_ucc_registration_request_evidence_missing'; END IF;
  v_request := extensions.pgp_sym_decrypt(
    v_target_request.request_payload_ciphertext,
    public.integration_payload_encryption_key(v_target_request.payload_encryption_key_reference)
  )::pg_catalog.jsonb;
  v_result := pg_catalog.jsonb_build_object(
    'operation_id', v_verification.id,
    'target_operation_id', v_verification.reconciliation_target_operation_id,
    'workspace_id', v_verification.workspace_id,
    'integration_account_id', v_verification.integration_account_id,
    'correlation_id', v_verification.correlation_id,
    'verification_purpose', v_verification.operation_purpose,
    'intended_client_code', v_request->'reg_details'->0->>'client_code',
    'pan', v_request->'reg_details'->0->>'primary_holder_pan'
  );
  IF NULLIF(v_result->>'intended_client_code', '') IS NULL OR NULLIF(v_result->>'pan', '') IS NULL THEN
    RAISE EXCEPTION 'nse_ucc_registration_identity_evidence_missing';
  END IF;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.recover_expired_nse_ucc_verification_events(
  p_event_outbox_id pg_catalog.uuid,
  p_max_attempts pg_catalog.int4 DEFAULT 3
)
RETURNS pg_catalog.text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_event public.event_outbox;
  v_operation public.integration_operations;
  v_request public.integration_api_interactions;
  v_result_id pg_catalog.uuid;
  v_retry_allowed pg_catalog.bool;
  v_completed_at pg_catalog.timestamptz := pg_catalog.now();
  v_key pg_catalog.text := 'integration_payload_encryption_key_v1';
  v_empty_hash pg_catalog.bytea := extensions.digest(''::pg_catalog.bytea, 'sha256');
BEGIN
  IF p_event_outbox_id IS NULL THEN RAISE EXCEPTION 'event_outbox_id_required'; END IF;
  IF p_max_attempts < 1 OR p_max_attempts > 5 THEN RAISE EXCEPTION 'invalid_max_attempts'; END IF;
  SELECT * INTO v_event FROM public.event_outbox event
  WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.event_type <> 'integration.nse.ucc_verification_requested'
     OR v_event.entity_type <> 'integration_operation' OR v_event.status <> 'processing'
     OR v_event.claim_expires_at > pg_catalog.now() THEN RETURN 'no_recovery_required'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation
  WHERE operation.id = v_event.entity_id FOR UPDATE;
  IF v_operation.id IS NULL OR v_operation.operation_type <> 'UCC_VERIFICATION'
     OR v_operation.safety_class <> 'READ_ONLY' THEN RETURN 'no_recovery_required'; END IF;
  v_retry_allowed := v_event.retry_count < p_max_attempts;
  IF v_operation.state = 'QUEUED' AND NOT EXISTS (
    SELECT 1 FROM public.integration_api_interactions interaction
    WHERE interaction.integration_operation_id = v_operation.id AND interaction.phase = 'REQUEST'
  ) THEN
    UPDATE public.integration_operations SET state = 'SUBMISSION_FAILED',
      attempt_count = GREATEST(attempt_count, v_event.retry_count), retry_allowed = v_retry_allowed,
      business_remark_category = 'verification_pre_request_claim_expired',
      native_business_status = NULL, ambiguous_outcome = false, reconciliation_required = false,
      completed_at = v_completed_at
    WHERE id = v_operation.id;
  ELSIF v_operation.state = 'SUBMITTING' THEN
    SELECT * INTO v_request FROM public.integration_api_interactions request
    WHERE request.integration_operation_id = v_operation.id AND request.phase = 'REQUEST'
      AND NOT EXISTS (
        SELECT 1 FROM public.integration_api_interactions result
        WHERE result.call_id = request.call_id AND result.phase = 'RESULT'
      )
    ORDER BY request.attempt_number DESC, request.created_at DESC LIMIT 1;
    IF v_request.id IS NULL THEN RETURN 'no_recovery_required'; END IF;
    INSERT INTO public.integration_api_interactions (
      workspace_id, integration_operation_id, integration_key, integration_environment,
      category, safety_class, operation_type, api_key, contract_version, endpoint_path,
      http_method, call_id, phase, attempt_number, correlation_id,
      payload_encryption_key_reference, payload_encryption_key_version, started_at,
      response_payload_ciphertext, response_header_metadata, response_content_type,
      response_bytes, response_hash, http_status, http_success, completed_at, elapsed_ms,
      normalized_outcome, error_category, timeout_occurred, network_failure,
      ambiguous_outcome, reconciliation_required
    ) VALUES (
      v_request.workspace_id, v_request.integration_operation_id, v_request.integration_key,
      v_request.integration_environment, v_request.category, v_request.safety_class,
      v_request.operation_type, v_request.api_key, v_request.contract_version,
      v_request.endpoint_path, v_request.http_method, v_request.call_id, 'RESULT',
      v_request.attempt_number, v_request.correlation_id, v_key, 1, v_request.started_at,
      extensions.pgp_sym_encrypt('', public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0'),
      '{}'::pg_catalog.jsonb, NULL, 0, v_empty_hash, NULL, NULL, v_completed_at,
      GREATEST(0::pg_catalog.int8, (EXTRACT(EPOCH FROM (v_completed_at - v_request.started_at)) * 1000)::pg_catalog.int8),
      'TRANSPORT_FAILURE', 'verification_read_lease_expired', false, false, false, false
    ) RETURNING id INTO v_result_id;
    UPDATE public.integration_operations SET state = 'SUBMISSION_FAILED',
      attempt_count = GREATEST(attempt_count, v_event.retry_count), retry_allowed = v_retry_allowed,
      business_remark_category = 'verification_read_lease_expired',
      native_business_status = NULL, ambiguous_outcome = false, reconciliation_required = false,
      completed_at = v_completed_at, last_interaction_id = v_result_id
    WHERE id = v_operation.id;
  ELSE
    RETURN 'no_recovery_required';
  END IF;
  UPDATE public.event_outbox SET status = 'failed',
    error_message = CASE WHEN v_retry_allowed THEN 'verification_read_retryable' ELSE 'verification_read_attempts_exhausted' END,
    claimed_by = NULL, claim_token = NULL, claim_expires_at = NULL, updated_at = pg_catalog.now()
  WHERE id = v_event.id;
  RETURN CASE WHEN v_retry_allowed THEN 'safe_read_retry_available' ELSE 'verification_attempts_exhausted' END;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_nse_ucc_verification_event(
  p_event_outbox_id pg_catalog.uuid,
  p_max_attempts pg_catalog.int4 DEFAULT 3,
  p_lease_seconds pg_catalog.int4 DEFAULT 120
)
RETURNS TABLE (
  event_outbox_id pg_catalog.uuid, integration_operation_id pg_catalog.uuid,
  correlation_id pg_catalog.uuid, attempt pg_catalog.int4, claim_state pg_catalog.text,
  claim_token pg_catalog.uuid
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_event public.event_outbox; v_operation public.integration_operations;
BEGIN
  IF p_event_outbox_id IS NULL THEN RAISE EXCEPTION 'event_outbox_id_required'; END IF;
  IF p_max_attempts < 1 OR p_max_attempts > 5 THEN RAISE EXCEPTION 'invalid_max_attempts'; END IF;
  IF p_lease_seconds < 15 OR p_lease_seconds > 900 THEN RAISE EXCEPTION 'invalid_lease_seconds'; END IF;
  WITH candidate AS (
    SELECT event.id, pg_catalog.gen_random_uuid() AS token
    FROM public.event_outbox event JOIN public.integration_operations operation ON operation.id = event.entity_id
    WHERE event.id = p_event_outbox_id
      AND event.event_type = 'integration.nse.ucc_verification_requested'
      AND event.entity_type = 'integration_operation' AND event.retry_count < p_max_attempts
      AND operation.operation_type = 'UCC_VERIFICATION' AND operation.safety_class = 'READ_ONLY'
      AND (
        (event.status = 'pending' AND operation.state = 'QUEUED')
        OR (event.status = 'failed' AND operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed)
      )
    FOR UPDATE OF event SKIP LOCKED
  ) UPDATE public.event_outbox event SET
    status = 'processing', retry_count = event.retry_count + 1, claimed_at = pg_catalog.now(),
    claimed_by = candidate.token, claim_token = candidate.token,
    claim_expires_at = pg_catalog.now() + (p_lease_seconds::pg_catalog.text || ' seconds')::pg_catalog.interval,
    error_message = NULL, updated_at = pg_catalog.now()
  FROM candidate WHERE event.id = candidate.id RETURNING event.* INTO v_event;
  IF v_event.id IS NULL THEN
    RETURN QUERY SELECT NULL::pg_catalog.uuid, NULL::pg_catalog.uuid, NULL::pg_catalog.uuid,
      0::pg_catalog.int4, 'no_event'::pg_catalog.text, NULL::pg_catalog.uuid;
    RETURN;
  END IF;
  SELECT * INTO v_operation FROM public.integration_operations WHERE id = v_event.entity_id;
  RETURN QUERY SELECT v_event.id, v_operation.id, v_operation.correlation_id,
    v_event.retry_count,
    CASE WHEN v_event.retry_count = 1 THEN 'newly_claimed' ELSE 'safe_retry_claimed' END,
    v_event.claim_token;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_nse_ucc_verification(
  p_event_outbox_id pg_catalog.uuid, p_claim_token pg_catalog.uuid,
  p_call_id pg_catalog.uuid, p_request_payload pg_catalog.text,
  p_request_header_metadata pg_catalog.jsonb, p_started_at pg_catalog.timestamptz
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_event public.event_outbox; v_operation public.integration_operations;
  v_json pg_catalog.jsonb; v_existing public.integration_api_interactions;
  v_bytes pg_catalog.int8; v_hash pg_catalog.bytea; v_key pg_catalog.text := 'integration_payload_encryption_key_v1';
BEGIN
  IF p_call_id IS NULL OR p_started_at IS NULL OR NULLIF(p_request_payload, '') IS NULL THEN RAISE EXCEPTION 'verification_request_incomplete'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_call_id::pg_catalog.text, 0));
  BEGIN v_json := p_request_payload::pg_catalog.jsonb; EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'verification_request_invalid_json'; END;
  IF pg_catalog.jsonb_typeof(v_json) <> 'object'
     OR EXISTS (
       SELECT 1 FROM pg_catalog.jsonb_object_keys(v_json) AS request_key(key_name)
       WHERE request_key.key_name NOT IN ('client_code', 'PAN', 'from_date', 'to_date')
     )
     OR v_json->>'client_code' !~ '^[A-Z0-9]{1,10}$'
     OR COALESCE(v_json->>'PAN', '') <> ''
     OR COALESCE(v_json->>'from_date', '') <> '' OR COALESCE(v_json->>'to_date', '') <> ''
     OR public.integration_payload_has_forbidden_key(v_json) THEN RAISE EXCEPTION 'verification_request_invalid'; END IF;
  IF NOT public.integration_header_metadata_is_safe(p_request_header_metadata, 'REQUEST')
     OR p_request_header_metadata->>'content_type' IS DISTINCT FROM 'application/json'
     OR p_request_header_metadata->>'accept' IS DISTINCT FROM 'application/json' THEN RAISE EXCEPTION 'unsafe_request_header_metadata'; END IF;
  v_bytes := pg_catalog.octet_length(pg_catalog.convert_to(p_request_payload, 'UTF8'));
  v_hash := extensions.digest(pg_catalog.convert_to(p_request_payload, 'UTF8'), 'sha256');
  SELECT * INTO v_event FROM public.event_outbox event WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.event_type <> 'integration.nse.ucc_verification_requested'
     OR v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token
     OR v_event.claim_expires_at <= pg_catalog.now() THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation WHERE operation.id = v_event.entity_id FOR UPDATE;
  IF v_operation.operation_type <> 'UCC_VERIFICATION' OR v_operation.api_key <> 'CLIENT_MASTER_REPORT'
     OR v_operation.category <> 'RECONCILIATION' OR v_operation.safety_class <> 'READ_ONLY'
     OR v_operation.contract_version <> 'NNF_1.9.7' THEN RAISE EXCEPTION 'integration_operation_not_verification'; END IF;
  SELECT * INTO v_existing FROM public.integration_api_interactions interaction WHERE interaction.call_id = p_call_id AND interaction.phase = 'REQUEST';
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.integration_operation_id IS DISTINCT FROM v_operation.id
       OR v_existing.attempt_number IS DISTINCT FROM v_event.retry_count
       OR v_existing.correlation_id IS DISTINCT FROM v_operation.correlation_id
       OR v_existing.endpoint_path <> '/nsemfdesk/api/v2/reports/client_master_report'
       OR v_existing.http_method <> 'POST' OR v_existing.request_content_type <> 'application/json'
       OR v_existing.request_hash IS DISTINCT FROM v_hash OR v_existing.request_bytes IS DISTINCT FROM v_bytes
       OR v_existing.request_header_metadata IS DISTINCT FROM p_request_header_metadata
       OR v_existing.started_at IS DISTINCT FROM p_started_at THEN RAISE EXCEPTION 'integration_request_idempotency_conflict'; END IF;
    RETURN v_existing;
  END IF;
  IF v_operation.state NOT IN ('QUEUED', 'SUBMISSION_FAILED')
     OR (v_operation.state = 'SUBMISSION_FAILED' AND NOT v_operation.retry_allowed) THEN
    RAISE EXCEPTION 'integration_operation_not_verification';
  END IF;
  INSERT INTO public.integration_api_interactions (
    workspace_id, integration_operation_id, integration_key, integration_environment,
    category, safety_class, operation_type, api_key, contract_version, endpoint_path,
    http_method, call_id, phase, attempt_number, correlation_id,
    payload_encryption_key_reference, payload_encryption_key_version,
    request_payload_ciphertext, request_header_metadata, request_content_type,
    request_bytes, request_hash, started_at, normalized_outcome
  ) VALUES (
    v_operation.workspace_id, v_operation.id, v_operation.integration_key, v_operation.integration_environment,
    v_operation.category, v_operation.safety_class, v_operation.operation_type, v_operation.api_key,
    v_operation.contract_version, '/nsemfdesk/api/v2/reports/client_master_report', 'POST',
    p_call_id, 'REQUEST', v_event.retry_count, v_operation.correlation_id, v_key, 1,
    extensions.pgp_sym_encrypt(p_request_payload, public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0'),
    p_request_header_metadata, 'application/json', v_bytes, v_hash, p_started_at, 'REQUEST_RECORDED'
  ) RETURNING * INTO v_existing;
  UPDATE public.integration_operations SET state = 'SUBMITTING', attempt_count = v_event.retry_count,
    native_business_status = NULL, business_remark_category = NULL, retry_allowed = false,
    ambiguous_outcome = false, reconciliation_required = false, submitted_at = p_started_at,
    completed_at = NULL, last_interaction_id = v_existing.id
  WHERE id = v_operation.id;
  RETURN v_existing;
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_nse_ucc_verification(
  p_event_outbox_id pg_catalog.uuid, p_claim_token pg_catalog.uuid, p_call_id pg_catalog.uuid,
  p_response_payload pg_catalog.text, p_response_content_type pg_catalog.text,
  p_response_header_metadata pg_catalog.jsonb, p_http_status pg_catalog.int4,
  p_native_status_value pg_catalog.text, p_native_remark_category pg_catalog.text,
  p_normalized_outcome pg_catalog.text, p_error_category pg_catalog.text,
  p_timeout_occurred pg_catalog.bool, p_network_failure pg_catalog.bool,
  p_completed_at pg_catalog.timestamptz, p_elapsed_ms pg_catalog.int8,
  p_max_attempts pg_catalog.int4 DEFAULT 3
)
RETURNS public.integration_api_interactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_request public.integration_api_interactions; v_existing public.integration_api_interactions;
  v_event public.event_outbox; v_operation public.integration_operations; v_interaction public.integration_api_interactions;
  v_target_request public.integration_api_interactions; v_registration_json pg_catalog.jsonb;
  v_response_json pg_catalog.jsonb; v_exact_match pg_catalog.bool := false; v_retry_allowed pg_catalog.bool := false;
  v_bytes pg_catalog.int8; v_hash pg_catalog.bytea; v_key pg_catalog.text := 'integration_payload_encryption_key_v1';
  v_state pg_catalog.text; v_event_status pg_catalog.text := 'completed';
BEGIN
  IF p_completed_at IS NULL OR p_elapsed_ms < 0 OR p_max_attempts < 1 OR p_max_attempts > 5
     OR p_normalized_outcome NOT IN ('SUCCESS','BUSINESS_FAILURE','HTTP_FAILURE','TRANSPORT_FAILURE') THEN
    RAISE EXCEPTION 'verification_result_invalid';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_call_id::pg_catalog.text, 0));
  SELECT * INTO v_request FROM public.integration_api_interactions interaction WHERE interaction.call_id = p_call_id AND interaction.phase = 'REQUEST';
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'integration_request_evidence_missing'; END IF;
  IF NOT public.integration_header_metadata_is_safe(p_response_header_metadata, 'RESULT') THEN RAISE EXCEPTION 'unsafe_response_header_metadata'; END IF;
  v_bytes := pg_catalog.octet_length(pg_catalog.convert_to(COALESCE(p_response_payload, ''), 'UTF8'));
  v_hash := extensions.digest(pg_catalog.convert_to(COALESCE(p_response_payload, ''), 'UTF8'), 'sha256');
  SELECT * INTO v_existing FROM public.integration_api_interactions interaction WHERE interaction.call_id = p_call_id AND interaction.phase = 'RESULT';
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.integration_operation_id IS DISTINCT FROM v_request.integration_operation_id
       OR v_existing.attempt_number IS DISTINCT FROM v_request.attempt_number
       OR v_existing.correlation_id IS DISTINCT FROM v_request.correlation_id
       OR v_existing.response_hash IS DISTINCT FROM v_hash OR v_existing.response_bytes IS DISTINCT FROM v_bytes
       OR v_existing.response_content_type IS DISTINCT FROM p_response_content_type
       OR v_existing.response_header_metadata IS DISTINCT FROM p_response_header_metadata
       OR v_existing.http_status IS DISTINCT FROM p_http_status
       OR v_existing.native_status_value IS DISTINCT FROM p_native_status_value
       OR v_existing.native_remark_category IS DISTINCT FROM p_native_remark_category
       OR v_existing.normalized_outcome IS DISTINCT FROM p_normalized_outcome
       OR v_existing.error_category IS DISTINCT FROM p_error_category
       OR v_existing.timeout_occurred IS DISTINCT FROM COALESCE(p_timeout_occurred, false)
       OR v_existing.network_failure IS DISTINCT FROM COALESCE(p_network_failure, false)
       OR v_existing.completed_at IS DISTINCT FROM p_completed_at OR v_existing.elapsed_ms IS DISTINCT FROM p_elapsed_ms
       THEN RAISE EXCEPTION 'integration_result_idempotency_conflict'; END IF;
    RETURN v_existing;
  END IF;
  SELECT * INTO v_event FROM public.event_outbox event WHERE event.id = p_event_outbox_id FOR UPDATE;
  IF v_event.id IS NULL OR v_event.status <> 'processing' OR v_event.claim_token IS DISTINCT FROM p_claim_token THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
  SELECT * INTO v_operation FROM public.integration_operations operation WHERE operation.id = v_request.integration_operation_id FOR UPDATE;
  IF v_operation.state <> 'SUBMITTING' THEN RAISE EXCEPTION 'integration_operation_not_submitting'; END IF;
  SELECT * INTO v_target_request FROM public.integration_api_interactions interaction
  WHERE interaction.integration_operation_id = v_operation.reconciliation_target_operation_id
    AND interaction.phase = 'REQUEST'
  ORDER BY interaction.attempt_number DESC, interaction.created_at DESC LIMIT 1;
  IF v_target_request.id IS NULL THEN RAISE EXCEPTION 'nse_ucc_registration_request_evidence_missing'; END IF;
  v_registration_json := extensions.pgp_sym_decrypt(
    v_target_request.request_payload_ciphertext,
    public.integration_payload_encryption_key(v_target_request.payload_encryption_key_reference)
  )::pg_catalog.jsonb;
  IF p_http_status BETWEEN 200 AND 299 THEN
    BEGIN v_response_json := p_response_payload::pg_catalog.jsonb; EXCEPTION WHEN invalid_text_representation THEN v_response_json := '{}'::pg_catalog.jsonb; END;
    v_exact_match := v_response_json->>'response_status' = 'S' AND EXISTS (
      SELECT 1 FROM pg_catalog.jsonb_array_elements(COALESCE(v_response_json->'report_data', '[]'::pg_catalog.jsonb)) AS report(record)
      WHERE pg_catalog.upper(pg_catalog.btrim(report.record->>'client_code')) = pg_catalog.upper(pg_catalog.btrim(v_registration_json->'reg_details'->0->>'client_code'))
        AND pg_catalog.upper(pg_catalog.btrim(COALESCE(report.record->>'primary_holder_pan', report.record->>'primary_pan'))) = pg_catalog.upper(pg_catalog.btrim(v_registration_json->'reg_details'->0->>'primary_holder_pan'))
    );
  END IF;
  IF p_normalized_outcome = 'SUCCESS' AND NOT (p_http_status BETWEEN 200 AND 299 AND v_exact_match AND p_native_status_value = 'S') THEN RAISE EXCEPTION 'verification_success_invariant_failed'; END IF;
  IF p_normalized_outcome = 'BUSINESS_FAILURE' AND NOT (p_http_status BETWEEN 200 AND 299 AND NOT v_exact_match) THEN RAISE EXCEPTION 'verification_business_failure_invariant_failed'; END IF;
  IF p_normalized_outcome = 'HTTP_FAILURE' AND (p_http_status IS NULL OR p_http_status BETWEEN 200 AND 299) THEN RAISE EXCEPTION 'verification_http_failure_invariant_failed'; END IF;
  IF p_normalized_outcome = 'TRANSPORT_FAILURE' AND p_http_status IS NOT NULL THEN RAISE EXCEPTION 'verification_transport_failure_invariant_failed'; END IF;
  IF p_normalized_outcome = 'TRANSPORT_FAILURE' THEN
    v_state := 'SUBMISSION_FAILED'; v_retry_allowed := v_event.retry_count < p_max_attempts; v_event_status := 'failed';
  ELSIF p_normalized_outcome = 'SUCCESS' THEN v_state := 'SUCCESS';
  ELSIF p_normalized_outcome = 'BUSINESS_FAILURE' THEN v_state := 'BUSINESS_FAILED';
  ELSE v_state := 'HTTP_FAILED';
  END IF;
  INSERT INTO public.integration_api_interactions (
    workspace_id, integration_operation_id, integration_key, integration_environment, category,
    safety_class, operation_type, api_key, contract_version, endpoint_path, http_method,
    call_id, phase, attempt_number, correlation_id, payload_encryption_key_reference,
    payload_encryption_key_version, started_at, response_payload_ciphertext,
    response_header_metadata, response_content_type, response_bytes, response_hash,
    http_status, http_success, completed_at, elapsed_ms, native_status_field,
    native_status_value, native_remark_category, normalized_outcome, error_category,
    timeout_occurred, network_failure, ambiguous_outcome, reconciliation_required
  ) VALUES (
    v_request.workspace_id, v_request.integration_operation_id, v_request.integration_key,
    v_request.integration_environment, v_request.category, v_request.safety_class,
    v_request.operation_type, v_request.api_key, v_request.contract_version,
    v_request.endpoint_path, v_request.http_method, p_call_id, 'RESULT', v_request.attempt_number,
    v_request.correlation_id, v_key, 1, v_request.started_at,
    extensions.pgp_sym_encrypt(COALESCE(p_response_payload, ''), public.integration_payload_encryption_key(v_key), 'cipher-algo=aes256, compress-algo=0'),
    p_response_header_metadata, p_response_content_type, v_bytes, v_hash, p_http_status,
    CASE WHEN p_http_status IS NULL THEN NULL ELSE p_http_status BETWEEN 200 AND 299 END,
    p_completed_at, p_elapsed_ms, CASE WHEN p_native_status_value IS NULL THEN NULL ELSE 'response_status' END,
    p_native_status_value, p_native_remark_category, p_normalized_outcome, p_error_category,
    COALESCE(p_timeout_occurred, false), COALESCE(p_network_failure, false), false, false
  ) RETURNING * INTO v_interaction;
  UPDATE public.integration_operations SET state = v_state, native_business_status = p_native_status_value,
    business_remark_category = p_native_remark_category, retry_allowed = v_retry_allowed,
    ambiguous_outcome = false, reconciliation_required = false, completed_at = p_completed_at,
    last_interaction_id = v_interaction.id WHERE id = v_operation.id;
  UPDATE public.event_outbox SET status = v_event_status,
    error_message = CASE WHEN v_event_status = 'failed' THEN
      CASE WHEN v_retry_allowed THEN 'verification_read_retryable' ELSE 'verification_read_attempts_exhausted' END
      ELSE NULL END,
    claimed_by = NULL, claim_token = NULL, claim_expires_at = NULL, updated_at = pg_catalog.now()
  WHERE id = v_event.id;
  RETURN v_interaction;
END;
$$;

CREATE OR REPLACE FUNCTION public.distribute_nse_ucc_verification_result(
  p_target_operation_id pg_catalog.uuid,
  p_verification_operation_id pg_catalog.uuid
)
RETURNS public.integration_operations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_target public.integration_operations;
  v_verification public.integration_operations;
  v_account public.integration_accounts;
  v_registration_request public.integration_api_interactions;
  v_request_json pg_catalog.jsonb;
  v_match pg_catalog.bool;
  v_local_status pg_catalog.text;
BEGIN
  SELECT * INTO v_target FROM public.integration_operations WHERE id = p_target_operation_id FOR UPDATE;
  SELECT * INTO v_verification FROM public.integration_operations WHERE id = p_verification_operation_id FOR UPDATE;
  SELECT * INTO v_account FROM public.integration_accounts WHERE id = v_target.integration_account_id FOR UPDATE;
  IF v_target.id IS NULL OR v_verification.id IS NULL
     OR v_verification.reconciliation_target_operation_id IS DISTINCT FROM v_target.id
     OR v_verification.state NOT IN ('SUCCESS', 'BUSINESS_FAILED', 'HTTP_FAILED') THEN
    RAISE EXCEPTION 'ucc_verification_result_not_distributable';
  END IF;
  IF v_verification.operation_purpose = 'POST_REGISTRATION_VERIFICATION'
     AND v_target.state <> 'SUCCESS' THEN RAISE EXCEPTION 'ucc_post_registration_verification_target_invalid'; END IF;
  IF v_verification.operation_purpose = 'AMBIGUOUS_WRITE_RECONCILIATION'
     AND v_target.state <> 'RECONCILIATION_REQUIRED' THEN RAISE EXCEPTION 'ucc_reconciliation_target_invalid'; END IF;
  v_match := public.nse_ucc_verification_evidence_matches(v_target.id, v_verification.id);
  v_local_status := CASE
    WHEN v_match THEN 'CONFIRMED'
    WHEN v_verification.state = 'BUSINESS_FAILED' THEN 'NOT_CONFIRMED'
    ELSE 'HTTP_FAILED'
  END;
  UPDATE public.integration_accounts SET
    integration_metadata = integration_metadata || pg_catalog.jsonb_build_object(
      'nse_registration', COALESCE(integration_metadata->'nse_registration', '{}'::pg_catalog.jsonb)
        || pg_catalog.jsonb_build_object(
          'client_master_verification_operation_id', v_verification.id,
          'client_master_verification_result_interaction_id', v_verification.last_interaction_id,
          'client_master_verification_purpose', v_verification.operation_purpose,
          'client_master_verification_status', v_local_status,
          'client_master_checked_at', v_verification.completed_at,
          'client_master_verified_at', CASE WHEN v_match THEN v_verification.completed_at ELSE NULL END
        )
    ), updated_at = pg_catalog.now()
  WHERE id = v_account.id;
  IF v_verification.operation_purpose = 'AMBIGUOUS_WRITE_RECONCILIATION' AND v_match THEN
    SELECT * INTO v_registration_request FROM public.integration_api_interactions interaction
    WHERE interaction.integration_operation_id = v_target.id AND interaction.phase = 'REQUEST'
    ORDER BY interaction.attempt_number DESC, interaction.created_at DESC LIMIT 1;
    v_request_json := extensions.pgp_sym_decrypt(
      v_registration_request.request_payload_ciphertext,
      public.integration_payload_encryption_key(v_registration_request.payload_encryption_key_reference)
    )::pg_catalog.jsonb;
    UPDATE public.integration_operations SET state = 'SUCCESS', ambiguous_outcome = false,
      reconciliation_required = false, retry_allowed = false,
      business_remark_category = 'reconciled_client_master_match', completed_at = pg_catalog.now(),
      reconciliation_resolution_operation_id = v_verification.id
    WHERE id = v_target.id RETURNING * INTO v_target;
    UPDATE public.integration_accounts SET state = 'REGISTERED',
      external_account_id = v_request_json->'reg_details'->0->>'client_code',
      current_operation_id = v_target.id, updated_at = pg_catalog.now()
    WHERE id = v_target.integration_account_id;
  END IF;
  RETURN v_target;
END;
$$;

ALTER TABLE public.investor_registration_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investor_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investor_bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_api_interactions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.investor_registration_profiles,
  public.investor_addresses,
  public.investor_bank_accounts,
  public.integration_accounts,
  public.integration_operations,
  public.integration_api_interactions
FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, INSERT, UPDATE ON TABLE
  public.investor_registration_profiles,
  public.investor_addresses
TO service_role;

REVOKE ALL ON FUNCTION
  public.bank_account_encryption_key(pg_catalog.text),
  public.bank_account_lookup_hmac_key(pg_catalog.text),
  public.integration_payload_encryption_key(pg_catalog.text),
  public.integration_payload_has_forbidden_key(pg_catalog.jsonb),
  public.integration_header_metadata_is_safe(pg_catalog.jsonb, pg_catalog.text),
  public.reject_integration_api_interaction_mutation(),
  public.validate_integration_operation_scope(),
  public.validate_integration_interaction_scope(),
  public.validate_integration_account_current_operation(),
  public.enforce_integration_operation_transition(),
  public.nse_ucc_verification_evidence_matches(pg_catalog.uuid, pg_catalog.uuid)
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.set_investor_bank_account(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool),
  public.prepare_nse_ucc_registration(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.jsonb),
  public.get_nse_ucc_registration_source(pg_catalog.uuid),
  public.claim_nse_ucc_registration_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4),
  public.start_nse_ucc_submission(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.timestamptz),
  public.finish_nse_ucc_submission(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.timestamptz, pg_catalog.int8, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.text, pg_catalog.text, pg_catalog.int4),
  public.recover_expired_nse_ucc_events(pg_catalog.int4),
  public.record_nse_ucc_validation_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text),
  public.get_integration_account_state(pg_catalog.uuid),
  public.prepare_nse_ucc_verification(pg_catalog.uuid, pg_catalog.text),
  public.get_nse_ucc_verification_source(pg_catalog.uuid),
  public.recover_expired_nse_ucc_verification_events(pg_catalog.uuid, pg_catalog.int4),
  public.claim_nse_ucc_verification_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4),
  public.start_nse_ucc_verification(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb, pg_catalog.timestamptz),
  public.finish_nse_ucc_verification(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.timestamptz, pg_catalog.int8, pg_catalog.int4),
  public.distribute_nse_ucc_verification_result(pg_catalog.uuid, pg_catalog.uuid)
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
  public.set_investor_bank_account(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool),
  public.prepare_nse_ucc_registration(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.jsonb),
  public.get_nse_ucc_registration_source(pg_catalog.uuid),
  public.claim_nse_ucc_registration_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4),
  public.start_nse_ucc_submission(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.timestamptz),
  public.finish_nse_ucc_submission(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.timestamptz, pg_catalog.int8, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.text, pg_catalog.text, pg_catalog.int4),
  public.recover_expired_nse_ucc_events(pg_catalog.int4),
  public.record_nse_ucc_validation_failure(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text),
  public.get_integration_account_state(pg_catalog.uuid),
  public.prepare_nse_ucc_verification(pg_catalog.uuid, pg_catalog.text),
  public.get_nse_ucc_verification_source(pg_catalog.uuid),
  public.recover_expired_nse_ucc_verification_events(pg_catalog.uuid, pg_catalog.int4),
  public.claim_nse_ucc_verification_event(pg_catalog.uuid, pg_catalog.int4, pg_catalog.int4),
  public.start_nse_ucc_verification(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb, pg_catalog.timestamptz),
  public.finish_nse_ucc_verification(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb, pg_catalog.int4, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.bool, pg_catalog.bool, pg_catalog.timestamptz, pg_catalog.int8, pg_catalog.int4),
  public.distribute_nse_ucc_verification_result(pg_catalog.uuid, pg_catalog.uuid)
TO service_role;

COMMENT ON TABLE public.integration_api_interactions IS
  'Append-only encrypted API evidence. Each call has immutable REQUEST and RESULT rows sharing call_id.';
COMMENT ON COLUMN public.integration_api_interactions.payload_encryption_key_reference IS
  'Non-secret Vault key reference retained with ciphertext for controlled key rotation.';
COMMENT ON COLUMN public.integration_api_interactions.native_remark_category IS
  'Queryable sanitized category only; the exact NSE remark remains in encrypted response evidence.';
COMMENT ON FUNCTION public.recover_expired_nse_ucc_events(pg_catalog.int4) IS
  'Recovers proven pre-request crashes subject to attempt limits and marks post-request expiry for reconciliation.';

COMMIT;
