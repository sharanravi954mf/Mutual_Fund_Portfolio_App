-- Frozen V2-A: pre-UCC subject, with no changes to registered-account invariants.
BEGIN;
CREATE TABLE moneybowl_onboarding.kyc_cases (
 case_id uuid PRIMARY KEY REFERENCES moneybowl_onboarding.cases(id),
 workspace_id uuid NOT NULL REFERENCES public.workspaces(id),
 pan_hmac bytea NOT NULL,
 state text NOT NULL DEFAULT 'KYC_CHECK_REQUIRED' CHECK(state IN
 ('KYC_CHECK_REQUIRED','KYC_CHECKING','KYC_NOT_AVAILABLE','KYC_COMPLIANT','KYC_PROVIDER_REVIEW_REQUIRED',
 'EKYC_DETAILS_REQUIRED','EKYC_INITIATION_PENDING','EKYC_IN_PROGRESS','PROVIDER_RECONCILIATION_REQUIRED','BLOCKED')),
 UNIQUE(workspace_id,pan_hmac)
);
-- Explicit RTA selector commissioning boundary. No inferred scheme-code mapping.
CREATE TABLE moneybowl_onboarding.ekyc_amcs (
 code text PRIMARY KEY CHECK(code ~ '^[A-Z0-9_-]{1,20}$'),
 label text NOT NULL CHECK(length(label) BETWEEN 1 AND 150),
 source_reference text NOT NULL CHECK(length(source_reference)>0), active boolean NOT NULL DEFAULT true
);
CREATE TABLE moneybowl_onboarding.kyc_operations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), case_id uuid NOT NULL REFERENCES moneybowl_onboarding.kyc_cases(case_id),
 request_id uuid NOT NULL, api text NOT NULL CHECK(api IN ('CLIENT_KYC_REPORT','EKYCREG')),
 request_ciphertext bytea NOT NULL, state text NOT NULL DEFAULT 'QUEUED'
 CHECK(state IN ('QUEUED','CLAIMED','SUBMITTING','RETRY','DONE','RECONCILIATION_REQUIRED','BLOCKED')),
 attempt integer NOT NULL DEFAULT 0 CHECK(attempt BETWEEN 0 AND 3),
 call_id uuid, claim_token uuid, lease_until timestamptz,
 transmission text NOT NULL DEFAULT 'PROVEN_NOT_SENT' CHECK(transmission IN ('PROVEN_NOT_SENT','MAYBE_SENT','SENT_WITH_RESULT')),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(case_id,request_id)
);
CREATE UNIQUE INDEX onboarding_one_ekyc ON moneybowl_onboarding.kyc_operations(case_id) WHERE api='EKYCREG';
CREATE UNIQUE INDEX onboarding_one_active_kyc ON moneybowl_onboarding.kyc_operations(case_id)
 WHERE state IN ('QUEUED','CLAIMED','SUBMITTING','RETRY','RECONCILIATION_REQUIRED');
ALTER TABLE moneybowl_onboarding.kyc_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE moneybowl_onboarding.ekyc_amcs ENABLE ROW LEVEL SECURITY;
ALTER TABLE moneybowl_onboarding.kyc_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_api_interactions ADD COLUMN onboarding_operation_id uuid REFERENCES moneybowl_onboarding.kyc_operations(id);
ALTER TABLE public.integration_api_interactions ADD CONSTRAINT onboarding_evidence_subject CHECK
 (onboarding_operation_id IS NULL OR (integration_operation_id IS NULL AND operation_type='ONBOARDING_KYC' AND integration_environment='UAT'));
CREATE FUNCTION moneybowl_onboarding.kyc_evidence_scope() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.operation_type='ONBOARDING_KYC' THEN
 IF NOT EXISTS(SELECT 1 FROM moneybowl_onboarding.kyc_operations o JOIN moneybowl_onboarding.cases c ON c.id=o.case_id
 WHERE o.id=NEW.onboarding_operation_id AND c.workspace_id=NEW.workspace_id AND o.api=NEW.api_key
 AND NEW.correlation_id=o.id AND NEW.call_id=o.call_id AND NEW.attempt_number=o.attempt
 AND NEW.integration_key='NSE_INVEST' AND NEW.category='KYC_COMPLIANCE' AND NEW.contract_version='NNF_1.9.7'
 AND NEW.safety_class=CASE WHEN o.api='EKYCREG' THEN 'OTHER_MUTATING' ELSE 'READ_ONLY' END)
 THEN RAISE EXCEPTION 'onboarding_evidence_scope_invalid'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER onboarding_evidence_scope BEFORE INSERT ON public.integration_api_interactions FOR EACH ROW EXECUTE FUNCTION moneybowl_onboarding.kyc_evidence_scope();
CREATE FUNCTION moneybowl_onboarding.kyc_audit(c moneybowl_onboarding.cases, kind text, op uuid DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 INSERT INTO moneybowl_onboarding.events(case_id,workspace_id,investor_profile_id,actor_user_id,event_type,evidence,created_at)
 VALUES(c.id,c.workspace_id,c.investor_profile_id,auth.uid(),'onboarding.'||kind,
 jsonb_build_object('operation_id',op,'actor_profile_id',c.actor_profile_id,'previous_state',coalesce((SELECT evidence->>'state' FROM moneybowl_onboarding.events WHERE case_id=c.id AND event_type LIKE 'onboarding.%' ORDER BY created_at DESC,id DESC LIMIT 1),'DRAFT'),'state',coalesce(c.reconciliation_reason,(SELECT state FROM moneybowl_onboarding.kyc_cases WHERE case_id=c.id))),clock_timestamp())
$$;
CREATE FUNCTION moneybowl_onboarding.kyc_authorize(id uuid) RETURNS moneybowl_onboarding.cases
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c moneybowl_onboarding.cases;
BEGIN
 PERFORM pg_advisory_xact_lock(718031,1);
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE cases.id=kyc_authorize.id AND actor_profile_id=moneybowl_authz.actor() FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 PERFORM moneybowl_onboarding.assert_actor(c.workspace_id);
 PERFORM 1 FROM public.advisor_investor_assignments WHERE workspace_id=c.workspace_id AND advisor_id=c.actor_profile_id AND investor_id=c.investor_profile_id FOR SHARE;
 IF c.investor_profile_id IS NOT NULL AND NOT moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,c.investor_profile_id)
 THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 RETURN c;
