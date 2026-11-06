-- C3. Every night, delete passport scans of requests ISSUED more than
-- 30 days ago (the purge-passports Edge Function does the deleting with
-- the Storage API). Run AFTER file 05 and AFTER deploying purge-passports.
--
-- Before running: replace PASTE_YOUR_SECRET with your CRON_SECRET value
-- (the same one your other scheduled jobs use). Do not save the real value
-- in this file.
--
-- To change 30 days later: set the Edge Function secret PASSPORT_KEEP_DAYS.

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule('purge-passports')
where exists (select 1 from cron.job where jobname = 'purge-passports');

select cron.schedule(
  'purge-passports',
  '30 2 * * *',  -- every day at 02:30 (UTC)
  $$
  select net.http_post(
    url := 'https://lhdkzcsaqlhswyytirxb.supabase.co/functions/v1/purge-passports',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', 'PASTE_YOUR_SECRET'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- Check it is scheduled:
-- select jobname, schedule from cron.job where jobname = 'purge-passports';
