-- Isolated-runner instrumentation, never a migration. Snapshot taken before M2.
-- Every fixture event mutation checks the replacement against the actual base feed.
CREATE FUNCTION m2_baseline.check_feed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE types text[]; lim integer; delay integer; before_rows jsonb; after_rows jsonb;
BEGIN
 SELECT array_agg(DISTINCT event_type) INTO types FROM public.event_outbox;
 IF types IS NULL THEN RETURN NULL; END IF;
 FOREACH lim IN ARRAY ARRAY[1,4,50] LOOP
  FOREACH delay IN ARRAY ARRAY[0,30,3600] LOOP
   SELECT COALESCE(jsonb_agg(to_jsonb(q)),'[]'::jsonb) INTO before_rows FROM m2_baseline.original_feed(types,lim,delay) q;
   SELECT COALESCE(jsonb_agg(to_jsonb(q)),'[]'::jsonb) INTO after_rows FROM public.list_dispatchable_outbox_events(types,lim,delay) q;
   IF before_rows IS DISTINCT FROM after_rows THEN RAISE EXCEPTION 'm2_feed_parity_failed'; END IF;
  END LOOP;
 END LOOP;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION m2_baseline.check_feed() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER m2_test_feed_parity AFTER INSERT OR UPDATE ON public.event_outbox
FOR EACH STATEMENT EXECUTE FUNCTION m2_baseline.check_feed();
