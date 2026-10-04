BEGIN;
CREATE FUNCTION pg_temp.h(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT md5('authz-history-'||n)::uuid $$;
DO $$ BEGIN
 IF (SELECT workspace_id FROM public.advisor_investor_assignments WHERE id=pg_temp.h(501)) IS DISTINCT FROM pg_temp.h(100) THEN RAISE EXCEPTION 'unique historical assignment not preserved'; END IF;
 IF (SELECT workspace_id FROM public.advisor_investor_assignments WHERE id=pg_temp.h(502)) IS NOT NULL THEN RAISE EXCEPTION 'ambiguous historical assignment guessed'; END IF;
 IF (SELECT workspace_id FROM public.folio_grants WHERE request_id=pg_temp.h(801)) IS DISTINCT FROM pg_temp.h(100) THEN RAISE EXCEPTION 'unique historical grant not preserved'; END IF;
 IF (SELECT workspace_id FROM public.folio_grants WHERE request_id=pg_temp.h(802)) IS NOT NULL THEN RAISE EXCEPTION 'ambiguous historical grant guessed'; END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',pg_temp.h(3)::text,true);
DO $$ BEGIN IF NOT public.has_active_folio_grant(pg_temp.h(3),pg_temp.h(701)) THEN RAISE EXCEPTION 'unique historical investor flow lost'; END IF; END $$;
SELECT set_config('request.jwt.claim.sub',pg_temp.h(4)::text,true);
DO $$ BEGIN IF public.has_active_folio_grant(pg_temp.h(4),pg_temp.h(702)) OR public.has_active_folio_grant(pg_temp.h(4),pg_temp.h(703)) THEN RAISE EXCEPTION 'ambiguous historical grant authorized'; END IF; END $$;
ROLLBACK;
