-- Stage 7, items 26, 29 and 30. Educational Attaché tools (attache and admin only).
-- Run AFTER 2026-11-11-08. Safe to run twice. Deletes nothing.
--
-- staff_search_students(query, wilaya)
--   attache / admin only. Searches ON THE SERVER by name, inscription
--   number or wilaya (at least 2 letters, or a wilaya). At most 50 results.
--   Returns names and wilaya only: NO phone, bank or passport number, so
--   there is no full list of student contacts.
-- staff_student_details(user)
--   attache / admin only. One student's record, phone, bank account and
--   passport number. EVERY call writes a STUDENT_DETAILS_VIEWED row to
--   access_log. (Results files are still opened through staff-documents,
--   which logs each one.)
-- students_per_wilaya()
--   attache / admin: every wilaya. Governor: only their own wilaya.
--   Students: not allowed. Counts only, no names.
-- alerts (emergency alerts)
--   every signed-in user : read
--   nobody               : insert / change / delete from the app. Alerts
--                          are written only by the Edge Function
--                          emergency-alert, which checks attache / admin.

begin;

-- ---------------------------------------------------------------
-- 1. Search
-- ---------------------------------------------------------------
create or replace function public.staff_search_students(p_query text, p_wilaya text default null)
returns table (
  user_id uuid,
  full_name text,
  first_name text,
  last_name text,
  wilaya text,
  inscription_number text,
  academic_year text,
  has_record boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare q text := nullif(trim(coalesce(p_query, '')), '');
begin
  if not public.is_staff() then
    raise exception 'Not allowed';
  end if;
  if (q is null or char_length(q) < 2) and p_wilaya is null then
    raise exception 'Type at least 2 letters or choose a wilaya';
  end if;

  return query
  select p.id,
         p.full_name::text,
         r.first_name, r.last_name,
         coalesce(r.wilaya, p.wilaya)::text,
         r.inscription_number,
         r.academic_year,
         r.user_id is not null
  from public.profiles p
  left join public.student_records r on r.user_id = p.id
  where p.role = 'student'
    and (p_wilaya is null or coalesce(r.wilaya, p.wilaya) = p_wilaya)
    and (q is null
         or p.full_name ilike '%' || q || '%'
         or r.first_name ilike '%' || q || '%'
         or r.last_name ilike '%' || q || '%'
         or (r.first_name || ' ' || r.last_name) ilike '%' || q || '%'
         or (r.last_name || ' ' || r.first_name) ilike '%' || q || '%'
         or r.inscription_number ilike '%' || q || '%')
  order by coalesce(r.last_name, p.full_name), r.first_name
  limit 50;
end;
$$;

revoke execute on function public.staff_search_students(text, text) from public, anon;
grant execute on function public.staff_search_students(text, text) to authenticated;

-- ---------------------------------------------------------------
-- 2. One student's details (logged)
-- ---------------------------------------------------------------
create or replace function public.staff_student_details(p_user uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare result jsonb;
begin
  if not public.is_staff() then
    raise exception 'Not allowed';
  end if;

  select jsonb_build_object(
    'user_id', p.id,
    'full_name', p.full_name,
    'profile_wilaya', p.wilaya,
    'profile_picture_url', p.profile_picture_url,
    'record', (select to_jsonb(r) from public.student_records r where r.user_id = p.id),
    'phone', (select ph.phone from public.user_phones ph where ph.user_id = p.id),
    'bank_account', (select b.account_number from public.bank_accounts b where b.user_id = p.id),
    'passport_number', (select n.passport_number from public.passport_numbers n where n.user_id = p.id)
  ) into result
  from public.profiles p
  where p.id = p_user;

  if result is null then
    raise exception 'Student not found';
  end if;

  perform public.write_access_log('STUDENT_DETAILS_VIEWED', p_user,
                                  public.student_wilaya(p_user), null);
  return result;
end;
$$;

revoke execute on function public.staff_student_details(uuid) from public, anon;
grant execute on function public.staff_student_details(uuid) to authenticated;

-- ---------------------------------------------------------------
-- 3. Dashboard: students per wilaya
--    A student = a profile with role 'student'. Their wilaya = the one in
--    their student record, or else the one in their profile.
-- ---------------------------------------------------------------
create or replace function public.students_per_wilaya()
returns table (wilaya text, students bigint, with_record bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
declare my_rep_wilaya text;
begin
  if public.is_staff() then
    my_rep_wilaya := null;
  else
    select p.rep_wilaya into my_rep_wilaya
    from public.profiles p where p.id = auth.uid() and p.role = 'rep';
    if my_rep_wilaya is null then
      raise exception 'Not allowed';
    end if;
  end if;

  return query
  select coalesce(r.wilaya, p.wilaya)::text as w,
         count(*)::bigint,
         count(r.user_id)::bigint
  from public.profiles p
  left join public.student_records r on r.user_id = p.id
  where p.role = 'student'
    and public.is_valid_wilaya(coalesce(r.wilaya, p.wilaya))
    and (my_rep_wilaya is null or coalesce(r.wilaya, p.wilaya) = my_rep_wilaya)
  group by 1
  order by 1;
end;
$$;

revoke execute on function public.students_per_wilaya() from public, anon;
grant execute on function public.students_per_wilaya() to authenticated;

-- ---------------------------------------------------------------
-- 4. Emergency alerts
-- ---------------------------------------------------------------
create table if not exists public.alerts (
  id         uuid primary key default gen_random_uuid(),
  title      text not null check (char_length(title) between 1 and 100),
  message    text not null check (char_length(message) between 1 and 1000),
  created_by uuid references auth.users(id) on delete set null,
  sent_count int  not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists alerts_created on public.alerts (created_at desc);

alter table public.alerts enable row level security;
revoke all on public.alerts from anon;
revoke insert, update, delete on public.alerts from authenticated;

drop policy if exists "alerts: read" on public.alerts;
create policy "alerts: read" on public.alerts
for select to authenticated using (true);

commit;
