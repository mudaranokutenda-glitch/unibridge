-- Stage 6, item 25. Date of entry into Algeria on attestation requests.
-- Run AFTER the 2026-11-05-05 attestation file. Safe to run twice. Deletes nothing.
--
-- From now on, a NEW request is refused unless it has BOTH:
--   * the passport file (already required), and
--   * the date of entry into Algeria (between 1990 and today).
-- Older requests may keep the date empty.
-- Same people can see it as the rest of the request: the student and
-- attache / admin (never a Governor).

begin;

alter table public.attestation_requests
  add column if not exists entry_date date;

alter table public.attestation_requests
  drop constraint if exists attestation_entry_date_range;
alter table public.attestation_requests
  add constraint attestation_entry_date_range
  check (entry_date is null or entry_date between date '1990-01-01' and current_date + 1);

create or replace function public.attestation_needs_entry_date()
returns trigger
language plpgsql
as $$
begin
  if new.entry_date is null then
    raise exception 'The date of entry into Algeria is required';
  end if;
  if new.passport_path is null then
    raise exception 'The passport file is required';
  end if;
  return new;
end;
$$;

drop trigger if exists attestation_needs_entry_date on public.attestation_requests;
create trigger attestation_needs_entry_date
before insert on public.attestation_requests
for each row execute function public.attestation_needs_entry_date();

commit;
