-- Claims never grant authority. Only the guarded approval transaction admits an MFD.
BEGIN;
CREATE SCHEMA mfd_application_private;
REVOKE ALL ON SCHEMA mfd_application_private FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE public.mfd_applications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 applicant_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 applicant_email text NOT NULL,
 business_name text NOT NULL CHECK (business_name=btrim(business_name,E' \t\r\n\f') AND length(business_name) BETWEEN 1 AND 200),
 claimed_arn text NOT NULL CHECK (claimed_arn=btrim(claimed_arn,E' \t\r\n\f') AND length(claimed_arn) BETWEEN 1 AND 100),
 applicant_note text CHECK (applicant_note=btrim(applicant_note,E' \t\r\n\f') AND length(applicant_note) BETWEEN 1 AND 2000),
 status text NOT NULL DEFAULT 'submitted' CHECK(status IN ('submitted','under_review','approved','rejected')),
 version integer NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 3),
 submitted_at timestamptz NOT NULL DEFAULT now(),
 review_started_at timestamptz,
 review_started_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 decided_at timestamptz,
 decided_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 decision_note text CHECK(decision_note=btrim(decision_note,E' \t\r\n\f') AND length(decision_note) BETWEEN 1 AND 2000),
 approved_business_name text,
 approved_arn text,
 profile_id uuid UNIQUE REFERENCES public.profiles(id) ON DELETE RESTRICT,
 workspace_id uuid UNIQUE REFERENCES public.workspaces(id) ON DELETE RESTRICT,
 membership_id uuid UNIQUE REFERENCES public.workspace_memberships(id) ON DELETE RESTRICT,
 CHECK ((status='submitted' AND version=1 AND review_started_at IS NULL AND review_started_by IS NULL)
   OR (status IN ('under_review','approved','rejected') AND review_started_at IS NOT NULL AND review_started_by IS NOT NULL AND review_started_at>=submitted_at)),
 CHECK ((status IN ('submitted','under_review') AND decided_at IS NULL AND decided_by IS NULL AND decision_note IS NULL)
   OR (status IN ('approved','rejected') AND version=3 AND decided_at IS NOT NULL AND decided_by IS NOT NULL AND decision_note IS NOT NULL AND decided_at>=review_started_at)),
 CHECK (status<>'under_review' OR version=2),
 CHECK ((status='approved' AND approved_business_name IS NOT NULL AND approved_business_name=business_name
     AND approved_arn IS NOT NULL AND approved_arn=claimed_arn AND profile_id IS NOT NULL AND workspace_id IS NOT NULL AND membership_id IS NOT NULL)
   OR (status<>'approved' AND approved_business_name IS NULL AND approved_arn IS NULL AND profile_id IS NULL AND workspace_id IS NULL AND membership_id IS NULL))
);
CREATE UNIQUE INDEX mfd_one_open_application ON public.mfd_applications(applicant_user_id) WHERE status IN ('submitted','under_review');
CREATE UNIQUE INDEX mfd_one_approved_application ON public.mfd_applications(applicant_user_id) WHERE status='approved';
CREATE INDEX mfd_application_applicant_history ON public.mfd_applications(applicant_user_id,submitted_at DESC,id);
CREATE INDEX mfd_application_queue ON public.mfd_applications(submitted_at DESC,id);

CREATE TABLE public.mfd_application_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 application_id uuid NOT NULL REFERENCES public.mfd_applications(id) ON DELETE RESTRICT,
 applicant_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 occurred_at timestamptz NOT NULL DEFAULT now(),
 event_type text NOT NULL CHECK(event_type IN ('submitted','review_started','approved','rejected')),
 request_id uuid NOT NULL UNIQUE,
 previous_status text,
 new_status text NOT NULL,
 previous_version integer,
 new_version integer NOT NULL,
 details jsonb NOT NULL CHECK(jsonb_typeof(details)='object'),
 UNIQUE(application_id,event_type),
 CHECK ((event_type='submitted' AND previous_status IS NULL AND previous_version IS NULL AND new_status='submitted' AND new_version=1)
   OR (event_type='review_started' AND previous_status IS NOT NULL AND previous_status='submitted' AND previous_version IS NOT NULL AND previous_version=1 AND new_status='under_review' AND new_version=2)
   OR (event_type IN ('approved','rejected') AND previous_status IS NOT NULL AND previous_status='under_review' AND previous_version IS NOT NULL AND previous_version=2 AND new_status=event_type AND new_version=3))
);
CREATE UNIQUE INDEX mfd_one_terminal_event ON public.mfd_application_events(application_id) WHERE event_type IN ('approved','rejected');
CREATE INDEX mfd_events_application ON public.mfd_application_events(application_id,occurred_at);