END $$;
CREATE FUNCTION public.get_onboarding_kyc(p_case_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c moneybowl_onboarding.cases; s text; r jsonb;
BEGIN
 c:=moneybowl_onboarding.kyc_authorize(p_case_id);
 SELECT state INTO s FROM moneybowl_onboarding.kyc_cases WHERE case_id=c.id;
 IF s IS NULL AND public.normalize_pan(moneybowl_onboarding.payload(c)->>'pan') IS NOT NULL THEN RETURN public.start_onboarding_kyc(c.workspace_id,c.id,moneybowl_onboarding.payload(c)->>'pan'); END IF;
 r:=moneybowl_onboarding.project(c);
 RETURN r||jsonb_build_object('status',coalesce(c.reconciliation_reason,s,'DRAFT'),'kyc_state',coalesce(s,'KYC_CHECK_REQUIRED'),
 'fields', (r->'fields')-ARRAY['kyc_method','kyc_status'],
 'amcs',CASE WHEN s IN ('KYC_NOT_AVAILABLE','EKYC_DETAILS_REQUIRED') THEN
 (SELECT coalesce(jsonb_agg(jsonb_build_object('code',code,'label',label) ORDER BY label),'[]') FROM moneybowl_onboarding.ekyc_amcs WHERE active) ELSE '[]'::jsonb END,
 'can_open_ekyc',s='EKYC_IN_PROGRESS');
END $$;
CREATE FUNCTION public.start_onboarding_kyc(p_workspace_id uuid,p_case_id uuid,p_pan text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c moneybowl_onboarding.cases; p public.profiles; h bytea; ids uuid[]; reason text; existing uuid; d jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(718031,1);
 PERFORM moneybowl_onboarding.assert_actor(p_workspace_id);
 IF p_case_id IS NULL OR public.normalize_pan(p_pan) IS NULL THEN RAISE EXCEPTION 'invalid_pan'; END IF;
 h:=extensions.hmac(public.normalize_pan(p_pan),public.pan_lookup_hmac_key(),'sha256');
 SELECT case_id INTO existing FROM moneybowl_onboarding.kyc_cases WHERE workspace_id=p_workspace_id AND pan_hmac=h;
 IF existing IS NOT NULL THEN RETURN public.get_onboarding_kyc(existing); END IF;
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=p_case_id;
 IF c.id IS NOT NULL THEN
 c:=moneybowl_onboarding.kyc_authorize(c.id);
 IF c.workspace_id<>p_workspace_id OR (public.normalize_pan(moneybowl_onboarding.payload(c)->>'pan') IS NOT NULL AND moneybowl_onboarding.payload(c)->>'pan' IS DISTINCT FROM public.normalize_pan(p_pan)) THEN RAISE EXCEPTION 'onboarding_identity_frozen'; END IF;
 IF public.normalize_pan(moneybowl_onboarding.payload(c)->>'pan') IS NULL THEN PERFORM public.save_investor_onboarding(c.workspace_id,c.id,c.version,jsonb_build_object('pan',public.normalize_pan(p_pan))); END IF;
 ELSE
 PERFORM public.save_investor_onboarding(p_workspace_id,p_case_id,0,jsonb_build_object('pan',public.normalize_pan(p_pan)));
 END IF;
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=p_case_id FOR UPDATE;
 INSERT INTO moneybowl_onboarding.kyc_cases(case_id,workspace_id,pan_hmac) VALUES(c.id,c.workspace_id,h);
 SELECT array_agg(DISTINCT profile_id) INTO ids FROM public.profile_pan_records WHERE pan_lookup_hmac=h AND status NOT IN ('INVALID_LEGACY','SUPERSEDED');
 IF coalesce(cardinality(ids),0)>1 THEN reason:='IDENTITY_RECONCILIATION_REQUIRED';
 ELSIF cardinality(ids)=1 THEN
 SELECT * INTO p FROM public.profiles WHERE id=ids[1] FOR UPDATE;
 IF p.role NOT IN ('investor','client') OR p.account_status<>'active'
 OR EXISTS(SELECT 1 FROM public.profile_pan_records WHERE profile_id=p.id AND (status='CONFLICT' OR (status IN ('OBSERVED','VERIFIED') AND pan_lookup_hmac<>h)))
 THEN reason:='IDENTITY_RECONCILIATION_REQUIRED';
 ELSIF NOT moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,p.id) THEN reason:='RELATIONSHIP_RECONCILIATION_REQUIRED';
 ELSE
 SELECT id INTO existing FROM moneybowl_onboarding.cases WHERE workspace_id=c.workspace_id AND investor_profile_id=p.id AND id<>c.id;
 IF existing IS NOT NULL THEN
 -- A V1 case is reused without changing its captured or verified facts.
 DELETE FROM moneybowl_onboarding.kyc_cases WHERE case_id=c.id;
 INSERT INTO moneybowl_onboarding.kyc_cases(case_id,workspace_id,pan_hmac) VALUES(existing,c.workspace_id,h);
 UPDATE moneybowl_onboarding.cases SET superseded_by=existing WHERE id=c.id;
 RETURN public.get_onboarding_kyc(existing);
 END IF;
 d:=moneybowl_onboarding.payload(c)||jsonb_build_object('legal_name',p.full_name,'email',coalesce(p.email,''),'mobile',coalesce(p.phone_number,''));
 UPDATE moneybowl_onboarding.cases SET investor_profile_id=p.id,payload_ciphertext=extensions.pgp_sym_encrypt(d::text,public.bank_account_encryption_key('bank_account_encryption_key_v1')) WHERE id=c.id RETURNING * INTO c;
 END IF;
 END IF;
 IF reason IS NOT NULL THEN UPDATE moneybowl_onboarding.cases SET reconciliation_reason=reason WHERE id=c.id RETURNING * INTO c; END IF;
 PERFORM moneybowl_onboarding.kyc_audit(c,CASE WHEN reason IS NULL THEN 'pan_resolved' ELSE 'identity_review_required' END);
 RETURN public.get_onboarding_kyc(c.id);
END $$;
-- V2 case PAN and provider state cannot be substituted through the legacy save API.
CREATE FUNCTION moneybowl_onboarding.guard_kyc_draft() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a jsonb; b jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM moneybowl_onboarding.kyc_cases WHERE case_id=OLD.id) THEN
 a:=moneybowl_onboarding.payload(OLD); b:=moneybowl_onboarding.payload(NEW);
 IF a->>'pan' IS DISTINCT FROM b->>'pan' OR a->>'kyc_status' IS DISTINCT FROM b->>'kyc_status' OR a->>'kyc_method' IS DISTINCT FROM b->>'kyc_method'
 THEN RAISE EXCEPTION 'onboarding_identity_frozen'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER onboarding_kyc_draft_guard BEFORE UPDATE ON moneybowl_onboarding.cases FOR EACH ROW EXECUTE FUNCTION moneybowl_onboarding.guard_kyc_draft();
