-- Item 6: an OPEN request that nobody matched is cancelled automatically.
-- Needs sql/2026-11-18-02-app-settings.sql (the table app_settings).
--
-- WHAT IT DOES
--   * new column transaction_requests.cancel_reason ('EXPIRED' when the job cancelled it)
--   * new setting request_expiry_hours = 48 in app_settings (the owner changes it in SQL:
--       update public.app_settings set value = 24, updated_at = now() where key = 'request_expiry_hours';)
--   * function expire_open_requests(): every request still OPEN that is older than that many
--     hours becomes CANCELLED with cancel_reason = 'EXPIRED', and its pending match suggestions
--     are closed (the existing trigger close_suggestions_when_not_open does it too;
--     the function closes them again to be sure). Returns how many requests it cancelled.
--   * a pg_cron job "expire-open-requests" every 15 minutes
--   * nobody in the app can set cancel_reason: a trigger ignores any value sent by a signed-in
--     user (only the database job and the owner can set it)
--
-- WHO CAN DO WHAT
--   expire_open_requests() : the owner and the cron job only (no rights for anon or authenticated)
--   cancel_reason          : readable like the rest of the request; written only by the job
-- Deletes nothing. Matched, completed and disputed requests are never touched.
--
-- Run in the Supabase SQL Editor. Safe to run twice.
-- Undo: select cron.unschedule('expire-open-requests');
--       drop function public.expire_open_requests();
--       drop trigger guard_cancel_reason on public.transaction_requests;

do $$
begin
  if to_regclass('public.app_settings') is null then
    raise exception 'SETUP PROBLEM: run sql/2026-11-18-02-app-settings.sql first (app_settings does not exist).';
  end if;
end $$;

begin;

alter table public.transaction_requests
  add column if not exists cancel_reason text;

alter table public.transaction_requests
  drop constraint if exists transaction_requests_cancel_reason_check;
alter table public.transaction_requests
  add constraint transaction_requests_cancel_reason_check
  check (cancel_reason is null or cancel_reason in ('EXPIRED'));

insert into public.app_settings (key, value)
values ('request_expiry_hours', 48)
on conflict (key) do nothing;

-- A signed-in user (the app) can never set or change cancel_reason.
create or replace function public.guard_cancel_reason()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.cancel_reason := null;
    else
      new.cancel_reason := old.cancel_reason;
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.guard_cancel_reason() from public, anon, authenticated;

drop trigger if exists guard_cancel_reason on public.transaction_requests;
create trigger guard_cancel_reason
before insert or update on public.transaction_requests
for each row execute function public.guard_cancel_reason();

create or replace function public.expire_open_requests()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  hours numeric;
  ids   uuid[];
  n     integer;
begin
  select s.value into hours from public.app_settings s where s.key = 'request_expiry_hours';
  if hours is null or hours <= 0 then
    hours := 48;
  end if;

  with expired as (
    update public.transaction_requests r
    set status = 'CANCELLED', cancel_reason = 'EXPIRED'
    where r.status::text = 'OPEN'
      and r.created_at < now() - make_interval(secs => (hours * 3600)::double precision)
    returning r.id
  )
  select coalesce(array_agg(expired.id), '{}'::uuid[]) into ids from expired;

  n := coalesce(array_length(ids, 1), 0);

  if n > 0 then
    update public.match_suggestions s
    set status = 'CLOSED', responded_at = now()
    where s.status = 'PENDING'
      and (s.request_a = any (ids) or s.request_b = any (ids));
  end if;

  return n;
end;
$$;

revoke execute on function public.expire_open_requests() from public, anon, authenticated;

commit;

-- The job: every 15 minutes.
create extension if not exists pg_cron;

select cron.unschedule('expire-open-requests')
where exists (select 1 from cron.job where jobname = 'expire-open-requests');

select cron.schedule(
  'expire-open-requests',
  '*/15 * * * *',
  $$ select public.expire_open_requests(); $$
);

-- Check: the job exists
select jobname, schedule from cron.job where jobname = 'expire-open-requests';
