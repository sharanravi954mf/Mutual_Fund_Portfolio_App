-- Auth accounts remain separate from canonical public.profiles investors.
BEGIN;
CREATE SCHEMA moneybowl_onboarding;
REVOKE ALL ON SCHEMA moneybowl_onboarding FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE moneybowl_onboarding.cases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 workspace_id uuid NOT NULL REFERENCES public.workspaces(id),
 actor_profile_id uuid NOT NULL REFERENCES public.profiles(id),
 investor_profile_id uuid REFERENCES public.profiles(id),
 payload_ciphertext bytea NOT NULL,
 superseded_by uuid REFERENCES moneybowl_onboarding.cases(id),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 reconciliation_reason text CHECK(reconciliation_reason IN ('IDENTITY_RECONCILIATION_REQUIRED','RELATIONSHIP_RECONCILIATION_REQUIRED')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(workspace_id,investor_profile_id)
);
ALTER TABLE moneybowl_onboarding.cases ENABLE ROW LEVEL SECURITY;
CREATE INDEX onboarding_cases_actor ON moneybowl_onboarding.cases(workspace_id,actor_profile_id);
CREATE TABLE moneybowl_onboarding.events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), case_id uuid REFERENCES moneybowl_onboarding.cases(id),
 workspace_id uuid REFERENCES public.workspaces(id), investor_profile_id uuid REFERENCES public.profiles(id),
 actor_user_id uuid REFERENCES auth.users(id), event_type text NOT NULL,
 evidence jsonb NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE moneybowl_onboarding.events ENABLE ROW LEVEL SECURITY;
CREATE INDEX onboarding_events_case ON moneybowl_onboarding.events(case_id,created_at);
CREATE FUNCTION moneybowl_onboarding.immutable_event() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'onboarding_audit_immutable'; END $$;
CREATE TRIGGER immutable_event BEFORE UPDATE OR DELETE ON moneybowl_onboarding.events
FOR EACH ROW EXECUTE FUNCTION moneybowl_onboarding.immutable_event();

