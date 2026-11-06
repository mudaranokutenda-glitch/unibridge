-- D4. Access log: who opened a passport or a student's results, and when.
-- Run AFTER file 01. Safe to run again.
--
-- Rows are written ONLY by the Edge Functions (staff-documents and
-- staff-reports), which is also the only way staff can open those files.
-- So staff cannot open a passport or results without leaving a row here.
--
-- WHO CAN DO WHAT
--   attache / admin : read the log
--   everyone else   : nothing
--   NOBODY          : can edit or delete a row (a trigger refuses it,
--                     even for the Edge Functions)
--
-- No file paths or links are stored, only ids.
-- student_id has no link to the profiles table on purpose: the rows stay
-- even if the student deletes their account.

begin;

create table if not exists public.access_log (
  id           bigint generated always as identity primary key,
  created_at   timestamptz not null default now(),
  actor_id     uuid not null,
  actor_role   text not null,
  student_id   uuid,
  kind         text not null
               check (kind in ('RESULTS_OPENED', 'PASSPORT_OPENED', 'PASSPORT_DELETED',
                               'RESULTS_COMPILED', 'FINAL_LIST_EXPORTED')),
  document_id  uuid,
  wilaya       text,
  academic_year text
);

create index if not exists access_log_created on public.access_log (created_at desc);

alter table public.access_log enable row level security;
revoke all on public.access_log from anon, authenticated;
grant select on public.access_log to authenticated;

drop policy if exists "access log: staff read" on public.access_log;
create policy "access log: staff read"
on public.access_log for select
to authenticated
using (public.is_staff());

create or replace function public.access_log_read_only()
returns trigger
language plpgsql
as $$
begin
  raise exception 'The access log cannot be changed or deleted';
end;
$$;

drop trigger if exists access_log_no_update on public.access_log;
create trigger access_log_no_update
before update or delete on public.access_log
for each row execute function public.access_log_read_only();

drop trigger if exists access_log_no_truncate on public.access_log;
create trigger access_log_no_truncate
before truncate on public.access_log
for each statement execute function public.access_log_read_only();

commit;