ALTER FUNCTION public.resolve_investor_onboarding(uuid,integer) SET SCHEMA moneybowl_onboarding;
ALTER FUNCTION moneybowl_onboarding.resolve_investor_onboarding(uuid,integer) RENAME TO resolve_v1;
CREATE FUNCTION public.resolve_investor_onboarding(p_case_id uuid,p_version integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(718031,1);
 IF EXISTS(SELECT 1 FROM moneybowl_onboarding.kyc_cases WHERE case_id=p_case_id AND state<>'KYC_COMPLIANT') THEN
 PERFORM moneybowl_onboarding.kyc_authorize(p_case_id); RAISE EXCEPTION 'authoritative_kyc_required'; END IF;
 RETURN moneybowl_onboarding.resolve_v1(p_case_id,p_version);
END $$;
CREATE FUNCTION public.request_onboarding_kyc(p_case_id uuid,p_request_id uuid,p_action text,p_email text DEFAULT NULL,p_mobile text DEFAULT NULL,p_amc_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c moneybowl_onboarding.cases; k moneybowl_onboarding.kyc_cases; o moneybowl_onboarding.kyc_operations; d jsonb; body jsonb; api text; event text;
BEGIN
 c:=moneybowl_onboarding.kyc_authorize(p_case_id);
 SELECT * INTO k FROM moneybowl_onboarding.kyc_cases WHERE case_id=c.id FOR UPDATE;
 IF k.case_id IS NULL OR c.reconciliation_reason IS NOT NULL OR p_request_id IS NULL OR p_action IS NULL OR p_action NOT IN ('CHECK','REFRESH','EKYC') THEN RAISE EXCEPTION 'onboarding_action_unavailable'; END IF;
 api:=CASE WHEN p_action='EKYC' THEN 'EKYCREG' ELSE 'CLIENT_KYC_REPORT' END;
 SELECT * INTO o FROM moneybowl_onboarding.kyc_operations WHERE case_id=c.id AND request_id=p_request_id;
 IF o.id IS NOT NULL THEN
 IF o.api<>api THEN RAISE EXCEPTION 'onboarding_request_conflict'; END IF;
 RETURN public.get_onboarding_kyc(c.id); END IF;
 -- Case lock serializes check/check, refresh/initiate and exact retries.
 IF EXISTS(SELECT 1 FROM moneybowl_onboarding.kyc_operations WHERE case_id=c.id AND state IN ('QUEUED','CLAIMED','SUBMITTING','RETRY','RECONCILIATION_REQUIRED')) THEN RETURN public.get_onboarding_kyc(c.id); END IF;
 IF EXISTS(SELECT 1 FROM public.profile_pan_records r WHERE r.pan_lookup_hmac=k.pan_hmac AND r.status NOT IN ('INVALID_LEGACY','SUPERSEDED')
 AND (c.investor_profile_id IS NULL OR r.profile_id<>c.investor_profile_id OR r.status='CONFLICT')) THEN
 UPDATE moneybowl_onboarding.cases SET reconciliation_reason='IDENTITY_RECONCILIATION_REQUIRED' WHERE id=c.id RETURNING * INTO c;
 PERFORM moneybowl_onboarding.kyc_audit(c,'identity_review_required'); RETURN public.get_onboarding_kyc(c.id);
 END IF;
 d:=moneybowl_onboarding.payload(c);
 IF public.normalize_pan(d->>'pan') IS NULL THEN RAISE EXCEPTION 'invalid_pan'; END IF;
 IF api='EKYCREG' THEN
 IF EXISTS(SELECT 1 FROM moneybowl_onboarding.kyc_operations prior WHERE prior.case_id=c.id AND prior.api='EKYCREG') THEN RETURN public.get_onboarding_kyc(c.id); END IF;
 IF k.state NOT IN ('KYC_NOT_AVAILABLE','EKYC_DETAILS_REQUIRED') THEN RAISE EXCEPTION 'onboarding_action_unavailable'; END IF;
 p_email:=coalesce(nullif(d->>'email',''),moneybowl_onboarding.email(p_email));
 p_mobile:=coalesce(nullif(d->>'mobile',''),moneybowl_onboarding.phone(p_mobile));
 -- NSE contract is ten digits; a captured +91 may be converted without guessing.
 IF p_mobile ~ '^91[0-9]{10}$' THEN p_mobile:=right(p_mobile,10); END IF;
 IF p_email IS NULL OR length(p_email)>254 OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
 OR p_mobile IS NULL OR p_mobile !~ '^[0-9]{10}$'
 OR NOT EXISTS(SELECT 1 FROM moneybowl_onboarding.ekyc_amcs WHERE code=p_amc_code AND active) THEN RAISE EXCEPTION 'ekyc_details_required'; END IF;
 -- Retain newly supplied investor facts for later stages, without attempting Auth linkage.
 d:=d||jsonb_build_object('email',coalesce(nullif(d->>'email',''),p_email),'mobile',coalesce(nullif(d->>'mobile',''),p_mobile));
 UPDATE moneybowl_onboarding.cases SET payload_ciphertext=extensions.pgp_sym_encrypt(d::text,public.bank_account_encryption_key('bank_account_encryption_key_v1')),
 version=version+1,updated_at=now() WHERE id=c.id RETURNING * INTO c;
 body:=jsonb_build_object('amcCode',p_amc_code,'panNo',d->>'pan','invEmail',p_email,'mobileNo',p_mobile);
 event:='integration.nse.ekyc_registration_requested';
 UPDATE moneybowl_onboarding.kyc_cases SET state='EKYC_INITIATION_PENDING' WHERE case_id=c.id;
 ELSE
 IF (p_action='CHECK' AND k.state NOT IN ('KYC_CHECK_REQUIRED','KYC_NOT_AVAILABLE')) OR
 (p_action='REFRESH' AND k.state<>'EKYC_IN_PROGRESS') THEN RAISE EXCEPTION 'onboarding_action_unavailable'; END IF;
 body:=jsonb_build_object('pan_no',d->>'pan'); event:='integration.nse.onboarding_kyc_check_requested';
 UPDATE moneybowl_onboarding.kyc_cases SET state='KYC_CHECKING' WHERE case_id=c.id;
 END IF;
 INSERT INTO moneybowl_onboarding.kyc_operations(case_id,request_id,api,request_ciphertext)
 VALUES(c.id,p_request_id,api,extensions.pgp_sym_encrypt(body::text,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'))) RETURNING * INTO o;
 INSERT INTO public.event_outbox(event_type,entity_type,entity_id,payload) VALUES(event,'onboarding_kyc_operation',o.id,'{}');
 PERFORM moneybowl_onboarding.kyc_audit(c,CASE WHEN api='EKYCREG' THEN 'ekyc_registration_requested' ELSE 'kyc_check_requested' END,o.id);
 RETURN public.get_onboarding_kyc(c.id);
END $$;
CREATE FUNCTION moneybowl_onboarding.kyc_classify(body text,pan text) RETURNS text LANGUAGE plpgsql SET search_path='' AS $$
DECLARE j jsonb; r jsonb; n integer; f text;
BEGIN
 j:=body::jsonb;
 IF jsonb_typeof(j)<>'object' OR j->>'response_status' IS DISTINCT FROM 'S' OR jsonb_typeof(j->'report_data') IS DISTINCT FROM 'array'
 OR j->>'report_data_total' !~ '^[0-9]+$' OR j->>'report_data_total' IS NULL THEN RETURN 'PROVIDER_RECONCILIATION_REQUIRED'; END IF;
 n:=(j->>'report_data_total')::integer;
 IF n<>jsonb_array_length(j->'report_data') THEN RETURN 'PROVIDER_RECONCILIATION_REQUIRED'; END IF;
 IF n=0 AND public.match_nse_response_diagnostic('NSE_CLIENT_KYC_REPORT','S',j->>'error_remark',n,j->'report_data')->>'outcome'='SUCCESS'
 THEN RETURN 'KYC_NOT_AVAILABLE'; END IF;
 IF n<>1 OR (j ? 'error_remark' AND j->>'error_remark' IS DISTINCT FROM '') THEN RETURN 'PROVIDER_RECONCILIATION_REQUIRED'; END IF;
 r:=j->'report_data'->0;
 FOREACH f IN ARRAY ARRAY['client_code','client_pan','holding_type','holder_name','holder_dob','kyc_status','status_remark'] LOOP
 IF jsonb_typeof(r->f) IS DISTINCT FROM 'string' THEN RETURN 'PROVIDER_RECONCILIATION_REQUIRED'; END IF;
 END LOOP;
 IF r->>'client_pan' IS DISTINCT FROM pan THEN RETURN 'PROVIDER_RECONCILIATION_REQUIRED'; END IF;
 -- No authoritative compliant status enumeration exists in retained v1.9.7.
 RETURN 'KYC_PROVIDER_REVIEW_REQUIRED';
EXCEPTION WHEN OTHERS THEN RETURN 'PROVIDER_RECONCILIATION_REQUIRED';
END $$;
CREATE FUNCTION moneybowl_onboarding.ekyc_link(body text) RETURNS text LANGUAGE plpgsql SET search_path='' AS $$
DECLARE j jsonb; link text;
BEGIN
 j:=body::jsonb; link:=j->>'link';
 IF jsonb_typeof(j)<>'object' OR jsonb_typeof(j->'link') IS DISTINCT FROM 'string' OR
 j->>'message' IS NULL OR j->>'message' NOT IN ('EKYC FRESH REGISTRATION REQUEST RECEIVED','EKYC FRESH REGISTRATION REQUEST RECEVIED')
 OR length(link)>2048 OR link !~ '^https://nseinvestuat\.nseindia\.com/nsemfdesk/ekycVerifyByUser/[A-Za-z0-9_-]{1,255}$' THEN RETURN NULL; END IF;
 RETURN link;
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;
CREATE FUNCTION moneybowl_onboarding.kyc_live(c moneybowl_onboarding.cases) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.profiles p JOIN public.workspaces w ON w.id=c.workspace_id
 JOIN public.mfd_applications a ON a.workspace_id=w.id AND a.profile_id=p.id
 WHERE p.id=c.actor_profile_id AND p.account_status='active' AND moneybowl_authz.account_active(p.user_id)
 AND moneybowl_authz.member_role(w.id,p.id)='admin' AND w.owner_profile_id=p.id AND a.status='approved')
 AND (c.investor_profile_id IS NULL OR moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,c.investor_profile_id))
 AND c.reconciliation_reason IS NULL AND c.superseded_by IS NULL
 -- A draft does not reserve an identity. Recheck canonical changes at dispatch/link time.
 AND NOT EXISTS(SELECT 1 FROM public.profile_pan_records r JOIN moneybowl_onboarding.kyc_cases k ON k.case_id=c.id
 WHERE r.pan_lookup_hmac=k.pan_hmac AND r.status NOT IN ('INVALID_LEGACY','SUPERSEDED')
 AND (c.investor_profile_id IS NULL OR r.profile_id<>c.investor_profile_id OR r.status='CONFLICT'))
 AND NOT EXISTS(SELECT 1 FROM public.profile_pan_records r JOIN moneybowl_onboarding.kyc_cases k ON k.case_id=c.id
 WHERE r.profile_id=c.investor_profile_id AND r.status IN ('OBSERVED','VERIFIED','CONFLICT') AND (r.pan_lookup_hmac<>k.pan_hmac OR r.status='CONFLICT'))
$$;
CREATE FUNCTION moneybowl_onboarding.kyc_context_guard() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a jsonb:=to_jsonb(OLD); b jsonb:=to_jsonb(NEW); k text;
BEGIN
 IF TG_TABLE_NAME='kyc_operations' THEN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'onboarding_operation_immutable'; END IF;
 FOREACH k IN ARRAY ARRAY['id','case_id','request_id','api','request_ciphertext','created_at'] LOOP
 IF a->k IS DISTINCT FROM b->k THEN RAISE EXCEPTION 'onboarding_operation_immutable'; END IF;
 END LOOP;
 ELSE
 IF TG_OP='INSERT' AND b->>'entity_type'='onboarding_kyc_operation' THEN
 IF b->'payload'<>'{}'::jsonb OR NOT EXISTS(SELECT 1 FROM moneybowl_onboarding.kyc_operations o WHERE o.id=(b->>'entity_id')::uuid AND b->>'event_type'=
 CASE WHEN o.api='EKYCREG' THEN 'integration.nse.ekyc_registration_requested' ELSE 'integration.nse.onboarding_kyc_check_requested' END)
 THEN RAISE EXCEPTION 'onboarding_event_invalid'; END IF;
 ELSIF TG_OP<>'INSERT' AND a->>'entity_type'='onboarding_kyc_operation' THEN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'onboarding_event_immutable'; END IF;
 FOREACH k IN ARRAY ARRAY['id','entity_type','entity_id','event_type','payload','created_at'] LOOP
 IF a->k IS DISTINCT FROM b->k THEN RAISE EXCEPTION 'onboarding_event_immutable'; END IF;
 END LOOP;
 ELSIF TG_OP='UPDATE' AND b->>'entity_type'='onboarding_kyc_operation' THEN RAISE EXCEPTION 'onboarding_event_immutable'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER onboarding_operation_immutable BEFORE UPDATE OR DELETE ON moneybowl_onboarding.kyc_operations FOR EACH ROW EXECUTE FUNCTION moneybowl_onboarding.kyc_context_guard();
CREATE TRIGGER onboarding_event_guard BEFORE INSERT OR UPDATE OR DELETE ON public.event_outbox FOR EACH ROW EXECUTE FUNCTION moneybowl_onboarding.kyc_context_guard();
CREATE UNIQUE INDEX onboarding_event_unique ON public.event_outbox(entity_id) WHERE entity_type='onboarding_kyc_operation';
CREATE FUNCTION public.claim_onboarding_kyc(p_event_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.event_outbox; o moneybowl_onboarding.kyc_operations; c moneybowl_onboarding.cases;
BEGIN
 PERFORM pg_advisory_xact_lock(718031,1);
 SELECT * INTO e FROM public.event_outbox WHERE id=p_event_id AND entity_type='onboarding_kyc_operation' FOR UPDATE;
 IF e.id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO o FROM moneybowl_onboarding.kyc_operations WHERE id=e.entity_id FOR UPDATE;
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=o.case_id FOR UPDATE;
 PERFORM moneybowl_authz.lock_scope(c.workspace_id);
 PERFORM 1 FROM public.advisor_investor_assignments WHERE workspace_id=c.workspace_id AND advisor_id=c.actor_profile_id AND investor_id=c.investor_profile_id FOR SHARE;
 IF o.state IN ('DONE','RECONCILIATION_REQUIRED','BLOCKED') THEN RETURN NULL; END IF;
 IF o.state IN ('CLAIMED','SUBMITTING') THEN
 IF o.lease_until>now() THEN RETURN NULL; END IF;
 IF o.api='EKYCREG' AND o.transmission='MAYBE_SENT' THEN
 UPDATE moneybowl_onboarding.kyc_operations SET state='RECONCILIATION_REQUIRED' WHERE id=o.id;
 UPDATE moneybowl_onboarding.kyc_cases SET state='PROVIDER_RECONCILIATION_REQUIRED' WHERE case_id=c.id;
 UPDATE public.event_outbox SET status='failed',claim_token=NULL,claim_expires_at=NULL,updated_at=now() WHERE id=e.id;
 PERFORM moneybowl_onboarding.kyc_audit(c,'provider_reconciliation_required',o.id);
 RETURN NULL;
 END IF;
 END IF;
 IF o.attempt>=3 OR NOT moneybowl_onboarding.kyc_live(c) THEN
 UPDATE moneybowl_onboarding.kyc_operations SET state='BLOCKED' WHERE id=o.id;
 UPDATE moneybowl_onboarding.kyc_cases SET state='BLOCKED' WHERE case_id=c.id;
 UPDATE public.event_outbox SET status='failed',claim_token=NULL,claim_expires_at=NULL,updated_at=now() WHERE id=e.id;
 PERFORM moneybowl_onboarding.kyc_audit(c,'blocked',o.id); RETURN NULL;
 END IF;
 UPDATE moneybowl_onboarding.kyc_operations SET state='CLAIMED',attempt=attempt+1,call_id=gen_random_uuid(),claim_token=gen_random_uuid(),
 lease_until=now()+interval '120 seconds',transmission='PROVEN_NOT_SENT' WHERE id=o.id RETURNING * INTO o;
 UPDATE public.event_outbox SET status='processing',claim_token=o.claim_token,claim_expires_at=o.lease_until,updated_at=now() WHERE id=e.id;
 RETURN jsonb_build_object('operation_id',o.id,'claim_token',o.claim_token,'call_id',o.call_id,'api',o.api,
 'request',extensions.pgp_sym_decrypt(o.request_ciphertext,public.integration_payload_encryption_key('integration_payload_encryption_key_v1')));
END $$;
CREATE FUNCTION public.start_onboarding_kyc_call(p_operation_id uuid,p_claim_token uuid,p_call_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o moneybowl_onboarding.kyc_operations; c moneybowl_onboarding.cases; body text;
BEGIN
 PERFORM pg_advisory_xact_lock(718031,1);
 SELECT * INTO o FROM moneybowl_onboarding.kyc_operations WHERE id=p_operation_id FOR UPDATE;
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=o.case_id FOR UPDATE;
 IF o.id IS NULL OR o.claim_token IS DISTINCT FROM p_claim_token OR o.call_id IS DISTINCT FROM p_call_id OR o.lease_until<=now() OR o.state NOT IN ('CLAIMED','SUBMITTING') THEN RAISE EXCEPTION 'onboarding_claim_invalid'; END IF;
 PERFORM moneybowl_authz.lock_scope(c.workspace_id);
 PERFORM 1 FROM public.advisor_investor_assignments WHERE workspace_id=c.workspace_id AND advisor_id=c.actor_profile_id AND investor_id=c.investor_profile_id FOR SHARE;
 IF NOT moneybowl_onboarding.kyc_live(c) THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.integration_api_interactions WHERE call_id=o.call_id AND phase='REQUEST') THEN RETURN true; END IF;
 body:=extensions.pgp_sym_decrypt(o.request_ciphertext,public.integration_payload_encryption_key('integration_payload_encryption_key_v1'));
 INSERT INTO public.integration_api_interactions(workspace_id,onboarding_operation_id,integration_key,integration_environment,category,safety_class,
 operation_type,api_key,contract_version,endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,
 request_payload_ciphertext,request_header_metadata,request_content_type,request_bytes,request_hash,started_at,normalized_outcome)
 VALUES(c.workspace_id,o.id,'NSE_INVEST','UAT','KYC_COMPLIANCE',CASE WHEN o.api='EKYCREG' THEN 'OTHER_MUTATING' ELSE 'READ_ONLY' END,
 'ONBOARDING_KYC',o.api,'NNF_1.9.7',CASE WHEN o.api='EKYCREG' THEN '/nsemfdesk/api/v1/EKYC/EKYCREG' ELSE '/nsemfdesk/api/v2/reports/CLIENT_KYC_REPORT' END,
 'POST',o.call_id,'REQUEST',o.attempt,o.id,'integration_payload_encryption_key_v1',1,
 extensions.pgp_sym_encrypt(body,public.integration_payload_encryption_key('integration_payload_encryption_key_v1')),
 '{"content_type":"application/json","accept":"application/json"}','application/json',octet_length(body),extensions.digest(body,'sha256'),now(),'REQUEST_RECORDED');
 -- Commit the conservative send fence before the HTTP call. A crash now must reconcile a mutation.
 UPDATE moneybowl_onboarding.kyc_operations SET state='SUBMITTING',transmission='MAYBE_SENT' WHERE id=o.id;
 RETURN true;
END $$;
CREATE FUNCTION public.finish_onboarding_kyc_call(p_operation_id uuid,p_claim_token uuid,p_call_id uuid,p_response_base64 text,p_http_status integer,p_transmission text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o moneybowl_onboarding.kyc_operations; c moneybowl_onboarding.cases; req public.integration_api_interactions;
 bytes bytea; body text:=''; v_state text; outcome text; retry boolean:=false; pan text;
BEGIN
 PERFORM pg_advisory_xact_lock(718031,1);
 SELECT * INTO o FROM moneybowl_onboarding.kyc_operations WHERE id=p_operation_id FOR UPDATE;
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=o.case_id FOR UPDATE;
 IF o.id IS NULL OR o.call_id IS DISTINCT FROM p_call_id OR o.claim_token IS DISTINCT FROM p_claim_token
 OR p_transmission IS NULL OR p_transmission NOT IN ('PROVEN_NOT_SENT','MAYBE_SENT','SENT_WITH_RESULT')
 OR p_response_base64 IS NULL OR length(p_response_base64)>1400000 THEN RAISE EXCEPTION 'onboarding_result_invalid'; END IF;
 bytes:=decode(p_response_base64,'base64');
 IF EXISTS(SELECT 1 FROM public.integration_api_interactions WHERE call_id=o.call_id AND phase='RESULT') THEN
 IF NOT EXISTS(SELECT 1 FROM public.integration_api_interactions WHERE call_id=o.call_id AND phase='RESULT' AND response_hash=extensions.digest(bytes,'sha256') AND http_status IS NOT DISTINCT FROM p_http_status)
 THEN RAISE EXCEPTION 'onboarding_result_conflict'; END IF;
 RETURN (SELECT k.state FROM moneybowl_onboarding.kyc_cases k WHERE case_id=c.id); END IF;
 IF o.state<>'SUBMITTING' AND NOT (o.api='EKYCREG' AND o.state='RECONCILIATION_REQUIRED' AND p_transmission='SENT_WITH_RESULT') THEN RAISE EXCEPTION 'onboarding_claim_invalid'; END IF;
 SELECT * INTO req FROM public.integration_api_interactions WHERE call_id=o.call_id AND phase='REQUEST';
 IF req.id IS NULL OR (p_transmission='SENT_WITH_RESULT' AND (p_http_status IS NULL OR p_http_status NOT BETWEEN 100 AND 599))
 OR (p_transmission<>'SENT_WITH_RESULT' AND (p_http_status IS NOT NULL OR octet_length(bytes)<>0)) THEN RAISE EXCEPTION 'onboarding_result_invalid'; END IF;
 BEGIN body:=convert_from(bytes,'UTF8'); EXCEPTION WHEN OTHERS THEN body:=''; END;
 pan:=moneybowl_onboarding.payload(c)->>'pan';
 v_state:='PROVIDER_RECONCILIATION_REQUIRED'; outcome:='AMBIGUOUS';
 IF p_transmission='PROVEN_NOT_SENT' THEN retry:=o.attempt<3; outcome:='PRE_TRANSMISSION_FAILURE';
 ELSIF p_transmission='MAYBE_SENT' THEN retry:=o.api='CLIENT_KYC_REPORT' AND o.attempt<3; outcome:='TRANSPORT_FAILURE';
 ELSIF p_http_status BETWEEN 200 AND 299 THEN
 IF o.api='EKYCREG' THEN
 IF moneybowl_onboarding.ekyc_link(body) IS NOT NULL THEN v_state:='EKYC_IN_PROGRESS'; END IF;
 ELSE v_state:=moneybowl_onboarding.kyc_classify(body,pan);
 -- Absence while provider flow is outstanding is not a failed initiation.
 IF v_state='KYC_NOT_AVAILABLE' AND EXISTS(SELECT 1 FROM moneybowl_onboarding.kyc_operations prior WHERE prior.case_id=c.id AND prior.api='EKYCREG' AND state='DONE') THEN v_state:='EKYC_IN_PROGRESS'; END IF;
 END IF;
 outcome:=CASE WHEN v_state='PROVIDER_RECONCILIATION_REQUIRED' THEN 'BUSINESS_FAILURE' ELSE 'SUCCESS' END;
 ELSE outcome:='HTTP_FAILURE'; retry:=o.api='CLIENT_KYC_REPORT' AND o.attempt<3 AND p_http_status IN (408,429,500,502,503,504);
 END IF;
 IF retry THEN v_state:=CASE WHEN o.api='EKYCREG' THEN 'EKYC_INITIATION_PENDING' ELSE 'KYC_CHECKING' END; END IF;
 INSERT INTO public.integration_api_interactions(workspace_id,onboarding_operation_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,
 endpoint_path,http_method,call_id,phase,attempt_number,correlation_id,payload_encryption_key_reference,payload_encryption_key_version,
 response_payload_ciphertext,response_header_metadata,response_bytes,response_hash,started_at,completed_at,http_status,http_success,normalized_outcome,native_remark_category)
 VALUES(req.workspace_id,o.id,req.integration_key,req.integration_environment,req.category,req.safety_class,req.operation_type,req.api_key,req.contract_version,
 req.endpoint_path,req.http_method,o.call_id,'RESULT',o.attempt,req.correlation_id,req.payload_encryption_key_reference,req.payload_encryption_key_version,
 extensions.pgp_sym_encrypt_bytea(bytes,public.integration_payload_encryption_key('integration_payload_encryption_key_v1')),'{}',octet_length(bytes),extensions.digest(bytes,'sha256'),req.started_at,now(),p_http_status,p_http_status BETWEEN 200 AND 299,outcome,lower(v_state));
 UPDATE moneybowl_onboarding.kyc_operations SET state=CASE WHEN retry THEN 'RETRY' WHEN v_state='PROVIDER_RECONCILIATION_REQUIRED' THEN 'RECONCILIATION_REQUIRED' ELSE 'DONE' END,
 transmission=p_transmission WHERE id=o.id;
 UPDATE moneybowl_onboarding.kyc_cases SET state=v_state WHERE case_id=c.id;
 UPDATE public.event_outbox SET status=CASE WHEN retry THEN 'failed' ELSE 'completed' END,claim_token=NULL,claim_expires_at=NULL,updated_at=now()
 WHERE entity_type='onboarding_kyc_operation' AND entity_id=o.id;
 PERFORM moneybowl_onboarding.kyc_audit(c,lower(v_state),o.id);
 RETURN v_state;
END $$;
CREATE FUNCTION public.get_onboarding_ekyc_link(p_case_id uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c moneybowl_onboarding.cases; body bytea;
BEGIN
 PERFORM pg_advisory_xact_lock(718031,1);
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=p_case_id FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 PERFORM moneybowl_authz.lock_scope(c.workspace_id);
 PERFORM 1 FROM public.advisor_investor_assignments WHERE workspace_id=c.workspace_id AND advisor_id=c.actor_profile_id AND investor_id=c.investor_profile_id FOR SHARE;
 IF NOT (moneybowl_onboarding.kyc_live(c) AND c.actor_profile_id=moneybowl_authz.actor()) AND NOT
 (moneybowl_authz.account_active(auth.uid()) AND EXISTS(SELECT 1 FROM public.investor_account_links l JOIN public.profiles p ON p.id=l.profile_id
 WHERE l.user_id=auth.uid() AND l.profile_id=c.investor_profile_id AND l.link_status='active' AND p.account_status='active'))
 THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM moneybowl_onboarding.kyc_cases WHERE case_id=c.id AND state='EKYC_IN_PROGRESS') THEN RETURN NULL; END IF;
 SELECT i.response_payload_ciphertext INTO body FROM public.integration_api_interactions i JOIN moneybowl_onboarding.kyc_operations o ON o.id=i.onboarding_operation_id
 WHERE o.case_id=c.id AND o.api='EKYCREG' AND o.state='DONE' AND i.phase='RESULT' AND i.normalized_outcome='SUCCESS';
 IF body IS NULL THEN RETURN NULL; END IF;
 RETURN moneybowl_onboarding.ekyc_link(convert_from(extensions.pgp_sym_decrypt_bytea(body,public.integration_payload_encryption_key('integration_payload_encryption_key_v1')),'UTF8'));
END $$;
-- Compose with the existing dispatcher feed; account operations retain their exact predicate.
ALTER FUNCTION public.list_dispatchable_outbox_events(text[],integer,integer) SET SCHEMA moneybowl_onboarding;
ALTER FUNCTION moneybowl_onboarding.list_dispatchable_outbox_events(text[],integer,integer) RENAME TO registered_dispatchable_events;
CREATE FUNCTION public.list_dispatchable_outbox_events(p_event_types text[],p_limit integer DEFAULT 10,p_retry_delay_seconds integer DEFAULT 30)
RETURNS TABLE(event_outbox_id uuid,event_type text,event_status text,retry_count integer,claim_expires_at timestamptz,created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 -- Invoke legacy validation even when no registered events are available.
 RETURN QUERY SELECT * FROM (
 SELECT * FROM moneybowl_onboarding.registered_dispatchable_events(p_event_types,p_limit,p_retry_delay_seconds)
 UNION ALL
 SELECT e.id,e.event_type,e.status,e.retry_count,e.claim_expires_at,e.created_at FROM public.event_outbox e
 JOIN moneybowl_onboarding.kyc_operations o ON o.id=e.entity_id AND e.entity_type='onboarding_kyc_operation'
 WHERE e.event_type=ANY(p_event_types) AND (
 (o.state='QUEUED' AND e.status='pending') OR
 (o.state='RETRY' AND e.status='failed' AND e.updated_at<=now()-make_interval(secs=>p_retry_delay_seconds)) OR
 (o.state IN ('CLAIMED','SUBMITTING') AND e.status='processing' AND o.lease_until<=now()))
 ) candidates ORDER BY CASE WHEN candidates.event_status='processing' THEN 0 ELSE 1 END,candidates.created_at,candidates.event_outbox_id LIMIT p_limit;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA moneybowl_onboarding FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA moneybowl_onboarding FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_onboarding_kyc(uuid),public.start_onboarding_kyc(uuid,uuid,text),public.request_onboarding_kyc(uuid,uuid,text,text,text,text),
 public.get_onboarding_ekyc_link(uuid),public.resolve_investor_onboarding(uuid,integer),public.claim_onboarding_kyc(uuid),public.start_onboarding_kyc_call(uuid,uuid,uuid),
 public.finish_onboarding_kyc_call(uuid,uuid,uuid,text,integer,text),public.list_dispatchable_outbox_events(text[],integer,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_onboarding_kyc(uuid),public.start_onboarding_kyc(uuid,uuid,text),public.request_onboarding_kyc(uuid,uuid,text,text,text,text),
 public.get_onboarding_ekyc_link(uuid),public.resolve_investor_onboarding(uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_onboarding_kyc(uuid),public.start_onboarding_kyc_call(uuid,uuid,uuid),public.finish_onboarding_kyc_call(uuid,uuid,uuid,text,integer,text),
 public.list_dispatchable_outbox_events(text[],integer,integer) TO service_role;
COMMIT;
