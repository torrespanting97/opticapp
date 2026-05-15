-- ════════════════════════════════════════════════════════════════════
-- 0005_cron_reminders.sql
-- • pg_cron: appointment-remind every 30 minutes
-- • pg_cron: oauth_states cleanup (expired rows)
-- ════════════════════════════════════════════════════════════════════

-- Appointment reminders — runs every 30 min, covers ±30 min windows
-- for 24 h and 1 h before each appointment.
do $$ begin perform cron.unschedule('appointment-remind'); exception when others then null; end $$;
select cron.schedule('appointment-remind', '*/30 * * * *', $$
  select net.http_post(
    url := current_setting('app.functions_url', true) || '/appointment-remind',
    headers := jsonb_build_object(
      'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'cron_service_token' limit 1),
      'content-type',  'application/json'),
    body := '{}'::jsonb,
    timeout_milliseconds := 25000);
$$);

-- Clean up expired OAuth handshake states every 15 minutes
do $$ begin perform cron.unschedule('oauth-states-gc'); exception when others then null; end $$;
select cron.schedule('oauth-states-gc', '*/15 * * * *',
  $$ delete from public.oauth_states where expires_at < now(); $$);
