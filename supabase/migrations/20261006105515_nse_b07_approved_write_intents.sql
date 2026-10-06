-- B07 UAT-only approved mutations. Historical BLOCKED review rows are untouched.
BEGIN;
CREATE TABLE nse_bank_mandate.write_intents (
 id uuid PRIMARY KEY,
 workspace_id uuid NOT NULL REFERENCES public.workspaces(id),
 integration_account_id uuid NOT NULL REFERENCES public.integration_accounts(id),
 investor_profile_id uuid NOT NULL REFERENCES public.profiles(id),
 bank_account_id uuid NOT NULL REFERENCES public.investor_bank_accounts(id),
 action text NOT NULL CHECK(action IN ('MANDATE','BANK_ADD','BANK_DEL')),
 version integer NOT NULL DEFAULT 1 CHECK(version=1),
 business_terms jsonb NOT NULL,
 request_ciphertext bytea NOT NULL,
 request_hash bytea NOT NULL,
 member_reference text UNIQUE,
 actor_profile_id uuid NOT NULL REFERENCES public.profiles(id),
 actor_user_id uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(actor_profile_id=investor_profile_id),
 CHECK((action='MANDATE')=(member_reference IS NOT NULL))
);
CREATE TABLE nse_bank_mandate.approvals (
 intent_id uuid PRIMARY KEY REFERENCES nse_bank_mandate.write_intents(id),
 version integer NOT NULL CHECK(version=1),
 request_hash bytea NOT NULL,
 actor_profile_id uuid NOT NULL REFERENCES public.profiles(id),
 actor_user_id uuid NOT NULL REFERENCES auth.users(id),
 approved_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE nse_bank_mandate.revocations (
 intent_id uuid PRIMARY KEY REFERENCES nse_bank_mandate.write_intents(id),
 actor_user_id uuid NOT NULL REFERENCES auth.users(id),
 revoked_at timestamptz NOT NULL DEFAULT now()
);
-- Operator-provisioned designation is independent of investor approval. It is
-- private and has no browser/service insert API. No default test designation.
CREATE TABLE nse_bank_mandate.uat_cases (
 bank_account_id uuid NOT NULL REFERENCES public.investor_bank_accounts(id),
 integration_account_id uuid NOT NULL REFERENCES public.integration_accounts(id),
 designation_reference uuid NOT NULL,
 designation_sha256 bytea NOT NULL CHECK(octet_length(designation_sha256)=32),
 baseline_client_result_id uuid NOT NULL REFERENCES public.integration_api_interactions(id),
 baseline_mandate_result_id uuid NOT NULL REFERENCES public.integration_api_interactions(id),
 designated_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 PRIMARY KEY(bank_account_id,integration_account_id),
 CHECK(expires_at>designated_at AND expires_at<=designated_at+interval '1 day')
);
CREATE TABLE nse_bank_mandate.bank_relationships (
 add_operation_id uuid PRIMARY KEY REFERENCES public.integration_operations(id),
 bank_account_id uuid NOT NULL REFERENCES public.investor_bank_accounts(id),
 integration_account_id uuid NOT NULL REFERENCES public.integration_accounts(id),
 write_result_id uuid NOT NULL REFERENCES public.integration_api_interactions(id),
 verification_result_id uuid NOT NULL REFERENCES public.integration_api_interactions(id),
 verified_at timestamptz NOT NULL,
 is_default boolean NOT NULL,
 UNIQUE(bank_account_id,integration_account_id)
);
CREATE TABLE nse_bank_mandate.bank_deletion_receipts (
 operation_id uuid PRIMARY KEY REFERENCES public.integration_operations(id),
 add_operation_id uuid NOT NULL REFERENCES nse_bank_mandate.bank_relationships(add_operation_id),
 result_id uuid NOT NULL REFERENCES public.integration_api_interactions(id),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE nse_bank_mandate.reconciliations (
 operation_id uuid NOT NULL REFERENCES public.integration_operations(id),
 result_id uuid NOT NULL REFERENCES public.integration_api_interactions(id),
 classification text NOT NULL CHECK(classification IN ('MATCH','ZERO','MULTIPLE','MISMATCH','INVALID','DELETE_RECEIPT_ONLY')),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(operation_id,result_id)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['write_intents','approvals','revocations','uat_cases','bank_relationships','bank_deletion_receipts','reconciliations'] LOOP
  EXECUTE format('ALTER TABLE nse_bank_mandate.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON nse_bank_mandate.%I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON nse_bank_mandate.%I FOR EACH ROW EXECUTE FUNCTION nse_bank_mandate.immutable_intent()',t);
 END LOOP;
END $$;

CREATE FUNCTION nse_bank_mandate.request(p_id uuid) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT extensions.pgp_sym_decrypt(request_ciphertext,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'))::jsonb
 FROM nse_bank_mandate.write_intents WHERE id=p_id
$$;
CREATE FUNCTION nse_bank_mandate.owned_bank(p_workspace uuid,p_account uuid,p_bank uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM moneybowl_authz.lock_scope(p_workspace);
 IF NOT EXISTS(SELECT 1 FROM public.integration_accounts a JOIN public.investor_bank_accounts b
  ON b.id=p_bank AND b.workspace_id=a.workspace_id AND b.investor_profile_id=a.investor_profile_id
  WHERE a.id=p_account AND a.workspace_id=p_workspace AND a.investor_profile_id=public.current_user_profile_id()
   AND public.can_select_order_request(a.workspace_id,a.investor_profile_id)
   AND moneybowl_authz.member_role(a.workspace_id,a.investor_profile_id)='investor'
   AND a.integration_environment='UAT' AND a.integration_key='NSE_INVEST' AND a.state='REGISTERED'
   AND b.is_active AND b.verification_status='verified') THEN RAISE EXCEPTION 'b07_owner_required'; END IF;
END $$;
CREATE FUNCTION public.draft_nse_bank_mandate_write(p_workspace_id uuid,p_integration_account_id uuid,p_bank_account_id uuid,
 p_action text,p_terms jsonb,p_request_id uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a public.integration_accounts; b public.investor_bank_accounts; i nse_bank_mandate.write_intents;
 r jsonb; body jsonb; ref text; start_day date; end_day date; registration_day date;
BEGIN
 PERFORM nse_bank_mandate.owned_bank(p_workspace_id,p_integration_account_id,p_bank_account_id);
 IF p_request_id IS NULL OR p_action IS NULL OR p_action NOT IN ('MANDATE','BANK_ADD','BANK_DEL') OR jsonb_typeof(p_terms) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_request_id::text,17));
 SELECT * INTO a FROM public.integration_accounts WHERE id=p_integration_account_id FOR UPDATE;
 SELECT * INTO b FROM public.investor_bank_accounts WHERE id=p_bank_account_id FOR UPDATE;
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=p_request_id;
 IF i.id IS NOT NULL THEN
  IF (i.workspace_id,i.integration_account_id,i.bank_account_id,i.action,i.business_terms) IS DISTINCT FROM
   (p_workspace_id,p_integration_account_id,p_bank_account_id,p_action,p_terms) THEN RAISE EXCEPTION 'b07_intent_conflict'; END IF;
  RETURN i.id;
 END IF;
 IF a.external_account_id IS NULL OR a.external_account_id !~ '^[A-Za-z0-9_-]{1,20}$'
 OR EXISTS(SELECT 1 FROM public.integration_accounts other WHERE other.id<>a.id AND other.integration_key='NSE_INVEST' AND other.integration_environment='UAT' AND other.external_account_id=a.external_account_id)
 THEN RAISE EXCEPTION 'b07_ucc_scope_invalid'; END IF;
 r:=jsonb_build_object('client_code',a.external_account_id,'account_no',extensions.pgp_sym_decrypt(b.account_number_ciphertext,public.bank_account_encryption_key(b.account_number_key_reference)),
  'ifsc_code',b.ifsc_code);
 IF p_action='MANDATE' THEN
  IF length(a.external_account_id)>10 OR b.micr_code IS NOT NULL THEN RAISE EXCEPTION 'b07_mandate_micr_contract_unresolved'; END IF;
  IF NOT(p_terms ?& ARRAY['amount','mandate_type','start_date','end_date','processing'])
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_terms) k WHERE k NOT IN ('amount','mandate_type','start_date','end_date','processing','registration_date'))
   OR EXISTS(SELECT 1 FROM jsonb_each(p_terms) e WHERE jsonb_typeof(e.value)<>'string')
   OR p_terms->>'amount' !~ '^[0-9]{1,13}(\.[0-9]{1,2})?$' OR (p_terms->>'amount')::numeric<=0
   OR p_terms->>'mandate_type' NOT IN ('X','E') OR p_terms->>'processing' NOT IN ('MEMBER','PROVIDER')
   OR p_terms->>'start_date' !~ '^\d{2}/\d{2}/\d{4}$' OR p_terms->>'end_date' !~ '^\d{2}/\d{2}/\d{4}$'
   THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
  start_day:=to_date(p_terms->>'start_date','DD/MM/YYYY');end_day:=to_date(p_terms->>'end_date','DD/MM/YYYY');
  IF to_char(start_day,'DD/MM/YYYY')<>p_terms->>'start_date' OR to_char(end_day,'DD/MM/YYYY')<>p_terms->>'end_date'
   OR start_day<current_date OR end_day<start_day THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
  IF p_terms->>'processing'='MEMBER' THEN
   IF NOT(p_terms ? 'registration_date') OR p_terms->>'registration_date' !~ '^\d{2}/\d{2}/\d{4}$' THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
   registration_day:=to_date(p_terms->>'registration_date','DD/MM/YYYY');
   IF to_char(registration_day,'DD/MM/YYYY')<>p_terms->>'registration_date' OR registration_day>current_date OR registration_day>start_day THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
  ELSIF p_terms ? 'registration_date' THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
  ref:='MB'||left(replace(gen_random_uuid()::text,'-',''),18);
  r:=r||(p_terms-'processing')||jsonb_build_object('ac_type',CASE b.account_type WHEN 'savings' THEN 'SB' WHEN 'current' THEN 'CB' WHEN 'nre' THEN 'NE' WHEN 'nro' THEN 'NO' END,'member_mandate_no',ref);
  -- Optional MICR is omitted for this bounded subset. Non-empty MICR stays blocked.
  body:=jsonb_build_object('reg_data',jsonb_build_array(r));
 ELSE
  IF jsonb_typeof(p_terms->'default_bank_flag') IS DISTINCT FROM 'string' OR p_terms <> jsonb_build_object('default_bank_flag',p_terms->>'default_bank_flag') OR p_terms->>'default_bank_flag' NOT IN ('Y','N') OR NOT(p_terms ? 'default_bank_flag') THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
  IF p_action='BANK_DEL' AND (b.is_default OR p_terms->>'default_bank_flag'<>'N') THEN RAISE EXCEPTION 'b07_default_delete_protected'; END IF;
  r:=r||p_terms||jsonb_build_object('action_type',CASE p_action WHEN 'BANK_ADD' THEN 'ADD' ELSE 'DEL' END,
   'account_type',CASE b.account_type WHEN 'savings' THEN 'SB' WHEN 'current' THEN 'CB' WHEN 'nre' THEN 'NE' WHEN 'nro' THEN 'NO' END,'micr_no',coalesce(b.micr_code,''));
  body:=jsonb_build_object('bank_dtl',jsonb_build_array(r));
 END IF;
 INSERT INTO nse_bank_mandate.write_intents(id,workspace_id,integration_account_id,investor_profile_id,bank_account_id,action,business_terms,
 request_ciphertext,request_hash,member_reference,actor_profile_id,actor_user_id)
 VALUES(p_request_id,a.workspace_id,a.id,a.investor_profile_id,b.id,p_action,p_terms,
 extensions.pgp_sym_encrypt(body::text,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'),
 extensions.digest(body::text,'sha256'),ref,a.investor_profile_id,auth.uid());
 RETURN p_request_id;
END $$;
CREATE FUNCTION public.approve_nse_bank_mandate_write(p_intent_id uuid,p_version integer) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i nse_bank_mandate.write_intents;
BEGIN
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=p_intent_id FOR UPDATE;
 PERFORM nse_bank_mandate.owned_bank(i.workspace_id,i.integration_account_id,i.bank_account_id);
 IF i.id IS NULL OR p_version IS DISTINCT FROM i.version OR EXISTS(SELECT 1 FROM nse_bank_mandate.revocations WHERE intent_id=i.id) THEN RAISE EXCEPTION 'b07_approval_invalid'; END IF;
 INSERT INTO nse_bank_mandate.approvals(intent_id,version,request_hash,actor_profile_id,actor_user_id)
 VALUES(i.id,i.version,i.request_hash,public.current_user_profile_id(),auth.uid()) ON CONFLICT DO NOTHING;
 RETURN i.id;
END $$;
CREATE FUNCTION public.revoke_nse_bank_mandate_write(p_intent_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i nse_bank_mandate.write_intents;
BEGIN
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=p_intent_id FOR UPDATE;
 PERFORM nse_bank_mandate.owned_bank(i.workspace_id,i.integration_account_id,i.bank_account_id);
 IF EXISTS(SELECT 1 FROM public.integration_operations WHERE id=i.id AND state NOT IN ('PREPARED','QUEUED','SUBMISSION_FAILED')) THEN RAISE EXCEPTION 'b07_already_submitted'; END IF;
 INSERT INTO nse_bank_mandate.revocations(intent_id,actor_user_id) VALUES(i.id,auth.uid()) ON CONFLICT DO NOTHING;
END $$;
-- No raw bank, PAN or UCC is exposed in the approval display.
CREATE FUNCTION public.get_nse_bank_mandate_draft(p_intent_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i nse_bank_mandate.write_intents; masked text;
BEGIN
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=p_intent_id;
 PERFORM nse_bank_mandate.owned_bank(i.workspace_id,i.integration_account_id,i.bank_account_id);
 SELECT masked_account_number INTO masked FROM public.investor_bank_accounts WHERE id=i.bank_account_id;
 RETURN jsonb_build_object('id',i.id,'version',i.version,'action',i.action,'terms',i.business_terms,'bank_account_id',i.bank_account_id,
 'masked_account_number',masked,'created_at',i.created_at,'approved',EXISTS(SELECT 1 FROM nse_bank_mandate.approvals WHERE intent_id=i.id),'revoked',EXISTS(SELECT 1 FROM nse_bank_mandate.revocations WHERE intent_id=i.id));
END $$;
CREATE FUNCTION nse_bank_mandate.path(p_action text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE p_action WHEN 'MANDATE' THEN '/nsemfdesk/api/v2/registration/product/MANDATE' WHEN 'BANK_ADD' THEN '/nsemfdesk/api/v2/registration/CLIENTBANKDTL' WHEN 'BANK_DEL' THEN '/nsemfdesk/api/v2/registration/CLIENTBANKDTL' END
$$;
CREATE FUNCTION nse_bank_mandate.event(p_action text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE p_action WHEN 'MANDATE' THEN 'integration.nse.mandate_registration_requested' WHEN 'BANK_ADD' THEN 'integration.nse.bank_add_requested' WHEN 'BANK_DEL' THEN 'integration.nse.bank_del_requested' END
$$;
CREATE FUNCTION nse_bank_mandate.assert_send(p_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i nse_bank_mandate.write_intents; a public.integration_accounts; b public.investor_bank_accounts;
 c nse_bank_mandate.uat_cases; r jsonb; rel nse_bank_mandate.bank_relationships; baseline jsonb; latest public.integration_api_interactions;
BEGIN
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=p_id FOR UPDATE;
 SELECT * INTO a FROM public.integration_accounts WHERE id=i.integration_account_id FOR UPDATE;
 SELECT * INTO b FROM public.investor_bank_accounts WHERE id=i.bank_account_id FOR UPDATE;
 IF i.id IS NULL OR a.workspace_id IS DISTINCT FROM i.workspace_id OR a.investor_profile_id IS DISTINCT FROM i.investor_profile_id
  OR a.integration_environment<>'UAT' OR a.integration_key<>'NSE_INVEST' OR a.state<>'REGISTERED'
  OR b.workspace_id<>i.workspace_id OR b.investor_profile_id<>i.investor_profile_id OR NOT b.is_active OR b.verification_status<>'verified'
  OR NOT moneybowl_authz.profile_active(i.investor_profile_id) OR moneybowl_authz.member_role(i.workspace_id,i.investor_profile_id) IS DISTINCT FROM 'investor'
  OR NOT EXISTS(SELECT 1 FROM public.investor_account_links l WHERE l.profile_id=i.investor_profile_id AND l.user_id=i.actor_user_id AND l.link_status='active')
  OR NOT EXISTS(SELECT 1 FROM nse_bank_mandate.approvals ap WHERE ap.intent_id=i.id AND ap.version=i.version AND ap.request_hash=i.request_hash AND ap.actor_profile_id=i.investor_profile_id AND ap.actor_user_id=i.actor_user_id)
  OR EXISTS(SELECT 1 FROM nse_bank_mandate.revocations WHERE intent_id=i.id) THEN RAISE EXCEPTION 'b07_approved_authority_required'; END IF;
 r:=coalesce(nse_bank_mandate.request(i.id)->'reg_data'->0,nse_bank_mandate.request(i.id)->'bank_dtl'->0);
 IF r->>'client_code' IS DISTINCT FROM a.external_account_id OR r->>'account_no' IS DISTINCT FROM extensions.pgp_sym_decrypt(b.account_number_ciphertext,public.bank_account_encryption_key(b.account_number_key_reference))
  OR r->>'ifsc_code' IS DISTINCT FROM b.ifsc_code OR coalesce(r->>'micr_no','') IS DISTINCT FROM coalesce(b.micr_code,'')
  OR coalesce(r->>'account_type',r->>'ac_type') IS DISTINCT FROM (CASE b.account_type WHEN 'savings' THEN 'SB' WHEN 'current' THEN 'CB' WHEN 'nre' THEN 'NE' WHEN 'nro' THEN 'NO' END)
  OR EXISTS(SELECT 1 FROM public.integration_accounts x WHERE x.id<>a.id AND x.integration_key='NSE_INVEST' AND x.integration_environment='UAT' AND x.external_account_id=a.external_account_id)
 THEN RAISE EXCEPTION 'b07_frozen_source_changed'; END IF;
 SELECT * INTO c FROM nse_bank_mandate.uat_cases WHERE bank_account_id=b.id AND integration_account_id=a.id;
 IF c.bank_account_id IS NULL OR c.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'b07_designated_uat_case_required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.integration_api_interactions e JOIN public.integration_operations o ON o.id=e.integration_operation_id
  WHERE e.id=c.baseline_client_result_id AND e.phase='RESULT' AND e.normalized_outcome='SUCCESS' AND e.api_key='CLIENT_MASTER_REPORT'
  AND o.integration_account_id=a.id AND o.workspace_id=i.workspace_id AND e.integration_environment='UAT'
  AND e.completed_at>=c.designated_at-interval '15 minutes')
 OR NOT EXISTS(SELECT 1 FROM public.integration_api_interactions e JOIN public.integration_operations o ON o.id=e.integration_operation_id
  WHERE e.id=c.baseline_mandate_result_id AND e.phase='RESULT' AND e.api_key='MANDATE_STATUS' AND e.http_status BETWEEN 200 AND 299
  AND o.integration_account_id=a.id AND o.workspace_id=i.workspace_id AND e.integration_environment='UAT'
  AND e.completed_at>=c.designated_at-interval '15 minutes') THEN RAISE EXCEPTION 'b07_baseline_evidence_required'; END IF;
 SELECT extensions.pgp_sym_decrypt(e.response_payload_ciphertext,public.integration_payload_encryption_key(e.payload_encryption_key_reference))::jsonb INTO baseline
 FROM public.integration_api_interactions e WHERE e.id=c.baseline_client_result_id;
 IF baseline->>'response_status' IS DISTINCT FROM 'S' OR jsonb_typeof(baseline->'report_data') IS DISTINCT FROM 'array'
  OR jsonb_array_length(baseline->'report_data')<>1 OR baseline->'report_data'->0->>'client_code' IS DISTINCT FROM r->>'client_code'
 THEN RAISE EXCEPTION 'b07_baseline_scope_invalid'; END IF;
 SELECT extensions.pgp_sym_decrypt(e.response_payload_ciphertext,public.integration_payload_encryption_key(e.payload_encryption_key_reference))::jsonb INTO baseline
 FROM public.integration_api_interactions e WHERE e.id=c.baseline_mandate_result_id;
 IF baseline->>'response_status' IS DISTINCT FROM 'S' OR baseline->>'error_remark' IS DISTINCT FROM '' OR jsonb_typeof(baseline->'report_data') IS DISTINCT FROM 'array'
  OR (baseline->>'report_data_total' ~ '^\d+$') IS NOT TRUE OR (baseline->>'report_data_total')::integer<>jsonb_array_length(baseline->'report_data')
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(baseline->'report_data') row WHERE row->>'clientCode' IS DISTINCT FROM r->>'client_code')
 THEN RAISE EXCEPTION 'b07_baseline_scope_invalid'; END IF;
 IF i.action='BANK_DEL' AND EXISTS(SELECT 1 FROM jsonb_array_elements(baseline->'report_data') row WHERE row->>'bankAccountNumber'=r->>'account_no')
 THEN RAISE EXCEPTION 'b07_bank_dependencies_present'; END IF;
 IF i.action='MANDATE' AND to_date(r->>'start_date','DD/MM/YYYY')<current_date THEN RAISE EXCEPTION 'b07_terms_expired'; END IF;
 IF i.action='BANK_ADD' AND EXISTS(SELECT 1 FROM nse_bank_mandate.bank_relationships WHERE bank_account_id=b.id AND integration_account_id=a.id) THEN RAISE EXCEPTION 'b07_relationship_already_exists'; END IF;
 IF i.action='BANK_DEL' THEN
  SELECT * INTO rel FROM nse_bank_mandate.bank_relationships WHERE bank_account_id=b.id AND integration_account_id=a.id;
  IF b.is_default OR r->>'default_bank_flag'<>'N' OR rel.is_default THEN RAISE EXCEPTION 'b07_default_delete_protected'; END IF;
  IF rel.add_operation_id IS NULL OR EXISTS(SELECT 1 FROM nse_bank_mandate.bank_deletion_receipts WHERE add_operation_id=rel.add_operation_id)
   OR NOT EXISTS(SELECT 1 FROM public.integration_operations o WHERE o.id=rel.add_operation_id AND o.state='SUCCESS' AND o.completed_at>=c.designated_at)
   OR NOT EXISTS(SELECT 1 FROM public.integration_api_interactions e WHERE e.id=rel.write_result_id
    AND e.integration_operation_id=rel.add_operation_id AND e.phase='RESULT' AND e.normalized_outcome='SUCCESS'
    AND e.http_status BETWEEN 200 AND 299
    AND nse_bank_mandate.classify(rel.add_operation_id,false,convert_from(extensions.pgp_sym_decrypt_bytea(e.response_payload_ciphertext,public.integration_payload_encryption_key(e.payload_encryption_key_reference)),'UTF8'))='SUCCESS')
   THEN RAISE EXCEPTION 'b07_fresh_created_relationship_required'; END IF;
  SELECT e.* INTO latest FROM public.integration_api_interactions e JOIN public.integration_operations v ON v.id=e.integration_operation_id
   WHERE v.reconciliation_target_operation_id=rel.add_operation_id AND v.operation_type='BANK_MANDATE_VERIFY'
    AND v.api_key='CLIENT_MASTER_REPORT' AND e.phase='RESULT' ORDER BY e.completed_at DESC,e.created_at DESC,e.id DESC LIMIT 1;
  IF latest.id IS NULL OR latest.completed_at<clock_timestamp()-interval '15 minutes' OR latest.normalized_outcome<>'SUCCESS'
   OR nse_bank_mandate.classify(rel.add_operation_id,true,convert_from(extensions.pgp_sym_decrypt_bytea(latest.response_payload_ciphertext,public.integration_payload_encryption_key(latest.payload_encryption_key_reference)),'UTF8'))<>'MATCH'
   OR ((nse_bank_mandate.request(rel.add_operation_id)->'bank_dtl'->0)-'action_type') IS DISTINCT FROM (r-'action_type')
  THEN RAISE EXCEPTION 'b07_fresh_created_relationship_required'; END IF;
  IF EXISTS(SELECT 1 FROM nse_bank_mandate.write_intents m JOIN nse_bank_mandate.approvals ap ON ap.intent_id=m.id WHERE m.bank_account_id=b.id AND m.action='MANDATE')
   OR EXISTS(SELECT 1 FROM public.integration_operations o WHERE o.integration_account_id=a.id AND o.category IN ('TRANSACTION','PAYMENT','SYSTEMATIC') AND o.safety_class<>'READ_ONLY')
   OR EXISTS(SELECT 1 FROM public.order_requests o WHERE o.workspace_id=i.workspace_id AND o.investor_profile_id=i.investor_profile_id)
   THEN RAISE EXCEPTION 'b07_bank_dependencies_present'; END IF;
 END IF;
END $$;

CREATE FUNCTION public.prepare_nse_bank_mandate_write(p_intent_id uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i nse_bank_mandate.write_intents;
BEGIN
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=p_intent_id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.integration_operations WHERE id=i.id) THEN RETURN i.id; END IF;
 PERFORM nse_bank_mandate.assert_send(i.id);
 IF EXISTS(SELECT 1 FROM nse_bank_mandate.write_intents other JOIN public.integration_operations o ON o.id=other.id
  WHERE other.bank_account_id=i.bank_account_id AND other.integration_account_id=i.integration_account_id
  AND (o.state IN ('PREPARED','QUEUED','SUBMITTING','RECONCILIATION_REQUIRED') OR o.retry_allowed)) THEN RAISE EXCEPTION 'b07_active_write_exists'; END IF;
 INSERT INTO public.integration_operations(id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state)
 VALUES(i.id,i.workspace_id,i.integration_account_id,'NSE_INVEST','UAT','MANDATE',CASE i.action WHEN 'MANDATE' THEN 'WRITE_MANDATE' ELSE 'WRITE_CLIENT' END,'BANK_MANDATE_WRITE',i.action,'NNF_1.9.7','PREPARED');
 INSERT INTO public.event_outbox(event_type,entity_id,entity_type,payload,status)
 VALUES(nse_bank_mandate.event(i.action),i.id,'integration_operation',jsonb_build_object('integration_operation_id',i.id),'pending');
 UPDATE public.integration_operations SET state='QUEUED' WHERE id=i.id;
 RETURN i.id;
END $$;
CREATE FUNCTION public.get_nse_bank_mandate_write_source(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o public.integration_operations; i nse_bank_mandate.write_intents; request jsonb; path text;
BEGIN
 SELECT * INTO o FROM public.integration_operations WHERE id=p_operation_id AND integration_key='NSE_INVEST' AND integration_environment='UAT' AND operation_type IN ('BANK_MANDATE_WRITE','BANK_MANDATE_VERIFY');
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=CASE o.operation_type WHEN 'BANK_MANDATE_WRITE' THEN o.id ELSE o.reconciliation_target_operation_id END;
 IF i.id IS NULL THEN RAISE EXCEPTION 'b07_source_invalid'; END IF;
 request:=nse_bank_mandate.request(i.id);
 IF o.operation_type='BANK_MANDATE_WRITE' THEN
  PERFORM nse_bank_mandate.assert_send(i.id);path:=nse_bank_mandate.path(i.action);
 ELSIF i.action='MANDATE' THEN
  request:=jsonb_build_object('memberMandateIds',i.member_reference);path:='/nsemfdesk/api/v2/reports/MANDATE_STATUS';
 ELSE
  request:=jsonb_build_object('client_code',request->'bank_dtl'->0->>'client_code','PAN','','from_date','','to_date','');path:='/nsemfdesk/api/v2/reports/client_master_report';
 END IF;
 RETURN jsonb_build_object('operation_id',o.id,'action',i.action,'kind',CASE o.operation_type WHEN 'BANK_MANDATE_WRITE' THEN 'WRITE' ELSE 'READ' END,'request',request,'path',path);
END $$;
CREATE FUNCTION public.prepare_nse_bank_mandate_verification(p_write_id uuid,p_request_id uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o public.integration_operations; old public.integration_operations; api text;
BEGIN
 SELECT * INTO o FROM public.integration_operations WHERE id=p_write_id AND operation_type='BANK_MANDATE_WRITE' AND integration_environment='UAT' FOR UPDATE;
 IF o.id IS NULL OR o.state NOT IN ('SUCCESS','RECONCILIATION_REQUIRED') OR p_request_id IS NULL THEN RAISE EXCEPTION 'b07_verification_target_invalid'; END IF;
 SELECT * INTO old FROM public.integration_operations WHERE id=p_request_id;
 IF old.id IS NOT NULL THEN
  IF old.operation_type<>'BANK_MANDATE_VERIFY' OR old.reconciliation_target_operation_id<>o.id THEN RAISE EXCEPTION 'b07_verification_conflict'; END IF;RETURN old.id;
 END IF;
 api:=CASE o.api_key WHEN 'MANDATE' THEN 'MANDATE_STATUS' ELSE 'CLIENT_MASTER_REPORT' END;
 INSERT INTO public.integration_operations(id,workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state,reconciliation_target_operation_id)
 VALUES(p_request_id,o.workspace_id,o.integration_account_id,'NSE_INVEST','UAT','RECONCILIATION','READ_ONLY','BANK_MANDATE_VERIFY',api,'NNF_1.9.7','PREPARED',o.id);
 INSERT INTO public.event_outbox(event_type,entity_id,entity_type,payload,status)
 VALUES('integration.nse.bank_mandate_verify_requested',p_request_id,'integration_operation',jsonb_build_object('integration_operation_id',p_request_id),'pending');
 UPDATE public.integration_operations SET state='QUEUED' WHERE id=p_request_id;
 RETURN p_request_id;
END $$;
-- SQL classifies the captured provider bytes independently of worker claims.
CREATE FUNCTION nse_bank_mandate.classify(p_intent uuid,p_read boolean,p_raw text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i nse_bank_mandate.write_intents; j jsonb; r jsonb; row jsonb; rows jsonb; k text; expected jsonb;
BEGIN
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=p_intent;
 r:=coalesce(nse_bank_mandate.request(i.id)->'reg_data'->0,nse_bank_mandate.request(i.id)->'bank_dtl'->0);
 j:=p_raw::jsonb;
 IF NOT p_read THEN
  rows:=CASE i.action WHEN 'MANDATE' THEN j->'reg_data' ELSE j->'bank_dtl' END;
  IF jsonb_typeof(rows) IS DISTINCT FROM 'array' OR jsonb_array_length(rows)<>1 THEN RETURN 'AMBIGUOUS'; END IF;
  row:=rows->0;
  FOR k IN SELECT jsonb_object_keys(r) LOOP
   -- Bank response contract does not echo default_bank_flag.
   IF i.action<>'MANDATE' AND k='default_bank_flag' THEN CONTINUE; END IF;
   IF row->k IS DISTINCT FROM r->k THEN RETURN 'AMBIGUOUS'; END IF;
  END LOOP;
  IF i.action='MANDATE' AND row->>'reg_status'='REG_SUCCESS' AND nullif(btrim(row->>'reg_id'),'') IS NOT NULL THEN RETURN 'SUCCESS'; END IF;
  IF i.action<>'MANDATE' AND row->>'status'='SUCCESS' THEN RETURN 'SUCCESS'; END IF;
  IF i.action<>'MANDATE' AND row->>'status'='FAIL' THEN RETURN 'BUSINESS_FAILURE'; END IF;
  RETURN 'AMBIGUOUS';
 END IF;
 IF j->>'response_status' IS DISTINCT FROM 'S' OR j->>'error_remark' IS DISTINCT FROM '' OR jsonb_typeof(j->'report_data') IS DISTINCT FROM 'array'
  OR (j->>'report_data_total' ~ '^\d+$') IS NOT TRUE OR (j->>'report_data_total')::int<>jsonb_array_length(j->'report_data') THEN RETURN 'INVALID'; END IF;
 rows:=j->'report_data';
 IF jsonb_array_length(rows)=0 THEN RETURN 'ZERO'; END IF;
 IF jsonb_array_length(rows)<>1 THEN RETURN 'MULTIPLE'; END IF;
 row:=rows->0;
 IF i.action='MANDATE' THEN
  expected:=jsonb_build_object('clientCode',r->>'client_code','memberMandateId',r->>'member_mandate_no','bankAccountNumber',r->>'account_no','mandateType',r->>'mandate_type','startDate',r->>'start_date','endDate',r->>'end_date');
  FOR k IN SELECT jsonb_object_keys(expected) LOOP IF row->k IS DISTINCT FROM expected->k THEN RETURN 'MISMATCH'; END IF; END LOOP;
  IF nullif(btrim(row->>'mandateId'),'') IS NULL OR nullif(btrim(row->>'status'),'') IS NULL OR (row->>'amount' ~ '^[0-9]+(\.[0-9]{1,2})?$') IS NOT TRUE OR (row->>'amount')::numeric<>(r->>'amount')::numeric
   OR (r ? 'registration_date' AND row->>'registrationDate' IS DISTINCT FROM r->>'registration_date') THEN RETURN 'MISMATCH'; END IF;
  RETURN 'MATCH';
 END IF;
 IF row->>'client_code' IS DISTINCT FROM r->>'client_code' THEN RETURN 'MISMATCH'; END IF;
 -- Deletion is never reconciled from absence, including a complete empty row.
 IF i.action='BANK_DEL' THEN RETURN 'DELETE_RECEIPT_ONLY'; END IF;
 FOR n IN 1..5 LOOP
  IF row->>('account_no_'||n)=r->>'account_no' THEN
   IF row->>('account_type_'||n) IS DISTINCT FROM r->>'account_type' OR row->>('ifsc_code_'||n) IS DISTINCT FROM r->>'ifsc_code'
    OR coalesce(nullif(btrim(row->>('micr_no_'||n)),''),'') IS DISTINCT FROM r->>'micr_no'
    OR row->>('default_bank_flag_'||n) IS DISTINCT FROM (CASE r->>'default_bank_flag' WHEN 'Y' THEN 'YES' ELSE 'NO' END)
    THEN RETURN 'MISMATCH'; END IF;
   IF EXISTS(SELECT 1 FROM generate_series(n+1,5) x WHERE row->>('account_no_'||x)=r->>'account_no') THEN RETURN 'MULTIPLE'; END IF;
   RETURN 'MATCH';
  END IF;
 END LOOP;
 RETURN 'ZERO';
EXCEPTION WHEN OTHERS THEN RETURN CASE WHEN p_read THEN 'INVALID' ELSE 'AMBIGUOUS' END;
END $$;
CREATE FUNCTION public.claim_nse_bank_mandate_write(p_event_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.event_outbox; o public.integration_operations; req public.integration_api_interactions; recovered_id uuid;
BEGIN
 SELECT ev.* INTO e FROM public.event_outbox ev JOIN public.integration_operations op ON op.id=ev.entity_id
 WHERE ev.id=p_event_id AND op.operation_type IN ('BANK_MANDATE_WRITE','BANK_MANDATE_VERIFY') AND op.integration_environment='UAT'
 AND ev.event_type=CASE op.operation_type WHEN 'BANK_MANDATE_VERIFY' THEN 'integration.nse.bank_mandate_verify_requested' ELSE nse_bank_mandate.event(op.api_key) END
 AND ev.entity_type='integration_operation'
 FOR UPDATE OF ev SKIP LOCKED;
 IF e.id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO o FROM public.integration_operations WHERE id=e.entity_id FOR UPDATE;
 IF e.status='processing' AND e.claim_expires_at<=clock_timestamp() THEN
  IF o.state='SUBMITTING' THEN
   SELECT * INTO req FROM public.integration_api_interactions WHERE integration_operation_id=o.id AND phase='REQUEST' AND attempt_number=e.retry_count;
   IF req.id IS NULL THEN RAISE EXCEPTION 'b07_request_evidence_required'; END IF;
   IF o.operation_type='BANK_MANDATE_VERIFY' THEN
    -- Verification is READ_ONLY: an uncertain transport has no provider-side
    -- mutation risk, so close this attempt truthfully and allow a bounded retry.
    INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,started_at,response_payload_ciphertext,response_header_metadata,response_bytes,response_hash,completed_at,elapsed_ms,normalized_outcome,native_remark_category,ambiguous_outcome,reconciliation_required)
    VALUES(o.workspace_id,o.id,'NSE_INVEST','UAT',o.category,o.safety_class,o.operation_type,o.api_key,o.contract_version,req.endpoint_path,'POST',req.call_id,'RESULT',req.attempt_number,o.correlation_id,'integration_payload_encryption_key_v1',1,req.started_at,
     extensions.pgp_sym_encrypt_bytea(''::bytea,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'),'{}',0,extensions.digest(''::bytea,'sha256'),clock_timestamp(),0,'TRANSPORT_FAILURE','b07_read_lease_expired',false,false) RETURNING id INTO recovered_id;
    UPDATE public.integration_operations SET state='SUBMISSION_FAILED',retry_allowed=e.retry_count<3,ambiguous_outcome=false,reconciliation_required=false,business_remark_category='b07_read_lease_expired',last_interaction_id=recovered_id,completed_at=clock_timestamp() WHERE id=o.id;
    UPDATE public.event_outbox SET status='failed',claim_token=NULL,claimed_by=NULL,claim_expires_at=NULL,error_message=CASE WHEN e.retry_count<3 THEN 'b07_read_retryable' ELSE 'b07_read_attempts_exhausted' END WHERE id=e.id;
   ELSE
    -- A persisted write request with lost result may have left this process.
    -- Never resend an uncertain mutation.
    INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,started_at,response_payload_ciphertext,response_header_metadata,response_bytes,response_hash,completed_at,elapsed_ms,normalized_outcome,native_remark_category,ambiguous_outcome,reconciliation_required)
    VALUES(o.workspace_id,o.id,'NSE_INVEST','UAT',o.category,o.safety_class,o.operation_type,o.api_key,o.contract_version,req.endpoint_path,'POST',req.call_id,'RESULT',req.attempt_number,o.correlation_id,'integration_payload_encryption_key_v1',1,req.started_at,
     extensions.pgp_sym_encrypt_bytea(''::bytea,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'),'{}',0,extensions.digest(''::bytea,'sha256'),clock_timestamp(),0,'AMBIGUOUS','b07_expired_after_request',true,true) RETURNING id INTO recovered_id;
    UPDATE public.integration_operations SET state='RECONCILIATION_REQUIRED',retry_allowed=false,ambiguous_outcome=true,reconciliation_required=true,business_remark_category='b07_expired_after_request',last_interaction_id=recovered_id,completed_at=clock_timestamp() WHERE id=o.id;
    UPDATE public.event_outbox SET status='failed',claim_token=NULL,claimed_by=NULL,claim_expires_at=NULL,error_message='b07_reconciliation_required' WHERE id=e.id;
    RETURN NULL;
   END IF;
  END IF;
  UPDATE public.integration_operations SET state='SUBMISSION_FAILED',retry_allowed=e.retry_count<3 WHERE id=o.id;
  UPDATE public.event_outbox SET status='failed',claim_token=NULL,claimed_by=NULL,claim_expires_at=NULL WHERE id=e.id;
  SELECT * INTO o FROM public.integration_operations WHERE id=o.id;
  SELECT * INTO e FROM public.event_outbox WHERE id=e.id;
 END IF;
 IF e.retry_count>=3 OR o.reconciliation_required OR NOT ((e.status='pending' AND o.state='QUEUED') OR (e.status='failed' AND o.state='SUBMISSION_FAILED' AND o.retry_allowed)) THEN RETURN NULL; END IF;
 UPDATE public.event_outbox SET status='processing',retry_count=retry_count+1,claimed_at=clock_timestamp(),claim_token=gen_random_uuid(),claim_expires_at=clock_timestamp()+interval '120 seconds',updated_at=clock_timestamp() WHERE id=e.id RETURNING * INTO e;
 RETURN jsonb_build_object('event_id',e.id,'operation_id',o.id,'claim_token',e.claim_token,'attempt',e.retry_count);
END $$;
CREATE FUNCTION public.start_nse_bank_mandate_write(p_event_id uuid,p_claim_token uuid,p_call_id uuid,p_request text,p_headers jsonb,p_started_at timestamptz)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.event_outbox; o public.integration_operations; old public.integration_api_interactions; src jsonb; result_id uuid;
BEGIN
 SELECT * INTO e FROM public.event_outbox WHERE id=p_event_id FOR UPDATE;
 SELECT * INTO o FROM public.integration_operations WHERE id=e.entity_id FOR UPDATE;
 IF p_call_id IS NULL OR p_started_at IS NULL OR e.status<>'processing' OR e.claim_token IS DISTINCT FROM p_claim_token OR p_claim_token IS NULL OR e.claim_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
 src:=public.get_nse_bank_mandate_write_source(o.id);
 IF p_request::jsonb IS DISTINCT FROM src->'request' OR NOT public.integration_header_metadata_is_safe(p_headers,'REQUEST')
 OR p_headers->>'content_type' IS DISTINCT FROM 'application/json' OR p_headers->>'accept' IS DISTINCT FROM 'application/json' THEN RAISE EXCEPTION 'b07_exact_request_required'; END IF;
 SELECT * INTO old FROM public.integration_api_interactions WHERE call_id=p_call_id AND phase='REQUEST';
 IF old.id IS NOT NULL THEN
  IF old.integration_operation_id<>o.id OR old.attempt_number<>e.retry_count OR old.request_hash IS DISTINCT FROM extensions.digest(p_request,'sha256') OR old.started_at IS DISTINCT FROM p_started_at OR old.request_header_metadata IS DISTINCT FROM p_headers THEN RAISE EXCEPTION 'b07_evidence_conflict'; END IF;RETURN old.id;
 END IF;
 IF o.state NOT IN ('QUEUED','SUBMISSION_FAILED') OR (o.state='SUBMISSION_FAILED' AND NOT o.retry_allowed) THEN RAISE EXCEPTION 'b07_not_submittable'; END IF;
 INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,request_payload_ciphertext,request_header_metadata,request_content_type,request_bytes,request_hash,started_at,normalized_outcome)
 VALUES(o.workspace_id,o.id,'NSE_INVEST','UAT',o.category,o.safety_class,o.operation_type,o.api_key,o.contract_version,src->>'path','POST',p_call_id,'REQUEST',e.retry_count,o.correlation_id,'integration_payload_encryption_key_v1',1,
 extensions.pgp_sym_encrypt(p_request,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'),p_headers,'application/json',octet_length(p_request),extensions.digest(p_request,'sha256'),p_started_at,'REQUEST_RECORDED') RETURNING id INTO result_id;
 UPDATE public.integration_operations SET state='SUBMITTING',retry_allowed=false,attempt_count=e.retry_count,submitted_at=p_started_at,last_interaction_id=result_id WHERE id=o.id;
 RETURN result_id;
END $$;
CREATE FUNCTION public.finish_nse_bank_mandate_write(p_event_id uuid,p_claim_token uuid,p_call_id uuid,p_response_base64 text,p_http_status integer,p_headers jsonb,p_delivery text,p_completed_at timestamptz)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.event_outbox; o public.integration_operations; req public.integration_api_interactions; old public.integration_api_interactions;
 raw bytea; payload text; outcome text; v_state text; v_category text; retry boolean:=false; ambiguous boolean:=false; rid uuid; intent_id uuid;
BEGIN
 IF p_completed_at IS NULL OR p_delivery NOT IN ('PROVEN_NOT_SENT','MAYBE_SENT','SENT_WITH_RESULT') OR p_delivery IS NULL OR NOT public.integration_header_metadata_is_safe(p_headers,'RESULT') THEN RAISE EXCEPTION 'b07_result_invalid'; END IF;
 raw:=decode(p_response_base64,'base64');
 IF octet_length(raw)>1048576 OR replace(encode(raw,'base64'),E'\n','') IS DISTINCT FROM p_response_base64 THEN RAISE EXCEPTION 'b07_result_invalid'; END IF;
 IF (p_delivery='SENT_WITH_RESULT') IS DISTINCT FROM (p_http_status IS NOT NULL) OR (p_http_status IS NOT NULL AND p_http_status NOT BETWEEN 100 AND 599) OR (p_http_status IS NULL AND octet_length(raw)<>0) THEN RAISE EXCEPTION 'b07_result_invalid'; END IF;
 SELECT * INTO e FROM public.event_outbox WHERE id=p_event_id FOR UPDATE;
 SELECT * INTO o FROM public.integration_operations WHERE id=e.entity_id FOR UPDATE;
 SELECT * INTO req FROM public.integration_api_interactions WHERE call_id=p_call_id AND phase='REQUEST' AND integration_operation_id=o.id;
 IF req.id IS NULL OR o.operation_type NOT IN ('BANK_MANDATE_WRITE','BANK_MANDATE_VERIFY') THEN RAISE EXCEPTION 'b07_request_evidence_required'; END IF;
 BEGIN payload:=convert_from(raw,'UTF8'); EXCEPTION WHEN OTHERS THEN payload:=NULL; END;
 intent_id:=CASE o.operation_type WHEN 'BANK_MANDATE_WRITE' THEN o.id ELSE o.reconciliation_target_operation_id END;
 IF p_delivery='PROVEN_NOT_SENT' THEN
  outcome:='PRE_TRANSMISSION_FAILURE';v_category:='b07_proven_not_sent';v_state:='SUBMISSION_FAILED';retry:=e.retry_count<3;
 ELSIF p_delivery='MAYBE_SENT' AND o.operation_type='BANK_MANDATE_VERIFY' THEN
  -- READ_ONLY verification can be retried safely even if the previous read may
  -- have reached NSE; there is no provider-side business mutation to duplicate.
  outcome:='TRANSPORT_FAILURE';v_category:='b07_read_transport_failure';v_state:='SUBMISSION_FAILED';retry:=e.retry_count<3;
 ELSIF p_delivery='MAYBE_SENT' THEN
  outcome:='AMBIGUOUS';v_category:='b07_maybe_sent';v_state:='RECONCILIATION_REQUIRED';ambiguous:=true;
 ELSIF o.operation_type='BANK_MANDATE_VERIFY' THEN
  IF p_http_status IN (408,429,500,502,503,504) THEN
   outcome:='HTTP_FAILURE';v_category:='b07_read_http_retryable';v_state:='SUBMISSION_FAILED';retry:=e.retry_count<3;
  ELSIF p_http_status NOT BETWEEN 200 AND 299 THEN
   outcome:='HTTP_FAILURE';v_category:='b07_read_http_failure';v_state:='HTTP_FAILED';
  ELSE
   v_category:=nse_bank_mandate.classify(intent_id,true,payload);
   outcome:=CASE v_category WHEN 'MATCH' THEN 'SUCCESS' ELSE 'BUSINESS_FAILURE' END;
   v_state:=CASE outcome WHEN 'SUCCESS' THEN 'SUCCESS' ELSE 'BUSINESS_FAILED' END;
  END IF;
 ELSIF p_http_status IN (400,403) THEN
  -- Match the established UCC write policy: these provider responses are
  -- definitive request failures, not uncertain mutations.
  outcome:='HTTP_FAILURE';v_category:='b07_http_definitive_failure';v_state:='HTTP_FAILED';
 ELSE
  outcome:=CASE WHEN p_http_status BETWEEN 200 AND 299 THEN nse_bank_mandate.classify(intent_id,false,payload) ELSE 'AMBIGUOUS' END;
  v_state:=CASE outcome WHEN 'SUCCESS' THEN 'SUCCESS' WHEN 'BUSINESS_FAILURE' THEN 'BUSINESS_FAILED' ELSE 'RECONCILIATION_REQUIRED' END;
  ambiguous:=outcome='AMBIGUOUS';v_category:='b07_'||lower(outcome);
 END IF;
 SELECT * INTO old FROM public.integration_api_interactions WHERE call_id=p_call_id AND phase='RESULT';
 IF old.id IS NOT NULL THEN
  IF old.integration_operation_id<>o.id OR old.response_hash IS DISTINCT FROM extensions.digest(raw,'sha256') OR old.http_status IS DISTINCT FROM p_http_status
   OR old.response_header_metadata IS DISTINCT FROM p_headers OR old.normalized_outcome IS DISTINCT FROM outcome OR old.completed_at IS DISTINCT FROM p_completed_at THEN RAISE EXCEPTION 'b07_evidence_conflict'; END IF;
  RETURN jsonb_build_object('result_id',old.id,'outcome',old.native_remark_category);
 END IF;
 IF e.status<>'processing' OR e.claim_token IS DISTINCT FROM p_claim_token OR p_claim_token IS NULL OR e.claim_expires_at<=clock_timestamp() OR req.attempt_number<>e.retry_count OR o.state<>'SUBMITTING' THEN RAISE EXCEPTION 'claim_not_owned'; END IF;
 INSERT INTO public.integration_api_interactions(workspace_id,integration_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,started_at,response_payload_ciphertext,response_header_metadata,response_content_type,response_bytes,response_hash,http_status,http_success,completed_at,elapsed_ms,normalized_outcome,native_remark_category,ambiguous_outcome,reconciliation_required)
 VALUES(o.workspace_id,o.id,'NSE_INVEST','UAT',o.category,o.safety_class,o.operation_type,o.api_key,o.contract_version,req.endpoint_path,'POST',p_call_id,'RESULT',req.attempt_number,o.correlation_id,'integration_payload_encryption_key_v1',1,req.started_at,
 extensions.pgp_sym_encrypt_bytea(raw,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'),p_headers,p_headers->>'content_type',octet_length(raw),extensions.digest(raw,'sha256'),p_http_status,p_http_status BETWEEN 200 AND 299,p_completed_at,greatest(0,(extract(epoch FROM p_completed_at-req.started_at)*1000)::bigint),outcome,v_category,ambiguous,ambiguous) RETURNING id INTO rid;
 UPDATE public.integration_operations op SET state=v_state,retry_allowed=retry,ambiguous_outcome=ambiguous,reconciliation_required=ambiguous,completed_at=p_completed_at,last_interaction_id=rid,business_remark_category=v_category WHERE op.id=o.id;
 UPDATE public.event_outbox SET status=CASE WHEN v_state IN ('SUBMISSION_FAILED','RECONCILIATION_REQUIRED') THEN 'failed' ELSE 'completed' END,claim_token=NULL,claimed_by=NULL,claim_expires_at=NULL,error_message=CASE WHEN v_state IN ('SUBMISSION_FAILED','RECONCILIATION_REQUIRED') THEN v_category ELSE NULL END,updated_at=clock_timestamp() WHERE id=e.id;
 IF o.operation_type='BANK_MANDATE_WRITE' AND o.api_key='BANK_DEL' AND outcome='SUCCESS' THEN
  INSERT INTO nse_bank_mandate.bank_deletion_receipts(operation_id,add_operation_id,result_id)
  SELECT o.id,rel.add_operation_id,rid FROM nse_bank_mandate.bank_relationships rel JOIN nse_bank_mandate.write_intents i ON i.id=o.id
   WHERE rel.bank_account_id=i.bank_account_id AND rel.integration_account_id=i.integration_account_id;
 END IF;
 IF o.operation_type='BANK_MANDATE_VERIFY' AND p_delivery='SENT_WITH_RESULT' THEN
  INSERT INTO nse_bank_mandate.reconciliations(operation_id,result_id,classification) VALUES(intent_id,rid,v_category);
 END IF;
 RETURN jsonb_build_object('result_id',rid,'outcome',v_category);
END $$;
CREATE FUNCTION nse_bank_mandate.evidence_matches(p_target uuid,p_verification uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.integration_operations w JOIN public.integration_operations v ON v.reconciliation_target_operation_id=w.id
 JOIN public.integration_api_interactions e ON e.integration_operation_id=v.id AND e.phase='RESULT'
 WHERE w.id=p_target AND v.id=p_verification AND w.operation_type='BANK_MANDATE_WRITE' AND v.operation_type='BANK_MANDATE_VERIFY'
 AND v.integration_account_id=w.integration_account_id AND v.workspace_id=w.workspace_id AND w.integration_environment='UAT' AND v.integration_environment='UAT'
 AND e.http_status BETWEEN 200 AND 299 AND e.normalized_outcome='SUCCESS'
 AND nse_bank_mandate.classify(w.id,true,convert_from(extensions.pgp_sym_decrypt_bytea(e.response_payload_ciphertext,public.integration_payload_encryption_key(e.payload_encryption_key_reference)),'UTF8'))='MATCH')
$$;
CREATE FUNCTION public.reconcile_nse_bank_mandate_write(p_verification_id uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v public.integration_operations; w public.integration_operations; i nse_bank_mandate.write_intents; e public.integration_api_interactions; receipt uuid;
BEGIN
 SELECT * INTO v FROM public.integration_operations WHERE id=p_verification_id AND operation_type='BANK_MANDATE_VERIFY';
 SELECT * INTO w FROM public.integration_operations WHERE id=v.reconciliation_target_operation_id AND operation_type='BANK_MANDATE_WRITE' FOR UPDATE;
 IF w.id IS NULL THEN RAISE EXCEPTION 'b07_verification_target_invalid'; END IF;
 IF NOT nse_bank_mandate.evidence_matches(w.id,v.id) THEN RETURN 'b07_reconciliation_unresolved'; END IF;
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=w.id;
 SELECT * INTO e FROM public.integration_api_interactions WHERE integration_operation_id=v.id AND phase='RESULT' AND normalized_outcome='SUCCESS' ORDER BY created_at DESC LIMIT 1;
 IF w.state='RECONCILIATION_REQUIRED' THEN
  UPDATE public.integration_operations SET state='SUCCESS',reconciliation_required=false,ambiguous_outcome=false,retry_allowed=false,reconciliation_resolution_operation_id=v.id,business_remark_category='b07_reconciled' WHERE id=w.id;
 END IF;
 IF i.action='BANK_ADD' THEN
  SELECT id INTO receipt FROM public.integration_api_interactions WHERE integration_operation_id=w.id AND phase='RESULT' ORDER BY attempt_number DESC,completed_at DESC,created_at DESC,id DESC LIMIT 1;
  -- Positive read projects the relationship. assert_send separately requires
  -- native ADD success before this relationship can be a deletion target.
  IF receipt IS NOT NULL THEN
   INSERT INTO nse_bank_mandate.bank_relationships(add_operation_id,bank_account_id,integration_account_id,write_result_id,verification_result_id,verified_at,is_default)
   VALUES(w.id,i.bank_account_id,i.integration_account_id,receipt,e.id,e.completed_at,i.business_terms->>'default_bank_flag'='Y') ON CONFLICT DO NOTHING;
  END IF;
 END IF;
 RETURN 'b07_reconciled';
END $$;
CREATE FUNCTION nse_bank_mandate.audit_authority() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i nse_bank_mandate.write_intents; kind text;
BEGIN
 SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=(CASE TG_TABLE_NAME WHEN 'write_intents' THEN to_jsonb(NEW)->>'id' ELSE to_jsonb(NEW)->>'intent_id' END)::uuid;
 kind:=CASE TG_TABLE_NAME WHEN 'write_intents' THEN 'drafted' WHEN 'approvals' THEN 'approved' ELSE 'revoked' END;
 INSERT INTO public.workspace_audit_logs(workspace_id,actor_id,action,event_type,target_type,entity_type,target_id,entity_id,actor_type,reason,payload)
 VALUES(i.workspace_id,i.actor_profile_id,'nse.bank_mandate.'||kind,'nse.bank_mandate.'||kind,'nse_bank_mandate_write','nse_bank_mandate_write',i.id,i.id,'investor','b07_'||kind,jsonb_build_object('action',i.action,'version',i.version));
 RETURN NEW;
END $$;
CREATE TRIGGER authority_audit AFTER INSERT ON nse_bank_mandate.write_intents FOR EACH ROW EXECUTE FUNCTION nse_bank_mandate.audit_authority();
CREATE TRIGGER authority_audit AFTER INSERT ON nse_bank_mandate.approvals FOR EACH ROW EXECUTE FUNCTION nse_bank_mandate.audit_authority();
CREATE TRIGGER authority_audit AFTER INSERT ON nse_bank_mandate.revocations FOR EACH ROW EXECUTE FUNCTION nse_bank_mandate.audit_authority();
CREATE FUNCTION nse_bank_mandate.guard_event() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP<>'INSERT' AND OLD.event_type IN ('integration.nse.mandate_registration_requested','integration.nse.bank_add_requested','integration.nse.bank_del_requested','integration.nse.bank_mandate_verify_requested') THEN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'b07_event_immutable'; END IF;
  IF (NEW.event_type,NEW.entity_id,NEW.entity_type,NEW.payload,NEW.id,NEW.created_at) IS DISTINCT FROM (OLD.event_type,OLD.entity_id,OLD.entity_type,OLD.payload,OLD.id,OLD.created_at) THEN RAISE EXCEPTION 'b07_event_immutable'; END IF;
 ELSIF NEW.event_type IN ('integration.nse.mandate_registration_requested','integration.nse.bank_add_requested','integration.nse.bank_del_requested','integration.nse.bank_mandate_verify_requested') THEN
  IF TG_OP='UPDATE' OR NEW.entity_type<>'integration_operation' OR NEW.payload IS DISTINCT FROM jsonb_build_object('integration_operation_id',NEW.entity_id)
  OR NOT EXISTS(SELECT 1 FROM public.integration_operations o WHERE o.id=NEW.entity_id AND o.integration_key='NSE_INVEST' AND o.integration_environment='UAT'
   AND NEW.event_type=CASE o.operation_type WHEN 'BANK_MANDATE_WRITE' THEN nse_bank_mandate.event(o.api_key) WHEN 'BANK_MANDATE_VERIFY' THEN 'integration.nse.bank_mandate_verify_requested' END)
  THEN RAISE EXCEPTION 'b07_event_invalid'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;RETURN NEW;
END $$;
CREATE TRIGGER b07_write_event_guard BEFORE INSERT OR UPDATE OR DELETE ON public.event_outbox FOR EACH ROW EXECUTE FUNCTION nse_bank_mandate.guard_event();
CREATE UNIQUE INDEX b07_one_event ON public.event_outbox(entity_id) WHERE event_type IN ('integration.nse.mandate_registration_requested','integration.nse.bank_add_requested','integration.nse.bank_del_requested','integration.nse.bank_mandate_verify_requested');

DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='nse_bank_mandate' OR (n.nspname='public' AND p.proname IN ('draft_nse_bank_mandate_write','approve_nse_bank_mandate_write','revoke_nse_bank_mandate_write','get_nse_bank_mandate_draft','prepare_nse_bank_mandate_write','get_nse_bank_mandate_write_source','prepare_nse_bank_mandate_verification','claim_nse_bank_mandate_write','start_nse_bank_mandate_write','finish_nse_bank_mandate_write','reconcile_nse_bank_mandate_write')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.draft_nse_bank_mandate_write(uuid,uuid,uuid,text,jsonb,uuid),public.approve_nse_bank_mandate_write(uuid,integer),public.revoke_nse_bank_mandate_write(uuid),public.get_nse_bank_mandate_draft(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_nse_bank_mandate_write(uuid),public.get_nse_bank_mandate_write_source(uuid),public.prepare_nse_bank_mandate_verification(uuid,uuid),public.claim_nse_bank_mandate_write(uuid),public.start_nse_bank_mandate_write(uuid,uuid,uuid,text,jsonb,timestamptz),public.finish_nse_bank_mandate_write(uuid,uuid,uuid,text,integer,jsonb,text,timestamptz),public.reconcile_nse_bank_mandate_write(uuid) TO service_role;

-- Preserve existing transition rules; add only exact B07 positive read evidence.
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
      AND (public.nse_ucc_verification_evidence_matches(
        OLD.id, NEW.reconciliation_resolution_operation_id
      ) OR (OLD.operation_type='BANK_MANDATE_WRITE' AND nse_bank_mandate.evidence_matches(OLD.id,NEW.reconciliation_resolution_operation_id)))
    )
    OR (
      OLD.state = 'HTTP_FAILED'
      AND NEW.state = 'SUBMISSION_FAILED'
      AND OLD.integration_key = 'NSE_INVEST'
      AND OLD.integration_environment = 'UAT'
      AND OLD.category = 'RECONCILIATION'
      AND OLD.safety_class = 'READ_ONLY'
      AND OLD.operation_type = 'UCC_VERIFICATION'
      AND OLD.api_key = 'CLIENT_MASTER_REPORT'
      AND NEW.retry_allowed
      AND NOT NEW.ambiguous_outcome
      AND NOT NEW.reconciliation_required
      AND COALESCE(pg_catalog.current_setting('app.nse_ucc_retryable_http_reopen', true), '') = 'enabled'
    )
  ) THEN RAISE EXCEPTION 'invalid_integration_operation_transition'; END IF;
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_dispatchable_outbox_events(
  p_event_types pg_catalog.text[],
  p_limit pg_catalog.int4 DEFAULT 10,
  p_retry_delay_seconds pg_catalog.int4 DEFAULT 30
)
RETURNS TABLE (
  event_outbox_id pg_catalog.uuid,
  event_type pg_catalog.text,
  event_status pg_catalog.text,
  retry_count pg_catalog.int4,
  claim_expires_at pg_catalog.timestamptz,
  created_at pg_catalog.timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_event_types IS NULL
     OR pg_catalog.cardinality(p_event_types) < 1
     OR pg_catalog.cardinality(p_event_types) > 32 THEN
    RAISE EXCEPTION 'dispatch_event_types_invalid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.unnest(p_event_types) AS requested(event_type)
    WHERE NULLIF(pg_catalog.btrim(requested.event_type), '') IS NULL
       OR requested.event_type !~ '^[a-z0-9][a-z0-9_.-]{0,99}$'
  ) THEN
    RAISE EXCEPTION 'dispatch_event_type_invalid';
  END IF;

  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 50 THEN
    RAISE EXCEPTION 'dispatch_limit_invalid';
  END IF;

  IF p_retry_delay_seconds IS NULL
     OR p_retry_delay_seconds < 0
     OR p_retry_delay_seconds > 3600 THEN
    RAISE EXCEPTION 'dispatch_retry_delay_invalid';
  END IF;

  RETURN QUERY
  SELECT feed.* FROM (
  SELECT
    event.id AS event_outbox_id,
    event.event_type,
    event.status AS event_status,
    event.retry_count,
    event.claim_expires_at,
    event.created_at
  FROM public.event_outbox AS event
  JOIN public.integration_operations AS operation
    ON event.entity_type = 'integration_operation'
   AND operation.id = event.entity_id
  WHERE event.event_type = ANY (p_event_types)
    AND NOT operation.ambiguous_outcome
    AND NOT operation.reconciliation_required
    AND (
      (
        event.status = 'pending'
        AND operation.state = 'QUEUED'
      )
      OR (
        event.status = 'failed'
        AND operation.state = 'SUBMISSION_FAILED'
        AND operation.retry_allowed
        AND event.updated_at <= pg_catalog.now()
          - pg_catalog.make_interval(secs => p_retry_delay_seconds)
      )
      OR (
        event.status = 'processing'
        AND event.claim_expires_at IS NOT NULL
        AND event.claim_expires_at <= pg_catalog.now()
        AND (operation.state IN ('QUEUED', 'SUBMITTING')
          OR (operation.operation_type IN ('ORDER_STATUS','PROV_ORDERS','CLIENT_READINESS','ORDER_FUNDING','SETTLEMENT_REDEMPTION','SIP_XSIP_REPORTS','STP_SWP_REPORTS','MANDATE_STATUS') AND operation.safety_class = 'READ_ONLY'
            AND operation.state = 'SUBMISSION_FAILED' AND operation.retry_allowed)
          OR (operation.operation_type IN ('BANK_MANDATE_WRITE','BANK_MANDATE_VERIFY') AND operation.state='SUBMISSION_FAILED' AND operation.retry_allowed))
      )
    )
  UNION ALL
  SELECT e.id,e.event_type,e.status,e.retry_count,e.claim_expires_at,e.created_at
  FROM public.event_outbox e JOIN nse_reference.jobs j ON j.event_id=e.id AND j.id=e.entity_id
  JOIN nse_reference.connections c ON c.id=j.connection_id AND c.workspace_id=j.workspace_id
  JOIN public.workspaces w ON w.id=j.workspace_id
  WHERE e.event_type='integration.nse.master_download_requested' AND e.entity_type='nse_reference_job'
    AND e.event_type=ANY(p_event_types) AND e.payload='{}'::jsonb AND c.enabled AND c.environment='UAT'
    AND w.workspace_status='active' AND NOT EXISTS(SELECT 1 FROM nse_reference.completions done WHERE done.id=j.id)
    AND (e.status='pending' OR (e.status='processing' AND e.claim_expires_at<=pg_catalog.now()))
  ) feed
  ORDER BY
    CASE WHEN feed.event_status = 'processing' THEN 0 ELSE 1 END,
    feed.created_at,
    feed.event_outbox_id
  LIMIT p_limit;
END;
$$;

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
  ELSIF NEW.operation_type = 'BANK_MANDATE_VERIFY' THEN
    IF NEW.category <> 'RECONCILIATION' OR NEW.safety_class <> 'READ_ONLY' OR NEW.operation_purpose IS NOT NULL
      OR NEW.integration_key<>'NSE_INVEST' OR NEW.integration_environment<>'UAT' OR NOT EXISTS (
       SELECT 1 FROM public.integration_operations target WHERE target.id=NEW.reconciliation_target_operation_id
        AND target.workspace_id=NEW.workspace_id AND target.integration_account_id=NEW.integration_account_id
        AND target.integration_key=NEW.integration_key AND target.integration_environment=NEW.integration_environment
        AND target.operation_type='BANK_MANDATE_WRITE'
        AND NEW.api_key=CASE target.api_key WHEN 'MANDATE' THEN 'MANDATE_STATUS' ELSE 'CLIENT_MASTER_REPORT' END
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
      AND ((NEW.operation_type='UCC_REGISTRATION' AND resolution.operation_type='UCC_VERIFICATION') OR (NEW.operation_type='BANK_MANDATE_WRITE' AND resolution.operation_type='BANK_MANDATE_VERIFY'))
  ) THEN RAISE EXCEPTION 'integration_reconciliation_resolution_mismatch'; END IF;
  RETURN NEW;
END;
$$;


COMMIT;
