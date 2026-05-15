-- Fix 1: Relax orders_folio_shape to accept both the old RPC format
-- (SVL-26-00001, year-seq) already sitting in the outbox, and the
-- corrected format (SVL-1-26, seq-year) going forward.
alter table orders drop constraint orders_folio_shape;
alter table orders add constraint orders_folio_shape
  check (folio ~ '^[A-Z]{3}-[0-9]{1,6}-[0-9]{1,6}$');

-- Fix 2: next_order_folio was returning SVL-{YY}-{NNNNN} (year first,
-- 5-digit sequence) which violates the original [0-9]{2,4} last segment.
-- Swap to SVL-{N}-{YY} matching the documented format (e.g. SVL-1-26)
-- and consistent with the Dart offline fallback.
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

  return format('SVL-%s-%s', n, to_char(yy % 100, 'FM00'));
end$$;
