-- B07 synthetic UAT operator authority.
-- This does not broaden browser/service authority. It exists only so a database
-- operator can exercise the already-merged UAT-only transport against an
-- explicitly designated synthetic fixture when no end-user Auth identity exists.
BEGIN;

ALTER TABLE nse_bank_mandate.write_intents
  ADD COLUMN authority_mode text NOT NULL DEFAULT 'INVESTOR'
    CHECK (authority_mode IN ('INVESTOR','UAT_OPERATOR')),
  ADD COLUMN operator_designation_reference uuid,
  ADD COLUMN operator_designation_sha256 bytea;

ALTER TABLE nse_bank_mandate.write_intents
  ALTER COLUMN actor_user_id DROP NOT NULL;

ALTER TABLE nse_bank_mandate.write_intents
  ADD CONSTRAINT b07_write_intent_authority_shape CHECK (
    (
      authority_mode='INVESTOR'
      AND actor_user_id IS NOT NULL
      AND operator_designation_reference IS NULL
      AND operator_designation_sha256 IS NULL
    )
    OR
    (
      authority_mode='UAT_OPERATOR'
      AND actor_user_id IS NULL
      AND operator_designation_reference IS NOT NULL
      AND operator_designation_sha256 IS NOT NULL
      AND octet_length(operator_designation_sha256)=32
    )
  );

