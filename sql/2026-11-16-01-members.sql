-- Student space membership approval.
-- Run AFTER 2026-11-11-17 (it uses notify_user() from file 07, is_staff() / is_rep_for() /
-- is_valid_wilaya() from the 2026-11-05 files, and the tables of files 08 to 11).
-- Safe to run twice. Deletes nothing.
--
-- WHAT IT DOES
--   Anyone who signs up can still use requests, chat, marketplace, rates and notifications,
--   and sees emergency alerts. The Student space (contacts, guide, help, appointments,
--   student record, results, bank account, passport number, attestation requests) opens
--   only for APPROVED members.
--   A Governor approves people of their own wilaya. The attache and the admin approve anyone.
--   Every account that exists when this file is run becomes APPROVED (backfill at the end).
--   Staff accounts (attache, admin, Governor) are always members.
--
-- WHO CAN DO WHAT (space_members)
--   the user themself : read their own row
--   attache / admin   : read all rows
--   a Governor        : read the rows of their own wilaya
--   nobody            : insert, update or delete directly from the app.
--   Rows change only through the functions request_membership() and decide_membership().
--
-- NOT CHANGED: the existing rules. The new rules below are RESTRICTIVE: they are added ON TOP
-- of the existing ones (both must allow it). alerts stay readable by every signed-in user.

-- ---------------------------------------------------------------
-- 0. New notification type (outside the transaction: Postgres needs that).
-- ---------------------------------------------------------------
do $$
declare
  t text;
begin
  select c.udt_name into t
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'notifications'
    and c.column_name = 'type' and c.data_type = 'USER-DEFINED';
  if t is not null then
    execute format('alter type public.%I add value if not exists %L', t, 'MEMBERSHIP_UPDATE');
  end if;
end $$;

begin;

-- ---------------------------------------------------------------
-- 1. The table
-- ---------------------------------------------------------------
create table if not exists public.space_members (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  status       text not null default 'PENDING'
               check (status in ('PENDING', 'APPROVED', 'REJECTED')),
  -- the wilaya of the profile when the request was made (the Governor of this wilaya decides)
  wilaya       text check (wilaya is null or public.is_valid_wilaya(wilaya)),
  requested_at timestamptz not null default now(),
  decided_by   uuid references auth.users(id) on delete set null,
  decided_at   timestamptz
);

create index if not exists space_members_pending
  on public.space_members (status, wilaya, requested_at);

alter table public.space_members enable row level security;
revoke all on public.space_members from anon;
revoke insert, update, delete on public.space_members from authenticated;
grant select on public.space_members to authenticated;

drop policy if exists "members: select own" on public.space_members;
create policy "members: select own"
on public.space_members for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "members: select staff" on public.space_members;
create policy "members: select staff"
on public.space_members for select
to authenticated
using (public.is_staff());

drop policy if exists "members: select governor" on public.space_members;
create policy "members: select governor"
on public.space_members for select
to authenticated
using (wilaya is not null and public.is_rep_for(wilaya));

-- ---------------------------------------------------------------
-- 2. is_member(): approved, or staff (attache, admin, Governor)
-- ---------------------------------------------------------------
create or replace function public.is_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
           select 1 from public.profiles p
           where p.id = auth.uid() and p.role in ('attache', 'admin', 'rep'))
      or exists (
           select 1 from public.space_members m
           where m.user_id = auth.uid() and m.status = 'APPROVED');
$$;

revoke execute on function public.is_member() from public, anon;
grant execute on function public.is_member() to authenticated;

-- ---------------------------------------------------------------
-- 3. request_membership(): ask to join. Returns the status afterwards.
--    Staff are always members. Someone who was REJECTED can ask again after 24 hours.
-- ---------------------------------------------------------------
create or replace function public.request_membership()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  w text;
  m public.space_members;
  n int;
  g uuid;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;
  if public.is_member() and not exists (select 1 from public.space_members where user_id = me) then
    return 'APPROVED'; -- staff
  end if;

  select p.wilaya into w from public.profiles p where p.id = me;
  if w is null or not public.is_valid_wilaya(w) then
    raise exception 'Choose your wilaya in your profile first.';
  end if;

  insert into public.space_members (user_id, status, wilaya)
  values (me, 'PENDING', w)
  on conflict (user_id) do nothing;
  get diagnostics n = row_count;

  if n = 0 then
    select * into m from public.space_members where user_id = me for update;
    if m.status in ('APPROVED', 'PENDING') then
      return m.status; -- nothing to do (one pending request at most)
    end if;
    if m.decided_at is not null and m.decided_at > now() - interval '24 hours' then
      raise exception 'You can ask again 24 hours after the last answer.';
    end if;
    update public.space_members
    set status = 'PENDING', wilaya = w, requested_at = now(), decided_by = null, decided_at = null
    where user_id = me;
  end if;

  -- Tell the Governors of this wilaya and the attache. The text has no personal data.
  for g in
    select p.id from public.profiles p
    where (p.role = 'rep' and p.rep_wilaya = w) or p.role = 'attache'
  loop
    perform public.notify_user(g, 'MEMBERSHIP_UPDATE',
      'A student asked to join the student space. Open Join requests.');
  end loop;
  return 'PENDING';
end;
$$;