CREATE FUNCTION moneybowl_onboarding.email(v text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT nullif(lower(btrim(v)),'') $$;
CREATE FUNCTION moneybowl_onboarding.phone(v text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT nullif(regexp_replace(v,'[^0-9]','','g'),'') $$;
CREATE FUNCTION moneybowl_onboarding.allowed(w uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce(moneybowl_authz.member_role(w,moneybowl_authz.actor())='admin',false)
 AND EXISTS(SELECT 1 FROM public.mfd_applications a JOIN public.workspaces ws ON ws.id=a.workspace_id
 WHERE a.workspace_id=w AND a.status='approved' AND a.profile_id=moneybowl_authz.actor()
 AND ws.owner_profile_id=a.profile_id)
$$;
CREATE FUNCTION moneybowl_onboarding.assert_actor(w uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM moneybowl_authz.lock_scope(w);
 IF NOT moneybowl_onboarding.allowed(w) THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION moneybowl_onboarding.payload(c moneybowl_onboarding.cases) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT extensions.pgp_sym_decrypt(c.payload_ciphertext,public.bank_account_encryption_key('bank_account_encryption_key_v1'))::jsonb
$$;

-- Both verified Auth contacts are required for newly MFD-asserted identity.
-- Legacy independently trusted verified_email still uses the existing bootstrap.
-- No metadata, PAN or MFD-provided "verified" flag authenticates an account.
CREATE FUNCTION moneybowl_onboarding.link_investor(p_id uuid) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public.profiles; u auth.users; candidates uuid[]; c moneybowl_onboarding.cases;
BEGIN
 -- Serializes both arrival orders, PAN resolution and contact-based ambiguity.
 PERFORM pg_advisory_xact_lock(718031,1);
 SELECT * INTO p FROM public.profiles WHERE id=p_id FOR UPDATE;
 IF p.id IS NULL OR p.account_status<>'active' OR p.role NOT IN ('investor','client')
 OR EXISTS(SELECT 1 FROM moneybowl_onboarding.cases WHERE investor_profile_id=p_id AND reconciliation_reason IS NOT NULL) THEN RETURN 'IDENTITY_RECONCILIATION_REQUIRED'; END IF;
 SELECT array_agg(id ORDER BY id) INTO candidates FROM auth.users a WHERE
 (a.email_confirmed_at IS NOT NULL AND moneybowl_onboarding.email(a.email)=moneybowl_onboarding.email(p.email))
 OR (a.phone_confirmed_at IS NOT NULL AND moneybowl_onboarding.phone(a.phone)=moneybowl_onboarding.phone(p.phone_number));
 IF coalesce(cardinality(candidates),0)=0 THEN RETURN 'ACCOUNT_NOT_LINKED'; END IF;
 IF cardinality(candidates)<>1 THEN RETURN 'IDENTITY_RECONCILIATION_REQUIRED'; END IF;
 SELECT * INTO u FROM auth.users WHERE id=candidates[1] FOR SHARE;
 IF NOT moneybowl_authz.account_active(u.id) THEN RETURN 'IDENTITY_RECONCILIATION_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM public.investor_account_links WHERE user_id=u.id AND profile_id=p.id AND link_status='active')
 AND (p.user_id IS NULL OR p.user_id=u.id)
 AND NOT EXISTS(SELECT 1 FROM public.profiles q WHERE q.user_id=u.id AND q.id<>p.id) THEN RETURN 'ACCOUNT_LINKED'; END IF;
 IF (p.user_id IS NOT NULL AND p.user_id<>u.id)
 OR EXISTS(SELECT 1 FROM public.profiles WHERE user_id=u.id AND id<>p.id)
 OR EXISTS(SELECT 1 FROM public.investor_account_links WHERE (user_id=u.id OR profile_id=p.id))
 OR EXISTS(SELECT 1 FROM public.profiles q WHERE q.id<>p.id AND q.role IN ('investor','client') AND
   (moneybowl_onboarding.email(q.email)=moneybowl_onboarding.email(p.email)
    OR moneybowl_onboarding.email(q.verified_email)=moneybowl_onboarding.email(p.email)
    OR moneybowl_onboarding.phone(q.phone_number)=moneybowl_onboarding.phone(p.phone_number)))
 THEN RETURN 'IDENTITY_RECONCILIATION_REQUIRED'; END IF;
 IF u.email_confirmed_at IS NULL OR u.phone_confirmed_at IS NULL
 OR moneybowl_onboarding.email(u.email) IS DISTINCT FROM moneybowl_onboarding.email(p.email)
 OR moneybowl_onboarding.phone(u.phone) IS DISTINCT FROM moneybowl_onboarding.phone(p.phone_number)
 OR moneybowl_onboarding.email(p.email) IS NULL OR moneybowl_onboarding.phone(p.phone_number) IS NULL
 THEN RETURN 'VERIFIED_CONTACTS_REQUIRED'; END IF;
 INSERT INTO public.user_accounts(user_id,account_state,onboarding_completed)
 VALUES(u.id,'linked_investor',true) ON CONFLICT(user_id) DO NOTHING;
 PERFORM 1 FROM public.user_accounts WHERE user_id=u.id FOR UPDATE;
 INSERT INTO public.investor_account_links(user_id,profile_id,verification_method,verified_at)
 VALUES(u.id,p.id,'verified_email_and_mobile',now());
 UPDATE public.profiles SET user_id=u.id WHERE id=p.id AND user_id IS NULL;
 UPDATE public.user_accounts SET account_state='linked_investor',onboarding_completed=true WHERE user_id=u.id;
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE investor_profile_id=p.id ORDER BY created_at LIMIT 1;
 INSERT INTO moneybowl_onboarding.events(case_id,workspace_id,investor_profile_id,actor_user_id,event_type,evidence)
 VALUES(c.id,c.workspace_id,p.id,auth.uid(),'account_linked',jsonb_build_object('linked_user_id',u.id,'method','verified_email_and_mobile',
 'email_confirmed_at',u.email_confirmed_at,'phone_confirmed_at',u.phone_confirmed_at));
 RETURN 'ACCOUNT_LINKED';
END $$;

CREATE FUNCTION moneybowl_onboarding.missing(c moneybowl_onboarding.cases) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d jsonb:=moneybowl_onboarding.payload(c); missing jsonb:='[]'::jsonb; k text;
BEGIN
 FOREACH k IN ARRAY ARRAY['legal_name','legal_first_name','pan','email','mobile','date_of_birth','gender','address_line_1','city','region','postal_code','country',
 'residency_status','tax_status','occupation','occupation_code','holding_mode','kyc_method','kyc_status','bank_name','account_type','account_number','ifsc_code','micr_code',
 'communication_preference','onboarding_mode','mobile_owner_relationship','email_owner_relationship','nomination_choice',
 'mobile_declaration_flag','email_declaration_flag','div_pay_mode','nse_state','nse_country','declarations'] LOOP
  IF nullif(btrim(d->>k),'') IS NULL THEN missing:=missing||jsonb_build_array(k); END IF;
 END LOOP;
 IF d->>'kyc_method'='ckyc' AND nullif(d->>'ckyc_number','') IS NULL THEN missing:=missing||'"ckyc_number"'::jsonb; END IF;
 IF d->>'nomination_choice'='opt_in' THEN missing:=missing||'"nomination_provider_support"'::jsonb;
   IF nullif(d->>'nominee_details','') IS NULL THEN missing:=missing||'"nominee_details"'::jsonb; END IF; END IF;
 IF d->>'holding_mode' IN ('joint','anyone_or_survivor') THEN missing:=missing||'"joint_holder_provider_support"'::jsonb; END IF;
 IF nullif(d->>'date_of_birth','') IS NOT NULL AND (d->>'date_of_birth')::date>current_date-interval '18 years' THEN missing:=missing||'"adult_investor_provider_support"'::jsonb; END IF;
 IF d->>'residency_status'='non_resident_individual' THEN missing:=missing||'"non_resident_provider_support"'::jsonb; END IF;
 IF c.investor_profile_id IS NULL THEN RETURN missing||'"identity_resolution"'::jsonb; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profile_pan_records r JOIN public.profiles p ON p.canonical_pan_record_id=r.id
 WHERE p.id=c.investor_profile_id AND r.status='VERIFIED') THEN missing:=missing||'"pan_verification"'::jsonb; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.investor_registration_profiles r WHERE r.workspace_id=c.workspace_id AND r.investor_profile_id=c.investor_profile_id AND r.kyc_verified_at IS NOT NULL)
 THEN missing:=missing||'"kyc_verification"'::jsonb; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.investor_bank_accounts b WHERE b.workspace_id=c.workspace_id AND b.investor_profile_id=c.investor_profile_id AND b.is_default AND b.is_active AND b.verification_status='verified')
 THEN missing:=missing||'"bank_verification"'::jsonb; END IF;
 RETURN missing;
END $$;
CREATE FUNCTION moneybowl_onboarding.project(c moneybowl_onboarding.cases, include_fields boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d jsonb:=moneybowl_onboarding.payload(c); m jsonb:=moneybowl_onboarding.missing(c); state text; account public.integration_accounts;
BEGIN
 SELECT * INTO account FROM public.integration_accounts a WHERE a.workspace_id=c.workspace_id AND a.investor_profile_id=c.investor_profile_id AND a.integration_key='NSE_INVEST' AND a.integration_environment='UAT';
 state:=CASE WHEN c.reconciliation_reason IS NOT NULL THEN c.reconciliation_reason
 WHEN c.investor_profile_id IS NULL THEN 'DRAFT'
 WHEN NOT moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,c.investor_profile_id) THEN 'RELATIONSHIP_RECONCILIATION_REQUIRED'
 WHEN account.state='REGISTERED' THEN 'NSE_REGISTERED'
 WHEN account.state='REGISTRATION_PENDING' THEN 'NSE_REGISTRATION_PENDING'
 WHEN account.state IN ('VALIDATION_FAILED','REGISTRATION_FAILED','RECONCILIATION_REQUIRED') THEN 'NSE_'||account.state
 WHEN jsonb_array_length(m)>0 THEN 'PROFILE_INCOMPLETE' ELSE 'PREREQUISITES_COMPLETE' END;
 RETURN jsonb_build_object('id',c.id,'workspace_id',c.workspace_id,'version',c.version,'legal_name',d->>'legal_name',
 'investor_profile_id',c.investor_profile_id,'status',state,'missing',m,
 'relationship_status',CASE WHEN moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,c.investor_profile_id) THEN 'READY' ELSE 'PENDING' END,
 'account_link_status',CASE WHEN EXISTS(SELECT 1 FROM public.investor_account_links l WHERE l.profile_id=c.investor_profile_id AND l.link_status='active') THEN 'LINKED' ELSE 'PENDING_VERIFIED_IDENTITY' END,
 'kyc_state',CASE WHEN EXISTS(SELECT 1 FROM public.investor_registration_profiles r WHERE r.workspace_id=c.workspace_id AND r.investor_profile_id=c.investor_profile_id AND r.kyc_verified_at IS NOT NULL) THEN 'VERIFIED' ELSE 'VERIFICATION_REQUIRED' END,
 'ucc_state',CASE WHEN jsonb_array_length(m)=0 THEN 'READY_FOR_PROVIDER_VALIDATION' ELSE 'PREREQUISITES_INCOMPLETE' END,
 'nse_state',coalesce(account.state,'NOT_REGISTERED'),'integration_operation_id',account.current_operation_id,
 'masked_pan',CASE WHEN public.normalize_pan(d->>'pan') IS NOT NULL THEN public.mask_pan(d->>'pan') ELSE '••••' END,
 'masked_account',CASE WHEN length(d->>'account_number')>=8 THEN '******'||right(d->>'account_number',4) ELSE '••••' END,
 'fields',CASE WHEN include_fields THEN d-ARRAY['pan','account_number'] ELSE '{}'::jsonb END);
