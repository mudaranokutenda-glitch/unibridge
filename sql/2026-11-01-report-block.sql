-- Report and block a user.
-- Run this once in the Supabase SQL Editor. It is safe to run again.
--
-- Step 1 of the app uses user_reports.
-- Step 2 of the app uses user_blocks, get_hidden_user_ids and chat_is_blocked.
-- The server protections (no match, no new messages between blocked people)
-- start working as soon as this file is run.

-- ---------------------------------------------------------------
-- 1. Reports
-- ---------------------------------------------------------------
create table if not exists public.user_reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  reason      text not null
              check (reason in ('SCAM', 'HARASSMENT', 'FAKE_PROFILE', 'INAPPROPRIATE', 'OTHER')),
  details     text check (char_length(details) <= 1000),
  status      text not null default 'OPEN'
              check (status in ('OPEN', 'REVIEWED', 'DISMISSED')),
  created_at  timestamptz not null default now(),
  check (reporter_id <> reported_id)
);

-- Only one OPEN report per person about the same user (stops spam).
create unique index if not exists user_reports_one_open
  on public.user_reports (reporter_id, reported_id)
  where status = 'OPEN';

alter table public.user_reports enable row level security;
revoke all on public.user_reports from anon;

-- Users may only create reports as themselves, always with status OPEN.
drop policy if exists "reports: insert own" on public.user_reports;
create policy "reports: insert own"
on public.user_reports for insert
to authenticated
with check (reporter_id = auth.uid() and status = 'OPEN');

-- Users may only see their own reports. No update / delete for anyone
-- (the owner reviews and changes status in the Table Editor).
drop policy if exists "reports: select own" on public.user_reports;
create policy "reports: select own"
on public.user_reports for select
to authenticated
using (reporter_id = auth.uid());

-- ---------------------------------------------------------------
-- 2. Blocks
-- ---------------------------------------------------------------
create table if not exists public.user_blocks (
  blocker_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.user_blocks enable row level security;
revoke all on public.user_blocks from anon;

drop policy if exists "blocks: select own" on public.user_blocks;
create policy "blocks: select own"
on public.user_blocks for select
to authenticated
using (blocker_id = auth.uid());

drop policy if exists "blocks: insert own" on public.user_blocks;
create policy "blocks: insert own"
on public.user_blocks for insert
to authenticated
with check (blocker_id = auth.uid());

drop policy if exists "blocks: delete own" on public.user_blocks;
create policy "blocks: delete own"
on public.user_blocks for delete
to authenticated
using (blocker_id = auth.uid());

-- ---------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------

-- Everyone I blocked + everyone who blocked me (blocking works both ways).
-- Returns only ids, so nobody can read the user_blocks rows of others.
create or replace function public.get_hidden_user_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select blocked_id from public.user_blocks where blocker_id = auth.uid()
  union
  select blocker_id from public.user_blocks where blocked_id = auth.uid();
$$;

-- True if the two people in this request have blocked each other
-- (either direction). Only answers for requests I am part of.
create or replace function public.chat_is_blocked(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.transaction_requests r
    join public.user_blocks b
      on (b.blocker_id = r.creator_id and b.blocked_id = r.matched_with_id)
      or (b.blocker_id = r.matched_with_id and b.blocked_id = r.creator_id)
    where r.id = p_request_id
      and auth.uid() in (r.creator_id, r.matched_with_id)
  );
$$;

revoke execute on function public.get_hidden_user_ids() from public, anon;
revoke execute on function public.chat_is_blocked(uuid) from public, anon;
grant execute on function public.get_hidden_user_ids() to authenticated;
grant execute on function public.chat_is_blocked(uuid) to authenticated;

-- ---------------------------------------------------------------
-- 4. Server protections
-- ---------------------------------------------------------------

-- No matching between blocked people (works whatever match_request does).
create or replace function public.prevent_blocked_match()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.matched_with_id is not null
     and new.matched_with_id is distinct from old.matched_with_id
     and exists (
       select 1 from public.user_blocks b
       where (b.blocker_id = new.creator_id and b.blocked_id = new.matched_with_id)
          or (b.blocker_id = new.matched_with_id and b.blocked_id = new.creator_id)
     )
  then
    raise exception 'You cannot match with this user.';
  end if;
  return new;
end;
$$;

revoke execute on function public.prevent_blocked_match() from public, anon, authenticated;

drop trigger if exists prevent_blocked_match on public.transaction_requests;
create trigger prevent_blocked_match
before update on public.transaction_requests
for each row execute function public.prevent_blocked_match();

-- No new messages in a chat between blocked people.
-- RESTRICTIVE = added on top of the existing messages rules (they stay).
drop policy if exists "messages: not between blocked users" on public.messages;
create policy "messages: not between blocked users"
on public.messages
as restrictive
for insert
to authenticated
with check (not public.chat_is_blocked(request_id));