CREATE FUNCTION nse_bank_mandate.create_operator_uat_intent(
  p_workspace_id uuid,
  p_integration_account_id uuid,
  p_bank_account_id uuid,
  p_action text,
  p_terms jsonb,
  p_request_id uuid,
  p_designation_reference uuid,
  p_designation_sha256 bytea
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  a public.integration_accounts;
  b public.investor_bank_accounts;
  i nse_bank_mandate.write_intents;
  c nse_bank_mandate.uat_cases;
  r jsonb;
  body jsonb;
  ref text;
  start_day date;
  end_day date;
  registration_day date;
BEGIN
  IF p_request_id IS NULL OR p_action NOT IN ('MANDATE','BANK_ADD','BANK_DEL')
    OR jsonb_typeof(p_terms) IS DISTINCT FROM 'object'
    OR p_designation_reference IS NULL OR p_designation_sha256 IS NULL
    OR octet_length(p_designation_sha256)<>32
  THEN RAISE EXCEPTION 'b07_operator_uat_terms_invalid'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_request_id::text,17));
  SELECT * INTO a FROM public.integration_accounts WHERE id=p_integration_account_id FOR UPDATE;
  SELECT * INTO b FROM public.investor_bank_accounts WHERE id=p_bank_account_id FOR UPDATE;
  SELECT * INTO c FROM nse_bank_mandate.uat_cases
   WHERE bank_account_id=p_bank_account_id AND integration_account_id=p_integration_account_id;

  IF a.id IS NULL OR b.id IS NULL
    OR a.workspace_id IS DISTINCT FROM p_workspace_id
    OR b.workspace_id IS DISTINCT FROM p_workspace_id
    OR b.investor_profile_id IS DISTINCT FROM a.investor_profile_id
    OR a.integration_key<>'NSE_INVEST' OR a.integration_environment<>'UAT' OR a.state<>'REGISTERED'
    OR NOT b.is_active OR b.verification_status<>'verified'
    OR NOT moneybowl_authz.profile_active(a.investor_profile_id)
    OR moneybowl_authz.member_role(a.workspace_id,a.investor_profile_id) IS DISTINCT FROM 'investor'
  THEN RAISE EXCEPTION 'b07_operator_uat_scope_invalid'; END IF;

  IF c.bank_account_id IS NULL OR c.expires_at<=clock_timestamp()
    OR c.designation_reference IS DISTINCT FROM p_designation_reference
    OR c.designation_sha256 IS DISTINCT FROM p_designation_sha256
  THEN RAISE EXCEPTION 'b07_designated_uat_case_required'; END IF;

  SELECT * INTO i FROM nse_bank_mandate.write_intents WHERE id=p_request_id;
  IF i.id IS NOT NULL THEN
    IF (i.workspace_id,i.integration_account_id,i.bank_account_id,i.action,i.business_terms,i.authority_mode,
        i.operator_designation_reference,i.operator_designation_sha256)
       IS DISTINCT FROM
       (p_workspace_id,p_integration_account_id,p_bank_account_id,p_action,p_terms,'UAT_OPERATOR',
        p_designation_reference,p_designation_sha256)
    THEN RAISE EXCEPTION 'b07_intent_conflict'; END IF;
    RETURN i.id;
  END IF;

  IF a.external_account_id IS NULL OR a.external_account_id !~ '^[A-Za-z0-9_-]{1,20}$'
    OR EXISTS(SELECT 1 FROM public.integration_accounts other
      WHERE other.id<>a.id AND other.integration_key='NSE_INVEST'
        AND other.integration_environment='UAT'
        AND other.external_account_id=a.external_account_id)
  THEN RAISE EXCEPTION 'b07_ucc_scope_invalid'; END IF;

  r:=jsonb_build_object(
    'client_code',a.external_account_id,
    'account_no',extensions.pgp_sym_decrypt(
      b.account_number_ciphertext,
      public.bank_account_encryption_key(b.account_number_key_reference)),
    'ifsc_code',b.ifsc_code
  );

  IF p_action='MANDATE' THEN
    IF length(a.external_account_id)>10 OR b.micr_code IS NOT NULL
    THEN RAISE EXCEPTION 'b07_mandate_micr_contract_unresolved'; END IF;
    IF NOT(p_terms ?& ARRAY['amount','mandate_type','start_date','end_date','processing'])
      OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_terms) k
        WHERE k NOT IN ('amount','mandate_type','start_date','end_date','processing','registration_date'))
      OR EXISTS(SELECT 1 FROM jsonb_each(p_terms) e WHERE jsonb_typeof(e.value)<>'string')
      OR p_terms->>'amount' !~ '^[0-9]{1,13}(\\.[0-9]{1,2})?$'
      OR (p_terms->>'amount')::numeric<=0
      OR p_terms->>'mandate_type' NOT IN ('X','E')
      OR p_terms->>'processing' NOT IN ('MEMBER','PROVIDER')
      OR p_terms->>'start_date' !~ '^\\d{2}/\\d{2}/\\d{4}$'
      OR p_terms->>'end_date' !~ '^\\d{2}/\\d{2}/\\d{4}$'
    THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
    start_day:=to_date(p_terms->>'start_date','DD/MM/YYYY');
    end_day:=to_date(p_terms->>'end_date','DD/MM/YYYY');
    IF to_char(start_day,'DD/MM/YYYY')<>p_terms->>'start_date'
      OR to_char(end_day,'DD/MM/YYYY')<>p_terms->>'end_date'
      OR start_day<current_date OR end_day<start_day
    THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
    IF p_terms->>'processing'='MEMBER' THEN
      IF NOT(p_terms ? 'registration_date')
        OR p_terms->>'registration_date' !~ '^\\d{2}/\\d{2}/\\d{4}$'
      THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
      registration_day:=to_date(p_terms->>'registration_date','DD/MM/YYYY');
      IF to_char(registration_day,'DD/MM/YYYY')<>p_terms->>'registration_date'
        OR registration_day>current_date OR registration_day>start_day
      THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
    ELSIF p_terms ? 'registration_date' THEN
      RAISE EXCEPTION 'b07_terms_invalid';
    END IF;
    ref:='MB'||left(replace(gen_random_uuid()::text,'-',''),18);
    r:=r||(p_terms-'processing')||jsonb_build_object(
      'ac_type',CASE b.account_type WHEN 'savings' THEN 'SB' WHEN 'current' THEN 'CB' WHEN 'nre' THEN 'NE' WHEN 'nro' THEN 'NO' END,
      'member_mandate_no',ref);
    body:=jsonb_build_object('reg_data',jsonb_build_array(r));
  ELSE
    IF jsonb_typeof(p_terms->'default_bank_flag') IS DISTINCT FROM 'string'
      OR p_terms <> jsonb_build_object('default_bank_flag',p_terms->>'default_bank_flag')
      OR p_terms->>'default_bank_flag' NOT IN ('Y','N')
      OR NOT(p_terms ? 'default_bank_flag')
    THEN RAISE EXCEPTION 'b07_terms_invalid'; END IF;
    IF p_action='BANK_DEL' AND (b.is_default OR p_terms->>'default_bank_flag'<>'N')
    THEN RAISE EXCEPTION 'b07_default_delete_protected'; END IF;
    r:=r||p_terms||jsonb_build_object(
      'action_type',CASE p_action WHEN 'BANK_ADD' THEN 'ADD' ELSE 'DEL' END,
      'account_type',CASE b.account_type WHEN 'savings' THEN 'SB' WHEN 'current' THEN 'CB' WHEN 'nre' THEN 'NE' WHEN 'nro' THEN 'NO' END,
      'micr_no',coalesce(b.micr_code,''));
    body:=jsonb_build_object('bank_dtl',jsonb_build_array(r));
  END IF;

  INSERT INTO nse_bank_mandate.write_intents(
    id,workspace_id,integration_account_id,investor_profile_id,bank_account_id,
    action,business_terms,request_ciphertext,request_hash,member_reference,
    actor_profile_id,actor_user_id,authority_mode,
    operator_designation_reference,operator_designation_sha256
  ) VALUES(
    p_request_id,a.workspace_id,a.id,a.investor_profile_id,b.id,
    p_action,p_terms,
    extensions.pgp_sym_encrypt(
      body::text,
      public.integration_payload_encryption_key('integration_payload_encryption_key_v1'),
      'cipher-algo=aes256, compress-algo=0'),
    extensions.digest(body::text,'sha256'),ref,
    a.investor_profile_id,NULL,'UAT_OPERATOR',
    p_designation_reference,p_designation_sha256
  );
  RETURN p_request_id;