END $$;

CREATE FUNCTION public.list_investor_onboarding_workspaces() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name) ORDER BY w.name),'[]'::jsonb)
 FROM public.workspaces w WHERE moneybowl_onboarding.allowed(w.id)
$$;
CREATE FUNCTION public.list_investor_onboarding(p_workspace_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM moneybowl_onboarding.assert_actor(p_workspace_id);
 RETURN coalesce((SELECT jsonb_agg(moneybowl_onboarding.project(c,false) ORDER BY c.updated_at DESC)
 FROM moneybowl_onboarding.cases c WHERE c.workspace_id=p_workspace_id AND c.actor_profile_id=moneybowl_authz.actor() AND c.superseded_by IS NULL
 AND (c.investor_profile_id IS NULL OR moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,c.investor_profile_id))),'[]');
END $$;
CREATE FUNCTION public.get_investor_onboarding(p_case_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c moneybowl_onboarding.cases;
BEGIN
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=p_case_id AND actor_profile_id=moneybowl_authz.actor();
 IF c.id IS NULL THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 PERFORM moneybowl_onboarding.assert_actor(c.workspace_id);
 IF c.investor_profile_id IS NOT NULL AND NOT moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,c.investor_profile_id) THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 IF c.superseded_by IS NOT NULL THEN RETURN public.get_investor_onboarding(c.superseded_by); END IF;
 RETURN moneybowl_onboarding.project(c);
END $$;

