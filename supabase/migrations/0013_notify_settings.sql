-- ════════════════════════════════════════════════════════════════════
-- 0013_notify_settings.sql
-- Stores notify-service config in Supabase Vault (same pattern as
-- cron_service_token in 0003_bootstrap.sql) and updates the trigger
-- function to read from vault.decrypted_secrets.
-- ════════════════════════════════════════════════════════════════════

-- ── Vault entries (idempotent) ─────────────────────────────────────
do $$
declare have int;
begin
  select count(*) into have from vault.secrets where name = 'notify_webhook_secret';
  if have = 0 then
    perform vault.create_secret(
      's2GnfRvYvEvlSAxX0xWeCpl9izTXkhCUWEoYGOootFk',
      'notify_webhook_secret',
      'Shared secret for Python notify service webhook endpoint'
    );
  end if;
end$$;

do $$
declare have int;
begin
  select count(*) into have from vault.secrets where name = 'notify_service_url';
  if have = 0 then
    -- Overwrite REPLACE_ME with your Railway URL after deploy:
    --   select vault.update_secret(
    --     (select id from vault.secrets where name = 'notify_service_url'),
    --     'https://your-service.railway.app');
    perform vault.create_secret(
      'REPLACE_ME',
      'notify_service_url',
      'URL of the Python notify service (Railway / Fly.io / VPS)'
    );
  end if;
end$$;

-- ── Update trigger function to read from Vault ────────────────────
create or replace function _notify_appointment_status()
returns trigger language plpgsql as $$
declare
  service_url text;
  secret      text;
begin
  if old.status is not distinct from new.status then
    return new;
  end if;

  if new.status not in ('confirmed', 'cancelled', 'no_show') then
    return new;
  end if;

  select decrypted_secret into service_url
    from vault.decrypted_secrets where name = 'notify_service_url' limit 1;
  select decrypted_secret into secret
    from vault.decrypted_secrets where name = 'notify_webhook_secret' limit 1;

  -- Skip if not configured yet
  if service_url is null or service_url = '' or service_url = 'REPLACE_ME' then
    return new;
  end if;

  perform net.http_post(
    url     := service_url || '/webhook/appointment-status',
    headers := jsonb_build_object(
      'content-type',    'application/json',
      'x-webhook-secret', coalesce(secret, '')
    ),
    body    := jsonb_build_object(
      'appointment_id', new.id,
      'new_status',     new.status,
      'old_status',     old.status,
      'clinic_id',      new.clinic_id,
      'client_id',      new.client_id
    ),
    timeout_milliseconds := 10000
  );

  return new;
end$$;

-- ── Update appointment-remind cron to use Vault URL ───────────────
do $$ begin perform cron.unschedule('appointment-remind'); exception when others then null; end $$;
select cron.schedule('appointment-remind', '*/30 * * * *', $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets
                 where name = 'notify_service_url' limit 1) || '/remind',
    headers := jsonb_build_object(
      'content-type',    'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets
                            where name = 'notify_webhook_secret' limit 1)
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 25000
  )
  where (select decrypted_secret from vault.decrypted_secrets
          where name = 'notify_service_url' limit 1)
        not in ('REPLACE_ME', '', null);
$$);
