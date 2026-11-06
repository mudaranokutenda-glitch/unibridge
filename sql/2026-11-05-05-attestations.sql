-- C1 + C2 + C3. Attestation de bourse.
-- Run AFTER files 01, 03 and 04. Safe to run again.
--
-- WHO CAN DO WHAT
--   attestation_requests
--     the student     : create a request (after consent), see their own
--     attache / admin : see all; change status only with set_attestation_status()
--     rep             : NOTHING (never passports or attestations)
--   bucket passports  (private, jpeg / png / pdf, max 10 MB)
--     the student     : upload into their own folder (after consent), see their own
--     attache / admin : open ONLY through the staff-documents Edge Function (logged)
--     nobody          : deletes from the app. Deleted by the Edge Functions
--                       (staff button, 30-day cleanup, delete account).
--   bucket attestations (private, pdf, max 10 MB)
--     attache / admin : upload, see
--     the student     : see and download only their own
--     rep             : nothing
--
-- Files: passports/<user_id>/<file>, attestations/<user_id>/<request_id>_<time>.pdf

begin;

-- ---------------------------------------------------------------
-- 1. Requests table
-- ---------------------------------------------------------------
create table if not exists public.attestation_requests (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null default auth.uid()
                      references auth.users(id) on delete cascade,
  status              text not null default 'PENDING'
                      check (status in ('PENDING', 'IN_REVIEW', 'ISSUED', 'REJECTED')),
  note                text check (char_length(note) <= 1000),
  passport_path       text,
  passport_deleted_at timestamptz,
  attestation_path    text,
  reviewed_by         uuid references auth.users(id) on delete set null,
  issued_at           timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (passport_path is null or passport_path like user_id::text || '/%'),
  check (attestation_path is null or attestation_path like user_id::text || '/%'),
  check (status <> 'REJECTED' or char_length(coalesce(note, '')) > 0),
  check (status <> 'ISSUED' or attestation_path is not null)
);

-- Only one open request (PENDING or IN_REVIEW) per student.
create unique index if not exists attestation_one_open
  on public.attestation_requests (user_id)
  where status in ('PENDING', 'IN_REVIEW');

alter table public.attestation_requests enable row level security;
revoke all on public.attestation_requests from anon;
revoke update, delete on public.attestation_requests from authenticated;

drop policy if exists "attestations: select own or staff" on public.attestation_requests;
create policy "attestations: select own or staff"
on public.attestation_requests for select
to authenticated
using (user_id = auth.uid() or public.is_staff());

drop policy if exists "attestations: insert own" on public.attestation_requests;
create policy "attestations: insert own"
on public.attestation_requests for insert
to authenticated
with check (
  user_id = auth.uid()
  and status = 'PENDING'
  and note is null
  and attestation_path is null
  and reviewed_by is null
  and issued_at is null
  and passport_deleted_at is null
  and passport_path is not null
  and public.has_document_consent()
);

drop trigger if exists attestation_requests_touch on public.attestation_requests;
create trigger attestation_requests_touch
before update on public.attestation_requests
for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------
-- 2. Notification type for the student (only if notifications.type is an enum)
-- ---------------------------------------------------------------
commit;

do $$
declare
  t text;
begin
  select c.udt_name into t
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'notifications'
    and c.column_name = 'type' and c.data_type = 'USER-DEFINED';
  if t is not null then
    execute format('alter type public.%I add value if not exists %L', t, 'ATTESTATION_UPDATE');
  end if;
end $$;

begin;

-- ---------------------------------------------------------------
-- 3. Staff change the status (the only way to update a request)
-- ---------------------------------------------------------------
create or replace function public.set_attestation_status(
  p_request_id uuid,
  p_status text,
  p_note text default null,
  p_attestation_path text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.attestation_requests;
  msg text;
begin
  if not public.is_staff() then
    raise exception 'Only the educational attaché or admin can do this';
  end if;
  if p_status not in ('IN_REVIEW', 'ISSUED', 'REJECTED') then
    raise exception 'Unknown status %', p_status;
  end if;

  select * into r from public.attestation_requests where id = p_request_id for update;
  if not found then
    raise exception 'Request not found';
  end if;
  if r.status in ('ISSUED', 'REJECTED') then
    raise exception 'This request is already closed';
  end if;
  if p_status = 'ISSUED' then
    if p_attestation_path is null
       or p_attestation_path not like r.user_id::text || '/%'
       or not exists (select 1 from storage.objects
                      where bucket_id = 'attestations' and name = p_attestation_path) then
      raise exception 'Upload the attestation PDF first';
    end if;
  end if;
  if p_status = 'REJECTED' and char_length(trim(coalesce(p_note, ''))) = 0 then
    raise exception 'Write a note for the student';
  end if;

  update public.attestation_requests
  set status = p_status,
      note = nullif(trim(coalesce(p_note, '')), ''),
      attestation_path = case when p_status = 'ISSUED' then p_attestation_path else attestation_path end,
      issued_at = case when p_status = 'ISSUED' then now() else issued_at end,
      reviewed_by = auth.uid()
  where id = p_request_id;

  -- Tell the student. No file paths or links in the text.
  msg := case p_status
           when 'IN_REVIEW' then 'Your attestation de bourse request is being reviewed.'
           when 'ISSUED'    then 'Your attestation de bourse is ready. Open Student space to download it.'
           else 'Your attestation de bourse request was not accepted. Open Student space to read the note.'
         end;
  -- If the notifications table refuses this type, the status change is
  -- still saved (test C2 in the checklist shows whether it arrived).
  begin
    insert into public.notifications (user_id, type, content)
    values (r.user_id, 'ATTESTATION_UPDATE', msg);
  exception when others then
    raise warning 'Notification not created: %', sqlerrm;
  end;
end;
$$;

revoke execute on function public.set_attestation_status(uuid, text, text, text) from public, anon;
grant execute on function public.set_attestation_status(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------
-- 4. Buckets
-- ---------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('passports', 'passports', false, 10485760,
        array['image/jpeg', 'image/png', 'application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attestations', 'attestations', false, 10485760, array['application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Passports: the student uploads into their own folder, after consent.
drop policy if exists "passports: upload own" on storage.objects;
create policy "passports: upload own"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'passports'
  and (storage.foldername(name))[1] = auth.uid()::text
  and array_length(storage.foldername(name), 1) = 1
  and public.has_document_consent()
);

drop policy if exists "passports: view own" on storage.objects;
create policy "passports: view own"
on storage.objects for select
to authenticated
using (
  bucket_id = 'passports'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Attestations: staff upload and see; the student sees their own.
drop policy if exists "attestations files: staff upload" on storage.objects;
create policy "attestations files: staff upload"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'attestations'
  and public.is_staff()
  and array_length(storage.foldername(name), 1) = 1
);

drop policy if exists "attestations files: view own or staff" on storage.objects;
create policy "attestations files: view own or staff"
on storage.objects for select
to authenticated
using (
  bucket_id = 'attestations'
  and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff())
);

-- No update or delete policies on either bucket.

commit;