CREATE FUNCTION public.save_investor_onboarding(p_workspace_id uuid,p_case_id uuid,p_version integer,p_fields jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c moneybowl_onboarding.cases; d jsonb; old_data jsonb; k text; val text; choices jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(718031,1);
 PERFORM moneybowl_onboarding.assert_actor(p_workspace_id);
 IF p_case_id IS NULL OR p_version IS NULL OR p_fields IS NULL OR jsonb_typeof(p_fields)<>'object' OR octet_length(p_fields::text)>20000 THEN RAISE EXCEPTION 'invalid_onboarding_input'; END IF;
 PERFORM pg_advisory_xact_lock(718031,1);
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=p_case_id FOR UPDATE;
 IF c.id IS NOT NULL AND (c.workspace_id<>p_workspace_id OR c.actor_profile_id<>moneybowl_authz.actor()) THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 IF c.superseded_by IS NOT NULL THEN RETURN public.get_investor_onboarding(c.superseded_by); END IF;
 IF c.investor_profile_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.integration_accounts WHERE workspace_id=c.workspace_id AND investor_profile_id=c.investor_profile_id) THEN RAISE EXCEPTION 'registration_inputs_locked'; END IF;
 old_data:=CASE WHEN c.id IS NULL THEN '{}'::jsonb ELSE moneybowl_onboarding.payload(c) END;
 d:=old_data;
 FOR k,val IN SELECT key,value #>> '{}' FROM jsonb_each(p_fields) LOOP
  IF k<>ALL(ARRAY['legal_name','legal_first_name','legal_middle_name','legal_last_name','pan','email','mobile','date_of_birth','gender',
    'address_line_1','address_line_2','address_line_3','city','region','postal_code','country','residency_status','tax_status','occupation','occupation_code',
    'holding_mode','holder_details','kyc_method','kyc_status','ckyc_number','bank_name','account_type','account_number','ifsc_code','micr_code',
    'communication_preference','onboarding_mode','mobile_owner_relationship','email_owner_relationship','nomination_choice','nominee_details',
    'mobile_declaration_flag','email_declaration_flag','div_pay_mode','nse_state','nse_country','declarations'])
    OR jsonb_typeof(p_fields->k)<>'string' OR length(val)>2000 THEN RAISE EXCEPTION 'invalid_onboarding_field'; END IF;
  val:=btrim(val);
  IF k IN ('pan','account_number','ifsc_code') THEN val:=upper(val); END IF;
  IF k='email' THEN val:=moneybowl_onboarding.email(val); END IF;
  IF k='mobile' THEN
   IF val !~ '^[+0-9 ()-]*$' THEN RAISE EXCEPTION 'invalid_mobile'; END IF;
   val:=moneybowl_onboarding.phone(val);
  END IF;
  IF k IN ('pan','account_number') AND coalesce(val,'')='' THEN CONTINUE; END IF;
  d:=jsonb_set(d,ARRAY[k],to_jsonb(coalesce(val,'')));
 END LOOP;
 IF c.id IS NOT NULL AND d=old_data THEN RETURN moneybowl_onboarding.project(c); END IF;
 IF (c.id IS NULL AND p_version<>0) OR (c.id IS NOT NULL AND c.version<>p_version) THEN RAISE EXCEPTION 'onboarding_version_conflict'; END IF;
 FOR k,choices IN SELECT key,value FROM jsonb_each('{
  "gender":["male","female","other","transgender"],"residency_status":["resident_individual","non_resident_individual"],
  "holding_mode":["single","joint","anyone_or_survivor"],"kyc_method":["kra","ckyc","biometric","aadhaar_ekyc_pan"],
  "kyc_status":["unknown","pending","completed"],"account_type":["savings","current","nre","nro"],
  "communication_preference":["physical","electronic","mobile"],"onboarding_mode":["paper","paperless"],
  "mobile_owner_relationship":["self","spouse","dependent","guardian"],"email_owner_relationship":["self","spouse","dependent","guardian"],
  "nomination_choice":["opt_in","opt_out"]}'::jsonb) LOOP
  IF nullif(d->>k,'') IS NOT NULL AND NOT choices ? (d->>k) THEN RAISE EXCEPTION 'invalid_onboarding_choice'; END IF;
 END LOOP;
 IF nullif(d->>'ckyc_number','') IS NOT NULL AND (d->>'ckyc_number') !~ '^[0-9]{14}$' THEN RAISE EXCEPTION 'invalid_ckyc_number'; END IF;
 IF nullif(d->>'pan','') IS NOT NULL AND public.normalize_pan(d->>'pan') IS NULL THEN RAISE EXCEPTION 'invalid_pan'; END IF;
 IF nullif(d->>'email','') IS NOT NULL AND (d->>'email') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'invalid_email'; END IF;
 IF nullif(d->>'mobile','') IS NOT NULL AND (d->>'mobile') !~ '^[0-9]{10,15}$' THEN RAISE EXCEPTION 'invalid_mobile'; END IF;
 IF nullif(d->>'date_of_birth','') IS NOT NULL THEN
  BEGIN
   IF (d->>'date_of_birth') !~ '^\d{4}-\d{2}-\d{2}$' OR (d->>'date_of_birth')::date>=current_date THEN RAISE EXCEPTION 'invalid_date_of_birth'; END IF;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RAISE EXCEPTION 'invalid_date_of_birth'; END;
 END IF;
 IF nullif(d->>'ifsc_code','') IS NOT NULL AND (d->>'ifsc_code') !~ '^[A-Z]{4}0[A-Z0-9]{6}$' THEN RAISE EXCEPTION 'invalid_ifsc_code'; END IF;
 IF nullif(d->>'micr_code','') IS NOT NULL AND (d->>'micr_code') !~ '^[0-9]{9}$' THEN RAISE EXCEPTION 'invalid_micr_code'; END IF;
 IF nullif(d->>'account_number','') IS NOT NULL AND (d->>'account_number') !~ '^[A-Z0-9]{4,40}$' THEN RAISE EXCEPTION 'invalid_bank_account_number'; END IF;
 IF c.investor_profile_id IS NOT NULL THEN
  IF NOT moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,c.investor_profile_id) THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
  FOREACH k IN ARRAY ARRAY['legal_name','pan','email','mobile'] LOOP
   IF d->>k IS DISTINCT FROM old_data->>k THEN RAISE EXCEPTION 'resolved_identity_immutable'; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM public.investor_registration_profiles r WHERE r.workspace_id=c.workspace_id AND r.investor_profile_id=c.investor_profile_id AND r.kyc_verified_at IS NOT NULL) THEN
   FOREACH k IN ARRAY ARRAY['legal_first_name','legal_middle_name','legal_last_name','date_of_birth','gender','residency_status','occupation','holding_mode',
     'kyc_method','ckyc_number','communication_preference','onboarding_mode','mobile_owner_relationship','email_owner_relationship','nomination_choice',
     'address_line_1','address_line_2','address_line_3','city','region','postal_code','country'] LOOP
    IF d->>k IS DISTINCT FROM old_data->>k THEN RAISE EXCEPTION 'verified_registration_requires_review'; END IF;
   END LOOP;
  END IF;
  IF nullif(old_data->>'date_of_birth','') IS NOT NULL AND d->>'date_of_birth' IS DISTINCT FROM old_data->>'date_of_birth' THEN RAISE EXCEPTION 'resolved_identity_immutable'; END IF;
 END IF;
 INSERT INTO moneybowl_onboarding.cases(id,workspace_id,actor_profile_id,payload_ciphertext)
 VALUES(p_case_id,p_workspace_id,moneybowl_authz.actor(),extensions.pgp_sym_encrypt(d::text,public.bank_account_encryption_key('bank_account_encryption_key_v1'),'cipher-algo=aes256, compress-algo=0'))
 ON CONFLICT(id) DO UPDATE SET payload_ciphertext=EXCLUDED.payload_ciphertext,version=c.version+1,updated_at=now()
 RETURNING * INTO c;
 IF c.investor_profile_id IS NOT NULL THEN PERFORM moneybowl_onboarding.materialize(c); END IF;
 INSERT INTO moneybowl_onboarding.events(case_id,workspace_id,investor_profile_id,actor_user_id,event_type,evidence)
 VALUES(c.id,c.workspace_id,c.investor_profile_id,auth.uid(),'draft_saved',jsonb_build_object('version',c.version));
 RETURN moneybowl_onboarding.project(c);
