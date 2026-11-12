-- Stage 1, items 2-4. Phone number (asked on the "Set up your profile" page).
-- Run AFTER 2026-11-11-01. Safe to run twice. Deletes nothing.
--
-- Format (app AND database): +263 or +213, then 8 to 10 digits.
--   ^\+(263|213)[0-9]{8,10}$      e.g. +213555123456, +263771234567
--
-- WHO CAN READ A PHONE NUMBER (table user_phones)
--   the student themself                 : yes (read, add, change)
--   attache / admin                      : yes (read only)
--   the Governor (role rep) of the
--   student's wilaya                     : yes (read only)
--   any other student / other Governor   : NO
-- The phone is never in get_public_profiles, notifications, logs or chat.
--
-- The student's wilaya = the wilaya of their student record, or, if they
-- have no record yet, the wilaya of their profile.

begin;

create or replace function public.is_valid_phone(p text)
returns boolean
language sql
immutable
as $$
  select coalesce(p ~ '^\+(263|213)[0-9]{8,10}$', false);
$$;

grant execute on function public.is_valid_phone(text) to authenticated;

-- The wilaya used by the security rules for a student.
-- security definer: reads one wilaya only. Wilayas are already public on
-- profile cards, so this reveals nothing private.
create or replace function public.student_wilaya(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select r.wilaya from public.student_records r where r.user_id = p_user),
    (select p.wilaya from public.profiles p where p.id = p_user)
  );
$$;

revoke execute on function public.student_wilaya(uuid) from public, anon;
grant execute on function public.student_wilaya(uuid) to authenticated;

create table if not exists public.user_phones (
  user_id    uuid primary key default auth.uid()
             references auth.users(id) on delete cascade,
  phone      text not null,
  updated_at timestamptz not null default now()
);

alter table public.user_phones
  drop constraint if exists user_phones_phone_format,
  add constraint user_phones_phone_format check (public.is_valid_phone(phone));

alter table public.user_phones enable row level security;
revoke all on public.user_phones from anon;
revoke delete on public.user_phones from authenticated;

drop policy if exists "phones: select" on public.user_phones;
create policy "phones: select"
on public.user_phones for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_staff()
  or public.is_rep_for(public.student_wilaya(user_id))
);

drop policy if exists "phones: insert own" on public.user_phones;
create policy "phones: insert own"
on public.user_phones for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "phones: update own" on public.user_phones;
create policy "phones: update own"
on public.user_phones for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop trigger if exists user_phones_touch on public.user_phones;
create trigger user_phones_touch
before update on public.user_phones
for each row execute function public.touch_updated_at();

-- The phone in the student record follows the same format from now on.
-- NOT VALID: old rows are not checked (nothing is changed or deleted),
-- only new and edited rows must match.
alter table public.student_records
  drop constraint if exists student_records_phone_format;
alter table public.student_records
  add constraint student_records_phone_format
  check (public.is_valid_phone(phone)) not valid;

commit;
