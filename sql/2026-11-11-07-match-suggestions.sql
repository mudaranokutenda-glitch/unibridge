-- Stage 4, item 18. Suggested matching.
-- Run AFTER 2026-11-11-06. Safe to run twice. Deletes nothing.
--
-- When a new OPEN request has the SAME amount and currency as another
-- user's OPEN request of the OPPOSITE type (SEND <-> RECEIVE):
--   * a suggestion is created (one at a time per request, the oldest
--     matching request first) and both people get a notification:
--     "A match is available. Accept or decline."
--   * the match happens ONLY when BOTH accept (function
--     respond_match_suggestion, security definer). Either can decline.
--   * a declined pair of users is never suggested to each other again,
--   * a suggestion expires after 24 hours,
--   * blocked users are never suggested to each other.
-- When both accept: the OLDER request becomes MATCHED with the other person
-- (that is the chat), and the other person's own request is CANCELLED,
-- because the exchange now happens in the matched request.
-- Manual Match stays as it is.
--
-- WHO CAN DO WHAT (match_suggestions)
--   the two people of a suggestion : read it, accept or decline (function only)
--   everyone else                  : nothing
--   nobody can insert, change or delete rows directly.

-- New notification types (outside the transaction: Postgres needs that).
do $$
declare
  t text;
begin
  select c.udt_name into t
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'notifications'
    and c.column_name = 'type' and c.data_type = 'USER-DEFINED';
  if t is not null then
    execute format('alter type public.%I add value if not exists %L', t, 'MATCH_SUGGESTION');
  end if;
end $$;

begin;

create table if not exists public.match_suggestions (
  id           uuid primary key default gen_random_uuid(),
  request_a    uuid not null references public.transaction_requests(id) on delete cascade,
  request_b    uuid not null references public.transaction_requests(id) on delete cascade,
  user_a       uuid not null references auth.users(id) on delete cascade,
  user_b       uuid not null references auth.users(id) on delete cascade,
  a_accepted   boolean not null default false,
  b_accepted   boolean not null default false,
  status       text not null default 'PENDING'
               check (status in ('PENDING', 'MATCHED', 'DECLINED', 'CLOSED')),
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '24 hours',
  responded_at timestamptz,
  unique (request_a, request_b),
  check (user_a <> user_b),
  check (request_a <> request_b)
);

create index if not exists match_suggestions_users on public.match_suggestions (user_a, user_b);

alter table public.match_suggestions enable row level security;
revoke all on public.match_suggestions from anon;
revoke insert, update, delete on public.match_suggestions from authenticated;

drop policy if exists "suggestions: own" on public.match_suggestions;
create policy "suggestions: own"
on public.match_suggestions for select
to authenticated
using (user_a = auth.uid() or user_b = auth.uid());

-- Tell one person, without stopping anything if it fails.
create or replace function public.notify_user(p_user uuid, p_type text, p_content text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- The type is written as a literal so it also works if notifications.type
  -- is an enum.
  execute format(
    'insert into public.notifications (user_id, type, content) values ($1, %L, $2)',
    p_type)
  using p_user, p_content;
exception when others then
  raise warning 'Notification not created: %', sqlerrm;
end;
$$;

revoke execute on function public.notify_user(uuid, text, text) from public, anon, authenticated;

-- After a new OPEN request: look for one opposite request to suggest.
create or replace function public.suggest_match_for_new_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
  msg text;
begin
  if new.status::text <> 'OPEN' then
    return new;
  end if;

  select r.id, r.creator_id into c
  from public.transaction_requests r
  where r.status::text = 'OPEN'
    and r.archived_at is null
    and r.id <> new.id
    and r.creator_id <> new.creator_id
    and r.amount = new.amount
    and r.currency = new.currency
    and r.type::text <> new.type::text
    -- never between blocked users
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = new.creator_id and b.blocked_id = r.creator_id)
         or (b.blocker_id = r.creator_id and b.blocked_id = new.creator_id))
    -- a declined pair is never suggested again
    and not exists (
      select 1 from public.match_suggestions s
      where s.status = 'DECLINED'
        and ((s.user_a = r.creator_id and s.user_b = new.creator_id)
          or (s.user_a = new.creator_id and s.user_b = r.creator_id)))
    -- one live suggestion at a time per request
    and not exists (
      select 1 from public.match_suggestions s
      where s.status = 'PENDING' and s.expires_at > now()
        and r.id in (s.request_a, s.request_b))
  order by r.created_at asc
  limit 1;

  if c.id is null then
    return new;
  end if;

  insert into public.match_suggestions (request_a, request_b, user_a, user_b)
  values (c.id, new.id, c.creator_id, new.creator_id)
  on conflict (request_a, request_b) do nothing;

  msg := 'A match is available for ' || trim(to_char(new.amount, 'FM999999990.##'))
         || ' ' || new.currency || '. Accept or decline in the app.';
  perform public.notify_user(c.creator_id, 'MATCH_SUGGESTION', msg);
  perform public.notify_user(new.creator_id, 'MATCH_SUGGESTION', msg);
  return new;
exception when others then
  -- Never stop someone from posting a request because of a suggestion.
  raise warning 'No suggestion made: %', sqlerrm;
  return new;
end;
$$;

revoke execute on function public.suggest_match_for_new_request() from public, anon, authenticated;

