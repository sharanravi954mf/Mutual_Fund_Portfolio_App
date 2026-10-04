-- Loaded only immediately before the containment migration in its local harness.
CREATE FUNCTION pg_temp.h(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT md5('authz-history-'||n)::uuid $$;
INSERT INTO auth.users(id,email,email_confirmed_at) SELECT pg_temp.h(n),'history-'||n||'@example.test',now() FROM generate_series(1,4) n;
INSERT INTO public.profiles(id,user_id,role) SELECT pg_temp.h(n),pg_temp.h(n),CASE WHEN n<3 THEN 'advisor' ELSE 'investor' END FROM generate_series(1,4) n;
UPDATE public.user_accounts SET account_state='advisor' WHERE user_id IN (pg_temp.h(1),pg_temp.h(2));
UPDATE public.user_accounts SET account_state='linked_investor' WHERE user_id IN (pg_temp.h(3),pg_temp.h(4));
INSERT INTO public.investor_account_links(user_id,profile_id,verification_method) VALUES(pg_temp.h(3),pg_temp.h(3),'test'),(pg_temp.h(4),pg_temp.h(4),'test');
INSERT INTO public.workspaces(id,name,slug) SELECT pg_temp.h(n),'History '||n,'authz-history-'||n FROM generate_series(100,102) n;
INSERT INTO public.workspace_memberships(workspace_id,profile_id,role,joined_at)
SELECT pg_temp.h(w),pg_temp.h(p),CASE WHEN p<3 THEN 'advisor' ELSE 'investor' END,'2026-01-01'
FROM (VALUES(100,1),(100,3),(101,2),(101,4),(102,2),(102,4)) x(w,p);
INSERT INTO public.advisor_investor_assignments(id,advisor_id,investor_id,assigned_at)
VALUES(pg_temp.h(501),pg_temp.h(1),pg_temp.h(3),'2026-02-01'),(pg_temp.h(502),pg_temp.h(2),pg_temp.h(4),'2026-02-01');
INSERT INTO public.folio_references(id,registrar,normalized_folio_number,amc_identity,source_folio_masked)
VALUES(pg_temp.h(601),'CAMS','HISTORY601','history','***601'),(pg_temp.h(602),'CAMS','HISTORY602','history','***602');
INSERT INTO public.portfolios(id,client_id,workspace_id)
VALUES(pg_temp.h(701),pg_temp.h(3),pg_temp.h(100)),(pg_temp.h(702),pg_temp.h(4),pg_temp.h(101)),(pg_temp.h(703),pg_temp.h(4),pg_temp.h(102));
INSERT INTO public.portfolio_folio_references(portfolio_id,folio_reference_id)
VALUES(pg_temp.h(701),pg_temp.h(601)),(pg_temp.h(702),pg_temp.h(602)),(pg_temp.h(703),pg_temp.h(602));
INSERT INTO public.verification_requests(id,user_id,method_code,status)
VALUES(pg_temp.h(801),pg_temp.h(3),'folio','approved'),(pg_temp.h(802),pg_temp.h(4),'folio','approved');
INSERT INTO public.verification_folio_evidence(request_id,folio_reference_id,holder_relationship,evidence_source)
VALUES(pg_temp.h(801),pg_temp.h(601),'SOLE_HOLDER','INVESTOR_DECLARATION'),(pg_temp.h(802),pg_temp.h(602),'SOLE_HOLDER','INVESTOR_DECLARATION');
INSERT INTO public.verification_request_assignments(request_id,advisor_account_id)
VALUES(pg_temp.h(801),pg_temp.h(1)),(pg_temp.h(802),pg_temp.h(2));
INSERT INTO public.folio_grants(request_id,user_id,profile_id,folio_reference_id,holder_relationship,approved_by)
VALUES(pg_temp.h(801),pg_temp.h(3),pg_temp.h(3),pg_temp.h(601),'SOLE_HOLDER',pg_temp.h(1)),(pg_temp.h(802),pg_temp.h(4),pg_temp.h(4),pg_temp.h(602),'SOLE_HOLDER',pg_temp.h(2));
