-- Stage 5, item 21. Staff contacts (Educational Attaché and Governors).
-- Run AFTER 2026-11-11-08. Safe to run twice. Deletes nothing.
--
-- WHO CAN DO WHAT (staff_contacts)
--   every signed-in user : read (these are the official staff contacts that
--                          students are meant to call)
--   attache / admin      : add, change, delete
--   everyone else        : cannot change anything
-- These are staff phone numbers given on purpose, not student phones.

begin;

create table if not exists public.staff_contacts (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null check (kind in ('attache', 'governor')),
  name       text not null check (char_length(name) between 1 and 120),
  wilaya     text,
  phone      text,
  email      text,
  sort_order int  not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A Governor contact belongs to exactly one wilaya; the attaché to none.
  check ((kind = 'governor' and wilaya is not null and public.is_valid_wilaya(wilaya))
      or (kind = 'attache' and wilaya is null)),
  check (phone is null or public.is_valid_phone(phone)),
  check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  check (phone is not null or email is not null)
);

create index if not exists staff_contacts_kind on public.staff_contacts (kind, wilaya, sort_order);

alter table public.staff_contacts enable row level security;
revoke all on public.staff_contacts from anon;

drop policy if exists "contacts: read" on public.staff_contacts;
create policy "contacts: read"
on public.staff_contacts for select
to authenticated
using (true);

drop policy if exists "contacts: staff insert" on public.staff_contacts;
create policy "contacts: staff insert"
on public.staff_contacts for insert
to authenticated
with check (public.is_staff());

drop policy if exists "contacts: staff update" on public.staff_contacts;
create policy "contacts: staff update"
on public.staff_contacts for update
to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "contacts: staff delete" on public.staff_contacts;
create policy "contacts: staff delete"
on public.staff_contacts for delete
to authenticated
using (public.is_staff());

drop trigger if exists staff_contacts_touch on public.staff_contacts;
create trigger staff_contacts_touch
before update on public.staff_contacts
for each row execute function public.touch_updated_at();

commit;
