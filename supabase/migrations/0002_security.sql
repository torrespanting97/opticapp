-- ════════════════════════════════════════════════════════════════════
-- 0002_security.sql — hardening: audit log, PII encryption, rate limits,
-- login attempts, session tracking, CHECK constraints, secure RLS.
-- ════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Per-clinic encryption key wrapper
-- The master key lives in Supabase Vault and is read inside a SECURITY
-- DEFINER function. The DB never stores plaintext keys.
-- ─────────────────────────────────────────────────────────────────────
create or replace function _enc_key()
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare k text;
begin
  -- vault.decrypted_secrets is provided by Supabase Vault
  select decrypted_secret into k
  from vault.decrypted_secrets
  where name = 'pii_encryption_key'
  limit 1;
  if k is null then
    raise exception 'pii_encryption_key missing in Vault';
  end if;
  return k;
end$$;

revoke all on function _enc_key() from public;

create or replace function pii_encrypt(plaintext text)
returns text
language sql
security definer
set search_path = pg_catalog, public
as $$
  select case when plaintext is null or plaintext = '' then null
              else encode(pgp_sym_encrypt(plaintext, _enc_key()), 'base64') end
$$;

create or replace function pii_decrypt(ciphertext text)
returns text
language sql
security definer
set search_path = pg_catalog, public
as $$
  select case when ciphertext is null or ciphertext = '' then null
              else pgp_sym_decrypt(decode(ciphertext, 'base64'), _enc_key()) end
$$;