END $$;

-- Publish captured inputs to the existing UCC source tables. Capture is never
-- verification: PAN/bank remain observed/unverified and KYC verified_at is NULL.
CREATE FUNCTION moneybowl_onboarding.materialize(c moneybowl_onboarding.cases) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d jsonb:=moneybowl_onboarding.payload(c); b public.investor_bank_accounts; k text; ready boolean:=true;
BEGIN
 IF EXISTS(SELECT 1 FROM public.integration_accounts WHERE workspace_id=c.workspace_id AND investor_profile_id=c.investor_profile_id) THEN RETURN; END IF;
 FOREACH k IN ARRAY ARRAY['legal_name','date_of_birth','residency_status','occupation','holding_mode','kyc_method','communication_preference',
 'mobile_owner_relationship','email_owner_relationship','onboarding_mode','nomination_choice'] LOOP
  IF nullif(d->>k,'') IS NULL THEN ready:=false; END IF;
 END LOOP;
 IF ready THEN
  INSERT INTO public.investor_registration_profiles(workspace_id,investor_profile_id,legal_name,legal_first_name,legal_middle_name,legal_last_name,
   investor_kind,date_of_birth,gender,residency_status,occupation,holding_mode,kyc_method,ckyc_number,communication_preference,
   mobile_owner_relationship,email_owner_relationship,onboarding_mode,nomination_opted_in)
  VALUES(c.workspace_id,c.investor_profile_id,d->>'legal_name',nullif(d->>'legal_first_name',''),nullif(d->>'legal_middle_name',''),nullif(d->>'legal_last_name',''),
   'individual',(d->>'date_of_birth')::date,nullif(d->>'gender',''),d->>'residency_status',d->>'occupation',d->>'holding_mode',d->>'kyc_method',nullif(d->>'ckyc_number',''),
   d->>'communication_preference',d->>'mobile_owner_relationship',d->>'email_owner_relationship',d->>'onboarding_mode',d->>'nomination_choice'='opt_in')
  ON CONFLICT(workspace_id,investor_profile_id) DO UPDATE SET
   legal_first_name=EXCLUDED.legal_first_name,legal_middle_name=EXCLUDED.legal_middle_name,legal_last_name=EXCLUDED.legal_last_name,
   gender=EXCLUDED.gender,residency_status=EXCLUDED.residency_status,occupation=EXCLUDED.occupation,holding_mode=EXCLUDED.holding_mode,
   kyc_method=EXCLUDED.kyc_method,ckyc_number=EXCLUDED.ckyc_number,communication_preference=EXCLUDED.communication_preference,
   mobile_owner_relationship=EXCLUDED.mobile_owner_relationship,email_owner_relationship=EXCLUDED.email_owner_relationship,
   onboarding_mode=EXCLUDED.onboarding_mode,nomination_opted_in=EXCLUDED.nomination_opted_in,updated_at=now()
  WHERE public.investor_registration_profiles.kyc_verified_at IS NULL;
 END IF;
 ready:=true;
 FOREACH k IN ARRAY ARRAY['address_line_1','city','region','postal_code','country'] LOOP
  IF nullif(d->>k,'') IS NULL THEN ready:=false; END IF;
 END LOOP;
 IF ready THEN
  INSERT INTO public.investor_addresses(workspace_id,investor_profile_id,address_line_1,address_line_2,address_line_3,city,region,postal_code,country)
  VALUES(c.workspace_id,c.investor_profile_id,d->>'address_line_1',d->>'address_line_2',d->>'address_line_3',d->>'city',d->>'region',d->>'postal_code',d->>'country')
  ON CONFLICT(workspace_id,investor_profile_id,address_type) WHERE is_current DO UPDATE SET
   address_line_1=EXCLUDED.address_line_1,address_line_2=EXCLUDED.address_line_2,address_line_3=EXCLUDED.address_line_3,
   city=EXCLUDED.city,region=EXCLUDED.region,postal_code=EXCLUDED.postal_code,country=EXCLUDED.country,updated_at=now();
 END IF;
 IF nullif(d->>'account_number','') IS NOT NULL AND nullif(d->>'account_type','') IS NOT NULL AND nullif(d->>'ifsc_code','') IS NOT NULL THEN
  SELECT * INTO b FROM public.investor_bank_accounts WHERE workspace_id=c.workspace_id AND investor_profile_id=c.investor_profile_id
   AND account_number_lookup_hmac=extensions.hmac(d->>'account_number',public.bank_account_lookup_hmac_key('bank_account_lookup_hmac_key_v1'),'sha256');
  IF b.id IS NULL THEN
   PERFORM public.set_investor_bank_account(c.workspace_id,c.investor_profile_id,d->>'account_type',d->>'account_number',d->>'ifsc_code',nullif(d->>'micr_code',''),d->>'legal_name','unverified',true);
  ELSIF b.verification_status='unverified' AND b.is_active THEN
   IF NOT b.is_default OR (b.account_type,b.ifsc_code,b.micr_code) IS DISTINCT FROM (d->>'account_type',d->>'ifsc_code',nullif(d->>'micr_code','')) THEN
    PERFORM public.set_investor_bank_account(c.workspace_id,c.investor_profile_id,d->>'account_type',d->>'account_number',d->>'ifsc_code',nullif(d->>'micr_code',''),d->>'legal_name','unverified',true);
   END IF;
  ELSIF NOT b.is_default OR NOT b.is_active OR (b.account_type,b.ifsc_code,b.micr_code) IS DISTINCT FROM (d->>'account_type',d->>'ifsc_code',nullif(d->>'micr_code','')) THEN
   RAISE EXCEPTION 'bank_change_requires_review';
  END IF;
 END IF;
