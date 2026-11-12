-- Stage 5, items 19 and 20. Gender, bank account number, passport number.
-- Run AFTER 2026-11-11-07. Safe to run twice. Deletes nothing.
--
-- gender: new column in student_records (MALE or FEMALE). Old records may
-- keep it empty; the app asks for it on the next save.
--
-- bank_accounts (exactly 20 digits)            passport_numbers (6-12, A-Z 0-9)
--   the student : read, add, change own          the student : read, add, change own
--   attache/admin: through staff functions ONLY  attache/admin: through staff
--                  (every view is logged)                       functions ONLY (logged)
--   Governor of the student's wilaya: through    Governor   : NEVER
--                  governor functions ONLY (logged)
--   everyone else: NOTHING                        everyone else: NOTHING
--
-- Why "through functions only": every time staff or a Governor sees a bank
-- account or a passport number, a row MUST be written to access_log. A plain
-- table read cannot write a log row, so staff have no direct read access;
-- they use the functions in sql/2026-11-11-13-staff-tools.sql and
-- 2026-11-11-14-governor-tools.sql, which check the role and write the log.
-- None of this is in get_public_profiles, notifications or chat.

begin;

-- ---------------------------------------------------------------
-- 1. Gender
-- ---------------------------------------------------------------
alter table public.student_records
  add column if not exists gender text;

alter table public.student_records
  drop constraint if exists student_records_gender_check;
alter table public.student_records
  add constraint student_records_gender_check
  check (gender is null or gender in ('MALE', 'FEMALE'));

-- ---------------------------------------------------------------
-- 2. Bank account number
-- ---------------------------------------------------------------
create table if not exists public.bank_accounts (
  user_id        uuid primary key default auth.uid()
                 references auth.users(id) on delete cascade,
  account_number text not null,
  updated_at     timestamptz not null default now()
);

alter table public.bank_accounts
  drop constraint if exists bank_accounts_format,
  add constraint bank_accounts_format check (account_number ~ '^[0-9]{20}$');

alter table public.bank_accounts enable row level security;
revoke all on public.bank_accounts from anon;
revoke delete on public.bank_accounts from authenticated;

drop policy if exists "bank: select own" on public.bank_accounts;
create policy "bank: select own"
on public.bank_accounts for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "bank: insert own" on public.bank_accounts;
create policy "bank: insert own"
on public.bank_accounts for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "bank: update own" on public.bank_accounts;
create policy "bank: update own"
on public.bank_accounts for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop trigger if exists bank_accounts_touch on public.bank_accounts;
create trigger bank_accounts_touch
before update on public.bank_accounts
for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------
-- 3. Passport number
-- ---------------------------------------------------------------
create table if not exists public.passport_numbers (
  user_id         uuid primary key default auth.uid()
                  references auth.users(id) on delete cascade,
  passport_number text not null,
  updated_at      timestamptz not null default now()
);

alter table public.passport_numbers
  drop constraint if exists passport_numbers_format,
  add constraint passport_numbers_format check (passport_number ~ '^[A-Z0-9]{6,12}$');

alter table public.passport_numbers enable row level security;
revoke all on public.passport_numbers from anon;
revoke delete on public.passport_numbers from authenticated;

drop policy if exists "passport number: select own" on public.passport_numbers;
create policy "passport number: select own"
on public.passport_numbers for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "passport number: insert own" on public.passport_numbers;
create policy "passport number: insert own"
on public.passport_numbers for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "passport number: update own" on public.passport_numbers;
create policy "passport number: update own"
on public.passport_numbers for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop trigger if exists passport_numbers_touch on public.passport_numbers;
create trigger passport_numbers_touch
before update on public.passport_numbers
for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------
-- 4. New kinds of access log rows (used by stages 7 and 8)
-- ---------------------------------------------------------------
do $$
declare c text;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.access_log'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%kind%'
  loop
    execute format('alter table public.access_log drop constraint %I', c);
  end loop;
end $$;

alter table public.access_log
  add constraint access_log_kind_check check (kind in (
    'RESULTS_OPENED', 'PASSPORT_OPENED', 'PASSPORT_DELETED',
    'RESULTS_COMPILED', 'FINAL_LIST_EXPORTED',
    -- new
    'STUDENT_DETAILS_VIEWED',      -- staff opened a student (bank + passport number shown)
    'BANK_ACCOUNT_VIEWED',         -- a Governor opened one student's bank account
    'BANK_LIST_VIEWED',            -- a Governor opened the bank account list of the wilaya
    'FINAL_LIST_EXPORTED_WITH_BANK',
    'RESULTS_TRACKER_VIEWED'
  ));

-- Writes one access_log row for the logged-in user. Only the database
-- functions below and in files 13-14 call it; app users cannot.
create or replace function public.write_access_log(
  p_kind text, p_student uuid default null, p_wilaya text default null,
  p_year text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.access_log (actor_id, actor_role, student_id, kind, wilaya, academic_year)
  values (auth.uid(),
          coalesce((select role from public.profiles where id = auth.uid()), 'unknown'),
          p_student, p_kind, p_wilaya, p_year);
end;
$$;

revoke execute on function public.write_access_log(text, uuid, text, text) from public, anon, authenticated;

commit;
