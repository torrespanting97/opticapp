-- ════════════════════════════════════════════════════════════════════
-- 0003_bootstrap.sql — extensions, Vault keys, storage buckets, cron
-- ════════════════════════════════════════════════════════════════════
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

-- Vault key for PII encryption (idempotent)
do $$
declare have_key int;
begin
  select count(*) into have_key from vault.secrets where name = 'pii_encryption_key';
  if have_key = 0 then
    perform vault.create_secret(
      encode(gen_random_bytes(32), 'base64'),
      'pii_encryption_key',
      'AES key for PII column encryption'
    );
  end if;
end$$;

-- Placeholder for the service-role JWT used by cron HTTP callouts.
-- Overwrite later with:
--   select vault.update_secret(
--     (select id from vault.secrets where name = 'cron_service_token'),
--     '<SERVICE_ROLE_JWT>');
do $$
declare have_tok int;
begin
  select count(*) into have_tok from vault.secrets where name = 'cron_service_token';
  if have_tok = 0 then
    perform vault.create_secret('REPLACE_ME', 'cron_service_token',
      'service_role JWT for cron HTTP callouts');
  end if;
end$$;

-- Storage buckets
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('receipts',      'receipts',      false, 10485760,
     array['image/jpeg','image/png','image/webp','image/heic']),
  ('clinic-assets', 'clinic-assets', true,   2097152,
     array['image/jpeg','image/png','image/svg+xml','image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Storage RLS — receipts path: <clinic_id>/<order_id>/<uuid>.<ext>
drop policy if exists "receipts_read_clinic"   on storage.objects;
drop policy if exists "receipts_write_clinic"  on storage.objects;
drop policy if exists "receipts_update_clinic" on storage.objects;
drop policy if exists "receipts_delete_clinic" on storage.objects;

create policy "receipts_read_clinic"   on storage.objects for select
  using (bucket_id = 'receipts' and (storage.foldername(name))[1]::uuid = current_clinic());
create policy "receipts_write_clinic"  on storage.objects for insert
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1]::uuid = current_clinic());
create policy "receipts_update_clinic" on storage.objects for update
  using (bucket_id = 'receipts' and (storage.foldername(name))[1]::uuid = current_clinic());
create policy "receipts_delete_clinic" on storage.objects for delete
  using (bucket_id = 'receipts' and (storage.foldername(name))[1]::uuid = current_clinic());

-- clinic-assets: public via direct URL only (no listing), writes by owner role
drop policy if exists "clinic_assets_write_owner" on storage.objects;
create policy "clinic_assets_write_owner" on storage.objects for insert
  with check (
    bucket_id = 'clinic-assets'
    and (storage.foldername(name))[1]::uuid = current_clinic()
    and exists (
      select 1 from memberships
       where clinic_id = current_clinic() and user_id = auth.uid() and role = 'owner'
    )
  );

-- pg_cron schedules (idempotent)
do $$ begin perform cron.unschedule('stats-daily-refresh'); exception when others then null; end $$;
select cron.schedule('stats-daily-refresh', '15 3 * * *',
  $$ refresh materialized view concurrently public.stats_daily; $$);

do $$ begin perform cron.unschedule('calendar-sync-10min'); exception when others then null; end $$;
select cron.schedule('calendar-sync-10min', '*/10 * * * *', $$
  select net.http_post(
    url := current_setting('app.functions_url', true) || '/calendar-sync',
    headers := jsonb_build_object(
      'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'cron_service_token' limit 1),
      'content-type',  'application/json'),
    body := '{}'::jsonb, timeout_milliseconds := 30000);
$$);

do $$ begin perform cron.unschedule('audit-log-roll'); exception when others then null; end $$;
select cron.schedule('audit-log-roll', '0 0 25 * *', $cron$
  do $body$
  declare
    next_start date := date_trunc('month', now() + interval '1 month')::date;
    next_end   date := (next_start + interval '1 month')::date;
    part_name  text := format('audit_log_%s', to_char(next_start, 'YYYY_MM'));
  begin
    if not exists (select 1 from pg_class where relname = part_name) then
      execute format(
        'create table %I partition of audit_log for values from (%L) to (%L); alter table %I enable row level security;',
        part_name, next_start, next_end, part_name);
    end if;
  end$body$;
$cron$);

do $$ begin perform cron.unschedule('rate-limit-gc'); exception when others then null; end $$;
select cron.schedule('rate-limit-gc', '*/30 * * * *',
  $$ delete from rate_limit where window_start < now() - interval '1 day'; $$);

do $$ begin perform cron.unschedule('client-purge'); exception when others then null; end $$;
select cron.schedule('client-purge', '30 4 * * *',
  $$ delete from clients where deleted_at is not null and deleted_at < now() - interval '30 days'; $$);

comment on schema public is 'Salud Visual SaaS — production schema';
