-- Tests for sql/2026-11-11-08 (bank, passport number), 09 (contacts),
-- 10 (guide, help) and 11 (appointments).
-- Replace STUDENT-A-ID, STUDENT-B-ID, GOVERNOR-ID, ATTACHE-ID (see README.md).
-- Nothing is saved: the file ends with rollback.

begin;

-- ---------- Student A saves private data ----------
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  insert into public.bank_accounts (user_id, account_number) values ('STUDENT-A-ID', '12345678901234567890')
  on conflict (user_id) do update set account_number = excluded.account_number;
  insert into public.passport_numbers (user_id, passport_number) values ('STUDENT-A-ID', 'AB123456')
  on conflict (user_id) do update set passport_number = excluded.passport_number;
  raise notice 'PASS T1 Student A can save a bank account and a passport number';

  begin
    update public.bank_accounts set account_number = '1234' where user_id = 'STUDENT-A-ID';
    raise notice 'FAIL T2 a bank account must be exactly 20 digits';
  exception when others then
    raise notice 'PASS T2 a bank account must be exactly 20 digits';
  end;
  begin
    update public.passport_numbers set passport_number = 'ab-12' where user_id = 'STUDENT-A-ID';
    raise notice 'FAIL T3 a passport number must be 6-12 capital letters or digits';
  exception when others then
    raise notice 'PASS T3 a passport number must be 6-12 capital letters or digits';
  end;
  begin
    update public.student_records set gender = 'OTHER' where user_id = 'STUDENT-A-ID';
    if found then
      raise notice 'FAIL T4 gender must be MALE or FEMALE';
    else
      raise notice 'SKIP T4 (Student A has no student record)';
    end if;
  exception when others then
    raise notice 'PASS T4 gender must be MALE or FEMALE';
  end;

  begin
    insert into public.staff_contacts (kind, name, email) values ('attache', 'Fake', 'x@y.zz');
    raise notice 'FAIL T5 a student cannot add a staff contact';
  exception when others then
    raise notice 'PASS T5 a student cannot add a staff contact';
  end;
  begin
    insert into public.faqs (question, answer) values ('Q', 'A');
    raise notice 'FAIL T6 a student cannot add a question to Help';
  exception when others then
    raise notice 'PASS T6 a student cannot add a question to Help';
  end;
  begin
    insert into public.guide_items (section_id, title) values ('BANK', 'Fake');
    raise notice 'FAIL T7 a student cannot add a guide item';
  exception when others then
    raise notice 'PASS T7 a student cannot add a guide item';
  end;
  raise notice '% T8 a student can read the 4 guide sections',
    case when (select count(*) from public.guide_sections where id in ('POLICE','BANK','BOURSE','MEDICAL')) = 4
    then 'PASS' else 'FAIL' end;

  insert into public.appointments (student_id, requested_at, reason)
  values ('STUDENT-A-ID', now() + interval '3 days', 'Test appointment (rolled back)');
  raise notice 'PASS T9 Student A can ask for an appointment';
  begin
    insert into public.appointments (student_id, requested_at, reason, status)
    values ('STUDENT-A-ID', now() + interval '3 days', 'Trying to self-accept', 'ACCEPTED');
    raise notice 'FAIL T10 a student cannot create an ACCEPTED appointment';
  exception when others then
    raise notice 'PASS T10 a student cannot create an ACCEPTED appointment';
  end;
end $$;

-- ---------- Student B must see none of it ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int; aid uuid;
begin
  select count(*) into n from public.bank_accounts where user_id = 'STUDENT-A-ID';
  raise notice '% T11 Student B cannot read A''s bank account', case when n = 0 then 'PASS' else 'FAIL' end;
  select count(*) into n from public.passport_numbers where user_id = 'STUDENT-A-ID';
  raise notice '% T12 Student B cannot read A''s passport number', case when n = 0 then 'PASS' else 'FAIL' end;
  select count(*) into n from public.appointments where student_id = 'STUDENT-A-ID';
  raise notice '% T13 Student B cannot see A''s appointments', case when n = 0 then 'PASS' else 'FAIL' end;
  begin
    perform public.staff_answer_appointment(
      (select id from public.appointments limit 1), 'ACCEPT', null, null);
    raise notice 'FAIL T14 a student cannot answer appointments';
  exception when others then
    raise notice 'PASS T14 a student cannot answer appointments';
  end;
end $$;

-- ---------- Governor: never the passport number, no direct bank read ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"GOVERNOR-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int;
begin
  select count(*) into n from public.passport_numbers where user_id = 'STUDENT-A-ID';
  raise notice '% T15 a Governor cannot read a passport number', case when n = 0 then 'PASS' else 'FAIL' end;
  select count(*) into n from public.bank_accounts where user_id = 'STUDENT-A-ID';
  raise notice '% T16 a Governor cannot read bank accounts directly (only through the logged functions)', case when n = 0 then 'PASS' else 'FAIL' end;
  select count(*) into n from public.appointments;
  raise notice '% T17 a Governor cannot see appointments', case when n = 0 then 'PASS' else 'FAIL' end;
end $$;

-- ---------- Educational Attaché ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"ATTACHE-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare aid uuid;
begin
  insert into public.staff_contacts (kind, name, phone) values ('attache', 'Test attaché', '+213555123456');
  raise notice 'PASS T18 the Educational Attaché can add a contact';
  begin
    insert into public.staff_contacts (kind, name, phone) values ('governor', 'No wilaya', '+213555123456');
    raise notice 'FAIL T19 a Governor contact needs a wilaya';
  exception when others then
    raise notice 'PASS T19 a Governor contact needs a wilaya';
  end;
  select id into aid from public.appointments where student_id = 'STUDENT-A-ID' and status = 'REQUESTED' limit 1;
  if aid is null then
    raise notice 'SKIP T20';
  else
    perform public.staff_answer_appointment(aid, 'PROPOSE', now() + interval '5 days', 'Is this better?');
    raise notice '% T20 the attaché can propose another time',
      case when (select status from public.appointments where id = aid) = 'PROPOSED' then 'PASS' else 'FAIL' end;
  end if;
end $$;

rollback;
