-- Item 7: dates for the attestation tracker (Received, In review, Issued / Rejected).
--
-- What already existed: created_at (Received) and issued_at (Issued).
-- What was MISSING: a date for "In review" and a date for "Rejected".
-- This file adds two columns and a trigger that fills them from now on:
--   reviewed_at : set when the status becomes IN_REVIEW (or when staff jump straight to
--                 ISSUED / REJECTED, it stays empty: the tracker then shows no date)
--   rejected_at : set when the status becomes REJECTED
--   issued_at   : also filled by the trigger if it is still empty when the status becomes ISSUED
-- Requests that were already in review, issued or rejected before this file have NO date for
-- those steps (the real dates were never saved). The tracker shows the step without a date.
--
-- No new rule: who can read or change attestation_requests does not change
--   (the student reads only their own rows; only set_attestation_status() changes the status;
--    the app cannot update the table). The two new columns hold dates only, no personal data.
-- Deletes nothing and changes no existing row.
--
-- Run in the Supabase SQL Editor. Safe to run twice.
-- Undo: drop trigger attestation_step_dates on public.attestation_requests;
--       drop function public.set_attestation_step_dates();
--       alter table public.attestation_requests drop column reviewed_at, drop column rejected_at;

begin;

alter table public.attestation_requests
  add column if not exists reviewed_at timestamptz,
  add column if not exists rejected_at timestamptz;

create or replace function public.set_attestation_step_dates()
returns trigger
language plpgsql
as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'IN_REVIEW' and new.reviewed_at is null then
      new.reviewed_at := now();
    elsif new.status = 'REJECTED' and new.rejected_at is null then
      new.rejected_at := now();
    elsif new.status = 'ISSUED' and new.issued_at is null then
      new.issued_at := now();
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.set_attestation_step_dates() from public, anon, authenticated;

drop trigger if exists attestation_step_dates on public.attestation_requests;
create trigger attestation_step_dates
before update of status on public.attestation_requests
for each row execute function public.set_attestation_step_dates();

commit;