-- Separate receipts also represent no-op review-start retries without duplicate events.
CREATE TABLE mfd_application_private.requests (
 request_id uuid PRIMARY KEY,
 actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 operation text NOT NULL CHECK(operation IN ('submit','start_review','approve','reject')),
 input jsonb NOT NULL,
 application_id uuid NOT NULL REFERENCES public.mfd_applications(id) ON DELETE RESTRICT,
 result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.mfd_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mfd_application_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfd_application_private.requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.mfd_applications,public.mfd_application_events,mfd_application_private.requests FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.mfd_applications,public.mfd_application_events TO authenticated;
CREATE POLICY mfd_application_read ON public.mfd_applications FOR SELECT TO authenticated
 USING(applicant_user_id=(SELECT auth.uid()) OR (SELECT public.has_platform_capability('mfd_applications.review')));
CREATE POLICY mfd_event_read ON public.mfd_application_events FOR SELECT TO authenticated
 USING(applicant_user_id=(SELECT auth.uid()) OR (SELECT public.has_platform_capability('mfd_applications.review')));

CREATE FUNCTION mfd_application_private.immutable() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$ BEGIN RAISE EXCEPTION 'mfd_history_immutable'; END $$;
CREATE TRIGGER mfd_event_immutable BEFORE UPDATE OR DELETE ON public.mfd_application_events FOR EACH ROW EXECUTE FUNCTION mfd_application_private.immutable();
CREATE TRIGGER mfd_receipt_immutable BEFORE UPDATE OR DELETE ON mfd_application_private.requests FOR EACH ROW EXECUTE FUNCTION mfd_application_private.immutable();
CREATE FUNCTION mfd_application_private.guard_application() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'mfd_history_immutable'; END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.status<>'submitted' THEN RAISE EXCEPTION 'mfd_transition_invalid'; END IF;
 ELSE
  IF (NEW.id,NEW.applicant_user_id,NEW.applicant_email,NEW.business_name,NEW.claimed_arn,NEW.applicant_note,NEW.submitted_at)
   IS DISTINCT FROM (OLD.id,OLD.applicant_user_id,OLD.applicant_email,OLD.business_name,OLD.claimed_arn,OLD.applicant_note,OLD.submitted_at) THEN RAISE EXCEPTION 'mfd_claims_immutable'; END IF;
  IF NOT ((OLD.status='submitted' AND NEW.status='under_review') OR (OLD.status='under_review' AND NEW.status IN ('approved','rejected')))
   OR NEW.version<>OLD.version+1 THEN RAISE EXCEPTION 'mfd_transition_invalid'; END IF;
  IF OLD.status='under_review' AND (NEW.review_started_at,NEW.review_started_by) IS DISTINCT FROM (OLD.review_started_at,OLD.review_started_by) THEN RAISE EXCEPTION 'mfd_history_immutable'; END IF;
 END IF;
 IF NEW.status='approved' AND NOT EXISTS (
  SELECT 1 FROM public.profiles p JOIN public.workspaces w ON w.owner_profile_id=p.id
   JOIN public.workspace_memberships m ON m.workspace_id=w.id AND m.profile_id=p.id
  WHERE p.id=NEW.profile_id AND p.user_id=NEW.applicant_user_id AND p.role='advisor' AND p.account_status='active'
   AND w.id=NEW.workspace_id AND w.workspace_status='active' AND m.id=NEW.membership_id AND m.role='admin' AND m.status='active' AND m.ended_at IS NULL
 ) THEN RAISE EXCEPTION 'mfd_provisioning_invalid'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER mfd_application_guard BEFORE INSERT OR UPDATE OR DELETE ON public.mfd_applications FOR EACH ROW EXECUTE FUNCTION mfd_application_private.guard_application();

CREATE FUNCTION mfd_application_private.require_browser() RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR current_setting('role',true) IS DISTINCT FROM 'authenticated' THEN
  RAISE EXCEPTION 'mfd_authentication_required' USING ERRCODE='42501';
 END IF;
END $$;
CREATE FUNCTION mfd_application_private.eligible(p_user uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM auth.users u JOIN public.user_accounts a ON a.user_id=u.id
  WHERE u.id=p_user AND u.email_confirmed_at IS NOT NULL AND nullif(btrim(u.email,E' \t\r\n\f'),'') IS NOT NULL
   AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false) AND (u.banned_until IS NULL OR u.banned_until<=now())
   AND a.account_state='explorer'
   AND NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.user_id=u.id)
   AND NOT EXISTS(SELECT 1 FROM public.investor_account_links l WHERE l.user_id=u.id AND l.link_status='active')
   AND NOT EXISTS(SELECT 1 FROM platform_authority.grants g WHERE g.user_id=u.id AND g.grant_key='platform_admin' AND g.revoked_at IS NULL)
   AND NOT EXISTS(SELECT 1 FROM public.mfd_applications m WHERE m.applicant_user_id=u.id AND m.status='approved'))
