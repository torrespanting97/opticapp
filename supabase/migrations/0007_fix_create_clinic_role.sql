-- Fix create_clinic: 'OWNER' was not a valid member_role enum value (must be lowercase 'owner').
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
    values (v_id, v_uid, 'owner'::member_role);

  return v_id;
end$$;

revoke all on function public.create_clinic(text, text, text) from public;
grant execute on function public.create_clinic(text, text, text) to authenticated;
