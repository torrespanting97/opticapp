-- ════════════════════════════════════════════════════════════════════
-- 0006_notify_service.sql
-- Wires Supabase → Python notify service via pg_net.
--
-- After applying this migration, run in the SQL editor:
--   alter database postgres
--     set "app.notify_service_url"    = 'https://your-service.railway.app';
--   alter database postgres
--     set "app.notify_webhook_secret" = 'your-webhook-secret';
-- ════════════════════════════════════════════════════════════════════

-- ── Trigger: fire notify service on appointment status change ──────
create or replace function _notify_appointment_status()
returns trigger language plpgsql as $$
declare
  service_url text;
  secret      text;
begin
  -- Skip if status didn't actually change
  if old.status is not distinct from new.status then
    return new;
  end if;

  -- Only notify on actionable transitions
  if new.status not in ('confirmed', 'cancelled', 'no_show') then
    return new;
  end if;

  service_url := current_setting('app.notify_service_url', true);
  secret      := current_setting('app.notify_webhook_secret', true);

  -- If not configured yet, skip silently
  if service_url is null or service_url = '' then
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

-- Drop old trigger if it exists, then create fresh
drop trigger if exists trg_appointments_notify on appointments;
create trigger trg_appointments_notify
  after update of status on appointments
  for each row execute function _notify_appointment_status();

-- ── Update cron: remind via Python service instead of Edge Function ─
-- Cancels the old appointment-remind cron (Edge Function) and replaces
-- it with one that calls the Python service's /remind endpoint.

do $$ begin perform cron.unschedule('appointment-remind'); exception when others then null; end $$;
select cron.schedule('appointment-remind', '*/30 * * * *', $$
  select net.http_post(
    url     := current_setting('app.notify_service_url', true) || '/remind',
    headers := jsonb_build_object(
      'content-type',    'application/json',
      'x-webhook-secret', current_setting('app.notify_webhook_secret', true)
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 25000
  );
$$);
