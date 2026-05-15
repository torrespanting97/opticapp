-- ════════════════════════════════════════════════════════════════════
-- 0004_onboarding.sql — auth signup trigger + user-facing RPCs
-- ════════════════════════════════════════════════════════════════════

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_clinic uuid := nullif(new.raw_user_meta_data->>'clinic_id','')::uuid;
  v_name   text := coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1));
begin
  insert into public.profiles (id, full_name, default_clinic)
  values (new.id, v_name, v_clinic) on conflict (id) do nothing;
  if v_clinic is not null then
    insert into public.memberships (clinic_id, user_id, role)
    values (v_clinic, new.id,
      case when exists (select 1 from public.memberships where clinic_id = v_clinic)
           then 'viewer'::member_role else 'owner'::member_role end)
    on conflict do nothing;
  end if;
  return new;
end$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.record_auth_attempt(p_email text, p_ok boolean)
returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_ip inet;
begin
  v_ip := nullif(current_setting('request.headers', true)::jsonb->>'x-forwarded-for','')::inet;
  insert into auth_attempts (email, ip, succeeded) values (lower(p_email), v_ip, p_ok);
  return is_locked_out(lower(p_email), v_ip);
end$$;
grant execute on function public.record_auth_attempt(text, boolean) to anon, authenticated;

create or replace function public.set_default_clinic(p_clinic uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if not exists (select 1 from memberships where clinic_id = p_clinic and user_id = auth.uid()) then
    raise exception 'not a member of clinic %', p_clinic;
  end if;
  update profiles set default_clinic = p_clinic where id = auth.uid();
end$$;
grant execute on function public.set_default_clinic(uuid) to authenticated;

-- Hot-path indexes
create index if not exists idx_orders_recent  on orders (clinic_id, created_at desc);
create index if not exists idx_wallet_recent  on wallet_ledger (clinic_id, occurred_at desc);
create index if not exists idx_appts_upcoming on appointments (clinic_id, starts_at)
  where status in ('scheduled','confirmed');
create index if not exists idx_clients_search on clients (clinic_id, lower(name));