$$;
CREATE FUNCTION mfd_application_private.lock_applicant(p_user uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 -- Serializes account lifecycle/platform commissioning and existing identity bootstrap/admission.
 PERFORM 1 FROM auth.users WHERE id=p_user FOR UPDATE;
 PERFORM 1 FROM public.user_accounts WHERE user_id=p_user FOR UPDATE;
END $$;
CREATE FUNCTION mfd_application_private.replay(p_request uuid,p_operation text,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r mfd_application_private.requests;
BEGIN
 IF p_request IS NULL THEN RAISE EXCEPTION 'mfd_invalid_input'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('mfd-request:'||p_request::text,0));
 SELECT * INTO r FROM mfd_application_private.requests WHERE request_id=p_request;
 IF FOUND THEN
  IF (r.actor_user_id,r.operation,r.input) IS DISTINCT FROM (auth.uid(),p_operation,p_input) THEN RAISE EXCEPTION 'mfd_request_conflict'; END IF;
  RETURN r.result;
 END IF;
 RETURN NULL;
END $$;
CREATE FUNCTION mfd_application_private.receipt(p_request uuid,p_operation text,p_input jsonb,p_application public.mfd_applications) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb:=to_jsonb(p_application);
BEGIN
 INSERT INTO mfd_application_private.requests(request_id,actor_user_id,operation,input,application_id,result)
 VALUES(p_request,auth.uid(),p_operation,p_input,p_application.id,result);
 RETURN result;
END $$;
CREATE FUNCTION mfd_application_private.require_reviewer() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM mfd_application_private.require_browser();
 PERFORM 1 FROM auth.users WHERE id=auth.uid() FOR SHARE;
 PERFORM 1 FROM public.profiles WHERE user_id=auth.uid() FOR SHARE;
 PERFORM 1 FROM platform_authority.grants WHERE user_id=auth.uid() AND grant_key IN ('platform_admin','mfd_applications.review') ORDER BY id FOR SHARE;
 IF NOT public.has_platform_capability('mfd_applications.review') THEN RAISE EXCEPTION 'platform_capability_required' USING ERRCODE='42501'; END IF;
END $$;

CREATE FUNCTION public.get_my_mfd_application_context() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM mfd_application_private.require_browser();
 RETURN jsonb_build_object('can_apply',mfd_application_private.eligible(auth.uid()) AND NOT EXISTS(
  SELECT 1 FROM public.mfd_applications WHERE applicant_user_id=auth.uid() AND status IN ('submitted','under_review')));
END $$;
CREATE FUNCTION public.submit_mfd_application(p_request_id uuid,p_business_name text,p_claimed_arn text,p_applicant_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a public.mfd_applications; input jsonb; replay jsonb;
BEGIN
 PERFORM mfd_application_private.require_browser();
 p_business_name:=btrim(p_business_name,E' \t\r\n\f'); p_claimed_arn:=btrim(p_claimed_arn,E' \t\r\n\f'); p_applicant_note:=nullif(btrim(p_applicant_note,E' \t\r\n\f'),'');
 IF p_business_name IS NULL OR length(p_business_name) NOT BETWEEN 1 AND 200 OR p_claimed_arn IS NULL OR length(p_claimed_arn) NOT BETWEEN 1 AND 100
  OR length(p_applicant_note)>2000 THEN RAISE EXCEPTION 'mfd_invalid_input'; END IF;
 input:=jsonb_build_object('business_name',p_business_name,'claimed_arn',p_claimed_arn,'applicant_note',p_applicant_note);
 replay:=mfd_application_private.replay(p_request_id,'submit',input); IF replay IS NOT NULL THEN RETURN replay; END IF;
 PERFORM mfd_application_private.lock_applicant(auth.uid());
 IF NOT mfd_application_private.eligible(auth.uid()) THEN RAISE EXCEPTION 'mfd_applicant_ineligible'; END IF;
 IF EXISTS(SELECT 1 FROM public.mfd_applications WHERE applicant_user_id=auth.uid() AND status IN ('submitted','under_review')) THEN RAISE EXCEPTION 'mfd_application_open'; END IF;
 INSERT INTO public.mfd_applications(applicant_user_id,applicant_email,business_name,claimed_arn,applicant_note)
 SELECT auth.uid(),u.email,p_business_name,p_claimed_arn,p_applicant_note FROM auth.users u WHERE u.id=auth.uid() RETURNING * INTO a;
 INSERT INTO public.mfd_application_events(application_id,applicant_user_id,actor_user_id,event_type,request_id,new_status,new_version,details)
 VALUES(a.id,a.applicant_user_id,auth.uid(),'submitted',p_request_id,'submitted',1,jsonb_build_object('business_name',a.business_name,'claimed_arn',a.claimed_arn));
 RETURN mfd_application_private.receipt(p_request_id,'submit',input,a);
END $$;
CREATE FUNCTION public.start_mfd_application_review(p_application_id uuid,p_expected_version integer,p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a public.mfd_applications; applicant uuid; input jsonb; replay jsonb;
BEGIN
 PERFORM mfd_application_private.require_reviewer();
 IF p_application_id IS NULL OR p_expected_version IS NULL THEN RAISE EXCEPTION 'mfd_invalid_input'; END IF;
 input:=jsonb_build_object('application_id',p_application_id,'expected_version',p_expected_version);
 replay:=mfd_application_private.replay(p_request_id,'start_review',input); IF replay IS NOT NULL THEN RETURN replay; END IF;
 SELECT applicant_user_id INTO applicant FROM public.mfd_applications WHERE id=p_application_id;
 IF applicant IS NULL THEN RAISE EXCEPTION 'mfd_application_unavailable'; END IF;
 PERFORM mfd_application_private.lock_applicant(applicant);
 SELECT * INTO a FROM public.mfd_applications WHERE id=p_application_id FOR UPDATE;
 IF a.status IN ('approved','rejected') THEN RAISE EXCEPTION 'mfd_application_decided'; END IF;
 -- Another reviewer already started: no new transition/event, even with the old version.
 IF a.status='under_review' THEN RETURN mfd_application_private.receipt(p_request_id,'start_review',input,a); END IF;
 IF a.version<>p_expected_version THEN RAISE EXCEPTION 'mfd_application_changed'; END IF;
 UPDATE public.mfd_applications SET status='under_review',version=2,review_started_by=auth.uid(),review_started_at=now()
 WHERE id=a.id RETURNING * INTO a;
 INSERT INTO public.mfd_application_events(application_id,applicant_user_id,actor_user_id,event_type,request_id,previous_status,new_status,previous_version,new_version,details)
 VALUES(a.id,a.applicant_user_id,auth.uid(),'review_started',p_request_id,'submitted','under_review',1,2,'{}');
 RETURN mfd_application_private.receipt(p_request_id,'start_review',input,a);
END $$;

-- Internal implementation shared by the two public, fixed-action decision endpoints.
CREATE FUNCTION mfd_application_private.decide(p_application_id uuid,p_expected_version integer,p_request_id uuid,p_note text,p_approve boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a public.mfd_applications; applicant uuid; input jsonb; replay jsonb; operation text; v_profile_id uuid; v_workspace_id uuid; v_membership_id uuid;
BEGIN
 PERFORM mfd_application_private.require_browser();
 PERFORM platform_authority.require_mutation('mfd_applications.review');
 p_note:=btrim(p_note,E' \t\r\n\f');
 IF p_application_id IS NULL OR p_expected_version IS NULL OR p_note IS NULL OR length(p_note) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'mfd_decision_note_required'; END IF;
 operation:=CASE WHEN p_approve THEN 'approve' ELSE 'reject' END;
 input:=jsonb_build_object('application_id',p_application_id,'expected_version',p_expected_version,'note',p_note);
 replay:=mfd_application_private.replay(p_request_id,operation,input); IF replay IS NOT NULL THEN RETURN replay; END IF;
 SELECT applicant_user_id INTO applicant FROM public.mfd_applications WHERE id=p_application_id;
 IF applicant IS NULL THEN RAISE EXCEPTION 'mfd_application_unavailable'; END IF;
 PERFORM mfd_application_private.lock_applicant(applicant);
 SELECT * INTO a FROM public.mfd_applications WHERE id=p_application_id FOR UPDATE;
 IF a.status IN ('approved','rejected') THEN RAISE EXCEPTION 'mfd_application_decided'; END IF;
 IF a.status<>'under_review' OR a.version<>p_expected_version THEN RAISE EXCEPTION 'mfd_application_changed'; END IF;
 IF p_approve THEN
  IF NOT mfd_application_private.eligible(applicant) THEN RAISE EXCEPTION 'mfd_applicant_ineligible'; END IF;
  INSERT INTO public.profiles(user_id,role,account_status,full_name,email)
  VALUES(applicant,'advisor','active',a.business_name,a.applicant_email) RETURNING id INTO v_profile_id;
  INSERT INTO public.workspaces(name,slug,owner_profile_id,workspace_status)
  VALUES(a.business_name,'mfd-'||a.id::text,v_profile_id,'active') RETURNING id INTO v_workspace_id;
  INSERT INTO public.workspace_memberships(workspace_id,profile_id,role,status)
  VALUES(v_workspace_id,v_profile_id,'admin','active') RETURNING id INTO v_membership_id;
  UPDATE public.user_accounts SET account_state='advisor',onboarding_completed=true WHERE user_id=applicant;
  UPDATE public.mfd_applications SET status='approved',version=3,decided_at=now(),decided_by=auth.uid(),decision_note=p_note,
   approved_business_name=a.business_name,approved_arn=a.claimed_arn,profile_id=v_profile_id,workspace_id=v_workspace_id,membership_id=v_membership_id
  WHERE id=a.id RETURNING * INTO a;
 ELSE
  -- Rejection records a decision only. Never resets a subsequently changed identity.
  UPDATE public.mfd_applications SET status='rejected',version=3,decided_at=now(),decided_by=auth.uid(),decision_note=p_note WHERE id=a.id RETURNING * INTO a;
 END IF;
 INSERT INTO public.mfd_application_events(application_id,applicant_user_id,actor_user_id,event_type,request_id,previous_status,new_status,previous_version,new_version,details)
 VALUES(a.id,applicant,auth.uid(),a.status,p_request_id,'under_review',a.status,2,3,
  jsonb_build_object('decision_note',p_note,'claimed_arn',a.claimed_arn,'approved_arn',a.approved_arn,'approved_business_name',a.approved_business_name,
   'profile_id',a.profile_id,'workspace_id',a.workspace_id,'membership_id',a.membership_id,'registration_review',CASE WHEN p_approve THEN 'manual_platform_review' ELSE NULL END));
 IF p_approve THEN
  INSERT INTO public.workspace_audit_logs(workspace_id,actor_user_id,actor_type,action,event_type,target_type,target_id,correlation_id,payload)
  VALUES(a.workspace_id,auth.uid(),'platform_admin','mfd.application_provisioned','mfd.application_provisioned','mfd_application',a.id,p_request_id,
   jsonb_build_object('application_id',a.id,'applicant_user_id',applicant,'profile_id',a.profile_id,'workspace_id',a.workspace_id,'membership_id',a.membership_id));
 END IF;
 RETURN mfd_application_private.receipt(p_request_id,operation,input,a);
END $$;
CREATE FUNCTION public.approve_mfd_application(p_application_id uuid,p_expected_version integer,p_request_id uuid,p_evidence text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT mfd_application_private.decide(p_application_id,p_expected_version,p_request_id,p_evidence,true) $$;
CREATE FUNCTION public.reject_mfd_application(p_application_id uuid,p_expected_version integer,p_request_id uuid,p_reason text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT mfd_application_private.decide(p_application_id,p_expected_version,p_request_id,p_reason,false) $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA mfd_application_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_my_mfd_application_context(),public.submit_mfd_application(uuid,text,text,text),public.start_mfd_application_review(uuid,integer,uuid),public.approve_mfd_application(uuid,integer,uuid,text),public.reject_mfd_application(uuid,integer,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_my_mfd_application_context(),public.submit_mfd_application(uuid,text,text,text),public.start_mfd_application_review(uuid,integer,uuid),public.approve_mfd_application(uuid,integer,uuid,text),public.reject_mfd_application(uuid,integer,uuid,text) TO authenticated;
COMMIT;
