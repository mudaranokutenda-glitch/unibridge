-- The CRON_SECRET, stored ONCE inside the database (Supabase Vault, encrypted).
-- The new nightly jobs and the new database triggers read it from here, so
-- you never have to paste it into any other file.
--
-- HOW TO RUN
--   1. Open this file in the Supabase SQL Editor (NOT in VS Code).
--   2. In the editor, replace PASTE_YOUR_SECRET with your CRON_SECRET value
--      (the same value as `supabase secrets list` shows for CRON_SECRET).
--   3. Run it. Do NOT save the real value in this file.
-- Safe to run twice (the second run just updates the value).

create extension if not exists supabase_vault with schema vault;

do $$
declare
  v_secret text := 'PASTE_YOUR_SECRET';
  v_id uuid;
begin
  if v_secret = 'PASTE_YOUR_' || 'SECRET' or length(v_secret) < 8 then
    raise exception 'Replace PASTE_YOUR_SECRET with your real CRON_SECRET in the SQL Editor first';
  end if;

  select id into v_id from vault.secrets where name = 'cron_secret';
  if v_id is null then
    perform vault.create_secret(v_secret, 'cron_secret', 'CRON_SECRET used to call Edge Functions');
  else
    perform vault.update_secret(v_id, v_secret);
  end if;
end $$;

-- Helper used by the jobs and triggers. Only the database itself (postgres)
-- can call it; app users cannot.
create or replace function public.cron_secret()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret' limit 1;
$$;

revoke execute on function public.cron_secret() from public, anon, authenticated;

-- Calls an Edge Function in the background with the secret header.
-- Only the database itself can call it.
create extension if not exists pg_net;

create or replace function public.call_edge_function(p_name text, p_body jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://lhdkzcsaqlhswyytirxb.supabase.co/functions/v1/' || p_name,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', coalesce(public.cron_secret(), '')
    ),
    body := coalesce(p_body, '{}'::jsonb)
  );
exception when others then
  -- Never block the app's action because a push could not be sent.
  raise warning 'Edge Function % not called: %', p_name, sqlerrm;
end;
$$;

revoke execute on function public.call_edge_function(text, jsonb) from public, anon, authenticated;
