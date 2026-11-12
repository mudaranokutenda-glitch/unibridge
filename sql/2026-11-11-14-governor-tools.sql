-- Stage 8, items 31-35. Governor tools (role rep, OWN wilaya only).
-- Run AFTER 2026-11-11-13. Safe to run twice. Deletes nothing.
--
-- The Governor's wilaya always comes from their own profile (rep_wilaya),
-- never from the app, so a Governor can never ask about another wilaya.
-- Students and other Governors get "Not allowed".
--
-- rep_results_tracker(year, semester)
--   who in my wilaya has uploaded results for that year and semester, and
--   who has not. Names and yes/no only; the files are still opened through
--   staff-documents (logged).
-- rep_students_without_record()
--   users of my wilaya (profile wilaya) who have not filled in their student
--   record, with their phone so the Governor can contact them.
-- rep_bank_accounts()
--   the bank accounts of my wilaya's students (view only). EVERY call writes
--   a BANK_LIST_VIEWED row to access_log.
-- Counts per wilaya: students_per_wilaya() in file 13 (own wilaya only for a
-- Governor).
-- Passport numbers and passport files: NEVER for a Governor.

begin;

create or replace function public.my_rep_wilaya()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.rep_wilaya from public.profiles p
  where p.id = auth.uid() and p.role = 'rep';
$$;

revoke execute on function public.my_rep_wilaya() from public, anon;
grant execute on function public.my_rep_wilaya() to authenticated;

-- 31. Results tracker
create or replace function public.rep_results_tracker(p_year text, p_semester text)
returns table (user_id uuid, first_name text, last_name text, has_uploaded boolean, uploaded_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
declare w text := public.my_rep_wilaya();
begin
  if w is null then raise exception 'Not allowed'; end if;
  if p_year !~ '^[0-9]{4}-[0-9]{4}$' or p_semester not in ('S1', 'S2', 'ANNUAL') then
    raise exception 'Choose a year and a semester';
  end if;

  return query
  select r.user_id, r.first_name, r.last_name,
         max(a.uploaded_at) is not null,
         max(a.uploaded_at)
  from public.student_records r
  left join public.academic_results a
    on a.user_id = r.user_id and a.academic_year = p_year and a.semester = p_semester
  where r.wilaya = w
  group by r.user_id, r.first_name, r.last_name
  order by (max(a.uploaded_at) is not null), r.last_name, r.first_name;
end;
$$;

revoke execute on function public.rep_results_tracker(text, text) from public, anon;
grant execute on function public.rep_results_tracker(text, text) to authenticated;

-- 32. Users of my wilaya without a student record
create or replace function public.rep_students_without_record()
returns table (user_id uuid, full_name text, phone text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare w text := public.my_rep_wilaya();
begin
  if w is null then raise exception 'Not allowed'; end if;
  return query
  select p.id, p.full_name::text, ph.phone
  from public.profiles p
  left join public.user_phones ph on ph.user_id = p.id
  where p.role = 'student'
    and p.wilaya = w
    and not exists (select 1 from public.student_records r where r.user_id = p.id)
  order by p.full_name;
end;
$$;

revoke execute on function public.rep_students_without_record() from public, anon;
grant execute on function public.rep_students_without_record() to authenticated;

-- 34. Bank accounts of my wilaya (view only, logged)
create or replace function public.rep_bank_accounts()
returns table (user_id uuid, first_name text, last_name text, account_number text)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare w text := public.my_rep_wilaya();
begin
  if w is null then raise exception 'Not allowed'; end if;
  perform public.write_access_log('BANK_LIST_VIEWED', null, w, null);
  return query
  select r.user_id, r.first_name, r.last_name, b.account_number
  from public.student_records r
  left join public.bank_accounts b on b.user_id = r.user_id
  where r.wilaya = w
  order by r.last_name, r.first_name;
end;
$$;

revoke execute on function public.rep_bank_accounts() from public, anon;
grant execute on function public.rep_bank_accounts() to authenticated;

commit;
