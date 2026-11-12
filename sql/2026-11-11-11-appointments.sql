-- Stage 5, item 24. Appointments with the Educational Attaché.
-- Run AFTER 2026-11-11-07 (it uses notify_user). Safe to run twice. Deletes nothing.
--
-- Steps:
--   student asks: date and time + reason          -> REQUESTED (attaché notified)
--   attaché: accept                                -> ACCEPTED  (student notified)
--            propose another time                  -> PROPOSED  (student notified)
--            decline (with a note)                 -> DECLINED  (student notified)
--   student, on a PROPOSED time: accept it         -> ACCEPTED  (attaché notified)
--   student: cancel (while not finished)           -> CANCELLED (attaché notified)
--
-- WHO CAN DO WHAT (appointments)
--   the student      : see own, ask, answer a proposal, cancel own
--   attache / admin  : see all, accept / propose / decline
--   Governor / other students : nothing
-- Status changes go only through the two functions below.

do $$
declare
  t text;
begin
  select c.udt_name into t
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'notifications'
    and c.column_name = 'type' and c.data_type = 'USER-DEFINED';
  if t is not null then
    execute format('alter type public.%I add value if not exists %L', t, 'APPOINTMENT_UPDATE');
  end if;
end $$;

begin;

create table if not exists public.appointments (
  id           uuid primary key default gen_random_uuid(),
  student_id   uuid not null default auth.uid()
               references auth.users(id) on delete cascade,
  requested_at timestamptz not null,
  reason       text not null check (char_length(reason) between 3 and 1000),
  status       text not null default 'REQUESTED'
               check (status in ('REQUESTED', 'ACCEPTED', 'PROPOSED', 'DECLINED', 'CANCELLED')),
  proposed_at  timestamptz,
  staff_note   text check (char_length(staff_note) <= 1000),
  handled_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (status <> 'PROPOSED' or proposed_at is not null)
);

create index if not exists appointments_student on public.appointments (student_id, created_at desc);
create index if not exists appointments_status on public.appointments (status, requested_at);

alter table public.appointments enable row level security;
revoke all on public.appointments from anon;
revoke update, delete on public.appointments from authenticated;

drop policy if exists "appointments: select own or staff" on public.appointments;
create policy "appointments: select own or staff"
on public.appointments for select
to authenticated
using (student_id = auth.uid() or public.is_staff());

drop policy if exists "appointments: student asks" on public.appointments;
create policy "appointments: student asks"
on public.appointments for insert
to authenticated
with check (
  student_id = auth.uid()
  and status = 'REQUESTED'
  and proposed_at is null and staff_note is null and handled_by is null
  and requested_at > now()
);

-- At most 3 active appointments per student: REQUESTED, PROPOSED or
-- ACCEPTED, with a time still in the future.
create or replace function public.limit_active_appointments()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  -- One insert at a time per student, so two quick taps cannot both pass.
  perform pg_advisory_xact_lock(hashtext('appointments:' || new.student_id::text));

  select count(*) into n
  from public.appointments
  where student_id = new.student_id
    and status in ('REQUESTED', 'PROPOSED', 'ACCEPTED')
    and coalesce(proposed_at, requested_at) > now();

  if n >= 3 then
    raise exception 'You already have 3 appointments waiting or planned. Cancel one before asking for a new one.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.limit_active_appointments() from public, anon, authenticated;

drop trigger if exists limit_active_appointments on public.appointments;
create trigger limit_active_appointments
before insert on public.appointments
for each row execute function public.limit_active_appointments();

drop trigger if exists appointments_touch on public.appointments;
create trigger appointments_touch
before update on public.appointments
for each row execute function public.touch_updated_at();

-- Tell every attaché / admin about a new request.
create or replace function public.notify_staff_new_appointment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare s uuid;
begin
  for s in select id from public.profiles where role in ('attache', 'admin') loop
    perform public.notify_user(s, 'APPOINTMENT_UPDATE',
      'New appointment request for ' || to_char(new.requested_at at time zone 'Africa/Algiers', 'DD/MM/YYYY HH24:MI') || '.');
  end loop;
  return new;
