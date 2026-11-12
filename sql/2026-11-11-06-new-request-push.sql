-- Stage 4, item 17. "New request" push to everyone except the creator.
-- Run AFTER 2026-11-11-03 (secret). Safe to run twice. Deletes nothing.
-- Needs the Edge Function new-request-push (deploy it first).
--
-- How it works: when a request is posted, the database calls the Edge
-- Function new-request-push ONCE. The function sends the push in batches to
-- every phone, except the creator, people who switched it off, and people
-- blocked with the creator. No inbox row is created per user.
--
-- notification_settings (one row per user, only when they change a switch)
--   the user themself : read, add, change their own row
--   everyone else     : nothing
--   No row = notifications ON (the default).

begin;

create table if not exists public.notification_settings (
  user_id      uuid primary key default auth.uid()
               references auth.users(id) on delete cascade,
  new_requests boolean not null default true,
  updated_at   timestamptz not null default now()
);

alter table public.notification_settings enable row level security;
revoke all on public.notification_settings from anon;
revoke delete on public.notification_settings from authenticated;

drop policy if exists "notification settings: own" on public.notification_settings;
create policy "notification settings: own"
on public.notification_settings for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "notification settings: insert own" on public.notification_settings;
create policy "notification settings: insert own"
on public.notification_settings for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "notification settings: update own" on public.notification_settings;
create policy "notification settings: update own"
on public.notification_settings for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop trigger if exists notification_settings_touch on public.notification_settings;
create trigger notification_settings_touch
before update on public.notification_settings
for each row execute function public.touch_updated_at();

-- When a new OPEN request is posted, call the Edge Function once.
-- Only the request id is sent; the function reads the rest itself.
create or replace function public.push_new_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status::text = 'OPEN' then
    -- A failed push must never stop a request from being posted.
    begin
      perform public.call_edge_function(
        'new-request-push',
        jsonb_build_object('request_id', new.id)
      );
    exception when others then
      raise warning 'New-request push not sent: %', sqlerrm;
    end;
  end if;
  return new;
end;
$$;

revoke execute on function public.push_new_request() from public, anon, authenticated;

drop trigger if exists push_new_request on public.transaction_requests;
create trigger push_new_request
after insert on public.transaction_requests
for each row execute function public.push_new_request();

commit;