END $$;

CREATE FUNCTION public.resolve_investor_onboarding(p_case_id uuid,p_version integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c moneybowl_onboarding.cases; d jsonb; p public.profiles; matches uuid[]; h bytea; pan_id uuid;
 reused boolean:=true; reason text; link_state text; existing_case moneybowl_onboarding.cases;
BEGIN
 -- Same order as save and bootstrap. Scope locks also fence retained JWTs.
 PERFORM pg_advisory_xact_lock(718031,1);
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=p_case_id AND actor_profile_id=moneybowl_authz.actor() FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 PERFORM moneybowl_onboarding.assert_actor(c.workspace_id);
 IF c.investor_profile_id IS NOT NULL AND NOT moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,c.investor_profile_id) THEN RAISE EXCEPTION 'onboarding_not_authorized' USING ERRCODE='42501'; END IF;
 IF c.superseded_by IS NOT NULL THEN RETURN public.get_investor_onboarding(c.superseded_by); END IF;
 IF c.investor_profile_id IS NOT NULL AND c.version=p_version+1 THEN RETURN moneybowl_onboarding.project(c); END IF;
 IF c.version IS DISTINCT FROM p_version THEN RAISE EXCEPTION 'onboarding_version_conflict'; END IF;
 d:=moneybowl_onboarding.payload(c);
 IF c.reconciliation_reason IS NOT NULL THEN RETURN moneybowl_onboarding.project(c); END IF;
 IF public.normalize_pan(d->>'pan') IS NULL OR nullif(d->>'legal_name','') IS NULL THEN RAISE EXCEPTION 'identity_details_required'; END IF;
 h:=extensions.hmac(public.normalize_pan(d->>'pan'),public.pan_lookup_hmac_key(),'sha256');
 SELECT array_agg(DISTINCT r.profile_id) INTO matches FROM public.profile_pan_records r
 WHERE r.pan_lookup_hmac=h AND r.status NOT IN ('INVALID_LEGACY','SUPERSEDED');
 IF coalesce(cardinality(matches),0)>1 THEN reason:='IDENTITY_RECONCILIATION_REQUIRED';
 ELSIF cardinality(matches)=1 THEN
  SELECT * INTO p FROM public.profiles WHERE id=matches[1] FOR UPDATE;
  IF p.role NOT IN ('investor','client') OR p.account_status<>'active'
   OR (c.investor_profile_id IS NOT NULL AND c.investor_profile_id<>p.id)
   OR EXISTS(SELECT 1 FROM public.profile_pan_records r WHERE r.profile_id=p.id AND r.status='CONFLICT')
   OR EXISTS(SELECT 1 FROM public.profile_pan_records r WHERE r.profile_id=p.id AND r.status IN ('CONFLICT','VERIFIED','OBSERVED') AND r.pan_lookup_hmac<>h)
   OR lower(btrim(p.full_name)) IS DISTINCT FROM lower(btrim(d->>'legal_name'))
   OR (nullif(p.email,'') IS NOT NULL AND moneybowl_onboarding.email(p.email) IS DISTINCT FROM moneybowl_onboarding.email(d->>'email'))
   OR (nullif(p.phone_number,'') IS NOT NULL AND moneybowl_onboarding.phone(p.phone_number) IS DISTINCT FROM moneybowl_onboarding.phone(d->>'mobile'))
   OR EXISTS(SELECT 1 FROM public.investor_registration_profiles r WHERE r.investor_profile_id=p.id AND nullif(d->>'date_of_birth','') IS NOT NULL AND r.date_of_birth<>(d->>'date_of_birth')::date)
  THEN reason:='IDENTITY_RECONCILIATION_REQUIRED';
  ELSIF NOT moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,p.id) THEN reason:='RELATIONSHIP_RECONCILIATION_REQUIRED';
  END IF;
 ELSE
  -- Contact overlap without a compatible PAN is evidence of a conflict, never
  -- permission to create a second person or to take over the existing person.
  IF EXISTS(SELECT 1 FROM public.profiles q WHERE q.role IN ('investor','client') AND
    (moneybowl_onboarding.email(q.email)=moneybowl_onboarding.email(d->>'email')
     OR moneybowl_onboarding.email(q.verified_email)=moneybowl_onboarding.email(d->>'email')
     OR moneybowl_onboarding.phone(q.phone_number)=moneybowl_onboarding.phone(d->>'mobile')))
  THEN reason:='IDENTITY_RECONCILIATION_REQUIRED';
  ELSE
   INSERT INTO public.profiles(role,full_name,email,phone_number,account_status)
   VALUES('investor',d->>'legal_name',nullif(d->>'email',''),nullif(d->>'mobile',''),'active') RETURNING * INTO p;
   INSERT INTO public.profile_pan_records(profile_id,pan_ciphertext,pan_lookup_hmac,masked_pan,source,source_system,status)
   VALUES(p.id,extensions.pgp_sym_encrypt(d->>'pan',public.pan_encryption_key(),'cipher-algo=aes256, compress-algo=0'),h,public.mask_pan(d->>'pan'),'ADVISOR','MANUAL','OBSERVED') RETURNING id INTO pan_id;
   UPDATE public.profiles SET canonical_pan_record_id=pan_id WHERE id=p.id;
   INSERT INTO public.workspace_memberships(workspace_id,profile_id,role,status,invited_by)
   VALUES(c.workspace_id,p.id,'investor','active',c.actor_profile_id);
   INSERT INTO public.advisor_investor_assignments(workspace_id,advisor_id,investor_id,assigned_by,status)
   VALUES(c.workspace_id,c.actor_profile_id,p.id,c.actor_profile_id,'active');
   reused:=false;
  END IF;
 END IF;
 IF reason IS NOT NULL THEN
  UPDATE moneybowl_onboarding.cases SET reconciliation_reason=reason,version=version+1,updated_at=now() WHERE id=c.id RETURNING * INTO c;
  INSERT INTO moneybowl_onboarding.events(case_id,workspace_id,actor_user_id,event_type,evidence)
  VALUES(c.id,c.workspace_id,auth.uid(),'reconciliation_required',jsonb_build_object('reason',reason,'candidate_investor_ids',to_jsonb(matches)));
  RETURN moneybowl_onboarding.project(c);
 END IF;
 SELECT * INTO existing_case FROM moneybowl_onboarding.cases WHERE workspace_id=c.workspace_id AND investor_profile_id=p.id AND id<>c.id;
 IF existing_case.id IS NOT NULL THEN
  -- Equivalent restarted request returns the canonical case, never overwrites it.
  UPDATE moneybowl_onboarding.cases SET superseded_by=existing_case.id WHERE id=c.id;
  INSERT INTO moneybowl_onboarding.events(case_id,workspace_id,investor_profile_id,actor_user_id,event_type,evidence)
  VALUES(c.id,c.workspace_id,p.id,auth.uid(),'case_reused',jsonb_build_object('canonical_case_id',existing_case.id));
  RETURN moneybowl_onboarding.project(existing_case);
 END IF;
 UPDATE moneybowl_onboarding.cases SET investor_profile_id=p.id,version=version+1,updated_at=now() WHERE id=c.id RETURNING * INTO c;
 PERFORM moneybowl_onboarding.materialize(c);
 link_state:=moneybowl_onboarding.link_investor(p.id);
 IF link_state='IDENTITY_RECONCILIATION_REQUIRED' THEN
  UPDATE moneybowl_onboarding.cases SET reconciliation_reason=link_state WHERE id=c.id RETURNING * INTO c;
 END IF;
 INSERT INTO moneybowl_onboarding.events(case_id,workspace_id,investor_profile_id,actor_user_id,event_type,evidence)
 VALUES(c.id,c.workspace_id,p.id,auth.uid(),'identity_resolved',jsonb_build_object('reused',reused,'relationship',CASE WHEN reused THEN 'existing' ELSE 'created' END,'link_result',link_state,'version',c.version,'state',moneybowl_onboarding.project(c,false)->>'status'));
 RETURN moneybowl_onboarding.project(c);
