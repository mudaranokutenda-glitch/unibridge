-- At most 3 OPEN requests per user at the same time.
-- Run AFTER 2026-11-11-16. Safe to run twice. Deletes nothing.
--
-- A 4th OPEN request is refused with a plain message that the app shows
-- as it is. Requests that are already open are not touched (a user who
-- has more than 3 today keeps them, but cannot post a new one).
-- MATCHED, COMPLETED, CANCELLED ... requests do not count.

begin;

create or replace function public.limit_open_requests()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  if new.status::text <> 'OPEN' then
    return new;
  end if;

  -- One insert at a time per user, so two quick taps cannot both pass.
  perform pg_advisory_xact_lock(hashtext('open_requests:' || new.creator_id::text));

  select count(*) into n
  from public.transaction_requests
  where creator_id = new.creator_id
    and status::text = 'OPEN';

  if n >= 3 then
    raise exception 'You already have 3 open requests. Cancel one before posting a new one.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.limit_open_requests() from public, anon, authenticated;

drop trigger if exists limit_open_requests on public.transaction_requests;
create trigger limit_open_requests
before insert on public.transaction_requests
for each row execute function public.limit_open_requests();

commit;
