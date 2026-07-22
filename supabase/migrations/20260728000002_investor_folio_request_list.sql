-- Sprint 5.3.7: safe Investor request-list projection. Masking retains only
-- the final four canonical folio characters; shorter values are fully masked.
create or replace function public.mask_canonical_folio(p_folio text) returns text as $$
begin
  if p_folio is null or p_folio='' then return '••••'; end if;
  if length(p_folio)<=4 then return repeat('•',length(p_folio)); end if;
  return repeat('•',length(p_folio)-4)||right(p_folio,4);
end; $$ language plpgsql immutable security definer set search_path=public,pg_temp;

create or replace function public.get_my_folio_requests(p_page integer default 0,p_page_size integer default 25)
returns table(request_id uuid,version integer,registrar_display text,masked_folio text,status public.verification_request_status,submitted_at timestamptz) as $$
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if p_page < 0 or p_page_size < 1 or p_page_size > 100 then raise exception 'Invalid pagination'; end if;
  return query
  select r.id,r.version,case when f.registrar='KFINTECH' then 'KFintech' else 'CAMS' end,
    public.mask_canonical_folio(f.normalized_folio_number),r.status,r.submitted_at
  from public.verification_requests r
  join public.verification_folio_evidence e on e.request_id=r.id
  join public.folio_references f on f.id=e.folio_reference_id
  where r.user_id=auth.uid() and r.method_code='folio'
  order by r.submitted_at desc nulls last,r.created_at desc,r.id desc
  limit p_page_size offset p_page*p_page_size;
end; $$ language plpgsql security definer set search_path=public,pg_temp;

revoke all on function public.mask_canonical_folio(text) from public,anon,authenticated,service_role;
revoke all on function public.get_my_folio_requests(integer,integer) from public,anon,service_role;
grant execute on function public.get_my_folio_requests(integer,integer) to authenticated;
