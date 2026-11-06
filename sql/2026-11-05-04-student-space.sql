-- B1 + B2. Student record and results upload.
-- Run AFTER files 01, 02 and 03. Safe to run again.
--
-- WHO CAN DO WHAT
--   student_records (one per student)
--     the student      : see, create, edit their own
--     attache / admin  : see all (read only)
--     rep              : see records whose wilaya = their rep_wilaya (read only)
--     anyone else      : nothing
--   academic_results (one row per uploaded PDF) + bucket academic-results
--     the student      : upload (after consent), see, open and delete their own
--     attache / admin  : see the rows; open the files ONLY through the
--                        staff-documents Edge Function (every open is logged)
--     rep              : same as staff, only for students of their wilaya
--     anyone else      : nothing
--
-- Files: academic-results/<user_id>/<academic_year>/<file>.pdf, PDF only, max 10 MB.

begin;

-- ---------------------------------------------------------------
-- 1. Student record
-- ---------------------------------------------------------------
create table if not exists public.student_records (
  user_id              uuid primary key default auth.uid()
                       references auth.users(id) on delete cascade,
  first_name           text not null check (char_length(first_name) between 1 and 80),
  last_name            text not null check (char_length(last_name) between 1 and 80),
  program              text not null check (char_length(program) between 1 and 120),
  level                text not null check (char_length(level) between 1 and 60),
  start_year           int  not null check (start_year between 1990 and 2100),
  academic_year        text not null check (academic_year ~ '^[0-9]{4}-[0-9]{4}$'),
  phone                text not null check (phone ~ '^\+?[0-9 ]{8,20}$'),
  wilaya               text not null check (public.is_valid_wilaya(wilaya)),
  inscription_number   text not null check (char_length(inscription_number) between 1 and 40),
  expected_finish_year int  not null check (expected_finish_year between 1990 and 2100),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  check (expected_finish_year >= start_year)
);

create index if not exists student_records_wilaya_year
  on public.student_records (wilaya, academic_year);

alter table public.student_records enable row level security;
revoke all on public.student_records from anon;

-- Can the logged-in user see this student's record and results?
-- (the student, staff, or the rep of the student's wilaya)
create or replace function public.can_view_student(p_student uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_student = auth.uid()
      or public.is_staff()
      or exists (
           select 1 from public.student_records r
           where r.user_id = p_student and public.is_rep_for(r.wilaya)
         );
$$;

revoke execute on function public.can_view_student(uuid) from public;
grant execute on function public.can_view_student(uuid) to anon, authenticated;

drop policy if exists "records: select" on public.student_records;
create policy "records: select"
on public.student_records for select
to authenticated
using (user_id = auth.uid() or public.is_staff() or public.is_rep_for(wilaya));

drop policy if exists "records: insert own" on public.student_records;
create policy "records: insert own"
on public.student_records for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "records: update own" on public.student_records;
create policy "records: update own"
on public.student_records for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- No delete policy: the record goes away with the account.

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists student_records_touch on public.student_records;
create trigger student_records_touch
before update on public.student_records
for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------
-- 2. Results: table
-- ---------------------------------------------------------------
create table if not exists public.academic_results (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid()
                references auth.users(id) on delete cascade,
  academic_year text not null check (academic_year ~ '^[0-9]{4}-[0-9]{4}$'),
  semester      text not null check (semester in ('S1', 'S2', 'ANNUAL')),
  file_path     text not null unique,
  file_name     text not null check (char_length(file_name) between 1 and 200),
  size_bytes    int  not null check (size_bytes between 1 and 10485760),
  uploaded_at   timestamptz not null default now(),
  -- The file must be inside the student's own folder for that year.
  check (file_path like user_id::text || '/' || academic_year || '/%')
);

create index if not exists academic_results_user on public.academic_results (user_id, academic_year);

alter table public.academic_results enable row level security;
revoke all on public.academic_results from anon;
revoke update on public.academic_results from authenticated;

drop policy if exists "results: select" on public.academic_results;
create policy "results: select"
on public.academic_results for select
to authenticated
using (public.can_view_student(user_id));

drop policy if exists "results: insert own" on public.academic_results;
create policy "results: insert own"
on public.academic_results for insert
to authenticated
with check (user_id = auth.uid() and public.has_document_consent());

drop policy if exists "results: delete own" on public.academic_results;
create policy "results: delete own"
on public.academic_results for delete
to authenticated
using (user_id = auth.uid());

-- ---------------------------------------------------------------
-- 3. Results: private bucket (PDF only, max 10 MB)
-- ---------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('academic-results', 'academic-results', false, 10485760, array['application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Upload: only into my own folder <my id>/<yyyy-yyyy>/<file>, after consent.
drop policy if exists "results files: upload own" on storage.objects;
create policy "results files: upload own"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'academic-results'
  and (storage.foldername(name))[1] = auth.uid()::text
  and (storage.foldername(name))[2] ~ '^[0-9]{4}-[0-9]{4}$'
  and array_length(storage.foldername(name), 1) = 2
  and public.has_document_consent()
);

-- View / open: only my own files. Staff and reps open files through the
-- staff-documents Edge Function, which checks their role and logs it.
drop policy if exists "results files: view own" on storage.objects;
create policy "results files: view own"
on storage.objects for select
to authenticated
using (
  bucket_id = 'academic-results'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "results files: delete own" on storage.objects;
create policy "results files: delete own"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'academic-results'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- No update policy: a file cannot be replaced, only deleted and uploaded again.

commit;
