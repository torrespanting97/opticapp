-- ════════════════════════════════════════════════════════════════════
-- 0005_advisor_fixes.sql — close every Supabase linter finding
-- ════════════════════════════════════════════════════════════════════

-- SECURITY DEFINER view → SECURITY INVOKER
drop view if exists public.client_balances;
create view public.client_balances with (security_invoker = on) as
  select client_id, clinic_id, sum(amount) as balance
  from public.wallet_ledger group by client_id, clinic_id;

-- Pin search_path on every function
alter function public.is_locked_out(text, inet) set search_path = pg_catalog, public;

-- RLS on remaining tables (deny-all by default)
alter table public.geocode_cache  enable row level security;
alter table public.auth_attempts  enable row level security;
alter table public.rate_limit     enable row level security;
alter table public.audit_log_2026_05 enable row level security;
alter table public.audit_log_2026_06 enable row level security;
alter table public.audit_log_2026_07 enable row level security;

create policy "geocode_read" on public.geocode_cache for select to authenticated using (true);
-- auth_attempts + rate_limit + audit_log partitions: no policies = no client access.

-- Move pg_trgm out of public schema
drop index if exists public.clients_name_idx;
drop extension if exists pg_trgm;
create extension pg_trgm with schema extensions;
create index clients_name_trgm_idx on public.clients
  using gin (name extensions.gin_trgm_ops);

-- stats_daily mat view → not directly exposed; access via SECURITY INVOKER RPC
revoke select on public.stats_daily from anon, authenticated;
create or replace function public.clinic_stats(p_from date, p_to date)
returns table(d date, orders bigint, gross numeric, collected numeric, outstanding numeric)
language sql stable security invoker set search_path = pg_catalog, public as $$
  select d, orders, gross, collected, outstanding
  from public.stats_daily
  where clinic_id = current_clinic() and d between p_from and p_to
  order by d desc
$$;
grant execute on function public.clinic_stats(date, date) to authenticated;

-- Public storage bucket cannot list objects
drop policy if exists "clinic_assets_read_all" on storage.objects;

-- Lock down internal SECURITY DEFINER helpers
revoke all on function public._audit_row()                                from public, anon, authenticated;
revoke all on function public._enc_key()                                  from public, anon, authenticated;
revoke all on function public.pii_encrypt(text)                           from public, anon, authenticated;
revoke all on function public.handle_new_user()                           from public, anon, authenticated;
revoke all on function public.rate_limit_hit(text, integer, interval)     from public, anon, authenticated;

-- Public RPCs — explicit grants
grant execute on function public.delete_client(uuid)                 to authenticated;
grant execute on function public.set_default_clinic(uuid)            to authenticated;
grant execute on function public.pii_decrypt(text)                   to authenticated;
grant execute on function public.record_auth_attempt(text, boolean)  to anon, authenticated;