revoke execute on function public.request_membership() from public, anon;
grant execute on function public.request_membership() to authenticated;

-- ---------------------------------------------------------------
-- 4. decide_membership(user, approve): attache and admin for anyone,
--    a Governor only for requests of their own wilaya. PENDING requests only.
-- ---------------------------------------------------------------
create or replace function public.decide_membership(p_user uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  m public.space_members;
begin
  -- Nobody decides about themselves. The same message for "not found" and "not yours".
  if me is null or p_user is null or p_user = me then
    raise exception 'Not allowed';
  end if;
  select * into m from public.space_members where user_id = p_user for update;
  if not found or not (public.is_staff() or (m.wilaya is not null and public.is_rep_for(m.wilaya))) then
    raise exception 'Not allowed';
  end if;
  if m.status <> 'PENDING' then
    raise exception 'This request was already answered.';
  end if;

  update public.space_members
  set status = case when p_approve then 'APPROVED' else 'REJECTED' end,
      decided_by = me,
      decided_at = now()
  where user_id = p_user;

  perform public.notify_user(p_user, 'MEMBERSHIP_UPDATE',
    case when p_approve
      then 'Your request to join the student space was approved.'
      else 'Your request to join the student space was not approved.'
    end);
end;
$$;

revoke execute on function public.decide_membership(uuid, boolean) from public, anon;
grant execute on function public.decide_membership(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------
-- 5. pending_members(): the waiting requests I may decide. No phone, no email.
-- ---------------------------------------------------------------
create or replace function public.pending_members()
returns table (
  user_id uuid,
  full_name text,
  profile_picture_url text,
  wilaya text,
  requested_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (public.is_staff() or exists (
            select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'rep' and p.rep_wilaya is not null)) then
    raise exception 'Not allowed';
  end if;

  return query
  select m.user_id, p.full_name::text, p.profile_picture_url::text, m.wilaya, m.requested_at
  from public.space_members m
  join public.profiles p on p.id = m.user_id
  where m.status = 'PENDING'
    and (public.is_staff() or (m.wilaya is not null and public.is_rep_for(m.wilaya)))
  order by m.requested_at;
end;
$$;

revoke execute on function public.pending_members() from public, anon;
grant execute on function public.pending_members() to authenticated;

-- ---------------------------------------------------------------
-- 6. RESTRICTIVE rules: the Student space opens only for members.
-- ---------------------------------------------------------------
-- Reading (the contacts, guide and help lists):
drop policy if exists "members only: read" on public.staff_contacts;
create policy "members only: read" on public.staff_contacts
as restrictive for select to authenticated using (public.is_member());

drop policy if exists "members only: read" on public.guide_sections;
create policy "members only: read" on public.guide_sections
as restrictive for select to authenticated using (public.is_member());

drop policy if exists "members only: read" on public.guide_items;
create policy "members only: read" on public.guide_items
as restrictive for select to authenticated using (public.is_member());

drop policy if exists "members only: read" on public.faqs;
create policy "members only: read" on public.faqs
as restrictive for select to authenticated using (public.is_member());

-- Adding (record, results, attestation request, appointment, bank account, passport number):
drop policy if exists "members only: insert" on public.student_records;
create policy "members only: insert" on public.student_records
as restrictive for insert to authenticated with check (public.is_member());

drop policy if exists "members only: insert" on public.academic_results;
create policy "members only: insert" on public.academic_results
as restrictive for insert to authenticated with check (public.is_member());

drop policy if exists "members only: insert" on public.attestation_requests;
create policy "members only: insert" on public.attestation_requests
as restrictive for insert to authenticated with check (public.is_member());

drop policy if exists "members only: insert" on public.appointments;
create policy "members only: insert" on public.appointments
as restrictive for insert to authenticated with check (public.is_member());

drop policy if exists "members only: insert" on public.bank_accounts;
create policy "members only: insert" on public.bank_accounts
as restrictive for insert to authenticated with check (public.is_member());

drop policy if exists "members only: insert" on public.passport_numbers;
create policy "members only: insert" on public.passport_numbers
as restrictive for insert to authenticated with check (public.is_member());

-- Files: no upload of results or passports for non-members. Every other bucket is unaffected.
drop policy if exists "members only: upload private documents" on storage.objects;
create policy "members only: upload private documents" on storage.objects
as restrictive for insert to authenticated
with check (bucket_id not in ('academic-results', 'passports') or public.is_member());

-- Guide PDFs (recommended, easy to remove): the guide files open only for members too.
-- To remove this one rule:  drop policy "members only: read guide files" on storage.objects;
drop policy if exists "members only: read guide files" on storage.objects;
create policy "members only: read guide files" on storage.objects
as restrictive for select to authenticated
using (bucket_id <> 'guide' or public.is_member());

-- ---------------------------------------------------------------
-- 7. Backfill: every account that exists now becomes APPROVED (staff included).
--    These rows have decided_by empty. New sign-ups after this file are NOT approved.
-- ---------------------------------------------------------------
insert into public.space_members (user_id, status, wilaya, requested_at, decided_at)
select p.id,
       'APPROVED',
       case when p.wilaya is not null and public.is_valid_wilaya(p.wilaya) then p.wilaya end,
       now(),
       now()
from public.profiles p
on conflict (user_id) do nothing;

commit;
