-- Schedule send-booking-reminder Edge Function every 5 minutes via pg_cron + pg_net.
-- Prerequisite: service_role_key must exist in vault.secrets before this migration runs.
-- See ops runbook: store via `select vault.create_secret('<key>', 'service_role_key')` in Dashboard.

select cron.schedule(
  'send-booking-reminder',
  '*/5 * * * *',
  $$
  select net.http_post(
    url     := 'https://zgjtjbwrnfkfjrwfefby.supabase.co/functions/v1/send-booking-reminder',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret
        from   vault.decrypted_secrets
        where  name = 'service_role_key'
        limit  1
      )
    ),
    body    := '{}'::jsonb
  );
  $$
);