drop trigger if exists suggest_match_for_new_request on public.transaction_requests;
create trigger suggest_match_for_new_request
after insert on public.transaction_requests
for each row execute function public.suggest_match_for_new_request();

-- A request that is no longer OPEN closes its pending suggestions.
create or replace function public.close_suggestions_when_not_open()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status::text = 'OPEN' and new.status::text <> 'OPEN' then
    update public.match_suggestions
    set status = 'CLOSED', responded_at = now()
    where status = 'PENDING' and new.id in (request_a, request_b);
  end if;
  return new;
end;
$$;

revoke execute on function public.close_suggestions_when_not_open() from public, anon, authenticated;

drop trigger if exists close_suggestions_when_not_open on public.transaction_requests;
create trigger close_suggestions_when_not_open
after update of status on public.transaction_requests
for each row execute function public.close_suggestions_when_not_open();

-- My live suggestions (for the home screen).
create or replace function public.my_match_suggestions()
returns table (
  id uuid,
  my_request_id uuid,
  other_user_id uuid,
  amount numeric,
  currency text,
  my_type text,
  i_accepted boolean,
  other_accepted boolean,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select s.id,
         case when s.user_a = auth.uid() then s.request_a else s.request_b end,
         case when s.user_a = auth.uid() then s.user_b else s.user_a end,
         ra.amount::numeric,
         ra.currency::text,
         (case when s.user_a = auth.uid() then ra.type else rb.type end)::text,
         case when s.user_a = auth.uid() then s.a_accepted else s.b_accepted end,
         case when s.user_a = auth.uid() then s.b_accepted else s.a_accepted end,
         s.expires_at
  from public.match_suggestions s
  join public.transaction_requests ra on ra.id = s.request_a
  join public.transaction_requests rb on rb.id = s.request_b
  where (s.user_a = auth.uid() or s.user_b = auth.uid())
    and s.status = 'PENDING'
    and s.expires_at > now()
    and ra.status::text = 'OPEN' and rb.status::text = 'OPEN'
  order by s.created_at desc;
$$;

revoke execute on function public.my_match_suggestions() from public, anon;
grant execute on function public.my_match_suggestions() to authenticated;

-- Accept or decline. Returns the id of the matched request when the match
-- happened (both accepted), otherwise null.
create or replace function public.respond_match_suggestion(p_id uuid, p_accept boolean)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.match_suggestions;
  ra public.transaction_requests;
  rb public.transaction_requests;
  other uuid;
begin
  select * into s from public.match_suggestions where id = p_id for update;
  if not found or auth.uid() is null or auth.uid() not in (s.user_a, s.user_b) then
    raise exception 'Suggestion not found';
  end if;
  if s.status <> 'PENDING' then
    raise exception 'This suggestion is closed';
  end if;
  if s.expires_at <= now() then
    update public.match_suggestions set status = 'CLOSED', responded_at = now() where id = p_id;
    raise exception 'This suggestion has expired';
  end if;
  other := case when auth.uid() = s.user_a then s.user_b else s.user_a end;

  if not p_accept then
    update public.match_suggestions
    set status = 'DECLINED', responded_at = now()
    where id = p_id;
    perform public.notify_user(other, 'MATCH_SUGGESTION',
      'The suggested match was declined. Your request stays open.');
    return null;
  end if;

  if auth.uid() = s.user_a then
    update public.match_suggestions set a_accepted = true where id = p_id
    returning * into s;
  else
    update public.match_suggestions set b_accepted = true where id = p_id
    returning * into s;
  end if;

  if not (s.a_accepted and s.b_accepted) then
    perform public.notify_user(other, 'MATCH_SUGGESTION',
      'The other student accepted the suggested match. Accept it too to start the chat.');
    return null;
  end if;

  -- Both accepted: check that everything is still valid, then match.
  select * into ra from public.transaction_requests where id = s.request_a for update;
  select * into rb from public.transaction_requests where id = s.request_b for update;
  if ra.status::text <> 'OPEN' or rb.status::text <> 'OPEN'
     or ra.archived_at is not null or rb.archived_at is not null then
    update public.match_suggestions set status = 'CLOSED', responded_at = now() where id = p_id;
    raise exception 'One of the requests is no longer open';
  end if;
  if exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = s.user_a and b.blocked_id = s.user_b)
       or (b.blocker_id = s.user_b and b.blocked_id = s.user_a)) then
    update public.match_suggestions set status = 'CLOSED', responded_at = now() where id = p_id;
    raise exception 'You cannot match with this user.';
  end if;

  update public.match_suggestions
  set status = 'MATCHED', responded_at = now()
  where id = p_id;

  update public.transaction_requests
  set status = 'MATCHED', matched_with_id = s.user_b
  where id = s.request_a;

  update public.transaction_requests
  set status = 'CANCELLED'
  where id = s.request_b;

  perform public.notify_user(s.user_a, 'MATCH_FOUND', 'Your suggested match is confirmed. Open the chat.');
  perform public.notify_user(s.user_b, 'MATCH_FOUND', 'Your suggested match is confirmed. Open the chat.');
  return s.request_a;
end;
$$;

revoke execute on function public.respond_match_suggestion(uuid, boolean) from public, anon;
grant execute on function public.respond_match_suggestion(uuid, boolean) to authenticated;

-- Live updates on the home screen (the security rules above still apply).
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public'
                   and tablename = 'match_suggestions') then
    execute 'alter publication supabase_realtime add table public.match_suggestions';
  end if;
end $$;

commit;
