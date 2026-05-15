-- 0006_rpcs.sql
-- Applied live to project rcldmmanvvtkkrbwpkgk via MCP apply_migration on this iteration.

create table if not exists public.order_folio_seq (
  clinic_id uuid primary key references public.clinics(id) on delete cascade,
  current_year smallint not null,
  current_n integer not null default 0
);

create or replace function public.next_order_folio(p_clinic uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  yy smallint := extract(year from now())::smallint;
  n  integer;
  is_member boolean;
begin
  select exists(
    select 1 from public.memberships m
    where m.clinic_id = p_clinic and m.user_id = auth.uid()
  ) into is_member;
  if not coalesce(is_member, false) then
    raise exception 'forbidden';
  end if;

  insert into public.order_folio_seq(clinic_id, current_year, current_n)
    values (p_clinic, yy, 1)
  on conflict (clinic_id) do update
    set current_year = case when public.order_folio_seq.current_year = yy
                            then public.order_folio_seq.current_year else yy end,
        current_n    = case when public.order_folio_seq.current_year = yy
                            then public.order_folio_seq.current_n + 1 else 1 end
  returning current_n into n;

  return format('SVL-%s-%s', to_char(yy % 100, 'FM00'), to_char(n, 'FM00000'));
end$$;

revoke all on function public.next_order_folio(uuid) from public;
grant execute on function public.next_order_folio(uuid) to authenticated;

create or replace function public.create_clinic(
  p_name text,
  p_phone text default null,
  p_address text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name';
  end if;

  insert into public.clinics(name, phone, address)
    values (trim(p_name), p_phone, p_address)
    returning id into v_id;

  insert into public.memberships(clinic_id, user_id, role)
    values (v_id, v_uid, 'OWNER');

  return v_id;
end$$;

revoke all on function public.create_clinic(text, text, text) from public;
grant execute on function public.create_clinic(text, text, text) to authenticated;