END $$;

-- Keep all pre-existing trusted bootstrap/platform/invitation behavior behind a
-- private function; the public entry first resolves MFD-created identities.
ALTER FUNCTION public.bootstrap_identity() SET SCHEMA moneybowl_onboarding;
ALTER FUNCTION moneybowl_onboarding.bootstrap_identity() RENAME TO legacy_bootstrap;
REVOKE ALL ON FUNCTION moneybowl_onboarding.legacy_bootstrap() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.bootstrap_identity()
RETURNS TABLE(account_state public.user_account_state,onboarding_completed boolean,resolution text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u auth.users; ids uuid[]; result text;
BEGIN
 PERFORM pg_advisory_xact_lock(718031,1);
 SELECT * INTO u FROM auth.users WHERE auth.users.id=auth.uid() FOR SHARE;
 IF u.id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 IF NOT moneybowl_authz.account_active(u.id) THEN RAISE EXCEPTION 'account_unavailable'; END IF;
 SELECT array_agg(DISTINCT p.id) INTO ids FROM public.profiles p
 WHERE EXISTS(SELECT 1 FROM moneybowl_onboarding.cases c WHERE c.investor_profile_id=p.id)
 AND ((u.email_confirmed_at IS NOT NULL AND moneybowl_onboarding.email(u.email)=moneybowl_onboarding.email(p.email))
 OR (u.phone_confirmed_at IS NOT NULL AND moneybowl_onboarding.phone(u.phone)=moneybowl_onboarding.phone(p.phone_number)));
 IF cardinality(ids)>1 THEN result:='IDENTITY_RECONCILIATION_REQUIRED';
 ELSIF cardinality(ids)=1 THEN result:=moneybowl_onboarding.link_investor(ids[1]); END IF;
 IF result IN ('IDENTITY_RECONCILIATION_REQUIRED','VERIFIED_CONTACTS_REQUIRED') THEN
  -- Existing links remain intact; reconciliation never detaches an identity.
  IF NOT EXISTS(SELECT 1 FROM public.investor_account_links WHERE user_id=u.id AND link_status='active') THEN
   INSERT INTO public.user_accounts(user_id,account_state,onboarding_completed) VALUES(u.id,'link_pending',true)
   ON CONFLICT(user_id) DO UPDATE SET account_state='link_pending',onboarding_completed=true;
   INSERT INTO moneybowl_onboarding.events(actor_user_id,event_type,evidence) VALUES(u.id,'bootstrap_reconciliation_required','{}');
   RETURN QUERY SELECT 'link_pending'::public.user_account_state,true,CASE WHEN result='IDENTITY_RECONCILIATION_REQUIRED' THEN 'identity_reconciliation_required' ELSE 'verified_contacts_required' END;
   RETURN;
  END IF;
 END IF;
 RETURN QUERY SELECT * FROM moneybowl_onboarding.legacy_bootstrap();
END $$;

-- Narrow service hook: no new NSE caller or retry path. Existing outbox/worker
-- owns submission, immutable evidence, reconciliation and provider validation.
CREATE FUNCTION public.prepare_onboarded_investor_ucc(p_case_id uuid,p_external_account_candidate text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c moneybowl_onboarding.cases; d jsonb; op public.integration_operations;
BEGIN
 SELECT * INTO c FROM moneybowl_onboarding.cases WHERE id=p_case_id FOR UPDATE;
 IF c.id IS NULL OR c.reconciliation_reason IS NOT NULL OR NOT moneybowl_authz.assigned(c.workspace_id,c.actor_profile_id,c.investor_profile_id)
 OR jsonb_array_length(moneybowl_onboarding.missing(c))>0 THEN RAISE EXCEPTION 'onboarding_prerequisites_incomplete'; END IF;
 SELECT o.* INTO op FROM public.integration_operations o JOIN public.integration_accounts a ON a.id=o.integration_account_id
 WHERE a.workspace_id=c.workspace_id AND a.investor_profile_id=c.investor_profile_id AND o.operation_type='UCC_REGISTRATION'
 ORDER BY o.created_at DESC LIMIT 1;
 IF op.id IS NOT NULL THEN RETURN op.id; END IF;
 d:=moneybowl_onboarding.payload(c);
 SELECT * INTO op FROM public.prepare_nse_ucc_registration(c.workspace_id,c.investor_profile_id,jsonb_build_object(
 'external_account_candidate',p_external_account_candidate,'ucc_mode','physical','nse_codes',jsonb_build_object(
 'tax_status',d->>'tax_status','occupation_code',d->>'occupation_code','state',d->>'nse_state','country',d->>'nse_country',
 'mobile_declaration_flag',d->>'mobile_declaration_flag','email_declaration_flag',d->>'email_declaration_flag','div_pay_mode',d->>'div_pay_mode')));
 INSERT INTO moneybowl_onboarding.events(case_id,workspace_id,investor_profile_id,actor_user_id,event_type,evidence)
 VALUES(c.id,c.workspace_id,c.investor_profile_id,auth.uid(),'nse_registration_prepared',jsonb_build_object('integration_operation_id',op.id));
 RETURN op.id;
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA moneybowl_onboarding FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA moneybowl_onboarding FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.list_investor_onboarding_workspaces(),public.list_investor_onboarding(uuid),
 public.get_investor_onboarding(uuid),public.save_investor_onboarding(uuid,uuid,integer,jsonb),public.resolve_investor_onboarding(uuid,integer),
 public.bootstrap_identity(),public.prepare_onboarded_investor_ucc(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.list_investor_onboarding_workspaces(),public.list_investor_onboarding(uuid),
 public.get_investor_onboarding(uuid),public.save_investor_onboarding(uuid,uuid,integer,jsonb),public.resolve_investor_onboarding(uuid,integer),public.bootstrap_identity() TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_onboarded_investor_ucc(uuid,text) TO service_role;
COMMIT;