END $$;

REVOKE ALL ON FUNCTION nse_bank_mandate.create_operator_uat_intent(
  uuid,uuid,uuid,text,jsonb,uuid,uuid,bytea
) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION nse_bank_mandate.assert_send(p_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
  OR NOT (
    (
      i.authority_mode='INVESTOR' AND i.actor_user_id IS NOT NULL
      AND EXISTS(SELECT 1 FROM public.investor_account_links l WHERE l.profile_id=i.investor_profile_id AND l.user_id=i.actor_user_id AND l.link_status='active')
      AND EXISTS(SELECT 1 FROM nse_bank_mandate.approvals ap WHERE ap.intent_id=i.id AND ap.version=i.version AND ap.request_hash=i.request_hash AND ap.actor_profile_id=i.investor_profile_id AND ap.actor_user_id=i.actor_user_id)
    )
    OR
    (
      i.authority_mode='UAT_OPERATOR' AND i.actor_user_id IS NULL
      AND i.operator_designation_reference IS NOT NULL AND i.operator_designation_sha256 IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM nse_bank_mandate.uat_cases c0
        WHERE c0.bank_account_id=i.bank_account_id
          AND c0.integration_account_id=i.integration_account_id
          AND c0.designation_reference=i.operator_designation_reference
          AND c0.designation_sha256=i.operator_designation_sha256
          AND c0.expires_at>clock_timestamp()
      )
    )
  )
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


CREATE OR REPLACE FUNCTION nse_bank_mandate.audit_authority()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  i nse_bank_mandate.write_intents;
  kind text;
  audit_actor uuid;
  audit_actor_type text;
BEGIN
  SELECT * INTO i FROM nse_bank_mandate.write_intents
   WHERE id=(CASE TG_TABLE_NAME WHEN 'write_intents' THEN to_jsonb(NEW)->>'id'
            ELSE to_jsonb(NEW)->>'intent_id' END)::uuid;
  IF TG_TABLE_NAME='write_intents' AND i.authority_mode='UAT_OPERATOR' THEN
    kind:='uat_operator_authorized';
    audit_actor:=NULL;
    audit_actor_type:='system';
  ELSE
    kind:=CASE TG_TABLE_NAME WHEN 'write_intents' THEN 'drafted'
         WHEN 'approvals' THEN 'approved' ELSE 'revoked' END;
    audit_actor:=i.actor_profile_id;
    audit_actor_type:='investor';
  END IF;
  INSERT INTO public.workspace_audit_logs(
    workspace_id,actor_id,action,event_type,target_type,entity_type,
    target_id,entity_id,actor_type,reason,payload
  ) VALUES(
    i.workspace_id,audit_actor,'nse.bank_mandate.'||kind,
    'nse.bank_mandate.'||kind,'nse_bank_mandate_write','nse_bank_mandate_write',
    i.id,i.id,audit_actor_type,'b07_'||kind,
    jsonb_build_object('action',i.action,'version',i.version,'authority_mode',i.authority_mode)
  );
  RETURN NEW;
END $$;

COMMIT;