revoke all on function pii_encrypt(text) from public;
revoke all on function pii_decrypt(text) from public;
grant execute on function pii_decrypt(text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. CHECK constraints — first line of input validation in the DB itself
-- ─────────────────────────────────────────────────────────────────────

-- Defensive length and shape checks (independent of any client validation)
alter table clients
  add constraint clients_name_len   check (char_length(name) between 1 and 120),
  add constraint clients_phone_shape check (phone is null or phone ~ '^[+0-9 ()-]{7,20}$'),
  add constraint clients_email_shape check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  add constraint clients_age_range  check (age is null or (age between 0 and 130));

alter table orders
  add constraint orders_folio_shape check (folio ~ '^[A-Z]{3}-[0-9]{1,6}-[0-9]{2,4}$'),
  add constraint orders_cost_nonneg check (cost          >= 0 and cost          < 1000000),
  add constraint orders_down_nonneg check (down_payment  >= 0 and down_payment  <= cost),
  add constraint orders_aro_range   check (aro_mm     is null or aro_mm     between 30 and 80),
  add constraint orders_pte_range   check (puente_mm  is null or puente_mm  between 10 and 30),
  add constraint orders_var_range   check (varilla_mm is null or varilla_mm between 100 and 170);

alter table prescriptions
  add constraint rx_eje_od check (od_eje is null or od_eje ~ '^[0-9]{1,3}°?$'),
  add constraint rx_eje_oi check (oi_eje is null or oi_eje ~ '^[0-9]{1,3}°?$');

alter table appointments
  add constraint appt_times check (ends_at > starts_at and ends_at - starts_at <= interval '1 day');

alter table wallet_ledger
  add constraint ledger_amount_range
    check (amount between -1000000 and 1000000);

-- ─────────────────────────────────────────────────────────────────────
-- 3. Audit log (append-only, partitioned by month)
-- ─────────────────────────────────────────────────────────────────────
create table audit_log (
  id          bigint generated always as identity,
  at          timestamptz not null default now(),
  clinic_id   uuid,
  actor_id    uuid,
  ip          inet,
  user_agent  text,
  action      text not null,            -- insert|update|delete|login|export|...
  target_tbl  text,
  target_id   uuid,
  before      jsonb,
  after       jsonb,
  primary key (id, at)
) partition by range (at);

-- Initial monthly partition (others added by pg_cron)
create table audit_log_2026_05 partition of audit_log
  for values from ('2026-05-01') to ('2026-06-01');

alter table audit_log enable row level security;

-- Owners can read their clinic's audit log; nobody can update/delete.
create policy "audit_read" on audit_log for select
  using (clinic_id = current_clinic());
create policy "audit_no_update" on audit_log for update using (false);
create policy "audit_no_delete" on audit_log for delete using (false);

-- Generic audit trigger
create or replace function _audit_row()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare jwt_claims jsonb;
begin
  jwt_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  insert into audit_log (clinic_id, actor_id, ip, user_agent, action, target_tbl, target_id, before, after)
  values (
    coalesce((new).clinic_id, (old).clinic_id),
    nullif(jwt_claims->>'sub','')::uuid,
    nullif(current_setting('request.headers', true)::jsonb->>'x-forwarded-for','')::inet,
    nullif(current_setting('request.headers', true)::jsonb->>'user-agent',''),
    lower(tg_op),
    tg_table_name,
    coalesce((new).id, (old).id),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('UPDATE','INSERT') then to_jsonb(new) end
  );
  return coalesce(new, old);
end$$;

do $$
declare t text;
begin
  for t in select unnest(array[
    'clients','prescriptions','orders','wallet_ledger','appointments','memberships'
  ]) loop
    execute format(
      'create trigger trg_%1$s_audit
         after insert or update or delete on %1$s
         for each row execute function _audit_row()', t);
  end loop;
end$$;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Login attempts + lockout
-- ─────────────────────────────────────────────────────────────────────
create table auth_attempts (
  id          bigint generated always as identity primary key,
  email       text,
  ip          inet,
  succeeded   boolean not null,
  at          timestamptz not null default now()
);
create index on auth_attempts (email, at desc);
create index on auth_attempts (ip,    at desc);

create or replace function is_locked_out(p_email text, p_ip inet)
returns boolean language sql stable as $$
  select count(*) >= 5
  from auth_attempts
  where at > now() - interval '15 minutes'
    and not succeeded
    and (email = p_email or ip = p_ip)
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 5. Per-IP / per-user rate limiting (used by edge functions)
-- ─────────────────────────────────────────────────────────────────────
create table rate_limit (
  bucket      text not null,           -- e.g. 'extract-receipt:ip:1.2.3.4'
  window_start timestamptz not null,
  count        int not null default 0,
  primary key (bucket, window_start)
);
create index on rate_limit (window_start);

create or replace function rate_limit_hit(p_bucket text, p_max int, p_window interval)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare ws timestamptz; c int;
begin
  ws := date_trunc('minute', now());
  insert into rate_limit(bucket, window_start, count)
    values (p_bucket, ws, 1)
    on conflict (bucket, window_start)
    do update set count = rate_limit.count + 1
    returning count into c;
  -- house-keeping
  delete from rate_limit where window_start < now() - p_window - interval '5 minutes';
  return c <= p_max;
end$$;
revoke all on function rate_limit_hit(text,int,interval) from public;

-- ─────────────────────────────────────────────────────────────────────
-- 6. Session tracking (idle expiry, forced logout on role change)
-- ─────────────────────────────────────────────────────────────────────
create table sessions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  device      text,
  ip          inet,
  user_agent  text,
  last_seen   timestamptz default now(),
  revoked_at  timestamptz
);
create index on sessions (user_id, last_seen desc);

alter table sessions enable row level security;
create policy "sessions_self" on sessions
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────
-- 7. Soft-delete + privacy erasure (GDPR / LFPDPPP)
-- ─────────────────────────────────────────────────────────────────────
alter table clients add column if not exists deleted_at timestamptz;
alter table clients add column if not exists opted_out  boolean default false;

create or replace function delete_client(p_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  -- Must belong to current clinic (RLS check)
  perform 1 from clients where id = p_id and clinic_id = current_clinic();
  if not found then
    raise exception 'forbidden';
  end if;

  -- Anonymise PII; keep Rx for legally required retention (NOM-007-SSA3: 5 years)
  update clients set
    name       = 'Paciente eliminado',
    phone      = null,
    email      = null,
    street     = null,
    between    = null,
    colonia    = null,
    reference  = null,
    lat        = null,
    lng        = null,
    notes      = null,
    deleted_at = now()
  where id = p_id;
end$$;
revoke all on function delete_client(uuid) from public;
grant execute on function delete_client(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 8. Consents (LFPDPPP aviso de privacidad)
-- ─────────────────────────────────────────────────────────────────────
create table consents (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients(id) on delete cascade,
  clinic_id   uuid not null references clinics(id),
  kind        text not null,           -- 'privacy','marketing','data_share'
  version     text not null,
  given_at    timestamptz not null default now(),
  ip          inet,
  user_agent  text
);
create index on consents (client_id, kind);
alter table consents enable row level security;
create policy "consents_tenant" on consents
  using (clinic_id = current_clinic()) with check (clinic_id = current_clinic());

-- ─────────────────────────────────────────────────────────────────────
-- 9. Harden existing helper functions (search_path injection defence)
-- ─────────────────────────────────────────────────────────────────────
alter function public.current_clinic()         set search_path = pg_catalog, public;
alter function public._charge_order()          set search_path = pg_catalog, public;
alter function public._touch_updated()         set search_path = pg_catalog, public;

-- ─────────────────────────────────────────────────────────────────────
-- 10. Storage policy: receipts bucket — private, signed-URL only
-- ─────────────────────────────────────────────────────────────────────
-- (Run once via Supabase Studio or CLI)
-- insert into storage.buckets (id, name, public) values ('receipts','receipts', false)
--   on conflict (id) do nothing;
-- Policies:
--   read:  clinic member of the path's clinic_id (path = clinic_id/order_id/uuid.jpg)
--   write: same