end;
$$;

revoke execute on function public.notify_staff_new_appointment() from public, anon, authenticated;

drop trigger if exists notify_staff_new_appointment on public.appointments;
create trigger notify_staff_new_appointment
after insert on public.appointments
for each row execute function public.notify_staff_new_appointment();

-- The attaché answers: p_action = 'ACCEPT', 'PROPOSE' (with p_time) or 'DECLINE'.
create or replace function public.staff_answer_appointment(
  p_id uuid, p_action text, p_time timestamptz default null, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare a public.appointments; msg text;
begin
  if not public.is_staff() then
    raise exception 'Only the Educational Attaché or admin can do this';
  end if;
  select * into a from public.appointments where id = p_id for update;
  if not found then raise exception 'Appointment not found'; end if;
  if a.status not in ('REQUESTED', 'PROPOSED') then
    raise exception 'This appointment is already closed';
  end if;

  if p_action = 'ACCEPT' then
    update public.appointments
    set status = 'ACCEPTED', handled_by = auth.uid(),
        staff_note = nullif(trim(coalesce(p_note, '')), '')
    where id = p_id;
    msg := 'Your appointment with the Educational Attaché is confirmed for '
           || to_char(coalesce(a.proposed_at, a.requested_at) at time zone 'Africa/Algiers', 'DD/MM/YYYY HH24:MI') || '.';
  elsif p_action = 'PROPOSE' then
    if p_time is null or p_time <= now() then
      raise exception 'Choose a future date and time';
    end if;
    update public.appointments
    set status = 'PROPOSED', proposed_at = p_time, handled_by = auth.uid(),
        staff_note = nullif(trim(coalesce(p_note, '')), '')
    where id = p_id;
    msg := 'The Educational Attaché proposed another time: '
           || to_char(p_time at time zone 'Africa/Algiers', 'DD/MM/YYYY HH24:MI') || '. Open the app to answer.';
  elsif p_action = 'DECLINE' then
    update public.appointments
    set status = 'DECLINED', handled_by = auth.uid(),
        staff_note = nullif(trim(coalesce(p_note, '')), '')
    where id = p_id;
    msg := 'Your appointment request was declined. Open the app to read the note.';
  else
    raise exception 'Unknown action %', p_action;
  end if;

  perform public.notify_user(a.student_id, 'APPOINTMENT_UPDATE', msg);
end;
$$;

revoke execute on function public.staff_answer_appointment(uuid, text, timestamptz, text) from public, anon;
grant execute on function public.staff_answer_appointment(uuid, text, timestamptz, text) to authenticated;

-- The student answers: p_action = 'ACCEPT_PROPOSAL' or 'CANCEL'.
create or replace function public.student_answer_appointment(p_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare a public.appointments; msg text;
begin
  select * into a from public.appointments where id = p_id for update;
  if not found or a.student_id <> auth.uid() then
    raise exception 'Appointment not found';
  end if;

  if p_action = 'ACCEPT_PROPOSAL' then
    if a.status <> 'PROPOSED' then raise exception 'There is no proposed time to accept'; end if;
    update public.appointments set status = 'ACCEPTED' where id = p_id;
    msg := 'A student accepted the proposed appointment time.';
  elsif p_action = 'CANCEL' then
    if a.status not in ('REQUESTED', 'PROPOSED', 'ACCEPTED') then
      raise exception 'This appointment is already closed';
    end if;
    update public.appointments set status = 'CANCELLED' where id = p_id;
    msg := 'A student cancelled an appointment.';
  else
    raise exception 'Unknown action %', p_action;
  end if;

  if a.handled_by is not null then
    perform public.notify_user(a.handled_by, 'APPOINTMENT_UPDATE', msg);
  else
    perform public.notify_user(s.id, 'APPOINTMENT_UPDATE', msg)
    from public.profiles s where s.role in ('attache', 'admin');
  end if;
end;
$$;

revoke execute on function public.student_answer_appointment(uuid, text) from public, anon;
grant execute on function public.student_answer_appointment(uuid, text) to authenticated;

commit;
