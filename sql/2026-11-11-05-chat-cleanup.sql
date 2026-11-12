-- Stage 2, item 11. Auto-clean chats 30 days after a request ends.
-- Run AFTER 2026-11-11-03 (secret) and 04. Safe to run twice.
-- Needs the Edge Function chat-cleanup (deploy it first).
--
-- What happens every night at 03:00 UTC, for requests that are COMPLETED or
-- CANCELLED and ended more than 30 days ago:
--   * their chat photos are deleted with the Storage API (Edge Function),
--   * their messages are deleted,
--   * archived_at is set, so they disappear from all lists in the app.
-- NOT deleted: the transaction_requests row and the ratings (ratings and
-- the "completed" count depend on them). DISPUTED requests are never cleaned.
--
-- This file itself deletes nothing.

begin;

alter table public.transaction_requests
  add column if not exists archived_at timestamptz,
  add column if not exists ended_at timestamptz;

-- When did the request end? Set automatically when it becomes COMPLETED or
-- CANCELLED (and emptied if it goes to another status, e.g. DISPUTED).
create or replace function public.set_request_ended_at()
returns trigger
language plpgsql
as $$
begin
  if new.status::text in ('COMPLETED', 'CANCELLED') then
    if tg_op = 'INSERT' or old.status is distinct from new.status then
      new.ended_at := now();
    end if;
  else
    new.ended_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists set_request_ended_at on public.transaction_requests;
create trigger set_request_ended_at
before insert or update of status on public.transaction_requests
for each row execute function public.set_request_ended_at();

-- Requests that ended before this file: use their last change date.
update public.transaction_requests
set ended_at = coalesce(updated_at, created_at, now())
where status::text in ('COMPLETED', 'CANCELLED') and ended_at is null;

create index if not exists transaction_requests_cleanup
  on public.transaction_requests (ended_at)
  where archived_at is null;

commit;

-- Nightly job (reads the secret from file 03).
create extension if not exists pg_cron;

select cron.unschedule('chat-cleanup')
where exists (select 1 from cron.job where jobname = 'chat-cleanup');

select cron.schedule(
  'chat-cleanup',
  '0 3 * * *',
  $$ select public.call_edge_function('chat-cleanup', '{}'::jsonb); $$
);
